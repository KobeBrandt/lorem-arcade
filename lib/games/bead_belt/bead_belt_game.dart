import 'dart:math';
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';

import '../../arcade/arcade_level_game.dart';
import '../../ui/app_theme.dart';
import 'bead_belt_level.dart';
import 'bead_belt_model.dart';
import 'bead_belt_painter.dart';
import 'belt_shape.dart';

/// Bead Belt: dock buckets next to a turning belt and let them catch the
/// beads of their color. The rules live in [BeadBeltModel].
class BeadBeltGame extends ArcadeLevelGame with TapCallbacks {
  BeadBeltGame(super.setup, {BeadBeltLevel? level})
    : model = BeadBeltModel(level ?? BeadBeltLevel.generate(setup.level)) {
    model
      ..onBucketFilled = _onBucketFilled
      ..onBucketLeft = _onBucketLeft;
    _updateStatus();
  }

  final BeadBeltModel model;
  final BeadBeltPainter _painter = BeadBeltPainter();

  bool _tapped = false;
  double _time = 0;
  int _combo = 0;
  double _comboTimer = 0;
  final List<_Ring> _rings = [];

  /// Lane of the last rejected tap and the time since, for the shake.
  int _rejectLane = -1;
  double _rejectAge = _rejectLife;

  /// Seconds within which a next filled bucket raises the combo.
  static const double _comboWindow = 2;
  static const double _slideDuration = 0.25;
  static const double _rejectLife = 0.35;

  /// Upcoming bead colors shown next to the hopper.
  static const int previewCount = 5;

  /// Belt fill from which the belt warns that it is close to jamming.
  static const double warnFill = 0.8;

  /// Color id for the shape on a bead or bucket, or null when the theme
  /// draws no shapes.
  int? _symbol(int color) => setup.style.showShapes ? color : null;

  @override
  bool get hasProgress => _tapped;

  @override
  Color backgroundColor() => const Color(0x00000000);

  // ---------------------------------------------------------------- input

  @override
  void onTapDown(TapDownEvent event) {
    if (!_layoutReady) return;
    final p = event.canvasPosition.toOffset();
    for (var lane = 0; lane < _laneRects.length; lane++) {
      if (_laneRects[lane].contains(p)) {
        tapLane(lane);
        return;
      }
    }
  }

  /// A tap on [lane]. Returns true when its front bucket was docked.
  bool tapLane(int lane) {
    if (result.value != null) return false;
    final dock = model.dockFront(lane);
    if (dock == null) {
      setup.sounds.blocked();
      _rejectLane = lane;
      _rejectAge = 0;
      return false;
    }
    _tapped = true;
    setup.sounds.tap();
    if (setup.haptics) HapticFeedback.lightImpact();
    _updateStatus();
    return true;
  }

  void _onBucketFilled(int dock) {
    _combo = _comboTimer > 0 ? _combo + 1 : 1;
    _comboTimer = _comboWindow;
    setup.sounds.complete(_combo);
  }

  void _onBucketLeft(int dock, DockedBucket bucket) {
    if (_layoutReady) {
      _rings.add(
        _Ring(_dockRects[dock].center, setup.style.palette[bucket.color]),
      );
    }
    _updateStatus();
  }

  // --------------------------------------------------------------- update

  @override
  void update(double dt) {
    super.update(dt);
    // Long frames (for example after a pause) must not skip the rules.
    final step = min(dt, 0.1);
    _time += step;
    _rejectAge += step;
    _comboTimer = max(0, _comboTimer - step);
    for (final ring in _rings) {
      ring.t += step / 0.5;
    }
    _rings.removeWhere((ring) => ring.t >= 1);
    if (result.value != null) return;
    model.update(step);
    _updateStatus();
    if (model.isCleared) {
      finish(ArcadeResult.won(model.stars));
    } else if (model.isJammed) {
      finish(const ArcadeResult.lost('The belt jammed'));
    }
  }

  void _updateStatus() {
    status.value =
        'Belt ${model.beltCount}/${model.beltCapacity}'
        ' · Buckets ${model.filledBuckets}/${model.totalBuckets}';
  }

  // --------------------------------------------------------------- layout

  bool _layoutReady = false;
  late Offset _beltCenter;
  late double _scale;
  late double _beadRadius;
  late double _channel;
  late Rect _topCard;
  late Rect _bottomCard;
  late Rect _hopperRect;
  List<Rect> _dockRects = const [];
  List<Rect> _laneRects = const [];
  List<Rect> _frontRects = const [];
  late double _queueSize;

  /// Tap area of [lane] (for tests and accessibility).
  Rect laneTapRect(int lane) => _laneRects[lane];

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final w = size.x;
    final h = size.y;
    if (w <= 0 || h <= 0) return;
    final contentWidth = min(w - 24, 460.0);
    final left = (w - contentWidth) / 2;
    final cx = w / 2;
    final level = model.level;

    // Belt: fixed 2:1 shape, limited by width and by a third of the height.
    final beltWidth = min(contentWidth - 40, h * 0.3 * 2);
    _scale = beltWidth / 2;
    final spacing = _scale * BeltShape.length / level.beltCapacity;
    _beadRadius = (spacing * 0.4).clamp(3.5, 8.0);
    _channel = _beadRadius * 2 + 8;

    const cardTop = 4.0;
    _hopperRect = Rect.fromCenter(
      center: Offset(cx, cardTop + 22),
      width: 64,
      height: 24,
    );
    final beltTop = _hopperRect.bottom + 6 + _channel / 2;
    _beltCenter = Offset(cx, beltTop + _scale * BeltShape.halfHeight);
    final beltBottom = _beltCenter.dy + _scale * BeltShape.halfHeight;

    // Docks under the bottom straight of the belt.
    final n = level.dockCount;
    final dockPitch = _scale * 1.2 / n;
    final dockWidth = min(60.0, dockPitch - 8);
    final dockHeight = dockWidth * 1.05;
    final dockTop = beltBottom + _channel / 2 + 12;
    _dockRects = [
      for (var k = 0; k < n; k++)
        Rect.fromLTWH(
          cx + BeltShape.dockX(k, n) * _scale - dockWidth / 2,
          dockTop,
          dockWidth,
          dockHeight,
        ),
    ];
    final dockBottom = dockTop + dockHeight;
    _topCard = Rect.fromLTRB(
      left,
      cardTop,
      left + contentWidth,
      dockBottom + 14,
    );

    // Lanes fill the rest.
    final lanesTop = _topCard.bottom + 14;
    final lanesBottom = max(lanesTop + 120, h - 12);
    _bottomCard = Rect.fromLTRB(
      left,
      lanesTop,
      left + contentWidth,
      lanesBottom,
    );
    final laneCount = model.lanes.length;
    const gap = 10.0;
    final laneWidth = min(
      110.0,
      (contentWidth - 24 - gap * (laneCount - 1)) / laneCount,
    );
    final lanesWidth = laneWidth * laneCount + gap * (laneCount - 1);
    final laneLeft = cx - lanesWidth / 2;
    _laneRects = [
      for (var i = 0; i < laneCount; i++)
        Rect.fromLTRB(
          laneLeft + i * (laneWidth + gap),
          lanesTop + 12,
          laneLeft + i * (laneWidth + gap) + laneWidth,
          lanesBottom - 12,
        ),
    ];
    final frontSize = min(laneWidth - 20, 64.0);
    _frontRects = [
      for (final lane in _laneRects)
        Rect.fromCenter(
          center: Offset(lane.center.dx, lane.top + 14 + frontSize / 2),
          width: frontSize,
          height: frontSize,
        ),
    ];
    _queueSize = frontSize * 0.62;
    _layoutReady = true;
  }

  Offset _beltPoint(double u) => _beltCenter + BeltShape.pointAt(u) * _scale;

  // --------------------------------------------------------------- render

  final Paint _cardBorder = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = AppColors.glassBorder;
  final Paint _cardFill = Paint()..color = AppColors.glassFill;
  final Paint _wellFill = Paint()..color = AppColors.well;
  final Paint _beltStroke = Paint()..style = PaintingStyle.stroke;
  final Paint _arrowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..color = const Color(0x26FFFFFF);
  final Paint _markPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round;
  final Paint _ringPaint = Paint()..style = PaintingStyle.stroke;
  final Paint _rejectPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  /// Lane that last rejected a tap, or -1 (for tests).
  int get rejectedLane => _rejectAge < _rejectLife ? _rejectLane : -1;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!_layoutReady) return;
    _renderCard(canvas, _topCard);
    _renderCard(canvas, _bottomCard);
    _renderBelt(canvas);
    _renderHopper(canvas);
    _renderDocks(canvas);
    _renderLanes(canvas);
    _renderFlying(canvas);
    _renderRings(canvas);
  }

  void _renderCard(Canvas canvas, Rect rect) {
    final card = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(AppRadii.card),
    );
    canvas.drawRRect(card, _cardFill);
    canvas.drawRRect(card, _cardBorder);
  }

  void _renderBelt(Canvas canvas) {
    final belt = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: _beltCenter,
        width: _scale * BeltShape.halfWidth * 2,
        height: _scale * BeltShape.halfHeight * 2,
      ),
      Radius.circular(_scale * BeltShape.radius),
    );
    // The belt edge turns red when full and pulses red when close to it.
    final fill = model.fill;
    final Color edge;
    if (fill >= 1) {
      edge = AppColors.danger.withValues(alpha: 0.6);
    } else if (fill >= warnFill) {
      final pulse = 0.5 + 0.5 * sin(_time * 8);
      edge = AppColors.danger.withValues(alpha: 0.2 + 0.35 * pulse);
    } else {
      edge = AppColors.glassBorder;
    }
    _beltStroke
      ..strokeWidth = _channel + (fill >= warnFill ? 4 : 2)
      ..color = edge;
    canvas.drawRRect(belt, _beltStroke);
    _beltStroke
      ..strokeWidth = _channel
      ..color = AppColors.well;
    canvas.drawRRect(belt, _beltStroke);

    // Faint chevrons between the bead places show the direction.
    final c = model.beltCapacity;
    for (var j = 0; j < c; j += 3) {
      final u = ((j + 0.5 + model.phase) % c) / c;
      final at = _beltPoint(u);
      final dir = BeltShape.directionAt(u);
      final normal = Offset(-dir.dy, dir.dx) * (_beadRadius * 0.6);
      final tip = at + dir * 2.5;
      final back = at - dir * 2.5;
      canvas.drawPath(
        Path()
          ..moveTo(back.dx + normal.dx, back.dy + normal.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(back.dx - normal.dx, back.dy - normal.dy),
        _arrowPaint,
      );
    }

    // Dock pick-up marks on the belt edge.
    for (var k = 0; k < _dockRects.length; k++) {
      final bucket = model.docks[k];
      _markPaint.color = bucket == null
          ? AppColors.glassBorder
          : setup.style.palette[bucket.color].withValues(alpha: 0.8);
      final x = _dockRects[k].center.dx;
      final y = _beltCenter.dy + _scale * BeltShape.halfHeight + _channel / 2;
      canvas.drawLine(
        Offset(x, y + 2),
        Offset(x, _dockRects[k].top - 2),
        _markPaint,
      );
    }

    for (var i = 0; i < c; i++) {
      final color = model.slotColor(i);
      if (color < 0) continue;
      _painter.bead(
        canvas,
        _beltPoint(model.slotU(i)),
        _beadRadius,
        setup.style.palette[color],
        symbol: _symbol(color),
      );
    }
  }

  void _renderHopper(Canvas canvas) {
    final pill = RRect.fromRectAndRadius(
      _hopperRect,
      const Radius.circular(AppRadii.pill),
    );
    canvas.drawRRect(pill, _wellFill);
    canvas.drawRRect(pill, _cardBorder);
    final label = _painter.text(
      '${model.reservoirCount}',
      13,
      AppColors.textMuted,
    );
    label.paint(
      canvas,
      _hopperRect.center - Offset(label.width / 2, label.height / 2),
    );

    // The next beads to come, nearest first, fading out.
    final next = model.upcoming(previewCount);
    const radius = 5.5;
    for (var k = 0; k < next.length; k++) {
      final at = Offset(
        _hopperRect.right + 12 + radius + k * radius * 2.6,
        _hopperRect.center.dy,
      );
      final color = setup.style.palette[next[k]];
      _painter.bead(
        canvas,
        at,
        radius,
        color.withValues(alpha: 1 - k * 0.15),
        symbol: _symbol(next[k]),
      );
    }
  }

  void _renderDocks(Canvas canvas) {
    for (var k = 0; k < _dockRects.length; k++) {
      final rect = _dockRects[k];
      final well = RRect.fromRectAndRadius(
        rect.inflate(4),
        const Radius.circular(AppRadii.block + 4),
      );
      canvas.drawRRect(well, _wellFill);
      canvas.drawRRect(well, _cardBorder);
      final bucket = model.docks[k];
      if (bucket == null) continue;

      var target = rect.deflate(5);
      var opacity = 1.0;
      if (bucket.isLeaving) {
        final t = 1 - bucket.leaveTimer / BeadBeltModel.leaveDuration;
        target = Rect.fromCenter(
          center: target.center - Offset(0, 14 * t),
          width: target.width * (1 + 0.2 * t),
          height: target.height * (1 + 0.2 * t),
        );
        opacity = (1 - t).clamp(0.0, 1.0);
      } else if (bucket.age < _slideDuration) {
        final t = _Ease.easeOut(bucket.age / _slideDuration);
        target = Rect.lerp(_frontRects[bucket.lane], target, t)!;
      }
      _painter.bucket(
        canvas,
        target,
        setup.style.palette[bucket.color],
        fill: bucket.collected / bucket.capacity,
        label: '${bucket.capacity - bucket.collected}',
        opacity: opacity,
        symbol: _symbol(bucket.color),
      );
    }
  }

  void _renderLanes(Canvas canvas) {
    final hint = !_tapped ? 0.5 + 0.5 * sin(_time * 4) : 0.0;
    for (var i = 0; i < _laneRects.length; i++) {
      final rect = _laneRects[i];
      final lane = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(AppRadii.tube),
      );
      canvas.drawRRect(lane, _wellFill);
      canvas.drawRRect(lane, _cardBorder);
      // A rejected tap shakes a red outline on the lane.
      if (i == _rejectLane && _rejectAge < _rejectLife) {
        final k = _rejectAge / _rejectLife;
        _rejectPaint.color = AppColors.danger.withValues(alpha: 1 - k);
        canvas.drawRRect(
          lane.shift(Offset(sin(_rejectAge * 60) * 4 * (1 - k), 0)),
          _rejectPaint,
        );
      }
      final queue = model.lanes[i];
      if (queue.isEmpty) continue;

      final front = queue.first;
      final canDock = model.hasFreeDock && result.value == null;
      _painter.bucket(
        canvas,
        _frontRects[i],
        setup.style.palette[front.color],
        label: '${front.capacity}',
        opacity: canDock ? 1 : 0.55,
        highlight: canDock && hint > 0.5,
        symbol: _symbol(front.color),
      );

      // Waiting buckets, smaller, as many as fit.
      var y = _frontRects[i].bottom + 14;
      for (var q = 1; q < queue.length; q++) {
        if (y + _queueSize > rect.bottom - 8) {
          final more = _painter.text(
            '+${queue.length - q}',
            12,
            AppColors.textMuted,
          );
          more.paint(
            canvas,
            Offset(
              rect.center.dx - more.width / 2,
              rect.bottom - 8 - more.height,
            ),
          );
          break;
        }
        _painter.bucket(
          canvas,
          Rect.fromLTWH(
            rect.center.dx - _queueSize / 2,
            y,
            _queueSize,
            _queueSize * 0.8,
          ),
          setup.style.palette[queue[q].color],
          opacity: 0.45,
          symbol: _symbol(queue[q].color),
        );
        y += _queueSize * 0.8 + 10;
      }
    }
  }

  void _renderFlying(Canvas canvas) {
    for (final bead in model.flying) {
      final from = _beltPoint(bead.fromU);
      final to = _dockRects[bead.dock].center;
      final t = _Ease.easeIn(bead.t.clamp(0.0, 1.0));
      final at = Offset.lerp(from, to, t)! - Offset(0, sin(pi * t) * 16);
      _painter.bead(
        canvas,
        at,
        _beadRadius * (1 - 0.3 * t),
        setup.style.palette[bead.color],
        symbol: _symbol(bead.color),
      );
    }
  }

  void _renderRings(Canvas canvas) {
    for (final ring in _rings) {
      _ringPaint
        ..strokeWidth = 4 * (1 - ring.t) + 1
        ..color = ring.color.withValues(alpha: 1 - ring.t);
      canvas.drawCircle(ring.center, 12 + 36 * ring.t, _ringPaint);
    }
  }
}

/// Expanding ring where a full bucket left.
class _Ring {
  _Ring(this.center, this.color);

  final Offset center;
  final Color color;
  double t = 0;
}

/// Small easing curves without pulling in the animation library.
abstract final class _Ease {
  static double easeOut(double t) =>
      1 - pow(1 - t.clamp(0.0, 1.0), 3).toDouble();
  static double easeIn(double t) => t * t;
}
