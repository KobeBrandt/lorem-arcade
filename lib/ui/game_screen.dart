import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../game/color_flow_game.dart';
import '../game/game_feedback.dart';
import '../game/game_mode.dart';
import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'hud.dart';
import 'level_complete_screen.dart';
import 'result_banner.dart';
import 'tutorial_card.dart';

/// Text for the share sheet after a daily win.
String dailyShareText(DateTime day, int taps, int streak) =>
    'Color Flow · ${weekdayNames[day.weekday - 1]} · '
    '${taps == 1 ? '1 tap' : '$taps taps'} · streak $streak';

/// Plays one mode. Home goes back to the mode list.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.mode,
    required this.progress,
    required this.settings,
    required this.sounds,
  });

  final GameMode mode;
  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// The day this screen opened, so a daily puzzle that runs past
  /// midnight still counts for the day it belongs to.
  final DateTime _today = DateTime.now();

  late final ColorFlowGame _game = _createGame();
  double? _inset;

  /// The last win, shown on the win card.
  LevelResult? _lastResult;

  late bool _showTutorial = !widget.progress.tutorialSeen(widget.mode);

  ColorFlowGame _createGame() {
    final mode = widget.mode;
    final progress = widget.progress;
    final settings = widget.settings;
    final style = settings.blockStyle(progress.totalStars);
    final haptics = settings.haptics;
    final sounds = widget.sounds;
    return switch (mode) {
      GameMode.daily => ColorFlowGame(
        mode: mode,
        initialLevel: dailyLevelFor(_today),
        seed: dayKey(_today),
        style: style,
        sounds: sounds,
        haptics: haptics,
        onWon: _onDailyWon,
      ),
      GameMode.endless => ColorFlowGame(
        mode: mode,
        style: style,
        sounds: sounds,
        haptics: haptics,
        onScore: (score) {
          // Every call is one new point.
          progress.reportEndlessScore(score);
          progress.addEndlessPoints(1);
        },
      ),
      GameMode.rush => ColorFlowGame(
        mode: mode,
        style: style,
        sounds: sounds,
        haptics: haptics,
        // Saved on every point, so the best score survives a quit.
        onScore: progress.reportRushScore,
      ),
      _ => ColorFlowGame(
        mode: mode,
        initialLevel: progress.level(mode),
        style: style,
        sounds: sounds,
        haptics: haptics,
        onLevelReached: (level) => progress.setLevel(mode, level),
        onWon: _onLevelWon,
      ),
    };
  }

  void _onLevelWon(LevelResult result) {
    _lastResult = result;
    final progress = widget.progress;
    progress.recordStars(widget.mode, _game.level, result.stars);
    progress.recordTime(widget.mode, result.seconds);
  }

  void _onDailyWon(LevelResult result) {
    _lastResult = result;
    final progress = widget.progress;
    progress.markDailySolved(_today);
    progress.recordDailyStars(_today, result.stars);
    progress.recordTime(GameMode.daily, result.seconds);
  }

  void _home() => Navigator.of(context).pop();

  void _closeTutorial() {
    widget.progress.markTutorialSeen(widget.mode);
    setState(() => _showTutorial = false);
    // The clock (or the rush spawner) ran while the card was open:
    // start fresh.
    if (widget.mode == GameMode.timed || widget.mode == GameMode.rush) {
      _game.retryLevel();
    }
  }

  Future<void> _shareDaily() async {
    final taps = _lastResult?.taps ?? 0;
    final streak = widget.progress.dailyStreak(_today);
    await SharePlus.instance.share(
      ShareParams(text: dailyShareText(_today, taps, streak)),
    );
  }

  Widget _won(BuildContext context, ColorFlowGame game) {
    switch (game.mode) {
      case GameMode.daily:
        final streak = widget.progress.dailyStreak(_today);
        return LevelCompleteScreen(
          pill: streak == 1 ? 'Streak 1 day' : 'Streak $streak days',
          title: 'Daily solved',
          message: 'Come back tomorrow for a new puzzle.',
          stars: _lastResult?.stars,
          buttonLabel: 'Home',
          onPressed: _home,
          secondaryLabel: 'Share',
          onSecondary: _shareDaily,
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
          stars: _lastResult?.stars,
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
    message: game.mode == GameMode.rush
        ? 'Score ${game.hud.value.score ?? 0}. Start a new run.'
        : 'Try the same level again.',
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
      body: Stack(
        children: [
          GameWidget<ColorFlowGame>(
            game: _game,
            backgroundBuilder: (context) => const GlowBackground(),
            initialActiveOverlays: const ['hud'],
            overlayBuilderMap: {
              'hud': (context, game) =>
                  Hud(game: game, onHome: _home, day: _today),
              'stuck': _stuck,
              'failed': _failed,
              'won': _won,
            },
          ),
          if (_showTutorial)
            Positioned.fill(
              child: TutorialCard(mode: widget.mode, onDone: _closeTutorial),
            ),
        ],
      ),
    );
  }
}
