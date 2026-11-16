import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  final prefs = await SharedPreferences.getInstance();
  runApp(ColorFlowApp(progress: Progress(prefs)));
}

class ColorFlowApp extends StatelessWidget {
  const ColorFlowApp({super.key, required this.progress});

  final Progress progress;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Color Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true)
          .copyWith(scaffoldBackgroundColor: AppColors.bgDeep),
      home: HomeScreen(progress: progress),
    );
  }
}
