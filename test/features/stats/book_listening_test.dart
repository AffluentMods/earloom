// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/native.dart';
import 'package:earloom/app/providers.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/accounts/data/account_session.dart';
import 'package:earloom/features/player/player_engine.dart';
import 'package:earloom/features/stats/data/book_listening.dart';
import 'package:earloom/features/stats/data/listening_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = ItemRef(LocalSource(), 'b1');

void main() {
  test('a book never played is empty; one played twice at 1.5x says so', () async {
    final db = GlobalDb(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [globalDbProvider.overrideWithValue(db), accountSessionProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);
    expect((await container.read(bookListeningProvider(_ref).future)).isEmpty, isTrue);

    const book = NowPlaying(
      ref: _ref,
      title: 'Salt and Starlight',
      duration: Duration(hours: 2),
      chapters: [Chapter(index: 0, title: 'One', start: Duration.zero, end: Duration(hours: 2))],
    );
    final log = ListeningLog(db);
    for (final (session, end) in [('s1', DateTime(2026, 11, 10, 21)), ('s2', DateTime(2026, 11, 12, 21))]) {
      await log.record(
        ListeningSpan(book: book, sessionId: session, end: end, listened: const Duration(minutes: 20), speed: 1.5),
      );
    }
    await log.finished(book, DateTime(2026, 11, 12, 22));
    container.invalidate(bookListeningProvider(_ref));
    final data = await container.read(bookListeningProvider(_ref).future);
    expect(data.time, const Duration(minutes: 40));
    expect(data.sessions, 2);
    expect(data.averageSpeed, closeTo(1.5, 0.001));
    expect(data.startedOn, DateTime(2026, 11, 10, 20, 40));
    expect(data.finishedOn, DateTime(2026, 11, 12, 22));
  });
}
