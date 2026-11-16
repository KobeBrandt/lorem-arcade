/// Pure game rules, shared by the live game and the level solver.
///
/// Tubes are ordered left to right. Blocks on the loop travel along the
/// bottom edge from right to left, so after leaving tube `s` a block passes
/// tubes `s-1, s-2, ..., 0`, then wraps to `n-1, n-2, ..., s`.
/// The source tube is checked last (after one full lap).
class Board {
  Board({required this.tubes, required this.tubeSize});

  /// Each tube is a list of color ids, bottom first.
  final List<List<int>> tubes;
  final int tubeSize;

  Board copy() => Board(
    tubes: [for (final t in tubes) List<int>.of(t)],
    tubeSize: tubeSize,
  );

  int get tubeCount => tubes.length;

  /// Length of the same-color run on top of [tube]. 0 when empty.
  int topRunLength(int tube) {
    final t = tubes[tube];
    if (t.isEmpty) return 0;
    final color = t.last;
    var n = 0;
    for (var i = t.length - 1; i >= 0 && t[i] == color; i--) {
      n++;
    }
    return n;
  }

  /// True when a tube is full of one color.
  bool isComplete(int tube) {
    final t = tubes[tube];
    return t.length == tubeSize && t.every((c) => c == t.first);
  }

  /// Win: every tube is empty or full of one color.
  bool get isWon {
    for (var i = 0; i < tubes.length; i++) {
      if (tubes[i].isNotEmpty && !isComplete(i)) return false;
    }
    return true;
  }

  /// Order in which a block released from [source] passes the tubes.
  List<int> passOrder(int source) => [
    for (var i = source - 1; i >= 0; i--) i,
    for (var i = tubeCount - 1; i > source; i--) i,
    source,
  ];

  String key() => tubes.map((t) => t.join(',')).join('|');
}

/// Tracks blocks that are on their way into a tube but have not landed yet,
/// so that eligibility checks see the tube as it will be.
class TubeReservations {
  TubeReservations(int tubeCount)
    : incoming = List.generate(tubeCount, (_) => <int>[]);

  final List<List<int>> incoming;

  /// A tube accepts [color] when it has free space and is empty or its
  /// top color (counting incoming blocks) matches.
  bool accepts(Board board, int tube, int color) {
    final t = board.tubes[tube];
    final pending = incoming[tube];
    final used = t.length + pending.length;
    if (used >= board.tubeSize) return false;
    if (used == 0) return true;
    final top = pending.isNotEmpty ? pending.last : t.last;
    return top == color;
  }

  void reserve(int tube, int color) => incoming[tube].add(color);

  /// Called when the first reserved block of [tube] lands.
  int land(Board board, int tube) {
    final color = incoming[tube].removeAt(0);
    board.tubes[tube].add(color);
    return color;
  }

  bool isBusy(int tube) => incoming[tube].isNotEmpty;

  /// Routing score for putting [color] into [tube]; null when the tube
  /// does not accept it. Higher is better:
  /// - matching top: 10 + number of same-color blocks on top
  ///   (blocks still falling in count too)
  /// - empty tube: 1
  int? score(Board board, int tube, int color) {
    if (!accepts(board, tube, color)) return null;
    final t = board.tubes[tube];
    final pending = incoming[tube];
    if (t.isEmpty && pending.isEmpty) return 1;
    final onTube = t.isNotEmpty && t.last == color
        ? board.topRunLength(tube)
        : 0;
    return 10 + onTube + pending.length;
  }

  /// Best tube for [color] among [order] (the tubes in the order the block
  /// will pass them). Highest score wins; ties go to the first one passed.
  /// Returns null when no tube accepts the color.
  int? chooseTube(Board board, List<int> order, int color) {
    int? best;
    var bestScore = 0;
    for (final tube in order) {
      final s = score(board, tube, color);
      if (s != null && s > bestScore) {
        best = tube;
        bestScore = s;
      }
    }
    return best;
  }
}
