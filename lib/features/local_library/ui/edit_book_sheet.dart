// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/library/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/local_library_repository.dart';
import '../data/providers.dart';
import 'error_details_card.dart';
import 'local_cover.dart';

/// Opens [EditBookSheet] for a local book. Completes with true when the
/// changes were saved.
Future<bool?> showEditBookSheet(BuildContext context, String bookId) {
  return showModalBottomSheet<bool>(
    context: context,
    // Above the tab bar and mini player, wherever it is opened from.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EditBookSheet(bookId: bookId),
  );
}

/// Edits what the tags got wrong: title, author, narrator, series and
/// number, description and the cover.
class EditBookSheet extends ConsumerStatefulWidget {
  const EditBookSheet({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<EditBookSheet> createState() => _EditBookSheetState();
}

class _EditBookSheetState extends ConsumerState<EditBookSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _authors = TextEditingController();
  final _narrators = TextEditingController();
  final _series = TextEditingController();
  final _sequence = TextEditingController();
  final _description = TextEditingController();

  BookDetail? _initial;
  String? _pickedCover;
  bool _saving = false;
  ({String message, String details})? _error;

  @override
  void dispose() {
    for (final c in [_title, _authors, _narrators, _series, _sequence, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(BookDetail detail) {
    _initial = detail;
    final s = detail.summary;
    _title.text = s.title;
    _authors.text = s.authors.join(', ');
    _narrators.text = s.narrators.join(', ');
    _series.text = s.seriesName ?? '';
    _sequence.text = s.seriesSequence ?? '';
    _description.text = detail.descriptionHtml ?? '';
  }

  /// Names as typed, split on commas. Untouched fields keep the stored list,
  /// so a name like "Example, Jane" from the tags survives a save.
  List<String> _names(TextEditingController controller, List<String> stored) {
    if (controller.text == stored.join(', ')) return stored;
    return controller.text.split(',').map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
  }

  Future<void> _pickCover() async {
    final path = await ref.read(importPickerProvider).pickImage();
    if (path != null && mounted) setState(() => _pickedCover = path);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final initial = _initial;
    if (initial == null || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(localLibraryRepositoryProvider)
          .updateMetadata(
            widget.bookId,
            LocalBookEdit(
              title: _title.text,
              authors: _names(_authors, initial.summary.authors),
              narrators: _names(_narrators, initial.summary.narrators),
              seriesName: _series.text,
              seriesSequence: _sequence.text,
              description: _description.text,
              coverImagePath: _pickedCover,
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = (
          message: error is UnsupportedCoverImage ? l10n.editBookCoverUnsupported : l10n.editBookSaveFailed,
          details: '$error\n$stack',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = ref.watch(localBookProvider(widget.bookId));
    if (_initial == null && book.value != null) _fill(book.value!);

    final Widget content;
    if (_initial != null) {
      content = _buildForm(context, _initial!);
    } else if (book.hasError || (book.hasValue && book.value == null)) {
      content = Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: ErrorDetailsCard(message: l10n.editBookSaveFailed, details: '${book.error ?? 'Book not found'}'),
      );
    } else {
      content = const Padding(
        padding: EdgeInsets.all(Space.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.sm, Space.sm),
            child: Row(
              children: [
                Expanded(child: Text(l10n.editBookTitle, style: theme.textTheme.titleLarge)),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  child: Text(l10n.genericCancel),
                ),
                const SizedBox(width: Space.xs),
                FilledButton(onPressed: _saving || _initial == null ? null : _save, child: Text(l10n.genericSave)),
              ],
            ),
          ),
          Flexible(child: content),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, BookDetail detail) {
    final l10n = AppLocalizations.of(context);
    final repository = ref.read(localLibraryRepositoryProvider);
    final File? cover = _pickedCover != null
        ? File(_pickedCover!)
        : repository.coverFile(widget.bookId, detail.summary.coverKey);
    const gap = SizedBox(height: Space.lg);
    return Form(
      key: _form,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.sm, Space.xl, Space.xl),
        children: [
          Row(
            children: [
              LocalCover(file: cover, size: 96, title: detail.summary.title),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), shape: const StadiumBorder()),
                    onPressed: _saving ? null : _pickCover,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(l10n.editBookChangeCover),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          TextFormField(
            controller: _title,
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: l10n.editBookFieldTitle, border: const OutlineInputBorder()),
            validator: (value) => (value ?? '').trim().isEmpty ? l10n.editBookTitleRequired : null,
          ),
          gap,
          TextFormField(
            controller: _authors,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.editBookFieldAuthors,
              helperText: l10n.editBookNamesHint,
              border: const OutlineInputBorder(),
            ),
          ),
          gap,
          TextFormField(
            controller: _narrators,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l10n.editBookFieldNarrators,
              helperText: l10n.editBookNamesHint,
              border: const OutlineInputBorder(),
            ),
          ),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _series,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.editBookFieldSeries, border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: TextFormField(
                  controller: _sequence,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.editBookFieldSequence,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          gap,
          TextFormField(
            controller: _description,
            enabled: !_saving,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.editBookFieldDescription,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[gap, ErrorDetailsCard(message: _error!.message, details: _error!.details)],
        ],
      ),
    );
  }
}
