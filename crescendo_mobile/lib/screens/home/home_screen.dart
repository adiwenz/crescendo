import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../../design/app_text.dart';
import '../../models/exercise.dart';
import '../../screens/explore/exercise_preview_screen.dart';
import '../../services/daily_exercise_service.dart';
import '../../services/sync_diagnostic_service.dart';
import '../../services/reference_midi_engine.dart';
import '../../models/reference_note.dart';
import '../../state/library_store.dart';
import '../../widgets/home/home_category_banner_row.dart';
import '../../services/audio_synth_service.dart';
import '../../services/reference_audio_cache_service.dart';
import '../../services/vocal_range_service.dart';
import '../../models/pitch_highway_difficulty.dart';
import '../../services/exercise_audio_asset_resolver.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:audioplayers/audioplayers.dart';
import '../../services/review_audio_bounce_service.dart';
import '../../services/range_store.dart';
import '../../utils/audio_constants.dart';
import 'styles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Exercise>? _dailyExercises;
  bool _isLoading = true;
  int? _debugRenderingTimeMs;
  String? _debugError;

  @override
  void initState() {
    super.initState();
    _loadDailyExercises();
    // Listen to completion changes
    libraryStore.addListener(_onCompletionChanged);
  }

  @override
  void dispose() {
    libraryStore.removeListener(_onCompletionChanged);
    super.dispose();
  }

  void _onCompletionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadDailyExercises() async {
    final exercises = await dailyExerciseService.getTodaysExercises();
    if (mounted) {
      setState(() {
        _dailyExercises = exercises;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: HomeScreenStyles.homeScreenGradient,
            ),
            child: SafeArea(
              bottom: false,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome',
                          style: AppText.h1.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Let\'s train your voice',
                          style: AppText.body.copyWith(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Today\'s Progress', style: AppText.h2),
                        const SizedBox(height: 12),
                        _TodaysProgressCard(dailyExercises: _dailyExercises),
                        const SizedBox(height: 24),
                        Text('Today\'s Exercises', style: AppText.h2),
                        const SizedBox(height: 12),
                        _ExercisesWithProgressIndicator(
                          exercises: _dailyExercises,
                          isLoading: _isLoading,
                        ),
                        // Debug section (only in debug mode)
                        if (kDebugMode) ...[
                          const SizedBox(height: 24),
                          _DebugSection(
                            onDebugResult: (timeMs, error) {
                              setState(() {
                                _debugRenderingTimeMs = timeMs;
                                _debugError = error;
                              });
                              // Auto-hide after 5s
                              Future.delayed(const Duration(seconds: 5), () {
                                if (mounted) {
                                  setState(() {
                                    _debugRenderingTimeMs = null;
                                    _debugError = null;
                                  });
                                }
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // TOP OVERLAY FOR PERFORMANCE
          if (_debugRenderingTimeMs != null || _debugError != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _debugError != null
                          ? Colors.red.withOpacity(0.9)
                          : Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _debugError ?? '✅ Rendered in ${_debugRenderingTimeMs}ms (48kHz)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Debug section with sync diagnostic button
///
/// How to use:
/// 1. Tap "Run Sync Diagnostic" button
/// 2. Test runs: 2s lead-in, then plays a sharp click at t=2.0s, records for 5s total
/// 3. After recording, analyzes WAV to find click onset
/// 4. Computes offsetMs = detectedClickMs - scheduledClickMs (2000ms)
/// 5. Saves offsetMs to SharedPreferences for use in review playback compensation
///
/// Interpreting offsetMs:
/// - Positive offsetMs: recorded audio is LATE relative to scheduled reference (MIDI plays too early)
/// - Negative offsetMs: recorded audio is EARLY relative to scheduled reference (MIDI plays too late)
/// - Typical values: 0-100ms (good sync), 100-300ms (noticeable drift), >300ms (significant issue)
class _DebugSection extends StatefulWidget {
  final Function(int? timeMs, String? error) onDebugResult;
  const _DebugSection({required this.onDebugResult});

  @override
  State<_DebugSection> createState() => _DebugSectionState();
}

class _DebugSectionState extends State<_DebugSection> {
  bool _running = false;
  String? _statusMessage;
  int? _savedOffset;
  bool _testPlaying = false;
  int _testRunId = 0;
  bool _audioPlaying = false;
  final AudioSynthService _audioSynth = AudioSynthService();
  final AudioPlayer _directPlayer = AudioPlayer(); // For direct WAV playback
  StreamSubscription? _audioCompleteSub;
  bool _isGeneratingFiveTone = false;
  bool _generatingCache = false;
  int _cacheProgress = 0;
  int _cacheTotal = 0;
  String? _currentExerciseId;
  List<String>? _availableExercises;
  bool _loadingExercises = false;
  String? _playingExerciseId;

  @override
  void initState() {
    super.initState();
    _loadSavedOffset();
  }

  @override
  void dispose() {
    _audioCompleteSub?.cancel();
    _audioSynth.dispose();
    _directPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadSavedOffset() async {
    final offset = await SyncDiagnosticService.getSavedOffset();
    if (mounted) {
      setState(() {
        _savedOffset = offset;
      });
    }
  }

  Future<void> _runDiagnostic() async {
    if (_running) return;

    setState(() {
      _running = true;
      _statusMessage = 'Running diagnostic...';
    });

    try {
      final offsetMs = await SyncDiagnosticService.runDiagnostic();

      if (mounted) {
        setState(() {
          _running = false;
          if (offsetMs != null) {
            _statusMessage = 'Offset: ${offsetMs}ms';
            _savedOffset = offsetMs;
          } else {
            _statusMessage = 'Diagnostic failed - check logs';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _clearOffset() async {
    await SyncDiagnosticService.clearSavedOffset();
    if (mounted) {
      setState(() {
        _savedOffset = null;
        _statusMessage = 'Offset cleared';
      });
    }
  }

  Future<void> _runRouteChangeTest() async {
    if (_testPlaying) return;

    setState(() {
      _testPlaying = true;
      _testRunId++;
      _statusMessage =
          'Playing 5-note scale... Unplug headphones to test resumption';
    });

    try {
      final engine = ReferenceMidiEngine();
      await engine.initialize();

      // Create a 5-note scale: C4, D4, E4, F4, G4 (MIDI 60, 62, 64, 65, 67)
      // Each note plays for 0.5s with 0.5s spacing (total 5 seconds)
      final notes = [
        ReferenceNote(startSec: 0.0, endSec: 0.5, midi: 60), // C4
        ReferenceNote(startSec: 1.0, endSec: 1.5, midi: 62), // D4
        ReferenceNote(startSec: 2.0, endSec: 2.5, midi: 64), // E4
        ReferenceNote(startSec: 3.0, endSec: 3.5, midi: 65), // F4
        ReferenceNote(startSec: 4.0, endSec: 4.5, midi: 67), // G4
      ];

      // Track position for route change resumption
      final startTime = DateTime.now();
      Timer? positionTimer;

      positionTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_testPlaying) {
          timer.cancel();
          return;
        }
        final elapsed =
            DateTime.now().difference(startTime).inMilliseconds / 1000.0;
        engine.updatePosition(elapsed, runId: _testRunId);
      });

      await engine.playSequence(
        notes: notes,
        leadInSec: 0.0,
        runId: _testRunId,
        mode: 'exercise',
      );

      // Wait for playback to complete (5 seconds total)
      await Future.delayed(const Duration(milliseconds: 5500));

      positionTimer.cancel();

      if (mounted && _testRunId == _testRunId) {
        setState(() {
          _testPlaying = false;
          _statusMessage = 'Test complete';
        });
        engine.clearContext(runId: _testRunId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testPlaying = false;
          _statusMessage = 'Test error: $e';
        });
      }
    }
  }

  Future<void> _stopTest() async {
    final engine = ReferenceMidiEngine();
    await engine.stopAll(tag: 'test-stop');
    engine.clearContext(runId: _testRunId);
    if (mounted) {
      setState(() {
        _testPlaying = false;
      });
    }
  }

  Future<void> _generateAndPlayFiveTone() async {
    if (_isGeneratingFiveTone) return;

    setState(() {
      _isGeneratingFiveTone = true;
    });
    widget.onDebugResult(null, null);

    try {
      final startTime = DateTime.now();

      // 1. Get user range
      final rangeStore = RangeStore();
      final range = await rangeStore.getRange();
      final lowestMidi = range.$1 ?? 48; // Default C3
      final highestMidi = range.$2 ?? 72; // Default C5
      
      debugPrint('[DebugGen] Range: $lowestMidi to $highestMidi');

      // 2. Setup Full Range Sequence
      // We loop from lowest to highest, generating a 5-tone scale at each step
      final offsets = [0, 2, 4, 5, 7, 5, 4, 2, 0];
      const noteDurationSec = 0.4; // Slightly faster for full range test
      const gapDurationSec = 0.5;
      const leadInSec = 2.0;

      final notes = <ReferenceNote>[];
      var currentTime = leadInSec;

      for (var baseMidi = lowestMidi; baseMidi <= highestMidi; baseMidi++) {
        for (var i = 0; i < offsets.length; i++) {
          notes.add(ReferenceNote(
            midi: baseMidi + offsets[i],
            startSec: currentTime,
            endSec: currentTime + noteDurationSec,
          ));
          currentTime += noteDurationSec;
        }
        currentTime += gapDurationSec; // Gap between repetitions
      }

      final totalDurationSec = currentTime + 1.0;

      // 3. Render
      final bounceService = ReviewAudioBounceService();
      final renderedFile = await bounceService.renderReferenceWav(
        notes: notes,
        durationSec: totalDurationSec,
        sampleRate: AudioConstants.audioSampleRate,
        soundFontAssetPath: 'assets/soundfonts/default.sf2',
        program: 0,
      );

      final elapsed = DateTime.now().difference(startTime);

      if (mounted) {
        setState(() {
          _isGeneratingFiveTone = false;
        });
        widget.onDebugResult(elapsed.inMilliseconds, null);
      }

      // 4. Play
      await _directPlayer.stop();
      await _directPlayer.play(DeviceFileSource(renderedFile.path));
    } catch (e) {
      debugPrint('[DebugGen] Error: $e');
      if (mounted) {
        setState(() {
          _isGeneratingFiveTone = false;
        });
        widget.onDebugResult(null, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Debug Tools',
            style: AppText.h2.copyWith(color: Colors.red.shade700),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _running ? null : _runDiagnostic,
            child: Text(_running ? 'Running...' : 'Run Sync Diagnostic'),
          ),
          if (_savedOffset != null) ...[
            const SizedBox(height: 8),
            Text(
              'Saved offset: ${_savedOffset}ms',
              style: AppText.body.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _clearOffset,
              child: const Text('Clear Offset'),
            ),
          ],
          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage!,
              style: AppText.body
                  .copyWith(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Route Change Test',
            style:
                AppText.h2.copyWith(color: Colors.red.shade700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Plays a 5-note scale (C4-D4-E4-F4-G4). Unplug headphones mid-play to test automatic resumption.',
            style: AppText.body
                .copyWith(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _testPlaying ? _stopTest : _runRouteChangeTest,
            child: Text(_testPlaying ? 'Stop Test' : 'Test Route Change'),
          ),
          if (_testPlaying) ...[
            const SizedBox(height: 8),
            Text(
              'Playing... Unplug headphones to test resumption',
              style: AppText.body
                  .copyWith(fontSize: 11, color: Colors.orange.shade700),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Cached Audio Test',
            style:
                AppText.h2.copyWith(color: Colors.red.shade700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Plays cached reference audio for head_voice_scales/easy exercise.',
            style: AppText.body
                .copyWith(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _audioPlaying ? _stopAudio : _playCachedAudio,
            child: Text(_audioPlaying ? 'Stop Audio' : 'Play Cached Audio'),
          ),
          if (_audioPlaying) ...[
            const SizedBox(height: 8),
            Text(
              'Playing cached audio...',
              style: AppText.body
                  .copyWith(fontSize: 11, color: Colors.orange.shade700),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Cache Generation',
            style:
                AppText.h2.copyWith(color: Colors.red.shade700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Manually generate reference audio cache for current vocal range.',
            style: AppText.body
                .copyWith(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _generatingCache ? null : _generateCache,
            child: Text(_generatingCache
                ? 'Generating... ($_cacheProgress/$_cacheTotal)'
                : 'Generate Cache'),
          ),
          if (_generatingCache && _currentExerciseId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Generating: $_currentExerciseId',
              style: AppText.body
                  .copyWith(fontSize: 11, color: Colors.orange.shade700),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Exercise Assets',
            style:
                AppText.h2.copyWith(color: Colors.red.shade700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'List and play exercise M4A assets from the app bundle.',
            style: AppText.body
                .copyWith(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _loadingExercises ? null : _loadAvailableExercises,
            child: Text(
                _loadingExercises ? 'Loading...' : 'List Available Exercises'),
          ),
          if (_availableExercises != null) ...[
            const SizedBox(height: 8),
            Text(
              'Found ${_availableExercises!.length} exercises:',
              style: AppText.body
                  .copyWith(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            ...(_availableExercises!.map((exerciseId) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          exerciseId,
                          style: AppText.body.copyWith(fontSize: 12),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => _playExerciseAsset(exerciseId),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: const Size(0, 32),
                        ),
                        child: Text(
                            _playingExerciseId == exerciseId ? 'Stop' : 'Play'),
                      ),
                    ],
                  ),
                ))),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          Text(
            'Dynamic Reference Gen',
            style:
                AppText.h2.copyWith(color: Colors.red.shade700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Generates a 5-tone scale on-the-fly at 48kHz, transposed to your range, with a 2s lead-in.',
            style: AppText.body
                .copyWith(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _isGeneratingFiveTone ? null : _generateAndPlayFiveTone,
            icon: _isGeneratingFiveTone
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.music_note, size: 18),
            label: Text(_isGeneratingFiveTone
                ? 'Generating...'
                : 'Generate 5-Tone Scale'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateCache() async {
    if (_generatingCache) return;

    setState(() {
      _generatingCache = true;
      _cacheProgress = 0;
      _cacheTotal = 0;
      _statusMessage = 'Starting cache generation...';
    });

    try {
      // Get current vocal range
      final (lowestMidi, highestMidi) = await VocalRangeService().getRange();

      // getRange() always returns valid values (uses defaults if not set)
      // So we can proceed directly

      debugPrint(
          '[Debug] Generating cache for range: $lowestMidi-$highestMidi');

      // Generate cache with progress callback
      await ReferenceAudioCacheService.instance.generateCacheForRange(
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
        onProgress: (current, total, exerciseId) {
          if (mounted) {
            setState(() {
              _cacheProgress = current;
              _cacheTotal = total;
              _currentExerciseId = exerciseId;
              _statusMessage = 'Generating: $exerciseId ($current/$total)';
            });
          }
        },
        shouldCancel: () => !_generatingCache,
      );

      if (mounted) {
        setState(() {
          _generatingCache = false;
          _statusMessage = 'Cache generation complete!';
          _currentExerciseId = null;
        });
      }

      debugPrint('[Debug] Cache generation complete');
    } catch (e, stackTrace) {
      debugPrint('[Debug] Error generating cache: $e');
      debugPrint('[Debug] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _generatingCache = false;
          _statusMessage = 'Error: $e';
          _currentExerciseId = null;
        });
      }
    }
  }

  Future<void> _loadAvailableExercises() async {
    if (_loadingExercises) return;

    setState(() {
      _loadingExercises = true;
      _statusMessage = 'Loading available exercises...';
    });

    try {
      final exercises =
          await ExerciseAudioAssetResolver.listAvailableExercises();
      if (mounted) {
        setState(() {
          _availableExercises = exercises;
          _loadingExercises = false;
          _statusMessage = 'Found ${exercises.length} exercises';
        });
      }
      debugPrint('[Debug] Available exercises: ${exercises.join(", ")}');
    } catch (e, stackTrace) {
      debugPrint('[Debug] Error loading exercises: $e');
      debugPrint('[Debug] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _loadingExercises = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _playExerciseAsset(String exerciseId) async {
    if (_playingExerciseId != null) {
      // Stop current playback
      await _audioSynth.stop();
      _audioCompleteSub?.cancel();
      if (mounted) {
        setState(() {
          _playingExerciseId = null;
        });
      }
      return;
    }

    setState(() {
      _playingExerciseId = exerciseId;
      _statusMessage = 'Loading $exerciseId...';
    });

    try {
      // Load asset to temp file
      final assetPath = ExerciseAudioAssetResolver.getM4aAssetPath(exerciseId);
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final fileName = p.basename(assetPath);
      final tempPath = p.join(
          dir.path, 'asset_${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final file = File(tempPath);
      await file.writeAsBytes(bytes, flush: true);

      debugPrint('[Debug] Playing full asset for $exerciseId: $tempPath');

      // Play using AudioSynthService
      await _audioSynth.playFile(tempPath);

      // Listen for completion
      _audioCompleteSub?.cancel();
      _audioCompleteSub = _audioSynth.onComplete.listen((_) {
        if (mounted) {
          setState(() {
            _playingExerciseId = null;
            _statusMessage = 'Finished playing $exerciseId';
          });
        }
      });

      if (mounted) {
        setState(() {
          _statusMessage = 'Playing $exerciseId (full range)...';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[Debug] Error playing exercise asset: $e');
      debugPrint('[Debug] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _playingExerciseId = null;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _playCachedAudio() async {
    if (_audioPlaying) return;

    setState(() {
      _audioPlaying = true;
      _statusMessage = 'Loading cached audio...';
    });

    try {
      // Get current vocal range
      final (lowestMidi, highestMidi) = await VocalRangeService().getRange();
      final rangeHash = ReferenceAudioCacheService.generateRangeHash(
        lowestMidi: lowestMidi,
        highestMidi: highestMidi,
      );
      final variantKey = PitchHighwayDifficulty.easy.name;

      debugPrint(
          '[Debug] Looking up cached audio: exerciseId=head_voice_scales, rangeHash=$rangeHash, variantKey=$variantKey');

      // Look up cached audio
      final cachedAudioPath =
          await ReferenceAudioCacheService.instance.getCachedAudioPath(
        exerciseId: 'head_voice_scales',
        rangeHash: rangeHash,
        variantKey: variantKey,
      );

      if (cachedAudioPath == null) {
        // Debug: list what's actually cached
        final cachedFiles = await ReferenceAudioCacheService.instance
            .debugListCachedFiles('head_voice_scales');
        if (mounted) {
          setState(() {
            _audioPlaying = false;
            if (cachedFiles.isEmpty) {
              _statusMessage = 'No cached files found for head_voice_scales';
            } else {
              _statusMessage =
                  'Cache miss! Found ${cachedFiles.length} files but none match rangeHash=$rangeHash';
              debugPrint('[Debug] Cached files for head_voice_scales:');
              for (final file in cachedFiles) {
                debugPrint(
                    '[Debug]   - rangeHash=${file['rangeHash']}, variantKey=${file['variantKey']}, exists=${file['exists']}, size=${file['size']}');
              }
            }
          });
        }
        return;
      }

      debugPrint('[Debug] Found cached audio: $cachedAudioPath');

      if (mounted) {
        setState(() {
          _statusMessage = 'Playing: $cachedAudioPath';
        });
      }

      // Use AudioSynthService to play the file (now supports M4A)
      await _audioSynth.playFile(cachedAudioPath);

      // Listen for completion
      _audioCompleteSub?.cancel();
      _audioCompleteSub = _audioSynth.onComplete.listen((_) {
        if (mounted) {
          setState(() {
            _audioPlaying = false;
            _statusMessage = 'Playback complete';
          });
        }
      });
    } catch (e, stackTrace) {
      debugPrint('[Debug] Error playing cached audio: $e');
      debugPrint('[Debug] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _audioPlaying = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _stopAudio() async {
    await _audioSynth.stop();
    if (mounted) {
      setState(() {
        _audioPlaying = false;
        _statusMessage = 'Stopped';
      });
    }
  }
}

class _ExercisesWithProgressIndicator extends StatelessWidget {
  final List<Exercise>? exercises;
  final bool isLoading;

  const _ExercisesWithProgressIndicator({
    required this.exercises,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (exercises == null || exercises!.isEmpty) {
      return const SizedBox.shrink();
    }

    final completedIds = libraryStore.completedExerciseIds;

    const double gutterWidth = 48.0; // Fixed-width timeline gutter
    const double cardSpacing = 16.0; // Bottom padding between cards
    const double cardHeight = 96.0; // Card height (from HomeCategoryBannerRow)
    final mutedLineColor = HomeScreenStyles.iconInactive.withOpacity(0.3);

    // Calculate line positions: start at first circle center, end at last circle center
    // Each row has height = cardHeight, with cardSpacing between rows
    // Circle centers are at cardHeight/2 from the top of each row
    final double firstCircleCenterY =
        cardHeight / 2; // Center of first row (index 0)

    // Calculate the exact position of the last circle center
    // For n items: row 0 at 0, row 1 at (cardHeight + cardSpacing), etc.
    // Last row (index n-1) starts at: (n-1) * (cardHeight + cardSpacing)
    final int lastRowIndex = exercises!.length - 1;
    final double lastRowTop = lastRowIndex * (cardHeight + cardSpacing);
    final double lastCircleCenterY = lastRowTop + (cardHeight / 2);

    // Line starts at first circle center and extends all the way to last circle center
    // Extend to the bottom edge of the last circle to ensure it connects fully
    const double circleRadius = TimelineIcon._size / 2; // 16.0
    final double lineTop = firstCircleCenterY;
    final double lastCircleBottom = lastCircleCenterY + circleRadius;
    final double lineHeight = lastCircleBottom - firstCircleCenterY;

    return Stack(
      children: [
        // Vertical connector line - positioned between first and last circle centers only
        if (exercises!.length > 1 && lineHeight > 0)
          Positioned(
            left: (gutterWidth / 2) - 0.75, // Center of gutter
            top: lineTop, // Start at first circle center
            child: Container(
              width: 1.5,
              height: lineHeight, // Height from first to last circle center
              decoration: BoxDecoration(
                color: mutedLineColor,
                borderRadius: BorderRadius.circular(0.75),
              ),
            ),
          ),
        // Column of rows - each row contains icon + card
        Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(exercises!.length, (index) {
            final exercise = exercises![index];
            final isCompleted = completedIds.contains(exercise.id);

            return Padding(
              padding: EdgeInsets.only(
                  bottom: index < exercises!.length - 1 ? cardSpacing : 0),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left: Timeline gutter with icon
                    SizedBox(
                      width: gutterWidth,
                      child: Center(
                        child: TimelineIcon(isCompleted: isCompleted),
                      ),
                    ),
                    // Right: Exercise card
                    Expanded(
                      child: HomeCategoryBannerRow(
                        title: exercise.title,
                        subtitle: '', // Not used, but required by widget
                        bannerStyleId: exercise.bannerStyleId,
                        onTap: () {
                          // Navigate to the exercise preview screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ExercisePreviewScreen(
                                  exerciseId: exercise.id),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

enum TimelineIconStatus {
  completed,
  incomplete,
  current,
}

class TimelineIcon extends StatelessWidget {
  final bool isCompleted;
  static const double _size = 32.0; // Circle size

  const TimelineIcon({
    super.key,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCompleted
            ? HomeScreenStyles
                .timelineCheckmarkBackground // Color from HomeScreenStyles
            : Colors
                .white, // White background to cover the line behind incomplete circles
        border: Border.all(
          color: isCompleted
              ? HomeScreenStyles.timelineCheckmarkBackground
              : HomeScreenStyles.iconInactive
                  .withOpacity(0.4), // Muted gray/lavender for incomplete
          width: isCompleted ? 0 : 2,
        ),
      ),
      child: isCompleted
          ? const Icon(
              Icons.check_rounded,
              size: 20,
              color: Colors.white,
            )
          : null,
    );
  }
}

class _TodaysProgressCard extends StatelessWidget {
  final List<Exercise>? dailyExercises;

  const _TodaysProgressCard({this.dailyExercises});

  @override
  Widget build(BuildContext context) {
    final completedIds = libraryStore.completedExerciseIds;

    // Calculate remaining time
    final minutesLeft = dailyExercises != null && dailyExercises!.isNotEmpty
        ? dailyExerciseService.calculateRemainingMinutes(
            dailyExercises!, completedIds)
        : 0;

    // Calculate progress percentage
    final totalExercises = dailyExercises?.length ?? 0;
    final completedCount = totalExercises > 0
        ? dailyExercises!.where((e) => completedIds.contains(e.id)).length
        : 0;
    final todaysProgress =
        totalExercises > 0 ? completedCount / totalExercises : 0.0;

    // Format remaining time text
    String remainingTimeText;
    if (minutesLeft <= 0) {
      remainingTimeText = 'All done for today 🎉';
    } else if (minutesLeft < 1) {
      remainingTimeText = '<1 min left';
    } else {
      remainingTimeText = '$minutesLeft min left to practice';
    }

    return Container(
      decoration: BoxDecoration(
        color:
            HomeScreenStyles.cardFill.withOpacity(HomeScreenStyles.cardOpacity),
        borderRadius: BorderRadius.circular(HomeScreenStyles.cardBorderRadius),
        border: Border.all(
          color: HomeScreenStyles.cardBorder,
          width: HomeScreenStyles.cardBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: HomeScreenStyles.cardShadowColor,
            blurRadius: HomeScreenStyles.cardShadowBlur,
            spreadRadius: HomeScreenStyles.cardShadowSpread,
            offset: HomeScreenStyles.cardShadowOffset,
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${(todaysProgress * 100).round()}% Complete',
                    style: HomeScreenStyles.cardTitle.copyWith(fontSize: 20),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    remainingTimeText,
                    style: HomeScreenStyles.cardSubtitle,
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HomeScreenStyles.accentPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.trending_up,
                  color: HomeScreenStyles.accentPurple,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: todaysProgress.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: HomeScreenStyles.progressBarBackground,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  HomeScreenStyles.progressBarFill),
            ),
          ),
        ],
      ),
    );
  }
}

