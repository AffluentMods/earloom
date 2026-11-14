#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Builds the Android release: an app bundle for Google Play (play flavor)
# and an APK for F-Droid and IzzyOnDroid (foss flavor). Always obfuscated;
# the symbols needed to read stack traces go to build/debug-symbols/<version>
# (archive them, never commit them). Signing uses android/key.properties
# (git-ignored); without it the build is debug-signed and must not ship.
#
#   tool/release_android.sh
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
symbols="build/debug-symbols/$version"

if [[ ! -f android/key.properties ]]; then
  echo "NOTE: android/key.properties is missing, so this build is signed with the debug key."
  echo "      Fine for testing; do not upload it to a store."
fi

tool/check.sh

flutter build appbundle --release --flavor play \
  --obfuscate --split-debug-info="$symbols/play"
flutter build apk --release --flavor foss \
  --obfuscate --split-debug-info="$symbols/foss"
tool/ci/check_foss_deps.sh

echo
echo "Built $version:"
echo "  build/app/outputs/bundle/playRelease/app-play-release.aab   (Google Play)"
echo "  build/app/outputs/flutter-apk/app-foss-release.apk          (F-Droid, IzzyOnDroid)"
echo "  $symbols                                                     (archive with the release)"
