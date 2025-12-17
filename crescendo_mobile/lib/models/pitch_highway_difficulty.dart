enum PitchHighwayDifficulty { easy, medium, hard }

String pitchHighwayDifficultyLabel(PitchHighwayDifficulty difficulty) {
  return switch (difficulty) {
    PitchHighwayDifficulty.easy => 'Easy',
    PitchHighwayDifficulty.medium => 'Medium',
    PitchHighwayDifficulty.hard => 'Hard',
  };
}

PitchHighwayDifficulty? pitchHighwayDifficultyFromName(String? raw) {
  return switch (raw) {
    'easy' => PitchHighwayDifficulty.easy,
    'medium' => PitchHighwayDifficulty.medium,
    'hard' => PitchHighwayDifficulty.hard,
    _ => null,
  };
}
