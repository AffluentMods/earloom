// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/features/item_detail/ui/item_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../features/library/browse_screens_test.dart' show PlayRecorder, addLocalBook, playerOverrides;
import '../support/test_app.dart';

/// Home, Library, Item detail, Search, You and Settings at 200% text on a
/// small phone: nothing may overflow (docs/plan/09-phase8-settings-polish.md
/// 8.4).
void main() {
  setUpAll(loadAppFonts);

  testWidgets('the main screens hold up at 200% text on a small phone', (tester) async {
    usePhoneSize(tester, size: const Size(360, 740));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final l10n = await loadL10n();
    final local = await openTestLocalDb(tester);
    const id = '0b1c2d3e-4f50-4617-8899-aabbccddeeff';
    await addLocalBook(
      tester,
      local,
      id: id,
      title: 'The Remarkably Long Title of a Book About Glass Orchards',
      series: 'Orchard Songs',
      sequence: '1',
      positionMs: 1000000,
      chapters: 4,
    );
    await addLocalBook(tester, local, id: 'b2', title: 'Salt and Static', positionMs: 60000, updatedAt: 5);
    await pumpEarloom(tester, localDb: local, overrides: playerOverrides(PlayRecorder()));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'Home');

    for (final tab in [l10n.tabLibrary, l10n.tabSearch, l10n.tabYou]) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
      expect(tester.takeException(), isNull, reason: tab);
    }

    await tester.tap(find.text(l10n.tabLibrary).last);
    await settle(tester);
    await tester.tap(find.textContaining('Remarkably').first);
    await settle(tester);
    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Item detail');
  });
}
