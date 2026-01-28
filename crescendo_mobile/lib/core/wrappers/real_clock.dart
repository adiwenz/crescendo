import 'dart:async';
import 'package:crescendo_mobile/core/interfaces/i_clock.dart';

class RealClock implements IClock {
  @override
  Timer createTimer(Duration duration, void Function() callback) {
    return Timer(duration, callback);
  }

  @override
  DateTime now() {
    return DateTime.now();
  }

  @override
  Timer periodic(Duration duration, void Function(Timer p1) callback) {
    return Timer.periodic(duration, callback);
  }
}
