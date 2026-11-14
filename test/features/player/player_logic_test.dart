// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:math';

import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/chapters.dart';
import 'package:earloom/features/player/playable.dart';
import 'package:earloom/features/player/player_prefs.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:earloom/features/player/sleep_timer.dart';
import 'package:earloom/features/player/track_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

const _ref = ItemRef(LocalSource(), 'b1');

void main() {
  group('TrackMap', () {
    final map = TrackMap(demoBook(_ref, RecordingSink()).tracks);

    test('locates the start, boundaries, the middle, past the end and negatives', () {
      expect(map.locate(Duration.zero), (index: 0, offset: Duration.zero));
      expect(map.locate(const Duration(minutes: 10)), (index: 1, offset: Duration.zero));
      expect(map.locate(const Duration(minutes: 25)), (index: 1, offset: const Duration(minutes: 15)));
      expect(map.locate(const Duration(hours: 5)), (index: 2, offset: const Duration(minutes: 30)));
      expect(map.locate(const Duration(seconds: -4)), (index: 0, offset: Duration.zero));
    });

    test('round trips 10,000 random positions', () {
      final random = Random(7);
      for (var i = 0; i < 10000; i++) {
        final x = Duration(milliseconds: random.nextInt(map.total.inMilliseconds));
        final at = map.locate(x);
        expect(map.toGlobal(at.index, at.offset), x);
      }
    });
  });

  group('chapters', () {
    String name(int n) => 'Part $n';

    test('fall back to one per track, then one for the whole book', () {
      final multi = demoBook(_ref, RecordingSink());
      final perTrack = effectiveChapters(multi, titleForTrack: name, wholeBookTitle: 'Whole');
      expect(perTrack.map((c) => c.title), ['Part 1', 'Part 2', 'Part 3']);
      expect(perTrack.last.end, const Duration(hours: 1));

      final single = PlayableBook(
        ref: _ref,
        title: 'One',
        sink: RecordingSink(),
        tracks: [
          PlayableTrack(uri: Uri.parse('file:///a.m4b'), start: Duration.zero, duration: const Duration(hours: 2)),
        ],
      );
      final whole = effectiveChapters(single, titleForTrack: name, wholeBookTitle: 'Whole');
      expect(whole.single.title, 'Whole');
    });

    test('own chapters win, are sorted, and the last one reaches the end', () {
      final book = PlayableBook(
        ref: _ref,
        title: 'One',
        sink: RecordingSink(),
        tracks: [
          PlayableTrack(uri: Uri.parse('file:///a.m4b'), start: Duration.zero, duration: const Duration(hours: 1)),
        ],
        chapters: const [
          Chapter(index: 1, title: 'Two', start: Duration(minutes: 30), end: Duration(minutes: 59)),
          Chapter(index: 0, title: '', start: Duration.zero, end: Duration(minutes: 30)),
        ],
      );
      final chapters = effectiveChapters(book, titleForTrack: name, wholeBookTitle: 'Whole');
      expect(chapters.map((c) => c.title), ['Part 1', 'Two']);
      expect(chapters.last.end, const Duration(hours: 1));
      expect(chapterIndexAt(chapters, const Duration(minutes: 30)), 1);
      expect(chapterIndexAt(chapters, const Duration(minutes: 29, seconds: 59)), 0);
    });
  });

  group('start position', () {
    final t0 = DateTime(2026, 11, 14, 8);

    test('the newer one wins; a far newer server position comes with an undo', () {
      final local = PositionStamp(const Duration(minutes: 10), t0);
      final near = PositionStamp(const Duration(minutes: 10, seconds: 20), t0.add(const Duration(hours: 1)));
      final far = PositionStamp(const Duration(minutes: 40), t0.add(const Duration(hours: 1)));
      final older = PositionStamp(const Duration(minutes: 40), t0.subtract(const Duration(hours: 1)));

      expect(resolveStart(local: local, server: older).position, const Duration(minutes: 10));
      final quiet = resolveStart(local: local, server: near);
      expect((quiet.position, quiet.fromOtherDevice), (near.position, false));
      final loud = resolveStart(local: local, server: far);
      expect((loud.position, loud.fromOtherDevice, loud.undoTo), (far.position, true, local.position));
      expect(resolveStart(server: far).position, far.position);
      expect(resolveStart().position, Duration.zero);
    });

    test('remote updates: our own echo is ignored', () {
      final synced = DateTime(2026, 11, 14, 9);
      final echo = PositionStamp(const Duration(minutes: 50), synced);
      expect(
        resolveRemote(here: Duration.zero, playing: false, remote: echo, lastSyncedAt: synced),
        isA<IgnoreRemote>(),
      );
    });
  });

  test('fade volume ramps down smoothly', () {
    const fade = Duration(seconds: 30);
    expect(sleepFadeVolume(const Duration(minutes: 1), fade), 1);
    expect(sleepFadeVolume(Duration.zero, fade), 0);
    final half = sleepFadeVolume(const Duration(seconds: 15), fade);
    expect(half, closeTo(0.5, 0.01));
    expect(sleepFadeVolume(const Duration(seconds: 5), Duration.zero), 1);
  });

  test('smart rewind steps', () {
    expect(smartRewindFor(const Duration(seconds: 30)), Duration.zero);
    expect(smartRewindFor(const Duration(minutes: 3)), const Duration(seconds: 5));
    expect(smartRewindFor(const Duration(minutes: 30)), const Duration(seconds: 15));
    expect(smartRewindFor(const Duration(hours: 3)), const Duration(seconds: 30));
  });

  test('prefs survive a round trip and broken values fall back', () {
    const prefs = PlayerPrefs(
      skipBack: Duration(seconds: 10),
      defaultSpeed: 1.35,
      remoteButtons: RemoteButtons.chapters,
    );
    final back = PlayerPrefs.fromJson(prefs.toJson());
    expect((back.skipBack, back.defaultSpeed, back.remoteButtons), (prefs.skipBack, 1.35, RemoteButtons.chapters));
    final broken = PlayerPrefs.fromJson({'defaultSpeed': 'fast', 'remoteButtons': 'banana', 'boostDecibels': 99});
    expect((broken.defaultSpeed, broken.remoteButtons, broken.boostDecibels), (1.0, RemoteButtons.skip, 10.0));
  });
}
