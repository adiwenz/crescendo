#!/usr/bin/env dart

/// CLI tool to generate full-range M4A reference audio files for exercises.
///
/// Usage:
///   dart run tool/generate_exercise_m4as.dart
///   dart run tool/generate_exercise_m4as.dart --force
///   dart run tool/generate_exercise_m4as.dart --out assets/audio/exercises --bitrate 96k
///
/// This script generates:
/// - Full-range M4A files covering C2..C7 for each non-glide exercise
/// - JSON index files mapping MIDI steps to time ranges for slicing
///
/// Requires ffmpeg to be installed and available in PATH.

import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

// Configuration
const int defaultSampleRate = 8000;
const String defaultBitrate = '64k';
const int defaultMinMidi = 36; // C2
const int defaultMaxMidi = 96; // C7
const double fadeInOutMs = 8.0; // 8ms fade per note
const double amplitude = 0.3; // Safe volume level
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
    required this.gapBetweenRepetitionsSec,
  });
}

class _PitchHighwaySpec {
  final List<_PitchSegment> segments;

  _PitchHighwaySpec({required this.segments});
}

void main(List<String> args) async {
  // Parse arguments
  final argsMap = _parseArgs(args);
  final outputDir = argsMap['out'] as String? ?? 'assets/audio/exercises';
  final force = argsMap['force'] as bool? ?? false;
  final bitrate = argsMap['bitrate'] as String? ?? defaultBitrate;
  final sampleRate =
      int.parse(argsMap['sampleRate'] as String? ?? '$defaultSampleRate');
  final minMidi = int.parse(argsMap['minMidi'] as String? ?? '$defaultMinMidi');
  final maxMidi = int.parse(argsMap['maxMidi'] as String? ?? '$defaultMaxMidi');

  print('Exercise M4A Generator');
  print('=====================');
  print('Output: $outputDir');
  print(
      'Range: ${_midiToName(minMidi)} (MIDI $minMidi) to ${_midiToName(maxMidi)} (MIDI $maxMidi)');
  print('Sample rate: $sampleRate Hz');
  print('Bitrate: $bitrate');
  print('Force regenerate: $force');
  print('');

  // Check for ffmpeg
  if (!await _checkFfmpeg()) {
    print('ERROR: ffmpeg not found in PATH.');
    print('Please install ffmpeg:');
    print('  macOS: brew install ffmpeg');
    print('  Linux: sudo apt-get install ffmpeg');
    print('  Windows: Download from https://ffmpeg.org/download.html');
    exit(1);
  }

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
    print(
        'Or manually create tool/exercises.json based on tool/exercises.json.example');
    print('');
    exit(1);
  }

  final nonGlideExercises = exercises.where((e) {
    return e.highwaySpec != null &&
        e.highwaySpec!.segments.isNotEmpty &&
        !e.isGlide &&
        e.id != 'sirens'; // Skip sirens (handled separately)
  }).toList();

  print('Found ${nonGlideExercises.length} non-glide exercises to process');
  print('');

  final startTime = DateTime.now();
  int generated = 0;
  int skipped = 0;
  int errors = 0;

  for (final exercise in nonGlideExercises) {
    final m4aPath = p.join(outputDir, '${exercise.id}_fullrange.m4a');
    final jsonPath = p.join(outputDir, '${exercise.id}_fullrange_index.json');

    // Check if already exists (unless force)
    if (!force &&
        await File(m4aPath).exists() &&
        await File(jsonPath).exists()) {
      print('⏭  Skipping ${exercise.id} (already exists)');
      skipped++;
      continue;
    }

    try {
      print('🎵 Generating ${exercise.id}...');
      final result = await _generateExerciseAudio(
        exercise: exercise,
        minMidi: minMidi,
        maxMidi: maxMidi,
        sampleRate: sampleRate,
        bitrate: bitrate,
        outputDir: outputDir,
      );

      if (result != null) {
        print(
            '   ✓ Generated ${result['m4aSize']} bytes M4A, ${result['duration']}s');
        print('   ✓ Index: ${result['stepCount']} steps');
        generated++;
      } else {
        print('   ✗ Failed to generate');
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
    } else if (arg == '--bitrate' && i + 1 < args.length) {
      map['bitrate'] = args[++i];
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

Future<bool> _checkFfmpeg() async {
  try {
    final result = await Process.run('ffmpeg', ['-version']);
    return result.exitCode == 0;
  } catch (e) {
    return false;
  }
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
// This reads exercise definitions from a JSON file or uses inline definitions
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

  // Fallback: return empty list with instructions
  print('');
  print('NOTE: No exercises.json found. Creating a template...');
  print('Please create tool/exercises.json with exercise definitions.');
  print('See tool/exercises.json.example for format.');
  print('');

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

  // Require gapBetweenRepetitionsSec to be present in JSON
  final gapBetweenRepetitionsSecJson = json['gapBetweenRepetitionsSec'];
  if (gapBetweenRepetitionsSecJson == null) {
    throw Exception(
        'Exercise "${json['id']}" is missing required field "gapBetweenRepetitionsSec" in exercises.json');
  }
  final gapBetweenRepetitionsSec =
      (gapBetweenRepetitionsSecJson as num).toDouble();

  return _VocalExercise(
    id: json['id'] as String,
    name: json['name'] as String,
    highwaySpec: highwaySpec,
    isGlide: json['isGlide'] as bool? ?? false,
    gapBetweenRepetitionsSec: gapBetweenRepetitionsSec,
  );
}

Future<Map<String, dynamic>?> _generateExerciseAudio({
  required _VocalExercise exercise,
  required int minMidi,
  required int maxMidi,
  required int sampleRate,
  required String bitrate,
  required String outputDir,
}) async {
  // Build full-range note sequence using standalone algorithm
  final notes = _buildTransposedSequence(
    exercise: exercise,
    lowestMidi: minMidi,
    highestMidi: maxMidi,
    leadInSec: leadInSec,
    gapBetweenRepetitionsSec: exercise.gapBetweenRepetitionsSec,
  );

  if (notes.isEmpty) {
    print('   ⚠ No notes generated for ${exercise.id}');
    return null;
  }

  // Extract step boundaries by detecting gaps between repetitions
  final steps = <Map<String, dynamic>>[];

  // Sort notes by start time
  final sortedNotes = List<_ReferenceNote>.from(notes)
    ..sort((a, b) => a.startSec.compareTo(b.startSec));

  // Group notes into steps by detecting gaps (gap > 0.5s indicates new step)
  final gapThresholdSec = 0.5;
  var currentStepNotes = <_ReferenceNote>[];
  var currentStepStartSec = sortedNotes.first.startSec;
  var currentStepRootMidi =
      sortedNotes.first.midi; // Approximate root from first note

  for (var i = 0; i < sortedNotes.length; i++) {
    final note = sortedNotes[i];
    final isFirstNote = i == 0;
    final prevNote = isFirstNote ? null : sortedNotes[i - 1];

    final gapSec = isFirstNote ? 0.0 : (note.startSec - prevNote!.endSec);

    if (gapSec > gapThresholdSec && currentStepNotes.isNotEmpty) {
      // End of current step, start new one
      final stepEndSec = currentStepNotes.map((n) => n.endSec).reduce(math.max);
      steps.add({
        'rootMidi': currentStepRootMidi,
        'startSec': currentStepStartSec,
        'endSec': stepEndSec,
      });

      currentStepNotes = [note];
      currentStepStartSec = note.startSec;
      currentStepRootMidi = note.midi;
    } else {
      // Continue current step
      currentStepNotes.add(note);
      // Update root MIDI to lowest note in step (pattern root)
      if (note.midi < currentStepRootMidi) {
        currentStepRootMidi = note.midi;
      }
    }
  }

  // Add final step
  if (currentStepNotes.isNotEmpty) {
    final stepEndSec = currentStepNotes.map((n) => n.endSec).reduce(math.max);
    steps.add({
      'rootMidi': currentStepRootMidi,
      'startSec': currentStepStartSec,
      'endSec': stepEndSec,
    });
  }

  // Calculate total duration
  final totalDurationSec = notes.map((n) => n.endSec).reduce(math.max);

  // Generate WAV file
  final tempDir = await Directory.systemTemp.createTemp('exercise_m4a_gen_');
  final tempWavPath = p.join(tempDir.path, '${exercise.id}.wav');

  try {
    await _renderWav(
      notes: notes,
      sampleRate: sampleRate,
      durationSec: totalDurationSec,
      outputPath: tempWavPath,
    );

    // Convert to M4A
    final m4aPath = p.join(outputDir, '${exercise.id}_fullrange.m4a');
    await _convertWavToM4A(
      wavPath: tempWavPath,
      m4aPath: m4aPath,
      bitrate: bitrate,
      sampleRate: sampleRate,
    );

    // Write index JSON
    final indexPath = p.join(outputDir, '${exercise.id}_fullrange_index.json');
    final indexData = {
      'exerciseId': exercise.id,
      'leadInSec': leadInSec,
      'range': {
        'minMidi': minMidi,
        'maxMidi': maxMidi,
      },
      'steps': steps,
    };
    await File(indexPath).writeAsString(
      JsonEncoder.withIndent('  ').convert(indexData),
    );

    // Note: Visual notes are now generated from pattern JSONs via generate_exercise_xmaps.dart
    // The pattern JSONs are the source of truth for visual rendering

    final m4aFile = File(m4aPath);
    final m4aSize = await m4aFile.length();

    return {
      'm4aSize': m4aSize,
      'duration': totalDurationSec.toStringAsFixed(2),
      'stepCount': steps.length,
    };
  } finally {
    // Clean up temp directory
    await tempDir.delete(recursive: true);
  }
}

// Standalone version of buildTransposedSequence (no Flutter dependencies)
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

Future<void> _renderWav({
  required List<_ReferenceNote> notes,
  required int sampleRate,
  required double durationSec,
  required String outputPath,
}) async {
  final totalFrames = (durationSec * sampleRate).ceil();
  final samples = List<double>.filled(totalFrames, 0.0);
  final fadeFrames = ((fadeInOutMs / 1000.0) * sampleRate).round();

  for (final note in notes) {
    final startFrame = (note.startSec * sampleRate).round();
    final endFrame = math.min((note.endSec * sampleRate).round(), totalFrames);
    final noteFrames = endFrame - startFrame;

    if (noteFrames <= 0 || startFrame < 0 || startFrame >= totalFrames)
      continue;

    final hz = 440.0 * math.pow(2.0, (note.midi - 69.0) / 12.0);

    for (var f = 0; f < noteFrames; f++) {
      final frameIndex = startFrame + f;
      if (frameIndex >= totalFrames) break;

      final noteTime = f / sampleRate;
      final sample = _pianoSample(hz, noteTime);

      // Apply fade in/out
      double fade = 1.0;
      if (f < fadeFrames) {
        fade = f / fadeFrames; // Fade in
      } else if (f >= noteFrames - fadeFrames) {
        fade = (noteFrames - f) / fadeFrames; // Fade out
      }

      samples[frameIndex] += sample * fade;
    }
  }

  // Convert to 16-bit PCM and write WAV
  final int16Samples = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    int16Samples[i] = (clamped * 32767.0).round().clamp(-32768, 32767);
  }

  final wavBytes = _encodeWav16Mono(int16Samples, sampleRate);
  await File(outputPath).writeAsBytes(wavBytes);
}

double _pianoSample(double hz, double noteTime) {
  // Simple piano-like synthesis with attack and decay
  final attack = (noteTime / 0.02).clamp(0.0, 1.0);
  final decay = math.exp(-3.0 * noteTime);
  final env = attack * decay;
  final fundamental = math.sin(2 * math.pi * hz * noteTime);
  final harmonic2 = 0.6 * math.sin(2 * math.pi * hz * 2 * noteTime);
  final harmonic3 = 0.3 * math.sin(2 * math.pi * hz * 3 * noteTime);
  final harmonic4 = 0.15 * math.sin(2 * math.pi * hz * 4 * noteTime);
  return amplitude * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
}

Uint8List _encodeWav16Mono(Int16List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final fileSize = 36 + dataSize;

  final header = ByteData(44);
  var offset = 0;

  // RIFF header
  header.setUint8(offset++, 0x52); // 'R'
  header.setUint8(offset++, 0x49); // 'I'
  header.setUint8(offset++, 0x46); // 'F'
  header.setUint8(offset++, 0x46); // 'F'
  header.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  header.setUint8(offset++, 0x57); // 'W'
  header.setUint8(offset++, 0x41); // 'A'
  header.setUint8(offset++, 0x56); // 'V'
  header.setUint8(offset++, 0x45); // 'E'

  // fmt chunk
  header.setUint8(offset++, 0x66); // 'f'
  header.setUint8(offset++, 0x6D); // 'm'
  header.setUint8(offset++, 0x74); // 't'
  header.setUint8(offset++, 0x20); // ' '
  header.setUint32(offset, 16, Endian.little);
  offset += 4;
  header.setUint16(offset, 1, Endian.little);
  offset += 2; // PCM format
  header.setUint16(offset, 1, Endian.little);
  offset += 2; // mono
  header.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  header.setUint32(offset, sampleRate * 2, Endian.little);
  offset += 4; // byte rate
  header.setUint16(offset, 2, Endian.little);
  offset += 2; // block align
  header.setUint16(offset, 16, Endian.little);
  offset += 2; // bits per sample

  // data chunk
  header.setUint8(offset++, 0x64); // 'd'
  header.setUint8(offset++, 0x61); // 'a'
  header.setUint8(offset++, 0x74); // 't'
  header.setUint8(offset++, 0x61); // 'a'
  header.setUint32(offset, dataSize, Endian.little);

  // Combine header + samples
  final bytes = Uint8List(44 + dataSize);
  bytes.setRange(0, 44, header.buffer.asUint8List());
  bytes.setRange(44, 44 + dataSize, samples.buffer.asUint8List());

  return bytes;
}

Future<void> _convertWavToM4A({
  required String wavPath,
  required String m4aPath,
  required String bitrate,
  required int sampleRate,
}) async {
  final result = await Process.run(
    'ffmpeg',
    [
      '-y', // Overwrite output file
      '-i', wavPath,
      '-c:a', 'aac',
      '-b:a', bitrate,
      '-ac', '1', // Mono
      '-ar', '$sampleRate',
      m4aPath,
    ],
  );

  if (result.exitCode != 0) {
    throw Exception('ffmpeg failed: ${result.stderr}');
  }
}
