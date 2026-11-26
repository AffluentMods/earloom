// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/library/models.dart';
import 'package:earloom/core/library/source_id.dart';
import 'package:earloom/features/downloads/data/download_manager.dart';
import 'package:earloom/features/downloads/ui/bulk_download.dart';
import 'package:flutter_test/flutter_test.dart';

const account = AbsSource('acct-affluent');

BookSummary book(String id, {SourceId source = account}) => BookSummary(ref: ItemRef(source, id), title: id);

DownloadState state(String id, DownloadPhase phase) => DownloadState(ref: ItemRef(account, id), phase: phase);

void main() {
  test('Download all adds what is not on the phone or on its way, once each', () {
    final books = [
      book('done'),
      book('running'),
      book('failed'),
      book('new'),
      book('new'),
      book('local', source: const LocalSource()),
      book('other', source: const AbsSource('acct-other')),
    ];
    final states = {
      for (final s in [
        state('done', DownloadPhase.complete),
        state('running', DownloadPhase.downloading),
        state('failed', DownloadPhase.failed),
      ])
        s.key: s,
    };
    expect([for (final b in booksToDownload(books, states, account)) b.ref.itemId], ['failed', 'new']);
    expect(booksToDownload(books, states, null), isEmpty, reason: 'no server account');
  });
}
