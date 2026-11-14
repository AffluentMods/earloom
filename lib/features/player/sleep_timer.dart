// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// What the sleep timer is set to. The timer lives in the player engine,
/// not in the UI, so it runs with the screen off and from the car.
sealed class SleepTimer {
  const SleepTimer();
}

final class SleepOff extends SleepTimer {
  const SleepOff();
}

/// Pause after [remaining] of listening. The countdown only runs while
/// audio plays: pausing for a phone call does not eat the timer.
final class SleepAfter extends SleepTimer {
  const SleepAfter({required this.original, required this.remaining});

  /// What the user picked, used again when a shake extends the timer.
  final Duration original;
  final Duration remaining;

  SleepAfter copyWith({Duration? remaining}) => SleepAfter(original: original, remaining: remaining ?? this.remaining);
}

/// Pause when chapter [chapterIndex] ends.
final class SleepAtChapterEnd extends SleepTimer {
  const SleepAtChapterEnd(this.chapterIndex);
  final int chapterIndex;
}

/// Pause when the book ends (do not move on to the next one).
final class SleepAtBookEnd extends SleepTimer {
  const SleepAtBookEnd();
}

/// The choices offered in the sleep sheet, in minutes.
const sleepPresetMinutes = [5, 10, 15, 30, 45, 60, 90];

/// Volume for the fade out: full until [fade] before the end, then a smooth
/// ramp down to silence.
double sleepFadeVolume(Duration remaining, Duration fade) {
  if (fade <= Duration.zero || remaining >= fade) return 1;
  if (remaining <= Duration.zero) return 0;
  final t = remaining.inMilliseconds / fade.inMilliseconds;
  // Ease out: most of the drop happens late, which sounds natural.
  return t * t * (3 - 2 * t);
}

/// How far to rewind when playback resumes after a pause of [paused].
/// Short pauses need no rewind; long ones need a little context.
Duration smartRewindFor(Duration paused) {
  if (paused < const Duration(minutes: 1)) return Duration.zero;
  if (paused < const Duration(minutes: 5)) return const Duration(seconds: 5);
  if (paused < const Duration(hours: 1)) return const Duration(seconds: 15);
  return const Duration(seconds: 30);
}
