import 'dart:ui' show Canvas, PictureRecorder;

import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lorem_arcade/arcade/arcade_level_game.dart';
import 'package:lorem_arcade/game/game_feedback.dart';
import 'package:lorem_arcade/games/shikaku/shikaku_board.dart';
import 'package:lorem_arcade/games/shikaku/shikaku_game.dart';
import 'package:lorem_arcade/games/shikaku/shikaku_levels.dart';
import 'package:lorem_arcade/games/shikaku/shikaku_solver.dart';
import 'package:lorem_arcade/ui/app_theme.dart';

/// A 3x2 grid split into a 2x2 (number 4 top left) and a 1x2 (number 2).
ShikakuPuzzle _small() => ShikakuPuzzle(
  cols: 3,
  rows: 2,
  clues: const [4, 0, 2, 0, 0, 0],
  solution: const [ShikakuRect(0, 0, 2, 2), ShikakuRect(2, 0, 1, 2)],
);

/// Records every sound the game asks for.
class _FakeSounds implements GameSounds {
  final List<String> events = [];

  @override
  void tap() => events.add('tap');
  @override
  void whoosh() => events.add('whoosh');
  @override
  void blocked() => events.add('blocked');
  @override
  void complete(int combo) => events.add('complete');
  @override
  void win() => events.add('win');
  @override
  void fail() => events.add('fail');
}

ShikakuGame _game(int level, [GameSounds sounds = const SilentSounds()]) =>
    ShikakuGame(
      ArcadeSetup(
        level: level,
        style: const BlockStyle(palette: AppColors.blocks),
        sounds: sounds,
        haptics: false,
      ),
    );

void main() {
  group('ShikakuRect', () {
    test('spanning works in every drag direction', () {
      expect(ShikakuRect.spanning(3, 4, 1, 2), const ShikakuRect(1, 2, 3, 3));
      expect(ShikakuRect.spanning(1, 2, 3, 4), const ShikakuRect(1, 2, 3, 3));
      expect(ShikakuRect.spanning(2, 2, 2, 2).area, 1);
    });

    test('overlap and contains', () {
      const a = ShikakuRect(0, 0, 2, 2);
      expect(a.overlaps(const ShikakuRect(1, 1, 2, 2)), isTrue);
      expect(a.overlaps(const ShikakuRect(2, 0, 1, 2)), isFalse);
      expect(a.contains(1, 1), isTrue);
      expect(a.contains(2, 1), isFalse);
    });
  });

  group('rules', () {
    test('a valid rectangle holds one number equal to its area', () {
      final puzzle = _small();
      expect(puzzle.isValid(const ShikakuRect(0, 0, 2, 2)), isTrue);
      expect(puzzle.isValid(const ShikakuRect(2, 0, 1, 2)), isTrue);
      // Wrong area.
      expect(puzzle.isValid(const ShikakuRect(0, 0, 1, 2)), isFalse);
      // Two numbers.
      expect(puzzle.isValid(const ShikakuRect(0, 0, 3, 1)), isFalse);
      // No number.
      expect(puzzle.isValid(const ShikakuRect(1, 1, 2, 1)), isFalse);
    });

    test('invalid rectangles stay red and count once each', () {
      final board = ShikakuBoard(_small());
      final first = board.place(const ShikakuRect(0, 0, 1, 2));
      expect(first.placed.valid, isFalse);
      expect(board.placed, hasLength(1));
      expect(board.mistakes, 1);
      expect(board.doneCells, 0);
      board.place(const ShikakuRect(1, 1, 2, 1));
      expect(board.mistakes, 2);
    });

    test('drawing over rectangles replaces them; removing frees cells', () {
      final board = ShikakuBoard(_small());
      board.place(const ShikakuRect(0, 0, 1, 2));
      board.place(const ShikakuRect(2, 0, 1, 2));
      final outcome = board.place(const ShikakuRect(0, 0, 2, 2));
      expect(outcome.replaced.map((p) => p.rect), [
        const ShikakuRect(0, 0, 1, 2),
      ]);
      expect(board.placed, hasLength(2));
      expect(board.doneCells, 6);
      expect(outcome.solved, isTrue);
      expect(board.removeAt(2, 1)?.rect, const ShikakuRect(2, 0, 1, 2));
      expect(board.removeAt(2, 1), isNull);
      expect(board.isSolved, isFalse);
    });

    test('a full cover with a red rectangle is not solved', () {
      final puzzle = ShikakuPuzzle(
        cols: 2,
        rows: 1,
        clues: const [2, 0],
        solution: const [ShikakuRect(0, 0, 2, 1)],
      );
      final board = ShikakuBoard(puzzle);
      board.place(const ShikakuRect(0, 0, 1, 1));
      board.place(const ShikakuRect(1, 0, 1, 1));
      expect(board.isSolved, isFalse);
      expect(board.place(const ShikakuRect(0, 0, 2, 1)).solved, isTrue);
    });
  });

  test('stars: 0 mistakes 3, 1 to 2 mistakes 2, 3 or more 1', () {
    expect(shikakuStars(0), 3);
    expect(shikakuStars(1), 2);
    expect(shikakuStars(2), 2);
    expect(shikakuStars(3), 1);
    expect(shikakuStars(12), 1);
  });

  group('solver', () {
    test('finds the one split of a small grid', () {
      final solutions = ShikakuSolver.of(_small()).solve();
      expect(solutions, hasLength(1));
      expect(solutions.single.toSet(), _small().solution.toSet());
    });

    test('sees a second split', () {
      // Two 2s in a 2x2 grid: two rows or two columns.
      final solver = ShikakuSolver(cols: 2, rows: 2, clues: const [2, 0, 0, 2]);
      expect(solver.countSolutions(), 2);
    });

    test('finds no split when the areas do not add up', () {
      final solver = ShikakuSolver(cols: 2, rows: 2, clues: const [2, 0, 0, 0]);
      expect(solver.countSolutions(), 0);
    });
  });

  group('levels', () {
    test('the grid grows from 5x5 to 10x10', () {
      expect(shikakuSize(1), 5);
      expect(shikakuSize(4), 5);
      expect(shikakuSize(5), 6);
      expect(shikakuSize(21), 10);
      expect(shikakuSize(500), 10);
    });

    test('the same level always gives the same puzzle', () {
      for (final level in [1, 7, 23]) {
        final a = buildShikakuPuzzle(level);
        final b = buildShikakuPuzzle(level);
        expect(a.clues, b.clues);
        expect(a.solution, b.solution);
      }
      expect(buildShikakuPuzzle(2).clues, isNot(buildShikakuPuzzle(3).clues));
    });

    test('levels 1 to 30 have exactly one solution, the stored one', () {
      for (var level = 1; level <= 30; level++) {
        final puzzle = buildShikakuPuzzle(level);
        final size = shikakuSize(level);
        expect(puzzle.cols, size);
        expect(puzzle.rows, size);
        final solutions = ShikakuSolver.of(puzzle).solve(limit: 2);
        expect(solutions, hasLength(1), reason: 'level $level');
        expect(
          solutions.single.toSet(),
          puzzle.solution.toSet(),
          reason: 'level $level',
        );
        var area = 0;
        for (final rect in puzzle.solution) {
          expect(puzzle.isValid(rect), isTrue, reason: 'level $level');
          area += rect.area;
        }
        expect(area, puzzle.cellCount);
      }
    });

    test('generation is fast', () {
      final watch = Stopwatch()..start();
      for (var level = 1; level <= 60; level++) {
        buildShikakuPuzzle(level);
      }
      // 60 levels well under a second on a desktop test machine.
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('ShikakuGame', () {
    testWithGame<ShikakuGame>(
      'applying the solution without mistakes wins with 3 stars',
      () => _game(6),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        expect(game.hasProgress, isFalse);
        expect(game.status.value, 'Cells 0/36 · Mistakes 0');
        for (final rect in game.puzzle.solution) {
          expect(game.result.value, isNull);
          game.draw(rect);
          expect(game.hasProgress, isTrue);
        }
        final result = game.result.value;
        expect(result, isNotNull);
        expect(result!.won, isTrue);
        expect(result.stars, 3);
        expect(game.status.value, 'Cells 36/36 · Mistakes 0');
      },
    );

    testWithGame<ShikakuGame>(
      'mistakes lower the stars; tapping removes a rectangle',
      () => _game(1),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        // A rectangle with no number at all, drawn on a free cell.
        final empty = _freeCell(game.puzzle);
        game.draw(ShikakuRect(empty.$1, empty.$2, 1, 1));
        expect(game.board.mistakes, 1);
        expect(game.status.value, endsWith('Mistakes 1'));
        game.tapCell(empty.$1, empty.$2);
        expect(game.board.placed, isEmpty);
        expect(game.board.mistakes, 1);
        for (final rect in game.puzzle.solution) {
          game.draw(rect);
        }
        expect(game.result.value?.stars, 2);
      },
    );

    testWithGame<ShikakuGame>(
      'dragging across cells draws the previewed rectangle',
      () => _game(1),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        final rect = game.puzzle.solution.first;
        final start = game.cellRect(rect.left, rect.top).center;
        final end = game.cellRect(rect.right - 1, rect.bottom - 1).center;
        expect(game.cellAt(start), (rect.left, rect.top));
        expect(game.cellAt(end), (rect.right - 1, rect.bottom - 1));
        expect(game.cellAt(game.gridRect.topLeft.translate(-5, -5)), isNull);
        game.draw(
          ShikakuRect.spanning(
            game.cellAt(end)!.$1,
            game.cellAt(end)!.$2,
            game.cellAt(start)!.$1,
            game.cellAt(start)!.$2,
          ),
        );
        expect(game.board.placed.single.rect, rect);
        expect(game.board.placed.single.valid, isTrue);
      },
    );

    testWithGame<ShikakuGame>(
      'sounds: tap on place, blocked on a mistake, complete on the win',
      () => _game(1, _sounds),
      (game) async {
        _sounds.events.clear();
        game.onGameResize(Vector2(411, 700));
        final empty = _freeCell(game.puzzle);
        game.draw(ShikakuRect(empty.$1, empty.$2, 1, 1));
        expect(_sounds.events, ['blocked']);
        for (final rect in game.puzzle.solution) {
          game.draw(rect);
        }
        expect(_sounds.events.first, 'blocked');
        expect(_sounds.events.last, 'complete');
        expect(_sounds.events.where((e) => e == 'tap'), isNotEmpty);
      },
    );

    testWithGame<ShikakuGame>(
      'renders a board with placed, red and previewed rectangles',
      () => _game(10),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        game.draw(game.puzzle.solution.first);
        final empty = _freeCell(game.puzzle);
        game.draw(ShikakuRect(empty.$1, empty.$2, 1, 1));
        game.preview = const ShikakuRect(0, 0, 2, 3);
        game.update(0.1);
        final recorder = PictureRecorder();
        game.render(Canvas(recorder));
        recorder.endRecording();
      },
    );
  });
}

final _FakeSounds _sounds = _FakeSounds();

/// A cell without a number, in reading order.
(int, int) _freeCell(ShikakuPuzzle puzzle) {
  for (var row = 0; row < puzzle.rows; row++) {
    for (var col = 0; col < puzzle.cols; col++) {
      if (puzzle.clueAt(col, row) == 0) return (col, row);
    }
  }
  throw StateError('no free cell');
}
