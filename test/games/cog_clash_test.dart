import 'dart:ui' show Canvas, PictureRecorder;

import 'package:color_flow/arcade/arcade_level_game.dart';
import 'package:color_flow/game/game_feedback.dart';
import 'package:color_flow/games/cog_clash/cog_battle.dart';
import 'package:color_flow/games/cog_clash/cog_clash_game.dart';
import 'package:color_flow/games/cog_clash/cog_model.dart';
import 'package:color_flow/ui/app_theme.dart';
import 'package:flame/events.dart' show TapDownEvent;
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, TapDownDetails;
import 'package:flutter_test/flutter_test.dart';

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

CogClashGame Function() _game(int level, {GameSounds? sounds}) =>
    () => CogClashGame(
      ArcadeSetup(
        level: level,
        style: const BlockStyle(palette: AppColors.blocks),
        sounds: sounds ?? const SilentSounds(),
        haptics: false,
      ),
    );

/// Phone portrait area under the shell's top bar.
void _prepare(CogClashGame game) => game.onGameResize(Vector2(411, 700));

/// Runs the fight until it ends (or a little past the length cap).
void _runFight(CogClashGame game) {
  for (var i = 0; i < 60 * 100 && game.result.value == null; i++) {
    game.update(1 / 60);
  }
}

/// Buys the offer with the most power gained per coin and places it in
/// a socket linked to a weapon, until nothing helps. Then fights.
void _autoBuild(CogClashGame game) {
  var rerolls = 0;
  while (true) {
    var best = 0.0;
    int? bestOffer;
    int? bestSocket;
    for (var i = 0; i < CogShop.offerCount; i++) {
      if (!game.shop.canAfford(i)) continue;
      final gear = game.shop.offers[i];
      for (final socket in game.board.linkedEmptySockets) {
        final copy = game.board.copy()..place(socket, gear);
        final gain = (copy.totalPower - game.board.totalPower) / gear.price;
        if (gain > best) {
          best = gain;
          bestOffer = i;
          bestSocket = socket;
        }
      }
    }
    if (bestOffer == null) {
      if (game.shop.coins >= 2 && rerolls < 10) {
        game.reroll();
        rerolls++;
        continue;
      }
      break;
    }
    expect(game.selectOffer(bestOffer), isTrue);
    expect(game.tapSocket(bestSocket!), isTrue);
  }
  game.startFight();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('power', () {
    CogBoard board() => CogBoard(weapons: const [5]);

    test('sums a chain of number gears linked to the weapon', () {
      final b = board()
        ..place(6, const Gear.number(2))
        ..place(7, const Gear.number(5))
        ..place(12, const Gear.number(1));
      expect(b.powerOf(5), 8);
      expect(b.powered, {6, 7, 12});
    });

    test('gears without a link to the weapon add nothing', () {
      final b = board()
        ..place(6, const Gear.number(3))
        ..place(9, const Gear.number(7))
        ..place(19, const Gear.multiplier(3));
      expect(b.powerOf(5), 3);
      expect(b.powered, {6});
    });

    test('multipliers in the chain multiply the sum', () {
      final b = board()
        ..place(6, const Gear.number(4))
        ..place(7, const Gear.multiplier(2))
        ..place(8, const Gear.number(1))
        ..place(0, const Gear.multiplier(3));
      expect(b.powerOf(5), (4 + 1) * 2 * 3);
    });

    test('a multiplier alone gives no power', () {
      final b = board()..place(6, const Gear.multiplier(3));
      expect(b.powerOf(5), 0);
    });

    test('a chain can feed two weapons', () {
      final b = CogBoard(weapons: const [5, 14]);
      // 6-7-8 and 13 (below 8, next to weapon 14). Different values,
      // so nothing merges.
      final values = {6: 1, 7: 2, 8: 3, 13: 4};
      values.forEach((s, v) => b.place(s, Gear.number(v)));
      expect(b.powerOf(5), 10);
      expect(b.powerOf(14), 10);
      expect(b.totalPower, 20);
    });

    test('equal number gears side by side merge into the sum', () {
      final b = board()..place(6, const Gear.number(3));
      final placement = b.place(7, const Gear.number(3))!;
      expect(placement.merged, isTrue);
      expect(placement.socket, 6);
      expect(b.gearAt(6), const Gear.number(6));
      expect(b.isEmpty(7), isTrue);
      expect(b.powerOf(5), 6);
    });

    test('stars follow the fighter HP left', () {
      expect(starsForHp(100, 100), 3);
      expect(starsForHp(67, 100), 3);
      expect(starsForHp(60, 100), 2);
      expect(starsForHp(30, 100), 1);
    });
  });

  group('shop', () {
    testWithGame<CogClashGame>(
      'an offer the coins do not cover is rejected',
      _game(1),
      (game) async {
        _prepare(game);
        // Spend coins until the cheapest offer is out of reach.
        while (true) {
          final i = [
            0,
            1,
            2,
          ].firstWhere((i) => game.shop.canAfford(i), orElse: () => -1);
          if (i < 0) break;
          final socket = game.board.linkedEmptySockets.first;
          expect(game.selectOffer(i), isTrue);
          expect(game.tapSocket(socket), isTrue);
        }
        final coins = game.shop.coins;
        expect(game.selectOffer(0), isFalse);
        expect(game.selectedOffer, isNull);
        expect(game.shop.coins, coins);
      },
    );

    testWithGame<CogClashGame>(
      'placing in a taken socket is rejected',
      _game(2, sounds: _sounds),
      (g) async {
        _prepare(g);
        expect(g.hasProgress, isFalse);
        expect(g.selectOffer(0), isTrue);
        expect(g.tapSocket(6), isTrue);
        expect(g.hasProgress, isTrue);
        final coins = g.shop.coins;
        final gear = g.board.gearAt(6);
        expect(g.selectOffer(1), isTrue);
        _sounds.events.clear();
        expect(g.tapSocket(6), isFalse);
        expect(g.tapSocket(5), isFalse, reason: 'weapon socket');
        expect(g.shop.coins, coins);
        expect(g.board.gearAt(6), gear);
        expect(_sounds.events, ['blocked', 'blocked']);
      },
    );

    testWithGame<CogClashGame>('reroll costs one coin', _game(3), (game) async {
      _prepare(game);
      final coins = game.shop.coins;
      expect(game.reroll(), isTrue);
      expect(game.shop.coins, coins - 1);
    });

    testWithGame<CogClashGame>(
      'tap on an offer then on a socket places the gear',
      _game(1),
      (game) async {
        _prepare(game);
        final hint = game.config.hintSocket!;
        expect(game.board.weapons, contains(hint - 1));
        game.onTapDown(_tap(game, game.offerRect(0).center));
        expect(game.selectedOffer, 0);
        game.onTapDown(_tap(game, game.socketRect(hint).center));
        expect(game.board.gearAt(hint), isNotNull);
        expect(game.board.totalPower, greaterThan(0));
        game.onTapDown(_tap(game, game.fightRect.center));
        expect(game.isFighting, isTrue);
      },
    );

    test('tap targets are at least 48 px', () {
      final game = _game(4)();
      game.onGameResize(Vector2(411, 700));
      expect(game.socketRect(0).width, greaterThanOrEqualTo(48));
      expect(game.offerRect(0).height, greaterThanOrEqualTo(48));
      expect(game.rerollRect.width, greaterThanOrEqualTo(48));
      expect(game.fightRect.height, greaterThanOrEqualTo(48));
      game.onGameResize(Vector2(1024, 1300));
      expect(game.fightRect.width, lessThanOrEqualTo(460));
      game.disposeNotifiers();
    });
  });

  group('balance', () {
    for (var level = 1; level <= 10; level++) {
      testWithGame<CogClashGame>(
        'the auto builder wins level $level',
        _game(level),
        (game) async {
          _prepare(game);
          _autoBuild(game);
          _runFight(game);
          expect(game.result.value, isNotNull);
          expect(game.result.value!.won, isTrue);
          expect(game.result.value!.stars, inInclusiveRange(1, 3));
        },
      );
    }

    for (var level = 3; level <= 12; level++) {
      testWithGame<CogClashGame>(
        'a fight without gears loses level $level',
        _game(level),
        (game) async {
          _prepare(game);
          game.startFight();
          _runFight(game);
          expect(game.result.value?.won, isFalse);
          expect(game.result.value?.reason, 'Your fighter fell');
          expect(
            game.battle!.time,
            lessThanOrEqualTo(CogBattle.maxTime + CogBattle.step),
          );
        },
      );
    }

    test('the same level gives the same offers and fight', () {
      final a = CogShop(CogLevel.forLevel(7));
      final b = CogShop(CogLevel.forLevel(7));
      expect(a.offers, b.offers);
      final c = CogBattle(CogLevel.forLevel(7), [20]);
      final d = CogBattle(CogLevel.forLevel(7), [20]);
      // Big and small frame steps give the same fight.
      while (!c.isOver) {
        c.advance(0.25);
      }
      while (!d.isOver) {
        d.advance(1 / 144);
      }
      expect(c.won, d.won);
      expect(c.kills, d.kills);
      expect(c.fighterHp, closeTo(d.fighterHp, 1));
    });

    testWithGame<CogClashGame>(
      'a fight plays the start sound',
      _game(1, sounds: _sounds),
      (game) async {
        _prepare(game);
        _sounds.events.clear();
        game.startFight();
        expect(_sounds.events, ['whoosh']);
        expect(game.startFight(), isFalse);
        expect(game.selectOffer(0), isFalse);
      },
    );
  });

  testWithGame<CogClashGame>(
    'renders the build phase and the fight on phone and tablet sizes',
    _game(5),
    (game) async {
      void paint() {
        final recorder = PictureRecorder();
        game.render(Canvas(recorder));
        recorder.endRecording().dispose();
      }

      for (final size in [Vector2(411, 700), Vector2(1024, 1300)]) {
        game.onGameResize(size);
        paint();
      }
      _autoBuild(game);
      for (var i = 0; i < 60 * 3; i++) {
        game.update(1 / 60);
        if (i % 30 == 0) paint();
      }
      _runFight(game);
      paint();
      expect(game.result.value, isNotNull);
    },
  );
}

final _sounds = _FakeSounds();

TapDownEvent _tap(FlameGame game, Offset position) => TapDownEvent(
  1,
  game,
  TapDownDetails(
    globalPosition: position,
    localPosition: position,
    kind: PointerDeviceKind.touch,
  ),
);
