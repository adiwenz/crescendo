/// Constants for audio timing and behavior
class AudioConstants {
  /// Lead-in time in milliseconds before the first target note reaches the sing line
  static const int leadInMs = 2000;
  
  /// Lead-in time in seconds (for convenience)
  static const double leadInSec = 2.0;
  
  /// Standard audio sample rate for recording and playback (48kHz)
  static const int audioSampleRate = 48000;
  
  /// Do not score pitch accuracy during the lead-in period
  static bool shouldScoreAtTime(double timeSec) {
    return timeSec >= leadInSec;
  }
  
  /// Check if a time (in milliseconds) is during the lead-in period
  static bool isDuringLeadIn(int timeMs) {
    return timeMs < leadInMs;
  }
}
