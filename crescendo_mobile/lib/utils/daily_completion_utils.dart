import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Utilities for daily exercise completion tracking
class DailyCompletionUtils {
  static bool _initialized = false;

  /// Initialize timezone data (call once at app startup)
  static void initialize() {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
  }

  /// Generate a date key (YYYY-MM-DD) in America/New_York timezone
  static String generateDateKey(DateTime timestamp) {
    initialize();
    final location = tz.getLocation('America/New_York');
    final localTime = tz.TZDateTime.from(timestamp, location);
    return '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-${localTime.day.toString().padLeft(2, '0')}';
  }

  /// Get today's date key
  static String getTodayDateKey() {
    return generateDateKey(DateTime.now());
  }

  /// Default tolerance in seconds for countdown completion (elapsedSec >= requiredSec - tolerance)
  static const int countdownToleranceSec = 2;

  /// Countdown: only counts for daily effort if session ended normally AND reached end.
  /// completionPercent 0–1; elapsedSec/requiredSec from session.
  static bool countsForDailyEffortCountdown({
    required bool sessionEndedNormally,
    double? completionPercent,
    int? elapsedSec,
    int? requiredSec,
  }) {
    if (!sessionEndedNormally) return false;
    if (completionPercent != null && completionPercent >= 1.0) return true;
    if (elapsedSec != null && requiredSec != null && requiredSec > 0) {
      final tolerance = countdownToleranceSec.clamp(0, requiredSec ~/ 5);
      return elapsedSec >= requiredSec - tolerance;
    }
    return completionPercent != null && completionPercent >= 0.95;
  }

  /// PitchHighway: counts for daily effort only when the user played through the whole
  /// exercise (playback completed). The player uses [sessionEndedNormally] for this;
  /// this percent-based helper is legacy.
  static bool countsForDailyEffortPitchHighway(double? completionPercent) {
    if (completionPercent == null) return false;
    return completionPercent >= 0.95;
  }

  /// Legacy / generic: use 95% threshold (e.g. when exercise type is unknown).
  static bool countsForDailyEffort(double? completionPercent) {
    if (completionPercent == null) return false;
    return completionPercent >= 0.95;
  }
}
