// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/providers.dart';
import 'package:earloom/core/db/global_db.dart';
import 'package:earloom/l10n/gen/app_localizations.dart';
import 'package:earloom/core/net/abs_auth_api.dart';
import 'package:earloom/core/net/server_probe.dart';
import 'package:earloom/core/net/server_version.dart';
import 'package:earloom/core/storage/secure_store.dart';
import 'package:earloom/features/accounts/data/account_session.dart';
import 'package:earloom/features/accounts/data/accounts_repository.dart';
import 'package:earloom/features/accounts/ui/accounts_screen.dart';
import 'package:earloom/features/accounts/ui/add_server_controller.dart';
import 'package:earloom/features/accounts/ui/add_server_screen.dart';
import 'package:earloom/features/home/ui/home_screen.dart';
import 'package:earloom/features/onboarding/ui/onboarding_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fake_http.dart';
import '../../support/test_app.dart';

class FakeProbe extends ServerProbe {
  FakeProbe(this.result);
  final ProbeResult result;
  final seen = <String>[];

  @override
  Future<ProbeResult> probe(String input, {Map<String, String> headers = const {}}) async {
    seen.add(input);
    return result;
  }
}

final okServer = ProbeOk(
  baseUrl: Uri.parse('http://192.168.1.20:13378'),
  version: const ServerVersion(2, 37, 2),
  authMethods: const {AuthMethod.local, AuthMethod.openid},
  oidcButtonText: 'Example SSO',
);

/// A repository whose server accepts affluent / right.
AccountsRepository fakeRepository(GlobalDb db, MemorySecureStore store) => AccountsRepository(
  db: db,
  store: store,
  authApi: (url, headers) {
    final (dio, _) = fakeDio((r) async {
      final body = r.data as Map;
      if (body['password'] != 'right') return const FakeResponse(401, 'Unauthorized');
      return FakeResponse.json(200, {
        'user': {'id': 'u1', 'username': 'affluent', 'type': 'user', 'accessToken': 'a', 'refreshToken': 'r'},
      });
    });
    return AbsAuthApi(url, dio: dio, headers: headers);
  },
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a fresh install opens onboarding, with both ways in', (tester) async {
    await pumpEarloom(tester, onboarded: false);
    final l10n = await loadL10n();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text(l10n.onboardingConnectServer), findsOneWidget);
    expect(find.text(l10n.onboardingUseLocalFiles), findsOneWidget);
  });

  testWidgets('each probe failure has its own message, with details to copy', (tester) async {
    final l10n = await loadL10n();
    for (final (result, message) in [
      (const ProbeUnreachable('connectionError: refused'), l10n.probeUnreachable),
      (const ProbeNotAbs('HTTP 404'), l10n.probeNotAbs),
      (ProbeNotInitialized(Uri.parse('http://x')), l10n.probeNotInitialized),
      (const ProbeTooOld(ServerVersion(2, 20, 0)), l10n.probeTooOld('2.20.0')),
    ]) {
      await pumpEarloom(
        tester,
        initialRoute: '/accounts/add',
        overrides: [serverProbeProvider.overrideWithValue(FakeProbe(result))],
      );
      await tester.enterText(find.byType(TextField).first, 'books.example.com');
      await tester.tap(find.text(l10n.genericContinue));
      await tester.pumpAndSettle();
      expect(find.text(message), findsOneWidget, reason: '$result');
      expect(find.text(l10n.genericCopyDetails), findsOneWidget);
    }
  });

  testWidgets('a found server shows its version, the cleartext warning and both sign-in methods', (tester) async {
    final l10n = await loadL10n();
    await pumpEarloom(
      tester,
      initialRoute: '/accounts/add',
      overrides: [serverProbeProvider.overrideWithValue(FakeProbe(okServer))],
    );
    await tester.enterText(find.byType(TextField).first, '192.168.1.20:13378');
    await tester.tap(find.text(l10n.genericContinue));
    await tester.pumpAndSettle();
    expect(find.text(l10n.probeServerVersion('2.37.2')), findsOneWidget);
    expect(find.text(l10n.probeCleartextWarning), findsOneWidget);
    expect(find.text(l10n.signInUsername), findsOneWidget);
    expect(find.text(l10n.signInWithSso('Example SSO')), findsOneWidget);
  });

  testWidgets('wrong password says so; the right one signs in and lands on Home', (tester) async {
    tester.view.physicalSize = const Size(412, 1100) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final l10n = await loadL10n();
    final store = MemorySecureStore();
    late GlobalDb db;
    await pumpEarloom(
      tester,
      onboarded: false,
      initialRoute: '/accounts/add',
      onDb: (value) => db = value,
      secureStore: store,
      overrides: [
        serverProbeProvider.overrideWithValue(FakeProbe(okServer)),
        accountsRepositoryProvider.overrideWith((ref) => fakeRepository(db, store)),
      ],
    );
    await tester.enterText(find.byType(TextField).first, '192.168.1.20:13378');
    await tester.tap(find.text(l10n.genericContinue));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, l10n.signInUsername), 'affluent');
    await tester.enterText(find.widgetWithText(TextField, l10n.signInPassword), 'wrong');
    // The button enables itself on the next frame, once both fields are filled.
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.signInButton));
    await settle(tester);
    expect(find.text(l10n.signInWrongCredentials), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, l10n.signInPassword), 'right');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.signInButton));
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(AddServerScreen), findsNothing);
    expect(await store.readAccess((await tester.runAsync(db.currentAccount))!.id), 'a');
  });

  testWidgets('the sign-in-again banner shows only for a signed-out current account', (tester) async {
    final l10n = await loadL10n();
    final db = await openTestGlobalDb(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [globalDbProvider.overrideWithValue(db), secureStoreProvider.overrideWithValue(MemorySecureStore())],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ReauthBanner()),
        ),
      ),
    );
    await settle(tester);
    expect(find.text(l10n.sessionExpiredBanner), findsNothing);
    await tester.runAsync(
      () => db.putCurrentAccount(
        AccountsCompanion.insert(
          id: 'a1',
          serverUrl: 'https://books.example.com',
          displayName: 'books.example.com',
          serverVersion: '2.37.2',
          userId: 'u1',
          username: 'affluent',
          userType: 'user',
          authMethod: 'local',
          createdAt: 0,
          lastUsedAt: 0,
        ),
      ),
    );
    await settle(tester);
    expect(find.text(l10n.sessionExpiredBanner), findsNothing);
    await tester.runAsync(() => db.setAccountStatus('a1', AccountStatus.needsReauth));
    await settle(tester);
    expect(find.text(l10n.sessionExpiredBanner), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
