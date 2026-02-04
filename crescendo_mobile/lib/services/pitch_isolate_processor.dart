import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';


/// A "mailbox" processor that runs PitchDetector in a separate Isolate.
/// It drops older chunks if the isolate is busy (latest-only processing).
class PitchIsolateProcessor {
  // Config
  final int sampleRate;
  
  // Communication
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  
  // Stream to output results to main thread
  final StreamController<double?> _resultController = StreamController<double?>.broadcast();
  Stream<double?> get resultStream => _resultController.stream;

  // Mailbox state
  bool _isIsolateBusy = false;
  Uint8List? _pendingChunk; // The latest chunk waiting to be sent
  
  // Stats
  int chunksDropped = 0;
  int chunksSent = 0;
  int chunksProcessed = 0;
  double avgComputeMs = 0.0;
  
  PitchIsolateProcessor({this.sampleRate = 48000});

  Future<void> init() async {
    if (_isolate != null) return;

    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      _entryPoint, 
      _InitMessage(_receivePort!.sendPort, sampleRate),
    );

    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _flushPending();
      } else if (message is _ResultMessage) {
        _isIsolateBusy = false;
        chunksProcessed++;
        
        // Update stats
        if (avgComputeMs == 0) {
          avgComputeMs = message.computeMs;
        } else {
          avgComputeMs = (avgComputeMs * 0.9) + (message.computeMs * 0.1);
        }
        
        // Emit result
        _resultController.add(message.pitchHz);

        // If we have a pending chunk that arrived while busy, send it now
        _flushPending();
      }
    });
  }

  /// Non-blocking call to request pitch processing.
  /// If isolate is busy, this chunk replaces any previously pending chunk (overwriting/dropping it).
  void process(Uint8List pcmInt16Bytes) {
    if (_isolate == null || _sendPort == null) return;
    
    if (_isIsolateBusy) {
      // Isolate is busy, store this as the latest pending chunk
      if (_pendingChunk != null) {
        chunksDropped++;
      }
      _pendingChunk = pcmInt16Bytes; 
    } else {
      // Isolate is free, send immediately
      _sendChunk(pcmInt16Bytes);
    }
  }

  void _flushPending() {
    if (_pendingChunk != null) {
      final chunk  = _pendingChunk!;
      _pendingChunk = null;
      _sendChunk(chunk);
    }
  }
  
  void _sendChunk(Uint8List chunk) {
    if (_sendPort == null) return;
    
    _isIsolateBusy = true;
    chunksSent++;
    _sendPort!.send(_ProcessMessage(chunk));
  }

  void dispose() {
    _sendPort?.send(_ShutdownMessage());
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _receivePort?.close();
    _resultController.close();
  }

  // --- Isolate Entry Point ---
  
  static void _entryPoint(_InitMessage initMsg) {
    final mainSendPort = initMsg.sendPort;
    final receivePort = ReceivePort();
    
    // Handshake: send our SendPort back to main
    mainSendPort.send(receivePort.sendPort);
    
    // Pitch detector state
    // We reuse a buffer to avoid allocs if possible, though PitchDetector 
    // implementation might create its own. We'll do our best.
    final detector = PitchDetector(
      audioSampleRate: initMsg.sampleRate.toDouble(),
      bufferSize: 2048, 
    );
    
    // We'll accumulate small chunks until we have enough for the detector?
    // OR we assume the main thread sends us sizeable chunks (e.g. 2048 samples).
    // The user's prompt says "The isolate converts PCM16 -> float... and runs getPitchFromFloatBuffer".
    // It also mentions "Throttle... compute pitch at most every 20-40ms".
    // Since we are "mailbox" driven, the throttling is effectively controlled by 
    // how fast the main thread sends and how fast we return "Done".
    
    // We need a local buffer to hold samples if incoming chunks are small.
    // However, usually recorder streams send ~20-50ms chunks.
    // Let's assume we process what we get if it's large enough, or just process it.
    // PitchDetector needs a specific buffer size? older versions did. 
    // Modern `pitch_detector_dart` usually takes a List<double>.
    
    receivePort.listen((message) async {
      if (message is _ProcessMessage) {
        final start = DateTime.now().microsecondsSinceEpoch;
        
        final bytes = message.pcmData;
        
        // Convert PCM16 -> Float
        // Reuse a static list if acceptable, or just alloc. 
        // In Dart isolates, heap is separate, so alloc is local.
        final bd = ByteData.sublistView(bytes);
        final sampleCount = bytes.length ~/ 2;
        final floatBuffer = List<double>.generate(sampleCount, (i) {
          return bd.getInt16(i * 2, Endian.little) / 32768.0;
        });
        
        double? pitchHz;
        try {
          final result = await detector.getPitchFromFloatBuffer(floatBuffer);
          if (result.pitched) {
            pitchHz = result.pitch;
          }
        } catch (_) {}
        
        final end = DateTime.now().microsecondsSinceEpoch;
        final durationMs = (end - start) / 1000.0;
        
        mainSendPort.send(_ResultMessage(pitchHz, durationMs));
      } else if (message is _ShutdownMessage) {
        receivePort.close();
      }
    });
  }
}

// --- Messages ---

class _InitMessage {
  final SendPort sendPort;
  final int sampleRate;
  _InitMessage(this.sendPort, this.sampleRate);
}

class _ProcessMessage {
  final Uint8List pcmData;
  _ProcessMessage(this.pcmData);
}

class _ResultMessage {
  final double? pitchHz;
  final double computeMs;
  _ResultMessage(this.pitchHz, this.computeMs);
}

class _ShutdownMessage {}
