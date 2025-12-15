import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../audio/hold_stability.dart';
import '../../models/exercise_plan.dart';
import '../../models/pitch_frame.dart';

class HoldStabilityScreen extends StatefulWidget {
  final ExercisePlan plan;
  final List<PitchFrame> frames;
  final List<HoldMetrics>? previousHoldMetrics;

  const HoldStabilityScreen({
    super.key,
    required this.plan,
    required this.frames,
    this.previousHoldMetrics,
  });

  @override
  State<HoldStabilityScreen> createState() => _HoldStabilityScreenState();
}

class _HoldStabilityScreenState extends State<HoldStabilityScreen> {
  late final List<_NoteHold> _noteHolds;
  late final _SessionHoldSummary _summary;

  @override
  void initState() {
    super.initState();
    _noteHolds = _computeNoteHolds();
    _summary = _summarize(_noteHolds);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hold Stability')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummary(),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _noteHolds.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final h = _noteHolds[idx];
                  return _NoteCard(
                    label: 'Note ${idx + 1} (${_midiLabel(h.midi)})',
                    hold: h,
                    prev: widget.previousHoldMetrics != null &&
                            idx < widget.previousHoldMetrics!.length
                        ? widget.previousHoldMetrics![idx]
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final best = _summary.best;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Session stability',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _StatChip(
              label: 'Avg hold',
              value:
                  '${_summary.avgHold.toStringAsFixed(2)}s',
            ),
            _StatChip(
              label: 'Avg σ (cents)',
              value: _summary.avgStdDev != null
                  ? _summary.avgStdDev!.toStringAsFixed(1)
                  : '—',
            ),
            if (best != null)
              _StatChip(
                label: 'Best hold',
                value:
                    '${best.hold.maxContinuousOnPitchSec.toStringAsFixed(2)}s (${_midiLabel(best.midi)})',
              ),
          ],
        ),
      ],
    );
  }

  List<_NoteHold> _computeNoteHolds() {
    final holds = <_NoteHold>[];
    double cursor = 0;
    for (var i = 0; i < widget.plan.notes.length; i++) {
      final n = widget.plan.notes[i];
      final start = cursor;
      final end = cursor + n.durationSec;
      cursor = end + widget.plan.gapSec;
      final targetHz = 440.0 * math.pow(2, (n.midi - 69) / 12.0);
      final hm = computeHoldMetrics(
        frames: widget.frames,
        noteStart: start,
        noteEnd: end,
        targetHz: targetHz,
      );
      holds.add(_NoteHold(
        midi: n.midi,
        durationSec: n.durationSec,
        hold: hm,
      ));
    }
    return holds;
  }

  _SessionHoldSummary _summarize(List<_NoteHold> holds) {
    if (holds.isEmpty) {
      return _SessionHoldSummary(avgHold: 0, avgStdDev: null, best: null);
    }
    final avgHold = holds
            .map((h) => h.hold.maxContinuousOnPitchSec)
            .reduce((a, b) => a + b) /
        holds.length;
    final stds = holds
        .map((h) => h.hold.stabilityCentsStdDev)
        .where((v) => v != null && v!.isFinite)
        .cast<double>()
        .toList();
    final avgStd = stds.isNotEmpty
        ? stds.reduce((a, b) => a + b) / stds.length
        : null;
    final best = holds.isNotEmpty
        ? holds.reduce((a, b) => a.hold.maxContinuousOnPitchSec >=
                b.hold.maxContinuousOnPitchSec
            ? a
            : b)
        : null;
    return _SessionHoldSummary(
      avgHold: avgHold,
      avgStdDev: avgStd,
      best: best,
    );
  }
}

class _NoteCard extends StatelessWidget {
  final String label;
  final _NoteHold hold;
  final HoldMetrics? prev;

  const _NoteCard({
    required this.label,
    required this.hold,
    this.prev,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = hold.hold.holdPercent;
    final prevSecs = prev?.maxContinuousOnPitchSec;
    final currSecs = hold.hold.maxContinuousOnPitchSec;
    final deltaPct =
        (prevSecs != null && prevSecs > 0) ? ((currSecs - prevSecs) / prevSecs) : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _StabilityBar(
            duration: hold.durationSec,
            holdSec: currSecs,
          ),
          const SizedBox(height: 4),
          Text(
            'Held on pitch: ${currSecs.toStringAsFixed(2)}s'
            '${prevSecs != null ? ' → ${currSecs.toStringAsFixed(2)}s' : ''}'
            '${deltaPct != null ? ' (${(deltaPct * 100).toStringAsFixed(0)}%)' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Stability (σ): ${hold.hold.stabilityCentsStdDev?.toStringAsFixed(1) ?? '—'} cents • Hold ${ (pct * 100).toStringAsFixed(0)}%',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
          ),
          if (hold.hold.driftCentsPerSec != null &&
              hold.hold.driftCentsPerSec!.isFinite)
            Text(
              'Drift: ${hold.hold.driftCentsPerSec!.toStringAsFixed(1)} cents/s',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
        ],
      ),
    );
  }
}

class _StabilityBar extends StatelessWidget {
  final double duration;
  final double holdSec;

  const _StabilityBar({required this.duration, required this.holdSec});

  @override
  Widget build(BuildContext context) {
    final pct = duration > 0 ? (holdSec / duration).clamp(0.0, 1.0) : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final filled = constraints.maxWidth * pct;
        return Container(
          height: 10,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: filled,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(
                  colors: [Colors.green, Colors.lightGreenAccent],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NoteHold {
  final int midi;
  final double durationSec;
  final HoldMetrics hold;

  _NoteHold({required this.midi, required this.durationSec, required this.hold});
}

class _SessionHoldSummary {
  final double avgHold;
  final double? avgStdDev;
  final _NoteHold? best;

  _SessionHoldSummary({
    required this.avgHold,
    required this.avgStdDev,
    required this.best,
  });
}

String _midiLabel(int midi) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  final name = names[midi % 12];
  final octave = (midi ~/ 12) - 1;
  return '$name$octave';
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
