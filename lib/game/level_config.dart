import 'dart:math';

/// Size settings for one level.
///
/// Colors: 3 at the start, +1 every 5 levels, max 6.
/// Tube size: 4 for levels 1-9, 5 for 10-19, 6 from 20.
/// Loop capacity: tube size minus 1.
/// Every level has 2 extra empty tubes. Belt-full mode has 1 and the loop
/// starts full (with none, almost no board is solvable).
///
/// Special blocks (see Board): hidden from level 12, locked from level 22,
/// a rainbow on half the levels from level 32.
class LevelConfig {
  const LevelConfig({
    required this.level,
    required this.colorCount,
    required this.tubeSize,
    required this.loopCapacity,
    required this.emptyTubes,
    this.beltFull = false,
  });

  factory LevelConfig.forLevel(int level, {bool beltFull = false}) {
    final colorCount = (3 + (level - 1) ~/ 5).clamp(3, 6);
    final tubeSize = level < 10 ? 4 : (level < 20 ? 5 : 6);
    return LevelConfig(
      level: level,
      colorCount: colorCount,
      tubeSize: tubeSize,
      loopCapacity: tubeSize - 1,
      emptyTubes: beltFull ? 1 : 2,
      beltFull: beltFull,
    );
  }

  /// Rush mode: 3 colors, a 4th after 10 clears and a 5th after 25.
  /// Tube size 4, loop capacity 6, 2 more tubes than colors.
  factory LevelConfig.rush(int clears) => LevelConfig(
    level: 1,
    colorCount: clears >= 25 ? 5 : (clears >= 10 ? 4 : 3),
    tubeSize: 4,
    loopCapacity: 6,
    emptyTubes: 2,
  );

  final int level;
  final int colorCount;
  final int tubeSize;
  final int loopCapacity;
  final int emptyTubes;

  /// The level starts with the loop full of blocks.
  final bool beltFull;

  /// Blocks of each color: one full tube.
  int get blockCount => colorCount * tubeSize;

  int get tubeCount => colorCount + emptyTubes;

  /// Hidden blocks: 2 at level 12, +1 every 5 levels, max 6.
  int get hiddenCount => level < 12 ? 0 : min(6, 2 + (level - 12) ~/ 5);

  /// Locked blocks: 1 at level 22, +1 every 10 levels, max 3.
  int get lockedCount => level < 22 ? 0 : min(3, 1 + (level - 22) ~/ 10);

  /// From level 32 the generator adds one rainbow block on half the levels.
  bool get mayHaveRainbow => level >= 32;

  /// Loop speed in px/s: 260, +3% per level, at most +60% (level 21+).
  double get loopSpeed => 260 * (1 + min(0.6, 0.03 * (level - 1)));
}
