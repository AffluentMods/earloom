// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/cover_theme.dart';
import '../../../../app/theme/tokens.dart';
import '../../../../core/library/browse_models.dart';
import '../../../../core/library/models.dart';
import '../../../../core/library/source_id.dart';
import '../../../../core/ui/cover_image.dart';
import '../../../local_library/data/providers.dart';
import '../../data/library_providers.dart';
import 'progress_badge.dart';

/// Where the cover of [ref] comes from: the imported file for local books,
/// the pre-sized server cover for server books (null for books of an
/// account that is not current, which get the placeholder).
CoverSource? coverSourceFor(WidgetRef ref, ItemRef item, String? coverKey) {
  if (coverKey == null) return null;
  switch (item.source) {
    case LocalSource():
      final file = ref.watch(localLibraryRepositoryProvider).coverFile(item.itemId, coverKey);
      return file == null ? null : FileCover(file.path);
    case AbsSource():
      final repository = ref.watch(absLibraryRepositoryProvider);
      if (repository == null || repository.source != item.source) return null;
      return NetworkCover(
        itemCoverUrl: repository.client.url('/api/items/${item.itemId}/cover'),
        cacheKey: '${item.itemId}-$coverKey',
        headers: ref.watch(coverHeadersProvider).value ?? const {},
      );
  }
}

/// A small version of the cover, only sampled for color by [CoverTheme].
ImageProvider? coverSampleImage(CoverSource? source) => switch (source) {
  FileCover(:final path) => ResizeImage(FileImage(File(path)), width: 128),
  NetworkCover(:final itemCoverUrl, :final cacheKey, :final headers) => CachedNetworkImageProvider(
    itemCoverUrl.replace(queryParameters: {'width': '128', 'format': 'webp'}).toString(),
    cacheKey: '$cacheKey-128',
    cacheManager: CoverCache.manager,
    headers: headers,
  ),
  null => null,
};

/// The cover of a book, the way covers look everywhere: square, rounded,
/// never stretched, letterboxed on the palette, with an optional progress
/// badge in the corner.
class BookCover extends ConsumerWidget {
  const BookCover({
    super.key,
    required this.book,
    required this.size,
    this.heroTag,
    this.shadow = true,
    this.showProgress = true,
  });

  final BookSummary book;
  final double size;
  final Object? heroTag;
  final bool shadow;
  final bool showProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = CoverImage(
      source: coverSourceFor(ref, book.ref, book.coverKey),
      title: book.title,
      size: size,
      radius: coverRadius(size),
      heroTag: heroTag,
      shadow: shadow,
    );
    final progress = book.progress;
    if (!showProgress || progress == null || !progress.isStarted) return cover;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          cover,
          // Downloaded badge (Phase 4): the top left corner is kept free for
          // the downloads feature's `DownloadedBadge`.
          Positioned(
            right: Space.sm,
            bottom: Space.sm,
            child: ProgressBadge(progress: progress, size: (size * 0.2).clamp(22.0, 32.0)),
          ),
        ],
      ),
    );
  }
}

/// Corner radius for a cover of [size]: small covers get smaller corners so
/// they keep the same look.
double coverRadius(double size) => (Radii.cover * (size / 160)).clamp(6.0, Radii.cover);

/// Themes [child] with the colors of [book]'s cover.
class BookCoverTheme extends ConsumerWidget {
  const BookCoverTheme({super.key, required this.book, required this.child});

  final BookSummary? book;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = book;
    final image = b == null ? null : coverSampleImage(coverSourceFor(ref, b.ref, b.coverKey));
    if (b == null || image == null) return child;
    return CoverTheme(
      itemId: b.ref.key,
      coverUpdatedAt: b.coverKey.hashCode,
      cover: image,
      child: child,
    );
  }
}

/// An author photo, or initials when there is none.
class AuthorAvatar extends ConsumerWidget {
  const AuthorAvatar({super.key, required this.author, required this.size, this.semanticLabel});

  final AuthorSummary author;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = author.imageUrl;
    return ClipOval(
      child: CoverImage(
        source: url == null
            ? null
            : NetworkCover(
                itemCoverUrl: url,
                cacheKey: author.imageKey ?? author.id,
                headers: ref.watch(coverHeadersProvider).value ?? const {},
              ),
        title: semanticLabel ?? author.name,
        size: size,
        radius: size / 2,
      ),
    );
  }
}
