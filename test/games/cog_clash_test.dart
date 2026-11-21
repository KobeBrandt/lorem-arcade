import 'dart:ui' show Canvas, PictureRecorder;

import 'package:lorem_arcade/arcade/arcade_level_game.dart';
import 'package:lorem_arcade/game/game_feedback.dart';
import 'package:lorem_arcade/games/cog_clash/cog_battle.dart';
import 'package:lorem_arcade/games/cog_clash/cog_clash_game.dart';
import 'package:lorem_arcade/games/cog_clash/cog_model.dart';
import 'package:lorem_arcade/games/cog_clash/cog_painter.dart';
import 'package:lorem_arcade/ui/app_theme.dart';
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

ArcadeSetup _setup(int level, GameSounds? sounds) => ArcadeSetup(
  level: level,
  style: const BlockStyle(palette: AppColors.blocks),
  sounds: sounds ?? const SilentSounds(),
  haptics: false,
);

CogClashGame Function() _game(int level, {GameSounds? sounds}) =>
    () => CogClashGame(_setup(level, sounds));

CogClashGame Function() _endless() =>
    () => CogClashGame.endless(_setup(1, null));

/// Phone portrait area under the shell's top bar.
void _prepare(CogClashGame game) => game.onGameResize(Vector2(411, 700));

/// Buys the offer with the most power gained per coin and places it,
/// while that helps. Rerolls a few times when nothing helps.
void _buyWhatHelps(CogClashGame game, {int maxRerolls = 2}) {
  var rerolls = 0;
  while (true) {
    var best = 0.0;
    int? bestOffer;
    int? bestSocket;
    for (var i = 0; i < CogShop.offerCount; i++) {
      if (!game.shop.canAfford(i)) continue;
      final gear = game.shop.offers[i];
      for (var socket = 0; socket < game.board.socketCount; socket++) {
        if (!game.board.isEmpty(socket)) continue;
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
      if (game.shop.coins >= 4 && rerolls < maxRerolls) {
        game.reroll();
        rerolls++;
        continue;
      }
      return;
    }
    expect(game.selectOffer(bestOffer), isTrue);
    expect(game.tapSocket(bestSocket!), isTrue);
  }
}

/// Plays the run live: buys what helps every half second, until the
/// run ends or [seconds] pass.
void _autoPlay(CogClashGame game, {double seconds = 400}) {
  for (var i = 0; i < 60 * seconds && game.result.value == null; i++) {
    if (i % 30 == 0) _buyWhatHelps(game);
    game.update(1 / 60);
  }
}

/// Runs the game without any input until it ends.
void _idle(CogClashGame game, {double seconds = 400}) {
  for (var i = 0; i < 60 * seconds && game.result.value == null; i++) {
    game.update(1 / 60);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('power', () {
    CogBoard board() => CogBoard(weapons: const [5]);

    test('sums a chain of number gears linked to the weapon', () {
      final b = board()
        ..place(6, const Gear.number(3))
        ..place(7, const Gear.number(4));
      expect(b.powerOf(5), 7);
    });

    test('gears without a link to the weapon add nothing', () {
      final b = board()
        ..place(6, const Gear.number(3))
        ..place(18, const Gear.number(5));
      expect(b.powerOf(5), 3);
    });

    test('multipliers in the chain multiply the sum', () {
      final b = board()
        ..place(6, const Gear.number(3))
        ..place(7, const Gear.multiplier(2));
      expect(b.powerOf(5), 6);
    });

    test('a multiplier alone gives no power', () {
      final b = board()..place(6, const Gear.multiplier(3));
      expect(b.powerOf(5), 0);
    });

    test('a chain can feed two weapons', () {
      final b = CogBoard(weapons: const [5, 9])
        ..place(6, const Gear.number(1))
        ..place(7, const Gear.number(2))
        ..place(8, const Gear.number(4));
      expect(b.powers, [7, 7]);
      expect(b.totalPower, 14);
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

    test('a merged gear keeps merging with an equal neighbor', () {
      // 2 at 7 and 4 at 12 (under 7). A 2 placed at 8 merges into 7 as a
      // 4, which then merges into 12 as an 8.
      final b = board()
        ..place(7, const Gear.number(2))
        ..place(12, const Gear.number(4));
      final placement = b.place(8, const Gear.number(2))!;
      expect(placement.merged, isTrue);
      expect(placement.socket, 12);
      expect(b.gearAt(12), const Gear.number(8));
      expect(b.isEmpty(7), isTrue);
      expect(b.isEmpty(8), isTrue);
    });

    test('multipliers never merge', () {
      final b = board()..place(6, const Gear.multiplier(2));
      final placement = b.place(7, const Gear.multiplier(2))!;
      expect(placement.merged, isFalse);
      expect(b.gearAt(6), const Gear.multiplier(2));
      expect(b.gearAt(7), const Gear.multiplier(2));
    });

    test('a removed gear leaves an empty socket; weapons stay', () {
      final b = board()..place(6, const Gear.number(3));
      expect(b.remove(6), const Gear.number(3));
      expect(b.isEmpty(6), isTrue);
      expect(b.remove(6), isNull);
      expect(b.remove(5), isNull);
      expect(b.isWeapon(5), isTrue);
    });

    test('sell price is half the price, rounded down', () {
      expect(const Gear.number(5).sellPrice, 2);
      expect(const Gear.number(16).sellPrice, 8);
      expect(const Gear.multiplier(2).sellPrice, 3);
      expect(const Gear.multiplier(3).sellPrice, 5);
    });

    test('stars follow the fighter HP left', () {
      expect(starsForHp(100, 100), 3);
      expect(starsForHp(67, 100), 3);
      expect(starsForHp(60, 100), 2);
      expect(starsForHp(30, 100), 1);
    });
  });

  group('levels', () {
    test('wave counts grow with the level', () {
      expect(CogLevel.forLevel(1).waveCount, 2);
      expect(CogLevel.forLevel(3).waveCount, 2);
      expect(CogLevel.forLevel(4).waveCount, 3);
      expect(CogLevel.forLevel(9).waveCount, 3);
      expect(CogLevel.forLevel(10).waveCount, 4);
      expect(CogLevel.forLevel(30).waveCount, 4);
    });

    test('later waves are stronger', () {
      final config = CogLevel.forLevel(6);
      for (var k = 1; k < config.waveCount!; k++) {
        expect(config.wave(k).hp, greaterThan(config.wave(k - 1).hp));
      }
      final endless = CogLevel.endless();
      expect(endless.isEndless, isTrue);
      expect(endless.wave(30).hp, greaterThan(endless.wave(10).hp));
      expect(
        endless.wave(30).enemyCount,
        greaterThan(endless.wave(0).enemyCount),
      );
    });
  });

  group('battle', () {
    test('the first wave waits for the countdown', () {
      final battle = CogBattle(CogLevel.forLevel(1), [5]);
      expect(battle.isWaiting, isTrue);
      expect(battle.hasStarted, isFalse);
      final start = List.of(battle.enemyX);
      battle.advance(CogBattle.countdown - 0.1);
      expect(battle.enemyX, start);
      expect(battle.shots, isEmpty);
      battle.advance(0.5);
      expect(battle.isWaiting, isFalse);
      expect(battle.hasStarted, isTrue);
      expect(battle.enemyX.first, lessThan(start.first));
    });

    test('new powers take effect at once', () {
      final battle = CogBattle(CogLevel.forLevel(1), [0]);
      battle.advance(CogBattle.countdown + 4);
      expect(battle.shots, isEmpty);
      battle.setPowers([3]);
      battle.advance(1);
      expect(battle.shots.isNotEmpty || battle.waveHp < battle.wave.hp, isTrue);
    });

    test('a strong fight clears every wave with 3 stars and pays coins', () {
      final config = CogLevel.forLevel(5);
      final battle = CogBattle(config, [500, 500]);
      var hits = 0;
      var kills = 0;
      battle.onHit = (_, _) => hits++;
      battle.onKill = (_, _) => kills++;
      while (!battle.isOver) {
        battle.advance(0.5);
      }
      expect(battle.won, isTrue);
      expect(battle.stars, 3);
      expect(battle.wavesCleared, config.waveCount);
      final enemies = [
        for (var k = 0; k < config.waveCount!; k++) config.wave(k).enemyCount,
      ].reduce((a, b) => a + b);
      expect(battle.kills, enemies);
      expect(kills, enemies);
      expect(hits, greaterThan(0));
      expect(battle.coinsEarned, greaterThanOrEqualTo(enemies));
    });

    for (var level = 1; level <= 12; level++) {
      test('a fight without power loses level $level', () {
        final config = CogLevel.forLevel(level);
        final battle = CogBattle(config, [for (final _ in config.weapons) 0]);
        while (!battle.isOver) {
          battle.advance(0.5);
        }
        expect(battle.won, isFalse);
        expect(battle.fighterHp, 0);
        expect(battle.wavesCleared, 0);
      });
    }

    test('the endless run only ends when the fighter falls', () {
      final battle = CogBattle(CogLevel.endless(), [60, 60]);
      while (!battle.isOver) {
        battle.advance(0.5);
      }
      expect(battle.won, isFalse);
      expect(battle.wavesCleared, greaterThan(0));
    });

    test('big and small frame steps give the same fight', () {
      final c = CogBattle(CogLevel.forLevel(7), [20, 20]);
      final d = CogBattle(CogLevel.forLevel(7), [20, 20]);
      while (!c.isOver) {
        c.advance(0.25);
      }
      while (!d.isOver) {
        d.advance(1 / 144);
      }
      expect(c.won, d.won);
      expect(c.kills, d.kills);
      expect(c.wavesCleared, d.wavesCleared);
      expect(c.fighterHp, closeTo(d.fighterHp, 1));
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

    testWithGame<CogClashGame>(
      'a tap on a placed gear without a picked offer sells it',
      _game(2, sounds: _sounds),
      (g) async {
        _prepare(g);
        expect(g.selectOffer(0), isTrue);
        expect(g.tapSocket(6), isTrue);
        final gear = g.board.gearAt(6)!;
        final coins = g.shop.coins;
        _sounds.events.clear();
        expect(g.tapSocket(6), isTrue);
        expect(g.board.isEmpty(6), isTrue);
        expect(g.shop.coins, coins + gear.sellPrice);
        expect(g.battle.powers, [0]);
        expect(_sounds.events, ['whoosh']);
        expect(g.tapSocket(5), isFalse, reason: 'weapons cannot be sold');
        expect(g.tapSocket(6), isFalse, reason: 'nothing left to sell');
      },
    );

    testWithGame<CogClashGame>(
      'a picked offer previews the power gain per socket',
      _game(1),
      (game) async {
        _prepare(game);
        final hint = game.config.hintSocket!;
        expect(game.previewGain(hint), 0);
        expect(game.selectOffer(0), isTrue);
        final gear = game.shop.offers[0];
        expect(game.previewGain(hint), gear.value);
        // Far from the weapon nothing links up.
        expect(game.previewGain(19), 0);
        expect(game.tapSocket(hint), isTrue);
        expect(game.previewGain(hint + 1), 0, reason: 'cleared after a buy');
      },
    );

    testWithGame<CogClashGame>('reroll costs one coin', _game(3), (game) async {
      _prepare(game);
      final coins = game.shop.coins;
      expect(game.reroll(), isTrue);
      expect(game.shop.coins, coins - 1);
    });

    testWithGame<CogClashGame>(
      'tap on an offer then on a socket places the gear and powers up',
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
        expect(game.battle.powers.first, game.board.totalPower);
      },
    );

    test('tap targets are at least 48 px and the arena fits', () {
      final game = _game(4)();
      for (final size in [Vector2(360, 600), Vector2(411, 700)]) {
        game.onGameResize(size);
        expect(game.socketRect(0).width, greaterThanOrEqualTo(48));
        expect(game.offerRect(0).height, greaterThanOrEqualTo(48));
        expect(game.rerollRect.width, greaterThanOrEqualTo(48));
        expect(game.rerollRect.bottom, lessThanOrEqualTo(size.y));
        expect(game.arenaRect.height, greaterThanOrEqualTo(120));
        expect(game.arenaRect.bottom, lessThan(game.socketRect(0).top));
      }
      game.onGameResize(Vector2(1024, 1300));
      expect(game.arenaRect.width, lessThanOrEqualTo(460));
      game.disposeNotifiers();
    });
  });

  group('live run', () {
    testWithGame<CogClashGame>(
      'the wave walks after the countdown and gears can still be placed',
      _game(1, sounds: _sounds),
      (game) async {
        _prepare(game);
        _sounds.events.clear();
        expect(game.hasProgress, isFalse);
        for (var i = 0; i < 60 * (CogBattle.countdown + 0.5); i++) {
          game.update(1 / 60);
        }
        expect(game.battle.isWaiting, isFalse);
        expect(game.hasProgress, isTrue);
        expect(_sounds.events, contains('whoosh'));
        expect(game.selectOffer(0), isTrue);
        expect(game.tapSocket(game.config.hintSocket!), isTrue);
        expect(game.battle.powers.first, greaterThan(0));
      },
    );

    testWithGame<CogClashGame>(
      'defeated enemies pay coins into the shop',
      _game(2),
      (game) async {
        _prepare(game);
        _buyWhatHelps(game);
        final coins = game.shop.coins;
        for (var i = 0; i < 60 * 60 && game.battle.kills == 0; i++) {
          game.update(1 / 60);
        }
        expect(game.battle.kills, greaterThan(0));
        expect(game.shop.coins, greaterThan(coins));
        expect(game.killBursts, game.battle.kills);
      },
    );

    for (var level = 1; level <= 10; level++) {
      testWithGame<CogClashGame>(
        'the auto player wins level $level',
        _game(level),
        (game) async {
          _prepare(game);
          _autoPlay(game);
          final result = game.result.value;
          expect(result, isNotNull);
          expect(result!.won, isTrue, reason: game.status.value);
          expect(result.stars, inInclusiveRange(1, 3));
          expect(game.killBursts, game.battle.kills);
        },
      );
    }

    for (final level in [1, 5, 10]) {
      testWithGame<CogClashGame>(
        'doing nothing loses level $level',
        _game(level),
        (game) async {
          _prepare(game);
          _idle(game);
          expect(game.result.value?.won, isFalse);
          expect(game.result.value?.reason, 'Your fighter fell');
        },
      );
    }

    testWithGame<CogClashGame>(
      'the endless run ends with the waves cleared as score',
      _endless(),
      (game) async {
        _prepare(game);
        expect(game.isEndless, isTrue);
        _autoPlay(game, seconds: 1200);
        final result = game.result.value;
        expect(result, isNotNull, reason: game.status.value);
        expect(result!.won, isFalse);
        expect(result.score, game.battle.wavesCleared);
        expect(result.score, greaterThanOrEqualTo(3));
        expect(result.reason, 'Your fighter fell');
      },
    );

    testWithGame<CogClashGame>(
      'the endless run without gears scores 0',
      _endless(),
      (game) async {
        _prepare(game);
        _idle(game);
        expect(game.result.value?.score, 0);
      },
    );
  });

  test('the text cache does not grow without limit', () {
    final cache = TextCache();
    for (var i = 0; i < 1000; i++) {
      cache.get('Wave HP $i', size: 15, color: AppColors.text);
    }
    expect(cache.length, lessThanOrEqualTo(TextCache.maxEntries));
  });

  testWithGame<CogClashGame>(
    'renders the countdown and the fight on phone and tablet sizes',
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
      for (var i = 0; i < 60 * 12; i++) {
        if (i % 30 == 0) _buyWhatHelps(game);
        game.update(1 / 60);
        if (i % 30 == 0) paint();
      }
      _autoPlay(game);
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
