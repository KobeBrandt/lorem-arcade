import 'package:flutter/material.dart';

import '../arcade/arcade_catalog.dart';
import '../arcade/arcade_level_screen.dart';
import '../game/game_feedback.dart';
import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'glass_page.dart';
import 'hub_screen.dart';

/// Mode list of a hub game with an endless run: Levels and Endless.
class ArcadeModeScreen extends StatefulWidget {
  const ArcadeModeScreen({
    super.key,
    required this.game,
    required this.progress,
    required this.settings,
    this.sounds = const SilentSounds(),
  });

  /// A game with [ArcadeGame.hasEndless].
  final ArcadeGame game;
  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  State<ArcadeModeScreen> createState() => _ArcadeModeScreenState();
}

/// Texts of the mode list of one game.
typedef _ModeTexts = ({String intro, String levels, String endless});

class _ArcadeModeScreenState extends State<ArcadeModeScreen> {
  ArcadeGame get _game => widget.game;

  _ModeTexts get _texts => switch (_game) {
    ArcadeGame.cogClash => (
      intro:
          'Link gears to your weapons while the waves walk in. Defeated '
          'enemies pay coins for more gears.',
      levels: 'Beat every wave of the level. Your fighter does not heal.',
      endless:
          'Waves never stop and keep getting stronger. '
          '${Progress.endlessPointsPerStar} waves give 1 star.',
    ),
    ArcadeGame.gateDrop => (
      intro:
          'Pour balls through multiplier gates to stop the horde. Fill the '
          'fever meter for double damage.',
      levels:
          'Stop the horde before it reaches the wall. Every 5th level is a '
          'boss, every 7th a bonus.',
      endless:
          'Wave after wave on new shafts, each horde tougher. '
          '${Progress.endlessPointsPerStar} waves give 1 star.',
    ),
    _ => (
      intro:
          'Swipe or use the arrows to steer. Every carrot makes the '
          'tail longer.',
      levels: 'Eat every carrot of the level. You have 3 lives.',
      endless:
          'One life, faster with every carrot. '
          '${Progress.endlessPointsPerStar} carrots give 1 star.',
    ),
  };

  Future<void> _open({required bool endless}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArcadeLevelScreen(
          game: _game,
          progress: widget.progress,
          settings: widget.settings,
          sounds: widget.sounds,
          endless: endless,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final stars = p.gameStars(_game.id);
    final level = 'Level ${p.gameLevel(_game.id)}';
    final texts = _texts;
    return GlassPage(
      title: _game.title,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
          child: Text(texts.intro, style: AppText.body),
        ),
        HubCard(
          icon: Icons.flag_outlined,
          title: 'Levels',
          description: texts.levels,
          status: stars == 0 ? level : '$level · $stars ★',
          onTap: () => _open(endless: false),
        ),
        const SizedBox(height: 12),
        HubCard(
          icon: Icons.all_inclusive_rounded,
          title: 'Endless',
          description: texts.endless,
          status: 'Best ${p.gameBest(_game.id)}',
          onTap: () => _open(endless: true),
        ),
      ],
    );
  }
}
