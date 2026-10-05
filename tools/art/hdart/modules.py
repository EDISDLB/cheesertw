"""Vehicle module icons (assets/icons/modules/): damage panel, module inspector, crit callouts.

Modules are flat-front SYMBOLS (status glyphs, not objects), bevelled in one material per state:

    <id>.svg            normal     steel                      (intact / neutral)
    <id>_damaged.svg    damaged    amber  (state.warning)  + a tapered crack chipped into the outline
    <id>_destroyed.svg  destroyed  signal (state.danger)   + the silhouette broken in two along a
                                                             jagged break, halves pushed apart

The crack and the break are shape cues, so the three states read apart without colour. Every module
owns a unique outline: piston (engine), shell rack (ammo_rack), hooped drum (fuel_tank), breech +
barrel + muzzle brake (gun), internally toothed ring (turret_ring), Z periscope (optics), set +
mast + broadcast arcs (radio), track run with grousers (track).
"""

from __future__ import annotations

import math

from . import geom as G
from . import kit
from .registry import add, note
from .tokens import MATERIALS

STATE_MAT = {"normal": "steel", "damaged": "amber", "destroyed": "signal"}
BEV = 1.8


def _drop(cx, top, r):
    """Angular fuel drop: chamfered teardrop."""
    body = G.ngon(cx, top + r * 2.1, r, 8, rot_deg=22.5)
    tipg = G.poly([(cx, top), (cx + r * 0.93, top + r * 1.72), (cx - r * 0.93, top + r * 1.72)])
    return G.union(body, tipg)


# ---------------------------------------------------------------------------
# Shapes: each returns (silhouette, details) on the 64 grid.
# details: list of (kind, geometry) with kind in 'engrave' | 'inlay' | 'glass' | 'dark'
# ---------------------------------------------------------------------------
def engine():
    crown = G.cbox(13, 7, 51, 29, 5, 5, 2.5, 2.5)
    rod = G.poly([(26.5, 27), (37.5, 27), (35.6, 40), (28.4, 40)])
    big_end = G.circle(32, 45.5, 11.0, n=96)
    sil = G.union(crown, rod, big_end)
    det = [
        ("engrave", G.union(G.rect(16.5, 11.6, 47.5, 13.6), G.rect(16.5, 16.0, 47.5, 18.0))),
        ("engrave", G.circle(32, 23.6, 2.6, n=32)),
        ("engrave", G.circle(32, 45.5, 4.6, n=48)),
        ("engrave", G.diff(G.circle(32, 45.5, 8.2, n=64), G.circle(32, 45.5, 7.0, n=64))),
    ]
    return sil, det


def ammo_rack():
    shells = []
    seams = []
    for cx in (18.0, 32.0, 46.0):
        shells.append(kit.shell_flat(cx, 50.5, 41.0, 11.0))
        seams.append(G.rect(cx - 4.8, 31.9, cx + 4.8, 33.3))  # case mouth seam
    base = G.cbox(7, 48, 57, 56, 2.5, 2.5, 2.5, 2.5)
    band = G.rect(8.5, 37.5, 55.5, 42.5)
    sil = G.union(shells, base, band)
    det = [
        ("engrave", G.union(seams)),
        ("engrave", G.union(G.rect(8.5, 37.5, 55.5, 38.6), G.rect(8.5, 41.4, 55.5, 42.5))),
        ("engrave", G.union([G.rect(x - 1.6, 51, x + 1.6, 53.2) for x in (14, 32, 50)])),
    ]
    return sil, det


def fuel_tank():
    body = G.cbox(14, 12, 50, 56, 5, 5, 4, 4)
    hoops = G.union(G.cbox(11.5, 21, 52.5, 26, 1.2, 1.2, 1.2, 1.2), G.cbox(11.5, 44, 52.5, 49, 1.2, 1.2, 1.2, 1.2))
    bung = G.cbox(18.5, 7, 27.5, 13, 1.8, 1.8, 0, 0)
    sil = G.union(body, hoops, bung)
    det = [
        ("engrave", _drop(32, 28.0, 5.2)),
        ("engrave", G.union(G.rect(11.5, 23, 52.5, 24), G.rect(11.5, 46, 52.5, 47))),
        ("engrave", G.rect(21.5, 8.6, 24.5, 10.6)),
    ]
    return sil, det


def gun():
    """Elevated gun on its trunnion cradle: reads as ordnance, never as a key."""
    ang = -31.0
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    piv = (22.0, 39.0)

    def along(t, half_w, t0=None):
        t0 = t if t0 is None else t0
        p0 = (piv[0] + ux * t0, piv[1] + uy * t0)
        p1 = (piv[0] + ux * t, piv[1] + uy * t)
        return G.thick_line(p0, p1, half_w * 2)

    barrel = G.thick_line(piv, (piv[0] + ux * 35, piv[1] + uy * 35), 7.4)
    bore_evac = along(24.0, 5.2, 16.0)  # fume extractor bulge
    brake = G.T(G.R(G.cbox(-5.5, -6.6, 5.5, 6.6, 1.6, 1.6, 1.6, 1.6), ang, (0, 0)), piv[0] + ux * 36.5, piv[1] + uy * 36.5)
    mantlet = G.R(G.cbox(piv[0] - 9, piv[1] - 8.5, piv[0] + 7, piv[1] + 8.5, 3.5, 3.5, 3.5, 3.5), ang, piv)
    cradle = G.poly([(7, 56), (38, 56), (33, 46), (12, 46)])
    sil = G.union(barrel, bore_evac, brake, mantlet, cradle)
    det = [
        ("engrave", G.T(G.R(G.union(G.rect(-3.2, -4.6, -1.8, 4.6), G.rect(0.6, -4.6, 2.0, 4.6)), ang, (0, 0)),
                        piv[0] + ux * 36.5, piv[1] + uy * 36.5)),
        ("engrave", G.circle(piv[0], piv[1], 2.6, n=32)),
        ("engrave", G.rect(14, 50.2, 32, 51.6)),
    ]
    sil, *rest = kit.shrink_to(sil, *[g for _, g in det])
    det = [(k, g) for (k, _), g in zip(det, rest)]
    return sil, det


def turret_ring():
    c = (32, 32)
    ring = G.diff(G.circle(*c, 25.0, n=128), G.circle(*c, 16.5, n=96))
    teeth = []
    for i in range(18):
        a = math.radians(i * 20 + 10)
        ux, uy = math.cos(a), math.sin(a)
        p = (c[0] + 15.0 * ux, c[1] + 15.0 * uy)
        t = G.R(G.cbox(-1.6, -2.4, 1.6, 2.4, 0.6, 0.6, 0, 0), math.degrees(a) - 90, (0, 0))
        teeth.append(G.T(G.R(G.rect(-2.8, -1.7, 2.8, 1.7), math.degrees(a), (0, 0)), *p))
    ring = G.union(ring, G.inter(G.union(teeth), G.circle(*c, 17.0, n=96)))
    pin = G.gear(39.5, 39.5, 4.2, 6.6, 8, tooth_frac=0.5, tip_frac=0.32, rot_deg=10)
    sil = G.union(ring, pin)
    det = [
        ("engrave", G.diff(G.circle(*c, 22.6, n=128), G.circle(*c, 21.4, n=128))),
        ("engrave", G.circle(39.5, 39.5, 1.8, n=24)),
    ]
    return sil, det


def optics():
    """Vision device, front view: two lens barrels on a hinge bridge with a focus wheel. The glass
    lenses carry the meaning; in damaged/destroyed states they become dark recesses."""
    left = G.cbox(7, 19, 29, 56, 6, 6, 7, 7)
    right = G.cbox(35, 19, 57, 56, 6, 6, 7, 7)
    bridge = G.rect(27, 25, 37, 41)
    wheel = G.cbox(27.5, 9, 36.5, 22, 2, 2, 0, 0)
    sil = G.union(left, right, bridge, wheel)
    det = [
        ("glass", G.circle(18, 42.5, 8.2, n=64)),
        ("glass", G.circle(46, 42.5, 8.2, n=64)),
        ("engrave", G.union(G.rect(27.5, 13, 36.5, 14.2), G.rect(27.5, 16.6, 36.5, 17.8))),
        ("engrave", G.union(G.rect(10, 27.5, 26, 28.7), G.rect(38, 27.5, 54, 28.7))),
    ]
    return sil, det


def radio():
    box = G.cbox(7, 30, 47, 56, 3, 3, 3, 3)
    mount = G.cbox(35, 25.5, 45, 31, 1.5, 1.5, 0, 0)
    mast = G.rect(38.4, 18.5, 41.6, 27)
    tip = G.circle(40, 17.0, 2.9, n=32)
    cx, cy = 40.0, 17.0
    waves = G.union(
        kit.arc(cx, cy, 7.4, 3.2, -42, 42), kit.arc(cx, cy, 12.8, 3.2, -40, 40),
        kit.arc(cx, cy, 7.4, 3.2, 138, 222), kit.arc(cx, cy, 12.8, 3.2, 140, 220),
    )
    sil = G.union(box, mount, mast, tip, waves)
    det = [
        ("engrave", G.diff(G.circle(18.5, 43, 6.5, n=64), G.circle(18.5, 43, 5.0, n=64))),
        ("engrave", G.circle(18.5, 43, 1.8, n=24)),
        ("engrave", G.union([G.rect(29, y, 42, y + 1.8) for y in (37, 41.5, 46)])),
        ("engrave", G.rect(11, 51.2, 43, 52.4)),
    ]
    return sil, det


def track():
    """Track run in side view, front to the right: a long sloped front run up to the idler and a
    blunt sprocket end, grousers on the ground run. Asymmetric, so it mirrors into left/right."""
    outer = G.poly([(6, 27), (12, 19), (44, 19), (58, 25), (58, 29), (47, 45), (12, 45), (6, 39)])
    inner = G.shrink(outer, 5.2)
    belt = G.diff(outer, inner)
    teeth = [G.rect(x, 44.5, x + 3.2, 48.5) for x in range(12, 46, 6)]
    wheels = G.union([G.circle(x, 32.5, 6.0, n=48) for x in (18.5, 32.5)])
    idler = G.circle(46.5, 31.0, 4.4, n=40)
    sil = G.union(belt, teeth, wheels, idler)
    det = [
        ("engrave", G.union([G.circle(x, 32.5, 2.0, n=24) for x in (18.5, 32.5)] + [G.circle(46.5, 31.0, 1.5, n=20)])),
        ("engrave", G.union([G.rect(x + 3.9, 40.6, x + 5.1, 45) for x in range(12, 46, 6)])),
    ]
    return sil, det


SHAPES = {
    "engine": engine,
    "ammo_rack": ammo_rack,
    "fuel_tank": fuel_tank,
    "gun": gun,
    "turret_ring": turret_ring,
    "optics": optics,
    "radio": radio,
    "track": track,
}

# Break line per module (p0 just outside the top-right edge -> p1 past the opposite edge).
CRACK = {
    "engine": ((50, 4), (14, 60)),
    "ammo_rack": ((44, 6), (20, 60)),
    "fuel_tank": ((52, 8), (12, 58)),
    "gun": ((46, 6), (22, 58)),
    "turret_ring": ((54, 8), (10, 56)),
    "optics": ((40, 6), (24, 60)),
    "radio": ((36, 12), (22, 60)),
    "track": ((38, 14), (24, 52)),
}

NAMES = {
    "engine": "Engine", "ammo_rack": "Ammo rack", "fuel_tank": "Fuel tank", "gun": "Gun",
    "turret_ring": "Turret ring (traverse)", "optics": "Optics (vision devices)", "radio": "Radio",
    "track": "Track",
}


def _mirror(fn):
    def inner():
        sil, det = fn()
        return G.mirror_x(sil, 32), [(k, G.mirror_x(g, 32)) for k, g in det]
    return inner


def draw_state_symbol(d, sil, det, state, crack, normal_mat="steel", bevel=BEV, keep_glass=True):
    """Shared renderer for module / crew-tool style status symbols."""
    mat = normal_mat if state == "normal" else STATE_MAT[state]
    kit.check(sil, "module", lo=6.0, hi=58.0)
    if state == "destroyed":
        pieces = kit.split(sil, crack[0], crack[1])
        shifted = G.union([G.T(r, *o) for r, o in pieces])
        x0, y0, x1, y1 = shifted.bounds
        if x0 < 6 or y0 < 6 or x1 > 58 or y1 > 58:
            # the pushed-apart halves need a little more room: scale the whole symbol about its centre
            k = min(1.0, (58 - 32) / max(32 - x0, x1 - 32, 1e-6), (58 - 32) / max(32 - y0, y1 - 32, 1e-6))
            sc = lambda g: G.S(g, k, k, origin=(32, 32))  # noqa: E731
            sil = sc(sil)
            det = [(kk, sc(g)) for kk, g in det]
            crack = tuple((32 + (p[0] - 32) * k, 32 + (p[1] - 32) * k) for p in crack)
            pieces = kit.split(sil, crack[0], crack[1])
            shifted = G.union([G.T(r, *o) for r, o in pieces])
        kit.check(shifted, "module destroyed", lo=6.0, hi=58.0)
        d.keyline(shifted, kit.KEY)
        for region, off in pieces:
            face = d.plate(G.T(region, *off), mat, bevel=bevel)
            _details(d, det, mat, face, clip=region, off=off, keep_glass=False)
        return
    if state == "damaged":
        sil, wedge = kit.chip(sil, crack[0], crack[1])
        d.keyline(sil, kit.KEY)
        face = d.plate(sil, mat, bevel=bevel)
        _details(d, det, mat, face, clip=sil, off=(0, 0), keep_glass=False)
        return
    d.keyline(sil, kit.KEY)
    face = d.plate(sil, mat, bevel=bevel)
    _details(d, det, mat, face, clip=sil, off=(0, 0), keep_glass=keep_glass)


def _details(d, det, mat, face, clip, off, keep_glass):
    for kind, g in det:
        g = G.T(G.inter(g, clip), *off)
        if g.is_empty:
            continue
        if kind == "engrave":
            d.engrave(G.inter(g, face), mat, face, depth=0.9)
        elif kind == "glass":
            if keep_glass:
                d.keyline(g, 0.8, "#0A0D10", 0.9)
                d.plate(g, "glass", bevel=0.9)
                # one glint, top-left
                x0, y0, x1, y1 = g.bounds
                gl = G.inter(G.poly([(x0, y0 + (y1 - y0) * 0.42), (x0 + (x1 - x0) * 0.42, y0), (x0 + (x1 - x0) * 0.58, y0),
                                     (x0, y0 + (y1 - y0) * 0.58)]), G.shrink(g, 1.6))
                d.path(gl, MATERIALS["glass"][0], 0.85)
            else:
                d.engrave(G.inter(g, face), mat, face, depth=0.9)
        elif kind == "inlay":
            d.inlay(g, mat, face, bevel=0.9, shadow=(0.8, 1.0))


def draw_module(d, mid: str, state: str):
    fn = SHAPES.get(mid)
    crack = CRACK.get(mid)
    if mid == "track_left":
        fn, crack = _mirror(track), ((26, 14), (40, 52))
    elif mid == "track_right":
        fn, crack = track, CRACK["track"]
    sil, det = fn()
    draw_state_symbol(d, sil, det, state, crack)


def draw_fire(d):
    outer, core = kit.flame(32, 57.5, 51, 40)
    outer, core = kit.shrink_to(outer, core)
    kit.check(outer, "fire")
    d.keyline(outer, kit.KEY)
    d.plate(outer, "dusk", bevel=BEV)
    d.keyline(core, 0.9, "#B8460F", 0.9)
    d.plate(core, "he", bevel=1.2)


def draw_repair(d):
    w = kit.wrench(32, 32, 56, 9.0, ang=-45, jaw=21)
    w, = kit.shrink_to(w)
    kit.check(w, "repair")
    d.keyline(w, kit.KEY)
    face = d.plate(w, "verdant", bevel=BEV)
    d.engrave(G.inter(G.thick_line((15, 49), (30, 34), 2.0), face), "verdant", face, depth=0.8)


def _register():
    note("modules", "Damage-panel module glyphs. Three files per module: `<id>` normal (steel), "
                    "`<id>_damaged` (amber + crack chip), `<id>_destroyed` (red + broken in two). Show at "
                    "24-40 px; upload @128. The crack/break shape keeps the states apart without colour.")
    ids = ["engine", "ammo_rack", "fuel_tank", "gun", "turret_ring", "optics", "radio", "track", "track_left",
           "track_right"]
    uses = {
        "engine": "Engine module: damage panel, module inspector, crit callout",
        "ammo_rack": "Ammo rack module (shown when hit; ammo-rack detonation callout)",
        "fuel_tank": "Fuel tank module",
        "gun": "Gun module (damaged gun = worse dispersion / reload)",
        "turret_ring": "Turret ring / traverse mechanism module",
        "optics": "Optics / vision devices (damaged = reduced view range)",
        "radio": "Radio module (damaged = reduced signal range)",
        "track": "Track (generic; same glyph as track_right)",
        "track_left": "Left track, for hull diagrams (mirror of track_right)",
        "track_right": "Right track, for hull diagrams",
    }
    for mid in ids:
        base = NAMES.get(mid, "Track")
        if mid == "track_left":
            base = "Left track"
        elif mid == "track_right":
            base = "Right track"
        for state in ("normal", "damaged", "destroyed"):
            key = mid if state == "normal" else f"{mid}_{state}"
            use = uses[mid] if state == "normal" else f"{base}: {state} state ({'amber' if state == 'damaged' else 'red'})"
            add("modules", key, f"Module: {base} ({state})", use, lambda d, m=mid, s=state: draw_module(d, m, s))
    add("modules", "fire", "Status: vehicle on fire", "Damage panel / HUD: vehicle is burning (pair with the extinguisher consumable)",
        draw_fire)
    add("modules", "repair", "Status: repairing", "Damage panel: module repair in progress (green wrench)", draw_repair)


_register()
