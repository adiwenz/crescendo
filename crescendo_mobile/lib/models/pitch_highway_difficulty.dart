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

int pitchHighwayDifficultyIndex(PitchHighwayDifficulty difficulty) {
  return switch (difficulty) {
    PitchHighwayDifficulty.easy => 0,
    PitchHighwayDifficulty.medium => 1,
    PitchHighwayDifficulty.hard => 2,
  };
}

PitchHighwayDifficulty pitchHighwayDifficultyFromIndex(int index) {
  return switch (index) {
    0 => PitchHighwayDifficulty.easy,
    1 => PitchHighwayDifficulty.medium,
    _ => PitchHighwayDifficulty.hard,
  };
}
