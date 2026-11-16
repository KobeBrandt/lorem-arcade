import 'dart:ui';

/// Sounds the game asks for. The app passes a real player or [SilentSounds].
abstract class GameSounds {
  /// A tap sent blocks into the loop.
  void tap();

  /// Blocks rose into the loop.
  void whoosh();

  /// A tap did nothing (loop full, tube busy, no moves left).
  void blocked();

  /// A tube was sorted. [combo] is 1 for a single completion, 2 for the
  /// second within the combo window, and so on (pitch rises with it).
  void complete(int combo);

  void win();

  void fail();
}

class SilentSounds implements GameSounds {
  const SilentSounds();

  @override
  void tap() {}

  @override
  void whoosh() {}

  @override
  void blocked() {}

  @override
  void complete(int combo) {}

  @override
  void win() {}

  @override
  void fail() {}
}

/// What the player did in a won level.
class LevelResult {
  const LevelResult({
    required this.taps,
    required this.solutionLength,
    required this.seconds,
  });

  /// Accepted taps (taps that sent blocks into the loop).
  final int taps;
  final int solutionLength;

  /// Play time from start to win.
  final double seconds;

  int get stars => starsFor(taps, solutionLength);
}

/// 3 stars at the solver's tap count or fewer, 2 up to 50% more
/// (rounded up), 1 otherwise.
int starsFor(int taps, int solutionLength) {
  if (taps <= solutionLength) return 3;
  if (taps <= (solutionLength * 1.5).ceil()) return 2;
  return 1;
}

/// Colors and look the game draws blocks with.
class BlockStyle {
  const BlockStyle({required this.palette, this.showShapes = true});

  /// One color per color id (at least 6).
  final List<Color> palette;

  /// Draw the shape symbol on each block.
  final bool showShapes;
}
