// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:audio_service/audio_service.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/audio_handler.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/features/player/player_prefs.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:earloom/features/player/sleep_timer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player.dart';

const _ref = ItemRef(LocalSource(), 'b1');

Future<(PlayerEngine, AppAudioHandler, MemoryPlayerStore)> _setUp({PlayerPrefs prefs = const PlayerPrefs()}) async {
  final store = MemoryPlayerStore()..prefs = prefs;
  final engine = PlayerEngine(
    backend: FakeBackend(),
    store: store,
    resolver: (ref, {startAt}) async => (demoBook(ref, RecordingSink()), StartDecision(startAt ?? Duration.zero)),
    chapterNames: ChapterNames(forTrack: (n) => 'Part $n', wholeBook: 'Whole'),
  );
  await engine.restore();
  final handler = AppAudioHandler(engine, speedLabel: 'Speed', sleepLabel: (m) => 'Sleep in $m min');
  return (engine, handler, store);
}

void main() {
  test('the lock screen shows the chapter as title, the book as album, and the whole book by default', () async {
    final (engine, handler, _) = await _setUp();
    await engine.playItem(_ref, startAt: const Duration(minutes: 12), autoplay: false);
    await Future<void>.delayed(Duration.zero);
    final item = handler.mediaItem.value!;
    expect((item.title, item.album, item.artist), ('Part 2', "The Clockmaker's Tide", 'Mara Ellison'));
    expect(item.duration, const Duration(hours: 1));
    expect(handler.playbackState.value.updatePosition, const Duration(minutes: 12));
    await engine.dispose();
  });

  test('chapter progress on the lock screen maps seeks back to the book', () async {
    final (engine, handler, _) = await _setUp(prefs: const PlayerPrefs(lockScreenChapter: true));
    await engine.playItem(_ref, startAt: const Duration(minutes: 12), autoplay: false);
    await Future<void>.delayed(Duration.zero);
    expect(handler.mediaItem.value!.duration, const Duration(minutes: 20), reason: 'the second file');
    expect(handler.playbackState.value.updatePosition, const Duration(minutes: 2));
    await handler.seek(const Duration(minutes: 5));
    expect(engine.value.position, const Duration(minutes: 15));
    await engine.dispose();
  });

  test('the notification speed button cycles common speeds', () async {
    final (engine, handler, _) = await _setUp();
    await engine.playItem(_ref, autoplay: false);
    for (final expected in [1.25, 1.5, 2.0, 1.0]) {
      await handler.customAction(AppAudioHandler.speedAction);
      expect(engine.value.speed, expected);
    }
    await engine.dispose();
  });

  // On Android a headset or car pause key reaches pause(), a play key play()
  // (third_party/audio_service patch); only the toggle keys reach click().
  test('a pause key while paused leaves the book paused where it was', () async {
    final (engine, handler, _) = await _setUp();
    await engine.playItem(_ref, startAt: const Duration(minutes: 12));
    await handler.pause();
    final at = engine.value.position;
    await handler.pause();
    await Future<void>.delayed(Duration.zero);
    expect(engine.value.playing, isFalse);
    expect(engine.value.position, at);
    expect(handler.playbackState.value.playing, isFalse);
    await engine.dispose();
  });

  test('a play key while playing changes nothing', () async {
    // All day is bedtime here, so pressing play would start a sleep timer.
    final (engine, handler, _) = await _setUp(
      prefs: const PlayerPrefs(autoSleep: true, autoSleepFrom: 0, autoSleepUntil: 24 * 60),
    );
    await engine.playItem(_ref, startAt: const Duration(minutes: 12));
    engine.setSleepTimer(const SleepOff());
    // In the last second, play starts the book over.
    await engine.seek(const Duration(minutes: 59, seconds: 59, milliseconds: 300));
    await handler.play();
    expect(engine.value.playing, isTrue);
    expect(engine.value.sleep, isA<SleepOff>());
    expect(engine.value.position, greaterThan(const Duration(minutes: 59)));
    await engine.dispose();
  });

  test('the headset toggle button still plays and pauses', () async {
    final (engine, handler, _) = await _setUp();
    await engine.playItem(_ref, startAt: const Duration(minutes: 12), autoplay: false);
    await Future<void>.delayed(Duration.zero);
    await handler.click();
    await Future<void>.delayed(Duration.zero);
    expect(engine.value.playing, isTrue);
    await handler.click();
    await Future<void>.delayed(Duration.zero);
    expect(engine.value.playing, isFalse);
    await engine.dispose();
  });

  test('headset next and previous skip by default, or move by chapter', () async {
    final (engine, handler, store) = await _setUp();
    await engine.playItem(_ref, startAt: const Duration(minutes: 12), autoplay: false);
    await handler.skipToNext();
    expect(engine.value.position, const Duration(minutes: 12, seconds: 30));
    await engine.updatePrefs(store.prefs.copyWith(remoteButtons: RemoteButtons.chapters));
    await handler.skipToNext();
    expect(engine.value.position, const Duration(minutes: 30));
    expect(handler.playbackState.value.processingState, AudioProcessingState.ready);
    await engine.dispose();
  });
}
