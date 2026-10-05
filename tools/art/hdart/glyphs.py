"""HULLDOWN Stencil - the brand's constructed letterforms.

Geometric, all-straight construction: every curve of a normal typeface is replaced by a 45-degree
chamfer (round letters are octagons), and stencil bridges break the counters of O/D/A/R and the
stem joints of D/E. Glyphs are built on a 100-unit cap height and returned as shapely geometry, so
they can be bevelled, inlaid or engraved like any other icon shape. No font files involved.
"""

from __future__ import annotations

from dataclasses import dataclass

from .geom import EMPTY, S, T, cbox, diff, inter, poly, rect, union

CAP = 100.0


@dataclass(frozen=True)
class Weight:
    S: float  # vertical stem width
    T: float  # horizontal stroke height
    C: float  # big chamfer (round letters)
    cs: float  # small corner chamfer (square corners)
    G: float  # stencil gap width (0 disables stencil bridges)
    D: float  # horizontal width of diagonal strokes
    wscale: float = 1.0  # global width factor


HEAVY = Weight(S=24, T=21, C=27, cs=5, G=6.5, D=30)
BOLD = Weight(S=20, T=18, C=24, cs=4, G=6, D=26)
MEDIUM = Weight(S=15, T=13.5, C=20, cs=3, G=5, D=20)
NUMERAL = Weight(S=24, T=21, C=27, cs=4, G=0, D=30)  # roman numerals on badges: no stencil gaps


def _inner_c(w: Weight) -> float:
    return max(w.C - 0.42 * (w.S + w.T) / 2, 3.0)


def _v_shape(x, width, w: Weight, top=0.0, bottom=CAP, flat=None):
    """Solid V: two diagonals meeting in a flat foot."""
    F = w.D * 0.62 if flat is None else flat
    h = bottom - top
    cx = x + width / 2
    # inner apex height where the two inner edges meet
    run = width / 2 - F / 2
    yi = top + h * (width / 2 - w.D) / run if run > 0 else bottom
    return poly(
        [
            (x, top),
            (x + w.D, top),
            (cx, yi),
            (x + width - w.D, top),
            (x + width, top),
            (cx + F / 2, bottom),
            (cx - F / 2, bottom),
        ]
    )


def g_H(w: Weight):
    W = 76 * w.wscale
    l = cbox(0, 0, w.S, CAP, w.cs, 0, 0, w.cs)
    r = cbox(W - w.S, 0, W, CAP, 0, w.cs, w.cs, 0)
    bar = rect(w.S - 1, 50 - w.T / 2, W - w.S + 1, 50 + w.T / 2)
    return union(l, r, bar), W


def g_U(w: Weight):
    # The counter keeps a wide flat floor (small inner chamfers), otherwise heavy weights read as 'V'.
    W = 76 * w.wscale
    co = w.C * 0.72
    outer = cbox(0, 0, W, CAP, w.cs, w.cs, co, co)
    ci = max(min(co - 0.42 * (w.S + w.T) / 2, (W - 2 * w.S) * 0.22), 2.5)
    inner = cbox(w.S, -1, W - w.S, CAP - w.T, 0, 0, ci, ci)
    return diff(outer, inner), W


def g_L(w: Weight):
    W = 60 * w.wscale
    g = poly(
        [
            (0, w.cs),
            (w.cs, 0),
            (w.S, 0),
            (w.S, CAP - w.T),
            (W, CAP - w.T),
            (W, CAP - w.cs),
            (W - w.cs, CAP),
            (w.cs, CAP),
            (0, CAP - w.cs),
        ]
    )
    return g, W


def g_D(w: Weight):
    W = 76 * w.wscale
    outer = cbox(0, 0, W, CAP, w.cs, w.C, w.C, w.cs)
    ci = _inner_c(w)
    inner = cbox(w.S, w.T, W - w.S, CAP - w.T, 0, ci, ci, 0)
    g = diff(outer, inner)
    if w.G:
        g = diff(g, rect(w.S, -1, w.S + w.G, w.T + 1), rect(w.S, CAP - w.T - 1, w.S + w.G, CAP + 1))
    return g, W


def g_O(w: Weight):
    W = 78 * w.wscale
    outer = cbox(0, 0, W, CAP, w.C, w.C, w.C, w.C)
    ci = _inner_c(w)
    inner = cbox(w.S, w.T, W - w.S, CAP - w.T, ci, ci, ci, ci)
    g = diff(outer, inner)
    if w.G:
        g = diff(g, rect(W / 2 - w.G / 2, -1, W / 2 + w.G / 2, w.T + 1))
        g = diff(g, rect(W / 2 - w.G / 2, CAP - w.T - 1, W / 2 + w.G / 2, CAP + 1))
    return g, W


def g_C(w: Weight):
    W = 70 * w.wscale
    outer = cbox(0, 0, W, CAP, w.C, w.C, w.C, w.C)
    ci = _inner_c(w)
    inner = cbox(w.S, w.T, W - w.S, CAP - w.T, ci, ci, ci, ci)
    g = diff(outer, inner, rect(W - w.S - 1, w.T + 4, W + 1, CAP - w.T - 4))
    return g, W


def g_G(w: Weight):
    W = 76 * w.wscale
    outer = cbox(0, 0, W, CAP, w.C, w.C, w.C, w.C)
    ci = _inner_c(w)
    inner = cbox(w.S, w.T, W - w.S, CAP - w.T, ci, ci, ci, ci)
    g = diff(outer, inner, rect(W - w.S - 1, w.T + 4, W + 1, 50 - w.T / 2))
    spur = rect(W * 0.46, 50 - w.T / 2, W, 50 + w.T / 2)
    g = union(g, inter(spur, outer))
    return g, W


def _cross(p1, d1, p2, d2):
    """Intersection of the lines p1 + t*d1 and p2 + s*d2."""
    det = -d1[0] * d2[1] + d1[1] * d2[0]
    t = (-(p2[0] - p1[0]) * d2[1] + (p2[1] - p1[1]) * d2[0]) / det
    return (p1[0] + t * d1[0], p1[1] + t * d1[1])


def g_W(w: Weight):
    """Four parallel-sided arms of equal slope. The middle apex is lowered to 24 % of the cap height
    and cut flat to the same width as the feet, so both V counters stay open at heavy weights."""
    W = 124 * w.wscale
    D = w.D * 0.92  # horizontal arm width (perpendicular weight ~= stem width)
    F = w.D * 0.62  # flat width of the feet and of the middle apex
    ya = 24.0
    cx = W / 2
    xr_top = cx - F / 2 + D  # right edge of the inner-left arm at the apex height
    p1 = (xr_top - F) * CAP / (2 * CAP - ya)  # left foot x, chosen so all four arms share one slope
    u = (p1, CAP)  # outer-left arm direction
    v = (p1 + F - xr_top, CAP - ya)  # inner-left arm direction
    c1 = _cross((D, 0), u, (cx - F / 2, ya), v)  # tip of the left V counter
    c3 = (cx, ya + (cx - xr_top) / v[0] * v[1])  # tip of the middle counter
    pts = [(0, 0), (D, 0), c1, (cx - F / 2, ya), (cx + F / 2, ya), (W - c1[0], c1[1]), (W - D, 0), (W, 0),
           (W - p1, CAP), (W - p1 - F, CAP), c3, (p1 + F, CAP), (p1, CAP)]
    return poly(pts), W


def g_N(w: Weight):
    # Wider than H with a slightly lighter diagonal so both counters stay open; the whole letter is
    # clipped to a chamfered box so the diagonal never pokes past the stems' corner chamfers.
    W = 82 * w.wscale
    D = w.D * 0.9
    outer = cbox(0, 0, W, CAP, w.cs, w.cs, w.cs, w.cs)
    l = rect(0, 0, w.S, CAP)
    r = rect(W - w.S, 0, W, CAP)
    diag = poly([(0, 0), (D, 0), (W, CAP), (W - D, CAP)])
    return inter(union(l, r, diag), outer), W


def g_A(w: Weight):
    W = 78 * w.wscale
    big = w.C * 1.35
    bar_y = 60
    outer = poly([(0, CAP), (0, big), (big, 0), (W - big, 0), (W, big), (W, CAP), (W - w.S, CAP),
                  (W - w.S, bar_y + w.T), (w.S, bar_y + w.T), (w.S, CAP)])
    ci = max(big - 0.42 * (w.S + w.T) / 2, 3)
    counter = cbox(w.S, w.T, W - w.S, bar_y, ci, ci, 0, 0)
    g = diff(outer, counter)
    if w.G:
        g = diff(g, rect(W / 2 - w.G / 2, -1, W / 2 + w.G / 2, w.T + 1))
    return g, W


def g_M(w: Weight):
    W = 96 * w.wscale
    l = cbox(0, 0, w.S, CAP, w.cs, 0, 0, w.cs)
    r = cbox(W - w.S, 0, W, CAP, 0, w.cs, w.cs, 0)
    v = _v_shape(0, W, w, top=0, bottom=66, flat=w.D * 0.5)
    return union(l, r, v), W


def g_E(w: Weight):
    W = 62 * w.wscale
    stem = cbox(0, 0, w.S, CAP, w.cs, 0, 0, w.cs)
    g0 = w.G
    top = cbox(w.S + g0, 0, W, w.T, 0, w.cs, 0, 0)
    mid = rect(w.S + g0, 50 - w.T / 2, W * 0.86, 50 + w.T / 2)
    bot = cbox(w.S + g0, CAP - w.T, W, CAP, 0, 0, w.cs, 0)
    if not w.G:
        top = union(top, rect(w.S - 1, 0, w.S + 1, w.T))
        bot = union(bot, rect(w.S - 1, CAP - w.T, w.S + 1, CAP))
        mid = union(mid, rect(w.S - 1, 50 - w.T / 2, w.S + 1, 50 + w.T / 2))
    return union(stem, top, mid, bot), W


def g_R(w: Weight):
    W = 76 * w.wscale
    stem = cbox(0, 0, w.S, CAP, w.cs, 0, 0, w.cs)
    bowl_b = 58
    c = w.C * 0.8
    outer = cbox(0, 0, W, bowl_b, w.cs, c, c, 0)
    ci = max(c - 0.42 * (w.S + w.T) / 2, 2.5)
    inner = cbox(w.S, w.T, W - w.S, bowl_b - w.T, 0, ci, ci, 0)
    bowl = diff(outer, inner)
    if w.G:
        bowl = diff(bowl, rect(w.S, -1, w.S + w.G, w.T + 1))
    leg = poly([(W * 0.40, bowl_b - w.T), (W * 0.40 + w.D, bowl_b - w.T), (W, CAP), (W - w.D, CAP)])
    leg = inter(leg, rect(0, bowl_b - w.T, W, CAP))
    return union(stem, bowl, leg), W


def g_I(w: Weight):
    W = w.S
    return cbox(0, 0, W, CAP, w.cs, w.cs, w.cs, w.cs), W


def g_V(w: Weight):
    W = 76 * w.wscale
    return _v_shape(0, W, w, flat=w.D * 0.75), W


def g_X(w: Weight):
    W = 76 * w.wscale
    a = poly([(0, 0), (w.D, 0), (W, CAP), (W - w.D, CAP)])
    b = poly([(W - w.D, 0), (W, 0), (w.D, CAP), (0, CAP)])
    return union(a, b), W


def g_dot(w: Weight):
    s = w.T * 0.9
    return rect(0, 50 - s / 2, s, 50 + s / 2), s


def g_space(w: Weight):
    return EMPTY, 30 * w.wscale


GLYPHS = {
    "H": g_H, "U": g_U, "L": g_L, "D": g_D, "O": g_O, "C": g_C, "G": g_G, "W": g_W, "N": g_N,
    "A": g_A, "M": g_M, "E": g_E, "R": g_R, "I": g_I, "V": g_V, "X": g_X, "·": g_dot, " ": g_space,
}

# Optical kerning pairs (in cap units); negative pulls letters together.
KERN = {("L", "D"): -6, ("L", "L"): 0, ("O", "W"): -6, ("W", "N"): 0, ("D", "O"): 0, ("A", "G"): -2, ("R", "A"): -2}


def text(s: str, weight: Weight = HEAVY, tracking: float = 12.0, cap: float = 100.0, x: float = 0.0,
         y: float = 0.0):
    """Lay out a string. Returns (geometry, width) with the cap top at y and left edge at x."""
    out = []
    pen = 0.0
    prev = None
    for ch in s:
        fn = GLYPHS[ch]
        g, adv = fn(weight)
        if prev is not None:
            pen += KERN.get((prev, ch), 0)
        if not g.is_empty:
            out.append(T(g, pen, 0))
        pen += adv + tracking
        prev = ch
    width = pen - tracking
    geom = union(out)
    k = cap / CAP
    geom = S(geom, k, k, origin=(0, 0))
    geom = T(geom, x, y)
    return geom, width * k
