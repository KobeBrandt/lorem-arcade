import 'package:flutter/material.dart';

import '../game/game_mode.dart';
import '../progress.dart';
import 'app_theme.dart';
import 'glass_page.dart';

/// Totals, plus level reached and fastest win per mode. Before anything
/// is played it shows a hint and a Play Levels button, which pops this
/// screen with [GameMode.levels] so home opens that mode.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.progress});

  final Progress progress;

  /// Seconds as m:ss, or a dash when there is no time yet.
  static String formatTime(double? seconds) {
    if (seconds == null) return '-';
    final s = seconds.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (!p.hasPlayed) {
      return GlassPage(
        title: 'Stats',
        children: [
          GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Text(
                  'Play a level to see your stats here.',
                  style: AppText.body,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                AccentButton(
                  label: 'Play Levels',
                  onPressed: () =>
                      Navigator.of(context).pop<GameMode>(GameMode.levels),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return GlassPage(
      title: 'Stats',
      children: [
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: _Big(label: 'Levels solved', value: '${p.levelsSolved}'),
              ),
              Expanded(
                child: _Big(label: 'Total stars', value: '${p.totalStars}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final mode in GameMode.values) ...[
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mode.title, style: AppText.title.copyWith(fontSize: 18)),
                const SizedBox(height: 8),
                ..._rows(mode),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  List<Widget> _rows(GameMode mode) {
    final p = progress;
    switch (mode) {
      case GameMode.endless:
        return [
          _Row('Best score', '${p.endlessBest}'),
          _Row('Points earned', '${p.endlessPoints}'),
        ];
      case GameMode.rush:
        return [_Row('Best score', '${p.rushBest}')];
      case GameMode.daily:
        return [
          _Row('Current streak', '${p.dailyStreak(DateTime.now())}'),
          _Row('Longest streak', '${p.dailyLongestStreak}'),
          _Row('Best time', formatTime(p.bestTime(mode))),
        ];
      default:
        return [
          _Row('Level reached', '${p.level(mode)}'),
          _Row('Best time', formatTime(p.bestTime(mode))),
        ];
    }
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppText.display),
        Text(label, style: AppText.caption),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.body)),
          Text(
            value,
            style: AppText.body.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
