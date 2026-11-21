import 'dart:math';
import 'dart:ui' as ui;

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../../arcade/arcade_level_game.dart';
import '../../ui/app_theme.dart';
import 'cog_battle.dart';
import 'cog_model.dart';
import 'cog_painter.dart';

/// Cog Clash: buy gears and link them to your weapon gears while waves
/// of enemies walk in. Weapon power is the sum of the linked number
/// gears times the product of the linked multipliers, and it changes the
/// moment the board changes. Defeated enemies pay coins.
///
/// A level has 2 to 4 waves; stars by fighter HP left after the last
/// one: 3 above 2/3, 2 above 1/3, else 1. The endless run
/// ([CogClashGame.endless]) never stops; its score is the waves cleared.
class CogClashGame extends ArcadeLevelGame with TapCallbacks {
  CogClashGame(ArcadeSetup setup)
    : this._(setup, CogLevel.forLevel(setup.level));

  /// The endless run.
  CogClashGame.endless(ArcadeSetup setup) : this._(setup, CogLevel.endless());

  CogClashGame._(super.setup, this.config) {
    board = config.newBoard();
    shop = CogShop(config);
    battle = CogBattle(config, board.powers)
      ..onHit = _onHit
      ..onKill = _onKill;
    _updateStatus();
  }

  final CogLevel config;
  late final CogBoard board;
  late final CogShop shop;
  late final CogBattle battle;

  /// Offer picked in the shop, waiting for a socket.
  int? selectedOffer;

  bool _placed = false;
  double _time = 0;
  int _coinsSeen = 0;
  final List<_Burst> _bursts = [];
  final List<_Popup> _popups = [];
  final TextCache _text = TextCache();

  /// Total power gain of placing the picked offer in each empty socket.
  /// Only sockets with a gain are in the map.
  Map<int, int> _preview = const {};

  /// What a rejected tap hit, for the red shake; null when none.
  Rect? _rejectRect;
  double _rejectAge = _rejectLife;

  /// Seconds the front enemy still flashes after a hit.
  double _hitFlash = 0;

  /// Seconds the arena still shakes after a kill.
  double _shake = 0;

  /// Bursts shown for defeated enemies so far.
  int _killBursts = 0;

  /// Longest frame the game steps at once (for example after a pause).
  static const double maxFrame = 0.1;

  static const double _rejectLife = 0.35;
  static const double _shakeLife = 0.25;
  static const int _maxPopups = 12;

  bool get isEndless => config.isEndless;

  /// True once the run ended (won, lost or ended).
  bool get isOver => result.value != null;

  /// Power gain of placing the picked offer in [socket], or 0.
  @visibleForTesting
  int previewGain(int socket) => _preview[socket] ?? 0;

  /// Bursts shown for defeated enemies so far.
  @visibleForTesting
  int get killBursts => _killBursts;

  @override
  bool get hasProgress => _placed || battle.hasStarted;

  @override
  Color backgroundColor() => const Color(0x00000000);

  List<Color> get _palette => setup.style.palette;

  // ---------------------------------------------------------------- layout

  bool _layoutReady = false;
  double _cell = 64;
  late Rect _arena;
  late Rect _header;
  late Rect _boardPanel;
  late Rect _caption;
  late List<Rect> _offerRects;
  late Rect _rerollRect;
  late Rect _wavePill;
  late Path _gearSmall;
  late Path _gearWeapon;
  late Path _gearOffer;

  static const double _top = 8;
  static const double _pad = 10;
  static const double _headerHeight = 28;
  static const double _captionHeight = 26;
  static const double _offerHeight = 88;
  static const double _buttonHeight = 52;
  static const double _gap = 10;

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    final w = size.x;
    final h = size.y;
    final cw = min(w - 32, 460.0);
    final left = (w - cw) / 2;
    final arenaHeight = (h * 0.24).clamp(120.0, 200.0);
    const fixed =
        _top +
        _gap +
        _headerHeight +
        _captionHeight +
        _offerHeight +
        _gap +
        _buttonHeight +
        12;
    final boardSpace = h - fixed - arenaHeight;
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
    _arena = Rect.fromLTWH(left, _top, cw, arenaHeight);
    _header = Rect.fromLTWH(
      w / 2 - boardW / 2,
      _arena.bottom + _gap,
      boardW,
      _headerHeight,
    );
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
    _wavePill = Rect.fromLTWH(
      left + rerollW + 10,
      buttonTop,
      cw - rerollW - 10,
      _buttonHeight,
    );
    _gearSmall = gearPath(_cell * 0.42, 10);
    _gearWeapon = gearPath(_cell * 0.47, 12, depth: 0.2);
    _gearOffer = gearPath(min(28, _offerHeight * 0.3), 10);
    _layoutReady = true;
  }

  /// Tap area of a board socket.
  Rect socketRect(int socket) => Rect.fromLTWH(
    _boardPanel.left + _pad + board.colOf(socket) * _cell,
    _boardPanel.top + _pad + board.rowOf(socket) * _cell,
    _cell,
    _cell,
  );

  Rect offerRect(int offer) => _offerRects[offer];

  Rect get rerollRect => _rerollRect;

  /// The fight area at the top.
  Rect get arenaRect => _arena;

  // ----------------------------------------------------------------- input

  @override
  void onTapDown(TapDownEvent event) {
    if (!_layoutReady || isOver) return;
    final p = event.canvasPosition.toOffset();
    for (var i = 0; i < _offerRects.length; i++) {
      if (_offerRects[i].contains(p)) {
        if (!selectOffer(i)) _shakeAt(_offerRects[i]);
        return;
      }
    }
    if (_rerollRect.contains(p)) {
      if (!reroll()) _shakeAt(_rerollRect);
      return;
    }
    for (var s = 0; s < board.socketCount; s++) {
      if (socketRect(s).contains(p)) {
        if (!tapSocket(s)) _shakeAt(socketRect(s));
        return;
      }
    }
  }

  void _shakeAt(Rect rect) {
    _rejectRect = rect;
    _rejectAge = 0;
  }

  /// Picks offer [offer] (or drops it when it is already picked).
  /// Rejected when the coins do not cover the price.
  bool selectOffer(int offer) {
    if (isOver) return false;
    if (selectedOffer == offer) {
      _select(null);
      setup.sounds.tap();
      return true;
    }
    if (!shop.canAfford(offer)) {
      _reject();
      return false;
    }
    _select(offer);
    setup.sounds.tap();
    _haptic();
    return true;
  }

  /// Picks [offer] (or none) and works out the power preview.
  void _select(int? offer) {
    selectedOffer = offer;
    _refreshPreview();
  }

  void _refreshPreview() {
    final offer = selectedOffer;
    if (offer == null) {
      _preview = const {};
      return;
    }
    final gear = shop.offers[offer];
    final before = board.totalPower;
    _preview = {
      for (var s = 0; s < board.socketCount; s++)
        if (board.isEmpty(s))
          s: (board.copy()..place(s, gear)).totalPower - before,
    }..removeWhere((_, gain) => gain <= 0);
  }

  /// With a picked offer: buys it and places it in [socket]. Without one:
  /// sells the gear in [socket] for [Gear.sellPrice]. Rejected when the
  /// socket is taken (or empty, when selling) or holds a weapon.
  bool tapSocket(int socket) {
    if (isOver) return false;
    final offer = selectedOffer;
    if (offer == null && board.gearAt(socket) != null) return _sell(socket);
    if (offer == null || !board.isEmpty(socket)) {
      _reject();
      return false;
    }
    if (!shop.canAfford(offer)) {
      _select(null);
      _reject();
      return false;
    }
    final gear = shop.buy(offer)!;
    final placement = board.place(socket, gear)!;
    _placed = true;
    _select(null);
    battle.setPowers(board.powers);
    if (placement.merged) {
      setup.sounds.complete(1);
      _bursts.add(_Burst(socketRect(placement.socket).center));
    } else {
      setup.sounds.tap();
    }
    _haptic();
    _updateStatus();
    return true;
  }

  bool _sell(int socket) {
    final gear = board.remove(socket)!;
    shop.sell(gear);
    _placed = true;
    battle.setPowers(board.powers);
    setup.sounds.whoosh();
    _haptic();
    _addPopup('+${gear.sellPrice}', socketRect(socket).center, AppColors.text);
    _updateStatus();
    return true;
  }

  /// New offers for [CogShop.rerollPrice] coin.
  bool reroll() {
    if (isOver || !shop.reroll()) {
      _reject();
      return false;
    }
    _select(null);
    setup.sounds.tap();
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

  void _addPopup(String text, Offset at, Color color) {
    if (_popups.length >= _maxPopups) _popups.removeAt(0);
    _popups.add(_Popup(text, at, color));
  }

  void _onHit(int damage, int weapon) {
    _hitFlash = 0.12;
    if (!_layoutReady || battle.aliveCount == 0) return;
    final at = _arenaPoint(battle.enemyX[battle.front], _arenaUnit * 1.9);
    final jitter = Offset(((_popups.length * 37) % 21 - 10).toDouble(), 0);
    _addPopup('-$damage', at + jitter, _weaponColor(weapon));
  }

  void _onKill(double x, int coins) {
    _killBursts++;
    _shake = _shakeLife;
    if (!_layoutReady) return;
    final at = _arenaPoint(x, 0);
    _bursts.add(_Burst(at - Offset(0, _arenaUnit * 0.75)));
    _addPopup(
      '+$coins',
      at - Offset(0, _arenaUnit * 2.2),
      AppColors.accentMint,
    );
  }

  void _updateStatus() {
    final b = battle;
    final wave = isEndless
        ? 'Wave ${b.waveIndex + 1}'
        : 'Wave ${b.waveIndex + 1}/${config.waveCount}';
    status.value =
        'Coins ${shop.coins} · $wave · Fighter ${b.fighterHp.ceil()}';
  }

  // ---------------------------------------------------------------- update

  @override
  void update(double dt) {
    super.update(dt);
    // Long frames (for example after a pause) must not jump the fight.
    final frame = min(dt, maxFrame);
    _time += frame;
    _rejectAge += frame;
    _hitFlash = max(0, _hitFlash - frame);
    _shake = max(0, _shake - frame);
    for (final burst in _bursts) {
      burst.age += frame;
    }
    _bursts.removeWhere((burst) => burst.age >= _Burst.life);
    for (final popup in _popups) {
      popup.age += frame;
    }
    _popups.removeWhere((popup) => popup.age >= _Popup.life);
    if (isOver) return;

    final wasWaiting = battle.isWaiting;
    final clearedBefore = battle.wavesCleared;
    battle.advance(frame);
    if (wasWaiting && !battle.isWaiting) setup.sounds.whoosh();
    if (battle.wavesCleared > clearedBefore) {
      setup.sounds.complete(min(battle.wavesCleared + 1, 6));
      _haptic();
    }
    // Defeated enemies pay coins.
    final earned = battle.coinsEarned - _coinsSeen;
    if (earned > 0) {
      _coinsSeen = battle.coinsEarned;
      shop.coins += earned;
      _refreshPreview();
    }
    _updateStatus();
    if (battle.isOver) {
      if (isEndless) {
        finish(ArcadeResult.ended(battle.wavesCleared, 'Your fighter fell'));
      } else if (battle.won!) {
        finish(ArcadeResult.won(battle.stars));
      } else {
        finish(const ArcadeResult.lost('Your fighter fell'));
      }
    }
  }

  // ---------------------------------------------------------------- render

  // Paints are reused, so a frame allocates almost nothing. Each helper
  // sets one up for the next draw call only.
  final Paint _fillPaint = Paint();
  final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;
  final Paint _layerPaint = Paint();

  Paint _fill(Color color) => _fillPaint
    ..shader = null
    ..color = color;

  Paint _shaded(Shader shader) => _fillPaint
    ..color = const Color(0xFFFFFFFF)
    ..shader = shader;

  Paint _stroke(Color color, [double width = 1]) => _strokePaint
    ..color = color
    ..strokeWidth = width;

  double get _arenaUnit => min(_arena.height * 0.13, 30.0);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!_layoutReady) return;
    _renderArena(canvas);
    _renderHeader(canvas);
    _renderBoard(canvas);
    _renderShop(canvas);
    _renderBursts(canvas);
    _renderPopups(canvas);
    _renderReject(canvas);
  }

  static Color _alpha(double a) => Color.fromRGBO(0, 0, 0, a.clamp(0.0, 1.0));

  void _glassPanel(Canvas canvas, RRect r) {
    canvas.drawRRect(
      r,
      _shaded(
        ui.Gradient.linear(r.outerRect.topCenter, r.outerRect.bottomCenter, [
          AppColors.glassFill,
          AppColors.glassFillLow,
        ]),
      ),
    );
    canvas.drawRRect(r, _stroke(AppColors.glassBorder));
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
      canvas.drawRRect(r, _fill(AppColors.glassStrong));
      canvas.drawRRect(r, _stroke(_weaponColor(i).withValues(alpha: 0.6)));
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
      if (selectedOffer != null) ...board.linkedEmptySockets,
      if (!_placed && config.hintSocket != null) config.hintSocket!,
    };
    final pulse = 0.5 + 0.5 * sin(_time * 4);
    for (var s = 0; s < board.socketCount; s++) {
      final rect = socketRect(s);
      final c = rect.center;
      // Socket well.
      canvas.drawCircle(c, _cell * 0.34, _fill(AppColors.well));
      final glow = glowing.contains(s);
      canvas.drawCircle(
        c,
        _cell * 0.34,
        glow
            ? _stroke(
                AppColors.accentMint.withValues(alpha: 0.45 + 0.55 * pulse),
                2.5,
              )
            : _stroke(AppColors.glassBorder),
      );
      final spin =
          ((board.colOf(s) + board.rowOf(s)).isEven ? 1 : -1) * _time * 1.4;
      final weaponIndex = board.weapons.indexOf(s);
      if (weaponIndex >= 0) {
        _drawWeapon(canvas, c, weaponIndex, spin);
        continue;
      }
      final gear = board.gearAt(s);
      if (gear == null) {
        // Power the picked offer would add here.
        final gain = _preview[s];
        if (gain != null) {
          _text.paintCentered(
            canvas,
            '+$gain',
            c,
            size: _cell * 0.2,
            color: AppColors.accentMint.withValues(alpha: 0.6 + 0.4 * pulse),
          );
        }
        continue;
      }
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
      _shaded(
        ui.Gradient.linear(Offset(-r, -r), Offset(r, r), [
          AppColors.accentMint,
          AppColors.accentLavender,
        ]),
      ),
    );
    canvas.restore();
    canvas.drawCircle(Offset.zero, r * 0.5, _fill(AppColors.well));
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
    canvas.drawPath(path, _fill(color));
    if (!gear.isNumber) {
      // Multipliers get a dark ring so they read apart from numbers.
      canvas.drawPath(
        path,
        _stroke(AppColors.well.withValues(alpha: 0.6 * alpha), 2),
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

  String get _captionText {
    if (selectedOffer != null) return 'Tap a glowing socket to place it';
    if (config.hintSocket != null && !_placed) {
      return 'Tap a gear below, then the glowing socket';
    }
    if (board.hasGears) return 'Buy a gear, or tap a placed gear to sell it';
    return 'Tap a gear to buy it · Coins ${shop.coins}';
  }

  void _renderShop(Canvas canvas) {
    _text.paintCentered(
      canvas,
      _captionText,
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
        canvas.drawRRect(r, _stroke(AppColors.accentMint, 2.5));
      }
      final spin = selectedOffer == i ? _time * 2 : 0.0;
      _drawGear(
        canvas,
        Offset(rect.center.dx, rect.top + 34),
        gear,
        _gearOffer,
        spin,
        afford ? 1 : 0.35,
        15,
      );
      _text.paintCentered(
        canvas,
        gear.price == 1 ? '1 coin' : '${gear.price} coins',
        Offset(rect.center.dx, rect.bottom - 14),
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
    canvas.drawRRect(reroll, _fill(AppColors.glassStrong));
    canvas.drawRRect(reroll, _stroke(AppColors.glassBorder));
    _text.paintCentered(
      canvas,
      'Reroll · ${CogShop.rerollPrice}',
      _rerollRect.center,
      size: 16,
      color: shop.coins >= CogShop.rerollPrice
          ? AppColors.text
          : AppColors.textMuted,
    );
    // Coins and the wave state.
    final pill = RRect.fromRectAndRadius(_wavePill, const Radius.circular(999));
    canvas.drawRRect(pill, _fill(AppColors.glassStrong));
    canvas.drawRRect(pill, _stroke(AppColors.glassBorder));
    _text.paintCentered(
      canvas,
      'Coins ${shop.coins} · $_waveLabel',
      _wavePill.center,
      size: 15,
      color: AppColors.text,
    );
  }

  String get _waveLabel {
    final b = battle;
    final n = b.waveIndex + 1;
    final name = isEndless ? 'Wave $n' : 'Wave $n/${config.waveCount}';
    if (b.isWaiting) return '$name in ${b.waitLeft.ceil()}';
    return name;
  }

  /// Red outline that jiggles on the target of a rejected tap.
  void _renderReject(Canvas canvas) {
    final rect = _rejectRect;
    if (rect == null || _rejectAge >= _rejectLife) return;
    final k = _rejectAge / _rejectLife;
    final dx = sin(_rejectAge * 60) * 4 * (1 - k);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(Offset(dx, 0)).inflate(2),
        const Radius.circular(20),
      ),
      _stroke(AppColors.danger.withValues(alpha: 1 - k), 2.5),
    );
  }

  // ----------------------------------------------------------------- arena

  double get _groundY => _arena.bottom - _arena.height * 0.18;

  Offset _arenaPoint(double x, double lift) {
    final a = _arena;
    return Offset(
      a.left + 16 + (x / CogBattle.arenaLength) * (a.width - 32),
      _groundY - lift,
    );
  }

  void _renderArena(Canvas canvas) {
    final b = battle;
    final a = _arena;
    final panel = RRect.fromRectAndRadius(
      a,
      const Radius.circular(AppRadii.card),
    );
    _glassPanel(canvas, panel);
    canvas.save();
    canvas.clipRRect(panel);
    // A kill shakes the arena for a moment.
    if (_shake > 0) {
      final k = _shake / _shakeLife;
      canvas.translate(sin(_time * 70) * 3 * k, cos(_time * 55) * 2 * k);
    }
    // Ground.
    canvas.drawLine(
      Offset(a.left + 12, _groundY),
      Offset(a.right - 12, _groundY),
      _stroke(AppColors.glassBorder, 2),
    );
    final unit = _arenaUnit;
    _renderFighter(canvas, b, unit);
    if (b.isWaiting) {
      _renderCountdown(canvas, b);
    } else {
      _renderWave(canvas, b, unit);
    }
    canvas.restore();
  }

  /// Big "Wave 2 in 3" while the board is built between waves.
  void _renderCountdown(Canvas canvas, CogBattle b) {
    final secs = b.waitLeft.ceil();
    final k = b.waitLeft - b.waitLeft.floor();
    final center = Offset(
      _arena.center.dx + _arena.width * 0.12,
      _arena.center.dy - 8,
    );
    final title = _text.get(
      'Wave ${b.waveIndex + 1}',
      size: 15,
      color: AppColors.textMuted,
      weight: FontWeight.w600,
    );
    title.paint(canvas, center - Offset(title.width / 2, title.height + 18));
    final number = _text.get(
      '$secs',
      size: 40,
      color: AppColors.text,
      weight: FontWeight.w800,
    );
    canvas.saveLayer(
      Rect.fromCenter(center: center, width: 120, height: 80),
      _layerPaint..color = _alpha(0.4 + 0.6 * k),
    );
    number.paint(canvas, center - Offset(number.width / 2, number.height / 2));
    canvas.restore();
  }

  void _renderWave(Canvas canvas, CogBattle b, double unit) {
    final a = _arena;
    // Enemies, front first.
    for (var i = b.front; i < b.enemyX.length; i++) {
      final x = b.enemyX[i];
      if (x > CogBattle.arenaLength + 6) continue;
      final bob = (sin(_time * 9 + i) * 0.5 + 0.5) * unit * 0.15;
      final base = _arenaPoint(x, bob);
      // The front enemy flashes white when a shot lands.
      final tint = _palette[(i.isEven ? 0 : 4) % _palette.length];
      final hit = i == b.front && _hitFlash > 0;
      final color = hit
          ? Color.lerp(tint, const Color(0xFFFFFFFF), 0.6)!
          : tint;
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
        _fill(color),
      );
      final eye = _fill(AppColors.well);
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
      canvas.drawCircle(p, unit * 0.32, _fill(color.withValues(alpha: 0.25)));
      canvas.drawCircle(p, unit * 0.16, _fill(color));
    }
    // Shared wave HP above the wave.
    if (b.aliveCount > 0) {
      final frontX = b.enemyX[b.front];
      final backX = min(b.enemyX.last, CogBattle.arenaLength);
      final mid = _arenaPoint((frontX + max(frontX, backX)) / 2, unit * 2.3);
      final label = _text.get(
        'Wave HP ${b.waveHp}',
        size: 14,
        color: AppColors.text,
      );
      final x = mid.dx.clamp(
        a.left + 12 + label.width / 2,
        a.right - 12 - label.width / 2,
      );
      final y = max(a.top + 6 + label.height, mid.dy);
      label.paint(canvas, Offset(x - label.width / 2, y - label.height));
      _bar(
        canvas,
        Rect.fromCenter(center: Offset(x, y + 6), width: 90, height: 6),
        b.waveHp / b.wave.hp,
        _palette[0],
      );
    }
  }

  void _renderFighter(Canvas canvas, CogBattle b, double unit) {
    final base = _arenaPoint(CogBattle.fighterX, 0);
    final shake = b.inContact ? sin(_time * 40) * 1.5 : 0.0;
    final body = Rect.fromCenter(
      center: base - Offset(-shake, unit * 0.85),
      width: unit * 1.1,
      height: unit * 1.7,
    );
    final rbody = RRect.fromRectAndRadius(body, Radius.circular(unit * 0.55));
    canvas.drawRRect(
      rbody,
      _shaded(
        ui.Gradient.linear(body.topCenter, body.bottomCenter, [
          AppColors.accentMint,
          AppColors.accentLavender,
        ]),
      ),
    );
    // Red pulse while the front enemy hurts the fighter.
    if (b.inContact) {
      final pulse = 0.5 + 0.5 * sin(_time * 18);
      canvas.drawRRect(
        rbody,
        _fill(AppColors.danger.withValues(alpha: 0.25 + 0.25 * pulse)),
      );
    }
    canvas.drawCircle(
      body.center + Offset(unit * 0.2, -unit * 0.35),
      unit * 0.1,
      _fill(AppColors.well),
    );
    // Small gear cannon on the fighter's side.
    canvas.save();
    canvas.translate(body.right, body.center.dy + unit * 0.15);
    canvas.rotate(_time * 3);
    canvas.scale(unit * 0.32 / (_cell * 0.42));
    canvas.drawPath(_gearSmall, _fill(AppColors.well));
    canvas.restore();
    // Fighter HP.
    final hp = b.fighterHp / CogBattle.fighterMaxHp;
    _text.paintCentered(
      canvas,
      '${b.fighterHp.ceil()}',
      Offset(body.center.dx, body.top - 18),
      size: 13,
      color: AppColors.text,
    );
    _bar(
      canvas,
      Rect.fromCenter(
        center: Offset(body.center.dx, body.top - 7),
        width: unit * 1.6,
        height: 5,
      ),
      hp,
      hp > 1 / 3 ? AppColors.accentMint : AppColors.danger,
    );
  }

  void _bar(Canvas canvas, Rect rect, double fraction, Color color) {
    final r = Radius.circular(rect.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, r), _fill(AppColors.well));
    final f = fraction.clamp(0.0, 1.0);
    if (f <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, rect.width * f, rect.height),
        r,
      ),
      _fill(color),
    );
  }

  void _renderBursts(Canvas canvas) {
    for (final burst in _bursts) {
      final k = burst.age / _Burst.life;
      canvas.drawCircle(
        burst.center,
        12 + 26 * k,
        _stroke(AppColors.accentMint.withValues(alpha: 1 - k), 3 * (1 - k)),
      );
    }
  }

  /// Damage numbers, coins from kills and sales that float up and fade.
  void _renderPopups(Canvas canvas) {
    for (final popup in _popups) {
      final k = popup.age / _Popup.life;
      final p = _text.get(
        popup.text,
        size: 15,
        color: popup.color,
        weight: FontWeight.w800,
      );
      canvas.saveLayer(
        Rect.fromCenter(
          center: popup.at,
          width: p.width + 8,
          height: p.height + 40,
        ).shift(Offset(0, -14 * k)),
        _layerPaint..color = _alpha(1 - k * k),
      );
      p.paint(canvas, popup.at - Offset(p.width / 2, p.height / 2 + 28 * k));
      canvas.restore();
    }
  }
}

/// Short ring shown on a merge or a defeated enemy.
class _Burst {
  _Burst(this.center);

  static const double life = 0.4;

  final Offset center;
  double age = 0;
}

/// Floating text: damage on a hit, coins from a kill or a sale.
class _Popup {
  _Popup(this.text, this.at, this.color);

  static const double life = 0.7;

  final String text;
  final Offset at;
  final Color color;
  double age = 0;
}
