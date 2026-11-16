import 'dart:math';

import 'board.dart';
import 'level_config.dart';

/// A generated level: the tubes, the blocks already on the loop at the
/// start (belt-full mode only), and how many taps the solver needed.
class Puzzle {
  const Puzzle({
    required this.board,
    this.loop = const [],
    required this.solutionLength,
  });

  final Board board;

  /// Colors of the blocks on the loop at the start, in loop order.
  final List<int> loop;

  final int solutionLength;
}

/// Builds random levels and keeps only those the solver can finish.
class LevelGenerator {
  LevelGenerator({Random? random}) : _random = random ?? Random();

  final Random _random;

  static const int _maxAttempts = 200;
  static const int _maxSolverNodes = 60000;

  Puzzle generate(LevelConfig config) =>
      config.beltFull ? _generateBelt(config) : _generateNormal(config);

  Puzzle _generateNormal(LevelConfig config) {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final board = _shuffled(config);
      if (_hasCompleteTube(board)) continue;
      final path = Solver(config.loopCapacity, _maxSolverNodes).solve(board);
      if (path != null) {
        return Puzzle(board: board, solutionLength: path.length);
      }
    }
    throw StateError('No solvable level found for level ${config.level}');
  }

  /// Belt-full: one empty tube, and the loop starts full. Loop blocks land
  /// as soon as a tube fits them, so the first taps free up loop space.
  Puzzle _generateBelt(LevelConfig config) {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final blocks = _shuffledBlocks(config);
      final loop = blocks.sublist(0, config.loopCapacity);
      final rest = blocks.sublist(config.loopCapacity);

      // Every tube starts full, then one slot is freed per loop block.
      final lengths = List.filled(config.colorCount, config.tubeSize);
      for (var i = 0; i < loop.length; i++) {
        final candidates = [
          for (var t = 0; t < lengths.length; t++)
            if (lengths[t] > 1) t,
        ];
        lengths[candidates[_random.nextInt(candidates.length)]]--;
      }
      var at = 0;
      final tubes = <List<int>>[
        for (final n in lengths) rest.sublist(at, at += n),
        for (var t = 0; t < config.emptyTubes; t++) <int>[],
      ];
      final board = Board(tubes: tubes, tubeSize: config.tubeSize);

      if (_hasCompleteTube(board)) continue;

      final path = LoopSolver(
        config.loopCapacity,
        _maxSolverNodes,
      ).solve(board, loop);
      if (path != null) {
        return Puzzle(board: board, loop: loop, solutionLength: path.length);
      }
    }
    throw StateError('No solvable belt level found for level ${config.level}');
  }

  List<int> _shuffledBlocks(LevelConfig config) => <int>[
    for (var c = 0; c < config.colorCount; c++)
      for (var i = 0; i < config.tubeSize; i++) c,
  ]..shuffle(_random);

  Board _shuffled(LevelConfig config) {
    final blocks = _shuffledBlocks(config);
    final tubes = <List<int>>[
      for (var t = 0; t < config.colorCount; t++)
        blocks.sublist(t * config.tubeSize, (t + 1) * config.tubeSize),
      for (var t = 0; t < config.emptyTubes; t++) <int>[],
    ];
    return Board(tubes: tubes, tubeSize: config.tubeSize);
  }

  bool _hasCompleteTube(Board board) {
    for (var i = 0; i < board.tubeCount; i++) {
      if (board.isComplete(i)) return true;
    }
    return false;
  }
}

List<int> _allTubes(Board board) => [
  for (var i = 0; i < board.tubeCount; i++) i,
];

/// Depth-first search over "clean" moves: a tap whose blocks all find a
/// tube within their first lap, so the loop is empty again before the
/// next tap. If a level is solvable this way, the player can always win
/// by waiting for each tap to settle.
class Solver {
  Solver(this.loopCapacity, this.maxNodes);

  final int loopCapacity;
  final int maxNodes;
  int _nodes = 0;
  final Set<String> _seen = {};

  bool canSolve(Board board) => solve(board) != null;

  /// Returns the tubes to tap, in order, or null when no solution was found
  /// within [maxNodes] steps.
  List<int>? solve(Board board) {
    _nodes = 0;
    _seen.clear();
    final path = <int>[];
    return _search(board, path) ? path : null;
  }

  bool _search(Board board, List<int> path) {
    if (board.isWon) return true;
    if (++_nodes > maxNodes) return false;
    if (!_seen.add(board.key())) return false;

    for (var source = 0; source < board.tubeCount; source++) {
      final next = applyCleanMove(board, source, loopCapacity);
      if (next == null) continue;
      path.add(source);
      if (_search(next, path)) return true;
      path.removeLast();
    }
    return false;
  }
}

/// Simulates one tap on [source] where every block lands in its first lap.
/// Returns null when the tap is not allowed or not clean.
Board? applyCleanMove(Board board, int source, int loopCapacity) {
  if (board.isComplete(source)) return null;
  final run = board.topRunLength(source);
  if (run == 0 || run > loopCapacity) return null;

  final next = board.copy();
  final color = next.tubes[source].last;
  next.tubes[source].removeRange(
    next.tubes[source].length - run,
    next.tubes[source].length,
  );

  final reservations = TubeReservations(next.tubeCount);
  final order = next.passOrder(source);
  for (var b = 0; b < run; b++) {
    final target = reservations.chooseTube(next, order, color);
    if (target == null) return null;
    reservations.reserve(target, color);
  }
  for (var t = 0; t < next.tubeCount; t++) {
    while (reservations.isBusy(t)) {
      reservations.land(next, t);
    }
  }
  // A move that changes nothing is useless for the search.
  if (next.key() == board.key()) return null;
  return next;
}

/// Lands loop blocks wherever they fit (best-tube score), again and again,
/// until no block can land. Blocks that never fit stay on the loop.
/// Returns the new board and the blocks left on the loop.
(Board, List<int>) settleLoop(Board board, List<int> loop, List<int> order) {
  final next = board.copy();
  final left = List<int>.of(loop);
  final reservations = TubeReservations(next.tubeCount);
  var changed = true;
  while (changed) {
    changed = false;
    for (var i = 0; i < left.length; i++) {
      final target = reservations.chooseTube(next, order, left[i]);
      if (target == null) continue;
      next.tubes[target].add(left.removeAt(i));
      changed = true;
      break;
    }
  }
  return (next, left);
}

/// Search for levels where blocks may stay on the loop between taps
/// (belt-full mode). After each tap the player waits until every block
/// that can land has landed.
class LoopSolver {
  LoopSolver(this.loopCapacity, this.maxNodes);

  final int loopCapacity;
  final int maxNodes;
  int _nodes = 0;
  final Set<String> _seen = {};

  List<int>? solve(Board board, List<int> loop) {
    _nodes = 0;
    _seen.clear();
    final (start, left) = settleLoop(board, loop, _allTubes(board));
    final path = <int>[];
    return _search(start, left, path) ? path : null;
  }

  bool _search(Board board, List<int> loop, List<int> path) {
    if (loop.isEmpty && board.isWon) return true;
    if (++_nodes > maxNodes) return false;
    // Loop order matters: settleLoop lands the first block that fits.
    final key = '${board.key()}#${loop.join(',')}';
    if (!_seen.add(key)) return false;

    for (var source = 0; source < board.tubeCount; source++) {
      if (board.isComplete(source)) continue;
      final run = board.topRunLength(source);
      if (run == 0 || loop.length + run > loopCapacity) continue;
      final tapped = board.copy();
      final color = tapped.tubes[source].last;
      tapped.tubes[source].removeRange(
        tapped.tubes[source].length - run,
        tapped.tubes[source].length,
      );
      final (next, left) = settleLoop(tapped, [
        ...List.filled(run, color),
        ...loop,
      ], board.passOrder(source));
      path.add(source);
      if (_search(next, left, path)) return true;
      path.removeLast();
    }
    return false;
  }
}
