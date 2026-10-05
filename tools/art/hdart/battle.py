"""Battle HUD icons (assets/icons/battle/): minimap markers, map pings, radial commands, hit results,
status alerts and reticle elements.

Families and their grammar:

* Minimap markers (24 x 24 grid, like assets/icons/minimap/): pure white + 1.5 px ink keyline,
  tinted at runtime with the team colour of the active CVD scheme. Shape language: arrow = self /
  camera, rings = zones (bases, capture points = 4 heavy segments, last-seen ghost = 8 thin dashes),
  corner brackets = objective, PIN = player pings (octagonal head on a narrow spike, never the
  heavy-class shield; the cut-out symbol inside says which ping). Keylines are checked against the
  canvas, so sharp tips are cut flat rather than clipped.
* Radial command icons (64 grid): white glyphs (ui.py grammar) for the command wheel.
* Hit results (64 grid): coloured bevelled symbols for the hit callout / damage log, following the
  VFX colour language (brand-art.md 10.2): plate + projectile path tells the result.
* Status: spotted_warning is the brand's dusk crest chevron with ripples (never a lamp);
  the others are white tintable glyphs.
* Reticle elements: white with an ink outline, built for overlay tinting; segment images keep
  the full-ring canvas so the client only rotates copies about the image centre.
"""

from __future__ import annotations

import math

from . import geom as G
from . import kit
from . import modules as M
from .registry import add, note
from .tokens import INK

K24 = 1.5  # keyline at 24 px


# ---------------------------------------------------------------------------
# Minimap markers (24 grid)
# ---------------------------------------------------------------------------
def mm(d, g, name):
    x0, y0, x1, y1 = g.bounds
    if x0 < 1.95 or y0 < 1.95 or x1 > 22.05 or y1 > 22.05:
        raise ValueError(f"minimap {name} out of bounds {g.bounds}")
    # the keyline mitres out at sharp tips: it must stay on the canvas too (no clipped points)
    kx0, ky0, kx1, ky1 = G.grow(g, K24).bounds
    if kx0 < 0.3 or ky0 < 0.3 or kx1 > 23.7 or ky1 > 23.7:
        raise ValueError(f"minimap {name}: keyline {tuple(round(v, 2) for v in (kx0, ky0, kx1, ky1))} is clipped")
    d.keyline(g, K24)
    d.path(g, "#FFFFFF")


def _flag(cx, cy, s=1.0):
    """Swallowtail flag on a pole (cx, cy = centre of the group)."""
    pole = G.rect(cx - 4.4 * s, cy - 5.4 * s, cx - 3.0 * s, cy + 5.4 * s)
    fl = G.poly([(cx - 3.0 * s, cy - 5.4 * s), (cx + 5.0 * s, cy - 5.4 * s), (cx + 2.8 * s, cy - 2.9 * s),
                 (cx + 5.0 * s, cy - 0.4 * s), (cx - 3.0 * s, cy - 0.4 * s)])
    return G.union(pole, fl)


def mm_self():
    # navigation arrow with a notched tail; points up (rotate with the hull heading). The tip is cut
    # flat by 1.2 px so its keyline mitre stays on the canvas.
    return G.poly([(11.4, 2.6), (12.6, 2.6), (20.5, 21), (12, 16.4), (3.5, 21)])


def mm_last_seen():
    """Ghost of a vehicle that dropped out of sight: a thin ring broken into eight short dashes around
    a small position dot. Thin dashes keep it apart from the four heavy capture-point segments."""
    dashes = G.union([kit.arc(12, 12, 7.4, 1.9, a + 9, a + 36, n=8) for a in range(0, 360, 45)])
    return G.union(dashes, G.cbox(10.3, 10.3, 13.7, 13.7, 0.9, 0.9, 0.9, 0.9))


def mm_base(enemy: bool):
    ring = kit.ring(12, 12, 7.4, 1.8, n=48)
    flag = _flag(12.0, 12.0, 0.92)
    g = G.union(ring, flag)
    if enemy:
        ticks = G.union(G.rect(11.0, 2.0, 13.0, 4.0), G.rect(11.0, 20.0, 13.0, 22.0), G.rect(2.0, 11.0, 4.0, 13.0),
                        G.rect(20.0, 11.0, 22.0, 13.0))
        g = G.union(g, ticks)
    return g


def mm_capture(contested: bool):
    segs = G.union([kit.arc(12, 12, 8.4, 2.6, a + 8, a + 82, n=14) for a in (0, 90, 180, 270)])
    if contested:
        a = G.poly([(5.6, 9.0), (11.0, 12.0), (5.6, 15.0)])
        b = G.poly([(18.4, 9.0), (13.0, 12.0), (18.4, 15.0)])
        inner = G.union(a, b)
    else:
        inner = G.cbox(9.6, 9.6, 14.4, 14.4, 1.2, 1.2, 1.2, 1.2)
    return G.union(segs, inner)


def mm_objective():
    """Mission / mode objective: four corner brackets framing a solid centre block. The only square
    minimap zone, so it never reads as a base or capture ring."""
    br = kit.corner_brackets(3.2, 3.2, 20.8, 20.8, 7.0, 2.5, chamfer=1.6)
    return G.union(br, G.cbox(8.9, 8.9, 15.1, 15.1, 1.6, 1.6, 1.6, 1.6))


PIN_C = (12.0, 9.4)  # centre of the pin head


def _pin():
    """Ping pin: an octagonal head on a narrow spike that touches the map at (12, 21.6). The round
    head and the waist above the spike keep it apart from the heavy-class shield (flat top, straight
    sides, wide point) at 16 px."""
    head = G.ngon(*PIN_C, 8.0, 8, rot_deg=22.5)
    spike = G.poly([(9.3, 14.6), (14.7, 14.6), (12.6, 21.6), (11.4, 21.6)])  # flat-cut tip: keyline stays on canvas
    return G.union(head, spike)


def mm_ping(kind):
    pin = _pin()
    cx, cy = PIN_C
    if kind == "attack":
        sym = G.poly([(cx - 4.2, cy - 3.2), (cx + 4.2, cy - 3.2), (cx, cy + 3.9)])
    elif kind == "defend":
        sym = G.diff(G.rect(cx - 4.3, cy - 3.7, cx + 4.3, cy + 3.5), G.rect(cx - 2.5, cy - 4.2, cx - 0.9, cy - 1.3),
                     G.rect(cx + 0.9, cy - 4.2, cx + 2.5, cy - 1.3))
    elif kind == "help":
        sym = G.union(G.poly([(cx - 1.4, cy - 4.6), (cx + 1.4, cy - 4.6), (cx + 0.85, cy + 1.2), (cx - 0.85, cy + 1.2)]),
                      G.rect(cx - 1.25, cy + 2.4, cx + 1.25, cy + 4.6))
    elif kind == "spotted":
        # the HUD's 'spotted' mark (brand-art.md 8.8): a single crest chevron, never an eye (the
        # light-class minimap pip owns the eye)
        sym = G.chevron(cx, cy - 3.9, 4.6, 4.4, 2.6, flat_tip=1.6)
    elif kind == "position":
        sym = G.ngon(cx, cy, 2.9, 8, rot_deg=22.5)
    else:
        raise KeyError(kind)
    return G.diff(pin, sym)


def mm_camera():
    """Camera direction cone on a 64 canvas: apex at the centre so the image rotates about it."""
    return G.poly([(32, 32), (12.5, 4.0), (51.5, 4.0)])


def draw_camera(d):
    g = mm_camera()
    d.keyline(g, 1.0)
    d.path(g, "#FFFFFF")


def draw_view_range_ring(d):
    """Dashed view-range ring on a 128 canvas (stretch the image to the view-range diameter)."""
    segs = G.union([kit.arc(64, 64, 59, 2.6, a, a + 7.0, n=4) for a in range(0, 360, 10)])
    d.keyline(segs, 1.0)
    d.path(segs, "#FFFFFF")


# ---------------------------------------------------------------------------
# Radial command icons (64 grid, white)
# ---------------------------------------------------------------------------
def cmd_attack():
    """Advance and strike: a heavy arrow driving up-right with three speed lines behind it."""
    arr = kit.arrow((22, 42), (54, 10), w=10, head_len=20, head_half=16)
    lines = G.union([G.T(G.R(G.rect(-7, -2.2, 7, 2.2), -45, (0, 0)), *c) for c in ((14, 36), (20, 48), (28, 56))])
    lines = G.inter(lines, G.rect(6, 6, 58, 58))
    return G.union(arr, lines)


def cmd_defend():
    wall = G.rect(8, 22, 56, 56)
    merlons = G.union([G.rect(x, 10, x + 10, 23) for x in (8, 27, 46)])
    gate = G.union(G.rect(26, 40, 38, 57), G.circle(32, 40, 6, n=32))
    slits = G.union(G.rect(15, 30, 18, 38), G.rect(46, 30, 49, 38))
    return G.diff(G.union(wall, merlons), gate, slits)


def cmd_help():
    bang = G.union(G.poly([(27.6, 10), (36.4, 10), (35, 38), (29, 38)]), G.rect(28.4, 44, 35.6, 51))
    arcs = G.union(kit.arc(32, 30, 18, 5, 140, 220, n=20), kit.arc(32, 30, 18, 5, -40, 40, n=20),
                   kit.arc(32, 30, 26, 5, 148, 212, n=20), kit.arc(32, 30, 26, 5, -32, 32, n=20))
    return G.union(bang, arcs)


def cmd_retreat():
    shaft = kit.stroke([(46, 56), (46, 24), (40, 14), (24, 14), (18, 24), (18, 34)], 8)
    head = kit.head((18, 50), 90, 16, 13)
    return G.union(shaft, head)


def cmd_enemy_spotted():
    alm, pup = kit.eye(32, 32, 40, 23, 6.0)
    eye = G.diff(alm, G.diff(G.circle(32, 32, 9.5, n=48), G.circle(32, 32, 6.4, n=40)))
    ticks = G.union(G.rect(29.5, 4, 34.5, 14), G.rect(29.5, 50, 34.5, 60), G.rect(4, 29.5, 10, 34.5), G.rect(54, 29.5, 60, 34.5))
    return G.union(G.diff(eye, G.EMPTY), ticks)


def cmd_capture():
    """Capture: a swallowtail flag inside the segmented capture ring."""
    segs = G.union([kit.arc(32, 32, 24, 5, a + 10, a + 80, n=20) for a in (0, 90, 180, 270)])
    pole = G.rect(22, 15, 27, 48)
    fl = G.poly([(27, 15), (45, 15), (39.5, 22), (45, 29), (27, 29)])
    base = G.cbox(18, 46, 31, 50, 1.5, 1.5, 0, 0)
    return G.union(segs, pole, fl, base)


def cmd_follow_me():
    arr = kit.arrow((32, 46), (32, 6), w=10, head_len=18, head_half=17)
    trail = G.union(G.rect(27, 49, 37, 53), G.rect(27, 56, 37, 59))
    return G.union(arr, trail)


def cmd_need_assistance():
    arrows = []
    for a in (45, 135, 225, 315):
        r0, r1 = 30, 14
        p0 = (32 + r0 * math.cos(math.radians(a)), 32 + r0 * math.sin(math.radians(a)))
        p1 = (32 + r1 * math.cos(math.radians(a)), 32 + r1 * math.sin(math.radians(a)))
        arrows.append(kit.arrow(p0, p1, w=6, head_len=11, head_half=9))
    return G.union(arrows + [G.cbox(27, 27, 37, 37, 2, 2, 2, 2)])


def cmd_affirmative():
    return kit.checkmark(32, 29.8, 46, 9)  # optically centred


def cmd_negative():
    return kit.xmark(32, 32, 40, 9)


def cmd_reloading():
    sh = kit.shell_flat(32, 47, 30, 11)
    arc_a = kit.arc_arrow(32, 32, 24, 5.5, 150, 390, head_len=11, head_half=8.5)
    return G.union(G.diff(arc_a, G.grow(sh, 2.0)), sh)


def cmd_ping_map():
    mp = G.poly([(6, 18), (22, 12), (42, 18), (58, 12), (58, 52), (42, 58), (22, 52), (6, 58)])
    folds = G.union(G.rect(21, 12, 23, 52), G.rect(41, 18, 43, 58))
    pin = G.poly([(26, 14), (38, 14), (41, 17), (41, 27), (32, 38), (23, 27), (23, 17)])
    dot = G.circle(32, 22.5, 3.2, n=24)
    mp = G.diff(mp, folds, G.grow(pin, 2.4))
    return G.T(G.union(mp, G.diff(pin, dot)), 0, -3.0)  # centred on the canvas


# ---------------------------------------------------------------------------
# Hit results (coloured symbols)
# ---------------------------------------------------------------------------
def _plate(x0=34, x1=44, y0=8, y1=56, slope=0.0):
    return G.poly([(x0 + slope, y0), (x1 + slope, y0), (x1, y1), (x0, y1)])


def hit_penetration(d):
    """Pierced plate: a shell path enters, punches through a sloped plate and exits with spall."""
    plate = G.poly([(27, 57), (40, 57), (46, 7), (33, 7)])
    shaft_l = G.rect(6, 28, 29, 36)
    shaft_r = kit.arrow((40, 32), (58, 32), w=8, head_len=11, head_half=9.5)
    sil = G.union(plate, shaft_l, shaft_r)
    kit.check(sil, "hit_penetration")
    d.keyline(sil, kit.KEY)
    d.plate(plate, "steel", bevel=1.6)
    hole = G.inter(G.ngon(36.5, 32, 8.2, 8, rot_deg=22.5), plate)
    d.path(G.grow(hole, 0.6), INK)
    d.plate(G.union(shaft_l, shaft_r), "dusk", bevel=1.2)
    spall = G.union([G.T(G.R(G.poly([(0, -1.6), (8, 0), (0, 1.6)]), a, (0, 0)), 44, 32) for a in (-42, 42)])
    d.keyline(spall, 0.8)
    d.plate(spall, "he", bevel=0.6)


def hit_ricochet(d):
    plate = G.poly([(18, 56), (28, 56), (50, 14), (40, 14)])
    inc = kit.stroke([(9, 33.5), (30, 38)], 6)
    out = kit.arrow((30, 38), (52, 56), w=6, head_len=11, head_half=9)
    path = G.union(inc, out)
    path_vis = G.diff(path, G.grow(plate, 0.0))
    sil = G.union(plate, path)
    kit.check(sil, "hit_ricochet")
    d.keyline(sil, kit.KEY)
    d.plate(plate, "steel", bevel=1.6)
    d.keyline(path_vis, 0.9)
    d.plate(path, "apcr", bevel=1.2)
    spark = G.union([G.T(G.R(G.poly([(0, -1.2), (6, 0), (0, 1.2)]), a, (0, 0)), 30, 38) for a in (-120, -160)])
    d.keyline(spark, 0.8)
    d.plate(spark, "snow", bevel=0.5)


def hit_blocked(d):
    """Blocked: a shell flattened against a thick plate, sparks thrown back."""
    plate = G.cbox(37, 7, 51, 57, 2, 2, 2, 2)
    shell = G.union(G.rect(9, 27, 25, 37), G.poly([(25, 25.5), (35.5, 28), (35.5, 36), (25, 38.5)]))
    flat = G.rect(34.5, 24, 38, 40)
    sil = G.union(plate, shell, flat)
    kit.check(sil, "hit_blocked")
    d.keyline(sil, kit.KEY)
    d.plate(plate, "steel", bevel=1.6)
    d.plate(G.union(shell, flat), "gunmetal", bevel=1.2)
    for a in (-140, -112, 112, 140):
        sp = G.T(G.R(G.poly([(0, -1.5), (8, 0), (0, 1.5)]), a, (0, 0)), 33, 32)
        g = G.diff(sp, G.grow(G.union(shell, plate), 0.6))
        d.keyline(g, 0.7)
        d.plate(g, "snow", bevel=0.4)


def hit_critical(d):
    ring = kit.ring(32, 32, 23.6, 4.2, n=96)
    cog = G.diff(G.gear(32, 32, 12.5, 17.5, 9, tooth_frac=0.52, tip_frac=0.32, rot_deg=10), G.circle(32, 32, 5, n=32))
    pieces = kit.split(cog, (44, 14), (22, 52), gap=2.6, amp=2.8, shift=2.4)
    sil = G.union(ring, *[G.T(r, *o) for r, o in pieces])
    kit.check(sil, "hit_critical")
    d.keyline(sil, kit.KEY)
    d.plate(ring, "he", bevel=1.2)
    for r, o in pieces:
        d.plate(G.T(r, *o), "amber", bevel=1.4)


def hit_kill(d):
    ring = kit.ring(32, 32, 20, 5, n=96)
    ticks = G.union(G.rect(29.5, 6, 34.5, 13), G.rect(29.5, 51, 34.5, 58), G.rect(6, 29.5, 13, 34.5), G.rect(51, 29.5, 58, 34.5))
    x = kit.xmark(32, 32, 34, 8)
    sil = G.union(ring, ticks, x)
    kit.check(sil, "hit_kill")
    d.keyline(sil, kit.KEY)
    d.plate(G.union(ring, ticks), "signal", bevel=1.2)
    d.keyline(x, 1.0)
    d.plate(x, "bone", bevel=1.2)


def hit_fire(d):
    M.draw_fire(d)


def hit_track(d):
    """Track broken: the module track glyph in its destroyed treatment (crit callouts reuse the
    module glyph, brand-art.md 10.2)."""
    M.draw_module(d, "track", "destroyed")


def spotted_warning(d):
    """The brand's 'you are spotted' alert: dusk crest chevron with two expanding ripple arcs."""
    crest = G.chevron(32, 30, 20, 13, 8.5, flat_tip=4)
    r1 = kit.arc(32, 46, 22, 4.2, 222, 318, n=32)
    r2 = kit.arc(32, 46, 33, 4.2, 232, 308, n=40)
    sil = G.union(crest, r1, r2)
    sil, crest, r1, r2 = kit.shrink_to(sil, crest, r1, r2)
    kit.check(sil, "spotted_warning")
    d.keyline(sil, kit.KEY)
    d.plate(r2, "dusk", bevel=1.0)
    d.plate(r1, "dusk", bevel=1.0)
    d.plate(crest, "dusk", bevel=1.8)


def spotted_enemy():
    alm, pup = kit.eye(32, 32, 34, 19, 4.6)
    eye = G.diff(alm, G.diff(G.circle(32, 32, 8, n=48), G.circle(32, 32, 5, n=40)))
    rays = []
    for a in range(0, 360, 45):
        r0, r1 = (21, 28) if a % 90 == 0 else (20, 25.5)
        p0 = (32 + r0 * math.cos(math.radians(a)), 32 + r0 * math.sin(math.radians(a)))
        p1 = (32 + r1 * math.cos(math.radians(a)), 32 + r1 * math.sin(math.radians(a)))
        rays.append(G.thick_line(p0, p1, 4.4))
    return G.union(eye, G.diff(G.union(rays), G.grow(alm, 2.2)))


def damage_direction():
    """Indicator wedge on a 128 canvas, pointing outward at the top; rotate about the centre."""
    band = G.arc_band(64, 64, 60, 46, -112, -68, n=32)
    point = G.poly([(56, 6.5), (64, 2.5), (72, 6.5)])
    return G.union(band, point)


def stun():
    pts = []
    for i in range(0, 120):
        t = i / 119
        a = t * 2.15 * 2 * math.pi
        r = 3 + t * 20
        pts.append((32 + r * math.cos(a), 33 + r * math.sin(a)))
    sp = kit.stroke(pts, 5.0)
    return G.union(sp, G.circle(32, 33, 3.6, n=24))


def smoke_screen():
    puffs = [(20, 38, 12.5), (34, 28, 14.5), (47, 38, 11.5), (32, 44, 12)]
    g = G.union([G.ngon(x, y, r, 8, rot_deg=22.5) for x, y, r in puffs])
    g = G.diff(g, G.rect(0, 50, 64, 64))
    base = G.rect(10, 50, 54, 55)
    return G.T(G.union(g, base), 0, -2.6)  # centred on the canvas


# ---------------------------------------------------------------------------
# Reticle elements (white, ink outline, overlay tinting)
# ---------------------------------------------------------------------------
def reticle_center():
    dot = G.cbox(29.5, 29.5, 34.5, 34.5, 1.2, 1.2, 1.2, 1.2)
    ticks = G.union(G.rect(30.5, 10, 33.5, 22), G.rect(30.5, 42, 33.5, 54), G.rect(10, 30.5, 22, 33.5), G.rect(42, 30.5, 54, 33.5))
    return G.union(dot, ticks)


def reticle_dispersion_segment():
    """One of three dispersion-ring segments (100 deg + 20 deg gaps) on the full 128 ring canvas, at
    the top. The client places three copies rotated 0/120/240 about the centre; the number of lit
    segments is the penetration cue (3 likely, 2 marginal, 1 unlikely)."""
    band = kit.arc(64, 64, 56, 4.0, -140, -40, n=48)
    ends = G.union([G.T(G.R(G.rect(-5, -1.6, 5, 1.6), a, (0, 0)), 64 + 56 * math.cos(math.radians(a)),
                        64 + 56 * math.sin(math.radians(a))) for a in (-140, -40)])
    return G.union(band, ends)


def reticle_reload_arc_segment():
    """A 90 deg quarter of the reload arc (inner radius, thin) on the full 128 canvas, top-right
    quadrant. Four rotated copies make the ring; fill progress with a UIGradient transparency mask."""
    return kit.arc(64, 64, 47, 3.0, -90, 0, n=48)


def reticle_lock_bracket():
    """Top-left lock bracket on a 32 canvas; rotate by 90 deg steps for the other corners."""
    return G.poly([(4, 4), (22, 4), (22, 8.5), (8.5, 8.5), (8.5, 22), (4, 22)])


def _white(fn, check_box=(6, 6, 58, 58), key=kit.KEY):
    def draw(d):
        g = fn()
        x0, y0, x1, y1 = g.bounds
        if x0 < check_box[0] - 0.06 or y0 < check_box[1] - 0.06 or x1 > check_box[2] + 0.06 or y1 > check_box[3] + 0.06:
            g, = kit.shrink_to(g, box=check_box)
        d.keyline(g, key)
        d.path(g, "#FFFFFF")
    return draw


def _register():
    note("battle", "Battle HUD. 24 px minimap markers and 64 px command / status glyphs are WHITE: tint "
                   "with the team colour of the active CVD scheme (or a ping colour). Hit results and "
                   "`spotted_warning` are pre-coloured. Reticle pieces are white with an ink outline; "
                   "segment images keep the full ring canvas so copies rotate about the image centre.")
    mmk = [
        ("self", mm_self, "Minimap: own vehicle arrow (rotate with hull heading, draw on top, larger than pips)"),
        ("last_seen", mm_last_seen, "Minimap: last known position of a vehicle that dropped out of sight"),
        ("base_ally", lambda: mm_base(False), "Minimap: allied base (ring + flag)"),
        ("base_enemy", lambda: mm_base(True), "Minimap: enemy base (ring + flag + target ticks: shape cue)"),
        ("capture_point", lambda: mm_capture(False), "Minimap: capture point (segmented ring)"),
        ("capture_point_contested", lambda: mm_capture(True), "Minimap: capture point being contested (clashing heads)"),
        ("objective", mm_objective, "Minimap: mission / mode objective"),
        ("ping_attack", lambda: mm_ping("attack"), "Map ping: attack here"),
        ("ping_defend", lambda: mm_ping("defend"), "Map ping: defend here"),
        ("ping_help", lambda: mm_ping("help"), "Map ping: need help here"),
        ("ping_spotted", lambda: mm_ping("spotted"), "Map ping: enemy spotted here"),
        ("ping_position", lambda: mm_ping("position"), "Map ping: go to / I am here"),
    ]
    for key, fn, use in mmk:
        add("battle", key, f"Minimap: {key.replace('_', ' ')}", use, lambda d, fn=fn, k=key: mm(d, fn(), k), w=24, h=24,
            tint=True)
    add("battle", "camera_direction", "Minimap: camera direction cone",
        "Minimap: camera view cone; apex at the image centre, rotate with the camera yaw; ~35 % opacity",
        draw_camera, tint=True)
    add("battle", "view_range_ring", "Minimap: view range ring (dashed)",
        "Minimap: view-range guide ring; stretch the 128 px image to the view-range diameter", draw_view_range_ring,
        w=128, h=128, tint=True)
    cmds = [
        ("cmd_attack", cmd_attack, "Radial command: attack"),
        ("cmd_defend", cmd_defend, "Radial command: defend the base / position"),
        ("cmd_help", cmd_help, "Radial command: help!"),
        ("cmd_retreat", cmd_retreat, "Radial command: fall back"),
        ("cmd_enemy_spotted", cmd_enemy_spotted, "Radial command: enemy spotted"),
        ("cmd_capture", cmd_capture, "Radial command: capture the base"),
        ("cmd_follow_me", cmd_follow_me, "Radial command: follow me"),
        ("cmd_need_assistance", cmd_need_assistance, "Radial command: need assistance (rally to me)"),
        ("cmd_affirmative", cmd_affirmative, "Radial command: affirmative"),
        ("cmd_negative", cmd_negative, "Radial command: negative"),
        ("cmd_reloading", cmd_reloading, "Radial command: reloading"),
        ("cmd_ping_map", cmd_ping_map, "Radial command: open map ping"),
    ]
    for key, fn, use in cmds:
        add("battle", key, f"Command: {key[4:].replace('_', ' ')}", use, _white(fn), tint=True)
    hits = [
        ("hit_penetration", hit_penetration, "Hit callout / damage log: penetration (pierced plate)"),
        ("hit_ricochet", hit_ricochet, "Hit callout: ricochet (deflect arrow)"),
        ("hit_blocked", hit_blocked, "Hit callout: no penetration (blocked)"),
        ("hit_critical", hit_critical, "Hit callout: critical module / crew hit"),
        ("hit_kill", hit_kill, "Hit callout: target destroyed"),
        ("hit_fire", hit_fire, "Hit callout: target set on fire"),
        ("hit_track", hit_track, "Hit callout: track broken"),
    ]
    for key, fn, use in hits:
        add("battle", key, f"Hit result: {key[4:]}", use, fn)
    add("battle", "spotted_warning", "Status: you are spotted (dusk crest chevron)",
        "HUD: 'you are spotted' alert, top centre, 2 s (pre-coloured dusk)", spotted_warning)
    add("battle", "spotted_enemy", "Status: enemy spotted (eye burst)", "HUD: you spotted an enemy / spotting assist",
        _white(spotted_enemy), tint=True)
    add("battle", "damage_direction", "Status: damage direction wedge",
        "HUD: damage-direction wedge on a 128 canvas; rotate about the centre toward the shooter (red; white when blocked)",
        _white(damage_direction, check_box=(2, 2, 126, 126), key=1.5), w=128, h=128, tint=True)
    add("battle", "stun", "Status: stunned", "HUD: stunned (artillery splash)", _white(stun), tint=True)
    add("battle", "smoke_screen", "Status: in smoke", "HUD: inside a smoke screen / smoke deployed", _white(smoke_screen),
        tint=True)
    rets = [
        ("reticle_center", reticle_center, 64, "Reticle: centre dot + ticks"),
        ("reticle_dispersion_segment", reticle_dispersion_segment, 128,
         "Reticle: one of three dispersion-ring segments (rotate 0/120/240; lit count = penetration chance)"),
        ("reticle_reload_arc_segment", reticle_reload_arc_segment, 128,
         "Reticle: quarter reload arc (rotate 0/90/180/270; mask with UIGradient for progress)"),
        ("reticle_lock_bracket", reticle_lock_bracket, 32, "Reticle: target-lock corner bracket (rotate per corner)"),
    ]
    for key, fn, size, use in rets:
        box = (2, 2, size - 2, size - 2)
        add("battle", key, f"Reticle: {key[8:].replace('_', ' ')}", use, _white(fn, check_box=box, key=1.5),
            w=size, h=size, tint=True)


_register()
