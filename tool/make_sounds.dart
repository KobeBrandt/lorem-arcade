// Writes the game's sound effects into assets/audio/.
//
// Run from the project root: dart run tool/make_sounds.dart
import 'dart:io';

import 'package:lorem_arcade/audio/wav_synth.dart';

void main() {
  final directory = Directory('assets/audio');
  directory.createSync(recursive: true);
  final sounds = buildAllSounds();
  for (final entry in sounds.entries) {
    final file = File('${directory.path}/${entry.key}');
    file.writeAsBytesSync(entry.value);
    final milliseconds = ((entry.value.length - 44) / 2 / sampleRate * 1000)
        .round();
    stdout.writeln('${file.path}  ${milliseconds}ms  ${entry.value.length} B');
  }
}
