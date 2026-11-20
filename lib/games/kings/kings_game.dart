import 'dart:math';
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';

import '../../arcade/arcade_level_game.dart';
import 'kings_board.dart';
import 'kings_generator.dart';
import 'kings_painter.dart';

/// Kings: place one king in every row, every column and every colored
/// region. No two kings may touch, not even diagonally.
///
/// A tap cycles a cell from empty to a cross (a note for the player) to
/// a king and back to empty. A king that breaks a rule stays on the
/// board and turns red, and counts as a mistake; stars come from the
/// mistakes, see [kingsStars]. The level is won as soon as all kings
/// stand and every rule holds. There is no way to lose.
///
/// Levels are endless; [generateKingsPuzzle] builds each from its level
/// number, so the same level is always the same puzzle.
class KingsGame extends ArcadeLevelGame with TapCallbacks {
  KingsGame(super.setup)
    : board = KingsBoard(generateKingsPuzzle(setup.level)) {
    _updateStatus();
  }

  /// Widest grid on tablets, in logical pixels.
  static const double maxGridSize = 520;

  final KingsBoard board;
  final KingsPainter _painter = KingsPainter();

  bool _touched = false;

  /// Grid rectangle on screen and the size of one cell.
  Rect gridRect = Rect.zero;
  double cell = 0;

  /// Real time since the start, for the clash pulse.
  double clock = 0;

  @override
  bool get hasProgress => _touched;

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    const pad = 24.0;
    final side = min(maxGridSize, min(size.x, size.y) - pad * 2);
    cell = max(1.0, side / board.size);
    final w = cell * board.size;
    gridRect = Rect.fromLTWH((size.x - w) / 2, (size.y - w) / 2, w, w);
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (cell <= 1) return;
    final p = event.canvasPosition.toOffset();
    if (!gridRect.contains(p)) return;
    final col = ((p.dx - gridRect.left) / cell).floor();
    final row = ((p.dy - gridRect.top) / cell).floor();
    tapCell(row, col);
  }

  /// A tap on the cell at [row], [col]. Public for tests.
  KingsTapOutcome tapCell(int row, int col) {
    if (result.value != null) return KingsTapOutcome.ignored;
    final outcome = board.tap(row, col);
    switch (outcome) {
      case KingsTapOutcome.ignored:
        return outcome;
      case KingsTapOutcome.crossed:
      case KingsTapOutcome.cleared:
        setup.sounds.tap();
        if (setup.haptics) HapticFeedback.selectionClick();
      case KingsTapOutcome.king:
        setup.sounds.complete(1 + min(board.kingCount ~/ 3, 3));
        if (setup.haptics) HapticFeedback.lightImpact();
      case KingsTapOutcome.clash:
        setup.sounds.blocked();
        if (setup.haptics) HapticFeedback.mediumImpact();
    }
    _touched = true;
    _updateStatus();
    if (board.solved) {
      if (setup.haptics) HapticFeedback.heavyImpact();
      finish(ArcadeResult.won(kingsStars(board.mistakes)));
    }
    return outcome;
  }

  void _updateStatus() {
    status.value =
        'Kings ${board.kingCount}/${board.size} · Mistakes ${board.mistakes}';
  }

  @override
  void update(double dt) {
    super.update(dt);
    clock += min(dt, 0.1);
  }

  @override
  void render(Canvas canvas) {
    if (cell > 1) _painter.render(canvas, this);
    super.render(canvas);
  }
}
