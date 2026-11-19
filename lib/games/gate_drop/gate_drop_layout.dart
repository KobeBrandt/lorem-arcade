import 'dart:math';

/// Width of the shaft in shaft units. The physics runs in these units and
/// the game scales them to the screen.
const double shaftWidth = 100;

/// Height of the shaft in shaft units.
const double shaftHeight = 150;

/// A horizontal gate bar. An open gate multiplies the balls that fall
/// through it. A locked gate ([lock] above 0) is solid: it swallows balls
/// until [lock] of them landed, then it opens.
class GateSpec {
  const GateSpec({
    required this.x,
    required this.y,
    required this.halfWidth,
    required this.multiplier,
    this.lock = 0,
    this.swing = 0,
    this.swingSpeed = 0,
    this.phase = 0,
  });

  /// Center of the bar.
  final double x;
  final double y;
  final double halfWidth;

  /// A ball that crosses the gate becomes this many balls.
  final int multiplier;

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
/// ends in the same place.
class SolidSpec {
  const SolidSpec(this.ax, this.ay, this.bx, this.by, {this.radius = 1.2});

  /// A round peg at (x, y).
  const SolidSpec.peg(double x, double y, {double radius = 1.8})
    : this(x, y, x, y, radius: radius);

  final double ax;
  final double ay;
  final double bx;
  final double by;
  final double radius;

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
  });

  final List<GateSpec> gates;

  /// Pegs and deflector bars. The floor is added by the shaft itself.
  final List<SolidSpec> solids;

  /// Balls in the cup at the start.
  final int balls;

  /// Total horde hit points. Each ball that reaches the pipe deals 1.
  final int hordeHp;

  /// Seconds the horde needs to walk to the wall.
  final double hordeSeconds;

  /// Shaft x of the best pour line (the column of the strongest gates).
  final double bestX;
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
