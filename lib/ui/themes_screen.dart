import 'package:flutter/material.dart';

import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'glass_page.dart';

/// Block color themes. Locked themes show their star cost.
class ThemesScreen extends StatefulWidget {
  const ThemesScreen({
    super.key,
    required this.progress,
    required this.settings,
  });

  final Progress progress;
  final Settings settings;

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  Future<void> _select(BlockTheme theme, int stars) async {
    if (await widget.settings.selectTheme(theme, stars) && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final stars = widget.progress.totalStars;
    final selected = widget.settings.theme;
    return GlassPage(
      title: 'Themes',
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Earn stars to unlock.', style: AppText.body),
            ),
            StarCountPill(stars: stars),
          ],
        ),
        if (widget.settings.colorBlind) ...[
          const SizedBox(height: 8),
          const Text(
            'The color-blind palette is on in Settings and is used instead.',
            style: AppText.caption,
          ),
        ],
        const SizedBox(height: 16),
        for (final theme in BlockTheme.values) ...[
          _ThemeCard(
            theme: theme,
            unlocked: theme.unlockedWith(stars),
            selected: theme == selected,
            onTap: () => _select(theme, stars),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.unlocked,
    required this.selected,
    required this.onTap,
  });

  final BlockTheme theme;
  final bool unlocked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Widget trailing;
    if (selected) {
      trailing = const Icon(
        Icons.check_circle_rounded,
        color: AppColors.accentMint,
      );
    } else if (unlocked) {
      trailing = const SizedBox(width: 24);
    } else {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_rounded, color: AppColors.textMuted, size: 18),
          const SizedBox(width: 6),
          StarCountPill(stars: theme.cost),
        ],
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      enabled: unlocked,
      label: unlocked ? null : '${theme.title}, locked, ${theme.cost} stars',
      child: Opacity(
        opacity: unlocked ? 1 : 0.6,
        child: Stack(
          children: [
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          theme.title,
                          style: AppText.title.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            for (final color in theme.palette) ...[
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.block / 2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  onTap: unlocked ? onTap : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
