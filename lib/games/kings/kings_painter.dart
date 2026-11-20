import 'dart:math';
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

import '../../ui/app_theme.dart';
import 'kings_board.dart';
import 'kings_game.dart';

/// Fill color of [region]. Themes have 6 colors and grids up to 9
/// regions, so regions past the palette reuse a color in a darker shade;
/// they also get stripes, see [kingsRegionStriped].
Color kingsRegionColor(List<Color> palette, int region) {
  final base = palette[region % palette.length];
  if (region < palette.length) return base;
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness(hsl.lightness * 0.6).toColor();
}

/// True when [region] reuses a palette color and is drawn with stripes.
bool kingsRegionStriped(List<Color> palette, int region) =>
    region >= palette.length;

/// Draws Kings: a glass panel with the colored region grid, region
/// borders, crosses and crowns. Clashing kings pulse red.
class KingsPainter {
  static const Color _line = Color(0x33000000);
  static const Color _border = AppColors.well;
  static const Color _mark = Color(0xB314121F);
  static const Color _crown = AppColors.textOnAccent;
  static const Color _gem = Color(0xFFFFFFFF);
  static const Color _stripe = Color(0x2EFFFFFF);

  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void render(Canvas canvas, KingsGame game) {
    final grid = game.gridRect;
    final cell = game.cell;
    final board = game.board;
    final puzzle = board.puzzle;
    final n = board.size;
    final palette = game.setup.style.palette;

    // Glass panel behind the grid.
    final panel = RRect.fromRectAndRadius(
      grid.inflate(10),
      const Radius.circular(AppRadii.tube + 4),
    );
    canvas.drawRRect(panel, _fill..color = AppColors.glassFill);
    canvas.drawRRect(
      panel,
      _stroke
        ..color = AppColors.glassBorder
        ..strokeWidth = 1.5,
    );

    final rounded = RRect.fromRectAndRadius(
      grid,
      const Radius.circular(AppRadii.tube),
    );
    canvas.save();
    canvas.clipRRect(rounded);

    // Region fills, with stripes on regions that reuse a color.
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final region = puzzle.regionAt(row, col);
        final r = _cellRect(game, row, col);
        canvas.drawRect(r, _fill..color = kingsRegionColor(palette, region));
        if (kingsRegionStriped(palette, region)) _drawStripes(canvas, r);
      }
    }

    // Thin cell lines.
    _stroke
      ..color = _line
      ..strokeWidth = 1;
    for (var i = 1; i < n; i++) {
      final x = grid.left + i * cell;
      final y = grid.top + i * cell;
      canvas.drawLine(Offset(x, grid.top), Offset(x, grid.bottom), _stroke);
      canvas.drawLine(Offset(grid.left, y), Offset(grid.right, y), _stroke);
    }

    // Thick borders between regions.
    _stroke
      ..color = _border
      ..strokeWidth = max(2.0, cell * 0.07);
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final region = puzzle.regionAt(row, col);
        final r = _cellRect(game, row, col);
        if (col < n - 1 && puzzle.regionAt(row, col + 1) != region) {
          canvas.drawLine(r.topRight, r.bottomRight, _stroke);
        }
        if (row < n - 1 && puzzle.regionAt(row + 1, col) != region) {
          canvas.drawLine(r.bottomLeft, r.bottomRight, _stroke);
        }
      }
    }

    // Marks.
    final clashing = board.clashingKings;
    final pulse = 0.5 + 0.5 * sin(game.clock * 6);
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final r = _cellRect(game, row, col);
        switch (board.markAt(row, col)) {
          case KingsMark.empty:
            break;
          case KingsMark.cross:
            _drawCross(canvas, r);
          case KingsMark.king:
            final clash = clashing.contains(row * n + col);
            if (clash) {
              canvas.drawRect(
                r,
                _fill
                  ..color = AppColors.danger.withValues(
                    alpha: 0.35 + 0.25 * pulse,
                  ),
              );
            }
            _drawCrown(canvas, r, clash);
        }
      }
    }
    canvas.restore();

    canvas.drawRRect(
      rounded,
      _stroke
        ..color = _border
        ..strokeWidth = max(2.0, cell * 0.07),
    );
  }

  Rect _cellRect(KingsGame game, int row, int col) => Rect.fromLTWH(
    game.gridRect.left + col * game.cell,
    game.gridRect.top + row * game.cell,
    game.cell,
    game.cell,
  );

  /// Diagonal stripes; the spacing divides the cell so they line up
  /// across neighboring cells.
  void _drawStripes(Canvas canvas, Rect r) {
    canvas.save();
    canvas.clipRect(r);
    final step = r.width / 4;
    _stroke
      ..color = _stripe
      ..strokeWidth = max(1.0, step * 0.35);
    for (var i = 0; i <= 8; i++) {
      final x = r.left + i * step;
      canvas.drawLine(Offset(x - r.width, r.bottom), Offset(x, r.top), _stroke);
    }
    canvas.restore();
  }

  void _drawCross(Canvas canvas, Rect r) {
    final c = r.center;
    final d = r.width * 0.14;
    _stroke
      ..color = _mark
      ..strokeWidth = max(1.5, r.width * 0.07);
    canvas.drawLine(c.translate(-d, -d), c.translate(d, d), _stroke);
    canvas.drawLine(c.translate(-d, d), c.translate(d, -d), _stroke);
  }

  /// A crown with three points and a gem on each point.
  void _drawCrown(Canvas canvas, Rect r, bool clash) {
    final s = r.width;
    Offset at(double x, double y) => Offset(r.left + s * x, r.top + s * y);
    final body = Path()
      ..moveTo(at(0.22, 0.72).dx, at(0.22, 0.72).dy)
      ..lineTo(at(0.2, 0.38).dx, at(0.2, 0.38).dy)
      ..lineTo(at(0.36, 0.52).dx, at(0.36, 0.52).dy)
      ..lineTo(at(0.5, 0.3).dx, at(0.5, 0.3).dy)
      ..lineTo(at(0.64, 0.52).dx, at(0.64, 0.52).dy)
      ..lineTo(at(0.8, 0.38).dx, at(0.8, 0.38).dy)
      ..lineTo(at(0.78, 0.72).dx, at(0.78, 0.72).dy)
      ..close();
    final fill = clash ? AppColors.danger : _crown;
    canvas.drawPath(body, _fill..color = fill);
    if (clash) {
      canvas.drawPath(
        body,
        _stroke
          ..color = _crown
          ..strokeWidth = max(1.0, s * 0.04),
      );
    }
    // Band under the points.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          r.left + s * 0.22,
          r.top + s * 0.64,
          r.right - s * 0.22,
          r.top + s * 0.74,
        ),
        Radius.circular(s * 0.03),
      ),
      _fill..color = fill,
    );
    _fill.color = clash ? _crown : _gem;
    for (final p in [at(0.2, 0.36), at(0.5, 0.27), at(0.8, 0.36)]) {
      canvas.drawCircle(p, s * 0.05, _fill);
    }
  }
}
