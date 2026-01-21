import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var audioSessionChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Setup method channel for audio session configuration
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    audioSessionChannel = FlutterMethodChannel(
      name: "com.adriannawenz.crescendo/audioSession",
      binaryMessenger: controller.binaryMessenger
    )
    
    audioSessionChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate not available", details: nil))
        return
      }
      
      switch call.method {
      case "ensureReviewAudioSession":
        let tag = (call.arguments as? [String: Any])?["tag"] as? String ?? "unknown"
        let configResult = AudioSessionConfigurator.shared.ensureReviewAudioSession(tag: tag)
        result(configResult)
        
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
