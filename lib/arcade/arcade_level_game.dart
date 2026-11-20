import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import '../game/game_feedback.dart';

/// What the shell gives a level game when it builds one.
class ArcadeSetup {
  const ArcadeSetup({
    required this.level,
    required this.style,
    this.sounds = const SilentSounds(),
    this.haptics = true,
  });

  /// 1-based level number. Levels get harder as it grows.
  final int level;

  /// Block colors of the selected theme (shared with Color Flow).
  final BlockStyle style;

  final GameSounds sounds;

  /// Whether the game may use haptic feedback.
  final bool haptics;
}

/// How a level ended.
class ArcadeResult {
  /// Won with 1 to 3 [stars].
  const ArcadeResult.won(int stars)
    : stars = stars < 1 ? 1 : (stars > 3 ? 3 : stars),
      reason = '',
      score = 0;

  /// Lost; [reason] is shown to the player, for example 'The belt is full'.
  const ArcadeResult.lost(this.reason) : stars = 0, score = 0;

  /// An endless run ended with [score]; [reason] says why.
  const ArcadeResult.ended(this.score, this.reason) : stars = 0;

  final int stars;
  final String reason;

  /// Score of an ended endless run, else 0.
  final int score;

  bool get won => stars > 0;
}

/// Base class of the level games in the hub (Bead Belt, Cog Clash, Gate
/// Drop). The shell ([ArcadeLevelScreen]) owns the top bar, pause, back
/// confirm, the result cards, stars and saved levels. A game only plays
/// one level and reports how it ended through [result].
///
/// The game fills the area under the top bar. It must not draw its own
/// home or restart buttons.
abstract class ArcadeLevelGame extends FlameGame {
  ArcadeLevelGame(this.setup);

  final ArcadeSetup setup;

  /// One short line under the level title, for example 'Belt 12/40'.
  final ValueNotifier<String> status = ValueNotifier('');

  /// Set once when the level ends. The shell shows the result card.
  final ValueNotifier<ArcadeResult?> result = ValueNotifier(null);

  /// True once the player did something that leaving would throw away.
  /// The shell asks before leaving or restarting only then.
  bool get hasProgress;

  /// Optional Flutter controls the shell shows under the game, for
  /// example arrow buttons. Null (the default) shows none.
  Widget? buildControls(BuildContext context) => null;

  /// Ends the level. Later calls are ignored.
  @protected
  void finish(ArcadeResult outcome) {
    if (result.value != null) return;
    result.value = outcome;
  }

  /// Releases the notifiers. The shell calls it when the game is replaced.
  @mustCallSuper
  void disposeNotifiers() {
    status.dispose();
    result.dispose();
  }
}
