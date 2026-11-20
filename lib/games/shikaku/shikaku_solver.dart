import 'shikaku_board.dart';

/// Finds the ways to split a Shikaku grid, as an exact cover of its cells.
///
/// Each number gets a list of candidate rectangles: the right area, inside
/// the grid, over that number and no other. The search then always fills
/// the free cell with the fewest candidates left, so a dead end shows up
/// early. Each candidate holds one number, so covering every cell once
/// also uses every number once.
class ShikakuSolver {
  ShikakuSolver({required this.cols, required this.rows, required this.clues})
    : assert(clues.length == cols * rows) {
    _buildCandidates();
  }

  /// Solver for the numbers of [puzzle] (its solution is not used).
  factory ShikakuSolver.of(ShikakuPuzzle puzzle) =>
      ShikakuSolver(cols: puzzle.cols, rows: puzzle.rows, clues: puzzle.clues);

  final int cols;
  final int rows;

  /// Numbers row by row, 0 for none.
  final List<int> clues;

  final List<ShikakuRect> _rects = [];
  final List<List<int>> _rectCells = [];
  late final List<List<int>> _byCell;
  late final List<bool> _used;
  final List<int> _chosen = [];
  final List<List<ShikakuRect>> _found = [];
  int _limit = 0;
  int _nodes = 0;
  int _maxNodes = 0;
  bool _aborted = false;

  /// Search steps of the last [solve].
  int get nodes => _nodes;

  /// True when the last [solve] hit its step limit before it was done.
  bool get aborted => _aborted;

  void _buildCandidates() {
    final cellCount = cols * rows;
    _byCell = List.generate(cellCount, (_) => <int>[]);
    _used = List.filled(cellCount, false);
    for (var i = 0; i < cellCount; i++) {
      final value = clues[i];
      if (value <= 0) continue;
      final col = i % cols;
      final row = i ~/ cols;
      for (var w = 1; w <= value && w <= cols; w++) {
        if (value % w != 0) continue;
        final h = value ~/ w;
        if (h > rows) continue;
        for (var left = col - w + 1; left <= col; left++) {
          if (left < 0 || left + w > cols) continue;
          for (var top = row - h + 1; top <= row; top++) {
            if (top < 0 || top + h > rows) continue;
            _addCandidate(ShikakuRect(left, top, w, h), i);
          }
        }
      }
    }
  }

  void _addCandidate(ShikakuRect rect, int clueIndex) {
    final cells = <int>[];
    for (var row = rect.top; row < rect.bottom; row++) {
      for (var col = rect.left; col < rect.right; col++) {
        final index = row * cols + col;
        if (index != clueIndex && clues[index] > 0) return;
        cells.add(index);
      }
    }
    final id = _rects.length;
    _rects.add(rect);
    _rectCells.add(cells);
    for (final cell in cells) {
      _byCell[cell].add(id);
    }
  }

  /// Returns up to [limit] solutions. With [maxNodes] above 0 the search
  /// stops after that many steps and sets [aborted].
  List<List<ShikakuRect>> solve({int limit = 2, int maxNodes = 0}) {
    _found.clear();
    _chosen.clear();
    _used.fillRange(0, _used.length, false);
    _limit = limit;
    _nodes = 0;
    _maxNodes = maxNodes;
    _aborted = false;
    var area = 0;
    for (final value in clues) {
      area += value;
    }
    if (area == cols * rows) _search();
    return List.unmodifiable(_found);
  }

  /// 0, 1 or 2 (2 meaning two or more). -1 when [maxNodes] ran out first.
  int countSolutions({int maxNodes = 0}) {
    final count = solve(limit: 2, maxNodes: maxNodes).length;
    if (_aborted && count < 2) return -1;
    return count;
  }

  bool _fits(int id) {
    for (final cell in _rectCells[id]) {
      if (_used[cell]) return false;
    }
    return true;
  }

  void _search() {
    if (_found.length >= _limit || _aborted) return;
    _nodes++;
    if (_maxNodes > 0 && _nodes > _maxNodes) {
      _aborted = true;
      return;
    }
    var best = -1;
    var bestCount = 1 << 30;
    for (var cell = 0; cell < _used.length; cell++) {
      if (_used[cell]) continue;
      var count = 0;
      for (final id in _byCell[cell]) {
        if (_fits(id)) count++;
      }
      if (count < bestCount) {
        best = cell;
        bestCount = count;
        if (count <= 1) break;
      }
    }
    if (best < 0) {
      _found.add([for (final id in _chosen) _rects[id]]);
      return;
    }
    if (bestCount == 0) return;
    for (final id in _byCell[best]) {
      if (!_fits(id)) continue;
      for (final cell in _rectCells[id]) {
        _used[cell] = true;
      }
      _chosen.add(id);
      _search();
      _chosen.removeLast();
      for (final cell in _rectCells[id]) {
        _used[cell] = false;
      }
      if (_found.length >= _limit || _aborted) return;
    }
  }
}
