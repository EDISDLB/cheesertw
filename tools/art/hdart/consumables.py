"""Consumable icons (assets/icons/consumables/): battle consumable slots, loadout, shop.

Consumables are PHYSICAL OBJECTS on the fixed 3/4 camera (solid.py), resting on their largest face,
each in its functional material:

    repair_kit          olive tool case, steel handle, bone wrench stamp
    med_kit             bone medical case, first-aid tile (bone plus on green: never a red cross)
    extinguisher        upright red bottle with valve, lever and hose horn
    extinguisher_auto   red bottle lying in a strapped cradle, with a dusk heat-sensor head
    engine_boost        dusk jerrycan with the pressed X panel and a spout
    combat_ration       olive tin with a bone label, plus a wrapped ration bar
    smoke               grenade canister (pin ring, lever) with a smoke cloud behind it
    reserve_tracks      three spare track links with guide horns and steel pins

`_large` variants follow one rule: two units, the second standing behind and to the left of the
first, so "large" reads as a shape (a bigger cluster), not only as a colour or a badge.
"""

from __future__ import annotations

import math

from . import geom as G
from . import kit, solid
from .registry import add, note
from .tokens import INK

FIT = (7.0, 8.0, 57.0, 56.0)


def _xlate(solids, dx, dy, dz):
    """Translate solids in world space."""
    out = []
    for s in solids if isinstance(solids, (list, tuple)) else [solids]:
        ns = solid.Solid(smooth=s.smooth, order=s.order, sep=s.sep,
                         centre=(s.centre[0] + dx, s.centre[1] + dy, s.centre[2] + dz), name=s.name)
        for f in s.faces:
            ns.faces.append(solid.Face([(p[0] + dx, p[1] + dy, p[2] + dz) for p in f.pts], f.normal, f.mat, f.kind,
                                       f.tone, f.tag))
        out.append(ns)
    return out


def _front(g, x0, ytop, z):
    """Map a 2D decal drawn in world units (u right, v down) onto the plane z=const."""
    return solid.plane_map(g, (x0, ytop, z), (1, 0, 0), (0, -1, 0))


def _left(g, z0, ytop, x):
    """Decal on the plane x=const (the visible left side): u runs toward the viewer (+z)."""
    return solid.plane_map(g, (x, ytop, z0), (0, 0, 1), (0, -1, 0))


def _top(g, x0, z0, y):
    return solid.plane_map(g, (x0, y, z0), (1, 0, 0), (0, 0, 1))


def _seq_order(solids, start):
    for i, s in enumerate(solids):
        s.order = start + i * 0.001
    return solids


# ---------------------------------------------------------------------------
# Object builders: each returns (solids, decals) where decals are callables (d, f) -> None
# ---------------------------------------------------------------------------
def toolbox(dx=0.0, dz=0.0):
    W, H, D = 1.0, 0.72, 0.55
    body = solid.box(-W, 0, -D, W, H, D, "olive", chamfer=0.05)
    lid = solid.box(-W - 0.04, H, -D - 0.04, W + 0.04, H + 0.2, D + 0.04, "olive", chamfer=0.06)
    posts = [solid.box(x - 0.06, H + 0.2, -0.07, x + 0.06, H + 0.42, 0.07, "steel") for x in (-0.5, 0.5)]
    bar = solid.box(-0.6, H + 0.36, -0.09, 0.6, H + 0.48, 0.09, "steel")
    latches = [solid.box(x - 0.1, H - 0.14, D, x + 0.1, H + 0.12, D + 0.06, "brass") for x in (-0.68, 0.68)]
    ss = [body, lid] + posts + [bar] + latches
    body.order, lid.order = 0, 1
    for i, p in enumerate(posts):
        p.order = 2 + i * 0.01
    bar.order = 2.5
    for i, l in enumerate(latches):
        l.order = 3 + i * 0.01
    ss = _xlate(ss, dx, 0, dz)
    wr = kit.wrench(0, 0, 1.0, 0.14, ang=-16, jaw=0.34)

    def dec(d, f):
        g = f(_front(wr, dx, H * 0.5, D + dz))  # wrench is centred at (0, 0): place it mid-face
        face = f(_front(G.rect(-W + 0.08, 0.06, W - 0.08, H - 0.06), dx, H, D + dz))
        d.inlay(G.inter(g, face), "bone", face, bevel=0.7, shadow=(0.7, 0.9))
    return ss, [dec]


def medcase(dx=0.0, dz=0.0):
    W, H, D = 0.72, 1.1, 0.42
    body = solid.box(-W, 0, -D, W, H, D, "bone", chamfer=0.07)
    rim = solid.box(-W - 0.03, H * 0.68, -D - 0.03, W + 0.03, H * 0.74, D + 0.03, "canvas", chamfer=0.08)
    grip = solid.box(-0.32, H, -0.08, 0.32, H + 0.16, 0.08, "gunmetal")
    body.order, rim.order, grip.order = 0, 0.5, 1
    ss = _xlate([body, rim, grip], dx, 0, dz)

    def dec(d, f):
        face = f(_front(G.rect(-W + 0.06, 0.06, W - 0.06, H - 0.06), dx, H, D + dz))
        tile = f(_front(G.cbox(-0.42, 0.20, 0.42, 1.0, 0.12, 0.12, 0.12, 0.12), dx, H, D + dz))
        tile = G.inter(tile, face)
        d.keyline(tile, 0.9, INK, 0.85)
        tface = d.plate(tile, "verdant", bevel=0.9)
        pl = f(_front(kit.plus(0, 0.60, 0.56, 0.17), dx, H, D + dz))
        d.inlay(G.inter(pl, tface), "bone", tface, bevel=0.6, shadow=(0.6, 0.8))
    return ss, [dec]


def draw_object(d, solids, decals=(), extra=None, box=FIT, extra_draw=None):
    sc = solid.Scene().add(solids)
    f = sc.fitter(box, extra=extra)
    sil = f(sc.silhouette())
    if extra is not None:
        sil = G.union(sil, f(extra))
    kit.check(sil, "consumable")
    if extra_draw is not None:
        extra_draw(d, f)
    sc.render(d, f)
    for dec in decals:
        dec(d, f)


def draw_repair_kit(d, large=False):
    if large:
        a, da = toolbox(dx=-0.55, dz=-1.15)
        for s in a:
            s.order = (s.order or 0) - 100
        b, db = toolbox()
        draw_object(d, a + b, da + db)
    else:
        s, dec = toolbox()
        draw_object(d, s, dec)


def draw_med_kit(d, large=False):
    if large:
        a, da = medcase(dx=-0.7, dz=-0.95)
        for s in a:
            s.order = (s.order or 0) - 100
        b, db = medcase(dx=0.25)
        draw_object(d, a + b, da + db)
    else:
        s, dec = medcase()
        draw_object(d, s, dec)


def draw_extinguisher(d):
    R = 0.46
    prof = [(0.0, R - 0.03, "signal"), (0.06, R, "signal"), (0.62, R, "signal"), (0.62, R, "bone"), (1.0, R, "bone"),
            (1.0, R, "signal"), (1.55, R, "signal")]
    for i in range(1, 7):
        t = i / 6
        prof.append((1.55 + 0.26 * math.sin(t * math.pi / 2), R * math.cos(t * math.pi / 2) * 0.62 + 0.17 * (t), "signal"))
    prof += [(1.81, 0.17, "steel"), (1.97, 0.17, "steel"), (1.97, 0.24, "steel"), (2.12, 0.24, "steel"), (2.12, 0.0, "steel")]
    body = solid.revolve(prof, n=40, name="ext")
    for s in body:
        s.order = (s.order or 0)
    lever = solid.extrude([(-0.06, 0.0), (0.62, 0.30), (0.62, 0.40), (-0.06, 0.13)], (0.0, 2.04, -0.06), (1, 0, 0),
                          (0, 1, 0), (0, 0, 0.12), "steel", name="lever")
    lever.order = 10
    hose = solid.cylinder((0.18, 1.97, 0.10), (0.62, 1.60, 0.30), 0.075, "obsidian", n=16)
    horn = solid.cylinder((0.62, 1.60, 0.30), (0.74, 1.18, 0.40), 0.08, "obsidian", n=16,
                          profile=[(0.0, 0.08), (1.0, 0.16)])
    for s in hose + horn:
        s.order = 11
    draw_object(d, body + [lever] + hose + horn)


def draw_extinguisher_auto(d):
    R = 0.40
    prof = []
    for i in range(0, 7):
        t = i / 6
        prof.append((-1.0 + 0.30 * (1 - math.cos(t * math.pi / 2)), R * math.sin(t * math.pi / 2), "signal"))
    prof += [(0.70, R, "signal")]
    for i in range(1, 7):
        t = i / 6
        prof.append((0.70 + 0.30 * math.sin(t * math.pi / 2), R * math.cos(t * math.pi / 2), "signal"))
    bottle = solid.revolve([(s, r, m) for s, r, m in prof], axis=(1, 0, 0), centre=(0, 0.62, 0), n=40, name="bottle")
    for s in bottle:
        s.order = 5
    straps = []
    for x in (-0.45, 0.42):
        st = solid.revolve([(x - 0.06, R + 0.035, "steel"), (x + 0.06, R + 0.035, "steel")], axis=(1, 0, 0),
                           centre=(0, 0.62, 0), n=40, name="strap")
        for s in st:
            s.order = 6 + x
        straps += st
    base = solid.box(-0.95, 0.0, -0.42, 0.95, 0.12, 0.42, "gunmetal", chamfer=0.04)
    base.order = 0
    saddles = [solid.box(x - 0.13, 0.12, -0.3, x + 0.13, 0.36, 0.3, "gunmetal") for x in (-0.45, 0.42)]
    for s in saddles:
        s.order = 1
    valve = solid.cylinder((1.0, 0.62, 0), (1.18, 0.62, 0), 0.13, "steel", n=20)
    pipe = solid.cylinder((1.12, 0.62, 0), (1.12, 1.18, 0), 0.06, "steel", n=16)
    sensor = solid.cylinder((1.12, 1.18, 0), (1.12, 1.38, 0), 0.15, "dusk", n=24,
                            profile=[(0.0, 0.15), (0.55, 0.15), (1.0, 0.04)])
    for s in valve + pipe + sensor:
        s.order = 8
    draw_object(d, [base] + saddles + bottle + straps + valve + pipe + sensor)


def draw_engine_boost(d):
    W, H, D = 0.78, 1.3, 0.30
    body = solid.box(-W, 0, -D, W, H, D, "dusk", chamfer=0.05)
    body.order = 0
    handle = solid.extrude([(-0.62, 0.0), (0.12, 0.0), (0.12, 0.26), (-0.62, 0.26)], (0, H, -0.07), (1, 0, 0), (0, 1, 0),
                           (0, 0, 0.14), "dusk", name="handle")
    handle.order = 1
    spout = solid.cylinder((0.42, H, 0.0), (0.56, H + 0.30, 0.0), 0.13, "steel", n=20)
    for s in spout:
        s.order = 2

    def dec(d, f):
        face = f(_front(G.rect(-W + 0.06, 0.05, W - 0.06, H - 0.05), 0, H, D))
        panel = G.cbox(-0.58, 0.18, 0.58, 1.12, 0.1, 0.1, 0.1, 0.1)
        xbar = G.inter(G.union(G.thick_line((-0.58, 0.18), (0.58, 1.12), 0.2), G.thick_line((0.58, 0.18), (-0.58, 1.12), 0.2)),
                       panel)
        d.engrave(G.inter(f(_front(G.diff(panel, G.shrink(panel, 0.07)), 0, H, D)), face), "dusk", face, depth=0.7)
        d.inlay(G.inter(f(_front(xbar, 0, H, D)), face), "dusk", face, bevel=0.8, shadow=(0.7, 0.9))
        # handle hole (cut into the handle plate)
        hole = f(solid.plane_map(G.cbox(-0.52, 0.06, -0.02, 0.18, 0.06, 0.06, 0.06, 0.06), (0, H, 0.07), (1, 0, 0),
                                 (0, 1, 0)))
        d.path(hole, INK)
    draw_object(d, [body, handle] + spout, [dec])


def draw_combat_ration(d):
    """Olive ration tin with a bone label band and a pull-ring lid, a wrapped ration bar in front."""
    R = 0.50
    prof = [(0.0, R + 0.03, "steel"), (0.07, R + 0.03, "steel"), (0.07, R, "olive"), (0.24, R, "olive"), (0.24, R, "bone"),
            (0.66, R, "bone"), (0.66, R, "olive"), (0.86, R, "olive"), (0.86, R + 0.03, "steel"), (0.93, R + 0.03, "steel")]
    cx, cz = 0.22, -0.30
    can = solid.revolve(prof, centre=(cx, 0, cz), n=40, name="can")
    bar = solid.box(-1.0, 0, 0.10, 0.12, 0.18, 0.56, "khaki", chamfer=0.03)
    band = solid.box(-0.58, 0.0, 0.08, -0.34, 0.20, 0.58, "olive")
    bar.order, band.order = 5, 6

    def dec(d, f):
        ring = f(_top(G.diff(G.circle(0, 0, 0.20, n=32), G.circle(0, 0, 0.12, n=32)), cx + 0.10, cz + 0.04, 0.93))
        tab = f(_top(G.cbox(-0.06, -0.30, 0.06, -0.12, 0.02, 0.02, 0, 0), cx + 0.10, cz + 0.04, 0.93))
        d.path(G.grow(G.union(ring, tab), 0.45), INK, 0.8)
        d.path(G.union(ring, tab), "#E2E9EF")
        # stamped band across the label
        lab = f(_front(G.rect(-0.30, 0.0, 0.30, 0.10), cx, 0.50, cz + R))
        _ = lab
    draw_object(d, can + [bar, band], [dec])


def draw_smoke(d):
    """Smoke grenade canister (bone colour band, steel fuze, lever, pin ring) with a chamfered smoke
    cloud billowing behind it to the upper right."""
    R = 0.30
    prof = [(0.0, R, "gunmetal"), (0.82, R, "gunmetal"), (0.82, R, "bone"), (1.00, R, "bone"), (1.00, R, "gunmetal"),
            (1.16, R, "gunmetal"), (1.16, 0.17, "steel"), (1.40, 0.17, "steel"), (1.40, 0.0, "steel")]
    can = solid.revolve(prof, centre=(-0.35, 0, 0.1), n=36, name="smoke")
    lever = solid.extrude([(0.0, 0.0), (0.09, 0.0), (0.09, 1.0), (0.0, 1.06)], (-0.35 + R, 0.30, 0.02), (1, 0, 0),
                          (0, 1, 0), (0, 0, 0.14), "steel", name="lever")
    lever.order = 5
    top = solid.proj.project((-0.35, 1.40, 0.1))
    puffs = [(0.42, -0.30, 0.40), (0.95, -0.55, 0.42), (1.18, -0.05, 0.36), (0.70, 0.12, 0.30), (0.15, -0.72, 0.30)]
    cloud = G.union([G.ngon(top[0] + dx, top[1] + dy, r, 8, rot_deg=22.5) for dx, dy, r in puffs])
    inner = G.union([G.ngon(top[0] + dx - r * 0.18, top[1] + dy - r * 0.2, r * 0.52, 8, rot_deg=22.5)
                     for dx, dy, r in puffs[:3]])

    def under(d, f):
        g = f(cloud)
        d.keyline(g, kit.KEY)
        face = d.plate(g, "steel", bevel=1.6)
        d.path(G.inter(f(inner), face), "#E2E9EF", 0.55)

    def ring(d, f):
        rg = f(_left(G.diff(G.circle(0, 0, 0.13, n=24), G.circle(0, 0, 0.075, n=24)), 0.12, 1.34, -0.35 - 0.17))
        d.path(G.grow(rg, 0.5), INK, 0.9)
        d.path(rg, "#E2E9EF")
    draw_object(d, can + [lever], [ring], extra=cloud, extra_draw=under)


def draw_reserve_tracks(d):
    """A spare track section standing on end, tread side to the viewer: three steel shoes with dark
    grouser bars, joined by hinge pins whose ends stick out at both sides (the classic stowed spare
    track on a hull plate)."""
    ss = []
    W, T = 0.80, 0.16
    ys = (0.0, 0.52, 1.04)
    for i, y in enumerate(ys):
        shoe = solid.box(-W, y, -T, W, y + 0.46, T, "steel", chamfer=0.03)
        shoe.order = i * 10
        bl = solid.box(-W + 0.06, y + 0.13, T, -0.17, y + 0.33, T + 0.14, "gunmetal")
        br = solid.box(0.17, y + 0.13, T, W - 0.06, y + 0.33, T + 0.14, "gunmetal")
        bl.order, br.order = i * 10 + 1, i * 10 + 1.5
        ss += [shoe, bl, br]
    for i, y in enumerate((0.49, 1.01)):
        pin = solid.cylinder((-W - 0.14, y, 0.0), (W + 0.14, y, 0.0), 0.075, "gunmetal", n=14)
        for s_ in pin:
            s_.order = i * 10 + 5
        ss += pin
    draw_object(d, ss)


def _register():
    note("consumables", "Battle consumables: slot icons (loadout, HUD consumable bar, shop). Physical "
                        "objects in 3/4 view; upload @128. `_large` = two units (shape cue).")
    items = [
        ("repair_kit", "Repair kit", "Repair kit: repairs damaged modules (HUD slot, loadout, shop)", draw_repair_kit, {}),
        ("repair_kit_large", "Large repair kit", "Large repair kit: repairs all modules + passive repair bonus",
         draw_repair_kit, {"large": True}),
        ("med_kit", "Med kit", "Med kit: heals injured crew", draw_med_kit, {}),
        ("med_kit_large", "Large med kit", "Large med kit: heals all crew + passive injury resistance", draw_med_kit,
         {"large": True}),
        ("extinguisher", "Fire extinguisher", "Manual fire extinguisher: puts out a fire", draw_extinguisher, {}),
        ("extinguisher_auto", "Automatic fire extinguisher", "Automatic extinguisher: triggers on fire by itself",
         draw_extinguisher_auto, {}),
        ("engine_boost", "Engine boost", "Fuel additive / engine boost: temporary engine power", draw_engine_boost, {}),
        ("combat_ration", "Combat ration", "Combat ration: crew skill bonus for the battle", draw_combat_ration, {}),
        ("smoke", "Smoke screen", "Smoke grenade: deploys a smoke screen", draw_smoke, {}),
        ("reserve_tracks", "Reserve tracks", "Reserve track links: faster track repair / extra track HP",
         draw_reserve_tracks, {}),
    ]
    for key, name, use, fn, kw in items:
        add("consumables", key, f"Consumable: {name}", use, lambda d, fn=fn, kw=kw: fn(d, **kw))


_register()
