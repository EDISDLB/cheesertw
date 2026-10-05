"""Mission icons (assets/icons/missions/): missions hub tabs, mission cards, rewards screens.

Flat-front symbols in the field-paperwork language: bone paper, gunmetal clips and bindings, khaki
maps and envelopes, with one accent each (dusk for time-limited and special, verdant for done).
Every member owns its outline:

    daily             tear-off page (portrait) with a binding bar and a dusk sun
    weekly            landscape wall calendar with a row of seven day cells
    special           sealed envelope with a dusk wax seal
    event             swallowtail pennant on a pole
    campaign          zig-zag folded operations map with a route to a flag pin
    class_mission     clipboard with a target and five class pips
    vehicle_mission   hanging vehicle tag (landscape plate, hole at the left) with a hull profile
    mission_complete  paper sheet with a round verdant check stamp breaking its corner
    battle_pass       ticket with semicircle side notches, perforation and a ridge band
"""

from __future__ import annotations


from . import geom as G
from . import kit
from .achievements import _hull
from .registry import add, note
from .tokens import INK


def _sym(d, sil, name):
    kit.check(sil, name)
    d.keyline(sil, kit.KEY)


def daily(d):
    page = G.cbox(13, 13, 51, 57, 0, 0, 4, 4)
    bind = G.cbox(10, 8, 54, 17, 2, 2, 0, 0)
    sil = G.union(page, bind)
    _sym(d, sil, "daily")
    face = d.plate(page, "bone", bevel=1.6)
    d.plate(bind, "gunmetal", bevel=1.3)
    for x in (21, 43):
        d.engrave(G.cbox(x - 2, 10.5, x + 2, 14.5, 0.8, 0.8, 0.8, 0.8), "gunmetal", bind, depth=0.6)
    c = (32, 36)
    sun = G.circle(*c, 7.5, n=48)
    rays = G.union([G.T(G.R(G.poly([(-1.8, -10.5), (1.8, -10.5), (0, -15)]), a, (0, 0)), *c) for a in range(0, 360, 45)])
    d.inlay(G.union(sun, rays), "dusk", face, bevel=0.9, shadow=(0.8, 1.0))
    d.engrave(G.rect(19, 50, 45, 51.6), "bone", face, depth=0.6)


def weekly(d):
    page = G.cbox(6, 17, 58, 54, 0, 0, 4, 4)
    head = G.cbox(6, 12, 58, 24, 2, 2, 0, 0)
    sil = G.union(page, head)
    _sym(d, sil, "weekly")
    face = d.plate(page, "bone", bevel=1.6)
    d.plate(head, "gunmetal", bevel=1.3)
    for x in (16, 48):
        d.engrave(G.cbox(x - 2, 14.5, x + 2, 18.5, 0.8, 0.8, 0.8, 0.8), "gunmetal", head, depth=0.6)
    cells = [G.cbox(9.5 + i * 6.6, 31, 14.5 + i * 6.6, 38, 1, 1, 1, 1) for i in range(7)]
    for i, cg in enumerate(cells):
        if i < 4:
            d.inlay(cg, "dusk", face, bevel=0.6, shadow=(0.6, 0.7))
        else:
            d.engrave(cg, "bone", face, depth=0.7)
    d.engrave(G.union(G.rect(10, 43, 54, 44.6), G.rect(10, 47.5, 40, 49.1)), "bone", face, depth=0.6)


def special(d):
    env = G.cbox(6, 16, 58, 52, 2, 2, 2, 2)
    sil = env
    _sym(d, sil, "special")
    face = d.plate(env, "khaki", bevel=1.6)
    flap = kit.stroke([(8, 18), (32, 36), (56, 18)], 1.6)
    d.engrave(G.inter(flap, face), "khaki", face, depth=0.7)
    d.engrave(G.inter(G.union(kit.stroke([(8, 50), (24, 37)], 1.4), kit.stroke([(56, 50), (40, 37)], 1.4)), face), "khaki", face,
              depth=0.6)
    seal = G.ngon(32, 36, 9.5, 8, rot_deg=22.5)
    d.keyline(seal, 1.0)
    sface = d.plate(seal, "dusk", bevel=1.1)
    mark = G.diff(G.poly([(25.5, 39.5), (29.5, 34.5), (34.5, 34.5), (38.5, 39.5)]),
                  G.poly([(27.6, 40.4), (30.5, 36.6), (33.5, 36.6), (36.4, 40.4)]))
    d.engrave(G.inter(mark, sface), "dusk", sface, depth=0.6)


def event(d):
    pole = G.rect(16, 12, 21, 57)
    fin = G.cbox(14, 7, 23, 13, 2, 2, 0, 0)
    flag = G.poly([(21, 13), (55, 13), (46, 24.5), (55, 36), (21, 36)])
    sil = G.union(pole, fin, flag)
    _sym(d, sil, "event")
    d.plate(pole, "steel", bevel=1.2)
    d.plate(fin, "brass", bevel=1.0)
    face = d.plate(flag, "dusk", bevel=1.6)
    d.inlay(G.inter(G.rect(21, 22.6, 43, 26.4), face), "bone", face, bevel=0.6, shadow=(0.6, 0.7))


def campaign(d):
    mp = G.poly([(6, 17), (22, 11), (42, 17), (58, 11), (58, 50), (42, 56), (22, 50), (6, 56)])
    sil = mp
    _sym(d, sil, "campaign")
    face = d.plate(mp, "khaki", bevel=1.6)
    panels = [G.poly([(22, 11), (42, 17), (42, 56), (22, 50)])]
    d.path(G.inter(panels[0], face), "#000000", 0.12)
    d.engrave(G.inter(G.union(G.rect(21.4, 11, 22.6, 50), G.rect(41.4, 17, 42.6, 56)), face), "khaki", face, depth=0.5)
    route = []
    pts = [(12, 47), (18, 40), (26, 41), (32, 33), (40, 32), (45, 25)]
    for i in range(len(pts) - 1):
        p0, p1 = pts[i], pts[i + 1]
        for t in (0.15, 0.6):
            a = (p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t)
            b = (p0[0] + (p1[0] - p0[0]) * (t + 0.3), p0[1] + (p1[1] - p0[1]) * (t + 0.3))
            route.append(G.thick_line(a, b, 2.0))
    d.engrave(G.inter(G.union(route), face), "khaki", face, depth=0.6)
    pole = G.rect(45, 15, 47.4, 28)
    fl = G.poly([(47.4, 15), (55, 18), (47.4, 21.5)])
    pin = G.union(pole, fl)
    d.keyline(pin, 0.9)
    d.plate(pin, "dusk", bevel=0.7)


def _clipboard():
    board = G.cbox(11, 12, 53, 58, 3, 3, 3, 3)
    clip = G.cbox(22, 6, 42, 16, 3, 3, 0, 0)
    return board, clip


def class_mission(d):
    board, clip = _clipboard()
    sil = G.union(board, clip)
    _sym(d, sil, "class_mission")
    d.plate(board, "gunmetal", bevel=1.6)
    paper = G.cbox(15, 17, 49, 54.5, 0, 0, 2, 2)
    face = d.plate(paper, "bone", bevel=1.0)
    d.plate(clip, "steel", bevel=1.2)
    c = (32, 31)
    tgt = G.union(kit.ring(*c, 8, 2.4, n=48), G.circle(*c, 2.6, n=24), G.rect(31, 19.5, 33, 24), G.rect(31, 38, 33, 42.5),
                  G.rect(20.5, 30, 25, 32), G.rect(39, 30, 43.5, 32))
    d.engrave(G.inter(tgt, face), "bone", face, depth=0.7)
    for i in range(5):
        x = 19.8 + i * 6.1
        p = G.cbox(x - 2, 46, x + 2, 50, 1, 1, 1, 1)
        if i == 0:
            d.inlay(p, "dusk", face, bevel=0.5, shadow=(0.5, 0.6))
        else:
            d.engrave(p, "bone", face, depth=0.6)


def vehicle_mission(d):
    tag = G.cbox(6, 15, 58, 49, 8, 3, 3, 8)
    sil = tag
    _sym(d, sil, "vehicle_mission")
    face = d.plate(tag, "steel", bevel=1.6)
    d.engrave(G.circle(13, 32, 2.8, n=24), "steel", face, depth=0.8)
    hull = _hull(36, 33, 34)
    d.inlay(G.inter(hull, G.shrink(face, 0.6)), "gunmetal", face, bevel=0.8, shadow=(0.9, 1.1))
    d.engrave(G.rect(20, 42.5, 52, 44), "steel", face, depth=0.5)


def mission_complete(d):
    paper = G.cbox(9, 8, 45, 54, 0, 4, 0, 0)
    stamp = G.circle(42, 42, 14.5, n=96)
    sil = G.union(paper, stamp)
    _sym(d, sil, "mission_complete")
    face = d.plate(paper, "bone", bevel=1.6)
    d.engrave(G.inter(G.union([G.rect(14, y, 38, y + 1.8) for y in (16, 22, 28)]), face), "bone", face, depth=0.6)
    d.keyline(stamp, 1.2)
    sface = d.plate(stamp, "verdant", bevel=1.4)
    ring = G.diff(G.circle(42, 42, 11.5, n=72), G.circle(42, 42, 10.2, n=72))
    d.engrave(G.inter(ring, sface), "verdant", sface, depth=0.6)
    d.inlay(kit.checkmark(42, 42.5, 13, 3.6), "bone", sface, bevel=0.7, shadow=(0.7, 0.9))


def battle_pass(d):
    t = G.cbox(6, 16, 58, 50, 3, 3, 3, 3)
    notches = G.union(G.circle(6, 33, 5.0, n=40), G.circle(58, 33, 5.0, n=40))
    ticket = G.diff(t, notches)
    sil = ticket
    _sym(d, sil, "battle_pass")
    face = d.plate(ticket, "gold", bevel=1.6)
    band = G.inter(G.rect(18, 16, 30, 50), face)
    d.path(band, "#1B2228")
    perf = G.union([G.rect(40.5, y, 42, y + 2.4) for y in range(19, 48, 5)])
    d.engrave(G.inter(perf, face), "gold", face, depth=0.6)
    ridge = G.poly([(18.5, 37), (22, 31), (26, 31), (29.5, 37)])
    sun = G.diff(G.circle(24, 31, 4.2, n=32), G.rect(0, 31.2, 64, 64))
    d.path(G.inter(sun, band), "#FF7A2F")
    d.path(G.inter(ridge, band), "#0B0F12")
    d.path(G.inter(G.diff(ridge, G.T(ridge, 0, 1.0)), band), "#FF7A2F")
    d.engrave(G.inter(G.union(G.rect(45.5, 26, 51.5, 28), G.rect(45.5, 31, 51.5, 33), G.rect(45.5, 36, 50, 38)), face), "gold", face,
              depth=0.6)
    _ = INK


ITEMS = [
    ("daily", daily, "Daily missions tab / card"),
    ("weekly", weekly, "Weekly missions tab / card"),
    ("special", special, "Special (limited) missions / orders"),
    ("event", event, "Event missions"),
    ("campaign", campaign, "Campaign (operation chain) missions"),
    ("class_mission", class_mission, "Class-specific mission (composite the class glyph next to it)"),
    ("vehicle_mission", vehicle_mission, "Vehicle-specific mission"),
    ("mission_complete", mission_complete, "Mission complete stamp / claimed state"),
    ("battle_pass", battle_pass, "Battle pass (season pass) entry and progress header"),
]


def _register():
    note("missions", "Mission hub tabs and cards. Flat symbols with one accent each; upload @128.")
    for key, fn, use in ITEMS:
        add("missions", key, f"Missions: {key.replace('_', ' ')}", use, fn)


_register()
