import 'dart:math';

import 'shikaku_board.dart';
import 'shikaku_solver.dart';

/// Grid side for [level] (1-based): 5 at levels 1 to 4, then one more
/// every 4 levels, up to 10 from level 21 on.
int shikakuSize(int level) => min(10, 5 + (max(1, level) - 1) ~/ 4);

/// Largest rectangle area the generator cuts on a grid of side [size].
int shikakuMaxArea(int size) => min(12, size + 2);

/// Builds the puzzle of [level] (1-based). The level number is the seed,
/// so the same level always gives the same puzzle, and the solver checks
/// that it has exactly one solution.
///
/// It cuts the grid into random rectangles, puts each number in a random
/// cell of its rectangle, and asks the solver for a second solution. When
/// there is one, it moves a number to a cell that the other solution does
/// not share, and asks again. After a few tries it cuts a new grid.
ShikakuPuzzle buildShikakuPuzzle(int level) {
  final n = max(1, level);
  final size = shikakuSize(n);
  final random = Random(n * 7919 + 13);
  while (true) {
    final puzzle = _attempt(random, size, size, shikakuMaxArea(size));
    if (puzzle != null) return puzzle;
  }
}

ShikakuPuzzle? _attempt(Random random, int cols, int rows, int maxArea) {
  final solution = _cut(random, cols, rows, maxArea);
  final clueCell = [for (final rect in solution) _randomCell(random, rect)];
  for (var repair = 0; repair < 24; repair++) {
    final clues = List.filled(cols * rows, 0);
    for (var i = 0; i < solution.length; i++) {
      final (col, row) = clueCell[i];
      clues[row * cols + col] = solution[i].area;
    }
    final solver = ShikakuSolver(cols: cols, rows: rows, clues: clues);
    final found = solver.solve(limit: 2, maxNodes: 20000);
    if (solver.aborted) return null;
    if (found.length == 1) {
      return ShikakuPuzzle(
        cols: cols,
        rows: rows,
        clues: clues,
        solution: solution,
      );
    }
    // Two solutions: move one number out of a rectangle the other
    // solution uses differently.
    final other = found.firstWhere(
      (s) => !_sameSplit(s, solution),
      orElse: () => found.last,
    );
    final otherSet = other.toSet();
    final differing = [
      for (var i = 0; i < solution.length; i++)
        if (!otherSet.contains(solution[i])) i,
    ];
    if (differing.isEmpty) return null;
    final i = differing[random.nextInt(differing.length)];
    final (col, row) = clueCell[i];
    final rival = other.firstWhere((r) => r.contains(col, row));
    final free = [
      for (var y = solution[i].top; y < solution[i].bottom; y++)
        for (var x = solution[i].left; x < solution[i].right; x++)
          if (!rival.contains(x, y)) (x, y),
    ];
    clueCell[i] = free.isEmpty
        ? _randomCell(random, solution[i])
        : free[random.nextInt(free.length)];
  }
  return null;
}

bool _sameSplit(List<ShikakuRect> a, List<ShikakuRect> b) =>
    a.length == b.length && a.toSet().containsAll(b);

(int, int) _randomCell(Random random, ShikakuRect rect) => (
  rect.left + random.nextInt(rect.width),
  rect.top + random.nextInt(rect.height),
);

/// Cuts the grid into rectangles. The first free cell in reading order is
/// always the top left corner of the next rectangle, so the free cells to
/// its right and below decide which sizes fit.
List<ShikakuRect> _cut(Random random, int cols, int rows, int maxArea) {
  final used = List.filled(cols * rows, false);
  final rects = <ShikakuRect>[];
  for (var start = 0; start < used.length; start++) {
    if (used[start]) continue;
    final col = start % cols;
    final row = start ~/ cols;
    var run = 0;
    while (col + run < cols && !used[row * cols + col + run]) {
      run++;
    }
    final options = <ShikakuRect>[];
    for (var w = 1; w <= run; w++) {
      for (var h = 1; row + h <= rows && w * h <= maxArea; h++) {
        if (!_free(used, cols, col, row + h - 1, w)) break;
        if (w * h >= 2) options.add(ShikakuRect(col, row, w, h));
      }
    }
    final rect = options.isEmpty
        ? ShikakuRect(col, row, 1, 1)
        : options[random.nextInt(options.length)];
    for (var y = rect.top; y < rect.bottom; y++) {
      for (var x = rect.left; x < rect.right; x++) {
        used[y * cols + x] = true;
      }
    }
    rects.add(rect);
  }
  return rects;
}

bool _free(List<bool> used, int cols, int col, int row, int width) {
  for (var x = col; x < col + width; x++) {
    if (used[row * cols + x]) return false;
  }
  return true;
}
