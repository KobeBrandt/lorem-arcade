/// Pure Dart synthesis of the game's short sound effects as 16-bit mono WAV.
///
/// No Flutter imports, so `tool/make_sounds.dart` can run it with plain
/// `dart run`, and tests can check the output without audio playback.
library;

import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 44100;

/// Highest allowed amplitude (about -6 dBFS) for any sound.
const double maxPeak = 0.5;

/// Number of combo levels that get their own `complete_N.wav`.
const int completeLevels = 5;

/// Encodes [samples] (range -1..1) as a 16-bit mono PCM WAV file.
Uint8List encodeWav(Float64List samples, {int rate = sampleRate}) {
  final dataSize = samples.length * 2;
  final bytes = ByteData(44 + dataSize);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little); // fmt chunk size
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little); // byte rate
  bytes.setUint16(32, 2, Endian.little); // block align
  bytes.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    bytes.setInt16(44 + i * 2, value, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// All game sounds by file name (e.g. `tap.wav`).
Map<String, Uint8List> buildAllSounds() {
  return {
    'tap.wav': encodeWav(synthTap()),
    'whoosh.wav': encodeWav(synthWhoosh()),
    'blocked.wav': encodeWav(synthBlocked()),
    for (var level = 1; level <= completeLevels; level++)
      'complete_$level.wav': encodeWav(synthComplete(level)),
    'win.wav': encodeWav(synthWin()),
    'fail.wav': encodeWav(synthFail()),
  };
}

/// Soft click, ~40 ms.
Float64List synthTap() {
  final out = _buffer(0.04);
  final random = math.Random(1);
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final envelope = math.exp(-t * 140);
    final tone =
        math.sin(2 * math.pi * 1400 * t) +
        0.5 * math.sin(2 * math.pi * 700 * t);
    final noise = (random.nextDouble() * 2 - 1) * math.exp(-t * 600) * 0.3;
    out[i] = (tone + noise) * envelope;
  }
  return _finish(out, peak: 0.35, fadeIn: 0.001, fadeOut: 0.008);
}

/// Soft low-passed noise swell, ~250 ms, quiet.
Float64List synthWhoosh() {
  final out = _buffer(0.25);
  final random = math.Random(2);
  var low = 0.0;
  var lower = 0.0;
  for (var i = 0; i < out.length; i++) {
    final progress = i / out.length;
    // Cutoff sweeps up then down for a "passing by" feel.
    final cutoff = 300 + 1800 * math.sin(math.pi * progress);
    final alpha = 1 - math.exp(-2 * math.pi * cutoff / sampleRate);
    final noise = random.nextDouble() * 2 - 1;
    low += alpha * (noise - low);
    lower += alpha * (low - lower);
    out[i] = lower * math.pow(math.sin(math.pi * progress), 1.5);
  }
  return _finish(out, peak: 0.22, fadeIn: 0.01, fadeOut: 0.02);
}

/// Low soft thud, ~120 ms.
Float64List synthBlocked() {
  final out = _buffer(0.12);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final frequency = 80 + 70 * math.exp(-t * 30);
    phase += 2 * math.pi * frequency / sampleRate;
    out[i] = (math.sin(phase) + 0.2 * math.sin(2 * phase)) * math.exp(-t * 28);
  }
  return _finish(out, peak: 0.45, fadeIn: 0.003, fadeOut: 0.02);
}

/// Major scale steps (semitones above C5) used for the rising combo chords.
const List<int> completeSteps = [0, 2, 4, 5, 7];

/// Root frequency of the chord for combo [level] (1-based, clamped 1..5).
double completeRoot(int level) {
  final index = level.clamp(1, completeLevels) - 1;
  return _note(523.25, completeSteps[index]);
}

/// Soft major chord, ~450 ms, pitched up for each combo [level].
Float64List synthComplete(int level) {
  final root = completeRoot(level);
  final out = _buffer(0.45);
  final frequencies = [root, _note(root, 4), _note(root, 7), root * 2];
  const weights = [1.0, 0.8, 0.7, 0.3];
  for (var i = 0; i < out.length; i++) {
    final t = i / sampleRate;
    final attack = math.min(1.0, t / 0.015);
    final envelope = attack * math.exp(-t * 6.5);
    var sum = 0.0;
    for (var k = 0; k < frequencies.length; k++) {
      sum += weights[k] * _bell(frequencies[k], t);
    }
    out[i] = sum * envelope;
  }
  return _finish(out, peak: maxPeak, fadeIn: 0.002, fadeOut: 0.04);
}

/// Bright rising arpeggio, ~800 ms.
Float64List synthWin() {
  final out = _buffer(0.8);
  const notes = [523.25, 659.25, 783.99, 1046.5];
  const spacing = 0.1;
  for (var n = 0; n < notes.length; n++) {
    final start = (n * spacing * sampleRate).round();
    final isLast = n == notes.length - 1;
    final decay = isLast ? 4.0 : 9.0;
    for (var i = start; i < out.length; i++) {
      final t = (i - start) / sampleRate;
      final attack = math.min(1.0, t / 0.008);
      out[i] += _bell(notes[n], t) * attack * math.exp(-t * decay);
    }
  }
  return _finish(out, peak: maxPeak, fadeIn: 0.002, fadeOut: 0.06);
}

/// Soft descending two-tone, ~500 ms.
Float64List synthFail() {
  final out = _buffer(0.5);
  const notes = [392.0, 311.13]; // G4 then Eb4
  const noteLength = 0.25;
  for (var n = 0; n < notes.length; n++) {
    final start = (n * noteLength * sampleRate).round();
    final end = n == notes.length - 1
        ? out.length
        : ((n + 1) * noteLength * sampleRate).round();
    for (var i = start; i < end; i++) {
      final t = (i - start) / sampleRate;
      final remaining = (end - i) / sampleRate;
      final attack = math.min(1.0, t / 0.02);
      final release = math.min(1.0, remaining / 0.03);
      final tone =
          math.sin(2 * math.pi * notes[n] * t) +
          0.15 * math.sin(2 * math.pi * notes[n] * 2 * t);
      out[i] = tone * attack * release * math.exp(-t * 3);
    }
  }
  return _finish(out, peak: 0.42, fadeIn: 0.002, fadeOut: 0.04);
}

/// Sine with a faint second harmonic, for a soft bell-like tone.
double _bell(double frequency, double t) {
  return math.sin(2 * math.pi * frequency * t) +
      0.12 * math.sin(2 * math.pi * frequency * 2 * t);
}

double _note(double base, int semitones) =>
    base * math.pow(2, semitones / 12).toDouble();

Float64List _buffer(double seconds) =>
    Float64List((seconds * sampleRate).round());

/// Scales [samples] so the loudest one equals [peak], then applies linear
/// fades at both ends to avoid clicks.
Float64List _finish(
  Float64List samples, {
  required double peak,
  required double fadeIn,
  required double fadeOut,
}) {
  var loudest = 0.0;
  for (final s in samples) {
    loudest = math.max(loudest, s.abs());
  }
  if (loudest > 0) {
    final gain = math.min(peak, maxPeak) / loudest;
    for (var i = 0; i < samples.length; i++) {
      samples[i] *= gain;
    }
  }
  final inCount = (fadeIn * sampleRate).round();
  final outCount = (fadeOut * sampleRate).round();
  for (var i = 0; i < inCount && i < samples.length; i++) {
    samples[i] *= i / inCount;
  }
  for (var i = 0; i < outCount && i < samples.length; i++) {
    samples[samples.length - 1 - i] *= i / outCount;
  }
  return samples;
}
