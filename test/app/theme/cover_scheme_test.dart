// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:drift/native.dart';
import 'package:earloom/app/debug/demo_books.dart';
import 'package:earloom/app/theme/cover_scheme.dart';
import 'package:earloom/app/theme/tokens.dart';
import 'package:earloom/core/db/account_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

ImageProvider fileCover(DemoBook book) => FileImage(File(book.coverAsset));

DemoBook demo(String id) => demoBooks.firstWhere((b) => b.id == id);

void main() {
  testWidgets('a colorful cover gives a seed with the cover\'s own hue', (tester) async {
    await tester.runAsync(() async {
      // The teal cover: hue around 190 to 210 degrees.
      final seed = await CoverSchemeService.extractSeed(fileCover(demo('demo-clockmakers-tide')));
      final hct = Hct.fromInt(seed.toARGB32());
      expect(hct.hue, inInclusiveRange(180, 250));
      expect(hct.chroma, greaterThan(CoverSchemeService.minChroma));
    });
  });

  testWidgets('a gray cover falls back to the neutral seed', (tester) async {
    await tester.runAsync(() async {
      final seed = await CoverSchemeService.extractSeed(fileCover(demo('demo-quiet-places')));
      expect(seed, NeutralSeed.color);
    });
  });

  testWidgets('different covers give different seeds', (tester) async {
    await tester.runAsync(() async {
      final seeds = <int>{};
      for (final book in demoBooks) {
        seeds.add((await CoverSchemeService.extractSeed(fileCover(book))).toARGB32());
      }
      // Eight covers, one of them gray. No two colorful covers may collide.
      expect(seeds.length, demoBooks.length);
    });
  });

  testWidgets('the second lookup comes from the cache and gives the same scheme', (tester) async {
    await tester.runAsync(() async {
      final db = AccountDb(NativeDatabase.memory());
      addTearDown(db.close);
      final service = CoverSchemeService(db);
      final book = demo('demo-salt-and-starlight');

      final first = await service.schemeFor(
        itemId: book.id,
        coverUpdatedAt: 1,
        cover: fileCover(book),
        brightness: Brightness.dark,
      );
      expect(await db.coverColorsDao.lookup(book.id, 1), isNotNull);

      // An image that cannot load proves the cache answered, not the image.
      final second = await service.schemeFor(
        itemId: book.id,
        coverUpdatedAt: 1,
        cover: FileImage(File('does/not/exist.jpg')),
        brightness: Brightness.dark,
      );
      expect(second, first);

      // Same seed, other brightness: still no image needed.
      final light = await service.schemeFor(
        itemId: book.id,
        coverUpdatedAt: 1,
        cover: FileImage(File('does/not/exist.jpg')),
        brightness: Brightness.light,
      );
      expect(light.brightness, Brightness.light);
    });
  });
}
