enum PitchHighwayDifficulty { easy, medium, hard }

String pitchHighwayDifficultyLabel(PitchHighwayDifficulty difficulty) {
  return switch (difficulty) {
    PitchHighwayDifficulty.easy => 'Level 1',
    PitchHighwayDifficulty.medium => 'Level 2',
    PitchHighwayDifficulty.hard => 'Level 3',
  };
}

String pitchHighwayDifficultySpeedLabel(PitchHighwayDifficulty difficulty) {
  return switch (difficulty) {
    PitchHighwayDifficulty.easy => 'Slow',
    PitchHighwayDifficulty.medium => 'Medium',
    PitchHighwayDifficulty.hard => 'Fast',
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

int pitchHighwayDifficultyLevel(PitchHighwayDifficulty difficulty) {
  return switch (difficulty) {
    PitchHighwayDifficulty.easy => 1,
    PitchHighwayDifficulty.medium => 2,
    PitchHighwayDifficulty.hard => 3,
  };
}

PitchHighwayDifficulty pitchHighwayDifficultyFromLevel(int level) {
  return switch (level) {
    1 => PitchHighwayDifficulty.easy,
    2 => PitchHighwayDifficulty.medium,
    _ => PitchHighwayDifficulty.hard,
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
