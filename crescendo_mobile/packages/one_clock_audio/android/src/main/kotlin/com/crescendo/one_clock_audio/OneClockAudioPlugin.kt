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
        timestampNanos: Long
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
                "timestampNanos" to timestampNanos
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
        val playbackPath = if (playbackKey.isNotEmpty()) flutterAssets.getAssetFilePathByName(playbackKey) else ""
        
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

  interface NativeCb {
    fun onCaptured(
      pcm16: ByteArray,
      numFrames: Int,
      sampleRate: Int,
      channels: Int,
      inputFramePos: Long,
      outputFramePos: Long,
      timestampNanos: Long
    )
  }
}
