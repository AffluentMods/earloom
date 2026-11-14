// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/player/bookmarks.dart';
import '../features/player/media_browser.dart';
import '../features/player/player_controller.dart';
import '../features/player/player_engine.dart';
import '../features/player/sleep_timer.dart';
import '../features/player/ui/player_widgets.dart';

/// The app side of ios/Runner/EarloomBridge.swift: CarPlay asks for lists
/// and plays, Siri and Shortcuts resume, bookmark and start the sleep
/// timer, and the app shows the sleep timer as a Live Activity.
class NativeBridge {
  NativeBridge({required this.engine, required this.browser, required this.addBookmark, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.affluentlabs.earloom/native';

  final PlayerEngine engine;
  final MediaBrowser browser;
  final Future<void> Function() addBookmark;
  final MethodChannel _channel;
  StreamSubscription<PlayerSnapshot>? _sub;
  ({bool on, bool playing, int minutes})? _shown;

  void start({required bool liveActivities}) {
    _channel.setMethodCallHandler(handle);
    if (liveActivities) _sub = engine.snapshots.listen(_updateSleepActivity);
  }

  /// Calls from native code. Public for tests.
  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'children':
        final parent = args['parent'] as String? ?? 'root';
        final items = await browser.children(parent == 'root' ? AudioService.browsableRootId : parent);
        return [for (final m in items) _toMap(m)];
      case 'play':
        final ref = MediaBrowser.refOf(args['id'] as String? ?? '');
        if (ref != null) await engine.playItem(ref);
        return null;
      case 'resume':
        await engine.play();
        return null;
      case 'bookmark':
        await addBookmark();
        return null;
      case 'sleep':
        final minutes = (args['minutes'] as num?)?.toInt() ?? 30;
        final d = Duration(minutes: minutes.clamp(1, 240));
        engine.setSleepTimer(SleepAfter(original: d, remaining: d));
        if (!engine.value.playing) await engine.play();
        return null;
      case 'cycleSpeed':
        const cycle = [1.0, 1.25, 1.5, 2.0];
        final now = engine.value.speed;
        await engine.setSpeed(cycle.firstWhere((v) => v > now + 0.001, orElse: () => cycle.first));
        return null;
    }
    throw MissingPluginException(call.method);
  }

  static Map<String, Object?> _toMap(MediaItem m) => {
    'id': m.id,
    'title': m.title,
    'subtitle': m.artist,
    'art': m.artUri?.toString(),
    'playable': m.playable ?? false,
    'progress': m.extras?['androidx.media.MediaItem.Extras.COMPLETION_PERCENTAGE'],
  };

  /// Shows the sleep timer on the lock screen while it runs, updating only
  /// when what it shows changes (on, playing, minutes left).
  void _updateSleepActivity(PlayerSnapshot s) {
    final left = s.sleepRemaining;
    final on = s.sleep is! SleepOff && left != null && s.hasBook;
    final next = (on: on, playing: s.playing, minutes: left == null ? 0 : (left.inSeconds / 60).ceil());
    final last = _shown;
    if (last != null && last == next) return;
    _shown = next;
    if (!on) {
      if (last?.on ?? false) unawaited(_invoke('sleepActivityEnd'));
      return;
    }
    unawaited(
      _invoke('sleepActivityShow', {
        'title': s.now?.title ?? '',
        'remainingSeconds': left.inSeconds,
        'paused': !s.playing,
      }),
    );
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on Object {
      // No Live Activities here (older iOS, turned off): nothing to show.
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _channel.setMethodCallHandler(null);
  }
}

final nativeBridgeProvider = Provider<void>((ref) {
  if (!Platform.isIOS) return;
  final engine = ref.watch(playerEngineProvider);
  final l10n = deviceL10n();
  final bridge = NativeBridge(
    engine: engine,
    browser: ref.watch(mediaBrowserProvider),
    addBookmark: () async {
      final s = engine.value;
      final now = s.now;
      if (now == null) return;
      final chapter = s.chapter;
      final title = chapter == null
          ? formatClock(s.position)
          : l10n.bookmarkDefaultTitle(chapter.title, formatClock(s.position - chapter.start));
      await ref.read(bookmarkServiceProvider).add(now.ref, s.position, title);
    },
  )..start(liveActivities: true);
  ref.onDispose(bridge.dispose);
});
