class DebugFlags {
  /// Enable Pitch Highway V2 (Controller-based flow).
  /// Usage: flutter run --dart-define=PITCH_HIGHWAY_V2=true
  static const bool enablePitchHighwayV2 =
      bool.fromEnvironment('PITCH_HIGHWAY_V2', defaultValue: false);
}
