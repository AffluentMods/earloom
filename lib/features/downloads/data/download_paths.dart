// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Where downloads live on disk. File names are ours (track_000), never taken
/// from the server.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/library/source_id.dart';

/// Paths of downloads, relative to Application Support:
///
/// ```
/// accounts/<accountId>/downloads/<itemId>/            a book
/// accounts/<accountId>/downloads/<itemId>/<episodeId>/ a podcast episode
///   cover.img
///   track_000.mp3
/// ```
///
/// The database keeps relative paths only: the absolute path of the app's
/// folders changes between launches on iOS. Removing an account deletes
/// `accounts/<accountId>` as a whole (accounts screen).
class DownloadPaths {
  const DownloadPaths(this.support);

  /// Application Support.
  final Directory support;

  static String accountFolder(String accountId) => p.posix.join('accounts', _safe(accountId), 'downloads');

  static String folderFor(ItemRef ref) {
    final source = ref.source;
    if (source is! AbsSource) throw ArgumentError('Only server items are downloaded');
    final base = p.posix.join(accountFolder(source.accountId), _safe(ref.itemId));
    return ref.episodeId == null ? base : p.posix.join(base, _safe(ref.episodeId!));
  }

  /// `track_000.mp3`. The extension is kept (players sniff by it) but only
  /// if it is a short plain one.
  static String trackName(int index, String? ext) {
    final clean = (ext ?? '').toLowerCase().replaceAll('.', '');
    final safe = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(clean) ? clean : 'audio';
    return 'track_${index.toString().padLeft(3, '0')}.$safe';
  }

  static const coverName = 'cover.img';

  File file(String relative) => File(p.join(support.path, relative));

  Directory dir(String relative) => Directory(p.join(support.path, relative));

  /// Ids are UUIDs; anything else is reduced to safe characters so a path
  /// can never leave the downloads folder.
  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}
