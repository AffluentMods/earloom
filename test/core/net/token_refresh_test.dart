// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:earloom/core/net/abs_auth_api.dart';
import 'package:earloom/core/net/abs_errors.dart';
import 'package:earloom/core/net/auth_interceptor.dart';
import 'package:earloom/core/net/jwt.dart';
import 'package:earloom/core/net/redacting_logger.dart';
import 'package:earloom/core/net/token_refresher.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_http.dart';

class RecordingEvents implements TokenEvents {
  final rotated = <String>[];
  final reauth = <String>[];

  @override
  void tokensRotated(String accountId) => rotated.add(accountId);

  @override
  void needsReauth(String accountId) => reauth.add(accountId);
}

Map<String, Object?> loginBody(String access, String refresh) => {
  'user': {
    'id': 'u1',
    'username': 'affluent',
    'type': 'user',
    'token': 'legacy',
    'accessToken': access,
    'refreshToken': refresh,
  },
  'userDefaultLibraryId': 'lib1',
  'serverSettings': {'timeZone': 'UTC'},
};

void main() {
  final now = DateTime.utc(2026, 11, 14, 12);
  final base = Uri.parse('https://books.example.com');

  late MemorySecureStore store;
  late RecordingEvents events;
  setUp(() {
    store = MemorySecureStore();
    events = RecordingEvents();
  });

  TokenRefresher refresherWith(Future<FakeResponse> Function(RequestOptions r) server) {
    final (dio, _) = fakeDio(server);
    return TokenRefresher(
      store: store,
      events: events,
      clock: () => now,
      apiFor: (_) async => AbsAuthApi(base, dio: dio),
    );
  }

  group('jwt', () {
    test('reads exp and decides when a refresh is due', () {
      final token = fakeJwt(exp: now.add(const Duration(minutes: 10)));
      expect(jwtExpiry(token), now.add(const Duration(minutes: 10)));
      expect(jwtExpiresSoon(token, now: now), isFalse);
      expect(jwtExpiresSoon(token, now: now.add(const Duration(minutes: 9))), isTrue);
      expect(jwtExpiresSoon('not.a.jwt', now: now), isTrue);
    });
  });

  group('TokenRefresher', () {
    test('stores the rotated pair and reports it', () async {
      await store.writeTokens('a1', access: 'old-access', refresh: 'old-refresh');
      final seen = <RequestOptions>[];
      final refresher = refresherWith((r) async {
        seen.add(r);
        return FakeResponse.json(200, loginBody('new-access', 'new-refresh'));
      });
      expect(await refresher.refresh('a1'), isTrue);
      expect(seen.single.headers['x-refresh-token'], 'old-refresh');
      expect(seen.single.data, isNull, reason: 'refresh has no body');
      expect(await store.readAccess('a1'), 'new-access');
      expect(await store.readRefresh('a1'), 'new-refresh');
      expect(events.rotated, ['a1']);
    });

    test('concurrent callers share one refresh', () async {
      await store.writeTokens('a1', access: 'old', refresh: 'r0');
      final release = Completer<void>();
      var hits = 0;
      final refresher = refresherWith((r) async {
        hits++;
        await release.future;
        return FakeResponse.json(200, loginBody('a', 'r1'));
      });
      final results = Future.wait([for (var i = 0; i < 10; i++) refresher.refresh('a1')]);
      release.complete();
      expect(await results, everyElement(isTrue));
      expect(hits, 1);
    });

    test('401 means sign in again, and does not retry', () async {
      await store.writeTokens('a1', access: 'old', refresh: 'dead');
      var hits = 0;
      final refresher = refresherWith((r) async {
        hits++;
        return FakeResponse.json(401, {'error': 'Invalid refresh token'});
      });
      expect(await refresher.refresh('a1'), isFalse);
      expect(events.reauth, ['a1']);
      expect(hits, 1);
    });

    test('429 and network errors keep the account signed in', () async {
      await store.writeTokens('a1', access: 'old', refresh: 'r0');
      final limited = refresherWith(
        (r) async => FakeResponse.json(
          429,
          {'error': 'Too many authentication requests'},
          {
            'retry-after': ['330'],
          },
        ),
      );
      await expectLater(
        limited.refresh('a1'),
        throwsA(isA<AbsRateLimited>().having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 330))),
      );
      final offline = refresherWith((r) async => throw connectionError(r));
      await expectLater(offline.refresh('a1'), throwsA(isA<AbsUnreachable>()));
      expect(events.reauth, isEmpty);
      expect(await store.readRefresh('a1'), 'r0');
    });

    test('refreshIfNeeded only refreshes close to expiry', () async {
      var hits = 0;
      final refresher = refresherWith((r) async {
        hits++;
        return FakeResponse.json(200, loginBody(fakeJwt(exp: now.add(const Duration(hours: 1))), 'r1'));
      });
      await store.writeTokens(
        'a1',
        access: fakeJwt(exp: now.add(const Duration(minutes: 30))),
        refresh: 'r0',
      );
      await refresher.refreshIfNeeded('a1');
      expect(hits, 0);
      await store.writeTokens(
        'a1',
        access: fakeJwt(exp: now.add(const Duration(minutes: 1))),
        refresh: 'r0',
      );
      await refresher.refreshIfNeeded('a1');
      expect(hits, 1);
    });
  });

  group('AuthInterceptor', () {
    test('10 parallel requests that all get 401 cause exactly one refresh, then all succeed', () async {
      final fresh = fakeJwt(exp: now.add(const Duration(hours: 1)), id: 'fresh');
      final stale = fakeJwt(exp: now.add(const Duration(hours: 1)), id: 'stale');
      await store.writeTokens('a1', access: stale, refresh: 'r0');
      var refreshes = 0;
      final refresher = refresherWith((r) async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return FakeResponse.json(200, loginBody(fresh, 'r1'));
      });
      final (api, _) = fakeDio((r) async {
        final auth = r.headers['Authorization'];
        if (auth == 'Bearer $stale') return const FakeResponse(401, 'Unauthorized');
        if (auth == 'Bearer $fresh') return FakeResponse.json(200, {'ok': true});
        return const FakeResponse(500, 'unexpected');
      });
      api.interceptors.add(AuthInterceptor(accountId: 'a1', store: store, refresher: refresher, retryDio: api));
      final results = await Future.wait([
        for (var i = 0; i < 10; i++) api.get<Object?>('https://books.example.com/api/me'),
      ]);
      expect(results.map((r) => r.statusCode), everyElement(200));
      expect(refreshes, 1);
    });

    test('a failed refresh surfaces the original 401 without looping', () async {
      await store.writeTokens(
        'a1',
        access: fakeJwt(exp: now.add(const Duration(hours: 1))),
        refresh: 'dead',
      );
      final refresher = refresherWith((r) async => FakeResponse.json(401, {'error': 'Invalid refresh token'}));
      var calls = 0;
      final (api, _) = fakeDio((r) async {
        calls++;
        return const FakeResponse(401, 'Unauthorized');
      });
      api.interceptors.add(AuthInterceptor(accountId: 'a1', store: store, refresher: refresher, retryDio: api));
      await expectLater(api.get<Object?>('https://books.example.com/api/me'), throwsA(isA<DioException>()));
      expect(calls, 1);
      expect(events.reauth, ['a1']);
    });

    test('custom headers are sent on every request', () async {
      await store.writeTokens(
        'a1',
        access: fakeJwt(exp: now.add(const Duration(hours: 1))),
        refresh: 'r',
      );
      await store.writeCustomHeaders('a1', {'CF-Access-Client-Id': 'abc'});
      final refresher = refresherWith((r) async => const FakeResponse(500));
      final (api, adapter) = fakeDio((r) async => FakeResponse.json(200, {}));
      api.interceptors.add(AuthInterceptor(accountId: 'a1', store: store, refresher: refresher, retryDio: api));
      await api.get<Object?>('https://books.example.com/api/me');
      expect(adapter.requests.single.headers['CF-Access-Client-Id'], 'abc');
    });
  });

  group('RedactingLogger', () {
    test('never prints a token, cookie or password', () async {
      final lines = <String>[];
      final (api, _) = fakeDio((r) async => FakeResponse.json(200, {}));
      api.interceptors.add(RedactingLogger(sink: lines.add));
      await api.post<Object?>(
        'https://books.example.com/login?token=SECRET5',
        data: {'username': 'affluent', 'password': 'SECRET1'},
        options: Options(
          headers: {'Authorization': 'Bearer SECRET2', 'x-refresh-token': 'SECRET3', 'cookie': 'SECRET4'},
        ),
      );
      final log = lines.join('\n');
      expect(log, isNot(contains('SECRET')));
      expect(log, contains('affluent'));
    });
  });
}
