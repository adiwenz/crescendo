import Flutter
import AVFoundation

public class SwiftTransportClockPlugin: NSObject, FlutterPlugin {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()

  private var inputFormat: AVAudioFormat?
  private var outputFormat: AVAudioFormat?

  private var audioFile: AVAudioFile?
  private var recordingURL: URL?

  // Transport anchors
  private var recordStartSampleTime: Int64? = nil
  private var playbackStartSampleTime: Int64? = nil

  private var isEngineRunning = false
  private var isRecording = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "transport_clock", binaryMessenger: registrar.messenger())
    let instance = SwiftTransportClockPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public override init() {
    super.init()

    // Attach nodes
    engine.attach(player)

    // Route player -> mainMixer
    let mainMixer = engine.mainMixerNode
    let hwFormat = mainMixer.outputFormat(forBus: 0)
    self.outputFormat = hwFormat

    engine.connect(player, to: mainMixer, format: hwFormat)
  }

  private func ensureSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setPreferredSampleRate(48000) // optional; remove if you want system default
    try session.setActive(true, options: [])
  }

  private func ensureEngineRunning() throws {
    if isEngineRunning { return }
    try ensureSession()

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    self.inputFormat = format

    engine.prepare()
    try engine.start()
    isEngineRunning = true
  }

  private func currentEngineSampleTime() -> Int64? {
    if let t = player.lastRenderTime,
       let p = player.playerTime(forNodeTime: t) {
      return Int64(p.sampleTime)
    }

    let mixer = engine.mainMixerNode
    if let t = mixer.lastRenderTime {
      return Int64(t.sampleTime)
    }

    return nil
  }

  private func startPlayback(fromPath path: String, seekSeconds: Double) throws {
    try ensureEngineRunning()

    let url = URL(fileURLWithPath: path)
    let file = try AVAudioFile(forReading: url)
    let sr = file.processingFormat.sampleRate

    let seekFrame = AVAudioFramePosition(seekSeconds * sr)
    let maxFrames = file.length - seekFrame
    if maxFrames <= 0 { return }

    player.stop()

    playbackStartSampleTime = currentEngineSampleTime()

    player.scheduleSegment(
      file,
      startingFrame: seekFrame,
      frameCount: AVAudioFrameCount(maxFrames),
      at: nil,
      completionHandler: nil
    )

    player.play()

    playbackStartSampleTime = currentEngineSampleTime()
  }

  private func startRecording(toDirectory dirPath: String?) throws -> String {
    try ensureEngineRunning()
    guard let format = inputFormat else {
      throw NSError(domain: "transport_clock", code: -1, userInfo: [NSLocalizedDescriptionKey: "No input format"])
    }

    let baseDir: URL
    if let dirPath = dirPath, !dirPath.isEmpty {
      baseDir = URL(fileURLWithPath: dirPath, isDirectory: true)
    } else {
      baseDir = FileManager.default.temporaryDirectory
    }

    let url = baseDir.appendingPathComponent("crescendo_recording_\(Int(Date().timeIntervalSince1970)).wav")
    recordingURL = url

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: format.sampleRate,
      AVNumberOfChannelsKey: format.channelCount,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false
    ]

    audioFile = try AVAudioFile(forWriting: url, settings: settings)

    engine.inputNode.removeTap(onBus: 0)

    recordStartSampleTime = currentEngineSampleTime()

    engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self = self else { return }
      do {
        try self.audioFile?.write(from: buffer)
      } catch {
        // swallow to avoid crashing realtime thread
      }
    }

    isRecording = true

    if recordStartSampleTime == nil {
      recordStartSampleTime = currentEngineSampleTime()
    }

    return url.path
  }

  private func stopRecording() {
    if isRecording {
      engine.inputNode.removeTap(onBus: 0)
      audioFile = nil
      isRecording = false
    }
  }

  private func stopAll() {
    stopRecording()
    player.stop()
    engine.stop()
    isEngineRunning = false
  }

  // MARK: - Mixing Logic

  private func readInt16PCM(from file: AVAudioFile) throws -> ([Int16], Double) {
    let format = file.processingFormat
    let capacity = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
       throw NSError(domain: "transport_clock", code: -2, userInfo: [NSLocalizedDescriptionKey: "Buffer alloc failed"])
    }
    try file.read(into: buffer)
    
    // We assume the buffer is Float32 non-interleaved or similar from AVAudioFile defaults,
    // but requirements say "Read both WAVs as PCM" and "Assertion for simplicity: both WAVs are mono 16-bit PCM at same sample rate".
    // However, AVAudioFile.read usually gives us Float32 buffers unless we strictly open in a way that doesn't.
    // To be safe and sample-accurate for matching the prompt's request (assuming inputs are already simple),
    // let's try to convert whatever we got to [Int16].

    // The simplest robust way if we can't trust the input file format is to use an AudioConverter,
    // but the prompt prompt says "Assumption for simplicity: both WAVs are mono 16-bit PCM".
    // If they ARE 16-bit PCM, AVAudioFile might still read them into float buffers by default.
    // Let's assume we get float data in the buffer and convert to Int16 manually for mixing.
    
    guard let channelData = buffer.floatChannelData else {
         throw NSError(domain: "transport_clock", code: -3, userInfo: [NSLocalizedDescriptionKey: "No float channel data"])
    }
    
    let count = Int(buffer.frameLength)
    let channels = Int(format.channelCount)
    var samples = [Int16]()
    samples.reserveCapacity(count)
    
    // Mix down to mono by averaging if needed, or just take first channel
    // Prompt says: "if not, convert to mono (average channels)"
    
    let ptrs = UnsafeBufferPointer(start: channelData, count: channels)
    
    for i in 0..<count {
        var sum: Float = 0
        for ch in 0..<channels {
            sum += ptrs[ch][i]
        }
        let avg = sum / Float(channels)
        // Clip and convert
        let val = max(-1.0, min(1.0, avg))
        samples.append(Int16(val * 32767.0))
    }
    
    return (samples, format.sampleRate)
  }

  private func writeInt16PCM(samples: [Int16], sampleRate: Double, to path: String) throws -> String {
      let url = URL(fileURLWithPath: path)
      let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
      ]
      
      let file = try AVAudioFile(forWriting: url, settings: settings)
      // processingFormat is often Float32 even if file is Int16
      let format = file.processingFormat
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
      buffer.frameLength = AVAudioFrameCount(samples.count)
      
      // If we got an int16 buffer directly (unlikely)
      if let channelData = buffer.int16ChannelData {
          let ptr = channelData[0]
          samples.withUnsafeBufferPointer { srcPtr in
             ptr.update(from: srcPtr.baseAddress!, count: samples.count)
          }
      } 
      // Most likely: we got a float buffer. Convert Int16 -> Float (-1.0 to 1.0)
      else if let channelData = buffer.floatChannelData {
          let ptr = channelData[0]
          // Normalize 32767 -> 1.0
          let norm = 1.0 / 32768.0 
          for i in 0..<samples.count {
              ptr[i] = Float(samples[i]) * Float(norm)
          }
      }
      else {
           throw NSError(domain: "transport_clock", code: -4, userInfo: [NSLocalizedDescriptionKey: "Could not get buffer channel data"])
      }
      
      try file.write(from: buffer)
      return path
  }

  private func mixWithOffset(
    referencePath: String,
    vocalPath: String,
    vocalOffsetSamples: Int64,
    outputPath: String
  ) throws -> String {
      let refURL = URL(fileURLWithPath: referencePath)
      let vocURL = URL(fileURLWithPath: vocalPath)
      
      let refFile = try AVAudioFile(forReading: refURL)
      let vocFile = try AVAudioFile(forReading: vocURL)
      
      let (refSamples, refSR) = try readInt16PCM(from: refFile)
      let (vocSamples, vocSR) = try readInt16PCM(from: vocFile)
      
      // Enforce same sample rate - small epsilon for float diffs
      if abs(refSR - vocSR) > 1.0 {
          throw NSError(domain: "transport_clock", code: -5, userInfo: [NSLocalizedDescriptionKey: "Sample rate mismatch: \(refSR) vs \(vocSR)"])
      }
      
      // Calculate output size
      // Reference is at 0
      // Vocal is at vocalOffsetSamples
      
      // We need a common timeline starting at min(0, vocalOffsetSamples)
      // but usually we just want the result to start at 0 (start of reference playback).
      // However, if vocal started BEFORE playback (negative offset? unlikely for this flow but possible if logic is weird),
      // we should handle it.
      // Prompt: "Place reference at t=0. Place vocal starting at vocalOffsetSamples. ... outputStart = min(0, vocalOffsetSamples)"
      
      let startSample = min(0, vocalOffsetSamples)
      let refEnd = Int64(refSamples.count)
      let vocEnd = vocalOffsetSamples + Int64(vocSamples.count)
      let endSample = max(refEnd, vocEnd)
      
      let totalLength = endSample - startSample
      var outSamples = [Int16](repeating: 0, count: Int(totalLength))
      
      // Helper to add
      func addToMix(source: [Int16], offsetFromStart: Int64) {
          let destStartIndex = Int(offsetFromStart - startSample)
          for i in 0..<source.count {
              let val = Int32(source[i])
              let existing = Int32(outSamples[destStartIndex + i])
              let sum = val + existing
              // Hard clip
              let clipped = max(-32768, min(32767, sum))
              outSamples[destStartIndex + i] = Int16(clipped)
          }
      }
      
      // Reference is at 0
      addToMix(source: refSamples, offsetFromStart: 0)
      
      // Vocal is at vocalOffsetSamples
      addToMix(source: vocSamples, offsetFromStart: vocalOffsetSamples)
      
      return try writeInt16PCM(samples: outSamples, sampleRate: refSR, to: outputPath)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {

      case "ensureStarted":
        try ensureEngineRunning()
        result(true)

      case "getSampleRate":
        try ensureEngineRunning()
        let sr = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        result(sr)

      case "getCurrentSampleTime":
        try ensureEngineRunning()
        result(currentEngineSampleTime())

      case "startPlayback":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "bad_args", message: "Missing path", details: nil))
          return
        }
        let seek = (args["seekSeconds"] as? Double) ?? 0.0
        try startPlayback(fromPath: path, seekSeconds: seek)
        result(true)

      case "startRecording":
        let args = call.arguments as? [String: Any]
        let dir = args?["dirPath"] as? String
        let outPath = try startRecording(toDirectory: dir)
        result(outPath)

      case "stopRecording":
        stopRecording()
        result(true)

      case "getRecordStartSampleTime":
        result(recordStartSampleTime)

      case "getPlaybackStartSampleTime":
        result(playbackStartSampleTime)

      case "stopAll":
        stopAll()
        result(true)

      case "mixWithOffset":
          guard let args = call.arguments as? [String: Any],
                let refPath = args["referencePath"] as? String,
                let vocPath = args["vocalPath"] as? String,
                let outPath = args["outputPath"] as? String,
                let offset = args["vocalOffsetSamples"] as? NSNumber else { // Int64 passes as NSNumber usually
              result(FlutterError(code: "bad_args", message: "Missing mixing paths or offset", details: nil))
              return
          }
          
          let offVal = offset.int64Value
          
          DispatchQueue.global(qos: .userInitiated).async {
              do {
                  let path = try self.mixWithOffset(referencePath: refPath, vocalPath: vocPath, vocalOffsetSamples: offVal, outputPath: outPath)
                  DispatchQueue.main.async {
                      result(path)
                  }
              } catch {
                  DispatchQueue.main.async {
                      result(FlutterError(code: "mix_error", message: "\(error)", details: nil))
                  }
              }
          }

      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "native_error", message: "\(error)", details: nil))
    }
  }
}
