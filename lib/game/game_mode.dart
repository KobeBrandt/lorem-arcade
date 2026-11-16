import 'level_config.dart';

enum GameMode {
  levels('Levels', 'Sort every tube, one level after another.'),
  moves('Move limit', 'Finish each level within a set number of taps.'),
  timed('Timed', 'Beat the clock. Bigger levels give more time.'),
  daily('Daily puzzle', 'One puzzle a day, the same for everyone.'),
  endless('Endless', 'Boards keep coming. Score a point per sorted tube.'),
  beltFull('Belt full', 'The loop starts full. Make room before you can tap.');

  const GameMode(this.title, this.description);

  final String title;
  final String description;

  /// Modes that move through numbered levels and save the level reached.
  bool get hasLevels =>
      this == levels || this == moves || this == timed || this == beltFull;

  LevelConfig configFor(int level) =>
      LevelConfig.forLevel(level, beltFull: this == beltFull);
}

/// Move limit: the solver's tap count plus 50%, rounded up.
int moveLimitFor(int solutionLength) => (solutionLength * 1.5).ceil();

/// Timed: 6 seconds per block on the board.
int secondsFor(LevelConfig config) => config.blockCount * 6;

/// Daily puzzle size by weekday, Monday small to Sunday big.
const List<int> dailyLevels = [1, 6, 10, 16, 20, 25, 30];

int dailyLevelFor(DateTime day) => dailyLevels[day.weekday - 1];

/// Date as yyyymmdd, used as the daily seed and the saved solve date.
int dayKey(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

const List<String> weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
