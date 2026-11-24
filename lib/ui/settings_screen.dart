import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings.dart';
import 'app_theme.dart';
import 'glass_page.dart';

/// Public privacy policy page. Google Play requires a link to it inside the app.
final Uri privacyPolicyUrl = Uri.parse(
  'https://kbrandt.dev/lorem-arcade/privacy',
);

/// Opens [url] and reports whether it worked.
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _openInBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// Haptics, sound, the color-blind palette, hidden games and the privacy link.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.openUrl = _openInBrowser,
  });

  final Settings settings;

  /// Opens links. Tests pass a fake to avoid starting a browser.
  final UrlOpener openUrl;

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
          _sectionHeader('Hidden games'),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _hiddenGames(),
          ),
          const SizedBox(height: 24),
          _sectionHeader('About'),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _PrivacyLink(openUrl: openUrl),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Semantics(header: true, child: Text(title, style: AppText.title)),
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

/// Opens the privacy policy in the browser, or shows its URL when that fails.
class _PrivacyLink extends StatelessWidget {
  const _PrivacyLink({required this.openUrl});

  final UrlOpener openUrl;

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await openUrl(privacyPolicyUrl);
    } on Exception {
      opened = false;
    }
    if (opened) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not open browser. Visit $privacyPolicyUrl'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.privacy_tip_outlined, color: AppColors.text),
      title: Text(
        'Privacy policy',
        style: AppText.title.copyWith(fontSize: 18),
      ),
      subtitle: const Text('Opens in your browser.', style: AppText.caption),
      trailing: const Icon(Icons.open_in_new, color: AppColors.text),
      onTap: () => _open(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
