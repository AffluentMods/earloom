// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

/// An Audiobookshelf server version such as 2.37.2.
final class ServerVersion implements Comparable<ServerVersion> {
  const ServerVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Parses "2.37.2", "v2.37.2" or "2.37.2-beta". Null when unreadable.
  static ServerVersion? tryParse(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(value);
    if (match == null) return null;
    return ServerVersion(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3] ?? '0'));
  }

  @override
  int compareTo(ServerVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(ServerVersion other) => compareTo(other) < 0;
  bool operator >=(ServerVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) => other is ServerVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Oldest server Earloom works with: the JWT sign-in arrived in 2.26.0.
const minServerVersion = ServerVersion(2, 26, 0);

/// Admins of servers below this see a security notice: 2.36.0 fixes
/// CVE-2026-73085 and 2.37.0 completes the fix for GHSA-m5hp-x2xc-7jqq
/// (docs/abs-api.md section 16).
const securityAdvisoryBelow = ServerVersion(2, 37, 0);
