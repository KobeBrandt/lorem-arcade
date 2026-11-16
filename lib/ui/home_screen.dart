import 'package:flutter/material.dart';

import '../game/game_feedback.dart';
import '../game/game_mode.dart';
import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'game_screen.dart';
import 'glass_page.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'themes_screen.dart';

/// Start screen: one glass card per game mode.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.progress,
    required this.settings,
    this.sounds = const SilentSounds(),
  });

  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Map<GameMode, IconData> _icons = {
    GameMode.levels: Icons.grid_view_rounded,
    GameMode.moves: Icons.touch_app_rounded,
    GameMode.timed: Icons.timer_outlined,
    GameMode.daily: Icons.calendar_today_rounded,
    GameMode.endless: Icons.all_inclusive_rounded,
    GameMode.beltFull: Icons.sync_rounded,
  };

  Future<void> _open(GameMode mode) => _push(
    (_) => GameScreen(
      mode: mode,
      progress: widget.progress,
      settings: widget.settings,
      sounds: widget.sounds,
    ),
  );

  Future<void> _push(WidgetBuilder builder) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
    // Progress or settings may have changed on the other screen.
    if (mounted) setState(() {});
  }

  String _status(GameMode mode, DateTime today) {
    final p = widget.progress;
    switch (mode) {
      case GameMode.daily:
        final streak = p.dailyStreak(today);
        final days = streak == 1 ? '1 day' : '$streak days';
        return p.dailySolved(today)
            ? 'Solved · streak $days'
            : '${weekdayNames[today.weekday - 1]} · streak $days';
      case GameMode.endless:
        return 'Best ${p.endlessBest}';
      default:
        return 'Level ${p.level(mode)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          const GlowBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    RoundIconButton(
                      icon: Icons.bar_chart_rounded,
                      tooltip: 'Stats',
                      onPressed: () =>
                          _push((_) => StatsScreen(progress: widget.progress)),
                    ),
                    const SizedBox(width: 8),
                    RoundIconButton(
                      icon: Icons.palette_outlined,
                      tooltip: 'Themes',
                      onPressed: () => _push(
                        (_) => ThemesScreen(
                          progress: widget.progress,
                          settings: widget.settings,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    RoundIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: 'Settings',
                      onPressed: () => _push(
                        (_) => SettingsScreen(settings: widget.settings),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const Flexible(
                        child: Text('Color Flow', style: AppText.display),
                      ),
                      const SizedBox(width: 12),
                      StarCountPill(stars: widget.progress.totalStars),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 24),
                  child: Text('Pick a mode.', style: AppText.body),
                ),
                for (final mode in GameMode.values) ...[
                  _ModeCard(
                    icon: _icons[mode]!,
                    title: mode.title,
                    description: mode.description,
                    status: _status(mode, today),
                    enabled:
                        mode != GameMode.daily ||
                        !widget.progress.dailySolved(today),
                    onTap: () => _open(mode),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Stack(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                  ),
                  child: Icon(icon, color: AppColors.textOnAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.title.copyWith(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(description, style: AppText.caption),
                      const SizedBox(height: 8),
                      GlassPill(text: status),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.card),
                onTap: enabled ? onTap : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
