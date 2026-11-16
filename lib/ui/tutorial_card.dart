import 'package:flutter/material.dart';

import '../game/game_mode.dart';
import 'app_theme.dart';

/// Short explanation shown the first time a mode is opened.
String tutorialText(GameMode mode) => switch (mode) {
  GameMode.levels =>
    'Tap a tube to send its top blocks into the loop. '
        'They ride the loop and drop into a tube that fits. Sort every tube.',
  GameMode.moves =>
    'Same rules, but every level has a tap limit. '
        'Plan ahead: the level fails when the moves run out.',
  GameMode.timed =>
    'Sort every tube before the clock runs out. '
        'The clock turns red in the last 10 seconds.',
  GameMode.daily =>
    'One puzzle a day, the same for everyone. '
        'Solve it every day to grow your streak.',
  GameMode.endless =>
    'Boards keep coming. Each sorted tube scores a point. '
        'Every 5 points earn a star.',
  GameMode.beltFull =>
    'The loop starts full. Let blocks land to make room '
        'before you can send new ones.',
};

/// Glass card over a dimmed game with the tutorial text and 'Got it'.
class TutorialCard extends StatelessWidget {
  const TutorialCard({super.key, required this.mode, required this.onDone});

  final GameMode mode;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgDeep.withValues(alpha: 0.6),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassPill(text: 'How to play'),
                  const SizedBox(height: 16),
                  Text(
                    mode.title,
                    style: AppText.display,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tutorialText(mode),
                    style: AppText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  AccentButton(label: 'Got it', onPressed: onDone),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
