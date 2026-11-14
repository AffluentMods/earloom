// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_db.dart';
import '../../../core/library/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'import_models.dart';
import 'import_picker.dart';
import 'local_importer.dart';
import 'local_library_repository.dart';
import 'local_storage.dart';

/// The On this device database. Opened in `main` next to GlobalDb and
/// provided through an override; tests override it with an in-memory one.
final localDbProvider = Provider<LocalDb>(
  (ref) => throw StateError('localDbProvider must be overridden at startup'),
);

/// Where imported books are stored: `<application support>/local`. Set in
/// `main`; tests point it at a temporary directory.
final localStorageProvider = Provider<LocalStorage>(
  (ref) => throw StateError('localStorageProvider must be overridden at startup'),
);

/// Words the repository puts into chapters and the Now Playing series line,
/// in the device language.
final localLibraryStringsProvider = Provider<LocalLibraryStrings>((ref) {
  final locale = basicLocaleListResolution(PlatformDispatcher.instance.locales, AppLocalizations.supportedLocales);
  final l10n = lookupAppLocalizations(locale);
  return LocalLibraryStrings(
    untitledChapter: l10n.chapterNumber,
    seriesLine: (series, sequence) => sequence == null ? series : l10n.seriesBookOf(sequence, series),
  );
});

final localLibraryRepositoryProvider = Provider<LocalLibraryRepository>(
  (ref) => LocalLibraryRepository(
    db: ref.watch(localDbProvider),
    storage: ref.watch(localStorageProvider),
    strings: ref.watch(localLibraryStringsProvider),
  ),
);

/// Imports picked files. A [BookImporter] so the import screen can be
/// tested with a fake.
final bookImporterProvider = Provider<BookImporter>(
  (ref) => LocalImporter(db: ref.watch(localDbProvider), storage: ref.watch(localStorageProvider)),
);

/// The system pickers. Overridden in widget tests.
final importPickerProvider = Provider<ImportPicker>((ref) => const PlatformImportPicker());

/// The local books in the given order, filtered by an optional search.
final localBooksProvider = StreamProvider.autoDispose.family<List<BookSummary>, ({LocalBookSort sort, String? query})>(
  (ref, args) => ref.watch(localLibraryRepositoryProvider).watchBooks(sort: args.sort, query: args.query),
);

final localBookProvider = StreamProvider.autoDispose.family<BookDetail?, String>(
  (ref, id) => ref.watch(localLibraryRepositoryProvider).watchBook(id),
);

final localProgressProvider = StreamProvider.autoDispose.family<ListeningProgress?, String>(
  (ref, id) => ref.watch(localLibraryRepositoryProvider).watchProgress(id),
);

final localBookmarksProvider = StreamProvider.autoDispose.family<List<Bookmark>, String>(
  (ref, id) => ref.watch(localLibraryRepositoryProvider).watchBookmarks(id),
);
