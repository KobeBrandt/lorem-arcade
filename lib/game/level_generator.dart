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

/// Rush start: every tube gets [perTube] random blocks of the active
/// colors and the loop is empty. With fewer blocks than the tube size no
/// tube can be complete. No solver: rush is endless survival.
Puzzle rushStart(
  LevelConfig config,
  Random random, {
  int perTube = 2,
}) => Puzzle(
  board: Board(
    tubes: [
      for (var t = 0; t < config.tubeCount; t++)
        [for (var i = 0; i < perTube; i++) random.nextInt(config.colorCount)],
    ],
    tubeSize: config.tubeSize,
  ),
  solutionLength: 0,
);

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
      _addSpecials(board, config);
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
      _addSpecials(board, config);

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

  /// Places the special blocks of [config] on a shuffled board: maybe one
  /// rainbow (replacing a block of a random color), then hidden blocks
  /// and locked blocks, never on top of a tube.
  void _addSpecials(Board board, LevelConfig config) {
    final positions = <(int, int)>[
      for (var t = 0; t < board.tubeCount; t++)
        for (var i = 0; i < board.tubes[t].length; i++) (t, i),
    ]..shuffle(_random);

    if (config.mayHaveRainbow && _random.nextBool()) {
      final color = _random.nextInt(config.colorCount);
      final at = positions.firstWhere((p) => board.tubes[p.$1][p.$2] == color);
      board.tubes[at.$1][at.$2] = Board.rainbow;
      positions.remove(at);
    }

    // A locked top would block its tube from the start: far fewer
    // boards are solvable that way.
    positions.removeWhere((p) => p.$2 == board.tubes[p.$1].length - 1);
    final hidden = positions.take(config.hiddenCount).toList();
    for (final p in hidden) {
      board.hidden[p.$1].add(p.$2);
    }
    for (final p in positions.skip(hidden.length).take(config.lockedCount)) {
      board.locked[p.$1].add(p.$2);
    }
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
  if (board.isComplete(source) && !board.canTapComplete(source)) return null;
  final run = board.topRunLength(source);
  if (run == 0 || run > loopCapacity) return null;

  final before = board.completeFlags();
  final next = board.copy();
  final blocks = next.takeRun(source);

  final reservations = TubeReservations(next.tubeCount);
  final order = next.passOrder(source);
  for (final color in blocks) {
    final target = reservations.chooseTube(next, order, color);
    if (target == null) return null;
    reservations.reserve(target, color);
  }
  reservations.landAll(next);
  next.settleCompletions(before);
  // A move that changes nothing is useless for the search.
  if (next.key() == board.key()) return null;
  return next;
}

/// Gives loop blocks a tube wherever they fit, again and again, until no
/// block fits, then lands them. Each round the block with the best score
/// goes first (ties: the first one on the loop), so a block that continues
/// a run beats one that only fits on a rainbow. Blocks that never fit stay
/// on the loop. Completed tubes then open locked blocks. This is exactly
/// what the game does when it plans targets.
/// Returns the new board and the blocks left on the loop.
(Board, List<int>) settleLoop(Board board, List<int> loop, List<int> order) {
  final before = board.completeFlags();
  final next = board.copy();
  final left = List<int>.of(loop);
  final reservations = TubeReservations(next.tubeCount);
  while (true) {
    int? bestIndex;
    var bestTube = -1;
    var bestScore = 0;
    for (var i = 0; i < left.length; i++) {
      final target = reservations.chooseTube(next, order, left[i]);
      if (target == null) continue;
      final s = reservations.score(next, target, left[i])!;
      if (s > bestScore) {
        bestIndex = i;
        bestTube = target;
        bestScore = s;
      }
    }
    if (bestIndex == null) break;
    reservations.reserve(bestTube, left.removeAt(bestIndex));
  }
  reservations.landAll(next);
  next.settleCompletions(before);
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
      if (board.isComplete(source) && !board.canTapComplete(source)) {
        continue;
      }
      final run = board.topRunLength(source);
      if (run == 0 || loop.length + run > loopCapacity) continue;
      final tapped = board.copy();
      final blocks = tapped.takeRun(source);
      final (next, left) = settleLoop(tapped, [
        ...blocks,
        ...loop,
      ], board.passOrder(source));
      path.add(source);
      if (_search(next, left, path)) return true;
      path.removeLast();
    }
    return false;
  }
}
