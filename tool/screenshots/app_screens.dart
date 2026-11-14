// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

// Renders the real app screens, filled with the made-up demo books, to PNG
// files in build/screenshots/app/, for design review without a device. Not
// part of the test suite (the file name does not end in _test.dart). Run it
// from the repo root:
//
//   flutter test tool/screenshots/app_screens.dart
//
// Rendering differs a little between operating systems, so these images are
// for looking at, never for pixel comparison.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:earloom/app/debug/demo_books.dart';
import 'package:earloom/app/providers.dart';
import 'package:earloom/app/theme/cover_scheme.dart';
import 'package:earloom/app/router.dart';
import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/app/theme/tokens.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/db/local_db.dart';
import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/core/ui/cover_image.dart';
import 'package:earloom/features/local_library/data/local_search_text.dart';
import 'package:earloom/features/player/playable.dart';
import 'package:earloom/features/player/player_controller.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/support/fake_player.dart';
import '../../test/support/test_app.dart';

const _pixelRatio = 2.0;
const _phone = Size(390, 844);
const _tablet = Size(1180, 820);

/// Fixed ids: local book ids must be UUIDs.
String _idOf(int i) => '00000000-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}';

/// Durations and progress for the demo books, in minutes.
const _length = [612, 534, 488, 701, 245, 398, 655, 377];
const _listened = [212, 0, 488, 120, null, 37, null, null];

Future<void> _seed(WidgetTester tester, LocalDb local, GlobalDb global, Directory storage) async {
  await tester.runAsync(() async {
    final now = DateTime.now();
    for (var i = 0; i < demoBooks.length; i++) {
      final b = demoBooks[i];
      final id = _idOf(i);
      final dir = Directory('${storage.path}/$id')..createSync(recursive: true);
      const cover = 'cover_1700000000000.jpg';
      File(b.coverAsset).copySync('${dir.path}/$cover');
      final durationMs = _length[i] * 60000;
      final series = b.series == null ? null : 'The Example Saga';
      await local
          .into(local.localBooks)
          .insert(
            LocalBooksCompanion.insert(
              id: id,
              title: b.title,
              authors: [b.author],
              narrators: [b.narrator],
              genres: const ['Fiction'],
              seriesName: Value(series),
              seriesSequence: Value(series == null ? null : (i - 1).toString()),
              description: const Value(
                'A made-up book for screenshots. The river turns twice a day and the clocks of the old town '
                'turn with it, until one morning they stop.',
              ),
              publishedYear: const Value('2024'),
              coverFile: const Value(cover),
              sourceFormat: 'm4b',
              fingerprint: '1:$id',
              durationMs: Value(durationMs),
              sizeBytes: Value(durationMs ~/ 30),
              sortTitle: LocalSearchText.sortTitle(b.title),
              sortAuthor: LocalSearchText.sortAuthor([b.author]),
              searchText: LocalSearchText.searchText(
                title: b.title,
                authors: [b.author],
                narrators: [b.narrator],
                seriesName: series,
              ),
              addedAtMs: now.subtract(Duration(days: i * 3)).millisecondsSinceEpoch,
              updatedAtMs: now.millisecondsSinceEpoch,
            ),
          );
      for (var c = 0; c < 12; c++) {
        final length = durationMs ~/ 12;
        await local
            .into(local.localChapters)
            .insert(
              LocalChaptersCompanion.insert(
                bookId: id,
                idx: c,
                title: Value('Chapter ${c + 1}'),
                startMs: c * length,
                endMs: (c + 1) * length,
              ),
            );
      }
      final listened = _listened[i];
      if (listened != null) {
        final played = now.subtract(Duration(hours: i * 7)).millisecondsSinceEpoch;
        await local
            .into(local.localProgress)
            .insert(
              LocalProgressCompanion.insert(
                bookId: id,
                positionMs: listened * 60000,
                durationMs: durationMs,
                isFinished: Value(listened == _length[i]),
                finishedAtMs: Value(listened == _length[i] ? played : null),
                updatedAtMs: played,
                lastPlayedAtMs: Value(played),
              ),
            );
      }
    }

    // Listening time over the last weeks, for the stats screen.
    final first = demoBooks[0];
    final ref = ItemRef(const LocalSource(), _idOf(0)).key;
    await global
        .into(global.listenedBooks)
        .insert(
          ListenedBooksCompanion.insert(
            refKey: ref,
            title: first.title,
            author: Value(first.author),
            narrator: Value(first.narrator),
            coverPath: Value('${storage.path}/${_idOf(0)}/cover_1700000000000.jpg'),
            firstAt: now.subtract(const Duration(days: 40)).millisecondsSinceEpoch,
            lastAt: now.millisecondsSinceEpoch,
          ),
        );
    for (var d = 0; d < 40; d++) {
      if (d % 6 == 5) continue;
      final day = now.subtract(Duration(days: d));
      final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      for (final hour in [7, 21, 22]) {
        final seconds = (900 + (d * 37 + hour * 11) % 1500).toDouble();
        await global
            .into(global.listeningBuckets)
            .insert(
              ListeningBucketsCompanion.insert(
                day: key,
                hour: hour,
                refKey: ref,
                seconds: seconds,
                bookSeconds: seconds * 1.2,
              ),
            );
      }
    }
  });
}

PlayableBook _playable(ItemRef ref, Directory storage) {
  final i = int.parse(ref.itemId.split('-').last) - 1;
  final b = demoBooks[i];
  final total = Duration(minutes: _length[i]);
  final cover = '${storage.path}/${ref.itemId}/cover_1700000000000.jpg';
  return PlayableBook(
    ref: ref,
    title: b.title,
    author: b.author,
    narrator: b.narrator,
    seriesLine: b.series,
    tracks: [PlayableTrack(uri: Uri.parse('file:///book/track_000.m4b'), start: Duration.zero, duration: total)],
    chapters: [
      for (var c = 0; c < 12; c++)
        Chapter(index: c, title: 'Chapter ${c + 1}', start: total * c ~/ 12, end: total * (c + 1) ~/ 12),
    ],
    cover: FileCover(cover),
    artworkUri: Uri.file(cover),
    coverKey: 'cover_1700000000000.jpg',
    sink: RecordingSink(),
  );
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await settle(tester);
  // Let file images decode and cover colors resolve, then draw them.
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('build/screenshots/app/$name.png');
    await out.create(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void _go(WidgetTester tester, String location) {
  GoRouter.of(tester.element(find.byType(Navigator).first)).go(location);
}

/// Cover colors worked out up front: the real service decodes images,
/// which a widget test's fake clock never lets finish.
class _KnownCoverColors extends CoverSchemeService {
  _KnownCoverColors(this.seeds) : super(null);
  final Map<String, Color> seeds;

  @override
  Future<ColorScheme> schemeFor({
    required String itemId,
    required int coverUpdatedAt,
    required ImageProvider cover,
    required Brightness brightness,
    bool amoled = false,
  }) async => CoverSchemeService.schemeFromSeed(seeds[itemId] ?? NeutralSeed.color, brightness, amoled: amoled);
}

final _seeds = <String, Color>{};

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['SHOTS']?.split(',');
  bool wanted(String name) => only == null || only.any(name.contains);

  for (final mode in [AppThemeMode.dark, AppThemeMode.light]) {
    for (final size in {'phone': _phone, 'tablet': _tablet}.entries) {
      final suffix = '${size.key}_${mode.name}';
      final routes = <String, String>{
        'home': AppRoutes.home,
        'library': AppRoutes.library,
        'search': AppRoutes.search,
        'you': AppRoutes.you,
        'stats': AppRoutes.stats,
        'settings': AppRoutes.settings,
        'downloads': AppRoutes.downloads,
        'item': AppRoutes.book(ItemRef(const LocalSource(), _idOf(0)), base: AppRoutes.home),
        'item_unstarted': AppRoutes.book(ItemRef(const LocalSource(), _idOf(1)), base: AppRoutes.library),
        'player': AppRoutes.player,
        'onboarding': AppRoutes.onboarding,
      };
      for (final route in routes.entries) {
        final name = '${route.key}_$suffix';
        if (!wanted(name)) continue;
        if (size.key == 'tablet' && !{'home', 'library', 'player', 'item'}.contains(route.key)) continue;
        testWidgets(name, (tester) async {
          tester.view.physicalSize = size.value * _pixelRatio;
          tester.view.devicePixelRatio = _pixelRatio;
          addTearDown(tester.view.reset);
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = true);
          // The Now Playing background drifts forever; reduce motion holds it.
          tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
            disableAnimations: true,
          );
          addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

          final storage = Directory.systemTemp.createTempSync('earloom_shots_');
          addTearDown(() => storage.deleteSync(recursive: true));
          final local = await openTestLocalDb(tester);
          final global = await openTestGlobalDb(tester);
          await _seed(tester, local, global, storage);
          if (_seeds.isEmpty) {
            await tester.runAsync(() async {
              for (var i = 0; i < demoBooks.length; i++) {
                final seed = await CoverSchemeService.extractSeed(FileImage(File(demoBooks[i].coverAsset)));
                _seeds[ItemRef(const LocalSource(), _idOf(i)).key] = seed;
              }
            });
          }
          await pumpEarloom(
            tester,
            themeMode: mode,
            onboarded: route.key != 'onboarding',
            localDb: local,
            globalDb: global,
            storageRoot: storage,
            overrides: [
              coverSchemeServiceProvider.overrideWithValue(_KnownCoverColors(_seeds)),
              bookResolverProvider.overrideWithValue(
                (ref, {startAt}) async =>
                    (_playable(ref, storage), StartDecision(startAt ?? const Duration(minutes: 212))),
              ),
            ],
          );
          if (route.key != 'onboarding') {
            final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
            final engine = container.read(playerEngineProvider);
            await tester.runAsync(() => engine.playItem(ItemRef(const LocalSource(), _idOf(0)), autoplay: false));
          }
          _go(tester, route.value);
          await _shoot(tester, name);
        });
      }
    }
  }
}
