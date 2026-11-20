# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 Affluent Labs LLC
"""Draws the Earloom app icon and writes every size the platforms need.

The mark: a sound wave of seven rounded bars with two threads woven through
it, for "ear" and "loom". At the second and the sixth bar the threads swap
places: the lower one rises over the bar, the upper one passes behind it.
The ground is split along the diagonal, teal above and ink below. Shapes are
defined once, in a 108 unit square (Android's adaptive icon grid), and drawn
both as PNG (Pillow) and as Android vector drawables.

Run from the repo root: python3 tool/icon/gen_icon.py
Needs Pillow (pip install pillow). Only for regenerating the icon.
"""

import json
import math
import os
from PIL import Image, ImageDraw, ImageOps

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# Colors.
BG_TOP = (14, 62, 70)  # deep teal
BG_BOTTOM = (13, 20, 27)  # ink
BAR = (243, 235, 221)  # warm paper
THREAD = (242, 119, 91)  # coral
# The icon's teal half: a little lighter in its corner than at the diagonal.
TEAL_LIGHT = (14, 70, 81)
TEAL_DEEP = (11, 58, 67)

# Geometry in the 108 grid. Content stays inside the 66 unit safe circle,
# with room to spare: launchers cut the icon to their own shapes.
C = 54.0  # the middle, both ways
BAR_W = 6.0
PITCH = 8.4  # from one bar's center to the next
HEIGHTS = [17.8, 27.2, 38.0, 51.2, 38.0, 27.2, 17.8]
THREAD_H = 2.9
THREAD_OFF = 3.1  # each thread's center line, above and below the middle
CROSS = (1, 5)  # the bars where the threads swap places
STEPS = 40  # straight pieces per curve

# How much the mark grows where no safe circle cuts it.
SCALE_FULL = 1.42  # iOS and the store icon: the mark is 74% of the width
SCALE_LEGACY = 1.28  # Android before adaptive icons


def bar_x(i):
    return C + (i - len(HEIGHTS) // 2) * PITCH


def strand(i, x_from, x_to):
    """The rising thread at crossing bar [i], as a polygon between two x
    positions. It leaves the bar before at the lower level and reaches the
    bar after at the upper one, in an S curve. Outside that stretch it runs
    level."""
    xa = bar_x(i - 1) + BAR_W / 2
    xb = bar_x(i + 1) - BAR_W / 2
    y_from, y_to = C + THREAD_OFF, C - THREAD_OFF
    top, bottom = [], []
    for k in range(STEPS + 1):
        x = x_from + (x_to - x_from) * k / STEPS
        u = min(1.0, max(0.0, (x - xa) / (xb - xa)))
        y = y_from + (y_to - y_from) * (3 * u * u - 2 * u * u * u)
        slope = (y_to - y_from) * 6 * u * (1 - u) / (xb - xa)
        # Measured straight down, a slanted thread is taller than a level one.
        half = THREAD_H / 2 * math.sqrt(1 + slope * slope)
        top.append((x, y - half))
        bottom.append((x, y + half))
    return top + bottom[::-1]


def shapes():
    """The mark in paint order: ("rect", x0, y0, x1, y1, radius, color) and
    ("poly", points, color)."""
    out = []
    last = len(HEIGHTS) - 1

    def level(off, a, b):
        # A level piece of thread from bar [a] to bar [b]. Its ends hide
        # under those bars.
        y0, y1 = C + off - THREAD_H / 2, C + off + THREAD_H / 2
        out.append(("rect", bar_x(a), y0, bar_x(b), y1, 0.0, THREAD))

    # Behind the bars: both threads, from the first bar to the last. Next to
    # a crossing bar the rising thread takes the place of a level one: of the
    # lower one before the bar, of the upper one after it.
    start_upper, start_lower = 0, 0
    for i in CROSS:
        level(-THREAD_OFF, start_upper, i)
        if i - 1 > start_lower:
            level(THREAD_OFF, start_lower, i - 1)
        out.append(("poly", strand(i, bar_x(i - 1), bar_x(i + 1)), THREAD))
        start_upper, start_lower = i + 1, i
    if last > start_upper:
        level(-THREAD_OFF, start_upper, last)
    level(THREAD_OFF, start_lower, last)
    for i, h in enumerate(HEIGHTS):
        x = bar_x(i)
        out.append(("rect", x - BAR_W / 2, C - h / 2, x + BAR_W / 2, C + h / 2, BAR_W / 2, BAR))
    # In front: the rising thread where it passes over its bar.
    reach = (PITCH - BAR_W) / 2
    for i in CROSS:
        x = bar_x(i)
        out.append(("poly", strand(i, x - BAR_W / 2 - reach, x + BAR_W / 2 + reach), THREAD))
    return out


def ground(size):
    """The background: teal above the diagonal, ink below it."""
    # A gray ramp that runs from the top left corner to the diagonal, turned
    # into the two teals. Past the diagonal the ink covers it.
    ramp = Image.linear_gradient("L").transform(
        (size, size), Image.AFFINE, (0, 0, 128, 255 / size, 255 / size, 0), resample=Image.BILINEAR
    )
    img = ImageOps.colorize(ramp, TEAL_LIGHT, TEAL_DEEP)
    ImageDraw.Draw(img).polygon([(size, 0), (size, size), (0, size)], fill=BG_BOTTOM)
    return img


def render(size, *, background=True, scale=1.0, color=None, rounded=0.0):
    """The icon at [size] px. [scale] grows the mark (iOS has no safe zone
    cut, so the mark can be larger there). [rounded] is a corner radius as
    a fraction of size, for legacy Android icons."""
    ss = 4
    big = size * ss
    base = ground(big).convert("RGBA") if background else Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    unit = big / 108.0

    def t(v):
        return (C + (v - C) * scale) * unit

    for shape in shapes():
        fill = (color or shape[-1]) + (255,)
        if shape[0] == "rect":
            _, x0, y0, x1, y1, r, _ = shape
            draw.rounded_rectangle((t(x0), t(y0), t(x1), t(y1)), radius=r * scale * unit, fill=fill)
        else:
            draw.polygon([(t(x), t(y)) for x, y in shape[1]], fill=fill)
    img = base.resize((size, size), Image.LANCZOS)
    if rounded:
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, big - 1, big - 1), radius=rounded * big, fill=255)
        img.putalpha(mask.resize((size, size), Image.LANCZOS))
    return img


def write_ios():
    folder = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    with open(os.path.join(folder, "Contents.json")) as f:
        images = json.load(f)["images"]
    master = render(1024, scale=SCALE_FULL)
    for item in images:
        pts = float(item["size"].split("x")[0])
        px = round(pts * float(item["scale"].rstrip("x")))
        master.resize((px, px), Image.LANCZOS).convert("RGB").save(os.path.join(folder, item["filename"]))


def write_android():
    res = os.path.join(ROOT, "android/app/src/main/res")
    for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        render(px, scale=SCALE_LEGACY, rounded=0.22).save(os.path.join(res, f"mipmap-{name}", "ic_launcher.png"))

    def vector(color_for):
        paths = []
        for shape in shapes():
            col = color_for(shape[-1])
            paths.append(
                f'    <path android:fillColor="#FF{col[0]:02X}{col[1]:02X}{col[2]:02X}" android:pathData="{path_of(shape)}"/>'
            )
        return (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Generated by tool/icon/gen_icon.py. Edit that, not this. -->\n"
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n' + "\n".join(paths) + "\n</vector>\n"
        )

    with open(os.path.join(res, "drawable", "ic_launcher_foreground.xml"), "w") as f:
        f.write(vector(lambda c: c))
    with open(os.path.join(res, "drawable", "ic_launcher_monochrome.xml"), "w") as f:
        f.write(vector(lambda c: (255, 255, 255)))
    light = "#FF%02X%02X%02X" % TEAL_LIGHT
    deep = "#FF%02X%02X%02X" % TEAL_DEEP
    bottom = "#FF%02X%02X%02X" % BG_BOTTOM
    with open(os.path.join(res, "drawable", "ic_launcher_background.xml"), "w") as f:
        # Ink everywhere first, then the teal half on top: two halves side
        # by side can leave a hairline between them.
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<!-- Generated by tool/icon/gen_icon.py. Edit that, not this. -->\n"
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    xmlns:aapt="http://schemas.android.com/aapt"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n'
            f'    <path android:fillColor="{bottom}" android:pathData="M0,0H108V108H0Z"/>\n'
            '    <path android:pathData="M0,0H108L0,108Z">\n'
            "        <aapt:attr name=\"android:fillColor\">\n"
            '            <gradient android:type="linear" android:startX="0" android:startY="0"\n'
            '                android:endX="54" android:endY="54"\n'
            f'                android:startColor="{light}" android:endColor="{deep}"/>\n'
            "        </aapt:attr>\n"
            "    </path>\n"
            "</vector>\n"
        )
    anydpi = os.path.join(res, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, "ic_launcher.xml"), "w") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@drawable/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>\n'
            "</adaptive-icon>\n"
        )


def num(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def path_of(shape):
    """Android path data for one shape."""
    if shape[0] == "poly":
        return "M" + "L".join(f"{num(x)},{num(y)}" for x, y in shape[1]) + "Z"
    _, x0, y0, x1, y1, r, _ = shape
    r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
    if r <= 0:
        return f"M{num(x0)},{num(y0)}H{num(x1)}V{num(y1)}H{num(x0)}Z"
    f = num
    return (
        f"M{f(x0 + r)},{f(y0)}H{f(x1 - r)}A{f(r)},{f(r)} 0,0 1 {f(x1)},{f(y0 + r)}"
        f"V{f(y1 - r)}A{f(r)},{f(r)} 0,0 1 {f(x1 - r)},{f(y1)}"
        f"H{f(x0 + r)}A{f(r)},{f(r)} 0,0 1 {f(x0)},{f(y1 - r)}"
        f"V{f(y0 + r)}A{f(r)},{f(r)} 0,0 1 {f(x0 + r)},{f(y0)}Z"
    )


def write_store():
    out = os.path.join(ROOT, "fastlane/metadata/android/en-US/images")
    os.makedirs(out, exist_ok=True)
    render(512, scale=SCALE_FULL).convert("RGB").save(os.path.join(out, "icon.png"))
    feature_graphic().save(os.path.join(out, "featureGraphic.png"))


def feature_graphic():
    """Google Play's 1024 x 500 banner: the mark, the name, the promise,
    and three of the made-up demo covers."""
    from PIL import ImageFont

    w, h, ss = 1024, 500, 2
    img = Image.new("RGB", (w * ss, h * ss))
    px = img.load()
    for y in range(h * ss):
        for x in range(w * ss):
            t = min(1.0, max(0.0, (x * 0.25 + y) / (h * ss * 1.6)))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM))
    img = img.convert("RGBA")
    mark = render(150 * ss, background=False, scale=SCALE_FULL)
    img.alpha_composite(mark, (56 * ss, 70 * ss))
    fonts = os.path.join(ROOT, "assets/fonts")
    serif = ImageFont.truetype(os.path.join(fonts, "Newsreader-Variable.ttf"), 92 * ss)
    try:
        serif.set_variation_by_axes([600, 72])
    except Exception:
        pass
    sans = ImageFont.truetype(os.path.join(fonts, "Inter-Variable.ttf"), 30 * ss)
    try:
        sans.set_variation_by_axes([14, 500])
    except Exception:
        pass
    draw = ImageDraw.Draw(img)
    draw.text((64 * ss, 238 * ss), "Earloom", font=serif, fill=BAR + (255,))
    draw.text((68 * ss, 362 * ss), "Your audiobooks, ready when you are.", font=sans, fill=(214, 222, 224, 255))
    covers = ["ember_road.jpg", "clockmakers_tide.jpg", "salt_and_starlight.jpg"]
    spots = [(620, 92, -8), (742, 60, 0), (864, 92, 8)]
    for name, (x, y, angle) in zip(covers, spots):
        cover = Image.open(os.path.join(ROOT, "assets/demo/covers", name)).convert("RGBA")
        size = 230 * ss
        cover = cover.resize((size, size), Image.LANCZOS)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=18 * ss, fill=255)
        cover.putalpha(mask)
        cover = cover.rotate(-angle, resample=Image.BICUBIC, expand=True)
        img.alpha_composite(cover, ((x - 115) * ss + (size - cover.size[0]) // 2 + 0, y * ss))
    return img.resize((w, h), Image.LANCZOS).convert("RGB")


if __name__ == "__main__":
    write_ios()
    write_android()
    write_store()
    print("icon written")
