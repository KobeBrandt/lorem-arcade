import 'dart:math';
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show BuildContext, KeyEventResult, Widget;

import '../../arcade/arcade_level_game.dart';
import 'moo_munch_arrows.dart';
import 'moo_munch_board.dart';
import 'moo_munch_level.dart';
import 'moo_munch_painter.dart';

/// Moo Munch: steer a cow to the carrots. Every carrot adds a spot to
/// its tail; the fence, rocks and its own tail stop it.
///
/// Levels: eat the level's carrots with [mooLives] lives. A crash costs
/// a life and puts the cow back at the start; stars are the lives left.
/// Endless: one life, the cow gets faster with every carrot, and the
/// score is the carrots eaten.
///
/// Turn by swiping on the field, with the arrow buttons under it, or
/// with the arrow keys.
class MooMunchGame extends ArcadeLevelGame with DragCallbacks, KeyboardEvents {
  MooMunchGame.levels(super.setup) : endless = false {
    level = buildMooMunchLevel(setup.level);
    board = MooMunchBoard(
      cols: mooCols,
      rows: mooRows,
      rocks: level.rocks,
      seed: setup.level,
    );
    _updateStatus();
  }

  MooMunchGame.endless(super.setup) : endless = true {
    level = const MooMunchLevel(carrots: 0, stepSeconds: 0.22, rocks: {});
    board = MooMunchBoard(
      cols: mooCols,
      rows: mooRows,
      seed: DateTime.now().millisecondsSinceEpoch,
    );
    _updateStatus();
  }

  /// Swipe distance in logical pixels that counts as one turn.
  static const double swipeDistance = 18;

  final bool endless;
  late final MooMunchLevel level;
  late final MooMunchBoard board;
  final MooMunchPainter _painter = MooMunchPainter();

  int carrots = 0;
  int lives = mooLives;

  /// Fades from 1 to 0 after a crash, for the red flash.
  double crashFlash = 0;

  /// Field rectangle on screen and the size of one cell.
  Rect fieldRect = Rect.zero;
  double cell = 0;

  double _clock = 0;
  Offset _swipe = Offset.zero;

  @override
  bool get hasProgress => board.moving || carrots > 0;

  @override
  Color backgroundColor() => const Color(0x00000000);

  double get stepSeconds =>
      endless ? mooEndlessStep(carrots) : level.stepSeconds;

  /// Queues a turn; plays a tap when it was taken.
  void steer(Heading heading) {
    if (result.value != null) return;
    if (board.turn(heading)) setup.sounds.tap();
  }

  @override
  Widget? buildControls(BuildContext context) => MooMunchArrows(onTurn: steer);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    const pad = 12.0;
    cell = max(
      1.0,
      min((size.x - pad * 2) / mooCols, (size.y - pad * 2) / mooRows),
    );
    final w = cell * mooCols;
    final h = cell * mooRows;
    fieldRect = Rect.fromLTWH((size.x - w) / 2, (size.y - h) / 2, w, h);
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _swipe = Offset.zero;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    _swipe += Offset(event.localDelta.x, event.localDelta.y);
    if (_swipe.distance < swipeDistance) return;
    steer(
      _swipe.dx.abs() > _swipe.dy.abs()
          ? (_swipe.dx > 0 ? Heading.right : Heading.left)
          : (_swipe.dy > 0 ? Heading.down : Heading.up),
    );
    _swipe = Offset.zero;
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final heading = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => Heading.up,
      LogicalKeyboardKey.arrowDown => Heading.down,
      LogicalKeyboardKey.arrowLeft => Heading.left,
      LogicalKeyboardKey.arrowRight => Heading.right,
      _ => null,
    };
    if (heading == null) return KeyEventResult.ignored;
    steer(heading);
    return KeyEventResult.handled;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final frame = min(dt, 0.1);
    if (crashFlash > 0) crashFlash = max(0, crashFlash - frame * 2);
    if (result.value != null) return;
    _clock += frame;
    while (_clock >= stepSeconds && result.value == null) {
      _clock -= stepSeconds;
      tick();
    }
  }

  /// One cow step. Public for tests.
  @visibleForTesting
  void tick() {
    switch (board.step()) {
      case StepOutcome.idle:
      case StepOutcome.moved:
        break;
      case StepOutcome.ate:
        carrots++;
        setup.sounds.complete(1 + min(carrots ~/ 5, 3));
        if (setup.haptics) HapticFeedback.lightImpact();
        if (!endless && carrots >= level.carrots) {
          finish(ArcadeResult.won(lives));
        } else if (board.carrot == null) {
          // The tail fills the whole field.
          finish(
            endless
                ? ArcadeResult.ended(carrots, 'The field is full')
                : ArcadeResult.won(lives),
          );
        }
      case StepOutcome.crashed:
        _crash();
    }
    _updateStatus();
  }

  void _crash() {
    crashFlash = 1;
    if (setup.haptics) HapticFeedback.mediumImpact();
    if (endless) {
      finish(ArcadeResult.ended(carrots, 'The cow bumped into something'));
      return;
    }
    lives--;
    if (lives <= 0) {
      finish(const ArcadeResult.lost('Out of lives'));
      return;
    }
    setup.sounds.blocked();
    board.reset();
    _clock = 0;
  }

  void _updateStatus() {
    status.value = endless
        ? 'Carrots $carrots'
        : 'Carrots $carrots/${level.carrots} · Lives $lives';
  }

  @override
  void render(Canvas canvas) {
    if (cell > 1) _painter.render(canvas, this);
    super.render(canvas);
  }
}
