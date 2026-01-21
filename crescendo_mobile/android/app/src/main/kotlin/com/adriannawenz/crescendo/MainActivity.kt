package com.adriannawenz.crescendo

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.adriannawenz.crescendo/aacEncoder"
    private val backgroundExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "encodeToM4A") {
                val args = call.arguments as Map<*, *>
                val pcmSamples = args["pcmSamples"] as List<Int>
                val sampleRate = args["sampleRate"] as Int
                val outputPath = args["outputPath"] as String
                val bitrate = args["bitrate"] as Int
                
                // Encode on background thread to avoid blocking UI
                backgroundExecutor.execute {
                    try {
                        val durationMs = encodePCMToM4A(pcmSamples, sampleRate, outputPath, bitrate)
                        // Result must be called on main thread
                        mainHandler.post {
                            result.success(durationMs)
                        }
                    } catch (e: Exception) {
                        mainHandler.post {
                            result.error("ENCODING_ERROR", "Failed to encode to M4A: ${e.message}", null)
                        }
                    }
                }
            } else {
                result.notImplemented()
            }
        }
    }
    
    private fun encodePCMToM4A(
        pcmSamples: List<Int>,
        sampleRate: Int,
        outputPath: String,
        bitrate: Int
    ): Int {
        val mimeType = "audio/mp4a-latm"
        val codec = MediaCodec.createEncoderByType(mimeType)
        
        val format = MediaFormat.createAudioFormat(mimeType, sampleRate, 1).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate * 1000)
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var muxerStarted = false
        var trackIndex = -1
        
        codec.start()
        
        val bufferInfo = MediaCodec.BufferInfo()
        val sampleData = ByteArray(pcmSamples.size * 2)
        
        // Convert Int samples to ByteArray (little-endian Int16)
        for (i in pcmSamples.indices) {
            val sample = pcmSamples[i].toShort()
            sampleData[i * 2] = (sample.toInt() and 0xFF).toByte()
            sampleData[i * 2 + 1] = ((sample.toInt() shr 8) and 0xFF).toByte()
        }
        
        var inputOffset = 0
        var eosSent = false
        
        while (true) {
            val inputIndex = codec.dequeueInputBuffer(10000)
            if (inputIndex >= 0) {
                val inputBuffer = codec.getInputBuffer(inputIndex)
                inputBuffer?.clear()
                
                val chunkSize = if (inputBuffer != null) {
                    minOf(inputBuffer.remaining(), sampleData.size - inputOffset)
                } else {
                    0
                }
                
                if (chunkSize > 0 && !eosSent) {
                    inputBuffer?.put(sampleData, inputOffset, chunkSize)
                    codec.queueInputBuffer(inputIndex, 0, chunkSize, 0, 0)
                    inputOffset += chunkSize
                } else if (!eosSent) {
                    codec.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    eosSent = true
                }
            }
            
            val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
            if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                trackIndex = muxer.addTrack(codec.outputFormat)
                muxer.start()
                muxerStarted = true
            } else if (outputIndex >= 0) {
                val outputBuffer = codec.getOutputBuffer(outputIndex)
                
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    bufferInfo.size = 0
                }
                
                if (bufferInfo.size != 0 && muxerStarted && outputBuffer != null) {
                    outputBuffer.position(bufferInfo.offset)
                    outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                    muxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                }
                
                codec.releaseOutputBuffer(outputIndex, false)
                
                if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    break
                }
            }
        }
        
        codec.stop()
        codec.release()
        muxer.stop()
        muxer.release()
        
        val durationMs = (pcmSamples.size.toDouble() / sampleRate * 1000).roundToInt()
        return durationMs
    }
}
