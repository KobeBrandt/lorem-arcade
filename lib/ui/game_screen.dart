import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../game/color_flow_game.dart';
import '../game/game_feedback.dart';
import '../game/game_mode.dart';
import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'confirm_dialog.dart';
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

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  /// The day this screen opened, so a daily puzzle that runs past
  /// midnight still counts for the day it belongs to.
  final DateTime _today = DateTime.now();

  late final ColorFlowGame _game = _createGame();
  double? _inset;
  double? _bottomInset;
  double? _textScale;

  /// The last win, shown on the win card.
  LevelResult? _lastResult;

  late bool _showTutorial = !widget.progress.tutorialSeen(widget.mode);

  /// The Paused card shows after the app comes back from the background.
  bool _showPaused = false;

  /// The app went to the background (or lost focus) during this screen.
  bool _pausedByLifecycle = false;

  /// A leave or restart dialog is open.
  bool _dialogOpen = false;

  bool _left = false;
  GameStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game.hud.addListener(_onHudChanged);
    // Nothing runs under the tutorial card. The game keeps this through
    // loading, so a level that is built while the card shows stays paused.
    if (_showTutorial) _game.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.hud.removeListener(_onHudChanged);
    _saveState();
    // GameWidget has already removed the game; free what it holds last.
    _game.disposeResources();
    super.dispose();
  }

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
        // Only a game saved for today's puzzle.
        restoreState: progress.savedState(mode, _today),
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
        restoreState: progress.savedState(mode, _today),
        style: style,
        sounds: sounds,
        haptics: haptics,
        onLevelReached: (level) => progress.setLevel(mode, level),
        onWon: _onLevelWon,
      ),
    };
  }

  /// A won or failed level has nothing left to resume. Also rebuilds the
  /// tube semantics layer, which only shows while playing.
  void _onHudChanged() {
    final status = _game.hud.value.status;
    if (status == _lastStatus) return;
    _lastStatus = status;
    if (status == GameStatus.won || status == GameStatus.failed) {
      widget.progress.clearGameState(widget.mode);
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_pausedByLifecycle) return;
        _pausedByLifecycle = true;
        _game.pause();
        _saveState();
      case AppLifecycleState.resumed:
        if (!_pausedByLifecycle) return;
        _pausedByLifecycle = false;
        // The tutorial card keeps the game paused until it closes.
        if (_showTutorial) return;
        final status = _game.status;
        if (status == GameStatus.playing || status == GameStatus.stuck) {
          // Wait for the player before the clock runs again.
          if (mounted) setState(() => _showPaused = true);
        } else if (!_dialogOpen) {
          _game.resume();
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Saves the unfinished level so it can go on later. A won or failed
  /// level removes the saved game; nothing changes while a level builds.
  void _saveState() {
    final mode = widget.mode;
    if (!Progress.keepsState(mode)) return;
    final status = _game.status;
    if (status == GameStatus.loading) return;
    if (status == GameStatus.won || status == GameStatus.failed) {
      widget.progress.clearGameState(mode);
      return;
    }
    widget.progress.saveGameState(mode, _game.saveState(), _today);
  }

  void _resume() {
    setState(() => _showPaused = false);
    if (!_dialogOpen) _game.resume();
  }

  void _onLevelWon(LevelResult result) {
    _lastResult = result;
    final progress = widget.progress;
    // Save the next level now, so leaving on the win card moves on.
    progress.saveLevelWon(widget.mode, _game.level);
    progress.clearGameState(widget.mode);
    progress.recordStars(widget.mode, _game.level, result.stars);
    progress.recordTime(widget.mode, result.seconds);
  }

  void _onDailyWon(LevelResult result) {
    _lastResult = result;
    final progress = widget.progress;
    progress.clearGameState(GameMode.daily);
    progress.markDailySolved(_today);
    progress.recordDailyStars(_today, result.stars);
    progress.recordTime(GameMode.daily, result.seconds);
  }

  /// Leaves at once (from a result card or after confirming).
  void _home() {
    if (_left) return;
    _left = true;
    _saveState();
    Navigator.of(context).pop();
  }

  /// Back button and the HUD's Home button: closes the tutorial card,
  /// else leaves, asking first when there is progress to lose.
  Future<void> _requestLeave() async {
    if (_showTutorial) {
      _closeTutorial();
      return;
    }
    if (_dialogOpen) return;
    final ask = leaveNeedsConfirm(
      status: _game.status,
      hasProgress: _game.hasProgress,
    );
    if (!ask) {
      _home();
      return;
    }
    final leave = await _confirm(
      title: 'Leave this run?',
      message: leaveMessage(widget.mode),
      confirmLabel: 'Leave',
      cancelLabel: 'Stay',
    );
    if (leave && mounted) _home();
  }

  /// The HUD's round button: asks first when there is progress to lose.
  Future<void> _requestRestart() async {
    if (_dialogOpen) return;
    if (_game.hasProgress) {
      final mode = widget.mode;
      final restart = await _confirm(
        title: restartTitle(mode),
        message: restartMessage(mode),
        confirmLabel: 'Restart',
      );
      if (!restart || !mounted) return;
    }
    _game.restartPressed();
  }

  /// Shows a confirm dialog with the game paused behind it.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
  }) async {
    _dialogOpen = true;
    final wasPaused = _game.isPaused;
    _game.pause();
    try {
      return await showConfirmDialog(
        context,
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      );
    } finally {
      _dialogOpen = false;
      // Stay paused behind the Paused card.
      if (!wasPaused && !_showPaused && !_showTutorial && mounted) {
        _game.resume();
      }
    }
  }

  void _closeTutorial() {
    widget.progress.markTutorialSeen(widget.mode);
    setState(() => _showTutorial = false);
    // The game was paused under the card; a saved game goes on as it was.
    if (!_showPaused && !_dialogOpen) _game.resume();
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

  Widget _loading(BuildContext context, ColorFlowGame game) {
    final text = game.mode == GameMode.rush || game.mode == GameMode.endless
        ? 'Building board'
        : 'Building level ${game.hud.value.level}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Semantics(
          liveRegion: true,
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.accentMint),
                const SizedBox(height: 16),
                Text(text, style: AppText.body, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
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

  /// One screen reader button per tube over the board. It holds no
  /// hit-testable widgets, so real taps go through to the game.
  Widget _tubeSemantics() => ValueListenableBuilder<int>(
    valueListenable: _game.layoutVersion,
    builder: (context, _, _) => Stack(
      children: [
        for (var i = 0; i < _game.tubeCount; i++)
          Positioned.fromRect(
            rect: _game.tubeTapRect(i),
            child: Semantics(
              button: true,
              label: _game.tubeLabel(i),
              onTap: () => _game.tapTube(i),
              excludeSemantics: true,
              child: const SizedBox.expand(),
            ),
          ),
      ],
    ),
  );

  Widget _pausedCard() => ColoredBox(
    color: AppColors.bgDeep.withValues(alpha: 0.6),
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: GlassCard(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    child: const Text(
                      'Paused',
                      style: AppText.display,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  AccentButton(label: 'Resume', onPressed: _resume),
                  const SizedBox(height: 10),
                  GlassButton(label: 'Home', onPressed: _requestLeave),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// Passes the insets and the text scale to the game after this frame:
  /// they can relayout the game and update the HUD, which must not
  /// happen during a build.
  void _syncMetrics(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (padding.top == _inset &&
        padding.bottom == _bottomInset &&
        scale == _textScale) {
      return;
    }
    _inset = padding.top;
    _bottomInset = padding.bottom;
    _textScale = scale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _game.topInset = padding.top;
      _game.bottomInset = padding.bottom;
      _game.textScale = scale;
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncMetrics(context);
    final showTubes =
        !_showTutorial && !_showPaused && _game.status == GameStatus.playing;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Stack(
          children: [
            GameWidget<ColorFlowGame>(
              game: _game,
              backgroundBuilder: (context) => const GlowBackground(),
              initialActiveOverlays: const ['hud'],
              overlayBuilderMap: {
                'hud': (context, game) => Hud(
                  game: game,
                  onHome: _requestLeave,
                  onRestart: _requestRestart,
                  day: _today,
                  onHeight: (height) => game.hudHeight = height,
                ),
                'loading': _loading,
                'stuck': _stuck,
                'failed': _failed,
                'won': _won,
              },
            ),
            if (showTubes) Positioned.fill(child: _tubeSemantics()),
            if (_showPaused) Positioned.fill(child: _pausedCard()),
            if (_showTutorial)
              Positioned.fill(
                child: TutorialCard(mode: widget.mode, onDone: _closeTutorial),
              ),
          ],
        ),
      ),
    );
  }
}
