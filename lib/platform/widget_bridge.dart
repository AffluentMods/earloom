// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../core/ui/cover_image.dart';
import '../features/player/player_controller.dart';
import '../features/player/player_engine.dart';

/// What the home screen widget shows, in plain values.
final class WidgetSnapshot {
  const WidgetSnapshot({
    required this.hasBook,
    this.title = '',
    this.subtitle = '',
    this.coverPath,
    this.progress = 0,
    this.playing = false,
  });

  final bool hasBook;
  final String title;
  final String subtitle;
  final String? coverPath;

  /// Per mille of the book.
  final int progress;
  final bool playing;

  static WidgetSnapshot of(PlayerSnapshot s, {required String idleTitle, String? coverPath}) {
    final now = s.now;
    if (now == null) return WidgetSnapshot(hasBook: false, title: idleTitle);
    final chapter = s.chapter;
    final d = s.duration.inMilliseconds;
    return WidgetSnapshot(
      hasBook: true,
      title: now.title,
      subtitle: (chapter != null && now.chapters.length > 1) ? chapter.title : (now.author ?? ''),
      coverPath: coverPath,
      progress: d <= 0 ? 0 : (s.position.inMilliseconds * 1000 ~/ d).clamp(0, 1000),
      playing: s.playing,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot &&
      other.hasBook == hasBook &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.coverPath == coverPath &&
      other.progress == progress &&
      other.playing == playing;

  @override
  int get hashCode => Object.hash(hasBook, title, subtitle, coverPath, progress, playing);
}

/// Writes the widget's data from the main isolate, only when something the
/// widget shows changes (progress at most once a minute). Widgets never
/// talk to a server (docs/plan/07-phase6-system-integration.md 6.4).
class WidgetBridge {
  WidgetBridge({required this.labels, Future<void> Function(Map<String, Object?> data)? write})
    : _write = write ?? _writeHomeWidget;

  /// Screen reader labels and the idle title, from l10n.
  final ({String play, String pause, String back, String idle}) labels;
  final Future<void> Function(Map<String, Object?> data) _write;
  WidgetSnapshot? _last;
  DateTime _lastProgressWrite = DateTime.fromMillisecondsSinceEpoch(0);
  String? _coverFor;
  String? _coverPath;

  static Future<void> _writeHomeWidget(Map<String, Object?> data) async {
    if (!Platform.isAndroid) return;
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData<Object>(e.key, e.value, deleteFile: false);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: 'com.affluentlabs.earloom.widget.NowPlayingWidget');
  }

  Future<String?> _cover(NowPlaying now) async {
    final key = now.coverKey ?? now.ref.key;
    if (key == _coverFor) return _coverPath;
    _coverFor = key;
    final cover = now.cover;
    _coverPath = switch (cover) {
      FileCover(:final path) => path,
      NetworkCover(:final itemCoverUrl, :final headers) => await _download(itemCoverUrl, headers),
      null => null,
    };
    return _coverPath;
  }

  static Future<String?> _download(Uri url, Map<String, String> headers) async {
    try {
      final file = await CachedNetworkImageProvider.defaultCacheManager.getSingleFile(
        url.replace(queryParameters: {'width': '256', 'format': 'jpeg'}).toString(),
        headers: headers,
      );
      return file.path;
    } on Object {
      return null;
    }
  }

  Future<void> update(PlayerSnapshot s) async {
    final now = s.now;
    final coverPath = now == null ? null : await _cover(now);
    final next = WidgetSnapshot.of(s, idleTitle: labels.idle, coverPath: coverPath);
    final last = _last;
    if (next == last) return;
    final onlyProgress =
        last != null &&
        last.hasBook == next.hasBook &&
        last.title == next.title &&
        last.subtitle == next.subtitle &&
        last.coverPath == next.coverPath &&
        last.playing == next.playing;
    if (onlyProgress && DateTime.now().difference(_lastProgressWrite) < const Duration(minutes: 1)) return;
    _last = next;
    _lastProgressWrite = DateTime.now();
    await _write({
      'np.hasBook': next.hasBook,
      'np.title': next.title,
      'np.subtitle': next.subtitle,
      'np.cover': next.coverPath,
      'np.progress': next.progress,
      'np.playing': next.playing,
      'l.play': labels.play,
      'l.pause': labels.pause,
      'l.back': labels.back,
    });
  }
}

final widgetBridgeProvider = Provider<void>((ref) {
  final l10n = deviceL10n();
  final engine = ref.watch(playerEngineProvider);
  final prefs = engine.prefs;
  final bridge = WidgetBridge(
    labels: (
      play: l10n.playerPlay,
      pause: l10n.playerPause,
      back: l10n.playerSkipBack(prefs.skipBack.inSeconds),
      idle: l10n.appName,
    ),
  );
  var busy = false;
  PlayerSnapshot? pending;
  Future<void> push(PlayerSnapshot s) async {
    if (busy) {
      pending = s;
      return;
    }
    busy = true;
    try {
      await bridge.update(s);
    } on Object {
      // A launcher without widget support: nothing to update.
    } finally {
      busy = false;
      final p = pending;
      pending = null;
      if (p != null) unawaited(push(p));
    }
  }

  unawaited(push(engine.value));
  final sub = engine.snapshots.listen((s) => unawaited(push(s)));
  ref.onDispose(sub.cancel);
});
