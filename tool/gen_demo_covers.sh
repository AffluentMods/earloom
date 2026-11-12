#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
#
# Regenerates the made-up demo covers in assets/demo/covers/.
# They are original, generated art (a gradient plus the bundled fonts), so
# they are safe for screenshots, tests and the debug screens.
# Needs ffmpeg with the drawtext filter. Run from the repo root.
set -euo pipefail
out=assets/demo/covers
serif=assets/fonts/Newsreader-Variable.ttf
sans=assets/fonts/Inter-Variable.ttf
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# name | width | height | color from | color to | text color | title lines (use / to break) | author
covers=(
  "clockmakers_tide|600|600|0x0B3954|0x087E8B|0xF4F1DE|The/Clockmaker's/Tide|MARA ELLISON"
  "salt_and_starlight|600|600|0xFF5A5F|0xC81D25|0xFFF5E1|Salt and/Starlight|MARA ELLISON"
  "ember_road|600|600|0xF4A259|0xBC4B51|0x2B1B17|Ember/Road|THEO VANCE"
  "ash_harbor|600|600|0x5B8E7D|0x2F4858|0xF1FAEE|Ash/Harbor|THEO VANCE"
  "quiet_places|600|600|0x8A8A8A|0x6E6E73|0xF2F2F2|A Field Guide/to Quiet/Places|INES OKAFOR"
  "lanterns_under_the_ice|600|900|0x1D3557|0xA8DADC|0xFFFFFF|Lanterns/Under/the Ice|RAFAEL DORN"
  "long_way_to_morning|600|600|0x3A0CA3|0xF72585|0xFFFFFF|The Long/Way to/Morning|RAFAEL DORN"
  "kindling_sky|600|600|0xE9C46A|0xE76F51|0x2B1B17|Kindling/Sky|THEO VANCE"
)

for row in "${covers[@]}"; do
  IFS='|' read -r name w h from to fg title author <<<"$row"
  filter="format=rgb24"
  IFS='/' read -ra lines <<<"$title"
  y=$((h / 6))
  n=0
  for line in "${lines[@]}"; do
    # Text goes through files, so quotes in a title need no escaping.
    printf '%s' "$line" >"$tmp/line$n.txt"
    filter+=",drawtext=fontfile=$serif:textfile=$tmp/line$n.txt:fontcolor=$fg:fontsize=76:x=48:y=$y"
    y=$((y + 84))
    n=$((n + 1))
  done
  printf '%s' "$author" >"$tmp/author.txt"
  filter+=",drawbox=x=48:y=$((h - 112)):w=72:h=3:color=$fg@0.9:t=fill"
  filter+=",drawtext=fontfile=$sans:textfile=$tmp/author.txt:fontcolor=$fg@0.92:fontsize=24:x=48:y=$((h - 88))"
  ffmpeg -hide_banner -loglevel error -y -f lavfi \
    -i "gradients=s=${w}x${h}:c0=$from:c1=$to:nb_colors=2:x0=0:y0=0:x1=$w:y1=$h:speed=0.00001" \
    -vf "$filter" -frames:v 1 -update 1 -q:v 4 "$out/$name.jpg"
  echo "wrote $out/$name.jpg"
done
