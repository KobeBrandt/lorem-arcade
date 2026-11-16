import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game/game_feedback.dart';
import 'ui/app_theme.dart';

/// Block color themes, unlocked with stars.
enum BlockTheme {
  standard('Default', 0, AppColors.blocks),
  neon('Neon', 30, [
    Color(0xFFFF2E9A), // hot pink
    Color(0xFFF5FF3B), // electric yellow
    Color(0xFF2EC5FF), // cyan
    Color(0xFF39FF88), // neon green
    Color(0xFFFF8A1F), // neon orange
    Color(0xFFA35CFF), // violet
  ]),
  pastel('Pastel', 75, [
    Color(0xFFFFB3D1), // rose
    Color(0xFFFFEBA3), // butter
    Color(0xFFA8D1FF), // sky
    Color(0xFFB5F0D3), // mint
    Color(0xFFFFB98A), // peach
    Color(0xFFD6C4FF), // lilac
  ]),
  mono('Mono + shapes', 150, [
    Color(0xFFFAFAFA),
    Color(0xFFD4D4D4),
    Color(0xFFADADAD),
    Color(0xFF878787),
    Color(0xFF666666),
    Color(0xFF4A4A4A),
  ]);

  const BlockTheme(this.title, this.cost, this.palette);

  final String title;

  /// Total stars needed to unlock.
  final int cost;
  final List<Color> palette;

  BlockStyle get style => BlockStyle(palette: palette);

  bool unlockedWith(int stars) => stars >= cost;
}

/// Okabe-Ito colors (without black), told apart with every common kind
/// of color blindness. Shapes are always on.
const BlockStyle colorBlindStyle = BlockStyle(
  palette: [
    Color(0xFFD55E00), // vermillion
    Color(0xFFF0E442), // yellow
    Color(0xFF56B4E9), // sky blue
    Color(0xFF009E73), // bluish green
    Color(0xFFE69F00), // orange
    Color(0xFFCC79A7), // reddish purple
  ],
  showShapes: true,
);

/// Saved player settings. Listeners hear every change.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  final SharedPreferences _prefs;

  static const String _hapticsKey = 'setting_haptics';
  static const String _soundKey = 'setting_sound';
  static const String _colorBlindKey = 'setting_color_blind';
  static const String _themeKey = 'setting_theme';

  bool get haptics => _prefs.getBool(_hapticsKey) ?? true;
  bool get sound => _prefs.getBool(_soundKey) ?? true;
  bool get colorBlind => _prefs.getBool(_colorBlindKey) ?? false;

  Future<void> setHaptics(bool value) => _setBool(_hapticsKey, value);
  Future<void> setSound(bool value) => _setBool(_soundKey, value);
  Future<void> setColorBlind(bool value) => _setBool(_colorBlindKey, value);

  Future<void> _setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
    notifyListeners();
  }

  /// The selected theme (Default when nothing or something unknown is saved).
  BlockTheme get theme {
    final name = _prefs.getString(_themeKey);
    return BlockTheme.values.firstWhere(
      (t) => t.name == name,
      orElse: () => BlockTheme.standard,
    );
  }

  /// Selects [theme] when [stars] unlock it. Returns whether it did.
  Future<bool> selectTheme(BlockTheme theme, int stars) async {
    if (!theme.unlockedWith(stars)) return false;
    await _prefs.setString(_themeKey, theme.name);
    notifyListeners();
    return true;
  }

  /// What the game draws blocks with: the color-blind palette while it
  /// is on, else the selected theme (Default if it is no longer unlocked).
  BlockStyle blockStyle(int stars) {
    if (colorBlind) return colorBlindStyle;
    final selected = theme;
    return selected.unlockedWith(stars)
        ? selected.style
        : BlockTheme.standard.style;
  }
}
