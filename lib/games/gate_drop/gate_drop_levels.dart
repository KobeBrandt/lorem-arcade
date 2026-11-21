import 'dart:math';

import 'gate_drop_layout.dart';
import 'gate_drop_shaft.dart';

/// First level with a trap gate (/2) next to the good column.
const int trapFromLevel = 4;

/// First level with bumpers among the pegs.
const int bumperFromLevel = 5;

/// First level with a refill gate that sends balls back to the cup.
const int refillFromLevel = 7;

/// First level with a small, fast x10 jackpot gate.
const int jackpotFromLevel = 8;

/// Every 5th level is a boss level.
const int bossEvery = 5;

/// Every 7th level is a bonus level, unless it is also a boss level.
const int bonusEvery = 7;

/// The kind of level [level] in the level list.
LevelKind gateDropLevelKind(int level) {
  if (level % bossEvery == 0) return LevelKind.boss;
  if (level % bonusEvery == 0) return LevelKind.bonus;
  return LevelKind.normal;
}

/// Builds the layout of [level] (1-based). The same level always gives
/// the same layout.
///
/// Every level has one good column: a gate in each row near [bestX].
/// Higher levels add rows, narrow the gates, let the column drift, add a
/// lock (level 3+), a trap, bumpers, a moving gate (level 6+), a refill
/// gate and a jackpot, see the `...FromLevel` constants.
///
/// Horde hit points come from a test run: the whole cup is poured on the
/// good column ([pourDamage]) and the horde gets a share of that damage.
/// The share grows from 35% at level 1 to 55% at level 9 and later, so a
/// level can always be won, and 3 stars stay possible with a good aim.
/// [extraShare] adds to that share (endless waves). The jackpot is left
/// out of the test run, so it is pure bonus.
///
/// [kind] is [gateDropLevelKind] by default. A boss level puts the
/// shield on its lock. A bonus level has no refill gate, and its horde
/// hit points are the full test run damage, the target for the stars.
/// [seed] changes the random parts (endless runs).
GateDropLayout buildGateDropLevel(
  int level, {
  LevelKind? kind,
  int? seed,
  double extraShare = 0,
}) {
  final l = max(1, level);
  final levelKind = kind ?? gateDropLevelKind(l);
  final rng = Random(seed ?? l);
  final balls = min(100, 40 + (l - 1) * 4);
  final rows = min(5, 2 + l ~/ 2);
  final bestX = l == 1 ? 50.0 : 30 + rng.nextDouble() * 40;
  final halfWidth = max(9.0, 30 - (l - 1) * 2.4);
  var lockRow = l >= 3 ? 1 + rng.nextInt(rows - 1) : -1;
  if (levelKind == LevelKind.boss && lockRow < 0) lockRow = rows - 1;
  var moveRow = -1;
  if (l >= 6) {
    moveRow = rng.nextInt(rows);
    if (moveRow == lockRow) moveRow = (moveRow + 1) % rows;
  }

  const top = 30.0;
  const bottom = 116.0;
  final gap = (bottom - top) / (rows - 1);
  final gates = <GateSpec>[];
  final solids = <SolidSpec>[];
  var product = 1.0;
  var shieldGate = -1;
  var bestGate = -1;
  double? decoyX;

  // Good column multipliers: x2 on top, then more x3 and x5 as the
  // level grows, in a shuffled row order.
  final threes = min(rows - 1, (l - 1) ~/ 2);
  final fives = min(min(2, threes), max(0, (l - 5) ~/ 3));
  final lower = [
    for (var r = 1; r < rows; r++) r <= fives ? 5 : (r <= threes ? 3 : 2),
  ]..shuffle(rng);
  final mults = [2, ...lower];

  for (var r = 0; r < rows; r++) {
    final y = top + r * gap;
    final drift = (rng.nextDouble() - 0.5) * min(l, 8) * 1.2;
    final x = (bestX + drift).clamp(halfWidth + 2, shaftWidth - halfWidth - 2);
    final mult = mults[r];
    final hw = halfWidth + rng.nextDouble() * 3;
    var lock = 0;
    if (r == lockRow) {
      // A lock costs a share of the balls that reach it.
      lock = (balls * min(product, 6) * (0.2 + 0.01 * l)).ceil();
      if (levelKind == LevelKind.boss) shieldGate = gates.length;
    }
    final moving = r == moveRow;
    if (bestGate < 0 || mult > gates[bestGate].multiplier) {
      bestGate = gates.length;
    }
    gates.add(
      GateSpec(
        x: x.toDouble(),
        y: y,
        halfWidth: hw,
        multiplier: mult,
        lock: lock,
        swing: moving ? 6.0 + l : 0,
        swingSpeed: moving ? 0.8 + 0.05 * l : 0,
        phase: moving ? rng.nextDouble() * pi * 2 : 0,
      ),
    );
    product *= mult;

    final leftRoom = x - hw;
    final rightRoom = shaftWidth - (x + hw);
    final room = max(leftRoom, rightRoom);
    final leftWider = leftRoom > rightRoom;

    // A small x2 decoy on the wider side from level 2 on.
    if (l >= 2 && r.isOdd && room > 16) {
      final dx = leftWider ? leftRoom / 2 : x + hw + rightRoom / 2;
      decoyX ??= dx;
      gates.add(GateSpec(x: dx, y: y, halfWidth: 6, multiplier: 2));
    }

    // A trap right next to the good gate on even rows, so careless aim
    // costs balls.
    if (l >= trapFromLevel && r.isEven && r > 0 && room > 15) {
      final tx = leftWider ? x - hw - 7.5 : x + hw + 7.5;
      gates.add(
        GateSpec(
          x: tx,
          y: y,
          halfWidth: 5.5,
          multiplier: 1,
          kind: GateKind.halve,
        ),
      );
    }

    // Pegs between this row and the next, kept off the good column.
    // From [bumperFromLevel] on some of them are bumpers.
    if (r < rows - 1) {
      final py = y + gap / 2;
      final pegs = 2 + rng.nextInt(3);
      for (var p = 0; p < pegs; p++) {
        final px = 6 + rng.nextDouble() * (shaftWidth - 12);
        final pyy = py + (rng.nextDouble() - 0.5) * 4;
        final bumper = l >= bumperFromLevel && rng.nextDouble() < 0.4;
        if ((px - x).abs() < hw + (bumper ? 7 : 4)) continue;
        solids.add(bumper ? SolidSpec.bumper(px, pyy) : SolidSpec.peg(px, pyy));
      }
    }
  }

  // A refill gate low in the shaft, under the decoy when there is one:
  // balls that took the x2 decoy come back to the cup doubled.
  if (l >= refillFromLevel && levelKind != LevelKind.bonus) {
    final last = gates[gates.length - 1];
    final rx =
        decoyX ??
        (last.x > shaftWidth / 2 ? last.x / 2 : (last.x + shaftWidth) / 2);
    gates.add(
      GateSpec(
        x: rx.clamp(8.0, shaftWidth - 8.0),
        y: 127,
        halfWidth: 5,
        multiplier: 1,
        kind: GateKind.refill,
      ),
    );
  }

  // Deflectors near the walls push wall huggers back inward.
  solids.add(const SolidSpec(0, 60, 9, 65));
  solids.add(const SolidSpec(shaftWidth, 88, shaftWidth - 9, 93));

  final draft = GateDropLayout(
    gates: List.of(gates),
    solids: solids,
    balls: balls,
    hordeHp: 1,
    hordeSeconds: max(35.0, 75.0 - 3 * (l - 1)),
    bestX: gates[bestGate].x,
    kind: levelKind,
    shieldGate: shieldGate,
  );

  // The jackpot: small, fast and far from the column most of the time.
  if (l >= jackpotFromLevel) {
    gates.add(
      GateSpec(
        x: shaftWidth / 2,
        y: top + gap * 0.3,
        halfWidth: 3.5,
        multiplier: 10,
        swing: 34,
        swingSpeed: 1.7,
        phase: rng.nextDouble() * pi * 2,
      ),
    );
  }

  final damage = pourDamage(draft);
  final share = levelKind == LevelKind.bonus
      ? 1.0
      : min(0.55, 0.35 + 0.025 * (l - 1)) + extraShare;
  return GateDropLayout(
    gates: gates,
    solids: draft.solids,
    balls: draft.balls,
    hordeHp: max(20, (damage * share).round()),
    hordeSeconds: levelKind == LevelKind.boss
        ? draft.hordeSeconds * 1.25
        : draft.hordeSeconds,
    bestX: draft.bestX,
    kind: levelKind,
    shieldGate: shieldGate,
  );
}

/// Layout of wave [wave] (1-based) of an endless run. Waves never have a
/// boss or a bonus; they get harder like the levels, and after wave 9 the
/// horde keeps growing by 2% of the test run damage per wave.
GateDropLayout buildGateDropWave(int wave, int runSeed) => buildGateDropLevel(
  wave,
  kind: LevelKind.normal,
  seed: runSeed * 1009 + wave,
  extraShare: min(0.35, max(0, wave - 9) * 0.02),
);

/// Damage of pouring the whole cup at [GateDropLayout.bestX] at the game's
/// pour rate, run until the shaft is empty. Refilled balls are not poured
/// again, so the number stays on the safe side.
int pourDamage(GateDropLayout layout, {int pourRate = 12}) {
  final shaft = GateDropShaft(layout, seed: layout.balls);
  final stepsPerBall = (1 / GateDropShaft.step / pourRate).round();
  var left = layout.balls;
  // Safety limit: one minute of shaft time.
  for (var step = 0; step < 120 * 60; step++) {
    if (left > 0 && step % stepsPerBall == 0 && shaft.drop(layout.bestX)) {
      left--;
    }
    shaft.tick();
    if (left == 0 && shaft.count == 0) break;
  }
  return shaft.damageWeight;
}
