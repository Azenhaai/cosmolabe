#!/usr/bin/env python3
"""Renders the app icon and installs it into both platform trees.

The design is the Alidade: a graduated limb with the sighting rule laid across
it, aimed at a star. Drawn here rather than rasterised from the SVG because no
SVG rasteriser is installed and the geometry is three shapes — a ring, a bar,
a star — so a dependency would buy nothing.

Everything is drawn at four times the target size and downsampled, which is
the cheapest antialiasing there is and the only kind Pillow gives for free.

    python3 tool/build_icons.py
"""

import json
import math
import pathlib
import shutil

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent

# --- design -----------------------------------------------------------------

BASE = 1024
SS = 4  # supersampling factor
N = BASE * SS

BG_TOP = (242, 239, 230)
BG_BOTTOM = (228, 223, 210)
MARK = (28, 78, 143)
GOLD = (192, 138, 46)

RING_RADIUS = 250
RING_WIDTH = 26
ALIDADE_WIDTH = 44
PIVOT_RADIUS = 34
PIVOT_WIDTH = 18
STAR_RADIUS = 92
STAR_PUNCH = 86
AIM_DEG = 30  # the rule points this far above the horizontal

# Android masks the adaptive icon to roughly the central two thirds: the
# foreground is authored on a 108dp canvas of which about 66dp survives the
# mask. Scaling the mark by the bare 72/108 leaves it visibly shrunken next to
# other launcher icons, so it is sized instead by its real extent — the ring
# plus the star tip, which reach 342 units — to land just inside that circle.
ADAPTIVE_SCALE = 0.82


def scaled(value):
    return value * SS


def polar(radius, degrees, centre=None):
    cx, cy = centre or (N / 2, N / 2)
    a = math.radians(degrees)
    return cx + radius * math.cos(a), cy - radius * math.sin(a)


def sparkle_points(cx, cy, r, waist=0.2, steps=22):
    """Four-pointed star with concave sides, sampled from its Bezier arms.

    Pillow has no curve primitive, so the quadratics are evaluated by hand;
    at icon sizes twenty-two samples an arm is well past what any pixel grid
    can resolve.
    """
    k = r * waist
    tips = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    controls = [
        (cx + k, cy - k),
        (cx + k, cy + k),
        (cx - k, cy + k),
        (cx - k, cy - k),
    ]
    points = []
    for i in range(4):
        start = tips[i]
        control = controls[i]
        end = tips[(i + 1) % 4]
        for step in range(steps):
            t = step / steps
            mt = 1 - t
            points.append(
                (
                    mt * mt * start[0] + 2 * mt * t * control[0] + t * t * end[0],
                    mt * mt * start[1] + 2 * mt * t * control[1] + t * t * end[1],
                )
            )
    return points


def gradient_background(size, top, bottom):
    image = Image.new("RGB", (1, size), top)
    pixels = image.load()
    for y in range(size):
        t = y / max(1, size - 1)
        pixels[0, y] = tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        )
    return image.resize((size, size), Image.NEAREST)


def thick_line(draw, start, end, width, colour):
    """A line with round caps, which Pillow will not do on its own."""
    draw.line([start, end], fill=colour, width=int(width))
    for point in (start, end):
        draw.ellipse(
            [
                point[0] - width / 2,
                point[1] - width / 2,
                point[0] + width / 2,
                point[1] + width / 2,
            ],
            fill=colour,
        )


def draw_mark(draw, scale=1.0, punch_colour=None):
    """The ring, the rule, the pivot and the star.

    [punch_colour] fills the disc that lets the star sit over the ring. On the
    opaque icon that is the background colour; on a transparent foreground
    layer it has to be left alone, or the layer would carry a pale blob.
    """
    centre = (N / 2, N / 2)
    ring = scaled(RING_RADIUS) * scale

    draw.ellipse(
        [
            centre[0] - ring,
            centre[1] - ring,
            centre[0] + ring,
            centre[1] + ring,
        ],
        outline=MARK,
        width=int(scaled(RING_WIDTH) * scale),
    )

    start = polar(ring - scaled(6) * scale, AIM_DEG + 180, centre)
    end = polar(ring - scaled(6) * scale, AIM_DEG, centre)
    thick_line(draw, start, end, scaled(ALIDADE_WIDTH) * scale, MARK)

    pivot = scaled(PIVOT_RADIUS) * scale
    draw.ellipse(
        [
            centre[0] - pivot,
            centre[1] - pivot,
            centre[0] + pivot,
            centre[1] + pivot,
        ],
        outline=MARK,
        width=int(scaled(PIVOT_WIDTH) * scale),
    )

    sx, sy = polar(ring, AIM_DEG, centre)
    if punch_colour is not None:
        punch = scaled(STAR_PUNCH) * scale
        draw.ellipse(
            [sx - punch, sy - punch, sx + punch, sy + punch],
            fill=punch_colour,
        )
    draw.polygon(
        sparkle_points(sx, sy, scaled(STAR_RADIUS) * scale),
        fill=GOLD,
    )


def render_icon():
    """The opaque icon, for iOS and for the legacy Android launcher."""
    image = gradient_background(N, BG_TOP, BG_BOTTOM)
    draw = ImageDraw.Draw(image)
    draw_mark(draw, punch_colour=BG_TOP)
    return image.resize((BASE, BASE), Image.LANCZOS)


def render_adaptive_foreground():
    """Transparent layer with the mark shrunk into Android's safe circle."""
    image = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    # No punch disc: on a transparent layer it would show as a pale blob over
    # whatever background the launcher composites underneath.
    draw_mark(draw, scale=ADAPTIVE_SCALE, punch_colour=None)
    return image.resize((BASE, BASE), Image.LANCZOS)


def render_adaptive_background():
    return gradient_background(N, BG_TOP, BG_BOTTOM).resize(
        (BASE, BASE), Image.LANCZOS
    )


# --- installation -----------------------------------------------------------


def install_ios(icon):
    appicon = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = json.loads((appicon / "Contents.json").read_text())

    written = 0
    for entry in contents["images"]:
        filename = entry.get("filename")
        if not filename:
            continue
        base = float(entry["size"].split("x")[0])
        scale = int(entry["scale"].rstrip("x"))
        pixels = round(base * scale)
        # iOS icons must be fully opaque with no alpha channel at all, or the
        # App Store rejects the upload.
        icon.convert("RGB").resize((pixels, pixels), Image.LANCZOS).save(
            appicon / filename, "PNG"
        )
        written += 1
    return written


ANDROID_DENSITIES = {
    "mdpi": 1,
    "hdpi": 1.5,
    "xhdpi": 2,
    "xxhdpi": 3,
    "xxxhdpi": 4,
}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
"""


def render_monochrome():
    """The themed-icon layer Android 13 and later tints itself.

    It has to be a silhouette on transparency: the system throws the colours
    away and keeps only the shape, so anything relying on the gold star to
    carry the design would come out unreadable.
    """
    image = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    centre = (N / 2, N / 2)
    ring = scaled(RING_RADIUS) * ADAPTIVE_SCALE
    ink = (255, 255, 255, 255)

    draw.ellipse(
        [centre[0] - ring, centre[1] - ring, centre[0] + ring, centre[1] + ring],
        outline=ink,
        width=int(scaled(RING_WIDTH) * ADAPTIVE_SCALE),
    )
    thick_line(
        draw,
        polar(ring - scaled(6) * ADAPTIVE_SCALE, AIM_DEG + 180, centre),
        polar(ring - scaled(6) * ADAPTIVE_SCALE, AIM_DEG, centre),
        scaled(ALIDADE_WIDTH) * ADAPTIVE_SCALE,
        ink,
    )
    sx, sy = polar(ring, AIM_DEG, centre)
    punch = scaled(STAR_PUNCH) * ADAPTIVE_SCALE
    # Clear a gap so the star reads against the ring even in one colour.
    draw.ellipse(
        [sx - punch, sy - punch, sx + punch, sy + punch],
        fill=(0, 0, 0, 0),
    )
    draw.polygon(
        sparkle_points(sx, sy, scaled(STAR_RADIUS) * ADAPTIVE_SCALE),
        fill=ink,
    )
    return image.resize((BASE, BASE), Image.LANCZOS)


def install_android(icon, foreground, background, monochrome):
    res = ROOT / "android/app/src/main/res"
    written = 0

    for density, factor in ANDROID_DENSITIES.items():
        folder = res / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)

        legacy = round(48 * factor)
        icon.convert("RGB").resize((legacy, legacy), Image.LANCZOS).save(
            folder / "ic_launcher.png", "PNG"
        )
        written += 1

        # Adaptive layers are authored on a 108dp canvas.
        adaptive = round(108 * factor)
        for image, name in (
            (foreground, "ic_launcher_foreground.png"),
            (background, "ic_launcher_background.png"),
            (monochrome, "ic_launcher_monochrome.png"),
        ):
            source = image if image.mode == "RGBA" else image.convert("RGBA")
            source.resize((adaptive, adaptive), Image.LANCZOS).save(
                folder / name, "PNG"
            )
            written += 1

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(ADAPTIVE_XML)
    (anydpi / "ic_launcher_round.xml").write_text(ADAPTIVE_XML)
    written += 2

    return written


def main():
    icon = render_icon()
    foreground = render_adaptive_foreground()
    background = render_adaptive_background()
    monochrome = render_monochrome()

    master = ROOT / "assets/icon"
    master.mkdir(parents=True, exist_ok=True)
    icon.save(master / "icon-1024.png", "PNG")
    foreground.save(master / "adaptive-foreground.png", "PNG")
    background.save(master / "adaptive-background.png", "PNG")
    monochrome.save(master / "adaptive-monochrome.png", "PNG")

    ios = install_ios(icon)
    android = install_android(icon, foreground, background, monochrome)

    print(f"master renders: 4 in {master.relative_to(ROOT)}")
    print(f"iOS: {ios} icons written")
    print(f"Android: {android} files written")

    # A contact sheet at the sizes that actually decide whether it works.
    sheet = Image.new("RGB", (820, 220), (250, 249, 247))
    x = 20
    for size in (180, 120, 80, 60, 40):
        sheet.paste(icon.resize((size, size), Image.LANCZOS), (x, 180 - size))
        x += size + 18
    circle = Image.new("RGBA", (180, 180), (0, 0, 0, 0))
    masked = Image.alpha_composite(
        background.resize((180, 180), Image.LANCZOS).convert("RGBA"),
        foreground.resize((180, 180), Image.LANCZOS),
    )
    mask = Image.new("L", (180, 180), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 179, 179], fill=255)
    circle.paste(masked, (0, 0), mask)
    sheet.paste(circle, (x + 10, 0), circle)
    sheet.save(master / "preview.png", "PNG")
    print("preview: assets/icon/preview.png (last one is the Android circle mask)")


if __name__ == "__main__":
    main()
