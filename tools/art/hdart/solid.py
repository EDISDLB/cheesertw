"""Faceted-solid renderer for physical-object icons on the fixed 3/4 camera (proj.py).

Physical objects (shells, consumables, equipment) are assembled from a few primitive solids:
extruded polygons (`extrude`, `prism`, `box`) and bodies of revolution (`revolve`). Each solid is
projected with the house camera (yaw 22 deg, elevation 38 deg, orthographic), back faces are culled
and the visible faces are flat-shaded into the material's tones:

* upward faces ('top') take the lit gradient plus one highlight rim on their front edge, like the
  currency objects;
* flat sides follow the currency rule: the most-lit side takes base, any other lit side a half step
  toward shade, unlit sides take shade;
* curved surfaces (revolve facets) are bucketed by Lambert term into highlight stripe / base /
  half-shade / shade, which gives the banded, machined look of the brand (no smooth gradients).

Solids are painted back to front (by depth of their centre along the view direction, or an explicit
`order`), each with an optional 0.8 px ink separation line, and the whole object gets the 2 px
keyline. Planar decals (stamps, labels, cut-outs) are mapped onto any 3D plane with `plane_map`.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from shapely import affinity

from . import geom as G
from . import proj
from .svgdoc import Doc, mix
from .tokens import INK, MATERIALS

_C, _S = math.cos(proj.YAW), math.sin(proj.YAW)
_CE, _SE = math.cos(proj.ELEV), math.sin(proj.ELEV)
VIEW = (-_S * _CE, _SE, _C * _CE)  # world-space unit vector pointing at the viewer


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _norm(a):
    ln = math.sqrt(_dot(a, a)) or 1e-9
    return (a[0] / ln, a[1] / ln, a[2] / ln)


def depth(p) -> float:
    return _dot(p, VIEW)


def lin_proj():
    """Screen = M * world (orthographic, linear). Returns ((xx, xy, xz), (yx, yy, yz))."""
    ex = proj.project((1, 0, 0))
    ey = proj.project((0, 1, 0))
    ez = proj.project((0, 0, 1))
    return (ex[0], ey[0], ez[0]), (ex[1], ey[1], ez[1])


def plane_map(geom2d, origin, u, v):
    """Map a 2D shape drawn in (u, v) plane coordinates onto the 3D plane origin + u*U + v*V and
    project it to (unfitted) screen space."""
    o = proj.project(origin)
    a = proj.project(_add(origin, u))
    b = proj.project(_add(origin, v))
    pu = (a[0] - o[0], a[1] - o[1])
    pv = (b[0] - o[0], b[1] - o[1])
    return affinity.affine_transform(geom2d, [pu[0], pv[0], pu[1], pv[1], o[0], o[1]])


@dataclass
class Face:
    pts: list
    normal: tuple
    mat: str
    kind: str = "side"  # 'side' | 'top' | 'flat' (no tone logic, uses `tone`)
    tone: str | None = None  # explicit fill override ('hi', 'base', 'mid', 'lo' or a hex)
    tag: str | None = None


@dataclass
class Solid:
    faces: list = field(default_factory=list)
    smooth: bool = False  # curved surface: bucket facets by Lambert instead of the flat-side rule
    order: float | None = None
    sep: float = 0.8  # ink separation line width drawn under this solid (0 disables)
    centre: tuple = (0.0, 0.0, 0.0)
    name: str = ""

    def key(self):
        return self.order if self.order is not None else depth(self.centre)


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------
def _face_normal(pts, centre):
    a = _sub(pts[1], pts[0])
    b = _sub(pts[2], pts[0])
    n = _norm(_cross(a, b))
    fc = _mul(tuple(sum(p[k] for p in pts) for k in range(3)), 1.0 / len(pts))
    if _dot(n, _sub(fc, centre)) < 0:
        n = _mul(n, -1)
    return n


def extrude(poly_uv, origin, u, v, depth_vec, mat, cap_mat=None, back_cap=True, smooth=False, name="",
            top_tag=None, side_mats=None):
    """Extrude a 2D polygon (list of (u, v)) lying in plane origin + u*U + v*V along depth_vec.
    Returns a Solid. The cap at origin+depth_vec is the 'front' cap. Side normals come from the
    polygon winding (so concave outlines shade correctly); U and V should be orthogonal."""
    # orient the outline counter-clockwise in (u, v)
    area = sum(poly_uv[i][0] * poly_uv[(i + 1) % len(poly_uv)][1] - poly_uv[(i + 1) % len(poly_uv)][0] * poly_uv[i][1]
               for i in range(len(poly_uv)))
    pts2 = list(poly_uv) if area > 0 else list(reversed(poly_uv))
    base = [_add(origin, _add(_mul(u, a), _mul(v, b))) for a, b in pts2]
    top = [_add(p, depth_vec) for p in base]
    n = len(base)
    centre = _mul(tuple(sum(p[k] for p in base + top) for k in range(3)), 1.0 / (2 * n))
    s = Solid(smooth=smooth, centre=centre, name=name)
    un, vn = _norm(u), _norm(v)
    for i in range(n):
        j = (i + 1) % n
        quad = [base[i], base[j], top[j], top[i]]
        du = pts2[j][0] - pts2[i][0]
        dv = pts2[j][1] - pts2[i][1]
        # outward 2D normal of a CCW edge is (dv, -du)
        nrm = _norm(_add(_mul(un, dv), _mul(vn, -du)))
        sm = side_mats[i] if side_mats else mat
        s.faces.append(Face(quad, nrm, sm))
    capm = cap_mat or mat
    dn = _norm(depth_vec)
    s.faces.append(Face(top, dn, capm, tag=top_tag or "cap1"))
    if back_cap:
        s.faces.append(Face(list(reversed(base)), _mul(dn, -1), capm, tag="cap0"))
    return s


def prism(pts_xz, y0, y1, mat, offset=(0.0, 0.0, 0.0), top_mat=None, name=""):
    """Vertical prism: polygon in the ground plane (x, z) extruded from y0 to y1."""
    o = (offset[0], offset[1] + y0, offset[2])
    return extrude(pts_xz, o, (1, 0, 0), (0, 0, 1), (0, y1 - y0, 0), mat, cap_mat=top_mat, name=name,
                   top_tag="top")


def box(x0, y0, z0, x1, y1, z1, mat, chamfer=0.0, top_mat=None, name=""):
    """Axis-aligned box, optional 45-degree chamfer on the four vertical edges."""
    c = chamfer
    if c:
        pts = [(x0 + c, z0), (x1 - c, z0), (x1, z0 + c), (x1, z1 - c), (x1 - c, z1), (x0 + c, z1), (x0, z1 - c),
               (x0, z0 + c)]
    else:
        pts = [(x0, z0), (x1, z0), (x1, z1), (x0, z1)]
    return prism(pts, y0, y1, mat, top_mat=top_mat, name=name)


def frame(axis):
    a = _norm(axis)
    ref = (0, 0, 1) if abs(a[2]) < 0.9 else (1, 0, 0)
    e1 = _norm(_cross(a, ref))
    e2 = _norm(_cross(a, e1))
    return a, e1, e2


SMOOTH_HI = 0.648  # lambert >= this: highlight stripe (about 15..30 % across a vertical cylinder)
SMOOTH_BASE = 0.44
SMOOTH_MID = 0.18


def _classify(lam):
    if lam >= SMOOTH_HI:
        return "hi"
    if lam >= SMOOTH_BASE:
        return "base"
    if lam >= SMOOTH_MID:
        return "mid"
    return "lo"


_THR = {("hi", "base"): SMOOTH_HI, ("base", "hi"): SMOOTH_HI, ("base", "mid"): SMOOTH_BASE,
        ("mid", "base"): SMOOTH_BASE, ("mid", "lo"): SMOOTH_MID, ("lo", "mid"): SMOOTH_MID}


def _ring_normal(a, e1, e2, k, t):
    radial = _add(_mul(e1, math.cos(t)), _mul(e2, math.sin(t)))
    return _norm(_add(radial, _mul(a, k)))


def _bisect(f, t0, t1, it=24):
    f0 = f(t0)
    for _ in range(it):
        tm = (t0 + t1) / 2
        if (f(tm) > 0) == (f0 > 0):
            t0, f0 = tm, f(tm)
        else:
            t1 = tm
    return (t0 + t1) / 2


def tone_runs(a, e1, e2, k, samples=240):
    """Visible arc of a frustum ring with slope k, split into tone runs.
    Returns [(tone, t_start, t_end), ...] in increasing t (t may exceed 2*pi)."""
    N = samples
    ts = [2 * math.pi * j / N for j in range(N)]
    vis = [proj.facing(_ring_normal(a, e1, e2, k, t)) > 1e-4 for t in ts]
    if not any(vis):
        return []
    if all(vis):
        start = 0
    else:
        start = next(j for j in range(N) if vis[j] and not vis[j - 1])
    fv = lambda t: proj.facing(_ring_normal(a, e1, e2, k, t))  # noqa: E731
    t_begin = _bisect(fv, ts[start] - 2 * math.pi / N, ts[start]) if not all(vis) else 0.0
    runs = []
    j = start
    cur = _classify(proj.lambert(_ring_normal(a, e1, e2, k, ts[j])))
    t_cur = t_begin
    steps = 0
    while steps < N:
        jn = (j + 1) % N
        tn = ts[j] + 2 * math.pi / N  # unwrapped next sample
        if not vis[jn]:
            t_end = _bisect(fv, ts[j] if ts[j] >= t_cur - 1e-9 else ts[j] + 2 * math.pi, tn)
            runs.append((cur, t_cur, max(t_end, t_cur)))
            return _unwrap(runs)
        nt = _classify(proj.lambert(_ring_normal(a, e1, e2, k, tn)))
        if nt != cur:
            thr = _THR.get((cur, nt))
            if thr is None:
                tb = (ts[j] + tn) / 2
            else:
                tj = ts[j] if ts[j] >= t_cur - 1e-9 else ts[j] + 2 * math.pi
                tb = _bisect(lambda t: proj.lambert(_ring_normal(a, e1, e2, k, t)) - thr, tj, tj + 2 * math.pi / N)
            runs.append((cur, t_cur, tb))
            cur, t_cur = nt, tb
        j = jn
        steps += 1
    runs.append((cur, t_cur, t_begin + 2 * math.pi))
    return _unwrap(runs)


def _unwrap(runs):
    out = []
    off = 0.0
    prev = None
    for tone, t0, t1 in runs:
        t0 += off
        t1 += off
        if prev is not None and t0 < prev - 1e-6:
            off += 2 * math.pi
            t0 += 2 * math.pi
            t1 += 2 * math.pi
        if t1 < t0:
            t1 += 2 * math.pi
        out.append((tone, t0, t1))
        prev = t1
    return out


def revolve(profile, axis=(0, 1, 0), centre=(0, 0, 0), n=40, name="", theta0=0.0, merge=True):
    """Body of revolution. profile: list of (s, r, mat) points along the axis (s grows along `axis`).
    Consecutive points with equal s make an annular step face (painted first: a step facing the
    viewer is only ever overlapped by the narrower part beyond it).

    Curved surfaces get analytic band shading: for every ring the visible arc is split where the
    Lambert term crosses the highlight / base / half-shade / shade thresholds, and band polygons
    join those boundaries ring to ring, so tone edges run as smooth lines instead of facet steps.
    `n` only sets the sampling density of the band outlines."""
    a, e1, e2 = frame(axis)

    def P(s, r, t):
        return _add(_add(centre, _mul(a, s)), _add(_mul(e1, r * math.cos(t)), _mul(e2, r * math.sin(t))))

    def ring(s, r):
        return [P(s, r, theta0 + 2 * math.pi * k / n) for k in range(n)]

    solids = []
    steps = []
    first = profile[0]
    if first[1] > 1e-6:
        c = _add(centre, _mul(a, first[0]))
        s0 = Solid(smooth=False, centre=c, name=name + ":cap0", sep=0)
        s0.faces.append(Face(list(reversed(ring(first[0], first[1]))), _mul(a, -1), first[2], tag="cap0"))
        steps.append(s0)
    # slopes of the curved segments, and per-ring smoothed slopes
    segs = []
    for i in range(len(profile) - 1):
        sa, ra, ma = profile[i]
        sb, rb, mb = profile[i + 1]
        if abs(sb - sa) < 1e-9:
            segs.append(None)
        else:
            segs.append((ra - rb) / (sb - sa))
    body = Solid(smooth=False, centre=_add(centre, _mul(a, profile[-1][0])), name=name + ":body", sep=0)
    run_cache = {}

    def runs_for(k):
        key = round(k, 6)
        if key not in run_cache:
            run_cache[key] = tone_runs(a, e1, e2, k)
        return run_cache[key]

    def ring_k(i):
        """smoothed slope at profile point i (average of the curved segments either side)."""
        ks = [segs[j] for j in (i - 1, i) if 0 <= j < len(segs) and segs[j] is not None]
        if not ks:
            return 0.0
        ang = sum(math.atan(k) for k in ks) / len(ks)
        return math.tan(ang)

    for i in range(len(profile) - 1):
        sa, ra, ma = profile[i]
        sb, rb, mb = profile[i + 1]
        if segs[i] is None:
            if abs(ra - rb) < 1e-9:
                continue
            outer, inner = ring(sa, max(ra, rb)), ring(sa, min(ra, rb))
            nrm = a if rb < ra else _mul(a, -1)
            cen = _add(centre, _mul(a, sa))
            st = Solid(smooth=False, centre=cen, name=f"{name}:step{i}", sep=0)
            disc = min(ra, rb) < 1e-6
            for k in range(n):
                j = (k + 1) % n
                quad = [outer[k], outer[j], cen] if disc else [outer[k], outer[j], inner[j], inner[k]]
                st.faces.append(Face(quad, nrm, mb, tag="step"))
            steps.append(st)
            continue
        k_mid = segs[i]
        # a run of rings in the same smooth stretch shares boundaries; at material/shape breaks
        # (neighbouring step) use the segment's own slope
        ka = ring_k(i) if (i > 0 and segs[i - 1] is not None) else k_mid
        kb = ring_k(i + 1) if (i + 1 < len(segs) and segs[i + 1] is not None) else k_mid
        RA, RB = runs_for(ka), runs_for(kb)
        if [r[0] for r in RA] != [r[0] for r in RB]:
            RA = RB = runs_for(k_mid)
        for (tone, ta0, ta1), (_, tb0, tb1) in zip(RA, RB):
            m = max(2, int(abs(ta1 - ta0) / (2 * math.pi / n)) + 1)
            mb_ = max(2, int(abs(tb1 - tb0) / (2 * math.pi / n)) + 1)
            pa = [P(sa, ra, theta0 * 0 + ta0 + (ta1 - ta0) * q / m) for q in range(m + 1)]
            pb = [P(sb, rb, tb0 + (tb1 - tb0) * q / mb_) for q in range(mb_ + 1)]
            pts = pa + list(reversed(pb))
            tm = (ta0 + ta1) / 2
            nrm = _ring_normal(a, e1, e2, k_mid, tm)
            body.faces.append(Face(pts, nrm, ma, kind="flat", tone=tone))
    last = profile[-1]
    if last[1] > 1e-6:
        c = _add(centre, _mul(a, last[0]))
        s1 = Solid(smooth=False, centre=c, name=name + ":cap1", sep=0)
        s1.faces.append(Face(ring(last[0], last[1]), a, last[2], tag="cap1"))
        steps.append(s1)
    if merge:
        for i, s_ in enumerate(steps):
            s_.order = -1000 + i
            if s_.name.endswith(":cap1"):
                s_.order = 1
        body.order = 0
    solids = steps + ([body] if body.faces else [])
    return solids


def lathe(points, mat_of=None, default="steel"):
    """Helper: build a revolve profile from (s, r) points and a list of (s_from, s_to, mat) bands.
    Points with equal s produce steps. mat_of(s_mid) picks the material for each segment."""
    out = []
    for i, (s, r) in enumerate(points):
        if mat_of is None:
            m = default
        else:
            if i + 1 < len(points):
                m = mat_of((s + points[i + 1][0]) / 2, i)
            else:
                m = mat_of(s, i)
        out.append((s, r, m))
    return out


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def _tone_hex(mat, tone):
    hi, base, lo = MATERIALS[mat]
    return {"hi": hi, "base": base, "mid": mix(base, lo, 0.5), "lo": lo}.get(tone, tone)


class Scene:
    def __init__(self):
        self.solids: list[Solid] = []

    def add(self, *items):
        for it in items:
            if isinstance(it, (list, tuple)):
                self.solids.extend(it)
            else:
                self.solids.append(it)
        return self

    def _visible(self):
        out = []
        for s in self.solids:
            faces = []
            for f in s.faces:
                if proj.facing(f.normal) > 1e-3:
                    g = G.poly([proj.project(p) for p in f.pts])
                    if g.area < 1e-7:
                        continue
                    g = g.buffer(0)
                    if not g.is_empty:
                        faces.append((f, g))
            out.append((s, faces))
        return out

    def silhouette(self):
        allg = []
        for s in self.solids:
            for f in s.faces:
                g = G.poly([proj.project(p) for p in f.pts])
                if g.area > 1e-7:
                    allg.append(g.buffer(0))
        return G.union(allg)

    def fitter(self, box=(7, 8, 57, 56), extra=None):
        allg = self.silhouette()
        if extra is not None:
            allg = G.union(allg, extra)
        bx0, by0, bx1, by1 = allg.bounds
        x0, y0, x1, y1 = box
        s = min((x1 - x0) / (bx1 - bx0), (y1 - y0) / (by1 - by0))
        ox = x0 + ((x1 - x0) - (bx1 - bx0) * s) / 2 - bx0 * s
        oy = y0 + ((y1 - y0) - (by1 - by0) * s) / 2 - by0 * s
        mtx = [s, 0, 0, s, ox, oy]
        f = lambda g: affinity.affine_transform(g, mtx)  # noqa: E731
        f.scale = s
        return f

    def render(self, d: Doc, f, keyline: float = 2.0, draw_keyline: bool = True, extra_sil=None):
        """Paint every solid through fit transform f. Returns dict tag -> fitted face geometry and
        the fitted silhouette."""
        vis = self._visible()
        sil = f(G.union([g for _, fs in vis for _, g in fs]))
        if extra_sil is not None:
            sil = G.union(sil, extra_sil)
        if draw_keyline and keyline:
            # bevel joins: sharp tips and steps get a chamfered keyline instead of mitre spikes
            d.path(sil.buffer(keyline, join_style=3), INK)
        tags = {}
        order = sorted(range(len(vis)), key=lambda i: vis[i][0].key())
        for i in order:
            s, faces = vis[i]
            if not faces:
                continue
            ssil = f(G.union([G.grow(g, 0.004) for _, g in faces]))
            if s.sep:
                d.keyline(ssil, s.sep, INK, 0.9)
            # underfill with the dominant material base so facet seams never show the background
            d.path(ssil, MATERIALS[faces[0][0].mat][1], simplify=0.05)
            buckets: dict[str, list] = {}
            tops = []
            side_lams = [proj.lambert(fc.normal) for fc, _ in faces if fc.kind == "side" and not _is_top(fc)]
            best = max(side_lams) if side_lams else 0.0
            for fc, g in faces:
                g = f(g)
                if fc.tag:
                    tags[fc.tag] = G.union(tags[fc.tag], g) if fc.tag in tags else g
                if fc.tone:
                    buckets.setdefault(_tone_hex(fc.mat, fc.tone), []).append(g)
                    continue
                if _is_top(fc) and not s.smooth:
                    tops.append((fc, g))
                    continue
                lam = proj.lambert(fc.normal)
                if s.smooth:
                    tone = _classify(lam)
                else:
                    if lam <= 0.05:
                        tone = "lo"
                    elif lam >= best - 1e-6:
                        tone = "base"
                    else:
                        tone = "mid"
                buckets.setdefault(_tone_hex(fc.mat, tone), []).append(g)
            for col, gs in buckets.items():
                d.path(G.union([G.grow(g, 0.06) for g in gs]), col, simplify=0.05)
            top_groups: dict[str, list] = {}
            for fc, g in tops:
                top_groups.setdefault(fc.mat, []).append(G.grow(g, 0.06))
            for mat, gs in top_groups.items():
                g = G.union(gs)
                hi, base, lo = MATERIALS[mat]
                x0, y0, x1, y1 = g.bounds
                fill = d.linear([(0, mix(base, hi, 0.45), 1), (1, base, 1)], 0, y0, 0, y1)
                d.path(g, fill)
                rim = G.diff(g, G.T(g, 0, -1.2))
                d.path(rim, hi)
        return tags, sil


def _is_top(fc: Face) -> bool:
    return fc.kind != "flat" and fc.normal[1] > 0.72


# ---------------------------------------------------------------------------
# Convenience builders
# ---------------------------------------------------------------------------
def cylinder(p0, p1, r, mat, n=36, cap_mat=None, profile=None, name=""):
    """Cylinder (or any lathe profile) from point p0 to p1. profile: optional list of (t, r) with t in
    0..1 along the axis (radii absolute); default is a plain cylinder of radius r."""
    ax = _sub(p1, p0)
    L = math.sqrt(_dot(ax, ax))
    if profile is None:
        prof = [(0.0, r, mat), (L, r, mat)]
    else:
        prof = [(t * L, rr, mat) for t, rr in profile]
    if cap_mat:
        prof = [(s, rr, m) for s, rr, m in prof]
    return revolve(prof, axis=ax, centre=p0, n=n, name=name)


def face_map(kind, x0, y0, z0, x1, y1, z1):
    """(origin, U, V) for decals drawn in a unit square (0..1, y down) on a box face.
    kind: 'front' (+z), 'left' (-x), 'top' (+y)."""
    if kind == "front":
        return (x0, y1, z1), (x1 - x0, 0, 0), (0, -(y1 - y0), 0)
    if kind == "left":
        return (x0, y1, z0), (0, 0, z1 - z0), (0, -(y1 - y0), 0)
    if kind == "top":
        return (x0, y1, z0), (x1 - x0, 0, 0), (0, 0, z1 - z0)
    raise KeyError(kind)


def decal(geom_unit, kind, x0, y0, z0, x1, y1, z1):
    o, u, v = face_map(kind, x0, y0, z0, x1, y1, z1)
    return plane_map(geom_unit, o, u, v)
