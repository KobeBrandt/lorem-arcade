import 'dart:math';

import 'kings_board.dart';

/// Largest Kings grid.
const int kingsMaxSize = 9;

/// Grid size for [level] (1-based): 5x5 on levels 1-3, 6x6 on 4-8, 7x7
/// on 9-15, 8x8 on 16-24 and 9x9 from level 25 on.
int kingsSizeForLevel(int level) {
  if (level <= 3) return 5;
  if (level <= 8) return 6;
  if (level <= 15) return 7;
  if (level <= 24) return 8;
  return kingsMaxSize;
}

/// Builds the puzzle of [level]. The level number seeds the random
/// numbers, so the same level always gives the same puzzle, and the
/// puzzle has exactly one solution.
///
/// It places the kings first, grows one region around each king, then
/// moves single cells between regions until no other solution is left.
KingsPuzzle generateKingsPuzzle(int level) {
  final n = kingsSizeForLevel(level);
  final random = Random(max(1, level) * 7919 + 101);
  while (true) {
    final solution = _randomKings(n, random);
    final regions = _growRegions(n, solution, random);
    if (_makeUnique(n, regions, solution, random)) {
      return KingsPuzzle(
        size: n,
        regions: List.unmodifiable(regions),
        solution: List.unmodifiable(solution),
      );
    }
  }
}

/// Finds up to [limit] solutions of the grid: the column of the king in
/// each row. Two are enough to tell that a puzzle is not unique.
List<List<int>> solveKings(int size, List<int> regions, {int limit = 2}) {
  final found = <List<int>>[];
  final cols = List<int>.filled(size, -1);
  // Regions that have no cell in row r or below: they must have a king
  // before row r is reached.
  final above = List<int>.filled(size + 1, 0);
  final lastRow = List<int>.filled(size, -1);
  for (var i = 0; i < regions.length; i++) {
    lastRow[regions[i]] = max(lastRow[regions[i]], i ~/ size);
  }
  for (var r = 0; r <= size; r++) {
    for (var region = 0; region < size; region++) {
      if (lastRow[region] < r) above[r] |= 1 << region;
    }
  }

  void place(int row, int usedCols, int usedRegions) {
    if (above[row] & ~usedRegions != 0) return;
    if (row == size) {
      found.add(List.of(cols));
      return;
    }
    for (var c = 0; c < size && found.length < limit; c++) {
      if (usedCols & (1 << c) != 0) continue;
      if (row > 0 && (cols[row - 1] - c).abs() <= 1) continue;
      final region = regions[row * size + c];
      if (usedRegions & (1 << region) != 0) continue;
      cols[row] = c;
      place(row + 1, usedCols | (1 << c), usedRegions | (1 << region));
    }
  }

  place(0, 0, 0);
  return found;
}

/// True when the cells of [region] form one piece (orthogonal steps).
/// [skip] is a cell index to leave out, or -1.
bool isRegionContiguous(
  int size,
  List<int> regions,
  int region, {
  int skip = -1,
}) {
  var start = -1;
  var count = 0;
  for (var i = 0; i < regions.length; i++) {
    if (i == skip || regions[i] != region) continue;
    count++;
    if (start < 0) start = i;
  }
  if (count == 0) return false;
  final seen = <int>{start};
  final queue = [start];
  while (queue.isNotEmpty) {
    final cell = queue.removeLast();
    for (final next in _neighbors(size, cell)) {
      if (next == skip || regions[next] != region) continue;
      if (seen.add(next)) queue.add(next);
    }
  }
  return seen.length == count;
}

Iterable<int> _neighbors(int size, int cell) sync* {
  final row = cell ~/ size, col = cell % size;
  if (row > 0) yield cell - size;
  if (row < size - 1) yield cell + size;
  if (col > 0) yield cell - 1;
  if (col < size - 1) yield cell + 1;
}

/// One king per row and column, none touching another.
List<int> _randomKings(int n, Random random) {
  final cols = List<int>.filled(n, -1);
  bool place(int row, int used) {
    if (row == n) return true;
    final order = List.generate(n, (i) => i)..shuffle(random);
    for (final c in order) {
      if (used & (1 << c) != 0) continue;
      if (row > 0 && (cols[row - 1] - c).abs() <= 1) continue;
      cols[row] = c;
      if (place(row + 1, used | (1 << c))) return true;
    }
    return false;
  }

  place(0, 0);
  return cols;
}

/// Grows region i from the king in row i, one random cell at a time.
List<int> _growRegions(int n, List<int> kings, Random random) {
  final regions = List<int>.filled(n * n, -1);
  for (var row = 0; row < n; row++) {
    regions[row * n + kings[row]] = row;
  }
  var left = n * n - n;
  while (left > 0) {
    final region = random.nextInt(n);
    final frontier = <int>[];
    for (var i = 0; i < regions.length; i++) {
      if (regions[i] != region) continue;
      for (final next in _neighbors(n, i)) {
        if (regions[next] < 0) frontier.add(next);
      }
    }
    if (frontier.isEmpty) continue;
    regions[frontier[random.nextInt(frontier.length)]] = region;
    left--;
  }
  return regions;
}

/// Moves cells between regions until [solution] is the only solution.
/// Each move takes a cell where another solution has a king and gives it
/// to a neighboring region, which then holds two of that solution's
/// kings. Returns false when it gets stuck, so the caller starts over.
bool _makeUnique(int n, List<int> regions, List<int> solution, Random random) {
  for (var step = 0; step < 120; step++) {
    final found = solveKings(n, regions);
    final others = found.where((s) => !_same(s, solution)).toList();
    if (others.isEmpty) return true;
    final other = others.first;
    final moves = <(int, int)>[];
    for (var row = 0; row < n; row++) {
      if (other[row] == solution[row]) continue;
      final cell = row * n + other[row];
      final from = regions[cell];
      if (!isRegionContiguous(n, regions, from, skip: cell)) continue;
      for (final next in _neighbors(n, cell)) {
        final to = regions[next];
        if (to != from && !moves.contains((cell, to))) moves.add((cell, to));
      }
    }
    if (moves.isEmpty) return false;
    final (cell, to) = moves[random.nextInt(moves.length)];
    regions[cell] = to;
  }
  return false;
}

bool _same(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
