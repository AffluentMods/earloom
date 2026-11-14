// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/accounts/data/account_session.dart';
import 'package:earloom/features/home/ui/home_screen.dart';
import 'package:earloom/features/library/data/library_providers.dart';
import 'package:earloom/features/player/player_controller.dart';
import 'package:earloom/features/player/playable.dart';
import 'package:earloom/features/player/progress_resolver.dart';
import 'package:earloom/features/podcasts/ui/episode_sheet.dart';
import 'package:earloom/features/podcasts/ui/episode_widgets.dart';
import 'package:earloom/features/podcasts/ui/podcast_library_screen.dart';
import 'package:earloom/features/podcasts/ui/show_screen.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/test_app.dart';
import '../library/abs_support.dart';
import 'podcast_support.dart';

/// Records what the screens ask the player to play, without playing.
class PlayRecorder {
  final calls = <(ItemRef, Duration?)>[];

  Future<(PlayableBook, StartDecision)> resolve(ItemRef item, {Duration? startAt}) async {
    calls.add((item, startAt));
    throw StateError('not playing in tests');
  }
}

/// The vertical scroll view of a screen.
Finder mainScroll(Type screen) => find
    .descendant(
      of: find.byType(screen),
      matching: find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical),
    )
    .first;

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

  /// The app with the podcast library selected, on a fake server.
  Future<({FakeAbsServer server, PlayRecorder player})> pumpPodcasts(
    WidgetTester tester, {
    bool admin = false,
    void Function(FakeAbsServer server)? configure,
  }) async {
    usePhoneSize(tester);
    final server = FakeAbsServer(routes: podcastRoutes());
    if (admin) server.routes['/api/me'] = (_) => adminUser();
    configure?.call(server);
    final db = await openTestAccountDb(tester);
    final session = await tester.runAsync(() => fakeSession(server, db));
    final player = PlayRecorder();
    late GlobalDb global;
    await pumpEarloom(
      tester,
      onDb: (d) => global = d,
      overrides: [
        bookResolverProvider.overrideWithValue(player.resolve),
        accountSessionProvider.overrideWithValue(session),
      ],
    );
    await tester.runAsync(
      () => global.writeSetting(LibrarySettingKeys.selection, 'abs:$testAccountId/$podcastLibraryId'),
    );
    await settle(tester, rounds: 10);
    return (server: server, player: player);
  }

  Future<void> openShow(WidgetTester tester) async {
    final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
    unawaited(router.push('/home/show/${Uri.encodeComponent(testSource.key)}/$showId'));
    await settle(tester, rounds: 8);
    expect(find.byType(ShowScreen), findsOneWidget);
  }

  serverTest('podcast Home: the episode in progress as the hero, episode shelves, latest episodes', (tester) async {
    final setup = await pumpPodcasts(tester);
    expect(find.text('Episode 1 - Pilot'), findsWidgets);
    expect(find.text(l10n.homeResume), findsOneWidget);
    await tester.tap(find.text(l10n.homeResume));
    await settle(tester);
    expect(setup.player.calls.first.$1, episodeRef(pilotId));

    await tester.scrollUntilVisible(find.text(l10n.homeShelfNewestEpisodes), 200, scrollable: mainScroll(HomeScreen));
    await tester.scrollUntilVisible(find.text(l10n.podcastLatestEpisodes), 200, scrollable: mainScroll(HomeScreen));
    expect(find.text('Episode 2 - Dog Ears'), findsWidgets);
  });

  serverTest('Library: shows in a grid with their unplayed count', (tester) async {
    await pumpPodcasts(tester);
    await tester.tap(find.text(l10n.tabLibrary));
    await settle(tester, rounds: 10);
    expect(find.byType(PodcastLibraryScreen), findsOneWidget);
    expect(find.text('Shelf Talk'), findsOneWidget);
    // Three episodes, none finished (the pilot is only started).
    expect(find.descendant(of: find.byType(UnplayedBadge), matching: find.text('3')), findsOneWidget);

    await tester.tap(find.text('Shelf Talk'));
    await settle(tester, rounds: 8);
    expect(find.byType(ShowScreen), findsOneWidget);
  });

  serverTest('Show: header, episodes newest first, filters, mark played from the episode sheet', (tester) async {
    final setup = await pumpPodcasts(tester);
    await openShow(tester);
    expect(find.text('Shelf Talk'), findsWidgets);
    expect(find.text(l10n.podcastEpisodes(3)), findsNothing, reason: 'counts sit in one line');
    expect(find.text('${l10n.podcastEpisodes(3)} · ${l10n.podcastUnplayed(3)}'), findsOneWidget);
    expect(find.text(l10n.podcastPlayLatest), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Episode 1 - Pilot'), 200, scrollable: mainScroll(ShowScreen));
    final third = tester.getTopLeft(find.text('Episode 3 - The Long Shelf')).dy;
    expect(third, lessThan(tester.getTopLeft(find.text('Episode 1 - Pilot')).dy), reason: 'newest first');

    await tester.tap(find.text(l10n.podcastFilterInProgress));
    await settle(tester);
    expect(find.text('Episode 1 - Pilot'), findsOneWidget);
    expect(find.text('Episode 3 - The Long Shelf'), findsNothing);
    await tester.tap(find.text(l10n.podcastFilterAll));
    await settle(tester);

    await tester.ensureVisible(find.text('Episode 2 - Dog Ears'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Episode 2 - Dog Ears'));
    await settle(tester);
    expect(find.byType(EpisodeSheet), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(l10n.podcastMarkPlayed));
    await settle(tester);
    expect(find.text(l10n.podcastMarkedPlayed), findsOneWidget);
    expect(setup.server.requestsTo('/api/me/progress/$showId/$dogEarsId').single.data, {'isFinished': true});
    expect(find.bySemanticsLabel(l10n.podcastMarkUnplayed), findsOneWidget);
  });

  serverTest('Play latest plays the newest episode; Play unplayed queues the rest', (tester) async {
    final setup = await pumpPodcasts(tester);
    await openShow(tester);
    await tester.tap(find.text(l10n.podcastPlayLatest));
    await settle(tester);
    expect(setup.player.calls.single.$1, episodeRef(longShelfId));

    await tester.tap(find.text(l10n.podcastPlayAllUnplayed));
    await settle(tester);
    expect(setup.player.calls.last.$1, episodeRef(longShelfId));
    expect(find.text(l10n.podcastQueuedUnplayed(2)), findsOneWidget);
  });

  serverTest('Episode sheet: a time in the show notes starts the episode there', (tester) async {
    final setup = await pumpPodcasts(tester);
    await openShow(tester);
    await tester.scrollUntilVisible(find.text('Episode 1 - Pilot'), 200, scrollable: mainScroll(ShowScreen));
    await tester.tap(find.text('Episode 1 - Pilot'));
    await settle(tester);
    expect(find.text(l10n.podcastShowNotes), findsOneWidget);

    final notes = find.byType(EpisodeSheet);
    await tester.tapOnText(find.textRange.ofSubstring('2:30', descendentOf: notes));
    await settle(tester);
    expect(setup.player.calls.single, (episodeRef(pilotId), const Duration(minutes: 2, seconds: 30)));
    await tester.tapOnText(find.textRange.ofSubstring('0:45', descendentOf: notes));
    await settle(tester);
    expect(setup.player.calls.last, (episodeRef(pilotId), const Duration(seconds: 45)));
  });

  group('admin actions', () {
    serverTest('a normal user never sees them', (tester) async {
      await pumpPodcasts(tester);
      await openShow(tester);
      expect(find.byTooltip(l10n.podcastAdminActions), findsNothing);
      expect(
        find.byTooltip(l10n.podcastSettingsTitle),
        findsOneWidget,
        reason: 'this phone\'s settings are for everyone',
      );
      GoRouter.of(tester.element(find.byType(ShowScreen))).go('/library');
      await settle(tester, rounds: 8);
      expect(find.byType(PodcastLibraryScreen), findsOneWidget);
      expect(find.byTooltip(l10n.podcastAdminAdd), findsNothing);
    });

    serverTest('an admin sees them, and each asks first', (tester) async {
      final setup = await pumpPodcasts(
        tester,
        admin: true,
        configure: (server) {
          server.routes['/api/podcasts/$showId/checknew'] = (_) => {
            'episodes': [newEpisode('ep-4', 'Episode 4 - Margins')],
          };
          server.routes['/api/items/$showId'] = (_) {
            final show = expandedShow();
            final media = Map<String, Object?>.from(show['media']! as Map);
            media['metadata'] = {
              ...(media['metadata']! as Map).cast<String, Object?>(),
              'feedUrl': 'https://feeds.example.test/shelf-talk.xml',
            };
            return {...show, 'media': media};
          };
        },
      );
      await openShow(tester);
      await tester.tap(find.byTooltip(l10n.podcastAdminActions));
      await settle(tester);
      expect(find.text(l10n.podcastAdminCheckNew), findsOneWidget);
      expect(find.text(l10n.podcastAdminDownloadToServer), findsOneWidget);
      expect(find.text(l10n.podcastAdminEditFeed), findsOneWidget);

      await tester.tap(find.text(l10n.podcastAdminCheckNew));
      await settle(tester);
      // Nothing is sent before the user confirms.
      expect(find.text(l10n.podcastAdminCheckNewConfirm('Shelf Talk')), findsOneWidget);
      expect(setup.server.requestsTo('/api/podcasts/$showId/checknew'), isEmpty);
      await tester.tap(find.text(l10n.podcastAdminConfirm));
      await settle(tester, rounds: 8);
      expect(setup.server.requestsTo('/api/podcasts/$showId/checknew'), hasLength(1));
      expect(find.text(l10n.podcastAdminFoundNew(1)), findsOneWidget);

      GoRouter.of(tester.element(find.byType(ShowScreen))).go('/library');
      await settle(tester, rounds: 8);
      expect(find.byTooltip(l10n.podcastAdminAdd), findsOneWidget);
    });
  });
}
