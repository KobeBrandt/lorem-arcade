import 'package:flutter/material.dart';

import '../settings.dart';
import 'app_theme.dart';
import 'glass_page.dart';

/// Haptics, sound and the color-blind palette.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => GlassPage(
        title: 'Settings',
        children: [
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _Toggle(
                  title: 'Haptics',
                  subtitle: 'Vibrate on taps and wins.',
                  value: settings.haptics,
                  onChanged: settings.setHaptics,
                ),
                _Toggle(
                  title: 'Sound',
                  subtitle: 'Sound effects while playing.',
                  value: settings.sound,
                  onChanged: settings.setSound,
                ),
                _Toggle(
                  title: 'Color-blind palette',
                  subtitle: 'Okabe-Ito colors with shapes. Replaces the theme.',
                  value: settings.colorBlind,
                  onChanged: settings.setColorBlind,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Semantics(
              header: true,
              child: const Text('Hidden games', style: AppText.title),
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _hiddenGames(),
          ),
        ],
      ),
    );
  }

  Widget _hiddenGames() {
    final hidden = settings.hiddenGames;
    if (hidden.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(
          'No hidden games. Long-press a game in the hub to hide it.',
          style: AppText.caption,
        ),
      );
    }
    return Column(
      children: [
        for (final game in hidden)
          ListTile(
            leading: Icon(game.icon, color: AppColors.text),
            title: Text(
              game.title,
              style: AppText.title.copyWith(fontSize: 18),
            ),
            trailing: TextButton(
              onPressed: () => settings.setHidden(game, false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentMint,
                minimumSize: const Size(64, 48),
              ),
              child: Text('Show', semanticsLabel: 'Show ${game.title}'),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: AppText.title.copyWith(fontSize: 18)),
      subtitle: Text(subtitle, style: AppText.caption),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.textOnAccent,
      activeTrackColor: AppColors.accentMint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }
}
