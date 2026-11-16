import 'package:color_flow/game/game_mode.dart';
import 'package:color_flow/progress.dart';
import 'package:color_flow/settings.dart';
import 'package:color_flow/ui/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('Stars', () {
    test('keeps the best stars per mode and level', () async {
      final p = Progress(await _prefs());
      expect(p.levelStars(GameMode.levels, 1), 0);
      await p.recordStars(GameMode.levels, 1, 2);
      await p.recordStars(GameMode.levels, 1, 1);
      expect(p.levelStars(GameMode.levels, 1), 2);
      await p.recordStars(GameMode.levels, 1, 3);
      expect(p.levelStars(GameMode.levels, 1), 3);
      // Other modes and levels are separate.
      expect(p.levelStars(GameMode.moves, 1), 0);
      expect(p.levelStars(GameMode.levels, 2), 0);
    });

    test('daily stars are saved per date', () async {
      final p = Progress(await _prefs());
      await p.recordDailyStars(DateTime(2026, 11, 16), 3);
      expect(p.dailyStars(DateTime(2026, 11, 16)), 3);
      expect(p.dailyStars(DateTime(2026, 11, 17)), 0);
    });

    test('total sums best stars plus 1 per 5 endless points', () async {
      final p = Progress(await _prefs());
      await p.recordStars(GameMode.levels, 1, 3);
      await p.recordStars(GameMode.levels, 1, 2);
      await p.recordStars(GameMode.timed, 4, 2);
      await p.recordDailyStars(DateTime(2026, 11, 16), 1);
      await p.addEndlessPoints(7);
      await p.addEndlessPoints(4);
      expect(p.endlessPoints, 11);
      expect(p.endlessStars, 2);
      expect(p.totalStars, 3 + 2 + 1 + 2);
      expect(p.levelsSolved, 3);
    });

    test('other saved keys do not count as stars', () async {
      final p = Progress(await _prefs({'level': 5, 'endless_best': 40}));
      expect(p.totalStars, 0);
      expect(p.levelsSolved, 0);
    });
  });

  group('Best time', () {
    test('keeps the fastest win per mode', () async {
      final p = Progress(await _prefs());
      expect(p.bestTime(GameMode.timed), isNull);
      await p.recordTime(GameMode.timed, 42.5);
      await p.recordTime(GameMode.timed, 50);
      expect(p.bestTime(GameMode.timed), 42.5);
      await p.recordTime(GameMode.timed, 30.2);
      expect(p.bestTime(GameMode.timed), 30.2);
      expect(p.bestTime(GameMode.levels), isNull);
    });
  });

  group('Rush best', () {
    test('keeps the best rush score under rush_best', () async {
      final prefs = await _prefs();
      final p = Progress(prefs);
      expect(p.rushBest, 0);
      await p.reportRushScore(7);
      await p.reportRushScore(4);
      expect(p.rushBest, 7);
      expect(prefs.getInt('rush_best'), 7);
      // Separate from endless, and no stars.
      expect(p.endlessBest, 0);
      expect(p.totalStars, 0);
    });
  });

  group('Daily longest streak', () {
    test('grows with the streak and stays after a missed day', () async {
      final p = Progress(await _prefs());
      expect(p.dailyLongestStreak, 0);
      await p.markDailySolved(DateTime(2026, 11, 1));
      await p.markDailySolved(DateTime(2026, 11, 2));
      await p.markDailySolved(DateTime(2026, 11, 3));
      expect(p.dailyLongestStreak, 3);
      // Missed a day: the streak starts over, the longest stays.
      expect(await p.markDailySolved(DateTime(2026, 11, 5)), 1);
      expect(p.dailyLongestStreak, 3);
    });

    test('counts a streak saved before it was tracked', () async {
      final p = Progress(await _prefs({'daily': '20261101:6'}));
      expect(p.dailyLongestStreak, 6);
    });
  });

  group('Tutorial', () {
    test('is remembered per mode', () async {
      final p = Progress(await _prefs());
      expect(p.tutorialSeen(GameMode.timed), isFalse);
      await p.markTutorialSeen(GameMode.timed);
      expect(p.tutorialSeen(GameMode.timed), isTrue);
      expect(p.tutorialSeen(GameMode.levels), isFalse);
    });
  });

  group('Settings', () {
    test('defaults: haptics and sound on, color-blind off', () async {
      final s = Settings(await _prefs());
      expect([s.haptics, s.sound, s.colorBlind], [true, true, false]);
      expect(s.theme, BlockTheme.standard);
      expect(s.blockStyle(0).palette, AppColors.blocks);
    });

    test('toggles are saved and notify listeners', () async {
      final prefs = await _prefs();
      final s = Settings(prefs);
      var calls = 0;
      s.addListener(() => calls++);
      await s.setSound(false);
      await s.setHaptics(false);
      expect(calls, 2);
      final reloaded = Settings(prefs);
      expect([reloaded.sound, reloaded.haptics], [false, false]);
    });

    test('themes unlock at their star cost', () async {
      final s = Settings(await _prefs());
      expect(BlockTheme.neon.unlockedWith(29), isFalse);
      expect(BlockTheme.neon.unlockedWith(30), isTrue);
      expect(await s.selectTheme(BlockTheme.pastel, 74), isFalse);
      expect(s.theme, BlockTheme.standard);
      expect(await s.selectTheme(BlockTheme.pastel, 75), isTrue);
      expect(s.theme, BlockTheme.pastel);
      expect(s.blockStyle(75).palette, BlockTheme.pastel.palette);
    });

    test('every theme has 6 different colors', () {
      for (final theme in BlockTheme.values) {
        expect(theme.palette.toSet(), hasLength(6), reason: theme.title);
      }
      expect(colorBlindStyle.palette.toSet(), hasLength(6));
    });

    test('color-blind palette overrides the theme', () async {
      final s = Settings(await _prefs());
      await s.selectTheme(BlockTheme.neon, 30);
      await s.setColorBlind(true);
      final style = s.blockStyle(30);
      expect(style.palette, colorBlindStyle.palette);
      expect(style.showShapes, isTrue);
    });

    test('a saved theme above the current stars falls back', () async {
      final s = Settings(await _prefs({'setting_theme': 'mono'}));
      expect(s.blockStyle(10).palette, AppColors.blocks);
      expect(s.blockStyle(150).palette, BlockTheme.mono.palette);
    });
  });
}
