import 'dart:math' show max;
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:lorem_arcade/arcade/arcade_level_game.dart';
import 'package:lorem_arcade/game/game_feedback.dart';
import 'package:lorem_arcade/games/gate_drop/gate_drop_game.dart';
import 'package:lorem_arcade/games/gate_drop/gate_drop_layout.dart';
import 'package:lorem_arcade/games/gate_drop/gate_drop_levels.dart';
import 'package:lorem_arcade/games/gate_drop/gate_drop_shaft.dart';
import 'package:lorem_arcade/ui/app_theme.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

GateDropLayout _layout(
  List<GateSpec> gates, {
  List<SolidSpec> solids = const [],
  int shieldGate = -1,
}) => GateDropLayout(
  gates: gates,
  solids: solids,
  balls: 10,
  hordeHp: 10,
  hordeSeconds: 60,
  bestX: 50,
  shieldGate: shieldGate,
);

ArcadeSetup _setup(int level) => ArcadeSetup(
  level: level,
  style: const BlockStyle(palette: AppColors.blocks),
  haptics: false,
);

GateDropGame _game(int level) => GateDropGame(_setup(level));

/// Runs [shaft] for [seconds] of shaft time.
void _tick(GateDropShaft shaft, double seconds) {
  for (var i = 0; i < seconds / GateDropShaft.step; i++) {
    shaft.tick();
  }
}

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

    test('a gate counts the balls it multiplied', () {
      final shaft = GateDropShaft(
        _layout(const [GateSpec(x: 50, y: 60, halfWidth: 10, multiplier: 2)]),
      );
      expect(shaft.gateHits[0], 0);
      shaft.drop(50);
      for (var i = 0; i < 120; i++) {
        shaft.tick();
      }
      expect(shaft.gateHits[0], 1);
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
      'the horde waits for the first pour',
      () => _game(1),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        _run(game, 200);
        expect(game.result.value, isNull);
        expect(game.hordeProgress, 0);
        expect(game.hasProgress, isFalse);
      },
    );

    testWithGame<GateDropGame>(
      'a short pour and then nothing lets the horde break through',
      () => _game(1),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        game.startPour(game.bestPourX);
        _run(game, 0.3);
        game.stopPour();
        expect(game.cupBalls, greaterThan(0));
        _run(game, 200);
        expect(game.result.value?.won, isFalse);
        expect(game.result.value?.reason, 'The horde broke through');
        expect(game.hordeProgress, 1);
        expect(game.hasProgress, isTrue);
      },
    );

    testWithGame<GateDropGame>('a pause stops the pour', () => _game(1), (
      game,
    ) async {
      game.onGameResize(Vector2(411, 700));
      game.startPour(game.bestPourX);
      expect(game.pouring, isTrue);
      game.pauseEngine();
      expect(game.pouring, isFalse);
      game.resumeEngine();
      final balls = game.cupBalls;
      _run(game, 1);
      expect(game.cupBalls, balls, reason: 'no pour after the resume');
    });

    testWithGame<GateDropGame>(
      'a gate glows when it multiplies balls',
      () => _game(1),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        expect(game.gateFlash.every((f) => f == 0), isTrue);
        game.startPour(game.bestPourX);
        _run(game, 1.5);
        expect(game.shaft.gateHits.any((h) => h > 0), isTrue);
        expect(game.gateFlash.any((f) => f > 0), isTrue);
      },
    );
  });

  test('horde hit points rise over the normal levels 1 to 10', () {
    var last = 0;
    for (var level = 1; level <= 10; level++) {
      if (gateDropLevelKind(level) != LevelKind.normal) continue;
      final hp = buildGateDropLevel(level).hordeHp;
      expect(hp, greaterThan(last), reason: 'level $level');
      last = hp;
    }
  });

  testWithGame<GateDropGame>(
    'pouring along the wall on level 6 runs out of balls',
    () => _game(6),
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

  group('new shaft parts', () {
    test('a trap keeps every second ball', () {
      final shaft = GateDropShaft(
        _layout(const [
          GateSpec(
            x: 50,
            y: 40,
            halfWidth: 30,
            multiplier: 1,
            kind: GateKind.halve,
          ),
        ]),
      );
      for (var n = 0; n < 4; n++) {
        shaft.drop(50, atY: 30);
        _tick(shaft, 0.4);
      }
      expect(shaft.gateHits[0], 4);
      expect(shaft.trappedWeight, 2);
      expect(shaft.weightInShaft + shaft.collectedWeight, 2);
    });

    test('a trap halves the weight of a merged ball', () {
      final shaft = GateDropShaft(
        _layout(const [
          GateSpec(
            x: 50,
            y: 40,
            halfWidth: 30,
            multiplier: 1,
            kind: GateKind.halve,
          ),
        ]),
      );
      shaft.drop(50, atY: 30);
      shaft.weight[0] = 6;
      _tick(shaft, 0.4);
      expect(shaft.weightInShaft, 3);
      expect(shaft.trappedWeight, 3);
    });

    test('a refill gate sends the ball back to the cup', () {
      final shaft = GateDropShaft(
        _layout(const [
          GateSpec(
            x: 50,
            y: 40,
            halfWidth: 30,
            multiplier: 1,
            kind: GateKind.refill,
          ),
        ]),
      );
      shaft.drop(50, atY: 30);
      shaft.weight[0] = 4;
      _tick(shaft, 0.4);
      expect(shaft.count, 0);
      expect(shaft.refilledWeight, 4);
      expect(shaft.collectedWeight, 0);
    });

    test('a bumper kicks a ball sideways, a peg barely does', () {
      double sideSpeed(SolidSpec solid) {
        final shaft = GateDropShaft(_layout(const [], solids: [solid]));
        shaft.drop(50.5, atY: 30);
        shaft.vx[0] = 0;
        var most = 0.0;
        for (var i = 0; i < 60; i++) {
          shaft.tick();
          if (shaft.count > 0) most = max(most, shaft.vx[0].abs());
        }
        return most;
      }

      final bumper = sideSpeed(const SolidSpec.bumper(50, 45));
      final peg = sideSpeed(const SolidSpec.peg(50, 45));
      expect(bumper, greaterThan(GateDropShaft.bumperKick * 0.3));
      expect(bumper, greaterThan(peg * 2));
    });

    test('balls do no damage while the shield lock is closed', () {
      final shaft = GateDropShaft(
        _layout(const [
          GateSpec(x: 20, y: 40, halfWidth: 8, multiplier: 2, lock: 3),
        ], shieldGate: 0),
      );
      expect(shaft.shieldUp, isTrue);
      shaft.drop(80);
      _tick(shaft, 6);
      expect(shaft.collectedWeight, 1);
      expect(shaft.damageWeight, 0);
      for (var n = 0; n < 3; n++) {
        shaft.drop(20, atY: 30);
        _tick(shaft, 0.2);
      }
      expect(shaft.shieldUp, isFalse);
      shaft.drop(80);
      _tick(shaft, 6);
      expect(shaft.damageWeight, 1);
    });
  });

  group('level kinds and parts', () {
    test('every 5th level is a boss, every 7th a bonus, boss first', () {
      expect(gateDropLevelKind(4), LevelKind.normal);
      expect(gateDropLevelKind(5), LevelKind.boss);
      expect(gateDropLevelKind(7), LevelKind.bonus);
      expect(gateDropLevelKind(14), LevelKind.bonus);
      expect(gateDropLevelKind(35), LevelKind.boss);
    });

    bool has(GateDropLayout l, bool Function(GateSpec) test) =>
        l.gates.any(test);

    test('new parts show up from their levels on', () {
      final l3 = buildGateDropLevel(3);
      expect(has(l3, (g) => g.kind == GateKind.halve), isFalse);
      expect(l3.solids.any((s) => s.bumper), isFalse);
      expect(
        has(buildGateDropLevel(trapFromLevel), (g) => g.kind == GateKind.halve),
        isTrue,
      );
      expect(buildGateDropLevel(6).solids.any((s) => s.bumper), isTrue);
      expect(has(buildGateDropLevel(6), (g) => g.isJackpot), isFalse);
      final l8 = buildGateDropLevel(jackpotFromLevel);
      expect(has(l8, (g) => g.isJackpot), isTrue);
      expect(has(l8, (g) => g.kind == GateKind.refill), isTrue);
      // The jackpot is never the aim line.
      final jackpot = l8.gates.firstWhere((g) => g.isJackpot);
      expect(jackpot.swing, greaterThan(0));
      expect(
        l8.gates.where((g) => !g.isJackpot).any((g) => g.x == l8.bestX),
        isTrue,
      );
    });

    test('a boss level shields its lock; a bonus level has no refill', () {
      final boss = buildGateDropLevel(5);
      expect(boss.kind, LevelKind.boss);
      expect(boss.shieldGate, greaterThanOrEqualTo(0));
      expect(boss.gates[boss.shieldGate].lock, greaterThan(0));
      final bonus = buildGateDropLevel(14);
      expect(bonus.kind, LevelKind.bonus);
      expect(has(bonus, (g) => g.kind == GateKind.refill), isFalse);
    });

    test('endless waves depend on the run seed', () {
      final a = buildGateDropWave(3, 1);
      final b = buildGateDropWave(3, 1);
      final c = buildGateDropWave(3, 2);
      expect(a.gates.map((g) => g.x), b.gates.map((g) => g.x));
      expect(a.gates.map((g) => g.x), isNot(c.gates.map((g) => g.x)));
      expect(buildGateDropWave(5, 1).kind, LevelKind.normal);
    });

    test('bonus stars follow the damage against the target', () {
      expect(gateDropBonusStars(90, 100), 3);
      expect(gateDropBonusStars(89, 100), 2);
      expect(gateDropBonusStars(60, 100), 2);
      expect(gateDropBonusStars(59, 100), 1);
    });
  });

  group('balance of the new levels', () {
    for (var level = 11; level <= 16; level++) {
      testWithGame<GateDropGame>(
        'pouring at the best gate wins level $level',
        () => _game(level),
        (game) async {
          game.onGameResize(Vector2(411, 700));
          game.startPour(game.bestPourX);
          _run(game, 180);
          final result = game.result.value;
          expect(result, isNotNull);
          expect(result!.won, isTrue, reason: result.reason);
        },
      );
    }
  });

  group('game systems', () {
    testWithGame<GateDropGame>(
      'a full fever meter starts a fever that doubles the damage',
      () => _game(2),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        game.feverMeter = GateDropGame.feverPoints - 1.0;
        game.startPour(game.bestPourX);
        _run(game, 1);
        expect(game.inFever, isTrue);
        expect(game.feverMeter, 0);
        _run(game, 3);
        expect(game.damageDealt, greaterThan(game.shaft.damageWeight));
        expect(game.banner, 'FEVER x2');
      },
    );

    testWithGame<GateDropGame>(
      'the fever ends after its seconds',
      () => _game(2),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        game.feverLeft = 1;
        _run(game, 1.1);
        expect(game.inFever, isFalse);
      },
    );

    testWithGame<GateDropGame>(
      'big bursts push the horde back',
      () => _game(3),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        game.startPour(game.bestPourX);
        _run(game, 120);
        expect(game.result.value?.won, isTrue);
        expect(game.knockbacks, greaterThan(0));
      },
    );

    testWithGame<GateDropGame>(
      'pops, sparks and combo sounds come with a good pour',
      () => GateDropGame(
        ArcadeSetup(
          level: 3,
          style: const BlockStyle(palette: AppColors.blocks),
          sounds: _sounds,
          haptics: false,
        ),
      ),
      (game) async {
        _sounds.events.clear();
        game.onGameResize(Vector2(411, 700));
        game.startPour(game.bestPourX);
        _run(game, 2.5);
        expect(game.popAge.any((a) => a >= 0), isTrue);
        expect(game.popText.contains('x2'), isTrue);
        expect(game.comboLevel, greaterThan(0));
        final combos = _sounds.events.where((e) => e.startsWith('complete'));
        expect(combos, isNotEmpty);
        // The combo climbs: a later step is higher than the first.
        expect(combos.last.compareTo(combos.first), greaterThanOrEqualTo(0));
        _run(game, 4);
        final recorder = PictureRecorder();
        game.render(Canvas(recorder));
        recorder.endRecording().dispose();
      },
    );

    testWithGame<GateDropGame>(
      'a lock that opens shakes the screen and bursts sparks',
      () => _game(3),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        game.startPour(game.bestPourX);
        for (var t = 0.0; t < 30 && game.shaft.locksOpened == 0; t += 1 / 60) {
          game.update(1 / 60);
        }
        expect(game.shaft.locksOpened, 1);
        expect(game.shake, greaterThan(0));
        expect(game.sparkAge.any((a) => a >= 0), isTrue);
      },
    );

    testWithGame<GateDropGame>(
      'a hit flashes the horde and the ghost bar trails the HP',
      () => _game(1),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        game.startPour(game.bestPourX);
        for (var t = 0.0; t < 10 && game.damageDealt == 0; t += 1 / 60) {
          game.update(1 / 60);
        }
        expect(game.hordeFlash, greaterThan(0));
        expect(game.ghostHp, greaterThanOrEqualTo(game.hordeHp));
      },
    );

    testWithGame<GateDropGame>(
      'the boss takes no damage before the shield lock opens',
      () => _game(5),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        expect(game.isBoss, isTrue);
        game.startPour(game.bestPourX);
        _run(game, 1);
        expect(game.shaft.shieldUp, isTrue);
        expect(game.hordeHp, game.layout.hordeHp);
        _run(game, 120);
        expect(game.result.value?.won, isTrue);
      },
    );

    testWithGame<GateDropGame>(
      'a bonus level never walks and ends when the cup is empty',
      () => _game(7),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        expect(game.isBonus, isTrue);
        expect(game.status.value, startsWith('Bonus'));
        game.startPour(game.bestPourX);
        _run(game, 120);
        expect(game.hordeProgress, 0);
        final result = game.result.value!;
        expect(result.won, isTrue);
        expect(
          result.stars,
          gateDropBonusStars(game.damageDealt, game.layout.hordeHp),
        );
      },
    );

    testWithGame<GateDropGame>(
      'endless: a beaten horde starts the next wave with a full cup',
      () => GateDropGame.endless(_setup(1), runSeed: 3),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        expect(game.status.value, startsWith('Wave 1'));
        for (var t = 0.0; t < 120 && game.wave == 1; t += 1 / 60) {
          game.startPour(game.bestPourX);
          game.update(1 / 60);
        }
        expect(game.wave, 2);
        expect(game.wavesCleared, 1);
        expect(game.result.value, isNull);
        expect(game.cupBalls, greaterThanOrEqualTo(game.startBalls));
        expect(game.hordeProgress, 0);
        expect(game.banner, 'Wave 2');
      },
    );

    testWithGame<GateDropGame>(
      'endless: the run ends with the waves as score',
      () => GateDropGame.endless(_setup(1), runSeed: 3),
      (game) async {
        game.onGameResize(Vector2(411, 700));
        for (var t = 0.0; t < 120 && game.wave == 1; t += 1 / 60) {
          game.startPour(game.bestPourX);
          game.update(1 / 60);
        }
        // A short pour starts the next horde, then nothing.
        game.startPour(game.bestPourX);
        _run(game, 0.3);
        game.stopPour();
        _run(game, 400);
        final result = game.result.value!;
        expect(result.won, isFalse);
        expect(result.score, 1);
      },
    );
  });

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
