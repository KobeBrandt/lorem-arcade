import 'package:flutter/material.dart';

import '../arcade/arcade_catalog.dart';
import '../arcade/arcade_level_screen.dart';
import '../game/game_feedback.dart';
import '../game/game_mode.dart';
import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'game_screen.dart';
import 'glass_page.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'themes_screen.dart';

/// First screen: one card per game. Color Flow opens its mode list; the
/// other games open their next level. Stars from every game add up and
/// unlock themes for all of them.
class HubScreen extends StatefulWidget {
  const HubScreen({
    super.key,
    required this.progress,
    required this.settings,
    this.sounds = const SilentSounds(),
  });

  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  Future<T?> _push<T>(WidgetBuilder builder) async {
    final result = await Navigator.of(context)
        .push(MaterialPageRoute<T>(builder: builder));
    // Progress or settings may have changed on the other screen.
    if (mounted) setState(() {});
    return result;
  }

  Future<void> _openColorFlow() => _push(
    (_) => HomeScreen(
      progress: widget.progress,
      settings: widget.settings,
      sounds: widget.sounds,
    ),
  );

  Future<void> _openGame(ArcadeGame game) => _push(
    (_) => ArcadeLevelScreen(
      game: game,
      progress: widget.progress,
      settings: widget.settings,
      sounds: widget.sounds,
    ),
  );

  Future<void> _openStats() async {
    final mode = await _push<GameMode>(
      (_) => StatsScreen(progress: widget.progress),
    );
    // The empty stats page asks to play a Color Flow mode.
    if (mode != null && mounted) {
      await _push(
        (_) => GameScreen(
          mode: mode,
          progress: widget.progress,
          settings: widget.settings,
          sounds: widget.sounds,
        ),
      );
    }
  }

  String _gameStatus(ArcadeGame game) {
    final p = widget.progress;
    final stars = p.gameStars(game.id);
    return stars == 0
        ? 'Level ${p.gameLevel(game.id)}'
        : 'Level ${p.gameLevel(game.id)} · $stars ★';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: Stack(
        children: [
          const GlowBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                padding: pagePadding(constraints.maxWidth),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      RoundIconButton(
                        icon: Icons.bar_chart_rounded,
                        tooltip: 'Stats',
                        onPressed: _openStats,
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
                          child: Text('Games', style: AppText.display),
                        ),
                        const SizedBox(width: 12),
                        StarCountPill(stars: p.totalStars),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 4, 8, 24),
                    child: Text(
                      'Stars from every game unlock themes.',
                      style: AppText.body,
                    ),
                  ),
                  HubCard(
                    icon: Icons.view_column_rounded,
                    title: 'Color Flow',
                    description:
                        'Sort colored blocks through a looping belt. '
                        '${GameMode.values.length} modes.',
                    status: 'Level ${p.level(GameMode.levels)}',
                    onTap: _openColorFlow,
                  ),
                  for (final game in ArcadeGame.values) ...[
                    const SizedBox(height: 12),
                    HubCard(
                      icon: game.icon,
                      title: game.title,
                      description: game.description,
                      status: _gameStatus(game),
                      onTap: () => _openGame(game),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One game on the hub: icon, title, description and status; the whole
/// card is one button.
class HubCard extends StatelessWidget {
  const HubCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $status',
      onTap: onTap,
      excludeSemantics: true,
      child: Stack(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                  ),
                  child: Icon(icon, color: AppColors.textOnAccent, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.title.copyWith(fontSize: 20)),
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
                onTap: onTap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
