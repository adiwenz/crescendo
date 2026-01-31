import 'dart:typed_data';

class OneClockCapture {
  final Uint8List pcm16;
  final int numFrames;
  final int sampleRate;
  final int channels;
  final int inputFramePos;
  final int outputFramePos;
  final int timestampNanos;

  OneClockCapture({
    required this.pcm16,
    required this.numFrames,
    required this.sampleRate,
    required this.channels,
    required this.inputFramePos,
    required this.outputFramePos,
    required this.timestampNanos,
  });

  factory OneClockCapture.fromMap(Map<dynamic, dynamic> m) {
    return OneClockCapture(
      pcm16: m['pcm16'] as Uint8List,
      numFrames: m['numFrames'] as int,
      sampleRate: m['sampleRate'] as int,
      channels: m['channels'] as int,
      inputFramePos: (m['inputFramePos'] as int),
      outputFramePos: (m['outputFramePos'] as int),
      timestampNanos: (m['timestampNanos'] as int),
    );
  }
}

class OneClockStartConfig {
  final String? playbackWavAssetOrPath;
  final int sampleRate;
  final int channels;
  final int framesPerCallback;

  const OneClockStartConfig({
    this.playbackWavAssetOrPath,
    this.sampleRate = 48000,
    this.channels = 1,
    this.framesPerCallback = 192,
  });

  Map<String, dynamic> toMap() => {
        'playback': playbackWavAssetOrPath ?? '',
        'sampleRate': sampleRate,
        'channels': channels,
        'framesPerCallback': framesPerCallback,
      };
}
