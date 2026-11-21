// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/app/theme/app_theme.dart';
import 'package:earloom/core/ui/cover_image.dart';
import 'package:earloom/features/settings/ui/settings_screen.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../support/test_app.dart';

Future<void> _open(WidgetTester tester, String section) async {
  tester.view.physicalSize = const Size(412, 1000) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await pumpEarloom(
    tester,
    initialRoute: '/you/settings',
    overrides: [
      packageInfoProvider.overrideWithValue(
        AsyncData(
          PackageInfo(appName: 'Earloom', packageName: 'com.affluentlabs.earloom', version: '0.1.0', buildNumber: '1'),
        ),
      ),
    ],
  );
  await settle(tester);
  await tester.tap(find.text(section));
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the settings home lists every section', (tester) async {
    final l10n = await loadL10n();
    await pumpEarloom(tester, initialRoute: '/you/settings');
    await settle(tester);
    for (final title in [
      l10n.settingsPlayback,
      l10n.settingsAppearance,
      l10n.settingsStats,
      l10n.settingsAccounts,
      l10n.settingsPrivacy,
      l10n.settingsAbout,
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('the theme changes at once', (tester) async {
    final l10n = await loadL10n();
    await _open(tester, l10n.settingsAppearance);
    await tester.tap(find.text(l10n.settingsThemeAmoled));
    await settle(tester);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, AppThemeMode.amoled.materialMode);
    expect(app.darkTheme?.colorScheme.surface, AppTheme.amoled().colorScheme.surface);
  });

  testWidgets('About shows the version and the disclaimer', (tester) async {
    final l10n = await loadL10n();
    await _open(tester, l10n.settingsAbout);
    expect(find.text(l10n.aboutDisclaimer), findsOneWidget);
    expect(find.text(l10n.aboutVersion('0.1.0 (1)')), findsOneWidget);
    expect(find.text(l10n.aboutContactBody('contact@affluentlabs.dev')), findsOneWidget);
  });

  testWidgets('Playback holds the player settings', (tester) async {
    final l10n = await loadL10n();
    await _open(tester, l10n.settingsPlayback);
    expect(find.text(l10n.playerSettingsSkipBack), findsOneWidget);
  });

  testWidgets('Privacy states the promise', (tester) async {
    final l10n = await loadL10n();
    await _open(tester, l10n.settingsPrivacy);
    expect(find.text(l10n.privacyStatement), findsOneWidget);
  });

  testWidgets('Privacy links to the full policy', (tester) async {
    final l10n = await loadL10n();
    await _open(tester, l10n.settingsPrivacy);
    expect(find.text(l10n.privacyPolicy), findsOneWidget);
    expect(find.text(l10n.privacyPolicyBody), findsOneWidget);
    // The address the store listings give: a web page anyone can open.
    expect(PrivacySettingsScreen.policy.scheme, 'https');
    expect(PrivacySettingsScreen.policy.path, endsWith('docs/privacy-policy.md'));
  });

  testWidgets('clearing saved covers empties every store that holds covers', (tester) async {
    final l10n = await loadL10n();
    await _open(tester, l10n.settingsPrivacy);
    final covers = _CountingCache();
    final older = _CountingCache();
    CoverCache.manager = covers;
    CoverCache.older = older;
    addTearDown(() => CoverCache.older = null);

    await tester.tap(find.text(l10n.privacyClearImageCache));
    await settle(tester);
    expect(covers.emptied, 1, reason: 'the store nearly all covers are in');
    expect(older.emptied, 1, reason: 'what earlier builds saved elsewhere');
    expect(find.text(l10n.privacyImageCacheCleared), findsOneWidget);
  });
}

/// A cover store that only counts how often it was emptied.
class _CountingCache extends Fake implements BaseCacheManager {
  int emptied = 0;

  @override
  Future<void> emptyCache() async => emptied++;
}
