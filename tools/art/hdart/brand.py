"""HULLDOWN brand marks: the ridge-and-turret emblem, wordmark and logo lockups."""

from __future__ import annotations

from . import geom as G
from . import glyphs
from .svgdoc import Doc
from .tokens import INK, MATERIALS, UI

DUSK = UI["accent.dusk"]
BONE = UI["brand.bone"]
KHAKI = UI["brand.khaki"]
SKY_TOP = "#121A21"
SKY_LOW = "#2A2427"
RIDGE = "#0B0F12"
WORD_ON_LIGHT = "#151C21"
PAD = 4 / 64  # emblem plate inset (4 px on the 64 grid); lockups use it as their outer bearing


# ---------------------------------------------------------------------------
# Turret silhouette (side view, gun to the right). Local units, base centre at (0, 0), y down.
# ---------------------------------------------------------------------------
def turret(antenna: bool = False, hull: bool = True):
    body = G.poly(
        [
            (-17, 0.5), (-18.5, -3), (-24, -4.2), (-25.5, -8.6), (-21.5, -12.2), (6, -12.2),
            (15.5, -8.4), (17.5, -3.2), (15, 0.5),
        ]
    )
    cupola = G.cbox(-13.5, -16.2, -4.5, -11.5, 2.2, 2.2, 0, 0)
    sight = G.cbox(4, -14.6, 8.4, -11.5, 1.2, 1.2, 0, 0)
    mantlet = G.cbox(14, -10.2, 21, -3.4, 0, 1.5, 1.5, 0)
    barrel = G.rect(20, -8.1, 44, -5.5)
    muzzle = G.cbox(41, -9.2, 47.5, -4.4, 0, 1, 1, 0)
    parts = [body, cupola, sight, mantlet, barrel, muzzle]
    if hull:
        parts.append(G.poly([(-17, 0), (15, 0), (24, 9), (-24, 9)]))
    if antenna:
        parts.append(G.thick_line((-21.5, -11.5), (-26.5, -31), 1.1))
    return G.union(parts)


def ridge_poly(x0, x1, crest_x, crest_y, base_y, left_y, right_y, crest_w):
    """Asymmetric hill crest. Returns polygon from left edge to right edge and down to base."""
    pts = [
        (x0, base_y),
        (x0, left_y),
        (x0 + (crest_x - crest_w / 2 - x0) * 0.55, left_y - (left_y - crest_y) * 0.72),
        (crest_x - crest_w / 2, crest_y + 0.6),
        (crest_x + crest_w * 0.1, crest_y),
        (crest_x + crest_w / 2, crest_y + 0.9),
        (crest_x + crest_w / 2 + (x1 - crest_x - crest_w / 2) * 0.5, crest_y + (right_y - crest_y) * 0.62),
        (x1, right_y),
        (x1, base_y),
    ]
    return G.poly(pts)


def ridge_line(ridge, top_y_cut, width):
    """Rim-light band along the top contour of the ridge."""
    return G.diff(ridge, G.T(ridge, 0, width))


# ---------------------------------------------------------------------------
# Emblem (square app icon). Drawn into an arbitrary doc at (x, y) with size s (64-grid scaled).
# ---------------------------------------------------------------------------
def draw_emblem(d: Doc, x: float, y: float, s: float, detail: str = "full"):
    k = s / 64.0

    def P(g):
        return G.T(G.S(g, k, k, origin=(0, 0)), x, y)

    plate = G.chamfer_all(4, 4, 60, 60, 9)
    window = G.chamfer_all(9.5, 9.5, 54.5, 54.5, 6)
    sun_c, sun_r = (32, 40.0), 17.0
    sun = G.circle(*sun_c, sun_r, n=96)
    ridge = ridge_poly(9.5, 54.5, 31, 38.4, 54.5, 47.0, 45.0, 22)
    tur = G.T(G.S(turret(antenna=False), 0.5, 0.5), 28.2, 38.7)
    line = G.inter(ridge_line(ridge, 0, 1.3), window)

    d.keyline(P(plate), 2.0 * k)
    if detail == "full":
        d.plate(P(plate), "gunmetal", bevel=2.4 * k)
        d.keyline(P(window), 0.9 * k, INK, 0.9)
    else:
        d.path(P(plate), MATERIALS["gunmetal"][1])
    sky = d.linear([(0, SKY_TOP, 1), (0.62, "#1C2229", 1), (1, SKY_LOW, 1)], 0, y + 9.5 * k, 0, y + 46 * k)
    d.path(P(window), sky)
    # sun with a soft halo
    halo = d.radial([(0, DUSK, 0.0), (0.72, DUSK, 0.0), (0.78, DUSK, 0.32), (1, DUSK, 0)],
                    x + sun_c[0] * k, y + sun_c[1] * k, 23 * k)
    d.path(P(G.inter(G.circle(*sun_c, 23, n=96), window)), halo)
    sun_fill = d.linear([(0, "#FFC48F", 1), (0.55, DUSK, 1), (1, "#E0581C", 1)], 0, y + 23 * k, 0, y + 40 * k)
    d.path(P(G.inter(sun, window)), sun_fill)
    # turret + ridge silhouette, rim-lit ridge line in front of the turret base
    d.path(P(G.inter(G.union(tur, ridge), window)), RIDGE)
    d.path(P(line), DUSK)
    return P(plate)


# ---------------------------------------------------------------------------
# Wordmark
# ---------------------------------------------------------------------------
def wordmark(cap: float, x: float, y: float, weight=glyphs.HEAVY, tracking: float = 12.0, word="HULLDOWN"):
    return glyphs.text(word, weight, tracking=tracking, cap=cap, x=x, y=y)


def draw_wordmark_flat(d: Doc, g, color=BONE, keyline: float = 0.0):
    if keyline:
        d.keyline(g, keyline)
    d.path(g, color)


def draw_wordmark_metal(d: Doc, g, cap: float):
    """Cinematic treatment: bone-to-khaki metal with bevel and keyline."""
    d.keyline(g, cap * 0.035)
    x0, y0, x1, y1 = g.bounds
    f = G.bevel(g, cap * 0.035)
    d.path(f["hi"], "#FFF8E8")
    d.path(f["mid"], "#D8CCAE")
    d.path(f["lo"], "#7F7152")
    fill = d.linear([(0, "#F4EBD3", 1), (0.48, "#E2D6B6", 1), (0.52, "#C9BA92", 1), (1, "#B3A272", 1)], 0, y0, 0, y1)
    d.path(f["face"], fill)


# ---------------------------------------------------------------------------
# Lockups
# ---------------------------------------------------------------------------
def logo_primary(path, on_light: bool = False):
    cap = 56
    em = 100
    gap = 24
    word, ww = wordmark(cap, em + gap, (em - cap) / 2)
    W = em + gap + ww + em * PAD  # right bearing matches the emblem plate's own inset on the left
    d = Doc(W, em, "HULLDOWN logo, primary horizontal" + (" (for light backgrounds)" if on_light else ""))
    draw_emblem(d, 0, 0, em)
    draw_wordmark_flat(d, word, color=WORD_ON_LIGHT if on_light else BONE)
    return d.save(path)


def logo_stacked(path, on_light: bool = False):
    em = 150
    cap = 52
    pad = em * PAD
    word, ww = wordmark(cap, 0, 0)
    W = max(ww, em) + 2 * pad
    word = G.T(word, (W - ww) / 2, em + 22)
    d = Doc(W, em + 22 + cap + pad, "HULLDOWN logo, stacked" + (" (for light backgrounds)" if on_light else ""))
    draw_emblem(d, (W - em) / 2, 0, em)
    draw_wordmark_flat(d, word, color=WORD_ON_LIGHT if on_light else BONE)
    return d.save(path)


def emblem(path, flat: bool = False):
    d = Doc(64, 64, "HULLDOWN emblem" + (" (flat, for 32 px and below)" if flat else ""))
    draw_emblem(d, 0, 0, 64, detail="flat" if flat else "full")
    return d.save(path)


def loading_logo(path):
    W, H = 1600, 720
    d = Doc(W, H, "HULLDOWN loading logo, cinematic")
    cx = W / 2
    horizon = 360
    # ridge across the full width (crest at the centre), fading toward the edges
    ridge = ridge_poly(0, W, cx + 6, horizon - 4, H, horizon + 96, horizon + 80, 250)
    # atmospheric glow, sky only: the ridge fades out toward the edges, and a glow left under it
    # would show through that fade as vertical banding
    glow = d.radial([(0, DUSK, 0.55), (0.35, DUSK, 0.22), (1, DUSK, 0)], cx, horizon - 10, 1, ellipse=(700, 330))
    d.path(G.diff(G.T(G.S(G.circle(0, 0, 1, n=128), 700, 330, origin=(0, 0)), cx, horizon - 10), ridge), glow)
    # sun, clipped to the sky so nothing shows through the ridge
    sun = G.diff(G.circle(cx, horizon + 8, 150, n=180), ridge)
    sun_fill = d.linear([(0, "#FFD2A6", 1), (0.5, "#FF8A3D", 1), (1, "#D9541A", 1)], 0, horizon - 142, 0, horizon + 10)
    d.path(sun, sun_fill)
    # heat-haze bands across the lower sun
    for yy, hh, op in ((horizon - 36, 4, 0.28), (horizon - 20, 6, 0.38)):
        d.path(G.inter(G.rect(cx - 160, yy, cx + 160, yy + hh), sun), "#B8460F", op)
    tur = G.T(G.S(turret(antenna=True), 4.1, 4.1), cx - 4, horizon - 2)
    sil = G.union(ridge, tur)
    fade = d.linear([(0, RIDGE, 0), (0.18, RIDGE, 0.85), (0.5, RIDGE, 1), (0.82, RIDGE, 0.85), (1, RIDGE, 0)], 0, 0, W, 0)
    d.path(sil, fade)
    rim = ridge_line(ridge, 0, 4)
    rim_fill = d.linear([(0, DUSK, 0), (0.2, DUSK, 0.9), (0.5, "#FFB27A", 1), (0.8, DUSK, 0.9), (1, DUSK, 0)], 0, 0, W, 0)
    d.path(rim, rim_fill)
    # rangefinder ticks along the horizon, both sides
    ticks = []
    for i in range(1, 12):
        for sgn in (-1, 1):
            tx = cx + sgn * (210 + i * 44)
            th = 18 if i % 3 == 0 else 9
            ticks.append(G.rect(tx - 1.5, horizon + 104, tx + 1.5, horizon + 104 + th))
    tick_fill = d.linear([(0, KHAKI, 0), (0.25, KHAKI, 0.7), (0.5, KHAKI, 0.0), (0.75, KHAKI, 0.7), (1, KHAKI, 0)], 0, 0, W, 0)
    d.path(G.union(ticks), tick_fill)
    # wordmark
    cap = 168
    word, ww = wordmark(cap, 0, 0, tracking=14)
    word = G.T(word, cx - ww / 2, horizon + 146)
    draw_wordmark_metal(d, word, cap)
    # underline: dusk rule with central crest notch (the ridge, restated)
    yb = horizon + 146 + cap + 30
    rule = G.union(
        G.rect(cx - ww / 2, yb, cx - 46, yb + 6),
        G.rect(cx + 46, yb, cx + ww / 2, yb + 6),
        G.poly([(cx - 46, yb), (cx - 18, yb - 16), (cx + 18, yb - 16), (cx + 46, yb), (cx + 46, yb + 6), (cx + 15, yb - 10),
                (cx - 15, yb - 10), (cx - 46, yb + 6)]),
    )
    d.path(rule, DUSK)
    return d.save(path)


def garage_logo(path):
    em = 96
    cap1 = 52
    cap2 = 34
    x = em + 22
    word, w1 = wordmark(cap1, x, (em - cap1) / 2)
    x2 = x + w1 + 26
    dot = G.chamfer_all(x2, em / 2 - 6, x2 + 12, em / 2 + 6, 2.5)
    x3 = x2 + 12 + 26
    sub, w2 = glyphs.text("COMMAND GARAGE", glyphs.MEDIUM, tracking=16, cap=cap2, x=x3, y=(em - cap2) / 2 + (cap1 - cap2) / 2)
    W = x3 + w2 + em * PAD
    d = Doc(W, em, "HULLDOWN Command Garage lockup")
    draw_emblem(d, 0, 0, em)
    draw_wordmark_flat(d, word)
    d.path(dot, DUSK)
    d.path(sub, KHAKI)
    return d.save(path)


def battle_logo(path):
    em = 48
    cap = 26
    x = em + 12
    weight = glyphs.Weight(S=24, T=21, C=27, cs=5, G=0, D=30)
    word, ww = wordmark(cap, x, (em - cap) / 2, weight=weight, tracking=13)
    W = x + ww + em * PAD  # leaves room for the 1.2 px keyline on the N
    d = Doc(W, em, "HULLDOWN battle logo, compact")
    draw_emblem(d, 0, 0, em, detail="flat")
    d.keyline(word, 1.2)
    d.path(word, BONE)
    return d.save(path)
