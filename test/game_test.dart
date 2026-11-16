import 'dart:math';
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:color_flow/game/board.dart';
import 'package:color_flow/game/color_flow_game.dart';
import 'package:color_flow/game/game_feedback.dart';
import 'package:color_flow/game/game_mode.dart';
import 'package:color_flow/game/level_config.dart';
import 'package:color_flow/game/level_generator.dart';
import 'package:flame/game.dart';
import 'package:flame_test/flame_test.dart';
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
  for (final name in ['stuck', 'failed', 'won']) {
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
    'taps are ignored while the tubes slide in',
    _game,
    (game) async {
      _prepare(game, slide: false);
      expect(game.isSliding, isTrue);
      final start = game.board.key();
      game.tapTube(0);
      expect(game.board.key(), start);
      expect(game.taps, 0);
      _run(game, 0.3);
      expect(game.isSliding, isTrue);
      _finishSlide(game);
      game.tapTube(0);
      expect(game.board.key(), isNot(start));
      expect(game.taps, 1);
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
}
