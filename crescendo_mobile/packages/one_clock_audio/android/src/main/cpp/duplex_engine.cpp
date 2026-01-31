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
};

class DuplexEngine : public oboe::AudioStreamCallback {
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
    onCaptured_ = env->GetMethodID(cls, "onCaptured", "([BIIIJJJ)V");
    if (!onCaptured_) LOGE("Failed to find onCaptured([BIIIJJJ)V");
  }

  bool start(JNIEnv* env,
             jobject assetMgrObj,
             const char* wavAssetPath,
             int32_t preferredSampleRate,
             int32_t channels,
             int32_t framesPerCallback) {
    stop();

    if (!loadWavPCM16FromAssets(env, assetMgrObj, wavAssetPath, preferredSampleRate)) {
      LOGE("Failed to load WAV asset");
      return false;
    }

    // Since we resampled on load, use the preferred rate.
    int32_t targetSR = preferredSampleRate;

    if (!openStreams(targetSR, channels, framesPerCallback)) {
      LOGE("Failed to open streams");
      return false;
    }

    running_.store(true);
    worker_ = std::thread([this]{ workerLoop(); });

    // Start input then output
    if (in_->requestStart() != oboe::Result::OK) { stop(); return false; }
    if (out_->requestStart() != oboe::Result::OK) { stop(); return false; }

    LOGI("Started duplex sr=%d ch=%d", sr_, channels);
    return true;
  }

  void stop() {
    running_.store(false);

    if (in_)  in_->requestStop();
    if (out_) out_->requestStop();

    {
      std::lock_guard<std::mutex> lk(cvMu_);
      cv_.notify_all();
    }
    if (worker_.joinable()) worker_.join();

    if (in_)  { in_->close();  in_.reset(); }
    if (out_) { out_->close(); out_.reset(); }

    playFrame_.store(0);
  }

  void setPlaybackGain(float g) { gain_.store(g); }

  // MASTER CLOCK: output callback
  oboe::DataCallbackResult onAudioReady(oboe::AudioStream*,
                                       void* audioData,
                                       int32_t numFrames) override {
    if (!running_.load()) return oboe::DataCallbackResult::Stop;

    float* out = reinterpret_cast<float*>(audioData);
    const int outCh = out_->getChannelCount();

    // (1) Pull mic frames INSIDE output callback (ties capture cadence to output callback)
    inBuf_.resize((size_t)numFrames * outCh);
    auto readRes = in_->read(inBuf_.data(), numFrames, 0 /*timeout*/);
    int32_t gotFrames = readRes ? readRes.value() : 0;

    // (2) Timestamp output (clock)
    int64_t outFramePos = 0;
    int64_t outNanos = 0;
    if (out_->getTimestamp(CLOCK_MONOTONIC, &outFramePos, &outNanos) == oboe::Result::OK) {
      lastOutFramePos_.store(outFramePos);
      lastTimestampNanos_.store(outNanos);
    }

    // (3) Timestamp input frame pos (best effort)
    int64_t inFramePos = 0;
    int64_t inNanos = 0;
    if (in_->getTimestamp(CLOCK_MONOTONIC, &inFramePos, &inNanos) == oboe::Result::OK) {
      lastInFramePos_.store(inFramePos);
    }

    // (4) Render playback from float buffer
    const float g = gain_.load();
    const int framesInPlay = (int)(play_.size() / (size_t)playCh_);
    int64_t pf = playFrame_.load();

    for (int i = 0; i < numFrames; i++) {
      for (int c = 0; c < outCh; c++) {
        float s = 0.f;
        if (framesInPlay > 0) {
          int wavC = (playCh_ == 1) ? 0 : (c % playCh_);
          int idx = (int)(pf % framesInPlay) * playCh_ + wavC;
          s = play_[(size_t)idx];
        }
        out[i * outCh + c] = s * g;
      }
      pf++;
    }
    playFrame_.store(pf);

    // (5) Convert captured float->PCM16 and push to rings (NO JNI here)
    if (gotFrames > 0) {
      const int totalSamples = gotFrames * outCh;
      pcm16_.resize((size_t)totalSamples);

      for (int i = 0; i < totalSamples; i++) {
        float x = clampf(inBuf_[i], -1.f, 1.f);
        pcm16_[(size_t)i] = (int16_t)lrintf(x * 32767.f);
      }

      CaptureMeta meta;
      meta.numFrames = gotFrames;
      meta.sampleRate = sr_;
      meta.channels = outCh;
      meta.inputFramePos = lastInFramePos_.load();
      meta.outputFramePos = lastOutFramePos_.load();
      meta.timestampNanos = lastTimestampNanos_.load();

      const uint8_t* metaBytes = reinterpret_cast<const uint8_t*>(&meta);
      const uint8_t* pcmBytes  = reinterpret_cast<const uint8_t*>(pcm16_.data());
      const size_t pcmLen = (size_t)totalSamples * sizeof(int16_t);

      bool okMeta = metaRing_.push(metaBytes, sizeof(CaptureMeta));
      bool okPcm  = pcmRing_.push(pcmBytes, pcmLen);

      if (okMeta && okPcm) {
        std::lock_guard<std::mutex> lk(cvMu_);
        cv_.notify_one();
      }
    }

    return oboe::DataCallbackResult::Continue;
  }

  void onErrorAfterClose(oboe::AudioStream*, oboe::Result error) override {
    LOGE("Oboe error after close: %d", (int)error);
    stop();
  }

private:
  bool openStreams(int32_t sampleRate, int32_t channels, int32_t framesPerCallback) {
    // OUTPUT (callback-driven)
    oboe::AudioStreamBuilder outB;
    outB.setDirection(oboe::Direction::Output)
       ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
       ->setSharingMode(oboe::SharingMode::Shared)
       ->setFormat(oboe::AudioFormat::Float)
       ->setChannelCount(channels)
       ->setSampleRate(sampleRate)
       ->setDataCallback(this);
    if (framesPerCallback > 0) outB.setFramesPerDataCallback(framesPerCallback);

    if (outB.openStream(out_) != oboe::Result::OK || !out_) return false;

    // INPUT (we read manually in output callback)
    oboe::AudioStreamBuilder inB;
    inB.setDirection(oboe::Direction::Input)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Shared)
      ->setFormat(oboe::AudioFormat::Float)
      ->setChannelCount(channels)
      ->setSampleRate(sampleRate)
      ->setInputPreset(oboe::InputPreset::Generic);

    if (inB.openStream(in_) != oboe::Result::OK || !in_) {
      out_.reset();
      return false;
    }

    // Negotiated
    sr_ = out_->getSampleRate();
    LOGI("Negotiated sr=%d outCh=%d inCh=%d",
         sr_, out_->getChannelCount(), in_->getChannelCount());
    return true;
  }

  bool loadWavPCM16FromAssets(JNIEnv* env, jobject assetMgrObj, const char* path, int32_t targetSampleRate) {
    if (!path || std::strlen(path) == 0) return false;

    AAssetManager* mgr = AAssetManager_fromJava(env, assetMgrObj);
    if (!mgr) return false;

    AAsset* asset = AAssetManager_open(mgr, path, AASSET_MODE_BUFFER);
    if (!asset) {
      LOGE("Could not open asset: %s", path);
      return false;
    }

    const uint8_t* data = (const uint8_t*)AAsset_getBuffer(asset);
    size_t size = (size_t)AAsset_getLength(asset);
    if (!data || size < 44) { AAsset_close(asset); return false; }

    auto u32 = [&](size_t off)->uint32_t {
      return (uint32_t)data[off] | ((uint32_t)data[off+1] << 8) |
             ((uint32_t)data[off+2] << 16) | ((uint32_t)data[off+3] << 24);
    };
    auto u16 = [&](size_t off)->uint16_t {
      return (uint16_t)data[off] | ((uint16_t)data[off+1] << 8);
    };

    if (memcmp(data, "RIFF", 4) || memcmp(data+8, "WAVE", 4)) {
      LOGE("Not a WAV");
      AAsset_close(asset);
      return false;
    }

    uint16_t format = 0, ch = 0, bps = 0;
    uint32_t sr = 0;
    const uint8_t* pcm = nullptr;
    uint32_t pcmBytes = 0;

    size_t cur = 12;
    while (cur + 8 <= size) {
      const char* id = (const char*)(data + cur);
      uint32_t chunkSize = u32(cur + 4);
      cur += 8;
      if (cur + chunkSize > size) break;

      if (!memcmp(id, "fmt ", 4)) {
        if (chunkSize < 16) break;
        format = u16(cur + 0);
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

    if (!pcm || format != 1 || bps != 16 || ch == 0 || sr == 0) {
      LOGE("WAV must be PCM16");
      AAsset_close(asset);
      return false;
    }

    // Set actual sample rate and channel count if we were to play natively
    // BUT we will resample to targetSampleRate if needed.
    wavSampleRate_ = targetSampleRate; // We pretend it's target rate after resampling
    playCh_ = (int32_t)ch;

    const int16_t* pcm16 = (const int16_t*)pcm;
    size_t srcSamples = pcmBytes / sizeof(int16_t);
    std::vector<float> srcData(srcSamples);
    for (size_t i = 0; i < srcSamples; i++) srcData[i] = (float)pcm16[i] / 32768.0f;
    
    AAsset_close(asset);

    // Resample if needed (Linear Interpolation)
    if ((int32_t)sr != targetSampleRate && targetSampleRate > 0) {
      double ratio = (double)sr / (double)targetSampleRate;
      size_t dstFrames = (size_t)((srcSamples / ch) / ratio);
      size_t dstSamples = dstFrames * ch;
      play_.resize(dstSamples);
      
      LOGI("Resampling WAV %d -> %d Hz (ratio %.3f)", sr, targetSampleRate, ratio);

      for (size_t i = 0; i < dstFrames; i++) {
        double srcIdx = i * ratio;
        size_t idx0 = (size_t)srcIdx;
        size_t idx1 = idx0 + 1;
        float frac = (float)(srcIdx - idx0);

        if (idx1 >= (srcSamples / ch)) idx1 = idx0; // Clamp

        for (int c = 0; c < ch; c++) {
          float s0 = srcData[idx0 * ch + c];
          float s1 = srcData[idx1 * ch + c];
          play_[i * ch + c] = s0 + (s1 - s0) * frac;
        }
      }
    } else {
      // No resampling
      play_ = std::move(srcData);
      LOGI("Loaded WAV sr=%d (native) ch=%d samples=%zu", sr, playCh_, srcSamples);
    }

    playFrame_.store(0);
    return true;
  }

  void workerLoop() {
    while (running_.load()) {
      std::unique_lock<std::mutex> lk(cvMu_);
      cv_.wait_for(lk, std::chrono::milliseconds(50));
      lk.unlock();

      while (true) {
        // 1. Peek Meta to see if we have a full header
        if (metaRing_.size() < sizeof(CaptureMeta)) break;
        
        CaptureMeta meta;
        if (!metaRing_.peek((uint8_t*)&meta, sizeof(CaptureMeta))) break;

        // 2. Check if we have enough PCM for this meta
        const size_t pcmBytesNeeded =
          (size_t)meta.numFrames * (size_t)meta.channels * sizeof(int16_t);
        
        if (pcmRing_.size() < pcmBytesNeeded) {
          // Meta is there but PCM not ready yet? Wait for next spin.
          break; 
        }

        // 3. Pop both (guaranteed to succeed now)
        metaRing_.pop((uint8_t*)&meta, sizeof(CaptureMeta));
        
        std::vector<uint8_t> pcmBytes(pcmBytesNeeded);
        pcmRing_.pop(pcmBytes.data(), pcmBytesNeeded);

        // Call Java callback
        JavaVM* jvm;
        jobject cb;
        jmethodID mid;
        {
          std::lock_guard<std::mutex> lock(cbMu_);
          jvm = jvm_;
          cb = cbGlobal_;
          mid = onCaptured_;
        }
        if (!jvm || !cb || !mid) continue;

        JNIEnv* env = nullptr;
        bool attached = false;
        if (jvm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) {
          if (jvm->AttachCurrentThread(&env, nullptr) == JNI_OK) attached = true;
        }
        if (!env) continue;

        jbyteArray arr = env->NewByteArray((jsize)pcmBytesNeeded);
        env->SetByteArrayRegion(arr, 0, (jsize)pcmBytesNeeded, (const jbyte*)pcmBytes.data());

        env->CallVoidMethod(cb, mid, arr,
                            (jint)meta.numFrames,
                            (jint)meta.sampleRate,
                            (jint)meta.channels,
                            (jlong)meta.inputFramePos,
                            (jlong)meta.outputFramePos,
                            (jlong)meta.timestampNanos);

        env->DeleteLocalRef(arr);
        if (attached) jvm->DetachCurrentThread();
      }
    }
  }

private:
  // Streams
  std::shared_ptr<oboe::AudioStream> out_;
  std::shared_ptr<oboe::AudioStream> in_;

  // Playback
  std::vector<float> play_;
  int32_t playCh_ = 1;
  int32_t wavSampleRate_ = 0;
  int32_t sr_ = 48000;
  std::atomic<int64_t> playFrame_{0};
  std::atomic<float> gain_{1.0f};

  // Capture buffers
  std::vector<float> inBuf_;
  std::vector<int16_t> pcm16_;

  // Clock metadata
  std::atomic<int64_t> lastOutFramePos_{0};
  std::atomic<int64_t> lastInFramePos_{0};
  std::atomic<int64_t> lastTimestampNanos_{0};

  // Rings
  ByteRing pcmRing_;
  ByteRing metaRing_;

  // Worker wake
  std::mutex cvMu_;
  std::condition_variable cv_;

  // Run state
  std::atomic<bool> running_{false};
  std::thread worker_;

  // Java callback
  std::mutex cbMu_;
  JavaVM* jvm_ = nullptr;
  jobject cbGlobal_ = nullptr;
  jmethodID onCaptured_ = nullptr;
};

// ---------------- JNI (RegisterNatives) ----------------
static DuplexEngine* gEngine = nullptr;

static jboolean nativeStart(JNIEnv* env, jobject,
                            jobject assetManager,
                            jstring wavAssetPath,
                            jint preferredSampleRate,
                            jint channels,
                            jint framesPerCallback) {
  if (!gEngine) gEngine = new DuplexEngine();

  const char* path = env->GetStringUTFChars(wavAssetPath, nullptr);
  bool ok = gEngine->start(env, assetManager, path,
                          (int32_t)preferredSampleRate,
                          (int32_t)channels,
                          (int32_t)framesPerCallback);
  env->ReleaseStringUTFChars(wavAssetPath, path);
  return ok ? JNI_TRUE : JNI_FALSE;
}

static void nativeStop(JNIEnv*, jobject) {
  if (gEngine) gEngine->stop();
}

static void nativeSetGain(JNIEnv*, jobject, jfloat gain) {
  if (gEngine) gEngine->setPlaybackGain(gain);
}

static void nativeSetCallback(JNIEnv* env, jobject, jobject cb) {
  if (!gEngine) gEngine = new DuplexEngine();
  gEngine->setJavaCallback(env, cb);
}

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  JNIEnv* env = nullptr;
  if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;

  // MUST MATCH Kotlin plugin class path
  const char* kClassName = "com/crescendo/one_clock_audio/OneClockAudioPlugin";
  jclass cls = env->FindClass(kClassName);
  if (!cls) {
    LOGE("FindClass failed for %s", kClassName);
    return JNI_ERR;
  }

  JNINativeMethod methods[] = {
    {"nativeStart", "(Landroid/content/res/AssetManager;Ljava/lang/String;III)Z", (void*)nativeStart},
    {"nativeStop", "()V", (void*)nativeStop},
    {"nativeSetGain", "(F)V", (void*)nativeSetGain},
    {"nativeSetCallback", "(Ljava/lang/Object;)V", (void*)nativeSetCallback},
  };

  if (env->RegisterNatives(cls, methods, sizeof(methods)/sizeof(methods[0])) != 0) {
    LOGE("RegisterNatives failed");
    return JNI_ERR;
  }

  return JNI_VERSION_1_6;
}
