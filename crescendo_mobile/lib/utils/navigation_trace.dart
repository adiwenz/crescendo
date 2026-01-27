import 'package:flutter/foundation.dart';

/// Precision timing utility for navigation lifecycle tracing.
class NavigationTrace {
  final String label;
  final String traceId;
  final Stopwatch _sw;
  static int _globalIdCounter = 0;

  NavigationTrace._(this.label, this.traceId) : _sw = Stopwatch()..start();

  /// Start a new navigation trace.
  static NavigationTrace start(String label) {
    final traceId = 'nav_${++_globalIdCounter}';
    final trace = NavigationTrace._(label, traceId);
    debugPrint('[NavigationTrace] ($traceId) START: $label');
    return trace;
  }

  /// Mark a specific milestone in the trace.
  void mark(String milestone) {
    final elapsed = _sw.elapsedMilliseconds;
    debugPrint('[NavigationTrace] ($traceId) MS: $elapsed ms - $milestone');
  }

  /// Mark first frame painted (usually called via WidgetsBinding.addPostFrameCallback).
  void markFirstFrame() {
    final elapsed = _sw.elapsedMilliseconds;
    debugPrint('[NavigationTrace] ($traceId) FIRST FRAME: $elapsed ms - Navigation Complete');
    _sw.stop();
  }
}
