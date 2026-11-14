// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/providers.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/net/reachability.dart';
import 'package:earloom/features/downloads/data/download_manager.dart';
import 'package:earloom/features/downloads/data/offline_providers.dart';
import 'package:earloom/features/downloads/ui/download_button.dart';
import 'package:earloom/features/downloads/ui/downloads_screen.dart';
import 'package:earloom/features/downloads/ui/offline_banner.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_downloads.dart';
import '../../support/test_app.dart';

const _book = ItemRef(AbsSource('a1'), 'i1');
const _gb = 1000 * 1000 * 1000;

DownloadState _state(
  DownloadPhase phase, {
  ItemRef ref = _book,
  String title = "The Clockmaker's Tide",
  int done = 0,
  int total = _gb,
  DownloadError? error,
  DateTime? finishedAt,
  DateTime? createdAt,
}) => DownloadState(
  ref: ref,
  phase: phase,
  title: title,
  author: 'Mara Ellison',
  bytesDone: done,
  bytesTotal: total,
  error: error,
  errorDetails: error == null ? null : 'HTTP 403 Forbidden',
  finishedAt: finishedAt,
  createdAt: createdAt,
);

/// A screen in the app's theme and strings, with a fake download manager.
Future<void> _pump(WidgetTester tester, Widget child, FakeDownloadManager manager) async {
  final offline = await openTestOfflineDb(tester);
  final global = await openTestGlobalDb(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        globalDbProvider.overrideWithValue(global),
        ...offlineTestOverrides(offline),
        downloadManagerProvider.overrideWithValue(manager),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await settle(tester);
}

Widget _buttons() => const Scaffold(
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DownloadButton(itemRef: _book, title: "The Clockmaker's Tide"),
        DownloadButton(itemRef: _book, title: "The Clockmaker's Tide", compact: true),
        DownloadedBadge(itemRef: _book),
      ],
    ),
  ),
);

void main() {
  late AppLocalizations l10n;
  setUpAll(() async => l10n = await loadL10n());

  group('DownloadButton', () {
    testWidgets('each state shows its words', (tester) async {
      final manager = FakeDownloadManager();
      await _pump(tester, _buttons(), manager);
      expect(find.text(l10n.downloadAction), findsOneWidget);
      expect(find.byType(DownloadedBadge), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsNothing);

      final cases = {
        DownloadPhase.queued: l10n.downloadQueued,
        DownloadPhase.waitingForWifi: l10n.downloadWaitingWifi,
        DownloadPhase.paused: l10n.downloadPaused,
        DownloadPhase.failed: l10n.downloadFailed,
        DownloadPhase.complete: l10n.downloadDownloaded,
      };
      for (final MapEntry(key: phase, value: words) in cases.entries) {
        manager.put(_state(phase, error: phase == DownloadPhase.failed ? DownloadError.forbidden : null));
        await settle(tester);
        expect(find.text(words), findsOneWidget, reason: phase.name);
      }
      // Downloaded: the badge shows too.
      expect(find.bySemanticsLabel(l10n.downloadDownloaded), findsWidgets);

      manager.put(_state(DownloadPhase.downloading, done: _gb * 42 ~/ 100));
      await settle(tester);
      expect(find.text(l10n.downloadProgress(42)), findsOneWidget);
      expect(find.bySemanticsLabel(l10n.downloadProgressSemantics(42)), findsNWidgets(2));
    });

    testWidgets('taps start, pause, resume and retry', (tester) async {
      final manager = FakeDownloadManager();
      await _pump(tester, _buttons(), manager);

      await tester.tap(find.text(l10n.downloadAction));
      await settle(tester);
      expect(manager.calls, ['enqueue ${_book.key}']);
      expect(find.text(l10n.downloadQueuedSnack), findsOneWidget);

      manager.put(_state(DownloadPhase.downloading, done: _gb ~/ 2));
      await settle(tester);
      await tester.tap(find.text(l10n.downloadProgress(50)));
      expect(manager.calls.last, 'pause ${_book.key}');

      manager.put(_state(DownloadPhase.paused, done: _gb ~/ 2));
      await settle(tester);
      await tester.tap(find.text(l10n.downloadPaused));
      expect(manager.calls.last, 'resume ${_book.key}');

      manager.put(_state(DownloadPhase.failed, error: DownloadError.network));
      await settle(tester);
      await tester.tap(find.text(l10n.downloadFailed));
      expect(manager.calls.last, 'resume ${_book.key}');
    });

    testWidgets('a failed download explains itself and offers copy details', (tester) async {
      final manager = FakeDownloadManager({_book.key: _state(DownloadPhase.failed, error: DownloadError.forbidden)});
      await _pump(tester, _buttons(), manager);
      await tester.longPress(find.text(l10n.downloadFailed));
      await settle(tester);
      expect(find.text(l10n.downloadErrorForbidden), findsOneWidget);
      expect(find.text(l10n.genericCopyDetails), findsOneWidget);
      expect(find.text(l10n.downloadRetry), findsOneWidget);
    });

    testWidgets('downloaded: remove asks first, download again starts over', (tester) async {
      final manager = FakeDownloadManager({_book.key: _state(DownloadPhase.complete)});
      await _pump(tester, _buttons(), manager);
      await tester.tap(find.text(l10n.downloadDownloaded));
      await settle(tester);
      expect(find.text(l10n.downloadRedownload), findsOneWidget);
      await tester.tap(find.text(l10n.downloadDelete));
      await settle(tester);
      expect(find.text(l10n.downloadDeleteConfirmBody), findsOneWidget);
      await tester.tap(find.text(l10n.genericRemove));
      await settle(tester);
      expect(manager.calls, ['delete ${_book.key}']);
      expect(find.text(l10n.downloadAction), findsOneWidget);
    });

    testWidgets('books from this phone need no button', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: DownloadButton(itemRef: ItemRef(LocalSource(), 'b1'), title: 'Local'),
        ),
        FakeDownloadManager(),
      );
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('Downloads screen', () {
    testWidgets('empty: one sentence', (tester) async {
      await _pump(tester, const DownloadsScreen(), FakeDownloadManager());
      expect(find.text(l10n.downloadsEmpty), findsOneWidget);
      expect(find.text(l10n.downloadsEmptyBody), findsOneWidget);
    });

    testWidgets('active and downloaded sections, pause all, storage', (tester) async {
      const second = ItemRef(AbsSource('a1'), 'i2');
      const third = ItemRef(AbsSource('a1'), 'i3');
      final manager = FakeDownloadManager({
        _book.key: _state(DownloadPhase.downloading, done: _gb ~/ 2),
        second.key: _state(DownloadPhase.complete, ref: second, title: 'Kindling Sky', total: 2 * _gb),
        third.key: _state(DownloadPhase.complete, ref: third, title: 'A Field Guide to Quiet Places', total: _gb),
      });
      await _pump(tester, const DownloadsScreen(), manager);
      expect(find.text(l10n.downloadsActive), findsOneWidget);
      expect(find.text(l10n.downloadsCompleted), findsOneWidget);
      expect(find.text('Kindling Sky'), findsOneWidget);
      // Half of the active one plus 3 GB downloaded.
      expect(find.text(l10n.downloadsStorageUsedOnly('3.5 GB')), findsOneWidget);

      await tester.tap(find.text(l10n.downloadsPauseAll));
      expect(manager.calls, ['pauseAll']);

      // Sort by size: the 2 GB book comes first.
      await tester.tap(find.byTooltip(l10n.downloadsSort));
      await settle(tester);
      await tester.tap(find.text(l10n.downloadsSortSize));
      await settle(tester);
      final kindling = tester.getTopLeft(find.text('Kindling Sky')).dy;
      final guide = tester.getTopLeft(find.text('A Field Guide to Quiet Places')).dy;
      expect(kindling, lessThan(guide));
    });

    testWidgets('select several and remove them', (tester) async {
      const second = ItemRef(AbsSource('a1'), 'i2');
      final manager = FakeDownloadManager({
        _book.key: _state(DownloadPhase.complete),
        second.key: _state(DownloadPhase.complete, ref: second, title: 'Kindling Sky'),
      });
      await _pump(tester, const DownloadsScreen(), manager);
      await tester.longPress(find.text('Kindling Sky'));
      await settle(tester);
      await tester.tap(find.text("The Clockmaker's Tide"));
      await settle(tester);
      expect(find.text(l10n.downloadsSelectedCount(2)), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.downloadsDeleteSelected(2)));
      await settle(tester);
      await tester.tap(find.text(l10n.genericRemove));
      await settle(tester);
      expect(manager.calls.toSet(), {'delete ${_book.key}', 'delete ${second.key}'});
      expect(find.text(l10n.downloadsEmpty), findsOneWidget);
    });

    testWidgets('remove finished books leaves unfinished ones', (tester) async {
      const second = ItemRef(AbsSource('a1'), 'i2');
      final manager = FakeDownloadManager({
        _book.key: _state(DownloadPhase.complete, finishedAt: DateTime(2026, 11, 1)),
        second.key: _state(DownloadPhase.complete, ref: second, title: 'Kindling Sky'),
      });
      await _pump(tester, const DownloadsScreen(), manager);
      await tester.tap(find.descendant(of: find.byType(AppBar), matching: find.byTooltip(l10n.downloadsMore)));
      await settle(tester);
      await tester.tap(find.text(l10n.downloadsDeleteFinished));
      await settle(tester);
      expect(find.text(l10n.downloadsDeleteFinishedBody(1)), findsOneWidget);
      await tester.tap(find.text(l10n.genericRemove));
      await settle(tester);
      expect(manager.calls, ['delete ${_book.key}']);
      expect(find.text('Kindling Sky'), findsOneWidget);
    });
  });

  testWidgets('the offline banner shows only while the server does not answer', (tester) async {
    final offline = await openTestOfflineDb(tester);
    final global = await openTestGlobalDb(tester);
    var answers = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          globalDbProvider.overrideWithValue(global),
          ...offlineTestOverrides(offline, pinger: (_, _) async => answers),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const OfflineBanner(child: Scaffold(body: Text('Home'))),
        ),
      ),
    );
    await settle(tester);
    expect(find.text(l10n.offlineBanner), findsNothing);

    final container = ProviderScope.containerOf(tester.element(find.text('Home')));
    final reach = container.read(reachabilityProvider);
    answers = false;
    await tester.runAsync(() => reach.setServer(Uri.parse('https://books.example.com')));
    await settle(tester);
    expect(reach.value, ServerReach.offline);
    expect(find.text(l10n.offlineBanner), findsOneWidget);

    answers = true;
    await tester.tap(find.text(l10n.offlineBannerCheck));
    await settle(tester);
    expect(find.text(l10n.offlineBanner), findsNothing);
  });
}
