#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Puts the demo server back to the snapshot: progress, bookmarks, playlists
# and sessions from reviewers disappear. Meant for a nightly cron job:
#   15 4 * * * /path/to/earloom/tool/demo-server/reset.sh >> /tmp/earloom-demo-reset.log 2>&1
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -d snapshot/config ]]; then
  echo "No snapshot yet. Run ./snapshot.sh once after setup." >&2
  exit 1
fi
docker compose stop abs
rm -rf data/config data/metadata
cp -a snapshot/config snapshot/metadata data/
docker compose start abs
echo "$(date -u +%FT%TZ) demo server reset"
