import 'dart:typed_data';

import 'package:color_flow/audio/sound_player.dart';
import 'package:color_flow/audio/wav_synth.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter_test/flutter_test.dart';

String _ascii(ByteData data, int offset) =>
    String.fromCharCodes(List.generate(4, (i) => data.getUint8(offset + i)));

void main() {
  final sounds = buildAllSounds();

  const expectedMs = {
    'tap.wav': 40,
    'whoosh.wav': 250,
    'blocked.wav': 120,
    'complete_1.wav': 450,
    'complete_2.wav': 450,
    'complete_3.wav': 450,
    'complete_4.wav': 450,
    'complete_5.wav': 450,
    'win.wav': 800,
    'fail.wav': 500,
  };

  test('builds exactly the expected files', () {
    expect(sounds.keys.toSet(), expectedMs.keys.toSet());
  });

  for (final name in expectedMs.keys) {
    group(name, () {
      late ByteData data;
      setUp(() {
        final bytes = sounds[name]!;
        data = ByteData.sublistView(bytes);
      });

      test('has a valid 16-bit mono 44.1 kHz PCM header', () {
        expect(_ascii(data, 0), 'RIFF');
        expect(data.getUint32(4, Endian.little), data.lengthInBytes - 8);
        expect(_ascii(data, 8), 'WAVE');
        expect(_ascii(data, 12), 'fmt ');
        expect(data.getUint32(16, Endian.little), 16);
        expect(data.getUint16(20, Endian.little), 1); // PCM
        expect(data.getUint16(22, Endian.little), 1); // mono
        expect(data.getUint32(24, Endian.little), 44100);
        expect(data.getUint32(28, Endian.little), 44100 * 2);
        expect(data.getUint16(32, Endian.little), 2);
        expect(data.getUint16(34, Endian.little), 16);
        expect(_ascii(data, 36), 'data');
        expect(data.getUint32(40, Endian.little), data.lengthInBytes - 44);
      });

      test('has the expected length', () {
        final sampleCount = (data.lengthInBytes - 44) ~/ 2;
        final ms = sampleCount / sampleRate * 1000;
        expect(ms, closeTo(expectedMs[name]!, 1));
      });

      test('stays under the peak, is not silent, and fades at both ends', () {
        final sampleCount = (data.lengthInBytes - 44) ~/ 2;
        final limit = (maxPeak * 32767).ceil();
        var loudest = 0;
        for (var i = 0; i < sampleCount; i++) {
          final value = data.getInt16(44 + i * 2, Endian.little).abs();
          if (value > loudest) loudest = value;
        }
        expect(loudest, lessThanOrEqualTo(limit));
        expect(loudest, greaterThan(32767 * 0.1));
        expect(data.getInt16(44, Endian.little), 0);
        expect(data.getInt16(44 + (sampleCount - 1) * 2, Endian.little), 0);
      });
    });
  }

  test('game audio context mixes with other audio and takes no focus', () {
    final android = SoundPlayer.gameAudioContext().android;
    expect(android.audioFocus, AndroidAudioFocus.none);
    expect(android.usageType, AndroidUsageType.game);
    expect(android.contentType, AndroidContentType.sonification);
  });

  test('combo chords rise in pitch and clamp above 5', () {
    for (var level = 2; level <= completeLevels; level++) {
      expect(completeRoot(level), greaterThan(completeRoot(level - 1)));
    }
    expect(completeRoot(9), completeRoot(completeLevels));
    expect(completeRoot(0), completeRoot(1));
  });
}
