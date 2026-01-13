import '../services/range_store.dart';

/// Service for managing vocal range with default fallbacks
class VocalRangeService {
  static const int defaultLowestMidi = 48; // C3
  static const int defaultHighestMidi = 79; // G5

  final RangeStore _rangeStore = RangeStore();

  /// Get the user's vocal range, or return defaults if not set
  Future<(int lowestMidi, int highestMidi)> getRange() async {
    final (lowest, highest) = await _rangeStore.getRange();
    if (lowest == null || highest == null || lowest >= highest) {
      return (defaultLowestMidi, defaultHighestMidi);
    }
    return (lowest, highest);
  }

  /// Check if user has set a custom range
  Future<bool> hasCustomRange() async {
    final (lowest, highest) = await _rangeStore.getRange();
    return lowest != null && highest != null && lowest < highest;
  }

  /// Get range as display string (e.g., "C3 – G5")
  Future<String> getRangeDisplay() async {
    final (lowest, highest) = await getRange();
    final lowestName = _midiToName(lowest);
    final highestName = _midiToName(highest);
    return '$lowestName – $highestName';
  }

  String _midiToName(int midi) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midi / 12).floor() - 1;
    return '${names[midi % 12]}$octave';
  }
}
