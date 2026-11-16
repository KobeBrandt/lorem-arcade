import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'glass_page.dart';

/// Win view in the same dark glass style as the game: blurred board
/// behind, glass card with a pill, title, message and one accent button.
class LevelCompleteScreen extends StatefulWidget {
  const LevelCompleteScreen({
    super.key,
    required this.pill,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.stars,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String pill;
  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  /// Stars earned in this level (1-3), shown above the title.
  final int? stars;

  /// Optional second button under the main one (for example Share).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  State<LevelCompleteScreen> createState() => _LevelCompleteScreenState();
}

class _LevelCompleteScreenState extends State<LevelCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: ColoredBox(
          color: AppColors.bgDeep.withValues(alpha: 0.6),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(curve),
                  child: GlassCard(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlassPill(text: widget.pill),
                        if (widget.stars != null) ...[
                          const SizedBox(height: 16),
                          StarRow(filled: widget.stars!),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          widget.title,
                          style: AppText.display,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.message,
                          style: AppText.body,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        AccentButton(
                          label: widget.buttonLabel,
                          onPressed: widget.onPressed,
                        ),
                        if (widget.secondaryLabel != null &&
                            widget.onSecondary != null) ...[
                          const SizedBox(height: 10),
                          GlassButton(
                            label: widget.secondaryLabel!,
                            onPressed: widget.onSecondary!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
