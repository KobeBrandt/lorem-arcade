import 'dart:math';
import 'dart:ui';

/// The belt loop as a rounded rectangle with a fixed shape. It is 2 units
/// wide and 1 unit high, centered on (0, 0), y pointing down.
///
/// A loop position u in [0, 1) starts at the bottom center and runs
/// clockwise on screen: left along the bottom, up, right along the top
/// and down again. The model and the renderer share it, so docks and
/// beads line up at any screen size.
abstract final class BeltShape {
  static const double halfWidth = 1;
  static const double halfHeight = 0.5;
  static const double radius = 0.3;

  static const double _straightX = halfWidth - radius;
  static const double _straightY = halfHeight - radius;
  static const double _arc = pi * radius / 2;

  /// Length of the loop in shape units.
  static const double length = 4 * _straightX + 4 * _straightY + 4 * _arc;

  /// Loop position where beads are fed (the top center).
  static const double feedU = 0.5;

  /// Loop position of dock [index] out of [count]. Docks sit along the
  /// bottom straight, left to right.
  static double dockU(int index, int count) {
    final x = -0.6 + 1.2 * (index + 0.5) / count;
    return ((-x) % length) / length;
  }

  /// Horizontal shape coordinate of dock [index] out of [count].
  static double dockX(int index, int count) =>
      -0.6 + 1.2 * (index + 0.5) / count;

  /// Point on the loop at position [u] (wraps around).
  static Offset pointAt(double u) {
    var d = (u % 1) * length;
    // Bottom, left half.
    if (d <= _straightX) return Offset(-d, halfHeight);
    d -= _straightX;
    if (d <= _arc) return _corner(-_straightX, _straightY, pi / 2, d);
    d -= _arc;
    if (d <= 2 * _straightY) return Offset(-halfWidth, _straightY - d);
    d -= 2 * _straightY;
    if (d <= _arc) return _corner(-_straightX, -_straightY, pi, d);
    d -= _arc;
    if (d <= 2 * _straightX) return Offset(-_straightX + d, -halfHeight);
    d -= 2 * _straightX;
    if (d <= _arc) return _corner(_straightX, -_straightY, pi * 1.5, d);
    d -= _arc;
    if (d <= 2 * _straightY) return Offset(halfWidth, -_straightY + d);
    d -= 2 * _straightY;
    if (d <= _arc) return _corner(_straightX, _straightY, 0, d);
    d -= _arc;
    return Offset(_straightX - d, halfHeight);
  }

  /// Unit direction of travel at [u].
  static Offset directionAt(double u) {
    final a = pointAt(u - 0.001);
    final b = pointAt(u + 0.001);
    final v = b - a;
    return v / v.distance;
  }

  static Offset _corner(double cx, double cy, double start, double along) {
    final angle = start + along / radius;
    return Offset(cx + radius * cos(angle), cy + radius * sin(angle));
  }
}
