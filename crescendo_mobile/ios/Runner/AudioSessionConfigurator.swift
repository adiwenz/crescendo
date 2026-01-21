import AVFoundation
import Flutter

/// Configures AVAudioSession for review/exercise playback with MIDI support
/// Ensures Bluetooth headphones and other routes work correctly
class AudioSessionConfigurator {
    static let shared = AudioSessionConfigurator()
    
    private let session = AVAudioSession.sharedInstance()
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var configChangeObserver: NSObjectProtocol?
    
    private init() {
        setupObservers()
    }
    
    /// Configure audio session for review playback (MIDI + recorded audio)
    /// Returns a map with session state for debugging
    func ensureReviewAudioSession(tag: String) -> [String: Any] {
        var result: [String: Any] = [:]
        
        do {
            // Get current route info before configuration
            let currentRoute = session.currentRoute
            let hasHeadphones = currentRoute.outputs.contains { output in
                output.portType == .headphones || 
                output.portType == .bluetoothA2DP || 
                output.portType == .bluetoothHFP ||
                output.portType == .bluetoothLE
            }
            
            // Build options: always include mixWithOthers and Bluetooth support
            var options: AVAudioSession.CategoryOptions = [
                .mixWithOthers,
                .allowBluetooth,
                .allowBluetoothA2DP
            ]
            
            // Only add defaultToSpeaker if NO headphones are connected
            if !hasHeadphones {
                options.insert(.defaultToSpeaker)
            }
            
            // Configure category, mode, and options
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: options
            )
            
            // Set preferred settings (optional, but helps with latency)
            try? session.setPreferredIOBufferDuration(0.005) // 5ms
            try? session.setPreferredSampleRate(48000)
            
            // Activate the session
            try session.setActive(true)
            
            // Get updated route info
            let updatedRoute = session.currentRoute
            var outputs: [[String: String]] = []
            for output in updatedRoute.outputs {
                outputs.append([
                    "portType": output.portType.rawValue,
                    "portName": output.portName
                ])
            }
            
            // Build result map
            result["category"] = session.category.rawValue
            result["mode"] = session.mode.rawValue
            result["options"] = options.rawValue
            result["outputs"] = outputs
            result["sampleRate"] = session.sampleRate
            result["ioBufferDuration"] = session.ioBufferDuration
            result["hasHeadphones"] = hasHeadphones
            result["engineRunning"] = false // Will be updated by caller if needed
            
            #if DEBUG
            print("[AudioSessionConfigurator] [\(tag)] Configured: category=\(session.category.rawValue), mode=\(session.mode.rawValue), options=\(options.rawValue)")
            print("[AudioSessionConfigurator] [\(tag)] Route: \(outputs.map { "\($0["portType"] ?? "unknown"):\($0["portName"] ?? "unknown")" }.joined(separator: ", "))")
            print("[AudioSessionConfigurator] [\(tag)] SampleRate=\(session.sampleRate), IOBufferDuration=\(session.ioBufferDuration)")
            #endif
            
        } catch {
            result["error"] = error.localizedDescription
            #if DEBUG
            print("[AudioSessionConfigurator] [\(tag)] ERROR configuring session: \(error)")
            #endif
        }
        
        return result
    }
    
    /// Setup observers for route changes, interruptions, and config changes
    private func setupObservers() {
        let notificationCenter = NotificationCenter.default
        
        // Route change observer
        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }
            
            #if DEBUG
            print("[AudioSessionConfigurator] Route changed: reason=\(reason.rawValue)")
            #endif
            
            // Reconfigure on route changes (headphones connect/disconnect)
            if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                _ = self.ensureReviewAudioSession(tag: "route_change")
            }
        }
        
        // Interruption observer
        interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            
            #if DEBUG
            print("[AudioSessionConfigurator] Interruption: type=\(type.rawValue)")
            #endif
            
            // Reconfigure when interruption ends
            if type == .ended {
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
                   AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                    _ = self.ensureReviewAudioSession(tag: "interruption_ended")
                }
            }
        }
    }
    
    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
