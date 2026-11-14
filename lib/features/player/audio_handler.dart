// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../core/ui/cover_image.dart';
import 'player_engine.dart';
import 'player_prefs.dart';

/// Bridges the engine to the lock screen, notification, headset, Bluetooth,
/// watch and car controls. It never plays anything itself.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  AppAudioHandler(this._engine, {this.onBookmark, this.bookmarkLabel = ''}) {
    _sub = _engine.snapshots.listen(_publish);
    _publish(_engine.value);
  }

  final PlayerEngine _engine;

  /// The Android notification's bookmark button.
  final Future<void> Function()? onBookmark;

  /// Spoken by screen readers for that button (from l10n).
  final String bookmarkLabel;
  late final StreamSubscription<PlayerSnapshot> _sub;

  static const bookmarkAction = 'bookmark';

  String? _itemKey;
  bool? _playing;
  bool? _buffering;
  double? _speed;
  bool? _loaded;
  Duration _publishedPosition = Duration.zero;
  DateTime _publishedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _publish(PlayerSnapshot s) {
    final now = s.now;
    if (now == null) {
      if (_itemKey != null) {
        _itemKey = null;
        mediaItem.add(null);
        playbackState.add(PlaybackState());
      }
      return;
    }
    final chapter = s.chapter;
    final multiChapter = now.chapters.length > 1;
    final key = '${now.ref.key}|${chapter?.index}|${now.duration.inSeconds}|${now.coverKey}';
    if (key != _itemKey) {
      _itemKey = key;
      final cover = now.cover;
      mediaItem.add(
        MediaItem(
          id: now.ref.key,
          // Lock screens show the title biggest: the chapter changes while
          // listening, the book title sits under it.
          title: multiChapter && chapter != null ? chapter.title : now.title,
          album: now.title,
          artist: now.author,
          duration: now.duration,
          artUri: now.artworkUri,
          artHeaders: cover is NetworkCover && cover.headers.isNotEmpty ? cover.headers : null,
          displayTitle: multiChapter && chapter != null ? chapter.title : now.title,
          displaySubtitle: now.title,
          displayDescription: now.author,
        ),
      );
    }
    final elapsed = DateTime.now().difference(_publishedAt);
    final expected = _publishedPosition + (_playing ?? false ? elapsed * (_speed ?? 1) : Duration.zero);
    final drift = (s.position - expected).abs();
    if (s.playing == _playing &&
        s.buffering == _buffering &&
        s.speed == _speed &&
        s.loaded == _loaded &&
        drift < const Duration(seconds: 2)) {
      return;
    }
    _playing = s.playing;
    _buffering = s.buffering;
    _speed = s.speed;
    _loaded = s.loaded;
    _publishedPosition = s.position;
    _publishedAt = DateTime.now();
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          if (s.playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward,
          if (onBookmark != null)
            MediaControl(
              androidIcon: 'drawable/ic_bookmark',
              label: bookmarkLabel,
              action: MediaAction.custom,
              customAction: const CustomMediaAction(name: bookmarkAction),
            ),
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.setSpeed,
        },
        processingState: s.buffering
            ? AudioProcessingState.buffering
            : (s.loaded ? AudioProcessingState.ready : AudioProcessingState.idle),
        playing: s.playing,
        updatePosition: s.position,
        bufferedPosition: s.position,
        speed: s.speed,
      ),
    );
  }

  @override
  Future<void> play() => _engine.play();

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> stop() async {
    await _engine.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _engine.seek(position);

  @override
  Future<void> fastForward() => _engine.skipForward();

  @override
  Future<void> rewind() => _engine.skipBack();

  @override
  Future<void> skipToNext() =>
      _engine.prefs.remoteButtons == RemoteButtons.chapters ? _engine.nextChapter() : _engine.skipForward();

  @override
  Future<void> skipToPrevious() =>
      _engine.prefs.remoteButtons == RemoteButtons.chapters ? _engine.previousChapter() : _engine.skipBack();

  @override
  Future<void> setSpeed(double speed) => _engine.setSpeed(speed);

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == bookmarkAction) await onBookmark?.call();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Swiping the app away while paused ends the session; while playing,
    // audio keeps going like any other player.
    if (!_engine.value.playing) await stop();
  }

  Future<void> dispose() => _sub.cancel();
}
