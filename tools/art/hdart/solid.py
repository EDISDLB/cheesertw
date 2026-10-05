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
    pu = _sub(proj.project(_add(origin, u)), o)
    pv = _sub(proj.project(_add(origin, v)), o)
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
    Returns a Solid. The cap at origin+depth_vec is the 'front' cap."""
    base = [_add(origin, _add(_mul(u, a), _mul(v, b))) for a, b in poly_uv]
    top = [_add(p, depth_vec) for p in base]
    n = len(base)
    centre = _mul(tuple(sum(p[k] for p in base + top) for k in range(3)), 1.0 / (2 * n))
    s = Solid(smooth=smooth, centre=centre, name=name)
    for i in range(n):
        j = (i + 1) % n
        quad = [base[i], base[j], top[j], top[i]]
        sm = side_mats[i] if side_mats else mat
        s.faces.append(Face(quad, _face_normal(quad, centre), sm))
    capm = cap_mat or mat
    s.faces.append(Face(top, _face_normal(top, centre), capm, tag=top_tag or "cap1"))
    if back_cap:
        s.faces.append(Face(list(reversed(base)), _face_normal(base, centre), capm, tag="cap0"))
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


def revolve(profile, axis=(0, 1, 0), centre=(0, 0, 0), n=40, name="", theta0=0.0, merge=True):
    """Body of revolution. profile: list of (s, r, mat) points along the axis (s grows along `axis`).
    Consecutive points with equal s make an annular step face. Returns a list of Solids. With
    merge=True (default) every curved facet goes into one smooth solid painted after the step faces:
    correct for any profile seen from its 'far' end (steps facing the viewer are always overlapped
    by the narrower part above them, never by the wider part below). merge=False keeps one solid
    per segment for depth sorting."""
    a, e1, e2 = frame(axis)

    def ring(s, r):
        out = []
        for k in range(n):
            t = theta0 + 2 * math.pi * k / n
            p = _add(_add(centre, _mul(a, s)), _add(_mul(e1, r * math.cos(t)), _mul(e2, r * math.sin(t))))
            out.append(p)
        return out

    solids = []
    first = profile[0]
    if first[1] > 1e-6:  # closing disc at the start
        rg = ring(first[0], first[1])
        c = _add(centre, _mul(a, first[0]))
        s0 = Solid(smooth=False, centre=c, name=name + ":cap0", sep=0)
        s0.faces.append(Face(list(reversed(rg)), _mul(a, -1), first[2], tag="cap0"))
        solids.append(s0)
    for i in range(len(profile) - 1):
        sa, ra, ma = profile[i]
        sb, rb, mb = profile[i + 1]
        mat = mb if (abs(sb - sa) < 1e-9) else ma
        cen = _add(centre, _mul(a, (sa + sb) / 2))
        if abs(sb - sa) < 1e-9:
            if abs(ra - rb) < 1e-9:
                continue
            # annular step: faces +a when the radius shrinks along the axis, -a when it grows
            outer, inner = ring(sa, max(ra, rb)), ring(sa, min(ra, rb))
            nrm = a if rb < ra else _mul(a, -1)
            st = Solid(smooth=False, centre=cen, name=f"{name}:step{i}", sep=0)
            disc = min(ra, rb) < 1e-6
            for k in range(n):
                j = (k + 1) % n
                quad = [outer[k], outer[j], cen] if disc else [outer[k], outer[j], inner[j], inner[k]]
                st.faces.append(Face(quad, nrm, mat, tag="step"))
            solids.append(st)
            continue
        r0, r1 = ring(sa, ra), ring(sb, rb)
        seg = Solid(smooth=True, centre=cen, name=f"{name}:seg{i}", sep=0)
        for k in range(n):
            j = (k + 1) % n
            if ra < 1e-6:
                quad = [r0[k], r1[k], r1[j]]
            elif rb < 1e-6:
                quad = [r0[k], r0[j], r1[k]]
            else:
                quad = [r0[k], r0[j], r1[j], r1[k]]
            # outward normal of the frustum facet
            tm = theta0 + 2 * math.pi * (k + 0.5) / n
            radial = _add(_mul(e1, math.cos(tm)), _mul(e2, math.sin(tm)))
            slope = (ra - rb) / (sb - sa)
            nrm = _norm(_add(radial, _mul(a, slope)))
            seg.faces.append(Face(quad, nrm, ma))
        solids.append(seg)
    last = profile[-1]
    if last[1] > 1e-6:
        rg = ring(last[0], last[1])
        c = _add(centre, _mul(a, last[0]))
        s1 = Solid(smooth=False, centre=c, name=name + ":cap1", sep=0)
        s1.faces.append(Face(rg, a, last[2], tag="cap1"))
        solids.append(s1)
    if merge:
        flat = [s for s in solids if not s.smooth]
        curved = [s for s in solids if s.smooth]
        if curved:
            m = Solid(smooth=True, centre=curved[-1].centre, name=name + ":body", sep=0)
            for s in curved:
                m.faces.extend(s.faces)
            for i, s in enumerate(flat):
                s.order = -1000 + i
            m.order = 0
            for s in flat:
                if s.name.endswith(":cap1"):
                    s.order = 1
            return flat + [m]
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
SMOOTH_HI = 0.63  # lambert >= this: highlight stripe
SMOOTH_BASE = 0.14
SMOOTH_MID = -0.06


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
            d.keyline(sil, keyline)
        tags = {}
        order = sorted(range(len(vis)), key=lambda i: vis[i][0].key())
        for i in order:
            s, faces = vis[i]
            if not faces:
                continue
            ssil = f(G.union([g for _, g in faces]))
            if s.sep:
                d.keyline(ssil, s.sep, INK, 0.9)
            # underfill with the dominant material base so facet seams never show the background
            d.path(ssil, MATERIALS[faces[0][0].mat][1])
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
                    if lam >= SMOOTH_HI:
                        tone = "hi"
                    elif lam >= SMOOTH_BASE:
                        tone = "base"
                    elif lam >= SMOOTH_MID:
                        tone = "mid"
                    else:
                        tone = "lo"
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
