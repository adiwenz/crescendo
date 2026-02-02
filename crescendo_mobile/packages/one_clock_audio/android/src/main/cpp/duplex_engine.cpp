#include <jni.h>
#include <android/asset_manager_jni.h>
#include <android/log.h>
#include <oboe/Oboe.h>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>
#include <cstdio>
#include <string>
#include <chrono>

#include "ring_buffer.h"

#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "DuplexEngine", __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  "DuplexEngine", __VA_ARGS__)

static inline float clampf(float x, float lo, float hi) {
  return x < lo ? lo : (x > hi ? hi : x);
}

struct CaptureMeta {
  int32_t numFrames;
  int32_t sampleRate;
  int32_t channels;
  int64_t inputFramePos;
  int64_t outputFramePos;
  int64_t timestampNanos;
  int64_t outputFramePosRel;
  int32_t sessionId;
};


struct SessionSnapshot {
  int32_t sessionId;
  int64_t sessionStartFrame;
  int64_t firstCaptureOutputFrame;
  int64_t lastOutputFrame;
  int32_t computedVocOffsetFrames;
  bool hasFirstCapture;
};

enum class EngineMode { kDuplexRecord, kPlaybackReview };

class DuplexEngine : public oboe::AudioStreamDataCallback {
public:
  DuplexEngine()
    : pcmRing_(1 << 20),  // 1MB
      metaRing_(1 << 16)  // 64KB
  {}

  ~DuplexEngine() { stop(); }

  void setJavaCallback(JNIEnv* env, jobject callbackObj) {
    std::lock_guard<std::mutex> lock(cbMu_);
    if (cbGlobal_) {
      env->DeleteGlobalRef(cbGlobal_);
      cbGlobal_ = nullptr;
      onCaptured_ = nullptr;
    }
    if (!callbackObj) return;

    env->GetJavaVM(&jvm_);
    cbGlobal_ = env->NewGlobalRef(callbackObj);

    jclass cls = env->GetObjectClass(callbackObj);
    // Updated signature: +long(relPos) +int(sessionId)
    onCaptured_ = env->GetMethodID(cls, "onCaptured", "([BIIIJJJJI)V");
    if (!onCaptured_) LOGE("Failed to find onCaptured([BIIIJJJJI)V");
    if (!onCaptured_) LOGE("Failed to find onCaptured([BIIIJJJJI)V");
  }

  // --- Session State ---
  SessionSnapshot getSessionSnapshot() const {
      SessionSnapshot s;
      s.sessionId = sessionId_.load();
      s.sessionStartFrame = sessionStartFrame_.load();
      s.firstCaptureOutputFrame = firstCaptureOutputFrame_.load();
      s.lastOutputFrame = playFrame_.load();
      s.computedVocOffsetFrames = computedVocOffsetFrames_.load();
      s.hasFirstCapture = hasFirstCapture_.load();
      return s;
  }

  void resetSessionStateForStart(int64_t startFrame) {
      sessionId_.fetch_add(1);
      sessionStartFrame_.store(startFrame);
      firstCaptureOutputFrame_.store(-1);
      hasFirstCapture_.store(false);
      computedVocOffsetFrames_.store(0);
      LOGI("Session Reset: ID=%d StartFrame=%lld", sessionId_.load(), (long long)startFrame);
  }

  void onFirstCaptureIfNeeded(int64_t captureBase) {
      bool expected = false;
      if (hasFirstCapture_.compare_exchange_strong(expected, true)) {
          firstCaptureOutputFrame_.store(captureBase);
          
          int64_t start = sessionStartFrame_.load();
          int64_t diff = captureBase - start;
          computedVocOffsetFrames_.store((int32_t)diff);
          
          LOGI("First Capture: Base=%lld, StartFrame=%lld, Diff=%lld (SessionID=%d)", 
               (long long)captureBase, (long long)start, (long long)diff, sessionId_.load());
      }
  }
  // --- Helpers for parsing ---
  bool parseWav(const uint8_t* data, size_t size, std::vector<float>& outFloats, int32_t& outCh, int32_t& outSr) {
     if (size < 44) return false;
     
     auto u32 = [&](size_t off)->uint32_t {
       return (uint32_t)data[off] | ((uint32_t)data[off+1] << 8) |
              ((uint32_t)data[off+2] << 16) | ((uint32_t)data[off+3] << 24);
     };
     auto u16 = [&](size_t off)->uint16_t {
       return (uint16_t)data[off] | ((uint16_t)data[off+1] << 8);
     };

     if (memcmp(data, "RIFF", 4) || memcmp(data+8, "WAVE", 4)) return false;

     size_t cur = 12;
     const uint8_t* pcm = nullptr;
     uint32_t pcmBytes = 0;
     uint16_t format=0, ch=0, bps=0;
     uint32_t sr=0;

     while (cur + 8 <= size) {
       const char* id = (const char*)(data + cur);
       uint32_t chunkSize = u32(cur + 4);
       cur += 8;
       if (cur + chunkSize > size) break;

       if (!memcmp(id, "fmt ", 4)) {
         if (chunkSize < 16) break;
         format = u16(cur);
         ch     = u16(cur + 2);
         sr     = u32(cur + 4);
         bps    = u16(cur + 14);
       } else if (!memcmp(id, "data", 4)) {
         pcm = data + cur;
         pcmBytes = chunkSize;
       }
       cur += chunkSize;
       if (cur & 1) cur++; 
     }

     if (!pcm || format != 1 || bps != 16) return false;

     outCh = ch;
     outSr = sr;
     size_t numSamples = pcmBytes / 2;
     outFloats.resize(numSamples);
     
     const int16_t* src = (const int16_t*)pcm;
     for (size_t i=0; i<numSamples; i++) {
         outFloats[i] = src[i] / 32768.0f;
     }
     return true;
  }

  bool loadWavAsset(JNIEnv* env, jobject assetMgrObj, const char* path, std::vector<float>& out, int32_t& ch, int32_t& sr) {
    if (!path) return false;
    AAssetManager* mgr = AAssetManager_fromJava(env, assetMgrObj);
    if (!mgr) return false;
    AAsset* asset = AAssetManager_open(mgr, path, AASSET_MODE_BUFFER);
    if (!asset) return false;
    
    const uint8_t* data = (const uint8_t*)AAsset_getBuffer(asset);
    size_t size = (size_t)AAsset_getLength(asset);
    bool ok = parseWav(data, size, out, ch, sr);
    AAsset_close(asset);
    return ok;
  }
  
  bool loadWavFile(const char* path, std::vector<float>& out, int32_t& ch, int32_t& sr) {
      FILE* f = fopen(path, "rb");
      if (!f) return false;
      fseek(f, 0, SEEK_END);
      long sz = ftell(f);
      rewind(f);
      if (sz < 44) { fclose(f); return false; }
      
      std::vector<uint8_t> buf(sz);
      fread(buf.data(), 1, sz, f);
      fclose(f);
      
      return parseWav(buf.data(), sz, out, ch, sr);
  }

  bool loadRefFromFile(const char* path) {
      std::vector<float> tmp;
      int32_t ch = 1;
      int32_t sr = 0;
      if (!loadWavFile(path, tmp, ch, sr)) return false;

      std::lock_guard<std::mutex> lk(trackMu_);
      trackRef_ = std::move(tmp);
      playCh_ = ch; 
      LOGI("Loaded Ref File: %zu frames, ch=%d, sr=%d", trackRef_.size()/ch, ch, sr);
      if(trackRef_.size() > 8) {
         LOGI("[RefPcm] first8=%.4f,%.4f,%.4f,%.4f...", trackRef_[0], trackRef_[1], trackRef_[2], trackRef_[3]);
      }
      return true;
  }

  bool loadVocFromFile(const char* path) {
      std::vector<float> tmp;
      int32_t ch = 1;
      int32_t sr = 0;
      if (!loadWavFile(path, tmp, ch, sr)) return false;

      // Downmix to mono if stereo? simpler mixing
      if (ch > 1) {
          std::vector<float> mono(tmp.size() / ch);
          for (size_t i=0; i<mono.size(); i++) {
              float sum = 0;
              for(int c=0; c<ch; c++) sum += tmp[i*ch+c];
              mono[i] = sum / ch;
          }
          tmp = std::move(mono);
          ch = 1;
      }

      std::lock_guard<std::mutex> lk(trackMu_);
      trackVoc_ = std::move(tmp);
      LOGI("Loaded Voc File: %zu frames, ch=%d, sr=%d", trackVoc_.size(), ch, sr);
      return true;
  }

  void stop() {
    running_.store(false);
    stopTransportRecording();
    {
      std::lock_guard<std::mutex> lk(transportFileMu_);
      if (transportRecordFile_) {
        updateWavDataSize(transportRecordFile_, transportRecordBytes_.load());
        fclose(transportRecordFile_);
        transportRecordFile_ = nullptr;
      }
    }
    if (in_) in_->close();
    if (out_) out_->close();
    in_.reset();
    out_.reset();

    cv_.notify_all();
    if(worker_.joinable()) worker_.join();

    pcmRing_.clear();
    metaRing_.clear();
    playFrame_.store(0);
    LOGI("Stopped. Rings cleared.");
  }

  // --- Transport: WAV writer + sample-time clock (iOS semantics) ---
  static void writeWavHeader(FILE* f, int32_t sampleRate, int32_t channels) {
    if (!f) return;
    uint8_t hdr[44] = {0};
    memcpy(hdr, "RIFF", 4);
    uint32_t riffSize = 36;
    hdr[4] = (uint8_t)(riffSize); hdr[5] = (uint8_t)(riffSize>>8); hdr[6] = (uint8_t)(riffSize>>16); hdr[7] = (uint8_t)(riffSize>>24);
    memcpy(hdr+8, "WAVE", 4);
    memcpy(hdr+12, "fmt ", 4);
    uint32_t fmtLen = 16;
    hdr[16]=fmtLen; hdr[17]=fmtLen>>8; hdr[18]=fmtLen>>16; hdr[19]=fmtLen>>24;
    uint16_t format = 1;
    hdr[20]=format; hdr[21]=format>>8;
    hdr[22]=channels; hdr[23]=channels>>8;
    hdr[24]=(uint8_t)(sampleRate); hdr[25]=(uint8_t)(sampleRate>>8); hdr[26]=(uint8_t)(sampleRate>>16); hdr[27]=(uint8_t)(sampleRate>>24);
    uint32_t byteRate = sampleRate * channels * 2;
    hdr[28]=(uint8_t)(byteRate); hdr[29]=(uint8_t)(byteRate>>8); hdr[30]=(uint8_t)(byteRate>>16); hdr[31]=(uint8_t)(byteRate>>24);
    uint16_t blockAlign = channels * 2;
    hdr[32]=blockAlign; hdr[33]=blockAlign>>8;
    uint16_t bits = 16;
    hdr[34]=bits; hdr[35]=bits>>8;
    memcpy(hdr+36, "data", 4);
    uint32_t dataSize = 0;
    hdr[40]=dataSize; hdr[41]=dataSize>>8; hdr[42]=dataSize>>16; hdr[43]=dataSize>>24;
    fwrite(hdr, 1, 44, f);
  }

  static void updateWavDataSize(FILE* f, int64_t dataBytes) {
    if (!f || dataBytes < 0) return;
    uint32_t sz = (uint32_t)(dataBytes > 0x7fffffff ? 0x7fffffff : dataBytes);
    fseek(f, 40, SEEK_SET);
    uint8_t b[4] = {(uint8_t)(sz), (uint8_t)(sz>>8), (uint8_t)(sz>>16), (uint8_t)(sz>>24)};
    fwrite(b, 1, 4, f);
    uint32_t riffSize = 36 + sz;
    fseek(f, 4, SEEK_SET);
    uint8_t r[4] = {(uint8_t)(riffSize), (uint8_t)(riffSize>>8), (uint8_t)(riffSize>>16), (uint8_t)(riffSize>>24)};
    fwrite(r, 1, 4, f);
  }

  void prepareTransportState() {
    mode_.store(EngineMode::kDuplexRecord);
    gainRef_.store(1.0f);
    gainVoc_.store(0.0f);
    vocOffset_.store(0);
    playFrame_.store(0);
    transportPlaybackStartFrame_.store(0);
    transportRecordStartFrame_.store(-1);
    transportRecordBytes_.store(0);
    firstCaptureLog_ = true;
    { std::lock_guard<std::mutex> lk(trackMu_); trackRef_.resize(1); trackRef_[0] = 0.f; playCh_ = 1; }
    LOGI("prepareTransportState (silence ref, no stream teardown)");
  }

  bool isDuplexRunning() const { return running_.load() && out_ != nullptr && in_ != nullptr; }
  int64_t getPlayFrame() const { return playFrame_.load(); }
  void setTransportPlaybackStartFrame(int64_t f) { transportPlaybackStartFrame_.store(f); }

  bool openTransportRecordFile(const char* outputPath, bool hasRecordPermission) {
    if (!running_.load() || !out_ || !in_) {
      LOGE("openTransportRecordFile: duplex not running");
      return false;
    }
    std::lock_guard<std::mutex> lk(transportFileMu_);
    if (transportRecordFile_) {
      updateWavDataSize(transportRecordFile_, transportRecordBytes_.load());
      fclose(transportRecordFile_);
      transportRecordFile_ = nullptr;
    }
    FILE* f = fopen(outputPath, "wb");
    if (!f) { LOGE("openTransportRecordFile: fopen failed %s", outputPath); return false; }
    writeWavHeader(f, 48000, 1);
    transportRecordFile_ = f;
    transportRecordPath_ = outputPath;
    transportRecordStartFrame_.store(-1);
    transportRecordBytes_.store(0);
    recordWriteCalls_.store(0);
    recordFramesWritten_.store(0);
    recordNonZeroFrames_.store(0);
    lastPeakAbs_.store(0.f);
    inputCallbacksSeen_.store(0);
    inputFramesSeen_.store(0);
    firstInputNanos_.store(0);
    lastInputNanos_.store(0);
    firstInputAfterRecordStart_.store(true);
    isTransportRecording_.store(true);
    LOGI("startRecording: writer opened path=%s running=%d in=%d out=%d isTransportRecording=1 recordPermission=%d",
         outputPath, running_.load() ? 1 : 0, in_ ? 1 : 0, out_ ? 1 : 0, hasRecordPermission ? 1 : 0);
    return true;
  }

  void stopTransportRecording() {
    isTransportRecording_.store(false);
    int64_t rwc = recordWriteCalls_.load();
    int64_t rfw = recordFramesWritten_.load();
    int64_t rnz = recordNonZeroFrames_.load();
    float lpa = lastPeakAbs_.load();
    int64_t ics = inputCallbacksSeen_.load();
    int64_t ifs = inputFramesSeen_.load();
    int64_t fin = firstInputNanos_.load();
    int64_t lin = lastInputNanos_.load();
    {
      std::lock_guard<std::mutex> lk(transportFileMu_);
      if (transportRecordFile_) {
        updateWavDataSize(transportRecordFile_, transportRecordBytes_.load());
        fclose(transportRecordFile_);
        transportRecordFile_ = nullptr;
      }
    }
    LOGI("stopRecording: writer closed inputCallbacksSeen=%lld inputFramesSeen=%lld recordWriteCalls=%lld recordFramesWritten=%lld recordNonZeroFrames=%lld lastPeakAbs=%.4f firstInputNanos=%lld lastInputNanos=%lld",
         (long long)ics, (long long)ifs, (long long)rwc, (long long)rfw, (long long)rnz, lpa, (long long)fin, (long long)lin);
    if (rfw == 0) {
      LOGE("[REC_ERROR] writer opened but ZERO frames written running=%d in=%d out=%d",
           running_.load() ? 1 : 0, in_ ? 1 : 0, out_ ? 1 : 0);
    }
  }

  int64_t getPlaybackStartSampleTime() const { return transportPlaybackStartFrame_.load(); }
  int64_t getRecordStartSampleTime() const {
    int64_t v = transportRecordStartFrame_.load();
    return v >= 0 ? v : 0;
  }
  bool hasRecordStartSampleTime() const { return transportRecordStartFrame_.load() >= 0; }

  void prepareForRecord() {
      stop();
      mode_.store(EngineMode::kDuplexRecord);
      
      // Always reset for recording
      gainRef_.store(1.0f);
      gainVoc_.store(0.0f); // Mute Vocal
      vocOffset_.store(0);
      playFrame_.store(0);
      // rings cleared in stop()
      
      LOGI("prepareForRecord: mode=kDuplexRecord gains=%.2f/%.2f offset=%d (Rings Cleared)", 
           gainRef_.load(), gainVoc_.load(), vocOffset_.load());
           
      firstCaptureLog_ = true;
  }
  
  void prepareForReview() {
      stop();
      mode_.store(EngineMode::kPlaybackReview);
      
      // PRESERVE GAINS for Review (do not reset)
      playFrame_.store(0);
      
      LOGI("prepareForReview: mode=kPlaybackReview gains=%.2f/%.2f offset=%d (Preserved)", 
           gainRef_.load(), gainVoc_.load(), vocOffset_.load());
  }

  bool startPlayback(int32_t sampleRate, int32_t channels) {
      // Assumes prepareForReview called previously
      oboe::AudioStreamBuilder outB;
      outB.setDirection(oboe::Direction::Output)
          ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
          ->setSharingMode(oboe::SharingMode::Shared)
          ->setFormat(oboe::AudioFormat::Float)
          ->setChannelCount(channels)
          ->setSampleRate(sampleRate)
          ->setDataCallback(this);
      
      if (outB.openStream(out_) != oboe::Result::OK) return false;
      
      running_.store(true);
      if (out_->requestStart() != oboe::Result::OK) { stop(); return false; }
      
      LOGI("Started PlaybackReview mode [Ref+Voc] sr=%d ch=%d", out_->getSampleRate(), channels);
      return true;
  }
  
  void setGains(float ref, float voc) {
      gainRef_.store(ref);
      gainVoc_.store(voc);
  }
  
  void setVocOffset(int32_t frames) {
      vocOffset_.store(frames);
  }  
  bool loadRefFromAsset(JNIEnv* env, jobject assetMgrObj, const char* path) {
      std::vector<float> tmp;
      int32_t ch = 1;
      int32_t sr = 0;
      if (!loadWavAsset(env, assetMgrObj, path, tmp, ch, sr)) return false;
      
      std::lock_guard<std::mutex> lk(trackMu_);
      trackRef_ = std::move(tmp);
      playCh_ = ch; 
      LOGI("Loaded Ref Asset: %zu frames, ch=%d, sr=%d", trackRef_.size()/ch, ch, sr);
      if(trackRef_.size() > 8) {
         LOGI("[RefPcm] first8=%.4f,%.4f,%.4f,%.4f...", trackRef_[0], trackRef_[1], trackRef_[2], trackRef_[3]);
      }
      return true;
  }

  // --- AUDIO CALLBACK ---
  oboe::DataCallbackResult onAudioReady(oboe::AudioStream*, void* audioData, int32_t numFrames) override {
    if (!running_.load()) return oboe::DataCallbackResult::Stop;
    
    float* out = (float*)audioData;
    int outCh = out_->getChannelCount();
    
    // Capture time
    int64_t pf = playFrame_.load();
    int64_t captureBase = pf;

    // --- Input Capture (Duplex only) ---
    int32_t gotFrames = 0;
    if (mode_ == EngineMode::kDuplexRecord && in_) {
        inBuf_.resize(numFrames * outCh);
        auto res = in_->read(inBuf_.data(), numFrames, 0);
        if (res) gotFrames = res.value();
    }

    // --- Input debug counters + transport record write (single path) ---
    if (mode_ == EngineMode::kDuplexRecord && in_) {
        inputCallbacksSeen_++;
        float peak = 0.f;
        if (gotFrames > 0) {
            inputFramesSeen_ += gotFrames;
            int64_t nowNs = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
            if (firstInputNanos_.load() == 0) firstInputNanos_.store(nowNs);
            lastInputNanos_.store(nowNs);
            int totalSamples = gotFrames * outCh;
            for (int i = 0; i < totalSamples; i++) {
                float a = std::fabs(inBuf_[i]);
                if (a > peak) peak = a;
            }
            lastPeakAbs_.store(peak);
        }
        if (isTransportRecording_.load() && firstInputAfterRecordStart_.exchange(false)) {
            LOGI("first input callback after startRecording: numFrames=%d peakAbs=%.4f isTransportRecording=1 writer!=null=%d",
                 gotFrames, peak, transportRecordFile_ != nullptr ? 1 : 0);
        }
        if (transportRecordFile_ != nullptr && isTransportRecording_.load() && gotFrames > 0) {
            std::lock_guard<std::mutex> lk(transportFileMu_);
            FILE* f = transportRecordFile_;
            if (f) {
                pcm16_.resize(gotFrames);
                for (int i = 0; i < gotFrames; i++) {
                    float s = 0;
                    for (int c = 0; c < outCh; c++) s += inBuf_[i * outCh + c];
                    s /= outCh;
                    pcm16_[i] = (int16_t)lrintf(clampf(s, -1.f, 1.f) * 32767.f);
                }
                size_t wrote = fwrite(pcm16_.data(), 2, gotFrames, f);
                if (wrote == (size_t)gotFrames) {
                    int64_t addBytes = (int64_t)gotFrames * 2;
                    transportRecordBytes_ += addBytes;
                    if (transportRecordStartFrame_.load() < 0) transportRecordStartFrame_.store(captureBase);
                    recordWriteCalls_++;
                    recordFramesWritten_ += gotFrames;
                    if (peak > 0.001f) recordNonZeroFrames_ += gotFrames;
                    lastPeakAbs_.store(peak);
                    if (recordWriteCalls_.load() <= 5) {
                        LOGI("[REC_WRITE] frames=%d totalWritten=%lld peak=%.4f fileBytesApprox=%lld",
                             gotFrames, (long long)recordFramesWritten_.load(), peak, (long long)(44 + transportRecordBytes_.load()));
                    }
                    if (recordWriteCalls_.load() % 20 == 0 && recordWriteCalls_.load() > 0 && transportRecordBytes_.load() <= 44) {
                        LOGE("record: after %lld writes file still <= 44 bytes", (long long)recordWriteCalls_.load());
                    }
                }
            }
        }
        // Also push to capture stream when transport recording (so Dart gets live pitch)
        if (gotFrames > 0 && transportRecordFile_ != nullptr && isTransportRecording_.load()) {
            int64_t relPos = captureBase - sessionStartFrame_.load();
            onFirstCaptureIfNeeded(captureBase);
            CaptureMeta meta = { gotFrames, 48000, 1, captureBase, captureBase, 0, relPos, sessionId_.load() };
            metaRing_.push((uint8_t*)&meta, sizeof(meta));
            pcmRing_.push((uint8_t*)pcm16_.data(), gotFrames * 2);
            { std::lock_guard<std::mutex> lk(cvMu_); cv_.notify_one(); }
        }
    }

    // --- Render Mixing ---
    float gRef = gainRef_.load();
    float gVoc = gainVoc_.load();
    int32_t vocOff = vocOffset_.load();
    
    // Safety check: if in record mode, FORCE ZERO voc gain just in case
    if (mode_ == EngineMode::kDuplexRecord) {
        gVoc = 0.0f; 
    }

    // Hold trackMu_ for entire mix to avoid data race with loadRefFromFile/loadVocFromFile
    {
        std::lock_guard<std::mutex> lk(trackMu_);
        size_t refLen = trackRef_.size() / playCh_;
        size_t vocLen = trackVoc_.size();
        const float* refData = trackRef_.data();
        const float* vocData = trackVoc_.data();
        int32_t pCh = playCh_;

        for (int i=0; i<numFrames; i++) {
            for (int c=0; c<outCh; c++) {
                float sum = 0.f;
                if (pf < refLen) {
                    int rIdx = (int)pf * pCh + (pCh > 1 ? c % pCh : 0);
                    sum += refData[rIdx] * gRef;
                }
                if (mode_ == EngineMode::kPlaybackReview) {
                    int64_t vPf = pf - vocOff;
                    if (vPf >= 0 && vPf < (int64_t)vocLen) {
                        sum += vocData[vPf] * gVoc;
                    }
                }
                out[i*outCh + c] = sum;
            }
            pf++;
        }
    }
    playFrame_.store(pf);
    
    // --- Process Capture (push to Java only when NOT recording to transport file) ---
    if (gotFrames > 0 && mode_ == EngineMode::kDuplexRecord && !transportRecordFile_) {
       if (firstCaptureLog_) {
           LOGI("[REC] firstCapture pf=%lld gotFrames=%d", (long long)captureBase, gotFrames);
           firstCaptureLog_ = false;
       }
       const int totalSamples = gotFrames * outCh;
       pcm16_.resize(totalSamples);
       for(int i=0; i<totalSamples; i++) pcm16_[i] = (int16_t)lrintf(clampf(inBuf_[i], -1.f, 1.f) * 32767.f);
       int64_t relPos = captureBase - sessionStartFrame_.load();
       onFirstCaptureIfNeeded(captureBase);
       CaptureMeta meta = { gotFrames, 48000, outCh, captureBase, captureBase, 0, relPos, sessionId_.load() };
       metaRing_.push((uint8_t*)&meta, sizeof(meta));
       pcmRing_.push((uint8_t*)pcm16_.data(), totalSamples * 2);
       std::lock_guard<std::mutex> lk(cvMu_);
       cv_.notify_one();
    }
    
    return oboe::DataCallbackResult::Continue;
  }
  
  void workerLoop() {
     while (running_.load()) {
       std::unique_lock<std::mutex> lk(cvMu_);
       cv_.wait_for(lk, std::chrono::milliseconds(50));
       lk.unlock();
       
       while(true) {
         if(metaRing_.size() < sizeof(CaptureMeta)) break;
         CaptureMeta meta;
         metaRing_.peek((uint8_t*)&meta, sizeof(meta));
         size_t bytes = meta.numFrames * meta.channels * 2;
         if(pcmRing_.size() < bytes) break;
         
         metaRing_.pop((uint8_t*)&meta, sizeof(meta));
         std::vector<uint8_t> pcm(bytes);
         pcmRing_.pop(pcm.data(), bytes);
         
         // Call Java
         JNIEnv* env = nullptr;
         bool att = false;
         JavaVM* jvm_local; jobject cb_local; jmethodID mid_local;
         {
             std::lock_guard<std::mutex> lk(cbMu_);
             jvm_local = jvm_; cb_local = cbGlobal_; mid_local = onCaptured_;
         }
         
         if(jvm_local && cb_local && mid_local) {
             if (jvm_local->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
                 jvm_local->AttachCurrentThread(&env, nullptr);
                 att = true;
             }
             if(env) {
                 jbyteArray arr = env->NewByteArray(bytes);
                 env->SetByteArrayRegion(arr, 0, bytes, (jbyte*)pcm.data());
                 env->CallVoidMethod(cb_local, mid_local, arr, 
                    (jint)meta.numFrames, (jint)meta.sampleRate, (jint)meta.channels,
                    (jlong)meta.inputFramePos, (jlong)meta.outputFramePos, (jlong)meta.timestampNanos,
                    (jlong)meta.outputFramePosRel, (jint)meta.sessionId);
                 env->DeleteLocalRef(arr);
                 if(att) jvm_local->DetachCurrentThread();
             }
         }
       }
     }
  }

  // JNI Handlers (StartDuplex update)
  bool startDuplex(int32_t sampleRate, int32_t channels) {
      // Assumes prepareForRecord called previously
      
      // Update Session Stats
      resetSessionStateForStart(playFrame_.load());
      
      oboe::AudioStreamBuilder outB;
      outB.setDirection(oboe::Direction::Output)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Shared)
        ->setFormat(oboe::AudioFormat::Float)
        ->setChannelCount(channels)
        ->setSampleRate(sampleRate)
        ->setDataCallback(this);
      if(outB.openStream(out_) != oboe::Result::OK) return false;

      oboe::AudioStreamBuilder inB;
      inB.setDirection(oboe::Direction::Input)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Shared)
        ->setFormat(oboe::AudioFormat::Float)
        ->setChannelCount(channels)
        ->setSampleRate(sampleRate)
        ->setInputPreset(oboe::InputPreset::Generic);
      if(inB.openStream(in_) != oboe::Result::OK) { out_.reset(); return false; }
      
      running_.store(true);
      worker_ = std::thread([this]{ workerLoop(); });
      
      in_->requestStart();
      out_->requestStart();
      LOGI("Started Duplex mode");
      return true;
  }


private:
  std::atomic<EngineMode> mode_{EngineMode::kDuplexRecord};

  std::shared_ptr<oboe::AudioStream> out_, in_;
  
  std::mutex trackMu_;
  std::vector<float> trackRef_; 
  std::vector<float> trackVoc_; 
  int32_t playCh_ = 1;
  
  std::atomic<float> gainRef_{1.0f};
  std::atomic<float> gainVoc_{1.0f};
  std::atomic<int32_t> vocOffset_{0};
  std::atomic<int64_t> playFrame_{0};
  
  std::atomic<bool> running_{false};
  std::thread worker_;
  
  // Capture
  std::vector<float> inBuf_;
  std::vector<int16_t> pcm16_;
  ByteRing pcmRing_{1<<20};
  ByteRing metaRing_{1<<16};
  std::mutex cvMu_;
  std::condition_variable cv_;
  
  std::mutex cbMu_;
  JavaVM* jvm_ = nullptr;
  jobject cbGlobal_ = nullptr;
  jmethodID onCaptured_ = nullptr;
  
  bool firstCaptureLog_ = true;
  
  std::atomic<int64_t> sessionStartFrame_{0};
  std::atomic<int32_t> sessionId_{0};
  std::atomic<int64_t> firstCaptureOutputFrame_{-1};
  std::atomic<bool> hasFirstCapture_{false};
  std::atomic<int32_t> computedVocOffsetFrames_{0};

  FILE* transportRecordFile_ = nullptr;
  std::string transportRecordPath_;
  std::mutex transportFileMu_;
  std::atomic<int64_t> transportPlaybackStartFrame_{0};
  std::atomic<int64_t> transportRecordStartFrame_{-1};
  std::atomic<int64_t> transportRecordBytes_{0};
  std::atomic<bool> isTransportRecording_{false};
  std::atomic<bool> firstInputAfterRecordStart_{false};

  // Debug counters for recording diagnostics
  std::atomic<int64_t> inputCallbacksSeen_{0};
  std::atomic<int64_t> inputFramesSeen_{0};
  std::atomic<int64_t> recordWriteCalls_{0};
  std::atomic<int64_t> recordFramesWritten_{0};
  std::atomic<int64_t> recordNonZeroFrames_{0};
  std::atomic<float> lastPeakAbs_{0.f};
  std::atomic<int64_t> firstInputNanos_{0};
  std::atomic<int64_t> lastInputNanos_{0};
};

static DuplexEngine* gEngine = nullptr;

extern "C" {
    
JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeSetCallback(JNIEnv* env, jobject, jobject cb) {
    if(!gEngine) gEngine = new DuplexEngine();
    gEngine->setJavaCallback(env, cb);
}

JNIEXPORT jboolean JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeStart(JNIEnv* env, jobject, jobject am, jstring path, jint sr, jint ch, jint fpc) {
    if(!gEngine) gEngine = new DuplexEngine();
    const char* p = env->GetStringUTFChars(path, 0);
    
    // START RECORD SESSION
    gEngine->prepareForRecord();
    
    LOGI("[DuplexEngine] START_SESSION (RECORD) playing reference=%s", p);
    
    // Choose loader based on path prefix
    bool loaded = false;
    if (p[0] == '/') {
        loaded = gEngine->loadRefFromFile(p);
    } else {
        loaded = gEngine->loadRefFromAsset(env, am, p);
    }
    
    env->ReleaseStringUTFChars(path, p);
    
    if (!loaded) {
        LOGE("nativeStart: Failed to load playback audio");
        return JNI_FALSE;
    }
    
    return gEngine->startDuplex(sr, ch) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeStop(JNIEnv* env, jobject) {
    if(gEngine) gEngine->stop();
}

JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeSetGain(JNIEnv* env, jobject, jfloat g) {
   if(gEngine) gEngine->setGains(g, 1.0f);
}

// --- NEW METHODS ---

JNIEXPORT jboolean JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeLoadReference(JNIEnv* env, jobject, jobject am, jstring path) {
    if(!gEngine) gEngine = new DuplexEngine();
    const char* p = env->GetStringUTFChars(path, 0);
    bool ok;
    if (p[0] == '/') ok = gEngine->loadRefFromFile(p);
    else ok = gEngine->loadRefFromAsset(env, am, p);
    env->ReleaseStringUTFChars(path, p);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeLoadVocal(JNIEnv* env, jobject, jstring path) {
    if(!gEngine) gEngine = new DuplexEngine();
    const char* p = env->GetStringUTFChars(path, 0);
    bool ok = gEngine->loadVocFromFile(p);
    env->ReleaseStringUTFChars(path, p);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeSetTrackGains(JNIEnv*, jobject, jfloat ref, jfloat voc) {
    if(gEngine) {
        gEngine->setGains(ref, voc);
        LOGI("nativeSetTrackGains: ref=%.2f voc=%.2f", ref, voc);
    }
}

JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeSetVocalOffset(JNIEnv*, jobject, jint frames) {
    if(gEngine) {
        gEngine->setVocOffset(frames);
        LOGI("nativeSetVocalOffset: frames=%d", frames);
    }
}

JNIEXPORT jboolean JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeStartPlaybackTwoTrack(JNIEnv*, jobject) {
    if(!gEngine) gEngine = new DuplexEngine();
    
    // Use preserved settings
    gEngine->prepareForReview();
    
    // Default 48k mono output for now
    return gEngine->startPlayback(48000, 1) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlongArray JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeGetSessionSnapshot(JNIEnv* env, jobject) {
    if (!gEngine) return nullptr;
    
    SessionSnapshot s = gEngine->getSessionSnapshot();
    
    jlongArray arr = env->NewLongArray(6);
    if (!arr) return nullptr;
    
    jlong fill[6];
    fill[0] = (jlong)s.sessionId;
    fill[1] = (jlong)s.sessionStartFrame;
    fill[2] = (jlong)s.firstCaptureOutputFrame;
    fill[3] = (jlong)s.lastOutputFrame;
    fill[4] = (jlong)s.computedVocOffsetFrames;
    fill[5] = (jlong)(s.hasFirstCapture ? 1 : 0);
    
    env->SetLongArrayRegion(arr, 0, 6, fill);
    return arr;
}

// --- Transport-style JNI (iOS semantics: one duplex, no stream open in startPlayback/startRecording) ---
JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeEnsureStarted(JNIEnv*, jobject) {
    if (!gEngine) gEngine = new DuplexEngine();
    if (gEngine->isDuplexRunning()) {
        LOGI("ensureStarted: duplex already running");
        return;
    }
    LOGI("ensureStarted: starting full duplex (input+output together)");
    gEngine->prepareTransportState();
    if (!gEngine->startDuplex(48000, 1)) {
        LOGE("ensureStarted: startDuplex failed");
        return;
    }
    LOGI("ensureStarted: duplex running");
}

JNIEXPORT jdouble JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeGetSampleRate(JNIEnv*, jobject) {
    return 48000.0;
}

JNIEXPORT jboolean JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeStartPlayback(JNIEnv* env, jobject, jobject am, jstring path, jfloat gain) {
    if (!gEngine) gEngine = new DuplexEngine();
    const char* p = env->GetStringUTFChars(path, 0);
    bool loaded = (p[0] == '/') ? gEngine->loadRefFromFile(p) : gEngine->loadRefFromAsset(env, am, p);
    env->ReleaseStringUTFChars(path, p);
    if (!loaded) {
        LOGE("startPlayback: failed to load ref");
        return JNI_FALSE;
    }
    gEngine->setGains(gain, 0.0f);
    int64_t now = gEngine->getPlayFrame();
    gEngine->setTransportPlaybackStartFrame(now);
    LOGI("startPlayback: ref loaded ok, playbackStartSampleTime=%lld", (long long)now);
    return JNI_TRUE;
}

JNIEXPORT jboolean JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeStartRecording(JNIEnv* env, jobject, jstring path, jboolean hasRecordPermission) {
    if (!gEngine) return JNI_FALSE;
    const char* p = env->GetStringUTFChars(path, 0);
    jboolean ok = gEngine->openTransportRecordFile(p, hasRecordPermission == JNI_TRUE) ? JNI_TRUE : JNI_FALSE;
    env->ReleaseStringUTFChars(path, p);
    return ok;
}

JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeStopRecording(JNIEnv*, jobject) {
    LOGI("nativeStopRecording");
    if (gEngine) gEngine->stopTransportRecording();
}

JNIEXPORT void JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeStopAll(JNIEnv*, jobject) {
    LOGI("nativeStopAll: stopping duplex, closing writer");
    if (gEngine) gEngine->stop();
}

JNIEXPORT jlong JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeGetPlaybackStartSampleTime(JNIEnv*, jobject) {
    return gEngine ? (jlong)gEngine->getPlaybackStartSampleTime() : 0;
}

JNIEXPORT jlong JNICALL Java_com_crescendo_one_1clock_1audio_OneClockAudioPlugin_nativeGetRecordStartSampleTime(JNIEnv*, jobject) {
    if (!gEngine) return -1;
    int64_t v = gEngine->getRecordStartSampleTime();
    return gEngine->hasRecordStartSampleTime() ? (jlong)v : -1;
}

}  // extern "C"

