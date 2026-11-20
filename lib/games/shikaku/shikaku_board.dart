/// A rectangle of whole cells on a Shikaku grid. Column [left] and row
/// [top] are 0-based; [width] and [height] are at least 1.
class ShikakuRect {
  const ShikakuRect(this.left, this.top, this.width, this.height);

  /// The smallest rectangle that holds both cells, in any order.
  factory ShikakuRect.spanning(int col1, int row1, int col2, int row2) {
    final left = col1 < col2 ? col1 : col2;
    final top = row1 < row2 ? row1 : row2;
    return ShikakuRect(
      left,
      top,
      (col1 - col2).abs() + 1,
      (row1 - row2).abs() + 1,
    );
  }

  final int left;
  final int top;
  final int width;
  final int height;

  /// One past the last column and row.
  int get right => left + width;
  int get bottom => top + height;

  int get area => width * height;

  bool contains(int col, int row) =>
      col >= left && col < right && row >= top && row < bottom;

  bool overlaps(ShikakuRect other) =>
      left < other.right &&
      other.left < right &&
      top < other.bottom &&
      other.top < bottom;

  @override
  bool operator ==(Object other) =>
      other is ShikakuRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'ShikakuRect($left, $top, ${width}x$height)';
}

/// One Shikaku puzzle: a grid with numbered cells and the solution it was
/// built from.
class ShikakuPuzzle {
  ShikakuPuzzle({
    required this.cols,
    required this.rows,
    required List<int> clues,
    required List<ShikakuRect> solution,
  }) : assert(clues.length == cols * rows),
       clues = List.unmodifiable(clues),
       solution = List.unmodifiable(solution);

  final int cols;
  final int rows;

  /// The number in each cell, row by row (index `row * cols + col`), or 0
  /// when the cell has none.
  final List<int> clues;

  /// The one way to split the grid, one rectangle per number.
  final List<ShikakuRect> solution;

  int get cellCount => cols * rows;

  int clueAt(int col, int row) => clues[row * cols + col];

  /// Whether [rect] holds exactly one number and its area equals it.
  bool isValid(ShikakuRect rect) {
    var value = 0;
    var count = 0;
    for (var row = rect.top; row < rect.bottom; row++) {
      for (var col = rect.left; col < rect.right; col++) {
        final clue = clueAt(col, row);
        if (clue > 0) {
          count++;
          value = clue;
        }
      }
    }
    return count == 1 && value == rect.area;
  }

  /// Whether [rect] lies fully inside the grid.
  bool fits(ShikakuRect rect) =>
      rect.left >= 0 &&
      rect.top >= 0 &&
      rect.width >= 1 &&
      rect.height >= 1 &&
      rect.right <= cols &&
      rect.bottom <= rows;
}

/// A rectangle the player drew, with its rule check.
class PlacedRect {
  const PlacedRect(this.rect, {required this.valid});

  final ShikakuRect rect;

  /// False when it breaks the rules; it is drawn red.
  final bool valid;
}

/// What drawing one rectangle did.
class PlaceOutcome {
  const PlaceOutcome({
    required this.placed,
    required this.replaced,
    required this.solved,
  });

  final PlacedRect placed;

  /// Rectangles the new one overlapped; they were removed.
  final List<PlacedRect> replaced;

  /// True when this rectangle completed the puzzle.
  final bool solved;
}

/// The player's split of a [ShikakuPuzzle]. Pure logic, no drawing, so
/// tests can play it rectangle by rectangle.
///
/// Every drawn rectangle that breaks the rules (not exactly one number
/// inside, or an area that differs from it) stays on the board and adds
/// one to [mistakes].
class ShikakuBoard {
  ShikakuBoard(this.puzzle);

  final ShikakuPuzzle puzzle;
  final List<PlacedRect> _placed = [];

  /// Rule-breaking rectangles drawn so far.
  int mistakes = 0;

  /// Rectangles drawn so far, including removed ones.
  int drawn = 0;

  List<PlacedRect> get placed => List.unmodifiable(_placed);

  /// The placed rectangle on that cell, or null.
  PlacedRect? at(int col, int row) {
    for (final p in _placed) {
      if (p.rect.contains(col, row)) return p;
    }
    return null;
  }

  /// Cells covered by rule-keeping rectangles.
  int get doneCells {
    var cells = 0;
    for (final p in _placed) {
      if (p.valid) cells += p.rect.area;
    }
    return cells;
  }

  /// True when valid rectangles cover every cell. Placed rectangles never
  /// overlap, so their areas add up to the covered cells.
  bool get isSolved =>
      _placed.every((p) => p.valid) && doneCells == puzzle.cellCount;

  /// Draws [rect]. Rectangles it overlaps are removed first.
  PlaceOutcome place(ShikakuRect rect) {
    assert(puzzle.fits(rect));
    final replaced = _placed.where((p) => p.rect.overlaps(rect)).toList();
    _placed.removeWhere((p) => p.rect.overlaps(rect));
    final placed = PlacedRect(rect, valid: puzzle.isValid(rect));
    _placed.add(placed);
    drawn++;
    if (!placed.valid) mistakes++;
    return PlaceOutcome(placed: placed, replaced: replaced, solved: isSolved);
  }

  /// Removes the rectangle on that cell. Returns it, or null when the cell
  /// was empty.
  PlacedRect? removeAt(int col, int row) {
    final hit = at(col, row);
    if (hit != null) _placed.remove(hit);
    return hit;
  }
}

/// Stars for a won level by rule-breaking rectangles drawn: 3 with none,
/// 2 with one or two, else 1.
int shikakuStars(int mistakes) {
  if (mistakes <= 0) return 3;
  if (mistakes <= 2) return 2;
  return 1;
}
