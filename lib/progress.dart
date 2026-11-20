import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'game/game_mode.dart';

/// Saved progress, separate per mode.
class Progress {
  Progress(this._prefs);

  final SharedPreferences _prefs;

  static const String _endlessBestKey = 'endless_best';

  static const String _rushBestKey = 'rush_best';

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

  static String _savedStateKey(GameMode mode) => 'saved_${mode.name}';

  /// Modes whose unfinished level is kept when the player leaves: the
  /// level modes and the daily puzzle. Endless and rush runs end.
  static bool keepsState(GameMode mode) =>
      mode.hasLevels || mode == GameMode.daily;

  int level(GameMode mode) => _prefs.getInt(_levelKey(mode)) ?? 1;

  Future<void> setLevel(GameMode mode, int level) =>
      _prefs.setInt(_levelKey(mode), level);

  /// Saves the next level right after [level] is won, so leaving on the
  /// win card does not play the same level again. Only for level modes.
  Future<void> saveLevelWon(GameMode mode, int level) async {
    if (mode.hasLevels) await setLevel(mode, level + 1);
  }

  int get endlessBest => _prefs.getInt(_endlessBestKey) ?? 0;

  Future<void> reportEndlessScore(int score) async {
    if (score > endlessBest) await _prefs.setInt(_endlessBestKey, score);
  }

  int get rushBest => _prefs.getInt(_rushBestKey) ?? 0;

  Future<void> reportRushScore(int score) async {
    if (score > rushBest) await _prefs.setInt(_rushBestKey, score);
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

  /// Best stars of every solved level and daily, plus the stars from
  /// endless points of Color Flow and the hub games.
  int get totalStars =>
      _starKeys.fold(0, (sum, key) => sum + (_prefs.getInt(key) ?? 0)) +
      endlessStars +
      _gameEndlessStars;

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

  /// Saves the unfinished game of [mode] (from `ColorFlowGame.saveState`)
  /// for [day]. A null [state] removes the saved game.
  Future<void> saveGameState(
    GameMode mode,
    Map<String, Object?>? state,
    DateTime day,
  ) {
    final key = _savedStateKey(mode);
    if (state == null) return _prefs.remove(key);
    return _prefs.setString(
      key,
      jsonEncode({'day': dayKey(day), 'state': state}),
    );
  }

  Future<void> clearGameState(GameMode mode) =>
      _prefs.remove(_savedStateKey(mode));

  /// The saved unfinished game of [mode], or null. The daily puzzle only
  /// returns a game saved for [today]. Broken data counts as none.
  Map<String, Object?>? savedState(GameMode mode, DateTime today) {
    final raw = _prefs.getString(_savedStateKey(mode));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final state = decoded['state'];
      if (state is! Map<String, Object?>) return null;
      if (mode == GameMode.daily && decoded['day'] != dayKey(today)) {
        return null;
      }
      return state;
    } on FormatException {
      return null;
    }
  }

  bool hasSavedState(GameMode mode, DateTime today) =>
      savedState(mode, today) != null;

  // Hub games (Bead Belt, Cog Clash, Gate Drop), by game id. Their stars
  // use the same 'stars_' prefix, so they count in [totalStars] and unlock
  // themes for every game.

  /// Level reached in the hub game [id] (1 when never played).
  int gameLevel(String id) => _prefs.getInt('level_$id') ?? 1;

  Future<void> setGameLevel(String id, int level) =>
      _prefs.setInt('level_$id', level);

  /// Best stars (0 when never won) for [level] of the hub game [id].
  int gameLevelStars(String id, int level) =>
      _prefs.getInt('$_starsPrefix${id}_$level') ?? 0;

  /// Keeps the best of the saved and the new stars (1 to 3).
  Future<void> recordGameStars(String id, int level, int stars) async {
    final value = stars.clamp(1, 3);
    if (value > gameLevelStars(id, level)) {
      await _prefs.setInt('$_starsPrefix${id}_$level', value);
    }
  }

  /// All stars earned in the hub game [id].
  int gameStars(String id) => _prefs
      .getKeys()
      .where((key) => key.startsWith('$_starsPrefix${id}_'))
      .fold(0, (sum, key) => sum + (_prefs.getInt(key) ?? 0));

  /// Whether anything has been played: a solve, a score, a best time or
  /// a level past the first.
  bool get hasPlayed =>
      levelsSolved > 0 ||
      endlessBest > 0 ||
      endlessPoints > 0 ||
      rushBest > 0 ||
      _daily != null ||
      GameMode.values.any((mode) => bestTime(mode) != null) ||
      GameMode.values.any((mode) => mode.hasLevels && level(mode) > 1);

  /// When the hub game [id] was last opened, or null when never.
  DateTime? lastPlayed(String id) {
    final ms = _prefs.getInt('played_$id');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markPlayed(String id, DateTime when) =>
      _prefs.setInt('played_$id', when.millisecondsSinceEpoch);

  /// Moo Munch is the secret hub game. It joins the hub once every
  /// other game is hidden and stays from then on.
  static const String _mooUnlockedKey = 'moo_munch_unlocked';

  bool get mooMunchUnlocked => _prefs.getBool(_mooUnlockedKey) ?? false;

  Future<void> unlockMooMunch() => _prefs.setBool(_mooUnlockedKey, true);

  // Endless runs of hub games (only Moo Munch has one now).

  /// Points of all endless runs of one hub game: `points_{id}`.
  static const String _gamePointsPrefix = 'points_';

  /// Best endless score of the hub game [id] (0 when never played).
  int gameBest(String id) => _prefs.getInt('best_$id') ?? 0;

  /// Points earned in all endless runs of the hub game [id].
  int gamePoints(String id) => _prefs.getInt('$_gamePointsPrefix$id') ?? 0;

  /// Saves an ended endless run of the hub game [id]: the best score and
  /// the points toward stars ([endlessPointsPerStar] points give 1 star).
  Future<void> reportGameRun(String id, int score) async {
    if (score <= 0) return;
    if (score > gameBest(id)) await _prefs.setInt('best_$id', score);
    await _prefs.setInt('$_gamePointsPrefix$id', gamePoints(id) + score);
  }

  /// Stars from the endless points of every hub game, per game.
  int get _gameEndlessStars => _prefs
      .getKeys()
      .where((key) => key.startsWith(_gamePointsPrefix))
      .fold(
        0,
        (sum, key) => sum + (_prefs.getInt(key) ?? 0) ~/ endlessPointsPerStar,
      );

  static DateTime _yesterday(DateTime day) =>
      DateTime(day.year, day.month, day.day - 1);
}
