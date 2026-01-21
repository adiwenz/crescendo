import Flutter
import UIKit
import AVFoundation

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
    
    audioSessionChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard call.method == "overrideOutputPort" else {
        result(FlutterMethodNotImplemented)
        return
      }
      
      guard let args = call.arguments as? [String: Any],
            let useSpeaker = args["useSpeaker"] as? Bool else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Missing or invalid 'useSpeaker' argument",
          details: nil
        ))
        return
      }
      
      do {
        let session = AVAudioSession.sharedInstance()
        if useSpeaker {
          try session.overrideOutputAudioPort(.speaker)
          #if DEBUG
          print("[AppDelegate] Overrode output port to speaker")
          #endif
        } else {
          try session.overrideOutputAudioPort(.none)
          #if DEBUG
          print("[AppDelegate] Reset output port override (using default routing)")
          #endif
        }
        result(true)
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
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
