import 'dart:async';
import 'package:crescendo_mobile/core/interfaces/i_clock.dart';

/// Fake clock for testing.
/// Allows manual time control and deterministic timer firing.
class FakeClock implements IClock {
  DateTime _now = DateTime(2025, 1, 1, 12, 0, 0);
  final List<_ScheduledTimer> _timers = [];

  @override
  DateTime now() => _now;

  /// Set the current time.
  void setNow(DateTime time) {
    _now = time;
  }

  /// Advance time by the given duration and fire any timers that should trigger.
  void advance(Duration duration) {
    _now = _now.add(duration);
    _checkAndFireTimers();
  }

  /// Fire all timers that should have triggered by now.
  void _checkAndFireTimers() {
    // Sort timers by fire time
    _timers.sort((a, b) => a.fireTime.compareTo(b.fireTime));

    // Fire all timers that should have triggered
    final timersToFire = <_ScheduledTimer>[];
    for (final timer in _timers) {
      if (!timer.isActive) continue;
      if (timer.fireTime.isBefore(_now) || timer.fireTime.isAtSameMomentAs(_now)) {
        timersToFire.add(timer);
      }
    }

    for (final timer in timersToFire) {
      if (!timer.isActive) continue;

      timer.callback();

      if (timer.isPeriodic && timer.isActive) {
        // Reschedule periodic timer
        timer.fireTime = timer.fireTime.add(timer.duration);
      } else {
        // Remove one-shot timer
        timer.cancel();
        _timers.remove(timer);
      }
    }
  }

  @override
  Timer createTimer(Duration duration, void Function() callback) {
    final timer = _ScheduledTimer(
      duration: duration,
      callback: callback,
      fireTime: _now.add(duration),
      isPeriodic: false,
    );
    _timers.add(timer);
    return timer;
  }

  @override
  Timer periodic(Duration duration, void Function(Timer) callback) {
    final timer = _ScheduledTimer(
      duration: duration,
      callback: () => callback(timer),
      fireTime: _now.add(duration),
      isPeriodic: true,
    );
    _timers.add(timer);
    return timer;
  }

  /// Clear all timers (for test cleanup).
  void clear() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Get count of active timers.
  int get activeTimerCount => _timers.where((t) => t.isActive).length;
}

class _ScheduledTimer implements Timer {
  final Duration duration;
  final void Function() callback;
  DateTime fireTime;
  final bool isPeriodic;
  bool _active = true;

  _ScheduledTimer({
    required this.duration,
    required this.callback,
    required this.fireTime,
    required this.isPeriodic,
  });

  @override
  void cancel() {
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
