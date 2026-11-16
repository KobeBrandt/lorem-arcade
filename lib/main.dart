import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio/sound_player.dart';
import 'game/game_feedback.dart';
import 'progress.dart';
import 'settings.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  final prefs = await SharedPreferences.getInstance();
  final settings = Settings(prefs);
  final sounds = await SoundPlayer.load();
  sounds.enabled = settings.sound;
  // Keep the player in step with the sound toggle.
  settings.addListener(() => sounds.enabled = settings.sound);
  runApp(
    ColorFlowApp(progress: Progress(prefs), settings: settings, sounds: sounds),
  );
}

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
      title: 'Color Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true)
          .copyWith(scaffoldBackgroundColor: AppColors.bgDeep),
      home: HomeScreen(progress: progress, settings: settings, sounds: sounds),
    );
  }
}
