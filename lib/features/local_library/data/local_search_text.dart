// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../../core/util/natural_sort.dart';
import '../../../core/util/search_fold.dart';

/// The derived columns of a local book that make sorting and searching
/// cheap in SQL. Recomputed on every metadata change.
abstract final class LocalSearchText {
  /// Case-insensitive, accent-insensitive, numbers padded so "Book 2" sorts
  /// before "Book 10".
  static String sortTitle(String title) => padNumbers(foldForSearch(title));

  static String sortAuthor(List<String> authors) => authors.isEmpty ? '' : padNumbers(foldForSearch(authors.first));

  static String searchText({
    required String title,
    String? subtitle,
    List<String> authors = const [],
    List<String> narrators = const [],
    String? seriesName,
  }) {
    return foldForSearch([title, ?subtitle, ...authors, ...narrators, ?seriesName].join(' | '));
  }

  /// A LIKE pattern matching [query] anywhere, with LIKE's wildcards escaped
  /// (use `ESCAPE '\'`). Null for a blank query.
  static String? likePattern(String? query) {
    if (query == null) return null;
    final folded = foldForSearch(query);
    if (folded.isEmpty) return null;
    final escaped = folded.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
    return '%$escaped%';
  }
}
