// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../core/ui/cover_image.dart';
import 'media_browser.dart';
import 'player_engine.dart';
import 'player_prefs.dart';

/// Bridges the engine to the lock screen, notification, headset, Bluetooth,
/// watch and car controls. It never plays anything itself.
class AppAudioHandler extends BaseAudioHandler with SeekHandler {
  AppAudioHandler(
    this._engine, {
    this.onBookmark,
    this.bookmarkLabel = '',
    this.speedLabel = '',
    this.sleepLabel,
    this.browser,
  }) {
    _sub = _engine.snapshots.listen(_publish);
    _publish(_engine.value);
  }

  final PlayerEngine _engine;

  /// Android Auto and other media browsers.
  final MediaBrowser? browser;

  /// The Android notification's bookmark button.
  final Future<void> Function()? onBookmark;

  /// Spoken by screen readers for that button (from l10n).
  final String bookmarkLabel;

  /// The speed button's label (from l10n).
  final String speedLabel;

  /// "Sleep in 12 min" for the notification subtitle (from l10n).
  final String Function(int minutes)? sleepLabel;

  static const speedAction = 'speed';
  static const speedCycle = [1.0, 1.25, 1.5, 2.0];
  late final StreamSubscription<PlayerSnapshot> _sub;

  static const bookmarkAction = 'bookmark';

  String? _itemKey;
  bool? _playing;
  bool? _buffering;
  double? _speed;
  bool? _loaded;
  Duration? _publishedScope;
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
    final sleepLeft = s.sleepRemaining;
    // Whole minutes, so the notification changes once a minute, not 4 times
    // a second.
    final sleepMinutes = sleepLeft == null ? null : (sleepLeft.inSeconds / 60).ceil();
    final chapterScope = _engine.prefs.lockScreenChapter && multiChapter && chapter != null;
    final key =
        '${now.ref.key}|${chapter?.index}|${now.duration.inSeconds}|${now.coverKey}|$sleepMinutes|$chapterScope';
    if (key != _itemKey) {
      _itemKey = key;
      final cover = now.cover;
      mediaItem.add(
        MediaItem(
          id: now.ref.key,
          // Lock screens show the title biggest: the chapter changes while
          // listening, the book title sits under it.
          title: multiChapter && chapter != null ? chapter.title : now.title,
          // An episode's album is its show.
          album: now.ref.episodeId != null ? now.author ?? now.title : now.title,
          artist: now.author,
          duration: chapterScope ? chapter.duration : now.duration,
          artUri: now.artworkUri,
          artHeaders: cover is NetworkCover && cover.headers.isNotEmpty ? cover.headers : null,
          displayTitle: multiChapter && chapter != null ? chapter.title : now.title,
          displaySubtitle: sleepMinutes == null ? now.title : sleepLabel?.call(sleepMinutes) ?? now.title,
          displayDescription: now.author,
        ),
      );
    }
    final elapsed = DateTime.now().difference(_publishedAt);
    final expected = _publishedPosition + (_playing ?? false ? elapsed * (_speed ?? 1) : Duration.zero);
    final drift = (s.position - expected).abs();
    final scopeStart = _scopeStart(s);
    if (scopeStart == _publishedScope &&
        s.playing == _playing &&
        s.buffering == _buffering &&
        s.speed == _speed &&
        s.loaded == _loaded &&
        drift < const Duration(seconds: 2)) {
      return;
    }
    _publishedScope = scopeStart;
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
          MediaControl(
            androidIcon: 'drawable/ic_speed',
            label: speedLabel,
            action: MediaAction.custom,
            customAction: const CustomMediaAction(name: speedAction),
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
        updatePosition: s.position - _scopeStart(s),
        bufferedPosition: s.position - _scopeStart(s),
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
  Future<void> seek(Duration position) => _engine.seek(position + _scopeStart(_engine.value));

  /// Where the lock screen's bar starts: the chapter start when it shows
  /// chapter progress, else the start of the book.
  Duration _scopeStart(PlayerSnapshot s) {
    final chapter = s.chapter;
    final many = (s.now?.chapters.length ?? 0) > 1;
    return _engine.prefs.lockScreenChapter && many && chapter != null ? chapter.start : Duration.zero;
  }

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
    if (name == speedAction) {
      final current = _engine.value.speed;
      final next = speedCycle.firstWhere((v) => v > current + 0.001, orElse: () => speedCycle.first);
      await _engine.setSpeed(next);
    }
  }

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async =>
      await browser?.children(parentMediaId) ?? const [];

  @override
  Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async =>
      await browser?.search(query) ?? const [];

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final ref = MediaBrowser.refOf(mediaId);
    if (ref != null) await _engine.playItem(ref);
  }

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) async {
    // "Play" with no title: resume what was playing.
    if (query.trim().isEmpty) return _engine.play();
    final hits = await browser?.search(query) ?? const [];
    final ref = hits.isEmpty ? null : MediaBrowser.refOf(hits.first.id);
    if (ref != null) await _engine.playItem(ref);
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<void> onTaskRemoved() async {
    // Swiping the app away while paused ends the session; while playing,
    // audio keeps going like any other player.
    if (!_engine.value.playing) await stop();
  }

  Future<void> dispose() => _sub.cancel();
}
