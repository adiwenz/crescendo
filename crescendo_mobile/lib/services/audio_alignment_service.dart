import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../models/audio_sync_info.dart';
import 'chirp_marker.dart';

class AudioAlignmentService {
  static const int _sampleRate = 48000;
  static const int _numChannels = 1;

  static Future<String> mixAlignedWavs({
    required String refPath,
    required String recPath,
    required AudioSyncInfo syncInfo,
    double refGain = 1.0,
    double recGain = 1.0,
  }) async {
    final fRef = File(refPath);
    final fRec = File(recPath);
    
    final bytesRef = await fRef.readAsBytes();
    final bytesRec = await fRec.readAsBytes();
    
    // Skip 44 byte headers
    final offRef = bytesRef.length >= 44 ? 44 : 0;
    final offRec = bytesRec.length >= 44 ? 44 : 0;
    
    final bdRef = ByteData.sublistView(bytesRef);
    final bdRec = ByteData.sublistView(bytesRec);
    
    final lenRef = (bytesRef.length - offRef) ~/ 2;
    final lenRec = (bytesRec.length - offRec) ~/ 2;
    
    final offset = syncInfo.sampleOffset;
    final offsetMs = (offset / syncInfo.sampleRate) * 1000;
    
    // Output length
    final recEnd = offset + lenRec;
    final maxLen = max(lenRef, recEnd);
    final outLen = max(0, maxLen);
    
    print('[MIX] lenRef=$lenRef lenRec=$lenRec');
    print('[MIX] offsetSamples=$offset offsetMs=${offsetMs.toStringAsFixed(1)}');
    print('[MIX] recEnd=$recEnd outLen=$outLen');
    
    final outBytesCount = outLen * 2;
    final outData = Uint8List(outBytesCount);
    final bdOut = ByteData.sublistView(outData);
    
    int? firstRefNonZero;
    int? firstRecNonZero;
    
    for (int i = 0; i < outLen; i++) {
        int sRef = 0;
        int sRec = 0;
        
        // Ref sample at i
        if (i < lenRef) {
          sRef = bdRef.getInt16(offRef + i*2, Endian.little);
          if (sRef != 0 && firstRefNonZero == null) firstRefNonZero = i;
        }
        
        // Rec sample at i corresponds to Rec index `i - offset`
        final recIdx = i - offset;
        if (recIdx >= 0 && recIdx < lenRec) {
           sRec = bdRec.getInt16(offRec + recIdx*2, Endian.little);
           if (sRec != 0 && firstRecNonZero == null) firstRecNonZero = i;
        }
        
        double mixed = (sRef * refGain) + (sRec * recGain);
        
        if (mixed > 32767) mixed = 32767;
        if (mixed < -32768) mixed = -32768;
        
        bdOut.setInt16(i*2, mixed.round(), Endian.little);
    }
    
    print('[MIX] firstRefNonZero=$firstRefNonZero');
    print('[MIX] firstRecNonZero=$firstRecNonZero (index in mix)');
    
    final header = _buildWavHeader(outBytesCount, syncInfo.sampleRate, _numChannels);
    
    print('[MIX_OUT] outSampleRate=${syncInfo.sampleRate}');
    print('[MIX_OUT] outChannels=$_numChannels');
    print('[MIX_OUT] outDataBytes=$outBytesCount');
    print('[MIX_OUT] outDurationMs=${(outLen / syncInfo.sampleRate * 1000).toStringAsFixed(1)}');
    
    if (syncInfo.sampleRate != _sampleRate) print('[MIX] WARNING: Rate mismatch!');
    final bb = BytesBuilder();
    bb.add(header);
    bb.add(outData);
    
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/sync_mixed_${DateTime.now().millisecondsSinceEpoch}.wav';
    await File(outPath).writeAsBytes(bb.toBytes());
    
    return outPath;
  }

  static Uint8List _buildWavHeader(int dataSize, int sampleRate, int channels) {
    final fileSize = dataSize + 36;
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;

    final header = BytesBuilder();
    // RIFF
    header.add('RIFF'.codeUnits);
    header.add(_int32(fileSize));
    header.add('WAVE'.codeUnits);
    // fmt
    header.add('fmt '.codeUnits);
    header.add(_int32(16)); // Subchunk1Size
    header.add(_int16(1));  // AudioFormat (PCM)
    header.add(_int16(channels));
    header.add(_int32(sampleRate));
    header.add(_int32(byteRate));
    header.add(_int16(blockAlign));
    header.add(_int16(16)); // BitsPerSample
    // data
    header.add('data'.codeUnits);
    header.add(_int32(dataSize));

    return header.toBytes();
  }

  static Uint8List _int32(int val) {
    final b = Uint8List(4);
    ByteData.view(b.buffer).setInt32(0, val, Endian.little);
    return b;
  }

  static Uint8List _int16(int val) {
    final b = Uint8List(2);
    ByteData.view(b.buffer).setInt16(0, val, Endian.little);
    return b;
  }
  /// Aligns the recorded WAV based on the computed sync info by trimming or padding.
  /// Returns the path to the new aligned WAV file.
  static Future<String> alignAndSave({
    required File recWav,
    required AudioSyncInfo sync,
  }) async {
    final offsetSamples = sync.sampleOffset; // recorded - ref
    final sampleRate = sync.sampleRate;
    
    print('[ALIGN] offsetSamples=$offsetSamples (${(offsetSamples/sampleRate*1000).toStringAsFixed(1)}ms)');

    final dir = await getTemporaryDirectory();
    final alignedPath = '${dir.path}/aligned_${DateTime.now().millisecondsSinceEpoch}.wav';

    // Positive offset => Recorder is LATE (recording starts AFTER ref).
    // We must TRIM the start of the recording so that t=0 aligns with ref t=0.
    if (offsetSamples > 0) {
      print('[ALIGN] Trimming $offsetSamples samples from start...');
      await _trimStartOfWavSamples(
        inputPath: recWav.path, 
        outputPath: alignedPath, 
        trimSamples: offsetSamples,
        sampleRate: sampleRate,
      );
    } 
    // Negative offset => Recorder is EARLY (recording starts BEFORE ref).
    // We must PAD the start of the recording with silence.
    // NOTE: This usually implies the user didn't record the first few ms?
    // Or we just started recording exceptionally early.
    else if (offsetSamples < 0) {
      final padSamples = -offsetSamples; // remove sign
      print('[ALIGN] Padding start with $padSamples silence samples...');
      await _prependSilenceToWavSamples(
         inputPath: recWav.path,
         outputPath: alignedPath,
         silenceSamples: padSamples,
         sampleRate: sampleRate,
      );
    } 
    // Zero offset
    else {
      print('[ALIGN] Perfect sync! Copying file...');
      await recWav.copy(alignedPath);
    }
    
    return alignedPath;
  }

  static Future<void> _trimStartOfWavSamples({
    required String inputPath, 
    required String outputPath, 
    required int trimSamples,
    required int sampleRate,
  }) async {
     final inputFile = File(inputPath);
     final bytes = await inputFile.readAsBytes();
     if (bytes.length < 44) return;
     
     final blockAlign = _numChannels * 2;
     final trimBytes = trimSamples * blockAlign; // sample * channels * 2
     
     // Skip original header
     if (44 + trimBytes >= bytes.length) {
       final header = _buildWavHeader(0, sampleRate, _numChannels);
       await File(outputPath).writeAsBytes(header);
       return;
     }

     final newLength = (bytes.length - 44) - trimBytes;
     
     final header = _buildWavHeader(newLength, sampleRate, _numChannels);
     
     final outBytes = BytesBuilder();
     outBytes.add(header);
     outBytes.add(bytes.sublist(44 + trimBytes));
     
     await File(outputPath).writeAsBytes(outBytes.toBytes());
  }

  static Future<void> _prependSilenceToWavSamples({
    required String inputPath, 
    required String outputPath, 
    required int silenceSamples,
    required int sampleRate,
  }) async {
    final inFile = File(inputPath);
    final bytes = await inFile.readAsBytes();
    
    final blockAlign = _numChannels * 2;
    final silenceBytesCount = silenceSamples * blockAlign;
    
    final currentDataLen = (bytes.length >= 44) ? bytes.length - 44 : 0;
    final newDataLen = currentDataLen + silenceBytesCount;
    
    final header = _buildWavHeader(newDataLen, sampleRate, _numChannels);
    final silence = Uint8List(silenceBytesCount); 
    
    final bb = BytesBuilder();
    bb.add(header);
    bb.add(silence);
    if (bytes.length > 44) {
      bb.add(bytes.sublist(44));
    }
    
    await File(outputPath).writeAsBytes(bb.toBytes());
  }

  static const int _searchRecSec = 3; // Search first 3s of rec (generous)

  /// Analyzes reference and recording to find the sync offset.
  /// Returns [AudioSyncInfo] if successful, or null if detection fails.
  static Future<AudioSyncInfo?> computeSync({
    required Uint8List refBytes,
    required Uint8List recBytes,
    int sampleRate = _sampleRate,
  }) async {
    // Generate needle
    final needle = ChirpMarker.generateChirpWaveform(sampleRate: sampleRate);

    // Ref: search start
    final resRef = _detectMarker(
      wavBytes: refBytes,
      marker: needle,
      searchStartSamples: 0,
      searchLenSamples: (0.5 * sampleRate).round(), // Search first 0.5s of ref
    );

    // Rec: search start
    final resRec = _detectMarker(
      wavBytes: recBytes,
      marker: needle,
      searchStartSamples: 0,
      searchLenSamples: (2.5 * sampleRate).round(), // Search first 2.5s of rec
    );

    if (resRef.bestLag != -1 && 
        resRec.bestLag != -1 && 
        resRec.confidence >= 6.0) { // Min confidence threshold
      
      final offset = resRec.bestLag - resRef.bestLag;
      final offsetMs = (offset / sampleRate) * 1000;
      
      print('[SYNC] sr=$sampleRate');
      print('[SYNC] refSyncSample=${resRef.bestLag}');
      print('[SYNC] recordedSyncSample=${resRec.bestLag}');
      print('[SYNC] sampleOffset=$offset');
      print('[SYNC] timeOffsetMs=${offsetMs.toStringAsFixed(2)}');
      print('[SYNC] confidence=${resRec.confidence.toStringAsFixed(1)}');
      
      if (resRef.bestLag.abs() >= 0.1 * sampleRate) {
         print('[SYNC] WARNING: Ref marker far from start! (${resRef.bestLag})');
      }
      
      return AudioSyncInfo(
        sampleRate: sampleRate,
        refSyncSample: resRef.bestLag,
        recordedSyncSample: resRec.bestLag,
      );
    }
    
    return null;
  }

  // Scans using cross-correlation (matched filter)
  static _CorrelationResult _detectMarker({
    required Uint8List wavBytes,
    required Float32List marker,
    required int searchStartSamples,
    required int searchLenSamples,
  }) {
    // Skip 44 byte header (WAV)
    const pcmOffset = 44;
    if (wavBytes.length < pcmOffset) return const _CorrelationResult(-1, 0.0);
    
    final numTotalSamples = (wavBytes.length - pcmOffset) ~/ 2;
    if (numTotalSamples <= 0) return const _CorrelationResult(-1, 0.0);

    // Bounds
    int start = searchStartSamples;
    if (start >= numTotalSamples) start = numTotalSamples - 1;
    
    int end = start + searchLenSamples;
    if (end > numTotalSamples) end = numTotalSamples;
    
    final markerLen = marker.length;
    final scanLimit = end - markerLen;
    
    if (scanLimit <= start) return const _CorrelationResult(-1, 0.0);
    
    final bd = ByteData.sublistView(wavBytes);
    
    double bestCorr = -1.0;
    int bestLag = -1;
    double sumAbsCorr = 0.0;
    int count = 0;
    
    // Optimization: Decode search region to float array once
    final regionLen = end - start;
    final signalRegion = Float32List(regionLen);
    
    for (int i=0; i<regionLen; i++) {
       final sampIndex = start + i;
       if (pcmOffset + sampIndex*2 + 2 <= wavBytes.length) {
         final s16 = bd.getInt16(pcmOffset + sampIndex*2, Endian.little);
         signalRegion[i] = s16 / 32768.0; 
       } else {
         signalRegion[i] = 0.0;
       }
    }
    
    // Scan
    final loopLimit = regionLen - markerLen;
    
    for (int lag=0; lag < loopLimit; lag++) {
       double dot = 0.0;
       for (int m=0; m < markerLen; m++) {
          dot += signalRegion[lag+m] * marker[m];
       }
       
       if (dot > bestCorr) {
          bestCorr = dot;
          bestLag = start + lag;
       }
       
       sumAbsCorr += dot.abs();
       count++;
    }
    
    double confidence = 0.0;
    if (count > 0) {
       final mean = sumAbsCorr / count;
       confidence = bestCorr / (mean + 1e-9);
    }
    
    return _CorrelationResult(bestLag, confidence);
  }
}

class _CorrelationResult {
  final int bestLag;
  final double confidence;
  const _CorrelationResult(this.bestLag, this.confidence);
}
