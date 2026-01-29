
/// MIDI event types
enum MidiEventType {
  noteOn,
  noteOff,
  pitchBend,
  controlChange,
  programChange,
  rpnMsb,
  rpnLsb,
  dataEntryMsb,
  dataEntryLsb,
  rpnNull,
}

/// MIDI event with absolute tick time
class MidiEvent {
  final int tick; // Absolute tick time (0-based)
  final MidiEventType type;
  final int channel; // 0-15
  final Map<String, int> data; // Event-specific parameters

  MidiEvent({
    required this.tick,
    required this.type,
    this.channel = 0,
    Map<String, int>? data,
  }) : data = data ?? {};

  /// Create a NoteOn event
  factory MidiEvent.noteOn({
    required int tick,
    required int note,
    required int velocity,
    int channel = 0,
  }) {
    return MidiEvent(
      tick: tick,
      type: MidiEventType.noteOn,
      channel: channel,
      data: {'note': note, 'velocity': velocity},
    );
  }

  /// Create a NoteOff event
  factory MidiEvent.noteOff({
    required int tick,
    required int note,
    int velocity = 0,
    int channel = 0,
  }) {
    return MidiEvent(
      tick: tick,
      type: MidiEventType.noteOff,
      channel: channel,
      data: {'note': note, 'velocity': velocity},
    );
  }

  /// Create a PitchBend event (14-bit value: 0-16383, center=8192)
  factory MidiEvent.pitchBend({
    required int tick,
    required int value, // 0-16383, 8192 = no bend
    int channel = 0,
  }) {
    return MidiEvent(
      tick: tick,
      type: MidiEventType.pitchBend,
      channel: channel,
      data: {'value': value.clamp(0, 16383)},
    );
  }

  /// Create a Control Change event
  factory MidiEvent.controlChange({
    required int tick,
    required int controller,
    required int value,
    int channel = 0,
  }) {
    return MidiEvent(
      tick: tick,
      type: MidiEventType.controlChange,
      channel: channel,
      data: {'controller': controller, 'value': value},
    );
  }

  /// Create a Program Change event
  factory MidiEvent.programChange({
    required int tick,
    required int program,
    int channel = 0,
  }) {
    return MidiEvent(
      tick: tick,
      type: MidiEventType.programChange,
      channel: channel,
      data: {'program': program},
    );
  }

  /// Create RPN messages to set pitch bend range
  static List<MidiEvent> setPitchBendRange({
    required int tick,
    required int semitones, // e.g., 12 for ±12 semitones
    int channel = 0,
  }) {
    return [
      // Set RPN to 0 (Pitch Bend Sensitivity)
      MidiEvent(
        tick: tick,
        type: MidiEventType.rpnMsb,
        channel: channel,
        data: {'value': 0},
      ),
      MidiEvent(
        tick: tick,
        type: MidiEventType.rpnLsb,
        channel: channel,
        data: {'value': 0},
      ),
      // Set data entry to semitones
      MidiEvent(
        tick: tick,
        type: MidiEventType.dataEntryMsb,
        channel: channel,
        data: {'value': semitones},
      ),
      MidiEvent(
        tick: tick,
        type: MidiEventType.dataEntryLsb,
        channel: channel,
        data: {'value': 0},
      ),
      // Null RPN
      MidiEvent(
        tick: tick,
        type: MidiEventType.rpnNull,
        channel: channel,
        data: {},
      ),
    ];
  }
}

/// MIDI score representation
class MidiScore {
  final int tempoBpm;
  final int ppq; // Ticks per quarter note (pulses per quarter)
  final int numTracks;
  final List<MidiEvent> events;
  final int pitchBendRangeSemitones;

  MidiScore({
    this.tempoBpm = 120,
    this.ppq = 480,
    this.numTracks = 1,
    required this.events,
    this.pitchBendRangeSemitones = 12, // ±12 semitones default
  });

  /// Convert seconds to ticks
  int secondsToTicks(double seconds) {
    final beats = seconds * (tempoBpm / 60.0);
    return (beats * ppq).round();
  }

  /// Convert ticks to seconds
  double ticksToSeconds(int ticks) {
    final beats = ticks / ppq;
    return beats * (60.0 / tempoBpm);
  }

  /// Get events sorted by tick time
  List<MidiEvent> get sortedEvents {
    final sorted = List<MidiEvent>.from(events);
    sorted.sort((a, b) => a.tick.compareTo(b.tick));
    return sorted;
  }
}

/// Builder for creating MIDI scores from ReferenceNote lists
class MidiScoreBuilder {
  final int tempoBpm;
  final int ppq;
  final int pitchBendRangeSemitones;
  final int channel;
  final int program; // MIDI program number (0-127)
  final double leadInSeconds;
  final List<MidiEvent> _events = [];

  MidiScoreBuilder({
    this.tempoBpm = 120,
    this.ppq = 480,
    this.pitchBendRangeSemitones = 12,
    this.channel = 0,
    this.program = 0, // Acoustic Grand Piano default
    this.leadInSeconds = 0.0,
  });

  /// Convert semitone offset to pitch bend value (14-bit)
  /// semitoneOffset: -12 to +12 (for ±12 semitone range)
  int _semitoneToPitchBend(double semitoneOffset) {
    // Clamp to bend range
    final clamped = semitoneOffset.clamp(
      -pitchBendRangeSemitones.toDouble(),
      pitchBendRangeSemitones.toDouble(),
    );
    // Convert to 14-bit value: 0 = -range, 8192 = 0, 16383 = +range
    final normalized = (clamped / pitchBendRangeSemitones).clamp(-1.0, 1.0);
    final bendValue = (8192 + (normalized * 8192)).round();
    return bendValue.clamp(0, 16383);
  }

  /// Convert MIDI note to semitone offset from base note
  double _midiToSemitoneOffset(int midiNote, int baseMidiNote) {
    return (midiNote - baseMidiNote).toDouble();
  }

  /// Add a sustained note with pitch bend for glides
  void addGlide({
    required double startSec,
    required double endSec,
    required int startMidi,
    required int endMidi,
    int updateRateHz = 100, // Pitch bend updates per second
  }) {
    final startTick = secondsToTicks(startSec + leadInSeconds);
    final endTick = secondsToTicks(endSec + leadInSeconds);
    final durationSec = endSec - startSec;
    final baseMidi = startMidi;

    // Set pitch bend range at the start (if not already set)
    if (_events.isEmpty || _events.first.type != MidiEventType.rpnMsb) {
      _events.addAll(MidiEvent.setPitchBendRange(
        tick: 0,
        semitones: pitchBendRangeSemitones,
        channel: channel,
      ));
    }

    // Program change at start
    _events.add(MidiEvent.programChange(
      tick: startTick,
      program: program,
      channel: channel,
    ));

    // NoteOn at start
    _events.add(MidiEvent.noteOn(
      tick: startTick,
      note: baseMidi,
      velocity: 80,
      channel: channel,
    ));

    // Initial pitch bend to start note
    final startOffset = _midiToSemitoneOffset(startMidi, baseMidi);
    final startBend = _semitoneToPitchBend(startOffset);
    _events.add(MidiEvent.pitchBend(
      tick: startTick,
      value: startBend,
      channel: channel,
    ));

    // Generate pitch bend events during glide
    final updateIntervalSec = 1.0 / updateRateHz;
    var currentTimeSec = startSec;
    final totalDurationSec = durationSec;

      while (currentTimeSec < endSec) {
        final progress = ((currentTimeSec - startSec) / totalDurationSec).clamp(0.0, 1.0);
        final currentMidi = (startMidi + (endMidi - startMidi) * progress).round();
        final semitoneOffset = _midiToSemitoneOffset(currentMidi, baseMidi);
        final bendValue = _semitoneToPitchBend(semitoneOffset);

      final tick = secondsToTicks(currentTimeSec + leadInSeconds);
      _events.add(MidiEvent.pitchBend(
        tick: tick,
        value: bendValue,
        channel: channel,
      ));

      currentTimeSec += updateIntervalSec;
    }

    // Final pitch bend to end note
    final endOffset = _midiToSemitoneOffset(endMidi, baseMidi);
    final endBend = _semitoneToPitchBend(endOffset);
    _events.add(MidiEvent.pitchBend(
      tick: endTick,
      value: endBend,
      channel: channel,
    ));

    // NoteOff at end
    _events.add(MidiEvent.noteOff(
      tick: endTick,
      note: baseMidi,
      channel: channel,
    ));
  }

  /// Add a regular note (non-glide)
  void addNote({
    required double startSec,
    required double endSec,
    required int midiNote,
    int velocity = 80,
  }) {
    final startTick = secondsToTicks(startSec + leadInSeconds);
    final endTick = secondsToTicks(endSec + leadInSeconds);

    // Program change at start (if first event)
    if (_events.isEmpty || _events.first.type != MidiEventType.rpnMsb) {
      _events.addAll(MidiEvent.setPitchBendRange(
        tick: 0,
        semitones: pitchBendRangeSemitones,
        channel: channel,
      ));
    }

    _events.add(MidiEvent.programChange(
      tick: startTick,
      program: program,
      channel: channel,
    ));

    _events.add(MidiEvent.noteOn(
      tick: startTick,
      note: midiNote,
      velocity: velocity,
      channel: channel,
    ));

    _events.add(MidiEvent.noteOff(
      tick: endTick,
      note: midiNote,
      channel: channel,
    ));
  }

  /// Convert seconds to ticks
  int secondsToTicks(double seconds) {
    final beats = seconds * (tempoBpm / 60.0);
    return (beats * ppq).round();
  }

  /// Build the MIDI score
  MidiScore build() {
    return MidiScore(
      tempoBpm: tempoBpm,
      ppq: ppq,
      events: _events,
      pitchBendRangeSemitones: pitchBendRangeSemitones,
    );
  }
}
