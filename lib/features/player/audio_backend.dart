// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'playable.dart';

enum BackendState { idle, loading, buffering, ready, completed }

/// Things the platform tells the player that are not plain state changes.
sealed class BackendSignal {
  const BackendSignal();
}

/// Something changed: playing, state, current track.
final class BackendChanged extends BackendSignal {
  const BackendChanged();
}

/// A phone call or another app took the audio.
final class InterruptionBegan extends BackendSignal {
  const InterruptionBegan({required this.duck});
  final bool duck;
}

final class InterruptionEnded extends BackendSignal {
  const InterruptionEnded({required this.shouldResume});
  final bool shouldResume;
}

/// Headphones unplugged or Bluetooth dropped.
final class BecameNoisy extends BackendSignal {
  const BecameNoisy();
}

/// The audio could not be loaded or decoded.
final class BackendFailed extends BackendSignal {
  const BackendFailed(this.details);
  final String details;
}

/// The thin layer over the platform player. Only [PlayerEngine] talks to
/// it; tests swap in a fake.
abstract interface class AudioBackend {
  Stream<BackendSignal> get signals;

  /// Replaces whatever was loaded. Throws when the first track cannot load.
  Future<void> load(List<PlayableTrack> tracks, {required int index, required Duration offset});
  void play();
  Future<void> pause();
  Future<void> seek(int index, Duration offset);
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double volume);

  /// Android only; a no-op elsewhere.
  Future<void> setSkipSilence(bool enabled);

  /// Android only, 0 to 10 dB; a no-op elsewhere.
  Future<void> setBoost(double decibels);
  Future<void> stop();

  int get index;
  Duration get offset;
  bool get playing;
  BackendState get state;
}

/// just_audio and audio_session.
final class JustAudioBackend implements AudioBackend {
  JustAudioBackend() {
    _enhancer = Platform.isAndroid ? AndroidLoudnessEnhancer() : null;
    _player = AudioPlayer(
      // The engine decides what an interruption means (the two minute rule
      // in docs/plan/04-phase3-player.md 3.1), so just_audio must not.
      handleInterruptions: false,
      audioPipeline: _enhancer == null ? null : AudioPipeline(androidAudioEffects: [_enhancer]),
    );
    _subs.add(
      _player.playbackEventStream.listen(
        (_) => _signals.add(const BackendChanged()),
        onError: (Object e, StackTrace _) => _signals.add(BackendFailed('$e')),
      ),
    );
    _subs.add(_player.playingStream.listen((_) => _signals.add(const BackendChanged())));
    unawaited(_configureSession());
  }

  late final AudioPlayer _player;
  late final AndroidLoudnessEnhancer? _enhancer;
  final _signals = StreamController<BackendSignal>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  Future<void> _configureSession() async {
    final AudioSession session;
    try {
      session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    } on Object catch (e) {
      _signals.add(BackendFailed('Audio session setup failed: $e'));
      return;
    }
    _subs.add(
      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _signals.add(InterruptionBegan(duck: event.type == AudioInterruptionType.duck));
        } else {
          _signals.add(InterruptionEnded(shouldResume: event.type != AudioInterruptionType.unknown));
        }
      }),
    );
    _subs.add(session.becomingNoisyEventStream.listen((_) => _signals.add(const BecameNoisy())));
  }

  @override
  Stream<BackendSignal> get signals => _signals.stream;

  @override
  Future<void> load(List<PlayableTrack> tracks, {required int index, required Duration offset}) async {
    final sources = [
      for (final t in tracks) AudioSource.uri(t.uri, headers: t.headers.isEmpty ? null : t.headers),
    ];
    await _player.setAudioSources(sources, initialIndex: index, initialPosition: offset);
  }

  @override
  void play() => unawaited(_player.play().catchError((Object e) => _signals.add(BackendFailed('$e'))));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(int index, Duration offset) => _player.seek(offset, index: index);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSkipSilence(bool enabled) async {
    if (Platform.isAndroid) await _player.setSkipSilenceEnabled(enabled);
  }

  @override
  Future<void> setBoost(double decibels) async {
    final enhancer = _enhancer;
    if (enhancer == null) return;
    await enhancer.setEnabled(decibels > 0);
    // The enhancer takes millibels.
    await enhancer.setTargetGain(decibels * 100);
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  int get index => _player.currentIndex ?? 0;

  @override
  Duration get offset => _player.position;

  @override
  bool get playing => _player.playing;

  @override
  BackendState get state => switch (_player.processingState) {
    ProcessingState.idle => BackendState.idle,
    ProcessingState.loading => BackendState.loading,
    ProcessingState.buffering => BackendState.buffering,
    ProcessingState.ready => BackendState.ready,
    ProcessingState.completed => BackendState.completed,
  };
}
