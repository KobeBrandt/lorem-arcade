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
/// the finger is down. Gates multiply the balls, traps halve them, refill
/// gates send them back to the cup, bumpers kick them sideways and locks
/// swallow balls until they open. Every ball that reaches the pipe at
/// the bottom fires a shot at the horde for 1 damage (2 in a fever).
/// The horde starts to walk with the first
/// pour, and big bursts of damage push it back.
///
/// Multiplies fill the fever meter. A full meter starts a fever: for a
/// few seconds every shot deals double damage.
///
/// The level is won when the horde has no hit points left. It is lost
/// when the horde reaches the wall, or when the cup and the shaft are
/// empty and the horde still stands. A boss level shields the horde until
/// the shield lock opens. A bonus level has no walking horde: pour the
/// whole cup, and the stars come from the damage, see
/// [gateDropBonusStars]. Other levels give stars by the balls left in
/// the cup, see [gateDropStars].
///
/// The endless run ([GateDropGame.endless]) plays wave after wave on new
/// shafts. A beaten horde tops the cup up to full. The run ends like a
/// lost level; its score is the waves cleared.
class GateDropGame extends ArcadeLevelGame with DragCallbacks {
  /// One level of the level list.
  GateDropGame(super.setup) : endless = false, runSeed = 0 {
    _load(buildGateDropLevel(setup.level));
    cupBalls = startBalls;
    _updateStatus();
  }

  /// An endless run. [runSeed] picks the shafts; a new run gets a random
  /// one.
  GateDropGame.endless(super.setup, {int? runSeed})
    : endless = true,
      runSeed = runSeed ?? Random().nextInt(1 << 20) {
    _load(buildGateDropWave(1, this.runSeed));
    cupBalls = startBalls;
    _updateStatus();
  }

  /// Glow of a gate that just acted on balls (a lock that opens glows
  /// at 1).
  static const double multiplyFlash = 0.45;

  /// Multiplies that fill the fever meter.
  static const int feverPoints = 60;

  /// Seconds one fever lasts.
  static const double feverSeconds = 4;

  /// Seconds a shot streak takes from the cannon to the horde.
  static const double shotTime = 0.22;
  static const int maxShots = 48;

  /// Floating texts (gate pop-ups and damage numbers) at the same time.
  static const int maxPops = 32;

  /// Sparks of a burst at the same time.
  static const int maxSparks = 96;

  /// Damage in one burst window that pushes the horde back, as a share
  /// of its hit points.
  static const double knockbackShare = 0.1;

  /// Seconds of one burst window.
  static const double knockbackWindow = 1.5;

  /// How far one knockback pushes the horde back, as a share of its walk.
  static const double knockbackPush = 0.03;

  /// Multiplies in a row that raise the combo sound by one step.
  static const int comboStep = 8;

  /// Highest combo sound step.
  static const int maxCombo = 5;

  /// Widest layout on tablets, in logical pixels.
  static const double maxWidth = 480;

  final bool endless;
  final int runSeed;

  late GateDropLayout layout;
  late GateDropShaft shaft;
  late Float64List gateFlash;
  final GateDropPainter _painter = GateDropPainter();

  /// Balls in the cup at the start of the level or wave.
  late int startBalls;

  /// Balls still in the cup.
  int cupBalls = 0;

  /// Hit points the horde has left.
  late int hordeHp;

  /// Damage dealt in this level or wave.
  int damageDealt = 0;

  /// The current wave of an endless run (1-based); 1 for a level.
  int wave = 1;

  /// Waves beaten in an endless run.
  int wavesCleared = 0;

  /// How far the horde walked, from 0 (start) to 1 (at the wall).
  double hordeProgress = 0;

  /// Fever meter, from 0 to [feverPoints].
  double feverMeter = 0;

  /// Seconds of fever left; 0 when there is no fever.
  double feverLeft = 0;

  bool get inFever => feverLeft > 0;

  /// Times big bursts pushed the horde back.
  int knockbacks = 0;

  /// Current step of the combo sound (0 to [maxCombo]).
  int comboLevel = 0;

  /// Cup position in shaft units.
  double cupX = shaftWidth / 2;
  bool pouring = false;

  /// Real time since the start, for animations and rate limits.
  double clock = 0;

  /// Screen shake, from 0 (still) to 1 (strong). It fades out.
  double shake = 0;

  /// Hit flash of the horde, from 0 to 1. It fades out.
  double hordeFlash = 0;

  /// Hit points the slow HP bar shows; it trails [hordeHp].
  double ghostHp = 0;

  /// Seconds the 'Wave N' or 'Shield down' banner still shows.
  double bannerLeft = 0;
  String banner = '';

  // Screen layout, set in onGameResize.
  Rect stripRect = Rect.zero;
  Rect shaftRect = Rect.zero;
  double scale = 0;

  // Shot streaks in a ring buffer: age (negative when free) and target.
  final Float64List shotAge = Float64List(maxShots)..fillRange(0, maxShots, -1);
  final Float64List shotLane = Float64List(maxShots);
  int _nextShot = 0;

  // Floating texts in a ring buffer, in screen units. Age is negative when
  // the slot is free. Tone: 0 gate color, 1 trap, 2 refill, 3 damage,
  // 4 jackpot, 5 banner-like (fever, shield).
  final Float64List popX = Float64List(maxPops);
  final Float64List popY = Float64List(maxPops);
  final Float64List popAge = Float64List(maxPops)..fillRange(0, maxPops, -1);
  final Float64List popSize = Float64List(maxPops);
  final Int32List popTone = Int32List(maxPops);
  final Int32List popGate = Int32List(maxPops);
  final List<String> popText = List.filled(maxPops, '');
  int _nextPop = 0;

  /// Seconds a floating text lives.
  static const double popLife = 0.8;

  // Sparks of bursts, in screen units.
  final Float64List sparkX = Float64List(maxSparks);
  final Float64List sparkY = Float64List(maxSparks);
  final Float64List sparkVx = Float64List(maxSparks);
  final Float64List sparkVy = Float64List(maxSparks);
  final Float64List sparkAge = Float64List(maxSparks)
    ..fillRange(0, maxSparks, -1);
  final List<Color> sparkColor = List.filled(
    maxSparks,
    const Color(0xFFFFFFFF),
  );
  int _nextSpark = 0;

  /// Seconds a banner shows.
  static const double bannerTime = 1.4;

  /// Seconds a spark lives.
  static const double sparkLife = 0.6;

  final Random _fxRandom = Random(7);

  double _accumulator = 0;
  double _pourClock = 0;
  bool _poured = false;
  bool _pouredThisWave = false;
  int? _pointer;
  int _seenWeight = 0;
  int _seenBalls = 0;
  int _seenLocks = 0;
  int _seenBig = 0;
  int _seenRefill = 0;
  bool _seenShield = false;
  double _simTime = 0;
  double _lastCombo = -10;
  double _lastMultiply = -10;
  int _comboHits = 0;
  double _lastHaptic = -10;
  double _lastBlocked = -10;
  double _burstStart = -10;
  int _burstDamage = 0;
  int _pendingDamage = 0;
  double _lastDamagePop = -10;
  int _statusCup = -1;
  int _statusHp = -1;
  int _statusWave = -1;
  int _statusDamage = -1;
  late Int32List _seenGateHits;
  late Int32List _popPending;
  late Float64List _lastGatePop;

  @override
  bool get hasProgress => _poured;

  @override
  Color backgroundColor() => const Color(0x00000000);

  bool get isBonus => layout.kind == LevelKind.bonus;
  bool get isBoss => layout.kind == LevelKind.boss;

  /// Balls poured per second while the finger is down.
  static const double pourRate = 12;

  /// Screen x of the strongest gate. The test player aims here.
  @visibleForTesting
  double get bestPourX => toScreenX(layout.bestX);

  double toScreenX(double sx) => shaftRect.left + sx * scale;
  double toScreenY(double sy) => shaftRect.top + sy * scale;

  /// Screen x where the horde walk starts.
  double get hordeStartX => stripRect.left + 18;

  /// Screen x of the wall the horde must not reach.
  double get wallX => stripRect.right - 22;

  /// Screen x of the front of the horde.
  double get hordeFrontX =>
      hordeStartX + (wallX - 10 - hordeStartX) * hordeProgress;

  /// Sets up [next] as the current shaft.
  void _load(GateDropLayout next) {
    layout = next;
    shaft = GateDropShaft(layout, seed: setup.level + wave * 13);
    startBalls = layout.balls;
    hordeHp = layout.hordeHp;
    ghostHp = hordeHp.toDouble();
    damageDealt = 0;
    hordeProgress = 0;
    gateFlash = Float64List(layout.gates.length);
    _seenGateHits = Int32List(layout.gates.length);
    _popPending = Int32List(layout.gates.length);
    _lastGatePop = Float64List(layout.gates.length)
      ..fillRange(0, layout.gates.length, -10);
    _seenWeight = 0;
    _seenBalls = 0;
    _seenLocks = 0;
    _seenBig = 0;
    _seenRefill = 0;
    _seenShield = shaft.shieldUp;
    _burstDamage = 0;
    _burstStart = -10;
    _pouredThisWave = false;
    _statusHp = -1;
    _updateStatus();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    const pad = 12.0;
    final width = min(size.x, maxWidth);
    final left = (size.x - width) / 2;
    final stripHeight = (size.y * 0.19).clamp(90.0, 140.0);
    stripRect = Rect.fromLTWH(left + pad, pad, width - pad * 2, stripHeight);
    final top = stripRect.bottom + 18;
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

  /// A pause ends the pour: the finger may leave the screen while the
  /// pause card is up, and the drag end would then never arrive.
  @override
  void pauseEngine() {
    super.pauseEngine();
    _pointer = null;
    stopPour();
  }

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
    _updateEffects(frame);
    if (result.value != null) return;
    _accumulator += frame;
    while (_accumulator >= GateDropShaft.step && result.value == null) {
      _accumulator -= GateDropShaft.step;
      _fixedStep();
    }
    _updateStatus();
  }

  void _updateEffects(double frame) {
    for (var i = 0; i < maxShots; i++) {
      if (shotAge[i] < 0) continue;
      shotAge[i] += frame;
      if (shotAge[i] > shotTime + 0.12) shotAge[i] = -1;
    }
    for (var i = 0; i < maxPops; i++) {
      if (popAge[i] < 0) continue;
      popAge[i] += frame;
      if (popAge[i] > popLife) popAge[i] = -1;
    }
    for (var i = 0; i < maxSparks; i++) {
      if (sparkAge[i] < 0) continue;
      sparkAge[i] += frame;
      if (sparkAge[i] > sparkLife) {
        sparkAge[i] = -1;
        continue;
      }
      sparkVy[i] += 260 * frame;
      sparkX[i] += sparkVx[i] * frame;
      sparkY[i] += sparkVy[i] * frame;
    }
    for (var g = 0; g < gateFlash.length; g++) {
      if (gateFlash[g] > 0) gateFlash[g] = max(0, gateFlash[g] - frame * 1.5);
    }
    shake = max(0, shake - frame * 3);
    hordeFlash = max(0, hordeFlash - frame * 5);
    bannerLeft = max(0, bannerLeft - frame);
    // The ghost bar waits a moment, then slides down to the real HP.
    if (ghostHp > hordeHp) {
      ghostHp = max(
        hordeHp.toDouble(),
        ghostHp - max(1.0, (ghostHp - hordeHp) * 3) * frame,
      );
    } else {
      ghostHp = hordeHp.toDouble();
    }
  }

  void _fixedStep() {
    const dt = GateDropShaft.step;
    _simTime += dt;
    if (pouring) {
      if (cupBalls <= 0) {
        pouring = false;
      } else {
        _pourClock += dt;
        final interval = 1 / pourRate;
        while (_pourClock >= interval && cupBalls > 0) {
          if (!shaft.drop(cupX)) {
            _pourClock = interval;
            break;
          }
          _pourClock -= interval;
          cupBalls--;
          _poured = true;
          _pouredThisWave = true;
        }
      }
    }
    shaft.tick();
    // The horde waits for the first pour, so reading the shaft is free.
    // A bonus level has no walking horde.
    if (_pouredThisWave && !isBonus) {
      hordeProgress += dt / layout.hordeSeconds;
    }
    if (feverLeft > 0) feverLeft = max(0, feverLeft - dt);

    _readGates();

    final refilled = shaft.refilledWeight - _seenRefill;
    if (refilled > 0) {
      _seenRefill = shaft.refilledWeight;
      cupBalls += refilled;
    }

    final base = shaft.damageWeight - _seenWeight;
    if (base > 0) {
      _seenWeight = shaft.damageWeight;
      _deal(base);
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
      final g = shaft.lastOpened;
      if (g >= 0) {
        gateFlash[g] = 1;
        _burstAtGate(g, const Color(0xFFC9B8FF), 18);
      }
      _celebrate(0.6);
    }
    if (_seenShield && !shaft.shieldUp) {
      _seenShield = false;
      _showBanner('Shield down!');
      hordeFlash = 1;
      _celebrate(1);
    }
    if (shaft.bigHits > _seenBig) {
      _seenBig = shaft.bigHits;
      shake = max(shake, 0.35);
    }
    _flushDamagePop();

    _checkEnd();
  }

  /// Turns new gate hits into flashes, pop-ups, fever points and combo.
  void _readGates() {
    var multiplies = 0;
    for (var g = 0; g < _seenGateHits.length; g++) {
      final hits = shaft.gateHits[g] - _seenGateHits[g];
      if (hits == 0) continue;
      _seenGateHits[g] = shaft.gateHits[g];
      gateFlash[g] = max(gateFlash[g], multiplyFlash);
      _popPending[g] += hits;
      final gate = layout.gates[g];
      if (gate.kind == GateKind.multiply) multiplies += hits;
      if (gate.isJackpot) {
        gateFlash[g] = 1;
        _burstAtGate(g, const Color(0xFFFFD36E), 14);
        shake = max(shake, 0.6);
      }
      if (_simTime - _lastGatePop[g] >= 0.22) _popGate(g);
    }
    if (multiplies == 0) {
      if (_simTime - _lastMultiply > 0.8) {
        _comboHits = 0;
        comboLevel = 0;
      }
      return;
    }
    _lastMultiply = _simTime;
    if (!inFever) {
      feverMeter += multiplies;
      if (feverMeter >= feverPoints) {
        feverMeter = 0;
        feverLeft = feverSeconds;
        _showBanner('FEVER x2');
        _celebrate(0.8);
      }
    }
    _comboHits += multiplies;
    while (_comboHits >= comboStep) {
      _comboHits -= comboStep;
      if (comboLevel < maxCombo) comboLevel++;
      _playCombo();
    }
  }

  void _popGate(int g) {
    final pending = _popPending[g];
    if (pending == 0 || scale <= 0) return;
    _popPending[g] = 0;
    _lastGatePop[g] = _simTime;
    final gate = layout.gates[g];
    final x = toScreenX(shaft.gateX[g]);
    final y = toScreenY(gate.y) - 6;
    switch (gate.kind) {
      case GateKind.multiply:
        final m = gate.multiplier;
        _pop(
          x,
          y,
          gate.isJackpot ? 'x10!' : 'x$m',
          11 + m * 1.6,
          gate.isJackpot ? 4 : 0,
          g,
        );
      case GateKind.halve:
        _pop(x, y, '/2', 13, 1, g);
      case GateKind.refill:
        _pop(x, y, '+$pending', 13, 2, g);
    }
  }

  void _pop(double x, double y, String text, double size, int tone, int g) {
    final i = _nextPop;
    _nextPop = (_nextPop + 1) % maxPops;
    popX[i] = x + (_fxRandom.nextDouble() - 0.5) * 8;
    popY[i] = y;
    popAge[i] = 0;
    popText[i] = text;
    popSize[i] = size;
    popTone[i] = tone;
    popGate[i] = g;
  }

  void _showBanner(String text) {
    banner = text;
    bannerLeft = bannerTime;
  }

  void _burstAtGate(int g, Color color, int count) {
    if (scale <= 0) return;
    _burst(
      toScreenX(shaft.gateX[g]),
      toScreenY(layout.gates[g].y),
      color,
      count,
    );
  }

  void _burst(double x, double y, Color color, int count) {
    for (var k = 0; k < count; k++) {
      final i = _nextSpark;
      _nextSpark = (_nextSpark + 1) % maxSparks;
      final angle = _fxRandom.nextDouble() * pi * 2;
      final speed = 60 + _fxRandom.nextDouble() * 140;
      sparkX[i] = x;
      sparkY[i] = y;
      sparkVx[i] = cos(angle) * speed;
      sparkVy[i] = sin(angle) * speed - 40;
      sparkAge[i] = 0;
      sparkColor[i] = color;
    }
  }

  /// Deals [base] damage from the pipe; a fever doubles it. Big bursts
  /// push the horde back.
  void _deal(int base) {
    final damage = inFever ? base * 2 : base;
    damageDealt += damage;
    hordeHp = max(0, hordeHp - damage);
    hordeFlash = 1;
    _pendingDamage += damage;

    if (isBonus) return;
    if (_simTime - _burstStart > knockbackWindow) {
      _burstStart = _simTime;
      _burstDamage = 0;
    }
    _burstDamage += damage;
    final threshold = max(1, (layout.hordeHp * knockbackShare).ceil());
    while (_burstDamage >= threshold) {
      _burstDamage -= threshold;
      knockbacks++;
      hordeProgress = max(0, hordeProgress - knockbackPush);
      shake = max(shake, 0.3);
    }
  }

  void _flushDamagePop() {
    if (_pendingDamage == 0 || _simTime - _lastDamagePop < 0.25) return;
    if (scale > 0) {
      _pop(
        hordeFrontX - 6,
        stripRect.top + 22 + _fxRandom.nextDouble() * 20,
        '-$_pendingDamage',
        min(22.0, 11 + _pendingDamage * 0.4),
        3,
        -1,
      );
    }
    _pendingDamage = 0;
    _lastDamagePop = _simTime;
  }

  void _checkEnd() {
    final empty = cupBalls <= 0 && shaft.count == 0;
    if (isBonus) {
      if (empty) {
        finish(
          ArcadeResult.won(gateDropBonusStars(damageDealt, layout.hordeHp)),
        );
      }
      return;
    }
    if (hordeHp <= 0) {
      if (endless) {
        _nextWave();
        return;
      }
      finish(ArcadeResult.won(gateDropStars(cupBalls, startBalls)));
    } else if (hordeProgress >= 1) {
      hordeProgress = 1;
      _lose('The horde broke through');
    } else if (empty) {
      _lose('Out of balls');
    }
  }

  void _lose(String reason) {
    if (endless) {
      finish(ArcadeResult.ended(wavesCleared, reason));
    } else {
      finish(ArcadeResult.lost(reason));
    }
  }

  void _nextWave() {
    wavesCleared++;
    wave++;
    _load(buildGateDropWave(wave, runSeed));
    cupBalls = max(cupBalls, startBalls);
    feverLeft = 0;
    _showBanner('Wave $wave');
    _celebrate(0.8);
  }

  void _fireShot() {
    // Reuse the oldest slot when all are busy.
    final i = _nextShot;
    _nextShot = (_nextShot + 1) % maxShots;
    shotAge[i] = 0;
    shotLane[i] = _fxRandom.nextDouble();
  }

  void _playCombo() {
    if (_simTime - _lastCombo < 0.15) return;
    _lastCombo = _simTime;
    setup.sounds.complete(max(1, comboLevel));
  }

  /// A big moment: shake by [strength], raise the combo sound and buzz.
  void _celebrate(double strength) {
    shake = max(shake, strength);
    comboLevel = min(maxCombo, comboLevel + 1);
    _lastMultiply = _simTime;
    _lastCombo = -10;
    _playCombo();
    if (setup.haptics && clock - _lastHaptic >= 0.15) {
      _lastHaptic = clock;
      HapticFeedback.lightImpact();
    }
  }

  void _updateStatus() {
    if (_statusCup == cupBalls &&
        _statusHp == hordeHp &&
        _statusDamage == damageDealt &&
        _statusWave == wave) {
      return;
    }
    _statusCup = cupBalls;
    _statusHp = hordeHp;
    _statusWave = wave;
    _statusDamage = damageDealt;
    status.value = switch (layout.kind) {
      _ when endless => 'Wave $wave · Balls $cupBalls · Horde $hordeHp',
      LevelKind.bonus =>
        'Bonus · Balls $cupBalls · Damage $damageDealt/${layout.hordeHp}',
      LevelKind.boss => 'Boss · Balls $cupBalls · Horde $hordeHp',
      LevelKind.normal => 'Balls $cupBalls · Horde $hordeHp',
    };
  }

  @override
  void render(Canvas canvas) {
    if (scale > 0) {
      if (shake > 0) {
        canvas.save();
        final amount = shake * shake * 6;
        canvas.translate(sin(clock * 91) * amount, cos(clock * 77) * amount);
        _painter.render(canvas, this);
        canvas.restore();
      } else {
        _painter.render(canvas, this);
      }
    }
    super.render(canvas);
  }
}
