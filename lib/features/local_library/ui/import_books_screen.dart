// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/util/size_format.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/import_models.dart';
import 'error_details_card.dart';
import 'import_controller.dart';

/// `/local/import`: copies audiobook files from the phone into the On this
/// device library. Explain, pick, copy with progress, report.
class ImportBooksScreen extends ConsumerWidget {
  const ImportBooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);
    final Widget body = switch (state) {
      ImportIdle() => _IntroView(onFiles: controller.chooseFiles, onFolder: controller.chooseFolder),
      ImportPreparing() => const _PreparingView(),
      ImportNeedsDecision(:final plan) => _DuplicatesView(
        plan: plan,
        onSkip: () => controller.resolveDuplicates(addCopies: false),
        onAddCopies: () => controller.resolveDuplicates(addCopies: true),
      ),
      ImportRunning() => _RunningView(state: state, onCancel: controller.cancel),
      ImportFinished() => _FinishedView(
        state: state,
        onOpenLibrary: () => context.go(AppRoutes.library),
        onAddMore: controller.reset,
      ),
      ImportProblem() => _ProblemView(problem: state, onRetry: controller.reset),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.importTitle)),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: Motion.normal,
          child: KeyedSubtree(key: ValueKey(state.runtimeType), child: body),
        ),
      ),
    );
  }
}

/// Book titles are set in the serif, at list size.
TextStyle? _bookTitleStyle(ThemeData theme) =>
    theme.textTheme.titleLarge?.copyWith(fontSize: theme.textTheme.titleMedium?.fontSize, height: 1.2);

/// A page with comfortable margins that scrolls when the text is large.
class _Page extends StatelessWidget {
  const _Page({required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xl),
            children: children,
          ),
        ),
        if (footer != null)
          Padding(padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.lg), child: footer),
      ],
    );
  }
}

class _IntroView extends StatelessWidget {
  const _IntroView({required this.onFiles, required this.onFolder});

  final VoidCallback onFiles;
  final VoidCallback onFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Page(
      children: [
        const SizedBox(height: Space.xl),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.library_music_outlined, size: 40, color: scheme.onSecondaryContainer),
          ),
        ),
        const SizedBox(height: Space.xl),
        Text(l10n.importHeadline, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.md),
        Text(
          l10n.importExplanation,
          style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xxl),
        _ChoiceCard(
          icon: Icons.audio_file_outlined,
          label: l10n.importChooseFiles,
          hint: l10n.importChooseFilesHint,
          onTap: onFiles,
          filled: true,
        ),
        const SizedBox(height: Space.md),
        _ChoiceCard(
          icon: Icons.folder_open_outlined,
          label: l10n.importChooseFolder,
          hint: l10n.importChooseFolderHint,
          onTap: onFolder,
        ),
        const SizedBox(height: Space.xl),
        Text(
          l10n.importSupportedFormats,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A large, two line action: what it does and what comes of it.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = filled ? scheme.primaryContainer : scheme.surfaceContainerHigh;
    final foreground = filled ? scheme.onPrimaryContainer : scheme.onSurface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(Radii.card),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 28),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleMedium?.copyWith(color: foreground)),
                      const SizedBox(height: Space.xs),
                      Text(hint, style: theme.textTheme.bodyMedium?.copyWith(color: foreground.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreparingView extends StatelessWidget {
  const _PreparingView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        Expanded(
          child: _Page(
            children: [
              Text(l10n.importPreparing, style: theme.textTheme.headlineMedium),
              const SizedBox(height: Space.sm),
              Text(
                l10n.importPreparingHint,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Space.xl),
              for (var i = 0; i < 3; i++) const _SkeletonRow(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shaped like a book row, so the list does not jump when it arrives.
class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.pill)),
      ),
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(0.7, 14),
                  const SizedBox(height: Space.sm),
                  bar(0.4, 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicatesView extends StatelessWidget {
  const _DuplicatesView({required this.plan, required this.onSkip, required this.onAddCopies});

  final ImportPlan plan;
  final VoidCallback onSkip;
  final VoidCallback onAddCopies;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final duplicates = plan.duplicates;
    return _Page(
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: onSkip, child: Text(l10n.importSkipDuplicates)),
          const SizedBox(height: Space.sm),
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: onAddCopies,
            child: Text(l10n.importAddCopies),
          ),
        ],
      ),
      children: [
        Text(l10n.importDuplicatesTitle, style: theme.textTheme.headlineMedium),
        const SizedBox(height: Space.md),
        Text(l10n.importDuplicatesBody(duplicates.length), style: theme.textTheme.bodyLarge),
        const SizedBox(height: Space.lg),
        for (final book in duplicates)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                Icon(Icons.library_books_outlined, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: Space.lg),
                Expanded(child: Text(book.duplicateOf!.title, style: _bookTitleStyle(theme))),
              ],
            ),
          ),
      ],
    );
  }
}

class _RunningView extends StatelessWidget {
  const _RunningView({required this.state, required this.onCancel});

  final ImportRunning state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final progress = state.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: progress?.fraction),
        Expanded(
          child: _Page(
            footer: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
              onPressed: state.cancelling ? null : onCancel,
              child: Text(l10n.genericCancel),
            ),
            children: [
              Text(l10n.importRunningTitle(state.books.length), style: theme.textTheme.headlineMedium),
              const SizedBox(height: Space.lg),
              for (var i = 0; i < state.books.length; i++) _RunningRow(book: state.books[i], index: i, state: state),
            ],
          ),
        ),
      ],
    );
  }
}

class _RunningRow extends StatelessWidget {
  const _RunningRow({required this.book, required this.index, required this.state});

  final PlannedBook book;
  final int index;
  final ImportRunning state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = state.progress;
    final current = progress?.bookIndex ?? 0;

    final Widget leading;
    final String status;
    if (index < current) {
      final failed = progress?.failedBooks.contains(index) ?? false;
      leading = Icon(
        failed ? Icons.error_outline_rounded : Icons.check_circle_rounded,
        color: failed ? scheme.error : scheme.primary,
      );
      status = failed ? l10n.importBookFailed : l10n.importBookAdded;
    } else if (index == current) {
      leading = SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          value: progress == null || progress.stage != ImportStage.copying ? null : progress.bookFraction,
          strokeWidth: 3,
        ),
      );
      status = switch (progress?.stage) {
        ImportStage.reading => l10n.importStageReading,
        ImportStage.saving => l10n.importStageSaving,
        _ => l10n.importBytesProgress(
          formatBytes(l10n, progress?.bookBytesDone ?? 0),
          formatBytes(l10n, book.totalBytes),
        ),
      };
    } else {
      leading = Icon(Icons.schedule_rounded, color: scheme.onSurfaceVariant);
      status = l10n.importWaiting(formatBytes(l10n, book.totalBytes));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            SizedBox(width: 40, child: Center(child: leading)),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.displayName, style: _bookTitleStyle(theme), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: Space.xs),
                  Text(status, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishedView extends StatelessWidget {
  const _FinishedView({required this.state, required this.onOpenLibrary, required this.onAddMore});

  final ImportFinished state;
  final VoidCallback onOpenLibrary;
  final VoidCallback onAddMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outcome = state.outcome;
    final added = outcome.added.length;
    return _Page(
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (added > 0) FilledButton(onPressed: onOpenLibrary, child: Text(l10n.importOpenLibrary)),
          if (added > 0) const SizedBox(height: Space.sm),
          if (added > 0)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: onAddMore,
              child: Text(l10n.importAddMore),
            )
          else
            FilledButton(onPressed: onAddMore, child: Text(l10n.importAddMore)),
        ],
      ),
      children: [
        const SizedBox(height: Space.lg),
        Icon(
          added > 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
          size: 56,
          color: added > 0 ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(height: Space.lg),
        Text(l10n.importDoneTitle(added), style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.md),
        for (final note in [
          if (outcome.cancelled) l10n.importDoneCancelled,
          if (state.skippedDuplicates > 0) l10n.importSkippedDuplicates(state.skippedDuplicates),
          if (state.skippedFiles > 0) l10n.importSkippedFiles(state.skippedFiles),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(
              note,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
        if (added > 0) ...[
          const SizedBox(height: Space.lg),
          for (final book in outcome.added)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  Icon(Icons.check_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: Space.md),
                  Expanded(child: Text(book.title, style: _bookTitleStyle(theme))),
                ],
              ),
            ),
        ],
        for (final failure in outcome.failed) ...[
          const SizedBox(height: Space.lg),
          ErrorDetailsCard(
            title: failure.bookName,
            titleStyle: _bookTitleStyle(theme),
            message: importErrorMessage(l10n, failure.kind),
            details: failure.details,
          ),
        ],
      ],
    );
  }
}

class _ProblemView extends StatelessWidget {
  const _ProblemView({required this.problem, required this.onRetry});

  final ImportProblem problem;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final message = switch (problem.kind) {
      ImportProblemKind.noAudio => l10n.importErrorNoAudio,
      ImportProblemKind.noSpace => l10n.importErrorNoSpace,
      ImportProblemKind.unreadable => l10n.importErrorUnreadable,
      ImportProblemKind.notDownloaded => l10n.importErrorNotDownloaded,
      ImportProblemKind.unknown => l10n.importErrorUnknown,
    };
    return _Page(
      footer: FilledButton(onPressed: onRetry, child: Text(l10n.genericRetry)),
      children: [
        const SizedBox(height: Space.lg),
        Icon(Icons.error_outline_rounded, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: Space.lg),
        Text(l10n.importFailedTitle, style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
        const SizedBox(height: Space.lg),
        ErrorDetailsCard(message: message, details: problem.details),
      ],
    );
  }
}

/// The plain words for a book that could not be imported.
String importErrorMessage(AppLocalizations l10n, ImportErrorKind kind) => switch (kind) {
  ImportErrorKind.noSpace => l10n.importErrorNoSpace,
  ImportErrorKind.unreadable => l10n.importErrorUnreadable,
  ImportErrorKind.notDownloaded => l10n.importErrorNotDownloaded,
  ImportErrorKind.unknown => l10n.importErrorUnknown,
};
