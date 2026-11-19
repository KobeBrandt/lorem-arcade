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

/// Side-view fight: the fighter stands on the left, the wave walks in
/// from the right. Runs in fixed steps, so the outcome does not depend on
/// the frame rate. No randomness.
class CogBattle {
  CogBattle(this.config, List<int> powers)
    : powers = List.unmodifiable(powers),
      waveHp = config.waveHp,
      _fireTimers = [
        for (var i = 0; i < powers.length; i++) fireInterval * i / 2,
      ] {
    enemyX = [
      for (var i = 0; i < config.enemyCount; i++)
        arenaLength + 4 + i * enemySpacing,
    ];
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

  /// Hard cap on the fight length in seconds. Reaching it is a loss.
  static const double maxTime = 90;

  final CogLevel config;

  /// Damage per hit of each weapon.
  final List<int> powers;

  late final List<double> enemyX;
  final List<CogShot> shots = [];
  final List<double> _fireTimers;

  int waveHp;
  double fighterHp = fighterMaxHp;
  double time = 0;
  double _pending = 0;

  /// Null while running; then true (won) or false (lost).
  bool? won;

  /// Enemies defeated so far.
  int get kills => config.enemyCount - aliveCount;

  /// Each enemy holds an equal share of [waveHp]; the front one goes first.
  int get aliveCount => waveHp <= 0
      ? 0
      : (waveHp * config.enemyCount / config.waveHp).ceil().clamp(
          1,
          config.enemyCount,
        );

  /// Index of the front enemy (lower indexes are defeated).
  int get front => config.enemyCount - aliveCount;

  bool get isOver => won != null;

  /// True while the front enemy touches the fighter.
  bool get inContact => aliveCount > 0 && enemyX[front] <= contactX + 0.001;

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
    final first = front;
    // Walk, keeping a gap behind the enemy in front.
    for (var i = first; i < enemyX.length; i++) {
      final minX = contactX + (i - first) * 6;
      enemyX[i] = max(minX, enemyX[i] - config.enemySpeed * step);
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
      }
    }
    if (waveHp <= 0) {
      shots.clear();
      won = true;
      return;
    }
    if (inContact) {
      fighterHp = max(0, fighterHp - config.enemyDps * step);
      if (fighterHp <= 0) won = false;
    }
    if (time >= maxTime) won = false;
  }

  /// Stars for a won fight, see [starsForHp].
  int get stars => starsForHp(fighterHp, fighterMaxHp);
}
