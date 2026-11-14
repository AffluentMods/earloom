// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/audio_backend.dart';
import 'package:earloom/features/player/playable.dart';
import 'package:earloom/features/player/progress_resolver.dart';

/// A backend whose audio advances with (fake) time. Also the silent
/// player every widget test gets (see `pumpEarloom`).
class FakeBackend implements AudioBackend {
  FakeBackend({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;
  final _signals = StreamController<BackendSignal>.broadcast();
  List<PlayableTrack> tracks = [];
  int _index = 0;
  Duration _base = Duration.zero;
  DateTime? _since;
  double speed = 1;
  double volume = 1;
  bool _playing = false;
  BackendState _state = BackendState.idle;
  Timer? _timer;
  int loads = 0;
  Object? failNextLoad;

  void emit(BackendSignal signal) => _signals.add(signal);

  @override
  Stream<BackendSignal> get signals => _signals.stream;

  void _settle() {
    final since = _since;
    if (!_playing || since == null) return;
    var offset = _base + now().difference(since) * speed;
    _since = now();
    while (offset >= tracks[_index].duration) {
      offset -= tracks[_index].duration;
      if (_index == tracks.length - 1) {
        _base = tracks[_index].duration;
        _playing = false;
        _state = BackendState.completed;
        _timer?.cancel();
        emit(const BackendChanged());
        return;
      }
      _index++;
    }
    _base = offset;
  }

  @override
  Future<void> load(List<PlayableTrack> tracks, {required int index, required Duration offset}) async {
    loads++;
    final fail = failNextLoad;
    if (fail != null) {
      failNextLoad = null;
      throw fail;
    }
    this.tracks = tracks;
    _index = index;
    _base = offset;
    _state = BackendState.ready;
  }

  @override
  void play() {
    _playing = true;
    _since = now();
    _timer ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _settle());
    emit(const BackendChanged());
  }

  @override
  Future<void> pause() async {
    _settle();
    _playing = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> seek(int index, Duration offset) async {
    _index = index;
    _base = offset;
    _since = now();
    if (_state == BackendState.completed) _state = BackendState.ready;
  }

  @override
  Future<void> setSpeed(double speed) async {
    _settle();
    this.speed = speed;
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;
  @override
  Future<void> setSkipSilence(bool enabled) async {}
  @override
  Future<void> setBoost(double decibels) async {}

  @override
  Future<void> stop() async {
    await pause();
    _state = BackendState.idle;
  }

  @override
  int get index {
    _settle();
    return _index;
  }

  @override
  Duration get offset {
    _settle();
    return _base;
  }

  @override
  bool get playing => _playing;

  @override
  BackendState get state => _state;
}

/// Records what the player reports.
class RecordingSink implements ProgressSink {
  final reports = <({Duration position, Duration listened, bool isPlaying})>[];
  Duration? finishedAt;
  Duration? closedAt;

  Duration get totalListened => reports.fold(Duration.zero, (sum, r) => sum + r.listened);

  @override
  Future<void> report({required Duration position, required Duration listened, required bool isPlaying}) async =>
      reports.add((position: position, listened: listened, isPlaying: isPlaying));

  @override
  Future<void> finished({required Duration position}) async => finishedAt = position;

  @override
  Future<void> close({required Duration position}) async => closedAt = position;
}

/// A three-track book: 10 min, 20 min, 30 min, three chapters per track.
PlayableBook demoBook(ItemRef ref, RecordingSink sink, {Duration start = Duration.zero}) {
  const minutes = [10, 20, 30];
  var at = Duration.zero;
  final tracks = <PlayableTrack>[];
  for (var i = 0; i < minutes.length; i++) {
    final d = Duration(minutes: minutes[i]);
    tracks.add(PlayableTrack(uri: Uri.parse('file:///book/track_$i.mp3'), start: at, duration: d));
    at += d;
  }
  return PlayableBook(ref: ref, title: 'The Clockmaker\'s Tide', author: 'Mara Ellison', tracks: tracks, sink: sink);
}

StartDecision at(Duration d) => StartDecision(d);
