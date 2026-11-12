// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import '../../l10n/gen/app_localizations.dart';

/// Formats a duration as localized hours and minutes: "0 min", "59 min",
/// "1 hr", "1 hr 1 min", "25 hrs 3 min". Seconds are dropped, negative
/// durations count as zero. Units and their order come from the l10n keys,
/// never from string concatenation here.
String formatDurationShort(AppLocalizations l10n, Duration duration) {
  final totalMinutes = duration.isNegative ? 0 : duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return l10n.durationMinutes(minutes);
  if (minutes == 0) return l10n.durationHours(hours);
  return l10n.durationHoursMinutes(l10n.durationHours(hours), l10n.durationMinutes(minutes));
}

/// "3 hr 12 min left".
String formatTimeLeft(AppLocalizations l10n, Duration remaining) {
  return l10n.timeLeft(formatDurationShort(l10n, remaining));
}
