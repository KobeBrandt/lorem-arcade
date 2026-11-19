import 'dart:math';
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../arcade/arcade_level_game.dart';
import 'gate_drop_layout.dart';
import 'gate_drop_levels.dart';
import 'gate_drop_painter.dart';
import 'gate_drop_shaft.dart';

/// Gate Drop: pour balls through multiplier gates to stop a horde.
///
/// A cup at the top of the shaft follows the finger and pours balls while
/// the finger is down. Gates multiply the balls, locks swallow balls until
/// they open, and every ball that reaches the pipe at the bottom fires a
/// shot at the horde for 1 damage. The level is won when the horde has no
/// hit points left. It is lost when the horde reaches the wall, or when
/// the cup and the shaft are empty and the horde still stands.
///
/// Stars come from the balls left in the cup at the win, see
/// [gateDropStars].
class GateDropGame extends ArcadeLevelGame with DragCallbacks {
  GateDropGame(super.setup) : layout = buildGateDropLevel(setup.level) {
    shaft = GateDropShaft(layout, seed: setup.level);
    cupBalls = layout.balls;
    hordeHp = layout.hordeHp;
    gateFlash = Float64List(layout.gates.length);
    _updateStatus();
  }

  /// Balls poured per second while the finger is down.
  static const double pourRate = 12;

  /// Seconds a shot streak takes from the cannon to the horde.
  static const double shotTime = 0.22;
  static const int maxShots = 48;

  /// Widest layout on tablets, in logical pixels.
  static const double maxWidth = 480;

  final GateDropLayout layout;
  late final GateDropShaft shaft;
  late final Float64List gateFlash;
  final GateDropPainter _painter = GateDropPainter();

  /// Balls still in the cup.
  late int cupBalls;

  /// Hit points the horde has left.
  late int hordeHp;

  /// How far the horde walked, from 0 (start) to 1 (at the wall).
  double hordeProgress = 0;

  /// Cup position in shaft units.
  double cupX = shaftWidth / 2;
  bool pouring = false;

  /// Real time since the start, for animations and rate limits.
  double clock = 0;

  // Screen layout, set in onGameResize.
  Rect stripRect = Rect.zero;
  Rect shaftRect = Rect.zero;
  double scale = 0;

  // Shot streaks in a ring buffer: age (negative when free) and target.
  final Float64List shotAge = Float64List(maxShots)..fillRange(0, maxShots, -1);
  final Float64List shotLane = Float64List(maxShots);
  int _nextShot = 0;
  final Random _fxRandom = Random(7);

  double _accumulator = 0;
  double _pourClock = 0;
  bool _poured = false;
  int? _pointer;
  int _seenWeight = 0;
  int _seenBalls = 0;
  int _seenLocks = 0;
  int _seenBig = 0;
  double _lastComplete = -10;
  double _lastBig = -10;
  double _lastHaptic = -10;
  double _lastBlocked = -10;
  int _combo = 0;
  int _statusCup = -1;
  int _statusHp = -1;

  @override
  bool get hasProgress => _poured;

  @override
  Color backgroundColor() => const Color(0x00000000);

  /// Screen x of the strongest gate. The test player aims here.
  @visibleForTesting
  double get bestPourX => toScreenX(layout.bestX);

  double toScreenX(double sx) => shaftRect.left + sx * scale;
  double toScreenY(double sy) => shaftRect.top + sy * scale;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    const pad = 12.0;
    final width = min(size.x, maxWidth);
    final left = (size.x - width) / 2;
    final stripHeight = (size.y * 0.19).clamp(90.0, 140.0);
    stripRect = Rect.fromLTWH(left + pad, pad, width - pad * 2, stripHeight);
    final top = stripRect.bottom + 14;
    final availWidth = width - pad * 2 - 12;
    final availHeight = size.y - top - pad - 6;
    scale = max(0.1, min(availWidth / shaftWidth, availHeight / shaftHeight));
    final w = shaftWidth * scale;
    shaftRect = Rect.fromLTWH(
      size.x / 2 - w / 2,
      top + 6,
      w,
      shaftHeight * scale,
    );
    _painter.layout(this);
  }

  /// Starts pouring with the cup at screen x [screenX].
  @visibleForTesting
  void startPour(double screenX) {
    if (result.value != null) return;
    moveCup(screenX);
    if (cupBalls <= 0) {
      if (clock - _lastBlocked > 0.4) {
        _lastBlocked = clock;
        setup.sounds.blocked();
      }
      return;
    }
    if (!pouring) {
      setup.sounds.tap();
      // The first ball drops at once.
      _pourClock = 1 / pourRate;
    }
    pouring = true;
  }

  /// Moves the cup to screen x [screenX].
  void moveCup(double screenX) {
    if (scale <= 0) return;
    final sx = (screenX - shaftRect.left) / scale;
    cupX = sx.clamp(7.0, shaftWidth - 7);
  }

  /// Stops pouring.
  @visibleForTesting
  void stopPour() => pouring = false;

  bool _inShaft(Vector2 p) =>
      p.y >= shaftRect.top - 12 &&
      p.y <= shaftRect.bottom + 12 &&
      p.x >= stripRect.left - 12 &&
      p.x <= stripRect.right + 12;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_pointer != null || !_inShaft(event.localPosition)) return;
    _pointer = event.pointerId;
    startPour(event.localPosition.x);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _pointer) return;
    moveCup(event.localEndPosition.x);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _pointer) return;
    _pointer = null;
    stopPour();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (event.pointerId != _pointer) return;
    _pointer = null;
    stopPour();
  }

  @override
  void update(double dt) {
    super.update(dt);
    final frame = min(dt, 0.1);
    clock += frame;
    for (var i = 0; i < maxShots; i++) {
      if (shotAge[i] < 0) continue;
      shotAge[i] += frame;
      if (shotAge[i] > shotTime + 0.12) shotAge[i] = -1;
    }
    for (var g = 0; g < gateFlash.length; g++) {
      if (gateFlash[g] > 0) gateFlash[g] = max(0, gateFlash[g] - frame * 1.5);
    }
    if (result.value != null) return;
    _accumulator += frame;
    while (_accumulator >= GateDropShaft.step && result.value == null) {
      _accumulator -= GateDropShaft.step;
      _fixedStep();
    }
    _updateStatus();
  }

  void _fixedStep() {
    const dt = GateDropShaft.step;
    if (pouring) {
      if (cupBalls <= 0) {
        pouring = false;
      } else {
        _pourClock += dt;
        const interval = 1 / pourRate;
        while (_pourClock >= interval && cupBalls > 0) {
          if (!shaft.drop(cupX)) {
            _pourClock = interval;
            break;
          }
          _pourClock -= interval;
          cupBalls--;
          _poured = true;
        }
      }
    }
    shaft.tick();
    hordeProgress += dt / layout.hordeSeconds;

    final damage = shaft.collectedWeight - _seenWeight;
    if (damage > 0) {
      _seenWeight = shaft.collectedWeight;
      hordeHp = max(0, hordeHp - damage);
    }
    final shots = shaft.collectedBalls - _seenBalls;
    if (shots > 0) {
      _seenBalls = shaft.collectedBalls;
      for (var s = 0; s < min(shots, 3); s++) {
        _fireShot();
      }
    }
    if (shaft.locksOpened > _seenLocks) {
      _seenLocks = shaft.locksOpened;
      if (shaft.lastOpened >= 0) gateFlash[shaft.lastOpened] = 1;
      _celebrate();
    }
    if (shaft.bigHits > _seenBig) {
      _seenBig = shaft.bigHits;
      if (clock - _lastBig > 1.5) {
        _lastBig = clock;
        _celebrate();
      }
    }

    if (hordeHp <= 0) {
      finish(ArcadeResult.won(gateDropStars(cupBalls, layout.balls)));
    } else if (hordeProgress >= 1) {
      hordeProgress = 1;
      finish(const ArcadeResult.lost('The horde broke through'));
    } else if (cupBalls <= 0 && shaft.count == 0) {
      finish(const ArcadeResult.lost('Out of balls'));
    }
  }

  void _fireShot() {
    // Reuse the oldest slot when all are busy.
    final i = _nextShot;
    _nextShot = (_nextShot + 1) % maxShots;
    shotAge[i] = 0;
    shotLane[i] = _fxRandom.nextDouble();
  }

  void _celebrate() {
    _combo = clock - _lastComplete < 2 ? min(_combo + 1, 4) : 1;
    if (clock - _lastComplete >= 0.5) {
      _lastComplete = clock;
      setup.sounds.complete(_combo);
    }
    if (setup.haptics && clock - _lastHaptic >= 0.15) {
      _lastHaptic = clock;
      HapticFeedback.lightImpact();
    }
  }

  void _updateStatus() {
    if (_statusCup == cupBalls && _statusHp == hordeHp) return;
    _statusCup = cupBalls;
    _statusHp = hordeHp;
    status.value = 'Balls $cupBalls · Horde $hordeHp';
  }

  @override
  void render(Canvas canvas) {
    if (scale > 0) _painter.render(canvas, this);
    super.render(canvas);
  }
}
