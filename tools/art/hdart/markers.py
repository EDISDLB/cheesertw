"""Vehicle marker frames for 3D BillboardGui (assets/icons/markers/).

White art + ink keyline, tinted at runtime with the team colour of the active CVD scheme. The HP-bar
slot is a dark inset (ink at 70 %) that stays dark under ImageColor3; the client draws the HP fill as
a separate Frame inside the slot. Layout on the 128 x 48 canvas (scale uniformly):

    backing      x 4..124, y 5..40   dark plate (ink 55 %), HULLDOWN cut; stays dark under tint
    class slot   x 7..31,  y 8..32    (place the 20 px minimap class glyph centred at (19, 20))
    team accent  x 35..117, y 5..8    team-colour stripe along the top edge
    name / tier  x 36..118, y 10..25  (text drawn by the client, Builder Sans Bold 12 px)
    HP slot      x 35..120, y 27..36  (dark inner track 37..118 x 29..34; HP fill is a client Frame)

Team styles differ by SHAPE, so they work without colour:

    ally      plain frame
    enemy     a downward pointer under the frame (it points at the vehicle) + cut HP-slot ends
    platoon   ally frame + a square number tab on the right (platoon pip 1-3 goes inside)
    self      ally frame + a crest notch on top (spectator / replay only)

target_lock (64 x 64): four corner brackets with inner ticks, drawn around the locked vehicle.
"""

from __future__ import annotations

from . import geom as G
from . import kit
from .registry import add, note
from .tokens import INK

WM, HM = 128, 48
KEYW = 1.6


def frame(style: str):
    """Returns (white parts, dark backing plate, dark HP track)."""
    plate = G.cbox(4, 5, 124, 40, 7, 0, 7, 0)  # HULLDOWN cut: chamfered top-left and bottom-right
    slot = G.diff(G.cbox(7, 8, 31, 32, 5, 0, 5, 0), G.cbox(10.5, 11.5, 27.5, 28.5, 3.4, 0, 3.4, 0))
    accent = G.cbox(35, 5, 117, 8.2, 0, 0, 0, 0)
    hp_outer = G.rect(35, 27, 120, 36)
    if style == "enemy":
        hp_outer = G.poly([(38, 27), (120, 27), (117, 36), (35, 36)])
    hp_inner = G.shrink(hp_outer, 2.0)
    hp = G.diff(hp_outer, hp_inner)
    parts = [slot, accent, hp]
    if style == "enemy":
        parts.append(G.poly([(11, 38), (27, 38), (19.7, 45.2), (18.3, 45.2)]))
    if style == "platoon":
        tab = G.diff(G.cbox(106, 9, 121, 23, 0, 3, 0, 3), G.cbox(108.6, 11.6, 118.4, 20.4, 0, 2, 0, 2))
        parts.append(tab)
        parts[1] = G.cbox(35, 5, 103, 8.2, 0, 0, 0, 0)
    if style == "self":
        parts.append(G.poly([(11, 4.8), (18.3, 2.2), (19.7, 2.2), (27, 4.8), (27, 6.7), (19, 4.0), (11, 6.7)]))
    return G.union(parts), plate, hp_inner


def draw_marker(d, style):
    g, plate, track = frame(style)
    # keyline included: its mitre at the pointer / crest tips must stay on the canvas
    x0, y0, x1, y1 = G.union(G.grow(g, KEYW), plate).bounds
    if x0 < 0.3 or y0 < 0.3 or x1 > WM - 0.3 or y1 > HM - 0.3:
        raise ValueError(f"marker {style} leaves canvas {(x0, y0, x1, y1)}")
    d.path(plate, INK, 0.55)
    d.path(track, INK, 0.75)
    d.keyline(g, KEYW)
    d.path(g, "#FFFFFF")


def draw_target_lock(d):
    br = kit.corner_brackets(6, 6, 58, 58, 15, 4.0, chamfer=3.0)
    ticks = G.union(G.rect(30.5, 6, 33.5, 13), G.rect(30.5, 51, 33.5, 58), G.rect(6, 30.5, 13, 33.5), G.rect(51, 30.5, 58, 33.5))
    g = G.union(br, ticks)
    d.keyline(g, kit.KEY)
    d.path(g, "#FFFFFF")


def _register():
    note("markers", "BillboardGui marker frames (128 x 48) and the target-lock frame. White: tint with "
                    "the team colour; the HP slot is a dark inset that stays dark. Team styles differ by "
                    "shape (enemy pointer, platoon tab, self crest).")
    uses = {
        "ally": "Allied vehicle marker frame (class slot, name line, HP slot)",
        "enemy": "Enemy vehicle marker frame: pointer under the class slot + cut HP-slot ends",
        "platoon": "Platoon-mate marker frame: ally frame + number tab",
        "self": "Own vehicle marker (spectator / replay): ally frame + crest notch",
    }
    for st in ("ally", "enemy", "platoon", "self"):
        add("markers", f"marker_{st}", f"Vehicle marker frame: {st}", uses[st], lambda d, s=st: draw_marker(d, s), w=WM, h=HM,
            tint=True)
    add("markers", "target_lock", "Target lock frame", "Locked-target brackets around the aimed vehicle (auto-aim lock)",
        draw_target_lock, tint=True)


_register()
