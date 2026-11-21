import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lorem_arcade/arcade/arcade_level_game.dart';
import 'package:lorem_arcade/game/game_feedback.dart';
import 'package:lorem_arcade/games/kings/kings_board.dart';
import 'package:lorem_arcade/games/kings/kings_game.dart';
import 'package:lorem_arcade/games/kings/kings_generator.dart';
import 'package:lorem_arcade/games/kings/kings_painter.dart';
import 'package:lorem_arcade/ui/app_theme.dart';

ArcadeSetup _setup(int level) => ArcadeSetup(
  level: level,
  style: const BlockStyle(palette: AppColors.blocks),
  haptics: false,
);

/// A 4x4 puzzle with known regions, one per row:
///
///     0 0 0 1
///     0 0 1 1
///     2 2 1 3
///     2 3 3 3
const KingsPuzzle _small = KingsPuzzle(
  size: 4,
  regions: [0, 0, 0, 1, 0, 0, 1, 1, 2, 2, 1, 3, 2, 3, 3, 3],
  solution: [1, 3, 0, 2],
);

void main() {
  group('Kings generator', () {
    test('the grid grows with the level up to 9x9', () {
      expect(kingsSizeForLevel(1), 5);
      expect(kingsSizeForLevel(4), 6);
      expect(kingsSizeForLevel(9), 7);
      expect(kingsSizeForLevel(16), 8);
      expect(kingsSizeForLevel(25), 9);
      expect(kingsSizeForLevel(500), kingsMaxSize);
      for (var level = 1; level < 60; level++) {
        expect(
          kingsSizeForLevel(level + 1),
          greaterThanOrEqualTo(kingsSizeForLevel(level)),
        );
      }
    });

    test('the same level always gives the same puzzle', () {
      for (final level in [1, 7, 20, 31]) {
        final a = generateKingsPuzzle(level);
        final b = generateKingsPuzzle(level);
        expect(a.regions, b.regions);
        expect(a.solution, b.solution);
      }
      expect(
        generateKingsPuzzle(2).regions,
        isNot(generateKingsPuzzle(3).regions),
      );
    });

    test('levels 1-30 have N contiguous regions and one solution', () {
      final watch = Stopwatch()..start();
      for (var level = 1; level <= 30; level++) {
        final p = generateKingsPuzzle(level);
        final n = p.size;
        expect(p.regions.length, n * n);
        expect(p.regions.toSet(), {for (var i = 0; i < n; i++) i});
        for (var region = 0; region < n; region++) {
          expect(
            isRegionContiguous(n, p.regions, region),
            isTrue,
            reason: 'level $level region $region',
          );
        }
        final solutions = solveKings(n, p.regions, limit: 3);
        expect(solutions, [p.solution], reason: 'level $level');
      }
      watch.stop();
      // ignore: avoid_print
      print('Generated levels 1-30 in ${watch.elapsedMilliseconds} ms');
    });

    test('the stored solution follows every rule', () {
      for (final level in [1, 12, 30]) {
        final p = generateKingsPuzzle(level);
        final board = KingsBoard(p);
        for (var row = 0; row < p.size; row++) {
          board.setKing(row * p.size + p.solution[row]);
        }
        expect(board.solved, isTrue);
      }
    });

    test('the solver finds the one solution of a known puzzle', () {
      expect(solveKings(4, _small.regions, limit: 5), [_small.solution]);
    });

    test('the solver finds every solution of a puzzle with two', () {
      // Four 1x4 column strips: no touching rule on rows breaks it down
      // to the two 4x4 permutations with no neighbors in a row.
      final strips = [for (var i = 0; i < 16; i++) i % 4];
      expect(solveKings(4, strips, limit: 10).length, 2);
      expect(solveKings(4, strips, limit: 1).length, 1);
    });
  });

  group('Kings rules', () {
    // Cell index of (row, col) on the 4x4 puzzle.
    int at(int row, int col) => row * 4 + col;

    test('kings clash on the same row, column, region or when touching', () {
      expect(kingsClash(_small, at(0, 0), at(0, 3)), isTrue); // row
      expect(kingsClash(_small, at(0, 2), at(3, 2)), isTrue); // column
      expect(kingsClash(_small, at(0, 0), at(1, 2)), isFalse);
      expect(kingsClash(_small, at(0, 2), at(1, 0)), isTrue); // region 0
      expect(kingsClash(_small, at(2, 3), at(3, 1)), isTrue); // region 3
      expect(kingsClash(_small, at(1, 1), at(2, 2)), isTrue); // diagonal touch
      expect(kingsClash(_small, at(1, 2), at(2, 2)), isTrue); // side touch
      expect(kingsClash(_small, at(1, 3), at(3, 1)), isFalse);
      expect(kingsClash(_small, at(0, 0), at(2, 3)), isFalse);
    });

    test('a tap toggles a king and crosses the cells it rules out', () {
      final board = KingsBoard(_small);
      expect(board.markAt(0, 0), KingsMark.empty);
      expect(board.tap(0, 0), KingsTapOutcome.king);
      expect(board.markAt(0, 0), KingsMark.king);
      expect(board.mistakes, 0);
      // Row, column, touching cells and region are crossed; others not.
      expect(board.markAt(0, 3), KingsMark.cross); // row
      expect(board.markAt(3, 0), KingsMark.cross); // column
      expect(board.markAt(1, 1), KingsMark.cross); // diagonal touch
      expect(board.markAt(0, 2), KingsMark.cross); // row
      expect(board.markAt(1, 2), KingsMark.empty);
      expect(board.markAt(2, 3), KingsMark.empty);
      expect(board.tap(0, 0), KingsTapOutcome.cleared);
      expect(board.markAt(0, 0), KingsMark.empty);
      expect(board.markAt(0, 3), KingsMark.empty);
      expect(board.mistakes, 1); // taking a king off is a mistake
      expect(board.tap(-1, 0), KingsTapOutcome.ignored);
      expect(board.tap(0, 4), KingsTapOutcome.ignored);
      expect(board.mistakes, 1);
    });

    test('a king on a crossed cell clashes, turns red and is a mistake', () {
      final board = KingsBoard(_small);
      expect(board.tap(0, 1), KingsTapOutcome.king); // region 0
      expect(board.clashingKings, isEmpty);
      expect(board.markAt(1, 0), KingsMark.cross);
      expect(board.tap(1, 0), KingsTapOutcome.clash); // touches and region 0
      expect(board.markAt(1, 0), KingsMark.king);
      expect(board.mistakes, 1);
      expect(board.clashingKings, {at(0, 1), at(1, 0)});

      // Taking it off clears the red and is one more mistake.
      expect(board.tap(1, 0), KingsTapOutcome.cleared);
      expect(board.clashingKings, isEmpty);
      expect(board.mistakes, 2);

      // A clash with two kings still counts once.
      expect(board.tap(3, 1), KingsTapOutcome.clash); // column of (0, 1)
      expect(board.mistakes, 3);
      expect(board.clashingKings, {at(0, 1), at(3, 1)});
      expect(board.solved, isFalse);
    });

    test('the puzzle is solved when N kings stand without a clash', () {
      final board = KingsBoard(_small);
      for (var row = 0; row < 4; row++) {
        expect(board.solved, isFalse);
        expect(board.tap(row, _small.solution[row]), KingsTapOutcome.king);
      }
      expect(board.kingCount, 4);
      expect(board.solved, isTrue);
      expect(board.mistakes, 0);
      expect(board.tap(0, 0), KingsTapOutcome.ignored);
    });

    test('stars come from the mistakes', () {
      expect(kingsStars(0), 3);
      expect(kingsStars(1), 2);
      expect(kingsStars(2), 2);
      expect(kingsStars(3), 1);
      expect(kingsStars(40), 1);
    });
  });

  group('Kings colors', () {
    test('up to 9 regions get 9 different looks with a 6-color theme', () {
      const palette = AppColors.blocks;
      final looks = {
        for (var region = 0; region < kingsMaxSize; region++)
          (
            kingsRegionColor(palette, region).toARGB32(),
            kingsRegionStriped(palette, region),
          ),
      };
      expect(looks.length, kingsMaxSize);
      final colors = {
        for (var region = 0; region < kingsMaxSize; region++)
          kingsRegionColor(palette, region).toARGB32(),
      };
      expect(colors.length, kingsMaxSize);
    });
  });

  group('KingsGame', () {
    test('status, progress and mistakes', () {
      final game = KingsGame(_setup(1));
      final n = game.board.size;
      expect(game.status.value, 'Kings 0/$n · Mistakes 0');
      expect(game.hasProgress, isFalse);
      game.tapCell(0, 0);
      expect(game.hasProgress, isTrue);
      expect(game.status.value, 'Kings 1/$n · Mistakes 0');
      game.tapCell(0, 1); // same row
      expect(game.status.value, 'Kings 2/$n · Mistakes 1');
      game.tapCell(0, 1); // taken off
      expect(game.status.value, 'Kings 1/$n · Mistakes 2');
      expect(game.result.value, isNull);
    });

    test('a solve with mistakes gives fewer stars', () {
      final game = KingsGame(_setup(2));
      final p = game.board.puzzle;
      // Three clashing kings in row 0 next to the right one.
      final wrong = [
        for (var c = 0; c < p.size; c++)
          if (c != p.solution[0]) c,
      ].take(3);
      for (final c in wrong) {
        game.tapCell(0, c);
      }
      for (var row = 0; row < p.size; row++) {
        game.tapCell(row, p.solution[row]);
      }
      expect(game.result.value, isNull); // wrong kings still stand
      for (final c in wrong) {
        game.tapCell(0, c);
      }
      expect(game.result.value?.won, isTrue);
      expect(game.result.value?.stars, 1);
    });

    testWithGame<KingsGame>(
      'tapping in the solution wins with 3 stars',
      () => KingsGame(_setup(5)),
      (game) async {
        game.update(0.016);
        expect(game.cell, greaterThan(1));
        final p = game.board.puzzle;
        for (var row = 0; row < p.size; row++) {
          expect(game.tapCell(row, p.solution[row]), KingsTapOutcome.king);
        }
        expect(game.result.value?.won, isTrue);
        expect(game.result.value?.stars, 3);
        expect(game.status.value, 'Kings ${p.size}/${p.size} · Mistakes 0');
        expect(game.tapCell(0, 0), KingsTapOutcome.ignored);
      },
    );
  });
}
