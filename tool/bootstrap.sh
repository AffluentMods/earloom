#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Run once after cloning, and again after pulling changes to pubspec.yaml,
# the database tables or the translation file. Then `flutter run` works.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
flutter gen-l10n
dart run build_runner build

# Use the repo's git hooks (secret scan, commit message rules).
git config core.hooksPath tool/hooks
echo "Ready. Run the app with: flutter run"
