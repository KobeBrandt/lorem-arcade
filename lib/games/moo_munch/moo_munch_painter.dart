import 'dart:math';
import 'dart:ui';

import 'moo_munch_board.dart';
import 'moo_munch_game.dart';

/// Draws the Moo Munch field: grass, rocks, the carrot and the cow.
class MooMunchPainter {
  static const Color _grassDark = Color(0xFF16261C);
  static const Color _grassLight = Color(0xFF1B2E22);
  static const Color _fence = Color(0x33FFFFFF);
  static const Color _rock = Color(0xFF6B6F7A);
  static const Color _rockShade = Color(0xFF4A4D56);
  static const Color _carrot = Color(0xFFFF8A1F);
  static const Color _leaf = Color(0xFF39C26B);
  static const Color _hide = Color(0xFFF4F1EA);
  static const Color _spot = Color(0xFF1E1B22);
  static const Color _muzzle = Color(0xFFF7A8C0);
  static const Color _horn = Color(0xFFE8D7A8);
  static const Color _crash = Color(0xFFFF5A6E);

  final Paint _paint = Paint()..isAntiAlias = true;

  void render(Canvas canvas, MooMunchGame game) {
    final field = game.fieldRect;
    final cell = game.cell;
    final board = game.board;

    // Grass with a soft checker, inside a rounded fence.
    final rounded = RRect.fromRectAndRadius(field, Radius.circular(cell * 0.6));
    canvas.save();
    canvas.clipRRect(rounded);
    canvas.drawRect(field, _paint..color = _grassDark);
    _paint.color = _grassLight;
    for (var y = 0; y < board.rows; y++) {
      for (var x = (y.isEven ? 0 : 1); x < board.cols; x += 2) {
        canvas.drawRect(_cellRect(game, x, y), _paint);
      }
    }
    if (game.crashFlash > 0) {
      canvas.drawRect(
        field,
        _paint..color = _crash.withValues(alpha: 0.35 * game.crashFlash),
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rounded,
      _paint
        ..color = _fence
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _paint.style = PaintingStyle.fill;

    for (final rock in board.rocks) {
      _drawRock(canvas, _cellRect(game, rock.x, rock.y));
    }
    final carrot = board.carrot;
    if (carrot != null) {
      _drawCarrot(canvas, _cellRect(game, carrot.x, carrot.y));
    }

    // Tail from the end to the neck, then the head on top.
    for (var i = board.body.length - 1; i >= 1; i--) {
      final c = board.body[i];
      _drawTail(canvas, _cellRect(game, c.x, c.y), i);
    }
    final head = board.head;
    _drawHead(canvas, _cellRect(game, head.x, head.y), board.facing);
  }

  Rect _cellRect(MooMunchGame game, int x, int y) => Rect.fromLTWH(
    game.fieldRect.left + x * game.cell,
    game.fieldRect.top + y * game.cell,
    game.cell,
    game.cell,
  );

  void _drawRock(Canvas canvas, Rect r) {
    final rock = r.deflate(r.width * 0.1);
    canvas.drawOval(rock, _paint..color = _rockShade);
    canvas.drawOval(
      Rect.fromLTRB(
        rock.left,
        rock.top,
        rock.right,
        rock.bottom - rock.height * 0.18,
      ),
      _paint..color = _rock,
    );
  }

  void _drawCarrot(Canvas canvas, Rect r) {
    final s = r.width;
    final top = r.top + s * 0.32;
    final body = Path()
      ..moveTo(r.left + s * 0.28, top)
      ..quadraticBezierTo(r.center.dx, top - s * 0.08, r.right - s * 0.28, top)
      ..lineTo(r.center.dx, r.bottom - s * 0.08)
      ..close();
    canvas.drawPath(body, _paint..color = _carrot);
    _paint
      ..color = _leaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, s * 0.09)
      ..strokeCap = StrokeCap.round;
    final base = Offset(r.center.dx, top);
    for (final dx in [-0.14, 0.0, 0.14]) {
      canvas.drawLine(base, Offset(base.dx + s * dx, r.top + s * 0.1), _paint);
    }
    _paint.style = PaintingStyle.fill;
  }

  void _drawTail(Canvas canvas, Rect r, int index) {
    final part = RRect.fromRectAndRadius(
      r.deflate(r.width * 0.08),
      Radius.circular(r.width * 0.3),
    );
    canvas.drawRRect(part, _paint..color = _hide);
    // A few spots, placed by index so they stay put while the cow walks.
    _paint.color = _spot;
    final s = r.width;
    final a = (index * 37) % 5 / 5;
    final b = (index * 53) % 7 / 7;
    canvas.drawCircle(
      Offset(r.left + s * (0.25 + a * 0.35), r.top + s * (0.3 + b * 0.3)),
      s * 0.13,
      _paint,
    );
    if (index.isEven) {
      canvas.drawCircle(
        Offset(r.left + s * (0.7 - b * 0.3), r.top + s * (0.68 - a * 0.25)),
        s * 0.09,
        _paint,
      );
    }
  }

  void _drawHead(Canvas canvas, Rect r, Heading facing) {
    final s = r.width;
    final c = r.center;
    // Forward and side unit vectors in screen space.
    final f = Offset(facing.dx.toDouble(), facing.dy.toDouble());
    final side = Offset(-f.dy, f.dx);
    Offset at(double forward, double across) =>
        c + f * (forward * s) + side * (across * s);

    // Horns behind the ears.
    _paint
      ..color = _horn
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, s * 0.1)
      ..strokeCap = StrokeCap.round;
    for (final across in [-1.0, 1.0]) {
      canvas.drawLine(at(-0.1, across * 0.3), at(-0.3, across * 0.52), _paint);
    }
    _paint.style = PaintingStyle.fill;

    canvas.drawCircle(c, s * 0.46, _paint..color = _hide);
    canvas.drawCircle(at(-0.18, 0.2), s * 0.12, _paint..color = _spot);
    // Muzzle at the front with two nostrils.
    canvas.drawCircle(at(0.26, 0), s * 0.22, _paint..color = _muzzle);
    _paint.color = _spot;
    canvas.drawCircle(at(0.32, -0.08), s * 0.04, _paint);
    canvas.drawCircle(at(0.32, 0.08), s * 0.04, _paint);
    // Eyes.
    canvas.drawCircle(at(0.02, -0.2), s * 0.06, _paint);
    canvas.drawCircle(at(0.02, 0.2), s * 0.06, _paint);
  }
}
