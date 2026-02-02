package com.crescendo.one_clock_audio

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.AssetManager
import android.os.Handler
import androidx.core.content.ContextCompat
import android.Manifest
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class OneClockAudioPlugin : FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler {

  private lateinit var methods: MethodChannel
  private lateinit var events: EventChannel
  private var sink: EventChannel.EventSink? = null
  private lateinit var assets: AssetManager
  private lateinit var flutterAssets: FlutterPlugin.FlutterAssets
  private lateinit var appContext: Context

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    System.loadLibrary("one_clock_engine")

    appContext = binding.applicationContext
    assets = binding.applicationContext.assets
    flutterAssets = binding.flutterAssets

    methods = MethodChannel(binding.binaryMessenger, "one_clock_audio/methods")
    methods.setMethodCallHandler(this)

    events = EventChannel(binding.binaryMessenger, "one_clock_audio/events")
    events.setStreamHandler(this)

    // Native -> Dart capture stream
    nativeSetCallback(object : NativeCb {
      override fun onCaptured(
        pcm16: ByteArray,
        numFrames: Int,
        sampleRate: Int,
        channels: Int,
        inputFramePos: Long,
        outputFramePos: Long,
        timestampNanos: Long,
        outputFramePosRel: Long,
        sessionId: Int
      ) {
        Handler(Looper.getMainLooper()).post {
          sink?.success(
            mapOf(
              "pcm16" to pcm16,
              "numFrames" to numFrames,
              "sampleRate" to sampleRate,
              "channels" to channels,
              "inputFramePos" to inputFramePos,
              "outputFramePos" to outputFramePos,
              "timestampNanos" to timestampNanos,
              "outputFramePosRel" to outputFramePosRel,
              "sessionId" to sessionId
            )
          )
        }
      }
    })
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
    events.setStreamHandler(null)
    sink = null
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    sink = events
  }

  override fun onCancel(arguments: Any?) {
    sink = null
  }

  // ---------- Helpers ----------
  private fun resolvePath(pathOrAssetKey: String): String {
    if (pathOrAssetKey.isBlank()) return ""

    val f = File(pathOrAssetKey)
    return if (f.exists() && f.isAbsolute) {
      f.absolutePath
    } else {
      // treat as flutter asset key
      flutterAssets.getAssetFilePathByName(pathOrAssetKey)
    }
  }

  private fun log(msg: String) {
    // stdout shows up in logcat as I/System.out
    println("[OneClockAudio] $msg")
  }

  // ---------- MethodChannel ----------
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {

        // Optional capability probe (recommended)
        "getCapabilities" -> {
          // Transport + review supported. Duplex capture depends on your native engine;
          // set true if your nativeEnsureStarted actually runs full duplex (input+output).
          result.success(
            mapOf(
              "transport" to true,
              "review" to true,
              "duplex" to true
            )
          )
        }

        // ===== Legacy duplex/capture API (keep if you still use it elsewhere) =====
        "start" -> {
          val playbackKey = call.argument<String>("playback") ?: ""
          val playbackPath = resolvePath(playbackKey)

          val sr = call.argument<Int>("sampleRate") ?: 48000
          val ch = call.argument<Int>("channels") ?: 1
          val fpc = call.argument<Int>("framesPerCallback") ?: 192

          log("start: key='$playbackKey' resolved='$playbackPath'")
          val ok = nativeStart(assets, playbackPath, sr, ch, fpc)
          if (ok) result.success(true) else result.error("START_FAIL", "nativeStart failed", null)
        }

        "stop" -> {
          nativeStop()
          result.success(true)
        }

        "setGain" -> {
          val g = (call.argument<Double>("gain") ?: 1.0).toFloat()
          nativeSetGain(g)
          result.success(true)
        }

        // ===== Two-track review API =====
        "loadReference" -> {
          val path = call.argument<String>("path") ?: ""
          val resolved = if (path.isBlank()) "" else resolvePath(path)
          log("loadReference: path='$path' resolved='$resolved' exists=${File(resolved).exists()}")
          val ok = nativeLoadReference(assets, resolved)
          result.success(ok)
        }

        "loadVocal" -> {
          val path = call.argument<String>("path") ?: ""
          val resolved = if (path.isBlank()) "" else File(path).absolutePath
          log("loadVocal: path='$path' resolved='$resolved' exists=${File(resolved).exists()}")
          val ok = nativeLoadVocal(resolved)
          result.success(ok)
        }

        "setTrackGains" -> {
          val ref = (call.argument<Double>("ref") ?: 1.0).toFloat()
          val voc = (call.argument<Double>("voc") ?: 1.0).toFloat()
          nativeSetTrackGains(ref, voc)
          result.success(true)
        }

        "setVocalOffset" -> {
          val frames = call.argument<Int>("frames") ?: 0
          nativeSetVocalOffset(frames)
          result.success(true)
        }

        "startPlaybackTwoTrack" -> {
          val ok = nativeStartPlaybackTwoTrack()
          result.success(ok)
        }

        "getSessionSnapshot" -> {
          val arr = nativeGetSessionSnapshot()
          result.success(arr)
        }

        // ===== Transport-style API (this is what your OneClockDebugTestScreen uses) =====
        "ensureStarted" -> {
          log("ensureStarted")
          nativeEnsureStarted()
          result.success(true)
        }

        "getSampleRate" -> {
          // ensureStarted optional here; if nativeGetSampleRate is safe without it, keep as-is.
          val sr = nativeGetSampleRate()
          result.success(sr)
        }

        "startPlayback" -> {
          val referencePath = call.argument<String>("referencePath") ?: ""
          val gain = (call.argument<Double>("gain") ?: 1.0).toFloat()
          val resolved = resolvePath(referencePath)
          log("startPlayback path='$resolved' gain=$gain exists=${File(resolved).exists()}")

          // iOS starts engine first; match that expectation
          nativeEnsureStarted()

          val ok = nativeStartPlayback(assets, resolved, gain)
          result.success(ok)
        }

        "startRecording" -> {
          val outputPath = call.argument<String>("outputPath") ?: ""
          if (outputPath.isBlank()) {
            result.error("bad_args", "Missing outputPath", null)
            return
          }

          // Delete old file so you don't accidentally read stale header-only content
          val f = File(outputPath)
          if (f.exists()) {
            try { f.delete() } catch (_: Exception) {}
          }

          log("startRecording outputPath='$outputPath'")

          // IMPORTANT:
          // Do NOT attempt to start/stop streams here in Kotlin (that caused AAUDIO "stream stolen").
          // The native engine should already be managing duplex/transport via ensureStarted().
          nativeEnsureStarted()

          val hasRecordPermission = ContextCompat.checkSelfPermission(appContext, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
          val ok = nativeStartRecording(outputPath, hasRecordPermission)
          if (ok) {
            // Return output path (matches iOS + Dart expectations)
            result.success(outputPath)
          } else {
            result.error("START_RECORDING_FAIL", "nativeStartRecording failed", null)
          }
        }

        "stopRecording" -> {
          log("stopRecording")
          nativeStopRecording()
          result.success(true)
        }

        "stopAll" -> {
          log("stopAll")
          nativeStopAll()
          result.success(true)
        }

        "getPlaybackStartSampleTime" -> {
          val t = nativeGetPlaybackStartSampleTime()
          result.success(t)
        }

        "getRecordStartSampleTime" -> {
          val t = nativeGetRecordStartSampleTime()
          // match Dart expectation: null if not available
          result.success(if (t < 0) null else t)
        }

        "mixWithOffset" -> {
          val refPath = call.argument<String>("referencePath") ?: ""
          val vocalPath = call.argument<String>("vocalPath") ?: ""
          val outPath = call.argument<String>("outPath") ?: ""
          val offset = (call.argument<Number>("vocalOffsetSamples") ?: 0).toLong()
          val refGain = (call.argument<Double>("refGain") ?: 1.0).toFloat()
          val vocalGain = (call.argument<Double>("vocalGain") ?: 1.0).toFloat()

          try {
            val out = mixWavWithOffset(refPath, vocalPath, outPath, offset, refGain, vocalGain)
            result.success(out)
          } catch (e: Exception) {
            result.error("mix_error", e.message, null)
          }
        }

        else -> result.notImplemented()
      }
    } catch (e: Exception) {
      result.error("native_error", e.message, null)
    }
  }

  // ---------- Offline mix helpers ----------
  private fun mixWavWithOffset(
    referencePath: String,
    vocalPath: String,
    outPath: String,
    vocalOffsetSamples: Long,
    refGain: Float,
    vocalGain: Float
  ): String {
    val refSamples = readWavToFloatMono(referencePath)
    val vocSamples = readWavToFloatMono(vocalPath)
    if (refSamples == null || vocSamples == null) throw IllegalArgumentException("Failed to read ref or vocal WAV")

    val refSr = refSamples.second
    val vocSr = vocSamples.second
    if (kotlin.math.abs(refSr - vocSr) > 1.0) throw IllegalArgumentException("Sample rate mismatch: $refSr vs $vocSr")

    val ref = refSamples.first
    val voc = vocSamples.first

    val startSample = minOf(0L, vocalOffsetSamples)
    val refEnd = ref.size.toLong()
    val vocEnd = vocalOffsetSamples + voc.size.toLong()
    val endSample = maxOf(refEnd, vocEnd)

    val totalLength = (endSample - startSample).toInt().coerceAtLeast(0)
    val out = FloatArray(totalLength)

    fun addToMix(source: FloatArray, offsetFromStart: Long, gain: Float) {
      val destStart = (offsetFromStart - startSample).toInt()
      for (i in source.indices) {
        val idx = destStart + i
        if (idx in 0 until totalLength) out[idx] += source[i] * gain
      }
    }

    addToMix(ref, 0L, refGain)
    addToMix(voc, vocalOffsetSamples, vocalGain)

    for (i in 0 until totalLength) out[i] = out[i].coerceIn(-1f, 1f)
    writeFloatMonoWav(outPath, out, refSr.toInt())
    return outPath
  }

  private fun readWavToFloatMono(path: String): Pair<FloatArray, Double>? {
    val f = File(path)
    if (!f.exists()) return null
    val bytes = f.readBytes()
    if (bytes.size < 44) return null
    if (bytes[0].toInt() != 'R'.code || bytes[1].toInt() != 'I'.code || bytes[2].toInt() != 'F'.code || bytes[3].toInt() != 'F'.code) return null

    var sr = 48000
    var ch = 1
    var dataOff = 44
    var dataLen = 0
    var i = 12
    while (i + 8 <= bytes.size) {
      val chunkId = String(bytes, i, 4, Charsets.US_ASCII)
      val chunkSize =
        (bytes[i + 4].toInt() and 0xff) or
          ((bytes[i + 5].toInt() and 0xff) shl 8) or
          ((bytes[i + 6].toInt() and 0xff) shl 16) or
          ((bytes[i + 7].toInt() and 0xff) shl 24)
      i += 8
      if (chunkId == "fmt ") {
        if (chunkSize >= 16) {
          ch = (bytes[i].toInt() and 0xff) or ((bytes[i + 1].toInt() and 0xff) shl 8)
          sr =
            (bytes[i + 4].toInt() and 0xff) or
              ((bytes[i + 5].toInt() and 0xff) shl 8) or
              ((bytes[i + 6].toInt() and 0xff) shl 16) or
              ((bytes[i + 7].toInt() and 0xff) shl 24)
        }
      } else if (chunkId == "data") {
        dataOff = i
        dataLen = chunkSize.coerceAtMost(bytes.size - i)
        break
      }
      i += chunkSize
      if (i and 1 != 0) i++ // padding
    }
    if (dataLen <= 0) return null

    val numSamplesTotal = dataLen / 2
    val numFrames = numSamplesTotal / ch
    val samples = FloatArray(numFrames)

    val src = java.nio.ByteBuffer.wrap(bytes, dataOff, dataLen).order(java.nio.ByteOrder.LITTLE_ENDIAN)
    for (j in 0 until numFrames) {
      var sum = 0f
      for (c in 0 until ch) sum += src.short.toInt() / 32768f
      samples[j] = sum / ch
    }
    return Pair(samples, sr.toDouble())
  }

  private fun writeFloatMonoWav(path: String, samples: FloatArray, sampleRate: Int) {
    val f = File(path)
    if (f.exists()) f.delete()

    f.outputStream().use { out ->
      val hdr = ByteArray(44)
      hdr[0] = 'R'.code.toByte(); hdr[1] = 'I'.code.toByte(); hdr[2] = 'F'.code.toByte(); hdr[3] = 'F'.code.toByte()

      val dataBytes = samples.size * 4
      val riffSize = 36 + dataBytes
      hdr[4] = (riffSize and 0xff).toByte()
      hdr[5] = (riffSize shr 8 and 0xff).toByte()
      hdr[6] = (riffSize shr 16 and 0xff).toByte()
      hdr[7] = (riffSize shr 24).toByte()

      hdr[8] = 'W'.code.toByte(); hdr[9] = 'A'.code.toByte(); hdr[10] = 'V'.code.toByte(); hdr[11] = 'E'.code.toByte()
      hdr[12] = 'f'.code.toByte(); hdr[13] = 'm'.code.toByte(); hdr[14] = 't'.code.toByte(); hdr[15] = ' '.code.toByte()
      hdr[16] = 16; hdr[17] = 0; hdr[18] = 0; hdr[19] = 0
      hdr[20] = 3; hdr[21] = 0 // float32
      hdr[22] = 1; hdr[23] = 0 // mono

      hdr[24] = (sampleRate and 0xff).toByte()
      hdr[25] = (sampleRate shr 8 and 0xff).toByte()
      hdr[26] = (sampleRate shr 16 and 0xff).toByte()
      hdr[27] = (sampleRate shr 24).toByte()

      val byteRate = sampleRate * 4
      hdr[28] = (byteRate and 0xff).toByte()
      hdr[29] = (byteRate shr 8 and 0xff).toByte()
      hdr[30] = (byteRate shr 16 and 0xff).toByte()
      hdr[31] = (byteRate shr 24).toByte()

      hdr[32] = 4; hdr[33] = 0 // block align
      hdr[34] = 32; hdr[35] = 0 // bits
      hdr[36] = 'd'.code.toByte(); hdr[37] = 'a'.code.toByte(); hdr[38] = 't'.code.toByte(); hdr[39] = 'a'.code.toByte()

      hdr[40] = (dataBytes and 0xff).toByte()
      hdr[41] = (dataBytes shr 8 and 0xff).toByte()
      hdr[42] = (dataBytes shr 16 and 0xff).toByte()
      hdr[43] = (dataBytes shr 24).toByte()

      out.write(hdr)

      val buf = java.nio.ByteBuffer.allocate(samples.size * 4).order(java.nio.ByteOrder.LITTLE_ENDIAN)
      for (s in samples) buf.putFloat(s)
      out.write(buf.array())
    }
  }

  // ---------- Native externs ----------
  private external fun nativeStart(
    assetManager: AssetManager,
    wavAssetPath: String,
    preferredSampleRate: Int,
    channels: Int,
    framesPerCallback: Int
  ): Boolean

  private external fun nativeStop()
  private external fun nativeSetGain(gain: Float)
  private external fun nativeSetCallback(cb: Any)

  // Review
  private external fun nativeLoadReference(assetManager: AssetManager, path: String): Boolean
  private external fun nativeLoadVocal(path: String): Boolean
  private external fun nativeSetTrackGains(ref: Float, voc: Float)
  private external fun nativeSetVocalOffset(frames: Int)
  private external fun nativeStartPlaybackTwoTrack(): Boolean
  private external fun nativeGetSessionSnapshot(): LongArray?

  // Transport
  private external fun nativeEnsureStarted()
  private external fun nativeGetSampleRate(): Double
  private external fun nativeStartPlayback(assetManager: AssetManager, path: String, gain: Float): Boolean
  private external fun nativeStartRecording(outputPath: String, hasRecordPermission: Boolean): Boolean
  private external fun nativeStopRecording()
  private external fun nativeStopAll()
  private external fun nativeGetPlaybackStartSampleTime(): Long
  private external fun nativeGetRecordStartSampleTime(): Long

  interface NativeCb {
    fun onCaptured(
      pcm16: ByteArray,
      numFrames: Int,
      sampleRate: Int,
      channels: Int,
      inputFramePos: Long,
      outputFramePos: Long,
      timestampNanos: Long,
      outputFramePosRel: Long,
      sessionId: Int
    )
  }
}
