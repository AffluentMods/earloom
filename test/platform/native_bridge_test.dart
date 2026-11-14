// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/media_browser.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/features/player/player_prefs.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:earloom/features/player/sleep_timer.dart';
import 'package:earloom/platform/native_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/player/media_browser_test.dart' show FakeCatalog;
import '../support/fake_player.dart';
import '../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CarPlay, Siri and the Live Activity go through one channel', () async {
    final l10n = await loadL10n();
    final played = <ItemRef>[];
    final engine = PlayerEngine(
      backend: FakeBackend(),
      store: MemoryPlayerStore(),
      resolver: (ref, {startAt}) async {
        played.add(ref);
        return (demoBook(ref, RecordingSink()), StartDecision(startAt ?? Duration.zero));
      },
    );
    await engine.restore();
    var bookmarks = 0;
    final outgoing = <MethodCall>[];
    const channel = MethodChannel(NativeBridge.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      outgoing.add(call);
      return null;
    });
    final bridge = NativeBridge(
      engine: engine,
      browser: MediaBrowser(FakeCatalog(), l10n),
      addBookmark: () async => bookmarks++,
    )..start(liveActivities: true);

    final root = await bridge.handle(const MethodCall('children', {'parent': 'root'})) as List;
    expect((root.first as Map)['title'], l10n.autoContinueListening);
    final books = await bridge.handle(const MethodCall('children', {'parent': 'continue'})) as List;
    final first = books.first as Map;
    expect((first['title'], first['progress'], first['playable']), ("The Clockmaker's Tide", 0.4, true));

    await bridge.handle(MethodCall('play', {'id': first['id']}));
    expect(played.single, const ItemRef(AbsSource('a1'), 'li1'));
    expect(engine.value.playing, isTrue);

    await bridge.handle(const MethodCall('cycleSpeed'));
    expect(engine.value.speed, 1.25);
    await bridge.handle(const MethodCall('bookmark'));
    expect(bookmarks, 1);

    await bridge.handle(const MethodCall('sleep', {'minutes': 20}));
    expect(engine.value.sleep, isA<SleepAfter>());
    await Future<void>.delayed(Duration.zero);
    final show = outgoing.lastWhere((c) => c.method == 'sleepActivityShow');
    expect((show.arguments as Map)['remainingSeconds'], 1200);

    engine.setSleepTimer(const SleepOff());
    await Future<void>.delayed(Duration.zero);
    expect(outgoing.last.method, 'sleepActivityEnd');

    await engine.stop();
    await bridge.dispose();
    await engine.dispose();
  });
}
