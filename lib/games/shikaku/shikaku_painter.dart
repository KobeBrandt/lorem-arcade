import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection, FontWeight;

import '../../ui/app_theme.dart';
import 'shikaku_board.dart';
import 'shikaku_game.dart';

/// Draws Shikaku: a glass panel with dark cell wells, the placed
/// rectangles in theme colors (red when they break the rules), the
/// numbers, and the rectangle being dragged with its area. Paints and
/// texts are cached, so a frame only allocates a few small objects.
class ShikakuPainter {
  final Map<String, TextPainter> _texts = {};

  final Paint _panelFill = Paint()..color = AppColors.glassFill;
  final Paint _wellFill = Paint()..color = AppColors.well;
  final Paint _border = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = AppColors.glassBorder;
  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  final Paint _glow = Paint()
    ..style = PaintingStyle.stroke
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

  TextPainter _text(String value, double size, Color color) {
    final key = '$value|$size|${color.toARGB32()}';
    final cached = _texts[key];
    if (cached != null) return cached;
    if (_texts.length > 120) _texts.clear();
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return _texts[key] = painter;
  }

  void render(Canvas canvas, ShikakuGame game) {
    final puzzle = game.puzzle;
    final cell = game.cell;
    final grid = game.gridRect;

    final panel = RRect.fromRectAndRadius(
      grid.inflate(8),
      Radius.circular(cell * 0.3 + 8),
    );
    canvas.drawRRect(panel, _panelFill);
    canvas.drawRRect(panel, _border);

    final wellRadius = Radius.circular(cell * 0.16);
    for (var row = 0; row < puzzle.rows; row++) {
      for (var col = 0; col < puzzle.cols; col++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            game.cellRect(col, row).deflate(1.5),
            wellRadius,
          ),
          _wellFill,
        );
      }
    }

    for (final placed in game.board.placed) {
      final color = placed.valid
          ? _colorOf(game, placed.rect)
          : AppColors.danger;
      final glow = identical(placed, game.lastPlaced) ? game.placeGlow : 0.0;
      _drawRect(canvas, game, placed.rect, color, glow);
    }

    final preview = game.preview;
    if (preview != null) {
      _drawRect(canvas, game, preview, AppColors.accentMint, 0);
    }

    final clueSize = max(10.0, cell * 0.44);
    for (var row = 0; row < puzzle.rows; row++) {
      for (var col = 0; col < puzzle.cols; col++) {
        final value = puzzle.clueAt(col, row);
        if (value <= 0) continue;
        final text = _text('$value', clueSize, AppColors.text);
        final center = game.cellRect(col, row).center;
        text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
      }
    }

    if (preview != null) _drawArea(canvas, game, preview);
  }

  /// Theme color of a valid rectangle, picked by the number inside it so
  /// it stays the same while the player redraws around it.
  Color _colorOf(ShikakuGame game, ShikakuRect rect) {
    final palette = game.setup.style.palette;
    for (var row = rect.top; row < rect.bottom; row++) {
      for (var col = rect.left; col < rect.right; col++) {
        if (game.puzzle.clueAt(col, row) > 0) {
          return palette[(row * 7 + col * 3) % palette.length];
        }
      }
    }
    return palette.first;
  }

  void _drawRect(
    Canvas canvas,
    ShikakuGame game,
    ShikakuRect rect,
    Color color,
    double glow,
  ) {
    final cell = game.cell;
    final topLeft = game.cellRect(rect.left, rect.top);
    final screen = Rect.fromLTWH(
      topLeft.left,
      topLeft.top,
      rect.width * cell,
      rect.height * cell,
    ).deflate(3);
    final rounded = RRect.fromRectAndRadius(
      screen,
      Radius.circular(cell * 0.2),
    );
    canvas.drawRRect(rounded, _fill..color = color.withValues(alpha: 0.26));
    if (glow > 0) {
      canvas.drawRRect(
        rounded,
        _glow
          ..color = color.withValues(alpha: 0.7 * glow)
          ..strokeWidth = 6,
      );
    }
    canvas.drawRRect(
      rounded,
      _stroke
        ..color = color
        ..strokeWidth = max(1.5, cell * 0.05),
    );
  }

  /// Area badge in the corner of the rectangle being dragged.
  void _drawArea(Canvas canvas, ShikakuGame game, ShikakuRect rect) {
    final cell = game.cell;
    final text = _text(
      '${rect.area}',
      max(10.0, cell * 0.3),
      AppColors.textOnAccent,
    );
    final corner = game.cellRect(rect.right - 1, rect.top).topRight;
    final w = max(text.width + 10, text.height + 2);
    final badge = Rect.fromLTWH(
      corner.dx - w / 2 - 3,
      corner.dy - text.height / 2 - 1 + 3,
      w,
      text.height + 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badge, Radius.circular(badge.height / 2)),
      _fill..color = AppColors.accentMint,
    );
    text.paint(canvas, badge.center - Offset(text.width / 2, text.height / 2));
  }
}
