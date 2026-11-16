import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/color_flow_game.dart';
import '../game/game_mode.dart';
import '../progress.dart';
import 'app_theme.dart';
import 'hud.dart';
import 'level_complete_screen.dart';
import 'result_banner.dart';

/// Plays one mode. Home goes back to the mode list.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.mode, required this.progress});

  final GameMode mode;
  final Progress progress;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// The day this screen opened, so a daily puzzle that runs past
  /// midnight still counts for the day it belongs to.
  final DateTime _today = DateTime.now();

  late final ColorFlowGame _game = _createGame();
  double? _inset;

  ColorFlowGame _createGame() {
    final mode = widget.mode;
    final progress = widget.progress;
    return switch (mode) {
      GameMode.daily => ColorFlowGame(
        mode: mode,
        initialLevel: dailyLevelFor(_today),
        seed: dayKey(_today),
        onWon: () => progress.markDailySolved(_today),
      ),
      GameMode.endless => ColorFlowGame(
        mode: mode,
        onScore: progress.reportEndlessScore,
      ),
      _ => ColorFlowGame(
        mode: mode,
        initialLevel: progress.level(mode),
        onLevelReached: (level) => progress.setLevel(mode, level),
      ),
    };
  }

  void _home() => Navigator.of(context).pop();

  Widget _won(BuildContext context, ColorFlowGame game) {
    switch (game.mode) {
      case GameMode.daily:
        final streak = widget.progress.dailyStreak(_today);
        return LevelCompleteScreen(
          pill: streak == 1 ? 'Streak 1 day' : 'Streak $streak days',
          title: 'Daily solved',
          message: 'Come back tomorrow for a new puzzle.',
          buttonLabel: 'Home',
          onPressed: _home,
        );
      case GameMode.endless:
        return LevelCompleteScreen(
          pill: 'Score ${game.hud.value.score ?? 0}',
          title: 'Board cleared',
          message: 'The next board is a bit bigger.',
          buttonLabel: 'Continue',
          onPressed: game.nextLevel,
        );
      default:
        return LevelCompleteScreen(
          pill: 'Level ${game.level}',
          title: 'Level complete',
          message: 'Every tube is sorted.',
          buttonLabel: 'Continue',
          onPressed: game.nextLevel,
        );
    }
  }

  Widget _stuck(BuildContext context, ColorFlowGame game) {
    final endless = game.mode == GameMode.endless;
    return ResultBanner(
      title: 'Stuck',
      message: 'No tube fits the loop and no block can land.',
      actionLabel: endless ? 'Skip' : 'Retry',
      onAction: endless ? game.skipBoard : game.retryLevel,
      onHome: _home,
    );
  }

  Widget _failed(BuildContext context, ColorFlowGame game) => ResultBanner(
    title: game.failReason,
    message: 'Try the same level again.',
    actionLabel: 'Retry',
    onAction: game.retryLevel,
    onHome: _home,
  );

  @override
  Widget build(BuildContext context) {
    // Set the inset after this frame: it can relayout the game and
    // update the HUD, which must not happen during a build.
    final inset = MediaQuery.paddingOf(context).top;
    if (inset != _inset) {
      _inset = inset;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _game.topInset = inset,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: GameWidget<ColorFlowGame>(
        game: _game,
        backgroundBuilder: (context) => const GlowBackground(),
        initialActiveOverlays: const ['hud'],
        overlayBuilderMap: {
          'hud': (context, game) => Hud(game: game, onHome: _home, day: _today),
          'stuck': _stuck,
          'failed': _failed,
          'won': _won,
        },
      ),
    );
  }
}
