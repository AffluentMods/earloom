// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../../core/net/abs_errors.dart';

/// One audio file of a downloadable item, from the expanded item.
final class SnapshotTrack {
  const SnapshotTrack({
    required this.index,
    required this.ino,
    required this.startOffset,
    required this.duration,
    required this.size,
    this.mimeType,
    this.ext,
    this.localPath,
  });

  factory SnapshotTrack.fromJson(Map<String, Object?> j) => SnapshotTrack(
    index: (j['index'] as num?)?.toInt() ?? 0,
    ino: '${j['ino']}',
    startOffset: (j['startOffset'] as num?)?.toDouble() ?? 0,
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    size: (j['size'] as num?)?.toInt() ?? 0,
    mimeType: j['mimeType'] as String?,
    ext: j['ext'] as String?,
    localPath: j['localPath'] as String?,
  );

  /// Play order, from 0.
  final int index;
  final String ino;

  /// Seconds into the whole item.
  final double startOffset;
  final double duration;

  /// Bytes, as the server reports them. Downloads are checked against it.
  final int size;
  final String? mimeType;
  final String? ext;

  /// Relative to Application Support, once assigned.
  final String? localPath;

  SnapshotTrack withLocalPath(String path) => SnapshotTrack(
    index: index,
    ino: ino,
    startOffset: startOffset,
    duration: duration,
    size: size,
    mimeType: mimeType,
    ext: ext,
    localPath: path,
  );

  Map<String, Object?> toJson() => {
    'index': index,
    'ino': ino,
    'startOffset': startOffset,
    'duration': duration,
    'size': size,
    'mimeType': mimeType,
    'ext': ext,
    'localPath': localPath,
  };
}

/// A chapter in whole-item seconds.
final class SnapshotChapter {
  const SnapshotChapter({required this.start, required this.end, required this.title});

  factory SnapshotChapter.fromJson(Map<String, Object?> j) => SnapshotChapter(
    start: (j['start'] as num?)?.toDouble() ?? 0,
    end: (j['end'] as num?)?.toDouble() ?? 0,
    title: (j['title'] ?? '').toString(),
  );

  final double start;
  final double end;
  final String title;

  Map<String, Object?> toJson() => {'start': start, 'end': end, 'title': title};
}

/// A series the item belongs to.
final class SnapshotSeries {
  const SnapshotSeries({required this.id, required this.name, this.sequence});
  final String id;
  final String name;
  final String? sequence;
}

/// What offline playback and the download manager read from an expanded
/// item (docs/abs-api.md section 8), for a book or one podcast episode.
final class ItemSnapshot {
  const ItemSnapshot({
    required this.title,
    required this.mediaType,
    required this.tracks,
    required this.chapters,
    this.author,
    this.narrator,
    this.seriesLine,
    this.libraryId,
    this.series = const [],
    this.progressTime,
    this.progressUpdatedAt,
    this.isFinished = false,
    this.updatedAt = 0,
  });

  final String title;
  final String? author;
  final String? narrator;
  final String? seriesLine;
  final String? libraryId;

  /// `book` or `podcast`.
  final String mediaType;
  final List<SnapshotTrack> tracks;
  final List<SnapshotChapter> chapters;
  final List<SnapshotSeries> series;

  /// The user's progress when the snapshot was taken.
  final double? progressTime;
  final int? progressUpdatedAt;
  final bool isFinished;

  /// The item's `updatedAt`, for cover cache keys.
  final int updatedAt;

  double get duration => tracks.isEmpty ? 0 : tracks.last.startOffset + tracks.last.duration;
  int get totalBytes => tracks.fold(0, (sum, t) => sum + t.size);

  /// The metadata copied into local sessions: enough for the server's
  /// listening history, nothing more.
  Map<String, Object?> sessionMetadata() => {
    'title': title,
    'authorName': ?author,
    'narratorName': ?narrator,
    'seriesName': ?seriesLine,
  };

  static ItemSnapshot parse(Map<String, Object?> item, {String? episodeId}) {
    final media = _map(item['media']);
    final meta = _map(media['metadata']);
    final progress = _map(item['userMediaProgress']);
    final libraryId = item['libraryId'] as String?;
    final updatedAt = (item['updatedAt'] as num?)?.toInt() ?? 0;
    if (episodeId != null) {
      final episode = _list(media['episodes']).firstWhere(
        (e) => e['id'] == episodeId,
        orElse: () => throw const AbsUnexpected('The episode is not in this podcast'),
      );
      final file = _map(episode['audioFile']);
      final fileMeta = _map(file['metadata']);
      final track = _map(episode['audioTrack']);
      final duration = ((track['duration'] ?? file['duration'] ?? episode['duration']) as num?)?.toDouble() ?? 0;
      return ItemSnapshot(
        title: (episode['title'] ?? '').toString(),
        author: _text(meta['author']),
        seriesLine: _text(meta['title']),
        libraryId: libraryId,
        mediaType: 'podcast',
        tracks: [
          SnapshotTrack(
            index: 0,
            ino: '${file['ino'] ?? track['ino']}',
            startOffset: 0,
            duration: duration,
            size: (fileMeta['size'] as num?)?.toInt() ?? 0,
            mimeType: (file['mimeType'] ?? track['mimeType']) as String?,
            ext: fileMeta['ext'] as String?,
          ),
        ],
        chapters: [for (final c in _list(episode['chapters'])) SnapshotChapter.fromJson(c)],
        progressTime: (progress['currentTime'] as num?)?.toDouble(),
        progressUpdatedAt: (progress['lastUpdate'] as num?)?.toInt(),
        isFinished: progress['isFinished'] == true,
        updatedAt: updatedAt,
      );
    }
    var tracksJson = _list(media['tracks']);
    // Without `expanded=1` there are no tracks: fall back to the audio
    // files in their own order.
    if (tracksJson.isEmpty) tracksJson = _list(media['audioFiles']).where((f) => f['exclude'] != true).toList();
    final tracks = <SnapshotTrack>[];
    var offset = 0.0;
    for (final t in tracksJson) {
      final fileMeta = _map(t['metadata']);
      final duration = (t['duration'] as num?)?.toDouble() ?? 0;
      final start = (t['startOffset'] as num?)?.toDouble() ?? offset;
      tracks.add(
        SnapshotTrack(
          index: tracks.length,
          ino: '${t['ino']}',
          startOffset: start,
          duration: duration,
          size: (fileMeta['size'] as num?)?.toInt() ?? 0,
          mimeType: t['mimeType'] as String?,
          ext: fileMeta['ext'] as String?,
        ),
      );
      offset = start + duration;
    }
    if (tracks.isEmpty) throw const AbsUnexpected('The item has no audio files');
    return ItemSnapshot(
      title: (meta['title'] ?? '').toString(),
      author: _text(meta['authorName']) ?? _text(_list(meta['authors']).map((a) => a['name']).join(', ')),
      narrator: _text(meta['narratorName']),
      seriesLine: _text(meta['seriesName']),
      libraryId: libraryId,
      mediaType: 'book',
      tracks: tracks,
      chapters: [for (final c in _list(media['chapters'])) SnapshotChapter.fromJson(c)],
      series: [
        for (final s in _list(meta['series']))
          if (s['id'] is String)
            SnapshotSeries(id: s['id'] as String, name: '${s['name'] ?? ''}', sequence: s['sequence']?.toString()),
      ],
      progressTime: (progress['currentTime'] as num?)?.toDouble(),
      progressUpdatedAt: (progress['lastUpdate'] as num?)?.toInt(),
      isFinished: progress['isFinished'] == true,
      updatedAt: updatedAt,
    );
  }

  static Map<String, Object?> _map(Object? v) => v is Map ? v.cast<String, Object?>() : const {};

  static List<Map<String, Object?>> _list(Object? v) => v is List
      ? [
          for (final e in v)
            if (e is Map) e.cast<String, Object?>(),
        ]
      : const [];

  static String? _text(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
