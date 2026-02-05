/// Constants for audio timing and behavior
class AudioConstants {
  /// Lead-in time in milliseconds before the first target note reaches the sing line
  static const int leadInMs = 2000;
  
  /// Lead-in time in seconds (for convenience)
  static const double leadInSec = 2.0;
  
  /// Centralized synchronization compensation value for speakers (200ms fallback)
  static const double manualSyncOffsetMs = 200.0;
  
  /// Centralized iOS-specific synchronization baseline (200ms)
  static const double iosSyncOffsetMs = 200.0;
  
  /// Standard audio sample rate for recording and playback (48kHz)
  static const int audioSampleRate = 48000;
  
  /// Do not score pitch accuracy during the lead-in period
  static bool shouldScoreAtTime(double timeSec) {
    return timeSec >= leadInSec;
  }
  
  static const double chirpDurationSec = 0.050; // 50ms chirp
  static const double chirpSilenceSec = 0.200; // 200ms silence
  static const double totalChirpOffsetSec = chirpDurationSec + chirpSilenceSec;

  /// Check if a time (in milliseconds) is during the lead-in period
  static bool isDuringLeadIn(int timeMs) {
    return timeMs < leadInMs;
  }
}
