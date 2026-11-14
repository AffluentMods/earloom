// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/item_detail/ui/item_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import 'browse_screens_test.dart' show PlayRecorder, addLocalBook, playerOverrides;

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a book page lists its bookmarks; tapping one plays from there', (tester) async {
    usePhoneSize(tester, size: const Size(390, 2400));
    final local = await openTestLocalDb(tester);
    final player = PlayRecorder();
    const id = '0b1c2d3e-4f50-4617-8899-aabbccddeeff';
    await addLocalBook(tester, local, id: id, title: 'The Glass Orchard', positionMs: 1000000, chapters: 4);
    await tester.runAsync(
      () => local
          .into(local.localBookmarks)
          .insert(
            LocalBookmarksCompanion.insert(bookId: id, positionMs: 1234000, title: 'The orchard gate', createdAtMs: 1),
          ),
    );
    await pumpEarloom(tester, localDb: local, overrides: playerOverrides(player));
    await settle(tester);
    await tester.tap(find.text('The Glass Orchard').first);
    await settle(tester);
    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(find.text('The orchard gate'), findsOneWidget);
    await tester.tap(find.text('The orchard gate'));
    await settle(tester);
    expect(player.calls.last, (const ItemRef(LocalSource(), id), const Duration(milliseconds: 1234000)));
  });
}
