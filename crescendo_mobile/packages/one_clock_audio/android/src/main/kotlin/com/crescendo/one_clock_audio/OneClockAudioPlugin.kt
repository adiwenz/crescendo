package com.crescendo.one_clock_audio

import android.content.res.AssetManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

class OneClockAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

  private lateinit var methods: MethodChannel
  private lateinit var events: EventChannel
  private var sink: EventChannel.EventSink? = null
  private lateinit var assets: AssetManager
  private lateinit var flutterAssets: FlutterPlugin.FlutterAssets

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    System.loadLibrary("one_clock_engine")
    assets = binding.applicationContext.assets
    flutterAssets = binding.flutterAssets

    methods = MethodChannel(binding.binaryMessenger, "one_clock_audio/methods")
    methods.setMethodCallHandler(this)

    events = EventChannel(binding.binaryMessenger, "one_clock_audio/events")
    events.setStreamHandler(this)

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

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
  override fun onCancel(arguments: Any?) { sink = null }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> {
        val playbackKey = call.argument<String>("playback") ?: ""
        var playbackPath = playbackKey
        
        // Robust check: Is it a file on disk?
        val f = java.io.File(playbackKey)
        val exists = f.exists()
        if (exists && f.isAbsolute) {
             playbackPath = f.absolutePath
        } else if (playbackKey.isNotEmpty()) {
             // It's likely a flutter asset key. Resolve it.
             playbackPath = flutterAssets.getAssetFilePathByName(playbackKey)
        }
        
        println("[OneClockAudio] start: key='$playbackKey' resolved='$playbackPath' fileExists=$exists")
        
        val sr = call.argument<Int>("sampleRate") ?: 48000
        val ch = call.argument<Int>("channels") ?: 1
        val fpc = call.argument<Int>("framesPerCallback") ?: 192

        val ok = nativeStart(assets, playbackPath, sr, ch, fpc)
        if (ok) result.success(true) else result.error("START_FAIL", "nativeStart failed", null)
      }
      "stop" -> { nativeStop(); result.success(true) }
      "setGain" -> {
        val g = (call.argument<Double>("gain") ?: 1.0).toFloat()
        nativeSetGain(g)
        result.success(true)
      }
      "loadReference" -> {
        val path = call.argument<String>("path") ?: ""
        var finalPath = path
        
        // Robust check: Is it a file on disk?
        val f = java.io.File(path)
        val exists = f.exists()
        if (exists && f.isAbsolute) {
             // It's a file. Ensure C++ sees it as absolute (starts with /)
             finalPath = f.absolutePath
        } else if (path.isNotEmpty()) {
             // Assume it's an asset key
             finalPath = flutterAssets.getAssetFilePathByName(path)
        }
        
        println("[OneClockAudio] loadReference: path='$path' resolved='$finalPath' (exists=$exists)")
        
        val ok = nativeLoadReference(assets, finalPath)
        result.success(ok)
      }
      "loadVocal" -> {
        val path = call.argument<String>("path") ?: ""
        // Vocal is always a file for now (recorded), but for consistency:
        var finalPath = path
        val f = java.io.File(path)
        val exists = f.exists()
        if (exists) finalPath = f.absolutePath
        
        println("[OneClockAudio] loadVocal: path='$path' resolved='$finalPath' exists=$exists")
        
        val ok = nativeLoadVocal(finalPath)
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
      else -> result.notImplemented()
    }
  }

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
  
  // New Methods
  private external fun nativeLoadReference(assetManager: AssetManager, path: String): Boolean
  private external fun nativeLoadVocal(path: String): Boolean
  private external fun nativeSetTrackGains(ref: Float, voc: Float)
  private external fun nativeSetVocalOffset(frames: Int)
  private external fun nativeStartPlaybackTwoTrack(): Boolean
  private external fun nativeGetSessionSnapshot(): LongArray?

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
