import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../ui/app_theme.dart';
import 'board.dart';
import 'game_feedback.dart';
import 'game_mode.dart';
import 'level_config.dart';
import 'level_generator.dart';

enum GameStatus { loading, playing, stuck, failed, won }

enum _Phase { rising, looping, falling }

/// Builds the puzzle for a level. A [seed] gives the same puzzle every
/// time (daily mode).
typedef LevelSource = Future<Puzzle> Function(LevelConfig config, int? seed);

/// Default level source: runs the generator and solver on a background
/// isolate so a slow search never freezes a frame.
Future<Puzzle> generateInBackground(LevelConfig config, int? seed) =>
    Isolate.run(
      () =>
          LevelGenerator(random: seed == null ? null : Random(seed))
              .generate(config),
    );

/// Default rush source: a fresh random start board.
Future<Puzzle> rushInBackground(LevelConfig config, int? seed) async =>
    rushStart(config, Random(seed));

/// Snapshot the Flutter HUD shows.
class HudState {
  const HudState({
    required this.level,
    required this.loopCount,
    required this.loopCapacity,
    required this.status,
    required this.blockedTaps,
    this.movesLeft,
    this.secondsLeft,
    this.score,
  });

  final int level;
  final int loopCount;
  final int loopCapacity;
  final GameStatus status;

  /// Goes up by one on every tap that did not fit in the loop.
  /// The HUD flashes the loop bar when it changes.
  final int blockedTaps;

  /// Move limit mode only.
  final int? movesLeft;

  /// Timed mode only.
  final int? secondsLeft;

  /// Endless and rush only: the run score.
  final int? score;
}

class _Particle {
  _Particle({
    required this.along,
    required this.lateral,
    required this.delay,
    required this.rotation,
    required this.color,
  });

  /// Offset behind the block head, along the path.
  final double along;

  /// Offset to the side of the path.
  final double lateral;

  /// Start delay for rise and fall, in seconds.
  final double delay;
  final double rotation;
  final int color;

  /// Start point of the current rise or fall.
  Offset from = Offset.zero;

  /// End point of a fall, inside the target slot.
  Offset to = Offset.zero;
}

class _FlyingBlock {
  _FlyingBlock({
    required this.color,
    required this.source,
    required this.distance,
    required this.checkOffset,
    required this.particles,
    required this.phaseDelay,
  });

  final int color;
  final int source;

  /// Head position along the loop path (unwrapped, grows forever).
  double distance;

  /// Added to [distance] for drop checks, so every block of one run checks
  /// tubes in the same order as the solver, starting at the source.
  final double checkOffset;
  final List<_Particle> particles;
  final double phaseDelay;

  _Phase phase = _Phase.rising;
  double phaseTime = 0;

  /// The first block of a tap: plays the whoosh when it reaches the loop.
  bool whooshOnLoop = false;

  /// Rush: a new block. It drops into the first tube with room.
  bool spawned = false;

  /// Rush: a locked new block. Its color stays hidden.
  bool locked = false;
  int target = -1;

  /// Checkpoint value at the last board change. Used for stuck detection.
  double lapMark = 0;

  double get checkpoint => distance + checkOffset;
}

class _Sparkle {
  _Sparkle(this.position, this.velocity, this.color);

  Offset position;
  Offset velocity;
  final Color color;
  double life = 1;
}

/// The board at a moment when no blocks were moving, for [saveState].
class _Snapshot {
  _Snapshot({
    required this.board,
    required this.loop,
    required this.taps,
    required this.movesLeft,
  });

  final Board board;

  /// Blocks still to put on the loop (belt-full start only).
  final List<int> loop;
  final int taps;
  final int movesLeft;
}

class ColorFlowGame extends FlameGame with TapCallbacks {
  ColorFlowGame({
    this.restoreState,
    this.mode = GameMode.levels,
    this.initialLevel = 1,
    this.seed,
    LevelSource? levelSource,
    this.onLevelReached,
    this.onScore,
    this.onWon,
    this.haptics = true,
    this.style = const BlockStyle(palette: AppColors.blocks),
    this.sounds = const SilentSounds(),
  }) : _levelSource =
           levelSource ??
           (mode == GameMode.rush ? rushInBackground : generateInBackground);

  final GameMode mode;
  final int initialLevel;

  /// A game saved with [saveState]. When it matches this mode (and level,
  /// or seed for daily), the game continues from it instead of building
  /// a new level. Invalid or mismatched data is ignored.
  final Map<String, Object?>? restoreState;

  /// Fixed generator seed (daily mode), or null for a random level.
  final int? seed;
  final LevelSource _levelSource;

  /// Called with the new level number when the player moves on,
  /// so the app can save progress.
  final ValueChanged<int>? onLevelReached;

  /// Endless and rush: called with the run score whenever it goes up.
  /// In rush every clear scores its combo level (+1, +2, +3, ...).
  final ValueChanged<int>? onScore;

  /// Called when a level is won, before the win overlay shows.
  final ValueChanged<LevelResult>? onWon;
  final bool haptics;

  /// Block colors and shapes.
  final BlockStyle style;
  final GameSounds sounds;

  /// Default block colors.
  static const List<Color> palette = AppColors.blocks;

  static const double _slideDelay = 0.06;
  static const double _slideDuration = 0.35;
  static const double _comboWindow = 2;
  static const double _comboLabelDuration = 1;
  static const Color _hiddenColor = Color(0xFF3A3F4B);
  static const Color _lockedColor = Color(0xFF7D8494);
  static const List<Color> _rainbowColors = [
    Color(0xFFFF5A5F),
    Color(0xFFFFB347),
    Color(0xFFFFE066),
    Color(0xFF5BE38C),
    Color(0xFF4DA8FF),
    Color(0xFFB57BFF),
    Color(0xFFFF5A5F),
  ];
  static const List<double> _rainbowStops = [
    0,
    1 / 6,
    2 / 6,
    3 / 6,
    4 / 6,
    5 / 6,
    1,
  ];
  static const double _blockLength = 46;
  static const double _blockGap = 10;
  static const double _channelWidth = 26;
  static const double _riseDuration = 0.35;
  static const double _fallDuration = 0.45;
  static const int _particlesPerBlock = 40;
  static const double _particleSize = 6;
  static const double _spriteSize = 16;
  static const double _shakeDuration = 0.35;
  static const double _pulseDuration = 0.8;
  static const double _arrowSpacing = 64;
  static const double _tubePad = 6;

  /// Rush: seconds between a tube bursting and its blocks vanishing.
  static const double _clearDelay = 0.5;

  final Random _random = Random();

  final ValueNotifier<HudState> hud = ValueNotifier(
    const HudState(
      level: 1,
      loopCount: 0,
      loopCapacity: 0,
      status: GameStatus.loading,
      blockedTaps: 0,
    ),
  );

  int level = 1;
  late LevelConfig config;
  Puzzle? _puzzle;
  Board? _board;
  late TubeReservations reservations;
  final List<_FlyingBlock> _flying = [];
  final List<_Sparkle> _sparkles = [];
  GameStatus status = GameStatus.loading;
  int _blockedTaps = 0;
  int _loadToken = 0;
  int _movesLeft = 0;
  int _requestedLevel = 1;
  bool _buildFailed = false;

  /// Blocks on the loop without a target tube, in the order the solver
  /// keeps them (newest tap first). See [_planTargets].
  final List<_FlyingBlock> _waiting = [];

  /// Blocks falling into each tube right now, for the slot they fill.
  List<int> _fallingInto = [];
  double _timeLeft = 0;
  int _score = 0;

  /// Rush: tubes cleared this run. Growth and spawn speed use this,
  /// not the score.
  int _clears = 0;

  /// Rush: the next spawn group, kept until the belt has room for it.
  List<RushSpawn>? _nextSpawn;

  /// Rush: spawns new blocks on a timer. Tests turn it off to spawn by hand.
  @visibleForTesting
  bool autoSpawn = true;

  /// Rush: time since the last new block, and the seconds left before
  /// each bursting tube empties (0 when it is not bursting).
  double _spawnTimer = 0;
  List<double> _clearTimers = [];

  /// Rush: loop distance of the spawn point (top center of the loop).
  double _spawnDistance = 0;

  /// Why the level failed, shown on the fail overlay.
  String failReason = '';

  /// Loop blocks of a belt-full start, spawned once the layout is ready.
  bool _loopPending = false;
  double _time = 0;

  /// Remaining shake and completion pulse time per tube, in seconds.
  List<double> _shake = [];
  List<double> _pulse = [];

  /// Accepted taps and play time of this attempt, for [LevelResult].
  int _taps = 0;
  double _playTime = 0;

  /// Completions within [_comboWindow] seconds of each other.
  int _combo = 0;
  double _lastCompleteTime = double.negativeInfinity;
  double _comboLabelTime = 0;
  TextPainter? _comboPainter;
  int _comboPainterValue = 0;

  /// Combo strength of each tube's completion pulse.
  List<int> _pulseCombo = [];

  /// Time since the board started, for the slide-in of the tubes.
  double _slideTime = 0;

  /// Level 1 hint: visible until the first tap on a tube.
  bool _hintVisible = false;
  int _hintTube = 0;

  /// A tap made while the tubes slide in, applied when the slide ends.
  int? _queuedTap;

  /// Paused by the app (for example when it goes to the background).
  bool _paused = false;

  /// The most recent board where nothing was moving, for [saveState].
  _Snapshot? _settled;

  /// Blocks put on the loop once the layout is ready (belt-full start).
  List<int> _pendingLoop = const [];

  /// Bumped on every relayout and every board change, so the Flutter
  /// screen can rebuild its accessibility labels.
  final ValueNotifier<int> layoutVersion = ValueNotifier(0);
  bool _versionBumpScheduled = false;

  /// Top system inset (status bar), set by the Flutter screen.
  double _topInset = 0;
  set topInset(double value) {
    if (value == _topInset) return;
    _topInset = value;
    _relayout();
  }

  /// Bottom system inset (navigation bar), set by the Flutter screen.
  double _bottomInset = 0;
  set bottomInset(double value) {
    if (value == _bottomInset) return;
    _bottomInset = value;
    _relayout();
  }

  /// Height of the Flutter HUD below the top inset.
  double _hudHeight = 96;
  set hudHeight(double value) {
    if (value == _hudHeight) return;
    _hudHeight = value;
    _relayout();
  }

  /// System text scale factor, used for all text drawn on the canvas.
  double _textScale = 1;
  set textScale(double value) {
    if (value == _textScale) return;
    _textScale = value;
    _centerKey = '';
    _comboPainter = null;
  }

  // Layout.
  late Rect _loopRect;
  late ui.Path _loopPath;
  late ui.PathMetric _metric;
  late List<Rect> _tubeRects;
  late List<Rect> _tapRects;
  late List<double> _dropDistance;
  late double _slotHeight;
  late double _tubeAreaCenter;
  List<Rect> _cardRects = const [];
  List<Paint> _cardFills = const [];
  bool _layoutReady = false;

  // Cached paints.
  final Paint _cardBorder = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = AppColors.glassBorder;
  final Paint _loopBorder = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _channelWidth + 2
    ..color = AppColors.glassBorder;
  final Paint _loopWell = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _channelWidth
    ..color = AppColors.well;
  final Paint _arrowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0x33FFFFFF);
  final Paint _tubeFill = Paint()..color = AppColors.well;
  final Paint _tubeOutline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _blockPaint = Paint();
  final Paint _shinePaint = Paint()..color = const Color(0x59FFFFFF);
  final Paint _symbolPaint = Paint()..color = const Color(0x52000000);
  final Paint _glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 6
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  final Paint _sparklePaint = Paint();
  final Paint _atlasPaint = Paint()..filterQuality = FilterQuality.low;

  // Center text, rebuilt only when the content changes.
  TextPainter? _centerPainter;
  String _centerKey = '';
  late TextPainter _questionPainter;
  late TextPainter _lockPainter;
  late final TextPainter _fingerPainter = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(Icons.touch_app_rounded.codePoint),
      style: TextStyle(
        fontFamily: Icons.touch_app_rounded.fontFamily,
        package: Icons.touch_app_rounded.fontPackage,
        fontSize: 44,
        color: AppColors.text,
        shadows: const [Shadow(blurRadius: 12, color: Color(0x99000000))],
      ),
    ),
  )..layout();

  // Particle batch drawing.
  ui.Image? _sprite;

  /// Set by [disposeResources]; the notifiers must not change after it.
  bool _resourcesDisposed = false;
  Float32List _transforms = Float32List(0);
  Float32List _rects = Float32List(0);
  Int32List _colors = Int32List(0);

  Board get board => _board!;

  /// Current combo count (0 before the first completion).
  @visibleForTesting
  int get combo => _combo;

  /// Accepted taps this attempt.
  @visibleForTesting
  int get taps => _taps;

  /// Endless and rush: the score of this run. Tests may set it in rush to
  /// skip ahead to a later stage.
  @visibleForTesting
  int get score => _score;
  @visibleForTesting
  set score(int value) => _score = value;

  /// Rush: tubes cleared this run. Tests may set it to skip ahead to a
  /// later stage.
  @visibleForTesting
  int get clears => _clears;
  @visibleForTesting
  set clears(int value) => _clears = value;

  /// Rush: seconds between two new blocks right now.
  double get spawnInterval => rushSpawnInterval(_clears);

  /// True while the tubes slide in; a tap is queued until it ends.
  bool get isSliding =>
      _board != null &&
      _slideTime < _slideDelay * (board.tubeCount - 1) + _slideDuration;

  /// True when no blocks are moving. Used by tests.
  @visibleForTesting
  bool get isSettled => _flying.isEmpty;

  /// True while the game is paused: nothing moves and taps are ignored.
  bool get isPaused => _paused;

  /// Stops all updates (timer, spawns, belt) until [resume].
  void pause() => _paused = true;

  void resume() => _paused = false;

  /// Frees [hud], [layoutVersion] and the particle sprite. Call once the
  /// host is done with this game, after its last [saveState]; GameWidget
  /// may attach a removed game again, so onRemove does not do this. Safe
  /// to call more than once.
  void disposeResources() {
    if (_resourcesDisposed) return;
    _resourcesDisposed = true;
    hud.dispose();
    layoutVersion.dispose();
    _sprite?.dispose();
    _sprite = null;
  }

  /// This attempt has an accepted tap (or, in rush and endless, a score).
  bool get hasProgress =>
      _taps > 0 ||
      ((mode == GameMode.rush || mode == GameMode.endless) && _score > 0);

  /// Number of tubes on screen (0 while there is no layout).
  int get tubeCount => _layoutReady ? _tubeRects.length : 0;

  /// Tap area of [tube] in game coordinates, as used for taps.
  Rect tubeTapRect(int tube) => _layoutReady ? _tapRects[tube] : Rect.zero;

  /// X of the point on the loop where blocks for [tube] drop off.
  @visibleForTesting
  double tubeDropX(int tube) => _pointOnLoop(_dropDistance[tube], 0).dx;

  /// Color names for accessibility labels, per color id.
  static const List<String> colorNames = [
    'pink',
    'yellow',
    'blue',
    'green',
    'orange',
    'purple',
  ];

  static String _colorName(int color) => color == Board.rainbow
      ? 'rainbow'
      : (color >= 0 && color < colorNames.length
            ? colorNames[color]
            : 'color ${color + 1}');

  /// Screen reader label for [tube], for example
  /// 'Tube 3, 4 of 6 blocks, top: pink x2'.
  String tubeLabel(int tube) {
    final b = _board;
    final name = 'Tube ${tube + 1}';
    if (b == null || tube < 0 || tube >= b.tubeCount) return name;
    final t = b.tubes[tube];
    if (t.isEmpty) return '$name, empty';
    final parts = <String>['$name, ${t.length} of ${b.tubeSize} blocks'];
    if (b.isComplete(tube)) {
      parts.add('sorted');
    } else if (b.isLocked(tube, t.length - 1)) {
      parts.add('locked top');
    } else {
      parts.add('top: ${_colorName(t.last)} x${b.topRunLength(tube)}');
    }
    final hidden = b.hidden[tube].length;
    if (hidden > 0) {
      parts.add('$hidden hidden ${hidden == 1 ? 'block' : 'blocks'}');
    }
    return parts.join(', ');
  }

  void _bumpVersion() {
    if (_resourcesDisposed) return;
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (_versionBumpScheduled) return;
      _versionBumpScheduled = true;
      binding.addPostFrameCallback((_) {
        _versionBumpScheduled = false;
        if (!_resourcesDisposed) layoutVersion.value++;
      });
    } else {
      layoutVersion.value++;
    }
  }

  // Transparent: the Flutter screen paints the gradient background.
  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    final sprite = await _buildSprite();
    if (_resourcesDisposed) {
      sprite.dispose();
      return;
    }
    _sprite = sprite;
    final saved = restoreState;
    if (saved != null && _restore(saved)) return;
    await startLevel(initialLevel);
  }

  /// Builds a new puzzle for [newLevel] and starts it. With [save], the
  /// level is reported to [onLevelReached] once it has started.
  Future<void> startLevel(int newLevel, {bool save = false}) async {
    final token = ++_loadToken;
    status = GameStatus.loading;
    _requestedLevel = newLevel;
    _removeResultOverlays();
    // The app registers 'loading'; tests and other hosts may not.
    if (overlays.registeredOverlays.contains('loading')) {
      overlays.add('loading');
    }
    _publishHudFor(newLevel);

    final newConfig = mode.configFor(newLevel);
    final Puzzle puzzle;
    try {
      puzzle = await _levelSource(newConfig, seed);
    } catch (_) {
      if (token != _loadToken) return;
      _buildFailed = true;
      overlays.remove('loading');
      _fail('Could not build a level');
      return;
    }
    // A newer request (for example a fast double tap) wins.
    if (token != _loadToken) return;

    _buildFailed = false;
    level = newLevel;
    config = newConfig;
    _puzzle = puzzle;
    _begin();
    if (save && mode.hasLevels) onLevelReached?.call(newLevel);
  }

  /// Plays the current puzzle again from the start. After a failed build
  /// it tries to build the level again.
  void retryLevel() {
    // Rush: every retry is a fresh run on a new start board.
    if (mode == GameMode.rush) {
      startLevel(1);
      return;
    }
    if (_buildFailed) {
      startLevel(_requestedLevel, save: _requestedLevel != level);
      return;
    }
    if (_puzzle == null || status == GameStatus.loading) return;
    _begin();
  }

  /// Endless mode: a new board of the same size; the score keeps going.
  Future<void> skipBoard() =>
      status == GameStatus.loading ? Future.value() : startLevel(level);

  /// The round button in the HUD: Skip in endless, Retry elsewhere.
  void restartPressed() {
    if (mode == GameMode.endless) {
      skipBoard();
    } else {
      retryLevel();
    }
  }

  Future<void> nextLevel() => startLevel(level + 1, save: true);

  // ----------------------------------------------------------- save/restore

  static const int _saveVersion = 1;

  /// The game as a JSON-encodable map, to continue later through
  /// [restoreState]. Level modes only; null in rush and endless, while
  /// loading, and once the level is won or failed. While blocks move,
  /// this is the most recent board where nothing moved.
  Map<String, Object?>? saveState() {
    if (mode == GameMode.rush || mode == GameMode.endless) return null;
    if (status == GameStatus.loading ||
        status == GameStatus.won ||
        status == GameStatus.failed) {
      return null;
    }
    final puzzle = _puzzle;
    if (puzzle == null || _board == null) return null;
    final now = _flying.isEmpty && !_loopPending
        ? _Snapshot(
            board: board,
            loop: const [],
            taps: _taps,
            movesLeft: _movesLeft,
          )
        : _settled;
    if (now == null) return null;
    return {
      'version': _saveVersion,
      'mode': mode.name,
      'level': level,
      'seed': seed,
      'puzzle': {
        ..._boardToJson(puzzle.board, puzzle.loop),
        'solutionLength': puzzle.solutionLength,
      },
      'board': _boardToJson(now.board, now.loop),
      'taps': now.taps,
      'elapsed': _playTime,
      'timeLeft': _timeLeft,
      'movesLeft': now.movesLeft,
      'score': _score,
    };
  }

  static Map<String, Object?> _boardToJson(Board b, List<int> loop) => {
    'tubeSize': b.tubeSize,
    'tubes': [for (final t in b.tubes) List<int>.of(t)],
    'locked': [for (final s in b.locked) s.toList()..sort()],
    'hidden': [for (final s in b.hidden) s.toList()..sort()],
    'loop': List<int>.of(loop),
  };

  static int _int(Object? v) => (v! as num).toInt();

  static List<int> _ints(Object? v) => [for (final e in v! as List) _int(e)];

  /// Reads a board saved by [_boardToJson]; throws on invalid data.
  (Board, List<int>) _boardFromJson(Object? json) {
    final map = json! as Map;
    final tubeSize = _int(map['tubeSize']);
    final tubes = [for (final t in map['tubes']! as List) _ints(t)];
    final locked = [for (final s in map['locked']! as List) _ints(s).toSet()];
    final hidden = [for (final s in map['hidden']! as List) _ints(s).toSet()];
    final loop = _ints(map['loop']);
    bool validColor(int c) =>
        c == Board.rainbow || (c >= 0 && c < style.palette.length);
    if (tubeSize <= 0 ||
        tubes.length < 2 ||
        locked.length != tubes.length ||
        hidden.length != tubes.length ||
        !loop.every(validColor)) {
      throw const FormatException('Invalid board');
    }
    for (var i = 0; i < tubes.length; i++) {
      final n = tubes[i].length;
      if (n > tubeSize ||
          !tubes[i].every(validColor) ||
          locked[i].any((k) => k < 0 || k >= n) ||
          hidden[i].any((k) => k < 0 || k >= n)) {
        throw const FormatException('Invalid tube');
      }
    }
    return (
      Board(tubes: tubes, tubeSize: tubeSize, locked: locked, hidden: hidden),
      loop,
    );
  }

  /// Continues from [saved] when it matches this game. Returns false (and
  /// changes nothing) for mismatched or invalid data.
  bool _restore(Map<String, Object?> saved) {
    try {
      if (mode == GameMode.rush || mode == GameMode.endless) return false;
      if (saved['version'] != _saveVersion) return false;
      if (saved['mode'] != mode.name) return false;
      final savedLevel = _int(saved['level']);
      if (mode == GameMode.daily) {
        final savedSeed = saved['seed'];
        if (seed == null || savedSeed == null || _int(savedSeed) != seed) {
          return false;
        }
      } else if (savedLevel != initialLevel) {
        return false;
      }
      final (puzzleBoard, puzzleLoop) = _boardFromJson(saved['puzzle']);
      final solution = _int((saved['puzzle']! as Map)['solutionLength']);
      final (current, loop) = _boardFromJson(saved['board']);
      if (current.tubeCount != puzzleBoard.tubeCount ||
          current.tubeSize != puzzleBoard.tubeSize) {
        return false;
      }
      final taps = _int(saved['taps']);
      final movesLeft = _int(saved['movesLeft']);
      final elapsed = (saved['elapsed']! as num).toDouble();
      final timeLeft = (saved['timeLeft']! as num).toDouble();
      final score = _int(saved['score']);
      if (taps < 0 || movesLeft < 0 || elapsed < 0 || timeLeft < 0) {
        return false;
      }
      if (mode == GameMode.timed && timeLeft <= 0) return false;

      _loadToken++;
      _buildFailed = false;
      level = savedLevel;
      _requestedLevel = savedLevel;
      config = mode.configFor(savedLevel);
      _puzzle = Puzzle(
        board: puzzleBoard,
        loop: puzzleLoop,
        solutionLength: solution,
      );
      _begin(
        from: _Snapshot(
          board: current,
          loop: loop,
          taps: taps,
          movesLeft: movesLeft,
        ),
      );
      _playTime = elapsed;
      _timeLeft = timeLeft;
      _score = score;
      // A restored board is shown right away, without the slide-in.
      _slideTime = double.infinity;
      _publishHud();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _removeResultOverlays() {
    overlays.remove('won');
    overlays.remove('stuck');
    overlays.remove('failed');
  }

  /// Starts the current puzzle, or continues from [from] (a restored game).
  void _begin({_Snapshot? from}) {
    overlays.remove('loading');
    final puzzle = _puzzle!;
    final newBoard = (from?.board ?? puzzle.board).copy();
    _board = newBoard;
    _queuedTap = null;
    _layoutReady = false;
    reservations = TubeReservations(newBoard.tubeCount);
    _flying.clear();
    _waiting.clear();
    _fallingInto = List.filled(newBoard.tubeCount, 0);
    _sparkles.clear();
    _shake = List.filled(newBoard.tubeCount, 0);
    _pulse = List.filled(newBoard.tubeCount, 0);
    _pulseCombo = List.filled(newBoard.tubeCount, 1);
    _taps = 0;
    _playTime = 0;
    _combo = 0;
    _lastCompleteTime = double.negativeInfinity;
    _comboLabelTime = 0;
    _slideTime = 0;
    _spawnTimer = 0;
    _clearTimers = List.filled(newBoard.tubeCount, 0);
    if (mode == GameMode.rush) {
      _score = 0;
      _clears = 0;
      _nextSpawn = null;
      config = LevelConfig.rush(0);
    }
    _movesLeft = moveLimitFor(puzzle.solutionLength);
    _timeLeft = secondsFor(config).toDouble();
    _pendingLoop = List<int>.of(from?.loop ?? puzzle.loop);
    if (from != null) {
      _taps = from.taps;
      _movesLeft = from.movesLeft;
    }
    _settled = _Snapshot(
      board: newBoard.copy(),
      loop: _pendingLoop,
      taps: _taps,
      movesLeft: _movesLeft,
    );
    _hintVisible = mode == GameMode.levels && level == 1 && _taps == 0;
    if (_hintVisible) {
      final path = Solver(config.loopCapacity, 60000).solve(newBoard);
      _hintTube = (path == null || path.isEmpty) ? 0 : path.first;
    }
    _removeResultOverlays();
    status = GameStatus.playing;
    _loopPending = _pendingLoop.isNotEmpty;
    _relayout();
    _publishHud();
  }

  /// Belt-full start: the loop blocks are spread evenly around the loop.
  void _spawnLoop() {
    _loopPending = false;
    final loop = _pendingLoop;
    final len = _metric.length;
    for (var i = 0; i < loop.length; i++) {
      final block = _FlyingBlock(
        color: loop[i],
        source: -1,
        distance: len * i / loop.length,
        checkOffset: 0,
        particles: _makeParticles(loop[i]),
        phaseDelay: 0,
      )..phase = _Phase.looping;
      block.lapMark = block.checkpoint;
      _flying.add(block);
      _waiting.add(block);
    }
    _planTargets([for (var i = 0; i < board.tubeCount; i++) i]);
    _publishHud();
  }

  /// Gives waiting blocks a target tube, exactly like [settleLoop] in the
  /// solver: the waiting block with the best score takes its best tube
  /// (ties: the first waiting block), then the search starts again, until
  /// no waiting block fits. Rush spawns score 0, so they go last. A block
  /// only drops at its target, so the game always matches the solver.
  /// [order] gives the tubes in the order a block passes them; by default
  /// every block uses [order]. Rush passes [orderFor] instead, so each
  /// block counts from where it is on the loop. Rush spawns do not look
  /// for the best tube: see [_messyTarget].
  void _planTargets(
    List<int> order, {
    List<int> Function(_FlyingBlock b)? orderFor,
  }) {
    while (true) {
      _FlyingBlock? best;
      var bestTube = -1;
      var bestScore = -1;
      for (final b in _waiting) {
        final tubes = orderFor?.call(b) ?? order;
        final target = b.spawned
            ? _messyTarget(b, tubes)
            : reservations.chooseTube(board, tubes, b.color);
        if (target == null) continue;
        final s = b.spawned ? 0 : reservations.score(board, target, b.color)!;
        if (s > bestScore) {
          best = b;
          bestTube = target;
          bestScore = s;
        }
      }
      if (best == null) break;
      reservations.reserve(bestTube, best.color, locked: best.locked);
      best.target = bestTube;
      _waiting.remove(best);
    }
  }

  /// Takes the target away from every block still on the loop that was
  /// heading for [tube] and puts it back with the waiting blocks.
  void _releaseTargets(int tube) {
    reservations.release(tube);
    for (final b in _flying) {
      if (b.target != tube || b.phase == _Phase.falling) continue;
      b.target = -1;
      _waiting.add(b);
    }
  }

  /// Rush spawn: the first tube in [order] with room, whatever its top
  /// color. A bursting tube and a locked top take nothing. A locked block
  /// also skips tubes with blocks still falling in, so nothing can land
  /// on top of it.
  int? _messyTarget(_FlyingBlock b, List<int> order) {
    for (final tube in order) {
      if (_clearTimers[tube] > 0) continue;
      if (b.locked && reservations.isBusy(tube)) continue;
      if (reservations.hasRoom(board, tube)) return tube;
    }
    return null;
  }

  /// Tubes in the order [b] reaches their drop points from where it is now.
  List<int> _orderAhead(_FlyingBlock b) {
    // A tapped block that has not reached the loop yet sits at its source.
    if (b.phase == _Phase.rising) return board.passOrder(b.source);
    final len = _metric.length;
    double ahead(int tube) {
      final a = (_dropDistance[tube] - b.checkpoint) % len;
      // A drop point right under the block is only reached after a lap.
      return a <= 0 ? len : a;
    }

    return [for (var i = 0; i < board.tubeCount; i++) i]
      ..sort((x, y) => ahead(x).compareTo(ahead(y)));
  }

  /// Plans every waiting block from its own place on the loop (rush).
  void _planFromPositions() => _planTargets(const [], orderFor: _orderAhead);

  int get _loopCount => _flying.where((b) => b.phase != _Phase.falling).length;

  void _publishHud() => _publishHudFor(level);

  void _publishHudFor(int shownLevel) {
    if (_resourcesDisposed) return;
    final value = HudState(
      level: shownLevel,
      loopCount: _board == null ? 0 : _loopCount,
      loopCapacity: mode.configFor(shownLevel).loopCapacity,
      status: status,
      blockedTaps: _blockedTaps,
      movesLeft: mode == GameMode.moves && _board != null ? _movesLeft : null,
      secondsLeft: mode == GameMode.timed && _board != null
          ? _timeLeft.ceil()
          : null,
      score: mode == GameMode.endless || mode == GameMode.rush ? _score : null,
    );
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) {
        if (!_resourcesDisposed) hud.value = value;
      });
    } else {
      hud.value = value;
    }
  }

  void _haptic(Future<void> Function() feedback) {
    if (haptics) feedback();
  }

  // ---------------------------------------------------------------- layout

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _relayout();
  }

  void _relayout() {
    if (_board != null && size.x > 0) _computeLayout(size);
  }

  void _computeLayout(Vector2 size) {
    final w = size.x;
    final h = size.y;
    const cardMargin = 8.0;
    const pathInset = cardMargin + 6 + _channelWidth / 2;
    const bottomRadius = 20.0;
    const rowGap = 28.0;
    // Space above and below a tube that still counts as a tap on it.
    const tapReach = 24.0;

    final n = board.tubeCount;
    final rows = n > 6 ? 2 : 1;
    // Wide screens: loop on the left half, tubes on the right half.
    final landscape = w > h;

    // The Flutter HUD sits below the status bar. Keep the board card
    // (which starts above the loop path) 12 dp below the HUD's loop bar.
    final loopTop = _topInset + _hudHeight + 12 + _channelWidth / 2 + 8;
    final cardTop = loopTop - _channelWidth / 2 - 8;
    final tubesBottom = h - max(24.0, _bottomInset + 16);
    if (landscape) {
      _loopRect = Rect.fromLTRB(
        pathInset,
        loopTop,
        w / 2 - 4 - 6 - _channelWidth / 2,
        max(loopTop + 120, tubesBottom + 20 - 8 - _channelWidth / 2),
      );
    } else {
      _loopRect = Rect.fromLTRB(
        pathInset,
        loopTop,
        w - pathInset,
        rows == 1 ? max(loopTop + 180, h * 0.44) : max(loopTop + 160, h * 0.38),
      );
    }
    final l = _loopRect;
    final topRadius = min(48.0, l.height / 3);

    // Clockwise on screen, starting on the bottom edge at the right corner.
    // The bottom corners are tight so the straight bottom edge is wide:
    // every tube needs its drop point on that straight edge.
    final straightLeft = l.left + bottomRadius;
    final straightRight = l.right - bottomRadius;
    // Path length up to the top center: bottom edge, bottom-left corner,
    // left edge, top-left corner, half the top edge.
    _spawnDistance =
        (straightRight - straightLeft) +
        pi / 2 * bottomRadius +
        (l.bottom - bottomRadius - l.top - topRadius) +
        pi / 2 * topRadius +
        (l.width / 2 - topRadius);
    _loopPath = ui.Path()
      ..moveTo(straightRight, l.bottom)
      ..lineTo(straightLeft, l.bottom)
      ..arcToPoint(
        Offset(l.left, l.bottom - bottomRadius),
        radius: const Radius.circular(bottomRadius),
      )
      ..lineTo(l.left, l.top + topRadius)
      ..arcToPoint(
        Offset(l.left + topRadius, l.top),
        radius: Radius.circular(topRadius),
      )
      ..lineTo(l.right - topRadius, l.top)
      ..arcToPoint(
        Offset(l.right, l.top + topRadius),
        radius: Radius.circular(topRadius),
      )
      ..lineTo(l.right, l.bottom - bottomRadius)
      ..arcToPoint(
        Offset(straightRight, l.bottom),
        radius: const Radius.circular(bottomRadius),
      )
      ..close();
    _metric = _loopPath.computeMetrics().first;

    // Drop points: one per tube along the straight bottom edge, tube 0 on
    // the left, so blocks pass the tubes in the order the rules expect.
    // Tube x order must equal tube index order (and so drop order).
    final span = straightRight - straightLeft - 8;
    final dropStep = min(76.0, span / (n - 1));
    final dropStart =
        (straightLeft + straightRight) / 2 - dropStep * (n - 1) / 2;
    _dropDistance = [
      for (var i = 0; i < n; i++) straightRight - (dropStart + dropStep * i),
    ];

    // Tube area: below the loop, or the right half on a wide screen.
    // Tubes are interleaved: tube i sits in row i % 2, one half step to
    // the right of tube i - 1, so x grows with the tube index. Tubes in
    // one row are [spacing] apart, and each tap column is that wide.
    final double tubeTop;
    final double step;
    final double firstX;
    Rect? tubeCard;
    if (landscape) {
      tubeCard = Rect.fromLTRB(
        w / 2 + 4,
        cardTop,
        w - cardMargin,
        tubesBottom + 20,
      );
      tubeTop = cardTop + 12 + tapReach;
      // The outermost tap columns reach half a row spacing past the
      // first and last tube.
      step = min(76.0, (tubeCard.width - 16) / (n - 1 + rows));
      _tubeAreaCenter = tubeCard.center.dx;
      firstX = _tubeAreaCenter - step * (n - 1) / 2;
    } else {
      // Every tube sits right under its drop point.
      tubeTop = l.bottom + 52;
      step = dropStep;
      _tubeAreaCenter = (straightLeft + straightRight) / 2;
      firstX = dropStart;
    }
    final spacing = step * rows;
    final tubeWidth = min(spacing * 0.74, 60.0);
    final available = tubesBottom - tubeTop - rowGap * (rows - 1);
    _slotHeight = max(
      4.0,
      min((available - _tubePad * 2 * rows) / (config.tubeSize * rows), 64.0),
    );
    final tubeHeight = _slotHeight * config.tubeSize + _tubePad * 2;

    _tubeRects = [];
    _tapRects = [];
    for (var i = 0; i < n; i++) {
      final row = i % rows;
      final cx = firstX + step * i;
      final top = tubeTop + row * (tubeHeight + rowGap);
      final rect = Rect.fromLTWH(
        cx - tubeWidth / 2,
        top,
        tubeWidth,
        tubeHeight,
      );
      _tubeRects.add(rect);
      // Two rows split the gap between them.
      final tapTop = row == 0 ? top - tapReach : top - rowGap / 2;
      final tapBottom = row == rows - 1
          ? rect.bottom + tapReach
          : rect.bottom + rowGap / 2;
      // Neighbors in a row share the exact same edge value.
      _tapRects.add(
        Rect.fromLTRB(
          firstX + step * (i - rows / 2),
          tapTop,
          firstX + step * (i + rows / 2),
          tapBottom,
        ),
      );
    }
    final lastBottom = _tubeRects.map((r) => r.bottom).reduce(max);
    _cardRects = landscape
        ? [
            Rect.fromLTRB(
              cardMargin,
              cardTop,
              w / 2 - 4,
              l.bottom + _channelWidth / 2 + 8,
            ),
            Rect.fromLTRB(
              tubeCard!.left,
              tubeCard.top,
              tubeCard.right,
              max(lastBottom + 20, l.bottom + _channelWidth / 2 + 8),
            ),
          ]
        : [Rect.fromLTRB(cardMargin, cardTop, w - cardMargin, lastBottom + 20)];
    _cardFills = [
      for (final card in _cardRects)
        Paint()
          ..shader = ui.Gradient.linear(card.topCenter, card.bottomCenter, [
            AppColors.glassFill,
            AppColors.glassFillLow,
          ]),
    ];
    final glyphSize = min(tubeWidth - _tubePad * 2, _slotHeight) * 0.5;
    _questionPainter = _glyph('?', glyphSize, null, _markColor(_hiddenColor));
    _lockPainter = _glyph(
      String.fromCharCode(Icons.lock_rounded.codePoint),
      glyphSize,
      Icons.lock_rounded,
      _markColor(_lockedColor),
    );
    _layoutReady = true;
    _bumpVersion();
    if (_loopPending) _spawnLoop();
  }

  /// Shape and glyph color on a block: dark on light blocks, light on
  /// dark blocks.
  static Color _markColor(Color block) => block.computeLuminance() > 0.35
      ? const Color(0x52000000)
      : const Color(0x66FFFFFF);

  TextPainter _glyph(
    String text,
    double fontSize,
    IconData? icon,
    Color color,
  ) => TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        fontFamily: icon?.fontFamily,
        package: icon?.fontPackage,
        color: color,
      ),
    ),
  )..layout();

  /// How far below its place a tube is during the slide-in.
  double _slideOffset(int tube) {
    final t = ((_slideTime - tube * _slideDelay) / _slideDuration).clamp(
      0.0,
      1.0,
    );
    if (t >= 1) return 0;
    final distance = size.y - _tubeRects[tube].top + 24;
    return distance * (1 - Curves.easeOutCubic.transform(t));
  }

  double _shakeOffset(int tube) {
    final t = _shake[tube];
    if (t <= 0) return 0;
    final progress = t / _shakeDuration;
    return sin((1 - progress) * pi * 8) * 7 * progress;
  }

  Rect _tubeRect(int tube) =>
      _tubeRects[tube].shift(Offset(_shakeOffset(tube), _slideOffset(tube)));

  Rect _slotRect(int tube, int slot) {
    final t = _tubeRect(tube);
    final bottom = t.bottom - _tubePad - slot * _slotHeight;
    return Rect.fromLTRB(
      t.left + _tubePad,
      bottom - _slotHeight + 2,
      t.right - _tubePad,
      bottom - 2,
    );
  }

  Offset _pointOnLoop(double distance, double lateral) {
    final len = _metric.length;
    final d = distance % len;
    final tangent = _metric.getTangentForOffset(d < 0 ? d + len : d)!;
    final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
    return tangent.position + normal * lateral;
  }

  // ----------------------------------------------------------------- input

  @override
  void onTapDown(TapDownEvent event) {
    if (!_layoutReady || _paused || status == GameStatus.loading) return;
    final tube = _tubeAt(event.canvasPosition.toOffset());
    if (tube != null) tapTube(tube);
  }

  /// Tube whose tap area contains [p], or null.
  int? _tubeAt(Offset p) {
    for (var i = 0; i < _tapRects.length; i++) {
      if (_tapRects[i].contains(p)) return i;
    }
    return null;
  }

  /// A tap on [tube] (also used by the accessibility layer). During the
  /// slide-in the last tap is queued and applied when the slide ends.
  void tapTube(int tube) {
    if (_paused || status != GameStatus.playing) return;
    if (tube < 0 || tube >= board.tubeCount) return;
    if (isSliding) {
      _queuedTap = tube;
      return;
    }
    _hintVisible = false;
    if (board.tubes[tube].isEmpty) return;

    // Rush: a bursting tube cannot be tapped.
    if (_clearTimers[tube] > 0) {
      _reject(tube);
      return;
    }

    // Locked top: the tube cannot be tapped.
    final run = board.topRunLength(tube);
    if (run == 0) {
      _reject(tube);
      return;
    }

    // Move limit: no taps left. The last blocks may still land.
    if (mode == GameMode.moves && _movesLeft == 0) {
      _reject(tube);
      return;
    }

    // Blocks are still falling into this tube; wait until they land.
    if (_fallingInto[tube] > 0) {
      _reject(tube);
      return;
    }

    // Loop has no room for the whole run: nothing is added.
    if (_loopCount + run > config.loopCapacity) {
      _blockedTaps++;
      _reject(tube);
      _publishHud();
      return;
    }

    // Blocks on the loop that were heading here look for a tube again
    // once the run has left.
    if (reservations.isBusy(tube)) _releaseTargets(tube);

    _haptic(HapticFeedback.lightImpact);
    sounds.tap();
    _taps++;
    if (mode == GameMode.moves) _movesLeft--;
    final topSlot = board.tubes[tube].length - 1;
    final slotRects = [
      for (var j = 0; j < run; j++) _slotRect(tube, topSlot - j),
    ];
    final colors = board.takeRun(tube);
    final start = _dropDistance[tube];
    final released = <_FlyingBlock>[];
    for (var j = 0; j < run; j++) {
      final spacing = j * (_blockLength + _blockGap);
      final block = _FlyingBlock(
        color: colors[j],
        source: tube,
        distance: start - spacing,
        checkOffset: spacing,
        particles: _makeParticles(colors[j]),
        phaseDelay: j * 0.08,
      )..whooshOnLoop = j == 0;
      final slotRect = slotRects[j];
      for (final p in block.particles) {
        p.from = Offset(
          slotRect.left + _random.nextDouble() * slotRect.width,
          slotRect.top + _random.nextDouble() * slotRect.height,
        );
      }
      _flying.add(block);
      released.add(block);
    }
    _waiting.insertAll(0, released);
    if (mode == GameMode.rush) {
      // Waiting spawns are planned again from their own place.
      _planFromPositions();
    } else {
      _planTargets(board.passOrder(tube));
    }
    _markProgress();
    _publishHud();
    _bumpVersion();
  }

  /// A tap that does nothing: the tube shakes.
  void _reject(int tube) {
    _shake[tube] = _shakeDuration;
    _haptic(HapticFeedback.mediumImpact);
    sounds.blocked();
  }

  List<_Particle> _makeParticles(int colorId, {bool locked = false}) {
    final rainbow = colorId == Board.rainbow && !locked;
    final hsl = locked
        ? HSLColor.fromColor(_lockedColor)
        : rainbow
        ? const HSLColor.fromAHSL(1, 0, 0.8, 0.62)
        : HSLColor.fromColor(style.palette[colorId]);
    return List.generate(_particlesPerBlock, (_) {
      final shade = (rainbow ? hsl.withHue(_random.nextDouble() * 360) : hsl)
          .withLightness(
            (hsl.lightness + (_random.nextDouble() - 0.5) * 0.18).clamp(0, 1),
          )
          .toColor();
      return _Particle(
        along: _random.nextDouble() * _blockLength,
        lateral: (_random.nextDouble() - 0.5) * (_channelWidth - 10),
        delay: _random.nextDouble() * 0.12,
        rotation: _random.nextDouble() * pi,
        color: shade.toARGB32(),
      );
    });
  }

  // ---------------------------------------------------------------- update

  @override
  void update(double dt) {
    if (_paused) return;
    super.update(dt);
    if (!_layoutReady || status == GameStatus.loading) return;
    final realDt = dt;
    dt = min(dt, 1 / 20);
    _time += dt;
    _slideTime += dt;
    final queued = _queuedTap;
    if (queued != null && !isSliding) {
      _queuedTap = null;
      tapTube(queued);
    }
    if (status == GameStatus.playing) _playTime += realDt;
    if (_comboLabelTime > 0) _comboLabelTime = max(0, _comboLabelTime - dt);

    for (var i = 0; i < _shake.length; i++) {
      if (_shake[i] > 0) _shake[i] = max(0, _shake[i] - dt);
      if (_pulse[i] > 0) _pulse[i] = max(0, _pulse[i] - dt);
    }
    _updateSparkles(dt);
    if (mode == GameMode.rush && status == GameStatus.playing) {
      _updateRush(dt);
    }

    final landed = <_FlyingBlock>[];
    for (final b in _flying) {
      b.phaseTime += dt;
      switch (b.phase) {
        case _Phase.rising:
          if (b.phaseTime >= b.phaseDelay + _riseDuration + 0.12) {
            b.phase = _Phase.looping;
            b.phaseTime = 0;
            b.lapMark = b.checkpoint;
            if (b.whooshOnLoop) sounds.whoosh();
          }
        case _Phase.looping:
          final before = b.checkpoint;
          b.distance += config.loopSpeed * dt;
          _checkDrops(b, before, b.checkpoint);
        case _Phase.falling:
          if (b.phaseTime >= _fallDuration + 0.12) landed.add(b);
      }
    }

    if (landed.isNotEmpty) {
      for (final b in landed) {
        final before = board.completeFlags();
        if (mode == GameMode.rush) {
          reservations.landBlock(board, b.target, b.color, locked: b.locked);
        } else {
          reservations.land(board, b.target);
        }
        _fallingInto[b.target]--;
        _flying.remove(b);
        // A completion opens a locked block, which can complete another.
        for (final tube in board.settleCompletions(before)) {
          _onTubeComplete(tube);
        }
      }
      _markProgress();
      _publishHud();
      _bumpVersion();
      if (_flying.isEmpty && !_loopPending) {
        _settled = _Snapshot(
          board: board.copy(),
          loop: const [],
          taps: _taps,
          movesLeft: _movesLeft,
        );
      }
    }

    if (mode != GameMode.rush &&
        status == GameStatus.playing &&
        _flying.isEmpty &&
        board.isWon) {
      status = GameStatus.won;
      _haptic(HapticFeedback.heavyImpact);
      sounds.win();
      onWon?.call(
        LevelResult(
          taps: _taps,
          solutionLength: _puzzle!.solutionLength,
          seconds: _playTime,
        ),
      );
      overlays.add('won');
      _publishHud();
    }

    _updateLimits(realDt);
    if (mode == GameMode.rush) {
      _checkOverflow();
    } else {
      _checkStuck();
    }
  }

  // ------------------------------------------------------------------ rush

  /// Rush: empties burst tubes and spawns new blocks.
  void _updateRush(double dt) {
    for (var i = 0; i < _clearTimers.length; i++) {
      if (_clearTimers[i] <= 0) continue;
      _clearTimers[i] = max(0, _clearTimers[i] - dt);
      if (_clearTimers[i] == 0) _clearTube(i);
    }

    if (!autoSpawn) return;
    _spawnTimer += dt;
    if (_spawnTimer < spawnInterval) return;
    // The group is picked once and held back until the loop has room
    // for all of it.
    final group = _nextSpawn ??= rollRushSpawn(
      _clears,
      config.colorCount,
      _random,
    );
    if (_loopCount + group.length > config.loopCapacity) return;
    _spawnTimer = 0;
    _nextSpawn = null;
    spawnGroup(group);
  }

  /// Rush: puts one block of [color] on the loop at the top center.
  @visibleForTesting
  void spawnBlock(int color, {bool locked = false}) =>
      spawnGroup([RushSpawn(color, locked: locked)]);

  /// Rush: puts [group] on the loop in a row, head at the top center.
  /// Each block drops into the first tube with room from where it is.
  @visibleForTesting
  void spawnGroup(List<RushSpawn> group) {
    final blocks = <_FlyingBlock>[];
    for (var i = 0; i < group.length; i++) {
      final spawn = group[i];
      final block = _FlyingBlock(
        color: spawn.color,
        source: -1,
        distance: _spawnDistance - i * (_blockLength + _blockGap),
        checkOffset: 0,
        particles: _makeParticles(spawn.color, locked: spawn.locked),
        phaseDelay: 0,
      );
      block
        ..phase = _Phase.looping
        ..spawned = true
        ..locked = spawn.locked
        ..lapMark = block.checkpoint;
      blocks.add(block);
    }
    _flying.addAll(blocks);
    _waiting.insertAll(0, blocks);
    _planFromPositions();
    _publishHud();
  }

  /// Rush: the blocks of a burst tube vanish. The board may grow, and
  /// waiting blocks may now land in the empty tube.
  void _clearTube(int tube) {
    board.tubes[tube].clear();
    board.hidden[tube].clear();
    board.locked[tube].clear();
    final next = LevelConfig.rush(_clears);
    if (next.tubeCount > board.tubeCount) {
      config = next;
      while (board.tubeCount < next.tubeCount) {
        board.addTube();
        reservations.addTube();
        _fallingInto = [..._fallingInto, 0];
        _shake = [..._shake, 0];
        _pulse = [..._pulse, 0];
        _pulseCombo = [..._pulseCombo, 1];
        _clearTimers = [..._clearTimers, 0];
      }
      _relayout();
    }
    _markProgress();
    _planFromPositions();
    _publishHud();
    _bumpVersion();
  }

  /// Rush game over: the loop is full, no tube is bursting, and every
  /// block went a full lap without landing. No tap fits a full loop.
  void _checkOverflow() {
    if (status != GameStatus.playing) return;
    if (_loopCount < config.loopCapacity) return;
    if (_clearTimers.any((t) => t > 0) || !_isIdle()) return;
    _fail('Belt overflow');
  }

  /// Move limit and timer checks.
  void _updateLimits(double dt) {
    if (status != GameStatus.playing) return;
    if (mode == GameMode.moves && _movesLeft == 0 && _isIdle()) {
      _fail('Out of moves');
    } else if (mode == GameMode.timed) {
      final shown = _timeLeft.ceil();
      _timeLeft = max(0, _timeLeft - dt);
      if (_timeLeft <= 0) {
        _fail('Time is up');
      } else if (_timeLeft.ceil() != shown) {
        _publishHud();
      }
    }
  }

  void _fail(String reason) {
    status = GameStatus.failed;
    failReason = reason;
    _haptic(HapticFeedback.heavyImpact);
    sounds.fail();
    overlays.remove('stuck');
    overlays.add('failed');
    _publishHud();
  }

  /// Nothing will change without a tap: no blocks move, or every block
  /// is on the loop and went a full lap since the last change.
  bool _isIdle() {
    final len = _metric.length;
    for (final b in _flying) {
      if (b.phase != _Phase.looping) return false;
      if (b.checkpoint - b.lapMark < len) return false;
    }
    return true;
  }

  void _checkDrops(_FlyingBlock b, double before, double after) {
    final tube = b.target;
    if (tube < 0) return;
    final len = _metric.length;
    final d = _dropDistance[tube];
    final at = d + ((after - d) / len).floorToDouble() * len;
    if (at <= before || at > after) return;

    final slot = board.tubes[tube].length + _fallingInto[tube];
    _fallingInto[tube]++;
    b.phase = _Phase.falling;
    b.phaseTime = 0;
    final slotRect = _slotRect(tube, slot);
    for (final p in b.particles) {
      p.from = _pointOnLoop(b.distance - p.along, p.lateral);
      p.to = Offset(
        slotRect.left + _random.nextDouble() * slotRect.width,
        slotRect.top + _random.nextDouble() * slotRect.height,
      );
    }
    _markProgress();
    _publishHud();
  }

  /// Something changed on the board: restart the stuck lap count.
  void _markProgress() {
    for (final b in _flying) {
      b.lapMark = b.checkpoint;
    }
    if (status == GameStatus.stuck) {
      status = GameStatus.playing;
      overlays.remove('stuck');
      _publishHud();
    }
  }

  /// Stuck: blocks are on the loop, each went a full lap without anything
  /// changing, and no tube can be tapped. Nothing can ever change again.
  void _checkStuck() {
    if (status != GameStatus.playing || _flying.isEmpty || !_isIdle()) return;
    final room = config.loopCapacity - _loopCount;
    for (var i = 0; i < board.tubeCount; i++) {
      final run = board.topRunLength(i);
      if (run > 0 && run <= room && !reservations.isBusy(i)) return;
    }
    status = GameStatus.stuck;
    overlays.add('stuck');
    _publishHud();
  }

  void _onTubeComplete(int tube) {
    _combo = _time - _lastCompleteTime <= _comboWindow ? _combo + 1 : 1;
    _lastCompleteTime = _time;
    if (_combo >= 2) _comboLabelTime = _comboLabelDuration;
    sounds.complete(_combo);

    _pulse[tube] = _pulseDuration;
    _pulseCombo[tube] = _combo;
    if (mode == GameMode.endless) {
      _score++;
      onScore?.call(_score);
    } else if (mode == GameMode.rush) {
      // Each clear scores its combo level; growth counts clears.
      _clears++;
      _score += _combo;
      onScore?.call(_score);
    }
    if (mode == GameMode.rush) _clearTimers[tube] = _clearDelay;
    _haptic(switch (_combo) {
      1 => HapticFeedback.lightImpact,
      2 => HapticFeedback.mediumImpact,
      _ => HapticFeedback.heavyImpact,
    });
    final rect = _tubeRects[tube];
    final origin = Offset(rect.center.dx, rect.top + 8);
    final sparkles = 18 + 12 * (min(_combo, 4) - 1);
    for (var i = 0; i < sparkles; i++) {
      final angle = -pi / 2 + (_random.nextDouble() - 0.5) * pi * 0.9;
      final speed = 90 + _random.nextDouble() * 160;
      _sparkles.add(
        _Sparkle(
          origin,
          Offset(cos(angle), sin(angle)) * speed,
          i.isEven ? AppColors.accentMint : AppColors.accentLavender,
        ),
      );
    }
  }

  void _updateSparkles(double dt) {
    for (final s in _sparkles) {
      s.velocity += Offset(0, 260 * dt);
      s.position += s.velocity * dt;
      s.life -= dt / 0.9;
    }
    _sparkles.removeWhere((s) => s.life <= 0);
  }

  // ---------------------------------------------------------------- render

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!_layoutReady) return;
    _renderCard(canvas);
    _renderLoop(canvas);
    _renderCenter(canvas);
    _renderTubes(canvas);
    _renderParticles(canvas);
    _renderBeltLocks(canvas);
    _renderSparkles(canvas);
    if (_comboLabelTime > 0 && _combo >= 2) _renderCombo(canvas);
    if (_hintVisible) _renderFinger(canvas);
  }

  /// 'Combo xN' above the tubes, fading out at the end.
  void _renderCombo(Canvas canvas) {
    if (_comboPainter == null || _comboPainterValue != _combo) {
      _comboPainterValue = _combo;
      _comboPainter = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(_textScale),
        text: TextSpan(
          text: 'Combo x$_combo',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.accentMint,
            shadows: [Shadow(blurRadius: 12, color: Color(0x99000000))],
          ),
        ),
      )..layout();
    }
    final painter = _comboPainter!;
    final alpha = (_comboLabelTime / 0.3).clamp(0.0, 1.0);
    final at = Offset(
      _tubeAreaCenter - painter.width / 2,
      _tubeRects.first.top - painter.height - 14,
    );
    canvas.saveLayer(
      at & painter.size,
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
    );
    painter.paint(canvas, at);
    canvas.restore();
  }

  // Frosted glass card behind the board.
  void _renderCard(Canvas canvas) {
    for (var i = 0; i < _cardRects.length; i++) {
      final card = RRect.fromRectAndRadius(
        _cardRects[i],
        const Radius.circular(AppRadii.card),
      );
      canvas.drawRRect(card, _cardFills[i]);
      canvas.drawRRect(card, _cardBorder);
    }
  }

  void _renderLoop(Canvas canvas) {
    canvas.drawPath(_loopPath, _loopBorder);
    canvas.drawPath(_loopPath, _loopWell);

    // Chevrons that slowly move with the flow, so the direction is clear.
    final len = _metric.length;
    final shift = (_time * 24) % _arrowSpacing;
    for (var d = shift; d < len; d += _arrowSpacing) {
      final tangent = _metric.getTangentForOffset(d)!;
      final dir = tangent.vector;
      final normal = Offset(-dir.dy, dir.dx);
      final tip = tangent.position + dir * 4;
      final back = tangent.position - dir * 4;
      canvas.drawPath(
        ui.Path()
          ..moveTo(back.dx + normal.dx * 5, back.dy + normal.dy * 5)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(back.dx - normal.dx * 5, back.dy - normal.dy * 5),
        _arrowPaint,
      );
    }
  }

  /// Inside the loop: the level 1 hint, or the loop counter.
  void _renderCenter(Canvas canvas) {
    final content = _hintVisible
        ? 'hint'
        : 'count:$_loopCount/${config.loopCapacity}';
    // The loop size is part of the key: the text must fit inside it.
    final key = '$content@${_loopRect.size}';
    if (key != _centerKey) {
      _centerKey = key;
      final TextSpan span;
      if (_hintVisible) {
        span = const TextSpan(
          style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.text),
          children: [
            TextSpan(text: 'Tap a tube to send its top color into the loop.\n'),
            TextSpan(
              text: 'Blocks drop into the best matching tube.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ],
        );
      } else {
        span = TextSpan(
          children: [
            TextSpan(
              text: '$_loopCount/${config.loopCapacity}\n',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const TextSpan(text: 'in loop', style: AppText.caption),
          ],
        );
      }
      // System text scale, shrunk when needed so the text fits the loop.
      final maxWidth = max(1.0, _loopRect.width - _channelWidth * 2 - 32);
      final maxHeight = max(1.0, _loopRect.height - _channelWidth * 2 - 8);
      var scale = _textScale;
      while (true) {
        final painter = TextPainter(
          text: span,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        );
        if (_hintVisible) {
          painter.layout(maxWidth: maxWidth);
        } else {
          // The counter must not wrap.
          painter.layout();
        }
        _centerPainter = painter;
        final fits = painter.height <= maxHeight && painter.width <= maxWidth;
        if (fits || scale <= 0.3) break;
        scale *= 0.9;
      }
    }
    final painter = _centerPainter!;
    painter.paint(
      canvas,
      _loopRect.center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _renderTubes(Canvas canvas) {
    for (var i = 0; i < _tubeRects.length; i++) {
      final rect = RRect.fromRectAndRadius(
        _tubeRect(i),
        const Radius.circular(AppRadii.tube),
      );

      if (_pulse[i] > 0) {
        final t = _pulse[i] / _pulseDuration;
        final strength = min(_pulseCombo[i], 4);
        _glowPaint
          ..color = AppColors.accentMint.withValues(alpha: 0.8 * t)
          ..strokeWidth = 6.0 + 3 * (strength - 1);
        canvas.drawRRect(
          rect.inflate((4 + 3 * strength) * (1 - t)),
          _glowPaint,
        );
      }

      canvas.drawRRect(rect, _tubeFill);
      _tubeOutline.color = board.isComplete(i)
          ? AppColors.accentMint
          : AppColors.glassBorder;
      canvas.drawRRect(rect, _tubeOutline);

      // Rush: the blocks of a burst tube fade out.
      final fading = _clearTimers[i] > 0;
      if (fading) {
        canvas.saveLayer(
          rect.outerRect,
          Paint()
            ..color = Color.fromRGBO(
              255,
              255,
              255,
              _clearTimers[i] / _clearDelay,
            ),
        );
      }
      final tube = board.tubes[i];
      for (var s = 0; s < tube.length; s++) {
        final slot = _slotRect(i, s);
        final r = RRect.fromRectAndRadius(
          slot,
          const Radius.circular(AppRadii.block),
        );
        final color = tube[s];
        final isLocked = board.isLocked(i, s);
        final isHidden = board.isHidden(i, s);
        if (isLocked) {
          _blockPaint.color = _lockedColor;
        } else if (isHidden) {
          _blockPaint.color = _hiddenColor;
        } else if (color == Board.rainbow) {
          _blockPaint
            ..color = const Color(0xFFFFFFFF)
            ..shader = ui.Gradient.sweep(
              slot.center,
              _rainbowColors,
              _rainbowStops,
            );
        } else {
          _blockPaint.color = style.palette[color];
        }
        canvas.drawRRect(r, _blockPaint);
        _blockPaint.shader = null;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(r.left + 3, r.top + 3, r.width - 6, 4),
            const Radius.circular(2),
          ),
          _shinePaint,
        );
        if (isLocked || isHidden) {
          final glyph = isLocked ? _lockPainter : _questionPainter;
          glyph.paint(
            canvas,
            slot.center - Offset(glyph.width / 2, glyph.height / 2 - 1),
          );
        } else if (color != Board.rainbow && style.showShapes) {
          _symbolPaint.color = _markColor(style.palette[color]);
          _drawSymbol(
            canvas,
            color,
            slot.center + const Offset(0, 2),
            min(slot.width, slot.height) * 0.36,
          );
        }
      }
      if (fading) canvas.restore();
    }
  }

  /// One shape per color, so colors can be told apart without color vision.
  void _drawSymbol(Canvas canvas, int colorId, Offset c, double size) {
    final h = size / 2;
    switch (colorId) {
      case 0: // circle
        canvas.drawCircle(c, h, _symbolPaint);
      case 1: // triangle
        canvas.drawPath(
          ui.Path()
            ..moveTo(c.dx, c.dy - h)
            ..lineTo(c.dx + h, c.dy + h * 0.8)
            ..lineTo(c.dx - h, c.dy + h * 0.8)
            ..close(),
          _symbolPaint,
        );
      case 2: // square
        canvas.drawRect(
          Rect.fromCenter(center: c, width: size * 0.85, height: size * 0.85),
          _symbolPaint,
        );
      case 3: // diamond
        canvas.drawPath(
          ui.Path()
            ..moveTo(c.dx, c.dy - h)
            ..lineTo(c.dx + h, c.dy)
            ..lineTo(c.dx, c.dy + h)
            ..lineTo(c.dx - h, c.dy)
            ..close(),
          _symbolPaint,
        );
      case 4: // star
        final path = ui.Path();
        for (var k = 0; k < 10; k++) {
          final radius = k.isEven ? h : h * 0.45;
          final a = -pi / 2 + k * pi / 5;
          final p = c + Offset(cos(a), sin(a)) * radius;
          k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), _symbolPaint);
      default: // plus
        final bar = size * 0.3;
        canvas.drawRect(
          Rect.fromCenter(center: c, width: size, height: bar),
          _symbolPaint,
        );
        canvas.drawRect(
          Rect.fromCenter(center: c, width: bar, height: size),
          _symbolPaint,
        );
    }
  }

  void _renderParticles(Canvas canvas) {
    final sprite = _sprite;
    if (sprite == null) return;
    var count = 0;
    for (final b in _flying) {
      count += b.particles.length;
    }
    if (count == 0) return;
    if (_colors.length < count) {
      _transforms = Float32List(count * 4);
      _rects = Float32List(count * 4);
      _colors = Int32List(count);
    }

    const scale = _particleSize / _spriteSize;
    const anchor = _spriteSize / 2;
    var n = 0;
    for (final b in _flying) {
      for (final p in b.particles) {
        final pos = _particlePosition(b, p);
        final c = cos(p.rotation) * scale;
        final s = sin(p.rotation) * scale;
        final i4 = n * 4;
        _transforms[i4] = c;
        _transforms[i4 + 1] = s;
        _transforms[i4 + 2] = pos.dx - c * anchor + s * anchor;
        _transforms[i4 + 3] = pos.dy - s * anchor - c * anchor;
        _rects[i4] = 0;
        _rects[i4 + 1] = 0;
        _rects[i4 + 2] = _spriteSize;
        _rects[i4 + 3] = _spriteSize;
        _colors[n] = p.color;
        n++;
      }
    }

    canvas.drawRawAtlas(
      sprite,
      Float32List.sublistView(_transforms, 0, n * 4),
      Float32List.sublistView(_rects, 0, n * 4),
      Int32List.sublistView(_colors, 0, n),
      BlendMode.modulate,
      null,
      _atlasPaint,
    );
  }

  /// Marks on blocks riding the loop: a lock glyph on locked blocks (rush),
  /// and the color's shape on the others, so they are not color-only.
  void _renderBeltLocks(Canvas canvas) {
    for (final b in _flying) {
      if (b.phase != _Phase.looping) continue;
      final at = _pointOnLoop(b.distance - _blockLength / 2, 0);
      if (!b.locked) {
        if (b.color != Board.rainbow && style.showShapes) {
          _symbolPaint.color = _markColor(style.palette[b.color]);
          _drawSymbol(canvas, b.color, at, _channelWidth * 0.5);
        }
        continue;
      }
      _lockPainter.paint(
        canvas,
        at - Offset(_lockPainter.width / 2, _lockPainter.height / 2),
      );
    }
  }

  void _renderSparkles(Canvas canvas) {
    for (final s in _sparkles) {
      _sparklePaint.color = s.color.withValues(alpha: s.life.clamp(0.0, 1.0));
      canvas.drawCircle(s.position, 2.5, _sparklePaint);
    }
  }

  void _renderFinger(Canvas canvas) {
    final rect = _tubeRects[_hintTube];
    final bob = sin(_time * 4) * 6;
    final at = Offset(
      rect.center.dx - _fingerPainter.width / 2 + 8,
      rect.top + 24 + bob,
    );
    _fingerPainter.paint(canvas, at);
  }

  Offset _particlePosition(_FlyingBlock b, _Particle p) {
    switch (b.phase) {
      case _Phase.rising:
        final target = _pointOnLoop(b.distance - p.along, p.lateral);
        final t = ((b.phaseTime - b.phaseDelay - p.delay) / _riseDuration)
            .clamp(0.0, 1.0);
        return Offset.lerp(p.from, target, Curves.easeOutCubic.transform(t))!;
      case _Phase.looping:
        // Small wobble so the stream looks loose, not rigid.
        final wobble = sin(b.distance * 0.05 + p.rotation * 6) * 1.5;
        return _pointOnLoop(b.distance - p.along, p.lateral + wobble);
      case _Phase.falling:
        final t = ((b.phaseTime - p.delay) / _fallDuration).clamp(0.0, 1.0);
        // Ease-in on y looks like gravity; linear x keeps the stream narrow.
        final x = p.from.dx + (p.to.dx - p.from.dx) * t;
        final y =
            p.from.dy + (p.to.dy - p.from.dy) * Curves.easeInQuad.transform(t);
        return Offset(x, y);
    }
  }

  Future<ui.Image> _buildSprite() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, _spriteSize, _spriteSize),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white,
    );
    final picture = recorder.endRecording();
    return picture.toImage(_spriteSize.toInt(), _spriteSize.toInt());
  }
}
