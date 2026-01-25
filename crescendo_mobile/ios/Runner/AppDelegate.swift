import Flutter
import UIKit
import AVFoundation
import AudioToolbox

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Set up method channel for audio session control
    let controller = window?.rootViewController as! FlutterViewController
    let audioSessionChannel = FlutterMethodChannel(
      name: "com.adriannawenz.crescendo/audioSession",
      binaryMessenger: controller.binaryMessenger
    )
    
      } catch {
        #if DEBUG
        print("[AppDelegate] ERROR overriding output port: \(error)")
        #endif
        result(FlutterError(
          code: "AUDIO_SESSION_ERROR",
          message: "Failed to override output port: \(error.localizedDescription)",
          details: nil
        ))
      }
    }
    
    audioSessionChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      let session = AVAudioSession.sharedInstance()
      
      switch call.method {
      case "overrideOutputPort":
        guard let args = call.arguments as? [String: Any],
              let useSpeaker = args["useSpeaker"] as? Bool else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing useSpeaker", details: nil))
          return
        }
        do {
          try session.overrideOutputAudioPort(useSpeaker ? .speaker : .none)
          result(true)
        } catch {
          result(FlutterError(code: "AUDIO_SESSION_ERROR", message: error.localizedDescription, details: nil))
        }
        
      case "getSyncMetrics":
        let currentRoute = session.currentRoute
        let isHeadphones = currentRoute.outputs.contains { output in
            output.portType == .headphones || 
            output.portType == .bluetoothA2DP || 
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE
        }
        
        let metrics: [String: Any] = [
            "inputLatency": session.inputLatency,
            "outputLatency": session.outputLatency,
            "ioBufferDuration": session.ioBufferDuration,
            "isHeadphones": isHeadphones,
            "sampleRate": session.sampleRate,
            "currentHostTime": CACurrentMediaTime()
        ]
        result(metrics)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    // Set up method channel for AAC encoding
    let aacEncoderChannel = FlutterMethodChannel(
      name: "com.adriannawenz.crescendo/aacEncoder",
      binaryMessenger: controller.binaryMessenger
    )
    
    aacEncoderChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard call.method == "encodeToM4A" else {
        result(FlutterMethodNotImplemented)
        return
      }
      
      guard let args = call.arguments as? [String: Any],
            let pcmSamples = args["pcmSamples"] as? [Int],
            let sampleRate = args["sampleRate"] as? Int,
            let outputPath = args["outputPath"] as? String,
            let bitrate = args["bitrate"] as? Int else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Missing or invalid arguments",
          details: nil
        ))
        return
      }
      
      // Encode PCM to AAC M4A on background queue
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let durationMs = try self.encodePCMToM4A(
            pcmSamples: pcmSamples,
            sampleRate: sampleRate,
            outputPath: outputPath,
            bitrate: bitrate
          )
          // Result callback must be on main thread
          DispatchQueue.main.async {
            result(durationMs)
          }
        } catch {
          #if DEBUG
          print("[AppDelegate] ERROR encoding to M4A: \(error)")
          #endif
          // Result callback must be on main thread
          DispatchQueue.main.async {
            result(FlutterError(
              code: "ENCODING_ERROR",
              message: "Failed to encode to M4A: \(error.localizedDescription)",
              details: nil
            ))
          }
        }
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  /// Encode PCM samples to AAC M4A file using ExtAudioFile
  private func encodePCMToM4A(
    pcmSamples: [Int],
    sampleRate: Int,
    outputPath: String,
    bitrate: Int
  ) throws -> Int {
    
    // Convert Int array to Int16 array
    let int16Samples = pcmSamples.map { Int16($0) }
    let frameCount = UInt32(int16Samples.count)
    
    // Create PCM format description
    var pcmFormat = AudioStreamBasicDescription(
      mSampleRate: Float64(sampleRate),
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian,
      mBytesPerPacket: 2,
      mFramesPerPacket: 1,
      mBytesPerFrame: 2,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 16,
      mReserved: 0
    )
    
    // Create AAC format description
    var aacFormat = AudioStreamBasicDescription(
      mSampleRate: Float64(sampleRate),
      mFormatID: kAudioFormatMPEG4AAC,
      mFormatFlags: 0,
      mBytesPerPacket: 0,
      mFramesPerPacket: 1024,
      mBytesPerFrame: 0,
      mChannelsPerFrame: 1,
      mBitsPerChannel: 0,
      mReserved: 0
    )
    
    // Create output file URL
    let outputURL = URL(fileURLWithPath: outputPath)
    
    // Create ExtAudioFile
    var extAudioFile: ExtAudioFileRef?
    var status = ExtAudioFileCreateWithURL(
      outputURL as CFURL,
      kAudioFileM4AType,
      &aacFormat,
      nil,
      AudioFileFlags.eraseFile.rawValue,
      &extAudioFile
    )
    
    guard status == noErr, let file = extAudioFile else {
      throw NSError(domain: "AACEncoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to create output file"])
    }
    
    // Set client data format (PCM)
    status = ExtAudioFileSetProperty(
      file,
      kExtAudioFileProperty_ClientDataFormat,
      UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
      &pcmFormat
    )
    
    guard status == noErr else {
      throw NSError(domain: "AACEncoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to set client format"])
    }
    
    // Note: ExtAudioFile doesn't expose a direct bitrate property.
    // The bitrate is controlled by the AudioConverter internally.
    // For AAC encoding, iOS will use a reasonable default bitrate based on the format.
    // If specific bitrate control is needed, we would need to use AudioConverter directly,
    // but for our use case, the default is acceptable.
    
    // Prepare sample data
    let sampleData = int16Samples.withUnsafeBufferPointer { buffer in
      Data(buffer: buffer)
    }
    
    // Create AudioBufferList
    var bufferList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(
        mNumberChannels: 1,
        mDataByteSize: UInt32(sampleData.count),
        mData: UnsafeMutableRawPointer(mutating: sampleData.withUnsafeBytes { $0.baseAddress })
      )
    )
    
    // Write frames
    status = ExtAudioFileWrite(file, frameCount, &bufferList)
    
    guard status == noErr else {
      ExtAudioFileDispose(file)
      throw NSError(domain: "AACEncoder", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to write audio data (status=\(status))"])
    }
    
    // Flush and close file
    status = ExtAudioFileDispose(file)
    if status != noErr {
      #if DEBUG
      print("[AppDelegate] Warning: Error disposing ExtAudioFile (status=\(status))")
      #endif
    }
    
    // Verify file was created
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: outputPath) else {
      throw NSError(domain: "AACEncoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Output file was not created: \(outputPath)"])
    }
    
    // Calculate duration
    let durationMs = Int((Double(int16Samples.count) / Double(sampleRate)) * 1000.0)
    
    #if DEBUG
    let fileSize = (try? fileManager.attributesOfItem(atPath: outputPath)[.size] as? Int64) ?? 0
    print("[AppDelegate] Encoded M4A: \(outputPath), duration=\(durationMs)ms, frames=\(int16Samples.count), size=\(fileSize) bytes")
    #endif
    
    return durationMs
  }
}
