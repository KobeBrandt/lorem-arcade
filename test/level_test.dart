import 'dart:math';

import 'package:color_flow/game/board.dart';
import 'package:color_flow/game/game_mode.dart';
import 'package:color_flow/game/level_config.dart';
import 'package:color_flow/game/level_generator.dart';
import 'package:color_flow/progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('LevelConfig', () {
    test('follows the size curve', () {
      final l1 = LevelConfig.forLevel(1);
      expect([l1.colorCount, l1.tubeSize, l1.loopCapacity], [3, 4, 3]);
      final l10 = LevelConfig.forLevel(10);
      expect([l10.colorCount, l10.tubeSize, l10.loopCapacity], [4, 5, 4]);
      expect(LevelConfig.forLevel(1, beltFull: true).emptyTubes, 1);
      final l30 = LevelConfig.forLevel(30);
      expect([l30.colorCount, l30.tubeSize, l30.loopCapacity], [6, 6, 5]);
      expect(LevelConfig.forLevel(99).colorCount, 6);
    });

    test('special block counts', () {
      int hidden(int level) => LevelConfig.forLevel(level).hiddenCount;
      int locked(int level) => LevelConfig.forLevel(level).lockedCount;
      expect([11, 12, 16, 17, 22, 27, 32, 99].map(hidden), [
        0,
        2,
        2,
        3,
        4,
        5,
        6,
        6,
      ]);
      expect([21, 22, 31, 32, 42, 99].map(locked), [0, 1, 1, 2, 3, 3]);
      expect(LevelConfig.forLevel(31).mayHaveRainbow, isFalse);
      expect(LevelConfig.forLevel(32).mayHaveRainbow, isTrue);
    });

    test('loop speed grows 3% per level up to +60%', () {
      double speed(int level) => LevelConfig.forLevel(level).loopSpeed;
      expect(speed(1), 260);
      expect(speed(2), closeTo(267.8, 1e-9));
      expect(speed(11), closeTo(338, 1e-9));
      expect(speed(21), closeTo(416, 1e-9));
      expect(speed(60), closeTo(416, 1e-9));
    });
  });

  group('Board', () {
    test('pass order goes left, wraps, and checks the source last', () {
      final board = Board(tubes: List.generate(5, (_) => <int>[]), tubeSize: 4);
      expect(board.passOrder(2), [1, 0, 4, 3, 2]);
    });

    test('empty tube accepts any color, full tube accepts none', () {
      final board = Board(
        tubes: [
          <int>[],
          [0, 0, 0, 0],
          [1],
        ],
        tubeSize: 4,
      );
      final r = TubeReservations(3);
      expect(r.accepts(board, 0, 5), isTrue);
      expect(r.accepts(board, 1, 0), isFalse);
      expect(r.accepts(board, 2, 1), isTrue);
      expect(r.accepts(board, 2, 0), isFalse);
    });

    test('run of same color leaves together', () {
      final board = Board(
        tubes: [
          [1, 0, 0],
          <int>[],
        ],
        tubeSize: 4,
      );
      final next = applyCleanMove(board, 0, 3)!;
      expect(next.tubes, [
        [1],
        [0, 0],
      ]);
    });

    test('routing prefers a matching tube over an empty one passed first', () {
      final board = Board(
        tubes: [
          [1, 0],
          <int>[],
          [2, 0],
        ],
        tubeSize: 4,
      );
      // The empty tube is first in the pass order; the score must still
      // pick the matching tube.
      final r = TubeReservations(3);
      expect(r.chooseTube(board, [1, 2, 0], 0), 2);
    });

    test('routing prefers the longer same-color run', () {
      final board = Board(
        tubes: [
          [1, 0],
          [0, 0],
          [2, 0],
        ],
        tubeSize: 4,
      );
      final r = TubeReservations(3);
      expect(r.chooseTube(board, [2, 1, 0], 0), 1);
    });

    test('routing ties go to the first tube passed', () {
      final board = Board(
        tubes: [
          <int>[],
          <int>[],
          [2, 0],
        ],
        tubeSize: 4,
      );
      final r = TubeReservations(3);
      expect(r.chooseTube(board, [1, 0], 0), 1);
      expect(r.chooseTube(board, [1, 0], 3), 1);
    });

    test('routing counts blocks still falling into a tube', () {
      final board = Board(
        tubes: [
          [0],
          <int>[],
        ],
        tubeSize: 4,
      );
      final r = TubeReservations(2)
        ..reserve(1, 0)
        ..reserve(1, 0);
      // Tube 1 will hold two 0s (score 12) vs tube 0 with one (score 11).
      expect(r.chooseTube(board, [0, 1], 0), 1);
    });

    test('run longer than loop capacity is not allowed', () {
      final board = Board(
        tubes: [
          [1, 0, 0, 0],
          <int>[],
        ],
        tubeSize: 4,
      );
      expect(applyCleanMove(board, 0, 2), isNull);
    });
  });

  group('Hidden blocks', () {
    test('are revealed for good once they are on top', () {
      final board = Board(
        tubes: [
          [0, 1, 2],
          <int>[],
          <int>[],
        ],
        tubeSize: 4,
        hidden: [
          {0, 1},
          <int>{},
          <int>{},
        ],
      );
      expect(board.isHidden(0, 1), isTrue);
      final next = applyCleanMove(board, 0, 3)!;
      expect(next.tubes[0], [0, 1]);
      expect(next.isHidden(0, 1), isFalse);
      expect(next.isHidden(0, 0), isTrue);
      // A block landing on it does not hide it again.
      next.tubes[0].add(2);
      expect(next.isHidden(0, 1), isFalse);
      // Rules use the true color, and hidden blocks are not in the key.
      expect(board.topRunLength(0), 1);
      expect(board.key(), Board(tubes: board.tubes, tubeSize: 4).key());
    });
  });

  group('Locked blocks', () {
    test('a run stops at a locked block', () {
      final board = Board(
        tubes: [
          [1, 0, 0],
          <int>[],
        ],
        tubeSize: 4,
        locked: [
          {1},
          <int>{},
        ],
      );
      expect(board.topRunLength(0), 1);
      expect(applyCleanMove(board, 0, 3)!.tubes, [
        [1, 0],
        [0],
      ]);
    });

    test('a locked top cannot be tapped and takes no blocks', () {
      final board = Board(
        tubes: [
          [1, 0],
          [0],
          <int>[],
        ],
        tubeSize: 4,
        locked: [
          {1},
          <int>{},
          <int>{},
        ],
      );
      expect(board.topRunLength(0), 0);
      expect(applyCleanMove(board, 0, 3), isNull);
      final r = TubeReservations(3);
      expect(r.accepts(board, 0, 0), isFalse);
      // The 0 skips the locked tube even though its top matches.
      expect(applyCleanMove(board, 1, 3)!.tubes[2], [0]);
    });

    test('a tube with a locked block is never complete', () {
      final board = Board(
        tubes: [
          [0, 0, 0, 0],
        ],
        tubeSize: 4,
        locked: [
          {0},
        ],
      );
      expect(board.isComplete(0), isFalse);
      expect(board.isWon, isFalse);
    });

    test('each completion opens one block: leftmost tube, topmost', () {
      final board = Board(
        tubes: [
          [0, 0, 0],
          <int>[],
          [1, 1, 0],
          [2, 1],
        ],
        tubeSize: 4,
        locked: [
          <int>{},
          <int>{},
          {0, 1},
          {0},
        ],
      );
      final next = applyCleanMove(board, 2, 3)!;
      expect(next.isComplete(0), isTrue);
      expect(next.locked, [
        <int>{},
        <int>{},
        {0},
        {0},
      ]);
    });

    test('an opened block can complete its tube and open the next', () {
      final board = Board(
        tubes: [
          [0, 0, 0],
          [1, 1, 1, 1],
          [2, 0],
        ],
        tubeSize: 4,
        locked: [
          <int>{},
          {3},
          {0},
        ],
      );
      final next = applyCleanMove(board, 2, 3)!;
      // Tube 0 completes and opens tube 1, which completes and opens tube 2.
      expect(next.isComplete(0), isTrue);
      expect(next.isComplete(1), isTrue);
      expect(next.lockedCount, 0);
    });
  });

  group('Rainbow block', () {
    const r = Board.rainbow;

    test('on top it always leaves alone; runs stop at it', () {
      final board = Board(
        tubes: [
          [1, 0, 0, r],
          [r],
          [2, r],
          <int>[],
          <int>[],
        ],
        tubeSize: 4,
        locked: [
          <int>{},
          <int>{},
          {0},
          <int>{},
          <int>{},
        ],
      );
      expect(board.topRunLength(0), 1);
      expect(board.topRunLength(1), 1);
      expect(board.topRunLength(2), 1);
      expect(board.copy().takeRun(0), [r]);
      final below = Board(
        tubes: [
          [0, r, 0, 0],
        ],
        tubeSize: 4,
      );
      expect(below.topRunLength(0), 2);
    });

    test('a rainbow in a complete tube can still be moved out', () {
      // Level 43 dead end: the rainbow sorted the pink tube, but one more
      // pink is elsewhere and the blues are one short.
      final board = Board(
        tubes: [
          [1, 1, 1],
          [0, 0, 0, r],
          [0],
          <int>[],
        ],
        tubeSize: 4,
      );
      expect(board.isComplete(1), isTrue);
      expect(board.canTapComplete(1), isTrue);
      final next = applyCleanMove(board, 1, 3)!;
      // The rainbow leaves alone and lands on the 1s (13 beats 11 for [0]).
      expect(next.tubes[0], [1, 1, 1, r]);
      expect(next.tubes[1], [0, 0, 0]);
      final done = applyCleanMove(next, 2, 3)!;
      expect(done.isWon, isTrue);
      expect(Solver(3, 60000).canSolve(board), isTrue);
    });

    test('any color lands on a rainbow top, scored as a match', () {
      final board = Board(
        tubes: [
          [0, r],
          [1],
          <int>[],
        ],
        tubeSize: 4,
      );
      final res = TubeReservations(3);
      expect(res.accepts(board, 0, 1), isTrue);
      expect(res.score(board, 0, 1), 11);
      expect(res.score(board, 0, 0), 12);
      // 1 on [0, R] (11) ties with [1] (11): the first passed wins.
      expect(res.chooseTube(board, [1, 0, 2], 1), 1);
      expect(res.chooseTube(board, [0, 1, 2], 1), 0);
    });

    test('a rainbow on the loop lands on the best tube top', () {
      final board = Board(
        tubes: [
          [1],
          [0, 0],
          <int>[],
          [2, 2, 2, 2],
        ],
        tubeSize: 4,
      );
      final res = TubeReservations(4);
      expect(res.chooseTube(board, [2, 0, 1, 3], r), 1);
      expect(res.score(board, 2, r), 1);
      expect(res.score(board, 3, r), isNull);
    });

    test('a full tube is complete when the other blocks share a color', () {
      final board = Board(
        tubes: [
          [0, r, 0, 0],
          [1, r, 0, 0],
          [0, 0, r],
        ],
        tubeSize: 4,
      );
      expect(board.isComplete(0), isTrue);
      expect(board.isComplete(1), isFalse);
      expect(board.isComplete(2), isFalse);
    });

    test('a rainbow completes a tube in a move', () {
      final board = Board(
        tubes: [
          [0, 0, 0],
          [1, 1, 1, r],
          [1],
          <int>[],
        ],
        tubeSize: 4,
      );
      // [1, 1, 1, R] is complete, but its rainbow can still be tapped out.
      final next = applyCleanMove(board, 1, 1)!;
      // The rainbow lands on the 0s (13 beats 11 for the single 1).
      expect(next.tubes[0], [0, 0, 0, r]);
      final done = applyCleanMove(next, 2, 1)!;
      expect(done.tubes[1], [1, 1, 1, 1]);
      expect(done.isWon, isTrue);
    });
  });

  group('LevelGenerator', () {
    test('creates solvable levels for each size step', () {
      final generator = LevelGenerator(random: Random(1));
      for (final level in [1, 6, 10, 16, 20, 30]) {
        final config = LevelConfig.forLevel(level);
        final puzzle = generator.generate(config);
        expect(puzzle.board.tubeCount, config.tubeCount);
        expect(puzzle.loop, isEmpty);
        final path = Solver(config.loopCapacity, 60000).solve(puzzle.board);
        expect(path, isNotNull, reason: 'level $level');
        expect(puzzle.solutionLength, path!.length);
      }
    });

    test('belt-full levels start with a full loop and are solvable', () {
      final generator = LevelGenerator(random: Random(2));
      for (final level in [1, 10, 20, 30]) {
        final config = LevelConfig.forLevel(level, beltFull: true);
        final puzzle = generator.generate(config);
        expect(puzzle.loop.length, config.loopCapacity);
        expect(puzzle.board.tubeCount, config.colorCount + 1);
        final blocks = puzzle.board.tubes.fold<int>(0, (n, t) => n + t.length);
        expect(blocks + puzzle.loop.length, config.blockCount);
        expect(
          LoopSolver(
            config.loopCapacity,
            60000,
          ).solve(puzzle.board, puzzle.loop),
          isNotNull,
          reason: 'level $level',
        );
      }
    });

    test('levels with special blocks are solvable', () {
      var rainbows = 0;
      for (final level in [12, 22, 32, 42]) {
        final config = LevelConfig.forLevel(level);
        for (var seed = 1; seed <= 4; seed++) {
          final puzzle = LevelGenerator(random: Random(seed)).generate(config);
          final board = puzzle.board;
          final reason = 'level $level seed $seed';
          int count(List<Set<int>> sets) =>
              sets.fold(0, (n, s) => n + s.length);
          expect(count(board.hidden), config.hiddenCount, reason: reason);
          expect(count(board.locked), config.lockedCount, reason: reason);
          for (var t = 0; t < board.tubeCount; t++) {
            final top = board.tubes[t].length - 1;
            expect(board.isHidden(t, top), isFalse, reason: reason);
            expect(board.isLocked(t, top), isFalse, reason: reason);
          }
          final hasRainbow = board.tubes.any((t) => t.contains(Board.rainbow));
          if (hasRainbow) rainbows++;
          if (level < 32) expect(hasRainbow, isFalse, reason: reason);
          final path = Solver(config.loopCapacity, 60000).solve(board);
          expect(path, isNotNull, reason: reason);
          expect(puzzle.solutionLength, path!.length, reason: reason);
        }
      }
      expect(rainbows, greaterThan(0));
    });

    test('belt-full levels with special blocks are solvable', () {
      for (final level in [12, 22, 32]) {
        final config = LevelConfig.forLevel(level, beltFull: true);
        final puzzle = LevelGenerator(random: Random(level)).generate(config);
        expect(
          LoopSolver(
            config.loopCapacity,
            60000,
          ).solve(puzzle.board, puzzle.loop),
          isNotNull,
          reason: 'level $level',
        );
      }
    });

    test('same seed gives the same daily puzzle', () {
      final config = LevelConfig.forLevel(
        dailyLevelFor(DateTime(2026, 11, 16)),
      );
      final a = LevelGenerator(random: Random(20261116)).generate(config);
      final b = LevelGenerator(random: Random(20261116)).generate(config);
      expect(a.board.key(), b.board.key());
    });
  });

  group('settleLoop', () {
    test('lands blocks that fit and keeps the rest', () {
      final board = Board(
        tubes: [
          [1, 0],
          [1, 1, 1, 1],
        ],
        tubeSize: 4,
      );
      final (next, left) = settleLoop(board, [0, 1, 0], [0, 1]);
      expect(next.tubes[0], [1, 0, 0, 0]);
      expect(left, [1]);
    });
  });

  group('GameMode', () {
    test('limits and daily sizes', () {
      expect(moveLimitFor(7), 11);
      expect(secondsFor(LevelConfig.forLevel(1)), 72);
      expect(dailyLevelFor(DateTime(2026, 11, 16)), 1); // a Monday
      expect(dailyLevelFor(DateTime(2026, 11, 22)), 30); // a Sunday
      expect(dayKey(DateTime(2026, 1, 5)), 20260105);
    });
  });

  group('Progress', () {
    test('daily streak counts days in a row and resets after a gap', () async {
      SharedPreferences.setMockInitialValues({});
      final progress = Progress(await SharedPreferences.getInstance());
      final mon = DateTime(2026, 11, 16);
      expect(await progress.markDailySolved(mon), 1);
      expect(progress.dailySolved(mon), isTrue);
      expect(await progress.markDailySolved(mon), 1); // counted once
      expect(await progress.markDailySolved(DateTime(2026, 11, 17)), 2);
      expect(progress.dailyStreak(DateTime(2026, 11, 19)), 0);
      expect(await progress.markDailySolved(DateTime(2026, 11, 19)), 1);
    });

    test('levels are saved per mode', () async {
      SharedPreferences.setMockInitialValues({'level': 7});
      final progress = Progress(await SharedPreferences.getInstance());
      expect(progress.level(GameMode.levels), 7);
      expect(progress.level(GameMode.timed), 1);
      await progress.setLevel(GameMode.timed, 3);
      expect(progress.level(GameMode.timed), 3);
      expect(progress.level(GameMode.levels), 7);
    });
  });
}
