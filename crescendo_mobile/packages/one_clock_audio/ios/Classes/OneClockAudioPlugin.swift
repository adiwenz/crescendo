import Flutter
import AVFoundation
import CoreMedia

public class OneClockAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "one_clock_audio/methods"
  private static let eventChannelName  = "one_clock_audio/events"

  private var eventSink: FlutterEventSink?

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()

  private var inputFormat: AVAudioFormat?
  private var outputFormat: AVAudioFormat?

  private var playbackFile: AVAudioFile?

  private var isEngineRunning = false
  private var isCapturing = false
  private var gain: Float = 1.0

  private var recordStartSampleTime: Int64? = nil
  private var playbackStartSampleTime: Int64? = nil

  private var timebaseInfo: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
  }()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methods = FlutterMethodChannel(name: methodChannelName, binaryMessenger: registrar.messenger())
    let events  = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())

    let instance = OneClockAudioPlugin()
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  public override init() {
    super.init()

    engine.attach(player)

    let mainMixer = engine.mainMixerNode
    let hwFormat = mainMixer.outputFormat(forBus: 0)
    self.outputFormat = hwFormat

    engine.connect(player, to: mainMixer, format: hwFormat)
  }

  // MARK: - FlutterStreamHandler
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - Session / Engine
  private func ensureSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
    try session.setPreferredSampleRate(48000)
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
    return nil
  }

  private func monotonicNanos() -> Int64 {
    let t = mach_absolute_time()
    let nanos = (t * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
    return Int64(nanos)
  }

  // MARK: - Unified API
  private func startUnified(playbackPathOrAssetPath: String, sampleRate: Int, channels: Int, framesPerCallback: Int) throws {
    try ensureEngineRunning()

    if !playbackPathOrAssetPath.isEmpty {
      let url = URL(fileURLWithPath: playbackPathOrAssetPath)
      self.playbackFile = try AVAudioFile(forReading: url)
    } else {
      self.playbackFile = nil
    }

    player.volume = gain

    recordStartSampleTime = nil
    playbackStartSampleTime = nil

    try startCaptureTap(bufferSizeFrames: max(256, framesPerCallback))

    if let file = playbackFile {
      startPlayback(file: file, seekSeconds: 0.0)
    }
  }

  private func stopUnified() {
    stopCaptureTap()
    player.stop()
    engine.stop()
    isEngineRunning = false
  }

  private func setUnifiedGain(_ g: Float) {
    gain = g
    player.volume = g
  }

  // MARK: - Playback
  private func startPlayback(file: AVAudioFile, seekSeconds: Double) {
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

  // MARK: - Capture tap
  private func startCaptureTap(bufferSizeFrames: Int) throws {
    guard let format = inputFormat else {
      throw NSError(domain: "one_clock_audio", code: -1, userInfo: [NSLocalizedDescriptionKey: "No input format"])
    }

    engine.inputNode.removeTap(onBus: 0)

    recordStartSampleTime = currentEngineSampleTime()
    if recordStartSampleTime == nil {
      recordStartSampleTime = currentEngineSampleTime()
    }

    let desiredBufferSize = AVAudioFrameCount(bufferSizeFrames)
    isCapturing = true

    engine.inputNode.installTap(onBus: 0, bufferSize: desiredBufferSize, format: format) { [weak self] buffer, time in
      guard let self = self else { return }
      guard self.isCapturing else { return }
      guard let sink = self.eventSink else { return }

      let (pcmBytes, frames) = self.convertToPCM16Mono(buffer: buffer)
      if frames <= 0 { return }

      let outputPos = self.currentEngineSampleTime() ?? 0
      let inputPos: Int64 = {
        let st = time.sampleTime
        if st >= 0 { return Int64(st) }
        return outputPos
      }()

      let tsNanos = self.monotonicNanos()
      let sr = Int(self.engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)

      sink([
        "pcm16": FlutterStandardTypedData(bytes: pcmBytes),
        "numFrames": frames,
        "sampleRate": sr,
        "channels": 1,
        "inputFramePos": inputPos,
        "outputFramePos": outputPos,
        "timestampNanos": tsNanos
      ])
    }
  }

  private func stopCaptureTap() {
    if isCapturing {
      engine.inputNode.removeTap(onBus: 0)
      isCapturing = false
    }
  }

  private func convertToPCM16Mono(buffer: AVAudioPCMBuffer) -> (Data, Int) {
    let frameCount = Int(buffer.frameLength)
    if frameCount <= 0 { return (Data(), 0) }

    if let floatData = buffer.floatChannelData {
      let chCount = Int(buffer.format.channelCount)
      if chCount <= 0 { return (Data(), 0) }

      var out = Data(count: frameCount * 2)
      out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
        let dst = raw.bindMemory(to: Int16.self)
        for i in 0..<frameCount {
          var sum: Float = 0
          for c in 0..<chCount { sum += floatData[c][i] }
          let mono = sum / Float(chCount)
          let clamped = max(-1.0, min(1.0, mono))
          dst[i] = Int16((clamped * 32767.0).rounded())
        }
      }
      return (out, frameCount)
    }

    if let int16Data = buffer.int16ChannelData {
      let chCount = Int(buffer.format.channelCount)
      if chCount <= 0 { return (Data(), 0) }

      var out = Data(count: frameCount * 2)
      out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
        let dst = raw.bindMemory(to: Int16.self)
        for i in 0..<frameCount {
          var acc: Int32 = 0
          for c in 0..<chCount { acc += Int32(int16Data[c][i]) }
          let mono = acc / Int32(chCount)
          let clamped = max(Int32(Int16.min), min(Int32(Int16.max), mono))
          dst[i] = Int16(clamped)
        }
      }
      return (out, frameCount)
    }

    return (Data(), 0)
  }

  // MARK: - Flutter method handler
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "start":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Missing args", details: nil))
          return
        }
        let playback = (args["playback"] as? String) ?? ""
        let sr = (args["sampleRate"] as? Int) ?? 48000
        let ch = (args["channels"] as? Int) ?? 1
        let fpc = (args["framesPerCallback"] as? Int) ?? 192

        try startUnified(playbackPathOrAssetPath: playback, sampleRate: sr, channels: ch, framesPerCallback: fpc)
        result(true)

      case "stop":
        stopUnified()
        result(true)

      case "setGain":
        let gain = (call.arguments as? [String: Any])?["gain"] as? Double ?? 1.0
        setUnifiedGain(Float(gain))
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "native_error", message: "\(error)", details: nil))
    }
  }
}
