import 'dart:typed_data';

class OneClockCapture {
  final Uint8List pcm16;
  final int numFrames;
  final int sampleRate;
  final int channels;
  final int inputFramePos;
  final int outputFramePos;
  final int timestampNanos;
  final int outputFramePosRel;
  final int sessionId;

  OneClockCapture({
    required this.pcm16,
    required this.numFrames,
    required this.sampleRate,
    required this.channels,
    required this.inputFramePos,
    required this.outputFramePos,
    required this.timestampNanos,
    required this.outputFramePosRel,
    required this.sessionId,
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
      outputFramePosRel: (m['outputFramePosRel'] as int?) ?? 0,
      sessionId: (m['sessionId'] as int?) ?? 0,
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

class NativeSessionSnapshot {
  final int sessionId;
  final int sessionStartFrame;
  final int firstCaptureOutputFrame;
  final int lastOutputFrame;
  final int computedVocOffsetFrames;
  final bool hasFirstCapture;

  NativeSessionSnapshot({
    required this.sessionId,
    required this.sessionStartFrame,
    required this.firstCaptureOutputFrame,
    required this.lastOutputFrame,
    required this.computedVocOffsetFrames,
    required this.hasFirstCapture,
  });

  factory NativeSessionSnapshot.fromList(List<int> list) {
      if (list.length < 6) return NativeSessionSnapshot(sessionId: -1, sessionStartFrame: 0, firstCaptureOutputFrame: 0, lastOutputFrame: 0, computedVocOffsetFrames: 0, hasFirstCapture: false);
      return NativeSessionSnapshot(
          sessionId: list[0],
          sessionStartFrame: list[1],
          firstCaptureOutputFrame: list[2],
          lastOutputFrame: list[3],
          computedVocOffsetFrames: list[4],
          hasFirstCapture: list[5] == 1,
      );
  }

  @override
  String toString() {
    return 'SID=$sessionId Start=$sessionStartFrame FirstCap=$firstCaptureOutputFrame Offset=$computedVocOffsetFrames HasCap=$hasFirstCapture';
  }
}
