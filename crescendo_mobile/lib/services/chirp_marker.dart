import 'dart:math';
import 'dart:typed_data';

class ChirpMarker {
  /// Generates a linear chirp with Hann window, encoded as PCM16 Little Endian.
  /// 
  /// [sampleRate] - default 48000
  /// [startHz] - default 1200
  /// [endHz] - default 8000
  /// [durationMs] - default 80
  /// [amplitude] - default 0.3
  /// [silenceAfterMs] - optional silence padding after the chirp
  static Uint8List buildChirpPcm16({
    int sampleRate = 48000,
    double startHz = 1200,
    double endHz = 8000,
    int durationMs = 80,
    double amplitude = 0.3,
    int silenceAfterMs = 20,
  }) {
    final numSamples = (durationMs * sampleRate) ~/ 1000;
    final silenceSamples = (silenceAfterMs * sampleRate) ~/ 1000;
    
    // Total bytes = (chirp + silence) * 2 bytes/sample
    final totalBytes = (numSamples + silenceSamples) * 2;
    final buffer = ByteData(totalBytes);
    
    final T = numSamples / sampleRate;
    final k = (endHz - startHz) / T;
    
    for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        final phase = 2 * pi * (startHz * t + (k * t * t) / 2);
        final rawSample = sin(phase);
        
        // Hann Window: 0.5 * (1 - cos(2*pi*n/(N-1)))
        final window = 0.5 * (1 - cos(2 * pi * i / (numSamples - 1)));
        
        final val = rawSample * window * amplitude;
        
        // PCM16 conversion
        final int16Val = (val * 32767).clamp(-32768, 32767).round();
        buffer.setInt16(i * 2, int16Val, Endian.little);
    }
    
    // Silence bytes are already 0 initialized by ByteData
    
    return buffer.buffer.asUint8List();
  }
  
  /// Generates the floating point samples of the chirp (normalized -1.0 to 1.0)
  /// Useful for cross-correlation "needle".
  static Float32List generateChirpWaveform({
    int sampleRate = 48000,
    double startHz = 1200,
    double endHz = 8000,
    int durationMs = 80,
  }) {
    final numSamples = (durationMs * sampleRate) ~/ 1000;
    final samples = Float32List(numSamples);
    
    final T = numSamples / sampleRate;
    final k = (endHz - startHz) / T;
    
    for (int i = 0; i < numSamples; i++) {
        final t = i / sampleRate;
        final phase = 2 * pi * (startHz * t + (k * t * t) / 2);
        final rawSample = sin(phase);
        final window = 0.5 * (1 - cos(2 * pi * i / (numSamples - 1)));
        samples[i] = rawSample * window; 
    }
    return samples;
  }
}
