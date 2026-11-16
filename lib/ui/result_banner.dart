import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Bottom card for a level that cannot go on: stuck, out of moves or
/// out of time. One main action plus Home.
class ResultBanner extends StatelessWidget {
  const ResultBanner({
    super.key,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onHome,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppText.title),
                const SizedBox(height: 4),
                Text(message, style: AppText.body, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                AccentButton(label: actionLabel, onPressed: onAction),
                const SizedBox(height: 10),
                GlassButton(label: 'Home', onPressed: onHome),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
