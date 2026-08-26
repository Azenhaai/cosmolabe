#!/usr/bin/env python3
"""Generates the app icon concepts as SVG.

Everything is laid out on a 1024 canvas. The essential marks stay inside a
circle of radius 340, because Android's adaptive icon masks to roughly the
central two thirds and anything outside that is cropped away on some launchers.
"""

import math
import pathlib

CANVAS = 1024
CENTRE = CANVAS / 2
SAFE_RADIUS = 340

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "icon" / "concepts"

PALETTES = {
    "azulejo": {
        "bg": "#F2EFE6",
        "bg2": "#E4DFD2",
        "mark": "#1C4E8F",
        "mark2": "#2E6BB3",
        "accent": "#C08A2E",
        "label": "Azulejo — cobalt on warm white",
    },
    "night": {
        "bg": "#0A1730",
        "bg2": "#050D1D",
        "mark": "#E9D7A9",
        "mark2": "#B9A170",
        "accent": "#C1452F",
        "label": "Manueline — gold on deep blue",
    },
}


def sparkle(cx, cy, r, waist=0.2):
    """Four-pointed star with concave sides — reads as a star far smaller than
    a straight-edged polygon does."""
    k = r * waist
    return (
        f"M {cx:.1f} {cy - r:.1f} "
        f"Q {cx + k:.1f} {cy - k:.1f} {cx + r:.1f} {cy:.1f} "
        f"Q {cx + k:.1f} {cy + k:.1f} {cx:.1f} {cy + r:.1f} "
        f"Q {cx - k:.1f} {cy + k:.1f} {cx - r:.1f} {cy:.1f} "
        f"Q {cx - k:.1f} {cy - k:.1f} {cx:.1f} {cy - r:.1f} Z"
    )


def polar(radius, degrees):
    """Screen coordinates for a polar position, measured anticlockwise from
    east so the maths reads the way it does on paper."""
    a = math.radians(degrees)
    return CENTRE + radius * math.cos(a), CENTRE - radius * math.sin(a)


def header(palette):
    p = PALETTES[palette]
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'width="{CANVAS}" height="{CANVAS}">\n'
        f'  <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">\n'
        f'    <stop offset="0" stop-color="{p["bg"]}"/>\n'
        f'    <stop offset="1" stop-color="{p["bg2"]}"/>\n'
        f'  </linearGradient></defs>\n'
        f'  <rect width="{CANVAS}" height="{CANVAS}" fill="url(#bg)"/>\n'
    )


def concept_alidade(palette):
    """A graduated limb with a sighting rule laid across it, aimed at a star.

    Not a picture of the instrument but of its use, which is also what the word
    cosmolabe means: the thing that takes the measure of the sky.
    """
    p = PALETTES[palette]
    ring = 250
    aim = 30  # degrees above the horizontal

    svg = [header(palette)]

    # The graduated limb.
    svg.append(
        f'  <circle cx="{CENTRE}" cy="{CENTRE}" r="{ring}" fill="none" '
        f'stroke="{p["mark"]}" stroke-width="26"/>\n'
    )

    # Degree marks, inside the limb, skipping the arc the star sits on.
    for i in range(36):
        angle = i * 10
        if abs(((angle - aim + 180) % 360) - 180) < 22:
            continue
        long_mark = i % 3 == 0
        r1, r2 = ring - 22, ring - (60 if long_mark else 40)
        x1, y1 = polar(r1, angle)
        x2, y2 = polar(r2, angle)
        svg.append(
            f'  <line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{p["mark2"]}" stroke-width="{11 if long_mark else 7}" '
            f'stroke-linecap="round"/>\n'
        )

    # The alidade, a diameter bar pivoting on the centre.
    x1, y1 = polar(ring - 6, aim + 180)
    x2, y2 = polar(ring - 6, aim)
    svg.append(
        f'  <line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
        f'stroke="{p["mark"]}" stroke-width="44" stroke-linecap="round"/>\n'
    )

    # Pivot.
    svg.append(
        f'  <circle cx="{CENTRE}" cy="{CENTRE}" r="34" fill="{p["bg"]}" '
        f'stroke="{p["mark"]}" stroke-width="18"/>\n'
    )

    # The star being sighted, sitting on the limb at the end of the rule.
    sx, sy = polar(ring, aim)
    svg.append(f'  <circle cx="{sx:.1f}" cy="{sy:.1f}" r="86" fill="{p["bg"]}"/>\n')
    svg.append(f'  <path d="{sparkle(sx, sy, 92)}" fill="{p["accent"]}"/>\n')

    svg.append("</svg>\n")
    return "".join(svg)


def concept_windrose(palette):
    """The compass rose of the portolan charts, with stars for points."""
    p = PALETTES[palette]
    svg = [header(palette)]

    long_r, short_r = 320, 190
    waist = 46

    # Four cardinal points as slender kites.
    for angle in (90, 0, 270, 180):
        tip = polar(long_r, angle)
        left = polar(waist, angle + 90)
        right = polar(waist, angle - 90)
        svg.append(
            f'  <path d="M {tip[0]:.1f} {tip[1]:.1f} L {left[0]:.1f} {left[1]:.1f} '
            f'L {right[0]:.1f} {right[1]:.1f} Z" fill="{p["mark"]}"/>\n'
        )

    # Four diagonals, shorter and lighter, so the cardinal axis stays dominant.
    for angle in (45, 135, 225, 315):
        tip = polar(short_r, angle)
        left = polar(waist * 0.62, angle + 90)
        right = polar(waist * 0.62, angle - 90)
        svg.append(
            f'  <path d="M {tip[0]:.1f} {tip[1]:.1f} L {left[0]:.1f} {left[1]:.1f} '
            f'L {right[0]:.1f} {right[1]:.1f} Z" fill="{p["mark2"]}"/>\n'
        )

    # Stars punctuating the diagonals, which is what makes it a sky rose rather
    # than a compass rose.
    for angle in (45, 135, 225, 315):
        sx, sy = polar(short_r + 62, angle)
        svg.append(f'  <path d="{sparkle(sx, sy, 40)}" fill="{p["accent"]}"/>\n')

    svg.append(
        f'  <circle cx="{CENTRE}" cy="{CENTRE}" r="52" fill="{p["bg"]}" '
        f'stroke="{p["mark"]}" stroke-width="22"/>\n'
    )
    svg.append(f'  <path d="{sparkle(CENTRE, CENTRE, 30)}" fill="{p["accent"]}"/>\n')

    svg.append("</svg>\n")
    return "".join(svg)


def concept_armillary(palette):
    """The armillary sphere of the Portuguese flag, cut down to three rings so
    that it survives being shrunk."""
    p = PALETTES[palette]
    r = 268
    svg = [header(palette)]

    # Meridian.
    svg.append(
        f'  <circle cx="{CENTRE}" cy="{CENTRE}" r="{r}" fill="none" '
        f'stroke="{p["mark"]}" stroke-width="24"/>\n'
    )
    # Equator, seen almost edge on.
    svg.append(
        f'  <ellipse cx="{CENTRE}" cy="{CENTRE}" rx="{r}" ry="76" fill="none" '
        f'stroke="{p["mark"]}" stroke-width="22"/>\n'
    )
    # Ecliptic, tilted by the real obliquity.
    svg.append(
        f'  <ellipse cx="{CENTRE}" cy="{CENTRE}" rx="{r}" ry="104" fill="none" '
        f'stroke="{p["mark2"]}" stroke-width="18" '
        f'transform="rotate(-23.4 {CENTRE} {CENTRE})"/>\n'
    )
    # Polar axis.
    svg.append(
        f'  <line x1="{CENTRE}" y1="{CENTRE - r - 34}" x2="{CENTRE}" '
        f'y2="{CENTRE + r + 34}" stroke="{p["mark2"]}" stroke-width="14" '
        f'stroke-linecap="round"/>\n'
    )
    svg.append(f'  <circle cx="{CENTRE}" cy="{CENTRE}" r="62" fill="{p["bg"]}"/>\n')
    svg.append(f'  <path d="{sparkle(CENTRE, CENTRE, 58)}" fill="{p["accent"]}"/>\n')

    svg.append("</svg>\n")
    return "".join(svg)


def concept_crux(palette):
    """The Southern Cross over a horizon — the sky Portuguese navigators had to
    learn from scratch once Polaris sank below the equator."""
    p = PALETTES[palette]
    svg = [header(palette)]

    # Horizon, a shallow arc so the stars read as being above something.
    svg.append(
        f'  <path d="M 150 792 Q {CENTRE} 700 874 792" fill="none" '
        f'stroke="{p["mark2"]}" stroke-width="20" stroke-linecap="round" '
        f'opacity="0.75"/>\n'
    )

    # Crux, roughly to scale: Acrux brightest at the foot, Gacrux at the head.
    stars = [
        (548, 268, 62),   # Gacrux
        (470, 632, 88),   # Acrux
        (300, 452, 70),   # Mimosa
        (700, 404, 64),   # Delta Crucis
        (430, 500, 30),   # Epsilon Crucis
    ]
    for cx, cy, r in stars:
        svg.append(
            f'  <path d="{sparkle(cx, cy, r * 2.1, 0.1)}" fill="{p["accent"]}" '
            f'opacity="0.22"/>\n'
        )
        svg.append(f'  <path d="{sparkle(cx, cy, r)}" fill="{p["mark"]}"/>\n')

    svg.append("</svg>\n")
    return "".join(svg)


CONCEPTS = {
    "alidade": (concept_alidade, "Alidade on a graduated limb, sighting a star"),
    "windrose": (concept_windrose, "Wind rose of the portolans, pointed with stars"),
    "armillary": (concept_armillary, "Armillary sphere, cut to three rings"),
    "crux": (concept_crux, "The Southern Cross over a horizon"),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    for name, (build, _) in CONCEPTS.items():
        for palette in PALETTES:
            path = OUT / f"{name}-{palette}.svg"
            path.write_text(build(palette))
            written.append(path)
    print(f"wrote {len(written)} concepts to {OUT}")
    print(f"safe radius used: {SAFE_RADIUS} of {CANVAS // 2}")


if __name__ == "__main__":
    main()
