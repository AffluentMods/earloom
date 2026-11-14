// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/library/source_id.dart';
import '../../accounts/data/account_session.dart';
import '../../player/player_controller.dart';
import 'stats_repository.dart';

/// "Your listening" for one book (docs/plan/08-phase7-stats.md 7.3).
final class BookListening {
  const BookListening({
    required this.time,
    required this.bookTime,
    required this.sessions,
    this.startedOn,
    this.finishedOn,
  });

  final Duration time;
  final Duration bookTime;
  final int sessions;
  final DateTime? startedOn;
  final DateTime? finishedOn;

  bool get isEmpty => sessions == 0 && time == Duration.zero;

  /// Average speed: book time covered per real time.
  double? get averageSpeed => time.inSeconds < 60 ? null : bookTime.inMilliseconds / time.inMilliseconds;
}

/// Combines this phone's log with other devices' sessions for the book.
final bookListeningProvider = FutureProvider.autoDispose.family<BookListening, ItemRef>((ref, item) async {
  final log = ref.watch(listeningLogProvider);
  final key = item.key;
  final mine = (await log.sessions()).where((s) => s.refKey == key).toList();
  final book = (await log.books()).where((b) => b.refKey == key).firstOrNull;
  var seconds = mine.fold(0.0, (a, s) => a + s.seconds);
  var bookSeconds = mine.fold(0.0, (a, s) => a + s.bookSeconds);
  var count = mine.length;
  int? first = mine.isEmpty ? null : mine.map((s) => s.startedAt).reduce((a, b) => a < b ? a : b);
  var finished = book?.finishedAt;

  final session = ref.watch(accountSessionProvider);
  final source = item.source;
  if (session != null && source is AbsSource && source.accountId == session.accountId) {
    try {
      final own = await ref.watch(deviceIdProvider.future);
      final path = item.episodeId == null
          ? '/api/me/item/listening-sessions/${item.itemId}'
          : '/api/me/item/listening-sessions/${item.itemId}/${item.episodeId}';
      final json = await session.client.get<Map<String, Object?>>(path, query: {'itemsPerPage': 100, 'page': 0});
      for (final s in ((json['sessions'] as List?) ?? const []).cast<Map<String, Object?>>()) {
        if ((s['deviceInfo'] as Map?)?['deviceId'] == own) continue;
        final listened = (s['timeListening'] as num?)?.toDouble() ?? 0;
        if (listened <= 0) continue;
        final covered = ((s['currentTime'] as num?) ?? 0) - ((s['startTime'] as num?) ?? 0);
        seconds += listened;
        bookSeconds += covered > 0 && covered < listened * 4 ? covered : listened;
        count++;
        final started = (s['startedAt'] as num?)?.toInt();
        if (started != null && (first == null || started < first)) first = started;
      }
      if (finished == null) {
        final progress = await session.client.get<Map<String, Object?>>(
          item.episodeId == null
              ? '/api/me/progress/${item.itemId}'
              : '/api/me/progress/${item.itemId}/${item.episodeId}',
        );
        final at = progress['finishedAt'];
        if (progress['isFinished'] == true && at is num) finished = at.toInt();
      }
    } on Object {
      // Offline or no progress: this phone's numbers stand.
    }
  }
  Duration secs(double s) => Duration(milliseconds: (s * 1000).round());
  return BookListening(
    time: secs(seconds),
    bookTime: secs(bookSeconds),
    sessions: count,
    startedOn: first == null ? null : DateTime.fromMillisecondsSinceEpoch(first),
    finishedOn: finished == null ? null : DateTime.fromMillisecondsSinceEpoch(finished),
  );
});
