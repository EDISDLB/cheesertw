"""Geometry helpers on top of shapely: primitives, transforms, bevels and SVG path output."""

from __future__ import annotations

import math
from typing import Iterable

from shapely import affinity
from shapely.geometry import GeometryCollection, LineString, MultiPolygon, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

MITRE = 2  # shapely join_style for mitre

EMPTY = Polygon()


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------
def rect(x0, y0, x1, y1):
    return box(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))


def cbox(x0, y0, x1, y1, tl=0.0, tr=0.0, br=0.0, bl=0.0):
    """Axis-aligned box with 45-degree chamfers per corner (tl, tr, br, bl).
    Chamfers are clamped so adjacent ones never overlap (they may meet in a point)."""
    w, h = abs(x1 - x0), abs(y1 - y0)
    lim = min(w, h) / 2.0 - 0.01
    tl, tr, br, bl = (min(c, lim) if c else 0.0 for c in (tl, tr, br, bl))
    pts = []
    pts += [(x0, y0 + tl), (x0 + tl, y0)] if tl else [(x0, y0)]
    pts += [(x1 - tr, y0), (x1, y0 + tr)] if tr else [(x1, y0)]
    pts += [(x1, y1 - br), (x1 - br, y1)] if br else [(x1, y1)]
    pts += [(x0 + bl, y1), (x0, y1 - bl)] if bl else [(x0, y1)]
    return Polygon(pts)


def chamfer_all(x0, y0, x1, y1, c):
    return cbox(x0, y0, x1, y1, c, c, c, c)


def poly(pts):
    return Polygon(pts)


def circle(cx, cy, r, n=72):
    return Point(cx, cy).buffer(r, quad_segs=max(4, n // 4))


def ngon(cx, cy, r, n, rot_deg=0.0):
    """Regular polygon; rot_deg=0 puts the first vertex straight up."""
    pts = []
    for i in range(n):
        a = math.radians(rot_deg + 360.0 * i / n - 90.0)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return Polygon(pts)


def thick_line(p0, p1, w, cap="flat"):
    cap_style = {"flat": 2, "square": 3, "round": 1}[cap]
    return LineString([p0, p1]).buffer(w / 2.0, cap_style=cap_style, join_style=MITRE)


def polyline(pts, w, cap="flat", mitre_limit=4.0):
    cap_style = {"flat": 2, "square": 3, "round": 1}[cap]
    return LineString(pts).buffer(w / 2.0, cap_style=cap_style, join_style=MITRE, mitre_limit=mitre_limit)


def arc_band(cx, cy, r_out, r_in, a0_deg, a1_deg, n=48):
    """Annular sector. Angles in degrees, 0 = +x (right), positive = clockwise on screen (y down)."""
    outer = []
    inner = []
    for i in range(n + 1):
        a = math.radians(a0_deg + (a1_deg - a0_deg) * i / n)
        outer.append((cx + r_out * math.cos(a), cy + r_out * math.sin(a)))
        inner.append((cx + r_in * math.cos(a), cy + r_in * math.sin(a)))
    return Polygon(outer + inner[::-1])


def chevron(cx, top_y, half_w, height, thick, flat_tip=0.0):
    """Upward-pointing chevron (^) stroke. Apex at (cx, top_y); arms reach (cx +/- half_w, top_y + height)."""
    t = thick
    # Arms are the outer edge shifted down by t, so the inner apex sits t below the outer apex.
    inner_apex_y = top_y + t
    pts = [
        (cx - flat_tip / 2, top_y),
        (cx + flat_tip / 2, top_y),
        (cx + half_w, top_y + height),
        (cx + half_w, top_y + height + t),
        (cx + flat_tip / 2, inner_apex_y) if flat_tip else (cx, inner_apex_y),
        (cx - flat_tip / 2, inner_apex_y) if flat_tip else (cx, inner_apex_y),
        (cx - half_w, top_y + height + t),
        (cx - half_w, top_y + height),
    ]
    out = Polygon(pts)
    return out.buffer(0)


def gear(cx, cy, r_root, r_tip, teeth, tooth_frac=0.5, rot_deg=0.0, tip_frac=None):
    """Gear outline. tooth_frac = angular fraction of pitch occupied by a tooth at the root,
    tip_frac = fraction at the tip (trapezoid teeth)."""
    if tip_frac is None:
        tip_frac = tooth_frac * 0.7
    pts = []
    pitch = 360.0 / teeth
    for i in range(teeth):
        a = rot_deg + i * pitch - 90.0
        half_root = tooth_frac * pitch / 2
        half_tip = tip_frac * pitch / 2
        for ang, r in (
            (a - half_root, r_root),
            (a - half_tip, r_tip),
            (a + half_tip, r_tip),
            (a + half_root, r_root),
        ):
            t = math.radians(ang)
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
        # root arc to next tooth
        nxt = a + pitch - half_root
        steps = 3
        for s in range(1, steps):
            t = math.radians(a + half_root + (nxt - (a + half_root)) * s / steps)
            pts.append((cx + r_root * math.cos(t), cy + r_root * math.sin(t)))
    return Polygon(pts)


# ---------------------------------------------------------------------------
# Boolean helpers / transforms
# ---------------------------------------------------------------------------
def union(*geoms):
    flat = []
    for g in geoms:
        if isinstance(g, (list, tuple)):
            flat.extend(g)
        else:
            flat.append(g)
    return unary_union([g for g in flat if g is not None and not g.is_empty])


def diff(a, *bs):
    out = a
    for b in bs:
        if b is not None and not b.is_empty:
            out = out.difference(b)
    return out


def inter(a, b):
    return a.intersection(b)


def T(g, dx=0.0, dy=0.0):
    return affinity.translate(g, dx, dy)


def S(g, sx, sy=None, origin=(0, 0)):
    return affinity.scale(g, sx, sx if sy is None else sy, origin=origin)


def R(g, deg, origin=(0, 0)):
    return affinity.rotate(g, deg, origin=origin)


def mirror_x(g, cx):
    return affinity.scale(g, -1, 1, origin=(cx, 0))


def mirror_y(g, cy):
    return affinity.scale(g, 1, -1, origin=(0, cy))


def sym_x(g, cx):
    """Union of g and its mirror around vertical line x=cx."""
    return union(g, mirror_x(g, cx))


def fit(g, x0, y0, x1, y1, align="center"):
    """Uniformly scale and move g so it fits the box."""
    bx0, by0, bx1, by1 = g.bounds
    s = min((x1 - x0) / (bx1 - bx0), (y1 - y0) / (by1 - by0))
    g = affinity.scale(g, s, s, origin=(bx0, by0))
    g = affinity.translate(g, x0 - bx0, y0 - by0)
    bx0, by0, bx1, by1 = g.bounds
    dx = ((x1 - x0) - (bx1 - bx0)) / 2 if align in ("center", "hcenter") else 0
    dy = ((y1 - y0) - (by1 - by0)) / 2 if align in ("center", "vcenter") else 0
    return affinity.translate(g, dx, dy)


def polys(g) -> list[Polygon]:
    if g is None or g.is_empty:
        return []
    if isinstance(g, Polygon):
        return [g]
    if isinstance(g, (MultiPolygon, GeometryCollection)):
        out = []
        for sub in g.geoms:
            out.extend(polys(sub))
        return out
    return []


def clean(g):
    return unary_union(polys(g.buffer(0)))


def grow(g, d, mitre_limit=2.0):
    return g.buffer(d, join_style=MITRE, mitre_limit=mitre_limit)


def shrink(g, d, mitre_limit=2.0):
    return g.buffer(-d, join_style=MITRE, mitre_limit=mitre_limit)


# ---------------------------------------------------------------------------
# Bevel facets
# ---------------------------------------------------------------------------
LIGHT = (-1.0 / math.sqrt(2), -1.0 / math.sqrt(2))  # light comes from the top-left


def _ring_facets(coords, b, out, lit_thr, light):
    pts = list(coords)[:-1]
    n = len(pts)
    if n < 3:
        return
    normals = []
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy) or 1e-9
        normals.append((dy / ln, -dx / ln))  # outward for positively-oriented ring
    inset = []
    for i in range(n):
        n1 = normals[i - 1]
        n2 = normals[i]
        d = 1.0 + n1[0] * n2[0] + n1[1] * n2[1]
        d = max(d, 0.35)
        inset.append((pts[i][0] - b * (n1[0] + n2[0]) / d, pts[i][1] - b * (n1[1] + n2[1]) / d))
    for i in range(n):
        j = (i + 1) % n
        q = Polygon([pts[i], pts[j], inset[j], inset[i]])
        if not q.is_valid:
            q = q.buffer(0)
        dot = normals[i][0] * light[0] + normals[i][1] * light[1]
        key = "hi" if dot > lit_thr else ("lo" if dot < -lit_thr else "mid")
        out[key].append(q)


def bevel(g, b, lit_thr=0.30, light=LIGHT):
    """Split shape g into bevel facets. Returns dict(hi, mid, lo, face) geometries."""
    out = {"hi": [], "mid": [], "lo": []}
    for p in polys(g):
        p = orient(p, sign=1.0)
        _ring_facets(p.exterior.coords, b, out, lit_thr, light)
        for ring in p.interiors:
            _ring_facets(ring.coords, b, out, lit_thr, light)
    face = shrink(g, b)
    res = {}
    for k, lst in out.items():
        u = unary_union(lst) if lst else EMPTY
        res[k] = u.intersection(g).difference(face) if not u.is_empty else EMPTY
    res["face"] = face
    return res


# ---------------------------------------------------------------------------
# SVG path output
# ---------------------------------------------------------------------------
def _fmt(v: float) -> str:
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    if s == "-0":
        s = "0"
    return s


def _ring_d(coords) -> str:
    pts = list(coords)
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    # drop near-duplicate consecutive points
    clean_pts = []
    for p in pts:
        if not clean_pts or abs(p[0] - clean_pts[-1][0]) > 0.004 or abs(p[1] - clean_pts[-1][1]) > 0.004:
            clean_pts.append(p)
    if len(clean_pts) < 3:
        return ""
    parts = [f"M{_fmt(clean_pts[0][0])} {_fmt(clean_pts[0][1])}"]
    for x, y in clean_pts[1:]:
        parts.append(f"L{_fmt(x)} {_fmt(y)}")
    return "".join(parts) + "Z"


def to_d(g, simplify: float = 0.02) -> str:
    out = []
    for p in polys(g):
        if simplify:
            p = p.simplify(simplify, preserve_topology=True)
        if p.is_empty or p.area < 0.01:
            continue
        out.append(_ring_d(p.exterior.coords))
        for ring in p.interiors:
            out.append(_ring_d(ring.coords))
    return "".join(out)


def points_iter(g) -> Iterable[tuple[float, float]]:
    for p in polys(g):
        yield from p.exterior.coords
