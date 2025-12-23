/// Mapping of exercise types and UI elements to illustration asset paths
/// Available assets:
/// - abstract_1.png through abstract_9.png
/// - abstract_set2_1.png through abstract_set2_9.png
class IllustrationAssets {
  // Category tiles (use abstract_set2_* for consistent style)
  static const String warmup = 'assets/illustrations/abstract_set2_5.png';
  static const String pitch = 'assets/illustrations/abstract_set2_9.png';
  static const String agility = 'assets/illustrations/abstract_set2_7.png';

  // Continue Training watermarks (use abstract_* for variety)
  static const String warmupWatermark = 'assets/illustrations/abstract_set2_6.png';
  static const String pitchWatermark = 'assets/illustrations/abstract_9.png';
  static const String lipTrillsWatermark = 'assets/illustrations/abstract_set2_5.png';

  // Today's Exercises watermarks
  static const String warmupExercise = 'assets/illustrations/abstract_set2_9.png';
  static const String pitchAccuracy = 'assets/illustrations/abstract_set2_7.png';

  // Quick actions (optional, can use abstract_set2_*)
  static const String recents = 'assets/illustrations/abstract_set2_4.png';
  static const String favorites = 'assets/illustrations/abstract_set2_5.png';

  /// Get watermark asset for a given exercise type
  static String? getWatermarkForType(String type) {
    switch (type.toLowerCase()) {
      case 'warmup':
        return warmupWatermark;
      case 'pitch':
        return pitchWatermark;
      case 'agility':
      case 'lip trills':
        return lipTrillsWatermark;
      default:
        return null;
    }
  }
}
