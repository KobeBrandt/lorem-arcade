/// What a Kings cell holds. A tap cycles empty, cross, king, empty.
enum KingsMark { empty, cross, king }

/// One Kings puzzle: a [size] x [size] grid split into [size] regions.
class KingsPuzzle {
  const KingsPuzzle({
    required this.size,
    required this.regions,
    required this.solution,
  });

  final int size;

  /// Region id (0 to size - 1) per cell, row by row.
  final List<int> regions;

  /// Column of the king in each row of the one solution.
  final List<int> solution;

  int regionAt(int row, int col) => regions[row * size + col];
}

/// What a tap on a cell did.
enum KingsTapOutcome {
  /// The cell got a cross.
  crossed,

  /// A king was placed and breaks no rule.
  king,

  /// A king was placed and clashes with another king: a mistake.
  clash,

  /// A king was taken off the cell.
  cleared,

  /// Nothing happened (the puzzle is solved or the cell is outside).
  ignored,
}

/// True when the kings on cells [a] and [b] (row-major indexes) break a
/// rule: same row, same column, same region, or touching, also
/// diagonally.
bool kingsClash(KingsPuzzle puzzle, int a, int b) {
  if (a == b) return false;
  final n = puzzle.size;
  final ar = a ~/ n, ac = a % n;
  final br = b ~/ n, bc = b % n;
  if (ar == br || ac == bc) return true;
  if (puzzle.regions[a] == puzzle.regions[b]) return true;
  return (ar - br).abs() <= 1 && (ac - bc).abs() <= 1;
}

/// Stars for a solved puzzle: 3 without mistakes, 2 for one or two, 1
/// for more.
int kingsStars(int mistakes) {
  if (mistakes <= 0) return 3;
  if (mistakes <= 2) return 2;
  return 1;
}

/// The player's marks on a [KingsPuzzle] and the rule checks. Free of
/// Flame so it can be tested on its own.
class KingsBoard {
  KingsBoard(this.puzzle)
    : marks = List.filled(puzzle.size * puzzle.size, KingsMark.empty);

  final KingsPuzzle puzzle;

  /// Mark per cell, row by row.
  final List<KingsMark> marks;

  /// King placements that created a clash. Crosses never count.
  int mistakes = 0;

  int get size => puzzle.size;

  KingsMark markAt(int row, int col) => marks[row * size + col];

  int get kingCount => marks.where((m) => m == KingsMark.king).length;

  /// Cell indexes of all kings.
  Iterable<int> get kings sync* {
    for (var i = 0; i < marks.length; i++) {
      if (marks[i] == KingsMark.king) yield i;
    }
  }

  /// Cell indexes of the kings that clash with at least one other king.
  Set<int> get clashingKings {
    final all = kings.toList();
    final clashing = <int>{};
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        if (kingsClash(puzzle, all[i], all[j])) {
          clashing
            ..add(all[i])
            ..add(all[j]);
        }
      }
    }
    return clashing;
  }

  /// True when [size] kings stand and no two of them clash.
  bool get solved => kingCount == size && clashingKings.isEmpty;

  /// Cycles the mark on a cell. A king that clashes with another king
  /// stays, and counts as one mistake.
  KingsTapOutcome tap(int row, int col) {
    if (solved) return KingsTapOutcome.ignored;
    if (row < 0 || col < 0 || row >= size || col >= size) {
      return KingsTapOutcome.ignored;
    }
    final index = row * size + col;
    switch (marks[index]) {
      case KingsMark.empty:
        marks[index] = KingsMark.cross;
        return KingsTapOutcome.crossed;
      case KingsMark.cross:
        final clash = kings.any((k) => kingsClash(puzzle, index, k));
        marks[index] = KingsMark.king;
        if (!clash) return KingsTapOutcome.king;
        mistakes++;
        return KingsTapOutcome.clash;
      case KingsMark.king:
        marks[index] = KingsMark.empty;
        return KingsTapOutcome.cleared;
    }
  }
}
