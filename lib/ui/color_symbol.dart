import 'dart:math';
import 'dart:ui';

/// Draws one shape per color id, so colors can be told apart without
/// color vision: circle, triangle, square, diamond, star, plus.
/// The shapes match the ones on the Color Flow blocks.
///
/// [size] is the width of the shape, [paint] its fill.
void drawColorSymbol(
  Canvas canvas,
  int colorId,
  Offset c,
  double size,
  Paint paint,
) {
  final h = size / 2;
  switch (colorId % 6) {
    case 0: // circle
      canvas.drawCircle(c, h, paint);
    case 1: // triangle
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - h)
          ..lineTo(c.dx + h, c.dy + h * 0.8)
          ..lineTo(c.dx - h, c.dy + h * 0.8)
          ..close(),
        paint,
      );
    case 2: // square
      canvas.drawRect(
        Rect.fromCenter(center: c, width: size * 0.85, height: size * 0.85),
        paint,
      );
    case 3: // diamond
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - h)
          ..lineTo(c.dx + h, c.dy)
          ..lineTo(c.dx, c.dy + h)
          ..lineTo(c.dx - h, c.dy)
          ..close(),
        paint,
      );
    case 4: // star
      final path = Path();
      for (var k = 0; k < 10; k++) {
        final radius = k.isEven ? h : h * 0.45;
        final a = -pi / 2 + k * pi / 5;
        final p = c + Offset(cos(a), sin(a)) * radius;
        k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), paint);
    default: // plus
      final bar = size * 0.3;
      canvas.drawRect(
        Rect.fromCenter(center: c, width: size, height: bar),
        paint,
      );
      canvas.drawRect(
        Rect.fromCenter(center: c, width: bar, height: size),
        paint,
      );
  }
}

/// Color of a symbol drawn on top of [base]: dark on light colors,
/// light on dark ones.
Color symbolColorOn(Color base) => base.computeLuminance() > 0.35
    ? const Color(0x59000000)
    : const Color(0x73FFFFFF);
