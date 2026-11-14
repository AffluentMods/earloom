// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/net/server_probe.dart';
import 'package:earloom/core/net/server_version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

Map<String, Object?> status({String version = '2.37.2', bool init = true, List<String> methods = const ['local']}) => {
  'app': 'audiobookshelf',
  'serverVersion': version,
  'isInit': init,
  'authMethods': methods,
  'authFormData': {'authLoginCustomMessage': ''},
};

void main() {
  group('candidateBaseUrls', () {
    test('no scheme tries https first, then http', () {
      expect(candidateBaseUrls('books.example.com'), [
        Uri.parse('https://books.example.com'),
        Uri.parse('http://books.example.com'),
      ]);
    });

    test('keeps ports and sub paths, drops trailing slashes, queries and fragments', () {
      expect(candidateBaseUrls('http://10.0.0.5:13378/'), [Uri.parse('http://10.0.0.5:13378')]);
      expect(candidateBaseUrls('https://example.com/abs//?x=1#y'), [Uri.parse('https://example.com/abs')]);
      expect(candidateBaseUrls('localhost:13378'), [
        Uri.parse('https://localhost:13378'),
        Uri.parse('http://localhost:13378'),
      ]);
    });

    test('rejects empty input, spaces and other schemes', () {
      expect(candidateBaseUrls('  '), isEmpty);
      expect(candidateBaseUrls('my server'), isEmpty);
      expect(candidateBaseUrls('ftp://example.com'), isEmpty);
    });
  });

  group('ServerProbe', () {
    test('a healthy server is ok, with version and sign-in methods', () async {
      final (dio, adapter) = fakeDio((r) async => FakeResponse.json(200, status(methods: ['local', 'openid'])));
      final result = await ServerProbe(dio: dio).probe('https://books.example.com/abs');
      expect(result, isA<ProbeOk>());
      final ok = result as ProbeOk;
      expect(ok.baseUrl, Uri.parse('https://books.example.com/abs'));
      expect(ok.version, const ServerVersion(2, 37, 2));
      expect(ok.authMethods, {AuthMethod.local, AuthMethod.openid});
      expect(ok.isCleartext, isFalse);
      expect(adapter.requests.single.uri.path, '/abs/status');
    });

    test('falls back to http when https does not answer, and flags cleartext', () async {
      final (dio, _) = fakeDio((r) async {
        if (r.uri.scheme == 'https') throw connectionError(r);
        return FakeResponse.json(200, status());
      });
      final result = await ServerProbe(dio: dio).probe('10.0.0.5:13378');
      expect((result as ProbeOk).baseUrl, Uri.parse('http://10.0.0.5:13378'));
      expect(result.isCleartext, isTrue);
    });

    test('custom headers go out with the probe', () async {
      final (dio, adapter) = fakeDio((r) async => FakeResponse.json(200, status()));
      await ServerProbe(dio: dio).probe('https://example.com', headers: {'CF-Access-Client-Id': 'abc'});
      expect(adapter.requests.single.headers['CF-Access-Client-Id'], 'abc');
    });

    test('each failure has its own result', () async {
      Future<ProbeResult> probeWith(FakeResponse answer) async {
        final (dio, _) = fakeDio((r) async => answer);
        return ServerProbe(dio: dio).probe('https://example.com');
      }

      expect(await probeWith(const FakeResponse(200, '<html>router</html>')), isA<ProbeNotAbs>());
      expect(await probeWith(const FakeResponse(404, 'Not found')), isA<ProbeNotAbs>());
      expect(await probeWith(FakeResponse.json(200, status(init: false))), isA<ProbeNotInitialized>());
      final old = await probeWith(FakeResponse.json(200, status(version: '2.25.1')));
      expect(old, isA<ProbeTooOld>());
      expect((old as ProbeTooOld).version, const ServerVersion(2, 25, 1));

      final (dio, _) = fakeDio((r) async => throw connectionError(r));
      expect(await ServerProbe(dio: dio).probe('example.com'), isA<ProbeUnreachable>());
      expect(await ServerProbe(dio: dio).probe('not an address'), isA<ProbeInvalidAddress>());
    });

    test('"not Audiobookshelf" on one scheme beats "unreachable" on the other', () async {
      final (dio, _) = fakeDio((r) async {
        if (r.uri.scheme == 'https') return const FakeResponse(200, '<html>nas login</html>');
        throw connectionError(r);
      });
      expect(await ServerProbe(dio: dio).probe('nas.local'), isA<ProbeNotAbs>());
    });
  });

  group('ServerVersion', () {
    test('parses and compares', () {
      expect(ServerVersion.tryParse('v2.37.2-beta'), const ServerVersion(2, 37, 2));
      expect(ServerVersion.tryParse('2.26'), const ServerVersion(2, 26, 0));
      expect(ServerVersion.tryParse('nope'), isNull);
      expect(const ServerVersion(2, 36, 9) < securityAdvisoryBelow, isTrue);
      expect(const ServerVersion(2, 37, 0) >= securityAdvisoryBelow, isTrue);
      expect(const ServerVersion(2, 25, 9) < minServerVersion, isTrue);
    });
  });
}
