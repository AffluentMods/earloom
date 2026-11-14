#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Fails when the foss flavor's release runtime classpath contains a Google
# proprietary library (Play Services, Firebase, Cast, ML Kit) or a known
# tracker. F-Droid rejects those (docs/plan/10-phase9-release.md 9.1).
set -euo pipefail
cd "$(dirname "$0")/../../android"
deps=$(./gradlew -q :app:dependencies --configuration fossReleaseRuntimeClasspath)
bad=$(grep -Eo "com\.google\.(android\.gms|firebase|mlkit|android\.play)[^ :]*|com\.crashlytics[^ :]*|io\.sentry[^ :]*" <<<"$deps" | sort -u || true)
if [[ -n "$bad" ]]; then
  echo "FAIL: the foss flavor pulls proprietary libraries:"
  echo "$bad"
  exit 1
fi
echo "OK: no proprietary Google libraries in the foss flavor."
