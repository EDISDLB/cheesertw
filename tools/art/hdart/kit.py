"""Shared 2D construction kit for the gameplay / UI icon groups.

Three rendering styles sit on top of svgdoc's grammar (keyline, plate, inlay, engrave):

* `symbol(d, sil, mat)`   bevelled material symbol (flat front), like the class and faction marks.
* `glyph(d, g)`           monochrome white glyph + ink keyline, for ImageColor3 tinting (UI, HUD).
* objects                 3/4-view physical objects, see solid.py.

Plus reusable motifs (arrows, rings, wrench, flame, eye, fracture marks, frames) so the same idea is
drawn the same way in every group.
"""

from __future__ import annotations

import math

from shapely.geometry import LineString

from . import geom as G
from .svgdoc import Doc
from .tokens import INK, MATERIALS

KEY = 2.0
BEV = 2.0
WHITE = "#FFFFFF"
SW = 6.0  # UI glyph stroke weight on the 64 grid (2.25 px at 24, 1.5 px at 16)


# ---------------------------------------------------------------------------
# Safety
# ---------------------------------------------------------------------------
def check(g, name: str, lo: float = 6.0, hi: float = 58.0, w: float = 64, h: float = 64):
    """Silhouette must sit in the live area (safe margin 4 + 2 px keyline)."""
    x0, y0, x1, y1 = g.bounds
    hx, hy = hi + (w - 64), hi + (h - 64)
    if x0 < lo - 0.06 or y0 < lo - 0.06 or x1 > hx + 0.06 or y1 > hy + 0.06:
        raise ValueError(f"{name}: silhouette {tuple(round(v, 1) for v in (x0, y0, x1, y1))} leaves live area")


def fit(g, *parts, box=(6.0, 6.0, 58.0, 58.0)):
    """Uniformly scale + centre g (and parts) into box. Returns (g, *parts)."""
    x0, y0, x1, y1 = g.bounds
    bx0, by0, bx1, by1 = box
    s = min((bx1 - bx0) / (x1 - x0), (by1 - by0) / (y1 - y0))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    tx, ty = (bx0 + bx1) / 2, (by0 + by1) / 2

    def tf(q):
        return G.T(G.S(q, s, s, origin=(cx, cy)), tx - cx, ty - cy)

    return (tf(g), *[tf(p) for p in parts])


def shrink_to(g, *parts, box=(6.0, 6.0, 58.0, 58.0)):
    """Like fit(), but only scales down (never enlarges)."""
    x0, y0, x1, y1 = g.bounds
    bx0, by0, bx1, by1 = box
    if x0 >= bx0 - 1e-6 and y0 >= by0 - 1e-6 and x1 <= bx1 + 1e-6 and y1 <= by1 + 1e-6:
        return (g, *parts)
    return fit(g, *parts, box=box)


# ---------------------------------------------------------------------------
# Rendering styles
# ---------------------------------------------------------------------------
def symbol(d: Doc, sil, mat: str, bevel: float = BEV, key: float = KEY):
    d.keyline(sil, key)
    return d.plate(sil, mat, bevel=bevel)


def glyph(d: Doc, g, color: str = WHITE, key: float = KEY):
    """White (tintable) glyph: ink keyline + flat fill. Holes in g stay open (the keyline lines them)."""
    d.keyline(g, key)
    d.path(g, color)


def glyph_cut(d: Doc, g, cut, color: str = WHITE, key: float = KEY, gap: float = 2.0):
    """Glyph with an overlapping secondary shape separated by an ink gap (e.g. a badge on a person).
    `cut` is drawn on top; g is cut back by `gap` around it."""
    base = G.diff(g, G.grow(cut, gap))
    d.keyline(G.union(base, cut), key)
    d.path(base, color)
    d.path(cut, color)


def rim_keyline(d: Doc, sil, mat: str = "gold", rim: float = 1.8, outer: float = 1.3, key: float = KEY):
    """Special (premium) treatment: ink keyline, a bevelled metal rim, then an outer ink line.
    Adds rim + outer px around the normal keyline, so the silhouette must sit that much further in."""
    d.keyline(sil, key + rim + outer)
    d.plate(G.grow(sil, key + rim), mat, bevel=rim * 0.6, face_grad=False)
    d.keyline(sil, key)


# ---------------------------------------------------------------------------
# Primitive motifs
# ---------------------------------------------------------------------------
def stroke(pts, w=SW, cap="flat", closed=False, mitre=4.0):
    if closed:
        pts = list(pts) + [pts[0], pts[1]]
    cap_style = {"flat": 2, "square": 3, "round": 1}[cap]
    return LineString(pts).buffer(w / 2.0, cap_style=cap_style, join_style=2, mitre_limit=mitre)


def ring(cx, cy, r, w=SW, n=96):
    return G.diff(G.circle(cx, cy, r + w / 2, n=n), G.circle(cx, cy, r - w / 2, n=n))


def oct_ring(cx, cy, r, w=SW, c_frac=0.29):
    """Chamfered (octagonal) ring of outer half-size r + w/2."""
    a = r + w / 2
    b = r - w / 2
    return G.diff(G.chamfer_all(cx - a, cy - a, cx + a, cy + a, a * c_frac * 2),
                  G.chamfer_all(cx - b, cy - b, cx + b, cy + b, max(b * c_frac * 2 - w * 0.4, 0.5)))


def arc(cx, cy, r, w, a0, a1, n=48):
    """Arc band centred on radius r. Angles in degrees, 0 = right, clockwise (screen)."""
    return G.arc_band(cx, cy, r + w / 2, r - w / 2, a0, a1, n=n)


def pt(cx, cy, r, ang):
    a = math.radians(ang)
    return (cx + r * math.cos(a), cy + r * math.sin(a))


def head(tip, ang, length, half):
    """Triangular arrowhead with its tip at `tip`, pointing along angle `ang` (deg, screen)."""
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    bx, by = tip[0] - ux * length, tip[1] - uy * length
    px, py = -uy, ux
    return G.poly([tip, (bx + px * half, by + py * half), (bx - px * half, by - py * half)])


def arrow(p0, p1, w=SW, head_len=None, head_half=None):
    """Straight arrow from p0 to p1 (tip at p1)."""
    hl = head_len if head_len is not None else w * 2.2
    hh = head_half if head_half is not None else w * 1.75
    ang = math.degrees(math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
    a = math.radians(ang)
    sx, sy = p1[0] - math.cos(a) * (hl - 0.5), p1[1] - math.sin(a) * (hl - 0.5)
    return G.union(G.thick_line(p0, (sx, sy), w), head(p1, ang, hl, hh))


def arc_arrow(cx, cy, r, w, a0, a1, head_len=None, head_half=None, n=48):
    """Arc from a0 to a1 (deg, clockwise positive) with an arrowhead at a1."""
    hl = head_len if head_len is not None else w * 2.0
    hh = head_half if head_half is not None else w * 1.6
    sign = 1 if a1 > a0 else -1
    da = math.degrees(hl / r) * sign
    band = arc(cx, cy, r, w, a0, a1 - da * 0.85, n=n)
    tip = pt(cx, cy, r, a1)
    tang = a1 + 90 * sign
    # head base centred on the arc
    base_c = pt(cx, cy, r, a1 - da)
    ang = math.degrees(math.atan2(tip[1] - base_c[1], tip[0] - base_c[0]))
    h = head(tip, ang, math.hypot(tip[0] - base_c[0], tip[1] - base_c[1]), hh)
    _ = tang
    return G.union(band, h)


def zigzag(p0, p1, amp, n, phase=1):
    """Zig-zag polyline points from p0 to p1 with n segments and amplitude amp."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy)
    ux, uy = dx / ln, dy / ln
    px, py = -uy, ux
    out = []
    for i in range(n + 1):
        t = i / n
        o = 0 if i in (0, n) else amp * (phase if i % 2 else -phase)
        out.append((p0[0] + dx * t + px * o, p0[1] + dy * t + py * o))
    return out


def fracture(p0, p1, gap=2.6, amp=3.0, n=4):
    """A jagged break line (as a cut-out shape) from p0 to p1."""
    return stroke(zigzag(p0, p1, amp, n), gap, cap="square", mitre=6.0)


def split(sil, p0, p1, gap=2.8, amp=3.2, n=4, shift=1.2):
    """Break a silhouette in two along a jagged line and push the halves apart by `shift`.
    Returns (piece_a, piece_b, offset_a, offset_b) where offsets are the translations applied."""
    cut = fracture(p0, p1, gap, amp, n)
    rest = G.diff(sil, cut)
    pieces = G.polys(rest)
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln, dx / ln  # normal to the break
    a, b = [], []
    for pc in pieces:
        c = pc.centroid
        side = (c.x - p0[0]) * nx + (c.y - p0[1]) * ny
        (a if side > 0 else b).append(pc)
    oa = (nx * shift / 2, ny * shift / 2)
    ob = (-nx * shift / 2, -ny * shift / 2)
    return G.T(G.union(a), *oa), G.T(G.union(b), *ob), oa, ob


def plus(cx, cy, size, w, chamfer=0.0):
    h, t = size / 2, w / 2
    g = G.union(G.rect(cx - h, cy - t, cx + h, cy + t), G.rect(cx - t, cy - h, cx + t, cy + h))
    return g


def xmark(cx, cy, size, w):
    h = size / 2
    return G.union(G.thick_line((cx - h, cy - h), (cx + h, cy + h), w), G.thick_line((cx - h, cy + h), (cx + h, cy - h), w))


def checkmark(cx, cy, size, w):
    s = size / 2
    pts = [(cx - s, cy + s * 0.05), (cx - s * 0.32, cy + s * 0.7), (cx + s, cy - s * 0.62)]
    return stroke(pts, w, cap="flat", mitre=3.0)


# ---------------------------------------------------------------------------
# Shared pictograms (drawn the same way in every group)
# ---------------------------------------------------------------------------
def wrench(cx, cy, length, w, ang=-45.0, jaw=None):
    """Open-end wrench along angle `ang`; jaw at the far (upper-right for -45) end, handle chamfered."""
    jaw = jaw or w * 2.6
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    p0 = (cx - ux * length / 2, cy - uy * length / 2)
    p1 = (cx + ux * length / 2, cy + uy * length / 2)
    handle = G.thick_line(p0, (cx + ux * (length / 2 - jaw * 0.6), cy + uy * (length / 2 - jaw * 0.6)), w)
    # head: octagon with an open slot pointing outward along the axis
    hd = G.ngon(p1[0], p1[1], jaw * 0.62, 8, rot_deg=22.5)
    slot_w = jaw * 0.42
    slot = G.thick_line((p1[0] - ux * jaw * 0.05, p1[1] - uy * jaw * 0.05), (p1[0] + ux * jaw, p1[1] + uy * jaw), slot_w)
    hd = G.diff(hd, slot)
    # tail end: small chamfered butt
    return G.union(handle, hd)


def flame(cx, base_y, h, w):
    """Angular three-tongue flame (faceted, no curves). Returns (outer, inner core)."""
    k = h / 40.0
    pts = [(-10, 0), (-13, -9), (-11, -17), (-7, -22), (-6.5, -15), (-3, -12), (-4, -24), (1, -34), (3, -40),
           (5, -30), (8, -23), (9.5, -27), (13, -19), (13.5, -9), (10, 0)]
    sx = w / 26.0
    outer = G.poly([(cx + x * sx, base_y + y * k) for x, y in pts])
    core_pts = [(-5, 0), (-6.5, -7), (-3.5, -13), (-1.5, -9), (1, -19), (4, -12), (6, -7), (5, 0)]
    core = G.poly([(cx + x * sx, base_y + y * k) for x, y in core_pts])
    return outer, core


def eye(cx, cy, w, h, pupil):
    """Almond eye (two arcs) with a round pupil hole. Returns (almond, pupil)."""
    a, b = w / 2, h / 2
    c = (a * a - b * b) / (2 * b)
    R = c + b
    alm = G.inter(G.circle(cx, cy + c, R, n=180), G.circle(cx, cy - c, R, n=180))
    return alm, G.circle(cx, cy, pupil, n=48)


def helmet(cx, top, w, h):
    """Padded tanker helmet (front view): dome, ear flaps, brow ridge. Returns (shape, ribs, brow)."""
    r = w / 2
    dome = G.inter(G.circle(cx, top + r, r, n=120), G.rect(cx - r - 1, top - 1, cx + r + 1, top + r))
    flaps_h = h - r
    body = G.union(dome, G.rect(cx - r, top + r - 0.5, cx + r, top + r + flaps_h * 0.35))
    flap_w = w * 0.24
    flaps = G.union(G.cbox(cx - r, top + r, cx - r + flap_w, top + h, 0, 0, flap_w * 0.45, flap_w * 0.2),
                    G.cbox(cx + r - flap_w, top + r, cx + r, top + h, 0, 0, flap_w * 0.2, flap_w * 0.45))
    shape = G.union(body, flaps)
    ribs = G.union([G.rect(cx + dx - w * 0.035, top + w * 0.1, cx + dx + w * 0.035, top + r * 0.95)
                    for dx in (-w * 0.2, 0, w * 0.2)])
    brow = G.rect(cx - r + flap_w * 0.6, top + r + flaps_h * 0.05, cx + r - flap_w * 0.6, top + r + flaps_h * 0.32)
    return shape, ribs, brow


def person(cx, top, size):
    """Abstract crew figure for social UI: helmet-head + shoulders (no face). Returns geometry."""
    s = size / 40.0
    headr = 8.0 * s
    head_c = (cx, top + headr)
    hd = G.union(G.inter(G.circle(*head_c, headr, n=72), G.rect(cx - 20 * s, top, cx + 20 * s, head_c[1])),
                 G.cbox(cx - headr, head_c[1] - 0.2, cx + headr, head_c[1] + headr * 0.95, 0, 0, headr * 0.55, headr * 0.55))
    sh_top = top + headr * 2 + 2.4 * s
    shoulders = G.cbox(cx - 16 * s, sh_top, cx + 16 * s, top + 40 * s, 8 * s, 8 * s, 0, 0)
    return G.union(hd, shoulders), hd, shoulders


def shell_flat(cx, base_y, h, w, nose="ogive"):
    """Flat side view of a shell (UI glyph): case + projectile. Returns geometry."""
    r = w / 2
    case_h = h * 0.42
    rim = G.rect(cx - r * 1.08, base_y - h * 0.06, cx + r * 1.08, base_y)
    case = G.rect(cx - r, base_y - case_h, cx + r, base_y - h * 0.05)
    pr = r * 0.86
    body_top = base_y - case_h - h * 0.16
    body = G.rect(cx - pr, body_top, cx + pr, base_y - case_h + 0.01)
    L = h - case_h - h * 0.16
    pts = []
    rho = (pr * pr + L * L) / (2 * pr)
    for i in range(0, 21):
        x = L * i / 20
        rr = math.sqrt(max(rho * rho - x * x, 0)) - (rho - pr)
        pts.append((cx + max(rr, 0), body_top - x))
    pts2 = [(2 * cx - px, py) for px, py in reversed(pts)]
    nose_g = G.poly(pts + pts2)
    return G.union(rim, case, body, nose_g)


def corner_brackets(x0, y0, x1, y1, arm, w, chamfer=None):
    """Four L-shaped corner brackets (target-lock / frame language). Outer corners chamfered."""
    c = chamfer if chamfer is not None else w * 0.9
    out = []
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x1, y1, -1, -1), (x0, y1, 1, -1)):
        pts = [(cx, cy + sy * c), (cx + sx * c, cy), (cx + sx * arm, cy), (cx + sx * arm, cy + sy * w),
               (cx + sx * w, cy + sy * w), (cx + sx * w, cy + sy * arm), (cx, cy + sy * arm)]
        out.append(G.poly(pts).buffer(0))
    return G.union(out)
