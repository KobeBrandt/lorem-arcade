import 'dart:math';

import 'cog_model.dart';

/// A shot on its way to the wave.
class CogShot {
  CogShot(this.x, this.weapon, this.damage);

  /// Arena position (0 is the left edge).
  double x;

  /// Index of the weapon that fired it.
  final int weapon;
  final int damage;
}

/// Live side-view fight: the fighter stands on the left, waves walk in
/// from the right while the player keeps building. The weapons fire with
/// the current [powers], which the game updates whenever the board
/// changes.
///
/// The first wave comes after [countdown] seconds, the next one
/// [waveGap] seconds after a wave falls. The fighter does not heal. A
/// level is won when its last wave falls; the endless run only ends
/// when the fighter falls.
///
/// Runs in fixed steps, so the outcome does not depend on the frame
/// rate. No randomness.
class CogBattle {
  CogBattle(this.config, List<int> powers)
    : powers = List.of(powers),
      _fireTimers = [
        for (var i = 0; i < powers.length; i++) fireInterval * i / 2,
      ] {
    _startWave(0);
    waitLeft = countdown;
  }

  static const double step = 1 / 60;
  static const double arenaLength = 100;
  static const double fighterX = 10;

  /// The front enemy touches the fighter here.
  static const double contactX = 17;
  static const double enemySpacing = 9;
  static const double fireInterval = 0.6;
  static const double shotSpeed = 110;
  static const double fighterMaxHp = 100;

  /// Seconds to build before the first wave.
  static const double countdown = 3;

  /// Seconds between a fallen wave and the next one.
  static const double waveGap = 3;

  final CogLevel config;

  /// Damage per hit of each weapon. Change it with [setPowers].
  final List<int> powers;

  final List<CogShot> shots = [];
  final List<double> _fireTimers;

  /// Index (0-based) of the current or next wave.
  int waveIndex = 0;
  late CogWave wave;
  late List<double> enemyX;
  late int waveHp;

  /// Seconds until the current wave starts walking; 0 while it walks.
  double waitLeft = 0;

  /// Waves defeated so far.
  int wavesCleared = 0;

  /// Coins paid by defeated enemies so far.
  int coinsEarned = 0;

  int _killsBefore = 0;
  int _waveKills = 0;

  double fighterHp = fighterMaxHp;
  double time = 0;
  double _pending = 0;

  /// Null while running; then true (won) or false (lost).
  bool? won;

  /// Called when a shot hits the wave, with its damage and weapon index.
  void Function(int damage, int weapon)? onHit;

  /// Called for each defeated enemy, with its arena position and the
  /// coins it paid.
  void Function(double x, int coins)? onKill;

  /// True while the board is built before a wave (or between waves).
  bool get isWaiting => waitLeft > 0;

  /// True once the first wave started walking.
  bool get hasStarted => waveIndex > 0 || waitLeft <= 0;

  /// Enemies defeated so far, in all waves.
  int get kills => _killsBefore + _waveKills;

  /// Each enemy holds an equal share of the wave HP; the front one goes
  /// first.
  int get aliveCount => waveHp <= 0
      ? 0
      : (waveHp * wave.enemyCount / wave.hp).ceil().clamp(1, wave.enemyCount);

  /// Index of the front enemy (lower indexes are defeated).
  int get front => wave.enemyCount - aliveCount;

  bool get isOver => won != null;

  /// True while the front enemy touches the fighter.
  bool get inContact =>
      !isWaiting && aliveCount > 0 && enemyX[front] <= contactX + 0.001;

  /// Sets the weapon powers, for example after a gear was placed.
  void setPowers(List<int> value) {
    for (var i = 0; i < powers.length && i < value.length; i++) {
      powers[i] = value[i];
    }
  }

  void _startWave(int index) {
    waveIndex = index;
    wave = config.wave(index);
    waveHp = wave.hp;
    _waveKills = 0;
    enemyX = [
      for (var i = 0; i < wave.enemyCount; i++)
        arenaLength + 4 + i * enemySpacing,
    ];
  }

  /// Advances by [dt] seconds in fixed [step]s.
  void advance(double dt) {
    if (isOver) return;
    _pending += dt;
    while (_pending >= step && !isOver) {
      _pending -= step;
      _tick();
    }
  }

  void _tick() {
    time += step;
    if (isWaiting) {
      waitLeft = max(0, waitLeft - step);
      return;
    }
    final first = front;
    // Walk, keeping a gap behind the enemy in front.
    for (var i = first; i < enemyX.length; i++) {
      final minX = contactX + (i - first) * 6;
      enemyX[i] = max(minX, enemyX[i] - wave.speed * step);
    }
    // Fire once the wave is in view.
    if (enemyX[first] <= arenaLength) {
      for (var w = 0; w < powers.length; w++) {
        if (powers[w] <= 0) continue;
        _fireTimers[w] -= step;
        if (_fireTimers[w] <= 0) {
          _fireTimers[w] += fireInterval;
          shots.add(CogShot(fighterX + 4, w, powers[w]));
        }
      }
    }
    // Shots hit the front enemy.
    for (final shot in List.of(shots)) {
      shot.x += shotSpeed * step;
      if (waveHp > 0 && shot.x >= enemyX[front] - 2) {
        shots.remove(shot);
        waveHp = max(0, waveHp - shot.damage);
        onHit?.call(shot.damage, shot.weapon);
      }
    }
    final waveKills = wave.enemyCount - aliveCount;
    if (waveKills > _waveKills) {
      for (var k = _waveKills; k < waveKills; k++) {
        coinsEarned += wave.coinsPerKill;
        onKill?.call(enemyX[k], wave.coinsPerKill);
      }
      _waveKills = waveKills;
    }
    if (waveHp <= 0) {
      shots.clear();
      wavesCleared++;
      final last = config.waveCount;
      if (last != null && wavesCleared >= last) {
        won = true;
        return;
      }
      _killsBefore += wave.enemyCount;
      _startWave(waveIndex + 1);
      waitLeft = waveGap;
      for (var w = 0; w < _fireTimers.length; w++) {
        _fireTimers[w] = fireInterval * w / 2;
      }
      return;
    }
    if (inContact) {
      fighterHp = max(0, fighterHp - wave.dps * step);
      if (fighterHp <= 0) won = false;
    }
  }

  /// Stars for a won level, see [starsForHp].
  int get stars => starsForHp(fighterHp, fighterMaxHp);
}
