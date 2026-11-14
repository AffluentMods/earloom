// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/library/browse_models.dart';
import 'package:earloom/core/net/abs_errors.dart';
import 'package:earloom/core/socket/abs_socket.dart';
import 'package:earloom/features/home/data/home_repository.dart';
import 'package:earloom/features/library/data/abs_json.dart';
import 'package:earloom/features/library/data/library_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';
import 'abs_support.dart';

const clockmaker = '695b9eb3-1a88-4320-b033-95089797f205';
const ashHarbor = '6957113a-8be3-4a90-88da-cf2e0e342ed9';
const fieldGuide = '7c1bec65-2448-4d37-bf1c-98889dc29197';
const exampleSaga = 'd22d1a16-8a7a-4fef-b740-7d3e5b98f093';

void main() {
  late FakeAbsServer server;
  late AccountDb db;
  late AbsLibraryRepository repository;
  var now = DateTime(2026, 11, 14, 12);

  setUp(() async {
    now = DateTime(2026, 11, 14, 12);
    server = FakeAbsServer();
    db = memoryAccountDb();
    repository = await fakeRepository(server, db, clock: () => now);
  });

  group('libraries and items', () {
    test('libraries are cached in display order', () async {
      await repository.refreshLibraries();
      final libraries = await repository.watchLibraries().first;
      expect(libraries.map((l) => l.name), ['Audiobooks', 'Podcasts']);
      expect(libraries.last.isPodcast, isTrue);
    });

    test('a full sync writes every item and removes ones the server no longer lists', () async {
      await db.catalogDao.upsertItems([
        AbsJson.item({
          'id': 'gone',
          'libraryId': testLibraryId,
          'mediaType': 'book',
          'addedAt': 1,
          'updatedAt': 1,
          'media': {
            'metadata': {'title': 'Removed on the server'},
          },
        }),
      ]);
      await repository.syncLibrary(testLibraryId);
      final books = await repository.watchBooks(testLibraryId, const LibraryQuery()).first;
      expect(books.map((b) => b.title), ['Ash Harbor', 'Cinder Interlude', 'A Field Guide to Quiet Places']);
      final request = server.requestsTo('/api/libraries/$testLibraryId/items').single;
      expect(request.uri.queryParameters['limit'], '${AbsLibraryRepository.syncPageSize}');
      expect(request.headers['Authorization'], startsWith('Bearer '));
      expect(request.uri.toString(), isNot(contains('token')));
    });

    test('a sync runs at most every six hours unless forced', () async {
      await repository.syncLibrary(testLibraryId);
      now = now.add(const Duration(hours: 1));
      await repository.syncLibrary(testLibraryId);
      expect(server.requestsTo('/api/libraries/$testLibraryId/items'), hasLength(1));
      await repository.syncLibrary(testLibraryId, force: true);
      now = now.add(const Duration(hours: 7));
      await repository.syncLibrary(testLibraryId);
      expect(server.requestsTo('/api/libraries/$testLibraryId/items'), hasLength(3));
    });

    test('list fields: authors, narrators, series, cover key from updatedAt', () async {
      await repository.syncLibrary(testLibraryId);
      final books = await repository.watchBooks(testLibraryId, const LibraryQuery()).first;
      final ash = books.firstWhere((b) => b.title == 'Ash Harbor');
      expect(ash.authors, ['Theo Vance']);
      expect(ash.narrators, ['Jonah Pryce']);
      expect(ash.seriesName, 'The Example Saga');
      expect(ash.seriesSequence, '2');
      expect(ash.coverKey, isNotNull);
      expect(ash.ref.source, testSource);
    });

    test('filters and sort combine', () async {
      await repository.syncLibrary(testLibraryId);
      Future<List<String>> titles(LibraryQuery q) async =>
          (await repository.watchBooks(testLibraryId, q).first).map((b) => b.title).toList();
      expect(await titles(const LibraryQuery(filters: [LibraryFilter(FilterKind.narrator, 'Jonah Pryce')])), [
        'Ash Harbor',
        'Cinder Interlude',
      ]);
      expect(
        await titles(
          const LibraryQuery(
            sort: LibrarySort.title,
            descending: true,
            filters: [
              LibraryFilter(FilterKind.narrator, 'Jonah Pryce'),
              LibraryFilter(FilterKind.tag, 'novella'),
            ],
          ),
        ),
        ['Cinder Interlude'],
      );
      expect(await titles(const LibraryQuery(filters: [LibraryFilter(FilterKind.genre, 'Nature')])), [
        'A Field Guide to Quiet Places',
      ]);
      // Genre names must match whole, not as a part of another name.
      expect(await titles(const LibraryQuery(filters: [LibraryFilter(FilterKind.genre, 'Science')])), isEmpty);
    });

    test('progress filters use the progress table', () async {
      await repository.syncLibrary(testLibraryId);
      await db.catalogDao.upsertProgress(
        AbsJson.progress({'libraryItemId': ashHarbor, 'currentTime': 100, 'duration': 1000, 'lastUpdate': 5}),
      );
      await db.catalogDao.upsertProgress(
        AbsJson.progress({'libraryItemId': fieldGuide, 'isFinished': true, 'progress': 1, 'lastUpdate': 6}),
      );
      Future<List<String>> titles(String value) async =>
          (await repository
                  .watchBooks(testLibraryId, LibraryQuery(filters: [LibraryFilter(FilterKind.progress, value)]))
                  .first)
              .map((b) => b.title)
              .toList();
      expect(await titles(ProgressFilterValue.inProgress), ['Ash Harbor']);
      expect(await titles(ProgressFilterValue.finished), ['A Field Guide to Quiet Places']);
      expect(await titles(ProgressFilterValue.notStarted), ['Cinder Interlude']);
    });
  });

  group('item detail', () {
    test('the expanded item and its progress are cached; reopening within 10 minutes does not refetch', () async {
      await repository.refreshItem(clockmaker);
      final detail = await repository.watchBook(clockmaker).firstWhere((d) => d?.chapters.isNotEmpty ?? false);
      expect(detail!.summary.title, "The Clockmaker's Tide");
      expect(detail.chapters, hasLength(8));
      expect(detail.genres, ['Fiction', 'Fantasy']);
      expect(detail.descriptionHtml, contains('harbor town'));
      expect(detail.summary.progress, isNotNull);
      expect(detail.authorIds['Mara Ellison'], 'd549684d-0013-4cc6-b8fa-8833bbbc7ea7');
      expect(detail.fileFormat, 'mp3');

      now = now.add(const Duration(minutes: 5));
      await repository.refreshItem(clockmaker);
      expect(server.requestsTo('/api/items/$clockmaker'), hasLength(1));
      now = now.add(const Duration(minutes: 6));
      await repository.refreshItem(clockmaker);
      expect(server.requestsTo('/api/items/$clockmaker'), hasLength(2));
      expect(server.requests.last.uri.queryParameters, {'expanded': '1', 'include': 'progress'});
    });

    test('an item the server answers 404 for is removed from the cache', () async {
      await repository.syncLibrary(testLibraryId);
      server.routes['/api/items/$ashHarbor'] = (_) => null;
      await expectLater(repository.refreshItem(ashHarbor), throwsA(isA<AbsHttpError>()));
      expect(await repository.watchBook(ashHarbor).first, isNull);
    });

    test('offline, the cached detail still renders', () async {
      await repository.refreshItem(clockmaker);
      server.offline = true;
      await expectLater(repository.refreshItem(clockmaker, force: true), throwsA(isA<AbsUnreachable>()));
      final detail = await repository.watchBook(clockmaker).firstWhere((d) => d?.chapters.isNotEmpty ?? false);
      expect(detail!.summary.title, "The Clockmaker's Tide");
    });
  });

  group('progress', () {
    test('progress from /api/me feeds Continue listening, newest first', () async {
      await repository.refreshProgress();
      final continuing = await repository.watchContinueListening().first;
      expect(continuing, isNotEmpty);
      expect(continuing.first.progress!.isStarted, isTrue);
      final updates = continuing.map((b) => b.progress!.updatedAt).toList();
      expect(updates, [...updates]..sort((a, b) => b.compareTo(a)));
    });

    test('mark finished changes the cache at once and sends isFinished', () async {
      server.routes['/api/me/progress/$clockmaker'] = (_) => const FakeResponse(200, 'OK');
      await repository.setFinished(clockmaker, finished: true);
      expect((await repository.watchProgress(clockmaker).first)!.isFinished, isTrue);
      final request = server.requestsTo('/api/me/progress/$clockmaker').single;
      expect(request.method, 'PATCH');
      expect(request.data, {'isFinished': true});
    });

    test('a failed mark finished puts the old progress back', () async {
      await repository.refreshProgress();
      server.offline = true;
      await expectLater(repository.setFinished(clockmaker, finished: true), throwsA(isA<AbsUnreachable>()));
      final progress = await repository.watchProgress(clockmaker).first;
      expect(progress!.isFinished, isFalse);
      expect(progress.position, const Duration(seconds: 144));
    });
  });

  group('socket', () {
    test('playback elsewhere updates progress; a user update replaces it', () async {
      await repository.apply(
        ProgressUpdated(
          sessionId: 's',
          progress: Map<String, Object?>.from(
            (fixture('socket_user_item_progress_updated')! as Map)['data'] as Map,
          ),
        ),
      );
      final event = (fixture('socket_user_item_progress_updated')! as Map)['data'] as Map;
      final id = event['libraryItemId'] as String;
      expect(await repository.watchProgress(id).first, isNotNull);

      await repository.apply(const UserUpdated({'mediaProgress': []}));
      expect(await repository.watchProgress(id).first, isNull);
    });

    test('item removed deletes it everywhere; item updated writes the new item', () async {
      await repository.syncLibrary(testLibraryId);
      await repository.apply(const ItemRemoved(itemId: ashHarbor));
      final books = await repository.watchBooks(testLibraryId, const LibraryQuery()).first;
      expect(books.map((b) => b.title), isNot(contains('Ash Harbor')));

      final updated = Map<String, Object?>.from(fixture('socket_item_updated')! as Map);
      await repository.apply(ItemsChanged([updated], added: false));
      final row = await db.catalogDao.watchItem(updated['id'] as String).first;
      expect(row, isNotNull);
      expect(await db.catalogDao.detail(updated['id'] as String), isNotNull);
    });

    test('a playlist change refetches playlists', () async {
      await repository.refreshLibraries();
      await repository.apply(const CatalogChanged('playlist'));
      expect(server.requestsTo('/api/libraries/$testLibraryId/playlists'), isNotEmpty);
    });
  });

  group('series, authors, collections, playlists', () {
    test('series list keeps natural sequence order from the server', () async {
      await repository.refreshSeriesList(testLibraryId);
      final series = await repository.watchSeriesList(testLibraryId).first;
      expect(series.single.name, 'The Example Saga');
      expect(series.single.books.map((b) => b.seriesSequence), ['1', '2', '2.5', '10']);
    });

    test('one series takes structured sequences from the series filter', () async {
      await repository.refreshSeries(exampleSaga);
      final series = await repository.watchSeries(exampleSaga).first;
      expect(series!.books, hasLength(4));
      final filter = server.requestsTo('/api/libraries/$testLibraryId/items').single;
      expect(filter.uri.queryParameters['filter'], 'series.${base64.encode(utf8.encode(exampleSaga))}');
      expect(filter.uri.queryParameters['sort'], 'sequence');
    });

    test('an author brings their books and series', () async {
      await repository.refreshAuthor('e271d8df-7aa6-43d5-8e62-5b661bf2aafa');
      final author = await repository.watchAuthor('e271d8df-7aa6-43d5-8e62-5b661bf2aafa').first;
      expect(author!.name, 'Theo Vance');
      final series = await repository.watchSeriesOfAuthor(testLibraryId, 'Theo Vance').first;
      expect(series.single.name, 'The Example Saga');
    });

    test('collections and playlists are cached with their books in order', () async {
      await repository.refreshCollections(testLibraryId);
      await repository.refreshPlaylists(testLibraryId);
      final collections = await repository.watchCollections(testLibraryId).first;
      expect(collections.single.name, 'Staff Picks');
      expect(collections.single.books, hasLength(2));
      final playlists = await repository.watchPlaylists(testLibraryId).first;
      expect(playlists.single.name, 'Road Trip Mix');
      expect(playlists.single.books, hasLength(2));
    });

    test('playlist create, rename, reorder and delete call the server and update the cache', () async {
      final playlist = Map<String, Object?>.from(
        ((fixture('library_playlists')! as Map)['results'] as List).first as Map,
      );
      final id = playlist['id'] as String;
      final items = (playlist['items'] as List).cast<Map<String, Object?>>();
      server.routes['/api/playlists'] = (_) => playlist;
      server.routes['/api/playlists/$id'] = (r) {
        if (r.method == 'DELETE') return const FakeResponse(200, 'OK');
        final body = r.data as Map;
        return {
          ...playlist,
          if (body['name'] != null) 'name': body['name'],
          if (body['items'] != null)
            'items': [
              for (final i in body['items'] as List)
                items.firstWhere((e) => e['libraryItemId'] == (i as Map)['libraryItemId']),
            ],
        };
      };

      final created = await repository.createPlaylist(testLibraryId, 'Road Trip Mix', firstItemId: ashHarbor);
      expect(created, id);
      expect(server.requestsTo('/api/playlists').single.data, {
        'libraryId': testLibraryId,
        'name': 'Road Trip Mix',
        'items': [
          {'libraryItemId': ashHarbor},
        ],
      });

      await repository.renamePlaylist(id, 'Night Drive');
      expect((await repository.watchPlaylist(id).first)!.name, 'Night Drive');

      final reversed = [for (final i in items.reversed) i['libraryItemId'] as String];
      await repository.reorderPlaylist(id, reversed);
      final order = (await repository.watchPlaylist(id).first)!.books.map((b) => b.ref.itemId).toList();
      expect(order, reversed);

      await repository.deletePlaylist(id);
      expect(await repository.watchPlaylist(id).first, isNull);
    });
  });

  group('home shelves', () {
    test('shelves render from the cache, refetched only after two minutes', () async {
      await repository.refreshShelves(testLibraryId);
      final shelves = await HomeRepository(repository).watchShelves(testLibraryId).first;
      expect(shelves.map((s) => s.id), [
        'continue-listening',
        'continue-series',
        'recently-added',
        'recent-series',
        'listen-again',
        'newest-authors',
      ]);
      expect(shelves.firstWhere((s) => s.id == 'recent-series').kind, ShelfKind.series);
      expect(shelves.firstWhere((s) => s.id == 'newest-authors').authors, hasLength(2));
      await repository.refreshShelves(testLibraryId);
      expect(server.requestsTo('/api/libraries/$testLibraryId/personalized'), hasLength(1));
      now = now.add(const Duration(minutes: 3));
      await repository.refreshShelves(testLibraryId);
      expect(server.requestsTo('/api/libraries/$testLibraryId/personalized'), hasLength(2));
    });
  });

  group('search', () {
    test('server search returns grouped results and caches the books', () async {
      final results = await repository.search(testLibraryId, 'the', cancel: CancelToken());
      expect(results.books.map((b) => b.title), ['The Long Way to Morning', 'Lanterns Under the Ice']);
      expect(results.series.single.name, 'The Example Saga');
      expect(results.authors.single.name, 'Theo Vance');
      expect(server.requests.single.uri.queryParameters['q'], 'the');
    });

    test('offline search finds books by narrator, series, genre and accents', () async {
      await repository.syncLibrary(testLibraryId);
      await repository.refreshSeriesList(testLibraryId);
      final byNarrator = await repository.searchOffline('jonah');
      expect(byNarrator.offline, isTrue);
      expect(byNarrator.books.map((b) => b.title), containsAll(['Ash Harbor', 'Cinder Interlude']));
      expect(byNarrator.narrators.map((n) => n.name), ['Jonah Pryce']);
      expect((await repository.searchOffline('EXAMPLE saga')).series.single.name, 'The Example Saga');
      expect((await repository.searchOffline('nature')).genres.single.name, 'Nature');
      expect((await repository.searchOffline('   ')).isEmpty, isTrue);
    });

    test('a cancelled search fails as cancelled, never with stale results', () async {
      final gate = Completer<void>();
      server.delays['/api/libraries/$testLibraryId/search'] = gate.future;
      final cancel = CancelToken();
      final pending = repository.search(testLibraryId, 'old', cancel: cancel);
      cancel.cancel();
      gate.complete();
      await expectLater(pending, throwsA(isA<AbsCancelled>()));
    });
  });
}
