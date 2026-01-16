import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'sine_sweep_service.dart';

/// Generates preview audio using sine waves (tones and sweeps).
/// Used for exercise previews that should be clean sine waves, not MIDI instruments.
class SinePreviewAudioGenerator {
  final SineSweepService _sweepService;
  final int sampleRate;

  SinePreviewAudioGenerator({this.sampleRate = 44100})
      : _sweepService = SineSweepService(sampleRate: 44100);

  /// Generate a single tone WAV file.
  /// [noteMidi]: MIDI note number (e.g., 60 = C4)
  /// [durationMs]: Duration of the tone in milliseconds
  /// [leadInMs]: Lead-in silence before the tone (default: 2000ms)
  /// [fadeMs]: Fade in/out duration in milliseconds (default: 10ms)
  Future<String> generateToneWav({
    required double noteMidi,
    required int durationMs,
    int leadInMs = 2000,
    int fadeMs = 10,
  }) async {
    final durationSeconds = durationMs / 1000.0;
    final fadeSeconds = fadeMs / 1000.0;
    final leadInSeconds = leadInMs / 1000.0;

    // Generate the tone
    final toneSamples = _sweepService.generateSineSweep(
      midiStart: noteMidi,
      midiEnd: noteMidi, // Same start and end = steady tone
      durationSeconds: durationSeconds,
      amplitude: 0.2,
      fadeSeconds: fadeSeconds,
    );

    // Prepend lead-in silence
    final leadInFrames = (leadInSeconds * sampleRate).round();
    final totalFrames = leadInFrames + toneSamples.length;
    final allSamples = Float32List(totalFrames);
    allSamples.setRange(leadInFrames, totalFrames, toneSamples);

    // Encode to WAV
    final wavBytes = _sweepService.encodeWav16Mono(allSamples);
    final dir = await getTemporaryDirectory();
    final path = p.join(
        dir.path,
        'preview_tone_${noteMidi.toInt()}_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }

  /// Generate a sweep WAV file (continuous glide).
  /// [startMidi]: Starting MIDI note
  /// [endMidi]: Ending MIDI note
  /// [durationMs]: Duration of the sweep in milliseconds
  /// [leadInMs]: Lead-in silence before the sweep (default: 2000ms)
  /// [fadeMs]: Fade in/out duration in milliseconds (default: 10ms)
  Future<String> generateSweepWav({
    required double startMidi,
    required double endMidi,
    required int durationMs,
    int leadInMs = 2000,
    int fadeMs = 10,
  }) async {
    final durationSeconds = durationMs / 1000.0;
    final fadeSeconds = fadeMs / 1000.0;
    final leadInSeconds = leadInMs / 1000.0;

    // Generate the sweep
    final sweepSamples = _sweepService.generateSineSweep(
      midiStart: startMidi,
      midiEnd: endMidi,
      durationSeconds: durationSeconds,
      amplitude: 0.2,
      fadeSeconds: fadeSeconds,
    );

    // Prepend lead-in silence
    final leadInFrames = (leadInSeconds * sampleRate).round();
    final totalFrames = leadInFrames + sweepSamples.length;
    final allSamples = Float32List(totalFrames);
    allSamples.setRange(leadInFrames, totalFrames, sweepSamples);

    // Encode to WAV
    final wavBytes = _sweepService.encodeWav16Mono(allSamples);
    final dir = await getTemporaryDirectory();
    final path = p.join(
        dir.path,
        'preview_sweep_${startMidi.toInt()}_${endMidi.toInt()}_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }

  /// Generate a composite WAV from multiple segments.
  /// Each segment can be a tone, sweep, or silence.
  Future<String> generateCompositeWav({
    required List<CompositeSegment> segments,
    int leadInMs = 2000,
  }) async {
    final leadInSeconds = leadInMs / 1000.0;
    final leadInFrames = (leadInSeconds * sampleRate).round();

    final allSamples = <Float32List>[];
    allSamples.add(Float32List(leadInFrames)); // Lead-in silence

    for (final segment in segments) {
      Float32List segmentSamples;
      switch (segment.type) {
        case CompositeSegmentType.tone:
          segmentSamples = _sweepService.generateSineSweep(
            midiStart: segment.startMidi!,
            midiEnd: segment.startMidi!,
            durationSeconds: segment.durationSeconds,
            amplitude: 0.2,
            fadeSeconds: 0.01,
          );
          break;
        case CompositeSegmentType.sweep:
          segmentSamples = _sweepService.generateSineSweep(
            midiStart: segment.startMidi!,
            midiEnd: segment.endMidi!,
            durationSeconds: segment.durationSeconds,
            amplitude: 0.2,
            fadeSeconds: 0.01,
          );
          break;
        case CompositeSegmentType.silence:
          segmentSamples = Float32List((segment.durationSeconds * sampleRate).round());
          break;
      }
      allSamples.add(segmentSamples);
    }

    // Concatenate all samples
    final totalLength = allSamples.fold<int>(0, (sum, samples) => sum + samples.length);
    final result = Float32List(totalLength);
    int offset = 0;
    for (final samples in allSamples) {
      result.setRange(offset, offset + samples.length, samples);
      offset += samples.length;
    }

    // Encode to WAV
    final wavBytes = _sweepService.encodeWav16Mono(result);
    final dir = await getTemporaryDirectory();
    final path = p.join(
        dir.path,
        'preview_composite_${DateTime.now().millisecondsSinceEpoch}.wav');
    final file = File(path);
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }
}

enum CompositeSegmentType {
  tone,
  sweep,
  silence,
}

class CompositeSegment {
  final CompositeSegmentType type;
  final double durationSeconds;
  final double? startMidi;
  final double? endMidi;

  CompositeSegment({
    required this.type,
    required this.durationSeconds,
    this.startMidi,
    this.endMidi,
  });

  factory CompositeSegment.tone({
    required double midi,
    required double durationSeconds,
  }) {
    return CompositeSegment(
      type: CompositeSegmentType.tone,
      durationSeconds: durationSeconds,
      startMidi: midi,
    );
  }

  factory CompositeSegment.sweep({
    required double startMidi,
    required double endMidi,
    required double durationSeconds,
  }) {
    return CompositeSegment(
      type: CompositeSegmentType.sweep,
      durationSeconds: durationSeconds,
      startMidi: startMidi,
      endMidi: endMidi,
    );
  }

  factory CompositeSegment.silence({
    required double durationSeconds,
  }) {
    return CompositeSegment(
      type: CompositeSegmentType.silence,
      durationSeconds: durationSeconds,
    );
  }
}
