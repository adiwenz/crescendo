/// Constants for exercise timing and behavior
class ExerciseConstants {
  /// Lead-in time in milliseconds before the first target note reaches the sing line
  static const int leadInMs = 2000;
  
  /// Lead-in time in seconds (for convenience)
  static const double leadInSec = 2.0;
  
  /// Do not score pitch accuracy during the lead-in period
  static bool shouldScoreAtTime(double timeSec) {
    return timeSec >= leadInSec;
  }
  
  /// Check if a time (in milliseconds) is during the lead-in period
  static bool isDuringLeadIn(int timeMs) {
    return timeMs < leadInMs;
  }
}
