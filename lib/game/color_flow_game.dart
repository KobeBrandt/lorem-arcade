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

  /// Endless mode only: tubes sorted this run.
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

class ColorFlowGame extends FlameGame with TapCallbacks {
  ColorFlowGame({
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
  }) : _levelSource = levelSource ?? generateInBackground;

  final GameMode mode;
  final int initialLevel;

  /// Fixed generator seed (daily mode), or null for a random level.
  final int? seed;
  final LevelSource _levelSource;

  /// Called with the new level number when the player moves on,
  /// so the app can save progress.
  final ValueChanged<int>? onLevelReached;

  /// Endless mode: called with the run score whenever it goes up.
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

  /// Top system inset (status bar), set by the Flutter screen.
  double _topInset = 0;
  set topInset(double value) {
    if (value == _topInset) return;
    _topInset = value;
    _relayout();
  }

  // Layout.
  late Rect _loopRect;
  late Rect _cardRect;
  late ui.Path _loopPath;
  late ui.PathMetric _metric;
  late List<Rect> _tubeRects;
  late List<double> _tubeCenters;
  late List<double> _dropDistance;
  late double _tubeSpacing;
  late double _slotHeight;
  bool _layoutReady = false;

  // Cached paints.
  final Paint _cardFill = Paint();
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
  late ui.Image _sprite;
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

  /// True while the tubes slide in; taps are ignored until it ends.
  bool get isSliding =>
      _board != null &&
      _slideTime < _slideDelay * (board.tubeCount - 1) + _slideDuration;

  /// True when no blocks are moving. Used by tests.
  @visibleForTesting
  bool get isSettled => _flying.isEmpty;

  // Transparent: the Flutter screen paints the gradient background.
  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    _sprite = await _buildSprite();
    await startLevel(initialLevel);
  }

  /// Builds a new puzzle for [newLevel] and starts it. With [save], the
  /// level is reported to [onLevelReached] once it has started.
  Future<void> startLevel(int newLevel, {bool save = false}) async {
    final token = ++_loadToken;
    status = GameStatus.loading;
    _requestedLevel = newLevel;
    _removeResultOverlays();
    _publishHudFor(newLevel);

    final newConfig = mode.configFor(newLevel);
    final Puzzle puzzle;
    try {
      puzzle = await _levelSource(newConfig, seed);
    } catch (_) {
      if (token != _loadToken) return;
      _buildFailed = true;
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

  void _removeResultOverlays() {
    overlays.remove('won');
    overlays.remove('stuck');
    overlays.remove('failed');
  }

  void _begin() {
    final puzzle = _puzzle!;
    final newBoard = puzzle.board.copy();
    _board = newBoard;
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
    _movesLeft = moveLimitFor(puzzle.solutionLength);
    _timeLeft = secondsFor(config).toDouble();
    _hintVisible = mode == GameMode.levels && level == 1;
    if (_hintVisible) {
      final path = Solver(config.loopCapacity, 60000).solve(newBoard);
      _hintTube = (path == null || path.isEmpty) ? 0 : path.first;
    }
    _removeResultOverlays();
    status = GameStatus.playing;
    _loopPending = puzzle.loop.isNotEmpty;
    _relayout();
    _publishHud();
  }

  /// Belt-full start: the loop blocks are spread evenly around the loop.
  void _spawnLoop() {
    _loopPending = false;
    final loop = _puzzle!.loop;
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
  /// solver: the first waiting block that fits a tube takes the best one,
  /// then the search starts again, until no waiting block fits. A block
  /// only drops at its target, so the game always matches the solver.
  void _planTargets(List<int> order) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final b in _waiting) {
        final target = reservations.chooseTube(board, order, b.color);
        if (target == null) continue;
        reservations.reserve(target, b.color);
        b.target = target;
        _waiting.remove(b);
        changed = true;
        break;
      }
    }
  }

  int get _loopCount => _flying.where((b) => b.phase != _Phase.falling).length;

  void _publishHud() => _publishHudFor(level);

  void _publishHudFor(int shownLevel) {
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
      score: mode == GameMode.endless ? _score : null,
    );
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding.addPostFrameCallback((_) => hud.value = value);
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

    // HUD: title row (56) + gap + loop bar (8) + gap, below the status bar.
    final loopTop = _topInset + 110;
    _loopRect = Rect.fromLTRB(
      pathInset,
      loopTop,
      w - pathInset,
      max(loopTop + 180, h * 0.44),
    );
    final l = _loopRect;
    final topRadius = min(48.0, l.height / 3);

    // Clockwise on screen, starting on the bottom edge at the right corner.
    // The bottom corners are tight so the straight bottom edge is wide:
    // every tube needs its drop point on that straight edge.
    final straightLeft = l.left + bottomRadius;
    final straightRight = l.right - bottomRadius;
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

    // Tubes use the full straight edge; each tap column is one spacing wide.
    final n = board.tubeCount;
    final span = straightRight - straightLeft - 8;
    _tubeSpacing = min(76.0, span / (n - 1));
    final groupStart =
        (straightLeft + straightRight) / 2 - _tubeSpacing * (n - 1) / 2;
    final tubeWidth = min(_tubeSpacing * 0.74, 60.0);

    final tubeTop = l.bottom + 52;
    final maxTubeHeight = h - 72 - tubeTop;
    _slotHeight = min((maxTubeHeight - _tubePad * 2) / config.tubeSize, 64.0);
    final tubeHeight = _slotHeight * config.tubeSize + _tubePad * 2;

    _tubeRects = [];
    _tubeCenters = [];
    _dropDistance = [];
    for (var i = 0; i < n; i++) {
      final cx = groupStart + _tubeSpacing * i;
      _tubeCenters.add(cx);
      _tubeRects.add(
        Rect.fromLTWH(cx - tubeWidth / 2, tubeTop, tubeWidth, tubeHeight),
      );
      _dropDistance.add(straightRight - cx);
    }
    _cardRect = Rect.fromLTRB(
      cardMargin,
      l.top - _channelWidth / 2 - 8,
      w - cardMargin,
      _tubeRects.first.bottom + 20,
    );
    _cardFill.shader = ui.Gradient.linear(
      _cardRect.topCenter,
      _cardRect.bottomCenter,
      [AppColors.glassFill, AppColors.glassFillLow],
    );
    final glyphSize = min(tubeWidth - _tubePad * 2, _slotHeight) * 0.5;
    _questionPainter = _glyph('?', glyphSize, null);
    _lockPainter = _glyph(
      String.fromCharCode(Icons.lock_rounded.codePoint),
      glyphSize,
      Icons.lock_rounded,
    );
    _layoutReady = true;
    if (_loopPending) _spawnLoop();
  }

  TextPainter _glyph(String text, double fontSize, IconData? icon) =>
      TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            fontFamily: icon?.fontFamily,
            package: icon?.fontPackage,
            color: const Color(0xCCFFFFFF),
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
    if (!_layoutReady || status == GameStatus.loading) return;
    final tube = _tubeAt(event.canvasPosition.toOffset());
    if (tube != null) tapTube(tube);
  }

  /// Tube whose tap column contains [p], or null.
  int? _tubeAt(Offset p) {
    final top = _tubeRects.first.top - 24;
    final bottom = _tubeRects.first.bottom + 24;
    if (p.dy < top || p.dy > bottom) return null;
    for (var i = 0; i < _tubeCenters.length; i++) {
      if ((p.dx - _tubeCenters[i]).abs() <= _tubeSpacing / 2) return i;
    }
    return null;
  }

  @visibleForTesting
  void tapTube(int tube) {
    if (status != GameStatus.playing || isSliding) return;
    _hintVisible = false;
    if (board.tubes[tube].isEmpty) return;

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
    if (reservations.isBusy(tube)) {
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
    _planTargets(board.passOrder(tube));
    _markProgress();
    _publishHud();
  }

  /// A tap that does nothing: the tube shakes.
  void _reject(int tube) {
    _shake[tube] = _shakeDuration;
    _haptic(HapticFeedback.mediumImpact);
    sounds.blocked();
  }

  List<_Particle> _makeParticles(int colorId) {
    final rainbow = colorId == Board.rainbow;
    final hsl = rainbow
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
    super.update(dt);
    if (!_layoutReady || status == GameStatus.loading) return;
    final realDt = dt;
    dt = min(dt, 1 / 20);
    _time += dt;
    _slideTime += dt;
    if (status == GameStatus.playing) _playTime += realDt;
    if (_comboLabelTime > 0) _comboLabelTime = max(0, _comboLabelTime - dt);

    for (var i = 0; i < _shake.length; i++) {
      if (_shake[i] > 0) _shake[i] = max(0, _shake[i] - dt);
      if (_pulse[i] > 0) _pulse[i] = max(0, _pulse[i] - dt);
    }
    _updateSparkles(dt);

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
        reservations.land(board, b.target);
        _fallingInto[b.target]--;
        _flying.remove(b);
        // A completion opens a locked block, which can complete another.
        for (final tube in board.settleCompletions(before)) {
          _onTubeComplete(tube);
        }
      }
      _markProgress();
      _publishHud();
    }

    if (status == GameStatus.playing && _flying.isEmpty && board.isWon) {
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
    _checkStuck();
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
    }
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
      _cardRect.center.dx - painter.width / 2,
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
    final card = RRect.fromRectAndRadius(
      _cardRect,
      const Radius.circular(AppRadii.card),
    );
    canvas.drawRRect(card, _cardFill);
    canvas.drawRRect(card, _cardBorder);
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
    final key = _hintVisible
        ? 'hint'
        : 'count:$_loopCount/${config.loopCapacity}';
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
      _centerPainter = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _loopRect.width - _channelWidth * 2 - 32);
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
          _drawSymbol(
            canvas,
            color,
            slot.center + const Offset(0, 2),
            min(slot.width, slot.height) * 0.36,
          );
        }
      }
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
      _sprite,
      Float32List.sublistView(_transforms, 0, n * 4),
      Float32List.sublistView(_rects, 0, n * 4),
      Int32List.sublistView(_colors, 0, n),
      BlendMode.modulate,
      null,
      _atlasPaint,
    );
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
