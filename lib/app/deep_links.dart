// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// The custom URL scheme of the app: `earloom://item/<id>`, `earloom://player`
/// (`?action=resume` also starts playback), `earloom://downloads`,
/// `earloom://search`. The last three are the app icon shortcuts.
const appScheme = 'earloom';

/// Maps an incoming URI to an in-app location.
///
/// Returns null when [uri] is already a plain in-app location (`/home`) and
/// needs no rewriting. For anything carrying a scheme or host it returns the
/// in-app location to open instead. Unknown or malformed links go to
/// [fallback]: a link from outside the app must never reach a route we did
/// not list here.
String? normalizeDeepLink(Uri uri, {String fallback = '/home'}) {
  if (!uri.hasScheme && !uri.hasAuthority) return null;
  if (uri.scheme != appScheme) return fallback;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  switch (uri.host) {
    case 'item' when segments.length == 1:
      return '/item/${Uri.encodeComponent(segments.single)}';
    case 'player' when segments.isEmpty:
      return uri.queryParameters['action'] == 'resume' ? '/player?resume=1' : '/player';
    case 'downloads' when segments.isEmpty:
      return '/you/downloads';
    case 'search' when segments.isEmpty:
      return '/search';
    default:
      return fallback;
  }
}
