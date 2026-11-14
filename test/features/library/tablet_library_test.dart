// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/features/item_detail/ui/item_detail_screen.dart';
import 'package:earloom/features/library/ui/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import 'browse_screens_test.dart' show PlayRecorder, addLocalBook, playerOverrides;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('on a tablet the book opens next to the library list', (tester) async {
    usePhoneSize(tester, size: const Size(1280, 800));
    final l10n = await loadL10n();
    final local = await openTestLocalDb(tester);
    await addLocalBook(tester, local, id: 'b1', title: 'The Glass Orchard', chapters: 3);
    await addLocalBook(tester, local, id: 'b2', title: 'Salt and Static');
    await pumpEarloom(tester, localDb: local, overrides: playerOverrides(PlayRecorder()));
    await settle(tester);
    await tester.tap(find.text(l10n.tabLibrary));
    await settle(tester);
    expect(find.text(l10n.libraryPickBook), findsOneWidget);

    await tester.tap(find.text('The Glass Orchard').first);
    await settle(tester);
    expect(find.byType(LibraryScreen), findsOneWidget, reason: 'the list stays');
    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Salt and Static').first);
    await settle(tester);
    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(find.text(l10n.libraryPickBook), findsNothing);
  });
}
