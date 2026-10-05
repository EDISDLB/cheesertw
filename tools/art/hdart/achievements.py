"""Achievement art (assets/icons/achievements/): rarity frames, category emblems, mastery badges.

Composition: the client stacks two 64 px images of the same size, frame_<rarity> below and
emblem_<category> on top. Every frame has the same dark WELL, a disc of radius 15.5 centred at
(32, 31); every emblem stays inside a radius-13.5 circle at that centre. Frames escalate by
material AND outline, like the tier plates:

    frame_common     steel octagonal ring
    frame_rare       blue enamel ring, steel rim, two side lugs
    frame_epic       violet enamel ring, silver rim, side wings and a crest tab
    frame_legendary  obsidian ring with a dusk inner rim and gold trim, wings, a tall ridge crest,
                     a keel point and the radial dusk glow (the only glowing frame)

Mastery badges (vehicle mastery, original design): an olive-drab gun barrel crossing a medallion,
carrying metal KILL RINGS slightly proud of the barrel. Class III = 1 bronze ring, II = 2 silver,
I = 3 gold, Ace = 3 gold rings on an obsidian medallion with a dusk sun and ridge. The outline
escalates as well (III plain, II + side lugs, I + plinth, Ace + stepped crest plinth + glow), so the
class reads without colour. The barrel breaking the medallion's top edge is the family silhouette
(no laurels, no stars, no figures).
"""

from __future__ import annotations

import math

from . import geom as G
from . import kit
from .registry import add, note
from .tokens import INK, MATERIALS, UI

WELL_C = (32.0, 31.0)
WELL_R = 15.5
EMB_R = 13.5


def _oct(cx, cy, r):
    return G.ngon(cx, cy, r, 8, rot_deg=22.5)


def frame_shapes(rarity):
    c = WELL_C
    ring = _oct(*c, 23.5)
    parts = {"ring": ring}
    if rarity in ("rare", "epic", "legendary"):
        lugs = G.union(G.cbox(5.5, 26, 12, 36, 2, 0, 0, 2), G.cbox(52, 26, 58.5, 36, 0, 2, 2, 0))
        parts["lugs"] = lugs
    if rarity in ("epic", "legendary"):
        wing = G.poly([(10, 22), (5, 18), (5, 44), (10, 40)])
        parts["wings"] = G.union(wing, G.mirror_x(wing, 32))
        parts.pop("lugs", None)
        crest = G.poly([(24, 9.5), (28, 5), (36, 5), (40, 9.5)])
        if rarity == "legendary":
            crest = G.poly([(21, 11), (26.5, 4.5), (37.5, 4.5), (43, 11)])
        parts["crest"] = crest
    if rarity == "legendary":
        parts["keel"] = G.poly([(25, 52), (39, 52), (32, 59)])
    return parts


def draw_frame(d, rarity):
    mats = {
        "common": ("steel", "steel"),
        "rare": ("r_rare", "steel"),
        "epic": ("r_epic", "silver"),
        "legendary": ("obsidian", "gold"),
    }
    enamel, trim = mats[rarity]
    parts = frame_shapes(rarity)
    sil = G.union(list(parts.values()))
    kit.check(sil, f"frame_{rarity}", lo=4.0, hi=60.0)
    if rarity == "legendary":
        glow = d.radial([(0, UI["accent.dusk"], 0.5), (0.6, UI["accent.dusk"], 0.16), (1, UI["accent.dusk"], 0)], 32, 31, 30)
        d.path(G.chamfer_all(2, 2, 62, 62, 12), glow)
    d.keyline(sil, kit.KEY)
    for k in ("wings", "lugs", "keel", "crest"):
        if k in parts:
            m = "dusk" if (k in ("keel", "crest") and rarity == "legendary") else trim
            d.plate(parts[k], m, bevel=1.3)
    ring = parts["ring"]
    if rarity == "common":
        face = d.plate(ring, "steel", bevel=kit.BEV)
    else:
        d.plate(ring, trim, bevel=1.6)
        inner = G.shrink(ring, 2.6)
        d.keyline(inner, 0.6, INK, 0.9)
        face = d.plate(inner, enamel, bevel=1.2)
    if rarity == "legendary":
        rim = G.diff(G.circle(*WELL_C, WELL_R + 2.6, n=96), G.circle(*WELL_C, WELL_R + 1.2, n=96))
        d.path(rim, UI["accent.dusk"])
        mark = G.diff(G.poly([(26.5, 9.6), (30.0, 6.8), (34.0, 6.8), (37.5, 9.6)]),
                      G.poly([(28.2, 10.2), (30.8, 8.2), (33.2, 8.2), (35.8, 10.2)]))
        d.engrave(G.inter(mark, parts["crest"]), "dusk", parts["crest"], depth=0.6)
    # rivets at the four diagonal facets
    for a in (45, 135, 225, 315):
        x = WELL_C[0] + 20.0 * math.cos(math.radians(a))
        y = WELL_C[1] + 20.0 * math.sin(math.radians(a))
        d.engrave(G.cbox(x - 1.1, y - 1.1, x + 1.1, y + 1.1, 0.5, 0.5, 0.5, 0.5), enamel if rarity != "common" else "steel",
                  face, depth=0.6)
    # the well: a recessed dark disc where the emblem sits
    well = G.circle(*WELL_C, WELL_R, n=96)
    d.path(G.T(G.grow(well, 0.8), 0.9, 0.9), MATERIALS[enamel if rarity != "common" else "steel"][0], 0.9)
    d.path(G.grow(well, 0.8), INK)
    d.path(well, d.linear([(0, MATERIALS["obsidian"][1], 1), (1, MATERIALS["obsidian"][2], 1)], 0, 15, 0, 47))


# ---------------------------------------------------------------------------
# Category emblems (bone, inside the well)
# ---------------------------------------------------------------------------
def _hull(cx, cy, w):
    """Generic vehicle side profile, gun to the right (NOT the brand turret)."""
    k = w / 40.0
    hull = G.poly([(-20, 2), (-17, -3), (15, -3), (20, 2), (16, 7), (-17, 7)])
    tur = G.poly([(-9, -3), (-7, -9), (6, -9), (9, -3)])
    gun = G.rect(8, -8, 22, -5.6)
    wheels = G.union([G.circle(x, 4.6, 2.0, n=16) for x in (-12, -6, 0, 6, 12)])
    g = G.diff(G.union(hull, tur, gun), wheels)
    return G.T(G.S(g, k, k, origin=(0, 0)), cx, cy)


def emblem_shape(cat):
    c = WELL_C
    if cat == "combat":
        def barrel(p0, p1):
            deg = math.degrees(math.atan2(p1[1] - p0[1], p1[0] - p0[0]))
            return G.union(G.thick_line(p0, p1, 3.4), G.T(G.R(G.rect(-3, -3, 3, 3), deg, (0, 0)), *p1),
                           G.T(G.R(G.rect(-3.2, -3.6, 3.2, 3.6), deg, (0, 0)), *p0))
        a = barrel((23, 40), (41, 22))
        b = barrel((41, 40), (23, 22))
        g = G.union(G.diff(a, G.grow(b, 1.2)), b)
    elif cat == "progression":
        steps = G.union(G.rect(20, 34, 26, 41), G.rect(27, 29, 33, 41), G.rect(34, 24, 40, 41))
        arr = kit.arrow((21, 29), (42, 19), w=3.2, head_len=6.5, head_half=5)
        g = G.union(steps, G.diff(arr, G.grow(steps, 1.2)))
    elif cat == "vehicles":
        g = _hull(c[0] - 1.5, c[1] + 2, 25)
    elif cat == "exploration":
        ring = kit.ring(*c, 10.5, 2.6, n=64)
        needle = G.union(G.poly([(c[0], c[1] - 9), (c[0] + 3.2, c[1]), (c[0] - 3.2, c[1])]))
        tail = G.poly([(c[0], c[1] + 9), (c[0] + 3.2, c[1]), (c[0] - 3.2, c[1])])
        ticks = G.union(G.rect(c[0] - 1, c[1] - 14.2, c[0] + 1, c[1] - 11.5))
        g = G.union(ring, needle, G.diff(tail, G.circle(*c, 1.0)), ticks)
        g = G.diff(g, G.circle(*c, 1.2, n=16))
    elif cat == "teamwork":
        a = G.diff(G.cbox(18, 25, 34, 37, 4, 4, 4, 4), G.cbox(21, 28, 31, 34, 2, 2, 2, 2))
        b = G.diff(G.cbox(30, 25, 46, 37, 4, 4, 4, 4), G.cbox(33, 28, 43, 34, 2, 2, 2, 2))
        cut = G.rect(29.5, 23, 31.5, 30)
        g = G.union(G.diff(a, G.grow(G.inter(b, G.rect(0, 30, 64, 64)), 1.0)), G.diff(b, G.grow(G.inter(a, G.rect(0, 0, 64, 31)), 1.0)))
        _ = cut
    elif cat == "skill":
        ring = kit.ring(*c, 9.5, 2.4, n=64)
        ticks = G.union(G.rect(c[0] - 1.1, c[1] - 14, c[0] + 1.1, c[1] - 7), G.rect(c[0] - 1.1, c[1] + 7, c[0] + 1.1, c[1] + 14),
                        G.rect(c[0] - 14, c[1] - 1.1, c[0] - 7, c[1] + 1.1), G.rect(c[0] + 7, c[1] - 1.1, c[0] + 14, c[1] + 1.1))
        hit = G.ngon(c[0] + 2.5, c[1] - 2.5, 3.0, 8, rot_deg=22.5)
        g = G.union(ring, ticks, hit)
    elif cat == "collection":
        cards = []
        for i, (dx, dy) in enumerate(((-6, 4), (0, 0), (6, -4))):
            cards.append(G.cbox(c[0] - 6 + dx, c[1] - 8 + dy, c[0] + 6 + dx, c[1] + 8 + dy, 2, 0, 2, 0))
        g = cards[0]
        for cd in cards[1:]:
            g = G.union(G.diff(g, G.grow(cd, 1.2)), cd)
    elif cat == "events":
        pole = G.rect(22.5, 19, 25.5, 43)
        knob = G.cbox(21.5, 17, 26.5, 20.5, 1.2, 1.2, 0, 0)
        fl = G.poly([(25.5, 20), (43, 20), (38, 26), (43, 32), (25.5, 32)])
        g = G.union(pole, knob, fl)
    else:
        raise KeyError(cat)
    return g


def draw_emblem(d, cat):
    g = emblem_shape(cat)
    x0, y0, x1, y1 = g.bounds
    # keep inside the emblem circle
    far = max(math.hypot(x - WELL_C[0], y - WELL_C[1]) for x, y in G.points_iter(g))
    if far > EMB_R:
        g = G.S(g, EMB_R / far, EMB_R / far, origin=WELL_C)
    d.keyline(g, 1.4)
    d.plate(g, "bone", bevel=0.9)


# ---------------------------------------------------------------------------
# Mastery badges
# ---------------------------------------------------------------------------
def draw_mastery(d, level):
    """level: 3, 2, 1 or 'ace'. A gun barrel crosses the medallion diagonally; its ported muzzle
    brake breaks out of the top-right edge, and painted kill rings count the class."""
    ace = level == "ace"
    rings = {3: 1, 2: 2, 1: 3, "ace": 3}[level]
    mat = {3: "bronze", 2: "silver", 1: "gold", "ace": "gold"}[level]
    disc_mat = {3: "gunmetal", 2: "gunmetal", 1: "gunmetal", "ace": "obsidian"}[level]
    c = (30, 35)
    disc = G.ngon(*c, 19.5, 16, rot_deg=11.25)
    parts = [disc]
    notches = None
    if level in (2, 1, "ace"):
        # side lugs: the first outline step (Class II and up), big enough to read at 24 px
        notches = G.union(G.cbox(6.0, 28, 13, 42, 3.0, 0, 0, 3.0), G.cbox(47, 28, 55, 42, 0, 3.0, 3.0, 0))
        parts.append(notches)
    crest = None
    if level in (1, "ace"):
        crest = G.poly([(14, 50), (10, 57), (50, 57), (46, 50)])
        if ace:
            crest = G.poly([(12, 49), (8, 57.5), (24, 55.5), (30, 58), (36, 55.5), (52, 57.5), (48, 49)])
        parts.append(crest)
    ang = -45.0
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    base = (17.0, 48.0)

    def at(t):
        return (base[0] + ux * t, base[1] + uy * t)

    barrel = G.union(G.thick_line(at(0), at(36), 6.4), G.thick_line(at(0), at(9), 8.4))
    brake = G.T(G.R(G.cbox(-6.0, -6.4, 6.0, 6.4, 1.6, 1.6, 1.6, 1.6), ang, (0, 0)), *at(39.5))
    ports = G.T(G.R(G.union(G.rect(-3.4, -6.6, -1.8, -3.2), G.rect(0.6, -6.6, 2.2, -3.2), G.rect(-3.4, 3.2, -1.8, 6.6),
                            G.rect(0.6, 3.2, 2.2, 6.6)), ang, (0, 0)), *at(39.5))
    brake = G.diff(brake, ports)
    gun = G.union(barrel, brake)
    sil = G.union(parts + [gun])
    sil_check = sil
    kit.check(sil_check, f"mastery_{level}")
    if ace:
        glow = d.radial([(0, UI["accent.dusk"], 0.45), (0.6, UI["accent.dusk"], 0.14), (1, UI["accent.dusk"], 0)], 32, 32, 31)
        d.path(G.chamfer_all(2, 2, 62, 62, 12), glow)
    d.keyline(sil, kit.KEY)
    if crest is not None:
        d.plate(crest, mat, bevel=1.3)
    if notches is not None:
        d.plate(notches, mat, bevel=1.1)
    d.plate(disc, mat, bevel=1.6)
    inner = G.shrink(disc, 3.0)
    d.keyline(inner, 0.6, INK, 0.9)
    face = d.plate(inner, disc_mat, bevel=1.2)
    if ace:
        sun = G.inter(G.circle(30, 37, 13.5, n=72), G.shrink(disc, 3.4))
        d.inlay(G.diff(sun, G.rect(0, 37.5, 64, 64)), "dusk", face, bevel=0.9, shadow=(0.8, 1.0))
        ridge = G.inter(G.poly([(9, 44), (18, 38.5), (40, 38), (50, 43), (50, 50), (9, 50)]), G.shrink(disc, 3.4))
        d.inlay(ridge, "obsidian", face, bevel=0.6, shadow=(0.6, 0.8))
    d.cast_shadow(gun, inner, 1.4, 1.6, opacity=0.6)
    d.keyline(gun, 1.0)
    # olive-drab barrel so the metal kill rings stand out (silver on steel would vanish)
    d.plate(barrel, "olive", bevel=1.1)
    d.plate(brake, "steel", bevel=1.1)
    for i in range(rings):
        t = 13.0 + i * 6.4
        # rings are a touch wider than the barrel, so the count also shows in the outline
        band = G.T(G.R(G.rect(-2.0, -4.1, 2.0, 4.1), ang, (0, 0)), *at(t))
        d.keyline(band, 0.8)
        d.plate(band, mat, bevel=0.6)


def draw_composite(d, rarity, cat):
    draw_frame(d, rarity)
    draw_emblem(d, cat)


def _register():
    note("achievements", "Composite `frame_<rarity>` (below) + `emblem_<category>` (above) at the same "
                         "size; the emblem sits in the frame's dark well (r 15.5 at 32,31). Mastery badges "
                         "are standalone.")
    for r in ("common", "rare", "epic", "legendary"):
        add("achievements", f"frame_{r}", f"Achievement frame: {r}",
            f"Achievement medal frame, {r} rarity (rarity.{r if r != 'common' else 'common'} family)",
            lambda d, r=r: draw_frame(d, r))
    uses = {
        "combat": "Combat feats (damage, kills, survival under fire)",
        "progression": "Progression (ranks, research, tiers)",
        "vehicles": "Vehicle collection and mastery milestones",
        "exploration": "Maps, modes and firsts",
        "teamwork": "Platoon, assists, spotting for the team",
        "skill": "Precision and skill feats",
        "collection": "Cosmetics and collection sets",
        "events": "Limited-time events",
    }
    for cat, use in uses.items():
        add("achievements", f"emblem_{cat}", f"Achievement emblem: {cat}", f"Category emblem: {use} (composite over a frame)",
            lambda d, c=cat: draw_emblem(d, c))
    for r, cat in (("common", "exploration"), ("rare", "teamwork"), ("epic", "skill"), ("legendary", "combat")):
        add("achievements", f"{cat}_{r}", f"Achievement example: {cat} on {r}",
            f"Preview only: `emblem_{cat}` over `frame_{r}`", lambda d, r=r, c=cat: draw_composite(d, r, c), subdir="examples")
    for lv, name in ((3, "Class III"), (2, "Class II"), (1, "Class I"), ("ace", "Ace")):
        add("achievements", f"mastery_{lv}", f"Vehicle mastery: {name}",
            f"Vehicle mastery badge {name}: results screen, garage carousel, service record",
            lambda d, lv=lv: draw_mastery(d, lv))


_register()
