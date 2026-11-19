import 'package:flutter/material.dart';

import '../games/bead_belt/bead_belt_game.dart';
import '../games/cog_clash/cog_clash_game.dart';
import '../games/gate_drop/gate_drop_game.dart';
import 'arcade_level_game.dart';

/// The level games in the hub, next to Color Flow.
enum ArcadeGame {
  beadBelt(
    'Bead Belt',
    'Send buckets to scoop matching beads off the belt before it overflows.',
    Icons.shopping_basket_outlined,
    BeadBeltGame.new,
  ),
  cogClash(
    'Cog Clash',
    'Link gears to your weapon, then watch your fighter take on the wave.',
    Icons.settings_suggest_outlined,
    CogClashGame.new,
  ),
  gateDrop(
    'Gate Drop',
    'Pour balls through multiplier gates to stop the horde.',
    Icons.filter_alt_outlined,
    GateDropGame.new,
  );

  const ArcadeGame(this.title, this.description, this.icon, this.create);

  final String title;
  final String description;
  final IconData icon;

  /// Builds the game for one level.
  final ArcadeLevelGame Function(ArcadeSetup setup) create;

  /// Key for saved progress: `level_{id}` and `stars_{id}_{level}`.
  String get id => name;
}
