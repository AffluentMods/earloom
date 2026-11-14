// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'playable.dart';

/// Translates between whole-book positions and (track, offset) pairs.
///
/// Everything the user sees is a whole-book position. The audio backend
/// works per track. This is the only place that converts between them.
final class TrackMap {
  TrackMap(List<PlayableTrack> tracks) : tracks = List.unmodifiable(tracks);

  final List<PlayableTrack> tracks;

  bool get isEmpty => tracks.isEmpty;

  Duration get total => tracks.isEmpty ? Duration.zero : tracks.last.start + tracks.last.duration;

  /// The track that holds [global] and the offset into it. Positions before
  /// the start or after the end are clamped to the book.
  ({int index, Duration offset}) locate(Duration global) {
    if (tracks.isEmpty) return (index: 0, offset: Duration.zero);
    final g = global < Duration.zero ? Duration.zero : (global > total ? total : global);
    var lo = 0;
    var hi = tracks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (tracks[mid].start <= g) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (index: lo, offset: g - tracks[lo].start);
  }

  Duration toGlobal(int index, Duration offset) {
    if (tracks.isEmpty) return Duration.zero;
    final i = index.clamp(0, tracks.length - 1);
    return tracks[i].start + offset;
  }
}
