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
    print("[AppDelegate] Setting up audioSession method channel")
    let controller = window?.rootViewController as! FlutterViewController
    let audioSessionChannel = FlutterMethodChannel(
      name: "com.adriannawenz.crescendo/audioSession",
      binaryMessenger: controller.binaryMessenger
    )
    
    audioSessionChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      print("[AppDelegate] audioSession method call: \(call.method)")
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
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
