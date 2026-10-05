"""UI glyphs (assets/icons/ui/): navigation, garage sections, actions, states, social, input.

Monochrome WHITE glyphs with a 2 px ink keyline, tinted at runtime with ImageColor3 (text.primary,
text.secondary, accent.dusk for the active item, state.* for status glyphs). Flat front, no bevel
(they are used at 16-32 px). Construction rules:

* 64 grid, live area 8..56 for outline glyphs (an optical inset of 2 px inside the icon live area),
  solid glyphs may use 6..58.
* One stroke weight: SW = 6 px (2.25 px at 24, 1.5 px at 16). Flat caps, mitre joins, 45-degree
  chamfers instead of round corners; circles only for true discs (lenses, wheels, clock faces).
* Single-stroke navigation chevrons are allowed here (open, one stroke): they never stack, so they
  never read as the filled XP / rank chevrons.
* Favourite is a bookmark ribbon (never a star); premium account is the dusk sun over the ridge;
  the platoon leader crown is a plain three-point circlet with flat chamfered tips and no jewels, so
  it never echoes the Crown Industries emblem.
"""

from __future__ import annotations

import math

from . import geom as G
from . import kit
from .kit import SW
from .registry import add, note

W = SW


def _s(pts, w=W, closed=False, cap="flat"):
    return kit.stroke(pts, w, cap=cap, closed=closed)


def _box_outline(x0, y0, x1, y1, c=4, w=W):
    outer = G.cbox(x0, y0, x1, y1, c, c, c, c)
    inner = G.cbox(x0 + w, y0 + w, x1 - w, y1 - w, max(c - w * 0.42, 0.5), max(c - w * 0.42, 0.5),
                   max(c - w * 0.42, 0.5), max(c - w * 0.42, 0.5))
    return G.diff(outer, inner)


def magnifier(cx=27, cy=27, r=14, w=W):
    ring = kit.ring(cx, cy, r, w, n=72)
    a = math.radians(45)
    p0 = (cx + (r + w / 2 - 1) * math.cos(a), cy + (r + w / 2 - 1) * math.sin(a))
    handle = G.thick_line(p0, (55, 55), w + 2.5)
    return G.union(ring, handle)


def person_g(cx, top, size):
    g, _, _ = kit.person(cx, top, size)
    return g


def glyph_fn(fn):
    def draw(d):
        g = fn()
        if isinstance(g, tuple):
            base, badge = g
            _, base, badge = kit.shrink_to(G.union(base, badge), base, badge, box=(6, 6, 58, 58))
            kit.check(G.union(base, badge), "ui")
            kit.glyph_cut(d, base, badge)
        else:
            g, = kit.shrink_to(g, box=(6, 6, 58, 58))
            kit.check(g, "ui")
            kit.glyph(d, g)
    return draw


# ---------------------------------------------------------------------------
# Glyph definitions
# ---------------------------------------------------------------------------
def garage():
    shell = _s([(10, 56), (10, 26), (32, 11), (54, 26), (54, 56)], W)
    slats = G.union([G.rect(20, y, 44, y + 4.2) for y in (33, 40.5, 48)])
    return G.union(shell, slats, G.rect(20, 52, 44, 56))


def battle():
    def barrel(p0, p1):
        a = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        deg = math.degrees(a)
        b = G.thick_line(p0, p1, 6.0)
        brake = G.T(G.R(G.rect(-5, -5.2, 5, 5.2), deg, (0, 0)), *p1)
        breech = G.T(G.R(G.rect(-5.5, -6.0, 5.5, 6.0), deg, (0, 0)), *p0)
        return G.union(b, brake, breech)
    a = barrel((15, 50), (47, 16))
    b = barrel((49, 50), (17, 16))
    return G.union(G.diff(a, G.grow(b, 2.0)), b)


def tech_tree():
    n1 = G.cbox(25, 8, 39, 22, 3, 3, 3, 3)
    n2 = G.cbox(8, 42, 22, 56, 3, 3, 3, 3)
    n3 = G.cbox(42, 42, 56, 56, 3, 3, 3, 3)
    link = _s([(32, 22), (32, 32)], 5) | _s([(15, 32), (49, 32)], 5) | _s([(15, 29.5), (15, 42)], 5) | _s([(49, 29.5), (49, 42)], 5)
    return G.union(n1, n2, n3, link)


def research():
    body = G.poly([(26, 12), (38, 12), (38, 25), (53, 50), (53, 56), (11, 56), (11, 50), (26, 25)])
    inner = G.shrink(body, W - 0.5)
    flask = G.diff(body, inner)
    liquid = G.inter(inner, G.rect(0, 40, 64, 64))
    rim = G.cbox(21, 7, 43, 12.5, 1.5, 1.5, 0, 0)
    return G.union(flask, G.shrink(liquid, 2.5), rim)


def store():
    bag = G.cbox(11, 23, 53, 56, 0, 0, 5, 5)
    handle = G.diff(_s([(22, 27), (22, 17), (26, 12), (38, 12), (42, 17), (42, 27)], 5), G.EMPTY)
    hole = G.union(G.circle(22, 31, 2.6, n=20), G.circle(42, 31, 2.6, n=20))
    return G.union(G.diff(bag, hole), G.diff(handle, G.rect(0, 23, 64, 64)))


def profile():
    tag = G.cbox(15, 8, 49, 57, 8, 8, 8, 8)
    hole = G.circle(32, 16, 3.4, n=32)
    lines = G.union(G.rect(21, 27, 43, 31), G.rect(21, 35, 43, 39), G.rect(21, 43, 36, 47))
    return G.diff(tag, hole, lines)


def missions():
    board = G.cbox(12, 12, 52, 58, 3, 3, 3, 3)
    clip = G.cbox(23, 6, 41, 17, 3, 3, 0, 0)
    cut = G.union(G.rect(16, 15, 48, 20))
    rows = []
    for i, y in enumerate((26, 36, 46)):
        rows.append(G.rect(30, y, 45, y + 4))
        rows.append(kit.checkmark(22, y + 2, 9, 3.2))
    board = G.diff(board, G.union(rows), G.grow(clip, 2.0))
    _ = cut
    return G.union(board, clip)


def achievements():
    disc = G.ngon(32, 25, 17, 12, rot_deg=15)
    inner = G.circle(32, 25, 7.5, n=40)
    tails = G.union(G.poly([(18, 34), (27, 37), (22, 57), (18, 52), (13, 55)]),
                    G.poly([(46, 34), (37, 37), (42, 57), (46, 52), (51, 55)]))
    return G.union(G.diff(tails, G.grow(disc, 2.0)), G.diff(disc, inner))


def settings():
    g = G.gear(32, 32, 18.5, 25.5, 8, tooth_frac=0.52, tip_frac=0.32, rot_deg=22.5)
    return G.diff(g, G.circle(32, 32, 8.5, n=48))


def notifications():
    bell = G.poly([(18, 44), (18, 28), (23, 18), (32, 14), (41, 18), (46, 28), (46, 44), (53, 51), (11, 51)])
    knob = G.cbox(28.5, 8, 35.5, 15, 2, 2, 0, 0)
    clap = G.cbox(26, 53.5, 38, 58, 0, 0, 2.5, 2.5)
    return G.union(bell, knob, clap)


def friends():
    back = person_g(22, 10, 36)
    front = person_g(40, 18, 38)
    return G.union(G.diff(back, G.grow(front, 2.2)), front)


def platoon():
    l = person_g(15, 14, 30)
    r = person_g(49, 14, 30)
    c = person_g(32, 18, 39)
    out = G.union(G.diff(G.union(l, r), G.grow(c, 2.2)), c)
    return out


def chat():
    bub = G.union(G.cbox(7, 10, 57, 45, 6, 6, 6, 6), G.poly([(16, 44), (29, 44), (14, 57)]))
    dots = G.union([G.cbox(x - 3.2, 24.3, x + 3.2, 30.7, 1.2, 1.2, 1.2, 1.2) for x in (20, 32, 44)])
    return G.diff(bub, dots)


def crew():
    shape, ribs, brow = kit.helmet(32, 9, 44, 46)
    gog = G.union(G.cbox(14.5, 36, 29, 45, 2.4, 2.4, 2.4, 2.4), G.cbox(35, 36, 49.5, 45, 2.4, 2.4, 2.4, 2.4))
    gog_gap = G.diff(G.grow(gog, 1.8), gog)  # goggles separated from the shell by an ink gap
    return G.diff(shape, ribs, gog_gap)


def equipment():
    """Equipment: a mountable module with connector pins and a gear window."""
    body = G.cbox(15, 13, 49, 51, 5, 5, 5, 5)
    pins = G.union([G.rect(7, y - 2.4, 15.5, y + 2.4) for y in (22, 32, 42)] +
                   [G.rect(48.5, y - 2.4, 57, y + 2.4) for y in (22, 32, 42)])
    cog = G.gear(32, 32, 8.2, 12.2, 8, tooth_frac=0.52, tip_frac=0.32, rot_deg=22.5)
    window = G.diff(G.grow(cog, 2.2), cog)
    hub = G.circle(32, 32, 3.4, n=24)
    return G.union(G.diff(G.union(body, pins), window, hub))


def ammo():
    return kit.shell_flat(32, 58, 52, 20)


def consumables():
    case = G.cbox(9, 24, 55, 55, 3, 3, 4, 4)
    handle = G.diff(_s([(22, 26), (22, 15), (42, 15), (42, 26)], 5.5), G.rect(0, 24, 64, 64))
    latch = G.union(G.rect(9, 35, 55, 38.5))
    clasp = G.cbox(27, 31, 37, 42.5, 1.5, 1.5, 1.5, 1.5)
    return G.union(G.diff(case, G.grow(clasp, 2.0), latch), clasp, handle)


def exterior():
    can = G.cbox(14, 24, 38, 58, 3, 3, 2, 2)
    neck = G.cbox(19, 17, 33, 24, 3, 3, 0, 0)
    nozzle = G.rect(22.5, 11, 29.5, 17)
    tip = G.rect(29.5, 11.5, 33, 14.5)
    label = G.rect(14, 33, 38, 36.5)
    spray = G.union([G.cbox(x - 2.2, y - 2.2, x + 2.2, y + 2.2, 0.8, 0.8, 0.8, 0.8)
                     for x, y in ((41, 13), (48, 9.5), (48, 17), (55, 13), (55, 6.5), (55, 20))])
    return G.union(G.diff(can, label), neck, nozzle, tip, spray)


def paint():
    roller = G.cbox(8, 8, 46, 23, 3, 3, 3, 3)
    arm = _s([(46, 15.5), (53, 15.5), (53, 31), (32, 31), (32, 38)], 4.5)
    grip = G.cbox(27.5, 37, 36.5, 58, 2, 2, 2, 2)
    return G.union(roller, arm, grip)


def camo_pattern():
    """A swatch cut by three angular disruptive stripes (camouflage pattern)."""
    tile = G.cbox(8, 8, 56, 56, 6, 6, 6, 6)
    stripes = G.union(
        G.poly([(2, 24), (14, 16), (24, 20), (34, 8), (40, 8), (27, 26), (15, 23), (2, 31)]),
        G.poly([(2, 44), (16, 34), (28, 38), (44, 22), (62, 18), (62, 24), (47, 28), (30, 45), (17, 41), (2, 51)]),
        G.poly([(22, 62), (34, 50), (46, 52), (62, 38), (62, 45), (48, 58), (36, 57), (29, 62)]),
    )
    return G.diff(tile, stripes)


def emblem():
    """Emblem decal: a sticker with a peeled corner, carrying a sun-over-ridge mark."""
    tile = G.poly([(8, 14), (14, 8), (56, 8), (56, 40), (40, 56), (8, 56)])
    fold = G.poly([(40, 56), (56, 40), (42, 42)])
    sun = G.circle(36, 22, 6.5, n=40)
    ridge = G.poly([(14, 46), (24, 32), (31, 38), (38, 31), (48, 42), (48, 46)])
    t = G.diff(tile, G.grow(fold, 2.0), sun, ridge)
    return G.union(t, fold)


def inscription():
    brush_h = G.T(G.R(G.cbox(-4, -15, 4, 9, 0, 0, 2, 2), 45, (0, 0)), 43, 21)
    ferrule = G.T(G.R(G.rect(-5, 9, 5, 14), 45, (0, 0)), 43, 21)
    tip = G.T(G.R(G.poly([(-5, 14), (5, 14), (0, 23)]), 45, (0, 0)), 43, 21)
    stroke = _s([(8, 50), (16, 44), (24, 50), (32, 44), (40, 50), (48, 44), (56, 50)], 5)
    return G.union(brush_h, G.diff(ferrule, G.EMPTY), tip, stroke)


def compare():
    a = kit.arrow((9, 21), (55, 21), w=6, head_len=12, head_half=10)
    b = kit.arrow((55, 43), (9, 43), w=6, head_len=12, head_half=10)
    return G.union(a, b)


def armor_inspect():
    """Armor thickness: a hatched plate cross-section with a dimension line across it."""
    plate = G.rect(22, 22, 42, 57)
    hatch = G.union([G.inter(G.T(G.R(G.rect(-14, -1.6, 14, 1.6), -45, (0, 0)), 32, y), G.shrink(plate, 3.5))
                     for y in (29, 38.5, 48)])
    ext = G.union(G.rect(22, 8, 26, 19), G.rect(38, 8, 42, 19))
    dim = G.union(kit.arrow((32, 12), (8, 12), w=4, head_len=8, head_half=6.5),
                  kit.arrow((32, 12), (56, 12), w=4, head_len=8, head_half=6.5))
    return G.union(G.diff(plate, hatch), G.diff(dim, G.grow(ext, 1.6)), ext)


def module_view():
    br = kit.corner_brackets(8, 8, 56, 56, 14, 5.5, chamfer=4)
    cog = G.diff(G.gear(32, 32, 9.5, 14, 8, tooth_frac=0.52, tip_frac=0.32, rot_deg=22.5), G.circle(32, 32, 4.5, n=32))
    return G.union(br, cog)


def rotate():
    return kit.arc_arrow(32, 33, 19, W, 150, 420, head_len=13, head_half=10)


def zoom_in():
    return G.union(magnifier(), kit.plus(27, 27, 15, 5))


def zoom_out():
    return G.union(magnifier(), G.rect(19.5, 24.5, 34.5, 29.5))


def filter_():
    return G.poly([(8, 10), (56, 10), (56, 14), (37, 33), (37, 50), (27, 56), (27, 33), (8, 14)])


def sort():
    bars = G.union(G.rect(8, 12, 40, 18), G.rect(8, 29, 32, 35), G.rect(8, 46, 22, 52))
    arr = kit.arrow((49, 10), (49, 56), w=6, head_len=12, head_half=9.5)
    return G.union(bars, arr)


def _ribbon():
    return G.poly([(15, 7), (49, 7), (49, 57), (32, 44), (15, 57)])


def favorite():
    r = _ribbon()
    return G.diff(r, G.poly([(21, 13), (43, 13), (43, 45.2), (32, 36.6), (21, 45.2)]))


def favorite_filled():
    return _ribbon()


def _lock_body():
    body = G.cbox(13, 28, 51, 57, 3, 3, 3, 3)
    hole = G.union(G.circle(32, 39, 4, n=24), G.rect(30.2, 40, 33.8, 49))
    return G.diff(body, hole)


def lock():
    shackle = G.diff(_s([(20, 30), (20, 18), (26, 10), (38, 10), (44, 18), (44, 30)], 6), G.EMPTY)
    return G.union(_lock_body(), shackle)


def unlocked():
    shackle = _s([(20, 30), (20, 11), (25, 6), (37, 6), (42, 11), (42, 18)], 6)
    return G.union(_lock_body(), G.diff(shackle, G.rect(0, 28, 64, 64)))


def check():
    return kit.checkmark(32, 33, 44, 8)


def close():
    return kit.xmark(32, 32, 38, 8)


def back():
    return kit.arrow((54, 32), (10, 32), w=7, head_len=17, head_half=15)


def forward():
    return kit.arrow((10, 32), (54, 32), w=7, head_len=17, head_half=15)


def _chev(direction):
    pts = [(14, 42), (32, 22), (50, 42)]
    g = _s(pts, 8, cap="flat")
    g = G.T(g, 0, 0)
    ang = {"up": 0, "right": 90, "down": 180, "left": 270}[direction]
    return G.R(g, ang, (32, 32))


def plus_():
    return kit.plus(32, 32, 44, 8)


def minus():
    return G.rect(10, 28, 54, 36)


def info():
    box = _box_outline(8, 8, 56, 56, 6, 5)
    dot = G.cbox(28.5, 15, 35.5, 22, 1.5, 1.5, 1.5, 1.5)
    stem = G.union(G.rect(28.5, 26, 35.5, 49), G.rect(24, 26, 30, 30), G.rect(24, 45, 40, 49))
    return G.union(box, dot, stem)


def warning():
    tri = G.poly([(32, 7), (59, 54), (5, 54)])
    tri = G.inter(tri, G.cbox(0, 0, 64, 64, 0, 0, 0, 0))
    tri = tri.buffer(-1.5, join_style=2).buffer(1.5, join_style=3)
    bang = G.union(G.poly([(28.6, 22), (35.4, 22), (34.2, 38), (29.8, 38)]), G.rect(29, 42, 35, 48))
    return G.diff(tri, bang)


def error():
    octo = G.ngon(32, 32, 26.5, 8, rot_deg=22.5)
    bang = G.union(G.poly([(28.6, 15), (35.4, 15), (34.2, 36), (29.8, 36)]), G.rect(29, 41, 35, 48))
    return G.diff(octo, bang)


def help_():
    ring = kit.ring(32, 32, 22.5, 5, n=96)
    hook = kit.arc(32, 25, 7.0, 5.4, 180, 360, n=24)
    tail = G.union(G.poly([(36.3, 24.5), (41.7, 24.5), (41.7, 26.5), (35.2, 33.6), (35.2, 38.5), (29.8, 38.5),
                           (29.8, 31.6), (36.3, 25.6)]))
    dot = G.rect(29.6, 42, 35.4, 47.8)
    return G.union(ring, hook, tail, dot)


def search():
    return magnifier()


def menu():
    return G.union([G.rect(10, y, 54, y + 6.5) for y in (13, 28.75, 44.5)])


def home():
    house = G.poly([(32, 7), (57, 30), (51, 30), (51, 57), (13, 57), (13, 30), (7, 30)])
    door = G.rect(27, 40, 37, 57)
    return G.diff(house, door)


def exit_():
    frame = _s([(36, 18), (36, 9), (11, 9), (11, 55), (36, 55), (36, 46)], 5.5)
    arr = kit.arrow((22, 32), (57, 32), w=6, head_len=12, head_half=10)
    return G.union(frame, arr)


def refresh():
    a = kit.arc_arrow(32, 32, 19, 5.5, 200, 340, head_len=11, head_half=8.5)
    b = kit.arc_arrow(32, 32, 19, 5.5, 20, 160, head_len=11, head_half=8.5)
    return G.union(a, b)


def timer():
    ring = kit.ring(32, 35, 19, 5.5, n=96)
    btn = G.union(G.rect(27, 7, 37, 11), G.rect(30, 10, 34, 16))
    side = G.T(G.R(G.rect(-3, -2.2, 3, 2.2), 45, (0, 0)), 48.5, 17.5)
    hand = G.union(G.thick_line((32, 35), (40, 25), 4.5), G.circle(32, 35, 3.6, n=24))
    return G.union(ring, btn, side, hand)


def hp():
    return G.poly([(32, 56), (8, 32), (8, 20), (16, 11), (25, 11), (32, 18), (39, 11), (48, 11), (56, 20), (56, 32)])


def damage():
    """Damage dealt: an armour plate punched through, cracks radiating from a ragged hole."""
    plate = G.cbox(8, 8, 56, 56, 8, 3, 8, 3)
    hole = G.poly([(30, 20), (37, 24), (44, 23), (41, 31), (45, 38), (37, 39), (33, 45), (28, 39), (20, 40), (24, 32),
                   (20, 25), (27, 26)])
    cracks = G.union([G.R(G.poly([(13, -1.6), (27, 0), (13, 1.6)]), a, (0, 0)) for a in (-60, 25, 130, 205)])
    cracks = G.T(cracks, 32.5, 32)
    return G.diff(plate, hole, cracks)


def xp_bonus():
    a = G.chevron(26, 10, 18, 11, 7, flat_tip=3)
    b = G.chevron(26, 22, 18, 11, 7, flat_tip=3)
    pl = kit.plus(49, 46, 15, 5)
    base = G.union(a, b)
    return base, pl


def premium():
    sun = G.diff(G.circle(32, 36, 15, n=96), G.rect(0, 36.5, 64, 64))
    rays = G.union([G.T(G.R(G.rect(-2.2, -24.5, 2.2, -18.5), a, (0, 0)), 32, 36) for a in (-60, -30, 0, 30, 60)])
    ridge = _s([(6, 49), (16, 44), (25, 40.5), (37, 40.5), (47, 45), (58, 47)], 5.5)
    base = G.union(G.diff(sun, G.grow(ridge, 2.0)), G.diff(rays, G.grow(ridge, 2.0)))
    return G.union(base, ridge)


def clock():
    ring = kit.ring(32, 32, 21.5, 5.5, n=96)
    hands = G.union(G.rect(29.5, 16, 34.5, 34.5), G.rect(29.5, 29.5, 45, 34.5))
    return G.union(ring, hands)


def calendar():
    page = G.cbox(8, 12, 56, 57, 3, 3, 3, 3)
    head = G.rect(8, 12, 56, 23)
    rings = G.union(G.rect(18, 6, 23, 16), G.rect(41, 6, 46, 16))
    cells = G.union([G.rect(14 + c * 10, 28 + r * 9, 20 + c * 10, 33 + r * 9) for r in range(3) for c in range(4)])
    body = G.diff(page, cells, G.grow(rings, 1.8))
    return G.union(body, rings)


def trophy():
    cup = G.poly([(17, 8), (47, 8), (47, 22), (41, 32), (35, 35), (29, 35), (23, 32), (17, 22)])
    handles = G.union(_s([(17, 13), (9, 13), (9, 21), (17, 27)], 4.5), _s([(47, 13), (55, 13), (55, 21), (47, 27)], 4.5))
    stem = G.rect(29, 34, 35, 45)
    base = G.union(G.cbox(21, 45, 43, 50, 1.5, 1.5, 0, 0), G.rect(16, 50, 48, 57))
    return G.union(cup, handles, stem, base)


def medal():
    ribbon = G.union(G.poly([(16, 6), (27, 6), (36, 26), (29, 30)]), G.poly([(48, 6), (37, 6), (28, 26), (35, 30)]))
    disc = G.ngon(32, 41, 16, 10, rot_deg=18)
    inner = G.diff(G.ngon(32, 41, 9.5, 10, rot_deg=18), G.ngon(32, 41, 6.5, 10, rot_deg=18))
    return G.union(G.diff(ribbon, G.grow(disc, 2.0)), G.diff(disc, inner))


def gift():
    box = G.union(G.rect(11, 30, 53, 57), G.rect(8, 21, 56, 30))
    split = G.union(G.rect(29.5, 21, 34.5, 57), G.rect(8, 29, 56, 31.4))
    bow = G.union(G.poly([(32, 21), (19, 9), (14, 14), (21, 21)]), G.poly([(32, 21), (45, 9), (50, 14), (43, 21)]))
    return G.union(G.diff(box, split), G.diff(bow, G.EMPTY))


def cart():
    basket = G.poly([(16, 15), (58, 15), (52, 38), (21, 38)])
    handle = _s([(5, 9), (13, 9), (22, 44), (50, 44)], 5)
    wheels = G.union(G.circle(25, 52, 4.6, n=32), G.circle(46, 52, 4.6, n=32))
    slots = G.union(G.rect(28, 20, 32, 33), G.rect(37, 20, 41, 33), G.rect(46, 20, 49, 33))
    return G.union(G.diff(basket, slots), handle, wheels)


def sell():
    tag = G.poly([(30, 7), (56, 7), (56, 33), (31, 58), (6, 33)])
    hole = G.circle(46, 17, 4, n=24)
    minus_g = G.T(G.R(G.rect(-9, -2.6, 9, 2.6), -45, (0, 0)), 29, 34)
    return G.diff(tag, hole, minus_g)


def repair():
    return kit.wrench(32, 32, 58, 8.5, ang=-45, jaw=21)


def upgrade():
    arr = kit.arrow((32, 46), (32, 7), w=11, head_len=17, head_half=19)
    bar = G.rect(12, 50, 52, 57)
    return G.union(arr, bar)


def download():
    arr = kit.arrow((32, 6), (32, 42), w=9, head_len=16, head_half=16)
    tray = _s([(9, 40), (9, 55), (55, 55), (55, 40)], 6)
    return G.union(arr, tray)


def invite():
    return person_g(26, 9, 46), kit.plus(48, 46, 18, 6)


def kick():
    return person_g(26, 9, 46), kit.xmark(48, 47, 14, 5.5)


def crown_leader():
    band = G.cbox(9, 42, 55, 54, 0, 0, 3, 3)
    pts = G.poly([(9, 43), (9, 20), (20, 31), (32, 13), (44, 31), (55, 20), (55, 43)])
    tips = G.union([G.cbox(x - 3.2, y - 3.2, x + 3.2, y + 3.2, 1.6, 1.6, 1.6, 1.6) for x, y in ((9, 18), (32, 11), (55, 18))])
    _ = tips
    crown = G.union(band, pts)
    crown = G.inter(crown, G.rect(6, 6, 58, 58))
    crown = G.diff(crown, G.rect(9, 39.5, 55, 42.3))
    return crown


def ready():
    ring = kit.oct_ring(32, 32, 23, 5.5)
    return G.union(ring, kit.checkmark(32, 33, 25, 6.5))


def not_ready():
    ring = kit.oct_ring(32, 32, 23, 5.5)
    glass = G.union(G.poly([(22, 18), (42, 18), (32, 32)]), G.poly([(32, 32), (42, 46), (22, 46)]))
    caps = G.union(G.rect(20, 15, 44, 19), G.rect(20, 45, 44, 49))
    return G.union(ring, glass, caps)


def microphone_off():
    cap = G.cbox(23, 6, 41, 37, 7, 7, 7, 7)
    cradle = _s([(15, 29), (15, 36), (21, 44), (43, 44), (49, 36), (49, 29)], 5)
    stem = G.union(G.rect(29.5, 44, 34.5, 53), G.rect(21, 52, 43, 57))
    mic = G.union(cap, cradle, stem)
    slash = G.thick_line((9, 9), (55, 55), 6)
    return G.union(G.diff(mic, G.grow(slash, 2.6)), slash)


def volume():
    spk = G.poly([(7, 24), (17, 24), (31, 11), (31, 53), (17, 40), (7, 40)])
    w1 = kit.arc(30, 32, 12, 5, -45, 45, n=24)
    w2 = kit.arc(30, 32, 22, 5, -45, 45, n=32)
    return G.union(spk, w1, w2)


def controller():
    body = G.poly([(14, 18), (50, 18), (57, 26), (59, 45), (54, 50), (46, 47), (41, 41), (23, 41), (18, 47), (10, 50), (5, 45),
                   (7, 26)])
    dpad = kit.plus(19, 30, 11, 3.6)
    btns = G.union([G.circle(x, y, 2.2, n=16) for x, y in ((45, 26), (50, 31), (40, 31), (45, 36))])
    return G.diff(body, dpad, btns)


def keyboard():
    body = G.cbox(5, 15, 59, 50, 3, 3, 3, 3)
    keys = []
    for r, (y, n, x0) in enumerate(((20, 7, 9), (28, 7, 11), (36, 7, 9))):
        for c in range(n):
            keys.append(G.rect(x0 + c * 6.8, y, x0 + c * 6.8 + 4, y + 4.2))
    keys.append(G.rect(18, 43, 46, 46.6))
    return G.diff(body, G.union(keys))


def touch():
    finger = G.cbox(27, 22, 37, 50, 4, 4, 0, 0)
    palm = G.union(G.cbox(22, 38, 50, 59, 2, 2, 3, 3), G.cbox(37, 33, 44, 44, 2.5, 2.5, 0, 0),
                   G.cbox(44, 35, 51, 44, 2.5, 2.5, 0, 0))
    thumb = G.poly([(22, 40), (14, 34), (11, 38), (18, 48), (22, 50)])
    hand = G.union(finger, palm, thumb)
    rip = G.union(kit.arc(32, 25, 11, 4, 200, 340, n=24), kit.arc(32, 25, 19, 4, 210, 330, n=32))
    return G.union(G.diff(hand, G.EMPTY), G.diff(rip, G.grow(hand, 2.0)))


GLYPHS = [
    # navigation / sections
    ("home", home, "Home / main hub"),
    ("garage", garage, "Garage section tab"),
    ("battle", battle, "Battle / play section, battle mode selector"),
    ("tech_tree", tech_tree, "Tech tree section"),
    ("research", research, "Research action / research-available badge"),
    ("store", store, "Store section"),
    ("profile", profile, "Player profile / service record (dog tag)"),
    ("missions", missions, "Missions section"),
    ("achievements", achievements, "Achievements section"),
    ("settings", settings, "Settings"),
    ("notifications", notifications, "Notification centre"),
    ("friends", friends, "Friends list"),
    ("platoon", platoon, "Platoon (squad) panel"),
    ("chat", chat, "Chat"),
    ("crew", crew, "Crew section (garage)"),
    ("equipment", equipment, "Equipment section (garage)"),
    ("ammo", ammo, "Ammunition section (garage)"),
    ("consumables", consumables, "Consumables section (garage)"),
    ("exterior", exterior, "Exterior / customization section"),
    ("paint", paint, "Paint (customization)"),
    ("camo_pattern", camo_pattern, "Camouflage pattern (customization)"),
    ("emblem", emblem, "Emblem decal (customization)"),
    ("inscription", inscription, "Inscription (customization)"),
    ("compare", compare, "Compare vehicles"),
    ("armor_inspect", armor_inspect, "Armor inspector"),
    ("module_view", module_view, "Module / X-ray view"),
    ("rotate", rotate, "Rotate camera / vehicle"),
    ("zoom_in", zoom_in, "Zoom in"),
    ("zoom_out", zoom_out, "Zoom out"),
    ("filter", filter_, "Filter list"),
    ("sort", sort, "Sort list"),
    ("favorite", favorite, "Favourite (off): bookmark ribbon"),
    ("favorite_filled", favorite_filled, "Favourite (on)"),
    ("lock", lock, "Locked item / requirement not met"),
    ("unlocked", unlocked, "Unlocked"),
    # generic actions
    ("check", check, "Confirm / done (tint state.success)"),
    ("close", close, "Close / cancel"),
    ("back", back, "Back"),
    ("forward", forward, "Forward / next"),
    ("chevron_up", lambda: _chev("up"), "Expand up / scroll up"),
    ("chevron_down", lambda: _chev("down"), "Expand / dropdown"),
    ("chevron_left", lambda: _chev("left"), "Previous / carousel left"),
    ("chevron_right", lambda: _chev("right"), "Next / carousel right"),
    ("plus", plus_, "Add / increase"),
    ("minus", minus, "Remove / decrease"),
    ("info", info, "Info (tint state.info)"),
    ("warning", warning, "Warning (tint state.warning)"),
    ("error", error, "Error (tint state.danger)"),
    ("help", help_, "Help / tutorial"),
    ("search", search, "Search"),
    ("menu", menu, "Menu"),
    ("exit", exit_, "Exit / leave"),
    ("refresh", refresh, "Refresh / retry"),
    ("timer", timer, "Timer / countdown"),
    ("clock", clock, "Time / duration"),
    ("calendar", calendar, "Date / schedule"),
    # stats and economy
    ("hp", hp, "Hit points stat"),
    ("damage", damage, "Damage stat"),
    ("xp_bonus", xp_bonus, "XP bonus / booster (tint currency.vehicle_xp)"),
    ("premium", premium, "Premium account (tint accent.dusk or currency.bullion)"),
    ("trophy", trophy, "Trophy / season reward"),
    ("medal", medal, "Medal / award"),
    ("gift", gift, "Gift / reward crate"),
    ("cart", cart, "Add to cart / purchase"),
    ("sell", sell, "Sell"),
    ("repair", repair, "Repair action"),
    ("upgrade", upgrade, "Upgrade / level up"),
    ("download", download, "Download / install"),
    # social
    ("invite", invite, "Invite to platoon"),
    ("kick", kick, "Kick from platoon"),
    ("crown_leader", crown_leader, "Platoon leader"),
    ("ready", ready, "Player ready (tint state.success)"),
    ("not_ready", not_ready, "Player not ready / waiting"),
    ("microphone_off", microphone_off, "Voice muted"),
    ("volume", volume, "Volume / audio settings"),
    # input
    ("controller", controller, "Gamepad input"),
    ("keyboard", keyboard, "Keyboard + mouse input"),
    ("touch", touch, "Touch input"),
]


def _register():
    note("ui", "Monochrome white glyphs with an ink keyline, tinted at runtime with ImageColor3 "
               "(text.secondary idle, text.primary hover, accent.dusk active, state.* for status). "
               "Use at 16-32 px; upload @64 for 16-24 px, @128 above.")
    for key, fn, use in GLYPHS:
        add("ui", key, f"UI: {key.replace('_', ' ')}", use, glyph_fn(fn), tint=True)


_register()
