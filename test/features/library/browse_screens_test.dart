// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/accounts/data/account_session.dart';
import 'package:earloom/features/home/ui/home_screen.dart';
import 'package:earloom/features/item_detail/ui/item_detail_screen.dart';
import 'package:earloom/features/library/ui/series_screen.dart';
import 'package:earloom/features/search/ui/search_screen.dart';
import 'package:earloom/features/local_library/data/local_search_text.dart';
import 'package:earloom/features/player/player_controller.dart';
import 'package:earloom/features/player/playable.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import 'abs_support.dart';

const clockmaker = '695b9eb3-1a88-4320-b033-95089797f205';

/// Records what the screens ask the player to play, without playing.
class PlayRecorder {
  final calls = <(ItemRef, Duration?)>[];

  Future<(PlayableBook, StartDecision)> resolve(ItemRef item, {Duration? startAt}) async {
    calls.add((item, startAt));
    throw StateError('not playing in tests');
  }
}

List<Override> playerOverrides(PlayRecorder recorder) => [
  bookResolverProvider.overrideWithValue(recorder.resolve),
];

/// Adds a local book (no files: the screens only read rows).
Future<void> addLocalBook(
  WidgetTester tester,
  LocalDb db, {
  required String id,
  required String title,
  String author = 'Mira Example',
  String narrator = 'Theo Reader',
  String? series,
  String? sequence,
  int durationMs = 3600000,
  int? positionMs,
  bool finished = false,
  int addedAt = 1,
  int updatedAt = 1000,
  int chapters = 0,
}) async {
  await tester.runAsync(() async {
    await db
        .into(db.localBooks)
        .insert(
          LocalBooksCompanion.insert(
            id: id,
            title: title,
            authors: [author],
            narrators: [narrator],
            genres: const [],
            seriesName: Value(series),
            seriesSequence: Value(sequence),
            sourceFormat: 'mp3',
            fingerprint: '1:$id',
            durationMs: Value(durationMs),
            sortTitle: LocalSearchText.sortTitle(title),
            sortAuthor: LocalSearchText.sortAuthor([author]),
            searchText: LocalSearchText.searchText(
              title: title,
              authors: [author],
              narrators: [narrator],
              seriesName: series,
            ),
            addedAtMs: addedAt,
            updatedAtMs: addedAt,
          ),
        );
    for (var i = 0; i < chapters; i++) {
      final length = durationMs ~/ chapters;
      await db
          .into(db.localChapters)
          .insert(
            LocalChaptersCompanion.insert(
              bookId: id,
              idx: i,
              title: Value('Part ${i + 1}'),
              startMs: i * length,
              endMs: (i + 1) * length,
            ),
          );
    }
    if (positionMs != null || finished) {
      await db
          .into(db.localProgress)
          .insert(
            LocalProgressCompanion.insert(
              bookId: id,
              positionMs: positionMs ?? durationMs,
              durationMs: durationMs,
              isFinished: Value(finished),
              updatedAtMs: updatedAt,
              lastPlayedAtMs: Value(updatedAt),
            ),
          );
    }
  });
}

/// The vertical scroll view of a screen (shelves inside it scroll sideways).
Finder mainScroll(Type screen) => find
    .descendant(
      of: find.byType(screen),
      matching: find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical),
    )
    .first;

/// A widget test with covers requested from the (fake) server. The cover
/// cache arms a cleanup timer the test has to let run out.
void serverTest(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pump(const Duration(seconds: 11));
  });
}

void main() {
  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await loadL10n();
    await loadAppFonts();
  });

  Future<({LocalDb local, PlayRecorder player})> pumpLocal(
    WidgetTester tester, {
    List<Override> extra = const [],
  }) async {
    usePhoneSize(tester);
    final local = await openTestLocalDb(tester);
    final player = PlayRecorder();
    return (local: local, player: player);
  }

  group('On this device only (no server)', () {
    testWidgets('Home welcomes a new user with both ways in', (tester) async {
      final setup = await pumpLocal(tester);
      await pumpEarloom(tester, localDb: setup.local, overrides: playerOverrides(setup.player));
      await settle(tester);
      expect(find.text(l10n.homeWelcomeTitle), findsOneWidget);
      expect(find.text(l10n.onboardingConnectServer), findsOneWidget);
      expect(find.text(l10n.homeAddFiles), findsOneWidget);
    });

    testWidgets('Home shows the book in progress; Resume plays it without leaving Home', (tester) async {
      final setup = await pumpLocal(tester);
      await addLocalBook(tester, setup.local, id: 'b1', title: 'The Glass Orchard', positionMs: 600000, updatedAt: 50);
      await addLocalBook(tester, setup.local, id: 'b2', title: 'Salt and Static', positionMs: 60000, updatedAt: 90);
      await addLocalBook(tester, setup.local, id: 'b3', title: 'Lantern Days', addedAt: 5);
      await pumpEarloom(tester, localDb: setup.local, overrides: playerOverrides(setup.player));
      await settle(tester);

      // The most recent in-progress book is the hero; the other one waits
      // on the Continue listening shelf.
      final hero = find.byType(HomeScreen);
      expect(find.descendant(of: hero, matching: find.text('Salt and Static')), findsWidgets);
      expect(find.text(l10n.homeContinueListening), findsWidgets);
      await tester.scrollUntilVisible(find.text(l10n.homeShelfRecentlyAdded), 200, scrollable: mainScroll(HomeScreen));
      await tester.scrollUntilVisible(find.text(l10n.homeResume), -200, scrollable: mainScroll(HomeScreen));

      await tester.tap(find.text(l10n.homeResume));
      await settle(tester);
      expect(setup.player.calls.single.$1, const ItemRef(LocalSource(), 'b2'));
      expect(find.byType(ItemDetailScreen), findsNothing);
    });

    testWidgets('Library lists local books, grid and list, with On this device as the library', (tester) async {
      final setup = await pumpLocal(tester);
      await addLocalBook(tester, setup.local, id: 'b1', title: 'Book 10', series: 'Saga', sequence: '10');
      await addLocalBook(tester, setup.local, id: 'b2', title: 'Book 2', series: 'Saga', sequence: '2');
      await pumpEarloom(tester, localDb: setup.local, overrides: playerOverrides(setup.player));
      await tester.tap(find.text(l10n.tabLibrary));
      await settle(tester);

      expect(find.text(l10n.sourceOnThisDevice), findsWidgets);
      // Natural order by title: 2 before 10.
      expect(tester.getTopLeft(find.text('Book 2')).dx, lessThan(tester.getTopLeft(find.text('Book 10')).dx));

      await tester.tap(find.byTooltip(l10n.libraryList));
      await settle(tester);
      expect(tester.getTopLeft(find.text('Book 2')).dy, lessThan(tester.getTopLeft(find.text('Book 10')).dy));

      // Series section groups them in sequence order.
      await tester.tap(find.text(l10n.librarySeries));
      await settle(tester);
      expect(find.text('Saga'), findsOneWidget);
      await tester.tap(find.text('Saga'));
      await settle(tester);
      expect(find.byType(SeriesScreen), findsOneWidget);
      expect(find.text(l10n.seriesStart), findsOneWidget);
    });

    testWidgets('Item detail of a local book: chapters play from their start; delete asks first', (tester) async {
      final setup = await pumpLocal(tester);
      const id = '0b1c2d3e-4f50-4617-8899-aabbccddeeff';
      await addLocalBook(tester, setup.local, id: id, title: 'The Glass Orchard', positionMs: 1000000, chapters: 4);
      await pumpEarloom(tester, localDb: setup.local, overrides: playerOverrides(setup.player));
      await settle(tester);
      await tester.tap(find.text('The Glass Orchard').first);
      await settle(tester);

      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(find.textContaining(l10n.itemResume), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Part 3'), 200, scrollable: mainScroll(ItemDetailScreen));
      expect(find.text(l10n.itemChapters), findsOneWidget);
      await tester.ensureVisible(find.text('Part 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Part 3'));
      await settle(tester);
      expect(setup.player.calls.single, (const ItemRef(LocalSource(), id), const Duration(milliseconds: 1800000)));

      await tester.tap(find.byTooltip(l10n.itemMoreActions));
      await settle(tester);
      expect(find.text(l10n.itemEdit), findsOneWidget);
      await tester.tap(find.text(l10n.itemDeleteLocal));
      await settle(tester);
      expect(find.text(l10n.itemDeleteLocalTitle), findsOneWidget);
      await tester.tap(find.text(l10n.genericDelete));
      await settle(tester, rounds: 12);
      expect(find.byType(ItemDetailScreen), findsNothing);
      final left = await tester.runAsync(() => setup.local.select(setup.local.localBooks).get());
      expect(left, isEmpty);
    });

    testWidgets('Search finds local books by narrator and remembers the search', (tester) async {
      final setup = await pumpLocal(tester);
      await addLocalBook(tester, setup.local, id: 'b1', title: 'The Glass Orchard', narrator: 'Priya Castellan');
      await pumpEarloom(tester, localDb: setup.local, overrides: playerOverrides(setup.player));
      await tester.tap(find.text(l10n.tabSearch));
      await settle(tester);
      expect(find.text(l10n.searchStartTitle), findsOneWidget);

      await tester.enterText(find.byType(SearchBar), 'castellan');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(find.text(l10n.searchGroupOnThisDevice), findsOneWidget);
      expect(find.text('The Glass Orchard'), findsOneWidget);
    });
  });

  group('with a server account', () {
    Future<({FakeAbsServer server, PlayRecorder player, LocalDb local})> pumpServer(
      WidgetTester tester, {
      void Function(FakeAbsServer server)? configure,
      bool withLocal = false,
    }) async {
      usePhoneSize(tester);
      final server = FakeAbsServer();
      configure?.call(server);
      final db = await openTestAccountDb(tester);
      final session = await tester.runAsync(() => fakeSession(server, db));
      final local = await openTestLocalDb(tester);
      if (withLocal) await addLocalBook(tester, local, id: 'l1', title: 'Pocket Atlas');
      final player = PlayRecorder();
      await pumpEarloom(
        tester,
        localDb: local,
        overrides: [...playerOverrides(player), accountSessionProvider.overrideWithValue(session)],
      );
      await settle(tester, rounds: 10);
      return (server: server, player: player, local: local);
    }

    serverTest('Home: the server book in progress, shelves in server order, and On this device', (tester) async {
      await pumpServer(tester, withLocal: true);
      expect(find.text("The Clockmaker's Tide"), findsWidgets);
      expect(find.text(l10n.homeResume), findsOneWidget);
      // Library switcher, since there are server libraries and this phone.
      expect(find.text('Audiobooks'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(l10n.homeShelfContinueSeries), 200, scrollable: mainScroll(HomeScreen));
      await tester.scrollUntilVisible(find.text(l10n.homeShelfRecentlyAdded), 200, scrollable: mainScroll(HomeScreen));
      await tester.scrollUntilVisible(find.text(l10n.homeShelfOnThisDevice), 200, scrollable: mainScroll(HomeScreen));
      expect(find.text('Pocket Atlas'), findsOneWidget);
    });

    serverTest('Item detail of a server book: header, chapters, details, mark finished', (tester) async {
      final setup = await pumpServer(
        tester,
        configure: (s) => s.routes['/api/me/progress/$clockmaker'] = (_) => 'OK',
      );
      final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
      unawaited(router.push('/home/book/${Uri.encodeComponent(testSource.key)}/$clockmaker'));
      await settle(tester, rounds: 8);

      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(find.text("The Clockmaker's Tide"), findsWidgets);
      expect(find.textContaining(l10n.itemResume), findsOneWidget);
      expect(find.text('Jonah Pryce'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(l10n.itemChapters), 200, scrollable: mainScroll(ItemDetailScreen));
      await tester.scrollUntilVisible(
        find.bySemanticsLabel(l10n.itemMarkFinished),
        -200,
        scrollable: mainScroll(ItemDetailScreen),
      );

      await tester.tap(find.bySemanticsLabel(l10n.itemMarkFinished));
      await settle(tester);
      expect(find.text(l10n.itemMarkedFinished), findsOneWidget);
      expect(setup.server.requestsTo('/api/me/progress/$clockmaker').single.data, {'isFinished': true});
      await tester.scrollUntilVisible(find.text(l10n.itemListenAgain), -200, scrollable: mainScroll(ItemDetailScreen));
      expect(find.text(l10n.itemListenAgain), findsOneWidget);
    });

    serverTest('Library: synced books in a grid, filters as removable chips', (tester) async {
      await pumpServer(tester);
      await tester.tap(find.text(l10n.tabLibrary));
      await settle(tester, rounds: 8);
      expect(find.text('Ash Harbor'), findsOneWidget);
      expect(find.text('Cinder Interlude'), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.libraryFilter));
      await settle(tester);
      final chip = find.widgetWithText(FilterChip, 'Jonah Pryce');
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
      );
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      await tester.tap(find.text(l10n.filterShowBooks));
      await settle(tester);
      expect(find.widgetWithText(InputChip, 'Jonah Pryce'), findsOneWidget);
      expect(find.text('A Field Guide to Quiet Places'), findsNothing);
      expect(find.text('Ash Harbor'), findsOneWidget);

      await tester.tap(find.text(l10n.filterClearAll));
      await settle(tester);
      expect(find.text('A Field Guide to Quiet Places'), findsOneWidget);
    });

    serverTest('Search: a newer query wins over a slower older one', (tester) async {
      final gate = Completer<void>();
      final setup = await pumpServer(tester);
      await tester.tap(find.text(l10n.tabSearch));
      await settle(tester);

      setup.server.delays['/api/libraries/$testLibraryId/search'] = gate.future;
      await tester.enterText(find.byType(SearchBar), 'old');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      setup.server.delays.clear();
      await tester.enterText(find.byType(SearchBar), 'lanterns');
      await tester.pump(const Duration(milliseconds: 350));
      gate.complete();
      await settle(tester, rounds: 6);

      final queries = setup.server
          .requestsTo('/api/libraries/$testLibraryId/search')
          .map((r) => r.uri.queryParameters['q']);
      expect(queries, ['old', 'lanterns']);
      expect(find.text(l10n.searchGroupBooks), findsOneWidget);
      expect(find.text('Lanterns Under the Ice'), findsOneWidget);
    });

    serverTest('Search offline falls back to the cache and says so', (tester) async {
      final setup = await pumpServer(tester);
      await tester.tap(find.text(l10n.tabLibrary));
      await settle(tester, rounds: 8);
      setup.server.offline = true;
      await tester.tap(find.text(l10n.tabSearch));
      await settle(tester);
      await tester.enterText(find.byType(SearchBar), 'jonah');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester, rounds: 6);
      expect(find.text(l10n.searchOffline), findsOneWidget);
      expect(find.text('Ash Harbor'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(l10n.searchGroupNarrators), 200, scrollable: mainScroll(SearchScreen));
      expect(find.text('Jonah Pryce'), findsWidgets);
    });
  });
}
