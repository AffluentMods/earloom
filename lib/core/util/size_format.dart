// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';

/// Formats a size in bytes for people: "820 KB", "4.2 MB", "312 MB",
/// "1.4 GB". One decimal below 10 of a unit, none above. Units are decimal
/// (1 MB = 1,000,000 bytes), as phones show storage.
String formatBytes(AppLocalizations l10n, int bytes) {
  final value = bytes < 0 ? 0 : bytes;
  String number(double v) {
    final format = NumberFormat.decimalPattern(l10n.localeName)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = v < 10 ? 1 : 0;
    return format.format(v);
  }

  if (value >= 1000 * 1000 * 1000) return l10n.sizeGigabytes(number(value / 1e9));
  if (value >= 1000 * 1000) return l10n.sizeMegabytes(number(value / 1e6));
  final kb = value / 1e3;
  return l10n.sizeKilobytes(number(kb < 1 && value > 0 ? 1 : kb.roundToDouble()));
}
