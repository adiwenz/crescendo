import 'package:flutter/foundation.dart' show debugPrint;

/// Enable/disable pitch highway debug logging
/// Set to false to disable all debug logs including frame timing
const bool kDebugPitchHighway = true;

/// Enable/disable frame timing logs (only logs frames > 50ms)
/// Set to false to completely disable frame timing spam
const bool kDebugFrameTiming = false;

/// Debug logging utilities with stack trace filtering and throttling
class DebugLog {
  static final Map<String, int> _lastLogTime = {};
  static int _buildCount = 0;
  static int _lastBuildLogTime = 0;

  /// Returns a filtered stack trace containing only app code lines
  /// (package:crescendo_mobile or /lib/)
  static String appStack({int maxLines = 12}) {
    final stack = StackTrace.current.toString();
    final lines = stack.split('\n');
    final appLines = <String>[];

    for (final line in lines) {
      if (line.contains('package:crescendo_mobile') || line.contains('/lib/')) {
        appLines.add(line);
        if (appLines.length >= maxLines) break;
      }
    }

    if (appLines.isEmpty) {
      // If no app lines found, return first 8 lines
      return lines.take(8).join('\n');
    }

    return appLines.join('\n');
  }

  /// Logs a message once per minimum interval (throttled by key)
  static void logOncePerMs(String key, String message, {int minIntervalMs = 250}) {
    if (!kDebugPitchHighway) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastTime = _lastLogTime[key] ?? 0;
    final elapsed = now - lastTime;

    if (elapsed >= minIntervalMs) {
      _lastLogTime[key] = now;
      debugPrint('[Debug] $message');
    }
  }

  /// Logs a one-off important event
  static void logEvent(String tag, String message) {
    if (!kDebugPitchHighway) return;
    debugPrint('[$tag] $message');
  }

  /// Tripwire helper: logs suspicious events with optional stack trace
  static void tripwire(
    String tag,
    String message, {
    bool includeStack = true,
    int throttleMs = 0,
  }) {
    if (!kDebugPitchHighway) return;

    // Throttle if requested
    if (throttleMs > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastTime = _lastLogTime['tripwire_$tag'] ?? 0;
      if (now - lastTime < throttleMs) return;
      _lastLogTime['tripwire_$tag'] = now;
    }

    final stackStr = includeStack ? '\n${appStack()}' : '';
    debugPrint('[TRIPWIRE:$tag] $message$stackStr');
  }

  /// Increments build counter and logs build rate every second
  static void logBuildRate() {
    if (!kDebugPitchHighway) return;

    _buildCount++;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastBuildLogTime;

    if (elapsed >= 1000) {
      debugPrint('[BuildRate] builds in last second: $_buildCount');
      _buildCount = 0;
      _lastBuildLogTime = now;
    }
  }

  /// Resets build counter (call on dispose/restart)
  static void resetBuildCounter() {
    _buildCount = 0;
    _lastBuildLogTime = 0;
  }
}
