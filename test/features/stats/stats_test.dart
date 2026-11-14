// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/native.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/features/stats/data/listening_log.dart';
import 'package:earloom/features/stats/data/stats_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = ItemRef(LocalSource(), 'b1');

NowPlaying _book({String title = 'Salt and Starlight', String? author = 'Mara Ellison'}) => NowPlaying(
  ref: _ref,
  title: title,
  author: author,
  narrator: 'Jonah Pryce',
  duration: const Duration(hours: 5),
  chapters: const [Chapter(index: 0, title: 'One', start: Duration.zero, end: Duration(hours: 5))],
);

ListeningSpan _span(DateTime end, Duration listened, {double speed = 1, String session = 's1'}) =>
    ListeningSpan(book: _book(), sessionId: session, end: end, listened: listened, speed: speed);

HourBucket _bucket(DateTime day, int minutes, {int hour = 21, String ref = 'local|b1'}) =>
    HourBucket(day: day, hour: hour, refKey: ref, seconds: minutes * 60.0, bookSeconds: minutes * 60.0);

void main() {
  group('the log', () {
    test('a stretch across midnight is split exactly between the two days', () {
      final pieces = ListeningLog.split(_span(DateTime(2026, 11, 14, 0, 10), const Duration(minutes: 30), speed: 2));
      expect(
        [for (final p in pieces) (p.day, p.hour, p.seconds.round())],
        [
          ('2026-11-13', 23, 1200),
          ('2026-11-14', 0, 600),
        ],
      );
      expect(pieces.fold(0.0, (a, p) => a + p.bookSeconds).round(), 3600, reason: 'book time at 2x');
    });

    test('records buckets, sessions, the book and its finish', () async {
      final db = GlobalDb(NativeDatabase.memory());
      addTearDown(db.close);
      final log = ListeningLog(db);
      await log.record(_span(DateTime(2026, 11, 14, 21, 0, 15), const Duration(seconds: 15)));
      await log.record(_span(DateTime(2026, 11, 14, 21, 0, 30), const Duration(seconds: 15)));
      await log.finished(_book(), DateTime(2026, 11, 14, 22));
      final input = await localStatsInput(log);
      expect(input.buckets.single.seconds, 30);
      expect(input.sessionSeconds, [30]);
      expect(input.books['local|b1']!.finishedAt, DateTime(2026, 11, 14, 22));
      expect(input.books['local|b1']!.narrator, 'Jonah Pryce');
    });

    test('a version 2 database gains the listening tables', () async {
      final v2 = NativeDatabase.memory(
        setup: (raw) {
          raw.execute('CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)');
          raw.execute("INSERT INTO app_settings VALUES ('theme_mode', 'dark')");
          raw.execute('PRAGMA user_version = 2');
        },
      );
      // Version 2 also had accounts; created by the migration from 1 in
      // the other test, here we only need the new tables to appear.
      final migrated = GlobalDb(v2);
      addTearDown(migrated.close);
      expect(await migrated.readSetting(SettingKeys.themeMode), 'dark');
      expect(await ListeningLog(migrated).buckets(), isEmpty);
    });
  });

  group('computeStats', () {
    final now = DateTime(2026, 11, 14, 20);
    DateTime day(int d) => DateTime(2026, 11, d);

    test('streaks count days over the threshold, and today not yet reached does not break one', () {
      final stats = computeStats(
        StatsInput(
          buckets: [_bucket(day(10), 20), _bucket(day(11), 2), _bucket(day(12), 30), _bucket(day(13), 45)],
          sessionSeconds: const [2700],
          books: const {},
        ),
        now: now,
      );
      expect(stats.streak, 2, reason: '12 and 13; the 11th was under 5 min');
      expect(stats.longestStreak, 2);
      expect(stats.today, Duration.zero);
      expect(stats.week.last.day, day(14));
      expect(stats.week.map((d) => d.time.inMinutes), [0, 0, 20, 2, 30, 45, 0]);
      expect(stats.longestSession, const Duration(minutes: 45));
    });

    test('week over week change, totals and the speed dividend', () {
      final stats = computeStats(
        StatsInput(
          buckets: [
            _bucket(day(13), 60),
            _bucket(day(5), 30),
            HourBucket(day: day(14), hour: 8, refKey: 'local|b1', seconds: 600, bookSeconds: 1200),
          ],
          sessionSeconds: const [],
          books: const {},
        ),
        now: now,
      );
      expect(stats.today, const Duration(minutes: 10));
      expect(stats.vsLastWeek, closeTo((70 - 30) / 30, 0.001));
      expect(stats.total, const Duration(minutes: 100));
      expect(stats.bookTime, const Duration(minutes: 110));
      expect(stats.hours[8], const Duration(minutes: 10));
      expect(stats.weekdays[DateTime.saturday - 1], const Duration(minutes: 10));
    });

    test('authors and narrators rank by time; finished books of this year, newest first', () {
      final stats = computeStats(
        StatsInput(
          buckets: [
            _bucket(day(1), 50, ref: 'a'),
            _bucket(day(2), 30, ref: 'b'),
            _bucket(day(3), 40, ref: 'c'),
          ],
          sessionSeconds: const [],
          books: {
            'a': StatsBook(refKey: 'a', title: 'A', author: 'Mara Ellison', finishedAt: DateTime(2026, 3, 1)),
            'b': StatsBook(refKey: 'b', title: 'B', author: 'Theo Vance', finishedAt: DateTime(2025, 12, 1)),
            'c': StatsBook(refKey: 'c', title: 'C', author: 'Theo Vance', finishedAt: DateTime(2026, 9, 1)),
          },
        ),
        now: now,
      );
      expect(stats.topAuthors.map((r) => (r.name, r.time.inMinutes)), [('Theo Vance', 70), ('Mara Ellison', 50)]);
      expect(stats.booksFinished, 3);
      expect(stats.finishedThisYear.map((b) => b.title), ['C', 'A']);
      expect(stats.topBooks.first.book.title, 'A');
    });
  });

  test('a server session is spread over its hours', () {
    final buckets = spreadSession(
      refKey: 'r',
      start: DateTime(2026, 11, 13, 23, 30),
      end: DateTime(2026, 11, 14, 0, 30),
      seconds: 3600,
      bookSeconds: 3600,
    );
    expect([for (final b in buckets) (b.day.day, b.hour, b.seconds.round())], [(13, 23, 1800), (14, 0, 1800)]);
  });
}
