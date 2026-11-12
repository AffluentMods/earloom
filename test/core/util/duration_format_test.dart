// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:earloom/core/util/duration_format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

void main() {
  test('formats hours and minutes', () async {
    final l10n = await loadL10n();
    String f(Duration d) => formatDurationShort(l10n, d);

    expect(f(Duration.zero), '0 min');
    expect(f(const Duration(minutes: 1)), '1 min');
    expect(f(const Duration(minutes: 59)), '59 min');
    expect(f(const Duration(hours: 1)), '1 hr');
    expect(f(const Duration(hours: 1, minutes: 1)), '1 hr 1 min');
    expect(f(const Duration(hours: 2, minutes: 30)), '2 hrs 30 min');
    expect(f(const Duration(hours: 25, minutes: 3)), '25 hrs 3 min');
  });

  test('drops seconds and never goes negative', () async {
    final l10n = await loadL10n();
    expect(formatDurationShort(l10n, const Duration(minutes: 59, seconds: 59)), '59 min');
    expect(formatDurationShort(l10n, const Duration(seconds: -90)), '0 min');
  });

  test('time left wraps the duration', () async {
    final l10n = await loadL10n();
    expect(formatTimeLeft(l10n, const Duration(hours: 3, minutes: 12)), '3 hrs 12 min left');
  });
}
