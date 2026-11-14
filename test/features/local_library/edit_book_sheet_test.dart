// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/features/local_library/data/import_source.dart';
import 'package:earloom/features/local_library/data/local_importer.dart';
import 'package:earloom/features/local_library/data/local_storage.dart';
import 'package:earloom/features/local_library/data/providers.dart';
import 'package:earloom/features/local_library/data/tags/file_tags.dart';
import 'package:earloom/features/local_library/ui/edit_book_sheet.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import 'support.dart';

void main() {
  late AppLocalizations l10n;

  /// Drift answers on the real event loop: give it real time, then let the
  /// sheet's animations finish.
  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  setUpAll(() async => l10n = await loadL10n());

  /// Unmounts the sheet, which ends its database streams. The in-memory
  /// database is left to the garbage collector: closing it from a widget
  /// test waits on stream work scheduled in the test's fake clock.
  Future<void> tearDownDb(WidgetTester tester, LocalDb db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<({LocalDb db, LocalStorage storage, String id})> seed(WidgetTester tester) async {
    late LocalDb db;
    late LocalStorage storage;
    late String id;
    await tester.runAsync(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = LocalDb(NativeDatabase.memory());
      storage = await tempStorage();
      final importer = LocalImporter(
        db: db,
        storage: storage,
        readTags: (paths) async => [
          const FileTags(
            album: 'The Glass Orchard',
            albumArtist: 'Example, Mira',
            composer: 'Theo Reader',
            duration: Duration(seconds: 5),
          ),
        ],
      );
      final plan = await importer.plan(PickedFiles([FakeSourceFile('01.mp3')]));
      id = (await importer.start(plan.books).done).added.single.bookId;
    });
    return (db: db, storage: storage, id: id);
  }

  Future<void> pumpSheetHost(WidgetTester tester, LocalDb db, LocalStorage storage, String id) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDbProvider.overrideWithValue(db),
          localStorageProvider.overrideWithValue(storage),
          localLibraryStringsProvider.overrideWithValue(testStrings),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(onPressed: () => showEditBookSheet(context, id), child: const Icon(Icons.edit)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.edit));
    await settleDb(tester);
  }

  testWidgets('shows the stored details, ready to edit', (tester) async {
    final (:db, :storage, :id) = await seed(tester);
    await pumpSheetHost(tester, db, storage, id);

    expect(find.text(l10n.editBookTitle), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'The Glass Orchard'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Example, Mira'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Theo Reader'), findsOneWidget);
    expect(find.text(l10n.editBookNamesHint), findsNWidgets(2));
    expect(find.text(l10n.editBookChangeCover), findsOneWidget);
    expect(find.bySemanticsLabel(l10n.bookNoCoverLabel), findsOneWidget);
    await tearDownDb(tester, db);
  });

  testWidgets('saves edits and closes', (tester) async {
    final (:db, :storage, :id) = await seed(tester);
    await pumpSheetHost(tester, db, storage, id);
    await tester.enterText(find.widgetWithText(TextFormField, 'The Glass Orchard'), 'The Glass Orchard, Revised');
    await tester.enterText(find.widgetWithText(TextFormField, 'Theo Reader'), 'Theo Reader, Ada Voice');
    await tester.enterText(find.widgetWithText(TextFormField, l10n.editBookFieldSeries), 'Orchard Tales');
    await tester.enterText(find.widgetWithText(TextFormField, l10n.editBookFieldSequence), '2');
    await tester.tap(find.text(l10n.genericSave));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(l10n.editBookTitle), findsNothing);
    final row = await db.select(db.localBooks).getSingle();
    expect(row.title, 'The Glass Orchard, Revised');
    // Untouched: the single "Last, First" name survives the save.
    expect(row.authors, ['Example, Mira']);
    expect(row.narrators, ['Theo Reader', 'Ada Voice']);
    expect(row.seriesName, 'Orchard Tales');
    expect(row.seriesSequence, '2');
    await tearDownDb(tester, db);
  });

  testWidgets('an empty title is not saved', (tester) async {
    final (:db, :storage, :id) = await seed(tester);
    await pumpSheetHost(tester, db, storage, id);
    await tester.enterText(find.widgetWithText(TextFormField, 'The Glass Orchard'), '   ');
    await tester.tap(find.text(l10n.genericSave));
    await settleDb(tester);
    expect(find.text(l10n.editBookTitleRequired), findsOneWidget);
    expect(find.text(l10n.editBookTitle), findsOneWidget);
    await tearDownDb(tester, db);
  });
}
