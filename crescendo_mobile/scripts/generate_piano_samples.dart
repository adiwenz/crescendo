import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:wav/wav.dart';

void main() async {
  final outputDir = Directory('assets/audio/piano');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
    print('Created directory: ${outputDir.path}');
  }

  print('Generating distinct chromatic piano samples in ${outputDir.path}...');

  // Generate MIDI 21 (A0) to 108 (C8)
  for (int midi = 21; midi <= 108; midi++) {
    // A4 = 440Hz is MIDI 69
    final freq = 440.0 * pow(2.0, (midi - 69) / 12.0);
    final fileName = '$midi.wav';
    
    // Generate a 3.0 second tone for fuller sustain
    final wav = generatePianoTone(freq, 3.0);
    
    final file = File('${outputDir.path}/$fileName');
    await wav.writeFile(file.path);
    
    print('Generated $fileName ($freq Hz)');
  }
  
  print('Done! Run "flutter pub get" and restart the app.');
}

/// Generates a synthetic piano-like tone
/// - Fundamental frequency + harmonics
/// - Exponential decay envelope
/// - Stereo (identical channels for mono-compat)
Wav generatePianoTone(double freq, double durationSec) {
  const sampleRate = 44100;
  final numSamples = (durationSec * sampleRate).toInt();
  final channels = [Float64List(numSamples), Float64List(numSamples)];

  for (int i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    
    // Amplitude Envelope (ADSR-ish)
    // Fast attack (0.01s), exponential decay
    double envelope = 0.0;
    if (t < 0.01) {
      envelope = t / 0.01;
    } else {
      envelope = exp(-(t - 0.01) * 3.0); // Decay factor
    }

    // Waveform synthesis
    // Piano has strong fundamental, some 2nd harmonic, weak higher harmonics
    // Adding a bit of "inharmonicity" or detuning makes it sound less like a beep?
    // Let's keep it simple: Standard harmonics.
    
    double sample = 0.0;
    
    // Fundamental
    sample += 1.0 * sin(2 * pi * freq * t);
    
    // 2nd Harmonic (Octave) - usually prominent in piano
    sample += 0.5 * sin(2 * pi * (freq * 2.0) * t);
    
    // 3rd Harmonic (Fifth)
    sample += 0.25 * sin(2 * pi * (freq * 3.0) * t);
    
    // 4th Harmonic
    sample += 0.125 * sin(2 * pi * (freq * 4.0) * t);

    // Apply envelope and master volume
    sample *= envelope * 0.5; // 0.5 master gain to avoid clipping

    // Write to both channels
    channels[0][i] = sample;
    channels[1][i] = sample;
  }

  // Create Wav object
  return Wav(
    channels,
    sampleRate,
    WavFormat.pcm16bit,
  );
}
