class AudioSyncInfo {
  final int sampleRate;
  final int refSyncSample;
  final int recordedSyncSample;

  const AudioSyncInfo({
    required this.sampleRate,
    required this.refSyncSample,
    required this.recordedSyncSample,
  });

  int get sampleOffset => recordedSyncSample - refSyncSample;
  double get timeOffsetSec => sampleOffset / sampleRate;

  Map<String, dynamic> toMap() => {
    'sampleRate': sampleRate,
    'refSyncSample': refSyncSample,
    'recordedSyncSample': recordedSyncSample,
  };

  factory AudioSyncInfo.fromMap(Map<String, dynamic> map) => AudioSyncInfo(
    sampleRate: map['sampleRate'] as int,
    refSyncSample: map['refSyncSample'] as int,
    recordedSyncSample: map['recordedSyncSample'] as int,
  );
}
