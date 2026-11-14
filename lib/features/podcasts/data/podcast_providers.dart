// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/library/source_id.dart';
import '../../../core/ui/cover_image.dart';
import '../../accounts/data/account_session.dart';
import '../../downloads/data/download_manager.dart';
import '../../downloads/data/offline_providers.dart';
import '../../library/data/abs_json.dart';
import '../../library/data/library_providers.dart';
import '../../player/player_controller.dart';
import '../../player/player_engine.dart';
import '../../player/player_prefs.dart' show QueueEntry;
import 'episode_notifier.dart';
import 'podcast_json.dart';
import 'podcast_models.dart';
import 'podcast_repository.dart';

// The podcast layer the screens use (docs/plan/06-phase5-podcasts.md).
// Podcasts only exist on Audiobookshelf accounts, so every provider here
// answers for the current account and is empty without one.

/// The podcast repository of the current account, or null without one. It
/// applies live socket changes (new episodes) while the account is current.
final podcastRepositoryProvider = Provider<AbsPodcastRepository?>((ref) {
  final session = ref.watch(accountSessionProvider);
  if (session == null) return null;
  final repository = AbsPodcastRepository(
    db: session.db,
    client: session.client,
    source: AbsSource(session.accountId),
  );
  final sub = session.socket.events.listen((event) async {
    try {
      await repository.apply(event);
    } on Object {
      // Picked up by the next refresh of that show.
    }
  });
  ref.onDispose(() {
    unawaited(sub.cancel());
    repository.dispose();
  });
  return repository;
});

/// The repository for [source] when it is the current account.
AbsPodcastRepository? podcastRepositoryFor(Ref ref, SourceId source) {
  if (source is! AbsSource) return null;
  final repository = ref.watch(podcastRepositoryProvider);
  return repository?.source == source ? repository : null;
}

typedef ShowsArgs = ({SourceId source, String libraryId, ShowSort sort});

final podcastShowsProvider = StreamProvider.autoDispose.family<List<ShowSummary>, ShowsArgs>((ref, args) {
  final repository = podcastRepositoryFor(ref, args.source);
  if (repository == null) return Stream.value(const []);
  return repository.watchShows(args.libraryId, sort: args.sort);
});

/// A show's header. Null when it is gone or not in the current account.
final showDetailProvider = StreamProvider.autoDispose.family<ShowDetail?, ItemRef>((ref, show) {
  final repository = podcastRepositoryFor(ref, show.source);
  if (repository == null) return Stream.value(null);
  return repository.watchShow(show.itemId);
});

final showEpisodesProvider = StreamProvider.autoDispose.family<List<EpisodeSummary>, ItemRef>((ref, show) {
  final repository = podcastRepositoryFor(ref, show.source);
  if (repository == null) return Stream.value(const []);
  return repository.watchEpisodes(show.itemId);
});

final episodeProvider = StreamProvider.autoDispose.family<EpisodeSummary?, ItemRef>((ref, episode) {
  final repository = podcastRepositoryFor(ref, episode.source);
  if (repository == null || episode.episodeId == null) return Stream.value(null);
  return repository.watchEpisode(episode);
});

final showPrefsProvider = StreamProvider.autoDispose.family<ShowPrefs, ItemRef>((ref, show) {
  final repository = podcastRepositoryFor(ref, show.source);
  if (repository == null) return Stream.value(const ShowPrefs());
  return repository.watchPrefs(show.itemId);
});

final episodesInProgressProvider = StreamProvider.autoDispose.family<List<EpisodeSummary>, LibraryKey>((ref, key) {
  final repository = podcastRepositoryFor(ref, key.source);
  if (repository == null) return Stream.value(const []);
  return repository.watchInProgress(key.libraryId);
});

final podcastShelvesProvider = StreamProvider.autoDispose.family<List<PodcastShelf>, LibraryKey>((ref, key) {
  final repository = podcastRepositoryFor(ref, key.source);
  if (repository == null) return Stream.value(const []);
  return repository.watchShelves(key.libraryId);
});

final recentEpisodesProvider = StreamProvider.autoDispose.family<List<EpisodeSummary>, LibraryKey>((ref, key) {
  final repository = podcastRepositoryFor(ref, key.source);
  if (repository == null) return Stream.value(const []);
  return repository.watchRecentEpisodes(key.libraryId);
});

/// The episode ids of [show] that are on this phone.
final downloadedEpisodesProvider = Provider.autoDispose.family<Set<String>, ItemRef>((ref, show) {
  final states = ref.watch(downloadStatesProvider).value ?? const <String, DownloadState>{};
  return {
    for (final s in states.values)
      if (s.isComplete && s.ref.source == show.source && s.ref.itemId == show.itemId && s.ref.episodeId != null)
        s.ref.episodeId!,
  };
});

/// What the current user may do on the server: from `/api/me` once heard,
/// else the type saved at sign-in.
final userAccessProvider = StreamProvider<UserAccess>((ref) {
  final session = ref.watch(accountSessionProvider);
  final repository = ref.watch(absLibraryRepositoryProvider);
  if (session == null || repository == null) return Stream.value(UserAccess.unknown);
  final fallback = UserAccess(type: session.account.userType);
  return repository.watchAccessJson().map((json) {
    if (json == null) return fallback;
    try {
      return UserAccess.fromUser(AbsJson.map(jsonDecode(json)), fallbackType: session.account.userType);
    } on FormatException {
      return fallback;
    }
  });
});

// --- Playback ---

/// The cover the queue shows for an episode: its show's cover.
CoverSource? episodeCover(AbsPodcastRepository repository, EpisodeSummary e, Map<String, String> headers) =>
    e.coverKey == null
    ? null
    : NetworkCover(
        itemCoverUrl: repository.client.url('/api/items/${e.ref.itemId}/cover'),
        cacheKey: '${e.ref.itemId}-${e.coverKey}',
        headers: headers,
      );

QueueEntry episodeQueueEntry(AbsPodcastRepository repository, EpisodeSummary e, Map<String, String> headers) =>
    QueueEntry.of(e.ref, title: e.title, author: e.showTitle, cover: episodeCover(repository, e, headers));

/// Show speeds and "next unplayed episode" for the player.
class _EpisodeHooks implements EpisodeHooks {
  _EpisodeHooks(this._ref);
  final Ref _ref;

  AbsPodcastRepository? _repositoryFor(ItemRef item) {
    final repository = _ref.read(podcastRepositoryProvider);
    return repository != null && repository.source == item.source ? repository : null;
  }

  @override
  Future<double?> showSpeed(ItemRef episode) async => (await _repositoryFor(episode)?.prefs(episode.itemId))?.speed;

  @override
  Future<void> saveShowSpeed(ItemRef episode, double speed) async {
    final repository = _repositoryFor(episode);
    if (repository == null) return;
    final prefs = await repository.prefs(episode.itemId);
    await repository.savePrefs(episode.itemId, prefs.copyWith(speed: speed));
  }

  @override
  Future<QueueEntry?> nextEpisode(ItemRef finished) async {
    final repository = _repositoryFor(finished);
    if (repository == null) return null;
    final next = await repository.nextUnplayed(finished);
    if (next == null) return null;
    final headers = await _ref.read(coverHeadersProvider.future);
    return episodeQueueEntry(repository, next, headers);
  }
}

/// Connects the player to the podcast settings. Kept alive by the player
/// side effects, like the listening recorder.
final podcastPlaybackBridgeProvider = Provider<void>((ref) {
  final engine = ref.watch(playerEngineProvider);
  engine.episodes = _EpisodeHooks(ref);
  ref.onDispose(() => engine.episodes = null);
});

// --- Automation (5.4) ---

final episodeNotifierProvider = Provider<EpisodeNotifier>((ref) {
  final l10n = deviceL10n();
  return LocalEpisodeNotifier(
    channelName: l10n.notificationNewEpisodeChannel,
    channelDescription: l10n.notificationNewEpisodeChannelBody,
  );
});

/// New episodes found while the app runs (the socket, a refresh): download
/// them for shows with auto-download on, tell about them for shows with
/// notifications on, and keep the automatic downloads within each show's
/// limits. Everything here runs in the main isolate with the app's own
/// client: there is no background refresh (see the Phase 5 notes).
class PodcastAutomation {
  PodcastAutomation(this._ref, this._repository);

  final Ref _ref;
  final AbsPodcastRepository _repository;

  /// At most this many notifications for one burst of new episodes.
  static const maxNotifications = 3;

  Future<void> onNewEpisodes(NewEpisodes event) async {
    final prefs = await _repository.prefs(event.show.itemId);
    final newest = [...event.episodes]..sort((a, b) => b.sortDate.compareTo(a.sortDate));
    if (prefs.autoDownload) {
      final manager = _ref.read(downloadManagerProvider);
      final wanted = prefs.keepLatest > 0 ? newest.take(prefs.keepLatest) : newest;
      for (final e in wanted) {
        try {
          await manager.enqueueItem(e.ref, reason: DownloadReason.podcast, title: e.title);
        } on Object {
          // Offline or no space: the download list shows it.
        }
      }
      await prune(event.show);
    }
    if (prefs.notifyNew) {
      final l10n = deviceL10n();
      final notifier = _ref.read(episodeNotifierProvider);
      for (final e in newest.take(maxNotifications)) {
        try {
          await notifier.show(
            id: e.episodeId.hashCode & 0x7fffffff,
            title: l10n.notificationNewEpisode(e.showTitle, e.title),
            body: e.showTitle,
            payload: e.ref.itemId,
          );
        } on Object {
          // A notification that cannot show is not worth an error.
        }
      }
    }
  }

  /// Applies "keep latest" and "delete played" to the automatic downloads
  /// of [show]. Episodes in progress always stay.
  Future<void> prune(ItemRef show) async {
    final prefs = await _repository.prefs(show.itemId);
    if (!prefs.autoDownload) return;
    final manager = _ref.read(downloadManagerProvider);
    final states = await manager.states.first;
    final auto = {
      for (final s in states.values)
        if (s.isComplete &&
            s.reason == DownloadReason.podcast &&
            s.ref.source == show.source &&
            s.ref.itemId == show.itemId &&
            s.ref.episodeId != null)
          s.ref.episodeId!: s.key,
    };
    if (auto.isEmpty) return;
    final episodes = await _repository.watchEpisodes(show.itemId).first;
    final downloaded = [
      for (final e in episodes)
        if (auto.containsKey(e.episodeId)) e,
    ];
    for (final id in episodesToPrune(downloaded, keepLatest: prefs.keepLatest, deletePlayed: prefs.deletePlayed)) {
      await manager.delete(auto[id]!);
    }
  }

  /// [prune] for every show with auto-download on.
  Future<void> pruneAll() async {
    for (final MapEntry(key: itemId, value: prefs) in (await _repository.automatedShows()).entries) {
      if (prefs.autoDownload) await prune(ItemRef(_repository.source, itemId));
    }
  }
}

/// Runs [PodcastAutomation] for the current account. Kept alive by the
/// player side effects. Tapping a new episode notification opens its show.
final podcastAutomationProvider = Provider<void>((ref) {
  final repository = ref.watch(podcastRepositoryProvider);
  if (repository == null) return;
  final automation = PodcastAutomation(ref, repository);
  final notifier = ref.read(episodeNotifierProvider);
  notifier.onOpen = (itemId) => unawaited(ref.read(routerProvider).push(AppRoutes.item(itemId)));
  final sub = repository.newEpisodes.listen((event) => unawaited(automation.onNewEpisodes(event)));
  // An episode that ends may now be "played": tidy up automatic downloads.
  final finished = ref.listen(playerNoticesProvider, (_, next) {
    if (next.value is BookFinished) unawaited(automation.pruneAll().catchError((Object _) {}));
  });
  final lifecycle = AppLifecycleListener(onResume: () => unawaited(automation.pruneAll().catchError((Object _) {})));
  ref.onDispose(() {
    unawaited(sub.cancel());
    finished.close();
    lifecycle.dispose();
    notifier.onOpen = null;
  });
});
