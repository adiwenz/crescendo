import 'package:flutter/material.dart';

class DebugOverlay extends StatelessWidget {
  final double? audioPositionMs;
  final double visualTimeMs;
  final double? pitchLagMs;
  final double offsetMs;
  final ValueChanged<double> onOffsetChange;
  final String? label;

  const DebugOverlay({
    super.key,
    required this.audioPositionMs,
    required this.visualTimeMs,
    required this.pitchLagMs,
    required this.offsetMs,
    required this.onOffsetChange,
    this.label,
  });

  String _fmt(double? v) => v == null ? '--' : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    final delta = audioPositionMs == null ? null : (visualTimeMs - audioPositionMs!);
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white, fontSize: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label != null) Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('audio: ${_fmt(audioPositionMs)} ms'),
                  Text('visual: ${_fmt(visualTimeMs)} ms'),
                  Text('delta: ${_fmt(delta)} ms'),
                  Text('pitch lag: ${_fmt(pitchLagMs)} ms'),
                  const SizedBox(height: 8),
                  Text('offset: ${offsetMs.toStringAsFixed(0)} ms'),
                  SizedBox(
                    width: 180,
                    child: Slider(
                      min: -300,
                      max: 300,
                      value: offsetMs.clamp(-300, 300),
                      onChanged: onOffsetChange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
