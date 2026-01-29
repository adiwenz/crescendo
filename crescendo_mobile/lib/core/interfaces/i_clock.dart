import 'dart:async';

abstract class IClock {
  DateTime now();
  Timer createTimer(Duration duration, void Function() callback);
  Timer periodic(Duration duration, void Function(Timer) callback);
}
