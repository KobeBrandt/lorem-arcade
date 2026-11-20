import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lorem_arcade/arcade/arcade_level_game.dart';
import 'package:lorem_arcade/game/game_feedback.dart';
import 'package:lorem_arcade/games/moo_munch/moo_munch_board.dart';
import 'package:lorem_arcade/games/moo_munch/moo_munch_game.dart';
import 'package:lorem_arcade/games/moo_munch/moo_munch_level.dart';
import 'package:lorem_arcade/ui/app_theme.dart';

ArcadeSetup _setup(int level) => ArcadeSetup(
  level: level,
  style: const BlockStyle(palette: AppColors.blocks),
  haptics: false,
);

void main() {
  group('MooMunchBoard', () {
    test('the cow waits for the first turn and may not turn back', () {
      final board = MooMunchBoard(cols: 9, rows: 9);
      board.carrot = null;
      expect(board.step(), StepOutcome.idle);
      expect(board.turn(Heading.left), isFalse); // into its own neck
      expect(board.turn(Heading.right), isFalse); // already facing right
      expect(board.turn(Heading.up), isTrue);
      expect(board.step(), StepOutcome.moved);
      expect(board.head, (x: 4, y: 3));
      expect(board.body.length, 3);
    });

    test('eating a carrot grows the tail and moves the carrot', () {
      final board = MooMunchBoard(cols: 9, rows: 9);
      // Put the carrot right in front of the cow.
      board.carrot = (x: board.head.x, y: board.head.y - 1);
      board.turn(Heading.up);
      expect(board.step(), StepOutcome.ate);
      expect(board.body.length, 4);
      expect(board.carrot, isNotNull);
      expect(board.body.contains(board.carrot), isFalse);
    });

    test('the fence and rocks stop the cow; reset puts it back', () {
      final board = MooMunchBoard(cols: 9, rows: 9, rocks: {(x: 4, y: 2)});
      board.carrot = null;
      board.turn(Heading.up);
      expect(board.step(), StepOutcome.moved); // y 3
      expect(board.step(), StepOutcome.crashed); // rock at y 2
      board.reset();
      expect(board.head, board.startHead);
      expect(board.moving, isFalse);

      board.turn(Heading.down);
      var outcome = StepOutcome.moved;
      for (var i = 0; i < 10 && outcome != StepOutcome.crashed; i++) {
        outcome = board.step();
      }
      expect(outcome, StepOutcome.crashed); // the bottom fence
    });

    test('carrots never grow on rocks or in closed-off cells', () {
      // A rock wall cuts off the top row.
      final wall = {for (var x = 0; x < 7; x++) (x: x, y: 1)};
      for (var seed = 0; seed < 30; seed++) {
        final board = MooMunchBoard(cols: 7, rows: 7, rocks: wall, seed: seed);
        expect(board.carrot!.y, greaterThan(1));
      }
    });
  });

  group('Moo Munch levels', () {
    test('later levels need more carrots, go faster and add rocks', () {
      final first = buildMooMunchLevel(1);
      final later = buildMooMunchLevel(8);
      expect(later.carrots, greaterThan(first.carrots));
      expect(later.stepSeconds, lessThan(first.stepSeconds));
      expect(first.rocks, isEmpty);
      expect(later.rocks, isNotEmpty);
      expect(buildMooMunchLevel(8).rocks, later.rocks);
      const startY = mooRows ~/ 2;
      expect(later.rocks.any((r) => r.y == startY), isFalse);
    });
  });

  group('MooMunchGame', () {
    test('a crash costs a life; the last one loses the level', () {
      final game = MooMunchGame.levels(_setup(1));
      game.board.carrot = null;
      for (var life = mooLives; life > 0; life--) {
        game.board.carrot = null;
        game.steer(Heading.up);
        for (var i = 0; i < mooRows && game.lives == life; i++) {
          game.tick();
        }
      }
      expect(game.lives, 0);
      expect(game.result.value?.won, isFalse);
    });

    test('eating the level carrots wins with stars = lives left', () {
      final game = MooMunchGame.levels(_setup(1));
      game.lives = 2;
      game.carrots = game.level.carrots - 1;
      game.board.carrot = (x: game.board.head.x, y: game.board.head.y - 1);
      game.steer(Heading.up);
      game.tick();
      expect(game.result.value?.won, isTrue);
      expect(game.result.value?.stars, 2);
    });

    test('endless ends on the first crash with the carrots as score', () {
      final game = MooMunchGame.endless(_setup(1));
      game.carrots = 7;
      game.board.carrot = null;
      game.steer(Heading.up);
      for (var i = 0; i < mooRows && game.result.value == null; i++) {
        game.tick();
      }
      expect(game.result.value?.score, 7);
      expect(game.result.value?.won, isFalse);
    });

    testWithGame<MooMunchGame>(
      'renders and steps in a real game loop',
      () => MooMunchGame.levels(_setup(3)),
      (game) async {
        game.steer(Heading.up);
        // Frames are capped at 0.1 s; one step takes about 0.22 s.
        for (var i = 0; i < 5; i++) {
          game.update(0.1);
        }
        expect(game.hasProgress, isTrue);
        expect(game.status.value, startsWith('Carrots'));
      },
    );
  });

  test('silent sounds are the default', () {
    expect(_setup(1).sounds, isA<SilentSounds>());
  });
}
