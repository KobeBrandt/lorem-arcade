import 'dart:math';

/// One square of the field.
typedef Cell = ({int x, int y});

/// Where the cow walks. Screen y grows downward.
enum Heading {
  up(0, -1),
  down(0, 1),
  left(-1, 0),
  right(1, 0);

  const Heading(this.dx, this.dy);

  final int dx;
  final int dy;

  Heading get opposite => switch (this) {
    Heading.up => Heading.down,
    Heading.down => Heading.up,
    Heading.left => Heading.right,
    Heading.right => Heading.left,
  };
}

/// What one step did.
enum StepOutcome {
  /// The cow waits for the first turn.
  idle,
  moved,
  ate,

  /// The cow walked into the fence, a rock or its own tail.
  crashed,
}

/// Field of Moo Munch: a cow that grows a tail of spots for every carrot
/// it eats. Pure logic, no drawing, so tests can play it step by step.
///
/// The cow stands still until the first [turn]. It starts facing right
/// with its tail to the left, so the first turn may not be left.
class MooMunchBoard {
  MooMunchBoard({
    required this.cols,
    required this.rows,
    Set<Cell> rocks = const {},
    int seed = 1,
    this.startLength = 3,
  }) : rocks = Set.unmodifiable(rocks),
       _random = Random(seed) {
    _reachable = _floodFrom(startHead);
    _placeCow();
    _spawnCarrot();
  }

  final int cols;
  final int rows;
  final Set<Cell> rocks;
  final int startLength;
  final Random _random;

  /// Head first.
  final List<Cell> body = [];

  /// Cells the cow can reach from the start. Carrots only grow there.
  late final List<Cell> _reachable;

  Heading facing = Heading.right;
  bool moving = false;
  final List<Heading> _turns = [];

  /// The carrot to eat, or null when the field has no free cell left.
  Cell? carrot;

  Cell get head => body.first;

  Cell get startHead => (x: cols ~/ 2, y: rows ~/ 2);

  /// Queues a turn for the next steps (at most 2 ahead). A turn back into
  /// the cow's own neck or into the way it already goes is ignored.
  /// Returns whether the turn was taken.
  bool turn(Heading heading) {
    final last = _turns.isEmpty ? facing : _turns.last;
    if (heading == last || heading == last.opposite || _turns.length >= 2) {
      return false;
    }
    _turns.add(heading);
    return true;
  }

  /// Moves the cow one cell.
  StepOutcome step() {
    if (!moving) {
      if (_turns.isEmpty) return StepOutcome.idle;
      moving = true;
    }
    if (_turns.isNotEmpty) facing = _turns.removeAt(0);
    final next = (x: head.x + facing.dx, y: head.y + facing.dy);
    final eats = next == carrot;
    // The tail tip moves away this step unless the cow grows.
    final blocking = eats ? body : body.sublist(0, body.length - 1);
    if (!_inside(next) || rocks.contains(next) || blocking.contains(next)) {
      return StepOutcome.crashed;
    }
    body.insert(0, next);
    if (!eats) {
      body.removeLast();
      return StepOutcome.moved;
    }
    _spawnCarrot();
    return StepOutcome.ate;
  }

  /// Puts the cow back at the start, short and waiting. The carrot stays
  /// unless the cow now stands on it.
  void reset() {
    _placeCow();
    if (carrot == null || body.contains(carrot)) _spawnCarrot();
  }

  void _placeCow() {
    body
      ..clear()
      ..addAll([
        for (var i = 0; i < startLength; i++)
          (x: startHead.x - i, y: startHead.y),
      ]);
    facing = Heading.right;
    moving = false;
    _turns.clear();
  }

  void _spawnCarrot() {
    final free = [
      for (final cell in _reachable)
        if (!body.contains(cell)) cell,
    ];
    carrot = free.isEmpty ? null : free[_random.nextInt(free.length)];
  }

  bool _inside(Cell c) => c.x >= 0 && c.y >= 0 && c.x < cols && c.y < rows;

  List<Cell> _floodFrom(Cell start) {
    final seen = <Cell>{start};
    final queue = [start];
    while (queue.isNotEmpty) {
      final cell = queue.removeLast();
      for (final h in Heading.values) {
        final next = (x: cell.x + h.dx, y: cell.y + h.dy);
        if (_inside(next) && !rocks.contains(next) && seen.add(next)) {
          queue.add(next);
        }
      }
    }
    // Stable order, so a seed always gives the same carrots.
    return seen.toList()..sort((a, b) => a.y != b.y ? a.y - b.y : a.x - b.x);
  }
}
