// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? norm(String link) => normalizeDeepLink(Uri.parse(link));

  test('plain in-app locations are left alone', () {
    expect(norm('/home'), isNull);
    expect(norm('/item/abc'), isNull);
  });

  test('item and player links map to their routes', () {
    expect(norm('earloom://item/test'), '/item/test');
    expect(norm('earloom://item/li_8c2b-41'), '/item/li_8c2b-41');
    expect(norm('earloom://player'), '/player');
    expect(norm('earloom://player/'), '/player');
  });

  test('an item id that happens to be a route name stays an item', () {
    expect(norm('earloom://item/home'), '/item/home');
  });

  test('ids are encoded, so they cannot add path segments or queries', () {
    expect(norm('earloom://item/a%2Fb'), '/item/a%2Fb');
    expect(norm('earloom://item/a%3Fx%3D1'), '/item/a%3Fx%3D1');
  });

  test('unknown or malformed links fall back to home', () {
    expect(norm('earloom://item'), '/home');
    expect(norm('earloom://item/a/b'), '/home');
    expect(norm('earloom://settings/delete-everything'), '/home');
    expect(norm('earloom://debug/colors'), '/home');
    expect(norm('https://example.com/item/test'), '/home');
    expect(norm('audiobookshelf://oauth'), '/home');
  });
}
