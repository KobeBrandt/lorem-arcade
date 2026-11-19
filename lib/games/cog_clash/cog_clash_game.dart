import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../arcade/arcade_level_game.dart';
import '../../ui/app_theme.dart';
import 'cog_battle.dart';
import 'cog_model.dart';
import 'cog_painter.dart';

/// Cog Clash: buy gears, link them to your weapon gears, then watch the
/// fight. Weapon power is the sum of the linked number gears times the
/// product of the linked multipliers. Stars by fighter HP left: 3 above
/// 2/3, 2 above 1/3, else 1.
class CogClashGame extends ArcadeLevelGame with TapCallbacks {
  CogClashGame(super.setup) : config = CogLevel.forLevel(setup.level) {
    board = config.newBoard();
    shop = CogShop(config);
    _updateStatus();
  }

  final CogLevel config;
  late final CogBoard board;
  late final CogShop shop;

  /// Offer picked in the shop, waiting for a socket.
  int? selectedOffer;

  /// The running or finished fight, null in the build phase.
  CogBattle? battle;

  bool _placed = false;
  double _time = 0;
  double _fightTime = 0;
  int _kills = 0;
  final List<_Burst> _bursts = [];
  final TextCache _text = TextCache();

  /// Time the board needs to slide up before the fight starts.
  static const double introDuration = 0.6;

  bool get isFighting => battle != null;

  @override
  bool get hasProgress => _placed;

  @override
  Color backgroundColor() => const Color(0x00000000);

  List<Color> get _palette => setup.style.palette;

  // ---------------------------------------------------------------- layout

  bool _layoutReady = false;
  double _cell = 64;
  late Rect _content;
  late Rect _header;
  late Rect _boardPanel;
  late Rect _caption;
  late List<Rect> _offerRects;
  late Rect _rerollRect;
  late Rect _fightRect;
  late Path _gearSmall;
  late Path _gearWeapon;
  late Path _gearOffer;

  static const double _top = 12;
  static const double _pad = 10;
  static const double _headerHeight = 28;
  static const double _captionHeight = 28;
  static const double _offerHeight = 96;
  static const double _buttonHeight = 56;
  static const double _gap = 12;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final w = size.x;
    final h = size.y;
    final cw = min(w - 32, 460.0);
    final left = (w - cw) / 2;
    const fixed =
        _top +
        _headerHeight +
        _captionHeight +
        _offerHeight +
        _gap +
        _buttonHeight +
        16 +
        _gap;
    final boardSpace = h - fixed;
    final cell = max(
      48.0,
      min(
        (cw - 2 * _pad) / CogLevel.cols,
        (boardSpace - 2 * _pad) / CogLevel.rows,
      ),
    );
    _cell = min(cell, 84);
    final boardW = _cell * CogLevel.cols + 2 * _pad;
    final boardH = _cell * CogLevel.rows + 2 * _pad;
    // Center the build layout when the screen has room to spare.
    final total =
        _headerHeight +
        boardH +
        _captionHeight +
        _offerHeight +
        _gap +
        _buttonHeight;
    final top = max(_top, (h - total) / 2 - 8);
    _content = Rect.fromLTWH(left, _top, cw, h - _top);
    _header = Rect.fromLTWH(w / 2 - boardW / 2, top, boardW, _headerHeight);
    _boardPanel = Rect.fromLTWH(_header.left, _header.bottom, boardW, boardH);
    _caption = Rect.fromLTWH(left, _boardPanel.bottom, cw, _captionHeight);
    final offerTop = _caption.bottom;
    final offerW = (cw - 2 * 10) / CogShop.offerCount;
    _offerRects = [
      for (var i = 0; i < CogShop.offerCount; i++)
        Rect.fromLTWH(left + i * (offerW + 10), offerTop, offerW, _offerHeight),
    ];
    final buttonTop = offerTop + _offerHeight + _gap;
    final rerollW = (cw - 10) / 3;
    _rerollRect = Rect.fromLTWH(left, buttonTop, rerollW, _buttonHeight);
    _fightRect = Rect.fromLTWH(
      left + rerollW + 10,
      buttonTop,
      cw - rerollW - 10,
      _buttonHeight,
    );
    _gearSmall = gearPath(_cell * 0.42, 10);
    _gearWeapon = gearPath(_cell * 0.47, 12, depth: 0.2);
    _gearOffer = gearPath(min(30, _offerHeight * 0.3), 10);
    _layoutReady = true;
  }

  /// Tap area of a board socket in the build layout.
  Rect socketRect(int socket) => Rect.fromLTWH(
    _boardPanel.left + _pad + board.colOf(socket) * _cell,
    _boardPanel.top + _pad + board.rowOf(socket) * _cell,
    _cell,
    _cell,
  );

  Rect offerRect(int offer) => _offerRects[offer];

  Rect get rerollRect => _rerollRect;

  Rect get fightRect => _fightRect;

  // ----------------------------------------------------------------- input

  @override
  void onTapDown(TapDownEvent event) {
    if (!_layoutReady || isFighting) return;
    final p = event.canvasPosition.toOffset();
    for (var i = 0; i < _offerRects.length; i++) {
      if (_offerRects[i].contains(p)) {
        selectOffer(i);
        return;
      }
    }
    if (_rerollRect.contains(p)) {
      reroll();
      return;
    }
    if (_fightRect.contains(p)) {
      startFight();
      return;
    }
    for (var s = 0; s < board.socketCount; s++) {
      if (socketRect(s).contains(p)) {
        tapSocket(s);
        return;
      }
    }
  }

  /// Picks offer [offer] (or drops it when it is already picked).
  /// Rejected when the coins do not cover the price.
  bool selectOffer(int offer) {
    if (isFighting) return false;
    if (selectedOffer == offer) {
      selectedOffer = null;
      setup.sounds.tap();
      return true;
    }
    if (!shop.canAfford(offer)) {
      _reject();
      return false;
    }
    selectedOffer = offer;
    setup.sounds.tap();
    _haptic();
    return true;
  }

  /// Buys the picked offer and places it in [socket]. Rejected without
  /// a picked offer or when the socket is taken.
  bool tapSocket(int socket) {
    final offer = selectedOffer;
    if (isFighting || offer == null || !board.isEmpty(socket)) {
      _reject();
      return false;
    }
    if (!shop.canAfford(offer)) {
      selectedOffer = null;
      _reject();
      return false;
    }
    final gear = shop.buy(offer)!;
    final placement = board.place(socket, gear)!;
    _placed = true;
    selectedOffer = null;
    if (placement.merged) {
      setup.sounds.complete(1);
      _bursts.add(_Burst(socketRect(placement.socket).center, false));
    } else {
      setup.sounds.tap();
    }
    _haptic();
    _updateStatus();
    return true;
  }

  /// New offers for [CogShop.rerollPrice] coin.
  bool reroll() {
    if (isFighting || !shop.reroll()) {
      _reject();
      return false;
    }
    selectedOffer = null;
    setup.sounds.tap();
    _haptic();
    _updateStatus();
    return true;
  }

  /// Ends the build phase and starts the fight.
  bool startFight() {
    if (isFighting) {
      _reject();
      return false;
    }
    selectedOffer = null;
    battle = CogBattle(config, board.powers);
    setup.sounds.whoosh();
    _haptic();
    _updateStatus();
    return true;
  }

  void _reject() {
    setup.sounds.blocked();
  }

  void _haptic() {
    if (setup.haptics) HapticFeedback.lightImpact();
  }

  void _updateStatus() {
    final b = battle;
    status.value = b == null
        ? 'Coins ${shop.coins} · Wave HP ${config.waveHp}'
        : 'Wave HP ${b.waveHp} · Fighter ${b.fighterHp.ceil()}';
  }

  // ---------------------------------------------------------------- update

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    for (final burst in List.of(_bursts)) {
      burst.age += dt;
      if (burst.age >= _Burst.life) _bursts.remove(burst);
    }
    final b = battle;
    if (b == null) return;
    final before = _fightTime;
    _fightTime += dt;
    if (_fightTime < introDuration || b.isOver) return;
    b.advance(before < introDuration ? _fightTime - introDuration : dt);
    if (b.kills > _kills) {
      _kills = b.kills;
      setup.sounds.complete(min(_kills, 6));
      _haptic();
      _bursts.add(_Burst(_arenaPoint(b.enemyX[_kills - 1], 0), true));
    }
    _updateStatus();
    if (b.isOver) {
      finish(
        b.won!
            ? ArcadeResult.won(b.stars)
            : const ArcadeResult.lost('Your fighter fell'),
      );
    }
  }

  // ---------------------------------------------------------------- render

  /// 0 in the build phase, 1 once the board has moved up for the fight.
  double get _fightProgress => battle == null
      ? 0
      : Curves.easeOutCubic.transform(
          (_fightTime / introDuration).clamp(0.0, 1.0),
        );

  static const double _fightScale = 0.55;

  Rect get _arena {
    final boardBottom =
        _content.top + (_headerHeight + _boardPanel.height) * _fightScale;
    return Rect.fromLTRB(
      _content.left,
      boardBottom + _gap,
      _content.right,
      size.y - 16,
    );
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!_layoutReady) return;
    final t = _fightProgress;
    // Board and header shrink towards the top during the fight.
    final scale = 1 - (1 - _fightScale) * t;
    final pivot = Offset(_header.center.dx, _header.top);
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy + (_top - _header.top) * t);
    canvas.scale(scale);
    canvas.translate(-pivot.dx, -pivot.dy);
    _renderHeader(canvas);
    _renderBoard(canvas);
    canvas.restore();
    if (t < 1) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - t));
      canvas.translate(0, 60 * t);
      _renderShop(canvas);
      canvas.restore();
    }
    if (battle != null) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, t));
      _renderArena(canvas);
      canvas.restore();
    }
    _renderBursts(canvas);
  }

  void _glassPanel(Canvas canvas, RRect r) {
    canvas.drawRRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.outerRect.topCenter,
          r.outerRect.bottomCenter,
          [AppColors.glassFill, AppColors.glassFillLow],
        ),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppColors.glassBorder,
    );
  }

  void _renderHeader(Canvas canvas) {
    for (var i = 0; i < board.weapons.length; i++) {
      final w = board.weapons[i];
      final label = 'Power ${board.powerOf(w)}';
      final p = _text.get(label, size: 14, color: AppColors.text);
      final onLeft = board.colOf(w) < board.cols / 2;
      final pill = Rect.fromLTWH(
        onLeft ? _header.left : _header.right - p.width - 24,
        _header.top + 2,
        p.width + 24,
        _headerHeight - 6,
      );
      final r = RRect.fromRectAndRadius(pill, const Radius.circular(999));
      canvas.drawRRect(r, Paint()..color = AppColors.glassStrong);
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _weaponColor(i).withValues(alpha: 0.6),
      );
      p.paint(canvas, pill.center - Offset(p.width / 2, p.height / 2));
    }
  }

  Color _weaponColor(int weapon) =>
      weapon == 0 ? AppColors.accentMint : AppColors.accentLavender;

  Color _gearColor(Gear gear) {
    if (!gear.isNumber) {
      return _palette[(gear.value == 2 ? 5 : 1) % _palette.length];
    }
    return _palette[(min(gear.value, 8) - 1) % 5];
  }

  void _renderBoard(Canvas canvas) {
    final panel = RRect.fromRectAndRadius(
      _boardPanel,
      const Radius.circular(AppRadii.card),
    );
    _glassPanel(canvas, panel);
    final powered = board.powered;
    final glowing = <int>{
      if (selectedOffer != null && !isFighting) ...board.linkedEmptySockets,
      if (!_placed && !isFighting && config.hintSocket != null)
        config.hintSocket!,
    };
    final pulse = 0.5 + 0.5 * sin(_time * 4);
    for (var s = 0; s < board.socketCount; s++) {
      final rect = socketRect(s);
      final c = rect.center;
      // Socket well.
      canvas.drawCircle(c, _cell * 0.34, Paint()..color = AppColors.well);
      canvas.drawCircle(
        c,
        _cell * 0.34,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = glowing.contains(s) ? 2.5 : 1
          ..color = glowing.contains(s)
              ? AppColors.accentMint.withValues(alpha: 0.45 + 0.55 * pulse)
              : AppColors.glassBorder,
      );
      final spin =
          ((board.colOf(s) + board.rowOf(s)).isEven ? 1 : -1) * _time * 1.4;
      final weaponIndex = board.weapons.indexOf(s);
      if (weaponIndex >= 0) {
        _drawWeapon(canvas, c, weaponIndex, spin);
        continue;
      }
      final gear = board.gearAt(s);
      if (gear == null) continue;
      final on = powered.contains(s);
      _drawGear(
        canvas,
        c,
        gear,
        _gearSmall,
        on ? spin : 0.0,
        on ? 1.0 : 0.35,
        _cell * 0.26,
      );
    }
  }

  void _drawWeapon(Canvas canvas, Offset c, int weapon, double angle) {
    final power = board.powerOf(board.weapons[weapon]);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.save();
    canvas.rotate(power > 0 ? angle : 0);
    final r = _cell * 0.47;
    canvas.drawPath(
      _gearWeapon,
      Paint()
        ..shader = ui.Gradient.linear(Offset(-r, -r), Offset(r, r), [
          AppColors.accentMint,
          AppColors.accentLavender,
        ]),
    );
    canvas.restore();
    canvas.drawCircle(Offset.zero, r * 0.5, Paint()..color = AppColors.well);
    _text.paintCentered(
      canvas,
      '$power',
      Offset.zero,
      size: _cell * 0.24,
      color: _weaponColor(weapon),
    );
    canvas.restore();
  }

  void _drawGear(
    Canvas canvas,
    Offset c,
    Gear gear,
    Path path,
    double angle,
    double alpha,
    double fontSize,
  ) {
    final color = _gearColor(gear).withValues(alpha: alpha);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.save();
    canvas.rotate(angle);
    canvas.drawPath(path, Paint()..color = color);
    if (!gear.isNumber) {
      // Multipliers get a dark ring so they read apart from numbers.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.well.withValues(alpha: 0.6 * alpha),
      );
    }
    canvas.restore();
    _text.paintCentered(
      canvas,
      gear.label,
      Offset.zero,
      size: fontSize,
      color: AppColors.textOnAccent.withValues(alpha: alpha),
      weight: FontWeight.w800,
    );
    canvas.restore();
  }

  void _renderShop(Canvas canvas) {
    final caption = selectedOffer == null
        ? (config.hintSocket != null && !_placed
              ? 'Tap a gear below, then the glowing socket'
              : 'Tap a gear to buy it · Coins ${shop.coins}')
        : 'Tap a glowing socket to place it';
    _text.paintCentered(
      canvas,
      caption,
      _caption.center,
      size: 13,
      color: AppColors.textMuted,
      weight: FontWeight.w500,
    );
    for (var i = 0; i < _offerRects.length; i++) {
      final rect = _offerRects[i];
      final gear = shop.offers[i];
      final afford = shop.canAfford(i);
      final r = RRect.fromRectAndRadius(rect, const Radius.circular(20));
      _glassPanel(canvas, r);
      if (selectedOffer == i) {
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = AppColors.accentMint,
        );
      }
      final spin = selectedOffer == i ? _time * 2 : 0.0;
      _drawGear(
        canvas,
        Offset(rect.center.dx, rect.top + 38),
        gear,
        _gearOffer,
        spin,
        afford ? 1 : 0.35,
        16,
      );
      _text.paintCentered(
        canvas,
        gear.price == 1 ? '1 coin' : '${gear.price} coins',
        Offset(rect.center.dx, rect.bottom - 16),
        size: 13,
        color: afford ? AppColors.text : AppColors.textMuted,
        weight: FontWeight.w600,
      );
    }
    // Reroll: glass pill.
    final reroll = RRect.fromRectAndRadius(
      _rerollRect,
      const Radius.circular(999),
    );
    canvas.drawRRect(reroll, Paint()..color = AppColors.glassStrong);
    canvas.drawRRect(
      reroll,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.glassBorder,
    );
    _text.paintCentered(
      canvas,
      'Reroll · 1',
      _rerollRect.center,
      size: 16,
      color: shop.coins >= CogShop.rerollPrice
          ? AppColors.text
          : AppColors.textMuted,
    );
    // Fight: accent gradient pill.
    final fight = RRect.fromRectAndRadius(
      _fightRect,
      const Radius.circular(999),
    );
    canvas.drawRRect(
      fight,
      Paint()
        ..shader = ui.Gradient.linear(
          _fightRect.centerLeft,
          _fightRect.centerRight,
          [AppColors.accentMint, AppColors.accentLavender],
        ),
    );
    _text.paintCentered(
      canvas,
      'Fight',
      _fightRect.center,
      size: 18,
      color: AppColors.textOnAccent,
    );
  }

  // ----------------------------------------------------------------- arena

  double get _groundY => _arena.bottom - _arena.height * 0.3;

  Offset _arenaPoint(double x, double lift) {
    final a = _arena;
    return Offset(
      a.left + 16 + (x / CogBattle.arenaLength) * (a.width - 32),
      _groundY - lift,
    );
  }

  void _renderArena(Canvas canvas) {
    final b = battle!;
    final a = _arena;
    final panel = RRect.fromRectAndRadius(
      a,
      const Radius.circular(AppRadii.card),
    );
    _glassPanel(canvas, panel);
    canvas.save();
    canvas.clipRRect(panel);
    // Ground.
    canvas.drawLine(
      Offset(a.left + 12, _groundY),
      Offset(a.right - 12, _groundY),
      Paint()
        ..color = AppColors.glassBorder
        ..strokeWidth = 2,
    );
    final unit = min(a.height * 0.1, 34.0);
    _renderFighter(canvas, b, unit);
    // Enemies, front first.
    for (var i = b.front; i < b.enemyX.length; i++) {
      final x = b.enemyX[i];
      if (x > CogBattle.arenaLength + 6) continue;
      final bob = (sin(_time * 9 + i) * 0.5 + 0.5) * unit * 0.15;
      final base = _arenaPoint(x, bob);
      final color = _palette[(i.isEven ? 0 : 4) % _palette.length];
      final body = Rect.fromCenter(
        center: base - Offset(0, unit * 0.75),
        width: unit * 1.3,
        height: unit * 1.5,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          body,
          topLeft: Radius.circular(unit * 0.65),
          topRight: Radius.circular(unit * 0.65),
          bottomLeft: Radius.circular(unit * 0.2),
          bottomRight: Radius.circular(unit * 0.2),
        ),
        Paint()..color = color,
      );
      final eye = Paint()..color = AppColors.well;
      canvas.drawCircle(
        body.center + Offset(-unit * 0.28, -unit * 0.2),
        unit * 0.1,
        eye,
      );
      canvas.drawCircle(
        body.center + Offset(unit * 0.05, -unit * 0.2),
        unit * 0.1,
        eye,
      );
    }
    // Shots.
    for (final shot in b.shots) {
      final p = _arenaPoint(shot.x, unit * 1.0);
      final color = _weaponColor(shot.weapon);
      canvas.drawCircle(
        p,
        unit * 0.32,
        Paint()..color = color.withValues(alpha: 0.25),
      );
      canvas.drawCircle(p, unit * 0.16, Paint()..color = color);
    }
    // Shared wave HP above the wave.
    if (b.aliveCount > 0) {
      final frontX = b.enemyX[b.front];
      final backX = min(b.enemyX.last, CogBattle.arenaLength);
      final mid = _arenaPoint((frontX + max(frontX, backX)) / 2, unit * 2.4);
      final label = _text.get(
        'Wave HP ${b.waveHp}',
        size: 15,
        color: AppColors.text,
      );
      final x = mid.dx.clamp(
        a.left + 12 + label.width / 2,
        a.right - 12 - label.width / 2,
      );
      label.paint(canvas, Offset(x - label.width / 2, mid.dy - label.height));
      _bar(
        canvas,
        Rect.fromCenter(center: Offset(x, mid.dy + 6), width: 90, height: 6),
        b.waveHp / config.waveHp,
        _palette[0],
      );
    }
    canvas.restore();
  }

  void _renderFighter(Canvas canvas, CogBattle b, double unit) {
    final base = _arenaPoint(CogBattle.fighterX, 0);
    final shake = b.inContact ? sin(_time * 40) * 1.5 : 0.0;
    final body = Rect.fromCenter(
      center: base - Offset(-shake, unit * 0.85),
      width: unit * 1.1,
      height: unit * 1.7,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(unit * 0.55)),
      Paint()
        ..shader = ui.Gradient.linear(body.topCenter, body.bottomCenter, [
          AppColors.accentMint,
          AppColors.accentLavender,
        ]),
    );
    canvas.drawCircle(
      body.center + Offset(unit * 0.2, -unit * 0.35),
      unit * 0.1,
      Paint()..color = AppColors.well,
    );
    // Small gear cannon on the fighter's side.
    canvas.save();
    canvas.translate(body.right, body.center.dy + unit * 0.15);
    canvas.rotate(_time * 3);
    canvas.scale(unit * 0.32 / (_cell * 0.42));
    canvas.drawPath(_gearSmall, Paint()..color = AppColors.well);
    canvas.restore();
    // Fighter HP.
    final hp = b.fighterHp / CogBattle.fighterMaxHp;
    _text.paintCentered(
      canvas,
      '${b.fighterHp.ceil()}',
      Offset(body.center.dx, body.top - 20),
      size: 13,
      color: AppColors.text,
    );
    _bar(
      canvas,
      Rect.fromCenter(
        center: Offset(body.center.dx, body.top - 8),
        width: unit * 1.6,
        height: 5,
      ),
      hp,
      hp > 1 / 3 ? AppColors.accentMint : AppColors.danger,
    );
  }

  void _bar(Canvas canvas, Rect rect, double fraction, Color color) {
    final r = Radius.circular(rect.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, r),
      Paint()..color = AppColors.well,
    );
    final f = fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width * f, rect.height),
        r,
      ),
      Paint()..color = color,
    );
  }

  void _renderBursts(Canvas canvas) {
    for (final burst in _bursts) {
      final k = burst.age / _Burst.life;
      final center = burst.inArena
          ? burst.center - Offset(0, _arena.height * 0.08)
          : burst.center;
      canvas.drawCircle(
        center,
        12 + 26 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - k)
          ..color = AppColors.accentMint.withValues(alpha: 1 - k),
      );
    }
  }
}

/// Short ring shown on a merge or a defeated enemy.
class _Burst {
  _Burst(this.center, this.inArena);

  static const double life = 0.4;

  final Offset center;
  final bool inArena;
  double age = 0;
}
