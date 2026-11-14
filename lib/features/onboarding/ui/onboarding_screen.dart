// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';

/// First launch: what Earloom is, and the two ways in. No permission
/// prompts here: they come later, when a feature needs them.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  static const _covers = [
    'assets/demo/covers/long_way_to_morning.jpg',
    'assets/demo/covers/clockmakers_tide.jpg',
    'assets/demo/covers/salt_and_starlight.jpg',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.lg),
                child: Column(
                  children: [
                    SizedBox(
                      height: math.min(box.maxHeight * 0.42, 360),
                      child: const _CoverFan(covers: _covers),
                    ),
                    const SizedBox(height: Space.xxl),
                    Text(
                      l10n.onboardingTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: Space.md),
                    Text(
                      l10n.onboardingBody,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
                    ),
                    const SizedBox(height: Space.xxl),
                    FilledButton.icon(
                      onPressed: () => context.push('/accounts/add'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      icon: const Icon(Icons.dns_outlined),
                      label: Text(l10n.onboardingConnectServer),
                    ),
                    const SizedBox(height: Space.md),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ref.read(onboardingProvider.notifier).complete();
                        if (context.mounted) context.go('/local/import');
                      },
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      icon: const Icon(Icons.phone_iphone_rounded),
                      label: Text(l10n.onboardingUseLocalFiles),
                    ),
                    const SizedBox(height: Space.sm),
                    TextButton(
                      onPressed: () => _explainAbs(context),
                      child: Text(l10n.onboardingWhatIsAbs),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _explainAbs(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.onboardingWhatIsAbs, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.md),
              Text(l10n.onboardingWhatIsAbsBody, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: Space.lg),
              OutlinedButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse('https://www.audiobookshelf.org'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(l10n.genericLearnMore),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three covers fanned like books on a table. Decorative: hidden from
/// screen readers. Settles in once when the screen opens (not with reduce
/// motion).
class _CoverFan extends StatelessWidget {
  const _CoverFan({required this.covers});

  final List<String> covers;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = math.min(box.maxHeight * 0.78, box.maxWidth * 0.52);
          const angles = [-0.16, 0.0, 0.16];
          const shifts = [-0.62, 0.0, 0.62];
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
            duration: Motion.slow * 2,
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => Stack(
              alignment: Alignment.center,
              children: [
                for (final i in [0, 2, 1])
                  Transform.translate(
                    offset: Offset(shifts[i] * size * t, (i == 1 ? -0.04 : 0.06) * size),
                    child: Transform.rotate(
                      angle: angles[i] * t,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.cover),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: 0.35),
                              blurRadius: size * 0.12,
                              offset: Offset(0, size * 0.05),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(covers[i], fit: BoxFit.cover),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
