#!/usr/bin/env python3
"""Variations on the wind rose, including the two Portuguese surfaces it is
actually found on: painted tile and stone pavement.

All of them are laid out on the same 1024 canvas and the same underlying
geometry, so the difference between them is material and treatment rather than
drawing — which is the point of the exercise.
"""

import math
import pathlib
import random

CANVAS = 1024
C = CANVAS / 2

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "icon" / "windrose"

# Compass bearings, clockwise from north, with the length and base half-width
# of each point. Three tiers give the rose its flower shape: the cardinals
# dominate, the ordinals answer them, the half-winds fill the gaps.
TIERS = [
    ([0, 90, 180, 270], 348, 54),
    ([45, 135, 225, 315], 252, 42),
    ([22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5], 168, 24),
]


def polar(radius, bearing):
    """Screen coordinates for a compass bearing — clockwise from north, which
    is the opposite sense to the mathematical convention."""
    a = math.radians(90 - bearing)
    return C + radius * math.cos(a), C - radius * math.sin(a)


def point_triangles(bearing, length, half_width):
    """The two halves of one compass point.

    Splitting each point down its axis and shading the halves differently is
    what makes a compass rose read as a raised, three-dimensional star rather
    than a flat asterisk. Every rose on every portolan does this.
    """
    tip = polar(length, bearing)
    left = polar(half_width, bearing - 90)
    right = polar(half_width, bearing + 90)
    return (
        [tip, left, (C, C)],
        [tip, right, (C, C)],
    )


def rose_polygons():
    """Every triangle of the rose, for the fills and for the stone test."""
    out = []
    for bearings, length, width in TIERS:
        for bearing in bearings:
            out.extend(point_triangles(bearing, length, width))
    return out


def path_of(points):
    head = f"M {points[0][0]:.1f} {points[0][1]:.1f}"
    rest = " ".join(f"L {x:.1f} {y:.1f}" for x, y in points[1:])
    return f"{head} {rest} Z"


def point_in_polygon(x, y, polygon):
    inside = False
    n = len(polygon)
    j = n - 1
    for i in range(n):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        if (yi > y) != (yj > y):
            if x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
                inside = not inside
        j = i
    return inside


def header(width=CANVAS):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {CANVAS} {CANVAS}" '
        f'width="{width}" height="{width}">\n'
    )


# ---------------------------------------------------------------- portolan


def portolan():
    """The rose as a 14th-century chart-maker drew it: alternating shaded
    halves, a lily on north, a cross on east."""
    ink = "#26221C"
    pale = "#EFE7D4"
    red = "#A8341F"
    gold = "#B5893A"
    svg = [header()]
    svg.append(f'  <rect width="{CANVAS}" height="{CANVAS}" fill="#F0E5CC"/>\n')

    # Rhumb lines radiating to the edge, the working part of a portolan.
    for i in range(32):
        bearing = i * 11.25
        x, y = polar(700, bearing)
        svg.append(
            f'  <line x1="{C}" y1="{C}" x2="{x:.1f}" y2="{y:.1f}" '
            f'stroke="{ink}" stroke-width="1.6" opacity="0.28"/>\n'
        )

    for bearings, length, width in TIERS:
        for bearing in bearings:
            left, right = point_triangles(bearing, length, width)
            fill = gold if length < 200 else ink
            svg.append(f'  <path d="{path_of(left)}" fill="{pale}" stroke="{ink}" stroke-width="2"/>\n')
            svg.append(f'  <path d="{path_of(right)}" fill="{fill}"/>\n')

    # East marked with a cross, towards the Holy Land. This is where the word
    # "orientation" comes from: finding the orient.
    ex, ey = polar(408, 90)
    svg.append(
        f'  <g stroke="{red}" stroke-width="17" stroke-linecap="round">\n'
        f'    <line x1="{ex - 46:.1f}" y1="{ey:.1f}" x2="{ex + 46:.1f}" y2="{ey:.1f}"/>\n'
        f'    <line x1="{ex:.1f}" y1="{ey - 46:.1f}" x2="{ex:.1f}" y2="{ey + 46:.1f}"/>\n'
        f'  </g>\n'
    )

    # North marked with a lily — an overgrown letter T, for Tramontana.
    svg.append(fleur_de_lis(C, 150, 1.0, red, ink))
    svg.append(f'  <circle cx="{C}" cy="{C}" r="30" fill="{pale}" stroke="{ink}" stroke-width="6"/>\n')
    svg.append("</svg>\n")
    return "".join(svg)


def fleur_de_lis(cx, cy, scale, fill, stroke):
    """A compact lily. Centuries of scribes elaborated the T of Tramontana
    until it turned into this."""
    s = scale
    d = (
        f"M {cx:.1f} {cy - 62 * s:.1f} "
        f"C {cx + 16 * s:.1f} {cy - 30 * s:.1f} {cx + 14 * s:.1f} {cy - 8 * s:.1f} {cx + 8 * s:.1f} {cy + 6 * s:.1f} "
        f"C {cx + 34 * s:.1f} {cy - 16 * s:.1f} {cx + 60 * s:.1f} {cy + 4 * s:.1f} {cx + 44 * s:.1f} {cy + 30 * s:.1f} "
        f"C {cx + 34 * s:.1f} {cy + 44 * s:.1f} {cx + 16 * s:.1f} {cy + 40 * s:.1f} {cx + 8 * s:.1f} {cy + 30 * s:.1f} "
        f"L {cx + 8 * s:.1f} {cy + 52 * s:.1f} L {cx - 8 * s:.1f} {cy + 52 * s:.1f} "
        f"L {cx - 8 * s:.1f} {cy + 30 * s:.1f} "
        f"C {cx - 16 * s:.1f} {cy + 40 * s:.1f} {cx - 34 * s:.1f} {cy + 44 * s:.1f} {cx - 44 * s:.1f} {cy + 30 * s:.1f} "
        f"C {cx - 60 * s:.1f} {cy + 4 * s:.1f} {cx - 34 * s:.1f} {cy - 16 * s:.1f} {cx - 8 * s:.1f} {cy + 6 * s:.1f} "
        f"C {cx - 14 * s:.1f} {cy - 8 * s:.1f} {cx - 16 * s:.1f} {cy - 30 * s:.1f} Z"
    )
    return f'  <path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{3 * s:.1f}"/>\n'


# ----------------------------------------------------------------- azulejo


def azulejo():
    """Cobalt on tin glaze, in a bordered panel.

    Painted tile has two tells that a flat vector fill misses: the cobalt pools
    darker where the brush lingered, and the drawing sits inside a ruled frame
    rather than floating.
    """
    cobalt = "#1B4C8C"
    deep = "#123A6E"
    glaze = "#F6F3EA"
    svg = [header()]
    svg.append(
        '  <defs>\n'
        '    <radialGradient id="pool" cx="50%" cy="50%" r="62%">\n'
        f'      <stop offset="0" stop-color="{deep}"/>\n'
        f'      <stop offset="1" stop-color="{cobalt}"/>\n'
        '    </radialGradient>\n'
        '  </defs>\n'
    )
    svg.append(f'  <rect width="{CANVAS}" height="{CANVAS}" fill="{glaze}"/>\n')

    # The ruled frame of a tile panel.
    svg.append(
        f'  <rect x="46" y="46" width="{CANVAS - 92}" height="{CANVAS - 92}" '
        f'fill="none" stroke="{cobalt}" stroke-width="13"/>\n'
        f'  <rect x="74" y="74" width="{CANVAS - 148}" height="{CANVAS - 148}" '
        f'fill="none" stroke="{cobalt}" stroke-width="5" opacity="0.65"/>\n'
    )

    # Corner motifs, the standard filler of a Portuguese panel.
    for x, y in [(110, 110), (CANVAS - 110, 110), (110, CANVAS - 110), (CANVAS - 110, CANVAS - 110)]:
        svg.append(
            f'  <circle cx="{x}" cy="{y}" r="17" fill="none" stroke="{cobalt}" stroke-width="6"/>\n'
            f'  <circle cx="{x}" cy="{y}" r="6" fill="{cobalt}"/>\n'
        )

    svg.append(f'  <circle cx="{C}" cy="{C}" r="322" fill="none" stroke="{cobalt}" stroke-width="7" opacity="0.5"/>\n')

    for bearings, length, width in TIERS:
        for bearing in bearings:
            left, right = point_triangles(bearing, length, width)
            svg.append(f'  <path d="{path_of(left)}" fill="{glaze}" stroke="{cobalt}" stroke-width="5"/>\n')
            svg.append(f'  <path d="{path_of(right)}" fill="url(#pool)"/>\n')

    svg.append(f'  <circle cx="{C}" cy="{C}" r="44" fill="{glaze}" stroke="{cobalt}" stroke-width="9"/>\n')
    svg.append(f'  <circle cx="{C}" cy="{C}" r="15" fill="{cobalt}"/>\n')
    svg.append("</svg>\n")
    return "".join(svg)


# ----------------------------------------------------------------- calçada


def calcada(cell=27, seed=7):
    """Calçada portuguesa: black basalt set into white limestone.

    The pavement is not a drawing but a mosaic of hand-cut chips, so this is
    built the same way — a jittered lattice of small irregular stones, each
    coloured by whichever field its centre lands in. The edges come out ragged
    on their own, which is exactly how the real thing looks and what a clean
    vector edge always gets wrong.
    """
    rng = random.Random(seed)
    polygons = rose_polygons()

    limestone = ["#F4F1E9", "#EDE8DC", "#E5DFD1", "#F7F5EF"]
    basalt = ["#2A2C31", "#22242A", "#33363D", "#1B1D22"]

    svg = [header()]
    svg.append(f'  <rect width="{CANVAS}" height="{CANVAS}" fill="#8C8578"/>\n')

    ring_inner, ring_outer = 366, 408
    stones = 0

    for row in range(-1, CANVAS // cell + 2):
        for col in range(-1, CANVAS // cell + 2):
            # Offset alternate rows so the lattice does not read as a grid.
            x = col * cell + (cell / 2 if row % 2 else 0)
            y = row * cell

            corners = []
            for dx, dy in ((0, 0), (1, 0), (1, 1), (0, 1)):
                jx = x + dx * cell + rng.uniform(-0.26, 0.26) * cell
                jy = y + dy * cell + rng.uniform(-0.26, 0.26) * cell
                corners.append((jx, jy))

            cx = sum(p[0] for p in corners) / 4
            cy = sum(p[1] for p in corners) / 4
            if not (-cell <= cx <= CANVAS + cell and -cell <= cy <= CANVAS + cell):
                continue

            distance = math.hypot(cx - C, cy - C)
            dark = ring_inner <= distance <= ring_outer
            if not dark:
                dark = any(point_in_polygon(cx, cy, poly) for poly in polygons)

            palette = basalt if dark else limestone
            fill = palette[rng.randrange(len(palette))]

            # Shrink each stone towards its centre to leave the mortar gap.
            shrunk = [
                (cx + (px - cx) * 0.84, cy + (py - cy) * 0.84) for px, py in corners
            ]
            svg.append(f'  <path d="{path_of(shrunk)}" fill="{fill}"/>\n')
            stones += 1

    svg.append("</svg>\n")
    return "".join(svg), stones


# ----------------------------------------------------------------- minimal


def minimal():
    """The rose reduced to what survives at forty pixels."""
    ink = "#1B4C8C"
    light = "#4E85C4"
    glaze = "#F2EFE6"
    gold = "#C08A2E"
    svg = [header()]
    svg.append(f'  <rect width="{CANVAS}" height="{CANVAS}" fill="{glaze}"/>\n')

    for bearing in (0, 90, 180, 270):
        left, right = point_triangles(bearing, 330, 58)
        svg.append(f'  <path d="{path_of(left)}" fill="{light}"/>\n')
        svg.append(f'  <path d="{path_of(right)}" fill="{ink}"/>\n')
    for bearing in (45, 135, 225, 315):
        left, right = point_triangles(bearing, 196, 40)
        svg.append(f'  <path d="{path_of(left)}" fill="{light}"/>\n')
        svg.append(f'  <path d="{path_of(right)}" fill="{ink}"/>\n')

    svg.append(f'  <circle cx="{C}" cy="{C}" r="46" fill="{glaze}"/>\n')
    svg.append(f'  <circle cx="{C}" cy="{C}" r="22" fill="{gold}"/>\n')
    svg.append("</svg>\n")
    return "".join(svg)


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    (OUT / "portolan.svg").write_text(portolan())
    (OUT / "azulejo.svg").write_text(azulejo())
    (OUT / "minimal.svg").write_text(minimal())

    # Two densities: fine for the poster, coarse for the icon, because at icon
    # size fine stones turn into noise.
    fine, fine_count = calcada(cell=24)
    (OUT / "calcada.svg").write_text(fine)
    coarse, coarse_count = calcada(cell=46, seed=11)
    (OUT / "calcada-coarse.svg").write_text(coarse)

    print(f"wrote 5 variations to {OUT}")
    print(f"calçada: {fine_count} stones fine, {coarse_count} coarse")


if __name__ == "__main__":
    main()
