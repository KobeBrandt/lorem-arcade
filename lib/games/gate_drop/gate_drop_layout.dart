import 'dart:math';

/// Width of the shaft in shaft units. The physics runs in these units and
/// the game scales them to the screen.
const double shaftWidth = 100;

/// Height of the shaft in shaft units.
const double shaftHeight = 150;

/// What an open gate does to a ball that falls through it.
enum GateKind {
  /// The ball becomes [GateSpec.multiplier] balls.
  multiply,

  /// A trap: every second ball that falls through is removed.
  halve,

  /// The ball leaves the shaft and goes back into the cup.
  refill,
}

/// The kind of a level.
enum LevelKind {
  /// Stop the horde before it reaches the wall.
  normal,

  /// A boss horde with a shield. Shots do no damage until the shield
  /// lock ([GateDropLayout.shieldGate]) opens.
  boss,

  /// No horde walks. Pour the whole cup; stars come from the damage.
  bonus,
}

/// A horizontal gate bar. An open gate acts on the balls that fall
/// through it, see [kind]. A locked gate ([lock] above 0) is solid: it
/// swallows balls until [lock] of them landed, then it opens.
class GateSpec {
  const GateSpec({
    required this.x,
    required this.y,
    required this.halfWidth,
    required this.multiplier,
    this.kind = GateKind.multiply,
    this.lock = 0,
    this.swing = 0,
    this.swingSpeed = 0,
    this.phase = 0,
  });

  /// Center of the bar.
  final double x;
  final double y;
  final double halfWidth;

  /// A ball that crosses a [GateKind.multiply] gate becomes this many
  /// balls. Ignored by the other kinds.
  final int multiplier;

  final GateKind kind;

  /// A small fast x10 gate.
  bool get isJackpot => kind == GateKind.multiply && multiplier >= 10;

  /// Balls needed to open the gate. 0 means open from the start.
  final int lock;

  /// Moving gates slide left and right by [swing] units around [x].
  final double swing;

  /// Angular speed of the slide in radians per second.
  final double swingSpeed;
  final double phase;

  /// Center of the bar at [time] seconds.
  double xAt(double time) =>
      swing == 0 ? x : x + swing * sin(time * swingSpeed + phase);
}

/// A solid round bar from (ax, ay) to (bx, by). A peg is a bar with both
/// ends in the same place. A bumper is a peg that kicks balls away.
class SolidSpec {
  const SolidSpec(
    this.ax,
    this.ay,
    this.bx,
    this.by, {
    this.radius = 1.2,
    this.bumper = false,
  });

  /// A round peg at (x, y).
  const SolidSpec.peg(double x, double y, {double radius = 1.8})
    : this(x, y, x, y, radius: radius);

  /// A bouncy peg at (x, y) that kicks balls sideways.
  const SolidSpec.bumper(double x, double y)
    : this(x, y, x, y, radius: 2.6, bumper: true);

  final double ax;
  final double ay;
  final double bx;
  final double by;
  final double radius;
  final bool bumper;

  bool get isPeg => ax == bx && ay == by;
}

/// Everything one level needs: the shaft parts, the balls in the cup and
/// the horde.
class GateDropLayout {
  const GateDropLayout({
    required this.gates,
    required this.solids,
    required this.balls,
    required this.hordeHp,
    required this.hordeSeconds,
    required this.bestX,
    this.kind = LevelKind.normal,
    this.shieldGate = -1,
  });

  final List<GateSpec> gates;

  /// Pegs and deflector bars. The floor is added by the shaft itself.
  final List<SolidSpec> solids;

  /// Balls in the cup at the start.
  final int balls;

  /// Total horde hit points. Each ball that reaches the pipe deals 1.
  /// On a bonus level it is the damage target for 3 stars' scale, see
  /// [gateDropBonusStars].
  final int hordeHp;

  /// Seconds the horde needs to walk to the wall.
  final double hordeSeconds;

  /// Shaft x of the best pour line (the column of the strongest gates).
  final double bestX;

  final LevelKind kind;

  /// Index of the lock gate that holds the boss shield, or -1.
  final int shieldGate;

  /// A copy with other horde numbers.
  GateDropLayout copyWith({int? hordeHp, double? hordeSeconds}) =>
      GateDropLayout(
        gates: gates,
        solids: solids,
        balls: balls,
        hordeHp: hordeHp ?? this.hordeHp,
        hordeSeconds: hordeSeconds ?? this.hordeSeconds,
        bestX: bestX,
        kind: kind,
        shieldGate: shieldGate,
      );
}

/// Stars for a won level, by the share of balls still in the cup:
/// 3 at 40% or more, 2 at 15% or more, else 1.
int gateDropStars(int ballsLeft, int ballsAtStart) {
  if (ballsAtStart <= 0) return 1;
  final share = ballsLeft / ballsAtStart;
  if (share >= 0.4) return 3;
  if (share >= 0.15) return 2;
  return 1;
}

/// Stars for a bonus level, by the damage dealt against [target]:
/// 3 at 90% or more, 2 at 60% or more, else 1.
int gateDropBonusStars(int damage, int target) {
  if (target <= 0) return 3;
  final share = damage / target;
  if (share >= 0.9) return 3;
  if (share >= 0.6) return 2;
  return 1;
}
