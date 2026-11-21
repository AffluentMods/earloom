// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:convert';

import 'package:earloom/core/ui/cover_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A one pixel PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _Image implements FileServiceResponse {
  @override
  Stream<List<int>> get content => Stream.value(_png);

  @override
  int? get contentLength => _png.length;

  @override
  String? get eTag => null;

  @override
  String get fileExtension => '.png';

  @override
  int get statusCode => 200;

  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));
}

/// A cover server that fails as told. [fail] gets the width asked for and
/// how often that width was asked for before, and returns the status to
/// fail with, or null to answer with an image.
class _Covers extends FileService {
  _Covers(this.fail);

  final int? Function(int width, int asksBefore) fail;
  final asked = <int>[];

  int times(int width) => asked.where((w) => w == width).length;

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    final width = int.parse(Uri.parse(url).queryParameters['width']!);
    final before = times(width);
    asked.add(width);
    final status = fail(width, before);
    if (status != null) throw HttpExceptionWithStatus(status, 'the test server fails', uri: Uri.parse(url));
    return _Image();
  }
}

var _run = 0;

/// Shows one server cover, 300 wide on a 3x screen: the 1024 bucket, with
/// 512 as the next smaller one.
Future<_Covers> _show(WidgetTester tester, int? Function(int width, int asksBefore) fail) async {
  final covers = _Covers(fail);
  CoverCache.manager = CacheManager(
    Config(
      'test-covers-${_run++}',
      repo: NonStoringObjectProvider(),
      fileSystem: MemoryCacheSystem(),
      fileService: covers,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: CoverImage(
          source: NetworkCover(itemCoverUrl: Uri.parse('http://abs.test/api/items/1/cover'), cacheKey: '1-$_run'),
          title: 'The Clockmaker',
          size: 300,
        ),
      ),
    ),
  );
  await _settle(tester);
  return covers;
}

/// Lets downloads and image decoding, which run in real time, finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Whether a decoded picture is on screen (not a placeholder).
bool _showsPicture(WidgetTester tester) =>
    tester.widgetList<RawImage>(find.byType(RawImage)).any((i) => i.image != null);

/// Ends a test with no timer still waiting: runs the clock past the tries
/// of a cover that keeps failing, takes the cover off the screen, and then
/// lets the cache tidy itself (it does so ten seconds after it was used).
Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(minutes: 1));
  await _settle(tester);
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
  await tester.pump(const Duration(seconds: 15));
}

void main() {
  // Flutter keeps decoded pictures between tests: start each one empty.
  setUp(() {
    imageCache.clear();
    imageCache.clearLiveImages();
  });

  testWidgets('a cover that loads shows, and is asked for once', (tester) async {
    final covers = await _show(tester, (_, _) => null);
    expect(_showsPicture(tester), isTrue);
    expect(find.text('TC'), findsNothing);
    expect(covers.asked.toSet(), {1024});
    await _finish(tester);
  });

  testWidgets('a cover whose download failed is asked for again, and then shows', (tester) async {
    // The wanted size fails once; the smaller one is not to be had either.
    final covers = await _show(tester, (width, before) => (width == 512 || before == 0) ? 503 : null);
    expect(find.text('TC'), findsOneWidget, reason: 'nothing to show yet: the initials');
    expect(_showsPicture(tester), isFalse);
    final first = covers.times(1024);
    expect(first, greaterThan(0));

    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(covers.times(1024), greaterThan(first), reason: 'asked again after the wait');
    expect(_showsPicture(tester), isTrue);
    expect(find.text('TC'), findsNothing);
    await _finish(tester);
  });

  testWidgets('while the wanted size fails, the next smaller size shows', (tester) async {
    final covers = await _show(tester, (width, _) => width == 1024 ? 503 : null);
    expect(covers.asked, contains(512));
    expect(_showsPicture(tester), isTrue);
    expect(find.text('TC'), findsNothing);
    await _finish(tester);
  });

  testWidgets('it stops asking after a few tries', (tester) async {
    final covers = await _show(tester, (_, _) => 503);
    for (final wait in const [2, 6, 20]) {
      await tester.pump(Duration(seconds: wait));
      await _settle(tester);
    }
    final total = covers.times(1024);
    await tester.pump(const Duration(minutes: 5));
    await _settle(tester);
    expect(covers.times(1024), total, reason: 'no more tries after the last wait');
    expect(find.text('TC'), findsOneWidget);
  });

  testWidgets('a cover the server does not have is not asked for again', (tester) async {
    final covers = await _show(tester, (_, _) => 404);
    final total = covers.asked.length;
    await tester.pump(const Duration(minutes: 1));
    await _settle(tester);
    expect(covers.asked.length, total);
    expect(covers.asked, isNot(contains(512)), reason: 'no smaller size either: there is no cover');
    expect(find.text('TC'), findsOneWidget);
  });
}
