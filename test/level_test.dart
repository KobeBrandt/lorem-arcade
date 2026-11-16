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
