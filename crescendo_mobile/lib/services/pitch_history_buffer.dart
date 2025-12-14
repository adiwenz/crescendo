import '../models/pitch_frame.dart';

class PitchHistoryBuffer {
  final int capacity;
  final List<PitchFrame> _frames = [];

  PitchHistoryBuffer({this.capacity = 120});

  void add(PitchFrame f) {
    _frames.add(f);
    if (_frames.length > capacity) {
      _frames.removeRange(0, _frames.length - capacity);
    }
  }

  List<PitchFrame> get frames => List.unmodifiable(_frames);

  void clear() => _frames.clear();
}
