import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../data/progress_repository.dart';
import '../../models/exercise_attempt.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../models/reference_note.dart';
import '../../models/vocal_exercise.dart';
import '../../models/exercise_level_progress.dart';
import '../../services/exercise_repository.dart';
import '../../services/audio_synth_service.dart';
import '../../services/sine_preview_audio_generator.dart';
import '../../services/exercise_metadata.dart';
import '../../services/exercise_level_progress_repository.dart';
import '../../utils/pitch_highway_tempo.dart';
import '../widgets/exercise_icon.dart';
import 'exercise_player_screen.dart';
import 'exercise_navigation.dart';
import 'exercise_review_summary_screen.dart';
import '../../services/attempt_repository.dart';

class ExerciseInfoScreen extends StatefulWidget {
  final String exerciseId;

  const ExerciseInfoScreen({super.key, required this.exerciseId});

  @override
  State<ExerciseInfoScreen> createState() => _ExerciseInfoScreenState();
}

class _ExerciseInfoScreenState extends State<ExerciseInfoScreen> {
  final _repo = ExerciseRepository();
  final _progress = ProgressRepository();
  final _attempts = AttemptRepository.instance;
  final AudioSynthService _synth = AudioSynthService();
  final SinePreviewAudioGenerator _previewGenerator = SinePreviewAudioGenerator();
  StreamSubscription<void>? _previewCompleteSub;
  final ExerciseLevelProgressRepository _levelProgress =
      ExerciseLevelProgressRepository();
  int _highestUnlockedLevel = ExerciseLevelProgress.minLevel;
  int _selectedLevel = ExerciseLevelProgress.minLevel;
  int? _highlightedLevel;
  Map<int, int> _bestScoresByLevel = const <int, int>{};
  bool _progressLoaded = false;
  double? _lastScore;
  ExerciseAttempt? _latestAttempt;

  @override
  void initState() {
    super.initState();
    _loadLastScore();
    _loadLatestAttempt();
    _loadProgress();
  }

  @override
  void dispose() {
    _previewCompleteSub?.cancel();
    _synth.dispose();
    super.dispose();
  }

  Future<void> _loadLastScore() async {
    final attempts = await _progress.fetchAttemptsForExercise(widget.exerciseId);
    if (!mounted) return;
    if (attempts.isEmpty) {
      setState(() => _lastScore = null);
      return;
    }
    attempts.sort((a, b) {
      final aTime = a.completedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.completedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    setState(() => _lastScore = attempts.first.overallScore);
  }

  Future<void> _loadLatestAttempt() async {
    // Ensure attempts are loaded from database
    await _attempts.ensureLoaded();
    if (!mounted) return;
    // Query most recent session by exerciseId (resilient to re-entry)
    final latest = _attempts.latestFor(widget.exerciseId);
    setState(() {
      _latestAttempt = latest;
    });
  }

  Future<void> _loadProgress({bool showToast = false}) async {
    final progress = await _levelProgress.getExerciseProgress(widget.exerciseId);
    if (!mounted) return;
    final previousHighest = _highestUnlockedLevel;
    final nextHighest = progress.highestUnlockedLevel;
    var nextSelected = _selectedLevel;
    if (!_progressLoaded || nextSelected > nextHighest || nextSelected < 1) {
      final preferred = progress.lastSelectedLevel;
      if (preferred != null &&
          preferred >= ExerciseLevelProgress.minLevel &&
          preferred <= nextHighest) {
        nextSelected = preferred;
      } else {
        nextSelected = nextHighest;
      }
    } else if (showToast && nextHighest > previousHighest && nextSelected == previousHighest) {
      nextSelected = nextHighest;
    }
    final levelUp = showToast && nextHighest > previousHighest;
    setState(() {
      _highestUnlockedLevel = nextHighest;
      _bestScoresByLevel = progress.bestScoreByLevel;
      _progressLoaded = true;
      _highlightedLevel = levelUp ? nextHighest : null;
      _selectedLevel = nextSelected;
    });
    if (levelUp && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Level up! Level $nextHighest unlocked.')),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        setState(() => _highlightedLevel = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercise = _repo.getExercise(widget.exerciseId);
    final durationSeconds = exercise.durationSeconds;
    final timeChip = durationSeconds != null
        ? (durationSeconds < 60
            ? '${durationSeconds}s'
            : '${exercise.estimatedMinutes} min')
        : (exercise.reps != null ? '${exercise.reps} reps' : '—');
    final typeLabel = _typeLabel(exercise.type);
    final isPitchHighway = exercise.type == ExerciseType.pitchHighway;
    final metadata = ExerciseMetadata.forExercise(exercise);
    final canPreviewAudio = metadata.previewSupported;
    final canReview = isPitchHighway && _latestAttempt != null;
    final selectionLocked = isPitchHighway && _selectedLevel > _highestUnlockedLevel;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(exercise.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              ExerciseIcon(iconKey: exercise.iconKey, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(exercise.name,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(label: typeLabel),
              _InfoChip(label: _difficultyLabel(exercise.difficulty)),
              _InfoChip(label: timeChip),
            ],
          ),
          if (isPitchHighway) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Difficulty Level'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(3, (index) {
                final level = index + 1;
                final unlocked = level <= _highestUnlockedLevel;
                final selected = _selectedLevel == level;
                final highlighted = _highlightedLevel == level;
                final best = _bestScoresByLevel[level];
                final label = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Level $level'),
                    if (!unlocked) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock, size: 14, color: Colors.grey[600]),
                    ],
                  ],
                );
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: highlighted ? Colors.amber.withOpacity(0.2) : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChoiceChip(
                        label: label,
                        selected: selected,
                        onSelected: unlocked
                            ? (_) {
                                setState(() => _selectedLevel = level);
                                _levelProgress.setLastSelectedLevel(
                                  exerciseId: widget.exerciseId,
                                  level: level,
                                );
                              }
                            : null,
                        labelStyle: unlocked
                            ? null
                            : Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(color: Colors.grey[500]),
                      ),
                      if (best != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Best $best%',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                      if (!unlocked)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Score 90%+ on previous level to unlock',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey[600]),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: 16),
          _SectionHeader(title: 'How to do it'),
          Text(exercise.description),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Purpose'),
          Text(exercise.purpose),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Targets'),
          ..._targetsForExercise(exercise)
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $t'),
                  ))
              .toList(),
          const SizedBox(height: 12),
          _SectionHeader(title: 'Tags'),
          Wrap(
            spacing: 8,
            children: exercise.tags.map((t) => Chip(label: Text(t))).toList(),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: canPreviewAudio ? () => _playPreview(exercise) : null,
            icon: const Icon(Icons.volume_up),
            label: const Text('Preview Exercise'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: selectionLocked
                ? null
                : () async {
                    final tapTime = DateTime.now();
                    debugPrint('[StartExercise] tapped at ${tapTime.millisecondsSinceEpoch}');
                    await _synth.stop();
                    final afterStop = DateTime.now();
                    debugPrint('[StartExercise] after stop: ${afterStop.difference(tapTime).inMilliseconds}ms');
                    await _startExercise(exercise);
                    final afterStart = DateTime.now();
                    debugPrint('[StartExercise] after _startExercise: ${afterStart.difference(tapTime).inMilliseconds}ms');
                    await _loadLastScore();
                    await _loadLatestAttempt();
                    await _loadProgress(showToast: true);
                  },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Exercise'),
          ),
          if (exercise.type == ExerciseType.pitchHighway) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: canReview
                  ? () {
                      // Navigate directly to Detailed Review (ExerciseReviewSummaryScreen)
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExerciseReviewSummaryScreen(
                            exercise: exercise,
                            attempt: _latestAttempt!,
                          ),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.replay),
              label: const Text('Review last take'),
            ),
            if (!canReview)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No take recorded yet.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          const SizedBox(height: 16),
          Text(
            'Last score: ${_lastScore?.toStringAsFixed(0) ?? '—'}%',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _startExercise(VocalExercise exercise) async {
    final startTime = DateTime.now();
    debugPrint('[StartExercise] _startExercise called at ${startTime.millisecondsSinceEpoch}');
    
    // Navigate immediately - move heavy work to the exercise screen
    final selectedDifficulty = pitchHighwayDifficultyFromLevel(_selectedLevel);
    final beforeNav = DateTime.now();
    debugPrint('[StartExercise] before Navigator.push: ${beforeNav.difference(startTime).inMilliseconds}ms');
    
    if (exercise.type == ExerciseType.pitchHighway) {
      // Save level selection (lightweight DB write, but don't block navigation)
      unawaited(_levelProgress.setLastSelectedLevel(
        exerciseId: widget.exerciseId,
        level: _selectedLevel,
      ));
      
      // Navigate immediately with original exercise - let the player screen handle range loading
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExercisePlayerScreen(
            exercise: exercise,
              pitchDifficulty: selectedDifficulty,
            ),
          ),
        );
      final afterNav = DateTime.now();
      debugPrint('[StartExercise] after Navigator.push completed: ${afterNav.difference(startTime).inMilliseconds}ms');
        return;
    }
    
    // For non-pitchHighway exercises, navigate immediately
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => buildExerciseScreen(
          exercise,
          pitchDifficulty: selectedDifficulty,
        ),
      ),
    );
    final afterNav = DateTime.now();
    debugPrint('[StartExercise] after Navigator.push completed: ${afterNav.difference(startTime).inMilliseconds}ms');
  }


  List<String> _targetsForExercise(VocalExercise exercise) {
    if (exercise.type == ExerciseType.pitchHighway &&
        exercise.highwaySpec?.segments.isNotEmpty == true) {
      final tol = exercise.highwaySpec!.segments.first.toleranceCents.round();
      return ['Pitch accuracy ±$tol cents', 'Stay centered on each note'];
    }
    if (exercise.type == ExerciseType.sustainedPitchHold) {
      return ['Hold within ±25 cents', 'Maintain stability for 3 seconds'];
    }
    if (exercise.type == ExerciseType.dynamicsRamp) {
      return ['Match the loudness ramp', 'Keep tone stable'];
    }
    if (exercise.type == ExerciseType.pitchMatchListening) {
      return ['Match the reference pitch', 'Listen then sing'];
    }
    if (exercise.type == ExerciseType.breathTimer ||
        exercise.type == ExerciseType.sovtTimer ||
        exercise.type == ExerciseType.cooldownRecovery) {
      return ['Complete the full timer cycle', 'Maintain steady airflow'];
    }
    return ['Follow the on-screen guidance'];
  }

  String _difficultyLabel(ExerciseDifficulty difficulty) {
    return switch (difficulty) {
      ExerciseDifficulty.beginner => 'Beginner',
      ExerciseDifficulty.intermediate => 'Intermediate',
      ExerciseDifficulty.advanced => 'Advanced',
    };
  }

  String _typeLabel(ExerciseType type) {
    return switch (type) {
      ExerciseType.pitchHighway => 'Pitch Highway',
      ExerciseType.breathTimer => 'Breath Timer',
      ExerciseType.sovtTimer => 'SOVT Timer',
      ExerciseType.sustainedPitchHold => 'Sustained Hold',
      ExerciseType.pitchMatchListening => 'Pitch Match',
      ExerciseType.articulationRhythm => 'Articulation Rhythm',
      ExerciseType.dynamicsRamp => 'Dynamics Ramp',
      ExerciseType.cooldownRecovery => 'Recovery',
    };
  }

  Future<void> _playPreview(VocalExercise exercise) async {
    debugPrint('[Preview] start - exercise=${exercise.id}');
    
    try {
      final metadata = ExerciseMetadata.forExercise(exercise);
      
      // Check if preview is supported
      if (!metadata.previewSupported) {
        if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No preview available for this exercise.')),
      );
        }
      return;
    }

      // Stop any existing playback
    await _synth.stop();
      _previewCompleteSub?.cancel();

      String? previewPath;
      final difficulty = pitchHighwayDifficultyFromLevel(_selectedLevel);
      final multiplier = PitchHighwayTempo.multiplierFor(
        difficulty,
        exercise.highwaySpec?.segments ?? [],
      );
      final scaledSegments = PitchHighwayTempo.scaleSegments(
        exercise.highwaySpec?.segments ?? [],
        multiplier,
      );

      // Use sine preview generator for glides
      if (metadata.previewAudioStyle == PreviewAudioStyle.sineSweep) {
        // Only for yawn-sigh preview (which should be a glide)
        if (exercise.id == 'yawn_sigh') {
          // Yawn-sigh: descending glide preview (timer-based exercise, no highwaySpec)
          // Generate a descending glide from C5 to C4 over 2 seconds
          const previewStartMidi = 72.0; // C5
          const previewEndMidi = 60.0; // C4
          const durationMs = 2000; // 2 seconds for the glide
          previewPath = await _previewGenerator.generateSweepWav(
            startMidi: previewStartMidi,
            endMidi: previewEndMidi,
            durationMs: durationMs,
            leadInMs: 2000,
            fadeMs: 10,
          );
          debugPrint('[Preview] Yawn-sigh descending glide C5->C4 ${durationMs}ms');
        } else {
          // Generic glide: single sweep (for other exercises that use sweeps)
          final glideSegments = scaledSegments.where((s) => s.isGlide).toList();
          if (glideSegments.isNotEmpty) {
            final glide = glideSegments.first;
            final startMidi = (glide.startMidi ?? glide.midiNote).toDouble();
            final endMidi = (glide.endMidi ?? glide.midiNote).toDouble();
            final durationMs = glide.endMs - glide.startMs;
            previewPath = await _previewGenerator.generateSweepWav(
              startMidi: startMidi,
              endMidi: endMidi,
              durationMs: durationMs,
              leadInMs: 2000,
              fadeMs: 10,
            );
          }
        }
      } else if (metadata.previewAudioStyle == PreviewAudioStyle.sineTone) {
        // For exercises that need discrete tones (NG Slides, Sirens, Fast 3-note, etc.)
        if (exercise.id == 'ng_slides') {
          // NG Slides: discrete notes only (bottom + top), matching Octave Slides
          final segments = scaledSegments;
          if (segments.length >= 2) {
            final bottomNote = segments[0];
            final topNote = segments[1];
            previewPath = await _previewGenerator.generateCompositeWav(
              segments: [
                CompositeSegment.tone(
                  midi: bottomNote.midiNote.toDouble(),
                  durationSeconds: (bottomNote.endMs - bottomNote.startMs) / 1000.0,
                ),
                CompositeSegment.silence(durationSeconds: 1.0), // 1s silence
                CompositeSegment.tone(
                  midi: topNote.midiNote.toDouble(),
                  durationSeconds: (topNote.endMs - topNote.startMs) / 1000.0,
                ),
              ],
              leadInMs: 2000,
            );
            debugPrint('[Preview] NG Slides: bottom note ${bottomNote.midiNote}, top note ${topNote.midiNote}');
          }
        } else if (exercise.id == 'sirens') {
          // Sirens: continuous sine wave glide up then down
          final segments = scaledSegments;
          if (segments.length >= 3) {
            final bottom1 = segments[0];
            final top = segments[1];
            final bottom2 = segments[2];
            final bottomMidi = bottom1.midiNote.toDouble();
            final topMidi = top.midiNote.toDouble();
            // Calculate durations from segments
            final upDuration = (top.endMs - bottom1.startMs) / 1000.0;
            final downDuration = (bottom2.endMs - top.startMs) / 1000.0;
            
            previewPath = await _previewGenerator.generateCompositeWav(
              segments: [
                CompositeSegment.sweep(
                  startMidi: bottomMidi,
                  endMidi: topMidi,
                  durationSeconds: upDuration,
                ),
                CompositeSegment.sweep(
                  startMidi: topMidi,
                  endMidi: bottomMidi,
                  durationSeconds: downDuration,
                ),
                CompositeSegment.silence(durationSeconds: 2.0), // 2s rest between cycles
              ],
              leadInMs: 2000,
            );
            debugPrint('[Preview] Sirens: continuous glide ${bottomMidi.toInt()} → ${topMidi.toInt()} → ${bottomMidi.toInt()}, 2s rest');
          }
        } else if (exercise.id == 'interval_training') {
          // TODO: Next release - Expand interval logic, multiple interval types, proper preview coverage
          // Generate preview with a sample interval (perfect 5th = 7 semitones)
          // Generate preview with a sample interval (perfect 5th = 7 semitones)
          const rootMidi = 60.0; // C4
          const intervalSemitones = 7; // Perfect 5th
          const intervalMidi = rootMidi + intervalSemitones;
          previewPath = await _previewGenerator.generateCompositeWav(
            segments: [
              CompositeSegment.tone(midi: rootMidi, durationSeconds: 1.0),
              CompositeSegment.silence(durationSeconds: 0.2),
              CompositeSegment.tone(midi: intervalMidi, durationSeconds: 1.0),
            ],
            leadInMs: 2000,
          );
          debugPrint('[Preview] Generated interval training preview: C4 -> G4');
        } else if (exercise.id == 'sustained_pitch_holds') {
          // TODO: Next release - Multi-note progression, review screen, improved flow
          // Generate a single steady tone for the hold duration (3 seconds)
          const targetMidi = 60.0; // C4
          const holdDurationMs = 3000; // 3 seconds
          previewPath = await _previewGenerator.generateToneWav(
            noteMidi: targetMidi,
            durationMs: holdDurationMs,
            leadInMs: 2000,
            fadeMs: 50, // Longer fade for smooth ending
          );
          debugPrint('[Preview] segment 1/1 - Sustained Pitch Hold ${holdDurationMs}ms');
        } else if (exercise.id == 'fast_three_note_patterns') {
          // Generate tones for each note in the pattern
          final segments = scaledSegments.take(9).toList(); // Take full pattern
          final compositeSegments = <CompositeSegment>[];
          for (var i = 0; i < segments.length; i++) {
            final seg = segments[i];
        final durationMs = seg.endMs - seg.startMs;
            compositeSegments.add(CompositeSegment.tone(
              midi: seg.midiNote.toDouble(),
              durationSeconds: durationMs / 1000.0,
            ));
            debugPrint('[Preview] segment ${i + 1}/${segments.length} - note ${seg.midiNote}');
          }
          previewPath = await _previewGenerator.generateCompositeWav(
            segments: compositeSegments,
            leadInMs: 2000,
          );
        } else {
          // Fallback: use regular note rendering
          final segments = scaledSegments.take(8).toList();
          final notes = segments.map((s) => ReferenceNote(
            startSec: s.startMs / 1000.0,
            endSec: s.endMs / 1000.0,
            midi: s.midiNote,
          )).toList();
          previewPath = await _synth.renderReferenceNotes(notes);
        }
      } else {
        // Regular note-based preview (discrete notes, not glides)
        final segments = scaledSegments; // Play ALL segments, not just first 8
        final notes = segments.map((s) => ReferenceNote(
          startSec: s.startMs / 1000.0,
          endSec: s.endMs / 1000.0,
          midi: s.midiNote,
        )).toList();
        debugPrint('[Preview] segment 1/${segments.length} - regular notes, total=${segments.length}');
        if (exercise.id == 'vv_zz_scales') {
          // Vv/Zz: ensure all segments are played with debug logs
          for (var i = 0; i < notes.length; i++) {
            debugPrint('[Preview] segment ${i + 1}/${notes.length} - Vv/Zz note ${notes[i].midi}');
          }
        }
        previewPath = await _synth.renderReferenceNotes(notes);
      }

      if (previewPath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to generate preview')),
          );
        }
      return;
      }

      // Play the preview and wait for completion
      await _synth.playFile(previewPath);
      
      // Wait for playback to complete
      final completer = Completer<void>();
      _previewCompleteSub = _synth.onComplete.listen((_) {
        debugPrint('[Preview] complete');
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      
      // Also set a timeout as fallback (audio duration + 500ms buffer)
      final timeout = Duration(milliseconds: 10000); // 10s max
      await completer.future.timeout(timeout, onTimeout: () {
        debugPrint('[Preview] timeout - forcing completion');
      });
      
    } catch (e) {
      debugPrint('[Preview] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Preview failed: $e')),
        );
      }
    } finally {
      _previewCompleteSub?.cancel();
      _previewCompleteSub = null;
      debugPrint('[Preview] end - state reset');
    }
  }

}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
