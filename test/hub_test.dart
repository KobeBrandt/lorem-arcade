import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lorem_arcade/hub/hub_game.dart';
import 'package:lorem_arcade/progress.dart';
import 'package:lorem_arcade/settings.dart';
import 'package:lorem_arcade/ui/hub_screen.dart';
import 'package:lorem_arcade/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(HubCard));

const _visible = [
  HubGame.colorFlow,
  HubGame.beadBelt,
  HubGame.cogClash,
  HubGame.gateDrop,
];

void main() {
  group('Settings hub layout', () {
    test('default order, view and sort', () async {
      final s = Settings(await _prefs());
      expect(s.gameOrder, HubGame.values);
      expect(s.hubView, HubView.list);
      expect(s.hubSort, HubSort.custom);
      expect(s.hiddenGames, isEmpty);
    });

    test('saved order skips unknown names and adds missing games', () async {
      final s = Settings(
        await _prefs({
          'hub_order': ['gateDrop', 'nope', 'colorFlow', 'gateDrop'],
        }),
      );
      expect(s.gameOrder.take(2), [HubGame.gateDrop, HubGame.colorFlow]);
      expect(s.gameOrder.toSet(), HubGame.values.toSet());
    });

    test('hide and show, view and sort are saved', () async {
      final prefs = await _prefs();
      final s = Settings(prefs);
      await s.setHidden(HubGame.cogClash, true);
      await s.setHubView(HubView.grid);
      await s.setHubSort(HubSort.recent);
      final reloaded = Settings(prefs);
      expect(reloaded.isHidden(HubGame.cogClash), isTrue);
      expect(reloaded.hiddenGames, [HubGame.cogClash]);
      expect(reloaded.hubView, HubView.grid);
      expect(reloaded.hubSort, HubSort.recent);
      await reloaded.setHidden(HubGame.cogClash, false);
      expect(reloaded.hiddenGames, isEmpty);
    });

    test('moving among shown games keeps hidden ones in place', () async {
      final s = Settings(await _prefs());
      await s.setHidden(HubGame.beadBelt, true);
      const shown = [HubGame.colorFlow, HubGame.cogClash, HubGame.gateDrop];
      await s.moveShown(shown, HubGame.gateDrop, up: true);
      expect(s.gameOrder, [
        HubGame.colorFlow,
        HubGame.beadBelt,
        HubGame.gateDrop,
        HubGame.cogClash,
        HubGame.mooMunch,
      ]);
      // Nothing moves past the edge.
      await s.moveShown(shown, HubGame.colorFlow, up: true);
      expect(s.gameOrder.first, HubGame.colorFlow);
    });
  });

  test('endless runs save best and add stars per 5 points', () async {
    final p = Progress(await _prefs());
    await p.reportGameRun('mooMunch', 7);
    await p.reportGameRun('mooMunch', 4);
    expect(p.gameBest('mooMunch'), 7);
    expect(p.gamePoints('mooMunch'), 11);
    expect(p.totalStars, 2);
  });

  Future<void> pumpHub(
    WidgetTester tester,
    Progress progress,
    Settings settings,
  ) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HubScreen(progress: progress, settings: settings),
      ),
    );
  }

  testWidgets('Moo Munch stays hidden until every game is hidden', (
    tester,
  ) async {
    final prefs = await _prefs();
    final progress = Progress(prefs);
    final settings = Settings(prefs);
    await pumpHub(tester, progress, settings);
    expect(find.text('Moo Munch'), findsNothing);

    for (final game in _visible) {
      await tester.longPress(_card(game.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide game'));
      await tester.pumpAndSettle();
    }
    expect(progress.mooMunchUnlocked, isTrue);
    expect(find.text('Moo Munch'), findsOneWidget);
    for (final game in _visible) {
      expect(find.text(game.title), findsNothing);
    }

    // Once unlocked, hiding it too shows the empty hint.
    await tester.longPress(_card('Moo Munch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide game'));
    await tester.pumpAndSettle();
    expect(find.text('All games are hidden.'), findsOneWidget);
  });

  testWidgets('view menu switches to grid and compact list', (tester) async {
    final prefs = await _prefs();
    final settings = Settings(prefs);
    await pumpHub(tester, Progress(prefs), settings);
    expect(find.byType(HubCard), findsNWidgets(4));

    await tester.tap(find.byTooltip('View and order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    expect(settings.hubView, HubView.grid);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    expect(find.byType(HubTile), findsNWidgets(4));

    await settings.setHubView(HubView.compact);
    await tester.pumpAndSettle();
    expect(find.byType(HubCompactRow), findsNWidgets(4));
  });

  testWidgets('recently played sorts the last opened game first', (
    tester,
  ) async {
    final prefs = await _prefs({'hub_sort': 'recent'});
    final progress = Progress(prefs);
    await progress.markPlayed('cogClash', DateTime(2026, 1, 2));
    await progress.markPlayed('gateDrop', DateTime(2026, 1, 1));
    await pumpHub(tester, progress, Settings(prefs));
    final cards = tester.widgetList<HubCard>(find.byType(HubCard)).toList();
    expect(cards.map((c) => c.title), [
      'Cog Clash',
      'Gate Drop',
      'Color Flow',
      'Bead Belt',
    ]);
  });

  testWidgets('Settings lists hidden games and shows them again', (
    tester,
  ) async {
    final prefs = await _prefs();
    final settings = Settings(prefs);
    await settings.setHidden(HubGame.beadBelt, true);
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );
    await tester.scrollUntilVisible(find.text('Bead Belt'), 100);
    expect(find.text('Bead Belt'), findsOneWidget);
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(settings.isHidden(HubGame.beadBelt), isFalse);
    expect(find.textContaining('No hidden games'), findsOneWidget);
  });
}
