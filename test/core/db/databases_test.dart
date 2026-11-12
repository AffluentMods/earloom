// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/native.dart';
import 'package:earloom/core/db/account_db.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalDb settings', () {
    late GlobalDb db;
    setUp(() => db = GlobalDb(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a missing key reads as null', () async {
      expect(await db.readSetting('nope'), isNull);
    });

    test('write then read, and a second write replaces the first', () async {
      await db.writeSetting(SettingKeys.themeMode, 'dark');
      expect(await db.readSetting(SettingKeys.themeMode), 'dark');
      await db.writeSetting(SettingKeys.themeMode, 'amoled');
      expect(await db.readSetting(SettingKeys.themeMode), 'amoled');
    });
  });

  group('AccountDb cover colors', () {
    late AccountDb db;
    setUp(() => db = AccountDb(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('lookup only matches the same cover revision', () async {
      await db.coverColorsDao.put('item-1', 100, 0xFF112233);
      expect((await db.coverColorsDao.lookup('item-1', 100))?.seedArgb, 0xFF112233);
      expect(await db.coverColorsDao.lookup('item-1', 101), isNull);
      expect(await db.coverColorsDao.lookup('item-2', 100), isNull);
    });

    test('a new cover revision replaces the old seed', () async {
      await db.coverColorsDao.put('item-1', 100, 0xFF112233);
      await db.coverColorsDao.put('item-1', 200, 0xFF445566);
      expect(await db.coverColorsDao.lookup('item-1', 100), isNull);
      expect((await db.coverColorsDao.lookup('item-1', 200))?.seedArgb, 0xFF445566);
    });
  });
}
