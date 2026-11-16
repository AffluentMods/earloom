#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Downloads the public-domain LibriVox books listed in books.txt into
# ./audiobooks/<Title>/ for the demo server. Needs curl, unzip and python3.
# Run from this folder: ./fetch_books.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p audiobooks

while IFS= read -r title || [[ -n "$title" ]]; do
  [[ -z "$title" || "$title" == \#* ]] && continue
  if [[ -d "audiobooks/$title" ]]; then
    echo "Already here: $title"
    continue
  fi
  echo "Looking up: $title"
  query=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote("^" + sys.argv[1]))' "$title")
  json=$(curl -fsS "https://librivox.org/api/feed/audiobooks/?title=${query}&format=json&fields=%7Bid,title,language,url_zip_file%7D") || {
    echo "  Could not reach the LibriVox catalog. Check the network and try again." >&2
    exit 1
  }
  zip=$(printf '%s' "$json" | python3 -c '
import json, sys
books = json.load(sys.stdin).get("books", [])
english = [b for b in books if b.get("language") == "English" and b.get("url_zip_file")]
print(english[0]["url_zip_file"] if english else "")
')
  if [[ -z "$zip" ]]; then
    echo "  Not found in English on LibriVox, skipped. Check the spelling in books.txt." >&2
    continue
  fi
  echo "  Downloading $zip"
  tmp=$(mktemp -d)
  curl -fL --retry 3 -o "$tmp/book.zip" "$zip"
  mkdir -p "audiobooks/$title"
  unzip -q "$tmp/book.zip" -d "audiobooks/$title"
  rm -rf "$tmp"
done < books.txt

echo "Done. Books are in $(pwd)/audiobooks"
