import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared colors for the whole app (dark glass style).
/// The Flame game and the Flutter widgets both read from here.
abstract final class AppColors {
  // Background.
  static const Color bgDeep = Color(0xFF07070B);
  static const Color bgMid = Color(0xFF12101C);
  static const Color bgGlow = Color(0xFF2B2350);

  // Glass surfaces.
  static const Color glassFill = Color(0x14FFFFFF);
  static const Color glassFillLow = Color(0x08FFFFFF);
  static const Color glassBorder = Color(0x1FFFFFFF);
  static const Color glassStrong = Color(0x1AFFFFFF);
  static const Color well = Color(0xFF0D0C14);

  // Text.
  static const Color text = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0x8CFFFFFF);
  static const Color textOnAccent = Color(0xFF14121F);

  // Accents.
  static const Color accentMint = Color(0xFFB8F5D6);
  static const Color accentLavender = Color(0xFFC9B8FF);
  static const Color danger = Color(0xFFFF5A6E);

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentMint, accentLavender],
  );

  /// Block colors: soft neon tones that glow on the dark background
  /// but stay clearly different from each other.
  static const List<Color> blocks = [
    Color(0xFFFF6FB5), // pink
    Color(0xFFFFD86B), // yellow
    Color(0xFF6FA8FF), // blue
    Color(0xFF6FE3B4), // green
    Color(0xFFFF9F6B), // orange
    Color(0xFFB49BFF), // purple
  ];
}

abstract final class AppRadii {
  static const double card = 28;
  static const double tube = 16;
  static const double block = 8;
  static const double pill = 999;
}

abstract final class AppText {
  static const TextStyle title = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const TextStyle display = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.text,
  );
  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: AppColors.textMuted,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textMuted,
  );
  static const TextStyle button = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textOnAccent,
  );
}

/// Dark background with a soft glow from the bottom.
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, 1.2),
          radius: 1.3,
          colors: [AppColors.bgGlow, AppColors.bgMid, AppColors.bgDeep],
          stops: [0, 0.55, 1],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// Frosted glass card, same look as the board card in the game.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding ?? const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.glassBorder),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.glassFill, AppColors.glassFillLow],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Circular glass icon button.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.glassStrong,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.glassBorder),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: AppColors.text, size: 24),
          ),
        ),
      ),
    );
  }
}

/// Full-width pill button with the accent gradient.
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: onPressed,
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: Center(child: Text(label, style: AppText.button)),
          ),
        ),
      ),
    );
  }
}

/// Small glass pill label.
class GlassPill extends StatelessWidget {
  const GlassPill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.glassStrong,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
    );
  }
}

/// Full-width pill button in glass, for the second choice next to an
/// [AccentButton].
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.glassStrong,
      shape: const StadiumBorder(
        side: BorderSide(color: AppColors.glassBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: Center(
            child: Text(
              label,
              style: AppText.button.copyWith(color: AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}
