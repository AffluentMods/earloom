// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Runs against the local dev server (tool/abs-dev). Skipped automatically
// when it is not running or its passwords file is missing.
@Tags(['server'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/library/browse_models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/net/abs_auth_api.dart';
import 'package:earloom/core/net/abs_client.dart';
import 'package:earloom/core/net/token_refresher.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:earloom/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'abs_auth_live_test.dart' show NoEvents, devPassword, devServer, skipReason;

Future<void> main() async {
  final skip = await skipReason();
  setUpAll(() => HttpOverrides.global = null);

  test('sync a real library into the cache, read books, detail, series and search', () async {
    final auth = AbsAuthApi(devServer);
    final login = await auth.login('affluent', devPassword('affluent')!);
    final store = MemorySecureStore();
    await store.writeTokens('live', access: login.accessToken, refresh: login.refreshToken);
    final refresher = TokenRefresher(store: store, events: NoEvents(), apiFor: (_) async => auth);
    final client = AbsClient.create(accountId: 'live', baseUrl: devServer, store: store, refresher: refresher);
    final db = AccountDb(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(client.close);
    final repo = AbsLibraryRepository(db: db, client: client, source: const AbsSource('live'));

    await repo.refreshLibraries(force: true);
    final libraries = await repo.watchLibraries().first;
    expect(libraries, isNotEmpty);
    final books = libraries.firstWhere((l) => !l.isPodcast);

    await repo.syncLibrary(books.id, force: true);
    final items = await repo.watchBooks(books.id, const LibraryQuery()).first;
    expect(items, isNotEmpty);
    // Sorted like the server: "A Field Guide" files under F.
    expect(items.map((b) => b.title), contains('A Field Guide to Quiet Places'));
    expect(items.first.title, isNot('A Field Guide to Quiet Places'));

    final first = items.first;
    await repo.refreshItem(first.ref.itemId, force: true);
    // The list row shows first; the expanded item (with chapters) follows.
    final detail = await repo
        .watchBook(first.ref.itemId)
        .firstWhere((d) => d != null && d.chapters.isNotEmpty)
        .timeout(const Duration(seconds: 10));
    expect(detail!.summary.title, first.title);

    await repo.refreshSeriesList(books.id, force: true);
    await repo.refreshShelves(books.id, force: true);
    final results = await repo.search(books.id, first.title.split(' ').last);
    expect(results.isEmpty, isFalse);
    final offline = await repo.searchOffline(first.title.split(' ').last, libraryId: books.id);
    expect(offline.isEmpty, isFalse);
  }, skip: skip);
}
