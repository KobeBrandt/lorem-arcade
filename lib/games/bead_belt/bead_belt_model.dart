import 'dart:math';

import 'bead_belt_level.dart';
import 'belt_shape.dart';

/// A bucket that sits in a dock and collects beads.
class DockedBucket {
  DockedBucket(this.color, this.capacity, this.lane);

  final int color;
  final int capacity;

  /// Lane it came from (for the slide animation).
  final int lane;

  /// Beads that landed in the bucket.
  int collected = 0;

  /// Beads flying to the bucket right now.
  int incoming = 0;

  /// Seconds since it was docked.
  double age = 0;

  /// Counts down once the bucket is full; the dock frees at 0.
  double leaveTimer = 0;

  bool get isFull => collected >= capacity;
  bool get isLeaving => isFull;

  /// True when the bucket can still take a bead of [bead].
  bool accepts(int bead) => bead == color && collected + incoming < capacity;
}

/// A bead on its way from the belt into a docked bucket.
class FlyingBead {
  FlyingBead(this.color, this.dock, this.fromU);

  final int color;
  final int dock;

  /// Loop position where it left the belt.
  final double fromU;

  /// 0 when it leaves the belt, 1 when it lands.
  double t = 0;
}

/// The Bead Belt rules without any drawing.
///
/// The belt is a ring of [beltCapacity] bead places that turns at
/// [BeadBeltLevel.beltSpeed] places per second. Feeding starts with the
/// first accepted tap: when an empty place passes the top center, one
/// bead comes from the reservoir, at most one per feed interval. When a
/// bead passes a dock whose bucket has its color and room, it flies into
/// that bucket. A full bucket leaves after [leaveDuration] seconds.
///
/// The level is lost when the belt is full, every dock holds a bucket
/// that takes none of the colors on the belt, and no bead is in flight,
/// for one full lap. Nothing can change in that state, so the lap is only
/// a safety margin.
///
/// Stars measure belt pressure: the highest belt fill reached. 3 stars if
/// the belt never went above 75%, 2 if it never got full, else 1.
class BeadBeltModel {
  BeadBeltModel(this.level)
    : lanes = [for (final lane in level.lanes) List.of(lane)],
      docks = List.filled(level.dockCount, null),
      _slots = List.filled(level.beltCapacity, -1),
      _reservoir = List.of(level.reservoir),
      _dockPos = [
        for (var k = 0; k < level.dockCount; k++)
          BeltShape.dockU(k, level.dockCount) * level.beltCapacity,
      ],
      totalBuckets = level.bucketCount;

  static const double leaveDuration = 0.45;
  static const double flightDuration = 0.32;
  static const double _maxStep = 1 / 60;

  final BeadBeltLevel level;
  final List<List<BeadBucket>> lanes;
  final List<DockedBucket?> docks;
  final List<FlyingBead> flying = [];
  final int totalBuckets;

  final List<int> _slots;
  final List<int> _reservoir;
  final List<double> _dockPos;

  /// Belt turn in bead places, in [0, beltCapacity).
  double phase = 0;

  int filledBuckets = 0;
  bool feeding = false;
  double maxFill = 0;
  double _feedCooldown = 0;
  double _jamTime = 0;
  bool _jammed = false;

  /// Called when a bucket gets its last bead.
  void Function(int dock)? onBucketFilled;

  /// Called when a bucket leaves its dock.
  void Function(int dock, DockedBucket bucket)? onBucketLeft;

  int get beltCapacity => level.beltCapacity;
  int get beltCount => _slots.where((c) => c >= 0).length;
  int get reservoirCount => _reservoir.length;
  bool get isCleared => filledBuckets == totalBuckets && flying.isEmpty;
  bool get isJammed => _jammed;
  bool get isOver => isCleared || _jammed;

  /// Color in belt place [i], or -1.
  int slotColor(int i) => _slots[i];

  /// Loop position (0..1) of belt place [i].
  double slotU(int i) => ((i + phase) % beltCapacity) / beltCapacity;

  /// Stars for the run so far (see the class comment).
  int get stars {
    if (maxFill <= 0.75) return 3;
    if (maxFill < 1) return 2;
    return 1;
  }

  /// Number of beads of [color] on the belt.
  int beltCountOf(int color) => _slots.where((c) => c == color).length;

  bool get hasFreeDock => docks.contains(null);

  /// Moves the front bucket of [lane] into a free dock. Returns the dock,
  /// or null when the tap is rejected (no bucket or no free dock).
  int? dockFront(int lane) {
    if (isOver || lane < 0 || lane >= lanes.length) return null;
    if (lanes[lane].isEmpty || !hasFreeDock) return null;
    final dock = _nearestFreeDock(lane);
    final bucket = lanes[lane].removeAt(0);
    docks[dock] = DockedBucket(bucket.color, bucket.capacity, lane);
    feeding = true;
    return dock;
  }

  /// Free dock closest to the lane, measured across the screen.
  int _nearestFreeDock(int lane) {
    final laneX = (lane + 0.5) / lanes.length;
    var best = -1;
    var bestDistance = double.infinity;
    for (var k = 0; k < docks.length; k++) {
      if (docks[k] != null) continue;
      final distance = ((k + 0.5) / docks.length - laneX).abs();
      if (distance < bestDistance - 1e-9) {
        best = k;
        bestDistance = distance;
      }
    }
    return best;
  }

  void update(double dt) {
    var left = dt;
    while (left > 1e-9 && !isOver) {
      final step = min(left, _maxStep);
      _step(step);
      left -= step;
    }
  }

  void _step(double dt) {
    final c = beltCapacity;
    final delta = level.beltSpeed * dt;
    final feedPos = BeltShape.feedU * c;
    _feedCooldown -= dt;

    for (var i = 0; i < c; i++) {
      final s = (i + phase) % c;
      final color = _slots[i];
      if (color >= 0) {
        for (var k = 0; k < docks.length; k++) {
          final bucket = docks[k];
          if (bucket == null || !bucket.accepts(color)) continue;
          if (!_crosses(s, delta, _dockPos[k])) continue;
          bucket.incoming++;
          _slots[i] = -1;
          flying.add(FlyingBead(color, k, s / c));
          break;
        }
      } else if (feeding &&
          _reservoir.isNotEmpty &&
          _feedCooldown <= 0 &&
          _crosses(s, delta, feedPos)) {
        _slots[i] = _reservoir.removeAt(0);
        _feedCooldown = level.feedInterval;
      }
    }
    phase = (phase + delta) % c;
    maxFill = max(maxFill, beltCount / c);

    for (final bead in flying) {
      bead.t += dt / flightDuration;
    }
    flying.removeWhere((bead) {
      if (bead.t < 1) return false;
      final bucket = docks[bead.dock]!;
      bucket
        ..incoming -= 1
        ..collected += 1;
      if (bucket.isFull) {
        bucket.leaveTimer = leaveDuration;
        onBucketFilled?.call(bead.dock);
      }
      return true;
    });

    for (var k = 0; k < docks.length; k++) {
      final bucket = docks[k];
      if (bucket == null) continue;
      bucket.age += dt;
      if (!bucket.isLeaving) continue;
      bucket.leaveTimer -= dt;
      if (bucket.leaveTimer <= 0) {
        docks[k] = null;
        filledBuckets++;
        onBucketLeft?.call(k, bucket);
      }
    }

    if (_isStuck()) {
      _jamTime += dt;
      if (_jamTime >= level.lapTime) _jammed = true;
    } else {
      _jamTime = 0;
    }
  }

  /// True while nothing can move: belt full, all docks hold buckets that
  /// take no color on the belt, and no bead is in flight.
  bool _isStuck() {
    if (flying.isNotEmpty) return false;
    if (_slots.contains(-1)) return false;
    for (final bucket in docks) {
      if (bucket == null || bucket.isLeaving) return false;
      if (_slots.any(bucket.accepts)) return false;
    }
    return true;
  }

  /// True when a place at [s] reaches [target] within [delta] places.
  bool _crosses(double s, double delta, double target) {
    final ahead = (target - s) % beltCapacity;
    return ahead < delta;
  }
}
