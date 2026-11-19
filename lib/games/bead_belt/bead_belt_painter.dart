import 'package:flutter/painting.dart';

import '../../ui/app_theme.dart';

/// Drawing helpers for Bead Belt: buckets, beads and cached labels.
class BeadBeltPainter {
  final Map<String, TextPainter> _labels = {};

  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  final Paint _shine = Paint()..color = const Color(0x59FFFFFF);

  /// A bucket in [rect]: a tapered body in [color], filled up to [fill]
  /// (0..1), with an optional [label] in the middle.
  void bucket(
    Canvas canvas,
    Rect rect,
    Color color, {
    double fill = 0,
    String? label,
    double opacity = 1,
    bool highlight = false,
  }) {
    final body = _bodyPath(rect);
    _fill.color = color.withValues(alpha: 0.22 * opacity);
    canvas.drawPath(body, _fill);
    if (fill > 0) {
      canvas.save();
      canvas.clipPath(body);
      final top = rect.bottom - rect.height * fill.clamp(0.0, 1.0);
      _fill.color = color.withValues(alpha: 0.9 * opacity);
      canvas.drawRect(
        Rect.fromLTRB(rect.left, top, rect.right, rect.bottom),
        _fill,
      );
      canvas.restore();
    }
    _stroke
      ..strokeWidth = highlight ? 3 : 2
      ..color = (highlight ? AppColors.accentMint : color).withValues(
        alpha: opacity,
      );
    canvas.drawPath(body, _stroke);
    // Rim.
    _fill.color = color.withValues(alpha: opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left - 2, rect.top - 3, rect.width + 4, 6),
        const Radius.circular(3),
      ),
      _fill,
    );
    if (label != null) {
      final painter = text(label, rect.height * 0.32, AppColors.text);
      canvas.saveLayer(
        rect.inflate(4),
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
      );
      painter.paint(
        canvas,
        rect.center - Offset(painter.width / 2, painter.height / 2 - 2),
      );
      canvas.restore();
    }
  }

  /// A round bead with a small shine.
  void bead(Canvas canvas, Offset center, double radius, Color color) {
    _fill.color = color;
    canvas.drawCircle(center, radius, _fill);
    canvas.drawCircle(
      center - Offset(radius * 0.3, radius * 0.35),
      radius * 0.35,
      _shine,
    );
  }

  Path _bodyPath(Rect rect) {
    final inset = rect.width * 0.12;
    final r = rect.width * 0.14;
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.right, rect.top)
      ..lineTo(rect.right - inset, rect.bottom - r)
      ..quadraticBezierTo(
        rect.right - inset,
        rect.bottom,
        rect.right - inset - r,
        rect.bottom,
      )
      ..lineTo(rect.left + inset + r, rect.bottom)
      ..quadraticBezierTo(
        rect.left + inset,
        rect.bottom,
        rect.left + inset,
        rect.bottom - r,
      )
      ..close();
  }

  /// Laid out label, cached by text, size and color.
  TextPainter text(String value, double size, Color color) {
    final key = '$value|${size.toStringAsFixed(1)}|${color.toARGB32()}';
    return _labels.putIfAbsent(
      key,
      () => TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: value,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w800,
            color: color,
            shadows: const [Shadow(blurRadius: 4, color: Color(0x99000000))],
          ),
        ),
      )..layout(),
    );
  }
}
