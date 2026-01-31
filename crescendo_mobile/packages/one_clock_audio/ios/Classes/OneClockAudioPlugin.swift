import Flutter
import AVFoundation
import CoreMedia

public class OneClockAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let methodChannelName = "one_clock_audio/methods"
  private static let eventChannelName  = "one_clock_audio/events"

  private var eventSink: FlutterEventSink?

  private let engine = AVAudioEngine()
  private let refPlayer = AVAudioPlayerNode()
  private let vocPlayer = AVAudioPlayerNode()

  private let sessionManager = OneClockSessionManager()

  private var inputFormat: AVAudioFormat?
  private var outputFormat: AVAudioFormat?
  private let format48Mono: AVAudioFormat

  private var refFile: AVAudioFile?
  private var vocFile: AVAudioFile?

  private var isEngineRunning = false
  private var isCapturing = false
  private var isPlaybackMode = false

  private var gain: Float = 1.0
  private var refGain: Float = 1.0
  private var vocGain: Float = 1.0
  private var vocOffsetFrames: Int = 0

  private var playbackStartSampleTime: Int64 = 0

  private let timebaseInfo: mach_timebase_info_data_t = {
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
    format48Mono = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    super.init()
    engine.attach(refPlayer)
    engine.attach(vocPlayer)
    let mainMixer = engine.mainMixerNode
    let format = mainMixer.outputFormat(forBus: 0)
    self.outputFormat = format
    engine.connect(refPlayer, to: mainMixer, format: format48Mono)
    engine.connect(vocPlayer, to: mainMixer, format: format48Mono)
  }

  // MARK: - FlutterStreamHandler
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
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

  private func currentOutputSampleTime() -> Int64? {
    guard let t = refPlayer.lastRenderTime,
          let p = refPlayer.playerTime(forNodeTime: t) else { return nil }
    return Int64(p.sampleTime)
  }

  private func monotonicNanos() -> Int64 {
    let t = mach_absolute_time()
    let nanos = (t * UInt64(timebaseInfo.numer)) / UInt64(timebaseInfo.denom)
    return Int64(nanos)
  }

  // MARK: - Duplex Record (start / stop)
  private func startDuplex(playbackPathOrAssetPath: String, sampleRate: Int, channels: Int, framesPerCallback: Int) throws {
    try ensureEngineRunning()
    print("[OneClockiOS] prepareForRecord …")

    refPlayer.volume = gain
    refPlayer.stop()

    if !playbackPathOrAssetPath.isEmpty {
      let url = URL(fileURLWithPath: playbackPathOrAssetPath)
      refFile = try AVAudioFile(forReading: url)
    } else {
      refFile = nil
    }

    sessionManager.beginSession(engineOutputSampleTime: currentOutputSampleTime() ?? 0)

    if let file = refFile {
      startRefPlayback(file: file, seekSeconds: 0.0)
    }
    playbackStartSampleTime = currentOutputSampleTime() ?? 0
    print("[OneClockiOS] Session Reset: ID=\(sessionManager.activeSessionId) StartFrame=\(playbackStartSampleTime)")

    try startCaptureTap(bufferSizeFrames: max(256, framesPerCallback))
  }

  private func stopDuplex() {
    print("[OneClockiOS] stop: tearing down tap and nodes")
    stopCaptureTap()
    refPlayer.stop()
    if isPlaybackMode {
      vocPlayer.stop()
      isPlaybackMode = false
    }
    engine.stop()
    isEngineRunning = false
  }

  private func startRefPlayback(file: AVAudioFile, seekSeconds: Double) {
    let sr = file.processingFormat.sampleRate
    let seekFrame = AVAudioFramePosition(seekSeconds * sr)
    let maxFrames = file.length - seekFrame
    if maxFrames <= 0 { return }
    refPlayer.stop()
    refPlayer.scheduleSegment(file, startingFrame: seekFrame, frameCount: AVAudioFrameCount(maxFrames), at: nil, completionHandler: nil)
    refPlayer.play()
  }

  // MARK: - Capture tap (session-gated, outputFramePosRel)
  private func startCaptureTap(bufferSizeFrames: Int) throws {
    guard let format = inputFormat else {
      throw NSError(domain: "one_clock_audio", code: -1, userInfo: [NSLocalizedDescriptionKey: "No input format"])
    }
    engine.inputNode.removeTap(onBus: 0)

    let activeSessionId = sessionManager.activeSessionId
    let sessionStartOutputSampleTime = playbackStartSampleTime

    isCapturing = true
    let desiredBufferSize = AVAudioFrameCount(bufferSizeFrames)

    engine.inputNode.installTap(onBus: 0, bufferSize: desiredBufferSize, format: format) { [weak self] buffer, time in
      guard let self = self else { return }
      guard self.isCapturing else { return }
      guard let sink = self.eventSink else { return }

      let sid = self.sessionManager.activeSessionId
      if sid != activeSessionId {
        print("[OneClockiOS] DROP stale capture: sessionId=\(activeSessionId) active=\(sid)")
        return
      }

      let (pcmBytes, frames) = self.convertToPCM16Mono(buffer: buffer)
      if frames <= 0 { return }

      let captureSampleTime = Int64(time.sampleTime)
      let outputFramePosRel = max(0, captureSampleTime - sessionStartOutputSampleTime)
      self.sessionManager.maybeSetFirstCapture(outputFrameRel: outputFramePosRel, sessionId: sid)
      self.sessionManager.updateLastOutputFrame(currentOutputFrame())

      let outputPos = self.currentOutputSampleTime() ?? 0
      let tsNanos = self.monotonicNanos()
      let sr = Int(self.engine.mainMixerNode.outputFormat(forBus: 0).sampleRate)

      sink([
        "pcm16": FlutterStandardTypedData(bytes: pcmBytes),
        "numFrames": frames,
        "sampleRate": sr,
        "channels": 1,
        "inputFramePos": captureSampleTime,
        "outputFramePos": outputPos,
        "timestampNanos": tsNanos,
        "outputFramePosRel": outputFramePosRel,
        "sessionId": sid
      ])
    }
  }

  private func currentOutputFrame() -> Int64 {
    currentOutputSampleTime() ?? 0
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

  // MARK: - Two-track playback (loadReference, loadVocal, setVocalOffset, setTrackGains, startPlaybackTwoTrack)
  private func loadReference(path: String) -> Bool {
    guard path.isEmpty == false else { refFile = nil; return true }
    do {
      let url = URL(fileURLWithPath: path)
      refFile = try AVAudioFile(forReading: url)
      return true
    } catch {
      print("[OneClockiOS] loadReference failed: \(path) \(error)")
      return false
    }
  }

  private func loadVocal(path: String) -> Bool {
    guard path.isEmpty == false else { vocFile = nil; return true }
    do {
      let url = URL(fileURLWithPath: path)
      vocFile = try AVAudioFile(forReading: url)
      return true
    } catch {
      print("[OneClockiOS] loadVocal failed: \(path) \(error)")
      return false
    }
  }

  private func setVocalOffset(frames: Int) {
    vocOffsetFrames = frames
    print("[OneClockiOS] nativeSetVocalOffset: frames=\(frames)")
  }

  private func setTrackGains(ref: Float, voc: Float) {
    refGain = ref
    vocGain = voc
    refPlayer.volume = ref
    vocPlayer.volume = voc
    print("[OneClockiOS] nativeSetTrackGains: ref=\(ref) voc=\(voc)")
  }

  private func startPlaybackTwoTrack() -> Bool {
    guard let ref = refFile, let voc = vocFile else {
      print("[OneClockiOS] startPlaybackTwoTrack: ref or voc not loaded")
      return false
    }
    print("[OneClockiOS] prepareForReview …")
    do {
      try ensureEngineRunning()
    } catch {
      print("[OneClockiOS] ensureEngineRunning failed: \(error)")
      return false
    }

    refPlayer.stop()
    vocPlayer.stop()

    refPlayer.volume = refGain
    vocPlayer.volume = vocGain

    let sampleRate: Double = 48000
    guard let anchorTime = refPlayer.lastRenderTime else {
      refPlayer.play()
      vocPlayer.play()
      scheduleTwoTrack(ref: ref, voc: voc, anchorSampleTime: 0)
      isPlaybackMode = true
      return true
    }

    let safetyFrames: Int64 = 1024
    let anchorSample = refPlayer.playerTime(forNodeTime: anchorTime)?.sampleTime ?? 0
    let startSample = Int64(anchorSample) + safetyFrames

    scheduleTwoTrack(ref: ref, voc: voc, anchorSampleTime: startSample)
    refPlayer.play()
    vocPlayer.play()
    isPlaybackMode = true
    return true
  }

  private func scheduleTwoTrack(ref: AVAudioFile, voc: AVAudioFile, anchorSampleTime: Int64) {
    let rate = 48000.0
    // Apply vocal offset: positive = voc starts later; negative = ref starts later (same anchor).
    let refDelay = vocOffsetFrames < 0 ? -vocOffsetFrames : 0
    let vocDelay = vocOffsetFrames > 0 ? vocOffsetFrames : 0
    let refStartSample = anchorSampleTime + Int64(refDelay)
    let vocStartSample = anchorSampleTime + Int64(vocDelay)

    let refStartTime = AVAudioTime(sampleTime: AVAudioFramePosition(refStartSample), atRate: rate)
    let vocStartTime = AVAudioTime(sampleTime: AVAudioFramePosition(vocStartSample), atRate: rate)

    refPlayer.scheduleSegment(ref, startingFrame: 0, frameCount: AVAudioFrameCount(ref.length), at: refStartTime, completionHandler: nil)
    vocPlayer.scheduleSegment(voc, startingFrame: 0, frameCount: AVAudioFrameCount(voc.length), at: vocStartTime, completionHandler: nil)
  }

  private func setUnifiedGain(_ g: Float) {
    gain = g
    refPlayer.volume = g
  }

  // MARK: - getSessionSnapshot (match Android list format for Dart NativeSessionSnapshot.fromList)
  private func getSessionSnapshot() -> [Int] {
    sessionManager.snapshotList()
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
        try startDuplex(playbackPathOrAssetPath: playback, sampleRate: sr, channels: ch, framesPerCallback: fpc)
        result(true)

      case "stop":
        stopDuplex()
        result(true)

      case "setGain":
        let g = (call.arguments as? [String: Any])?["gain"] as? Double ?? 1.0
        setUnifiedGain(Float(g))
        result(true)

      case "loadReference":
        let path = (call.arguments as? [String: Any])?["path"] as? String ?? ""
        result(loadReference(path: path))

      case "loadVocal":
        let path = (call.arguments as? [String: Any])?["path"] as? String ?? ""
        result(loadVocal(path: path))

      case "setVocalOffset":
        let frames = (call.arguments as? [String: Any])?["frames"] as? Int ?? 0
        setVocalOffset(frames: frames)
        result(true)

      case "setTrackGains":
        let ref = Float((call.arguments as? [String: Any])?["ref"] as? Double ?? 1.0)
        let voc = Float((call.arguments as? [String: Any])?["voc"] as? Double ?? 1.0)
        setTrackGains(ref: ref, voc: voc)
        result(true)

      case "startPlaybackTwoTrack":
        result(startPlaybackTwoTrack())

      case "getSessionSnapshot":
        result(getSessionSnapshot())

      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "native_error", message: "\(error)", details: nil))
    }
  }
}
