// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/db/global_db.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/util/natural_sort.dart';
import '../../../core/util/streams.dart';
import '../../accounts/data/account_session.dart';
import '../../home/data/home_repository.dart';
import '../../local_library/data/local_library_repository.dart';
import '../../local_library/data/providers.dart';
import 'library_repository.dart';

// The source-agnostic layer the screens use. Every provider here answers
// the same question for the current Audiobookshelf account and for On this
// device, so a screen never branches on where a book comes from.

/// Settings keys of the browsing screens (GlobalDb settings).
abstract final class LibrarySettingKeys {
  /// `local`, or `abs:<accountId>/<libraryId>`.
  static const selection = 'library.selection';

  /// Prefix of the grid or list choice, per library key.
  static const layoutPrefix = 'library.layout.';

  /// JSON list of the last searches, newest first.
  static const recentSearches = 'search.recent';
}

/// The library id of the On this device source: it has exactly one.
const localLibraryId = 'local';

const localLibrary = LibraryInfo(source: LocalSource(), id: localLibraryId, name: '');

/// The repository of the current Audiobookshelf account, or null when there
/// is none. It applies live socket changes to the cache for as long as the
/// account is current.
final absLibraryRepositoryProvider = Provider<AbsLibraryRepository?>((ref) {
  final session = ref.watch(accountSessionProvider);
  if (session == null) return null;
  final repository = AbsLibraryRepository(
    db: session.db,
    client: session.client,
    source: AbsSource(session.accountId),
  );
  final sub = session.socket.events.listen((event) async {
    try {
      await repository.apply(event);
    } on Object {
      // A live update that fails to apply is picked up by the next refresh.
    }
  });
  ref.onDispose(sub.cancel);
  return repository;
});

/// The repository for [source] when it is the current account. Books of an
/// account that is not current cannot be browsed until the user switches.
AbsLibraryRepository? absRepositoryFor(Ref ref, SourceId source) {
  if (source is! AbsSource) return null;
  final repository = ref.watch(absLibraryRepositoryProvider);
  return repository?.source == source ? repository : null;
}

final homeRepositoryProvider = Provider<HomeRepository?>((ref) {
  final library = ref.watch(absLibraryRepositoryProvider);
  return library == null ? null : HomeRepository(library);
});

/// Custom reverse-proxy headers of the current account, for cover requests.
final coverHeadersProvider = FutureProvider<Map<String, String>>((ref) async {
  final session = ref.watch(accountSessionProvider);
  if (session == null) return const {};
  return ref.watch(secureStoreProvider).readCustomHeaders(session.accountId);
});

/// The server libraries of the current account (empty without one).
final absLibrariesProvider = StreamProvider<List<LibraryInfo>>((ref) {
  final repository = ref.watch(absLibraryRepositoryProvider);
  if (repository == null) return Stream.value(const []);
  unawaited(repository.refreshLibraries().catchError((Object _) {}));
  return repository.watchLibraries();
});

final _selectionKeyProvider = StreamProvider<String?>(
  (ref) => ref.watch(globalDbProvider).watchSetting(LibrarySettingKeys.selection),
);

/// Every place the user can browse: each server library, then On this
/// device.
final availableLibrariesProvider = Provider<AsyncValue<List<LibraryInfo>>>((ref) {
  final abs = ref.watch(absLibrariesProvider);
  return abs.whenData((list) => [...list, localLibrary]);
});

/// The library the Home and Library tabs show. Falls back to the first
/// server library, else On this device.
final currentLibraryProvider = Provider<AsyncValue<LibraryInfo>>((ref) {
  final key = ref.watch(_selectionKeyProvider);
  final libraries = ref.watch(absLibrariesProvider);
  if (!key.hasValue || !libraries.hasValue) return const AsyncLoading();
  final selected = key.value;
  final list = libraries.value!;
  if (selected == localLibraryId) return const AsyncData(localLibrary);
  for (final l in list) {
    if (selected == selectionKey(l)) return AsyncData(l);
  }
  final books = list.where((l) => !l.isPodcast);
  if (books.isNotEmpty) return AsyncData(books.first);
  if (list.isNotEmpty) return AsyncData(list.first);
  return const AsyncData(localLibrary);
});

String selectionKey(LibraryInfo library) => switch (library.source) {
  LocalSource() => localLibraryId,
  AbsSource(:final accountId) => 'abs:$accountId/${library.id}',
};

/// Makes [library] the one Home and Library show, remembered across starts.
Future<void> selectLibrary(GlobalDb db, LibraryInfo library) =>
    db.writeSetting(LibrarySettingKeys.selection, selectionKey(library));

/// A place in a source: the source plus a library id (always
/// [localLibraryId] for On this device).
typedef LibraryKey = ({SourceId source, String libraryId});

LibraryKey libraryKeyOf(LibraryInfo library) => (source: library.source, libraryId: library.id);

// --- Books ---

/// Arguments of [libraryBooksProvider]. [limit] grows as the user scrolls.
typedef BooksArgs = ({SourceId source, String libraryId, LibraryQuery query, int limit});

final libraryBooksProvider = StreamProvider.autoDispose.family<List<BookSummary>, BooksArgs>((ref, args) {
  switch (args.source) {
    case LocalSource():
      return ref
          .watch(localLibraryRepositoryProvider)
          .watchBooks(sort: LocalBookSort.title)
          .map((books) => applyLocalQuery(books, args.query).take(args.limit).toList());
    case AbsSource():
      final repository = absRepositoryFor(ref, args.source);
      if (repository == null) return Stream.value(const []);
      return repository.watchBooks(args.libraryId, args.query, limit: args.limit);
  }
});

/// Sort and filters for local books, which are few enough to sort in
/// memory.
List<BookSummary> applyLocalQuery(List<BookSummary> books, LibraryQuery query) {
  bool matches(BookSummary b) {
    for (final f in query.filters) {
      final ok = switch (f.kind) {
        FilterKind.progress => switch (f.value) {
          ProgressFilterValue.finished => b.progress?.isFinished ?? false,
          ProgressFilterValue.inProgress => (b.progress?.isStarted ?? false) && !(b.progress?.isFinished ?? false),
          _ => !(b.progress?.isStarted ?? false),
        },
        FilterKind.author => b.authors.contains(f.value),
        FilterKind.narrator => b.narrators.contains(f.value),
        FilterKind.series => b.seriesName == f.value,
        FilterKind.downloaded => true,
        FilterKind.genre || FilterKind.tag || FilterKind.language => true,
      };
      if (!ok) return false;
    }
    return true;
  }

  int byTitle(BookSummary a, BookSummary b) => compareNatural(a.title, b.title);
  final sorted = books.where(matches).toList();
  int compare(BookSummary a, BookSummary b) => switch (query.sort) {
    LibrarySort.title || LibrarySort.publishedYear => byTitle(a, b),
    LibrarySort.author => compareNatural(a.authorLine, b.authorLine),
    LibrarySort.addedAt => (a.addedAt ?? DateTime(0)).compareTo(b.addedAt ?? DateTime(0)),
    LibrarySort.duration => a.duration.compareTo(b.duration),
    LibrarySort.progress => (b.progress?.updatedAt ?? DateTime(0)).compareTo(a.progress?.updatedAt ?? DateTime(0)),
  };
  sorted.sort((a, b) {
    if (query.filterOf(FilterKind.series) != null) {
      final bySequence = compareNatural(a.seriesSequence ?? '~', b.seriesSequence ?? '~');
      if (bySequence != 0) return bySequence;
    }
    final c = compare(a, b);
    final directed = query.descending ? -c : c;
    return directed != 0 ? directed : byTitle(a, b);
  });
  return sorted;
}

/// Choices for the filter sheet.
final filterChoicesProvider = StreamProvider.autoDispose.family<FilterChoices, LibraryKey>((ref, key) {
  switch (key.source) {
    case LocalSource():
      return ref.watch(localLibraryRepositoryProvider).watchBooks().map((books) {
        Set<String> all(Iterable<String> names) => names.toSet();
        List<String> sorted(Set<String> s) => s.toList()..sort(compareNatural);
        return FilterChoices(
          authors: sorted(all(books.expand((b) => b.authors))),
          narrators: sorted(all(books.expand((b) => b.narrators))),
          series: [
            for (final s in sorted(all(books.map((b) => b.seriesName).whereType<String>()))) (s, s),
          ],
        );
      });
    case AbsSource():
      final repository = absRepositoryFor(ref, key.source);
      if (repository == null) return Stream.value(FilterChoices.empty);
      unawaited(repository.refreshFilterData(key.libraryId).catchError((Object _) {}));
      return repository.watchFilterChoices(key.libraryId);
  }
});

// --- Series, authors, collections, playlists ---

final seriesListProvider = StreamProvider.autoDispose.family<List<SeriesSummary>, LibraryKey>((ref, key) {
  switch (key.source) {
    case LocalSource():
      return ref.watch(localLibraryRepositoryProvider).watchBooks(sort: LocalBookSort.title).map(localSeries);
    case AbsSource():
      final repository = absRepositoryFor(ref, key.source);
      if (repository == null) return Stream.value(const []);
      return repository.watchSeriesList(key.libraryId);
  }
});

/// Local books grouped by series name, books in natural sequence order.
List<SeriesSummary> localSeries(List<BookSummary> books) {
  final groups = <String, List<BookSummary>>{};
  for (final b in books) {
    final name = b.seriesName;
    if (name != null && name.trim().isNotEmpty) (groups[name] ??= []).add(b);
  }
  final names = groups.keys.toList()..sort(compareNatural);
  return [
    for (final name in names)
      SeriesSummary(
        source: const LocalSource(),
        id: name,
        name: name,
        books: groups[name]!..sort((a, b) => compareNatural(a.seriesSequence ?? '~', b.seriesSequence ?? '~')),
        bookCount: groups[name]!.length,
      ),
  ];
}

typedef ItemKey = ({SourceId source, String id});

final seriesProvider = StreamProvider.autoDispose.family<SeriesSummary?, ItemKey>((ref, key) {
  switch (key.source) {
    case LocalSource():
      return ref.watch(localLibraryRepositoryProvider).watchBooks(sort: LocalBookSort.title).map((books) {
        for (final s in localSeries(books)) {
          if (s.id == key.id) return s;
        }
        return null;
      });
    case AbsSource():
      final repository = absRepositoryFor(ref, key.source);
      if (repository == null) return Stream.value(null);
      return repository.watchSeries(key.id);
  }
});

final authorsListProvider = StreamProvider.autoDispose.family<List<AuthorSummary>, LibraryKey>((ref, key) {
  switch (key.source) {
    case LocalSource():
      return ref.watch(localLibraryRepositoryProvider).watchBooks().map((books) {
        final counts = <String, int>{};
        for (final b in books) {
          for (final a in b.authors) {
            counts[a] = (counts[a] ?? 0) + 1;
          }
        }
        final names = counts.keys.toList()..sort(compareNatural);
        return [
          for (final n in names) AuthorSummary(source: const LocalSource(), id: n, name: n, bookCount: counts[n]!),
        ];
      });
    case AbsSource():
      final repository = absRepositoryFor(ref, key.source);
      if (repository == null) return Stream.value(const []);
      return repository.watchAuthors(key.libraryId);
  }
});

/// An author for the Author screen. On this device has no author entity:
/// the id is the name.
final authorProvider = StreamProvider.autoDispose.family<AuthorSummary?, ItemKey>((ref, key) {
  switch (key.source) {
    case LocalSource():
      return Stream.value(AuthorSummary(source: key.source, id: key.id, name: key.id));
    case AbsSource():
      final repository = absRepositoryFor(ref, key.source);
      if (repository == null) return Stream.value(null);
      return repository.watchAuthor(key.id);
  }
});

/// An author's books grouped by series (in sequence order), then the books
/// in no series as a last group with an empty id.
typedef AuthorBooks = ({List<SeriesSummary> series, List<BookSummary> standalone});

typedef AuthorBooksArgs = ({SourceId source, String libraryId, String name});

final authorBooksProvider = StreamProvider.autoDispose.family<AuthorBooks, AuthorBooksArgs>((ref, args) {
  final filter = LibraryQuery(filters: [LibraryFilter(FilterKind.author, args.name)]);
  final books = ref.watch(
    libraryBooksProvider((source: args.source, libraryId: args.libraryId, query: filter, limit: 1000)).future,
  );
  switch (args.source) {
    case LocalSource():
      return Stream.fromFuture(books).map((list) {
        final series = localSeries(list);
        return (series: series, standalone: list.where((b) => b.seriesName == null).toList());
      });
    case AbsSource():
      final repository = absRepositoryFor(ref, args.source);
      if (repository == null) return Stream.value((series: const <SeriesSummary>[], standalone: const <BookSummary>[]));
      return combineLatest2(Stream.fromFuture(books), repository.watchSeriesOfAuthor(args.libraryId, args.name), (
        List<BookSummary> all,
        List<SeriesSummary> series,
      ) {
        final inSeries = {for (final s in series) ...s.books.map((b) => b.ref)};
        // A series lists all its books, also those by other authors: keep
        // only this author's.
        final mine = {for (final b in all) b.ref};
        final own = [
          for (final s in series)
            if (s.books.any((b) => mine.contains(b.ref)))
              SeriesSummary(
                source: s.source,
                id: s.id,
                name: s.name,
                books: s.books.where((b) => mine.contains(b.ref)).toList(),
                bookCount: s.books.where((b) => mine.contains(b.ref)).length,
              ),
        ];
        return (series: own, standalone: all.where((b) => !inSeries.contains(b.ref)).toList());
      });
  }
});

final collectionsProvider = StreamProvider.autoDispose.family<List<BookListSummary>, LibraryKey>((ref, key) {
  final repository = absRepositoryFor(ref, key.source);
  if (repository == null) return Stream.value(const []);
  return repository.watchCollections(key.libraryId);
});

final collectionProvider = StreamProvider.autoDispose.family<BookListSummary?, ItemKey>((ref, key) {
  final repository = absRepositoryFor(ref, key.source);
  if (repository == null) return Stream.value(null);
  return repository.watchCollection(key.id);
});

final playlistsProvider = StreamProvider.autoDispose.family<List<BookListSummary>, LibraryKey>((ref, key) {
  final repository = absRepositoryFor(ref, key.source);
  if (repository == null) return Stream.value(const []);
  return repository.watchPlaylists(key.libraryId);
});

final playlistProvider = StreamProvider.autoDispose.family<BookListSummary?, ItemKey>((ref, key) {
  final repository = absRepositoryFor(ref, key.source);
  if (repository == null) return Stream.value(null);
  return repository.watchPlaylist(key.id);
});

// --- One book ---

/// Everything the detail screen shows. Null when the book is gone, or when
/// it belongs to an account that is not the current one.
final bookDetailProvider = StreamProvider.autoDispose.family<BookDetail?, ItemRef>((ref, item) {
  switch (item.source) {
    case LocalSource():
      return ref.watch(localLibraryRepositoryProvider).watchBook(item.itemId);
    case AbsSource():
      final repository = absRepositoryFor(ref, item.source);
      if (repository == null) return Stream.value(null);
      return repository.watchBook(item.itemId);
  }
});

/// The library a server book is in, for "more in this series" and filters.
final libraryOfItemProvider = FutureProvider.autoDispose.family<String?, ItemRef>((ref, item) async {
  final repository = absRepositoryFor(ref, item.source);
  if (repository == null) return item.source is LocalSource ? localLibraryId : null;
  final row = await repository.db.catalogDao.watchItem(item.itemId).first;
  return row?.item.libraryId;
});

// --- Home ---

/// In-progress books of both sources, most recent first.
final continueListeningProvider = StreamProvider.autoDispose<List<BookSummary>>((ref) {
  final local = ref
      .watch(localLibraryRepositoryProvider)
      .watchBooks(sort: LocalBookSort.recentlyPlayed)
      .map((books) => books.where((b) => (b.progress?.isStarted ?? false) && !(b.progress?.isFinished ?? false)));
  final repository = ref.watch(absLibraryRepositoryProvider);
  final server = repository == null ? Stream.value(const <BookSummary>[]) : repository.watchContinueListening();
  return combineLatest2(local, server, (Iterable<BookSummary> l, List<BookSummary> s) {
    final all = [...l, ...s]
      ..sort((a, b) => (b.progress?.updatedAt ?? DateTime(0)).compareTo(a.progress?.updatedAt ?? DateTime(0)));
    return all;
  });
});

/// The local books, newest first.
final recentLocalBooksProvider = StreamProvider.autoDispose<List<BookSummary>>(
  (ref) => ref.watch(localLibraryRepositoryProvider).watchBooks(sort: LocalBookSort.recentlyAdded),
);

final homeShelvesProvider = StreamProvider.autoDispose.family<List<HomeShelf>, String>((ref, libraryId) {
  final repository = ref.watch(homeRepositoryProvider);
  if (repository == null) return Stream.value(const []);
  return repository.watchShelves(libraryId);
});

// --- Small preferences ---

/// Grid (true) or list for a library, remembered per library.
final gridLayoutProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, libraryKey) =>
      ref.watch(globalDbProvider).watchSetting('${LibrarySettingKeys.layoutPrefix}$libraryKey').map((v) => v != 'list'),
);

final recentSearchesProvider = StreamProvider.autoDispose<List<String>>(
  (ref) => ref.watch(globalDbProvider).watchSetting(LibrarySettingKeys.recentSearches).map(decodeRecentSearches),
);

List<String> decodeRecentSearches(String? json) {
  if (json == null) return const [];
  try {
    final list = jsonDecode(json);
    return [
      if (list is List)
        for (final s in list)
          if (s is String) s,
    ];
  } on FormatException {
    return const [];
  }
}
