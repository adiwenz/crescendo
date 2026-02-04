import 'dart:math';
import 'dart:typed_data';

class UltrasonicMarker {
  /// Generates a linear chirp with Hann window, encoded as PCM16 Little Endian.
  /// 
  /// [sampleRate] - e.g. 48000
  /// [startHz] - e.g. 19000
  /// [endHz] - e.g. 21000
  /// [durationMs] - e.g. 30
  /// [amplitude] - 0.0 to 1.0 (e.g. 0.15)
  /// [silenceAfterMs] - optional silence padding after the chirp
  static Uint8List buildUltrasonicChirpPcm16({
    required int sampleRate,
    required double startHz,
    required double endHz,
    required int durationMs,
    required double amplitude,
    int silenceAfterMs = 0,
  }) {
    final numSamples = (durationMs * sampleRate) ~/ 1000;
    final silenceSamples = (silenceAfterMs * sampleRate) ~/ 1000;
    
    // Total bytes = (chirp + silence) * 2 bytes/sample
    final totalBytes = (numSamples + silenceSamples) * 2;
    final buffer = ByteData(totalBytes);
    
    // Generate Chirp
    // Linear chirp: f(t) = f0 + (f1-f0) * t / T
    // Phase phi(t) = 2*pi * integral(0 to t) f(u) du
    //              = 2*pi * (f0*t + (f1-f0)/(2T) * t^2)
    
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
        // Clamp just in case
        final int16Val = (val * 32767).clamp(-32768, 32767).round();
        buffer.setInt16(i * 2, int16Val, Endian.little);
    }
    
    // Silence bytes are already 0 initialized by ByteData
    
    return buffer.buffer.asUint8List();
  }
  
  /// Generates the floating point samples of the chirp (normalized -1.0 to 1.0)
  /// Useful for cross-correlation "needle".
  static List<double> generateChirpWaveform({
    required int sampleRate,
    required double startHz,
    required double endHz,
    required int durationMs,
  }) {
    final numSamples = (durationMs * sampleRate) ~/ 1000;
    final samples = List<double>.filled(numSamples, 0.0);
    
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
