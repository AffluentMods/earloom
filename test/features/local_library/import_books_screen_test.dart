// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:earloom/app/router.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/features/local_library/data/import_models.dart';
import 'package:earloom/features/local_library/data/import_picker.dart';
import 'package:earloom/features/local_library/data/import_planner.dart';
import 'package:earloom/features/local_library/data/import_source.dart';
import 'package:earloom/features/local_library/data/providers.dart';
import 'package:earloom/features/local_library/ui/import_books_screen.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import 'support.dart';

class FakePicker implements ImportPicker {
  Completer<ImportSelection?>? pending;
  int filesCalls = 0;
  int folderCalls = 0;
  void Function()? onPreparing;

  @override
  Future<ImportSelection?> pickFiles({void Function()? onPreparing}) {
    filesCalls++;
    this.onPreparing = onPreparing;
    return (pending = Completer()).future;
  }

  @override
  Future<ImportSelection?> pickFolder() {
    folderCalls++;
    return (pending = Completer()).future;
  }

  @override
  Future<String?> pickImage() async => null;
}

class FakeJob implements ImportJob {
  final controller = StreamController<ImportProgress>.broadcast();
  final completer = Completer<ImportOutcome>();
  bool cancelled = false;

  @override
  Stream<ImportProgress> get progress => controller.stream;

  @override
  Future<ImportOutcome> get done => completer.future;

  @override
  void cancel() => cancelled = true;
}

class FakeImporter implements BookImporter {
  FakeImporter(this.planFor);

  final ImportPlan Function(ImportSelection selection) planFor;
  final jobs = <FakeJob>[];
  final started = <List<PlannedBook>>[];

  @override
  Future<ImportPlan> plan(ImportSelection selection) async => planFor(selection);

  @override
  ImportJob start(List<PlannedBook> books) {
    started.add(books);
    final job = FakeJob();
    jobs.add(job);
    return job;
  }
}

PlannedBook planned(String name, {int size = 4000000, DuplicateMatch? duplicateOf}) => PlannedBook(
  draft: BookDraft(
    files: [DraftFile(FakeSourceFile('$name/01.mp3', size: size))],
    folderName: name,
  ),
  fingerprint: '$size:$name',
  duplicateOf: duplicateOf,
);

void main() {
  late AppLocalizations l10n;
  late FakePicker picker;
  setUpAll(() async => l10n = await loadL10n());
  setUp(() => picker = FakePicker());

  Future<void> pumpScreen(WidgetTester tester, FakeImporter importer) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRoutes.importFiles,
      routes: [
        GoRoute(path: AppRoutes.importFiles, builder: (_, _) => const ImportBooksScreen()),
        GoRoute(
          path: AppRoutes.library,
          builder: (_, _) => const Scaffold(body: SizedBox(key: Key('library'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          importPickerProvider.overrideWithValue(picker),
          bookImporterProvider.overrideWithValue(importer),
        ],
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Lets AnimatedSwitcher finish without waiting for endless spinners.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  ImportPlan planOf(ImportSelection selection, List<PlannedBook> books, {List<String> skipped = const []}) =>
      ImportPlan(selection: selection, books: books, skippedFiles: skipped);

  testWidgets('explains what happens and offers both pickers', (tester) async {
    await pumpScreen(tester, FakeImporter((s) => planOf(s, const [])));
    expect(find.text(l10n.importTitle), findsOneWidget);
    expect(find.text(l10n.importExplanation), findsOneWidget);
    await tester.tap(find.text(l10n.importChooseFiles));
    expect(picker.filesCalls, 1);
    picker.pending!.complete(null);
    await settle(tester);
    await tester.tap(find.text(l10n.importChooseFolder));
    expect(picker.folderCalls, 1);
    picker.pending!.complete(null);
    await settle(tester);
    // Cancelled pickers leave the screen as it was.
    expect(find.text(l10n.importHeadline), findsOneWidget);
  });

  testWidgets('shows a preparing state while the picker hands files over', (tester) async {
    await pumpScreen(tester, FakeImporter((s) => planOf(s, [planned('One')])));
    await tester.tap(find.text(l10n.importChooseFiles));
    await tester.pump();
    picker.onPreparing!();
    await settle(tester);
    expect(find.text(l10n.importPreparing), findsOneWidget);
    expect(find.text(l10n.importPreparingHint), findsOneWidget);
  });

  testWidgets('copies with progress per book, then reports and opens the library', (tester) async {
    final importer = FakeImporter((s) => planOf(s, [planned('The Quiet Harbor'), planned('Second Book')]));
    await pumpScreen(tester, importer);
    await tester.tap(find.text(l10n.importChooseFolder));
    picker.pending!.complete(folder('Shelf', ['The Quiet Harbor/01.mp3', 'Second Book/01.mp3']));
    await settle(tester);

    expect(find.text(l10n.importRunningTitle(2)), findsOneWidget);
    expect(find.text('The Quiet Harbor'), findsOneWidget);
    final job = importer.jobs.single;
    job.controller.add(
      const ImportProgress(
        bookIndex: 0,
        bookCount: 2,
        bookName: 'The Quiet Harbor',
        stage: ImportStage.copying,
        bookBytesDone: 1000000,
        bookBytesTotal: 4000000,
        allBytesDone: 1000000,
        allBytesTotal: 8000000,
      ),
    );
    await tester.pump();
    expect(find.text(l10n.importBytesProgress('1 MB', '4 MB')), findsOneWidget);
    expect(find.text(l10n.importWaiting('4 MB')), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 0.125);

    job.controller.add(
      const ImportProgress(
        bookIndex: 1,
        bookCount: 2,
        bookName: 'Second Book',
        stage: ImportStage.reading,
        bookBytesDone: 4000000,
        bookBytesTotal: 4000000,
        allBytesDone: 8000000,
        allBytesTotal: 8000000,
      ),
    );
    await tester.pump();
    expect(find.text(l10n.importBookAdded), findsOneWidget);
    expect(find.text(l10n.importStageReading), findsOneWidget);

    job.completer.complete(
      const ImportOutcome(
        added: [
          ImportedBook(bookId: 'a', title: 'The Quiet Harbor'),
          ImportedBook(bookId: 'b', title: 'Second Book'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.importDoneTitle(2)), findsOneWidget);
    expect(find.text('2 books added'), findsOneWidget);
    await tester.tap(find.text(l10n.importOpenLibrary));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library')), findsOneWidget);
  });

  testWidgets('cancel stops the job and says what was kept', (tester) async {
    final importer = FakeImporter((s) => planOf(s, [planned('One'), planned('Two')]));
    await pumpScreen(tester, importer);
    await tester.tap(find.text(l10n.importChooseFiles));
    picker.pending!.complete(files(['a.mp3']));
    await settle(tester);
    await tester.tap(find.text(l10n.genericCancel));
    await tester.pump();
    final job = importer.jobs.single;
    expect(job.cancelled, isTrue);
    final cancel = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, l10n.genericCancel));
    expect(cancel.onPressed, isNull);

    job.completer.complete(
      const ImportOutcome(
        added: [ImportedBook(bookId: 'a', title: 'One')],
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.importDoneTitle(1)), findsOneWidget);
    expect(find.text(l10n.importDoneCancelled), findsOneWidget);
  });

  testWidgets('a failed book is explained in plain words with copyable details', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final importer = FakeImporter((s) => planOf(s, [planned('Broken Book')], skipped: ['notes.txt']));
    await pumpScreen(tester, importer);
    await tester.tap(find.text(l10n.importChooseFiles));
    picker.pending!.complete(files(['a.mp3', 'notes.txt']));
    await settle(tester);
    importer.jobs.single.completer.complete(
      const ImportOutcome(
        failed: [
          ImportFailure(bookName: 'Broken Book', kind: ImportErrorKind.noSpace, details: 'FileSystemException: ENOSPC'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.importDoneTitle(0)), findsOneWidget);
    expect(find.text(l10n.importErrorNoSpace), findsOneWidget);
    expect(find.text(l10n.importSkippedFiles(1)), findsOneWidget);
    await tester.tap(find.text(l10n.genericCopyDetails));
    await tester.pumpAndSettle();
    expect(copied, ['FileSystemException: ENOSPC']);
    expect(find.text(l10n.genericDetailsCopied), findsOneWidget);

    // Start over, once the snack bar is gone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.importAddMore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.importHeadline), findsOneWidget);
  });

  testWidgets('asks before adding a book that is already in the library', (tester) async {
    const existing = DuplicateMatch(bookId: 'old', title: 'Twice Told');
    final importer = FakeImporter((s) => planOf(s, [planned('Twice Told', duplicateOf: existing), planned('New One')]));
    await pumpScreen(tester, importer);
    await tester.tap(find.text(l10n.importChooseFolder));
    picker.pending!.complete(folder('Shelf', ['Twice Told/01.mp3', 'New One/01.mp3']));
    await settle(tester);

    expect(find.text(l10n.importDuplicatesTitle), findsOneWidget);
    expect(find.text(l10n.importDuplicatesBody(1)), findsOneWidget);
    expect(find.text('Twice Told'), findsOneWidget);
    await tester.tap(find.text(l10n.importSkipDuplicates));
    await settle(tester);
    expect(importer.started.single.map((b) => b.displayName), ['New One']);

    importer.jobs.single.completer.complete(
      const ImportOutcome(
        added: [ImportedBook(bookId: 'n', title: 'New One')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.importSkippedDuplicates(1)), findsOneWidget);
  });

  testWidgets('adding another copy imports every book', (tester) async {
    const existing = DuplicateMatch(bookId: 'old', title: 'Twice Told');
    final importer = FakeImporter((s) => planOf(s, [planned('Twice Told', duplicateOf: existing)]));
    await pumpScreen(tester, importer);
    await tester.tap(find.text(l10n.importChooseFiles));
    picker.pending!.complete(files(['a.mp3']));
    await settle(tester);
    await tester.tap(find.text(l10n.importAddCopies));
    await settle(tester);
    expect(importer.started.single, hasLength(1));
  });

  testWidgets('skipping the only book ends without copying', (tester) async {
    const existing = DuplicateMatch(bookId: 'old', title: 'Twice Told');
    final importer = FakeImporter((s) => planOf(s, [planned('Twice Told', duplicateOf: existing)]));
    await pumpScreen(tester, importer);
    await tester.tap(find.text(l10n.importChooseFiles));
    picker.pending!.complete(files(['a.mp3']));
    await settle(tester);
    await tester.tap(find.text(l10n.importSkipDuplicates));
    await tester.pumpAndSettle();
    expect(importer.started, isEmpty);
    expect(find.text(l10n.importDoneTitle(0)), findsOneWidget);
    expect(find.text(l10n.importOpenLibrary), findsNothing);
  });

  testWidgets('nothing playable is a plain error with a way back', (tester) async {
    await pumpScreen(tester, FakeImporter((s) => planOf(s, const [], skipped: ['notes.txt'])));
    await tester.tap(find.text(l10n.importChooseFiles));
    picker.pending!.complete(files(['notes.txt']));
    await tester.pumpAndSettle();
    expect(find.text(l10n.importFailedTitle), findsOneWidget);
    expect(find.text(l10n.importErrorNoAudio), findsOneWidget);
    expect(find.text(l10n.genericCopyDetails), findsOneWidget);
    await tester.tap(find.text(l10n.genericRetry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.importHeadline), findsOneWidget);
  });

  testWidgets('an unreadable pick is explained', (tester) async {
    await pumpScreen(tester, FakeImporter((s) => planOf(s, const [])));
    await tester.tap(find.text(l10n.importChooseFolder));
    picker.pending!.completeError(PlatformException(code: 'unreadable', message: 'denied'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.importErrorUnreadable), findsOneWidget);
  });

  testWidgets('files still in iCloud are explained', (tester) async {
    await pumpScreen(tester, FakeImporter((s) => planOf(s, const [])));
    await tester.tap(find.text(l10n.importChooseFolder));
    picker.pending!.completeError(const FolderNotDownloaded());
    await tester.pumpAndSettle();
    expect(find.text(l10n.importErrorNotDownloaded), findsOneWidget);
  });
}
