// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';

/// Why a call to an Audiobookshelf server failed, in terms the app can act
/// on. Every user-facing error message is built from one of these.
sealed class AbsFailure implements Exception {
  const AbsFailure(this.details);

  /// Technical details for the "Copy details" action. Never contains a token.
  final String details;

  @override
  String toString() => '$runtimeType: $details';

  /// Maps a dio error to a failure.
  static AbsFailure from(Object error) {
    if (error is AbsFailure) return error;
    if (error is DioException) {
      final response = error.response;
      if (response == null) return AbsUnreachable(_describe(error));
      final status = response.statusCode ?? 0;
      final body = _bodyText(response.data);
      if (status == 401) return AbsUnauthorized('HTTP 401 $body');
      if (status == 403) return AbsForbidden('HTTP 403 $body');
      if (status == 429) return AbsRateLimited(retryAfter: retryAfterOf(response), details: 'HTTP 429 $body');
      return AbsHttpError(status, 'HTTP $status $body');
    }
    return AbsUnexpected(error.toString());
  }

  static String _describe(DioException e) {
    final inner = e.error;
    return '${e.type.name}${inner == null ? '' : ': $inner'}';
  }

  static String _bodyText(Object? data) {
    if (data == null) return '';
    final text = data.toString();
    return text.length > 300 ? '${text.substring(0, 300)}...' : text;
  }

  /// Seconds to wait, from Retry-After or RateLimit-Reset.
  static Duration? retryAfterOf(Response<dynamic> response) {
    for (final name in ['retry-after', 'ratelimit-reset']) {
      final value = int.tryParse(response.headers.value(name) ?? '');
      if (value != null && value >= 0) return Duration(seconds: value);
    }
    return null;
  }
}

/// No answer: offline, DNS, refused, timed out, TLS problem.
final class AbsUnreachable extends AbsFailure {
  const AbsUnreachable(super.details);
}

/// Wrong credentials, or a token the server no longer accepts.
final class AbsUnauthorized extends AbsFailure {
  const AbsUnauthorized(super.details);
}

/// Signed in, but this user may not do that.
final class AbsForbidden extends AbsFailure {
  const AbsForbidden(super.details);
}

/// Too many sign-in attempts from this network. Wait, never sign out.
final class AbsRateLimited extends AbsFailure {
  const AbsRateLimited({this.retryAfter, required String details}) : super(details);

  final Duration? retryAfter;
}

final class AbsHttpError extends AbsFailure {
  const AbsHttpError(this.status, String details) : super(details);

  final int status;
}

final class AbsUnexpected extends AbsFailure {
  const AbsUnexpected(super.details);
}

/// Single sign-on came back with a different state than it started with.
final class OidcStateMismatch extends AbsFailure {
  const OidcStateMismatch(super.details);
}
