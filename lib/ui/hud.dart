import 'package:flutter/material.dart';

import '../game/color_flow_game.dart';
import '../game/game_mode.dart';
import 'app_theme.dart';

/// Top bar: Home left, title, a mode pill (moves, time or score) and the
/// round Retry (Skip in endless) button right, segmented loop bar below.
class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.game,
    required this.onHome,
    required this.day,
  });

  final ColorFlowGame game;
  final VoidCallback onHome;

  /// The day the game screen opened; names the daily puzzle.
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final endless = game.mode == GameMode.endless;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: ValueListenableBuilder<HudState>(
          valueListenable: game.hud,
          builder: (context, state, _) {
            final pill = _pillText(state);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      RoundIconButton(
                        icon: Icons.home_rounded,
                        tooltip: 'Home',
                        onPressed: onHome,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Title(
                          mode: game.mode,
                          level: state.level,
                          day: day,
                        ),
                      ),
                      if (pill != null) ...[
                        GlassPill(text: pill),
                        const SizedBox(width: 10),
                      ],
                      RoundIconButton(
                        icon: endless
                            ? Icons.skip_next_rounded
                            : Icons.refresh_rounded,
                        tooltip: endless ? 'Skip board' : 'Retry level',
                        onPressed: game.restartPressed,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // The loop count itself is shown inside the loop.
                LoopBar(
                  filled: state.loopCount,
                  capacity: state.loopCapacity,
                  flashKey: state.blockedTaps,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String? _pillText(HudState state) {
    if (state.movesLeft != null) {
      return state.movesLeft == 1 ? '1 move' : '${state.movesLeft} moves';
    }
    if (state.secondsLeft != null) {
      final s = state.secondsLeft!;
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    if (state.score != null) return 'Score ${state.score}';
    return null;
  }
}

/// Mode name as a small caption over the level title.
class _Title extends StatelessWidget {
  const _Title({required this.mode, required this.level, required this.day});

  final GameMode mode;
  final int level;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      GameMode.daily => weekdayNames[day.weekday - 1],
      GameMode.endless => 'Board $level',
      _ => 'Level $level',
    };
    if (mode == GameMode.levels) {
      return Text(title, style: AppText.title, overflow: TextOverflow.ellipsis);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(mode.title, style: AppText.caption),
        Text(
          title,
          style: AppText.title.copyWith(fontSize: 20, height: 1.1),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Segmented progress bar showing how full the loop is.
/// Flashes red when [flashKey] changes (a tap did not fit).
class LoopBar extends StatefulWidget {
  const LoopBar({
    super.key,
    required this.filled,
    required this.capacity,
    required this.flashKey,
  });

  final int filled;
  final int capacity;
  final int flashKey;

  @override
  State<LoopBar> createState() => _LoopBarState();
}

class _LoopBarState extends State<LoopBar> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void didUpdateWidget(LoopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flashKey != oldWidget.flashKey) _flash.forward(from: 0);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, _) {
        // 0 -> 1 -> 0 over the animation.
        final t = _flash.isAnimating ? 1 - (2 * _flash.value - 1).abs() : 0.0;
        final flashColor = Color.lerp(Colors.transparent, AppColors.danger, t)!;
        return Row(
          children: [
            for (var i = 0; i < widget.capacity; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i < widget.filled ? null : AppColors.glassStrong,
                    gradient: i < widget.filled
                        ? AppColors.accentGradient
                        : null,
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: flashColor,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
