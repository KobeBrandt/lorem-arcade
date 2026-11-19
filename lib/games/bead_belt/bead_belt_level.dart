import 'dart:math';

/// A bucket waiting in a lane. It takes [capacity] beads of [color].
class BeadBucket {
  const BeadBucket(this.color, this.capacity);

  final int color;
  final int capacity;
}

/// One Bead Belt level: the belt, the docks, the lanes and the beads.
class BeadBeltLevel {
  const BeadBeltLevel({
    required this.number,
    required this.colorCount,
    required this.dockCount,
    required this.beltCapacity,
    required this.beltSpeed,
    required this.feedInterval,
    required this.lanes,
    required this.reservoir,
  });

  final int number;
  final int colorCount;

  /// Docks next to the belt (3 to 5).
  final int dockCount;

  /// Bead places on the belt.
  final int beltCapacity;

  /// Belt speed in bead places per second.
  final double beltSpeed;

  /// Seconds between two beads fed onto the belt.
  final double feedInterval;

  /// Bucket queues. Index 0 of a lane is its front bucket.
  final List<List<BeadBucket>> lanes;

  /// Bead colors in the order they are fed onto the belt.
  final List<int> reservoir;

  int get bucketCount => lanes.fold(0, (sum, lane) => sum + lane.length);

  /// Seconds the belt needs for one full lap.
  double get lapTime => beltCapacity / beltSpeed;

  /// Builds level [number] (1-based). The same number gives the same level.
  factory BeadBeltLevel.generate(int number) {
    final level = max(1, number);
    final random = Random(level);

    final colorCount = level <= 2
        ? 2
        : level <= 5
        ? 3
        : level <= 9
        ? 4
        : level <= 14
        ? 5
        : 6;
    final laneCount = level <= 3
        ? 2
        : level <= 11
        ? 3
        : 4;
    final dockCount = level <= 7
        ? 3
        : level <= 17
        ? 4
        : 5;
    final bucketsPerColor = min(2 + (level - 1) ~/ 4, 5);
    final minCapacity = 8 + min((level - 1) ~/ 5, 3) * 2;
    final maxCapacity = minCapacity + min((level - 1) ~/ 3, 3) * 2;

    // Bucket order: each round holds every color once, in a random order.
    final plan = <BeadBucket>[];
    for (var round = 0; round < bucketsPerColor; round++) {
      final colors = List<int>.generate(colorCount, (c) => c)..shuffle(random);
      for (final color in colors) {
        final steps = (maxCapacity - minCapacity) ~/ 2;
        final capacity = minCapacity + random.nextInt(steps + 1) * 2;
        plan.add(BeadBucket(color, capacity));
      }
    }
    // Later levels mix the order more across rounds.
    final swaps = level <= 3 ? 0 : min(level ~/ 2, plan.length);
    for (var s = 0; s < swaps; s++) {
      final i = random.nextInt(plan.length - 1);
      final temp = plan[i];
      plan[i] = plan[i + 1];
      plan[i + 1] = temp;
    }

    // Lanes are filled round robin, so plan bucket k is a front bucket
    // once every earlier bucket has left its lane.
    final lanes = List.generate(laneCount, (_) => <BeadBucket>[]);
    for (var k = 0; k < plan.length; k++) {
      lanes[k % laneCount].add(plan[k]);
    }

    // Beads come from a window of the next plan buckets. A window as big
    // as the docks fits an ideal player; a bigger one fills the belt.
    final window = level <= 5
        ? dockCount - 1
        : level <= 12
        ? dockCount
        : dockCount + 1;
    final left = [for (final bucket in plan) bucket.capacity];
    final active = <int>[];
    var next = 0;
    final reservoir = <int>[];
    while (true) {
      while (active.length < window && next < plan.length) {
        active.add(next++);
      }
      if (active.isEmpty) break;
      final pick = active[random.nextInt(active.length)];
      reservoir.add(plan[pick].color);
      left[pick]--;
      if (left[pick] == 0) active.remove(pick);
    }

    return BeadBeltLevel(
      number: level,
      colorCount: colorCount,
      dockCount: dockCount,
      beltCapacity: min(32 + level * 2, 64),
      beltSpeed: min(3.0 + level * 0.06, 5.0),
      feedInterval: max(0.55 - level * 0.012, 0.22),
      lanes: lanes,
      reservoir: reservoir,
    );
  }
}
