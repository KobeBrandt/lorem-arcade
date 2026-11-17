import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:color_flow/game/board.dart';
import 'package:color_flow/game/color_flow_game.dart';
import 'package:color_flow/game/game_feedback.dart';
import 'package:color_flow/game/game_mode.dart';
import 'package:color_flow/game/level_config.dart';
import 'package:color_flow/game/level_generator.dart';
import 'package:flame/events.dart' show TapDownEvent;
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Level 1 sizes: tube size 4, loop capacity 3, 5 tubes.
Board _board() => Board(
  tubes: [
    [1, 0, 0],
    [2, 2, 1, 2],
    [1, 2],
    <int>[],
    <int>[],
  ],
  tubeSize: 4,
);

LevelSource _source(
  Board board, {
  List<int> loop = const [],
  int solution = 3,
}) =>
    (_, _) async => Puzzle(board: board, loop: loop, solutionLength: solution);

ColorFlowGame _game({
  GameMode mode = GameMode.levels,
  int solution = 3,
  GameSounds sounds = const SilentSounds(),
}) => ColorFlowGame(
  mode: mode,
  levelSource: _source(_board(), solution: solution),
  haptics: false,
  sounds: sounds,
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
  void complete(int combo) => events.add('complete $combo');

  @override
  void win() => events.add('win');

  @override
  void fail() => events.add('fail');
}

void _runUntilSettled(ColorFlowGame game) {
  for (var i = 0; i < 60 * 30 && !game.isSettled; i++) {
    game.update(1 / 60);
  }
}

/// Phone-sized screen, plus the result overlays the app registers.
/// With [slide], waits until the tubes have slid in and taps work.
void _prepare(ColorFlowGame game, {bool slide = true}) {
  game.onGameResize(Vector2(411, 891));
  for (final name in ['stuck', 'failed', 'won', 'loading']) {
    game.overlays.addEntry(name, (_, _) => const SizedBox());
  }
  if (slide) _finishSlide(game);
}

void _finishSlide(ColorFlowGame game) {
  for (var i = 0; i < 120 && game.isSliding; i++) {
    game.update(1 / 60);
  }
}

void _run(ColorFlowGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.update(1 / 60);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWithGame<ColorFlowGame>('blocks land where the solver expects', _game, (
    game,
  ) async {
    _prepare(game);
    for (final tube in [0, 2, 1]) {
      final expected = applyCleanMove(game.board, tube, 3)!;
      game.tapTube(tube);
      _runUntilSettled(game);
      expect(game.isSettled, isTrue);
      expect(game.board.tubes, expected.tubes, reason: 'tap on tube $tube');
    }
  });

  testWithGame<ColorFlowGame>(
    'block skips an empty tube for a better matching tube',
    () => ColorFlowGame(
      levelSource: _source(
        Board(
          tubes: [
            [1, 0],
            [1, 1, 2],
            [2, 0],
            <int>[],
            <int>[],
          ],
          tubeSize: 4,
        ),
      ),
      haptics: false,
    ),
    (game) async {
      _prepare(game);
      // From tube 0 the block passes empty tubes 4 and 3 first,
      // but tube 2 has a matching top, so it must land there.
      game.tapTube(0);
      _runUntilSettled(game);
      expect(game.board.tubes[2], [2, 0, 0]);
      expect(game.board.tubes[3], isEmpty);
      expect(game.board.tubes[4], isEmpty);
    },
  );

  testWithGame<ColorFlowGame>(
    'tap that does not fit in the loop changes nothing',
    _game,
    (game) async {
      _prepare(game);
      game.tapTube(0); // 2 blocks into the loop
      game.tapTube(2); // 1 more: loop is full (3/3)
      final before = game.board.key();
      final blockedBefore = game.hud.value.blockedTaps;

      game.tapTube(1); // does not fit
      expect(game.board.key(), before);
      expect(game.hud.value.blockedTaps, blockedBefore + 1);
      expect(game.status, GameStatus.playing);
    },
  );

  testWithGame<ColorFlowGame>('retry puts the same board back', _game, (
    game,
  ) async {
    _prepare(game);
    final start = game.board.key();
    game.tapTube(0);
    _runUntilSettled(game);
    expect(game.board.key(), isNot(start));
    expect(game.taps, 1);
    game.retryLevel();
    expect(game.board.key(), start);
    expect(game.isSettled, isTrue);
    expect(game.taps, 0);
    // The tubes slide in again.
    expect(game.isSliding, isTrue);
  });

  testWithGame<ColorFlowGame>(
    'a tap during the slide-in is queued until the slide ends',
    _game,
    (game) async {
      _prepare(game, slide: false);
      expect(game.isSliding, isTrue);
      final start = game.board.key();
      final expected = applyCleanMove(game.board, 0, 3)!;
      // Only the last tap is kept.
      game.tapTube(1);
      game.tapTube(0);
      expect(game.board.key(), start);
      expect(game.taps, 0);
      _run(game, 0.3);
      expect(game.isSliding, isTrue);
      expect(game.taps, 0);
      _finishSlide(game);
      game.update(1 / 60);
      expect(game.taps, 1);
      _runUntilSettled(game);
      expect(game.board.key(), expected.key());
    },
  );

  final failSounds = _FakeSounds();
  testWithGame<ColorFlowGame>(
    'move limit fails the level when taps run out',
    // Solution of 1 tap: the limit is 2 taps.
    () => _game(mode: GameMode.moves, solution: 1, sounds: failSounds),
    (game) async {
      _prepare(game);
      addTearDown(() => expect(failSounds.events.last, 'fail'));
      expect(game.hud.value.movesLeft, 2);
      game.tapTube(0);
      _runUntilSettled(game);
      game.tapTube(2);
      _runUntilSettled(game);
      expect(game.hud.value.movesLeft, 0);
      game.update(1 / 60);
      expect(game.status, GameStatus.failed);
      expect(game.failReason, 'Out of moves');
      game.retryLevel();
      expect(game.status, GameStatus.playing);
      expect(game.hud.value.movesLeft, 2);
    },
  );

  testWithGame<ColorFlowGame>(
    'timed mode fails when the clock runs out',
    () => _game(mode: GameMode.timed),
    (game) async {
      _prepare(game);
      expect(game.hud.value.secondsLeft, 72); // 12 blocks x 6 s
      _run(game, 71);
      expect(game.status, GameStatus.playing);
      _run(game, 2);
      expect(game.status, GameStatus.failed);
      expect(game.failReason, 'Time is up');
    },
  );

  testWithGame<ColorFlowGame>(
    'endless scores a point per sorted tube',
    () => ColorFlowGame(
      mode: GameMode.endless,
      levelSource: _source(
        Board(
          tubes: [
            [1, 0],
            [0, 0, 0],
            [1, 1, 1],
            <int>[],
            <int>[],
          ],
          tubeSize: 4,
        ),
      ),
      haptics: false,
    ),
    (game) async {
      _prepare(game);
      expect(game.hud.value.score, 0);
      game.tapTube(0);
      _runUntilSettled(game);
      expect(game.hud.value.score, 1);
    },
  );

  testWithGame<ColorFlowGame>(
    'belt-full start: loop blocks land and the level can be won',
    () => ColorFlowGame(
      mode: GameMode.beltFull,
      levelSource: _source(
        Board(
          tubes: [
            [0, 0, 0],
            [1, 1, 1],
            <int>[],
          ],
          tubeSize: 4,
        ),
        loop: [0, 1],
      ),
      haptics: false,
    ),
    (game) async {
      // Loop blocks are there right away, while the tubes slide in.
      _prepare(game, slide: false);
      expect(game.hud.value.loopCount, 2);
      _runUntilSettled(game);
      game.update(1 / 60);
      expect(game.board.tubes[0], [0, 0, 0, 0]);
      expect(game.board.tubes[1], [1, 1, 1, 1]);
      expect(game.status, GameStatus.won);
    },
  );

  for (final level in [1, 10, 20, 22, 32]) {
    final config = LevelConfig.forLevel(level, beltFull: true);
    final puzzle = LevelGenerator(random: Random(level)).generate(config);
    final path = LoopSolver(
      config.loopCapacity,
      60000,
    ).solve(puzzle.board, puzzle.loop)!;

    testWithGame<ColorFlowGame>(
      'belt-full level $level: solver taps win in the game',
      () => ColorFlowGame(
        mode: GameMode.beltFull,
        initialLevel: level,
        levelSource: (_, _) async => puzzle,
        haptics: false,
      ),
      (game) async {
        _prepare(game);
        _run(game, 15);
        for (final tube in path) {
          game.tapTube(tube);
          _run(game, 15);
        }
        expect(game.status, GameStatus.won);
      },
    );
  }

  // Levels with hidden (12+), locked (22+) and rainbow (32+) blocks.
  for (final level in [12, 22, 32, 42]) {
    final config = LevelConfig.forLevel(level);
    // At 32+ use the first seed that gives a rainbow.
    late Puzzle puzzle;
    for (var seed = 1; seed < 20; seed++) {
      puzzle = LevelGenerator(random: Random(seed)).generate(config);
      final rainbow = puzzle.board.tubes.any((t) => t.contains(Board.rainbow));
      if (!config.mayHaveRainbow || rainbow) break;
    }
    final path = Solver(config.loopCapacity, 60000).solve(puzzle.board)!;

    testWithGame<ColorFlowGame>(
      'level $level with special blocks: solver taps win in the game',
      () => ColorFlowGame(
        initialLevel: level,
        levelSource: (_, _) async => puzzle,
        haptics: false,
      ),
      (game) async {
        _prepare(game);
        // Draws hidden, locked and rainbow blocks without errors.
        game.render(Canvas(PictureRecorder()));
        var expected = game.board.copy();
        for (final tube in path) {
          expected = applyCleanMove(expected, tube, config.loopCapacity)!;
          game.tapTube(tube);
          _runUntilSettled(game);
          expect(game.board.key(), expected.key(), reason: 'tap on $tube');
          expect(game.board.hidden, expected.hidden, reason: 'tap on $tube');
        }
        game.update(1 / 60);
        expect(game.status, GameStatus.won);
        expect(game.board.lockedCount, 0);
      },
    );
  }

  final lockSounds = _FakeSounds();
  testWithGame<ColorFlowGame>(
    'a locked top is rejected and a completion opens the leftmost lock',
    () => ColorFlowGame(
      levelSource: _source(
        Board(
          tubes: [
            [0, 0, 0],
            [1, 2],
            [1, 1, 0],
            [2, 1],
            <int>[],
          ],
          tubeSize: 4,
          locked: [
            <int>{},
            {1},
            {0, 1},
            {0},
            <int>{},
          ],
        ),
      ),
      haptics: false,
      sounds: lockSounds,
    ),
    (game) async {
      _prepare(game);
      lockSounds.events.clear();
      final start = game.board.key();
      game.tapTube(1); // locked top
      expect(game.board.key(), start);
      expect(game.taps, 0);
      expect(lockSounds.events, ['blocked']);

      game.tapTube(2); // the 0 above the locks completes tube 0
      _runUntilSettled(game);
      expect(game.board.isComplete(0), isTrue);
      // One lock opens: tube 1 is the leftmost with a lock.
      expect(game.board.locked, [
        <int>{},
        <int>{},
        {0, 1},
        {0},
        <int>{},
      ]);
      expect(game.board.topRunLength(1), 1);
    },
  );

  final comboSounds = _FakeSounds();
  final results = <LevelResult>[];
  testWithGame<ColorFlowGame>(
    'combo, sounds and level result',
    () => ColorFlowGame(
      levelSource: _source(
        Board(
          tubes: [
            [0, 0, 0],
            [0, 0, 0],
            [1, 0, 0],
            [1, 1, 1],
            <int>[],
          ],
          tubeSize: 4,
        ),
        solution: 2,
      ),
      haptics: false,
      sounds: comboSounds,
      onWon: results.add,
    ),
    (game) async {
      _prepare(game);
      expect(game.combo, 0);
      // Two 0s complete tubes 1 and 0 within the combo window.
      game.tapTube(2);
      _runUntilSettled(game);
      expect(game.combo, 2);
      // A complete tube cannot be tapped (run of 4 > loop capacity).
      game.tapTube(0);
      _run(game, 3);
      // The next completion comes too late for the combo.
      game.tapTube(2);
      _runUntilSettled(game);
      expect(game.combo, 1);
      game.update(1 / 60);
      expect(game.status, GameStatus.won);
      expect(comboSounds.events, [
        'tap',
        'whoosh',
        'complete 1',
        'complete 2',
        'blocked',
        'tap',
        'whoosh',
        'complete 1',
        'win',
      ]);
      expect(results, hasLength(1));
      final result = results.single;
      expect(result.taps, 2);
      expect(result.solutionLength, 2);
      expect(result.stars, 3);
      expect(result.seconds, greaterThan(3.5));
      expect(result.seconds, lessThan(15));
    },
  );

  testWithGame<ColorFlowGame>(
    'a failed level build shows the fail overlay and retry builds again',
    () {
      var calls = 0;
      final game = ColorFlowGame(
        levelSource: (_, _) async {
          if (calls++ == 0) throw StateError('no level');
          return Puzzle(board: _board(), solutionLength: 3);
        },
        haptics: false,
      );
      // The build fails during load, so the overlay must exist first.
      game.overlays.addEntry('failed', (_, _) => const SizedBox());
      return game;
    },
    (game) async {
      _prepare(game);
      expect(game.status, GameStatus.failed);
      game.retryLevel();
      await Future<void>.delayed(Duration.zero);
      expect(game.status, GameStatus.playing);
      expect(game.board.key(), _board().key());
    },
  );

  group('Rush', () {
    /// Every tube full and mixed: nothing can land and nothing completes.
    Board fullBoard() => Board(
      tubes: [
        [0, 1, 0, 1],
        [1, 0, 1, 0],
        [0, 2, 0, 2],
        [2, 0, 2, 0],
        [1, 2, 1, 2],
      ],
      tubeSize: 4,
    );

    /// Tube 0 needs one more 1; a tap on tube 1 sends that 1.
    Board clearBoard() => Board(
      tubes: [
        [1, 1, 1],
        [1],
        [0, 2],
        [2, 0],
        <int>[],
      ],
      tubeSize: 4,
    );

    ColorFlowGame rush(
      Board board, {
      ValueChanged<int>? onScore,
      GameSounds sounds = const SilentSounds(),
    }) => ColorFlowGame(
      mode: GameMode.rush,
      levelSource: _source(board, solution: 0),
      haptics: false,
      onScore: onScore,
      sounds: sounds,
    );

    void runUntil(ColorFlowGame game, bool Function() done) {
      for (var i = 0; i < 60 * 30 && !done(); i++) {
        game.update(1 / 60);
      }
      expect(done(), isTrue, reason: 'condition not reached in 30 s');
    }

    test('config grows after 10 and 25 clears; spawns speed up', () {
      expect(GameMode.rush.hasLevels, isFalse);
      final start = LevelConfig.rush(0);
      expect(
        [start.colorCount, start.tubeCount, start.tubeSize, start.loopCapacity],
        [3, 5, 4, 6],
      );
      expect(LevelConfig.rush(9).tubeCount, 5);
      expect(LevelConfig.rush(10).colorCount, 4);
      expect(LevelConfig.rush(10).tubeCount, 6);
      expect(LevelConfig.rush(24).tubeCount, 6);
      expect(LevelConfig.rush(25).colorCount, 5);
      expect(LevelConfig.rush(25).tubeCount, 7);
      expect(rushSpawnInterval(0), 3);
      expect(rushSpawnInterval(1), closeTo(2.85, 1e-9));
      expect(rushSpawnInterval(2), closeTo(2.7075, 1e-9));
      expect(rushSpawnInterval(100), 1);
    });

    testWithGame<ColorFlowGame>(
      'starts with 2 random blocks per tube and an empty belt',
      () => ColorFlowGame(mode: GameMode.rush, haptics: false),
      (game) async {
        _prepare(game, slide: false);
        expect(game.status, GameStatus.playing);
        expect(game.board.tubeCount, 5);
        expect(game.board.tubeSize, 4);
        for (var i = 0; i < 5; i++) {
          expect(game.board.tubes[i], hasLength(2));
          expect(game.board.tubes[i].every((c) => c >= 0 && c < 3), isTrue);
          expect(game.board.isComplete(i), isFalse);
        }
        expect(game.hud.value.loopCount, 0);
        expect(game.hud.value.loopCapacity, 6);
        expect(game.hud.value.score, 0);
      },
    );

    testWithGame<ColorFlowGame>(
      'a block spawns every 3 s, faster after clears',
      () => rush(fullBoard()),
      (game) async {
        _prepare(game, slide: false);
        _run(game, 2.9);
        expect(game.hud.value.loopCount, 0);
        _run(game, 0.2);
        expect(game.hud.value.loopCount, 1);
        _run(game, 2.7);
        expect(game.hud.value.loopCount, 1);
        _run(game, 0.2);
        expect(game.hud.value.loopCount, 2);
        // 10 clears: 3 s x 0.95^10, about 1.8 s. The score does not count.
        game.score = 50;
        expect(game.spawnInterval, 3);
        game.clears = 10;
        expect(game.spawnInterval, closeTo(1.796, 0.001));
        _run(game, 1.85);
        // From 5 clears a spawn may be a group of 2.
        expect(game.hud.value.loopCount, inInclusiveRange(3, 4));
      },
    );

    final clearScores = <int>[];
    final clearSounds = _FakeSounds();
    testWithGame<ColorFlowGame>(
      'a full tube bursts, scores a point and empties',
      () => rush(clearBoard(), onScore: clearScores.add, sounds: clearSounds),
      (game) async {
        _prepare(game);
        game.tapTube(1);
        runUntil(game, () => game.board.isComplete(0));
        expect(game.hud.value.score, 1);
        expect(clearScores, [1]);
        expect(clearSounds.events, contains('complete 1'));
        // A bursting tube cannot be tapped.
        game.tapTube(0);
        expect(game.board.tubes[0], [1, 1, 1, 1]);
        expect(game.taps, 1);
        runUntil(game, () => game.board.tubes[0].isEmpty);
        expect(game.hud.value.score, 1);
        expect(game.status, GameStatus.playing);
        expect(game.spawnInterval, closeTo(2.85, 1e-9));
      },
    );

    testWithGame<ColorFlowGame>(
      'waiting blocks are planned again after a tube empties',
      () => rush(
        Board(
          tubes: [
            [1, 1, 1],
            [0, 1],
            [2, 0, 2, 0],
            [0, 2, 0, 2],
            [0, 2],
          ],
          tubeSize: 4,
        ),
      ),
      (game) async {
        _prepare(game);
        // No tube takes a 2: it waits on the loop.
        game.tapTube(4);
        // The 1 completes tube 0 and it empties before the first spawn.
        game.tapTube(1);
        runUntil(game, () => game.board.isComplete(0));
        expect(game.hud.value.loopCount, greaterThanOrEqualTo(1));
        runUntil(game, () => game.board.tubes[0].isEmpty);
        expect(game.hud.value.loopCount, 1);
        // The waiting 2 now lands in the empty tube.
        runUntil(game, () => game.board.tubes[0].isNotEmpty);
        expect(game.board.tubes[0].first, 2);
      },
    );

    testWithGame<ColorFlowGame>(
      'after 10 clears a new color and an empty tube join',
      () => rush(clearBoard()),
      (game) async {
        _prepare(game);
        game.clears = 9;
        game.tapTube(1);
        runUntil(game, () => game.board.tubeCount == 6);
        expect(game.clears, 10);
        expect(game.score, 1);
        expect(game.config.colorCount, 4);
        expect(game.board.tubes[5], isEmpty);
        expect(game.board.tubes[0], isEmpty);
        // The new tube is drawn and can take blocks.
        game.render(Canvas(PictureRecorder()));
        expect(game.reservations.accepts(game.board, 5, 3), isTrue);
        game.autoSpawn = false;
        game.spawnBlock(3);
        runUntil(game, () => game.isSettled);
        // The new tube is the first one the spawn passes.
        expect(game.board.tubes[5], [3]);
      },
    );

    testWithGame<ColorFlowGame>(
      'a full belt that goes a lap without landing ends the run',
      () => rush(fullBoard()),
      (game) async {
        _prepare(game, slide: false);
        // 6 spawns (3 s apart) fill the belt; nothing can land.
        _run(game, 18.2);
        expect(game.hud.value.loopCount, 6);
        expect(game.status, GameStatus.playing);
        // Full belt: no tap fits.
        game.tapTube(0);
        expect(game.taps, 0);
        runUntil(game, () => game.status == GameStatus.failed);
        expect(game.failReason, 'Belt overflow');
        expect(game.hud.value.loopCount, 6);

        // Retry starts a fresh run.
        game.score = 3;
        game.restartPressed();
        await Future<void>.delayed(Duration.zero);
        expect(game.status, GameStatus.playing);
        expect(game.score, 0);
        expect(game.hud.value.loopCount, 0);
      },
    );

    testWithGame<ColorFlowGame>(
      'a spawn drops into the first tube with room, whatever its color',
      () => rush(
        Board(
          tubes: [
            [0, 0],
            [1],
            [2, 2],
            [1, 1],
            [2, 0, 1],
          ],
          tubeSize: 4,
        ),
      ),
      (game) async {
        _prepare(game);
        game.autoSpawn = false;
        // From the top center the belt passes tube 4 first: its top is 1.
        game.spawnBlock(0);
        _runUntilSettled(game);
        expect(game.board.tubes[4], [2, 0, 1, 0]);
        // Tube 4 is full: the next one goes on to tube 3.
        game.spawnBlock(2);
        _runUntilSettled(game);
        expect(game.board.tubes[3], [1, 1, 2]);
        // A group rides in a row; each block drops like any spawn.
        game.spawnGroup(const [RushSpawn(0), RushSpawn(1)]);
        expect(game.hud.value.loopCount, 2);
        _runUntilSettled(game);
        expect(game.board.tubes[3], [1, 1, 2, 0]);
        expect(game.board.tubes[2], [2, 2, 1]);
        expect(game.board.tubes[0], [0, 0]);
        expect(game.board.tubes[1], [1]);
      },
    );

    testWithGame<ColorFlowGame>(
      'tapped blocks still drop into the best tube',
      () => rush(
        Board(
          tubes: [
            [1, 0],
            [1, 1, 2],
            [2, 0],
            <int>[],
            <int>[],
          ],
          tubeSize: 4,
        ),
      ),
      (game) async {
        _prepare(game);
        game.autoSpawn = false;
        // Empty tubes 4 and 3 come first, but tube 2 has a matching top.
        game.tapTube(0);
        _runUntilSettled(game);
        expect(game.board.tubes[2], [2, 0, 0]);
        expect(game.board.tubes[3], isEmpty);
        expect(game.board.tubes[4], isEmpty);
      },
    );

    test('spawn groups and locked spawns depend on clears', () {
      final random = Random(7);
      const samples = 4000;

      Map<int, int> sizes(int clears) {
        final counts = <int, int>{};
        for (var i = 0; i < samples; i++) {
          final group = rollRushSpawn(clears, 3, random);
          counts[group.length] = (counts[group.length] ?? 0) + 1;
          final colors = group.map((s) => s.color).toSet();
          expect(colors, hasLength(group.length), reason: 'distinct colors');
          expect(colors.every((c) => c >= 0 && c < 3), isTrue);
          if (clears < 8) expect(group.any((s) => s.locked), isFalse);
        }
        return counts;
      }

      expect(sizes(0), {1: samples});
      expect(sizes(4), {1: samples});
      final five = sizes(5);
      expect(five.keys.toSet(), {1, 2});
      expect(five[2]! / samples, closeTo(0.5, 0.05));
      final fourteen = sizes(14);
      expect(fourteen.keys.toSet(), {1, 2});
      final fifteen = sizes(15);
      expect(fifteen.keys.toSet(), {1, 2, 3});
      for (final size in [1, 2, 3]) {
        expect(fifteen[size]! / samples, closeTo(1 / 3, 0.05));
      }
      sizes(7); // no locks before 8 clears (checked inside)

      var blocks = 0;
      var locked = 0;
      for (var i = 0; i < samples; i++) {
        for (final s in rollRushSpawn(8, 3, random)) {
          blocks++;
          if (s.locked) locked++;
        }
      }
      expect(locked / blocks, closeTo(1 / 8, 0.03));
    });

    test('a locked top or a locked block falling in takes nothing', () {
      final board = Board(
        tubes: [
          [0, 1],
          <int>[],
          [2],
        ],
        tubeSize: 4,
        locked: [
          {1},
          <int>{},
          <int>{},
        ],
      );
      final r = TubeReservations(3);
      expect(r.hasRoom(board, 0), isFalse);
      expect(r.accepts(board, 0, 1), isFalse);
      expect(r.hasRoom(board, 1), isTrue);
      r.reserve(1, 0, locked: true);
      expect(r.hasRoom(board, 1), isFalse);
      expect(r.accepts(board, 1, 0), isFalse);
      expect(r.hasRoom(board, 2), isTrue);
      r.landBlock(board, 1, 0, locked: true);
      expect(board.tubes[1], [0]);
      expect(board.locked[1], {0});
      expect(r.hasRoom(board, 1), isFalse);
    });

    testWithGame<ColorFlowGame>(
      'a locked spawn lands like any spawn and nothing lands on it',
      () => rush(
        Board(
          tubes: [
            [0],
            [1],
            [2],
            [0, 1],
            [2, 2],
          ],
          tubeSize: 4,
        ),
      ),
      (game) async {
        _prepare(game);
        game.autoSpawn = false;
        game.spawnBlock(1, locked: true);
        // Draws the locked block on the belt without errors.
        game.update(1 / 60);
        game.render(Canvas(PictureRecorder()));
        _runUntilSettled(game);
        expect(game.board.tubes[4], [2, 2, 1]);
        expect(game.board.locked[4], {2});
        // It cannot be tapped.
        game.tapTube(4);
        expect(game.taps, 0);
        // Tube 4 has room, but its top is locked: the 0 goes on.
        game.spawnBlock(0);
        _runUntilSettled(game);
        expect(game.board.tubes[4], [2, 2, 1]);
        expect(game.board.tubes[3], [0, 1, 0]);
      },
    );

    final lockScores = <int>[];
    testWithGame<ColorFlowGame>(
      'a locked spawn keeps its tube open until the next clear opens it',
      () => rush(
        Board(
          tubes: [
            [1, 1, 1],
            [1],
            [0, 2],
            [2, 0],
            [2, 2, 2],
          ],
          tubeSize: 4,
        ),
        onScore: lockScores.add,
      ),
      (game) async {
        _prepare(game);
        game.autoSpawn = false;
        game.spawnBlock(2, locked: true);
        _runUntilSettled(game);
        // Full and one color, but locked: not complete.
        expect(game.board.tubes[4], [2, 2, 2, 2]);
        expect(game.board.locked[4], {3});
        expect(game.board.isComplete(4), isFalse);
        expect(game.clears, 0);

        // The 1 completes tube 0; that clear opens the lock in tube 4,
        // which completes tube 4 too: a combo of 2.
        game.tapTube(1);
        runUntil(game, () => game.board.isComplete(0));
        expect(game.board.locked.every((s) => s.isEmpty), isTrue);
        expect(game.board.isComplete(4), isTrue);
        expect(game.clears, 2);
        expect(game.score, 3);
        expect(lockScores, [1, 3]);
      },
    );

    final comboScores = <int>[];
    final comboSounds = _FakeSounds();
    testWithGame<ColorFlowGame>(
      'clears in a row score +1, +2, +3; clears are counted apart',
      () => rush(
        Board(
          tubes: [
            [0, 0, 0],
            [0, 0, 0],
            [0, 0, 0],
            [1, 0, 0, 0],
            <int>[],
          ],
          tubeSize: 4,
        ),
        onScore: comboScores.add,
        sounds: comboSounds,
      ),
      (game) async {
        _prepare(game);
        game.autoSpawn = false;
        // Three 0s complete tubes 2, 1 and 0 within the combo window.
        game.tapTube(3);
        _runUntilSettled(game);
        expect(game.combo, 3);
        expect(comboScores, [1, 3, 6]);
        expect(game.score, 6);
        expect(game.hud.value.score, 6);
        expect(game.clears, 3);
        expect(comboSounds.events.where((e) => e.startsWith('complete')), [
          'complete 1',
          'complete 2',
          'complete 3',
        ]);
        // Spawn speed uses clears, not the score.
        expect(game.spawnInterval, closeTo(rushSpawnInterval(3), 1e-9));
      },
    );

    testWithGame<ColorFlowGame>(
      'the board grows by clears, not by score',
      () => rush(clearBoard()),
      (game) async {
        _prepare(game);
        game.autoSpawn = false;
        game.score = 100;
        game.clears = 8;
        game.tapTube(1);
        runUntil(game, () => game.board.tubes[0].isEmpty);
        expect(game.score, 101);
        expect(game.clears, 9);
        expect(game.board.tubeCount, 5);
        expect(game.config.colorCount, 3);
      },
    );
  });

  group('Layout', () {
    Board eightTubes() => Board(
      tubes: [
        [0, 1],
        [1, 0],
        [2, 2],
        [0],
        [1],
        [2],
        <int>[],
        <int>[],
      ],
      tubeSize: 4,
    );

    void expectSeparateTapRects(ColorFlowGame game, Vector2 screen) {
      final rects = [
        for (var i = 0; i < game.tubeCount; i++) game.tubeTapRect(i),
      ];
      for (var i = 0; i < rects.length; i++) {
        final r = rects[i];
        expect(r.width, greaterThanOrEqualTo(48), reason: 'tube $i');
        expect(r.left, greaterThanOrEqualTo(0), reason: 'tube $i');
        expect(r.right, lessThanOrEqualTo(screen.x + 1e-6), reason: 'tube $i');
        expect(r.bottom, lessThanOrEqualTo(screen.y + 1e-6), reason: 'tube $i');
        for (var j = i + 1; j < rects.length; j++) {
          expect(r.overlaps(rects[j]), isFalse, reason: 'tubes $i and $j');
        }
      }
    }

    testWithGame<ColorFlowGame>(
      'more than 6 tubes: two rows with tap areas at least 48 wide',
      () => ColorFlowGame(levelSource: _source(eightTubes()), haptics: false),
      (game) async {
        _prepare(game);
        final screen = Vector2(360, 760);
        game.onGameResize(screen);
        expect(game.tubeCount, 8);
        expectSeparateTapRects(game, screen);
        // Interleaved: even tubes in the top row, odd tubes below.
        final top = game.tubeTapRect(0);
        for (var i = 0; i < 8; i++) {
          final r = game.tubeTapRect(i);
          if (i.isEven) {
            expect(r.top, top.top, reason: 'tube $i');
          } else {
            expect(r.top, greaterThanOrEqualTo(top.bottom - 1e-6));
            expect(r.top, game.tubeTapRect(1).top, reason: 'tube $i');
          }
        }

        // A real tap in the middle of tube 1 (bottom row).
        final expected = applyCleanMove(game.board, 1, 3)!;
        final at = game.tubeTapRect(1).center;
        game.onTapDown(
          TapDownEvent(
            1,
            game,
            TapDownDetails(
              globalPosition: at,
              localPosition: at,
              kind: PointerDeviceKind.touch,
            ),
          ),
        );
        game.update(1 / 60);
        game.textScale = 2.5;
        game.render(Canvas(PictureRecorder()));
        _runUntilSettled(game);
        expect(game.board.tubes, expected.tubes);
      },
    );

    testWithGame<ColorFlowGame>(
      'each drop point is above its tube, in tube order',
      () => ColorFlowGame(levelSource: _source(eightTubes()), haptics: false),
      (game) async {
        _prepare(game);
        for (final screen in [Vector2(360, 760), Vector2(411, 891)]) {
          game.onGameResize(screen);
          for (var i = 0; i < game.tubeCount; i++) {
            final x = game.tubeTapRect(i).center.dx;
            expect(game.tubeDropX(i), closeTo(x, 1e-3), reason: 'tube $i');
            if (i > 0) {
              expect(x, greaterThan(game.tubeTapRect(i - 1).center.dx));
            }
          }
        }
        // Landscape: tubes and drops each keep the tube order.
        game.onGameResize(Vector2(900, 420));
        for (var i = 1; i < game.tubeCount; i++) {
          expect(
            game.tubeTapRect(i).center.dx,
            greaterThan(game.tubeTapRect(i - 1).center.dx),
          );
          expect(game.tubeDropX(i), greaterThan(game.tubeDropX(i - 1)));
        }
      },
    );

    testWithGame<ColorFlowGame>(
      'landscape: tubes on the right half, taps still work',
      _game,
      (game) async {
        _prepare(game);
        final portrait = game.tubeTapRect(0);
        final screen = Vector2(900, 420);
        game.onGameResize(screen);
        expect(game.tubeCount, 5);
        expectSeparateTapRects(game, screen);
        for (var i = 0; i < 5; i++) {
          expect(game.tubeTapRect(i).left, greaterThanOrEqualTo(450));
        }
        expect(game.tubeTapRect(0), isNot(portrait));

        final expected = applyCleanMove(game.board, 0, 3)!;
        game.tapTube(0);
        game.update(1 / 60);
        game.render(Canvas(PictureRecorder()));
        _runUntilSettled(game);
        expect(game.board.tubes, expected.tubes);

        // Back to portrait at runtime.
        game.onGameResize(Vector2(411, 891));
        expect(game.tubeTapRect(0), portrait);
      },
    );

    testWithGame<ColorFlowGame>(
      'landscape with two rows',
      () => ColorFlowGame(levelSource: _source(eightTubes()), haptics: false),
      (game) async {
        _prepare(game);
        final screen = Vector2(900, 420);
        game.onGameResize(screen);
        expectSeparateTapRects(game, screen);
        final expected = applyCleanMove(game.board, 5, 3)!;
        game.tapTube(5);
        _runUntilSettled(game);
        expect(game.board.tubes, expected.tubes);
      },
    );
  });

  group('Save and restore', () {
    /// A different board, so a restore that did not happen shows.
    LevelSource otherSource() => _source(
      Board(
        tubes: [
          [2, 2, 1],
          [0],
          [1, 0],
          <int>[],
          <int>[],
        ],
        tubeSize: 4,
      ),
    );

    Map<String, Object?> roundTrip(Map<String, Object?> saved) =>
        jsonDecode(jsonEncode(saved)) as Map<String, Object?>;

    testWithGame<ColorFlowGame>(
      'keeps the last settled board, taps and moves left',
      () => _game(mode: GameMode.moves),
      (game) async {
        _prepare(game);
        expect(game.saveState()!['taps'], 0);
        game.tapTube(0);
        _runUntilSettled(game);
        final settled = game.board.copy();
        game.tapTube(2);
        expect(game.isSettled, isFalse);
        final saved = game.saveState()!;
        expect(roundTrip(saved), saved);
        expect(saved['mode'], 'moves');
        expect(saved['taps'], 1);
        expect(saved['movesLeft'], 4); // limit 5 (3 x 1.5), one used

        final restored = await initializeGame(
          () => ColorFlowGame(
            mode: GameMode.moves,
            restoreState: roundTrip(saved),
            levelSource: otherSource(),
            haptics: false,
          ),
        );
        expect(restored.status, GameStatus.playing);
        expect(restored.isSliding, isFalse);
        expect(restored.board.key(), settled.key());
        expect(restored.taps, 1);
        expect(restored.hasProgress, isTrue);
        expect(restored.hud.value.movesLeft, 4);
        // Retry plays the original puzzle from the start.
        restored.retryLevel();
        expect(restored.board.key(), _board().key());
        expect(restored.taps, 0);
        restored.onRemove();
      },
    );

    final timedSaves = <Map<String, Object?>>[];
    testWithGame<ColorFlowGame>(
      'keeps the time left in timed mode',
      () => _game(mode: GameMode.timed),
      (game) async {
        _prepare(game);
        _run(game, 10);
        game.tapTube(0);
        _runUntilSettled(game);
        final saved = roundTrip(game.saveState()!);
        timedSaves.add(saved);
        final timeLeft = saved['timeLeft']! as double;
        expect(timeLeft, lessThan(62.5));
        expect(timeLeft, greaterThan(55));

        final restored = await initializeGame(
          () => ColorFlowGame(
            mode: GameMode.timed,
            restoreState: saved,
            levelSource: otherSource(),
            haptics: false,
          ),
        );
        expect(restored.board.key(), game.board.key());
        expect(restored.hud.value.secondsLeft, timeLeft.ceil());
        expect(restored.taps, 1);
        restored.onRemove();
      },
    );

    for (final (name, create)
        in <(String, ColorFlowGame Function(Map<String, Object?>))>[
          (
            'another mode',
            (s) => ColorFlowGame(
              restoreState: s,
              levelSource: otherSource(),
              haptics: false,
            ),
          ),
          (
            'another level',
            (s) => ColorFlowGame(
              mode: GameMode.timed,
              initialLevel: 2,
              restoreState: s,
              levelSource: otherSource(),
              haptics: false,
            ),
          ),
          (
            'invalid data',
            (s) => ColorFlowGame(
              mode: GameMode.timed,
              restoreState: {
                ...s,
                'board': {'tubes': 'broken'},
              },
              levelSource: otherSource(),
              haptics: false,
            ),
          ),
        ]) {
      test('a save for $name is ignored', () async {
        expect(timedSaves, isNotEmpty, reason: 'needs the timed save test');
        final game = await initializeGame(() => create(timedSaves.first));
        expect(game.status, GameStatus.playing);
        expect(game.taps, 0);
        expect(game.board.tubes[0], [2, 2, 1]);
        game.onRemove();
      });
    }

    testWithGame<ColorFlowGame>(
      'nothing to save in rush, endless or after a win',
      () => _game(mode: GameMode.endless),
      (game) async {
        _prepare(game);
        expect(game.saveState(), isNull);
        final rush = await initializeGame(
          () => ColorFlowGame(mode: GameMode.rush, haptics: false),
        );
        expect(rush.saveState(), isNull);
        rush.onRemove();
      },
    );
  });

  group('Pause, progress and accessibility', () {
    testWithGame<ColorFlowGame>(
      'pause stops the timer and ignores taps',
      () => _game(mode: GameMode.timed),
      (game) async {
        _prepare(game);
        game.pause();
        expect(game.isPaused, isTrue);
        _run(game, 5);
        expect(game.hud.value.secondsLeft, 72);
        game.tapTube(0);
        expect(game.taps, 0);
        game.resume();
        expect(game.isPaused, isFalse);
        _run(game, 1.1);
        expect(game.hud.value.secondsLeft, 71);
        game.tapTube(0);
        expect(game.taps, 1);
      },
    );

    testWithGame<ColorFlowGame>(
      'pause stops rush spawns and the belt',
      () => ColorFlowGame(
        mode: GameMode.rush,
        levelSource: _source(
          Board(
            tubes: [
              [0, 1, 0, 1],
              [1, 0, 1, 0],
              [0, 2, 0, 2],
              [2, 0, 2, 0],
              [1, 2, 1, 2],
            ],
            tubeSize: 4,
          ),
          solution: 0,
        ),
        haptics: false,
      ),
      (game) async {
        _prepare(game, slide: false);
        game.pause();
        _run(game, 6);
        expect(game.hud.value.loopCount, 0);
        game.resume();
        _run(game, 3.1);
        expect(game.hud.value.loopCount, 1);
      },
    );

    testWithGame<ColorFlowGame>('hasProgress after an accepted tap', _game, (
      game,
    ) async {
      _prepare(game);
      expect(game.hasProgress, isFalse);
      game.tapTube(3); // empty tube: not accepted
      expect(game.hasProgress, isFalse);
      game.tapTube(0);
      expect(game.hasProgress, isTrue);
      game.retryLevel();
      expect(game.hasProgress, isFalse);
    });

    testWithGame<ColorFlowGame>(
      'tube labels and layout version',
      () => ColorFlowGame(
        levelSource: _source(
          Board(
            tubes: [
              [0, 0, 0, 0],
              [1, 2],
              [2, Board.rainbow],
              [0, 1, 2, 2],
              <int>[],
            ],
            tubeSize: 4,
            locked: [
              <int>{},
              {1},
              <int>{},
              <int>{},
              <int>{},
            ],
            hidden: [
              <int>{},
              <int>{},
              <int>{},
              {0, 1},
              <int>{},
            ],
          ),
        ),
        haptics: false,
      ),
      (game) async {
        _prepare(game);
        expect(game.tubeCount, 5);
        expect(
          [for (var i = 0; i < 5; i++) game.tubeLabel(i)],
          [
            'Tube 1, 4 of 4 blocks, sorted',
            'Tube 2, 2 of 4 blocks, locked top',
            'Tube 3, 2 of 4 blocks, top: rainbow x1',
            'Tube 4, 4 of 4 blocks, top: blue x2, 2 hidden blocks',
            'Tube 5, empty',
          ],
        );
        final version = game.layoutVersion.value;
        game.tapTube(3);
        expect(game.layoutVersion.value, greaterThan(version));
        final afterTap = game.layoutVersion.value;
        _runUntilSettled(game);
        expect(game.layoutVersion.value, greaterThan(afterTap));
        expect(
          game.tubeLabel(3),
          'Tube 4, 2 of 4 blocks, top: yellow x1, 1 hidden block',
        );
      },
    );

    Completer<Puzzle>? pendingBuild;
    testWithGame<ColorFlowGame>(
      'the loading overlay shows while a level builds',
      () {
        final game = ColorFlowGame(
          levelSource: (_, _) =>
              pendingBuild?.future ??
              Future.value(Puzzle(board: _board(), solutionLength: 3)),
          haptics: false,
        );
        game.overlays.addEntry('loading', (_, _) => const SizedBox());
        return game;
      },
      (game) async {
        _prepare(game);
        expect(game.overlays.isActive('loading'), isFalse);

        pendingBuild = Completer();
        final next = game.startLevel(2);
        expect(game.overlays.isActive('loading'), isTrue);
        expect(game.saveState(), isNull);
        pendingBuild!.complete(Puzzle(board: _board(), solutionLength: 3));
        await next;
        expect(game.overlays.isActive('loading'), isFalse);
        expect(game.status, GameStatus.playing);

        pendingBuild = Completer();
        final failing = game.startLevel(3);
        expect(game.overlays.isActive('loading'), isTrue);
        pendingBuild!.completeError(StateError('no level'));
        await failing;
        expect(game.overlays.isActive('loading'), isFalse);
        expect(game.status, GameStatus.failed);
      },
    );
  });
}
