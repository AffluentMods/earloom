// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/audio_backend.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/features/player/player_prefs.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:earloom/features/player/sleep_timer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

const _local = ItemRef(LocalSource(), 'b1');
const _other = ItemRef(LocalSource(), 'b2');
const _server = ItemRef(AbsSource('acct'), 'li1');

/// Runs [body] in fake time with a fresh engine.
void engineTest(
  String name,
  Future<void> Function(FakeAsync async, PlayerEngine engine, FakeBackend backend, Map<String, RecordingSink> sinks)
  body, {
  PlayerPrefs prefs = const PlayerPrefs(),
}) {
  test(name, () {
    fakeAsync((async) {
      final clock = async.getClock(DateTime(2026, 11, 14, 21));
      final backend = FakeBackend(now: clock.now);
      final store = MemoryPlayerStore()..prefs = prefs;
      final sinks = <String, RecordingSink>{};
      final engine = PlayerEngine(
        backend: backend,
        store: store,
        now: clock.now,
        resolver: (ref, {startAt}) async {
          final sink = sinks.putIfAbsent(ref.key, RecordingSink.new);
          return (demoBook(ref, sink), at(startAt ?? Duration.zero));
        },
      );
      var done = false;
      Object? error;
      StackTrace? trace;
      unawaited(
        () async {
          await engine.restore();
          await body(async, engine, backend, sinks);
        }().then(
          (_) => done = true,
          onError: (Object e, StackTrace s) {
            error = e;
            trace = s;
            done = true;
          },
        ),
      );
      for (var i = 0; i < 1000000 && !done; i++) {
        async.elapse(const Duration(milliseconds: 200));
      }
      if (error != null) Error.throwWithStackTrace(error!, trace!);
      expect(done, isTrue, reason: 'test body never finished');
      unawaited(engine.dispose());
      async.flushMicrotasks();
    });
  });
}

/// Lets fake time pass inside a test body.
Future<void> wait(Duration d) => Future<void>.delayed(d);

void main() {
  engineTest('plays across track boundaries and keeps whole-book positions', (async, engine, backend, sinks) async {
    await engine.playItem(_local, startAt: const Duration(minutes: 9, seconds: 50));
    expect(engine.value.playing, isTrue);
    await wait(const Duration(seconds: 20));
    expect(backend.index, 1, reason: 'moved into the second file');
    expect(
      engine.value.position.inSeconds,
      closeTo(const Duration(minutes: 10, seconds: 10).inSeconds, 1),
    );
    expect(engine.value.chapter?.index, 1);
  });

  engineTest('listening time is real time, not book time, at 2x', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    await engine.setSpeed(2);
    await wait(const Duration(minutes: 10));
    await engine.pause();
    final sink = sinks[_local.key]!;
    expect(sink.totalListened.inSeconds, closeTo(600, 2));
    expect(engine.value.position.inSeconds, closeTo(1200, 2));
  });

  engineTest('reports about every 15 seconds while playing, and on pause', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    await wait(const Duration(seconds: 61));
    final sink = sinks[_local.key]!;
    expect(sink.reports.length, inInclusiveRange(4, 5));
    await engine.pause();
    expect(sink.reports.last.isPlaying, isFalse);
  });

  engineTest('previous chapter: restart within, go back in the first 3 seconds', (async, engine, backend, sinks) async {
    await engine.playItem(_local, startAt: const Duration(minutes: 15), autoplay: false);
    await engine.previousChapter();
    expect(engine.value.position, const Duration(minutes: 10));
    await engine.previousChapter();
    expect(engine.value.position, Duration.zero);
    await engine.nextChapter();
    expect(engine.value.position, const Duration(minutes: 10));
  });

  engineTest('smart rewind after a long pause, never before zero', (async, engine, backend, sinks) async {
    await engine.playItem(_local, startAt: const Duration(seconds: 100));
    await engine.pause();
    final before = engine.value.position;
    await wait(const Duration(minutes: 10));
    await engine.play();
    expect(engine.value.position, before - const Duration(seconds: 15));

    await engine.seek(const Duration(seconds: 3));
    await engine.pause();
    await wait(const Duration(hours: 2));
    await engine.play();
    expect(engine.value.position, Duration.zero);
  });

  engineTest('sleep timer fades, pauses and rewinds by the fade', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    engine.setSleepTimer(const SleepAfter(original: Duration(minutes: 5), remaining: Duration(minutes: 5)));
    await wait(const Duration(minutes: 4, seconds: 45));
    expect(backend.volume, lessThan(1));
    expect(engine.value.playing, isTrue);
    await wait(const Duration(seconds: 20));
    expect(engine.value.playing, isFalse);
    expect(engine.value.sleep, isA<SleepOff>());
    expect(backend.volume, 1);
    expect(engine.value.position.inSeconds, closeTo(300 - 30, 2));
  });

  engineTest('the sleep countdown stops while paused', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    engine.setSleepTimer(const SleepAfter(original: Duration(minutes: 5), remaining: Duration(minutes: 5)));
    await wait(const Duration(minutes: 1));
    await engine.pause();
    await wait(const Duration(minutes: 30));
    expect(engine.value.sleepRemaining!.inSeconds, closeTo(240, 2));
  });

  engineTest('end of chapter respects a speed change made afterwards', (async, engine, backend, sinks) async {
    await engine.playItem(_local, startAt: const Duration(minutes: 8));
    engine.setSleepTimer(const SleepAtChapterEnd(0));
    await engine.setSpeed(2);
    await wait(const Duration(seconds: 61));
    expect(engine.value.playing, isFalse);
    expect(engine.value.position.inSeconds, closeTo(600 - 30, 3));
  });

  engineTest('a shake in the last minute extends by the original duration', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    engine.setSleepTimer(const SleepAfter(original: Duration(minutes: 5), remaining: Duration(minutes: 5)));
    expect(engine.sleepEndingSoon, isFalse);
    await wait(const Duration(minutes: 4, seconds: 30));
    expect(engine.sleepEndingSoon, isTrue);
    engine.extendSleepTimer();
    expect(engine.value.sleepRemaining!.inSeconds, closeTo(330, 2));
    expect(backend.volume, 1);
  });

  engineTest('a short interruption resumes, a long one does not', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    backend.emit(const InterruptionBegan(duck: false));
    await wait(const Duration(seconds: 30));
    expect(engine.value.playing, isFalse);
    backend.emit(const InterruptionEnded(shouldResume: true));
    await wait(const Duration(milliseconds: 100));
    expect(engine.value.playing, isTrue);

    backend.emit(const InterruptionBegan(duck: false));
    await wait(const Duration(minutes: 3));
    backend.emit(const InterruptionEnded(shouldResume: true));
    await wait(const Duration(milliseconds: 100));
    expect(engine.value.playing, isFalse);
  });

  engineTest('unplugging headphones pauses', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    backend.emit(const BecameNoisy());
    await wait(const Duration(milliseconds: 100));
    expect(engine.value.playing, isFalse);
  });

  engineTest('a finished book is reported and the queue moves on', (async, engine, backend, sinks) async {
    await engine.addToQueue(_other);
    await engine.playItem(_local, startAt: const Duration(minutes: 59, seconds: 50));
    await wait(const Duration(seconds: 15));
    expect(sinks[_local.key]!.finishedAt, const Duration(hours: 1));
    expect(sinks[_local.key]!.closedAt, isNotNull);
    expect(engine.value.now?.ref, _other);
    expect(engine.value.playing, isTrue);
    expect(engine.value.queue, isEmpty);
  });

  engineTest('sleep at end of book stops even with a queue', (async, engine, backend, sinks) async {
    await engine.addToQueue(_other);
    await engine.playItem(_local, startAt: const Duration(minutes: 59, seconds: 50));
    engine.setSleepTimer(const SleepAtBookEnd());
    await wait(const Duration(seconds: 15));
    expect(engine.value.now?.ref, _local);
    expect(engine.value.playing, isFalse);
    expect(engine.value.queue, [_other]);
  });

  engineTest('switching books closes the first one', (async, engine, backend, sinks) async {
    await engine.playItem(_local);
    await wait(const Duration(seconds: 5));
    await engine.playItem(_other);
    expect(sinks[_local.key]!.closedAt!.inSeconds, closeTo(5, 1));
    expect(engine.value.now?.ref, _other);
  });

  engineTest('remote progress: applied when paused, offered when playing', (async, engine, backend, sinks) async {
    await engine.playItem(_local, startAt: const Duration(minutes: 1));
    final offers = <PlayerNotice>[];
    engine.notices.listen(offers.add);
    await wait(const Duration(seconds: 20));
    await engine.applyRemote(_local, PositionStamp(const Duration(minutes: 30), DateTime(2026, 11, 14, 22)));
    await wait(Duration.zero);
    expect(offers.single, isA<RemoteJumpOffered>());
    expect(engine.value.position.inMinutes, 1);

    await engine.pause();
    await engine.applyRemote(_local, PositionStamp(const Duration(minutes: 30), DateTime(2026, 11, 14, 22)));
    expect(engine.value.position, const Duration(minutes: 30));
  });

  engineTest('a server stream that fails is reopened where it was', (async, engine, backend, sinks) async {
    await engine.playItem(_server, startAt: const Duration(minutes: 5));
    await wait(const Duration(seconds: 10));
    final loads = backend.loads;
    backend.emit(const BackendFailed('404 session gone'));
    await wait(const Duration(seconds: 1));
    expect(backend.loads, loads + 1);
    expect(engine.value.playing, isTrue);
    expect(engine.value.position.inSeconds, closeTo(310, 2));
  });

  engineTest('restore shows the last book paused and loads it on play', (async, engine, backend, sinks) async {
    await engine.playItem(_local, startAt: const Duration(minutes: 12));
    await engine.pause();
    final store = MemoryPlayerStore()..last = (await _lastOf(engine));
    final fresh = PlayerEngine(
      backend: backend,
      store: store,
      resolver: (ref, {startAt}) async => (demoBook(ref, RecordingSink()), at(startAt ?? const Duration(minutes: 12))),
    );
    await fresh.restore();
    expect(fresh.value.now?.title, 'The Clockmaker\'s Tide');
    expect(fresh.value.loaded, isFalse);
    expect(fresh.value.playing, isFalse);
    expect(fresh.value.position, const Duration(minutes: 12));
    await fresh.play();
    expect(fresh.value.loaded, isTrue);
    expect(fresh.value.playing, isTrue);
    await fresh.stop();
    await fresh.dispose();
  });
}

Future<LastPlayed> _lastOf(PlayerEngine engine) async {
  final now = engine.value.now!;
  return LastPlayed(
    ref: now.ref,
    title: now.title,
    author: now.author,
    position: engine.value.position,
    duration: now.duration,
    savedAt: DateTime(2026),
  );
}
