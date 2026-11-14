// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../core/library/browse_models.dart';
import '../../../core/library/source_id.dart';

/// Opens browse screens inside the tab the user is in, so the tab bar and
/// the mini player stay. Outside a browsing tab they open full screen.
abstract final class BrowseNav {
  /// The tab root the current location is in, or empty.
  static String base(BuildContext context) {
    final String path;
    try {
      path = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    } on Object {
      return '';
    }
    for (final b in AppRoutes.browseBases) {
      if (path == b || path.startsWith('$b/')) return b;
    }
    return '';
  }

  /// [heroTag] is the tag of the cover that was tapped, so it flies to the
  /// detail header.
  static void book(BuildContext context, ItemRef ref, {Object? heroTag}) =>
      context.push(AppRoutes.book(ref, base: base(context)), extra: heroTag);

  static void series(BuildContext context, SourceId source, String id) =>
      context.push(AppRoutes.series(source, id, base: base(context)));

  static void author(BuildContext context, SourceId source, String id) =>
      context.push(AppRoutes.author(source, id, base: base(context)));

  /// Books of a library with one filter: a narrator, a genre, a tag.
  static void filtered(BuildContext context, SourceId source, String libraryId, FilterKind kind, String value) =>
      context.push(AppRoutes.filtered(source, libraryId, kind, value, base: base(context)));

  static void collection(BuildContext context, SourceId source, String id) =>
      context.push(AppRoutes.collection(source, id, base: base(context)));

  static void playlist(BuildContext context, SourceId source, String id) =>
      context.push(AppRoutes.playlist(source, id, base: base(context)));
}

/// A hero tag that is unique on its screen: the same book can sit on two
/// shelves at once.
String coverHeroTag(ItemRef ref, String place) => 'cover|${ref.key}|$place';
