import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/exercise_attempt.dart';
import '../../models/exercise_take.dart';
import '../../models/replay_models.dart';
import '../../models/vocal_exercise.dart';
import '../../models/reference_note.dart';
import '../../services/transposed_exercise_builder.dart';
import '../../services/vocal_range_service.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../utils/audio_constants.dart';
import '../../utils/pitch_math.dart';
import '../../debug/debug_log.dart' show DebugLog, LogCat;
import '../widgets/overview_graph.dart';
import 'pitch_highway_review_screen.dart';
import '../../services/attempt_repository.dart';
import '../../models/last_take.dart';
import '../../models/pitch_frame.dart';

import '../../models/last_take_draft.dart';

class ExerciseReviewSummaryScreen extends StatefulWidget {
  final VocalExercise exercise;
  final ExerciseAttempt? attempt;
  final LastTakeDraft? draft;
  final PitchHighwayDifficulty? difficulty;

  const ExerciseReviewSummaryScreen({
    super.key,
    required this.exercise,
    this.attempt,
    this.draft,
    this.difficulty,
  }) : assert(attempt != null || draft != null, 'Must provide attempt or draft');

  @override
  State<ExerciseReviewSummaryScreen> createState() =>
      _ExerciseReviewSummaryScreenState();
}

class _ExerciseReviewSummaryScreenState
    extends State<ExerciseReviewSummaryScreen> {
  final VocalRangeService _vocalRangeService = VocalRangeService();
  List<PitchSample> _samples = const [];
  List<TargetNote> _targets = const [];
  List<ExerciseSegment> _segments = const [];
  int _durationMs = 0;
  bool _loading = true;
  ExerciseTake? _dbTake;
  late ExerciseAttempt _displayAttempt;

  @override
  void initState() {
    super.initState();
    _initAttempt();
    _loadReviewData();
  }

  void _initAttempt() {
    if (widget.attempt != null) {
      _displayAttempt = widget.attempt!;
    } else {
      // Build from draft
      final d = widget.draft!;
      _displayAttempt = ExerciseAttempt(
         id: '0', // transient
         exerciseId: d.exerciseId,
         categoryId: widget.exercise.categoryId,
         startedAt: d.createdAt.subtract(Duration(milliseconds: d.durationMs)),
         completedAt: d.createdAt,
         overallScore: d.score.toDouble(),
         recorderStartSec: 0.0, // approximates
         contourJson: d.contourJson,
         subScores: {}, // or {'intonation': d.score}
         minMidi: d.minMidi,
         maxMidi: d.maxMidi,
      );
    }
  }

  Future<void> _loadReviewData() async {
    var currentAttempt = _displayAttempt;
    String? pitchJson = currentAttempt.contourJson;

    try {
      // If using a draft, we must resolve the WAV path future
      if (widget.draft != null) {
        final d = widget.draft!;
        debugPrint('[ReviewSummary] Resolving WAV path from draft future...');
        try {
          // Await the encoding future
          final wavPath = await d.wavPathFuture;
          debugPrint('[ReviewSummary] Draft WAV resolved: $wavPath');
          
          // Recreate _displayAttempt with the resolved path since it's immutable
          _displayAttempt = ExerciseAttempt(
            id: _displayAttempt.id,
            exerciseId: _displayAttempt.exerciseId,
            categoryId: _displayAttempt.categoryId,
            startedAt: _displayAttempt.startedAt,
            completedAt: _displayAttempt.completedAt,
            overallScore: _displayAttempt.overallScore,
            subScores: _displayAttempt.subScores,
            recordingPath: wavPath, // <--- THE FIX
            contourJson: _displayAttempt.contourJson,
            targetNotesJson: _displayAttempt.targetNotesJson,
            segmentsJson: _displayAttempt.segmentsJson,
            notes: _displayAttempt.notes,
            pitchDifficulty: _displayAttempt.pitchDifficulty,
            recorderStartSec: _displayAttempt.recorderStartSec,
            minMidi: _displayAttempt.minMidi,
            maxMidi: _displayAttempt.maxMidi,
            referenceWavPath: _displayAttempt.referenceWavPath,
            referenceSampleRate: _displayAttempt.referenceSampleRate,
            referenceWavSha1: _displayAttempt.referenceWavSha1,
            version: _displayAttempt.version,
          );
          currentAttempt = _displayAttempt;
        } catch (e) {
           debugPrint('[ReviewSummary] Error resolving draft WAV path: $e');
        }
      }

      // If NOT using a draft, try to recover/load missing data from storage
      if (widget.draft == null) {
        // 1. If we have a summary (no contourJson) or missing audio, try to load from last_take
        if (pitchJson == null || 
            _displayAttempt.recordingPath == null || 
            !File(_displayAttempt.recordingPath!).existsSync()) {
          
          final lastTake = await AttemptRepository.instance.loadLastTake(widget.exercise.id);
          
          // Check if this latest take corresponds to the attempt we're viewing
          if (lastTake != null && 
              currentAttempt.completedAt != null &&
              (lastTake.createdAt.millisecondsSinceEpoch - currentAttempt.completedAt!.millisecondsSinceEpoch).abs() < 1000) {
            _dbTake = lastTake;
            debugPrint('[ReviewSummary] Loading data from file: pitch=${lastTake.pitchPath}, audio=${lastTake.audioPath}');
            
            // Load pitch if needed
            if (pitchJson == null) {
              try {
                final file = File(lastTake.pitchPath);
                if (await file.exists()) {
                  pitchJson = await file.readAsString();
                }
              } catch (e) {
                debugPrint('[ReviewSummary] Error reading pitch file: $e');
              }
            }
          }
        }

        // 2. If still null, try falling back to legacy DB
        if (pitchJson == null) {
          debugPrint('[ReviewSummary] Fetching legacy full record for id=${currentAttempt.id}');
          final full = await AttemptRepository.instance.getFullAttempt(currentAttempt.id);
          if (full != null) {
            pitchJson = full.contourJson;
            currentAttempt = full;
          }
        }
      }

    // Parse contour data (pitch samples)
    _samples = _parseContour(pitchJson);

    // Parse target notes from saved data or build from exercise
    _targets = _parseTargetNotes(currentAttempt.targetNotesJson) ??
        await _buildTargetNotesFromExercise();

    // Parse segments
    final allSegments = _parseSegments(currentAttempt.segmentsJson);

    // Filter segments to only include those that have recorded pitch data
    // A segment is considered "recorded" if there are pitch samples within its time range
    _segments = _filterRecordedSegments(allSegments, _samples);

    // Calculate duration
    if (_samples.isNotEmpty) {
      _durationMs = _samples.map((s) => s.timeMs).reduce(math.max);
    } else if (_targets.isNotEmpty) {
      _durationMs = _targets.map((t) => t.endMs).reduce(math.max);
    } else {
      _durationMs = 6000; // Default
    }

    } catch (e, stack) {
      debugPrint('[ReviewSummary] Error loading data: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading review: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Filter segments to only include those that have recorded pitch data
  List<ExerciseSegment> _filterRecordedSegments(
    List<ExerciseSegment> allSegments,
    List<PitchSample> samples,
  ) {
    if (samples.isEmpty) return const [];

    // Find the actual recorded duration from pitch samples
    final recordedEndMs = samples.map((s) => s.timeMs).reduce(math.max);

    // Filter segments to only those that:
    // 1. Start before the recorded end time
    // 2. Have at least some pitch samples within their time range
    return allSegments.where((segment) {
      // Segment must start before recorded end (with some tolerance)
      if (segment.startMs > recordedEndMs + 500) return false;

      // Check if there are pitch samples within this segment's time range
      // Use a tolerance to account for timing differences
      const toleranceMs = 200;
      final segmentStart = segment.startMs - toleranceMs;
      final segmentEnd = segment.endMs + toleranceMs;

      final hasRecordedData = samples.any((sample) {
        return sample.timeMs >= segmentStart && sample.timeMs <= segmentEnd;
      });

      return hasRecordedData;
    }).toList();
  }

  List<PitchSample> _parseContour(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map<PitchSample>((item) {
        final map = item as Map<String, dynamic>;
        final time = (map['t'] ?? map['time'] ?? 0) as num;
        final hz = map['hz'] as num?;
        final midi = map['midi'] as num?;
        return PitchSample(
          timeMs: (time * 1000).round(),
          midi: midi?.toDouble(),
          freqHz: hz?.toDouble(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  List<TargetNote>? _parseTargetNotes(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded.map<TargetNote>((item) {
        final map = item as Map<String, dynamic>;
        return TargetNote(
          startMs: (map['startMs'] as num).toInt(),
          endMs: (map['endMs'] as num).toInt(),
          midi: (map['midi'] as num).toDouble(),
          label: map['label'] as String?,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  List<ExerciseSegment> _parseSegments(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map<ExerciseSegment>((item) {
        final map = item as Map<String, dynamic>;
        return ExerciseSegment(
          segmentIndex: (map['segmentIndex'] as num).toInt(),
          startMs: (map['startMs'] as num).toInt(),
          endMs: (map['endMs'] as num).toInt(),
          transposeSemitone: (map['transposeSemitone'] as num).toInt(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<TargetNote>> _buildTargetNotesFromExercise() async {
    // Fallback: build from exercise if target notes weren't saved
    final (lowestMidi, highestMidi) = await _vocalRangeService.getRange();
    final difficulty = _displayAttempt.pitchDifficulty != null
        ? pitchHighwayDifficultyFromName(_displayAttempt.pitchDifficulty!)
        : PitchHighwayDifficulty.medium;

    // Special handling for Sirens: use buildSirensWithVisualPath to get audio notes
    final List<ReferenceNote> notes;
    if (widget.exercise.id == 'sirens') {
      final sirenResult = await compute(
        (Map<String, dynamic> args) => TransposedExerciseBuilder.buildSirensWithVisualPath(
              exercise: args['exercise'],
              lowestMidi: args['lowestMidi'],
              highestMidi: args['highestMidi'],
              leadInSec: args['leadInSec'],
              difficulty: args['difficulty'],
            ),
        {
          'exercise': widget.exercise,
          'lowestMidi': lowestMidi,
          'highestMidi': highestMidi,
          'leadInSec': AudioConstants.leadInSec,
          'difficulty': difficulty,
        },
      );
      notes = sirenResult.audioNotes; // Get the 3 notes per cycle
    } else {
      notes = await compute(
        (Map<String, dynamic> args) => TransposedExerciseBuilder.buildTransposedSequence(
              exercise: args['exercise'],
              lowestMidi: args['lowestMidi'],
              highestMidi: args['highestMidi'],
              leadInSec: args['leadInSec'],
              difficulty: args['difficulty'],
            ),
        {
          'exercise': widget.exercise,
          'lowestMidi': lowestMidi,
          'highestMidi': highestMidi,
          'leadInSec': AudioConstants.leadInSec,
          'difficulty': difficulty,
        },
      );
    }

    return notes.map((n) {
      return TargetNote(
        startMs: (n.startSec * 1000).round(),
        endMs: (n.endSec * 1000).round(),
        midi: n.midi.toDouble(),
        label: n.lyric,
      );
    }).toList();
  }

  void _openFullReplay() {
    final take = _buildLastTake();
    if (take == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recorded take available')),
      );
      return;
    }
    
    // Default to the very beginning, but if the recording started later,
    // provide a 2s lead-in for context.
    final sliceStartSec = take.recorderStartSec ?? 0.0;
    final replayStartSec = math.max(0.0, sliceStartSec - 2.0);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PitchHighwayReviewScreen(
          exercise: widget.exercise,
          lastTake: take,
          startTimeSec: replayStartSec,
          explicitDifficulty: widget.difficulty ?? 
              (take.pitchDifficulty != null 
                  ? pitchHighwayDifficultyFromName(take.pitchDifficulty!) 
                  : null),
        ),
      ),
    );
  }

  void _openSegmentReplay(ExerciseSegment segment) {
    final take = _buildLastTake();
    if (take == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No recorded take available')),
      );
      return;
    }
    // Start 2 seconds before the segment starts (for context/lead-in)
    // But don't go below 0.0
    final segmentStartSec = segment.startMs / 1000.0;
    final segmentEndSec = segment.endMs / 1000.0;
    final replayStartSec = (segmentStartSec - 2.0).clamp(0.0, double.infinity);

    // Log segment tap
    DebugLog.event(
      LogCat.seek,
      'segment_tap',
      fields: {
        'segmentIndex': segment.segmentIndex,
        'segmentStartSec': segmentStartSec,
        'segmentEndSec': segmentEndSec,
        'replayStartSec': replayStartSec,
      },
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PitchHighwayReviewScreen(
          exercise: widget.exercise,
          lastTake: take,
          startTimeSec: replayStartSec,
          explicitDifficulty: widget.difficulty ?? 
              (take.pitchDifficulty != null 
                  ? pitchHighwayDifficultyFromName(take.pitchDifficulty!) 
                  : null),
        ),
      ),
    );
  }

  LastTake? _buildLastTake() {
    if (_samples.isEmpty) return null;
    final frames = _samples.map((s) {
      return PitchFrame(
        time: s.timeMs / 1000.0,
        hz: s.freqHz,
        midi: s.midi,
      );
    }).toList();
    return LastTake(
      exerciseId: widget.exercise.id,
      recordedAt: _displayAttempt.completedAt ?? DateTime.now(),
      frames: frames,
      durationSec: _durationMs / 1000.0,
      audioPath: _dbTake?.audioPath ?? _displayAttempt.recordingPath,
      pitchDifficulty: _displayAttempt.pitchDifficulty,
      recorderStartSec: _displayAttempt.recorderStartSec,
      minMidi: _dbTake?.minMidi ?? _displayAttempt.minMidi,
      maxMidi: _dbTake?.maxMidi ?? _displayAttempt.maxMidi,
      referenceWavPath: _dbTake?.referenceWavPath ?? _displayAttempt.referenceWavPath,
      referenceSampleRate: _dbTake?.referenceSampleRate ?? _displayAttempt.referenceSampleRate,
      referenceWavSha1: _dbTake?.referenceWavSha1 ?? _displayAttempt.referenceWavSha1,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Review: ${widget.exercise.name}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall Score
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Overall Score',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${_displayAttempt.overallScore.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Overview Graph
            const Text(
              'Overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_samples.isNotEmpty)
              OverviewGraph(
                samples: _samples,
                segments: _segments,
                durationMs: _durationMs,
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No pitch data available'),
              ),

            const SizedBox(height: 32),

            // Actions
            const Text(
              'Review Options',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _samples.isEmpty ? null : _openFullReplay,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Review Full Take'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),

            if (_segments.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Jump to Segment',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ..._segments.map((segment) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => _openSegmentReplay(segment),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _getSegmentLabel(segment),
                        ),
                        Text(
                          '${_formatTime(segment.startMs)} - ${_formatTime(segment.endMs)}',
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final totalSeconds = (ms / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _getSegmentLabel(ExerciseSegment segment) {
    // Special handling for Sirens exercise
    // Sirens have pattern: bottom note → top note → bottom note (3 notes per cycle)
    if (widget.exercise.id == 'sirens') {
      // Find target notes within this segment's time range
      final toleranceMs = 100;
      final segmentTargets = _targets.where((target) {
        final targetMid = (target.startMs + target.endMs) ~/ 2;
        return targetMid >= (segment.startMs - toleranceMs) &&
            targetMid <= (segment.endMs + toleranceMs);
      }).toList();

      if (segmentTargets.length >= 3) {
        // Sort by time to get: bottom1, top, bottom2
        segmentTargets.sort((a, b) => a.startMs.compareTo(b.startMs));
        final bottom1 = segmentTargets.first;
        final top = segmentTargets[1]; // Middle note should be the top
        final bottom2 = segmentTargets.last;

        // Verify pattern: first and last should be same MIDI, middle should be higher
        final bottom1Midi = bottom1.midi.round();
        final topMidi = top.midi.round();
        final bottom2Midi = bottom2.midi.round();

        if (bottom1Midi == bottom2Midi && topMidi > bottom1Midi) {
          final startNote = PitchMath.midiToName(bottom1Midi);
          final topNote = PitchMath.midiToName(topMidi);
          final endNote = PitchMath.midiToName(bottom2Midi);
          return '$startNote → $topNote → $endNote';
        }
      }

      // Fallback: if we can't find 3 notes, try to find at least start and top
      if (segmentTargets.length >= 2) {
        segmentTargets.sort((a, b) => a.startMs.compareTo(b.startMs));
        final firstNote = segmentTargets.first;
        final highestNote =
            segmentTargets.reduce((a, b) => a.midi > b.midi ? a : b);
        final lastNote = segmentTargets.last;

        final startNote = PitchMath.midiToName(firstNote.midi.round());
        final topNote = PitchMath.midiToName(highestNote.midi.round());
        final endNote = PitchMath.midiToName(lastNote.midi.round());

        // If first and last are the same, show start → top → end
        if (firstNote.midi.round() == lastNote.midi.round()) {
          return '$startNote → $topNote → $endNote';
        }
      }

      // Final fallback: show start → end
      if (segmentTargets.isNotEmpty) {
        segmentTargets.sort((a, b) => a.startMs.compareTo(b.startMs));
        final firstNote = segmentTargets.first;
        final lastNote = segmentTargets.last;
        final startNote = PitchMath.midiToName(firstNote.midi.round());
        final endNote = PitchMath.midiToName(lastNote.midi.round());
        return '$startNote → $endNote';
      }
    }

    // Special handling for Octave Slides and NG Slides exercises
    // Both have pattern: bottom note, 1s silence, top note
    // But segments might be split at the silence gap, so we need to look for adjacent segments
    final isOctaveSlides = widget.exercise.id == 'octave_slides';
    final isNgSlides = widget.exercise.id == 'ng_slides';

    if (isOctaveSlides || isNgSlides) {
      // Find target notes within this segment's time range
      final toleranceMs = 100;
      final segmentTargets = _targets.where((target) {
        final targetMid = (target.startMs + target.endMs) ~/ 2;
        return targetMid >= (segment.startMs - toleranceMs) &&
            targetMid <= (segment.endMs + toleranceMs);
      }).toList();

      // For octave slides, also check the next segment (if it exists) to find the top note
      // Segments are likely split: first segment = bottom note, second segment = top note
      final segmentIndex = _segments.indexOf(segment);
      if (segmentIndex >= 0 && segmentIndex < _segments.length - 1) {
        final nextSegment = _segments[segmentIndex + 1];
        // Check if next segment is close in time (within 3 seconds) and has same transposition
        // This indicates it's part of the same octave slide pattern
        final timeGap = nextSegment.startMs - segment.endMs;
        if (timeGap < 3000 &&
            nextSegment.transposeSemitone == segment.transposeSemitone) {
          final nextSegmentTargets = _targets.where((target) {
            final targetMid = (target.startMs + target.endMs) ~/ 2;
            return targetMid >= (nextSegment.startMs - toleranceMs) &&
                targetMid <= (nextSegment.endMs + toleranceMs);
          }).toList();

          if (segmentTargets.isNotEmpty && nextSegmentTargets.isNotEmpty) {
            // Combine both segments to find bottom and top notes
            final allTargets = [...segmentTargets, ...nextSegmentTargets];
            allTargets.sort((a, b) => a.startMs.compareTo(b.startMs));
            final firstNote = allTargets.first;
            final lastNote = allTargets.last;

            if (isOctaveSlides) {
              // Verify they're an octave apart (or close to it)
              final midiDiff = (lastNote.midi - firstNote.midi).abs();
              if (midiDiff >= 10 && midiDiff <= 14) {
                // Octave is 12 semitones, allow some tolerance
                final startNote = PitchMath.midiToName(firstNote.midi.round());
                final endNote = PitchMath.midiToName(lastNote.midi.round());
                return '$startNote → $endNote';
              }
            } else if (isNgSlides) {
              // For NG slides, just verify the top note is higher
              if (lastNote.midi > firstNote.midi) {
                final startNote = PitchMath.midiToName(firstNote.midi.round());
                final endNote = PitchMath.midiToName(lastNote.midi.round());
                return '$startNote → $endNote';
              }
            }
          }
        }
      }

      // If segments are combined (single segment contains both notes), find bottom and top
      if (segmentTargets.length >= 2) {
        segmentTargets.sort((a, b) => a.startMs.compareTo(b.startMs));
        final firstNote = segmentTargets.first;
        final lastNote = segmentTargets.last;

        // Verify the pattern: first note should be lower than last note
        if (lastNote.midi > firstNote.midi) {
          final startNote = PitchMath.midiToName(firstNote.midi.round());
          final endNote = PitchMath.midiToName(lastNote.midi.round());
          return '$startNote → $endNote';
        }
      }

      // Fallback: if we can't find the pattern, use the segment's own notes
      if (segmentTargets.isNotEmpty) {
        segmentTargets.sort((a, b) => a.startMs.compareTo(b.startMs));
        final firstNote = segmentTargets.first;
        final lastNote = segmentTargets.last;
        final startNote = PitchMath.midiToName(firstNote.midi.round());
        final endNote = PitchMath.midiToName(lastNote.midi.round());
        return '$startNote → $endNote';
      }
    }

    // Standard handling for other exercises
    // Find target notes within this segment's time range
    final toleranceMs = 100;
    final segmentTargets = _targets.where((target) {
      final targetMid = (target.startMs + target.endMs) ~/ 2;
      return targetMid >= (segment.startMs - toleranceMs) &&
          targetMid <= (segment.endMs + toleranceMs);
    }).toList();

    if (segmentTargets.isEmpty) {
      // Fallback: use transposition to estimate based on exercise pattern
      // Use default base MIDI (C4 = 60) if range not available
      const baseMidi = 60;
      final startMidi = baseMidi + segment.transposeSemitone;
      // Estimate pattern spans ~7 semitones (typical scale fragment)
      final endMidi = startMidi + 7;
      return '${PitchMath.midiToName(startMidi)} → ${PitchMath.midiToName(endMidi)}';
    }

    // Get first note (by time) and highest note (by MIDI) in segment
    segmentTargets.sort((a, b) => a.startMs.compareTo(b.startMs));
    final firstNote = segmentTargets.first;
    final highestNote =
        segmentTargets.reduce((a, b) => a.midi > b.midi ? a : b);
    final lastNote = segmentTargets.last;

    // Use first note as start, and prefer highest note as end (for ascending patterns)
    // but fall back to last note if highest is not significantly higher
    final startNote = PitchMath.midiToName(firstNote.midi.round());
    final endMidi = (highestNote.midi - lastNote.midi).abs() < 2
        ? lastNote.midi // If highest and last are close, use last
        : highestNote.midi; // Otherwise use highest
    final endNote = PitchMath.midiToName(endMidi.round());

    return '$startNote → $endNote';
  }
}

class ExerciseSegment {
  final int segmentIndex;
  final int startMs;
  final int endMs;
  final int transposeSemitone;

  const ExerciseSegment({
    required this.segmentIndex,
    required this.startMs,
    required this.endMs,
    required this.transposeSemitone,
  });
}



class _DetailGraph extends StatefulWidget {
  final List<PitchSample> samples;
  final List<TargetNote> targets;
  final int durationMs;

  const _DetailGraph({
    required this.samples,
    required this.targets,
    required this.durationMs,
  });

  @override
  State<_DetailGraph> createState() => _DetailGraphState();
}

class _DetailGraphState extends State<_DetailGraph> {
  bool _showTargets = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.samples.isEmpty) return const SizedBox.shrink();

    // Compute viewport from samples
    final sampleMidis = widget.samples
        .map((s) =>
            s.midi ?? (s.freqHz != null ? PitchMath.hzToMidi(s.freqHz!) : null))
        .whereType<double>()
        .toList();
    if (sampleMidis.isEmpty) return const SizedBox.shrink();

    final minMidi = sampleMidis.reduce(math.min) - 3;
    final maxMidi = sampleMidis.reduce(math.max) + 3;

    // Smooth samples
    final smoothed = _smoothSamples(widget.samples);

    // Calculate width for full duration (e.g., 100 pixels per second)
    const pixelsPerSecond = 100.0;
    final graphWidth = (widget.durationMs / 1000.0) * pixelsPerSecond;
    final actualWidth = math.max(MediaQuery.of(context).size.width, graphWidth);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: const Color(0xFFF0F3F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle for showing targets
          Row(
            children: [
              Switch(
                value: _showTargets,
                onChanged: (value) => setState(() => _showTargets = value),
              ),
              const Text('Show Targets'),
            ],
          ),
          const SizedBox(height: 8),
          // Scrollable detail graph
          SizedBox(
            height: 300,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: actualWidth,
                child: CustomPaint(
                  size: Size(actualWidth, 300),
                  painter: _DetailGraphPainter(
                    samples: smoothed,
                    targets: _showTargets ? widget.targets : const [],
                    durationMs: widget.durationMs,
                    minMidi: minMidi,
                    maxMidi: maxMidi,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<PitchSample> _smoothSamples(List<PitchSample> samples) {
    if (samples.length < 3) return samples;
    final smoothed = <PitchSample>[];
    for (var i = 0; i < samples.length; i++) {
      final midi = samples[i].midi ??
          (samples[i].freqHz != null
              ? PitchMath.hzToMidi(samples[i].freqHz!)
              : null);
      if (midi == null) continue;

      // Simple moving average with window of 3
      var sum = midi;
      var count = 1;
      if (i > 0) {
        final prevMidi = samples[i - 1].midi ??
            (samples[i - 1].freqHz != null
                ? PitchMath.hzToMidi(samples[i - 1].freqHz!)
                : null);
        if (prevMidi != null) {
          sum += prevMidi;
          count++;
        }
      }
      if (i < samples.length - 1) {
        final nextMidi = samples[i + 1].midi ??
            (samples[i + 1].freqHz != null
                ? PitchMath.hzToMidi(samples[i + 1].freqHz!)
                : null);
        if (nextMidi != null) {
          sum += nextMidi;
          count++;
        }
      }

      smoothed.add(PitchSample(
        timeMs: samples[i].timeMs,
        midi: sum / count,
        freqHz: samples[i].freqHz,
      ));
    }
    return smoothed;
  }
}

class _DetailGraphPainter extends CustomPainter {
  final List<PitchSample> samples;
  final List<TargetNote> targets;
  final int durationMs;
  final double minMidi;
  final double maxMidi;

  _DetailGraphPainter({
    required this.samples,
    required this.targets,
    required this.durationMs,
    required this.minMidi,
    required this.maxMidi,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 8.0;
    const bottomPad = 8.0;

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFE6EEF3)
      ..strokeWidth = 1;
    for (var i = 0; i <= 6; i++) {
      final midi = minMidi + (maxMidi - minMidi) * (i / 6);
      final y =
          _midiToY(midi, minMidi, maxMidi, size.height, topPad, bottomPad);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Target bands (faint, if enabled)
    if (targets.isNotEmpty) {
      final targetPaint = Paint()
        ..color = const Color(0x1AFFD6A1) // Very faint
        ..style = PaintingStyle.fill;

      for (final target in targets) {
        final startX = (target.startMs / durationMs) * size.width;
        final endX = (target.endMs / durationMs) * size.width;
        final y = _midiToY(
            target.midi, minMidi, maxMidi, size.height, topPad, bottomPad);
        final bandHeight = 8.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                startX, y - bandHeight / 2, endX - startX, bandHeight),
            const Radius.circular(2),
          ),
          targetPaint,
        );
      }
    }

    // Pitch contour line
    final path = Path();
    bool started = false;

    for (final s in samples) {
      final midi =
          s.midi ?? (s.freqHz != null ? PitchMath.hzToMidi(s.freqHz!) : null);
      if (midi == null || !midi.isFinite) continue;

      final x = (s.timeMs / durationMs) * size.width;
      final y =
          _midiToY(midi, minMidi, maxMidi, size.height, topPad, bottomPad);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    final contourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFB347);
    canvas.drawPath(path, contourPaint);
  }

  @override
  bool shouldRepaint(covariant _DetailGraphPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.targets != targets ||
        oldDelegate.durationMs != durationMs ||
        oldDelegate.minMidi != minMidi ||
        oldDelegate.maxMidi != maxMidi;
  }

  double _midiToY(double midi, double minMidi, double maxMidi, double height,
      double topPad, double bottomPad) {
    final clamped = midi.clamp(minMidi, maxMidi);
    final usableHeight = (height - topPad - bottomPad).clamp(1.0, height);
    final ratio = (clamped - minMidi) / (maxMidi - minMidi);
    return (height - bottomPad) - ratio * usableHeight;
  }
}
