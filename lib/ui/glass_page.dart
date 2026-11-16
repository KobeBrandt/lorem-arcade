import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Full screen page in the dark glass style: back button, title and a
/// scrolling list of [children].
class GlassPage extends StatelessWidget {
  const GlassPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
                  children: [
                    RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: AppText.display,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Row of [max] star icons, the first [filled] of them filled.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.filled, this.max = 3, this.size});

  final int filled;
  final int max;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$filled of $max stars',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < max; i++)
              Icon(
                i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size ?? 40,
                color: i < filled ? starColor : AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}

const Color starColor = Color(0xFFFFD86B);

/// Small pill with a star icon and a count.
class StarCountPill extends StatelessWidget {
  const StarCountPill({super.key, required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars stars',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.glassStrong,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, color: starColor, size: 18),
              const SizedBox(width: 4),
              Text(
                '$stars',
                style: AppText.caption.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
