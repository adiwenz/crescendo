import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/pitch_service.dart';
import '../../services/range_store.dart';
import '../../utils/pitch_math.dart';
import '../widgets/piano_keyboard.dart';

class FindRangeHighestScreen extends StatefulWidget {
  final int lowestMidi;

  const FindRangeHighestScreen({super.key, required this.lowestMidi});

  @override
  State<FindRangeHighestScreen> createState() => _FindRangeHighestScreenState();
}

class _FindRangeHighestScreenState extends State<FindRangeHighestScreen> {
  final PitchService _service = PitchService();
  final RangeStore _store = RangeStore();
  StreamSubscription<PitchFrame>? _sub;
  bool _listening = false;
  int? _currentMidi;
  int? _stableMidi;
  int? _candidateMidi;
  int _candidateCount = 0;
  DateTime? _stableSince;
  bool _captured = false;
  bool _showSummary = false;
  String _status = 'Sing your highest comfortable note.';

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (_listening) return;
    await _service.start();
    _listening = true;
    _status = 'Listening...';
    _sub = _service.stream.listen(_onFrame, onError: (_) => _onNoPitch());
    setState(() {});
  }

  void _onFrame(PitchFrame frame) {
    final freq = frame.frequencyHz;
    final conf = frame.confidence;
    if (freq == null || !freq.isFinite || freq <= 0 || (conf != null && conf < 0.5)) {
      _onNoPitch();
      return;
    }
    final midi = (69 + 12 * (math.log(freq / 440.0) / math.ln2)).round();
    _currentMidi = midi;
    if (_candidateMidi == midi) {
      _candidateCount += 1;
    } else {
      _candidateMidi = midi;
      _candidateCount = 1;
      _stableSince = null;
    }
    final noteName = PitchMath.midiToName(midi);
    if (_stableSince == null) {
      _stableSince = DateTime.now();
    } else {
      final held = DateTime.now().difference(_stableSince!);
      if (held.inMilliseconds >= 3000 && !_captured) {
        _stableMidi = midi;
        _onStableCaptured(midi, noteName);
        return;
      }
    }
    _status = 'Listening... $noteName';
    setState(() {});
  }

  void _onNoPitch() {
    if (!_listening) return;
    _status = 'No pitch detected';
    _candidateMidi = null;
    _candidateCount = 0;
    _stableSince = null;
    setState(() {});
  }

  void _stopListening() {
    _sub?.cancel();
    _sub = null;
    _service.stop();
    _listening = false;
    setState(() {});
  }

  void _onStableCaptured(int midi, String noteName) {
    _captured = true;
    _stopListening();
    setState(() {
      _stableMidi = midi;
      _showSummary = true;
      _status = 'Captured $noteName';
    });
    Future.delayed(const Duration(seconds: 2), () async {
      await _store.saveRange(lowestMidi: widget.lowestMidi, highestMidi: midi);
      if (!mounted) return;
      Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final noteLabel = _stableMidi != null
        ? 'Highest: ${PitchMath.midiToName(_stableMidi!)}'
        : 'Highest: —';
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Find Your Range'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step 2: Sing your highest comfortable note',
              style:
                  Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 140,
                  child: PianoKeyboard(
                    startMidi: 36,
                    endMidi: 84,
                    highlightedMidi: _currentMidi,
                    onKeyTap: (_) {},
                    keyHeight: 26,
                  ),
                ),
              ),
            ),
            if (_showSummary) ...[
              const SizedBox(height: 12),
              Text('Your highest note was ${PitchMath.midiToName(_stableMidi!)}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            Text(noteLabel, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _listening || _captured ? null : _startListening,
                  child: const Text('Start Listening'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {
                    _stopListening();
                    Navigator.pop(context);
                  },
                  child: const Text('Back'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    _stopListening();
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
