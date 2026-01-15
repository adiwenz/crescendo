import Foundation
import AVFoundation
import AudioToolbox
import Flutter

@objc class MidiWavRenderer: NSObject, FlutterPlugin {
    // Store active engine/sequencer for real-time playback
    private var activeEngine: AVAudioEngine?
    private var activeSequencer: AVAudioSequencer?
    private var activeSampler: AVAudioUnitSampler?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.crescendo.midi_renderer", binaryMessenger: registrar.messenger())
        let instance = MidiWavRenderer()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "playMidiRealtime":
            guard let args = call.arguments as? [String: Any],
                  let midiBytes = args["midiBytes"] as? FlutterStandardTypedData,
                  let soundFontPath = args["soundFontPath"] as? String,
                  let leadInSeconds = args["leadInSeconds"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing required arguments", details: nil))
                return
            }
            
            DispatchQueue.main.async {
                do {
                    try self.playMidiRealtime(
                        midiBytes: midiBytes.data,
                        soundFontPath: soundFontPath,
                        leadInSeconds: leadInSeconds
                    )
                    result(true)
                } catch {
                    let errorMsg = "MIDI realtime playback failed: \(error.localizedDescription)"
                    print("[MidiWavRenderer] \(errorMsg)")
                    result(FlutterError(code: "PLAYBACK_ERROR", message: errorMsg, details: nil))
                }
            }
        case "stopMidiRealtime":
            stopMidiRealtime()
            result(true)
        case "renderMidiToWav":
            guard let args = call.arguments as? [String: Any],
                  let midiBytes = args["midiBytes"] as? FlutterStandardTypedData,
                  let soundFontPath = args["soundFontPath"] as? String,
                  let outputPath = args["outputPath"] as? String,
                  let sampleRate = args["sampleRate"] as? Int,
                  let numChannels = args["numChannels"] as? Int,
                  let leadInSeconds = args["leadInSeconds"] as? Double else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing required arguments", details: nil))
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let renderedPath = try self.renderMidiToWav(
                        midiBytes: midiBytes.data,
                        soundFontPath: soundFontPath,
                        outputPath: outputPath,
                        sampleRate: sampleRate,
                        numChannels: numChannels,
                        leadInSeconds: leadInSeconds
                    )
                    DispatchQueue.main.async {
                        result(renderedPath)
                    }
                } catch {
                    DispatchQueue.main.async {
                        let errorMsg = "MIDI render failed: \(error.localizedDescription)"
                        print("[MidiWavRenderer] \(errorMsg)")
                        result(FlutterError(code: "RENDER_ERROR", message: errorMsg, details: nil))
                    }
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func renderMidiToWav(
        midiBytes: Data,
        soundFontPath: String,
        outputPath: String,
        sampleRate: Int,
        numChannels: Int,
        leadInSeconds: Double
    ) throws -> String {
        // Check if running on simulator (manual rendering may have issues)
        #if targetEnvironment(simulator)
        print("[MidiWavRenderer] ⚠️ Running on simulator - manual rendering may have limitations")
        #endif
        
        // Configure AVAudioSession for offline rendering (CRITICAL for error -80801)
        let session = AVAudioSession.sharedInstance()
        do {
            // CRITICAL: Use .playback category with .mixWithOthers option for offline rendering
            // This prevents conflicts with other audio sessions
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setPreferredSampleRate(Double(sampleRate))
            // Don't set buffer duration - let the system choose
            try session.setActive(true, options: [])
            print("[MidiWavRenderer] ✅ Audio session configured: category=playback, sampleRate=\(sampleRate), options=mixWithOthers")
        } catch {
            print("[MidiWavRenderer] ⚠️ Audio session setup warning: \(error.localizedDescription)")
            // Try to continue with current session state
            do {
                try session.setActive(true, options: [])
            } catch {
                print("[MidiWavRenderer] ⚠️ Failed to activate session: \(error.localizedDescription)")
            }
        }
        
        // Create a dedicated audio engine for offline rendering (do NOT reuse shared engine)
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        
        // Try multiple format configurations if the first one fails
        var renderFormat: AVAudioFormat?
        let formatAttempts: [(sampleRate: Double, channels: AVAudioChannelCount)] = [
            (Double(sampleRate), AVAudioChannelCount(numChannels)), // Requested format
            (44100.0, 2), // Common fallback: 44.1kHz stereo
            (48000.0, 2), // Alternative: 48kHz stereo
            (44100.0, 1), // Last resort: 44.1kHz mono
        ]
        
        var selectedFormat: AVAudioFormat?
        var selectedSampleRate: Double = Double(sampleRate)
        var selectedChannels: AVAudioChannelCount = AVAudioChannelCount(numChannels)
        
        for attempt in formatAttempts {
            if let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: attempt.sampleRate,
                channels: attempt.channels,
                interleaved: false
            ) {
                selectedFormat = format
                selectedSampleRate = attempt.sampleRate
                selectedChannels = attempt.channels
                print("[MidiWavRenderer] Attempting format: \(attempt.sampleRate)Hz, \(attempt.channels)ch")
                break
            }
        }
        
        guard let finalRenderFormat = selectedFormat else {
            throw NSError(domain: "MidiWavRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create any render format"])
        }
        
        renderFormat = finalRenderFormat
        print("[MidiWavRenderer] Using format: \(selectedSampleRate)Hz, \(selectedChannels)ch")
        
        // Connect sampler to main mixer with render format
        let mainMixer = engine.mainMixerNode
        engine.connect(sampler, to: mainMixer, format: finalRenderFormat)
        
        // Set mixer output volume to avoid clipping
        mainMixer.outputVolume = 0.8
        
        // Load SoundFont
        let soundFontURL: URL
        if soundFontPath.hasPrefix("/") {
            soundFontURL = URL(fileURLWithPath: soundFontPath)
        } else {
            // Try to find in bundle
            if let bundleURL = Bundle.main.url(forResource: (soundFontPath as NSString).deletingPathExtension, withExtension: "sf2") {
                soundFontURL = bundleURL
            } else if let bundleURL = Bundle.main.url(forResource: soundFontPath, withExtension: nil) {
                soundFontURL = bundleURL
            } else {
                throw NSError(domain: "MidiWavRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "SoundFont not found: \(soundFontPath)"])
            }
        }
        
        guard FileManager.default.fileExists(atPath: soundFontURL.path) else {
            throw NSError(domain: "MidiWavRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "SoundFont file does not exist: \(soundFontURL.path)"])
        }
        
        // Load SoundFont into sampler
        do {
            try sampler.loadSoundBankInstrument(at: soundFontURL, program: 0, bankMSB: 0x79, bankLSB: 0)
        } catch {
            // Try alternative bank
            try sampler.loadSoundBankInstrument(at: soundFontURL, program: 0, bankMSB: 0, bankLSB: 0)
        }
        
        // Create sequencer with engine
        let sequencer = AVAudioSequencer(audioEngine: engine)
        
        // Write MIDI bytes to temporary file
        let midiFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        try midiBytes.write(to: midiFileURL)
        defer {
            try? FileManager.default.removeItem(at: midiFileURL)
        }
        
        // Load MIDI file into sequencer
        try sequencer.load(from: midiFileURL, options: [])
        
        // Route MIDI tracks to sampler
        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }
        
        // Calculate total duration from MIDI tracks
        // Find the maximum length across all tracks using lengthInBeats
        var maxLengthInBeats: Double = 0.0
        for track in sequencer.tracks {
            maxLengthInBeats = max(maxLengthInBeats, track.lengthInBeats)
        }
        
        // Convert beats to seconds using default tempo (120 BPM = 2 beats per second)
        // If MIDI file has tempo events, sequencer will use those, but for calculation we use default
        let defaultTempoBpm: Double = 120.0
        let beatsPerSecond = defaultTempoBpm / 60.0
        let sequencerDurationSeconds = maxLengthInBeats / beatsPerSecond
        
        // If no tracks or zero length, use a default duration (5 seconds)
        let midiDurationSeconds = sequencerDurationSeconds > 0 ? sequencerDurationSeconds : 5.0
        let totalDurationSeconds = leadInSeconds + midiDurationSeconds
        // Use selectedSampleRate for frame calculation
        let targetTotalFrames = AVAudioFramePosition(totalDurationSeconds * selectedSampleRate)
        
        print("[MidiWavRenderer] Rendering: leadIn=\(leadInSeconds)s, MIDI=\(midiDurationSeconds)s (maxBeats=\(maxLengthInBeats)), total=\(totalDurationSeconds)s, frames=\(targetTotalFrames)")
        
        // CRITICAL: Enable manual rendering mode BEFORE preparing/starting engine
        // This is the correct order to avoid error -80801
        let maxFrames: AVAudioFrameCount = 4096
        do {
            try engine.enableManualRenderingMode(.offline, format: finalRenderFormat, maximumFrameCount: maxFrames)
            print("[MidiWavRenderer] ✅ Manual rendering mode enabled successfully")
        } catch let error as NSError {
            let errorDetails = "Failed to enable manual rendering: \(error.localizedDescription) (code: \(error.code), domain: \(error.domain)). Format: \(selectedSampleRate)Hz, \(selectedChannels)ch. Session category: \(session.category.rawValue)"
            print("[MidiWavRenderer] ❌ \(errorDetails)")
            #if targetEnvironment(simulator)
            throw NSError(domain: "MidiWavRenderer", code: 100, userInfo: [NSLocalizedDescriptionKey: "Manual rendering not supported on simulator. Please test on a real device. \(errorDetails)"])
            #else
            throw NSError(domain: "MidiWavRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: errorDetails])
            #endif
        }
        
        // Prepare engine (after enabling manual rendering)
        engine.prepare()
        
        // Start engine
        do {
            try engine.start()
            print("[MidiWavRenderer] ✅ Engine started successfully")
        } catch {
            let errorDetails = "Failed to start engine: \(error.localizedDescription)"
            print("[MidiWavRenderer] ❌ \(errorDetails)")
            throw NSError(domain: "MidiWavRenderer", code: 4, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }
        
        // Create output file with proper settings
        // Use the manual rendering format settings (Float32, non-interleaved)
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: engine.manualRenderingFormat.settings)
        
        // Add lead-in silence if needed
        if leadInSeconds > 0 {
            let leadInFrames = AVAudioFrameCount(leadInSeconds * selectedSampleRate)
            let silenceBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: leadInFrames)!
            silenceBuffer.frameLength = leadInFrames
            // Buffer is already zero-filled
            try outputFile.write(from: silenceBuffer)
        }
        
        // Prepare sequencer
        sequencer.prepareToPlay()
        
        // Start sequencer
        try sequencer.start()
        
        // Manual offline rendering loop
        var totalFramesRendered: AVAudioFramePosition = 0
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: maxFrames)!
        
        // Safety: maximum render duration (5 minutes)
        let maxRenderFrames = AVAudioFramePosition(300.0 * selectedSampleRate)
        let actualTargetFrames = min(targetTotalFrames, maxRenderFrames)
        
        while totalFramesRendered < actualTargetFrames {
            // Calculate frames to render in this iteration
            let remainingFrames = actualTargetFrames - totalFramesRendered
            let framesToRender = min(maxFrames, AVAudioFrameCount(remainingFrames))
            buffer.frameLength = framesToRender
            
            // Render offline
            let status = try engine.renderOffline(framesToRender, to: buffer)
            
            switch status {
            case .success:
                // Write rendered buffer to file
                try outputFile.write(from: buffer)
                totalFramesRendered += AVAudioFramePosition(framesToRender)
                
            case .insufficientDataFromInputNode:
                // Render silence (sequencer may have finished)
                if let floatChannelData = buffer.floatChannelData {
                    let channelCount = Int(engine.manualRenderingFormat.channelCount)
                    for channel in 0..<channelCount {
                        let dest = floatChannelData[channel]
                        for frame in 0..<Int(framesToRender) {
                            dest[frame] = 0.0
                        }
                    }
                }
                try outputFile.write(from: buffer)
                totalFramesRendered += AVAudioFramePosition(framesToRender)
                
                // Check if sequencer is done
                if !sequencer.isPlaying {
                    // Render a few more frames for tail/reverb
                    let tailFrames = min(AVAudioFrameCount(0.5 * selectedSampleRate), maxFrames) // 0.5s tail
                    buffer.frameLength = tailFrames
                    if let floatChannelData = buffer.floatChannelData {
                        let channelCount = Int(engine.manualRenderingFormat.channelCount)
                        for channel in 0..<channelCount {
                            let dest = floatChannelData[channel]
                            for frame in 0..<Int(tailFrames) {
                                dest[frame] = 0.0
                            }
                        }
                    }
                    try outputFile.write(from: buffer)
                    break
                }
                
            case .cannotDoInCurrentContext:
                // Continue to next iteration
                continue
                
            case .error:
                throw NSError(domain: "MidiWavRenderer", code: 5, userInfo: [NSLocalizedDescriptionKey: "Engine render error"])
            @unknown default:
                throw NSError(domain: "MidiWavRenderer", code: 6, userInfo: [NSLocalizedDescriptionKey: "Unknown render status"])
            }
        }
        
        // Stop and cleanup
        sequencer.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        
        // Optionally deactivate audio session (but not required)
        // try? session.setActive(false, options: [])
        
        print("[MidiWavRenderer] ✅ Successfully rendered \(totalFramesRendered) frames (\(String(format: "%.2f", Double(totalFramesRendered) / selectedSampleRate))s) to \(outputPath)")
        
        return outputPath
    }
    
    // MARK: - Real-time MIDI Playback
    
    private func playMidiRealtime(
        midiBytes: Data,
        soundFontPath: String,
        leadInSeconds: Double
    ) throws {
        // Stop any existing playback
        stopMidiRealtime()
        
        // Configure AVAudioSession for playback
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            print("[MidiWavRenderer] ✅ Audio session configured for realtime playback")
        } catch {
            print("[MidiWavRenderer] ⚠️ Audio session setup warning: \(error.localizedDescription)")
            // Continue anyway
        }
        
        // Create a dedicated audio engine for real-time playback
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        
        // Connect sampler to main mixer (use engine's default format)
        let mainMixer = engine.mainMixerNode
        engine.connect(sampler, to: mainMixer, format: nil) // nil = use node's output format
        
        // Set mixer output volume to avoid clipping
        mainMixer.outputVolume = 0.8
        
        // Load SoundFont
        let soundFontURL: URL
        if soundFontPath.hasPrefix("/") {
            soundFontURL = URL(fileURLWithPath: soundFontPath)
        } else {
            if let bundleURL = Bundle.main.url(forResource: (soundFontPath as NSString).deletingPathExtension, withExtension: "sf2") {
                soundFontURL = bundleURL
            } else if let bundleURL = Bundle.main.url(forResource: soundFontPath, withExtension: nil) {
                soundFontURL = bundleURL
            } else {
                throw NSError(domain: "MidiWavRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "SoundFont not found: \(soundFontPath)"])
            }
        }
        
        guard FileManager.default.fileExists(atPath: soundFontURL.path) else {
            throw NSError(domain: "MidiWavRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "SoundFont file does not exist: \(soundFontURL.path)"])
        }
        
        // Load SoundFont into sampler
        do {
            try sampler.loadSoundBankInstrument(at: soundFontURL, program: 0, bankMSB: 0x79, bankLSB: 0)
        } catch {
            // Try alternative bank
            try sampler.loadSoundBankInstrument(at: soundFontURL, program: 0, bankMSB: 0, bankLSB: 0)
        }
        
        // Create sequencer with engine
        let sequencer = AVAudioSequencer(audioEngine: engine)
        
        // Write MIDI bytes to temporary file
        let midiFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mid")
        try midiBytes.write(to: midiFileURL)
        
        // Load MIDI file into sequencer
        try sequencer.load(from: midiFileURL, options: [])
        
        // Route MIDI tracks to sampler
        for track in sequencer.tracks {
            track.destinationAudioUnit = sampler
        }
        
        // Prepare and start engine
        engine.prepare()
        try engine.start()
        
        // Store references for cleanup
        activeEngine = engine
        activeSequencer = sequencer
        activeSampler = sampler
        
        // Start sequencer after lead-in delay
        if leadInSeconds > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + leadInSeconds) {
                do {
                    self.activeSequencer?.prepareToPlay()
                    try self.activeSequencer?.start()
                    print("[MidiWavRenderer] ✅ MIDI sequencer started after \(leadInSeconds)s lead-in")
                } catch {
                    print("[MidiWavRenderer] ❌ Failed to start sequencer: \(error.localizedDescription)")
                }
            }
        } else {
            sequencer.prepareToPlay()
            try sequencer.start()
            print("[MidiWavRenderer] ✅ MIDI sequencer started immediately")
        }
        
        // Clean up MIDI file after a delay (sequencer has loaded it)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            try? FileManager.default.removeItem(at: midiFileURL)
        }
        
        print("[MidiWavRenderer] ✅ Real-time MIDI playback initialized")
    }
    
    private func stopMidiRealtime() {
        if let sequencer = activeSequencer {
            sequencer.stop()
            activeSequencer = nil
        }
        if let engine = activeEngine {
            engine.stop()
            activeEngine = nil
        }
        activeSampler = nil
        print("[MidiWavRenderer] ✅ Real-time MIDI playback stopped")
    }
}
