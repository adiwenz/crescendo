import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recording_service.dart';
import '../audio/reference_midi_synth.dart';
import '../audio/midi_playback_config.dart';
// Note: AudioSessionDebug was removed - skip iOS audio session dumps for now

/// Sync diagnostic service to measure offset between reference MIDI playback and recorded audio
/// 
/// How to use:
/// 1. Tap "Run Sync Diagnostic" button (debug mode only)
/// 2. Test runs: 2s lead-in, then plays a sharp click at t=2.0s, records for 5s total
/// 3. After recording, analyzes WAV to find click onset
/// 4. Computes offsetMs = detectedClickMs - scheduledClickMs (2000ms)
/// 5. Saves offsetMs to SharedPreferences for use in review playback compensation
/// 
/// Interpreting offsetMs:
/// - Positive offsetMs: recorded audio is LATE relative to scheduled reference (MIDI plays too early)
/// - Negative offsetMs: recorded audio is EARLY relative to scheduled reference (MIDI plays too late)
/// - Typical values: 0-100ms (good sync), 100-300ms (noticeable drift), >300ms (significant issue)
class SyncDiagnosticService {
  static const String _prefsKey = 'sync_offset_ms';
  static const double _leadInSec = 2.0;
  static const double _testDurationSec = 5.0;
  static const double _scheduledClickSec = 2.0;
  static const int _clickMidiNote = 108; // C8 - very high pitch for sharp click
  static const int _clickVelocity = 127; // Maximum velocity
  static const double _clickDurationSec = 0.02; // 20ms click

  /// Run the sync diagnostic test
  /// Returns the computed offset in milliseconds, or null if test failed
  static Future<int?> runDiagnostic() async {
    if (!kDebugMode) {
      debugPrint('[SyncDiag] Diagnostic only available in debug mode');
      return null;
    }

    debugPrint('[SyncDiag] Starting sync diagnostic test...');
    debugPrint('[SyncDiag] Test parameters: leadIn=${_leadInSec}s, duration=${_testDurationSec}s, scheduledClick=${_scheduledClickSec}s');

    try {
      // Dump audio session before starting
      await _dumpAudioSession('before_test');

      // Initialize recording service
      final recorder = RecordingService(owner: 'sync_diag', bufferSize: 512);
      
      // Dump audio session after recorder init
      await _dumpAudioSession('after_recorder_init');

      // Start recording first
      await recorder.start();
      await _dumpAudioSession('after_recording_start');

      // Capture recording start time (this is the timeline anchor for the test)
      final recordingStartEpochMs = DateTime.now().millisecondsSinceEpoch;
      debugPrint('[SyncDiag] Recording started at: $recordingStartEpochMs');

      // Initialize MIDI synth
      final midiSynth = ReferenceMidiSynth();
      await midiSynth.init(config: MidiPlaybackConfig.exercise());
      await _dumpAudioSession('after_midi_init');

      // Schedule click at t=2.0s (relative to recording start)
      final clickScheduledMs = (_scheduledClickSec * 1000).round();
      final clickAbsoluteMs = recordingStartEpochMs + clickScheduledMs;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final delayMs = clickAbsoluteMs - nowMs;

      debugPrint('[SyncDiag] Scheduling click: scheduledClickMs=$clickScheduledMs (relative to recording start), '
          'clickAbsoluteMs=$clickAbsoluteMs, nowMs=$nowMs, delayMs=$delayMs');

      // Schedule click using Timer
      final delayMsClamped = delayMs.clamp(0, 10000);
      Future.delayed(Duration(milliseconds: delayMsClamped), () async {
        await _dumpAudioSession('before_click_play');
        await midiSynth.playClick(
          midiNote: _clickMidiNote,
          velocity: _clickVelocity,
          durationMs: (_clickDurationSec * 1000).round(),
          runId: 1,
        );
        await _dumpAudioSession('after_click_play');
      });

      // Wait for test duration
      await Future.delayed(Duration(milliseconds: (_testDurationSec * 1000).round()));

      // Stop recording and save to specific path
      final dir = await getApplicationDocumentsDirectory();
      final wavPath = p.join(dir.path, 'sync_diag_${recordingStartEpochMs}.wav');
      final result = await recorder.stop(customPath: wavPath);
      await _dumpAudioSession('after_recording_stop');

      if (result.audioPath.isEmpty) {
        debugPrint('[SyncDiag] Recording failed - empty audio path');
        return null;
      }

      debugPrint('[SyncDiag] Recording saved: ${result.audioPath}');

      // Analyze WAV file (use recording start as timeline anchor)
      final offsetMs = await _analyzeWavFile(result.audioPath, recordingStartEpochMs);
      
      if (offsetMs != null) {
        // Save offset to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_prefsKey, offsetMs);
        debugPrint('[SyncDiag] Offset saved to SharedPreferences: ${offsetMs}ms');
      }

      return offsetMs;
    } catch (e, stackTrace) {
      debugPrint('[SyncDiag] Error during diagnostic: $e');
      debugPrint('[SyncDiag] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Get the saved sync offset from SharedPreferences
  static Future<int?> getSavedOffset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_prefsKey)) {
        return prefs.getInt(_prefsKey);
      }
    } catch (e) {
      debugPrint('[SyncDiag] Error reading saved offset: $e');
    }
    return null;
  }

  /// Clear the saved sync offset
  static Future<void> clearSavedOffset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      debugPrint('[SyncDiag] Cleared saved offset');
    } catch (e) {
      debugPrint('[SyncDiag] Error clearing saved offset: $e');
    }
  }

  /// Analyze WAV file to find click onset time
  static Future<int?> _analyzeWavFile(String wavPath, int timelineStartEpochMs) async {
    try {
      final file = File(wavPath);
      if (!await file.exists()) {
        debugPrint('[SyncDiag] WAV file not found: $wavPath');
        return null;
      }

      final bytes = await file.readAsBytes();
      debugPrint('[SyncDiag] WAV file size: ${bytes.length} bytes');

      // Parse WAV header
      final wavInfo = _parseWavHeader(bytes);
      if (wavInfo == null) {
        debugPrint('[SyncDiag] Failed to parse WAV header');
        return null;
      }

      debugPrint('[SyncDiag] WAV info: sampleRate=${wavInfo.sampleRate}, '
          'channels=${wavInfo.channels}, bitsPerSample=${wavInfo.bitsPerSample}, '
          'dataSize=${wavInfo.dataSize}');

      // Find data chunk
      final dataStart = wavInfo.dataOffset;
      final dataEnd = dataStart + wavInfo.dataSize;
      
      if (dataEnd > bytes.length) {
        debugPrint('[SyncDiag] WAV data chunk extends beyond file size');
        return null;
      }

      // Search for click in window 1.8s - 2.5s (around scheduled click at 2.0s)
      final searchStartMs = 1800;
      final searchEndMs = 2500;
      final searchStartSample = (searchStartMs * wavInfo.sampleRate / 1000).round();
      final searchEndSample = (searchEndMs * wavInfo.sampleRate / 1000).round();
      final samplesPerMs = wavInfo.sampleRate / 1000.0;

      // Read samples (16-bit PCM)
      double maxAmplitude = 0.0;
      int maxAmplitudeSample = searchStartSample;
      
      for (int i = searchStartSample; i < searchEndSample && i * 2 + 1 < dataEnd - dataStart; i++) {
        final sampleOffset = dataStart + (i * wavInfo.channels * (wavInfo.bitsPerSample ~/ 8));
        if (sampleOffset + 1 >= bytes.length) break;

        // Read 16-bit signed integer (little-endian)
        final sample = _readInt16(bytes, sampleOffset);
        final amplitude = sample.abs().toDouble();

        if (amplitude > maxAmplitude) {
          maxAmplitude = amplitude;
          maxAmplitudeSample = i;
        }
      }

      // Convert sample index to milliseconds
      final detectedClickMs = (maxAmplitudeSample / samplesPerMs).round();
      final scheduledClickMs = (_scheduledClickSec * 1000).round();
      final offsetMs = detectedClickMs - scheduledClickMs;

      debugPrint('[SyncDiag] scheduledClickMs=$scheduledClickMs, '
          'detectedClickMs=$detectedClickMs, offsetMs=$offsetMs, '
          'sampleRate=${wavInfo.sampleRate}, channels=${wavInfo.channels}, '
          'maxAmplitude=$maxAmplitude');

      return offsetMs;
    } catch (e, stackTrace) {
      debugPrint('[SyncDiag] Error analyzing WAV: $e');
      debugPrint('[SyncDiag] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Parse WAV file header
  static _WavInfo? _parseWavHeader(Uint8List bytes) {
    if (bytes.length < 44) return null;

    // Check RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') return null;

    // Check WAVE format
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') return null;

    // Find fmt chunk
    int offset = 12;
    int? dataOffset;
    int? dataSize;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;

    while (offset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readUint32(bytes, offset + 4);

      if (chunkId == 'fmt ') {
        // Parse fmt chunk
        final audioFormat = _readUint16(bytes, offset + 8);
        if (audioFormat != 1) {
          debugPrint('[SyncDiag] Unsupported audio format: $audioFormat (expected 1 = PCM)');
          return null;
        }
        channels = _readUint16(bytes, offset + 10);
        sampleRate = _readUint32(bytes, offset + 12);
        // byteRate and blockAlign are read but not used (for future validation if needed)
        _readUint32(bytes, offset + 16); // byteRate
        _readUint16(bytes, offset + 20); // blockAlign
        bitsPerSample = _readUint16(bytes, offset + 22);
      } else if (chunkId == 'data') {
        dataOffset = offset + 8;
        dataSize = chunkSize;
        break;
      }

      offset += 8 + chunkSize;
      // Align to even boundary
      if (chunkSize % 2 == 1) offset++;
    }

    if (dataOffset == null || dataSize == null || sampleRate == null || 
        channels == null || bitsPerSample == null) {
      return null;
    }

    return _WavInfo(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataSize: dataSize,
    );
  }

  static int _readUint16(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8);
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  static int _readInt16(Uint8List bytes, int offset) {
    final uint16 = _readUint16(bytes, offset);
    // Convert unsigned to signed
    if (uint16 > 32767) {
      return uint16 - 65536;
    }
    return uint16;
  }

  /// Dump audio session state (iOS only, safe to call on other platforms)
  /// Note: AudioSessionDebug was removed - this is a placeholder for future implementation
  static Future<void> _dumpAudioSession(String tag) async {
    try {
      if (Platform.isIOS) {
        debugPrint('[SyncDiag] Audio session dump requested for tag: $tag (not implemented)');
        // TODO: Re-implement iOS audio session debugging if needed
      }
    } catch (e) {
      debugPrint('[SyncDiag] Error dumping audio session: $e');
    }
  }
}

class _WavInfo {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataSize;

  _WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataSize,
  });
}
