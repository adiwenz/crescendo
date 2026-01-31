package com.adriannawenz.crescendo

import android.content.res.AssetManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DuplexAudioPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

  private lateinit var methods: MethodChannel
  private lateinit var events: EventChannel
  private var sink: EventChannel.EventSink? = null
  private lateinit var flutterAssets: FlutterPlugin.FlutterAssets
  private lateinit var assetManager: AssetManager

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    System.loadLibrary("duplex_engine")
    assetManager = binding.applicationContext.assets
    flutterAssets = binding.flutterAssets

    methods = MethodChannel(binding.binaryMessenger, "duplex_audio/methods")
    methods.setMethodCallHandler(this)

    events = EventChannel(binding.binaryMessenger, "duplex_audio/events")
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
        android.os.Handler(android.os.Looper.getMainLooper()).post {
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
        val wavAssetPath = call.argument<String>("wavAssetPath") ?: ""
        val resolvedPath = flutterAssets.getAssetFilePathByName(wavAssetPath)
        val sr = call.argument<Int>("sampleRate") ?: 48000
        val ch = call.argument<Int>("channels") ?: 1
        val fpc = call.argument<Int>("framesPerCallback") ?: 192

        val ok = nativeStart(assetManager, resolvedPath, sr, ch, fpc)
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
