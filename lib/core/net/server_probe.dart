// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:dio/dio.dart';

import 'abs_errors.dart';
import 'server_version.dart';

/// Sign-in methods a server offers.
enum AuthMethod { local, openid }

sealed class ProbeResult {
  const ProbeResult();
}

final class ProbeOk extends ProbeResult {
  const ProbeOk({
    required this.baseUrl,
    required this.version,
    required this.authMethods,
    this.oidcButtonText,
    this.loginMessage,
  });

  /// Normalized: scheme, host, optional port and path, no trailing slash.
  final Uri baseUrl;
  final ServerVersion version;
  final Set<AuthMethod> authMethods;
  final String? oidcButtonText;

  /// Admin-set message for the sign-in screen (server-sanitized HTML).
  final String? loginMessage;

  bool get isCleartext => baseUrl.scheme == 'http';
}

/// No server answered at that address.
final class ProbeUnreachable extends ProbeResult {
  const ProbeUnreachable(this.details);
  final String details;
}

/// Something answered, but it is not Audiobookshelf.
final class ProbeNotAbs extends ProbeResult {
  const ProbeNotAbs(this.details);
  final String details;
}

/// Audiobookshelf, but nobody has set it up yet (no root user).
final class ProbeNotInitialized extends ProbeResult {
  const ProbeNotInitialized(this.baseUrl);
  final Uri baseUrl;
}

/// Audiobookshelf older than [minServerVersion].
final class ProbeTooOld extends ProbeResult {
  const ProbeTooOld(this.version);
  final ServerVersion version;
}

/// The address could not be read at all.
final class ProbeInvalidAddress extends ProbeResult {
  const ProbeInvalidAddress();
}

/// Turns what the user typed into the addresses to try, in order. Without a
/// scheme, https is tried first and plain http second (homelab servers on a
/// LAN often have no TLS).
List<Uri> candidateBaseUrls(String input) {
  var text = input.trim();
  if (text.isEmpty || text.contains(' ')) return const [];
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text);
  final schemes = hasScheme ? [''] : ['https://', 'http://'];
  final result = <Uri>[];
  for (final scheme in schemes) {
    final uri = Uri.tryParse('$scheme$text');
    if (uri == null || uri.host.isEmpty) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    // Uri.replace keeps the old query when given null, so rebuild instead.
    result.add(
      Uri(scheme: uri.scheme, userInfo: uri.userInfo, host: uri.host, port: uri.hasPort ? uri.port : null, path: path),
    );
  }
  return result;
}

/// Checks that an address is a reachable, initialized Audiobookshelf server
/// of a supported version.
class ServerProbe {
  ServerProbe({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const timeout = Duration(seconds: 8);

  Future<ProbeResult> probe(String input, {Map<String, String> headers = const {}}) async {
    final candidates = candidateBaseUrls(input);
    if (candidates.isEmpty) return const ProbeInvalidAddress();
    ProbeResult? firstFailure;
    for (final base in candidates) {
      final result = await _probeOne(base, headers);
      if (result is ProbeOk || result is ProbeNotInitialized || result is ProbeTooOld) return result;
      // Prefer reporting the more specific failure ("not Audiobookshelf")
      // over a plain "unreachable" from the other scheme.
      if (firstFailure == null || firstFailure is ProbeUnreachable) firstFailure = result;
    }
    return firstFailure!;
  }

  Future<ProbeResult> _probeOne(Uri base, Map<String, String> headers) async {
    final options = Options(
      headers: headers,
      sendTimeout: timeout,
      receiveTimeout: timeout,
      validateStatus: (_) => true,
      responseType: ResponseType.json,
    );
    try {
      final status = await _dio.getUri<Object?>(base.replace(path: '${base.path}/status'), options: options);
      final data = status.data;
      if (status.statusCode != 200 || data is! Map || data['app'] != 'audiobookshelf') {
        return ProbeNotAbs('GET ${base.replace(path: '${base.path}/status')} answered HTTP ${status.statusCode}');
      }
      if (data['isInit'] != true) return ProbeNotInitialized(base);
      final version = ServerVersion.tryParse(data['serverVersion'] as String?);
      if (version == null) return const ProbeNotAbs('No serverVersion in /status');
      if (version < minServerVersion) return ProbeTooOld(version);
      final methods = <AuthMethod>{
        for (final m in (data['authMethods'] as List? ?? const ['local']))
          if (m == 'local') AuthMethod.local else if (m == 'openid') AuthMethod.openid,
      };
      final form = data['authFormData'];
      String? text(String key) {
        final value = form is Map ? form[key] : null;
        return value is String && value.trim().isNotEmpty ? value : null;
      }

      return ProbeOk(
        baseUrl: base,
        version: version,
        authMethods: methods.isEmpty ? {AuthMethod.local} : methods,
        oidcButtonText: text('authOpenIDButtonText'),
        loginMessage: text('authLoginCustomMessage'),
      );
    } on DioException catch (e) {
      return ProbeUnreachable(AbsFailure.from(e).details);
    }
  }
}
