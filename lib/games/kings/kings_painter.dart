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

/// Draws Kings in the Shikaku look: a glass panel with dark cell wells,
/// each region as one rounded, see-through shape in its color with an
/// outline, automatic crosses and crowns. Clashing kings pulse red.
class KingsPainter {
  static const Color _mark = AppColors.textMuted;
  static const Color _crown = AppColors.text;
  static const Color _stripe = Color(0x2EFFFFFF);

  /// Gap between a region outline and the cell edge, in logical pixels.
  static const double _inset = 3;

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
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Region shapes, rebuilt when the grid moves or changes size.
  List<Path> _regionPaths = const [];
  Rect _pathsFor = Rect.zero;

  void render(Canvas canvas, KingsGame game) {
    final grid = game.gridRect;
    final cell = game.cell;
    final board = game.board;
    final n = board.size;
    final palette = game.setup.style.palette;

    final panel = RRect.fromRectAndRadius(
      grid.inflate(8),
      Radius.circular(cell * 0.3 + 8),
    );
    canvas.drawRRect(panel, _panelFill);
    canvas.drawRRect(panel, _border);

    final wellRadius = Radius.circular(cell * 0.16);
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            _cellRect(game, row, col).deflate(1.5),
            wellRadius,
          ),
          _wellFill,
        );
      }
    }

    if (_pathsFor != grid || _regionPaths.length != n) {
      _regionPaths = [for (var r = 0; r < n; r++) _regionPath(game, r)];
      _pathsFor = grid;
    }
    for (var region = 0; region < n; region++) {
      final path = _regionPaths[region];
      final color = kingsRegionColor(palette, region);
      canvas.drawPath(path, _fill..color = color.withValues(alpha: 0.26));
      if (kingsRegionStriped(palette, region)) {
        canvas.save();
        canvas.clipPath(path);
        _drawStripes(canvas, grid, cell);
        canvas.restore();
      }
    }

    // Clashing kings get a red well under the region outlines.
    final clashing = board.clashingKings;
    final pulse = 0.5 + 0.5 * sin(game.clock * 6);
    _fill.color = AppColors.danger.withValues(alpha: 0.35 + 0.25 * pulse);
    for (final index in clashing) {
      final row = index ~/ n, col = index % n;
      canvas.save();
      canvas.clipPath(_regionPaths[board.puzzle.regionAt(row, col)]);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          _cellRect(game, row, col).deflate(1.5),
          wellRadius,
        ),
        _fill,
      );
      canvas.restore();
    }

    _stroke.strokeWidth = max(1.5, cell * 0.05);
    for (var region = 0; region < n; region++) {
      _stroke.color = kingsRegionColor(palette, region);
      canvas.drawPath(_regionPaths[region], _stroke);
    }

    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        final r = _cellRect(game, row, col);
        switch (board.markAt(row, col)) {
          case KingsMark.empty:
            break;
          case KingsMark.cross:
            _drawCross(canvas, r);
          case KingsMark.king:
            final color = kingsRegionColor(
              palette,
              board.puzzle.regionAt(row, col),
            );
            _drawCrown(canvas, r, clashing.contains(row * n + col), color);
        }
      }
    }
  }

  /// The cells of [region] as one shape with rounded corners, [_inset]
  /// inside the edges it shares with other regions and the grid border.
  Path _regionPath(KingsGame game, int region) {
    final puzzle = game.board.puzzle;
    final n = puzzle.size;
    bool inRegion(int row, int col) =>
        row >= 0 &&
        col >= 0 &&
        row < n &&
        col < n &&
        puzzle.regionAt(row, col) == region;

    // Border edges between grid corners, clockwise on screen, so the
    // region is always on the right. Key: start corner (x, y).
    final edges = <(int, int), List<(int, int)>>{};
    void edge(int x0, int y0, int x1, int y1) =>
        (edges[(x0, y0)] ??= []).add((x1, y1));
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        if (!inRegion(row, col)) continue;
        if (!inRegion(row - 1, col)) edge(col, row, col + 1, row);
        if (!inRegion(row, col + 1)) edge(col + 1, row, col + 1, row + 1);
        if (!inRegion(row + 1, col)) edge(col + 1, row + 1, col, row + 1);
        if (!inRegion(row, col - 1)) edge(col, row + 1, col, row);
      }
    }

    final path = Path();
    while (edges.isNotEmpty) {
      // Walk one closed loop and keep only the corners.
      final corners = <(int, int)>[];
      final start = edges.keys.first;
      var at = start;
      (int, int)? dir;
      do {
        final outs = edges[at]!;
        // Where two loops touch at a corner, turn right so each loop
        // stays its own shape.
        var pick = 0;
        if (outs.length > 1 && dir != null) {
          final right = (-dir.$2, dir.$1);
          pick = outs.indexWhere((o) => (o.$1 - at.$1, o.$2 - at.$2) == right);
          if (pick < 0) pick = 0;
        }
        final next = outs.removeAt(pick);
        if (outs.isEmpty) edges.remove(at);
        final step = (next.$1 - at.$1, next.$2 - at.$2);
        if (step != dir) corners.add(at);
        dir = step;
        at = next;
      } while (at != start);
      if (corners.length > 1 && dir == _dirAt(corners[0], corners[1])) {
        corners.removeAt(0);
      }
      _addRoundedLoop(path, game, corners);
    }
    return path;
  }

  (int, int) _dirAt((int, int) from, (int, int) to) =>
      ((to.$1 - from.$1).sign, (to.$2 - from.$2).sign);

  /// Adds the clockwise grid loop [corners] to [path]: moved [_inset]
  /// inward, with round corners.
  void _addRoundedLoop(Path path, KingsGame game, List<(int, int)> corners) {
    final cell = game.cell;
    final grid = game.gridRect;
    final count = corners.length;
    final points = <Offset>[];
    for (var i = 0; i < count; i++) {
      final dirIn = _dirAt(corners[(i - 1 + count) % count], corners[i]);
      final dirOut = _dirAt(corners[i], corners[(i + 1) % count]);
      // Inward is right of the travel direction: (-dy, dx).
      final nx = -dirIn.$2 - dirOut.$2;
      final ny = dirIn.$1 + dirOut.$1;
      points.add(
        Offset(
          grid.left + corners[i].$1 * cell + nx * _inset,
          grid.top + corners[i].$2 * cell + ny * _inset,
        ),
      );
    }
    final radius = cell * 0.2;
    for (var i = 0; i < count; i++) {
      final prev = points[(i - 1 + count) % count];
      final p = points[i];
      final next = points[(i + 1) % count];
      final r = min(radius, min((p - prev).distance, (next - p).distance) / 2);
      final a = p + _unit(prev - p) * r;
      final b = p + _unit(next - p) * r;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.conicTo(p.dx, p.dy, b.dx, b.dy, sqrt1_2);
    }
    path.close();
  }

  Offset _unit(Offset v) => v / v.distance;

  Rect _cellRect(KingsGame game, int row, int col) => Rect.fromLTWH(
    game.gridRect.left + col * game.cell,
    game.gridRect.top + row * game.cell,
    game.cell,
    game.cell,
  );

  /// Diagonal stripes over the whole grid; draw them under a clip.
  void _drawStripes(Canvas canvas, Rect grid, double cell) {
    final step = cell / 4;
    _stroke
      ..color = _stripe
      ..strokeWidth = max(1.0, step * 0.35);
    final count = (grid.width * 2 / step).ceil();
    for (var i = 0; i <= count; i++) {
      final x = grid.left + i * step;
      canvas.drawLine(
        Offset(x - grid.height, grid.bottom),
        Offset(x, grid.top),
        _stroke,
      );
    }
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
  void _drawCrown(Canvas canvas, Rect r, bool clash, Color gem) {
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
    _fill.color = clash ? _crown : gem;
    for (final p in [at(0.2, 0.36), at(0.5, 0.27), at(0.8, 0.36)]) {
      canvas.drawCircle(p, s * 0.05, _fill);
    }
  }
}
