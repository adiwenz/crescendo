import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/reference_note.dart';
import '../models/harmonic_models.dart';
import '../services/harmonic_functions.dart';
import '../audio/wav_writer.dart';
import '../utils/audio_constants.dart';

/// Service for rendering MIDI notes to WAV and mixing with recorded audio.
/// Optimized for the new 48kHz hardware-synchronized standard.
class ReviewAudioBounceService {
  static const int defaultSampleRate = AudioConstants.audioSampleRate;
  static const double fadeInOutMs = 8.0; // 8ms fade in/out per note
  
  // Sine Lookup Table for performance optimization
  static const int _sineTableSize = 4096;
  static final Float32List _sineTable = _generateSineTable();
  
  static Float32List _generateSineTable() {
    final table = Float32List(_sineTableSize);
    for (var i = 0; i < _sineTableSize; i++) {
      table[i] = math.sin(2 * math.pi * i / _sineTableSize).toDouble();
    }
    return table;
  }
  
  /// Optimized sine function using lookup table
  @pragma('vm:prefer-inline')
  double _fastSin(double phase) {
    // phase is [0, 1]
    final index = (phase * _sineTableSize).toInt() & (_sineTableSize - 1);
    return _sineTable[index];
  }
  
  /// Generate a cache key for the bounced audio
  static String generateCacheKey({
    required String takeFileName,
    required String exerciseId,
    required int transposeSemitones,
    required int sampleRate,
    double renderStartSec = 0.0,
  }) {
    final keyString = '$takeFileName|$exerciseId|$transposeSemitones|$sampleRate|${renderStartSec.toStringAsFixed(3)}';
    final bytes = utf8.encode(keyString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
  
  static Future<Directory> getCacheDirectory() async {
    final cacheDir = await getApplicationCacheDirectory();
    final bounceDir = Directory(p.join(cacheDir.path, 'review_bounces'));
    if (!await bounceDir.exists()) {
      await bounceDir.create(recursive: true);
    }
    return bounceDir;
  }
  
  static Future<File?> getCachedMixedWav(String cacheKey) async {
    final cacheDir = await getCacheDirectory();
    final cachedFile = File(p.join(cacheDir.path, '${cacheKey}_mixed.wav'));
    if (await cachedFile.exists()) {
      return cachedFile;
    }
    return null;
  }
  
  /// Render reference notes to WAV file.
  /// Standardized at 48kHz for perfect hardware sync.
  Future<File> renderReferenceWav({
    required List<ReferenceNote> notes,
    List<ReferenceNote> harmonyNotes = const [],
    required double durationSec,
    required int sampleRate,
    String? savePath,
  }) async {
    final startTime = DateTime.now();
    
    // 0. Constants for Sync Signal (Piloting)
    final syncToneDuration = AudioConstants.chirpDurationSec;
    final totalSyncOffset = AudioConstants.totalChirpOffsetSec;
    
    // 1. Generate float samples (synthesis)
    final samples = _generateSamples(
      notes: notes,
      harmonyNotes: harmonyNotes,
      sampleRate: sampleRate,
      durationSec: durationSec + totalSyncOffset,
      timeOffsetSec: totalSyncOffset,
    );
    
    // 1b. Inject Sync Tone
    _injectSyncTone(samples, sampleRate, syncToneDuration);
    
    // 2. Convert to 16-bit PCM in-place
    final pcmSamples = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      // Inline clamping and scaling
      if (s >= 1.0) {
        pcmSamples[i] = 32767;
      } else if (s <= -1.0) {
        pcmSamples[i] = -32768;
      } else {
        pcmSamples[i] = (s * 32767.0).toInt();
      }
    }
    
    // 3. Write WAV file
    final String finalPath;
    if (savePath != null) {
      finalPath = savePath;
    } else {
      final cacheDir = await getCacheDirectory();
      finalPath = p.join(cacheDir.path, 'reference_${DateTime.now().millisecondsSinceEpoch}.wav');
    }

    await WavWriter.writePcm16Mono(
      samples: pcmSamples,
      sampleRate: sampleRate,
      path: finalPath,
    );
    
    final elapsed = DateTime.now().difference(startTime);
    debugPrint('[ReviewBounce] Reference WAV rendered in ${elapsed.inMilliseconds}ms at ${sampleRate}Hz');
    
    return File(finalPath);
  }

  /// Render audio using tick-based scheduling for precise rhythm and modulation.
  Future<File> renderTickBasedWav({
    required List<ReferenceNote> melodyNotes,
    required List<TickChordEvent> chordEvents,
    required List<TickModulationEvent> modEvents,
    required int initialRootMidi,
    required double durationSec,
    required int sampleRate,
    String? savePath,
  }) async {
    final startTime = DateTime.now();

    // 0. Constants for Sync Signal
    final syncToneDuration = AudioConstants.chirpDurationSec;
    final totalSyncOffset = AudioConstants.totalChirpOffsetSec;

    // 1. Generate float samples
    final samples = _generateTickBasedSamples(
      melodyNotes: melodyNotes,
      chordEvents: chordEvents,
      modEvents: modEvents,
      initialRootMidi: initialRootMidi,
      sampleRate: sampleRate,
      durationSec: durationSec + totalSyncOffset,
      timeOffsetSec: totalSyncOffset,
    );

    // 1b. Inject Sync Tone
    _injectSyncTone(samples, sampleRate, syncToneDuration);

    // 2. Convert to 16-bit PCM
    final pcmSamples = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      if (s >= 1.0) {
        pcmSamples[i] = 32767;
      } else if (s <= -1.0) {
        pcmSamples[i] = -32768;
      } else {
        pcmSamples[i] = (s * 32767.0).toInt();
      }
    }

    // 3. Write WAV
    final String finalPath;
    if (savePath != null) {
      finalPath = savePath;
    } else {
      final cacheDir = await getCacheDirectory();
      finalPath = p.join(cacheDir.path, 'reference_tick_${DateTime.now().millisecondsSinceEpoch}.wav');
    }

    await WavWriter.writePcm16Mono(
      samples: pcmSamples,
      sampleRate: sampleRate,
      path: finalPath,
    );
    
    debugPrint('[ReviewBounce] Tick-Based WAV rendered in ${DateTime.now().difference(startTime).inMilliseconds}ms');
    return File(finalPath);
  }

  Float32List _generateTickBasedSamples({
    required List<ReferenceNote> melodyNotes,
    required List<TickChordEvent> chordEvents,
    required List<TickModulationEvent> modEvents,
    required int initialRootMidi,
    required int sampleRate,
    required double durationSec,
    required double timeOffsetSec,
  }) {
    final totalFrames = (durationSec * sampleRate).ceil();
    final samples = Float32List(totalFrames);
    
    // Setup Musical Clock (Hardcoded to 120 BPM for now as per plan)
    const bpm = 120;
    const clock = MusicalClock(bpm: bpm, timeSignatureTop: 4, sampleRate: AudioConstants.audioSampleRate);
    final samplesPerTick = clock.samplesPerTick;

    // --- 1. Render Melody (Existing time-based approach is fine for melody which allows free movement) ---
    // We render melody first directly into buffer
    // Helper to mix notes into buffer
    void mixMelody(List<ReferenceNote> layerNotes, double amplitudeScale) {
        final fadeFrames = ((fadeInOutMs / 1000.0) * sampleRate).toInt();
        final invSampleRate = 1.0 / sampleRate;
        
        for (final note in layerNotes) {
          final startFrame = ((note.startSec + timeOffsetSec) * sampleRate).toInt();
          final endFrame = math.min(((note.endSec + timeOffsetSec) * sampleRate).toInt(), totalFrames);
          final noteFrames = endFrame - startFrame;
          
          if (noteFrames <= 0 || startFrame >= totalFrames) continue;
          
          final hz = 440.0 * math.pow(2.0, (note.midi - 69.0) / 12.0);
          
          // Phases
          var p1 = 0.0, p2 = 0.0, p3 = 0.0, p4 = 0.0;
          final p1Cr = hz * invSampleRate;
          
          for (var f = 0; f < noteFrames; f++) {
            final frameIndex = startFrame + f;
            if (frameIndex >= totalFrames) break;
            
            final noteTime = f * invSampleRate;
            final fundamental = _fastSin(p1);
            final harmonic2 = 0.6 * _fastSin(p2);
            final harmonic3 = 0.3 * _fastSin(p3);
            final harmonic4 = 0.15 * _fastSin(p4); // Thinner melody
            
            p1 += p1Cr; p1 -= p1.floor();
            p2 += p1Cr * 2; p2 -= p2.floor();
            p3 += p1Cr * 3; p3 -= p3.floor();
            p4 += p1Cr * 4; p4 -= p4.floor();

            final attack = (noteTime * 50.0);
            final env = (attack < 1.0 ? attack : 1.0) * math.exp(-3.0 * noteTime);
            final val = amplitudeScale * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
            
            double fade = 1.0;
            if (f < fadeFrames) fade = f / fadeFrames;
            else if (f >= noteFrames - fadeFrames) fade = (noteFrames - f) / fadeFrames;
            
            samples[frameIndex] += (val * fade);
          }
        }
    }
    mixMelody(melodyNotes, 0.45);

    // --- 2. Render Harmony (Tick-Based) ---
    // State
    var currentRootMidi = initialRootMidi; // Starts here
    final activeVoices = <int, _VoiceState>{}; // midi -> state
    
    // Sort events by tick
    chordEvents.sort((a, b) => a.startTick.compareTo(b.startTick));
    modEvents.sort((a, b) => a.tick.compareTo(b.tick));
    
    int chordEventIdx = 0;
    int modEventIdx = 0;
    
    // Offset in ticks to account for the sync chirp time
    // We need to shift musical time forward so tick 0 aligns with timeOffsetSec in the buffer
    final offsetSamples = (timeOffsetSec * sampleRate).round();

    for (var i = 0; i < totalFrames; i++) {
      // Calculate current tick relative to music start
      // i = buffer index
      // music sample index = i - offsetSamples
      final musicSampleIdx = i - offsetSamples;
      
      // Don't render harmony during lead-in silence before music starts
      if (musicSampleIdx < 0) continue; 
      
      final currentTick = (musicSampleIdx / samplesPerTick).floor();
      
      // 1. Process Modulations (Instantaneous at tick boundary)
      while (modEventIdx < modEvents.length && modEvents[modEventIdx].tick <= currentTick) {
        final mod = modEvents[modEventIdx];
        // Only apply if this is the *first* sample of this tick or we passed it
        // To prevent re-applying, we track index. 
        // Logic: if event.tick <= currentTick, apply it.
        // Wait, currentKey is stateful. We must apply strictly when tick transitions.
        // Actually, sorting and applying as we pass the tick is correct.
        // But we iterate per sample. 
        // Optimization: checking "modEvents[modEventIdx].tick == currentTick" is safer if we want to apply ONCE.
        // But if we skip samples (unlikely here), we might miss it.
        // Better: Process events that are "due".
        
        // Since we are iterating strictly monotonic i, we can just check if we reached the tick.
        // However, "currentTick" stays same for many samples.
        // We need to apply ONLY when we first enter the tick.
        
        // Check if this is the first sample of the tick
        final tickStartSample = (currentTick * samplesPerTick).ceil();
        if (musicSampleIdx == tickStartSample) {
            currentRootMidi += mod.semitoneDelta;
            // Also need to re-voice active chords? 
            // Usually modulations happen between chords or on chord changes.
            // If a chord is holding, shifting key underneath it is weird unless intended.
            // For now, assume chord events align with modulations.
        }
        
        // Advance index only after the tick is fully passed? 
        // No, we just need to ensure we don't re-process.
        // The issue is: currentTick increments.
        // If we process modEvents[idx] when currentTick >= event.tick, we increment idx.
        // But we are in a loop for samples. We only want to increment idx ONCE.
        
        // Correct Logic:
        // We only process events whose tick == currentTick AND we are at the start of that tick.
        // OR we simply maintain state outside the loop and update when constraints met.
        // Simpler: Pre-calculate "events at sample X".
        // Or check `if (musicSampleIdx == (modEvents[modEventIdx].tick * samplesPerTick).ceil())`
        
        // Let's use the explicit sample check for robustness
        final triggerSample = (mod.tick * samplesPerTick).ceil();
        if (musicSampleIdx == triggerSample) {
           currentRootMidi += mod.semitoneDelta;
           modEventIdx++;
        } else if (musicSampleIdx > triggerSample) {
           // We somehow missed it (shouldn't happen in single step loop), apply and move on
            currentRootMidi += mod.semitoneDelta;
            modEventIdx++;
        } else {
           break; // Not yet
        }
      }

      // 2. Process Chord Events
      // We manage active voices based on active chord events
      // This might be expensive to search every sample.
      // Better: Maintain list of "active chord notes".
      // When `musicSampleIdx` hits a chord start/end, update active notes.
      
      // Clean up finished chords
      // This is also event based. 
      // Better approach: Pre-calculate all note-on/note-off events in samples.
      
      // Refactoring slightly for performance:
      // Inside this loop is too slow for logic. 
      // Let's just synthesize "active voices" and update the set of active voices when events trigger.
      
      // Check for New Chords
      while (chordEventIdx < chordEvents.length) {
         final event = chordEvents[chordEventIdx];
         final startSample = (event.startTick * samplesPerTick).ceil();
         
         if (musicSampleIdx == startSample) {
            // Chord Starting!
            // Calculate actual MIDI notes based on CURRENT key
            final midiNotes = HarmonicFunctions.getChordNotes(
               chord: event.chord,
               keyRootMidi: currentRootMidi,
               isMinorKey: false,
               octaveOffset: event.octaveOffset
            );
            
            final endSample = ((event.startTick + event.durationTicks) * samplesPerTick).ceil();
            
            for (final midi in midiNotes) {
               final key = midi; // voice key
               // Overwrite/Add voice
               activeVoices[key] = _VoiceState(
                 midi: midi,
                 startSample: musicSampleIdx,
                 endSample: endSample,
                 phase: activeVoices[key]?.phase ?? 0.0, // Continue phase if same note (legato)
               );
            }
            chordEventIdx++;
         } else if (musicSampleIdx > startSample) {
            chordEventIdx++; // Catchup
         } else {
            break;
         }
      }
      
      // 3. Synthesize Active Voices
      final invSampleRate = 1.0 / sampleRate;
      
      // Use toList to allow removal
      final keys = activeVoices.keys.toList();
      for (final key in keys) {
         final voice = activeVoices[key]!;
         
         // Remove if finished
         if (musicSampleIdx >= voice.endSample) {
            activeVoices.remove(key);
            continue;
         }
         
         // Synthesize
         final hz = 440.0 * math.pow(2.0, (voice.midi - 69.0) / 12.0);
         final phaseInc = hz * invSampleRate;
         
         final fundamental = _fastSin(voice.phase);
         final h2 = 0.5 * _fastSin((voice.phase * 2) % 1.0);
         final h3 = 0.25 * _fastSin((voice.phase * 3) % 1.0);
         
         voice.phase = (voice.phase + phaseInc);
         voice.phase -= voice.phase.floor();
         
         // Envelope (ADSR ish)
         double amp = 0.15; // Background level
         
         // Attack (20ms)
         final samplesSinceStart = musicSampleIdx - voice.startSample;
         if (samplesSinceStart < (0.02 * sampleRate)) {
            amp *= (samplesSinceStart / (0.02 * sampleRate));
         }
         
         // Release (20ms before end)
         final samplesUntilEnd = voice.endSample - musicSampleIdx;
         if (samplesUntilEnd < (0.02 * sampleRate)) {
            amp *= (samplesUntilEnd / (0.02 * sampleRate));
         }
         
         samples[i] += amp * (fundamental + h2 + h3);
      }
    }
    
    return samples;
  }
  /// Optimized samples generation
  Float32List _generateSamples({
    required List<ReferenceNote> notes,
    List<ReferenceNote> harmonyNotes = const [],
    required int sampleRate,
    required double durationSec,
    double timeOffsetSec = 0.0,
  }) {
    final totalFrames = (durationSec * sampleRate).ceil();
    final samples = Float32List(totalFrames);
    final fadeFrames = ((fadeInOutMs / 1000.0) * sampleRate).toInt();
    final invSampleRate = 1.0 / sampleRate;

    // Helper to mix notes into buffer
    void mixNotes(List<ReferenceNote> layerNotes, double amplitudeScale) {
        for (final note in layerNotes) {
          final startFrame = ((note.startSec + timeOffsetSec) * sampleRate).toInt();
          final endFrame = math.min(((note.endSec + timeOffsetSec) * sampleRate).toInt(), totalFrames);
          final noteFrames = endFrame - startFrame;
          
          if (noteFrames <= 0 || startFrame >= totalFrames) continue;
          
          final hz = 440.0 * math.pow(2.0, (note.midi - 69.0) / 12.0);
          
          // Pre-calculate phase increments (normalized to [0, 1])
          final p1Cr = hz * invSampleRate;
          final p2Cr = p1Cr * 2.0;
          final p3Cr = p1Cr * 3.0;
          final p4Cr = p1Cr * 4.0;
          
          double p1 = 0.0, p2 = 0.0, p3 = 0.0, p4 = 0.0;
          
          for (var f = 0; f < noteFrames; f++) {
            final frameIndex = startFrame + f;
            if (frameIndex >= totalFrames) break;
            
            final noteTime = f * invSampleRate;
            
            // Sum harmonics using fast lookup
            final fundamental = _fastSin(p1);
            final harmonic2 = 0.6 * _fastSin(p2);
            final harmonic3 = 0.3 * _fastSin(p3);
            final harmonic4 = 0.15 * _fastSin(p4);
            
            // Advance phases
            p1 = (p1 + p1Cr); p1 -= p1.floor();
            p2 = (p2 + p2Cr); p2 -= p2.floor();
            p3 = (p3 + p3Cr); p3 -= p3.floor();
            p4 = (p4 + p4Cr); p4 -= p4.floor();
            
            // Envelope: 20ms attack, exponential decay
            final attack = (noteTime * 50.0); // 1.0 / 0.02
            final env = (attack < 1.0 ? attack : 1.0) * math.exp(-3.0 * noteTime);
            final val = amplitudeScale * env * (fundamental + harmonic2 + harmonic3 + harmonic4);
            
            // Apply fade in/out
            double fade = 1.0;
            if (f < fadeFrames) {
              fade = f / fadeFrames;
            } else if (f >= noteFrames - fadeFrames) {
              fade = (noteFrames - f) / fadeFrames;
            }
            
            samples[frameIndex] += (val * fade);
          }
        }
    }

    // Mix Melody (0.45 amplitude)
    mixNotes(notes, 0.45);
    
    // Mix Harmony (0.15 amplitude - background)
    if (harmonyNotes.isNotEmpty) {
      mixNotes(harmonyNotes, 0.15);
    }
    
    return samples;
  }
  
  void _injectSyncTone(Float32List samples, int sampleRate, double durationSec) {
    // Generate 19kHz ultrasonic sine wave (near Nyquist limit of 24kHz)
    final frames = (durationSec * sampleRate).toInt();
    final invSampleRate = 1.0 / sampleRate;
    const freq = 19000.0; 
    
    double phase = 0.0;
    final phaseInc = freq * invSampleRate;
    
    // Apply short fade in/out to avoid popping
    final fadeFrames = (0.002 * sampleRate).toInt(); // 2ms fade

    for (var i = 0; i < frames; i++) {
        if (i >= samples.length) break;
        
        final val = _fastSin(phase);
        phase = (phase + phaseInc); 
        phase -= phase.floor();
        
        double amp = 0.8; 
        
        // envelope
        if (i < fadeFrames) {
           amp *= (i / fadeFrames);
        } else if (i >= frames - fadeFrames) {
           amp *= ((frames - i) / fadeFrames);
        }
        
        samples[i] = val * amp;
    }
  }
  
  /// Mix two WAV files sample-by-sample (Optimized)
  Future<File> mixWavs({
    required File micWav,
    required File referenceWav,
    required double micGain,
    required double refGain,
    required double renderStartSec,
    required double durationSec,
    double micOffsetSec = 0.0,
    double refOffsetSec = 0.0,
    bool duckMicWhileRef = false,
  }) async {
    final startTime = DateTime.now();
    
    // Read both WAV files
    final micBytes = await micWav.readAsBytes();
    final refBytes = await referenceWav.readAsBytes();
    
    final micWavInfo = _parseWavHeader(micBytes);
    final refWavInfo = _parseWavHeader(refBytes);
    
    if (micWavInfo == null || refWavInfo == null) {
      throw Exception('Failed to parse WAV headers');
    }
    
    final sampleRate = refWavInfo.sampleRate; // Target rate matches reference (usually 48kHz)
    
    // Read samples as float [-1.0, 1.0]
    var micSamples = _readWavSamples(micBytes, micWavInfo);
    var refSamples = _readWavSamples(refBytes, refWavInfo);
    
    // Resample Mic if needed
    if (micWavInfo.sampleRate != sampleRate) {
      micSamples = _resample(micSamples, micWavInfo.sampleRate, sampleRate);
    }

    // Resample Ref if needed 
    if (refWavInfo.sampleRate != sampleRate) {
       refSamples = _resample(refSamples, refWavInfo.sampleRate, sampleRate);
    }
    
    // Windowing Logic
    final renderStartSamples = (renderStartSec * sampleRate).round();
    final outputLength = (durationSec * sampleRate).round();
    final micOffsetSamples = (micOffsetSec * sampleRate).round();
    final refOffsetSamples = (refOffsetSec * sampleRate).round();
    
    final pcmSamples = Int16List(outputLength);
    
    // Mix and convert to Int16 in one pass with windowing
    for (var i = 0; i < outputLength; i++) {
      // t is the absolute time in samples from 0.0 of the timeline
      final t = i + renderStartSamples;
      
      final micIdx = t - micOffsetSamples;
      final refIdx = t - refOffsetSamples;
      
      var micVal = (micIdx >= 0 && micIdx < micSamples.length) ? micSamples[micIdx] * micGain * 8.0 : 0.0;
      final refVal = (refIdx >= 0 && refIdx < refSamples.length) ? refSamples[refIdx] * refGain : 0.0;
      
      if (duckMicWhileRef && refVal.abs() > 0.001) {
        micVal *= 0.3;
      }
      
      final mixed = (micVal + refVal);
      // Inline clamping and scaling
      if (mixed >= 1.0) {
        pcmSamples[i] = 32767;
      } else if (mixed <= -1.0) {
        pcmSamples[i] = -32768;
      } else {
        pcmSamples[i] = (mixed * 32767.0).toInt();
      }
    }
    
    final cacheDir = await getCacheDirectory();
    final mixedFile = File(p.join(cacheDir.path, 'mixed_${DateTime.now().millisecondsSinceEpoch}.wav'));
    await WavWriter.writePcm16Mono(
      samples: pcmSamples,
      sampleRate: sampleRate,
      path: mixedFile.path,
    );
    
    debugPrint('[ReviewBounce] Mixed WAV created in ${DateTime.now().difference(startTime).inMilliseconds}ms');
    return mixedFile;
  }

  Float32List _resample(Float32List input, int fromRate, int toRate) {
    if (fromRate == toRate) return input;
    final ratio = toRate / fromRate;
    final outputLength = (input.length * ratio).round();
    final output = Float32List(outputLength);
    for (var i = 0; i < outputLength; i++) {
      final inputPos = i / ratio;
      final idx = inputPos.floor();
      final frac = inputPos - idx;
      if (idx >= input.length - 1) {
        output[i] = idx < input.length ? input[idx] : 0.0;
      } else {
        final s1 = input[idx];
        final s2 = input[idx + 1];
        output[i] = s1 + (s2 - s1) * frac;
      }
    }
    return output;
  }
  
  _WavInfo? _parseWavHeader(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;

    int offset = 12;
    int? dataOffset, dataSize, sampleRate, channels, bitsPerSample;

    while (offset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readUint32(bytes, offset + 4);

      if (chunkId == 'fmt ') {
        if (_readUint16(bytes, offset + 8) != 1) return null;
        channels = _readUint16(bytes, offset + 10);
        sampleRate = _readUint32(bytes, offset + 12);
        bitsPerSample = _readUint16(bytes, offset + 22);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 == 1) offset++;
    }

    if (dataOffset == null || dataSize == null || sampleRate == null || channels == null || bitsPerSample == null) return null;
    return _WavInfo(sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample, dataOffset: dataOffset, dataSize: dataSize);
  }
  
  static int _readUint16(Uint8List bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8);
  static int _readUint32(Uint8List bytes, int offset) => bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
  
  Float32List _readWavSamples(Uint8List bytes, _WavInfo info) {
    final dataBytes = bytes.sublist(info.dataOffset, math.min(info.dataOffset + info.dataSize, bytes.length));
    if (info.bitsPerSample == 16) {
      final int16Samples = Int16List.view(dataBytes.buffer, dataBytes.offsetInBytes, dataBytes.length ~/ 2);
      final list = Float32List(int16Samples.length);
      for (var i = 0; i < int16Samples.length; i++) {
        list[i] = int16Samples[i] / 32768.0;
      }
      return list;
    }
    throw Exception('Unsupported bits: ${info.bitsPerSample}');
  }
}

class _WavInfo {
  final int sampleRate, channels, bitsPerSample, dataOffset, dataSize;
  _WavInfo({required this.sampleRate, required this.channels, required this.bitsPerSample, required this.dataOffset, required this.dataSize});
}

class _VoiceState {
  final int midi;
  final int startSample;
  final int endSample;
  double phase;
  
  _VoiceState({
    required this.midi,
    required this.startSample,
    required this.endSample,
    this.phase = 0.0,
  });
}
