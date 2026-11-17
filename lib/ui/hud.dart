import 'package:flutter/material.dart';

import '../game/color_flow_game.dart';
import '../game/game_mode.dart';
import 'app_theme.dart';

/// Top bar: Home left, title, a mode pill (moves, time or score) and the
/// round Retry (Skip in endless) button right, segmented loop bar below.
/// Its rendered height (below the top inset) goes to [onHeight] after
/// every layout change, so the game can place the board under it.
class Hud extends StatefulWidget {
  const Hud({
    super.key,
    required this.game,
    required this.onHome,
    required this.onRestart,
    required this.day,
    this.onHeight,
  });

  final ColorFlowGame game;
  final VoidCallback onHome;

  /// The round Retry / Skip / New run button.
  final VoidCallback onRestart;

  /// The day the game screen opened; names the daily puzzle.
  final DateTime day;

  final ValueChanged<double>? onHeight;

  @override
  State<Hud> createState() => _HudState();
}

class _HudState extends State<Hud> {
  final GlobalKey _contentKey = GlobalKey();
  double? _reportedHeight;

  /// Measures the HUD after this frame (it may change with the text
  /// scale or the content) and reports a new height.
  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _contentKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final height = box.size.height;
      if (height == _reportedHeight) return;
      _reportedHeight = height;
      widget.onHeight?.call(height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final endless = game.mode == GameMode.endless;
    // Rebuild (and measure again) when the text scale changes.
    MediaQuery.textScalerOf(context);
    return SafeArea(
      child: Padding(
        key: _contentKey,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: ValueListenableBuilder<HudState>(
          valueListenable: game.hud,
          builder: (context, state, _) {
            _scheduleMeasure();
            final pill = _pillText(state);
            final secondsLeft = state.secondsLeft;
            final warning = secondsLeft != null && secondsLeft <= 10;
            final pillWidget = pill == null
                ? null
                : (warning ? WarningPill(text: pill) : GlassPill(text: pill));
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // At least 48 dp; grows with large text.
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      RoundIconButton(
                        icon: Icons.home_rounded,
                        tooltip: 'Home',
                        onPressed: widget.onHome,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Title(
                          mode: game.mode,
                          level: state.level,
                          day: widget.day,
                        ),
                      ),
                      if (pillWidget != null) ...[
                        // The clock is read out as it changes.
                        secondsLeft != null
                            ? Semantics(liveRegion: true, child: pillWidget)
                            : pillWidget,
                        const SizedBox(width: 10),
                      ],
                      RoundIconButton(
                        icon: endless
                            ? Icons.skip_next_rounded
                            : Icons.refresh_rounded,
                        tooltip: endless
                            ? 'Skip board'
                            : (game.mode == GameMode.rush
                                  ? 'New run'
                                  : 'Retry level'),
                        onPressed: widget.onRestart,
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
      GameMode.rush => mode.title,
      _ => 'Level $level',
    };
    if (mode == GameMode.levels || mode == GameMode.rush) {
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
        return Semantics(
          label: 'Loop ${widget.filled} of ${widget.capacity}',
          excludeSemantics: true,
          child: Row(
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
          ),
        );
      },
    );
  }
}

/// Red pill that pulses, for the last seconds on the clock.
class WarningPill extends StatefulWidget {
  const WarningPill({super.key, required this.text});

  final String text;

  @override
  State<WarningPill> createState() => _WarningPillState();
}

class _WarningPillState extends State<WarningPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 1,
        end: 1.12,
      ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.danger.withValues(alpha: 0.5),
              blurRadius: 12,
            ),
          ],
        ),
        child: Text(
          widget.text,
          style: AppText.caption.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
      ),
    );
  }
}
