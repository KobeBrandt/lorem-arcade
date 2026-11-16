import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

import '../game/game_feedback.dart';
import 'wav_synth.dart' show completeLevels;

/// Plays the game's sound effects from `assets/audio/` with flame_audio.
///
/// Every call is fire-and-forget: errors are caught and ignored so a sound
/// problem never breaks the game.
class SoundPlayer implements GameSounds {
  SoundPlayer._(this._tapPool, this._whooshPool, this._blockedPool);

  /// When false, every method does nothing.
  bool enabled = true;

  final AudioPool? _tapPool;
  final AudioPool? _whooshPool;
  final AudioPool? _blockedPool;

  static const Duration _tapGap = Duration(milliseconds: 40);
  static const Duration _whooshGap = Duration(milliseconds: 80);
  static const Duration _blockedGap = Duration(milliseconds: 60);

  final Stopwatch _clock = Stopwatch()..start();
  Duration? _lastTap;
  Duration? _lastWhoosh;
  Duration? _lastBlocked;

  static const String _tapFile = 'tap.wav';
  static const String _whooshFile = 'whoosh.wav';
  static const String _blockedFile = 'blocked.wav';
  static const String _winFile = 'win.wav';
  static const String _failFile = 'fail.wav';

  static String _completeFile(int level) => 'complete_$level.wav';

  /// Preloads every sound. Never throws; a sound that fails to load is
  /// simply silent.
  static Future<SoundPlayer> load() async {
    try {
      await FlameAudio.audioCache.loadAll([
        _tapFile,
        _whooshFile,
        _blockedFile,
        for (var level = 1; level <= completeLevels; level++)
          _completeFile(level),
        _winFile,
        _failFile,
      ]);
    } catch (error) {
      debugPrint('SoundPlayer: preload failed: $error');
    }
    final pools = await Future.wait([
      _createPool(_tapFile, maxPlayers: 4),
      _createPool(_whooshFile, maxPlayers: 3),
      _createPool(_blockedFile, maxPlayers: 2),
    ]);
    return SoundPlayer._(pools[0], pools[1], pools[2]);
  }

  static Future<AudioPool?> _createPool(
    String file, {
    required int maxPlayers,
  }) async {
    try {
      return await FlameAudio.createPool(file, maxPlayers: maxPlayers);
    } catch (error) {
      debugPrint('SoundPlayer: pool for $file failed: $error');
      return null;
    }
  }

  @override
  void tap() {
    if (!enabled || !_ready(_lastTap, _tapGap)) return;
    _lastTap = _clock.elapsed;
    _startPool(_tapPool, volume: 0.8);
  }

  @override
  void whoosh() {
    if (!enabled || !_ready(_lastWhoosh, _whooshGap)) return;
    _lastWhoosh = _clock.elapsed;
    _startPool(_whooshPool, volume: 0.7);
  }

  @override
  void blocked() {
    if (!enabled || !_ready(_lastBlocked, _blockedGap)) return;
    _lastBlocked = _clock.elapsed;
    _startPool(_blockedPool);
  }

  @override
  void complete(int combo) {
    if (!enabled) return;
    _play(_completeFile(combo.clamp(1, completeLevels)));
  }

  @override
  void win() {
    if (!enabled) return;
    _play(_winFile);
  }

  @override
  void fail() {
    if (!enabled) return;
    _play(_failFile);
  }

  bool _ready(Duration? last, Duration gap) =>
      last == null || _clock.elapsed - last >= gap;

  void _startPool(AudioPool? pool, {double volume = 1.0}) {
    if (pool == null) return;
    _guard(() => pool.start(volume: volume));
  }

  void _play(String file) {
    _guard(() => FlameAudio.play(file));
  }

  /// Runs [action] and swallows both sync and async errors.
  void _guard(Future<Object?> Function() action) {
    try {
      unawaited(
        action().then<void>(
          (_) {},
          onError: (Object error) {
            debugPrint('SoundPlayer: play failed: $error');
          },
        ),
      );
    } catch (error) {
      debugPrint('SoundPlayer: play failed: $error');
    }
  }
}
