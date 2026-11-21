import 'dart:ui' show Canvas, PictureRecorder;

import 'package:lorem_arcade/arcade/arcade_level_game.dart';
import 'package:lorem_arcade/game/game_feedback.dart';
import 'package:lorem_arcade/games/bead_belt/bead_belt_game.dart';
import 'package:lorem_arcade/games/bead_belt/bead_belt_level.dart';
import 'package:lorem_arcade/games/bead_belt/bead_belt_model.dart';
import 'package:lorem_arcade/ui/app_theme.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
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
  void complete(int combo) => events.add('complete$combo');

  @override
  void win() => events.add('win');

  @override
  void fail() => events.add('fail');
}

ArcadeSetup _setup(int level, [GameSounds sounds = const SilentSounds()]) =>
    ArcadeSetup(
      level: level,
      style: const BlockStyle(palette: AppColors.blocks),
      sounds: sounds,
      haptics: false,
    );

void _prepare(BeadBeltGame game) => game.onGameResize(Vector2(411, 700));

/// Docks the front bucket whose color is most common on the belt while a
/// dock is free. With nothing matching it waits, unless no bucket is
/// docked yet or the belt is almost full.
void _autoPlay(BeadBeltGame game) {
  final model = game.model;
  while (model.hasFreeDock) {
    var best = -1;
    var bestCount = -1;
    for (var lane = 0; lane < model.lanes.length; lane++) {
      if (model.lanes[lane].isEmpty) continue;
      final count = model.beltCountOf(model.lanes[lane].first.color);
      if (count > bestCount) {
        best = lane;
        bestCount = count;
      }
    }
    if (best < 0) return;
    final idle = model.docks.every((d) => d == null);
    final crowded = model.beltCount >= model.beltCapacity * 0.9;
    if (bestCount == 0 && !idle && !crowded) return;
    expect(game.tapLane(best), isTrue);
  }
}

void main() {
  group('level generator', () {
    for (var n = 1; n <= 30; n++) {
      test('level $n is clearable and well sized', () {
        final level = BeadBeltLevel.generate(n);
        expect(level.colorCount, inInclusiveRange(2, 6));
        expect(level.dockCount, inInclusiveRange(3, 5));
        expect(level.lanes.length, inInclusiveRange(2, 4));
        expect(level.beltCapacity, greaterThan(0));
        final beads = <int, int>{};
        for (final color in level.reservoir) {
          beads[color] = (beads[color] ?? 0) + 1;
        }
        final room = <int, int>{};
        for (final lane in level.lanes) {
          expect(lane, isNotEmpty);
          for (final bucket in lane) {
            expect(bucket.capacity, inInclusiveRange(8, 20));
            expect(bucket.color, inInclusiveRange(0, level.colorCount - 1));
            room[bucket.color] = (room[bucket.color] ?? 0) + bucket.capacity;
          }
        }
        expect(beads, room);
        expect(room.length, level.colorCount);
      });
    }

    test('the same level number gives the same level', () {
      final a = BeadBeltLevel.generate(12);
      final b = BeadBeltLevel.generate(12);
      expect(a.reservoir, b.reservoir);
      expect(
        [for (final lane in a.lanes) lane.map((b) => b.color).toList()],
        [for (final lane in b.lanes) lane.map((b) => b.color).toList()],
      );
    });

    test('later levels are bigger', () {
      final first = BeadBeltLevel.generate(1);
      final later = BeadBeltLevel.generate(20);
      expect(first.colorCount, 2);
      expect(first.dockCount, 3);
      expect(later.colorCount, 6);
      expect(later.dockCount, 5);
      expect(later.bucketCount, greaterThan(first.bucketCount));
      expect(later.feedInterval, lessThan(first.feedInterval));
    });
  });

  group('simulation', () {
    for (var n = 1; n <= 10; n++) {
      testWithGame<BeadBeltGame>(
        'an automatic player wins level $n',
        () => BeadBeltGame(_setup(n)),
        (game) async {
          _prepare(game);
          for (var i = 0; i < 60 * 600 && game.result.value == null; i++) {
            _autoPlay(game);
            game.update(1 / 60);
            if (i % 600 == 0) game.render(Canvas(PictureRecorder()));
          }
          final result = game.result.value;
          expect(result, isNotNull, reason: game.status.value);
          expect(result!.won, isTrue, reason: result.reason);
          expect(result.stars, inInclusiveRange(1, 3));
          expect(game.hasProgress, isTrue);
          expect(game.model.reservoirCount, 0);
          expect(game.model.beltCount, 0);
        },
      );
    }
  });

  group('tap rules', () {
    testWithGame<BeadBeltGame>(
      'a tap with no free dock is rejected',
      () => BeadBeltGame(_setup(1, _FakeSounds())),
      (game) async {
        _prepare(game);
        final sounds = game.setup.sounds as _FakeSounds;
        expect(game.hasProgress, isFalse);
        expect(game.tapLane(0), isTrue);
        expect(game.hasProgress, isTrue);
        expect(game.tapLane(1), isTrue);
        expect(game.tapLane(0), isTrue);
        expect(game.model.hasFreeDock, isFalse);
        expect(game.model.lanes[1], isNotEmpty);
        expect(game.tapLane(1), isFalse);
        expect(sounds.events, ['tap', 'tap', 'tap', 'blocked']);
      },
    );

    testWithGame<BeadBeltGame>(
      'a tap on an empty lane is rejected',
      () => BeadBeltGame(_setup(1, _FakeSounds())),
      (game) async {
        _prepare(game);
        final sounds = game.setup.sounds as _FakeSounds;
        expect(game.tapLane(0), isTrue);
        expect(game.tapLane(0), isTrue);
        expect(game.model.lanes[0], isEmpty);
        expect(game.tapLane(0), isFalse);
        expect(sounds.events.last, 'blocked');
      },
    );

    testWithGame<BeadBeltGame>(
      'a full bucket leaves and frees its dock',
      () => BeadBeltGame(_setup(1, _FakeSounds())),
      (game) async {
        _prepare(game);
        final sounds = game.setup.sounds as _FakeSounds;
        game
          ..tapLane(0)
          ..tapLane(1)
          ..tapLane(0);
        expect(game.model.hasFreeDock, isFalse);
        for (var i = 0; i < 60 * 120 && game.model.filledBuckets == 0; i++) {
          game.update(1 / 60);
        }
        expect(game.model.filledBuckets, 1);
        expect(game.model.hasFreeDock, isTrue);
        expect(sounds.events, contains('complete1'));
        expect(game.status.value, contains('Buckets 1/4'));
        expect(game.tapLane(1), isTrue);
      },
    );

    testWithGame<BeadBeltGame>(
      'a jammed belt loses the level',
      () => BeadBeltGame(
        _setup(1),
        level: const BeadBeltLevel(
          number: 1,
          colorCount: 2,
          dockCount: 1,
          beltCapacity: 4,
          beltSpeed: 4,
          feedInterval: 0.1,
          lanes: [
            [BeadBucket(0, 4)],
            [BeadBucket(1, 4)],
          ],
          reservoir: [1, 1, 1, 1, 0, 0, 0, 0],
        ),
      ),
      (game) async {
        _prepare(game);
        expect(game.tapLane(0), isTrue);
        // Before the belt is full nothing is lost.
        game.update(0.2);
        expect(game.result.value, isNull);
        for (var i = 0; i < 60 * 30 && game.result.value == null; i++) {
          game.update(1 / 60);
        }
        expect(game.model.beltCount, 4);
        final result = game.result.value;
        expect(result, isNotNull);
        expect(result!.won, isFalse);
        expect(result.reason, 'The belt jammed');
      },
    );

    testWithGame<BeadBeltGame>(
      'a rejected tap marks its lane for a short shake',
      () => BeadBeltGame(_setup(1)),
      (game) async {
        _prepare(game);
        expect(game.rejectedLane, -1);
        game
          ..tapLane(0)
          ..tapLane(0);
        expect(game.tapLane(0), isFalse);
        expect(game.rejectedLane, 0);
        game.render(Canvas(PictureRecorder()));
        // Frames are capped at 0.1 s, so step through the shake.
        for (var i = 0; i < 30; i++) {
          game.update(1 / 60);
        }
        expect(game.rejectedLane, -1);
      },
    );

    test('stars follow the highest belt fill', () {
      final model = BeadBeltModel(BeadBeltLevel.generate(1));
      expect(model.stars, 3);
      model.maxFill = 0.75;
      expect(model.stars, 3);
      model.maxFill = 0.76;
      expect(model.stars, 2);
      model.maxFill = 0.99;
      expect(model.stars, 2);
      model.maxFill = 1;
      expect(model.stars, 1);
    });

    test('the preview shows the next reservoir beads in order', () {
      final level = BeadBeltLevel.generate(6);
      final model = BeadBeltModel(level);
      expect(model.upcoming(5), level.reservoir.take(5).toList());
      model.dockFront(0);
      while (model.reservoirCount == level.reservoir.length) {
        model.update(1 / 60);
      }
      final fed = level.reservoir.length - model.reservoirCount;
      expect(model.upcoming(5), level.reservoir.skip(fed).take(5).toList());
      expect(
        model.upcoming(level.reservoir.length + 10).length,
        model.reservoirCount,
      );
    });

    for (final shapes in [true, false]) {
      testWithGame<BeadBeltGame>(
        'renders a busy belt with shapes ${shapes ? 'on' : 'off'}',
        () => BeadBeltGame(
          ArcadeSetup(
            level: 12,
            style: BlockStyle(palette: AppColors.blocks, showShapes: shapes),
            haptics: false,
          ),
        ),
        (game) async {
          _prepare(game);
          for (var lane = 0; lane < game.model.lanes.length; lane++) {
            game.tapLane(lane);
          }
          for (var i = 0; i < 60 * 8; i++) {
            game.update(1 / 60);
          }
          expect(game.model.beltCount, greaterThan(0));
          final recorder = PictureRecorder();
          game.render(Canvas(recorder));
          recorder.endRecording().dispose();
        },
      );
    }

    testWithGame<BeadBeltGame>(
      'the belt does not feed before the first tap',
      () => BeadBeltGame(_setup(1)),
      (game) async {
        _prepare(game);
        for (var i = 0; i < 60 * 10; i++) {
          game.update(1 / 60);
        }
        expect(game.model.beltCount, 0);
        expect(game.result.value, isNull);
        expect(game.status.value, 'Belt 0/34 · Buckets 0/4');
      },
    );

    testWithGame<BeadBeltGame>(
      'lane tap areas are at least 48 px',
      () => BeadBeltGame(_setup(20)),
      (game) async {
        _prepare(game);
        for (var lane = 0; lane < game.model.lanes.length; lane++) {
          final rect = game.laneTapRect(lane);
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
        game.onGameResize(Vector2(1024, 700));
        expect(game.laneTapRect(0).left, greaterThan(200));
        game.render(Canvas(PictureRecorder()));
      },
    );
  });
}
