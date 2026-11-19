import 'dart:math';
import 'dart:typed_data';

import 'gate_drop_layout.dart';

/// Ball physics of the shaft, in shaft units, with a fixed time step.
///
/// Balls are points with a radius in fixed-size arrays. They fall, bounce
/// off the walls, pegs and bars, multiply at open gates and get swallowed
/// by locked gates. The sloped floor rolls every ball into the pipe in
/// the middle. When the shaft is full, new copies merge into their parent
/// ball as extra weight, so no value is lost.
class GateDropShaft {
  GateDropShaft(GateDropLayout layout, {int seed = 1})
    : gates = layout.gates,
      _random = Random(seed),
      gateX = Float64List(layout.gates.length),
      lockLeft = Int32List(layout.gates.length) {
    for (var i = 0; i < gates.length; i++) {
      gateX[i] = gates[i].x;
      lockLeft[i] = gates[i].lock;
    }
    final all = [...layout.solids, ...floor];
    _solidCount = all.length;
    _sax = Float64List(_solidCount);
    _say = Float64List(_solidCount);
    _sbx = Float64List(_solidCount);
    _sby = Float64List(_solidCount);
    _sr = Float64List(_solidCount);
    for (var i = 0; i < _solidCount; i++) {
      _sax[i] = all[i].ax;
      _say[i] = all[i].ay;
      _sbx[i] = all[i].bx;
      _sby[i] = all[i].by;
      _sr[i] = all[i].radius;
    }
  }

  static const int maxBalls = 600;
  static const double ballRadius = 1.4;
  static const double step = 1 / 120;
  static const double gravity = 260;
  static const double maxFallSpeed = 160;
  static const double bounce = 0.45;
  static const double copySpread = 18;
  static const double pipeHalfWidth = 8;

  /// Half the thickness of a gate bar.
  static const double gateThickness = 1.2;

  /// A ball older than this is counted as rolled into the pipe.
  static const double maxAge = 14;

  /// Floor bars sloping down to the pipe from both walls.
  static const List<SolidSpec> floor = [
    SolidSpec(0, shaftHeight - 18, shaftWidth / 2 - pipeHalfWidth, 144),
    SolidSpec(
      shaftWidth,
      shaftHeight - 18,
      shaftWidth / 2 + pipeHalfWidth,
      144,
    ),
  ];

  final List<GateSpec> gates;
  final Random _random;

  /// Current center of each gate (moving gates slide).
  final Float64List gateX;

  /// Balls each gate still needs before it opens. 0 means open.
  final Int32List lockLeft;

  late final int _solidCount;
  late final Float64List _sax, _say, _sbx, _sby, _sr;

  final Float64List x = Float64List(maxBalls);
  final Float64List y = Float64List(maxBalls);
  final Float64List vx = Float64List(maxBalls);
  final Float64List vy = Float64List(maxBalls);
  final Float64List age = Float64List(maxBalls);

  /// Bit i is set once the ball crossed gate i.
  final Int32List passed = Int32List(maxBalls);

  /// How many balls this ball stands for (more than 1 after merges).
  final Int32List weight = Int32List(maxBalls);

  /// Balls in the shaft.
  int count = 0;

  double time = 0;

  /// Running totals the game reads to react (shots, sounds).
  int collectedBalls = 0;
  int collectedWeight = 0;
  int locksOpened = 0;
  int bigHits = 0;

  /// Index of the gate that opened last, or -1.
  int lastOpened = -1;

  /// Total weight of the balls in the shaft.
  int get weightInShaft {
    var sum = 0;
    for (var i = 0; i < count; i++) {
      sum += weight[i];
    }
    return sum;
  }

  /// Drops one ball at shaft x [atX] just under the cup. Returns false
  /// when the shaft is full.
  bool drop(double atX, {double atY = 8}) {
    if (count >= maxBalls) return false;
    final jitter = (_random.nextDouble() - 0.5) * 1.2;
    _add(
      (atX + jitter).clamp(ballRadius, shaftWidth - ballRadius),
      atY,
      (_random.nextDouble() - 0.5) * 8,
      20,
      0,
      1,
    );
    return true;
  }

  void _add(double px, double py, double pvx, double pvy, int mask, int w) {
    final i = count++;
    x[i] = px;
    y[i] = py;
    vx[i] = pvx;
    vy[i] = pvy;
    age[i] = 0;
    passed[i] = mask;
    weight[i] = w;
  }

  void _remove(int i) {
    final last = --count;
    if (i == last) return;
    x[i] = x[last];
    y[i] = y[last];
    vx[i] = vx[last];
    vy[i] = vy[last];
    age[i] = age[last];
    passed[i] = passed[last];
    weight[i] = weight[last];
  }

  void _collect(int i) {
    collectedBalls++;
    collectedWeight += weight[i];
    _remove(i);
  }

  /// Advances one fixed [step].
  void tick() {
    time += step;
    for (var g = 0; g < gates.length; g++) {
      gateX[g] = gates[g].xAt(time);
    }
    const dt = step;
    const r = ballRadius;
    var i = 0;
    while (i < count) {
      var bvx = vx[i];
      var bvy = min(maxFallSpeed, vy[i] + gravity * dt);
      final py = y[i];
      var bx = x[i] + bvx * dt;
      var by = py + bvy * dt;
      age[i] += dt;

      // Walls and ceiling.
      if (bx < r) {
        bx = r;
        if (bvx < 0) bvx = -bvx * bounce;
      } else if (bx > shaftWidth - r) {
        bx = shaftWidth - r;
        if (bvx > 0) bvx = -bvx * bounce;
      }
      if (by < r) {
        by = r;
        if (bvy < 0) bvy = -bvy * bounce;
      }

      // Pegs, bars and the floor.
      for (var s = 0; s < _solidCount; s++) {
        final ax = _sax[s], ay = _say[s];
        final ex = _sbx[s] - ax, ey = _sby[s] - ay;
        final len2 = ex * ex + ey * ey;
        var t = 0.0;
        if (len2 > 0) {
          t = ((bx - ax) * ex + (by - ay) * ey) / len2;
          if (t < 0) {
            t = 0;
          } else if (t > 1) {
            t = 1;
          }
        }
        final cx = ax + ex * t, cy = ay + ey * t;
        final dx = bx - cx, dy = by - cy;
        final reach = _sr[s] + r;
        final d2 = dx * dx + dy * dy;
        if (d2 >= reach * reach) continue;
        var nx = 0.0, ny = -1.0;
        if (d2 > 1e-9) {
          final d = sqrt(d2);
          nx = dx / d;
          ny = dy / d;
        }
        bx = cx + nx * reach;
        by = cy + ny * reach;
        final vn = bvx * nx + bvy * ny;
        if (vn < 0) {
          bvx -= (1 + bounce) * vn * nx;
          bvy -= (1 + bounce) * vn * ny;
          bvx *= 0.98;
        }
      }

      x[i] = bx;
      y[i] = by;
      vx[i] = bvx;
      vy[i] = bvy;

      // Gates.
      var gone = false;
      for (var g = 0; g < gates.length; g++) {
        final gy = gates[g].y;
        final gx = gateX[g];
        final hw = gates[g].halfWidth;
        if (lockLeft[g] > 0) {
          // A locked gate is solid and swallows what lands on it.
          if ((bx - gx).abs() <= hw + r &&
              (by - gy).abs() <= gateThickness + r) {
            lockLeft[g] -= weight[i];
            if (lockLeft[g] <= 0) {
              lockLeft[g] = 0;
              locksOpened++;
              lastOpened = g;
            }
            _remove(i);
            gone = true;
            break;
          }
          continue;
        }
        final bit = 1 << g;
        if ((passed[i] & bit) != 0) continue;
        if (py < gy && by >= gy && (bx - gx).abs() <= hw) {
          passed[i] |= bit;
          _multiply(i, gates[g].multiplier);
        }
      }
      if (gone) continue;

      // The pipe, or a ball that has been around too long.
      if ((by >= shaftHeight - 5 &&
              (bx - shaftWidth / 2).abs() < pipeHalfWidth) ||
          by > shaftHeight ||
          age[i] > maxAge) {
        _collect(i);
        continue;
      }
      i++;
    }
  }

  /// Turns ball [i] into [mult] balls. Copies that do not fit merge into
  /// ball [i] as weight.
  void _multiply(int i, int mult) {
    if (mult >= 5) bigHits++;
    final w = weight[i];
    for (var k = 1; k < mult; k++) {
      if (count < maxBalls) {
        final side = k.isOdd ? -1 : 1;
        final spread = copySpread * ((k + 1) ~/ 2) * side;
        _add(x[i], y[i], vx[i] + spread, vy[i], passed[i], w);
      } else {
        weight[i] += w;
      }
    }
  }
}
