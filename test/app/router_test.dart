// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/features/home/ui/home_screen.dart';
import 'package:earloom/features/item_detail/ui/item_detail_screen.dart';
import 'package:earloom/features/library/ui/library_screen.dart';
import 'package:earloom/features/player/ui/mini_player.dart';
import 'package:earloom/features/player/ui/now_playing_screen.dart';
import 'package:earloom/features/search/ui/search_screen.dart';
import 'package:earloom/features/you/ui/you_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('four tabs with localized labels, starting on Home', (tester) async {
    usePhoneSize(tester);
    await pumpEarloom(tester);
    final l10n = await loadL10n();

    expect(find.byType(HomeScreen), findsOneWidget);
    final bar = find.byType(NavigationBar);
    for (final label in [l10n.tabHome, l10n.tabLibrary, l10n.tabSearch, l10n.tabYou]) {
      expect(find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
    }

    await tester.tap(find.descendant(of: bar, matching: find.text(l10n.tabLibrary)));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text(l10n.tabSearch)));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);

    await tester.tap(find.descendant(of: bar, matching: find.text(l10n.tabYou)));
    await tester.pumpAndSettle();
    expect(find.byType(YouScreen), findsOneWidget);
  });

  testWidgets('each tab keeps its own navigator alive while another tab shows', (tester) async {
    usePhoneSize(tester);
    await pumpEarloom(tester);
    final l10n = await loadL10n();
    final bar = find.byType(NavigationBar);
    Finder offstage(Type type) => find.byType(type, skipOffstage: false);

    final homeBefore = tester.element(offstage(HomeScreen));
    final homeNavigator = tester.state<NavigatorState>(
      find.ancestor(of: offstage(HomeScreen), matching: offstage(Navigator)).first,
    );

    await tester.tap(find.descendant(of: bar, matching: find.text(l10n.tabLibrary)));
    await tester.pumpAndSettle();
    final libraryNavigator = tester.state<NavigatorState>(
      find.ancestor(of: offstage(LibraryScreen), matching: offstage(Navigator)).first,
    );

    // Two tabs, two navigators: a push in one cannot touch the other.
    expect(libraryNavigator, isNot(same(homeNavigator)));
    // Home is still mounted, untouched, behind the Library tab.
    expect(tester.element(offstage(HomeScreen)), same(homeBefore));

    await tester.tap(find.descendant(of: bar, matching: find.text(l10n.tabHome)));
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(HomeScreen)), same(homeBefore));
  });

  testWidgets('tablets get a side rail instead of the bottom bar', (tester) async {
    tester.view.physicalSize = const Size(1024, 768) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final l10n = await loadL10n();
    await pumpEarloom(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text(l10n.tabYou));
    await tester.pumpAndSettle();
    expect(find.byType(YouScreen), findsOneWidget);
  });

  testWidgets('with nothing loaded the mini player takes no height', (tester) async {
    await pumpEarloom(tester);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(tester.getSize(find.byType(MiniPlayer)).height, 0);
  });

  group('deep links', () {
    testWidgets('earloom://item/<id> opens item detail on a cold start', (tester) async {
      await pumpEarloom(tester, initialRoute: 'earloom://item/test');
      final detail = tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen));
      expect(detail.itemId, 'test');
    });

    testWidgets('earloom://item/<id> opens item detail while running', (tester) async {
      await pumpEarloom(tester);
      await openLink(tester, 'earloom://item/test');
      expect(tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).itemId, 'test');
    });

    testWidgets('an item whose id is a route name still opens item detail', (tester) async {
      await pumpEarloom(tester);
      await openLink(tester, 'earloom://item/home');
      expect(tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).itemId, 'home');
    });

    testWidgets('earloom://player with nothing loaded lands on Home', (tester) async {
      await pumpEarloom(tester);
      await openLink(tester, 'earloom://player');
      expect(find.byType(NowPlayingScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('unknown links land on Home, never on an error page', (tester) async {
      await pumpEarloom(tester);
      for (final link in [
        'earloom://nope/nothing',
        'earloom://debug/colors',
        'https://example.com/x',
        '/not-a-route',
      ]) {
        await openLink(tester, link);
        expect(find.byType(HomeScreen), findsOneWidget, reason: link);
        expect(find.byType(ItemDetailScreen), findsNothing, reason: link);
      }
    });
  });
}
