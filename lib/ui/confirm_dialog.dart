import 'package:flutter/material.dart';

import '../game/color_flow_game.dart';
import '../game/game_mode.dart';
import 'app_theme.dart';

/// Whether leaving the game should ask first: not on a win or fail
/// card and not before the first move.
bool leaveNeedsConfirm({
  required GameStatus status,
  required bool hasProgress,
}) => status != GameStatus.won && status != GameStatus.failed && hasProgress;

/// Body of the leave dialog: level modes keep their saved state.
String leaveMessage(GameMode mode) =>
    mode == GameMode.rush || mode == GameMode.endless
    ? 'This run will end.'
    : 'Your progress on this level is kept.';

/// Title of the restart dialog for the HUD's round button.
String restartTitle(GameMode mode) => switch (mode) {
  GameMode.endless => 'Skip this board?',
  GameMode.rush => 'Start a new run?',
  _ => 'Restart this level?',
};

/// Body of the restart dialog.
String restartMessage(GameMode mode) => switch (mode) {
  GameMode.endless => 'You get a new board. Your score is kept.',
  GameMode.rush => 'This run ends and a new one starts.',
  _ => 'This level starts over from the beginning.',
};

/// Glass dialog with a title, a message and two buttons. The accent
/// button confirms.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: AppText.title,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: AppText.body,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  AccentButton(label: confirmLabel, onPressed: onConfirm),
                  const SizedBox(height: 10),
                  GlassButton(label: cancelLabel, onPressed: onCancel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a [ConfirmDialog]. Returns true when the player confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.bgDeep.withValues(alpha: 0.6),
    builder: (context) => ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
    ),
  );
  return result ?? false;
}
