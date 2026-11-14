// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../../core/db/global_db.dart';
import 'download_manager.dart';

/// Settings > Downloads (docs/plan/05-phase4-offline.md 4.5), stored in
/// GlobalDb.
final class DownloadSettings {
  const DownloadSettings({
    this.wifiOnly = true,
    this.autoNextInSeries = false,
    this.autoDeleteFinished = false,
    this.maxGigabytes = 0,
  });

  /// Downloads use Wi-Fi (or Ethernet) only.
  final bool wifiOnly;

  /// Download the next book of a series once the current one passes 75%.
  final bool autoNextInSeries;

  /// Remove a download 7 days after the book was finished.
  final bool autoDeleteFinished;

  /// Keep at most this much (oldest finished books go first). 0 is off.
  final int maxGigabytes;

  DownloadSettings copyWith({bool? wifiOnly, bool? autoNextInSeries, bool? autoDeleteFinished, int? maxGigabytes}) =>
      DownloadSettings(
        wifiOnly: wifiOnly ?? this.wifiOnly,
        autoNextInSeries: autoNextInSeries ?? this.autoNextInSeries,
        autoDeleteFinished: autoDeleteFinished ?? this.autoDeleteFinished,
        maxGigabytes: maxGigabytes ?? this.maxGigabytes,
      );

  static const wifiOnlyKey = 'downloads_wifi_only';
  static const autoNextKey = 'downloads_auto_next_in_series';
  static const autoDeleteKey = 'downloads_auto_delete_finished';
  static const maxGbKey = 'downloads_max_gb';

  /// The size choices offered in Settings (0 is no limit).
  static const maxGbChoices = [0, 2, 5, 10, 20, 50];

  static Future<DownloadSettings> load(GlobalDb db) async {
    const d = DownloadSettings();
    bool flag(String? v, bool fallback) => v == null ? fallback : v == 'true';
    return DownloadSettings(
      wifiOnly: flag(await db.readSetting(wifiOnlyKey), d.wifiOnly),
      autoNextInSeries: flag(await db.readSetting(autoNextKey), d.autoNextInSeries),
      autoDeleteFinished: flag(await db.readSetting(autoDeleteKey), d.autoDeleteFinished),
      maxGigabytes: int.tryParse(await db.readSetting(maxGbKey) ?? '') ?? d.maxGigabytes,
    );
  }

  Future<void> save(GlobalDb db) async {
    await db.writeSetting(wifiOnlyKey, '$wifiOnly');
    await db.writeSetting(autoNextKey, '$autoNextInSeries');
    await db.writeSetting(autoDeleteKey, '$autoDeleteFinished');
    await db.writeSetting(maxGbKey, '$maxGigabytes');
  }
}

/// How long after finishing a book its download is removed (when on).
const autoDeleteAfter = Duration(days: 7);

/// Where a book must be for the next one in its series to download.
const autoNextAt = 0.75;

/// The downloads the storage rules remove now, oldest first. Only finished
/// books are ever chosen: the rules never delete an unfinished book.
List<String> downloadsToRemove(Iterable<DownloadState> downloads, DownloadSettings settings, DateTime now) {
  final complete = downloads.where((d) => d.isComplete).toList();
  final finished = complete.where((d) => d.finishedAt != null).toList()
    ..sort((a, b) => a.finishedAt!.compareTo(b.finishedAt!));
  final remove = <String>{};
  if (settings.autoDeleteFinished) {
    for (final d in finished) {
      if (now.difference(d.finishedAt!) >= autoDeleteAfter) remove.add(d.key);
    }
  }
  if (settings.maxGigabytes > 0) {
    final limit = settings.maxGigabytes * 1000 * 1000 * 1000;
    var used = downloads.fold<int>(0, (sum, d) => sum + (d.isComplete ? d.bytesTotal : d.bytesDone));
    for (final d in remove) {
      used -= downloads.firstWhere((x) => x.key == d).bytesTotal;
    }
    for (final d in finished) {
      if (used <= limit) break;
      if (remove.add(d.key)) used -= d.bytesTotal;
    }
  }
  return [
    for (final d in finished)
      if (remove.contains(d.key)) d.key,
  ];
}
