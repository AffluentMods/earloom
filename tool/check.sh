#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# The gate every phase and every pull request must pass. Runs locally (Git
# Bash on Windows, any shell on macOS and Linux) and in CI.
#   tool/check.sh            everything
#   tool/check.sh --fast     skip code generation (when nothing generated changed)
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { printf '\n== %s\n' "$1"; }
bad() { printf 'FAIL: %s\n' "$1"; fail=1; }

# Every file we wrote ourselves: tracked or new, never ignored or generated.
# Read into an array so paths with spaces survive.
mapfile -t ours < <(git ls-files -co --exclude-standard)

if [[ "${1:-}" != "--fast" ]]; then
  note "Code generation"
  flutter pub get >/dev/null
  flutter gen-l10n >/dev/null
  dart run build_runner build >/dev/null
fi

note "Format"
dart_files=()
for f in "${ours[@]}"; do
  [[ "$f" == *.dart && -f "$f" ]] && dart_files+=("$f")
done
dart format --output=none --set-exit-if-changed "${dart_files[@]}" >/dev/null \
  || bad "unformatted Dart files. Run: dart format lib test tool"

note "Analyze"
flutter analyze || fail=1

note "Tests"
flutter test || fail=1

note "Rule 2: no em or en dashes"
# Our own text only. License texts and lockfiles are other people's words.
dash_hits=0
for f in "${ours[@]}"; do
  case "$f" in
    LICENSE | CODE_OF_CONDUCT.md | assets/fonts/* | pubspec.lock | *.png | *.jpg | *.ttf | *.jar | *.pbxproj | *.storyboard) continue ;;
  esac
  [[ -f "$f" ]] || continue
  if grep -nIH -e $'\xe2\x80\x94' -e $'\xe2\x80\x93' "$f"; then dash_hits=1; fi
done
[[ $dash_hits -eq 0 ]] || bad "em or en dash found (use commas, colons, periods or parentheses)"

note "Rule 3: no raw colors in feature code"
if grep -rnE 'Color\(0x[0-9A-Fa-f]{6,8}\)|Colors\.[a-z]+[A-Z]?[a-zA-Z]*\b' lib/features lib/platform \
  | grep -vE 'Colors\.transparent'; then
  bad "hardcoded color in feature code (use the theme tokens or the ColorScheme)"
fi
# In the rest of lib/, a raw literal is allowed in exactly one place.
if grep -rnE 'Color\(0x[0-9A-Fa-f]{6,8}\)' lib --include='*.dart' \
  | grep -v '^lib/app/theme/tokens.dart:' | grep -v '\.g\.dart:' | grep -v '^lib/l10n/gen/'; then
  bad "raw color literal outside lib/app/theme/tokens.dart"
fi

note "Rule 1: no hardcoded UI strings in feature code"
if grep -rnE "Text\(\s*'[^']|Text\(\s*\"[^\"]|(label|tooltip|title|hintText|labelText|semanticLabel):\s*'[^']" lib/features lib/platform; then
  bad "possible hardcoded UI string (add an l10n key to lib/l10n/app_en.arb)"
fi

note "License headers"
for f in "${ours[@]}"; do
  case "$f" in
    *.dart | *.swift | *.kt) ;;
    *) continue ;;
  esac
  [[ -f "$f" ]] || continue
  if ! head -n 3 "$f" | grep -q 'SPDX-License-Identifier: GPL-3.0-or-later'; then
    bad "missing SPDX header: $f"
  elif ! head -n 4 "$f" | grep -q 'Copyright (c) [0-9]\{4\} Affluent Labs LLC'; then
    bad "missing copyright line: $f"
  fi
done

note "No secrets in fixtures or docs"
if grep -rnI 'eyJ[A-Za-z0-9_-]\{10,\}' test docs tool lib 2>/dev/null; then
  bad "something that looks like a token (eyJ...) is in the repo"
fi

note "No tracking, analytics or proprietary Google packages"
# The user's data goes only to their own server, and the F-Droid build must
# stay free of proprietary SDKs. Packages are matched by name in the lockfile.
if grep -nE '^  (firebase[a-z_]*|google_mobile_ads|google_sign_in[a-z_]*|sentry[a-z_]*|[a-z_]*crashlytics[a-z_]*|[a-z_]*analytics[a-z_]*|amplitude[a-z_]*|mixpanel[a-z_]*|datadog[a-z_]*|appsflyer[a-z_]*|onesignal[a-z_]*|live_activities):' pubspec.lock; then
  bad "a tracking or proprietary package is in pubspec.lock (see CONTRIBUTING.md rule 8)"
fi

note "No copyrighted or downloaded audio"
for f in "${ours[@]}"; do
  case "$f" in
    *.mp3 | *.m4b | *.m4a | *.opus | *.ogg | *.flac | *.aac | *.wav) bad "audio file in the repo: $f" ;;
  esac
done

echo
if [[ $fail -ne 0 ]]; then
  echo "check.sh: FAILED"
  exit 1
fi
echo "OK"
