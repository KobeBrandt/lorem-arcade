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
        ],
      ),
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
