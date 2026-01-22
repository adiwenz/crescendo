#!/usr/bin/env dart

/// CLI tool to generate exercise X-map JSON files for visual note layout.
///
/// Usage:
///   dart run tool/generate_exercise_xmaps.dart
///   dart run tool/generate_exercise_xmaps.dart --force
///   dart run tool/generate_exercise_xmaps.dart --out assets/generated/exercise_xmap
///
/// This script generates JSON mapping files that describe the X-axis layout
/// for each visual "midi pill" based on the same note schedule used for audio generation.
///
/// NOTE: This JSON will later be used to drive visual pill X placement, but is not used yet.

import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:path/path.dart' as p;

// Configuration
const int defaultSampleRate = 48000;
const int defaultMinMidi = 36; // C2
const int defaultMaxMidi = 96; // C7
const double leadInSec = 2.0; // Lead-in time

// Minimal model classes (standalone, no Flutter)
class _ReferenceNote {
  final double startSec;
  final double endSec;
  final int midi;

  _ReferenceNote({
    required this.startSec,
    required this.endSec,
    required this.midi,
  });
}

class _PitchSegment {
  final int startMs;
  final int endMs;
  final int midiNote;
  final double toleranceCents;
  final String? label;
  final int? startMidi;
  final int? endMidi;

  _PitchSegment({
    required this.startMs,
    required this.endMs,
    required this.midiNote,
    required this.toleranceCents,
    this.label,
    this.startMidi,
    this.endMidi,
  });

  bool get isGlide => startMidi != null && endMidi != null;
}

class _VocalExercise {
  final String id;
  final String name;
  final _PitchHighwaySpec? highwaySpec;
  final bool isGlide;
  final double gapBetweenRepetitionsSec;

  _VocalExercise({
    required this.id,
    required this.name,
    this.highwaySpec,
    this.isGlide = false,
    this.gapBetweenRepetitionsSec = 0.75, // Default, should match defaultGapBetweenRepetitionsSec in M4A generator
  });
}

class _PitchHighwaySpec {
  final List<_PitchSegment> segments;

  _PitchHighwaySpec({required this.segments});
}

void main(List<String> args) async {
  // Parse arguments
  final argsMap = _parseArgs(args);
  final outputDir = argsMap['out'] as String? ?? 'assets/generated/exercise_xmap';
  final force = argsMap['force'] as bool? ?? false;
  final sampleRate =
      int.parse(argsMap['sampleRate'] as String? ?? '$defaultSampleRate');
  final minMidi = int.parse(argsMap['minMidi'] as String? ?? '$defaultMinMidi');
  final maxMidi = int.parse(argsMap['maxMidi'] as String? ?? '$defaultMaxMidi');

  print('Exercise X-Map Generator');
  print('=======================');
  print('Output: $outputDir');
  print(
      'Range: ${_midiToName(minMidi)} (MIDI $minMidi) to ${_midiToName(maxMidi)} (MIDI $maxMidi)');
  print('Sample rate: $sampleRate Hz');
  print('Force regenerate: $force');
  print('');

  // Ensure output directory exists
  final outputDirectory = Directory(outputDir);
  if (!await outputDirectory.exists()) {
    await outputDirectory.create(recursive: true);
    print('Created directory: ${outputDirectory.path}');
  }

  // Get all exercises from JSON file
  final exercises = _getExercises();

  if (exercises.isEmpty) {
    print('');
    print('ERROR: No exercises found!');
    print('');
    print('To generate exercises.json, run:');
    print('  flutter run tool/extract_exercises_to_json.dart');
    print('');
    exit(1);
  }

  // Include both non-glide and glide exercises (slides), but exclude sirens
  final exercisesToProcess = exercises.where((e) {
    return e.highwaySpec != null &&
        e.highwaySpec!.segments.isNotEmpty &&
        e.id != 'sirens'; // Skip sirens (handled separately)
  }).toList();

  print(
      'Found ${exercisesToProcess.length} exercises to process (including slides)');
  print('');

  final startTime = DateTime.now();
  int generated = 0;
  int skipped = 0;
  int errors = 0;

  for (final exercise in exercisesToProcess) {
    final patternPath = p.join(outputDir, '${exercise.id}_pattern.json');

    // Check if already exists (unless force)
    if (!force && await File(patternPath).exists()) {
      print('⏭  Skipping ${exercise.id} (already exists)');
      skipped++;
      continue;
    }

    try {
      print('📊 Generating pattern xmap for ${exercise.id}...');
      
      // Build full-range note sequence (same logic as M4A generator)
      final notes = _buildTransposedSequence(
        exercise: exercise,
        lowestMidi: minMidi,
        highestMidi: maxMidi,
        leadInSec: leadInSec,
        gapBetweenRepetitionsSec: exercise.gapBetweenRepetitionsSec,
      );

      if (notes.isEmpty) {
        print('   ⚠ No notes generated for ${exercise.id}');
        skipped++;
        continue;
      }

      // Sort notes by start time
      final sortedNotes = List<_ReferenceNote>.from(notes)
        ..sort((a, b) => a.startSec.compareTo(b.startSec));

      // Generate pattern-only JSON
      final patternFile = await writePatternOnlyJson(
        exerciseId: exercise.id,
        scheduledNotes: sortedNotes,
        gapBetweenRepetitionsSec: exercise.gapBetweenRepetitionsSec,
        outputPath: patternPath,
      );

      if (patternFile != null) {
        print('   ✓ Generated pattern xmap: ${patternFile.path}');
        generated++;
      } else {
        print('   ✗ Failed to generate pattern xmap');
        errors++;
      }
    } catch (e, stackTrace) {
      print('   ✗ Error: $e');
      final verbose = argsMap['verbose'] as bool?;
      if (verbose == true) {
        print('   Stack trace: $stackTrace');
      }
      errors++;
    }
  }

  final elapsed = DateTime.now().difference(startTime);
  print('');
  print('Summary');
  print('=======');
  print('Generated: $generated');
  print('Skipped: $skipped');
  print('Errors: $errors');
  print('Total time: ${elapsed.inSeconds}s');
  print('');
  print('Files are in: ${outputDirectory.absolute.path}');
}

Map<String, dynamic> _parseArgs(List<String> args) {
  final map = <String, dynamic>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--force') {
      map['force'] = true;
    } else if (arg == '--verbose' || arg == '-v') {
      map['verbose'] = true;
    } else if (arg == '--out' && i + 1 < args.length) {
      map['out'] = args[++i];
    } else if (arg == '--sampleRate' && i + 1 < args.length) {
      map['sampleRate'] = args[++i];
    } else if (arg == '--minMidi' && i + 1 < args.length) {
      map['minMidi'] = args[++i];
    } else if (arg == '--maxMidi' && i + 1 < args.length) {
      map['maxMidi'] = args[++i];
    }
  }
  return map;
}

String _midiToName(int midi) {
  const names = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B'
  ];
  final octave = (midi / 12).floor() - 1;
  return '${names[midi % 12]}$octave';
}

// Get exercises (simplified - only includes exercises with highwaySpec)
List<_VocalExercise> _getExercises() {
  // Try to load from JSON file first (if it exists)
  final jsonFile = File('tool/exercises.json');
  if (jsonFile.existsSync()) {
    try {
      final jsonData =
          jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
      final exercisesList = jsonData['exercises'] as List<dynamic>;
      return exercisesList
          .map((e) => _exerciseFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Warning: Failed to load exercises.json: $e');
      print('Using inline exercise definitions instead.');
    }
  }

  return [];
}

_VocalExercise _exerciseFromJson(Map<String, dynamic> json) {
  final highwaySpecJson = json['highwaySpec'] as Map<String, dynamic>?;
  _PitchHighwaySpec? highwaySpec;

  if (highwaySpecJson != null) {
    final segmentsJson = highwaySpecJson['segments'] as List<dynamic>;
    final segments = segmentsJson.map((s) {
      final segJson = s as Map<String, dynamic>;
      return _PitchSegment(
        startMs: segJson['startMs'] as int,
        endMs: segJson['endMs'] as int,
        midiNote: segJson['midiNote'] as int,
        toleranceCents: (segJson['toleranceCents'] as num).toDouble(),
        label: segJson['label'] as String?,
        startMidi: segJson['startMidi'] as int?,
        endMidi: segJson['endMidi'] as int?,
      );
    }).toList();
    highwaySpec = _PitchHighwaySpec(segments: segments);
  }

  return _VocalExercise(
    id: json['id'] as String,
    name: json['name'] as String,
    highwaySpec: highwaySpec,
    isGlide: json['isGlide'] as bool? ?? false,
    gapBetweenRepetitionsSec: (json['gapBetweenRepetitionsSec'] as num?)?.toDouble() ?? 0.75,
  );
}

// Standalone version of buildTransposedSequence (same as M4A generator)
List<_ReferenceNote> _buildTransposedSequence({
  required _VocalExercise exercise,
  required int lowestMidi,
  required int highestMidi,
  required double leadInSec,
  required double gapBetweenRepetitionsSec,
}) {
  final spec = exercise.highwaySpec;
  if (spec == null || spec.segments.isEmpty) return [];

  // Sort segments by startMs
  final segments = List<_PitchSegment>.from(spec.segments)
    ..sort((a, b) => a.startMs.compareTo(b.startMs));

  // Extract pattern offsets
  final firstEvent = segments.first;
  final firstEventMidi = firstEvent.midiNote;
  final baseRootMidi = firstEventMidi;

  final patternOffsets = <int>[];
  for (final seg in segments) {
    if (!seg.isGlide) {
      patternOffsets.add(seg.midiNote - baseRootMidi);
    }
  }

  if (patternOffsets.isEmpty) return [];

  final patternMin = patternOffsets.reduce(math.min);
  final patternMax = patternOffsets.reduce(math.max);
  final patternSpan = patternMax - patternMin;

  final startTargetMidi =
      (lowestMidi).clamp(lowestMidi, highestMidi - patternSpan);
  final firstRootMidi = startTargetMidi - patternMin;

  // Calculate pattern duration
  final patternDurationMs =
      segments.isEmpty ? 0 : segments.map((s) => s.endMs).reduce(math.max);
  final patternDurationSec = patternDurationMs / 1000.0;

  // Build all transposed repetitions
  final allNotes = <_ReferenceNote>[];
  var transpositionSemitones = 0;
  var currentTimeSec = leadInSec;

  while (true) {
    final rootMidi = firstRootMidi + transpositionSemitones;
    final segmentLow = rootMidi + patternMin;
    final segmentHigh = rootMidi + patternMax;

    if (segmentHigh > highestMidi) break;
    if (segmentLow < lowestMidi) {
      transpositionSemitones++;
      continue;
    }

    // Build notes for this transposition
    for (final seg in segments) {
      if (seg.isGlide) continue; // Skip glides for now

      final segStartSec = currentTimeSec + (seg.startMs / 1000.0);
      final segEndSec = currentTimeSec + (seg.endMs / 1000.0);
      final patternOffset = seg.midiNote - baseRootMidi;
      final targetMidi = rootMidi + patternOffset;

      allNotes.add(_ReferenceNote(
        startSec: segStartSec,
        endSec: segEndSec,
        midi: targetMidi,
      ));
    }

    currentTimeSec += patternDurationSec + gapBetweenRepetitionsSec;
    transpositionSemitones++;

    if (transpositionSemitones > 100) break; // Safety check
  }

  return allNotes;
}

/// Generate and write an exercise X-map JSON file.
///
/// This function takes the same note schedule used for audio generation
/// and produces a JSON file describing the X-axis layout for visual note pills.
///
/// The JSON will later be used to drive visual pill X placement, but is not used yet.
Future<File?> writeExerciseXMapJson({
  required String exerciseId,
  required List<_ReferenceNote> notes,
  required double leadInSec,
  required double? sliceStartSec,
  required double? sliceEndSec,
  required int sampleRate,
  required String outputPath,
}) async {
  if (notes.isEmpty) {
    print('[XMAP_GEN] ERROR: No notes provided for $exerciseId');
    return null;
  }

  // Sort notes by start time (should already be sorted, but ensure it)
  final sortedNotes = List<_ReferenceNote>.from(notes)
    ..sort((a, b) => a.startSec.compareTo(b.startSec));

  // Calculate slice boundaries if not provided
  final effectiveSliceStartSec = sliceStartSec ?? sortedNotes.first.startSec;
  final effectiveSliceEndSec =
      sliceEndSec ?? sortedNotes.map((n) => n.endSec).reduce(math.max);
  final durationSec = effectiveSliceEndSec - effectiveSliceStartSec;

  // Convert notes to relative times (relative to slice start)
  final xmapNotes = <Map<String, dynamic>>[];
  int noteIndex = 0;

  for (final note in sortedNotes) {
    // Convert to relative time (relative to slice start)
    final relStartSec = note.startSec - effectiveSliceStartSec;
    final relEndSec = note.endSec - effectiveSliceStartSec;
    final durSec = relEndSec - relStartSec;

    // Validate monotonicity
    if (relStartSec < 0) {
      print(
          '[XMAP_GEN] WARNING: Note $noteIndex has negative relStartSec: $relStartSec (absStartSec: ${note.startSec})');
    }
    if (relEndSec <= relStartSec) {
      print(
          '[XMAP_GEN] WARNING: Note $noteIndex has invalid duration: relStartSec=$relStartSec, relEndSec=$relEndSec');
      continue; // Skip invalid notes
    }

    // Round to 3 decimal places for stable diffs
    final roundedStartSec = (relStartSec * 1000).round() / 1000.0;
    final roundedEndSec = (relEndSec * 1000).round() / 1000.0;
    final roundedDurSec = (durSec * 1000).round() / 1000.0;

    xmapNotes.add({
      'i': noteIndex,
      'midi': note.midi,
      'startSec': roundedStartSec,
      'endSec': roundedEndSec,
      'durSec': roundedDurSec,
      'xStart': roundedStartSec, // xStart/xEnd in seconds (same as startSec/endSec)
      'xEnd': roundedEndSec,
    });

    noteIndex++;
  }

  // Build the xmap JSON structure
  final xmapData = {
    'schemaVersion': 1,
    'exerciseId': exerciseId,
    'createdAtEpochMs': DateTime.now().millisecondsSinceEpoch,
    'sampleRate': sampleRate,
    'leadInSec': leadInSec,
    'sliceStartSec': effectiveSliceStartSec,
    'sliceEndSec': effectiveSliceEndSec,
    'durationSec': durationSec,
    'notes': xmapNotes,
  };

  // Write JSON file
  final file = File(outputPath);
  await file.writeAsString(
    JsonEncoder.withIndent('  ').convert(xmapData),
  );

  // Log summary
  print('[XMAP_GEN] exerciseId=$exerciseId');
  print('[XMAP_GEN] noteCount=${xmapNotes.length}');
  print('[XMAP_GEN] sliceStartSec=${effectiveSliceStartSec.toStringAsFixed(3)}');
  print('[XMAP_GEN] sliceEndSec=${effectiveSliceEndSec.toStringAsFixed(3)}');
  if (xmapNotes.isNotEmpty) {
    final firstNote = xmapNotes.first;
    final secondNote = xmapNotes.length > 1 ? xmapNotes[1] : null;
    final thirdNote = xmapNotes.length > 2 ? xmapNotes[2] : null;
    print(
        '[XMAP_GEN] first note: midi=${firstNote['midi']}, relStart=${firstNote['startSec']}, relDur=${firstNote['durSec']}');
    if (secondNote != null) {
      print(
          '[XMAP_GEN] second note: midi=${secondNote['midi']}, relStart=${secondNote['startSec']}, relDur=${secondNote['durSec']}');
    }
    if (thirdNote != null) {
      print(
          '[XMAP_GEN] third note: midi=${thirdNote['midi']}, relStart=${thirdNote['startSec']}, relDur=${thirdNote['durSec']}');
    }
  }
  print('[XMAP_GEN] output file: ${file.absolute.path}');

  return file;
}

/// Generate pattern-only JSON (single mini-exercise pattern).
/// Extracts the first pattern using gap detection and outputs simplified JSON.
/// Uses gapBetweenRepetitionsSec from exercises.json as the source of truth.
Future<File?> writePatternOnlyJson({
  required String exerciseId,
  required List<_ReferenceNote> scheduledNotes,
  required double gapBetweenRepetitionsSec,
  required String outputPath,
}) async {
  if (scheduledNotes.isEmpty) {
    print('[PATTERN_GEN] ERROR: No scheduled notes provided for $exerciseId');
    return null;
  }

  // Sort notes by start time (should already be sorted, but ensure it)
  final sortedNotes = List<_ReferenceNote>.from(scheduledNotes)
    ..sort((a, b) => a.startSec.compareTo(b.startSec));

  // Extract pattern using gap detection
  // Take notes until gap >= 0.20s, max 32 notes, fallback to 8 notes
  const double gapThresholdSec = 0.20;
  const int maxPatternNotes = 32;
  const int fallbackPatternNotes = 8;

  final patternNotes = <_ReferenceNote>[];
  
  // Start with first note
  patternNotes.add(sortedNotes.first);
  final patternStartSec = sortedNotes.first.startSec;
  final rootMidi = sortedNotes.first.midi;

  // Keep adding notes until we find a boundary gap or hit max
  double? detectedGapSec;
  for (var i = 1; i < sortedNotes.length && patternNotes.length < maxPatternNotes; i++) {
    final prevNote = sortedNotes[i - 1];
    final currNote = sortedNotes[i];
    final gapSec = currNote.startSec - prevNote.endSec;

    if (gapSec >= gapThresholdSec) {
      // Found pattern boundary
      detectedGapSec = gapSec;
      print('[PATTERN_GEN] Detected boundary gap: ${gapSec.toStringAsFixed(3)}s at note $i');
      break;
    }

    patternNotes.add(currNote);
  }

  // Fallback: if no boundary found and we have fewer than fallback count, use fallback
  if (patternNotes.length < fallbackPatternNotes && detectedGapSec == null) {
    print('[PATTERN_GEN] No boundary gap found, using fallback: first $fallbackPatternNotes notes');
    patternNotes.clear();
    patternNotes.addAll(sortedNotes.take(fallbackPatternNotes));
  }

  if (patternNotes.isEmpty) {
    print('[PATTERN_GEN] ERROR: No pattern notes extracted for $exerciseId');
    return null;
  }

  // Use gapBetweenRepetitionsSec from exercises.json as the source of truth
  // This ensures consistency between audio generation and visual pattern generation
  final gapBetweenPatterns = gapBetweenRepetitionsSec.clamp(0.0, double.infinity);

  // Build pattern-relative notes with midiDelta
  final xmapNotes = <Map<String, dynamic>>[];
  
  for (var i = 0; i < patternNotes.length; i++) {
    final note = patternNotes[i];
    
    // Convert to pattern-relative time (re-zeroed)
    final relStart = note.startSec - patternStartSec;
    final relEnd = note.endSec - patternStartSec;
    final midiDelta = note.midi - rootMidi;

    // Round to 2 decimal places for readability
    final xStart = (relStart * 100).round() / 100.0;
    final xEnd = (relEnd * 100).round() / 100.0;

    xmapNotes.add({
      'i': i,
      'midiDelta': midiDelta,
      'xStart': xStart,
      'xEnd': xEnd,
    });
  }

  // Calculate pattern duration (xEnd of last note, rounded to 2 decimals)
  final patternDurationSec = xmapNotes.isEmpty
      ? 0.0
      : ((xmapNotes.last['xEnd'] as double) * 100).round() / 100.0;

  // Verification asserts (debug mode)
  assert(xmapNotes[0]['xStart'] == 0.0, 'First note xStart must be 0.0');
  final lastXEnd = xmapNotes.last['xEnd'] as double;
  assert((patternDurationSec - lastXEnd).abs() < 0.01,
      'patternDurationSec must equal last note xEnd');
  assert(xmapNotes[0]['midiDelta'] == 0, 'First note midiDelta must be 0');

  // Build the pattern JSON structure (simplified, no exercise-level fields)
  final xmapData = {
    'schemaVersion': 1,
    'exerciseId': exerciseId,
    'patternId': 'default',
    'noteCount': xmapNotes.length,
    'patternDurationSec': patternDurationSec,
    'gapBetweenPatterns': (gapBetweenPatterns * 100).round() / 100.0, // Round to 2 decimals
    'notes': xmapNotes,
  };

  // Write JSON file
  final file = File(outputPath);
  await file.writeAsString(
    JsonEncoder.withIndent('  ').convert(xmapData),
  );

  // Debug logs
  final midiDeltas = xmapNotes.map((n) => n['midiDelta'] as int).toList();
  final roundedGap = (gapBetweenPatterns * 100).round() / 100.0;
  print('[PATTERN_GEN] exerciseId=$exerciseId');
  print('[PATTERN_GEN] rootMidi=$rootMidi (for debugging only)');
  print('[PATTERN_GEN] noteCount=${xmapNotes.length}');
  print('[PATTERN_GEN] patternDurationSec=${patternDurationSec.toStringAsFixed(2)}');
  print('[PATTERN_GEN] gapBetweenPatterns=${roundedGap.toStringAsFixed(2)} (from exercises.json)');
  print('[PATTERN_GEN] midiDeltas=$midiDeltas');
  if (detectedGapSec != null) {
    print('[PATTERN_GEN] boundaryGapSec=${detectedGapSec.toStringAsFixed(3)}');
  }
  print('[PATTERN_GEN] output file: ${file.absolute.path}');

  return file;
}
