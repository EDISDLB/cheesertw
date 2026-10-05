"""HULLDOWN icon sets: factions, classes, minimap glyphs, tiers, ranks, currencies.

Grid rules (see docs/design/brand-art.md, 'Iconography grammar'):
  * 64 x 64 viewBox, 4 px safe margin: nothing (including the keyline) leaves 4..60.
  * 2 px ink keyline around every silhouette; bevel 2 px; light from the top-left.
  * Two tones + one highlight per material (tokens.MATERIALS).
  * Symbols are flat-front; physical objects use the fixed 3/4 camera in proj.py.
"""

from __future__ import annotations

import math

from shapely import affinity

from . import geom as G
from . import glyphs, proj
from .brand import turret
from .svgdoc import Doc, mix
from .tokens import INK, MATERIALS, UI

KEY = 2.0  # keyline width at 64 px
BEV = 2.0  # bevel width at 64 px
SAFE = (4.0, 60.0)


def new64(title: str) -> Doc:
    return Doc(64, 64, title)


def check_safe(g, name: str, pad: float = KEY):
    x0, y0, x1, y1 = g.bounds
    lo, hi = SAFE
    if x0 - pad < lo - 0.05 or y0 - pad < lo - 0.05 or x1 + pad > hi + 0.05 or y1 + pad > hi + 0.05:
        raise ValueError(f"{name}: silhouette {tuple(round(v, 1) for v in (x0, y0, x1, y1))} + keyline leaves safe area")


def fitparts(sil, *parts, lo: float = 6.0, hi: float = 58.0):
    """If the silhouette leaves the live area (safe area minus keyline), uniformly scale it (and all
    parts with it) about its centre and nudge it back inside. Returns (sil, *parts)."""
    x0, y0, x1, y1 = sil.bounds
    if x0 >= lo - 1e-6 and y0 >= lo - 1e-6 and x1 <= hi + 1e-6 and y1 <= hi + 1e-6:
        return (sil, *parts)
    s = min(1.0, (hi - lo) / (x1 - x0), (hi - lo) / (y1 - y0))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    nx = min(max(cx, lo + (x1 - x0) * s / 2), hi - (x1 - x0) * s / 2)
    ny = min(max(cy, lo + (y1 - y0) * s / 2), hi - (y1 - y0) * s / 2)

    def tf(g):
        return G.T(G.S(g, s, s, origin=(cx, cy)), nx - cx, ny - cy)

    return (tf(sil), *[tf(p) for p in parts])


# ===========================================================================
# FACTIONS
# ===========================================================================
def faction_iron_union(d: Doc):
    ring = G.gear(32, 32, 22.2, 25.9, 12, tooth_frac=0.52, tip_frac=0.34, rot_deg=15)
    disc = G.circle(32, 32, 16.8, n=96)
    anvil = G.poly(
        [(15.4, 25.6), (20.5, 23.2), (46.6, 23.2), (46.6, 28.6), (40.6, 29.6), (37.6, 33.6), (37.6, 36.2),
         (42.8, 40.0), (42.8, 43.4), (21.2, 43.4), (21.2, 40.0), (26.4, 36.2), (26.4, 33.6), (23.4, 30.0),
         (19.6, 29.0)]
    )
    anvil = G.S(anvil, 0.86, 0.86, origin=(32, 33.5))
    sil = G.union(ring, disc)
    check_safe(sil, "iron_union")
    d.keyline(sil, KEY)
    d.plate(ring, "gunmetal", bevel=BEV)
    d.keyline(disc, 1.0, INK, 0.9)
    face = d.plate(disc, "f_iron", bevel=1.6)
    # forge-spark slots above the anvil
    sparks = G.union(G.cbox(30.6, 17.0, 33.4, 22.0, 1, 1, 1, 1), G.R(G.cbox(23.6, 18.6, 26.2, 23.0, 1, 1, 1, 1), -35, (25, 21)),
                     G.R(G.cbox(37.8, 18.6, 40.4, 23.0, 1, 1, 1, 1), 35, (39, 21)))
    d.inlay(sparks, "dusk", face, bevel=0.8, shadow=(0.8, 1.0))
    d.inlay(anvil, "steel", face, bevel=1.4, shadow=(1.4, 1.8))


def faction_crown_industries(d: Doc):
    body = G.poly([(10.5, 41), (10.5, 15.5), (21.5, 28.5), (32, 9.5), (42.5, 28.5), (53.5, 15.5), (53.5, 41)])
    jewels = G.union(
        G.cbox(7.2, 9.4, 13.8, 16.0, 1.6, 1.6, 1.6, 1.6),
        G.cbox(50.2, 9.4, 56.8, 16.0, 1.6, 1.6, 1.6, 1.6),
        G.cbox(28.4, 4.6, 35.6, 11.8, 1.8, 1.8, 1.8, 1.8),
    )
    band = G.cbox(7.5, 40, 56.5, 53.5, 2, 2, 4, 4)
    cog = G.gear(32, 46.8, 4.6, 6.4, 8, tooth_frac=0.5, tip_frac=0.32)
    cog = G.diff(cog, G.circle(32, 46.8, 2.0, n=24))
    sil = G.union(body, jewels, band)
    sil, body, jewels, band, cog = fitparts(sil, body, jewels, band, cog)
    check_safe(sil, "crown_industries")
    d.keyline(sil, KEY)
    d.plate(G.union(body, jewels), "brass", bevel=BEV)
    inner = G.shrink(body, 4.0)
    inner = G.diff(inner, G.rect(0, band.bounds[1] - 2.5, 64, 64))
    d.path(inner, MATERIALS["f_crown"][2])
    d.plate(G.shrink(inner, 0.9), "f_crown", bevel=1.0)
    face = d.plate(band, "brass", bevel=1.6)
    bx0, by0, bx1, by1 = band.bounds
    my = (by0 + by1) / 2
    slots = G.union(G.cbox(bx0 + 5.5, my - 1.5, bx0 + 14, my + 1.5, 1, 1, 1, 1), G.cbox(bx1 - 14, my - 1.5, bx1 - 5.5, my + 1.5, 1, 1, 1, 1))
    d.engrave(slots, "brass", face, depth=0.9)
    d.inlay(cog, "f_crown", face, bevel=0.9, shadow=(0.9, 1.1))


def _feather(root_x, tip_x, y_root, thick, rise, cut=3.0):
    """One wing feather: a bar from its root (x=root_x) out to a pointed tip at tip_x, rising by
    `rise` toward the tip."""
    return G.poly([(root_x, y_root), (tip_x + cut, y_root - rise), (tip_x, y_root - rise + thick * 0.5),
                   (tip_x + cut * 0.4, y_root - rise + thick), (root_x, y_root + thick)])


def faction_eastern_armor(d: Doc):
    """Winged spearhead. The wings are three stepped feathers per side, not chevrons (chevrons belong
    to the XP currencies and enlisted ranks), and they join in a pointed teal tail rather than a grip,
    so the mark never reads as a winged dagger."""
    blade = G.poly([(32, 4.0), (39.6, 19.5), (38.6, 27.0), (34.8, 36.5), (29.2, 36.5), (25.4, 27.0), (24.4, 19.5)])
    tail = G.poly([(27.5, 33.0), (36.5, 33.0), (36.5, 46.0), (32.0, 54.0), (27.5, 46.0)])
    thick, gap, rise = 6.2, 1.8, 10.0
    lens = (24.0, 19.0, 13.0)
    wing_l = G.union([_feather(30.0, 30.0 - ln, 26.0 + i * (thick + gap), thick, rise * ln / lens[0])
                      for i, ln in enumerate(lens)])
    body = G.union(wing_l, G.mirror_x(wing_l, 32), tail)
    sil = G.union(blade, body)
    sil, blade, body = fitparts(sil, blade, body)
    check_safe(sil, "eastern_armor")
    d.keyline(sil, KEY)
    d.plate(body, "f_eastern", bevel=1.5)
    d.keyline(blade, 1.0, INK, 0.9)
    face = d.plate(blade, "bone", bevel=BEV)
    # blade grind: the right half of the face falls into shade along the spine (two-tone steel)
    bx0, by0, bx1, by1 = blade.bounds
    spine = (bx0 + bx1) / 2
    d.path(G.inter(face, G.rect(spine, by0, bx1 + 1, by1)), MATERIALS["bone"][2], 0.55)
    d.path(G.inter(face, G.rect(spine - 0.5, by0, spine + 0.5, by1)), MATERIALS["bone"][0])


def _dune(x0, y0, xc, yc, x1, y1, y_bot, n=20):
    """Wind-blown dune: a long convex windward slope from (x0, y0) up to a sharp crest at (xc, yc),
    then a short, steep, slightly concave slip face down to (x1, y1)."""
    pts = [(x0, y_bot), (x0, y0)]
    for i in range(1, n + 1):
        t = i / n
        pts.append((x0 + (xc - x0) * t, y0 - (y0 - yc) * math.sin(t * math.pi / 2)))
    for i in range(1, 9):
        t = i / 8
        pts.append((xc + (x1 - xc) * t, yc + (y1 - yc) * (1 - (1 - t) ** 2)))
    pts.append((x1, y_bot))
    return G.poly(pts)


def _snowcap(ax, ay, w, h, teeth=3):
    """Region above a zig-zag snow line under a peak apex (intersect with the peak)."""
    pts = [(ax - w * 2, ay - 4), (ax + w * 2, ay - 4), (ax + w * 2, ay + h * 0.7)]
    for i in range(teeth * 2 + 1):
        t = 1 - i / (teeth * 2)
        x = ax - w * 2 + 4 * w * t
        y = ay + (h if i % 2 == 0 else h * 0.55)
        pts.append((x, y))
    pts.append((ax - w * 2, ay + h * 0.7))
    return G.poly(pts)


def faction_desert_corps(d: Doc):
    sun_c = (32, 26.5)
    rays = []
    for i in range(8):
        if i in (3, 4, 5):
            continue  # the three lower wedges would only poke out between the dunes
        a = math.radians(-90 + i * 45)
        long_ = i % 2 == 0
        r1 = 23.0 if long_ else 18.5
        half = 4.0 if long_ else 3.0
        r0 = 11.0
        px, py = -math.sin(a), math.cos(a)
        tip = (sun_c[0] + r1 * math.cos(a), sun_c[1] + r1 * math.sin(a))
        b0 = (sun_c[0] + r0 * math.cos(a) + half * px, sun_c[1] + r0 * math.sin(a) + half * py)
        b1 = (sun_c[0] + r0 * math.cos(a) - half * px, sun_c[1] + r0 * math.sin(a) - half * py)
        rays.append(G.poly([b0, tip, b1]))
    rays = G.union(rays)
    sun = G.circle(*sun_c, 9.8, n=72)
    base = G.cbox(6, 20, 58, 56, 0, 0, 3, 3)
    back = G.inter(_dune(6, 40.0, 24.0, 33.0, 34.0, 41.0, 56), base)
    front = G.inter(_dune(6, 50.0, 44.0, 38.0, 58.0, 46.0, 56), base)
    sky = G.diff(G.union(rays, sun), G.rect(0, 46, 64, 64))
    sil = G.union(sky, back, front)
    sil, rays, sun, back, front = fitparts(sil, rays, sun, back, front)
    check_safe(sil, "desert_corps")
    d.keyline(sil, KEY)
    d.plate(G.diff(rays, sun), "f_desert", bevel=1.4)
    d.keyline(G.diff(sun, back), 0.8, INK, 0.8)
    d.plate(sun, "gold", bevel=1.6)
    d.keyline(back, 0.9, INK, 0.9)
    d.plate(back, "f_desert_dark", bevel=1.5)
    d.keyline(front, 0.9, INK, 0.9)
    d.plate(front, "khaki", bevel=1.6)


def faction_mountain_republic(d: Doc):
    # ring and peaks sized so the emblem carries the same optical mass as the gear and the crystal
    disc = G.circle(32, 35.0, 23.0, n=120)
    inner = G.circle(32, 35.0, 18.8, n=96)
    apexes = [(19.5, 24.5), (32.5, 6.2), (45.5, 20.0)]
    peaks = G.poly([(9.0, 47.0), apexes[0], (25.0, 30.5), apexes[1], (40.0, 26.5), apexes[2], (55.0, 45.0)])
    peaks = G.inter(peaks, G.rect(0, 0, 64, 45.5))
    caps = G.union(_snowcap(*apexes[1], 3.9, 13.0, 3), _snowcap(*apexes[0], 2.3, 7.0, 2), _snowcap(*apexes[2], 2.3, 7.5, 2))
    groove = G.chevron(32, 47.2, 9.0, 4.0, 2.4)
    body = G.union(disc, peaks)
    body, disc, peaks, inner, caps, groove = fitparts(body, disc, peaks, inner, caps, groove)
    check_safe(body, "mountain_republic")
    d.keyline(body, KEY)
    d.plate(disc, "steel", bevel=BEV)
    d.keyline(inner, 0.9, INK, 0.85)
    face = d.plate(inner, "f_northern", bevel=1.2, face_override=None)
    d.cast_shadow(peaks, inner, 1.2, 1.4)
    d.keyline(peaks, 1.0, INK, 0.9)
    d.plate(peaks, "f_mountain", bevel=1.6)
    d.plate(G.inter(caps, G.shrink(peaks, 0.2)), "snow", bevel=0.9)
    # valley track: an engraved chevron groove on the disc (terrain mobility)
    lower = G.diff(face, peaks)
    d.engrave(G.inter(groove, lower), "f_northern", face, depth=0.7)


def faction_northern_federation(d: Doc):
    c = (32, 32)
    arms = []
    for i in range(6):
        ang = -90 + i * 60
        a = math.radians(ang)
        ux, uy = math.cos(a), math.sin(a)
        arm = G.thick_line(c, (c[0] + 26.5 * ux, c[1] + 26.5 * uy), 6.0)
        tip = G.R(G.cbox(-3.4, -3.4, 3.4, 3.4, 0, 0, 0, 0), 45, (0, 0))
        tip = G.T(tip, c[0] + 25.0 * ux, c[1] + 25.0 * uy)
        arm = G.union(arm, G.inter(tip, G.circle(*c, 27.6, n=96)))
        for r, ln in ((13.5, 8.6), (20.0, 6.2)):
            bx, by = c[0] + r * ux, c[1] + r * uy
            for sgn in (-1, 1):
                b = math.radians(ang + sgn * 55)
                arm = G.union(arm, G.thick_line((bx, by), (bx + ln * math.cos(b), by + ln * math.sin(b)), 3.6))
        arms.append(arm)
    flake = G.union(arms)
    flake = G.inter(flake, G.circle(*c, 27.8, n=120))
    core = G.ngon(32, 32, 9.6, 6, rot_deg=0)
    flake, core = fitparts(flake, core)
    check_safe(flake, "northern_federation")
    d.keyline(flake, KEY)
    d.plate(flake, "f_northern", bevel=1.5)
    d.keyline(core, 1.0, INK, 0.9)
    face = d.plate(core, "snow", bevel=1.4)
    d.engrave(G.ngon(32, 32, 4.0, 6, rot_deg=0), "snow", face, depth=0.8)


FACTION_DRAW = {
    "iron_union": faction_iron_union,
    "crown_industries": faction_crown_industries,
    "eastern_armor": faction_eastern_armor,
    "desert_corps": faction_desert_corps,
    "mountain_republic": faction_mountain_republic,
    "northern_federation": faction_northern_federation,
}


# ===========================================================================
# VEHICLE CLASSES (symbols). Each class owns one silhouette family:
#   light = spotter eye (almond), medium = flat-top hexagon, heavy = bastion shield,
#   td = low casemate trapezoid, artillery = trajectory arch over an impact point.
# ===========================================================================
def _vesica(cx, cy, a, b, n=96):
    c = (a * a - b * b) / (2 * b)
    R = c + b
    return G.inter(G.circle(cx, cy + c, R, n=n * 2), G.circle(cx, cy - c, R, n=n * 2))


def class_shapes(kind: str, scale: float = 1.0):
    """Return (silhouette, engraved detail) on the 64 grid."""
    if kind == "light":
        sil = _vesica(32, 32, 27.0, 15.0)
        det = G.diff(G.circle(32, 32, 9.0), G.circle(32, 32, 4.6))
        det = G.union(det)
    elif kind == "medium":
        sil = G.ngon(32, 32, 27.5, 6, rot_deg=30)
        sil = G.inter(sil, G.rect(0, 9, 64, 55))
        det = G.cbox(19, 28.6, 45, 35.4, 1.5, 1.5, 1.5, 1.5)
    elif kind == "heavy":
        sil = G.poly([(9, 12.5), (13, 8.5), (51, 8.5), (55, 12.5), (55, 37), (32, 57.5), (9, 37)])
        # one engraved inner contour (a second armor layer). Not stacked bars: a bar count that
        # grows with vehicle weight is another game's class convention.
        det = G.diff(G.shrink(sil, 7.0), G.shrink(sil, 10.2))
    elif kind == "td":
        sil = G.poly([(6, 47), (6, 43), (15.5, 18.5), (48.5, 18.5), (58, 43), (58, 47)])
        det = G.diff(G.circle(32, 33.5, 8.0), G.circle(32, 33.5, 4.0))
    elif kind == "artillery":
        arch = G.arc_band(32, 47, 26.5, 17.5, 180, 360, n=64)
        dot = G.circle(32, 41.5, 6.6)
        sil = G.union(arch, dot)
        det = G.EMPTY
    else:
        raise KeyError(kind)
    return sil, det


def draw_class(d: Doc, kind: str):
    sil, det = class_shapes(kind)
    sil, det = fitparts(sil, det)
    check_safe(sil, f"class {kind}")
    d.keyline(sil, KEY)
    face = d.plate(sil, "bone", bevel=BEV)
    if not det.is_empty:
        d.engrave(det, "bone", face, depth=1.0)


# Minimap glyphs: 24 x 24, white fill + 1.5 px ink keyline, tint via ImageColor3.
def draw_minimap(d: Doc, kind: str):
    k = 24 / 64.0
    if kind == "light":
        sil = _vesica(12, 12, 10.0, 6.4)
        hole = G.circle(12, 12, 2.9)
    elif kind == "medium":
        sil = G.ngon(12, 12, 10.0, 6, rot_deg=30)
        hole = G.EMPTY
    elif kind == "heavy":
        sil = G.poly([(2.8, 4.6), (4.4, 3.0), (19.6, 3.0), (21.2, 4.6), (21.2, 13.4), (12, 21.6), (2.8, 13.4)])
        hole = G.EMPTY
    elif kind == "td":
        sil = G.poly([(2.0, 18.2), (2.0, 16.4), (6.0, 6.0), (18.0, 6.0), (22.0, 16.4), (22.0, 18.2)])
        hole = G.EMPTY
    elif kind == "artillery":
        sil = G.union(G.arc_band(12, 17.6, 10.0, 5.8, 180, 360, n=48), G.circle(12, 15.4, 3.0))
        hole = G.EMPTY
    else:
        raise KeyError(kind)
    x0, y0, x1, y1 = sil.bounds
    if x0 < 1.95 or y0 < 1.95 or x1 > 22.05 or y1 > 22.05:
        raise ValueError(f"minimap {kind} out of bounds {sil.bounds}")
    d.keyline(sil, 1.5)
    d.path(sil, "#FFFFFF")
    if not hole.is_empty:
        d.path(hole, INK)


# ===========================================================================
# TIERS I..XI
# ===========================================================================
ROMAN = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]


def _numeral(n: int, cap: float, max_w: float, cx: float, top: float):
    g, w = glyphs.text(ROMAN[n - 1], glyphs.NUMERAL, tracking=11, cap=cap)
    sx = min(1.0, max_w / w)
    g = G.S(g, sx, 1.0, origin=(0, 0))
    w *= sx
    return G.T(g, cx - w / 2, top)


def draw_tier(d: Doc, n: int):
    if n <= 3:
        mat, num_mode = "steel", "engrave"
    elif n <= 6:
        mat, num_mode = "bronze", "engrave"
    elif n <= 8:
        mat, num_mode = "silver", "engrave"
    elif n <= 10:
        mat, num_mode = "gold", "engrave"
    else:
        mat, num_mode = "obsidian", "inlay"

    px0, px1 = (8, 56) if n <= 8 else (11, 53)
    plate = G.chamfer_all(px0, 17, px1, 47, 7)
    if n >= 4:
        # side notches cut into the plate (bronze and up)
        plate = G.diff(plate, G.poly([(px0, 28), (px0 + 3.5, 32), (px0, 36)]), G.poly([(px1, 28), (px1 - 3.5, 32), (px1, 36)]))
    parts = [plate]
    crest = None
    if n >= 7:
        crest = G.poly([(22, 17.5), (26.5, 11.5), (37.5, 11.5), (42, 17.5)])
        parts.append(crest)
    fins = None
    if n >= 9:
        fl = G.poly([(px0 + 1, 21), (6, 25), (6, 39), (px0 + 1, 43)])
        fins = G.union(fl, G.mirror_x(fl, 32))
        parts.append(fins)
    keel = None
    if n == 11:
        keel = G.poly([(24, 46.5), (40, 46.5), (32, 55.6)])
        crest = G.poly([(20, 17.5), (25.5, 8.0), (38.5, 8.0), (44, 17.5)])
        parts = [plate, crest, fins, keel]
    sil = G.union(parts)
    check_safe(sil, f"tier {n}")

    if n == 11:
        glow = d.radial([(0, UI["accent.dusk"], 0.55), (0.6, UI["accent.dusk"], 0.18), (1, UI["accent.dusk"], 0)], 32, 32, 30)
        d.path(G.chamfer_all(2, 2, 62, 62, 12), glow)
    d.keyline(sil, KEY)
    if fins is not None:
        d.plate(fins, "obsidian" if n == 11 else mat, bevel=1.4)
    if keel is not None:
        d.plate(keel, "dusk", bevel=1.4)
    if crest is not None:
        cm = "dusk" if n == 11 else mat
        d.plate(crest, cm, bevel=1.4)
    face = d.plate(plate, mat, bevel=BEV)
    if n == 11:
        rim = G.diff(G.shrink(plate, 2.6), G.shrink(plate, 3.8))
        d.path(rim, UI["accent.dusk"])
        face = G.shrink(plate, 3.8)
    num = _numeral(n, cap=18.0, max_w=(px1 - px0) - 15, cx=32, top=23.0)
    if num_mode == "engrave":
        d.engrave(num, mat, face, depth=1.0)
    else:
        d.inlay(num, "gold", face, bevel=1.1, shadow=(1.0, 1.2), shadow_opacity=0.8)
    # rivets on the crest for VII+
    if n >= 7 and n <= 10:
        for x in (27.5, 36.5):
            d.engrave(G.cbox(x - 1, 13.4, x + 1, 15.4, 0.5, 0.5, 0.5, 0.5), mat, crest, depth=0.6)
    if n == 11:
        # engraved ridge crest on the XI cap
        ridge_mark = G.diff(G.poly([(25.5, 15.6), (30.0, 11.4), (34.0, 11.4), (38.5, 15.6)]),
                            G.poly([(27.6, 16.2), (30.8, 13.2), (33.2, 13.2), (36.4, 16.2)]))
        d.engrave(G.inter(ridge_mark, crest), "dusk", crest, depth=0.6)


# ===========================================================================
# RANKS 1..15
# ===========================================================================
RANKS = [
    ("rank_01", "Recruit", "RCT"),
    ("rank_02", "Trackhand", "TRK"),
    ("rank_03", "Loader", "LDR"),
    ("rank_04", "Gunner", "GNR"),
    ("rank_05", "Gun Sergeant", "GSG"),
    ("rank_06", "Tank Commander", "TCO"),
    ("rank_07", "Section Leader", "SCL"),
    ("rank_08", "Troop Warden", "TWD"),
    ("rank_09", "Column Chief", "CCH"),
    ("rank_10", "Squadron Commandant", "SQC"),
    ("rank_11", "Battlegroup Leader", "BGL"),
    ("rank_12", "Vanguard Colonel", "VCL"),
    ("rank_13", "Armor Brigadier", "ABG"),
    ("rank_14", "Field General", "FGN"),
    ("rank_15", "Ridge Marshal", "RMR"),
]


def _tab(x0=15.0, x1=49.0, top=6.0, shoulder=14.6, bottom=58.0):
    cx = (x0 + x1) / 2
    return G.poly([(x0, bottom - 3), (x0, shoulder), (cx, top), (x1, shoulder), (x1, bottom - 3), (x1 - 3, bottom), (x0 + 3, bottom)])


def _pip(cx, cy, s=7.4):
    h = s / 2
    return G.cbox(cx - h, cy - h, cx + h, cy + h, 1.8, 1.8, 1.8, 1.8)


def _mini_mark(cx, cy, w):
    """Simplified ridge-and-turret brand mark for insignia (one solid shape)."""
    k = w / 30.0
    ridge = G.poly([(-15, 6), (-15, 3.2), (-7, 0.4), (8, 0), (15, 3.4), (15, 6)])
    tur = G.S(turret(hull=False), 0.30, 0.30)
    g = G.union(ridge, G.T(tur, -1, 0.6))
    g = G.S(g, k, k, origin=(0, 0))
    return G.T(g, cx, cy)


def draw_rank(d: Doc, idx: int):
    """idx 1..15"""
    if idx <= 5:
        band = "enlisted"
    elif idx <= 10:
        band = "command"
    elif idx <= 14:
        band = "high"
    else:
        band = "marshal"

    if band == "marshal":
        # wider tab whose top edge is the brand ridge (low, asymmetric crest) instead of a gable
        tab = G.poly([(11, 55), (11, 17.0), (20, 12.5), (27, 7.5), (37, 7.0), (44, 11.5), (53, 15.0), (53, 55), (50, 58),
                      (14, 58)])
    else:
        tab = _tab()
    check_safe(tab, f"rank {idx}")
    d.keyline(tab, KEY)

    if band == "enlisted":
        face = d.plate(tab, "olive", bevel=BEV)
        insignia = []
        if idx == 1:
            insignia.append(G.cbox(22, 36, 42, 41.5, 1.4, 1.4, 1.4, 1.4))
        else:
            n = min(idx - 1, 3)
            top, step = (23.0, 8.6) if idx < 5 else (20.6, 8.0)
            for i in range(n):
                insignia.append(G.chevron(32, top + i * step, 11.5, 7.6, 5.0, flat_tip=2.0))
            if idx == 5:
                insignia.append(G.cbox(20.5, 50.4, 43.5, 54.4, 1.2, 1.2, 1.2, 1.2))
        for g in insignia:
            d.inlay(g, "bone", face, bevel=1.0, shadow=(0.9, 1.2))
    elif band == "command":
        d.plate(tab, "silver", bevel=1.6)
        inner = G.shrink(tab, 3.0)
        d.keyline(inner, 0.6, INK, 0.9)
        face = d.plate(inner, "gunmetal", bevel=1.2)
        n = idx - 5
        cx, cy, dx, dy = 32, 37.5, 5.2, 9.2
        layouts = {
            1: [(cx, cy)],
            2: [(cx, cy - dy / 2 - 0.4), (cx, cy + dy / 2 + 0.4)],
            3: [(cx, cy - dy), (cx, cy), (cx, cy + dy)],
            4: [(cx - dx, cy - dy / 2), (cx + dx, cy - dy / 2), (cx - dx, cy + dy / 2), (cx + dx, cy + dy / 2)],
            5: [(cx - dx, cy - dy), (cx + dx, cy - dy), (cx, cy), (cx - dx, cy + dy), (cx + dx, cy + dy)],
        }
        for (px, py) in layouts[n]:
            d.inlay(_pip(px, py, 6.8 if n >= 4 else 7.4), "silver", face, bevel=1.0, shadow=(0.9, 1.2))
    else:
        d.plate(tab, "gold", bevel=1.6)
        inner = G.shrink(tab, 3.0)
        d.keyline(inner, 0.6, INK, 0.9)
        face = d.plate(inner, "obsidian", bevel=1.2)
        if band == "high":
            mark = _mini_mark(32, 23.6, 24)
            d.inlay(mark, "gold", face, bevel=0.8, shadow=(0.8, 1.0))
            n = idx - 11
            ys = {0: [], 1: [42.5], 2: [38.0, 48.0], 3: [35.0, 43.0, 51.0]}[n]
            for py in ys:
                d.inlay(_pip(32, py, 7.0), "gold", face, bevel=1.0, shadow=(0.9, 1.2))
            if n == 0:
                d.inlay(G.cbox(22, 38.5, 42, 43.0, 1.2, 1.2, 1.2, 1.2), "gold", face, bevel=0.9, shadow=(0.9, 1.2))
        else:
            # marshal: dusk sun + ridge mark + two gold bars
            # the mark sits low enough that the sun's upper half stays visible behind the turret
            sun = G.inter(G.circle(32, 33.5, 10.5, n=72), G.rect(0, 0, 64, 34.0))
            d.inlay(sun, "dusk", face, bevel=1.0, shadow=(0.8, 1.0))
            mark = _mini_mark(32, 29.0, 26)
            d.inlay(mark, "gold", face, bevel=0.8, shadow=(0.8, 1.0))
            for py in (41.5, 48.5):
                d.inlay(G.cbox(19, py, 45, py + 4.4, 1.3, 1.3, 1.3, 1.3), "gold", face, bevel=0.9, shadow=(0.9, 1.2))
    # shoulder button
    btn = G.circle(32, 13.0, 2.7, n=32)
    if band in ("high", "marshal"):
        btn = G.circle(32, 12.4 if band == "high" else 13.6, 2.3, n=32)
    btn_mat = {"enlisted": "brass", "command": "silver", "high": "gold", "marshal": "gold"}[band]
    d.keyline(btn, 0.8, INK, 0.9)
    d.plate(btn, btn_mat, bevel=0.9)


# ===========================================================================
# CURRENCIES
# ===========================================================================
class ObjectScene:
    """Collects projected faces of physical objects, then fits them to the 64 grid."""

    def __init__(self):
        self.items = []  # (geom, kind, payload)

    def add(self, geom, kind, payload=None):
        self.items.append((geom, kind, payload))

    def fit(self, x0=7, y0=8, x1=57, y1=56):
        allg = G.union([g for g, _, _ in self.items if g is not None and not g.is_empty])
        bx0, by0, bx1, by1 = allg.bounds
        s = min((x1 - x0) / (bx1 - bx0), (y1 - y0) / (by1 - by0))
        ox = x0 + ((x1 - x0) - (bx1 - bx0) * s) / 2 - bx0 * s
        oy = y0 + ((y1 - y0) - (by1 - by0) * s) / 2 - by0 * s
        return lambda g: affinity.affine_transform(g, [s, 0, 0, s, ox, oy])


def _side_tones(faces, mat):
    """Tone for each visible side face. The most-lit side takes the material base, other lit sides
    a half step toward shade (so two lit faces never merge into one flat shape), unlit sides shade."""
    hi, base, lo = MATERIALS[mat]
    lams = [proj.lambert(n) for k, n, _, _ in faces if k == "side"]
    best = max(lams) if lams else 0.0
    out = []
    for l in lams:
        if l <= 0.05:
            out.append(lo)
        elif l >= best - 1e-6:
            out.append(base)
        else:
            out.append(mix(base, lo, 0.5))
    return out


def draw_prism_object(d: Doc, faces, mat, f, keyline: bool = True):
    """Draw projected prism faces (from proj.prism) through fit transform f.
    Returns (top face geometry, inset top face usable as a clip for stamps)."""
    hi, base, lo = MATERIALS[mat]
    if keyline:
        sil = G.union([f(p) for _, _, p, _ in faces])
        d.keyline(sil, KEY)
    top_geom = None
    tones = iter(_side_tones(faces, mat))
    for kind, nrm, p, _ in faces:
        g = f(p)
        if kind == "top":
            top_geom = g
            continue
        d.path(g, next(tones))
    # top face: base gradient with a single highlight rim along its front edges
    x0, y0, x1, y1 = top_geom.bounds
    fill = d.linear([(0, mix(base, hi, 0.45), 1), (1, base, 1)], 0, y0, 0, y1)
    d.path(top_geom, fill)
    rim = G.diff(top_geom, G.T(top_geom, 0, -1.3))
    d.path(rim, hi)
    face = G.shrink(top_geom, 0.6)
    return top_geom, face


def currency_credits(d: Doc):
    R = 1.0
    hexpts = [(R * math.cos(math.radians(a)), R * math.sin(math.radians(a))) for a in range(0, 360, 60)]
    faces = proj.prism(hexpts, 0.0, 0.30)
    sc = ObjectScene()
    for _, _, p, _ in faces:
        sc.add(p, "f")
    f = sc.fit(6, 9, 58, 55)
    top, face = draw_prism_object(d, faces, "copper", f)
    # stamped design on the top plane: recessed inner hexagon ring + stencil C
    ring = G.diff(G.ngon(0, 0, 0.80, 6, rot_deg=30), G.ngon(0, 0, 0.68, 6, rot_deg=30))
    c_glyph, cw = glyphs.text("C", glyphs.BOLD, cap=0.78)
    c_glyph = G.T(c_glyph, -cw / 2, -0.39)
    stamp = G.union(ring, c_glyph)
    st = f(proj.on_plane(stamp, 0.30))
    d.engrave(G.inter(st, face), "copper", face, depth=0.9, recess=MATERIALS["copper"][2])


def currency_bullion(d: Doc):
    base = [(-1.0, -0.5), (1.0, -0.5), (1.0, 0.5), (-1.0, 0.5)]
    faces = proj.prism(base, 0.0, 0.62, top_scale=(0.80, 0.66))
    sc = ObjectScene()
    for _, _, p, _ in faces:
        sc.add(p, "f")
    f = sc.fit(6, 12, 58, 54)
    top, face = draw_prism_object(d, faces, "gold", f)
    # stamp: recessed cartouche with the ridge mark and two bars (assay marks)
    cart = G.diff(G.cbox(-0.6, -0.25, 0.6, 0.25, 0.08, 0.08, 0.08, 0.08), G.cbox(-0.51, -0.17, 0.51, 0.17, 0.05, 0.05, 0.05, 0.05))
    ridge = G.poly([(-0.40, 0.1), (-0.12, -0.06), (0.14, -0.06), (0.40, 0.1)])
    ridge = G.diff(ridge, G.T(ridge, 0, 0.07))
    bump = G.cbox(-0.08, -0.12, 0.12, -0.04, 0.02, 0.02, 0, 0)
    stamp = G.union(cart, ridge, bump)
    st = f(proj.on_plane(stamp, 0.62))
    d.engrave(G.inter(st, face), "gold", face, depth=0.8, recess=MATERIALS["gold"][2])


def currency_campaign_token(d: Doc):
    """A thick, square operations-map counter (small corner chamfers, so it never reads as the
    hexagonal Credits token) stamped with a pennant planted on a summit: the objective you push
    across the campaign map."""
    h, c = 0.86, 0.10
    pts = [(-h + c, -h), (h - c, -h), (h, -h + c), (h, h - c), (h - c, h), (-h + c, h), (-h, h - c), (-h, -h + c)]
    th = 0.40
    faces = proj.prism(pts, 0.0, th)
    sc = ObjectScene()
    for _, _, p, _ in faces:
        sc.add(p, "f")
    f = sc.fit(6, 8, 58, 56)
    top, face = draw_prism_object(d, faces, "rose", f)
    # recessed border groove + pennant on a pole planted on a summit (a peak, not a bar, so the stamp
    # can't be read as a letter)
    border = G.diff(G.chamfer_all(-0.70, -0.70, 0.70, 0.70, 0.08), G.chamfer_all(-0.60, -0.60, 0.60, 0.60, 0.06))
    peak = G.poly([(-0.46, 0.44), (-0.02, 0.02), (0.08, 0.02), (0.46, 0.44)])
    pole = G.rect(-0.02, -0.50, 0.08, 0.06)
    flag = G.poly([(0.08, -0.50), (0.44, -0.37), (0.08, -0.24)])
    stamp = G.union(border, peak, pole, flag)
    st = f(proj.on_plane(stamp, th))
    d.engrave(G.inter(st, face), "rose", face, depth=0.9, recess=MATERIALS["rose"][2])


def _xp_chevrons(top=7.0):
    a = G.chevron(32, top, 17.5, 11.0, 7.0, flat_tip=3.0)
    b = G.chevron(32, top + 11.5, 17.5, 11.0, 7.0, flat_tip=3.0)
    return a, b


def currency_xp(d: Doc, kind: str):
    mat = {"vehicle_xp": "xp_blue", "free_xp": "xp_violet", "crew_xp": "xp_teal"}[kind]
    if kind == "free_xp":
        a, b = _xp_chevrons(top=17.5)
        # four open arc segments: XP not bound to any vehicle
        ring = G.union(G.arc_band(32, 32, 27.5, 22.5, -63, -27, 16), G.arc_band(32, 32, 27.5, 22.5, 27, 63, 16),
                       G.arc_band(32, 32, 27.5, 22.5, 117, 153, 16), G.arc_band(32, 32, 27.5, 22.5, 207, 243, 16))
        sil = G.union(a, b, ring)
        check_safe(sil, kind)
        d.keyline(sil, KEY)
        d.plate(ring, "bone", bevel=1.4)
        d.plate(b, mat, bevel=1.6)
        d.keyline(a, 0.9, INK, 0.9)
        d.plate(a, mat, bevel=1.6)
        return
    a, b = _xp_chevrons(top=6.5)
    if kind == "vehicle_xp":
        tread = G.chamfer_all(8, 38, 56, 57, 8)
        inner = G.chamfer_all(12, 42, 52, 53, 5.0)
        sil = G.union(a, b, tread)
        check_safe(sil, kind)
        d.keyline(sil, KEY)
        d.plate(b, mat, bevel=1.6)
        d.keyline(a, 0.9, INK, 0.9)
        d.plate(a, mat, bevel=1.6)
        face = d.plate(tread, "gunmetal", bevel=1.6)
        d.engrave(inner, "gunmetal", face, depth=0.8)
        for x in (19, 32, 45):
            w = G.circle(x, 47.5, 4.2, n=32)
            d.inlay(w, "bone", inner, bevel=0.9, shadow=(0.7, 0.9))
        # track links along the top run
        for i in range(7):
            x = 14 + i * 6
            d.engrave(G.rect(x, 38.8, x + 2.2, 40.6), "gunmetal", face, depth=0.5)
    else:  # crew_xp
        helmet = G.union(
            G.inter(G.circle(32, 52, 17.5, n=96), G.rect(0, 0, 64, 52)),
            G.cbox(14.5, 46, 21.5, 58, 0, 0, 2.5, 2.5),
            G.cbox(42.5, 46, 49.5, 58, 0, 0, 2.5, 2.5),
        )
        sil = G.union(a, b, helmet)
        check_safe(sil, kind)
        d.keyline(sil, KEY)
        d.plate(b, mat, bevel=1.6)
        d.keyline(a, 0.9, INK, 0.9)
        d.plate(a, mat, bevel=1.6)
        face = d.plate(helmet, "olive", bevel=1.6)
        ribs = G.union([G.rect(x - 1.0, 36, x + 1.0, 45) for x in (26, 32, 38)])
        d.engrave(G.inter(ribs, face), "olive", face, depth=0.6)
        goggles = G.union(G.cbox(20, 44.8, 30.5, 51.2, 2, 2, 2, 2), G.cbox(33.5, 44.8, 44, 51.2, 2, 2, 2, 2),
                          G.rect(29.5, 46.6, 34.5, 49.0))
        d.inlay(goggles, "bone", face, bevel=0.9, shadow=(0.8, 1.0))
