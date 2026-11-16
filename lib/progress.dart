import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'game/game_mode.dart';

/// Saved progress, separate per mode.
class Progress {
  Progress(this._prefs);

  final SharedPreferences _prefs;

  static const String _endlessBestKey = 'endless_best';

  /// Points earned in all endless runs together; 5 points give 1 star.
  static const String _endlessPointsKey = 'endless_points';

  /// Last solved day and streak in one value ('yyyymmdd:streak'), so
  /// they can never be saved half.
  static const String _dailyKey = 'daily';

  static const String _dailyLongestKey = 'daily_longest';

  /// Best stars per solved level: `stars_{mode}_{level}` for level modes,
  /// `stars_daily_{yyyymmdd}` for the daily puzzle.
  static const String _starsPrefix = 'stars_';

  static const int endlessPointsPerStar = 5;

  /// Levels mode keeps the original 'level' key so old progress stays.
  static String _levelKey(GameMode mode) =>
      mode == GameMode.levels ? 'level' : 'level_${mode.name}';

  static String _starsKey(GameMode mode, int level) =>
      '$_starsPrefix${mode.name}_$level';

  static String _bestTimeKey(GameMode mode) => 'best_time_${mode.name}';

  static String _tutorialKey(GameMode mode) => 'tutorial_seen_${mode.name}';

  int level(GameMode mode) => _prefs.getInt(_levelKey(mode)) ?? 1;

  Future<void> setLevel(GameMode mode, int level) =>
      _prefs.setInt(_levelKey(mode), level);

  int get endlessBest => _prefs.getInt(_endlessBestKey) ?? 0;

  Future<void> reportEndlessScore(int score) async {
    if (score > endlessBest) await _prefs.setInt(_endlessBestKey, score);
  }

  int get endlessPoints => _prefs.getInt(_endlessPointsKey) ?? 0;

  Future<void> addEndlessPoints(int points) =>
      _prefs.setInt(_endlessPointsKey, endlessPoints + points);

  /// (last solved day, streak), or null when never solved.
  (int, int)? get _daily {
    final parts = _prefs.getString(_dailyKey)?.split(':');
    if (parts == null || parts.length != 2) return null;
    final day = int.tryParse(parts[0]);
    final streak = int.tryParse(parts[1]);
    if (day == null || streak == null) return null;
    return (day, streak);
  }

  bool dailySolved(DateTime today) => _daily?.$1 == dayKey(today);

  /// Days solved in a row up to today or yesterday. A missed day shows 0.
  int dailyStreak(DateTime today) {
    final daily = _daily;
    if (daily == null) return 0;
    final (last, streak) = daily;
    if (last == dayKey(today) || last == dayKey(_yesterday(today))) {
      return streak;
    }
    return 0;
  }

  /// Longest daily streak ever. Also counts a streak saved before the
  /// longest streak was tracked.
  int get dailyLongestStreak =>
      max(_prefs.getInt(_dailyLongestKey) ?? 0, _daily?.$2 ?? 0);

  /// Saves today's solve and returns the new streak.
  Future<int> markDailySolved(DateTime today) async {
    if (dailySolved(today)) return dailyStreak(today);
    final streak = dailyStreak(today) + 1;
    final longest = max(dailyLongestStreak, streak);
    await _prefs.setString(_dailyKey, '${dayKey(today)}:$streak');
    await _prefs.setInt(_dailyLongestKey, longest);
    return streak;
  }

  /// Best stars (0 when never solved) for a level of a level mode.
  int levelStars(GameMode mode, int level) =>
      _prefs.getInt(_starsKey(mode, level)) ?? 0;

  int dailyStars(DateTime day) => levelStars(GameMode.daily, dayKey(day));

  /// Keeps the best of the saved and the new stars (1 to 3).
  Future<void> recordStars(GameMode mode, int level, int stars) async {
    final value = stars.clamp(1, 3);
    if (value > levelStars(mode, level)) {
      await _prefs.setInt(_starsKey(mode, level), value);
    }
  }

  Future<void> recordDailyStars(DateTime day, int stars) =>
      recordStars(GameMode.daily, dayKey(day), stars);

  Iterable<String> get _starKeys =>
      _prefs.getKeys().where((key) => key.startsWith(_starsPrefix));

  /// Levels and daily puzzles solved at least once.
  int get levelsSolved => _starKeys.length;

  int get endlessStars => endlessPoints ~/ endlessPointsPerStar;

  /// Best stars of every solved level and daily, plus the endless stars.
  int get totalStars =>
      _starKeys.fold(0, (sum, key) => sum + (_prefs.getInt(key) ?? 0)) +
      endlessStars;

  /// Fastest win in [mode] in seconds, or null when never won.
  double? bestTime(GameMode mode) => _prefs.getDouble(_bestTimeKey(mode));

  Future<void> recordTime(GameMode mode, double seconds) async {
    final best = bestTime(mode);
    if (best == null || seconds < best) {
      await _prefs.setDouble(_bestTimeKey(mode), seconds);
    }
  }

  bool tutorialSeen(GameMode mode) =>
      _prefs.getBool(_tutorialKey(mode)) ?? false;

  Future<void> markTutorialSeen(GameMode mode) =>
      _prefs.setBool(_tutorialKey(mode), true);

  static DateTime _yesterday(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);
}
