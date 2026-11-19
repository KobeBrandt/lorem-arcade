import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio/sound_player.dart';
import 'game/game_feedback.dart';
import 'progress.dart';
import 'settings.dart';
import 'ui/app_theme.dart';
import 'ui/hub_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  final prefs = await SharedPreferences.getInstance();
  final settings = Settings(prefs);
  final sounds = await SoundPlayer.load();
  sounds.enabled = settings.sound;
  // Keep the player in step with the sound toggle.
  settings.addListener(() => sounds.enabled = settings.sound);
  // Phones play in portrait only; tablets may turn. Lock before the
  // first frame when the screen size is already known.
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final sizeKnown = !view.physicalSize.isEmpty;
  if (sizeKnown) {
    await SystemChrome.setPreferredOrientations(_orientationsFor(view));
  }
  runApp(
    ColorFlowApp(progress: Progress(prefs), settings: settings, sounds: sounds),
  );
  if (!sizeKnown) {
    // Fallback: the screen size is known for sure once the first frame
    // is drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      SystemChrome.setPreferredOrientations(_orientationsFor(view));
    });
  }
}

List<DeviceOrientation> _orientationsFor(FlutterView view) {
  final size = view.physicalSize / view.devicePixelRatio;
  return orientationsFor(size.shortestSide);
}

/// Smallest side (dp) from which a device counts as a tablet.
const double tabletShortestSide = 600;

/// Allowed orientations: portrait up on phones, all on tablets.
List<DeviceOrientation> orientationsFor(double shortestSide) =>
    shortestSide < tabletShortestSide
    ? const [DeviceOrientation.portraitUp]
    : DeviceOrientation.values;

class ColorFlowApp extends StatelessWidget {
  const ColorFlowApp({
    super.key,
    required this.progress,
    required this.settings,
    required this.sounds,
  });

  final Progress progress;
  final Settings settings;
  final GameSounds sounds;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Puzzles',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true)
          .copyWith(scaffoldBackgroundColor: AppColors.bgDeep),
      home: HubScreen(progress: progress, settings: settings, sounds: sounds),
    );
  }
}
