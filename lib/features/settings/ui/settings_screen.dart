// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../player/ui/player_settings_sheet.dart';
import '../../stats/ui/stats_screen.dart';

/// The settings home: one row per section, each with a line saying what
/// is inside.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget row(IconData icon, String title, String body, VoidCallback onTap) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(body),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(l10n.settingsTitle)),
          SliverList.list(
            children: [
              row(
                Icons.play_circle_outline_rounded,
                l10n.settingsPlayback,
                l10n.settingsPlaybackBody,
                () => context.push(AppRoutes.settingsPlayback),
              ),
              row(
                Icons.palette_outlined,
                l10n.settingsAppearance,
                l10n.settingsAppearanceBody,
                () => context.push(AppRoutes.settingsAppearance),
              ),
              row(
                Icons.flag_outlined,
                l10n.settingsStats,
                l10n.settingsStatsBody,
                () => showStatsGoalSheet(context),
              ),
              row(
                Icons.dns_outlined,
                l10n.settingsAccounts,
                l10n.settingsAccountsBody,
                () => context.push(AppRoutes.accounts),
              ),
              row(
                Icons.shield_outlined,
                l10n.settingsPrivacy,
                l10n.settingsPrivacyBody,
                () => context.push(AppRoutes.settingsPrivacy),
              ),
              row(
                Icons.info_outline_rounded,
                l10n.settingsAbout,
                l10n.settingsAboutBody,
                () => context.push(AppRoutes.settingsAbout),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PlaybackSettingsScreen extends StatelessWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPlayback)),
      body: const PlayerSettingsList(showTitle: false),
    );
  }
}

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final labels = {
      AppThemeMode.system: (Icons.brightness_auto_outlined, l10n.settingsThemeSystem),
      AppThemeMode.light: (Icons.light_mode_outlined, l10n.settingsThemeLight),
      AppThemeMode.dark: (Icons.dark_mode_outlined, l10n.settingsThemeDark),
      AppThemeMode.amoled: (Icons.contrast_rounded, l10n.settingsThemeAmoled),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAppearance)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xs),
            child: Text(
              l10n.settingsTheme,
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          RadioGroup<AppThemeMode>(
            groupValue: mode,
            onChanged: (m) {
              if (m != null) ref.read(themeModeProvider.notifier).set(m);
            },
            child: Column(
              children: [
                for (final entry in labels.entries)
                  RadioListTile<AppThemeMode>(
                    contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
                    value: entry.key,
                    secondary: Icon(entry.value.$1),
                    title: Text(entry.value.$2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsPrivacy)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Card.filled(
              margin: EdgeInsets.zero,
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_rounded, color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        l10n.privacyStatement,
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            leading: const Icon(Icons.image_not_supported_outlined),
            title: Text(l10n.privacyClearImageCache),
            subtitle: Text(l10n.privacyClearImageCacheBody),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await CachedNetworkImageProvider.defaultCacheManager.emptyCache();
              PaintingBinding.instance.imageCache
                ..clear()
                ..clearLiveImages();
              messenger.showSnackBar(SnackBar(content: Text(l10n.privacyImageCacheCleared)));
            },
          ),
        ],
      ),
    );
  }
}

final packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  static final _source = Uri.parse('https://github.com/AffluentMods/earloom');
  static const _contact = 'contact@affluentlabs.dev';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final version = ref.watch(packageInfoProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsAbout)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.appName, style: theme.textTheme.displaySmall),
                if (version != null)
                  Text(
                    l10n.aboutVersion('${version.version} (${version.buildNumber})'),
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            leading: const Icon(Icons.code_rounded),
            title: Text(l10n.aboutSource),
            subtitle: Text(l10n.aboutSourceBody),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => launchUrl(_source, mode: LaunchMode.externalApplication),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            leading: const Icon(Icons.mail_outline_rounded),
            title: Text(l10n.aboutContact),
            subtitle: Text(l10n.aboutContactBody(_contact)),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => launchUrl(
              Uri(scheme: 'mailto', path: _contact),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutLicenses),
            subtitle: Text(l10n.aboutLicensesBody),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appName,
              applicationVersion: version?.version,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
            child: Text(
              l10n.aboutDisclaimer,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, 0),
            child: Text(l10n.aboutMadeBy, style: theme.textTheme.labelLarge),
          ),
        ],
      ),
    );
  }
}
