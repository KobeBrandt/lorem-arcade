import 'package:flutter/material.dart';

import '../arcade/arcade_level_screen.dart';
import '../game/game_feedback.dart';
import '../game/game_mode.dart';
import '../hub/hub_game.dart';
import '../progress.dart';
import '../settings.dart';
import 'app_theme.dart';
import 'game_screen.dart';
import 'glass_page.dart';
import 'home_screen.dart';
import 'moo_munch_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'themes_screen.dart';

/// First screen: one card per game. Color Flow and Moo Munch open their
/// mode lists; the other games open their next level. Stars from every
/// game add up and unlock themes for all of them.
///
/// The player picks a view (list, grid, compact list) and a sort (custom
/// order, recently played), moves games and hides them. Hiding every
/// game unlocks Moo Munch.
class HubScreen extends StatefulWidget {
  const HubScreen({
    super.key,
    required this.progress,
    required this.settings,
    this.sounds = const SilentSounds(),
  });

  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  Progress get _progress => widget.progress;
  Settings get _settings => widget.settings;

  Future<T?> _push<T>(WidgetBuilder builder) async {
    final result = await Navigator.of(context)
        .push(MaterialPageRoute<T>(builder: builder));
    // Progress or settings may have changed on the other screen.
    if (mounted) setState(() {});
    return result;
  }

  Future<void> _open(HubGame game) async {
    await _progress.markPlayed(game.id, DateTime.now());
    if (!mounted) return;
    final arcade = game.arcade;
    if (arcade == null) {
      await _push(
        (_) => HomeScreen(
          progress: _progress,
          settings: _settings,
          sounds: widget.sounds,
        ),
      );
    } else if (arcade.hasEndless) {
      await _push(
        (_) => MooMunchScreen(
          progress: _progress,
          settings: _settings,
          sounds: widget.sounds,
        ),
      );
    } else {
      await _push(
        (_) => ArcadeLevelScreen(
          game: arcade,
          progress: _progress,
          settings: _settings,
          sounds: widget.sounds,
        ),
      );
    }
  }

  Future<void> _openStats() async {
    final mode = await _push<GameMode>((_) => StatsScreen(progress: _progress));
    // The empty stats page asks to play a Color Flow mode.
    if (mode != null && mounted) {
      await _push(
        (_) => GameScreen(
          mode: mode,
          progress: _progress,
          settings: _settings,
          sounds: widget.sounds,
        ),
      );
    }
  }

  Future<void> _openSettings() =>
      _push((_) => SettingsScreen(settings: _settings));

  /// Games in the player's own order: not hidden, and Moo Munch only
  /// once it is unlocked.
  List<HubGame> get _customShown => [
    for (final game in _settings.gameOrder)
      if (!_settings.isHidden(game) &&
          (game != HubGame.mooMunch || _progress.mooMunchUnlocked))
        game,
  ];

  /// Games as the hub shows them, in the selected sort.
  List<HubGame> get _shown {
    final custom = _customShown;
    if (_settings.hubSort == HubSort.custom) return custom;
    final games = [...custom];
    games.sort((a, b) {
      final pa = _progress.lastPlayed(a.id);
      final pb = _progress.lastPlayed(b.id);
      if (pa == null && pb == null) {
        return custom.indexOf(a) - custom.indexOf(b);
      }
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pb.compareTo(pa);
    });
    return games;
  }

  Future<void> _hide(HubGame game) async {
    await _settings.setHidden(game, true);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_customShown.isEmpty && !_progress.mooMunchUnlocked) {
      // Every game is hidden: the cow wanders in, and stays.
      await _progress.unlockMooMunch();
      if (!mounted) return;
      setState(() {});
      messenger.showSnackBar(
        const SnackBar(
          content: Text('A hungry cow wandered in. Say hi to Moo Munch!'),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text('${game.title} is hidden. Show it again in Settings.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _settings.setHidden(game, false),
        ),
      ),
    );
  }

  String _status(HubGame game) {
    final p = _progress;
    final arcade = game.arcade;
    if (arcade == null) return 'Level ${p.level(GameMode.levels)}';
    final stars = p.gameStars(arcade.id);
    final level = 'Level ${p.gameLevel(arcade.id)}';
    return stars == 0 ? level : '$level · $stars ★';
  }

  String _description(HubGame game) =>
      game.arcade?.description ??
      'Sort colored blocks through a looping belt. '
          '${GameMode.values.length} modes.';

  Future<void> _showGameMenu(HubGame game) async {
    final custom = _settings.hubSort == HubSort.custom;
    final shown = _customShown;
    final index = shown.indexOf(game);
    const onlyCustom = 'Only in Custom order';
    final action = await showModalBottomSheet<_GameAction>(
      context: context,
      backgroundColor: AppColors.bgMid,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Semantics(
                header: true,
                child: Text(game.title, style: AppText.title),
              ),
            ),
            _SheetTile(
              icon: Icons.arrow_upward_rounded,
              title: 'Move up',
              subtitle: custom ? null : onlyCustom,
              enabled: custom && index > 0,
              onTap: () => Navigator.of(context).pop(_GameAction.up),
            ),
            _SheetTile(
              icon: Icons.arrow_downward_rounded,
              title: 'Move down',
              subtitle: custom ? null : onlyCustom,
              enabled: custom && index < shown.length - 1,
              onTap: () => Navigator.of(context).pop(_GameAction.down),
            ),
            _SheetTile(
              icon: Icons.visibility_off_outlined,
              title: 'Hide game',
              subtitle: 'Show it again in Settings.',
              onTap: () => Navigator.of(context).pop(_GameAction.hide),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (action) {
      case _GameAction.up:
        await _settings.moveShown(shown, game, up: true);
      case _GameAction.down:
        await _settings.moveShown(shown, game, up: false);
      case _GameAction.hide:
        await _hide(game);
      case null:
        break;
    }
  }

  Future<void> _showViewMenu() async {
    final reorder = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bgMid,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: _settings,
        builder: (context, _) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHeader('View'),
                for (final view in HubView.values)
                  _SheetTile(
                    icon: view.icon,
                    title: view.title,
                    selected: _settings.hubView == view,
                    onTap: () => _settings.setHubView(view),
                  ),
                const _SheetHeader('Sort'),
                for (final sort in HubSort.values)
                  _SheetTile(
                    icon: sort == HubSort.custom
                        ? Icons.drag_indicator_rounded
                        : Icons.history_rounded,
                    title: sort.title,
                    selected: _settings.hubSort == sort,
                    onTap: () => _settings.setHubSort(sort),
                  ),
                const Divider(color: AppColors.glassBorder, height: 24),
                _SheetTile(
                  icon: Icons.swap_vert_rounded,
                  title: 'Reorder games',
                  subtitle: 'Drag games into your own order.',
                  onTap: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (reorder == true && mounted) await _showReorderSheet();
  }

  Future<void> _showReorderSheet() async {
    // The drag order is the custom order, so the hub switches to it.
    await _settings.setHubSort(HubSort.custom);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgMid,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          final games = _customShown;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
                    child: Semantics(
                      header: true,
                      child: const Text('Reorder games', style: AppText.title),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: Text(
                      'Drag the handle to move a game.',
                      style: AppText.caption,
                    ),
                  ),
                  Flexible(
                    child: ReorderableListView(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      onReorderItem: (from, to) {
                        final next = [...games];
                        next.insert(to, next.removeAt(from));
                        _settings.reorderShown(next);
                      },
                      children: [
                        for (final (i, game) in games.indexed)
                          ListTile(
                            key: ValueKey(game),
                            leading: Icon(game.icon, color: AppColors.text),
                            title: Text(
                              game.title,
                              style: AppText.body.copyWith(
                                color: AppColors.text,
                              ),
                            ),
                            trailing: ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(12),
                                child: Icon(
                                  Icons.drag_handle_rounded,
                                  color: AppColors.textMuted,
                                  semanticLabel: 'Drag to move',
                                ),
                              ),
                            ),
                            contentPadding: const EdgeInsets.only(
                              left: 24,
                              right: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    child: AccentButton(
                      label: 'Done',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _gameWidget(HubGame game, HubView view) {
    final status = _status(game);
    void onTap() => _open(game);
    void onLongPress() => _showGameMenu(game);
    return switch (view) {
      HubView.list => HubCard(
        icon: game.icon,
        title: game.title,
        description: _description(game),
        status: status,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
      HubView.compact => HubCompactRow(
        icon: game.icon,
        title: game.title,
        status: status,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
      HubView.grid => HubTile(
        icon: game.icon,
        title: game.title,
        status: status,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    };
  }

  List<Widget> _games(double width) {
    final games = _shown;
    if (games.isEmpty) {
      return [
        GlassCard(
          child: Column(
            children: [
              const Text(
                'All games are hidden.',
                style: AppText.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Show them again in Settings.',
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              AccentButton(label: 'Open Settings', onPressed: _openSettings),
            ],
          ),
        ),
      ];
    }
    final view = _settings.hubView;
    final gap = view == HubView.compact ? 8.0 : 12.0;
    if (view != HubView.grid) {
      return [
        for (final (i, game) in games.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          _gameWidget(game, view),
        ],
      ];
    }
    final columns = width >= 480 ? 3 : 2;
    return [
      for (var start = 0; start < games.length; start += columns) ...[
        if (start > 0) SizedBox(height: gap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: gap),
                Expanded(
                  child: start + c < games.length
                      ? _gameWidget(games[start + c], view)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => Scaffold(
        backgroundColor: AppColors.bgDeep,
        body: Stack(
          children: [
            const GlowBackground(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final padding = pagePadding(constraints.maxWidth);
                  return ListView(
                    padding: padding,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          RoundIconButton(
                            icon: Icons.tune_rounded,
                            tooltip: 'View and order',
                            onPressed: _showViewMenu,
                          ),
                          const SizedBox(width: 8),
                          RoundIconButton(
                            icon: Icons.bar_chart_rounded,
                            tooltip: 'Stats',
                            onPressed: _openStats,
                          ),
                          const SizedBox(width: 8),
                          RoundIconButton(
                            icon: Icons.palette_outlined,
                            tooltip: 'Themes',
                            onPressed: () => _push(
                              (_) => ThemesScreen(
                                progress: _progress,
                                settings: _settings,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          RoundIconButton(
                            icon: Icons.settings_outlined,
                            tooltip: 'Settings',
                            onPressed: _openSettings,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            const Flexible(
                              child: Text(
                                'Lorem Arcade',
                                style: AppText.display,
                              ),
                            ),
                            const SizedBox(width: 12),
                            StarCountPill(stars: _progress.totalStars),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(8, 4, 8, 24),
                        child: Text(
                          'Stars from every game unlock themes. '
                          'Long-press a game for more options.',
                          style: AppText.body,
                        ),
                      ),
                      ..._games(constraints.maxWidth - padding.horizontal),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _GameAction { up, down, hide }

class _SheetHeader extends StatelessWidget {
  const _SheetHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
    child: Semantics(header: true, child: Text(text, style: AppText.caption)),
  );
}

/// One choice in a hub bottom sheet. [selected] shows a check mark.
class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.enabled = true,
    this.selected,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool enabled;
  final bool? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.text : AppColors.textMuted;
    return Semantics(
      selected: selected,
      child: ListTile(
        enabled: enabled,
        leading: Icon(icon, color: color),
        title: Text(title, style: AppText.body.copyWith(color: color)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: AppText.caption),
        trailing: selected == true
            ? const Icon(Icons.check_rounded, color: AppColors.accentMint)
            : null,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    );
  }
}

/// Makes [child] one button for taps and long presses, with one
/// screen-reader label.
class _HubButton extends StatelessWidget {
  const _HubButton({
    required this.label,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : 'Options',
      excludeSemantics: true,
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.card),
                onTap: onTap,
                onLongPress: onLongPress,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One game on the hub: icon, title, description and status; the whole
/// card is one button. A long press calls [onLongPress] when given.
class HubCard extends StatelessWidget {
  const HubCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.status,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String description;
  final String status;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return _HubButton(
      label: '$title, $status',
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _IconBadge(icon: icon, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.title.copyWith(fontSize: 20)),
                  const SizedBox(height: 2),
                  Text(description, style: AppText.caption),
                  const SizedBox(height: 8),
                  GlassPill(text: status),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// One game as a slim row: small icon, title and status.
class HubCompactRow extends StatelessWidget {
  const HubCompactRow({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String status;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return _HubButton(
      label: '$title, $status',
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _IconBadge(icon: icon, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title, style: AppText.title.copyWith(fontSize: 18)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                status,
                style: AppText.caption,
                textAlign: TextAlign.end,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// One game as a grid tile: icon, title and status.
class HubTile extends StatelessWidget {
  const HubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    required this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String status;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return _HubButton(
      label: '$title, $status',
      onTap: onTap,
      onLongPress: onLongPress,
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _IconBadge(icon: icon, size: 56),
            const SizedBox(height: 12),
            Text(
              title,
              style: AppText.title.copyWith(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            GlassPill(text: status),
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.size});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: AppColors.accentGradient,
    ),
    child: Icon(icon, color: AppColors.textOnAccent, size: size / 2),
  );
}
