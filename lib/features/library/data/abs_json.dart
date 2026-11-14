// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:drift/drift.dart' show Value;

import '../../../core/db/account_db.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../core/util/natural_sort.dart';
import '../../../core/util/search_fold.dart';

/// Turns Audiobookshelf JSON (docs/abs-api.md sections 6 to 8 and 12) into
/// cache rows and view models. Lenient on purpose: a field of the wrong type
/// reads as missing, never as a crash.
abstract final class AbsJson {
  static String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
  static int integer(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);
  static double number(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) ?? 0 : 0);
  static bool boolean(Object? v) => v == true;
  static Map<String, Object?> map(Object? v) => v is Map ? Map<String, Object?>.from(v) : const {};
  static List<Map<String, Object?>> maps(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map) Map<String, Object?>.from(e),
  ];
  static List<String> strings(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is String && e.isNotEmpty) e,
  ];

  /// "A, B" as the compact item writes several names.
  static List<String> splitNames(String? joined) =>
      joined == null ? const [] : joined.split(', ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// Parses the compact `seriesName` ("The Example Saga #2, Other #1").
  static List<(String name, String? sequence)> parseSeriesSummary(String? summary) {
    if (summary == null || summary.trim().isEmpty) return const [];
    final out = <(String, String?)>[];
    for (final part in summary.split(', ')) {
      final hash = part.lastIndexOf(' #');
      if (hash > 0) {
        out.add((part.substring(0, hash).trim(), part.substring(hash + 2).trim()));
      } else if (part.trim().isNotEmpty) {
        out.add((part.trim(), null));
      }
    }
    return out;
  }

  /// The sequence padded for a natural SQL sort, empty when there is none.
  static String sequenceSortKey(String? sequence) =>
      sequence == null || sequence.trim().isEmpty ? '' : padNumbers(foldForSearch(sequence));

  static String sortText(String value) => padNumbers(foldForSearch(value));

  // --- Rows ---

  static LibrariesCompanion library(Map<String, Object?> json) => LibrariesCompanion.insert(
    id: str(json['id']) ?? '',
    name: str(json['name']) ?? '',
    mediaType: str(json['mediaType']) ?? 'book',
    displayOrder: Value(integer(json['displayOrder'])),
    icon: Value(str(json['icon'])),
  );

  /// The list row of any item JSON: compact (lists, shelves) or expanded
  /// (detail, search, socket).
  static ItemsCompanion item(Map<String, Object?> json) {
    final media = map(json['media']);
    final meta = map(media['metadata']);
    final isPodcast = json['mediaType'] == 'podcast';
    final title = str(meta['title']) ?? '';
    final authorObjects = maps(meta['authors']);
    final authors = authorObjects.isNotEmpty
        ? [for (final a in authorObjects) ?str(a['name'])]
        : splitNames(str(meta['authorName']) ?? str(meta['author']));
    final narratorList = strings(meta['narrators']);
    final narrators = narratorList.isNotEmpty ? narratorList : splitNames(str(meta['narratorName']));
    final seriesObjects = maps(meta['series']);
    String? seriesSummary = str(meta['seriesName']);
    if (seriesSummary == null && seriesObjects.isNotEmpty) {
      seriesSummary = [
        for (final s in seriesObjects)
          if (str(s['name']) != null) str(s['sequence']) == null ? s['name'] : '${s['name']} #${s['sequence']}',
      ].join(', ');
    } else if (seriesSummary == null && meta['series'] is Map) {
      // A single series object, as series filters and Continue series send.
      final s = map(meta['series']);
      if (str(s['name']) != null) {
        seriesSummary = str(s['sequence']) == null ? s['name'] as String : '${s['name']} #${s['sequence']}';
      }
    }
    final genres = strings(meta['genres']);
    final tags = strings(media['tags']);
    final subtitle = str(meta['subtitle']);
    final sortAuthor = str(meta['authorNameLF']) ?? (authors.isEmpty ? '' : authors.first);
    // Shelves and search send numEpisodes 0 and no episodes: leave the
    // cached count alone then.
    final episodeList = media['episodes'];
    final numEpisodes = episodeList is List && episodeList.isNotEmpty
        ? episodeList.length
        : integer(media['numEpisodes']);
    final duration = media['duration'] != null
        ? number(media['duration'])
        : maps(media['tracks']).fold<double>(0, (sum, t) => sum + number(t['duration']));
    return ItemsCompanion.insert(
      id: str(json['id']) ?? '',
      libraryId: str(json['libraryId']) ?? '',
      mediaType: isPodcast ? 'podcast' : 'book',
      title: title,
      sortTitle: sortText(str(meta['titleIgnorePrefix']) ?? title),
      subtitle: Value(subtitle),
      authors: authors,
      sortAuthor: sortAuthor.isEmpty ? '' : sortText(sortAuthor),
      narrators: narrators,
      seriesSummary: Value(seriesSummary),
      genres: genres,
      tags: tags,
      language: Value(str(meta['language'])),
      publishedYear: Value(str(meta['publishedYear'])),
      durationSec: Value(duration),
      sizeBytes: Value(integer(media['size'] ?? json['size'])),
      hasCover: Value(str(media['coverPath']) != null),
      addedAt: integer(json['addedAt']),
      updatedAt: integer(json['updatedAt']),
      numEpisodes: isPodcast && numEpisodes > 0 ? Value(numEpisodes) : const Value.absent(),
      searchText: foldForSearch(
        [
          title,
          ?subtitle,
          ...authors,
          ...narrators,
          ...parseSeriesSummary(seriesSummary).map((s) => s.$1),
          ...genres,
          ...tags,
        ].join(' | '),
      ),
    );
  }

  static ProgressCompanion progress(Map<String, Object?> json) => ProgressCompanion.insert(
    itemId: str(json['libraryItemId']) ?? '',
    episodeId: Value(str(json['episodeId']) ?? ''),
    progressId: Value(str(json['id'])),
    currentTime: Value(number(json['currentTime'])),
    duration: Value(number(json['duration'])),
    progress: Value(number(json['progress'])),
    isFinished: Value(boolean(json['isFinished'])),
    hideFromContinueListening: Value(boolean(json['hideFromContinueListening'])),
    finishedAt: Value(json['finishedAt'] is num ? integer(json['finishedAt']) : null),
    lastUpdate: integer(json['lastUpdate']),
  );

  static SeriesCompanion series(Map<String, Object?> json, {String? libraryId}) {
    final name = str(json['name']) ?? '';
    return SeriesCompanion.insert(
      id: str(json['id']) ?? '',
      libraryId: str(json['libraryId']) ?? libraryId ?? '',
      name: name,
      sortName: sortText(str(json['nameIgnorePrefix']) ?? name),
      description: Value(str(json['description'])),
      addedAt: Value(integer(json['addedAt'])),
    );
  }

  /// The sequence of [item] in [seriesId] or [seriesName]: from a structured
  /// series object when there is one, else from the display string.
  static String? sequenceIn(Map<String, Object?> item, {required String seriesId, required String seriesName}) {
    final meta = map(map(item['media'])['metadata']);
    final single = meta['series'];
    if (single is Map && single['id'] == seriesId) return str(single['sequence']);
    for (final s in maps(single)) {
      if (s['id'] == seriesId) return str(s['sequence']);
    }
    for (final (name, sequence) in parseSeriesSummary(str(meta['seriesName']))) {
      if (name == seriesName) return sequence;
    }
    return null;
  }

  static SeriesItemsCompanion seriesMember(String seriesId, String itemId, String? sequence, int position) =>
      SeriesItemsCompanion.insert(
        seriesId: seriesId,
        itemId: itemId,
        sequence: Value(sequence),
        sortKey: Value(sequenceSortKey(sequence)),
        position: Value(position),
      );

  static AuthorsCompanion author(Map<String, Object?> json, {String? libraryId}) {
    final name = str(json['name']) ?? '';
    return AuthorsCompanion.insert(
      id: str(json['id']) ?? '',
      libraryId: str(json['libraryId']) ?? libraryId ?? '',
      name: name,
      sortName: sortText(str(json['lastFirst']) ?? name),
      description: Value(str(json['description'])),
      hasImage: Value(str(json['imagePath']) != null),
      numBooks: Value(integer(json['numBooks'])),
      updatedAt: Value(integer(json['updatedAt'])),
    );
  }

  // --- View models ---

  static BookSummary summary(AbsSource source, ItemRow row, ProgressRow? progress) {
    final series = parseSeriesSummary(row.seriesSummary);
    return BookSummary(
      ref: ItemRef(source, row.id),
      title: row.title,
      subtitle: row.subtitle,
      authors: row.authors,
      narrators: row.narrators,
      seriesName: series.isEmpty ? null : series.first.$1,
      seriesSequence: series.isEmpty ? null : series.first.$2,
      duration: Duration(milliseconds: (row.durationSec * 1000).round()),
      coverKey: row.hasCover ? '${row.updatedAt}' : null,
      progress: progress == null ? null : listening(progress, fallbackDuration: row.durationSec),
      isDownloaded: row.isDownloaded,
      addedAt: row.addedAt == 0 ? null : DateTime.fromMillisecondsSinceEpoch(row.addedAt),
      isPodcast: row.mediaType == 'podcast',
    );
  }

  static ListeningProgress listening(ProgressRow row, {double fallbackDuration = 0}) {
    final duration = row.duration > 0 ? row.duration : fallbackDuration;
    return ListeningProgress(
      position: Duration(milliseconds: (row.currentTime * 1000).round()),
      duration: Duration(milliseconds: (duration * 1000).round()),
      isFinished: row.isFinished,
      finishedAt: row.finishedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(row.finishedAt!),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.lastUpdate),
    );
  }

  /// A summary straight from item JSON, for lists that are not cached as
  /// rows (search results while online).
  static BookSummary summaryFromJson(AbsSource source, Map<String, Object?> json, ProgressRow? progress) {
    final c = item(json);
    final row = ItemRow(
      id: c.id.value,
      libraryId: c.libraryId.value,
      mediaType: c.mediaType.value,
      title: c.title.value,
      sortTitle: c.sortTitle.value,
      subtitle: c.subtitle.value,
      authors: c.authors.value,
      sortAuthor: c.sortAuthor.value,
      narrators: c.narrators.value,
      seriesSummary: c.seriesSummary.value,
      genres: c.genres.value,
      tags: c.tags.value,
      language: c.language.value,
      publishedYear: c.publishedYear.value,
      durationSec: c.durationSec.value,
      sizeBytes: c.sizeBytes.value,
      hasCover: c.hasCover.value,
      addedAt: c.addedAt.value,
      updatedAt: c.updatedAt.value,
      isDownloaded: false,
      numEpisodes: c.numEpisodes.present ? c.numEpisodes.value : 0,
      searchText: c.searchText.value,
    );
    return summary(source, row, progress);
  }

  /// Everything the detail screen needs from an expanded item.
  static BookDetail detail(BookSummary summary, Map<String, Object?> json) {
    final media = map(json['media']);
    final meta = map(media['metadata']);
    final audioFiles = maps(media['audioFiles']);
    final formats = {
      for (final f in audioFiles) ?str(map(f['metadata'])['ext'])?.replaceFirst('.', '').toLowerCase(),
    };
    final bitRates = [for (final f in audioFiles) integer(f['bitRate'])].where((b) => b > 0).toList();
    return BookDetail(
      summary: summary,
      descriptionHtml: str(meta['description']),
      genres: strings(meta['genres']),
      tags: strings(media['tags']),
      publisher: str(meta['publisher']),
      publishedYear: str(meta['publishedYear']),
      language: str(meta['language']),
      isbn: str(meta['isbn']),
      asin: str(meta['asin']),
      chapters: [
        for (final (i, c) in maps(media['chapters']).indexed)
          Chapter(
            index: i,
            title: str(c['title']) ?? '',
            start: Duration(milliseconds: (number(c['start']) * 1000).round()),
            end: Duration(milliseconds: (number(c['end']) * 1000).round()),
          ),
      ],
      series: [
        for (final s in maps(meta['series']))
          if (str(s['id']) != null)
            SeriesMembership(id: s['id'] as String, name: str(s['name']) ?? '', sequence: str(s['sequence'])),
      ],
      authorIds: {
        for (final a in maps(meta['authors']))
          if (str(a['name']) != null && str(a['id']) != null) a['name'] as String: a['id'] as String,
      },
      sizeBytes: integer(media['size']) == 0 ? null : integer(media['size']),
      fileFormat: formats.isEmpty ? null : (formats.toList()..sort()).join(', '),
      bitRate: bitRates.isEmpty ? null : bitRates.reduce((a, b) => a > b ? a : b),
    );
  }

  static FilterChoices filterChoices(Map<String, Object?> json) => FilterChoices(
    genres: strings(json['genres']),
    tags: strings(json['tags']),
    series: [
      for (final s in maps(json['series']))
        if (str(s['id']) != null) (s['id'] as String, str(s['name']) ?? ''),
    ],
    authors: [for (final a in maps(json['authors'])) ?str(a['name'])],
    narrators: strings(json['narrators']),
    languages: strings(json['languages']),
  );
}
