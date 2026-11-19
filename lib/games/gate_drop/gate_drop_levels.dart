import 'dart:math';

import 'gate_drop_layout.dart';
import 'gate_drop_shaft.dart';

/// Builds the layout of [level] (1-based). The same level always gives
/// the same layout.
///
/// Every level has one good column: a gate in each row near [bestX].
/// Higher levels add rows, narrow the gates, let the column drift, add a
/// lock (level 3+) and a moving gate (level 6+).
///
/// Horde hit points come from a test run: the whole cup is poured on the
/// good column ([pourDamage]) and the horde gets a share of that damage.
/// The share grows from 35% at level 1 to 55% at level 9 and later, so a
/// level can always be won, and 3 stars stay possible with a good aim.
GateDropLayout buildGateDropLevel(int level) {
  final l = max(1, level);
  final rng = Random(l);
  final balls = min(100, 40 + (l - 1) * 4);
  final rows = min(5, 2 + l ~/ 2);
  final bestX = l == 1 ? 50.0 : 30 + rng.nextDouble() * 40;
  final halfWidth = max(9.0, 30 - (l - 1) * 2.4);
  final lockRow = l >= 3 ? 1 + rng.nextInt(rows - 1) : -1;
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
    }
    final moving = r == moveRow;
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

    // A small x2 decoy on the wider side from level 2 on.
    if (l >= 2 && r.isOdd) {
      final leftRoom = x - hw;
      final rightRoom = shaftWidth - (x + hw);
      final room = max(leftRoom, rightRoom);
      if (room > 16) {
        final dx = leftRoom > rightRoom ? leftRoom / 2 : x + hw + rightRoom / 2;
        gates.add(GateSpec(x: dx, y: y, halfWidth: 6, multiplier: 2));
      }
    }

    // Pegs between this row and the next, kept off the good column.
    if (r < rows - 1) {
      final py = y + gap / 2;
      final pegs = 2 + rng.nextInt(3);
      for (var p = 0; p < pegs; p++) {
        final px = 6 + rng.nextDouble() * (shaftWidth - 12);
        if ((px - x).abs() < hw + 4) continue;
        solids.add(SolidSpec.peg(px, py + (rng.nextDouble() - 0.5) * 4));
      }
    }
  }

  // Deflectors near the walls push wall huggers back inward.
  solids.add(const SolidSpec(0, 60, 9, 65));
  solids.add(const SolidSpec(shaftWidth, 88, shaftWidth - 9, 93));

  final draft = GateDropLayout(
    gates: gates,
    solids: solids,
    balls: balls,
    hordeHp: 1,
    hordeSeconds: max(35.0, 75.0 - 3 * (l - 1)),
    bestX: gates.reduce((a, b) => b.multiplier > a.multiplier ? b : a).x,
  );
  final share = min(0.55, 0.35 + 0.025 * (l - 1));
  return GateDropLayout(
    gates: draft.gates,
    solids: draft.solids,
    balls: draft.balls,
    hordeHp: max(20, (pourDamage(draft) * share).round()),
    hordeSeconds: draft.hordeSeconds,
    bestX: draft.bestX,
  );
}

/// Damage of pouring the whole cup at [GateDropLayout.bestX] at the game's
/// pour rate, run until the shaft is empty.
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
  return shaft.collectedWeight;
}
