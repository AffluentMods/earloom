// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// A position and when it was recorded.
final class PositionStamp {
  const PositionStamp(this.position, this.at);
  final Duration position;
  final DateTime at;
}

/// Where to start a book, and whether the user should hear why.
final class StartDecision {
  const StartDecision(this.position, {this.fromOtherDevice = false, this.undoTo});

  final Duration position;

  /// The server had a newer position from another device: say so, offer
  /// [undoTo] (where this phone had left off).
  final bool fromOtherDevice;
  final Duration? undoTo;
}

/// Positions closer than this count as the same place.
const sameSpotTolerance = Duration(seconds: 30);

/// Decides where playback starts (docs/plan/04-phase3-player.md, 3.7 case 1).
///
/// The newer of the two wins. When the server wins by more than
/// [sameSpotTolerance], the user gets a notice with an undo.
StartDecision resolveStart({PositionStamp? local, PositionStamp? server}) {
  if (server == null && local == null) return const StartDecision(Duration.zero);
  if (server == null) return StartDecision(local!.position);
  if (local == null) return StartDecision(server.position);
  if (!server.at.isAfter(local.at)) return StartDecision(local.position);
  final apart = (server.position - local.position).abs();
  if (apart <= sameSpotTolerance) return StartDecision(server.position);
  return StartDecision(server.position, fromOtherDevice: true, undoTo: local.position);
}

/// What to do with a progress update that arrives from another device while
/// a book is loaded here (3.7 cases 2 to 4).
sealed class RemoteProgressAction {
  const RemoteProgressAction();
}

/// Nothing to do: it is our own echo, older, or the same spot.
final class IgnoreRemote extends RemoteProgressAction {
  const IgnoreRemote();
}

/// Not playing here: move to the remote position quietly.
final class ApplyRemote extends RemoteProgressAction {
  const ApplyRemote(this.position);
  final Duration position;
}

/// Playing here and the remote spot is far away: ask once, never jump.
final class OfferJump extends RemoteProgressAction {
  const OfferJump(this.position);
  final Duration position;
}

/// Remote updates further away than this while playing get a prompt.
const jumpPromptDistance = Duration(minutes: 2);

RemoteProgressAction resolveRemote({
  required Duration here,
  required bool playing,
  required PositionStamp remote,
  required DateTime? lastSyncedAt,
}) {
  if (lastSyncedAt != null && !remote.at.isAfter(lastSyncedAt)) return const IgnoreRemote();
  final apart = (remote.position - here).abs();
  if (!playing) return apart <= const Duration(seconds: 2) ? const IgnoreRemote() : ApplyRemote(remote.position);
  return apart > jumpPromptDistance ? OfferJump(remote.position) : const IgnoreRemote();
}
