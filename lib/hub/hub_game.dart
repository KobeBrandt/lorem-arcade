import 'package:flutter/material.dart';

import '../arcade/arcade_catalog.dart';

/// One card on the hub. The enum order is the default hub order.
enum HubGame {
  colorFlow,
  beadBelt,
  cogClash,
  gateDrop,

  /// Secret game: it joins the hub the first time every other game is
  /// hidden, and stays from then on.
  mooMunch;

  /// The level game behind this card, or null for Color Flow.
  ArcadeGame? get arcade => switch (this) {
    HubGame.colorFlow => null,
    HubGame.beadBelt => ArcadeGame.beadBelt,
    HubGame.cogClash => ArcadeGame.cogClash,
    HubGame.gateDrop => ArcadeGame.gateDrop,
    HubGame.mooMunch => ArcadeGame.mooMunch,
  };

  String get title => arcade?.title ?? 'Color Flow';

  IconData get icon => arcade?.icon ?? Icons.view_column_rounded;

  /// Key for saved hub data and the last-played time.
  String get id => name;

  static HubGame? byId(String id) {
    for (final game in values) {
      if (game.id == id) return game;
    }
    return null;
  }
}

/// How the hub shows its games.
enum HubView {
  list('List', Icons.view_agenda_outlined),
  grid('Grid', Icons.grid_view_rounded),
  compact('Compact list', Icons.view_list_rounded);

  const HubView(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// In which order the hub shows its games.
enum HubSort {
  /// The player's own order.
  custom('Custom order'),

  /// Last played first; never played games follow in the custom order.
  recent('Recently played');

  const HubSort(this.title);

  final String title;
}
