import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection, FontWeight;

import '../../ui/app_theme.dart';
import 'gate_drop_game.dart';
import 'gate_drop_layout.dart';
import 'gate_drop_shaft.dart';

/// Draws Gate Drop: the horde strip with its HP bar, the fever meter, the
/// glass shaft with its gates, pegs, bumpers and balls, the cup, the shot
/// streaks, pop-up texts, sparks and banners. Paints and texts are cached,
/// so a frame only allocates a few small objects.
class GateDropPainter {
  final Float32List _points = Float32List(GateDropShaft.maxBalls * 2);
  final Map<String, TextPainter> _texts = {};

  Path _conduit = Path();
  Offset _cannon = Offset.zero;
  double _wallX = 0;

  final Paint _panelFill = Paint()..color = AppColors.glassFill;
  final Paint _wellFill = Paint()..color = AppColors.well;
  final Paint _border = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = AppColors.glassBorder;
  final Paint _fill = Paint();
  final Paint _eye = Paint()..color = AppColors.well;
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _balls = Paint()
    ..strokeCap = StrokeCap.round
    ..color = AppColors.accentMint;
  final Paint _glow = Paint()
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  final Paint _conduitPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round
    ..color = const Color(0x22B8F5D6);

  /// Builds the parts that only change with the game size.
  void layout(GateDropGame game) {
    final strip = game.stripRect;
    _wallX = game.wallX;
    _cannon = Offset(_wallX - 2, strip.top + strip.height * 0.6);
    final pipe = Offset(
      game.toScreenX(shaftWidth / 2),
      game.shaftRect.bottom + 4,
    );
    final side = game.shaftRect.right + 8;
    _conduit = Path()
      ..moveTo(pipe.dx, pipe.dy)
      ..lineTo(side, pipe.dy)
      ..lineTo(side, strip.bottom + 6)
      ..lineTo(_cannon.dx, strip.bottom + 6)
      ..lineTo(_cannon.dx, _cannon.dy);
  }

  TextPainter _text(String value, double size, Color color) {
    final key = '$value|$size|${color.toARGB32()}';
    final cached = _texts[key];
    if (cached != null) return cached;
    if (_texts.length > 80) _texts.clear();
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

  void _centerText(Canvas canvas, TextPainter text, Offset center) {
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }

  void render(Canvas canvas, GateDropGame game) {
    _renderStrip(canvas, game);
    canvas.drawPath(_conduit, _conduitPaint);
    _renderFever(canvas, game);
    _renderShaft(canvas, game);
    _renderShots(canvas, game);
    _renderSparks(canvas, game);
    _renderPops(canvas, game);
    _renderBanner(canvas, game);
  }

  static const Color _gold = Color(0xFFFFD36E);

  Color _kindColor(GateDropGame game, GateSpec gate) => switch (gate.kind) {
    GateKind.halve => AppColors.danger,
    GateKind.refill => AppColors.accentMint,
    GateKind.multiply when gate.isJackpot => _gold,
    GateKind.multiply => _gateColor(game, gate.multiplier),
  };

  String _gateLabel(GateSpec gate) => switch (gate.kind) {
    GateKind.halve => '/2',
    GateKind.refill => '+cup',
    GateKind.multiply => 'x${gate.multiplier}',
  };

  Color _gateColor(GateDropGame game, int multiplier) {
    final palette = game.setup.style.palette;
    final index = switch (multiplier) {
      2 => 2,
      3 => 3,
      5 => 1,
      _ => 0,
    };
    return palette[index % palette.length];
  }

  // Horde strip.

  void _renderStrip(Canvas canvas, GateDropGame game) {
    final strip = game.stripRect;
    final panel = RRect.fromRectAndRadius(
      strip,
      const Radius.circular(AppRadii.tube),
    );
    canvas.drawRRect(panel, _panelFill);
    canvas.drawRRect(panel, _border);

    // The wall the horde must not reach.
    final wall = Rect.fromLTWH(_wallX, strip.top + 8, 12, strip.height - 16);
    _fill.color = AppColors.glassStrong;
    canvas.drawRRect(
      RRect.fromRectAndRadius(wall, const Radius.circular(4)),
      _fill,
    );
    _stroke
      ..strokeWidth = 1
      ..color = AppColors.accentLavender.withValues(alpha: 0.6);
    for (var y = wall.top + 10; y < wall.bottom; y += 10) {
      canvas.drawLine(Offset(wall.left, y), Offset(wall.right, y), _stroke);
    }
    _fill.color = AppColors.accentMint;
    canvas.drawCircle(_cannon, 5, _fill);

    // The horde: one figure per share of the hit points. A hit flashes
    // it and makes it shake.
    canvas.save();
    canvas.clipRRect(panel);
    final startHp = game.layout.hordeHp;
    const figures = 30;
    final visible = game.hordeHp <= 0
        ? 0
        : min(figures, (game.hordeHp * figures / startHp).ceil());
    final endX = _wallX - 10;
    final jolt = game.hordeFlash * sin(game.clock * 70) * 2.5;
    final front = game.hordeFrontX + jolt;
    const rowsPerColumn = 3;
    final rowGap = (strip.height - 44) / (rowsPerColumn - 1);
    final body = Color.lerp(
      game.isBonus ? AppColors.accentLavender : AppColors.danger,
      AppColors.text,
      game.hordeFlash * 0.7,
    )!;
    _fill.color = body;
    if (game.isBoss && visible > 0) {
      _renderBoss(canvas, game, front, strip);
    }
    for (var i = game.isBoss ? 3 : 0; i < visible; i++) {
      final column = i ~/ rowsPerColumn;
      final row = i % rowsPerColumn;
      final cx = front - column * 15 - (row.isOdd ? 7 : 0);
      if (cx < strip.left - 10) break;
      final bob = sin(game.clock * 9 + i * 1.7) * 1.6;
      final cy = strip.top + 28 + row * rowGap + bob;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy), width: 12, height: 13),
          const Radius.circular(5),
        ),
        _fill,
      );
      canvas.drawCircle(Offset(cx + 2.5, cy - 2), 1.6, _eye);
      canvas.drawCircle(Offset(cx - 1.5, cy - 2), 1.6, _eye);
    }
    canvas.restore();

    final label = game.isBonus
        ? 'Target ${game.damageDealt}/${game.layout.hordeHp}'
        : '${game.isBoss ? 'Boss' : 'Horde'} ${game.hordeHp}';
    final hp = _text(label, 12, AppColors.textMuted);
    hp.paint(canvas, Offset(strip.left + 12, strip.top + 6));

    // HP bar with a slow ghost bar behind it.
    final hpBar = Rect.fromLTRB(
      strip.left + 24 + hp.width,
      strip.top + 10,
      endX,
      strip.top + 14,
    );
    if (hpBar.width > 20) {
      _fill.color = AppColors.glassFill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(hpBar, const Radius.circular(2)),
        _fill,
      );
      final full = game.layout.hordeHp.toDouble();
      final ghost = game.isBonus
          ? 0.0
          : (game.ghostHp / full).clamp(0.0, 1.0).toDouble();
      final now = game.isBonus
          ? (game.damageDealt / full).clamp(0.0, 1.0).toDouble()
          : (game.hordeHp / full).clamp(0.0, 1.0).toDouble();
      _fill.color = AppColors.text.withValues(alpha: 0.55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(hpBar.left, hpBar.top, hpBar.width * ghost, 4),
          const Radius.circular(2),
        ),
        _fill,
      );
      _fill.color = game.isBonus ? _gold : AppColors.danger;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(hpBar.left, hpBar.top, hpBar.width * now, 4),
          const Radius.circular(2),
        ),
        _fill,
      );
    }
    if (game.isBonus) return;
    // Distance left to the wall.
    final bar = Rect.fromLTWH(
      strip.left + 12,
      strip.bottom - 9,
      endX - strip.left - 12,
      3,
    );
    _fill.color = AppColors.glassFill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(2)),
      _fill,
    );
    _fill.color = game.hordeProgress > 0.75
        ? AppColors.danger
        : AppColors.accentLavender;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bar.left, bar.top, bar.width * game.hordeProgress, 3),
        const Radius.circular(2),
      ),
      _fill,
    );
  }

  /// The boss: one big figure at the front, with a shield bubble while
  /// the shield lock is closed.
  void _renderBoss(Canvas canvas, GateDropGame game, double front, Rect strip) {
    final cy = strip.top + strip.height * 0.55;
    final cx = front - 6;
    final bob = sin(game.clock * 5) * 1.5;
    final center = Offset(cx, cy + bob);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 30, height: 34),
        const Radius.circular(10),
      ),
      _fill,
    );
    canvas.drawCircle(center + const Offset(6, -6), 3, _eye);
    canvas.drawCircle(center + const Offset(-4, -6), 3, _eye);
    // Crown.
    final top = cy + bob;
    final crown = Path()
      ..moveTo(cx - 10, top - 17)
      ..lineTo(cx - 10, top - 25)
      ..lineTo(cx - 5, top - 20)
      ..lineTo(cx, top - 27)
      ..lineTo(cx + 5, top - 20)
      ..lineTo(cx + 10, top - 25)
      ..lineTo(cx + 10, top - 17)
      ..close();
    final keep = _fill.color;
    _fill.color = _gold;
    canvas.drawPath(crown, _fill);
    _fill.color = keep;
    if (game.shaft.shieldUp) {
      final pulse = 0.5 + 0.2 * sin(game.clock * 4);
      _stroke
        ..strokeWidth = 2.5
        ..color = AppColors.accentLavender.withValues(alpha: pulse + 0.2);
      canvas.drawArc(
        Rect.fromCenter(
          center: center + const Offset(4, 0),
          width: 52,
          height: 56,
        ),
        -pi / 2.4,
        pi / 1.2,
        false,
        _stroke,
      );
      _glow.color = AppColors.accentLavender.withValues(alpha: pulse * 0.4);
      canvas.drawCircle(center + const Offset(14, 0), 14, _glow);
    }
  }

  void _renderFever(Canvas canvas, GateDropGame game) {
    final strip = game.stripRect;
    final bar = Rect.fromLTWH(
      strip.left + 4,
      strip.bottom + 7,
      strip.width - 8,
      5,
    );
    final r = RRect.fromRectAndRadius(bar, const Radius.circular(3));
    _fill.color = AppColors.glassFill;
    canvas.drawRRect(r, _fill);
    final double share;
    if (game.inFever) {
      share = game.feverLeft / GateDropGame.feverSeconds;
      _glow.color = _gold.withValues(alpha: 0.5 + 0.3 * sin(game.clock * 14));
      canvas.drawRRect(r.inflate(2), _glow);
    } else {
      share = game.feverMeter / GateDropGame.feverPoints;
    }
    _fill.color = game.inFever ? _gold : _gold.withValues(alpha: 0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bar.left, bar.top, bar.width * share.clamp(0.0, 1.0), 5),
        const Radius.circular(3),
      ),
      _fill,
    );
    if (game.comboLevel >= 2) {
      final combo = _text('Combo ${game.comboLevel}', 10, _gold);
      combo.paint(canvas, Offset(bar.right - combo.width, bar.bottom + 1));
    }
  }

  void _renderSparks(Canvas canvas, GateDropGame game) {
    for (var i = 0; i < GateDropGame.maxSparks; i++) {
      final age = game.sparkAge[i];
      if (age < 0) continue;
      final t = age / GateDropGame.sparkLife;
      _fill.color = game.sparkColor[i].withValues(alpha: 1 - t);
      canvas.drawCircle(
        Offset(game.sparkX[i], game.sparkY[i]),
        2.2 * (1 - t) + 0.6,
        _fill,
      );
    }
  }

  void _renderPops(Canvas canvas, GateDropGame game) {
    for (var i = 0; i < GateDropGame.maxPops; i++) {
      final age = game.popAge[i];
      if (age < 0) continue;
      final t = age / GateDropGame.popLife;
      final g = game.popGate[i];
      final base = switch (game.popTone[i]) {
        1 => AppColors.danger,
        2 => AppColors.accentMint,
        3 => AppColors.text,
        4 => _gold,
        _ when g >= 0 && g < game.layout.gates.length => _kindColor(
          game,
          game.layout.gates[g],
        ),
        _ => AppColors.text,
      };
      // Pop in big, then float up and fade. Sizes and alphas are rounded,
      // so the text cache stays small.
      final grow = t < 0.15 ? 0.7 + t * 4 : 1.3 - (t - 0.15) * 0.35;
      final alpha = (1 - t * t).clamp(0.0, 1.0);
      final size = (game.popSize[i] * grow).roundToDouble();
      final text = _text(
        game.popText[i],
        size,
        base.withValues(alpha: (alpha * 10).round() / 10),
      );
      _centerText(canvas, text, Offset(game.popX[i], game.popY[i] - t * 22));
    }
  }

  void _renderBanner(Canvas canvas, GateDropGame game) {
    if (game.bannerLeft <= 0) return;
    final t = game.bannerLeft / GateDropGame.bannerTime;
    final alpha = (t > 0.85 ? (1 - t) / 0.15 : min(1.0, t / 0.3)).clamp(
      0.0,
      1.0,
    );
    final text = _text(
      game.banner,
      26,
      _gold.withValues(alpha: (alpha * 10).round() / 10),
    );
    final rect = game.shaftRect;
    _centerText(
      canvas,
      text,
      Offset(rect.center.dx, rect.top + rect.height * 0.12),
    );
  }

  void _renderShots(Canvas canvas, GateDropGame game) {
    final strip = game.stripRect;
    final front = game.hordeFrontX;
    _stroke
      ..strokeWidth = game.inFever ? 3 : 2
      ..color = game.inFever ? _gold : AppColors.accentMint;
    for (var i = 0; i < GateDropGame.maxShots; i++) {
      final age = game.shotAge[i];
      if (age < 0) continue;
      final target = Offset(
        front - 4,
        strip.top + 24 + game.shotLane[i] * (strip.height - 40),
      );
      final head = min(1.0, age / GateDropGame.shotTime);
      final tail = max(0.0, (age - 0.08) / GateDropGame.shotTime);
      if (tail >= 1) continue;
      canvas.drawLine(
        Offset.lerp(_cannon, target, tail)!,
        Offset.lerp(_cannon, target, head)!,
        _stroke,
      );
    }
  }

  // Shaft.

  void _renderShaft(Canvas canvas, GateDropGame game) {
    final rect = game.shaftRect;
    final s = game.scale;
    final panel = RRect.fromRectAndRadius(
      rect.inflate(6),
      const Radius.circular(AppRadii.tube),
    );
    canvas.drawRRect(panel, _wellFill);
    if (game.inFever) {
      _fill.color = _gold.withValues(alpha: 0.05 + 0.03 * sin(game.clock * 10));
      canvas.drawRRect(panel, _fill);
    }
    canvas.drawRRect(panel, _border);

    Offset at(double x, double y) =>
        Offset(game.toScreenX(x), game.toScreenY(y));

    // Aim line under the cup.
    _stroke
      ..strokeWidth = 1
      ..color = const Color(0x14FFFFFF);
    canvas.drawLine(at(game.cupX, 8), at(game.cupX, 140), _stroke);

    // Pegs, bars and the floor.
    final shaft = game.shaft;
    _stroke.color = const Color(0x40FFFFFF);
    _fill.color = const Color(0x59FFFFFF);
    for (final solid in game.layout.solids) {
      _drawSolid(canvas, game, solid);
    }
    for (final solid in GateDropShaft.floor) {
      _drawSolid(canvas, game, solid);
    }

    // The pipe.
    const half = GateDropShaft.pipeHalfWidth;
    final pipe = Rect.fromLTRB(
      game.toScreenX(shaftWidth / 2 - half),
      game.toScreenY(144),
      game.toScreenX(shaftWidth / 2 + half),
      rect.bottom + 6,
    );
    _glow.color = AppColors.accentMint.withValues(alpha: 0.25);
    canvas.drawRect(pipe, _glow);
    _stroke
      ..strokeWidth = 2
      ..color = AppColors.accentMint;
    canvas.drawLine(pipe.topLeft, pipe.bottomLeft, _stroke);
    canvas.drawLine(pipe.topRight, pipe.bottomRight, _stroke);

    // Gates.
    final band = max(8.0, 2.6 * s);
    for (var g = 0; g < shaft.gates.length; g++) {
      final gate = shaft.gates[g];
      final cx = game.toScreenX(shaft.gateX[g]);
      final cy = game.toScreenY(gate.y);
      final w = gate.halfWidth * 2 * s;
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: w, height: band),
        Radius.circular(band / 2),
      );
      final locked = shaft.lockLeft[g] > 0;
      final color = _kindColor(game, gate);
      final flash = game.gateFlash[g];
      if (flash > 0) {
        _glow.color = color.withValues(alpha: 0.6 * flash);
        canvas.drawRRect(r.inflate(6), _glow);
      }
      if (locked) {
        _fill.color = AppColors.glassStrong;
        canvas.drawRRect(r, _fill);
        final shield = g == shaft.shieldGate;
        _stroke
          ..strokeWidth = shield ? 2.5 : 1.5
          ..color = shield ? _gold : AppColors.accentLavender;
        canvas.drawRRect(r, _stroke);
        final label = _text(
          '${shaft.lockLeft[g]}',
          max(9.0, band * 0.85),
          AppColors.text,
        );
        _drawLock(canvas, Offset(cx - label.width / 2 - 7, cy), band * 0.4);
        _centerText(canvas, label, Offset(cx + 4, cy));
      } else {
        _fill.color = color.withValues(alpha: 0.35);
        canvas.drawRRect(r, _fill);
        _stroke
          ..strokeWidth = 1.5
          ..color = color;
        canvas.drawRRect(r, _stroke);
        _centerText(
          canvas,
          _text(_gateLabel(gate), max(9.0, band * 0.85), AppColors.text),
          Offset(cx, cy),
        );
      }
    }

    // Balls, drawn in one call.
    final count = shaft.count;
    for (var i = 0; i < count; i++) {
      _points[i * 2] = game.toScreenX(shaft.x[i]);
      _points[i * 2 + 1] = game.toScreenY(shaft.y[i]);
    }
    if (count > 0) {
      _balls
        ..strokeWidth = GateDropShaft.ballRadius * 2 * s
        ..color = game.inFever ? _gold : AppColors.accentMint;
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.sublistView(_points, 0, count * 2),
        _balls,
      );
    }

    _renderCup(canvas, game);
  }

  void _drawSolid(Canvas canvas, GateDropGame game, SolidSpec solid) {
    final s = game.scale;
    final a = Offset(game.toScreenX(solid.ax), game.toScreenY(solid.ay));
    if (solid.bumper) {
      final keepFill = _fill.color;
      final keepStroke = _stroke.color;
      _glow.color = AppColors.accentLavender.withValues(alpha: 0.35);
      canvas.drawCircle(a, solid.radius * s * 1.3, _glow);
      _fill.color = AppColors.accentLavender.withValues(alpha: 0.3);
      canvas.drawCircle(a, solid.radius * s, _fill);
      _stroke
        ..strokeWidth = 1.5
        ..color = AppColors.accentLavender;
      canvas.drawCircle(a, solid.radius * s, _stroke);
      _fill.color = keepFill;
      _stroke.color = keepStroke;
      return;
    }
    if (solid.isPeg) {
      canvas.drawCircle(a, solid.radius * s, _fill);
      return;
    }
    _stroke.strokeWidth = solid.radius * 2 * s;
    canvas.drawLine(
      a,
      Offset(game.toScreenX(solid.bx), game.toScreenY(solid.by)),
      _stroke,
    );
  }

  void _drawLock(Canvas canvas, Offset center, double size) {
    _stroke
      ..strokeWidth = 1.4
      ..color = AppColors.accentLavender;
    canvas.drawArc(
      Rect.fromCenter(
        center: center - Offset(0, size * 0.5),
        width: size * 1.4,
        height: size * 1.6,
      ),
      pi,
      pi,
      false,
      _stroke,
    );
    _fill.color = AppColors.accentLavender;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: center + Offset(0, size * 0.25),
          width: size * 2,
          height: size * 1.4,
        ),
        const Radius.circular(2),
      ),
      _fill,
    );
  }

  void _renderCup(Canvas canvas, GateDropGame game) {
    final s = game.scale;
    final cx = game.toScreenX(game.cupX);
    final top = game.toScreenY(0.5);
    final bottom = game.toScreenY(7);
    final cup = Path()
      ..moveTo(cx - 7 * s, top)
      ..lineTo(cx + 7 * s, top)
      ..lineTo(cx + 3.5 * s, bottom)
      ..lineTo(cx - 3.5 * s, bottom)
      ..close();
    _fill.color = game.pouring
        ? AppColors.accentMint.withValues(alpha: 0.3)
        : AppColors.glassStrong;
    canvas.drawPath(cup, _fill);
    _stroke
      ..strokeWidth = 1.5
      ..color = game.cupBalls > 0 ? AppColors.accentMint : AppColors.danger;
    canvas.drawPath(cup, _stroke);
    _centerText(
      canvas,
      _text('${game.cupBalls}', max(9.0, 3.2 * s), AppColors.text),
      Offset(cx, (top + bottom) / 2 - 0.5 * s),
    );
  }
}
