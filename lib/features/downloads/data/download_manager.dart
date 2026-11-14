// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Background, resumable downloads of whole books and episodes
/// (docs/plan/05-phase4-offline.md section 4.3).
library;

import '../../../core/library/source_id.dart';

/// Why something was downloaded. Automatic downloads may be removed by the
/// storage rules more readily than ones the user asked for.
enum DownloadReason { user, series, podcast }

/// What the download button and the Downloads screen show.
enum DownloadPhase {
  /// Not downloaded and not queued.
  none,

  /// Waiting for its turn (at most two books download at once).
  queued,

  /// Waiting because only Wi-Fi may be used and there is none.
  waitingForWifi,
  downloading,
  paused,
  failed,
  complete,
}

/// Why a download failed, for the words the user sees.
enum DownloadError {
  /// A file is smaller or larger than the server said.
  incomplete,

  /// The server could not be reached.
  network,

  /// The account may not download (the server's download permission).
  forbidden,

  /// The book or a file is gone from the server.
  notFound,

  /// Not enough space, or the files could not be written.
  storage,

  /// Signed out: sign in again.
  auth,
  other;

  static DownloadError? fromName(String? name) => values.where((v) => v.name == name).firstOrNull;
}

/// One download, as the UI sees it.
final class DownloadState {
  const DownloadState({
    required this.ref,
    required this.phase,
    this.title = '',
    this.author,
    this.libraryId,
    this.coverPath,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.error,
    this.errorDetails,
    this.reason = DownloadReason.user,
    this.createdAt,
    this.completedAt,
    this.finishedAt,
  });

  const DownloadState.none(this.ref)
    : phase = DownloadPhase.none,
      title = '',
      author = null,
      libraryId = null,
      coverPath = null,
      bytesDone = 0,
      bytesTotal = 0,
      error = null,
      errorDetails = null,
      reason = DownloadReason.user,
      createdAt = null,
      completedAt = null,
      finishedAt = null;

  final ItemRef ref;
  final DownloadPhase phase;
  final String title;
  final String? author;
  final String? libraryId;

  /// The saved cover, relative to Application Support.
  final String? coverPath;
  final int bytesDone;
  final int bytesTotal;
  final DownloadError? error;

  /// Technical details for "Copy details". Never a token or a full URL.
  final String? errorDetails;
  final DownloadReason reason;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// When the book was finished on this phone, for the auto-delete rules.
  final DateTime? finishedAt;

  String get key => ref.key;

  /// 0 to 1.
  double get fraction {
    if (phase == DownloadPhase.complete) return 1;
    if (bytesTotal <= 0) return 0;
    return (bytesDone / bytesTotal).clamp(0.0, 1.0);
  }

  /// Queued, waiting, downloading or paused: not yet on the phone, not
  /// failed.
  bool get isActive => switch (phase) {
    DownloadPhase.queued || DownloadPhase.waitingForWifi || DownloadPhase.downloading || DownloadPhase.paused => true,
    _ => false,
  };

  bool get isComplete => phase == DownloadPhase.complete;
}

abstract interface class DownloadManager {
  /// Every download, keyed by `ItemRef.key`. Emits on every change.
  Stream<Map<String, DownloadState>> get states;

  /// Saves the item's snapshot and cover, then downloads its audio files.
  /// [title] shows in the list until the item details arrive.
  Future<void> enqueueItem(ItemRef ref, {DownloadReason reason = DownloadReason.user, String? title});

  /// Downloads the books of a series in order, skipping ones already on the
  /// phone. [after] starts after that book; [limit] caps how many are added.
  /// Returns how many were added.
  Future<int> enqueueSeries(
    SourceId source, {
    required String libraryId,
    required String seriesId,
    String? after,
    int? limit,
    DownloadReason reason = DownloadReason.user,
  });

  Future<void> pause(String key);
  Future<void> resume(String key);

  /// Stops a download and removes its partial files.
  Future<void> cancel(String key);

  /// Removes downloaded files. Progress, bookmarks and listening stay.
  Future<void> delete(String key);
  Future<void> retryFailed();
  Future<void> pauseAll();
  Future<void> resumeAll();

  /// Records that the book was finished here (auto-delete rules).
  Future<void> markFinished(String key, DateTime at);

  /// Applies the Wi-Fi only setting to queued and running downloads.
  Future<void> setWifiOnly(bool value);
}
