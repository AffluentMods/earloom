// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/library/source_id.dart';
import '../../../core/net/abs_client.dart';
import '../../../core/ui/cover_image.dart';
import '../../accounts/data/account_session.dart';
import '../../player/player_controller.dart';
import 'listening_log.dart';

/// Listening in one local hour for one book.
final class HourBucket {
  const HourBucket({
    required this.day,
    required this.hour,
    required this.refKey,
    required this.seconds,
    required this.bookSeconds,
  });

  /// Local midnight of the day.
  final DateTime day;
  final int hour;
  final String refKey;
  final double seconds;
  final double bookSeconds;
}

/// A book as the stats show it.
final class StatsBook {
  const StatsBook({required this.refKey, required this.title, this.author, this.narrator, this.cover, this.finishedAt});

  final String refKey;
  final String title;
  final String? author;
  final String? narrator;
  final CoverSource? cover;
  final DateTime? finishedAt;

  StatsBook merge(StatsBook other) => StatsBook(
    refKey: refKey,
    title: title.isEmpty ? other.title : title,
    author: author ?? other.author,
    narrator: narrator ?? other.narrator,
    cover: cover ?? other.cover,
    finishedAt: finishedAt ?? other.finishedAt,
  );
}

/// Everything the stats are computed from.
final class StatsInput {
  const StatsInput({required this.buckets, required this.sessionSeconds, required this.books});
  final List<HourBucket> buckets;

  /// Length of every listening session, for "longest session".
  final List<double> sessionSeconds;
  final Map<String, StatsBook> books;

  static const empty = StatsInput(buckets: [], sessionSeconds: [], books: {});
}

/// Names a stat ranks by, with time listened.
typedef Ranked = ({String name, Duration time});

final class StatsSnapshot {
  const StatsSnapshot({
    required this.today,
    required this.goal,
    required this.streak,
    required this.longestStreak,
    required this.week,
    required this.lastWeekTotal,
    required this.days,
    required this.total,
    required this.bookTime,
    required this.booksFinished,
    required this.longestSession,
    required this.topAuthors,
    required this.topNarrators,
    required this.topBooks,
    required this.hours,
    required this.weekdays,
    required this.finishedThisYear,
    required this.year,
  });

  final Duration today;
  final Duration goal;
  final int streak;
  final int longestStreak;

  /// The last seven days, oldest first, today last.
  final List<({DateTime day, Duration time})> week;
  final Duration lastWeekTotal;

  /// Every day with listening, by local midnight.
  final Map<DateTime, Duration> days;
  final Duration total;
  final Duration bookTime;
  final int booksFinished;
  final Duration longestSession;
  final List<Ranked> topAuthors;
  final List<Ranked> topNarrators;
  final List<({StatsBook book, Duration time})> topBooks;

  /// 24 entries, midnight first.
  final List<Duration> hours;

  /// 7 entries, Monday first.
  final List<Duration> weekdays;
  final List<StatsBook> finishedThisYear;
  final int year;

  bool get isEmpty => total == Duration.zero;
  Duration get weekTotal => week.fold(Duration.zero, (a, d) => a + d.time);
  Duration get weekAverage => weekTotal ~/ 7;

  /// Change against the week before, as a fraction; null with nothing to
  /// compare.
  double? get vsLastWeek =>
      lastWeekTotal == Duration.zero ? null : (weekTotal.inSeconds - lastWeekTotal.inSeconds) / lastWeekTotal.inSeconds;
}

Duration _secs(double s) => Duration(milliseconds: (s * 1000).round());

/// Computes every stat. Pure, so it is tested with plain data.
StatsSnapshot computeStats(
  StatsInput input, {
  required DateTime now,
  Duration goal = const Duration(minutes: 30),
  Duration streakThreshold = const Duration(minutes: 5),
}) {
  final today = DateTime(now.year, now.month, now.day);
  final days = <DateTime, double>{};
  final hours = List<double>.filled(24, 0);
  final weekdays = List<double>.filled(7, 0);
  final perBook = <String, double>{};
  var total = 0.0;
  var bookTime = 0.0;
  for (final b in input.buckets) {
    days[b.day] = (days[b.day] ?? 0) + b.seconds;
    hours[b.hour] += b.seconds;
    weekdays[b.day.weekday - 1] += b.seconds;
    perBook[b.refKey] = (perBook[b.refKey] ?? 0) + b.seconds;
    total += b.seconds;
    bookTime += b.bookSeconds;
  }

  bool counts(DateTime day) => (days[day] ?? 0) >= streakThreshold.inSeconds;
  DateTime back(DateTime day, int n) => DateTime(day.year, day.month, day.day - n);

  // Today not reached yet does not break a streak that ran until yesterday.
  var streak = 0;
  var cursor = counts(today) ? today : back(today, 1);
  while (counts(cursor)) {
    streak++;
    cursor = back(cursor, 1);
  }

  var longestStreak = 0;
  var run = 0;
  DateTime? previous;
  for (final day in days.keys.where(counts).toList()..sort()) {
    run = (previous != null && back(day, 1) == previous) ? run + 1 : 1;
    if (run > longestStreak) longestStreak = run;
    previous = day;
  }

  final week = [
    for (var i = 6; i >= 0; i--) (day: back(today, i), time: _secs(days[back(today, i)] ?? 0)),
  ];
  var lastWeek = 0.0;
  for (var i = 7; i < 14; i++) {
    lastWeek += days[back(today, i)] ?? 0;
  }

  List<Ranked> rank(String? Function(StatsBook) name) {
    final byName = <String, double>{};
    perBook.forEach((key, seconds) {
      final n = input.books[key] == null ? null : name(input.books[key]!);
      if (n == null || n.trim().isEmpty) return;
      byName[n] = (byName[n] ?? 0) + seconds;
    });
    final list = [for (final e in byName.entries) (name: e.key, time: _secs(e.value))]
      ..sort((a, b) => b.time.compareTo(a.time));
    return list.take(5).toList();
  }

  final topBooks = [
    for (final e in perBook.entries)
      if (input.books[e.key] != null) (book: input.books[e.key]!, time: _secs(e.value)),
  ]..sort((a, b) => b.time.compareTo(a.time));

  final finished = input.books.values.where((b) => b.finishedAt != null).toList();
  final finishedThisYear = finished.where((b) => b.finishedAt!.toLocal().year == now.year).toList()
    ..sort((a, b) => b.finishedAt!.compareTo(a.finishedAt!));

  return StatsSnapshot(
    today: _secs(days[today] ?? 0),
    goal: goal,
    streak: streak,
    longestStreak: longestStreak,
    week: week,
    lastWeekTotal: _secs(lastWeek),
    days: {for (final e in days.entries) e.key: _secs(e.value)},
    total: _secs(total),
    bookTime: _secs(bookTime),
    booksFinished: finished.length,
    longestSession: _secs(input.sessionSeconds.fold(0.0, (a, b) => b > a ? b : a)),
    topAuthors: rank((b) => b.author),
    topNarrators: rank((b) => b.narrator),
    topBooks: topBooks.take(5).toList(),
    hours: [for (final h in hours) _secs(h)],
    weekdays: [for (final w in weekdays) _secs(w)],
    finishedThisYear: finishedThisYear,
    year: now.year,
  );
}

/// Spreads a server session's listening evenly over its wall-clock span,
/// in local hours. The server keeps only totals, so this is an estimate.
List<HourBucket> spreadSession({
  required String refKey,
  required DateTime start,
  required DateTime end,
  required double seconds,
  required double bookSeconds,
}) {
  final out = <HourBucket>[];
  if (seconds <= 0) return out;
  var from = start.toLocal();
  var to = end.toLocal();
  // A span shorter than the listening (clock trouble) becomes the listening.
  if (to.difference(from).inMilliseconds < seconds * 1000) to = from.add(_secs(seconds));
  final span = to.difference(from).inMicroseconds;
  while (from.isBefore(to)) {
    final next = DateTime(from.year, from.month, from.day, from.hour + 1);
    final stop = next.isBefore(to) ? next : to;
    final part = stop.difference(from).inMicroseconds / span;
    out.add(
      HourBucket(
        day: DateTime(from.year, from.month, from.day),
        hour: from.hour,
        refKey: refKey,
        seconds: seconds * part,
        bookSeconds: bookSeconds * part,
      ),
    );
    from = stop;
  }
  return out;
}

// --- Gathering ---------------------------------------------------------------

final listeningLogProvider = Provider<ListeningLog>((ref) => ListeningLog(ref.watch(globalDbProvider)));

/// Hooks the log to the player. Kept alive by the app shell.
final listeningRecorderProvider = Provider<void>((ref) {
  final engine = ref.watch(playerEngineProvider);
  final log = ref.watch(listeningLogProvider);
  engine
    ..onListened = ((span) => unawaited(log.record(span)))
    ..onFinishedBook = ((book, at) => unawaited(log.finished(book, at)));
  ref.onDispose(() {
    engine
      ..onListened = null
      ..onFinishedBook = null;
  });
});

abstract final class StatsSettings {
  static const goalMinutes = 'stats.goal_minutes';
  static const streakMinutes = 'stats.streak_minutes';
}

/// This phone's log as stats input.
Future<StatsInput> localStatsInput(ListeningLog log) async {
  final buckets = [
    for (final b in await log.buckets())
      HourBucket(
        day: DateTime.parse(b.day),
        hour: b.hour,
        refKey: b.refKey,
        seconds: b.seconds,
        bookSeconds: b.bookSeconds,
      ),
  ];
  final sessions = [for (final s in await log.sessions()) s.seconds];
  final books = {
    for (final b in await log.books())
      b.refKey: StatsBook(
        refKey: b.refKey,
        title: b.title,
        author: b.author,
        narrator: b.narrator,
        cover: b.coverPath != null
            ? FileCover(b.coverPath!)
            : (b.coverUrl != null
                  ? NetworkCover(itemCoverUrl: Uri.parse(b.coverUrl!), cacheKey: b.coverKey ?? b.coverUrl!)
                  : null),
        finishedAt: b.finishedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(b.finishedAt!),
      ),
  };
  return StatsInput(buckets: buckets, sessionSeconds: sessions, books: books);
}

/// Listening on other devices for the current server account: its
/// sessions minus the ones this phone made (those are in the local log).
Future<StatsInput> serverStatsInput(AbsClient client, String accountId, String ownDeviceId) async {
  final buckets = <HourBucket>[];
  final sessions = <double>[];
  final books = <String, StatsBook>{};
  for (var page = 0; page < 50; page++) {
    final json = await client.get<Map<String, Object?>>(
      '/api/me/listening-sessions',
      query: {'itemsPerPage': 100, 'page': page},
    );
    final list = ((json['sessions'] as List?) ?? const []).cast<Map<String, Object?>>();
    for (final s in list) {
      final itemId = s['libraryItemId'];
      if (itemId is! String) continue;
      final ref = ItemRef(AbsSource(accountId), itemId, episodeId: s['episodeId'] as String?);
      final meta = (s['mediaMetadata'] as Map?)?.cast<String, Object?>() ?? const {};
      final narrators = (meta['narrators'] as List?)?.whereType<String>().toList() ?? const [];
      books[ref.key] = (books[ref.key] ?? StatsBook(refKey: ref.key, title: '')).merge(
        StatsBook(
          refKey: ref.key,
          title: (s['displayTitle'] as String?) ?? (meta['title'] as String?) ?? '',
          author: s['displayAuthor'] as String?,
          narrator: narrators.isEmpty ? null : narrators.first,
          cover: NetworkCover(itemCoverUrl: client.url('/api/items/$itemId/cover'), cacheKey: itemId),
        ),
      );
      final device = (s['deviceInfo'] as Map?)?['deviceId'];
      if (device == ownDeviceId) continue;
      final seconds = (s['timeListening'] as num?)?.toDouble() ?? 0;
      if (seconds <= 0) continue;
      final covered = ((s['currentTime'] as num?) ?? 0) - ((s['startTime'] as num?) ?? 0);
      sessions.add(seconds);
      buckets.addAll(
        spreadSession(
          refKey: ref.key,
          start: DateTime.fromMillisecondsSinceEpoch((s['startedAt'] as num?)?.toInt() ?? 0),
          end: DateTime.fromMillisecondsSinceEpoch((s['updatedAt'] as num?)?.toInt() ?? 0),
          seconds: seconds,
          // Seeks make the covered time meaningless; then assume 1x.
          bookSeconds: covered > 0 && covered < seconds * 4 ? covered.toDouble() : seconds,
        ),
      );
    }
    final pages = (json['numPages'] as num?)?.toInt() ?? 1;
    if (page + 1 >= pages) break;
  }
  try {
    final progress = await client.get<Map<String, Object?>>('/api/me/progress');
    for (final p in ((progress['mediaProgress'] as List?) ?? const []).cast<Map<String, Object?>>()) {
      final itemId = p['libraryItemId'];
      final at = p['finishedAt'];
      if (itemId is! String || p['isFinished'] != true || at is! num) continue;
      final ref = ItemRef(AbsSource(accountId), itemId, episodeId: p['episodeId'] as String?);
      books[ref.key] = (books[ref.key] ?? StatsBook(refKey: ref.key, title: '')).merge(
        StatsBook(
          refKey: ref.key,
          title: '',
          cover: NetworkCover(itemCoverUrl: client.url('/api/items/$itemId/cover'), cacheKey: itemId),
          finishedAt: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
        ),
      );
    }
  } on Object {
    // Finished books are a bonus: stats still show without them.
  }
  return StatsInput(buckets: buckets, sessionSeconds: sessions, books: books);
}

StatsInput mergeInputs(StatsInput a, StatsInput b) {
  final books = {...a.books};
  b.books.forEach((key, book) => books[key] = books[key]?.merge(book) ?? book);
  return StatsInput(
    buckets: [...a.buckets, ...b.buckets],
    sessionSeconds: [...a.sessionSeconds, ...b.sessionSeconds],
    books: books,
  );
}

/// Server listening from other devices, cached for ten minutes.
final serverStatsProvider = FutureProvider<StatsInput>((ref) async {
  final session = ref.watch(accountSessionProvider);
  if (session == null) return StatsInput.empty;
  final deviceId = await ref.watch(deviceIdProvider.future);
  final timer = Timer(const Duration(minutes: 10), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return serverStatsInput(session.client, session.accountId, deviceId);
});

/// The goal and streak settings, in minutes.
final statsGoalsProvider = StreamProvider<({int goal, int streak})>((ref) {
  final db = ref.watch(globalDbProvider);
  final goal = db.watchSetting(StatsSettings.goalMinutes);
  return goal.asyncMap(
    (g) async => (
      goal: int.tryParse(g ?? '') ?? 30,
      streak: int.tryParse(await db.readSetting(StatsSettings.streakMinutes) ?? '') ?? 5,
    ),
  );
});

/// All stats, recomputed when the log changes. The server part arrives
/// when it can; the screen never waits on it.
final statsProvider = StreamProvider<StatsSnapshot>((ref) async* {
  final log = ref.watch(listeningLogProvider);
  final goals = ref.watch(statsGoalsProvider).value ?? (goal: 30, streak: 5);
  final server = ref.watch(serverStatsProvider).value ?? StatsInput.empty;
  Future<StatsSnapshot> build() async => computeStats(
    mergeInputs(await localStatsInput(log), server),
    now: DateTime.now(),
    goal: Duration(minutes: goals.goal),
    streakThreshold: Duration(minutes: goals.streak),
  );
  yield await build();
  await for (final _ in log.changes) {
    yield await build();
  }
});
