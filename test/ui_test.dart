import 'package:color_flow/progress.dart';
import 'package:color_flow/settings.dart';
import 'package:color_flow/ui/settings_screen.dart';
import 'package:color_flow/ui/themes_screen.dart';
import 'package:flutter/material.dart';
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
}
