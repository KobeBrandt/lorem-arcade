import 'package:shared_preferences/shared_preferences.dart';

import 'game/game_mode.dart';

/// Saved progress, separate per mode.
class Progress {
  Progress(this._prefs);

  final SharedPreferences _prefs;

  static const String _endlessBestKey = 'endless_best';

  /// Last solved day and streak in one value ('yyyymmdd:streak'), so
  /// they can never be saved half.
  static const String _dailyKey = 'daily';

  /// Levels mode keeps the original 'level' key so old progress stays.
  static String _levelKey(GameMode mode) =>
      mode == GameMode.levels ? 'level' : 'level_${mode.name}';

  int level(GameMode mode) => _prefs.getInt(_levelKey(mode)) ?? 1;

  Future<void> setLevel(GameMode mode, int level) =>
      _prefs.setInt(_levelKey(mode), level);

  int get endlessBest => _prefs.getInt(_endlessBestKey) ?? 0;

  Future<void> reportEndlessScore(int score) async {
    if (score > endlessBest) await _prefs.setInt(_endlessBestKey, score);
  }

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

  /// Saves today's solve and returns the new streak.
  Future<int> markDailySolved(DateTime today) async {
    if (dailySolved(today)) return dailyStreak(today);
    final streak = dailyStreak(today) + 1;
    await _prefs.setString(_dailyKey, '${dayKey(today)}:$streak');
    return streak;
  }

  static DateTime _yesterday(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);
}
