import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../game/game_feedback.dart';
import '../progress.dart';
import '../settings.dart';
import '../ui/app_theme.dart';
import '../ui/confirm_dialog.dart';
import '../ui/level_complete_screen.dart';
import 'arcade_catalog.dart';
import 'arcade_level_game.dart';

/// Plays the levels of one hub game: top bar (home, level, status,
/// restart), the game below it, pause when the app leaves the screen, a
/// confirm before throwing away progress, and the win and lose cards.
/// Stars and the next level are saved as soon as a level is won.
class ArcadeLevelScreen extends StatefulWidget {
  const ArcadeLevelScreen({
    super.key,
    required this.game,
    required this.progress,
    required this.settings,
    this.sounds = const SilentSounds(),
  });

  final ArcadeGame game;
  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  State<ArcadeLevelScreen> createState() => _ArcadeLevelScreenState();
}

class _ArcadeLevelScreenState extends State<ArcadeLevelScreen>
    with WidgetsBindingObserver {
  late int _level = widget.progress.gameLevel(widget.game.id);
  late ArcadeLevelGame _game;
  ArcadeResult? _result;
  bool _paused = false;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = _build();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _game.result.removeListener(_onResult);
    _game.disposeNotifiers();
    super.dispose();
  }

  ArcadeLevelGame _build() {
    final game = widget.game.create(
      ArcadeSetup(
        level: _level,
        style: widget.settings.blockStyle(widget.progress.totalStars),
        sounds: widget.sounds,
        haptics: widget.settings.haptics,
      ),
    );
    game.result.addListener(_onResult);
    return game;
  }

  /// Replaces the game with a fresh one for [_level].
  void _restartLevel() {
    final old = _game;
    old.result.removeListener(_onResult);
    setState(() {
      _result = null;
      _paused = false;
      _game = _build();
    });
    // The old game widget is gone after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.disposeNotifiers());
  }

  Future<void> _onResult() async {
    final result = _game.result.value;
    if (result == null || !mounted) return;
    if (result.won) {
      widget.sounds.win();
      await widget.progress.recordGameStars(
        widget.game.id,
        _level,
        result.stars,
      );
      await widget.progress.setGameLevel(widget.game.id, _level + 1);
    } else {
      widget.sounds.fail();
    }
    if (mounted) setState(() => _result = result);
  }

  void _next() {
    _level++;
    _restartLevel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || _result != null) return;
    if (!_paused) _pause();
  }

  void _pause() {
    _game.pauseEngine();
    setState(() => _paused = true);
  }

  void _resume() {
    _game.resumeEngine();
    setState(() => _paused = false);
  }

  bool get _needsConfirm => _result == null && _game.hasProgress;

  Future<bool> _confirm(String title, String message, String label) async {
    if (_dialogOpen) return false;
    _dialogOpen = true;
    final wasPaused = _paused;
    if (!wasPaused) _game.pauseEngine();
    final ok = await showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: label,
      cancelLabel: 'Stay',
    );
    _dialogOpen = false;
    if (!ok && !wasPaused && mounted) _game.resumeEngine();
    return ok;
  }

  Future<void> _requestLeave() async {
    if (_needsConfirm &&
        !await _confirm(
          'Leave this level?',
          'Your progress in this level will be lost.',
          'Leave',
        )) {
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _requestRestart() async {
    if (_needsConfirm &&
        !await _confirm(
          'Restart this level?',
          'Your progress in this level will be lost.',
          'Restart',
        )) {
      return;
    }
    if (mounted) _restartLevel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestLeave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Stack(
          children: [
            const GlowBackground(),
            SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: GameWidget<ArcadeLevelGame>(
                      key: ObjectKey(_game),
                      game: _game,
                    ),
                  ),
                ],
              ),
            ),
            if (_paused && _result == null) _pausedCard(),
            if (_result != null) _resultCard(_result!),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        RoundIconButton(
          icon: Icons.home_rounded,
          tooltip: 'Home',
          onPressed: _requestLeave,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '${widget.game.title} · Level $_level',
                  style: AppText.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: _game.status,
                builder: (context, text, _) => text.isEmpty
                    ? const SizedBox.shrink()
                    : Text(
                        text,
                        style: AppText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        RoundIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Restart level',
          onPressed: _requestRestart,
        ),
      ],
    ),
  );

  Widget _resultCard(ArcadeResult result) => result.won
      ? LevelCompleteScreen(
          pill: 'Level $_level',
          title: 'Level complete',
          message: switch (result.stars) {
            3 => 'Perfect run.',
            2 => 'Nice. Play it again later for 3 stars.',
            _ => 'Done. There is room for more stars.',
          },
          stars: result.stars,
          buttonLabel: 'Next level',
          onPressed: _next,
          secondaryLabel: 'Home',
          onSecondary: () => Navigator.of(context).pop(),
        )
      : LevelCompleteScreen(
          pill: 'Level $_level',
          title: 'Level failed',
          message: result.reason,
          buttonLabel: 'Retry',
          onPressed: _restartLevel,
          secondaryLabel: 'Home',
          onSecondary: () => Navigator.of(context).pop(),
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
}
