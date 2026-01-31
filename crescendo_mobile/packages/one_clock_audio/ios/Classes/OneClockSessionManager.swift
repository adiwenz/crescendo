import Foundation

/// Thread-safe session state for duplex record. Ensures capture events are gated by active session
/// and first-capture offset is set exactly once per session (matching Android behavior).
final class OneClockSessionManager {
  private let lock = NSLock()

  private(set) var activeSessionId: Int = 0
  private(set) var sessionStartSampleTime: Int64 = 0
  private(set) var firstCaptureOutputFrameRel: Int?
  private(set) var hasCapture: Bool = false
  private(set) var lastOutputFrame: Int64 = 0
  /// Computed offset for snapshot (firstCaptureOutputFrameRel or 0).
  var computedVocOffsetFrames: Int {
    firstCaptureOutputFrameRel ?? 0
  }

  /// Call at start of each record session. Increments activeSessionId and resets per-session fields.
  func beginSession(engineOutputSampleTime: Int64) {
    lock.lock()
    defer { lock.unlock() }
    activeSessionId += 1
    sessionStartSampleTime = engineOutputSampleTime
    firstCaptureOutputFrameRel = nil
    hasCapture = false
    lastOutputFrame = 0
    print("[OneClockiOS] Session Reset: ID=\(activeSessionId) StartFrame=\(sessionStartSampleTime)")
  }

  /// Only sets firstCaptureOutputFrameRel if sessionId matches active and it hasn't been set yet.
  /// Returns true if this capture was accepted as the first for this session.
  @discardableResult
  func maybeSetFirstCapture(outputFrameRel: Int64, sessionId: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard sessionId == activeSessionId else { return false }
    guard firstCaptureOutputFrameRel == nil else { return false }
    firstCaptureOutputFrameRel = Int(outputFrameRel)
    hasCapture = true
    let base = sessionStartSampleTime + outputFrameRel
    print("[OneClockiOS] First Capture: Base=\(base), StartFrame=\(sessionStartSampleTime), Diff=\(outputFrameRel) (SessionID=\(sessionId))")
    return true
  }

  func updateLastOutputFrame(_ frame: Int64) {
    lock.lock()
    defer { lock.unlock() }
    lastOutputFrame = frame
  }

  /// Snapshot string for debug; Dart parses getSessionSnapshot() as list, not this string.
  func snapshotString() -> String {
    lock.lock()
    defer { lock.unlock() }
    let cap = firstCaptureOutputFrameRel ?? 0
    return "SID=\(activeSessionId) Start=\(sessionStartSampleTime) FirstCap=\(cap) Offset=\(computedVocOffsetFrames) HasCap=\(hasCapture)"
  }

  /// Returns [sessionId, sessionStartFrame, firstCaptureOutputFrame, lastOutputFrame, computedVocOffsetFrames, hasFirstCapture 0|1]
  /// to match Android NativeSessionSnapshot.fromList().
  func snapshotList() -> [Int] {
    lock.lock()
    defer { lock.unlock() }
    let firstCap = firstCaptureOutputFrameRel ?? 0
    return [
      activeSessionId,
      Int(sessionStartSampleTime),
      firstCap,
      Int(lastOutputFrame),
      computedVocOffsetFrames,
      hasCapture ? 1 : 0
    ]
  }

  /// Check if a given sessionId is the current active session (for gating captures).
  func isActiveSession(_ sessionId: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return sessionId == activeSessionId
  }
}
