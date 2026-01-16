import 'package:flutter/material.dart';

import '../../models/vocal_exercise.dart';
import '../../models/exercise_attempt.dart';
import '../../routing/exercise_route_registry.dart';
import '../../services/attempt_repository.dart';
import '../../services/exercise_level_progress_repository.dart';
import '../../services/exercise_repository.dart';
import '../../services/audio_synth_service.dart';
import '../../widgets/banner_card.dart';
import '../../ui/screens/exercise_review_summary_screen.dart';
import '../../models/reference_note.dart';
import '../../services/sine_preview_audio_generator.dart';
import '../../services/exercise_metadata.dart';
import 'dart:async';
import '../../ui/route_observer.dart';
import '../../models/exercise_level_progress.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../utils/pitch_highway_tempo.dart';

class ExercisePreviewScreen extends StatefulWidget {
  final String exerciseId;

  const ExercisePreviewScreen({super.key, required this.exerciseId});

  @override
  State<ExercisePreviewScreen> createState() => _ExercisePreviewScreenState();
}

class _ExercisePreviewScreenState extends State<ExercisePreviewScreen>
    with RouteAware {
  final ExerciseRepository _repo = ExerciseRepository();
  final AttemptRepository _attempts = AttemptRepository.instance;
  final ExerciseLevelProgressRepository _levelProgress =
      ExerciseLevelProgressRepository();
  final AudioSynthService _synth = AudioSynthService();
  final SinePreviewAudioGenerator _previewGenerator =
      SinePreviewAudioGenerator();
  StreamSubscription<void>? _previewCompleteSub;
  VocalExercise? _exercise;
  ExerciseAttemptInfo? _latest;
  bool _loading = true;
  bool _previewing = false;
  int _highestUnlockedLevel = ExerciseLevelProgress.minLevel;
  int _selectedLevel = ExerciseLevelProgress.minLevel;
  int? _highlightedLevel;
  Map<int, int> _bestScoresByLevel = const <int, int>{};
  bool _progressLoaded = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[Preview] exerciseId=${widget.exerciseId}');
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _previewCompleteSub?.cancel();
    _synth.stop();
    super.dispose();
  }

  @override
  void didPopNext() {
    _refreshLatest();
    _refreshProgress(showToast: true);
  }

  Future<void> _load() async {
    final ex = _repo.getExercises().firstWhere(
          (e) => e.id == widget.exerciseId,
          orElse: () => _repo.getExercises().first,
        );
    await _refreshProgress();
    // Only ensure loaded, don't refresh - use cache which is already up to date
    await _attempts.ensureLoaded();
    final latest = _attempts.latestFor(widget.exerciseId);
    if (latest == null) {
      debugPrint('[Preview] latest attempt not found for ${widget.exerciseId}');
    }
    if (!mounted) return;
    setState(() {
      _exercise = ex;
      _latest = latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest);
      _loading = false;
    });
  }

  Future<void> _refreshLatest() async {
    // Use cache - it's already updated by AttemptRepository.save()
    // No need to refresh from database
    final latest = _attempts.latestFor(widget.exerciseId);
    if (!mounted) return;
    setState(() {
      _latest = latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest);
    });
  }

  Future<void> _refreshProgress({bool showToast = false}) async {
    final progress =
        await _levelProgress.getExerciseProgress(widget.exerciseId);
    if (!mounted) return;
    final previousHighest = _highestUnlockedLevel;
    final nextHighest = progress.highestUnlockedLevel;
    var nextSelected = _selectedLevel;
    if (!_progressLoaded ||
        nextSelected > nextHighest ||
        nextSelected < ExerciseLevelProgress.minLevel) {
      final preferred = progress.lastSelectedLevel;
      if (preferred != null &&
          preferred >= ExerciseLevelProgress.minLevel &&
          preferred <= nextHighest) {
        nextSelected = preferred;
      } else {
        nextSelected = nextHighest;
      }
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
    final ex = _exercise;
    // Get category name for AppBar
    String? categoryTitle;
    if (ex != null) {
      try {
        categoryTitle = _repo.getCategory(ex.categoryId).title;
      } catch (e) {
        // Fallback if category not found
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(categoryTitle ?? 'Exercise')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (ex != null) _Header(ex: ex),
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Purpose',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.purpose ??
                            ex?.description ??
                            'Build control and accuracy.'),
                        const SizedBox(height: 16),
                        const Text('How it works',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(ex?.description ??
                            'Follow along and match the guide.'),
                      ],
                    ),
                  ),
                ),
                if (ex != null &&
                    ExerciseMetadata.forExercise(ex).previewSupported) ...[
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Preview',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(ex.description),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed:
                                    _previewing ? null : () => _playPreview(ex),
                                icon: Icon(_previewing
                                    ? Icons.pause
                                    : Icons.play_arrow),
                                label: Text(
                                    _previewing ? 'Playing…' : 'Play preview'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (ex?.usesPitchHighway == true) ...[
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Difficulty',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
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
                              final difficulty =
                                  pitchHighwayDifficultyFromLevel(level);
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: highlighted
                                      ? Colors.amber.withOpacity(0.2)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ChoiceChip(
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Level $level'),
                                          if (!unlocked) ...[
                                            const SizedBox(width: 6),
                                            Icon(Icons.lock,
                                                size: 14,
                                                color: Colors.grey[600]),
                                          ],
                                        ],
                                      ),
                                      selected: selected,
                                      onSelected: unlocked
                                          ? (_) async {
                                              setState(
                                                  () => _selectedLevel = level);
                                              await _levelProgress
                                                  .setLastSelectedLevel(
                                                exerciseId: widget.exerciseId,
                                                level: level,
                                              );
                                            }
                                          : null,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      pitchHighwayDifficultySpeedLabel(
                                          difficulty),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                    if (best != null)
                                      Text(
                                        'Best: $best%',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey[600]),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ),
                          if (_highestUnlockedLevel <
                              ExerciseLevelProgress.maxLevel)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Score 90%+ on the previous level to unlock.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _startExercise,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Start Exercise'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _latest == null ? null : _reviewLast,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Review last take'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_latest != null)
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      title: Text(
                          'Last score: ${_latest!.score.toStringAsFixed(0)}'),
                      subtitle: Text('Completed ${_latest!.dateLabel}'),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _startExercise() async {
    // Stop preview immediately when starting exercise
    await _synth.stop();
    if (mounted) {
      setState(() => _previewing = false);
    }

    if (_exercise?.usesPitchHighway == true) {
      await _levelProgress.setLastSelectedLevel(
        exerciseId: widget.exerciseId,
        level: _selectedLevel,
      );
    }
    final opened = ExerciseRouteRegistry.open(
      context,
      widget.exerciseId,
      difficultyLevel: _selectedLevel,
    );
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercise not wired yet')),
      );
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));
    // Cache is already updated by AttemptRepository.save()
    // No need to refresh from database
    final latest = _attempts.latestFor(widget.exerciseId);
    if (mounted) {
      setState(() => _latest =
          latest == null ? null : ExerciseAttemptInfo.fromAttempt(latest));
    }
  }

  void _reviewLast() {
    final ex = _exercise;
    // Query most recent session by exerciseId from database (resilient to re-entry)
    final latest = _attempts.latestFor(widget.exerciseId);
    if (latest == null || ex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No take recorded yet.')),
      );
      return;
    }
    // Navigate directly to Detailed Review (ExerciseReviewSummaryScreen)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseReviewSummaryScreen(
          exercise: ex,
          attempt: latest,
        ),
      ),
    );
  }

  Future<void> _playPreview(VocalExercise ex) async {
    if (_previewing) return; // Prevent multiple simultaneous previews

    setState(() => _previewing = true);
    debugPrint('[Preview] start - exercise=${ex.id}');

    try {
      final metadata = ExerciseMetadata.forExercise(ex);

      // Check if preview is supported
      if (!metadata.previewSupported) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No preview available for this exercise')),
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
        ex.highwaySpec?.segments ?? [],
      );
      final scaledSegments = PitchHighwayTempo.scaleSegments(
        ex.highwaySpec?.segments ?? [],
        multiplier,
      );

      // Use sine preview generator for glides
      if (metadata.previewAudioStyle == PreviewAudioStyle.sineSweep) {
        // Only for yawn-sigh preview (which should be a glide)
        if (ex.id == 'yawn_sigh') {
          // Yawn-sigh: descending glide preview
          final glideSegments = scaledSegments.where((s) => s.isGlide).toList();
          if (glideSegments.isNotEmpty) {
            final glide = glideSegments.first;
            final durationMs = glide.endMs - glide.startMs;
            const previewStartMidi = 72.0; // C5
            const previewEndMidi = 60.0; // C4
            previewPath = await _previewGenerator.generateSweepWav(
              startMidi: previewStartMidi,
              endMidi: previewEndMidi,
              durationMs: durationMs,
              leadInMs: 2000,
              fadeMs: 10,
            );
            debugPrint('[Preview] Yawn-sigh descending glide ${durationMs}ms');
          }
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
        if (ex.id == 'ng_slides') {
          // NG Slides: discrete notes only (bottom + top), matching Octave Slides
          final segments = scaledSegments;
          if (segments.length >= 2) {
            final bottomNote = segments[0];
            final topNote = segments[1];
            previewPath = await _previewGenerator.generateCompositeWav(
              segments: [
                CompositeSegment.tone(
                  midi: bottomNote.midiNote.toDouble(),
                  durationSeconds:
                      (bottomNote.endMs - bottomNote.startMs) / 1000.0,
                ),
                CompositeSegment.silence(durationSeconds: 1.0), // 1s silence
                CompositeSegment.tone(
                  midi: topNote.midiNote.toDouble(),
                  durationSeconds: (topNote.endMs - topNote.startMs) / 1000.0,
                ),
              ],
              leadInMs: 2000,
            );
            debugPrint(
                '[Preview] NG Slides: bottom note ${bottomNote.midiNote}, top note ${topNote.midiNote}');
          }
        } else if (ex.id == 'sirens') {
          // Sirens: discrete notes only (bottom → top → bottom), 2s rest
          final segments = scaledSegments;
          if (segments.length >= 3) {
            final bottom1 = segments[0];
            final top = segments[1];
            final bottom2 = segments[2];
            previewPath = await _previewGenerator.generateCompositeWav(
              segments: [
                CompositeSegment.tone(
                  midi: bottom1.midiNote.toDouble(),
                  durationSeconds: (bottom1.endMs - bottom1.startMs) / 1000.0,
                ),
                CompositeSegment.tone(
                  midi: top.midiNote.toDouble(),
                  durationSeconds: (top.endMs - top.startMs) / 1000.0,
                ),
                CompositeSegment.tone(
                  midi: bottom2.midiNote.toDouble(),
                  durationSeconds: (bottom2.endMs - bottom2.startMs) / 1000.0,
                ),
                CompositeSegment.silence(
                    durationSeconds: 2.0), // 2s rest between cycles
              ],
              leadInMs: 2000,
            );
            debugPrint(
                '[Preview] Sirens: bottom ${bottom1.midiNote} → top ${top.midiNote} → bottom ${bottom2.midiNote}, 2s rest');
          }
        } else if (ex.id == 'interval_training') {
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
        } else if (ex.id == 'sustained_pitch_holds') {
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
          debugPrint(
              '[Preview] segment 1/1 - Sustained Pitch Hold ${holdDurationMs}ms');
        } else if (ex.id == 'fast_three_note_patterns') {
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
            debugPrint(
                '[Preview] segment ${i + 1}/${segments.length} - note ${seg.midiNote}');
          }
          previewPath = await _previewGenerator.generateCompositeWav(
            segments: compositeSegments,
            leadInMs: 2000,
          );
        } else {
          // Fallback: use regular note rendering
          final segments = scaledSegments.take(8).toList();
          final notes = segments
              .map((s) => ReferenceNote(
                    startSec: s.startMs / 1000.0,
                    endSec: s.endMs / 1000.0,
                    midi: s.midiNote,
                  ))
              .toList();
          previewPath = await _synth.renderReferenceNotes(notes);
        }
      } else {
        // Regular note-based preview (discrete notes, not glides)
        final segments = scaledSegments; // Play ALL segments, not just first 8
        final notes = segments
            .map((s) => ReferenceNote(
                  startSec: s.startMs / 1000.0,
                  endSec: s.endMs / 1000.0,
                  midi: s.midiNote,
                ))
            .toList();
        debugPrint(
            '[Preview] segment 1/${segments.length} - regular notes, total=${segments.length}');
        if (ex.id == 'vv_zz_scales') {
          // Vv/Zz: ensure all segments are played with debug logs
          for (var i = 0; i < notes.length; i++) {
            debugPrint(
                '[Preview] segment ${i + 1}/${notes.length} - Vv/Zz note ${notes[i].midi}');
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
      if (mounted) {
        setState(() => _previewing = false);
      }
      debugPrint('[Preview] end - state reset');
    }
  }
}

class _Header extends StatelessWidget {
  final VocalExercise ex;
  final ExerciseRepository _repo = ExerciseRepository();

  _Header({required this.ex});

  @override
  Widget build(BuildContext context) {
    // Get the category to use its sortOrder for consistent colors
    final category = _repo.getCategory(ex.categoryId);
    final bannerStyleId = category.sortOrder % 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Exercise name as header
        Text(
          ex.name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        // Description
        Text(
          ex.description,
          style: Theme.of(context).textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: BannerCard(
            title: ex.name,
            subtitle: ex.description,
            bannerStyleId: bannerStyleId, // Use category's color
          ),
        ),
      ],
    );
  }
}

class ExerciseAttemptInfo {
  final double score;
  final DateTime completedAt;
  final String? recordingPath;
  final ExerciseAttempt raw;

  ExerciseAttemptInfo({
    required this.score,
    required this.completedAt,
    required this.recordingPath,
    required this.raw,
  });

  factory ExerciseAttemptInfo.fromAttempt(ExerciseAttempt attempt) {
    return ExerciseAttemptInfo(
      score: attempt.overallScore,
      completedAt:
          attempt.completedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      recordingPath: attempt.recordingPath,
      raw: attempt,
    );
  }

  String get dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(completedAt.year, completedAt.month, completedAt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return '${_month(completedAt.month)} ${completedAt.day}';
  }

  String _month(int m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    if (m < 1 || m > 12) return '';
    return names[m - 1];
  }
}
