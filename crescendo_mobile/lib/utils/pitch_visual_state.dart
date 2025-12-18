class PitchVisualState {
  double? visualPitchHz;
  double? visualPitchMidi;
  double visualTimeSec = 0;
  bool isVoiced = false;

  void update({
    required double timeSec,
    required double? pitchHz,
    required double? pitchMidi,
    required bool voiced,
  }) {
    visualTimeSec = timeSec;
    visualPitchHz = pitchHz;
    visualPitchMidi = pitchMidi;
    isVoiced = voiced;
  }

  void reset() {
    visualPitchHz = null;
    visualPitchMidi = null;
    visualTimeSec = 0;
    isVoiced = false;
  }
}
