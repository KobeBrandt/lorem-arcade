import 'package:lorem_arcade/game/color_flow_game.dart';
import 'package:lorem_arcade/game/game_mode.dart';
import 'package:lorem_arcade/main.dart';
import 'package:lorem_arcade/progress.dart';
import 'package:lorem_arcade/settings.dart';
import 'package:lorem_arcade/ui/confirm_dialog.dart';
import 'package:lorem_arcade/ui/home_screen.dart';
import 'package:lorem_arcade/ui/settings_screen.dart';
import 'package:lorem_arcade/ui/stats_screen.dart';
import 'package:lorem_arcade/ui/themes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  testWidgets('settings screen toggles sound', (tester) async {
    final settings = Settings(await _prefs());
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );
    expect(settings.sound, isTrue);
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(settings.sound, isFalse);
  });

  testWidgets('settings screen opens the privacy policy', (tester) async {
    final settings = Settings(await _prefs());
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: settings,
          openUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(opened, [privacyPolicyUrl]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('settings screen shows the privacy URL when no browser opens', (
    tester,
  ) async {
    final settings = Settings(await _prefs());
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          settings: settings,
          openUrl: (_) async => throw Exception('no browser'),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('$privacyPolicyUrl'), findsOneWidget);
  });

  testWidgets('themes screen selects unlocked and ignores locked', (
    tester,
  ) async {
    // 30 stars: 10 levels with 3 stars each.
    final prefs = await _prefs({
      for (var i = 1; i <= 10; i++) 'stars_levels_$i': 3,
    });
    final settings = Settings(prefs);
    await tester.pumpWidget(
      MaterialApp(
        home: ThemesScreen(progress: Progress(prefs), settings: settings),
      ),
    );
    await tester.tap(find.text('Pastel'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(settings.theme, BlockTheme.standard);
    await tester.tap(find.text('Neon'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(settings.theme, BlockTheme.neon);
    // Locked themes show their cost.
    expect(find.text('75'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
  });

  group('Leave dialog', () {
    test('asks only with progress and no result card', () {
      expect(
        leaveNeedsConfirm(status: GameStatus.playing, hasProgress: true),
        isTrue,
      );
      expect(
        leaveNeedsConfirm(status: GameStatus.stuck, hasProgress: true),
        isTrue,
      );
      expect(
        leaveNeedsConfirm(status: GameStatus.playing, hasProgress: false),
        isFalse,
      );
      expect(
        leaveNeedsConfirm(status: GameStatus.won, hasProgress: true),
        isFalse,
      );
      expect(
        leaveNeedsConfirm(status: GameStatus.failed, hasProgress: true),
        isFalse,
      );
    });

    test('level modes keep progress, runs end', () {
      expect(
        leaveMessage(GameMode.levels),
        'Your progress on this level is kept.',
      );
      expect(
        leaveMessage(GameMode.daily),
        'Your progress on this level is kept.',
      );
      expect(leaveMessage(GameMode.rush), 'This run will end.');
      expect(leaveMessage(GameMode.endless), 'This run will end.');
      expect(restartTitle(GameMode.levels), 'Restart this level?');
      expect(restartTitle(GameMode.endless), 'Skip this board?');
      expect(restartTitle(GameMode.rush), 'Start a new run?');
    });

    testWidgets('Leave returns true, Stay returns false', (tester) async {
      final results = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showConfirmDialog(
                  context,
                  title: 'Leave this run?',
                  message: leaveMessage(GameMode.levels),
                  confirmLabel: 'Leave',
                  cancelLabel: 'Stay',
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Leave this run?'), findsOneWidget);
      expect(find.text('Your progress on this level is kept.'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(results, [false, true]);
      expect(find.text('Leave this run?'), findsNothing);
    });
  });

  group('Stats', () {
    testWidgets('empty state pops with Levels mode', (tester) async {
      final progress = Progress(await _prefs());
      GameMode? popped;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<GameMode>(
                  MaterialPageRoute(
                    builder: (_) => StatsScreen(progress: progress),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Play a level to see your stats here.'), findsOneWidget);
      expect(find.text('Levels solved'), findsNothing);
      await tester.tap(find.text('Play Levels'));
      await tester.pumpAndSettle();
      expect(popped, GameMode.levels);
    });

    testWidgets('shows stats once something is played', (tester) async {
      final progress = Progress(await _prefs({'stars_levels_1': 3}));
      await tester.pumpWidget(
        MaterialApp(home: StatsScreen(progress: progress)),
      );
      expect(find.text('Levels solved'), findsOneWidget);
      expect(find.text('Play Levels'), findsNothing);
    });
  });

  group('Home', () {
    testWidgets('mode cards are one button with title and status', (
      tester,
    ) async {
      final today = DateTime.now();
      final prefs = await _prefs({'level': 4});
      final progress = Progress(prefs);
      await progress.saveGameState(GameMode.levels, const {'level': 4}, today);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(progress: progress, settings: Settings(prefs)),
        ),
      );
      expect(
        find.bySemanticsLabel('Levels, Level 4 · in progress'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Move limit, Level 1'), findsOneWidget);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Move limit, Level 1'),
      );
      expect(node.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  test('portrait only on phones', () {
    expect(orientationsFor(411), [DeviceOrientation.portraitUp]);
    expect(orientationsFor(800), DeviceOrientation.values);
  });
}
