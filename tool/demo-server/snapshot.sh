#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Saves the server's clean state (after setup.dart) to ./snapshot. reset.sh
# puts it back every night. Run from this folder: ./snapshot.sh
set -euo pipefail
cd "$(dirname "$0")"
docker compose stop abs
rm -rf snapshot
mkdir -p snapshot
cp -a data/config data/metadata snapshot/
docker compose start abs
echo "Snapshot saved to $(pwd)/snapshot"
