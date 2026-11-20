// Draws the app icon PNGs used by flutter_launcher_icons.
// Run: flutter test tool/make_icon_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:lorem_arcade/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _size = 1024;

void main() {
  testWidgets('generate icon PNGs', (tester) async {
    await tester.runAsync(() async {
      Directory('assets/icon').createSync(recursive: true);
      await _save('assets/icon/icon.png', withBackground: true, scale: 0.8);
      // Adaptive foreground: content inside the 66% safe zone.
      await _save('assets/icon/foreground.png',
          withBackground: false, scale: 0.56);
    });
  });
}

Future<void> _save(String path,
    {required bool withBackground, required double scale}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const full = Rect.fromLTWH(0, 0, _size, _size);

  if (withBackground) {
    canvas.drawRect(
      full,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(_size / 2, _size * 1.1),
          _size * 1.2,
          [AppColors.bgGlow, AppColors.bgMid, AppColors.bgDeep],
          [0, 0.55, 1],
        ),
    );
  }

  final box = Rect.fromCenter(
    center: full.center,
    width: _size * scale,
    height: _size * scale,
  );
  final unit = box.width / 100;

  // Loop: rounded rectangle in the upper part, accent gradient stroke.
  final loop = Rect.fromLTWH(
      box.left + 6 * unit, box.top + 4 * unit, 88 * unit, 46 * unit);
  final loopRRect = RRect.fromRectAndRadius(loop, Radius.circular(16 * unit));
  canvas.drawRRect(
    loopRRect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * unit
      ..color = AppColors.well,
  );
  canvas.drawRRect(
    loopRRect,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * unit
      ..shader = ui.Gradient.linear(
        loop.topLeft,
        loop.bottomRight,
        [AppColors.accentMint, AppColors.accentLavender],
      ),
  );

  // Three blocks below, in three block colors.
  final colors = [AppColors.blocks[0], AppColors.blocks[1], AppColors.blocks[2]];
  for (var i = 0; i < 3; i++) {
    final block = Rect.fromLTWH(
      box.left + (14 + i * 26) * unit,
      box.top + 62 * unit,
      20 * unit,
      30 * unit,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(block, Radius.circular(6 * unit)),
      Paint()..color = colors[i],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(block.left + 3 * unit, block.top + 3 * unit,
            block.width - 6 * unit, 3 * unit),
        Radius.circular(2 * unit),
      ),
      Paint()..color = const Color(0x59FFFFFF),
    );
  }

  final image =
      await recorder.endRecording().toImage(_size.toInt(), _size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}
