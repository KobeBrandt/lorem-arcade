import 'dart:ui' show Canvas, PictureRecorder;

import 'package:color_flow/arcade/arcade_level_game.dart';
import 'package:color_flow/game/game_feedback.dart';
import 'package:color_flow/games/gate_drop/gate_drop_game.dart';
import 'package:color_flow/games/gate_drop/gate_drop_layout.dart';
import 'package:color_flow/games/gate_drop/gate_drop_levels.dart';
import 'package:color_flow/games/gate_drop/gate_drop_shaft.dart';
import 'package:color_flow/ui/app_theme.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

GateDropLayout _layout(List<GateSpec> gates) => GateDropLayout(
  gates: gates,
  solids: const [],
  balls: 10,
  hordeHp: 10,
  hordeSeconds: 60,
  bestX: 50,
);

GateDropGame _game(int level) => GateDropGame(
  ArcadeSetup(
    level: level,
    style: const BlockStyle(palette: AppColors.blocks),
    haptics: false,
  ),
);

/// Runs the game at 60 frames per second until it ends or [seconds] pass.
void _run(GateDropGame game, double seconds) {
  for (var t = 0.0; t < seconds && game.result.value == null; t += 1 / 60) {
    game.update(1 / 60);
  }
}

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
  void complete(int combo) => events.add('complete $combo');

  @override
  void win() => events.add('win');

  @override
  void fail() => events.add('fail');
}

final _sounds = _FakeSounds();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('gates', () {
    test('a ball crossing an x3 gate becomes 3 balls', () {
      final shaft = GateDropShaft(
        _layout([const GateSpec(x: 50, y: 40, halfWidth: 30, multiplier: 3)]),
      );
      shaft.drop(50, atY: 30);
      for (var i = 0; i < 40; i++) {
        shaft.tick();
      }
      expect(shaft.count, 3);
      expect(shaft.weightInShaft, 3);
    });

    test('a ball never multiplies twice at the same gate', () {
      final shaft = GateDropShaft(
        _layout([const GateSpec(x: 50, y: 40, halfWidth: 40, multiplier: 3)]),
      );
      shaft.drop(50, atY: 30);
      for (var i = 0; i < 40; i++) {
        shaft.tick();
      }
      expect(shaft.count, 3);
      // Lift every ball back above the gate and let it fall again.
      for (var i = 0; i < shaft.count; i++) {
        shaft.y[i] = 30;
        shaft.vy[i] = 0;
      }
      for (var i = 0; i < 30; i++) {
        shaft.tick();
      }
      expect(shaft.count, 3);
    });

    test('a lock opens after its count and then multiplies', () {
      final shaft = GateDropShaft(
        _layout([
          const GateSpec(x: 50, y: 40, halfWidth: 30, multiplier: 2, lock: 5),
        ]),
      );
      for (var n = 0; n < 5; n++) {
        expect(shaft.lockLeft[0], 5 - n);
        shaft.drop(50, atY: 30);
        for (var i = 0; i < 30; i++) {
          shaft.tick();
        }
      }
      expect(shaft.lockLeft[0], 0);
      expect(shaft.locksOpened, 1);
      expect(shaft.count, 0);
      shaft.drop(50, atY: 30);
      for (var i = 0; i < 40; i++) {
        shaft.tick();
      }
      expect(shaft.count, 2);
    });

    test('balls that miss the pipe still reach it', () {
      final shaft = GateDropShaft(_layout(const []));
      shaft.drop(5);
      shaft.drop(95);
      for (var i = 0; i < 120 * 8 && shaft.count > 0; i++) {
        shaft.tick();
      }
      expect(shaft.count, 0);
      expect(shaft.collectedWeight, 2);
    });
  });

  test('stars follow the balls left in the cup', () {
    expect(gateDropStars(40, 100), 3);
    expect(gateDropStars(39, 100), 2);
    expect(gateDropStars(15, 100), 2);
    expect(gateDropStars(14, 100), 1);
    expect(gateDropStars(0, 100), 1);
  });

  test('levels are the same every time', () {
    final a = buildGateDropLevel(7);
    final b = buildGateDropLevel(7);
    expect(a.hordeHp, b.hordeHp);
    expect(a.gates.map((g) => g.x), b.gates.map((g) => g.x));
  });

  group('balance', () {
    for (var level = 1; level <= 10; level++) {
      testWithGame<GateDropGame>(
        'pouring at the best gate wins level $level',
        () => _game(level),
        (game) async {
          game.onGameResize(Vector2(411, 700));
          game.startPour(game.bestPourX);
          expect(game.hasProgress, isFalse);
          _run(game, 0.2);
          expect(game.hasProgress, isTrue);
          _run(game, 120);
          final result = game.result.value;
          expect(result, isNotNull);
          expect(result!.won, isTrue, reason: result.reason);
        },
      );
    }

    testWithGame<GateDropGame>(
      'pouring nothing on level 1 loses',
      () => _game(1),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        _run(game, 200);
        expect(game.result.value, isNotNull);
        expect(game.result.value!.won, isFalse);
        expect(game.result.value!.reason, 'The horde broke through');
        expect(game.hasProgress, isFalse);
      },
    );
  });

  test('horde hit points rise over levels 1 to 10', () {
    var last = 0;
    for (var level = 1; level <= 10; level++) {
      final hp = buildGateDropLevel(level).hordeHp;
      expect(hp, greaterThan(last), reason: 'level $level');
      last = hp;
    }
  });

  testWithGame<GateDropGame>(
    'pouring along the wall on level 10 runs out of balls',
    () => _game(10),
    (game) async {
      game.onGameResize(Vector2(411, 700));
      game.startPour(game.toScreenX(3));
      _run(game, 120);
      expect(game.cupBalls, 0);
      expect(game.result.value?.won, isFalse);
      expect(game.result.value?.reason, 'Out of balls');
    },
  );

  testWithGame<GateDropGame>(
    'sounds: tap when pouring starts, blocked with an empty cup',
    () => GateDropGame(
      ArcadeSetup(
        level: 1,
        style: const BlockStyle(palette: AppColors.blocks),
        sounds: _sounds,
        haptics: false,
      ),
    ),
    (game) async {
      _sounds.events.clear();
      game.onGameResize(Vector2(411, 700));
      expect(game.status.value, 'Balls 40 · Horde ${game.hordeHp}');
      game.startPour(game.bestPourX);
      expect(_sounds.events, ['tap']);
      game.stopPour();
      game.cupBalls = 0;
      game.startPour(game.bestPourX);
      expect(_sounds.events.last, 'blocked');
    },
  );

  testWithGame<GateDropGame>(
    'renders a busy shaft without errors',
    () => _game(8),
    (game) async {
      game.onGameResize(Vector2(800, 1000));
      game.startPour(game.bestPourX);
      _run(game, 3);
      expect(game.shaft.count, greaterThan(0));
      final recorder = PictureRecorder();
      game.render(Canvas(recorder));
      recorder.endRecording().dispose();
    },
  );

  testWidgets('a finger in the shaft pours and moves the cup', (tester) async {
    final game = _game(1);
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    final start = Offset(game.bestPourX, game.shaftRect.center.dy);
    final gesture = await tester.startGesture(start);
    await tester.pump();
    expect(game.pouring, isTrue);
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(game.cupX, lessThan(shaftWidth / 2));
    await gesture.up();
    await tester.pump();
    expect(game.pouring, isFalse);
  });
}
