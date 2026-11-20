import 'package:flutter/material.dart';

import '../arcade/arcade_catalog.dart';
import '../arcade/arcade_level_screen.dart';
import '../game/game_feedback.dart';
import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'glass_page.dart';
import 'hub_screen.dart';

/// Mode list of Moo Munch: Levels and Endless.
class MooMunchScreen extends StatefulWidget {
  const MooMunchScreen({
    super.key,
    required this.progress,
    required this.settings,
    this.sounds = const SilentSounds(),
  });

  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  State<MooMunchScreen> createState() => _MooMunchScreenState();
}

class _MooMunchScreenState extends State<MooMunchScreen> {
  static const ArcadeGame _game = ArcadeGame.mooMunch;

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
    return GlassPage(
      title: _game.title,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, 20),
          child: Text(
            'Swipe or use the arrows to steer. Every carrot makes the '
            'tail longer.',
            style: AppText.body,
          ),
        ),
        HubCard(
          icon: Icons.flag_outlined,
          title: 'Levels',
          description: 'Eat every carrot of the level. You have 3 lives.',
          status: stars == 0 ? level : '$level · $stars ★',
          onTap: () => _open(endless: false),
        ),
        const SizedBox(height: 12),
        HubCard(
          icon: Icons.all_inclusive_rounded,
          title: 'Endless',
          description:
              'One life, faster with every carrot. '
              '${Progress.endlessPointsPerStar} carrots give 1 star.',
          status: 'Best ${p.gameBest(_game.id)}',
          onTap: () => _open(endless: true),
        ),
      ],
    );
  }
}
