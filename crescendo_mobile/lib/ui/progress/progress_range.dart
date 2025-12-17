enum ProgressRange {
  days7,
  days14,
  days30,
  all,
}

extension ProgressRangeX on ProgressRange {
  String get label => switch (this) {
        ProgressRange.days7 => '7d',
        ProgressRange.days14 => '14d',
        ProgressRange.days30 => '30d',
        ProgressRange.all => 'All',
      };

  Duration? get window => switch (this) {
        ProgressRange.days7 => const Duration(days: 7),
        ProgressRange.days14 => const Duration(days: 14),
        ProgressRange.days30 => const Duration(days: 30),
        ProgressRange.all => null,
      };
}
