// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../core/library/models.dart';
import '../../core/library/source_id.dart';
import '../../core/ui/cover_image.dart';

/// One audio file (or stream) of a book.
final class PlayableTrack {
  const PlayableTrack({
    required this.uri,
    required this.start,
    required this.duration,
    this.headers = const {},
    this.mimeType,
  });

  /// `file://` for local and downloaded books, `https://` or `http://` for
  /// streams. Never carries a token.
  final Uri uri;

  /// Where this track starts within the whole book.
  final Duration start;
  final Duration duration;

  /// Extra request headers for streams (custom reverse proxy headers).
  final Map<String, String> headers;
  final String? mimeType;
}

/// Everything the player needs, whatever the source. Built by the source:
/// LocalLibraryRepository for local books, the ABS session starter for
/// server books (streamed or downloaded).
final class PlayableBook {
  const PlayableBook({
    required this.ref,
    required this.title,
    required this.tracks,
    required this.sink,
    this.author,
    this.narrator,
    this.seriesLine,
    this.chapters = const [],
    this.startPosition = Duration.zero,
    this.artworkUri,
    this.cover,
    this.coverKey,
  });

  final ItemRef ref;
  final String title;
  final String? author;
  final String? narrator;

  /// "Book 2 of The Example Saga", for the Now Playing top bar.
  final String? seriesLine;
  final List<PlayableTrack> tracks;

  /// Never empty once the player has it: the player falls back to one
  /// chapter per track, then to one chapter for the whole book.
  final List<Chapter> chapters;
  final Duration startPosition;

  /// A local file the lock screen, car and widgets can show.
  final Uri? artworkUri;

  /// What the app shows. Defaults to [artworkUri] when that is a file.
  final CoverSource? cover;
  final String? coverKey;

  /// Receives progress for this book.
  final ProgressSink sink;

  Duration get duration => tracks.isEmpty ? Duration.zero : tracks.last.start + tracks.last.duration;
}

/// Where position updates for a playing book go. The player calls it; each
/// source decides what to do (local database, server session, outbox).
abstract interface class ProgressSink {
  /// Called about every 15 seconds while playing, and on pause, seek,
  /// chapter change, app background and stop. [listened] is real time
  /// spent playing since the previous call (not scaled by speed).
  Future<void> report({required Duration position, required Duration listened, required bool isPlaying});

  /// The book reached its end.
  Future<void> finished({required Duration position});

  /// Playback of this book ended (stop, switch to another book).
  Future<void> close({required Duration position});
}
