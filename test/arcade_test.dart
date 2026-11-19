import 'package:color_flow/arcade/arcade_catalog.dart';
import 'package:color_flow/arcade/arcade_level_game.dart';
import 'package:color_flow/arcade/arcade_level_screen.dart';
import 'package:color_flow/progress.dart';
import 'package:color_flow/settings.dart';
import 'package:color_flow/ui/hub_screen.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('Progress for hub games', () {
    test('levels and best stars per game; stars count in the total', () async {
      final progress = Progress(await _prefs({'stars_levels_1': 2}));
      expect(progress.gameLevel('beadBelt'), 1);
      await progress.setGameLevel('beadBelt', 4);
      expect(progress.gameLevel('beadBelt'), 4);
      expect(progress.gameLevel('gateDrop'), 1);

      await progress.recordGameStars('beadBelt', 1, 2);
      await progress.recordGameStars('beadBelt', 1, 1); // keeps the best
      await progress.recordGameStars('beadBelt', 2, 3);
      await progress.recordGameStars('cogClash', 1, 1);
      expect(progress.gameLevelStars('beadBelt', 1), 2);
      expect(progress.gameStars('beadBelt'), 5);
      expect(progress.gameStars('cogClash'), 1);
      expect(progress.totalStars, 2 + 5 + 1);
    });
  });

  testWidgets('hub shows Color Flow and every hub game as one button', (
    tester,
  ) async {
    final prefs = await _prefs({'level_gateDrop': 3, 'stars_gateDrop_1': 3});
    // A tall phone, so every card is built.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: HubScreen(progress: Progress(prefs), settings: Settings(prefs)),
      ),
    );
    expect(find.bySemanticsLabel('Color Flow, Level 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Bead Belt, Level 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Cog Clash, Level 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Gate Drop, Level 3 · 3 ★'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a won level saves stars and the next level', (tester) async {
    final prefs = await _prefs();
    final progress = Progress(prefs);
    await tester.pumpWidget(
      MaterialApp(
        home: ArcadeLevelScreen(
          game: ArcadeGame.beadBelt,
          progress: progress,
          settings: Settings(prefs),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Bead Belt · Level 1'), findsOneWidget);
    final game = tester
        .widget<GameWidget<ArcadeLevelGame>>(
          find.byType(GameWidget<ArcadeLevelGame>),
        )
        .game!;
    game.result.value = const ArcadeResult.won(2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress.gameLevelStars('beadBelt', 1), 2);
    expect(progress.gameLevel('beadBelt'), 2);
    expect(find.text('Next level'), findsOneWidget);
    await tester.tap(find.text('Next level'));
    await tester.pump();
    expect(find.text('Bead Belt · Level 2'), findsOneWidget);
  });

  test('ArcadeResult clamps stars and marks losses', () {
    expect(const ArcadeResult.won(5).stars, 3);
    expect(const ArcadeResult.won(0).stars, 1);
    expect(const ArcadeResult.lost('Belt full').won, isFalse);
  });
}
