/// Size settings for one level.
///
/// Colors: 3 at the start, +1 every 5 levels, max 6.
/// Tube size: 4 for levels 1-9, 5 for 10-19, 6 from 20.
/// Loop capacity: tube size minus 1.
/// Every level has 2 extra empty tubes. Belt-full mode has 1 and the loop
/// starts full (with none, almost no board is solvable).
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
}
