import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Log categories for filtering and organization
enum LogCat {
  lifecycle,
  audio,
  midi,
  recorder,
  replay,
  seek,
  route,
  ui,
  perf,
  error,
}

/// High-signal diagnostic logging utility with rate limiting and categorization
class DebugLog {
  static bool enabled = kDebugMode;
  static Set<LogCat> enabledCats = LogCat.values.toSet();
  
  // Rate limiting state
  static final Map<String, int> _countPerKey = {};
  static final Map<String, int> _lastMsPerKey = {};
  static final Map<String, Set<int>> _tripwireRunIds = {};
  
  // Context state
  static int? _currentRunId;
  static String? _currentExerciseId;
  static String? _currentMode; // "exercise" or "replay"
  
  /// Set context for current run
  static void setContext({int? runId, String? exerciseId, String? mode}) {
    _currentRunId = runId;
    _currentExerciseId = exerciseId;
    _currentMode = mode;
  }
  
  /// Get current context
  static Map<String, dynamic> getContext() {
    return {
      if (_currentRunId != null) 'runId': _currentRunId,
      if (_currentExerciseId != null) 'exerciseId': _currentExerciseId,
      if (_currentMode != null) 'mode': _currentMode,
    };
  }
  
  /// Log a message with category and optional rate limiting
  static void log(
    LogCat cat,
    String msg, {
    String? key,
    int throttleMs = 0,
    int maxPerRun = 0,
    int? runId,
    Map<String, dynamic>? extraMap,
  }) {
    if (!enabled || !enabledCats.contains(cat)) return;
    
    final effectiveRunId = runId ?? _currentRunId;
    final effectiveKey = key ?? msg;
    
    // Rate limiting check
    if (throttleMs > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastMs = _lastMsPerKey[effectiveKey];
      if (lastMs != null && (now - lastMs) < throttleMs) {
        return; // Throttled
      }
      _lastMsPerKey[effectiveKey] = now;
    }
    
    // Max per run check
    if (maxPerRun > 0 && effectiveRunId != null) {
      final runKey = '${effectiveKey}_run${effectiveRunId}';
      final count = _countPerKey[runKey] ?? 0;
      if (count >= maxPerRun) {
        return; // Max reached for this run
      }
      _countPerKey[runKey] = count + 1;
    }
    
    // Build log line
    final parts = <String>['[${cat.name}]', msg];
    final ctx = getContext();
    if (ctx.isNotEmpty) {
      ctx.forEach((k, v) => parts.add('$k=$v'));
    }
    if (extraMap != null) {
      extraMap.forEach((k, v) => parts.add('$k=$v'));
    }
    
    debugPrint(parts.join(' '));
  }
  
  /// Log a structured event (single line with key=value pairs)
  static void event(
    LogCat cat,
    String name, {
    int? runId,
    Map<String, dynamic>? fields,
  }) {
    if (!enabled || !enabledCats.contains(cat)) return;
    
    final parts = <String>['[${cat.name}]', name];
    final ctx = getContext();
    if (runId != null) {
      parts.add('runId=$runId');
    } else if (ctx.containsKey('runId')) {
      parts.add('runId=${ctx['runId']}');
    }
    if (fields != null) {
      fields.forEach((k, v) {
        if (v != null) {
          parts.add('$k=$v');
        }
      });
    }
    // Add other context
    ctx.forEach((k, v) {
      if (k != 'runId') parts.add('$k=$v');
    });
    
    debugPrint(parts.join(' '));
  }
  
  /// Tripwire: log with stack trace ONCE per runId for a given name
  static void tripwire(
    LogCat cat,
    String name, {
    int? runId,
    Map<String, dynamic>? fields,
    String? message,
  }) {
    if (!enabled || !enabledCats.contains(cat)) return;
    
    final effectiveRunId = runId ?? _currentRunId;
    if (effectiveRunId == null) return;
    
    final tripwireKey = '${cat.name}_$name';
    if (!_tripwireRunIds.containsKey(tripwireKey)) {
      _tripwireRunIds[tripwireKey] = {};
    }
    
    if (_tripwireRunIds[tripwireKey]!.contains(effectiveRunId)) {
      return; // Already logged for this run
    }
    
    _tripwireRunIds[tripwireKey]!.add(effectiveRunId);
    
    // Log event
    event(cat, name, runId: effectiveRunId, fields: fields);
    
    // Log stack trace
    if (message != null) {
      debugPrint('[${cat.name}] TRIPWIRE: $message');
    }
    debugPrint('[${cat.name}] Stack trace:');
    try {
      throw Exception('Stack trace');
    } catch (e, stack) {
      debugPrint(stack.toString());
    }
  }
  
  /// Clear rate limiting state (call between runs)
  static void clearState() {
    _countPerKey.clear();
    _lastMsPerKey.clear();
    _tripwireRunIds.clear();
  }
  
  /// Reset context
  static void resetContext() {
    _currentRunId = null;
    _currentExerciseId = null;
    _currentMode = null;
  }
}
