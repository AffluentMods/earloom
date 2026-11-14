// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// Where a book comes from: the On this device library or one Audiobookshelf
/// account. See docs/architecture.md section 4.
sealed class SourceId {
  const SourceId();

  /// Parses the form used in routes and database keys: `local` or
  /// `abs:<accountId>`. Returns null for anything else.
  static SourceId? tryParse(String value) {
    if (value == LocalSource.keyValue) return const LocalSource();
    if (value.startsWith('abs:') && value.length > 4) return AbsSource(value.substring(4));
    return null;
  }

  /// The stable string form, the inverse of [tryParse].
  String get key;

  @override
  String toString() => key;
}

/// Books imported from files on this phone.
final class LocalSource extends SourceId {
  const LocalSource();

  static const keyValue = 'local';

  @override
  String get key => keyValue;

  @override
  bool operator ==(Object other) => other is LocalSource;

  @override
  int get hashCode => key.hashCode;
}

/// One user on one Audiobookshelf server.
final class AbsSource extends SourceId {
  const AbsSource(this.accountId);

  final String accountId;

  @override
  String get key => 'abs:$accountId';

  @override
  bool operator ==(Object other) => other is AbsSource && other.accountId == accountId;

  @override
  int get hashCode => key.hashCode;
}

/// A book (or a podcast episode) in a source.
final class ItemRef {
  const ItemRef(this.source, this.itemId, {this.episodeId});

  final SourceId source;
  final String itemId;

  /// Set for podcast episodes, null for books.
  final String? episodeId;

  /// A single string, for keys in maps, databases and hero tags.
  String get key => episodeId == null ? '${source.key}|$itemId' : '${source.key}|$itemId|$episodeId';

  static ItemRef? tryParseKey(String value) {
    final parts = value.split('|');
    if (parts.length < 2 || parts.length > 3) return null;
    final source = SourceId.tryParse(parts[0]);
    if (source == null || parts[1].isEmpty) return null;
    return ItemRef(source, parts[1], episodeId: parts.length == 3 ? parts[2] : null);
  }

  @override
  bool operator ==(Object other) =>
      other is ItemRef && other.source == source && other.itemId == itemId && other.episodeId == episodeId;

  @override
  int get hashCode => Object.hash(source, itemId, episodeId);

  @override
  String toString() => key;
}
