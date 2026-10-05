"""Crew role icons (assets/icons/crew/): crew panel, damage panel crew row, barracks, crew books.

Abstract pictograms, never faces: the padded tanker helmet of the Crew XP currency (olive, ribbed,
bone goggles) sits lower-left, and the ROLE TOOL rises behind it upper-right, separated by an ink gap.
The tool is the identifier, so each role owns a distinct outline:

    commander       command pennant (swallowtail) on a staff
    gunner          crosshair reticle: thin ring, four long protruding ticks, centre dot
    driver          steering wheel: heavy rim, hub, three spokes
    loader          shell (flat side view)
    radio_operator  antenna mast with broadcast arcs (same arcs as the radio module)

`<role>_injured`: helmet and tool turn signal red and a first-aid badge (bone plus on a green
chamfered tile, the first-aid convention, never a red cross) is added bottom-right: a shape cue
on top of the colour change.
"""

from __future__ import annotations

from . import geom as G
from . import kit
from .registry import add, note
from .tokens import INK

ROLES = ["commander", "gunner", "driver", "loader", "radio_operator"]
NAMES = {"commander": "Commander", "gunner": "Gunner", "driver": "Driver", "loader": "Loader",
         "radio_operator": "Radio operator"}


def _helmet():
    shape, ribs, brow = kit.helmet(25.0, 23.0, 36.0, 34.0)
    gog = G.union(G.cbox(11.5, 41.0, 23.5, 48.5, 2.2, 2.2, 2.2, 2.2), G.cbox(26.5, 41.0, 38.5, 48.5, 2.2, 2.2, 2.2, 2.2),
                  G.rect(22.5, 43.2, 27.5, 46.2))
    return shape, ribs, gog


def tool(role: str):
    """Returns (tool silhouette, engraved details)."""
    if role == "commander":
        staff = G.rect(39.5, 6.5, 43.5, 34)
        knob = G.cbox(38.5, 6.0, 44.5, 10.0, 1.2, 1.2, 0, 0)
        flag = G.poly([(43.5, 8.5), (58, 8.5), (53.5, 14.5), (58, 20.5), (43.5, 20.5)])
        sil = G.union(staff, knob, flag)
        det = G.rect(46.5, 13.7, 51.5, 15.3)
    elif role == "gunner":
        c = (45.5, 19.0)
        ring = kit.ring(*c, 8.6, 3.0, n=72)
        ticks = G.union(G.cbox(c[0] - 1.8, 5.5, c[0] + 1.8, 13.5, 0.8, 0.8, 0, 0),
                        G.cbox(c[0] - 1.8, 24.5, c[0] + 1.8, 32.5, 0, 0, 0.8, 0.8),
                        G.cbox(32.0, c[1] - 1.8, 40.0, c[1] + 1.8, 0.8, 0, 0, 0.8),
                        G.cbox(51.0, c[1] - 1.8, 59.0 - 1.0, c[1] + 1.8, 0, 0.8, 0.8, 0))
        dot = G.circle(*c, 2.3, n=24)
        sil = G.union(ring, ticks, dot)
        det = G.EMPTY
    elif role == "driver":
        c = (45.0, 19.0)
        rim = kit.ring(*c, 10.2, 4.6, n=96)
        hub = G.circle(*c, 3.6, n=32)
        spokes = G.union([G.thick_line(c, kit.pt(*c, 10.5, a), 3.4) for a in (90, 210, 330)])
        sil = G.union(rim, hub, spokes)
        det = G.circle(*c, 1.3, n=16)
    elif role == "loader":
        sil = kit.shell_flat(45.5, 36.0, 30.5, 12.0)
        det = G.union(G.rect(40.4, 22.4, 50.6, 23.8))
    elif role == "radio_operator":
        c = (45.5, 14.0)
        mast = G.rect(43.7, 15, 47.3, 34)
        tip = G.circle(*c, 3.0, n=32)
        waves = G.union(kit.arc(*c, 7.6, 3.2, -46, 46), kit.arc(*c, 7.6, 3.2, 134, 226))
        outer = G.union(kit.arc(*c, 13.0, 3.2, -36, 36), kit.arc(*c, 13.0, 3.2, 144, 216))
        sil = G.union(mast, tip, waves, outer)
        det = G.EMPTY
    else:
        raise KeyError(role)
    return sil, det


def draw_crew(d, role: str, injured: bool = False):
    helmet, ribs, gog = _helmet()
    tsil, tdet = tool(role)
    _, helmet, ribs, gog, tsil, tdet = kit.shrink_to(G.union(helmet, tsil), helmet, ribs, gog, tsil, tdet)
    kit.check(G.union(helmet, tsil), f"crew {role}")
    hmat = "signal" if injured else "olive"
    tmat = "signal" if injured else "bone"
    # tool sits behind the helmet: cut the tool back where the helmet overlaps, with an ink gap
    tool_vis = G.diff(tsil, G.grow(helmet, 1.6))
    d.keyline(G.union(helmet, tool_vis), kit.KEY)
    tface = d.plate(tool_vis, tmat, bevel=1.4)
    if not tdet.is_empty:
        d.engrave(G.inter(tdet, tface), tmat, tface, depth=0.8)
    face = d.plate(helmet, hmat, bevel=kit.BEV)
    d.engrave(G.inter(ribs, face), hmat, face, depth=0.7)
    d.inlay(gog, "bone", face, bevel=0.9, shadow=(0.8, 1.0))
    if injured:
        badge = G.cbox(41.5, 41.5, 58.0, 58.0, 3.0, 3.0, 3.0, 3.0)
        d.keyline(badge, 1.6, INK)
        bface = d.plate(badge, "verdant", bevel=1.2)
        d.inlay(kit.plus(49.75, 49.75, 10.5, 3.6), "bone", bface, bevel=0.7, shadow=(0.6, 0.8))


def _register():
    note("crew", "Crew role pictograms: helmet + role tool. `<role>` normal (olive helmet, bone tool), "
                 "`<role>_injured` (red + first-aid badge). Crew panel, damage-panel crew row, barracks; "
                 "24-48 px, upload @128.")
    uses = {
        "commander": "Commander: crew panel, barracks, crew skills header",
        "gunner": "Gunner",
        "driver": "Driver",
        "loader": "Loader",
        "radio_operator": "Radio operator",
    }
    for r in ROLES:
        add("crew", r, f"Crew: {NAMES[r]}", uses[r], lambda d, r=r: draw_crew(d, r, False))
        add("crew", f"{r}_injured", f"Crew: {NAMES[r]} (injured)",
            f"{NAMES[r]} injured: damage-panel crew row (heal with a med kit)", lambda d, r=r: draw_crew(d, r, True))


_register()
