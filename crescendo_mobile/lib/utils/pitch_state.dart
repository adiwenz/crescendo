class PitchState {
  double? currentPitchHz;
  double? currentPitchMidi;
  double? lastValidPitchHz;
  double? lastValidPitchMidi;
  bool isVoiced = false;
  double timestampSec = 0;

  void updateVoiced({
    required double timeSec,
    double? pitchHz,
    double? pitchMidi,
  }) {
    timestampSec = timeSec;
    isVoiced = true;
    currentPitchHz = pitchHz;
    currentPitchMidi = pitchMidi;
    if (pitchHz != null) {
      lastValidPitchHz = pitchHz;
    }
    if (pitchMidi != null) {
      lastValidPitchMidi = pitchMidi;
    }
  }

  void updateUnvoiced({required double timeSec}) {
    timestampSec = timeSec;
    isVoiced = false;
    currentPitchHz = null;
    currentPitchMidi = null;
  }

  double? get effectiveMidi => currentPitchMidi ?? lastValidPitchMidi;

  double? get effectiveHz => currentPitchHz ?? lastValidPitchHz;

  void reset() {
    currentPitchHz = null;
    currentPitchMidi = null;
    lastValidPitchHz = null;
    lastValidPitchMidi = null;
    isVoiced = false;
    timestampSec = 0;
  }
}
