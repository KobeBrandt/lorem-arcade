/// Pure game rules, shared by the live game and the level solver.
///
/// Tubes are ordered left to right. Blocks on the loop travel along the
/// bottom edge from right to left, so after leaving tube `s` a block passes
/// tubes `s-1, s-2, ..., 0`, then wraps to `n-1, n-2, ..., s`.
/// The source tube is checked last (after one full lap).
///
/// Special blocks:
/// - Rainbow: stored as [Board.rainbow] in [tubes]. It is wild: any color
///   lands on it, it lands on any tube top, and it counts as any color for a
///   complete tube. A tap never takes it along with other blocks: a rainbow
///   on top leaves alone (even from a complete tube), and a run below the
///   top stops at a rainbow. So a rainbow in the wrong tube can always be
///   moved again.
/// - Locked: positions in [locked]. A locked block never moves, stops a
///   run, takes no blocks on top, and keeps its tube from being complete.
///   Every completed tube opens one locked block (see [unlockOne]).
/// - Hidden: positions in [hidden]. Only a look: rules use the true color.
///   A hidden block is revealed for good once it is the top of its tube.
///
/// Locked and hidden blocks never move while they are locked or hidden
/// (blocks only leave from the top), so their index in the tube is stable.
class Board {
  Board({
    required this.tubes,
    required this.tubeSize,
    List<Set<int>>? locked,
    List<Set<int>>? hidden,
  }) : locked = locked ?? [for (final _ in tubes) <int>{}],
       hidden = hidden ?? [for (final _ in tubes) <int>{}];

  /// Color id of a rainbow block.
  static const int rainbow = -1;

  /// Each tube is a list of color ids, bottom first.
  final List<List<int>> tubes;
  final int tubeSize;

  /// Per tube: indices (from the bottom) of locked blocks.
  final List<Set<int>> locked;

  /// Per tube: indices (from the bottom) of hidden blocks.
  final List<Set<int>> hidden;

  Board copy() => Board(
    tubes: [for (final t in tubes) List<int>.of(t)],
    tubeSize: tubeSize,
    locked: [for (final s in locked) Set<int>.of(s)],
    hidden: [for (final s in hidden) Set<int>.of(s)],
  );

  int get tubeCount => tubes.length;

  /// Adds an empty tube on the right (rush mode).
  void addTube() {
    tubes.add(<int>[]);
    locked.add(<int>{});
    hidden.add(<int>{});
  }

  bool isLocked(int tube, int index) => locked[tube].contains(index);

  bool isHidden(int tube, int index) => hidden[tube].contains(index);

  int get lockedCount => locked.fold(0, (n, s) => n + s.length);

  /// Number of top blocks of [tube] that a block of [color] joins: blocks
  /// of that color or rainbows, stopping at a locked block. For a rainbow
  /// [color], the run takes the color of the first non-rainbow block.
  int runFor(int tube, int color) {
    final t = tubes[tube];
    final lock = locked[tube];
    var runColor = color;
    var n = 0;
    for (var i = t.length - 1; i >= 0; i--) {
      if (lock.contains(i)) break;
      final block = t[i];
      if (block != rainbow) {
        if (runColor == rainbow) runColor = block;
        if (block != runColor) break;
      }
      n++;
    }
    return n;
  }

  /// Length of the run a tap on [tube] sends into the loop. 0 when the
  /// tube is empty or its top is locked. A rainbow on top leaves alone;
  /// other runs stop at a rainbow.
  int topRunLength(int tube) {
    final t = tubes[tube];
    final lock = locked[tube];
    if (t.isEmpty || lock.contains(t.length - 1)) return 0;
    final color = t.last;
    if (color == rainbow) return 1;
    var n = 0;
    for (var i = t.length - 1; i >= 0; i--) {
      if (lock.contains(i) || t[i] != color) break;
      n++;
    }
    return n;
  }

  /// A tap is allowed on a complete tube only to move its rainbow out.
  bool canTapComplete(int tube) =>
      tubes[tube].isNotEmpty && tubes[tube].last == rainbow;

  /// Removes the top run of [tube] and returns it, top block first.
  /// The new top block is revealed.
  List<int> takeRun(int tube) {
    final run = topRunLength(tube);
    final t = tubes[tube];
    final taken = [for (var i = 0; i < run; i++) t.removeLast()];
    hidden[tube].removeWhere((i) => i >= t.length - 1);
    return taken;
  }

  /// True when a tube is full, has no locked block, and every block that
  /// is not a rainbow has the same color.
  bool isComplete(int tube) {
    final t = tubes[tube];
    if (t.length != tubeSize || locked[tube].isNotEmpty) return false;
    var color = rainbow;
    for (final c in t) {
      if (c == rainbow) continue;
      if (color == rainbow) color = c;
      if (c != color) return false;
    }
    return true;
  }

  List<bool> completeFlags() => [
    for (var i = 0; i < tubeCount; i++) isComplete(i),
  ];

  /// Opens one locked block: the topmost one of the leftmost tube that
  /// has any. Returns its tube, or null when nothing is locked.
  int? unlockOne() {
    for (var i = 0; i < tubeCount; i++) {
      final lock = locked[i];
      if (lock.isEmpty) continue;
      lock.remove(lock.reduce((a, b) => a > b ? a : b));
      return i;
    }
    return null;
  }

  /// Opens one locked block for every tube that is complete now but was
  /// not in [before]. An opened block can complete another tube, which
  /// opens the next one. Returns the newly completed tubes in order.
  List<int> settleCompletions(List<bool> before) {
    final done = List<bool>.of(before);
    final completed = <int>[];
    var found = true;
    while (found) {
      found = false;
      for (var i = 0; i < tubeCount; i++) {
        if (done[i] || !isComplete(i)) continue;
        done[i] = true;
        completed.add(i);
        unlockOne();
        found = true;
      }
    }
    return completed;
  }

  /// Win: every tube is empty or complete.
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

  /// State key for the solver. Hidden blocks do not change the rules, so
  /// they are left out.
  String key() {
    final colors = tubes.map((t) => t.join(',')).join('|');
    if (lockedCount == 0) return colors;
    final locks = [for (final s in locked) (s.toList()..sort()).join(',')]
        .join('|');
    return '$colors#$locks';
  }
}

/// Tracks blocks that are on their way into a tube but have not landed yet,
/// so that eligibility checks see the tube as it will be.
class TubeReservations {
  TubeReservations(int tubeCount)
    : incoming = List.generate(tubeCount, (_) => <int>[]),
      incomingLocked = List.generate(tubeCount, (_) => <bool>[]);

  final List<List<int>> incoming;

  /// Per tube, parallel to [incoming]: true for a locked block (rush).
  final List<List<bool>> incomingLocked;

  /// A tube accepts [color] when it has free space and is empty or its
  /// top (counting incoming blocks) matches. Rainbows match anything.
  /// Nothing lands on a locked top, or on a locked block still falling in.
  bool accepts(Board board, int tube, int color) {
    final t = board.tubes[tube];
    final pending = incoming[tube];
    final used = t.length + pending.length;
    if (used >= board.tubeSize) return false;
    if (used == 0) return true;
    if (incomingLocked[tube].contains(true)) return false;
    if (pending.isEmpty && board.isLocked(tube, t.length - 1)) return false;
    final top = pending.isNotEmpty ? pending.last : t.last;
    return top == color || top == Board.rainbow || color == Board.rainbow;
  }

  /// Rush spawns: a tube takes any color when it has free space and its
  /// top (counting incoming blocks) is not locked.
  bool hasRoom(Board board, int tube) {
    final t = board.tubes[tube];
    final pending = incoming[tube];
    if (t.length + pending.length >= board.tubeSize) return false;
    if (incomingLocked[tube].contains(true)) return false;
    if (pending.isEmpty && t.isNotEmpty && board.isLocked(tube, t.length - 1)) {
      return false;
    }
    return true;
  }

  /// Tracks one more tube (see [Board.addTube]).
  void addTube() {
    incoming.add(<int>[]);
    incomingLocked.add(<bool>[]);
  }

  void reserve(int tube, int color, {bool locked = false}) {
    incoming[tube].add(color);
    incomingLocked[tube].add(locked);
  }

  /// Called when the first reserved block of [tube] lands.
  int land(Board board, int tube) {
    final color = incoming[tube].removeAt(0);
    final locked = incomingLocked[tube].removeAt(0);
    board.tubes[tube].add(color);
    if (locked) board.locked[tube].add(board.tubes[tube].length - 1);
    return color;
  }

  /// Lands the reserved block of [tube] with [color] and [locked], even
  /// when blocks reach the tube in another order than they were reserved
  /// (rush). A locked block stays locked in the tube.
  void landBlock(Board board, int tube, int color, {bool locked = false}) {
    final pending = incoming[tube];
    final flags = incomingLocked[tube];
    var i = 0;
    for (var k = 0; k < pending.length; k++) {
      if (pending[k] == color && flags[k] == locked) {
        i = k;
        break;
      }
    }
    pending.removeAt(i);
    flags.removeAt(i);
    board.tubes[tube].add(color);
    if (locked) board.locked[tube].add(board.tubes[tube].length - 1);
  }

  /// Lands every reserved block.
  void landAll(Board board) {
    for (var t = 0; t < incoming.length; t++) {
      while (isBusy(t)) {
        land(board, t);
      }
    }
  }

  bool isBusy(int tube) => incoming[tube].isNotEmpty;

  /// Routing score for putting [color] into [tube]; null when the tube
  /// does not accept it. Higher is better:
  /// - matching top: 10 + number of matching blocks on top (see
  ///   [Board.runFor]; blocks still falling in count too)
  /// - empty tube: 1
  int? score(Board board, int tube, int color) {
    if (!accepts(board, tube, color)) return null;
    final t = board.tubes[tube];
    final pending = incoming[tube];
    if (t.isEmpty && pending.isEmpty) return 1;
    final onTube = t.isEmpty ? 0 : board.runFor(tube, color);
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
