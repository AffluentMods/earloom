// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/features/player/player_prefs.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_player.dart';

const _source = AbsSource('acct');
const _pilot = ItemRef(_source, 'show-1', episodeId: 'ep-1');
const _next = ItemRef(_source, 'show-1', episodeId: 'ep-2');
const _otherShow = ItemRef(_source, 'show-2', episodeId: 'ep-9');
const _book = ItemRef(_source, 'book-1');

/// Show speeds and the next episode, in memory.
class FakeEpisodeHooks implements EpisodeHooks {
  final showSpeeds = <String, double>{};
  QueueEntry? next;
  final asked = <ItemRef>[];

  @override
  Future<double?> showSpeed(ItemRef episode) async => showSpeeds[episode.itemId];

  @override
  Future<void> saveShowSpeed(ItemRef episode, double speed) async => showSpeeds[episode.itemId] = speed;

  @override
  Future<QueueEntry?> nextEpisode(ItemRef finished) async {
    asked.add(finished);
    return next;
  }
}

void podcastTest(
  String name,
  Future<void> Function(PlayerEngine engine, MemoryPlayerStore store, FakeEpisodeHooks hooks) body, {
  PlayerPrefs prefs = const PlayerPrefs(),
}) {
  test(name, () {
    fakeAsync((async) {
      final clock = async.getClock(DateTime(2026, 11, 14, 21));
      final backend = FakeBackend(now: clock.now);
      final store = MemoryPlayerStore()..prefs = prefs;
      final hooks = FakeEpisodeHooks();
      final engine = PlayerEngine(
        backend: backend,
        store: store,
        now: clock.now,
        resolver: (ref, {startAt}) async => (demoBook(ref, RecordingSink()), at(startAt ?? Duration.zero)),
      )..episodes = hooks;
      var done = false;
      Object? error;
      StackTrace? trace;
      unawaited(
        () async {
          await engine.restore();
          await body(engine, store, hooks);
        }().then(
          (_) => done = true,
          onError: (Object e, StackTrace s) {
            error = e;
            trace = s;
            done = true;
          },
        ),
      );
      for (var i = 0; i < 100000 && !done; i++) {
        async.elapse(const Duration(milliseconds: 200));
      }
      if (error != null) Error.throwWithStackTrace(error!, trace!);
      expect(done, isTrue, reason: 'test body never finished');
      unawaited(engine.dispose());
      async.flushMicrotasks();
    });
  });
}

Future<void> wait(Duration d) => Future<void>.delayed(d);

void main() {
  podcastTest('episodes start at the podcast default, books at theirs', (engine, store, hooks) async {
    await engine.playItem(_pilot);
    expect(engine.value.speed, 1.5);
    await engine.playItem(_book);
    expect(engine.value.speed, 1.0);
  }, prefs: const PlayerPrefs(podcastSpeed: 1.5));

  podcastTest('a show speed overrides the podcast default, for every episode of that show', (
    engine,
    store,
    hooks,
  ) async {
    hooks.showSpeeds['show-1'] = 1.2;
    await engine.playItem(_pilot);
    expect(engine.value.speed, 1.2);
    await engine.playItem(_otherShow);
    expect(engine.value.speed, 1.5);
  }, prefs: const PlayerPrefs(podcastSpeed: 1.5));

  podcastTest('changing speed during an episode is remembered for its show', (engine, store, hooks) async {
    await engine.playItem(_pilot);
    await engine.setSpeed(1.75);
    expect(hooks.showSpeeds['show-1'], 1.75);
    expect(store.speeds, isEmpty, reason: 'not per episode');
    await engine.playItem(_next);
    expect(engine.value.speed, 1.75);
  });

  podcastTest('without per-book speeds, a change during an episode sets the podcast default', (
    engine,
    store,
    hooks,
  ) async {
    await engine.playItem(_pilot);
    await engine.setSpeed(1.25);
    expect(hooks.showSpeeds, isEmpty);
    expect(store.prefs.podcastSpeed, 1.25);
    expect(store.prefs.defaultSpeed, 1.0, reason: 'books keep theirs');
  }, prefs: const PlayerPrefs(speedPerBook: false));

  podcastTest('a finished episode plays the next unplayed one when Up next is empty', (engine, store, hooks) async {
    hooks.next = QueueEntry.of(_next, title: 'Episode 2');
    await engine.playItem(_pilot, startAt: const Duration(minutes: 59, seconds: 50));
    await wait(const Duration(seconds: 15));
    expect(hooks.asked, [_pilot]);
    expect(engine.value.now?.ref, _next);
    expect(engine.value.playing, isTrue);
  });

  podcastTest('Up next comes before the next episode', (engine, store, hooks) async {
    hooks.next = QueueEntry.of(_next, title: 'Episode 2');
    await engine.addToQueue(QueueEntry.of(_book, title: 'A book'));
    await engine.playItem(_pilot, startAt: const Duration(minutes: 59, seconds: 50));
    await wait(const Duration(seconds: 15));
    expect(engine.value.now?.ref, _book);
    expect(hooks.asked, isEmpty);
  });

  podcastTest('with the setting off, a finished episode stops', (engine, store, hooks) async {
    hooks.next = QueueEntry.of(_next, title: 'Episode 2');
    await engine.playItem(_pilot, startAt: const Duration(minutes: 59, seconds: 50));
    await wait(const Duration(seconds: 15));
    expect(engine.value.now?.ref, _pilot);
    expect(engine.value.playing, isFalse);
    expect(hooks.asked, isEmpty);
  }, prefs: const PlayerPrefs(podcastAutoNext: false));

  podcastTest('a finished book never asks for an episode', (engine, store, hooks) async {
    hooks.next = QueueEntry.of(_next, title: 'Episode 2');
    await engine.playItem(_book, startAt: const Duration(minutes: 59, seconds: 50));
    await wait(const Duration(seconds: 15));
    expect(hooks.asked, isEmpty);
    expect(engine.value.now?.ref, _book);
  });

  test('podcast settings survive a round trip and broken values fall back', () {
    const prefs = PlayerPrefs(podcastSpeed: 1.3, podcastAutoNext: false);
    final back = PlayerPrefs.fromJson(prefs.toJson());
    expect(back.podcastSpeed, 1.3);
    expect(back.podcastAutoNext, isFalse);
    final broken = PlayerPrefs.fromJson({'podcastSpeed': 'fast', 'podcastAutoNext': 3});
    expect(broken.podcastSpeed, 1.0);
    expect(broken.podcastAutoNext, isTrue);
  });
}
