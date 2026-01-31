import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class WavPcm16 {
  final int channels;
  final int sampleRate;
  final Int16List data;

  WavPcm16(this.channels, this.sampleRate, this.data);
}

class WavUtil {
  static const int _headerSize = 44;

  static Future<WavPcm16> readPcm16Wav(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final buffer = bytes.buffer;
    final view = ByteData.view(buffer);

    // 1. RIFF Check
    if (view.getUint32(0, Endian.big) != 0x52494646) { // RIFF
       throw Exception("Invalid WAV: No RIFF header");
    }
    if (view.getUint32(8, Endian.big) != 0x57415645) { // WAVE
       throw Exception("Invalid WAV: No WAVE header");
    }

    // 2. Scan Chunks
    int pos = 12;
    int channels = 1;
    int sampleRate = 48000;
    Int16List? pcmData;

    while (pos < view.lengthInBytes - 8) {
      final chunkId = view.getUint32(pos, Endian.big);
      final chunkSize = view.getUint32(pos + 4, Endian.little);
      final chunkEnd = pos + 8 + chunkSize;
      
      if (chunkId == 0x666d7420) { // fmt 
        // Parse Format
        int audioFormat = view.getUint16(pos + 8, Endian.little);
        channels = view.getUint16(pos + 10, Endian.little);
        sampleRate = view.getUint32(pos + 12, Endian.little);
        int bitsPerSample = view.getUint16(pos + 22, Endian.little);
        
        if (audioFormat != 1) throw Exception("Only PCM (format 1) supported");
        if (bitsPerSample != 16) throw Exception("Only 16-bit supported");

      } else if (chunkId == 0x64617461) { // data
        // Found Data
        final dataBytes = bytes.sublist(pos + 8, chunkEnd);
        pcmData = dataBytes.buffer.asInt16List();
      }

      pos = chunkEnd;
      // Pad to word boundary
      if (chunkSize % 2 != 0) pos++; 
    }

    if (pcmData == null) throw Exception("No data chunk found");

    return WavPcm16(channels, sampleRate, pcmData);
  }

  static Future<String> writePcm16MonoWav(String path, Int16List pcmData, int sampleRate) async {
    final file = File(path);
    final int channels = 1;
    final int byteRate = sampleRate * channels * 2;
    final int dataSize = pcmData.length * 2;
    final int totalSize = 36 + dataSize;
    
    final header = BytesBuilder();
    header.add([0x52, 0x49, 0x46, 0x46]); // RIFF 
    _addInt32(header, totalSize);
    header.add([0x57, 0x41, 0x56, 0x45]); // WAVE
    header.add([0x66, 0x6d, 0x74, 0x20]); // fmt 
    _addInt32(header, 16); 
    _addInt16(header, 1); // PCM
    _addInt16(header, channels); 
    _addInt32(header, sampleRate);
    _addInt32(header, byteRate);
    _addInt16(header, channels * 2); 
    _addInt16(header, 16); 
    header.add([0x64, 0x61, 0x74, 0x61]); // data
    _addInt32(header, dataSize);
    
    final allBytes = BytesBuilder();
    allBytes.add(header.toBytes());
    allBytes.add(pcmData.buffer.asUint8List());
    
    await file.writeAsBytes(allBytes.toBytes());
    return path;
  }
  
  static void _addInt32(BytesBuilder b, int v) {
    final d = ByteData(4); d.setInt32(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }
  static void _addInt16(BytesBuilder b, int v) {
    final d = ByteData(2); d.setInt16(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  static Future<String> mixMonoWithOffsetToWav({
    required String referencePath, 
    required String vocalPath, 
    required int offsetFrames, 
    required String outputPath
  }) async {
    
    final ref = await readPcm16Wav(referencePath);
    final voc = await readPcm16Wav(vocalPath);
    
    // Validate / Resample (Assume 48k for now as established)
    if (ref.sampleRate != 48000 || voc.sampleRate != 48000) {
      debugPrint("WARNING: Sample rate mismatch or not 48k! Mix may drift.");
    }
    
    // Calculate Output Length (Max extent)
    // ref: 0 to ref.length (frames)
    // voc: offsetFrames to offsetFrames + voc.length
    int refFrames = ref.data.length ~/ ref.channels;
    int vocFrames = voc.data.length ~/ voc.channels;
    int maxEnd = refFrames;
    if (offsetFrames + vocFrames > maxEnd) maxEnd = offsetFrames + vocFrames;
    
    // Clamp min start to 0 if offset is negative? 
    // We will assume output starts at t=0
    int totalFrames = maxEnd;
    final outBuffer = Int32List(totalFrames); // Mono accumulation
    
    // Mix Reference (Headroom 0.5)
    for (int i = 0; i < refFrames; i++) {
        // Downmix if stereo
        int val = 0;
        for (int c = 0; c < ref.channels; c++) {
           val += ref.data[i * ref.channels + c];
        }
        val ~/= ref.channels; // Average
        
        outBuffer[i] += (val * 0.5).round();
    }
    
    // Mix Vocal (Headroom 0.5)
    for (int i = 0; i < vocFrames; i++) {
        int pos = offsetFrames + i;
        if (pos >= 0 && pos < totalFrames) {
             // Downmix
            int val = 0;
            for (int c = 0; c < voc.channels; c++) {
               val += voc.data[i * voc.channels + c];
            }
            val ~/= voc.channels;
            
            outBuffer[pos] += (val * 0.5).round();
        }
    }
    
    // Convert to Int16
    final outPcm = Int16List(totalFrames);
    for (int i = 0; i < totalFrames; i++) {
        int s = outBuffer[i];
        if (s > 32767) s = 32767;
        if (s < -32768) s = -32768;
        outPcm[i] = s;
    }
    
    return writePcm16MonoWav(outputPath, outPcm, 48000);
  }

  static Future<void> debugPrintWav(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint("WAV DEBUG ($path): File not found");
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 44) {
         debugPrint("WAV DEBUG ($path): Too short (${bytes.length})");
         return;
      }
      final view = ByteData.view(bytes.buffer);
      
      int riff = view.getUint32(0, Endian.big);
      int wave = view.getUint32(8, Endian.big);
      bool valid = (riff == 0x52494646 && wave == 0x57415645);
      
      // We can reuse readPcm16Wav logic but lazy for print
      // Just print standard header fields
      int sr = view.getUint32(24, Endian.little);
      int ch = view.getUint16(22, Endian.little);
      int bps = view.getUint16(34, Endian.little);
      
      debugPrint("WAV DEBUG ($path): Valid=$valid SR=$sr Ch=$ch Bits=$bps Len=${bytes.length}");
      
      // Dump first 8 samples
      int offset = 44; // Assuming standard, readPcm does it better but this is quick check
      if (valid && bytes.length > 44 + 16) {
         final pcm = bytes.buffer.asInt16List(44, 8);
         debugPrint("   Samples: $pcm");
      }
      
    } catch (e) {
      debugPrint("WAV DEBUG ($path): Error $e");
    }
  }
}
