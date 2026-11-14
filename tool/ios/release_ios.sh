#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Builds the iOS release archive and IPA on the Mac. Run it yourself: signing
# needs your unlocked keychain and the App Store distribution profile, so
# nothing here touches certificates or keys. Always obfuscated; symbols go to
# build/debug-symbols/<version>/ios (archive them, never commit them).
#
#   tool/ios/release_ios.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

[[ "$(uname)" == "Darwin" ]] || { echo "Run this on the Mac."; exit 1; }
version=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
symbols="build/debug-symbols/$version/ios"

tool/check.sh
flutter build ipa --release --obfuscate --split-debug-info="$symbols"

echo
echo "Built $version:"
echo "  build/ios/ipa/*.ipa         (upload with Transporter or xcrun altool)"
echo "  build/ios/archive/Runner.xcarchive"
echo "  $symbols                    (archive with the release)"
