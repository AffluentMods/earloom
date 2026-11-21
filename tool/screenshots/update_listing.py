# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
"""Copies freshly rendered store screenshots to where the repo keeps them.

Render them first, then run this from the repo root:

    STORE=1 flutter test tool/screenshots/app_screens.dart
    python3 tool/screenshots/update_listing.py

It writes:
- the Google Play listing set in fastlane/metadata/android/en-US/images
  (phone and 10 inch tablet), which F-Droid and IzzyOnDroid read too;
- the four phone pictures the README shows, in docs/screenshots.

JPEG without an alpha channel: neither store takes pictures that have one,
and the files stay small. Needs Pillow (pip install pillow).
"""

import os
import sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
STORE = os.path.join(ROOT, "build", "screenshots", "store")
LISTING = os.path.join(ROOT, "fastlane", "metadata", "android", "en-US", "images")
README = os.path.join(ROOT, "docs", "screenshots")

# Rendered folder -> listing folder.
PLAY = {"play_phone": "phoneScreenshots", "play_tablet_10": "tenInchScreenshots"}
# The README shows the iPhone renders at a third of their size.
README_FROM = "ios_phone_6.9"
README_SHOTS = {"1_home": "home", "2_player": "player", "3_book": "book", "4_library": "library"}


def opaque(path):
    image = Image.open(path)
    if image.mode == "RGB":
        return image
    rgba = image.convert("RGBA")
    flat = Image.new("RGB", rgba.size, (0, 0, 0))
    flat.paste(rgba, mask=rgba.split()[3])
    return flat


def main():
    if not os.path.isdir(STORE):
        sys.exit("No build/screenshots/store: render first (see the top of this file).")
    written = 0
    for rendered, folder in PLAY.items():
        source = os.path.join(STORE, rendered)
        target = os.path.join(LISTING, folder)
        os.makedirs(target, exist_ok=True)
        for name in sorted(os.listdir(source)):
            stem = os.path.splitext(name)[0]
            opaque(os.path.join(source, name)).save(os.path.join(target, stem + ".jpg"), "JPEG", quality=90)
            written += 1
    os.makedirs(README, exist_ok=True)
    for stem, name in README_SHOTS.items():
        image = opaque(os.path.join(STORE, README_FROM, stem + ".png"))
        small = image.resize((image.width // 3, image.height // 3), Image.LANCZOS)
        small.save(os.path.join(README, name + ".jpg"), "JPEG", quality=88)
        written += 1
    print(f"{written} pictures written")


if __name__ == "__main__":
    main()
