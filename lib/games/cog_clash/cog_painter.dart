import 'dart:math';

import 'package:flutter/painting.dart';

/// Toothed circle centered on the origin. [radius] is the tip radius.
Path gearPath(double radius, int teeth, {double depth = 0.18}) {
  final inner = radius * (1 - depth);
  final step = 2 * pi / teeth;
  final path = Path();
  for (var i = 0; i < teeth; i++) {
    final a = i * step;
    final points = [
      (inner, a),
      (radius, a + step * 0.18),
      (radius, a + step * 0.45),
      (inner, a + step * 0.63),
    ];
    for (final (r, angle) in points) {
      final p = Offset(cos(angle) * r, sin(angle) * r);
      if (i == 0 && angle == a) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
  }
  return path..close();
}

/// Keeps laid out text so render does not build it every frame.
/// Starts over once it holds [maxEntries] texts, so changing numbers
/// (hit points, damage) cannot grow it without limit.
class TextCache {
  static const int maxEntries = 120;

  final Map<String, TextPainter> _cache = {};

  /// Number of cached texts.
  int get length => _cache.length;

  TextPainter get(
    String text, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w700,
  }) {
    final key = '$text|$size|${color.toARGB32()}|${weight.value}';
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= maxEntries) _cache.clear();
    return _cache[key] = (TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, fontWeight: weight, color: color),
      ),
    )..layout());
  }

  /// Paints [text] centered on [center].
  void paintCentered(
    Canvas canvas,
    String text,
    Offset center, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w700,
  }) {
    final p = get(text, size: size, color: color, weight: weight);
    p.paint(canvas, center - Offset(p.width / 2, p.height / 2));
  }

  void clear() => _cache.clear();
}
