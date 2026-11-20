import 'package:flutter/material.dart';

import '../games/bead_belt/bead_belt_game.dart';
import '../games/cog_clash/cog_clash_game.dart';
import '../games/gate_drop/gate_drop_game.dart';
import '../games/moo_munch/moo_munch_game.dart';
import 'arcade_level_game.dart';

/// The level games in the hub, next to Color Flow.
///
/// [mooMunch] only shows once it is unlocked, see
/// [Progress.mooMunchUnlocked].
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
  ),

  /// Secret game, see [HubGame.mooMunch]. Its levels play here; its
  /// endless run has its own screen.
  mooMunch(
    'Moo Munch',
    'Steer a hungry cow to the carrots. Do not bump into your own tail.',
    Icons.grass_rounded,
    MooMunchGame.levels,
    MooMunchGame.endless,
  );

  const ArcadeGame(
    this.title,
    this.description,
    this.icon,
    this.create, [
    this.createEndless,
  ]);

  final String title;
  final String description;
  final IconData icon;

  /// Builds the game for one level.
  final ArcadeLevelGame Function(ArcadeSetup setup) create;

  /// Builds an endless run, or null when the game has none. An endless
  /// run ends with [ArcadeResult.ended].
  final ArcadeLevelGame Function(ArcadeSetup setup)? createEndless;

  bool get hasEndless => createEndless != null;

  /// Key for saved progress: `level_{id}` and `stars_{id}_{level}`.
  String get id => name;
}
