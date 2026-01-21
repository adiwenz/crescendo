#!/usr/bin/env dart

/// Helper script to extract exercise definitions from exercise_seed.dart
/// and convert them to JSON format for use by generate_exercise_m4as.dart
///
/// This script must be run from within a Flutter environment (e.g., flutter run)
/// because it imports Flutter-dependent code.
///
/// Usage (from Flutter app context):
///   flutter run tool/extract_exercises_to_json.dart
///
/// Or manually create tool/exercises.json based on tool/exercises.json.example

import 'dart:convert';
import 'dart:io';
import '../lib/data/exercise_seed.dart';
import '../lib/models/vocal_exercise.dart';

void main() {
  print('Extracting exercises to JSON...');
  
  final exercises = seedVocalExercises();
  final exercisesJson = exercises.map((e) => _exerciseToJson(e)).toList();
  
  final output = {
    'exercises': exercisesJson,
  };
  
  final jsonFile = File('tool/exercises.json');
  jsonFile.writeAsStringSync(
    JsonEncoder.withIndent('  ').convert(output),
  );
  
  print('✓ Extracted ${exercisesJson.length} exercises to tool/exercises.json');
  print('');
  print('Now you can run: dart run tool/generate_exercise_m4as.dart');
}

Map<String, dynamic> _exerciseToJson(VocalExercise exercise) {
  final json = <String, dynamic>{
    'id': exercise.id,
    'name': exercise.name,
    'isGlide': exercise.isGlide,
  };
  
  if (exercise.highwaySpec != null) {
    json['highwaySpec'] = {
      'segments': exercise.highwaySpec!.segments.map((s) => {
        'startMs': s.startMs,
        'endMs': s.endMs,
        'midiNote': s.midiNote,
        'toleranceCents': s.toleranceCents,
        'label': s.label,
        'startMidi': s.startMidi,
        'endMidi': s.endMidi,
      }).toList(),
    };
  }
  
  return json;
}
