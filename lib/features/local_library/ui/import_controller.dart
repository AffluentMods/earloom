// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;

import '../data/import_models.dart';
import '../data/import_picker.dart';
import '../data/import_source.dart';
import '../data/local_importer.dart';
import '../data/providers.dart';

/// What the import screen shows.
sealed class ImportState {
  const ImportState();
}

/// Nothing picked yet.
final class ImportIdle extends ImportState {
  const ImportIdle();
}

/// The picker is handing over files, or they are being grouped and checked.
final class ImportPreparing extends ImportState {
  const ImportPreparing();
}

/// Some picked books are already in the library: the user decides.
final class ImportNeedsDecision extends ImportState {
  const ImportNeedsDecision(this.plan);

  final ImportPlan plan;
}

/// Copying.
final class ImportRunning extends ImportState {
  const ImportRunning({required this.books, this.progress, this.cancelling = false});

  final List<PlannedBook> books;

  /// Null until the first update.
  final ImportProgress? progress;
  final bool cancelling;

  ImportRunning copyWith({ImportProgress? progress, bool? cancelling}) => ImportRunning(
    books: books,
    progress: progress ?? this.progress,
    cancelling: cancelling ?? this.cancelling,
  );
}

/// The import is over.
final class ImportFinished extends ImportState {
  const ImportFinished({
    required this.books,
    required this.outcome,
    this.skippedDuplicates = 0,
    this.skippedFiles = 0,
  });

  final List<PlannedBook> books;
  final ImportOutcome outcome;
  final int skippedDuplicates;
  final int skippedFiles;
}

/// Why nothing could be imported at all.
enum ImportProblemKind { noAudio, noSpace, unreadable, notDownloaded, unknown }

/// The picked files could not be used.
final class ImportProblem extends ImportState {
  const ImportProblem(this.kind, this.details);

  final ImportProblemKind kind;

  /// For "Copy details".
  final String details;
}

final importControllerProvider = NotifierProvider.autoDispose<ImportController, ImportState>(ImportController.new);

/// Drives the import screen: pick, plan, ask about duplicates, copy, report.
///
/// A running import keeps going when the user leaves the screen; coming back
/// shows where it is.
class ImportController extends Notifier<ImportState> {
  KeepAliveLink? _keepAlive;
  ImportSelection? _selection;
  ImportJob? _job;

  @override
  ImportState build() {
    ref.onDispose(() => unawaited(_releaseSelection()));
    return const ImportIdle();
  }

  bool get _canPick => state is ImportIdle || state is ImportFinished || state is ImportProblem;

  Future<void> chooseFiles() {
    return _pick(
      () => ref.read(importPickerProvider).pickFiles(onPreparing: () => state = const ImportPreparing()),
    );
  }

  Future<void> chooseFolder() => _pick(() => ref.read(importPickerProvider).pickFolder());

  Future<void> _pick(Future<ImportSelection?> Function() pick) async {
    if (!_canPick) return;
    _keepAlive ??= ref.keepAlive();
    final before = state;
    try {
      final selection = await pick();
      if (selection == null) {
        state = before is ImportPreparing ? const ImportIdle() : before;
        _letGo();
        return;
      }
      _selection = selection;
      state = const ImportPreparing();
      final plan = await ref.read(bookImporterProvider).plan(selection);
      if (plan.isEmpty) {
        await _releaseSelection();
        state = ImportProblem(ImportProblemKind.noAudio, _describeSkipped(plan.skippedFiles));
        _letGo();
        return;
      }
      if (plan.duplicates.isNotEmpty) {
        state = ImportNeedsDecision(plan);
        return;
      }
      await _start(plan, plan.books);
    } on Object catch (error, stack) {
      await _releaseSelection();
      state = ImportProblem(_problemKind(error), '$error\n$stack');
      _letGo();
    }
  }

  /// Answers [ImportNeedsDecision]: add another copy of the books already in
  /// the library, or only the new ones.
  Future<void> resolveDuplicates({required bool addCopies}) async {
    final current = state;
    if (current is! ImportNeedsDecision) return;
    final plan = current.plan;
    final books = addCopies
        ? plan.books
        : [
            for (final b in plan.books)
              if (b.duplicateOf == null) b,
          ];
    if (books.isEmpty) {
      await _releaseSelection();
      state = ImportFinished(
        books: const [],
        outcome: const ImportOutcome(),
        skippedDuplicates: plan.duplicates.length,
        skippedFiles: plan.skippedFiles.length,
      );
      _letGo();
      return;
    }
    await _start(plan, books, skippedDuplicates: addCopies ? 0 : plan.duplicates.length);
  }

  Future<void> _start(ImportPlan plan, List<PlannedBook> books, {int skippedDuplicates = 0}) async {
    final job = ref.read(bookImporterProvider).start(books);
    _job = job;
    state = ImportRunning(books: books);
    final updates = job.progress.listen((progress) {
      final current = state;
      if (current is ImportRunning) state = current.copyWith(progress: progress);
    });
    final outcome = await job.done;
    unawaited(updates.cancel());
    _job = null;
    await _releaseSelection();
    state = ImportFinished(
      books: books,
      outcome: outcome,
      skippedDuplicates: skippedDuplicates,
      skippedFiles: plan.skippedFiles.length,
    );
    _letGo();
  }

  /// Stops a running import after the current chunk.
  void cancel() {
    final current = state;
    if (current is! ImportRunning || _job == null) return;
    _job!.cancel();
    state = current.copyWith(cancelling: true);
  }

  /// Back to the start, from a result, a problem or the duplicate question.
  Future<void> reset() async {
    if (state is ImportRunning || state is ImportPreparing) return;
    await _releaseSelection();
    state = const ImportIdle();
    _letGo();
  }

  Future<void> _releaseSelection() async {
    final selection = _selection;
    _selection = null;
    try {
      await selection?.onDone?.call();
    } on Object {
      // Cleaning up temporary copies is best effort.
    }
  }

  void _letGo() {
    _keepAlive?.close();
    _keepAlive = null;
  }

  static String _describeSkipped(List<String> names) => names.isEmpty ? 'No files' : 'Not audio: ${names.join(', ')}';

  static ImportProblemKind _problemKind(Object error) {
    if (error is FolderNotDownloaded) return ImportProblemKind.notDownloaded;
    if (error is PlatformException) return ImportProblemKind.unreadable;
    return switch (classifyImportError(error)) {
      ImportErrorKind.noSpace => ImportProblemKind.noSpace,
      ImportErrorKind.unreadable => ImportProblemKind.unreadable,
      ImportErrorKind.notDownloaded => ImportProblemKind.notDownloaded,
      ImportErrorKind.unknown => ImportProblemKind.unknown,
    };
  }
}
