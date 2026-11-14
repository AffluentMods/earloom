// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../core/library/source_id.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../accounts/data/account_session.dart';
import '../data/library_providers.dart';

/// The name the UI shows for a library.
String libraryName(AppLocalizations l10n, LibraryInfo library) =>
    library.source is LocalSource ? l10n.sourceOnThisDevice : library.name;

/// A pill with the current library's name; opens [showLibrarySwitcher].
class LibrarySwitcherButton extends ConsumerWidget {
  const LibrarySwitcherButton({super.key, required this.library, this.large = false});

  final LibraryInfo library;

  /// The serif title form, for the top of a screen.
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final name = libraryName(l10n, library);
    return Semantics(
      button: true,
      label: l10n.librarySwitcherLabel(name),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: () => showLibrarySwitcher(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: large ? text.titleLarge : text.titleMedium,
                  ),
                ),
                const SizedBox(width: Space.xs),
                Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the user pick a server library or On this device.
Future<void> showLibrarySwitcher(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _SwitcherSheet(),
  );
}

class _SwitcherSheet extends ConsumerWidget {
  const _SwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final libraries = ref.watch(availableLibrariesProvider).value ?? const [localLibrary];
    final current = ref.watch(currentLibraryProvider).value;
    final account = ref.watch(currentAccountProvider).value;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.sm),
            child: Text(l10n.librarySwitcherTitle, style: text.titleLarge),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final library in libraries)
                  ListTile(
                    minTileHeight: 64,
                    leading: CircleAvatar(
                      backgroundColor: scheme.secondaryContainer,
                      foregroundColor: scheme.onSecondaryContainer,
                      child: Icon(switch (library) {
                        LibraryInfo(source: LocalSource()) => Icons.phone_iphone_rounded,
                        LibraryInfo(isPodcast: true) => Icons.podcasts_rounded,
                        _ => Icons.auto_stories_rounded,
                      }),
                    ),
                    title: Text(libraryName(l10n, library)),
                    subtitle: library.source is AbsSource && account != null ? Text(account.displayName) : null,
                    trailing: current != null && selectionKey(current) == selectionKey(library)
                        ? Icon(Icons.check_rounded, color: scheme.primary)
                        : null,
                    onTap: () async {
                      Navigator.pop(context);
                      await selectLibrary(ref.read(globalDbProvider), library);
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: Space.lg),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.push(AppRoutes.importFiles);
                  },
                  icon: const Icon(Icons.library_add_outlined),
                  label: Text(l10n.homeAddFiles),
                ),
                if (account == null)
                  OutlinedButton.icon(
                    onPressed: () {
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      router.push(AppRoutes.addServer);
                    },
                    icon: const Icon(Icons.dns_outlined),
                    label: Text(l10n.onboardingConnectServer),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
