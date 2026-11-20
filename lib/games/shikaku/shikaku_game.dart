import 'dart:math';
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';

import '../../arcade/arcade_level_game.dart';
import 'shikaku_board.dart';
import 'shikaku_levels.dart';
import 'shikaku_painter.dart';

/// Shikaku: split the grid into rectangles. Each rectangle holds exactly
/// one number, and its area equals that number.
///
/// Drag from one cell to another to draw a rectangle; it replaces the
/// rectangles it overlaps. Tap a rectangle to remove it, or tap a free 1
/// to draw a single cell. A rectangle that breaks the rules stays on the
/// board in red and counts as a mistake. There is no way to lose; the
/// level is won when valid rectangles cover every cell.
///
/// Stars come from the mistakes, see [shikakuStars].
class ShikakuGame extends ArcadeLevelGame with DragCallbacks, TapCallbacks {
  ShikakuGame(super.setup) : puzzle = buildShikakuPuzzle(setup.level) {
    board = ShikakuBoard(puzzle);
    _updateStatus();
  }

  /// Largest cell side in logical pixels, so tablets do not get huge cells.
  static const double maxCell = 64;

  final ShikakuPuzzle puzzle;
  late final ShikakuBoard board;
  final ShikakuPainter _painter = ShikakuPainter();

  /// Grid rectangle on screen and the side of one cell.
  Rect gridRect = Rect.zero;
  double cell = 0;

  /// The rectangle being dragged, or null.
  ShikakuRect? preview;

  /// The last drawn rectangle and a glow that fades from 1 to 0.
  PlacedRect? lastPlaced;
  double placeGlow = 0;

  int? _pointer;
  (int, int)? _dragStart;

  @override
  bool get hasProgress => board.drawn > 0;

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    const pad = 16.0;
    cell = max(
      1.0,
      min(
        maxCell,
        min((size.x - pad * 2) / puzzle.cols, (size.y - pad * 2) / puzzle.rows),
      ),
    );
    final w = cell * puzzle.cols;
    final h = cell * puzzle.rows;
    gridRect = Rect.fromLTWH((size.x - w) / 2, (size.y - h) / 2, w, h);
  }

  /// Screen rectangle of a cell, for tests and the painter.
  Rect cellRect(int col, int row) => Rect.fromLTWH(
    gridRect.left + col * cell,
    gridRect.top + row * cell,
    cell,
    cell,
  );

  /// The cell under [point], or null outside the grid. With [clamp] a
  /// point outside snaps to the nearest cell.
  (int, int)? cellAt(Offset point, {bool clamp = false}) {
    if (cell <= 1) return null;
    final col = ((point.dx - gridRect.left) / cell).floor();
    final row = ((point.dy - gridRect.top) / cell).floor();
    if (clamp) {
      return (col.clamp(0, puzzle.cols - 1), row.clamp(0, puzzle.rows - 1));
    }
    if (col < 0 || row < 0 || col >= puzzle.cols || row >= puzzle.rows) {
      return null;
    }
    return (col, row);
  }

  // ---------------------------------------------------------------- input

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (_pointer != null || result.value != null) return;
    final start = cellAt(event.localPosition.toOffset());
    if (start == null) return;
    _pointer = event.pointerId;
    _dragStart = start;
    preview = ShikakuRect.spanning(start.$1, start.$2, start.$1, start.$2);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _pointer) return;
    final start = _dragStart!;
    final end = cellAt(event.localEndPosition.toOffset(), clamp: true)!;
    preview = ShikakuRect.spanning(start.$1, start.$2, end.$1, end.$2);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _pointer) return;
    final rect = preview;
    _endDrag();
    if (rect != null) draw(rect);
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (event.pointerId != _pointer) return;
    _endDrag();
  }

  void _endDrag() {
    _pointer = null;
    _dragStart = null;
    preview = null;
  }

  @override
  void onTapUp(TapUpEvent event) {
    final hit = cellAt(event.localPosition.toOffset());
    if (hit != null) tapCell(hit.$1, hit.$2);
  }

  /// A tap on a cell: removes the rectangle there, or draws a single cell
  /// on a free 1. Other free cells ignore taps, so a stray tap is never a
  /// mistake.
  void tapCell(int col, int row) {
    if (result.value != null) return;
    if (board.removeAt(col, row) != null) {
      setup.sounds.whoosh();
      if (setup.haptics) HapticFeedback.selectionClick();
      _updateStatus();
      return;
    }
    if (puzzle.clueAt(col, row) == 1) draw(ShikakuRect(col, row, 1, 1));
  }

  /// Draws [rect] on the board, replacing what it overlaps.
  void draw(ShikakuRect rect) {
    if (result.value != null || !puzzle.fits(rect)) return;
    final outcome = board.place(rect);
    lastPlaced = outcome.placed;
    placeGlow = 1;
    if (outcome.solved) {
      setup.sounds.complete(3);
      if (setup.haptics) HapticFeedback.heavyImpact();
      _updateStatus();
      finish(ArcadeResult.won(shikakuStars(board.mistakes)));
      return;
    }
    if (outcome.placed.valid) {
      setup.sounds.tap();
      if (setup.haptics) HapticFeedback.lightImpact();
    } else {
      setup.sounds.blocked();
      if (setup.haptics) HapticFeedback.mediumImpact();
    }
    _updateStatus();
  }

  void _updateStatus() {
    status.value =
        'Cells ${board.doneCells}/${puzzle.cellCount} · '
        'Mistakes ${board.mistakes}';
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (placeGlow > 0) placeGlow = max(0, placeGlow - min(dt, 0.1) * 2.5);
  }

  @override
  void render(Canvas canvas) {
    if (cell > 1) _painter.render(canvas, this);
    super.render(canvas);
  }
}
