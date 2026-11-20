import 'dart:math';

import 'moo_munch_board.dart';

/// Field size of every Moo Munch board.
const int mooCols = 13;
const int mooRows = 15;

/// Lives per level. Stars at the win are the lives left.
const int mooLives = 3;

/// One level of Moo Munch.
class MooMunchLevel {
  const MooMunchLevel({
    required this.carrots,
    required this.stepSeconds,
    required this.rocks,
  });

  /// Carrots to eat to win.
  final int carrots;

  /// Seconds per cow step; lower is faster.
  final double stepSeconds;

  final Set<Cell> rocks;
}

/// Builds [level] (1-based): more carrots, a faster cow, and from level
/// 3 on, rocks. The same level always gives the same rocks.
MooMunchLevel buildMooMunchLevel(int level) {
  final n = max(1, level);
  return MooMunchLevel(
    carrots: min(4 + n * 2, 30),
    stepSeconds: max(0.1, 0.24 - (n - 1) * 0.012),
    rocks: _rocks(n),
  );
}

Set<Cell> _rocks(int level) {
  final count = min((level - 2) * 2, 20);
  if (count <= 0) return const {};
  final random = Random(level * 7919);
  const startY = mooRows ~/ 2;
  const startX = mooCols ~/ 2;
  final rocks = <Cell>{};
  while (rocks.length < count) {
    final cell = (x: random.nextInt(mooCols), y: random.nextInt(mooRows));
    // Keep the start row free, and the cells around the cow's start.
    final nearStart =
        (cell.y - startY).abs() <= 1 && (cell.x - startX).abs() <= 3;
    if (cell.y == startY || nearStart) continue;
    rocks.add(cell);
  }
  return rocks;
}

/// Seconds per step in an endless run after [carrots] eaten.
double mooEndlessStep(int carrots) => max(0.08, 0.22 - carrots * 0.004);
