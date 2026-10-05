"""Equipment icons (assets/icons/equipment/): equipment slots, shop, compare, upgrade screens.

* Items are PHYSICAL OBJECTS on the fixed 3/4 camera, drawn inside the inner box 10..54 so the grade
  frame (4..8 band) never touches them.
* Category icons (cat_*) are flat symbols: a HULLDOWN-cut tile (chamfered top-left and
  bottom-right) in the category colour (equip.* tokens) with a bone glyph inlaid.
* Grades are an OVERLAY the client composites on top of the item at the same size:
      standard      no frame
      improved      grade_improved.svg      silver corner brackets (four L brackets)
      experimental  grade_experimental.svg  dusk-orange full chamfered frame with corner bolts
  Brackets vs full frame is the shape cue; colour is secondary. examples/ holds pre-composited
  previews for review and store art.
"""

from __future__ import annotations

import math

from . import geom as G
from . import kit, proj, solid
from .registry import add, note
from .tokens import INK, MATERIALS

BOX = (10.0, 10.0, 54.0, 54.0)


def front(g, x0, ytop, z):
    return solid.plane_map(g, (x0, ytop, z), (1, 0, 0), (0, -1, 0))


def left(g, z0, ytop, x):
    return solid.plane_map(g, (x, ytop, z0), (0, 0, 1), (0, -1, 0))


def top(g, x0, z0, y):
    return solid.plane_map(g, (x0, y, z0), (1, 0, 0), (0, 0, 1))


def on_axis_plane(g, centre, axis):
    """Decal on the plane through `centre` perpendicular to `axis` (u = frame e1-ish horizontal,
    v = screen-down-ish), for caps of tilted cylinders."""
    a = solid._norm(axis)
    up = (0, 1, 0)
    u = solid._norm(solid._cross(up, a))
    if solid._dot(u, (1, 0, 0)) < 0:
        u = solid._mul(u, -1)
    v = solid._norm(solid._cross(a, u))
    if v[1] > 0:
        v = solid._mul(v, -1)  # v points down in world
    return solid.plane_map(g, centre, u, v)


def glass_disc(d, f, centre, axis, r, coat=False):
    """Glass element drawn on a flat cap: bevelled glass disc, one glint, optional coating sheen."""
    g = f(on_axis_plane(G.circle(0, 0, r, n=64), centre, axis))
    d.keyline(g, 0.9)
    d.plate(g, "glass", bevel=1.0)
    if coat:
        d.path(G.inter(f(on_axis_plane(kit.arc(0, 0, r * 0.62, r * 0.14, 200, 300, n=24), centre, axis)), g),
               MATERIALS["xp_violet"][1], 0.9)
        d.path(G.inter(f(on_axis_plane(kit.arc(0, 0, r * 0.45, r * 0.10, 20, 90, n=16), centre, axis)), g),
               MATERIALS["xp_teal"][1], 0.85)
    gl = f(on_axis_plane(G.R(G.cbox(-r * 0.62, -r * 0.10, -r * 0.22, r * 0.10, r * 0.05, r * 0.05, r * 0.05, r * 0.05), 45,
                             (0, 0)), centre, axis))
    gl = G.T(gl, 0, 0)
    d.path(G.inter(G.T(gl, -0.0, -0.0), g), "#FFFFFF", 0.85)


def render(d, solids, decals=(), extra=None, pre=None, box=BOX):
    sc = solid.Scene().add(solids)
    f = sc.fitter(box, extra=extra)
    sil = f(sc.silhouette())
    if extra is not None:
        sil = G.union(sil, f(extra))
    kit.check(sil, "equipment", lo=box[0] - 0.05, hi=box[2] + 0.05)
    if pre is not None:
        pre(d, f)
    tags, _ = sc.render(d, f)
    for dec in decals:
        dec(d, f, tags)
    return f


def order(solids, k):
    for s in solids if isinstance(solids, (list, tuple)) else [solids]:
        s.order = k
    return solids


def hexbolt(x, y, z, r=0.09, h=0.1, mat="steel"):
    return order(solid.cylinder((x, y, z), (x, y + h, z), r, mat, n=6), 50)


# ---------------------------------------------------------------------------
# Items
# ---------------------------------------------------------------------------
def rammer(d):
    """Hydraulic rammer: ram cylinder on its bracket driving a pad against a shell (pointing up-right)."""
    ax = solid._norm((1.0, 0.62, 0.0))

    def P(t, h=0.0):
        return (ax[0] * t, 0.55 + ax[1] * t + h, 0.0)

    cyl = solid.cylinder(P(-1.25), P(-0.05), 0.30, "gunmetal", n=36)
    endcap = solid.cylinder(P(-1.38), P(-1.25), 0.34, "steel", n=36)
    collar = solid.cylinder(P(-0.12), P(0.0), 0.34, "steel", n=36)
    rod = solid.cylinder(P(0.0), P(0.52), 0.10, "steel", n=20)
    pad = solid.cylinder(P(0.52), P(0.66), 0.27, "steel", n=30)
    shell_prof = [(0.0, 0.25), (0.42, 0.25), (0.42, 0.21), (0.56, 0.22), (0.56, 0.21)]
    rho_l = 0.42
    for i in range(1, 9):
        x = rho_l * i / 8
        rho = (0.21 ** 2 + rho_l ** 2) / (2 * 0.21)
        shell_prof.append((0.56 + x, max(math.sqrt(max(rho * rho - x * x, 0)) - (rho - 0.21), 0.0)))
    L = shell_prof[-1][0]
    mats = []
    shell = solid.revolve([(s, r, "brass" if s < 0.42 else ("copper" if s < 0.56 else "ap")) for s, r in shell_prof],
                          axis=ax, centre=P(0.72), n=30, name="shell")
    _ = mats, L
    bracket = solid.box(-1.05, 0.0, -0.30, -0.35, 0.22, 0.30, "gunmetal", chamfer=0.04)
    post = solid.box(-0.85, 0.22, -0.12, -0.55, 0.42, 0.12, "steel")
    order(bracket, -10)
    order(post, -9)
    order(shell, 1)
    order(pad, 2)
    order(rod, 3)
    order(collar, 4)
    order(cyl, 5)
    order(endcap, 6)
    render(d, [bracket, post] + shell + pad + rod + collar + cyl + endcap)


def stabilizer(d):
    """Gyro stabilizer: a flywheel standing in a fork on a base that carries a spirit-level vial."""
    base = solid.box(-1.0, 0.0, -0.45, 1.0, 0.36, 0.45, "gunmetal", chamfer=0.05)
    order(base, 0)
    forks = [order(solid.box(x - 0.1, 0.36, -0.12, x + 0.1, 1.28, 0.12, "steel"), 1 + i) for i, x in enumerate((-0.86, 0.86))]
    axle = order(solid.cylinder((-0.8, 1.02, 0.0), (0.8, 1.02, 0.0), 0.06, "steel", n=12), 3)
    wheel = order(solid.cylinder((0.0, 1.02, -0.13), (0.0, 1.02, 0.13), 0.68, "steel", n=48,
                                 profile=[(0.0, 0.6), (0.18, 0.68), (0.82, 0.68), (1.0, 0.6)]), 4)

    def dec(d, f, tags):
        c = (0.0, 1.02, 0.13)
        cap = f(on_axis_plane(G.circle(0, 0, 0.6, n=64), c, (0, 0, 1)))
        holes = G.union([G.circle(0.36 * math.cos(math.radians(a)), 0.36 * math.sin(math.radians(a)), 0.11, n=20)
                         for a in (45, 135, 225, 315)])
        d.engrave(G.inter(f(on_axis_plane(holes, c, (0, 0, 1))), cap), "steel", cap, depth=0.7)
        d.engrave(G.inter(f(on_axis_plane(kit.ring(0, 0, 0.5, 0.05, n=64), c, (0, 0, 1))), cap), "steel", cap, depth=0.5)
        spin = kit.arc_arrow(0, 0, 0.82, 0.1, 200, 320, head_len=0.2, head_half=0.13)
        g = f(on_axis_plane(spin, c, (0, 0, 1)))
        d.keyline(g, 0.9)
        d.plate(g, "dusk", bevel=0.6)
        # spirit level vial on the base front
        vial = f(front(G.cbox(-0.55, 0.09, 0.55, 0.27, 0.06, 0.06, 0.06, 0.06), 0.0, 0.36, 0.45))
        d.keyline(vial, 0.8)
        d.plate(vial, "glass", bevel=0.6)
        bub = f(front(G.cbox(-0.12, 0.12, 0.12, 0.24, 0.04, 0.04, 0.04, 0.04), 0.0, 0.36, 0.45))
        d.path(bub, MATERIALS["glass"][0])
        ticks = f(front(G.union(G.rect(-0.2, 0.09, -0.17, 0.27), G.rect(0.17, 0.09, 0.2, 0.27)), 0.0, 0.36, 0.45))
        d.path(ticks, INK, 0.8)
    render(d, [base] + forks + axle + wheel, [dec])


def improved_aiming(d):
    """Gun-laying drive: gearbox with an elevation handwheel and a crank knob."""
    box = order(solid.box(-0.85, 0.0, -0.5, 0.75, 1.05, 0.5, "gunmetal", chamfer=0.06), 0)
    shaft = order(solid.cylinder((-0.05, 0.55, 0.5), (-0.05, 0.55, 0.7), 0.12, "steel", n=16), 1)
    wheel = order(solid.cylinder((-0.05, 0.55, 0.62), (-0.05, 0.55, 0.78), 0.72, "steel", n=48,
                                 profile=[(0.0, 0.66), (0.3, 0.72), (0.7, 0.72), (1.0, 0.66)]), 2)
    knob_base = (-0.05 + 0.5, 0.55 + 0.38, 0.78)
    knob = order(solid.cylinder(knob_base, (knob_base[0], knob_base[1], 1.12), 0.08, "ember", n=14,
                                profile=[(0.0, 0.06), (0.25, 0.06), (0.3, 0.09), (1.0, 0.09)]), 5)
    gear = order(solid.cylinder((0.75, 0.55, 0.0), (0.92, 0.55, 0.0), 0.36, "steel", n=12), -1)

    def dec(d, f, tags):
        c = (-0.05, 0.55, 0.78)
        cap = f(on_axis_plane(G.circle(0, 0, 0.66, n=64), c, (0, 0, 1)))
        holes = G.union([G.diff(G.arc_band(0, 0, 0.54, 0.2, a + 14, a + 76, n=12), G.EMPTY) for a in (0, 90, 180, 270)])
        d.engrave(G.inter(f(on_axis_plane(holes, c, (0, 0, 1))), cap), "steel", cap, depth=0.8)
        hub = f(on_axis_plane(G.circle(0, 0, 0.13, n=20), c, (0, 0, 1)))
        d.path(hub, MATERIALS["steel"][2])
        # elevation scale on the gearbox front
        face = f(front(G.rect(-0.8, 0.05, 0.7, 1.0), 0, 1.05, 0.5))
        sc = G.union([G.rect(0.42, 0.18 + i * 0.13, 0.62 if i % 2 == 0 else 0.54, 0.22 + i * 0.13) for i in range(6)])
        d.engrave(G.inter(f(front(sc, 0, 1.05, 0.5)), face), "gunmetal", face, depth=0.6)
    render(d, [box] + gear + shaft + wheel + knob, [dec])


def ventilation(d):
    """Ventilation unit: housing with a bladed fan on the front, louvres on the side, a top duct."""
    W, H, D = 0.85, 1.35, 0.42
    box = order(solid.box(-W, 0.0, -D, W, H, D, "gunmetal", chamfer=0.06), 0)
    duct = order(solid.cylinder((0.25, H, -0.05), (0.25, H + 0.3, -0.05), 0.26, "steel", n=28), 1)

    def dec(d, f, tags):
        face = f(front(G.rect(-W + 0.05, 0.05, W - 0.05, H - 0.05), 0, H, D))
        c = (0.0, 0.70)
        well = G.circle(*c, 0.66, n=72)
        d.engrave(G.inter(f(front(well, 0, H, D)), face), "gunmetal", face, depth=0.9)
        blades = []
        for i in range(5):
            a = i * 72
            bl = G.poly([(0.08, -0.08), (0.58, -0.22), (0.62, 0.02), (0.12, 0.10)])
            blades.append(G.R(bl, a, (0, 0)))
        blades = G.T(G.union(blades), *c)
        hubg = G.circle(*c, 0.15, n=24)
        bg = f(front(G.union(blades, hubg), 0, H, D))
        d.inlay(G.inter(bg, f(front(well, 0, H, D))), "steel", face, bevel=0.6, shadow=(0.6, 0.7))
        grill = G.diff(G.circle(*c, 0.66, n=72), G.circle(*c, 0.58, n=72))
        d.path(G.inter(f(front(grill, 0, H, D)), face), MATERIALS["steel"][1])
        # louvres on the left side
        lf = f(left(G.rect(0.05, 0.05, 2 * D - 0.05, H - 0.05), -D, H, -W))
        lv = G.union([G.rect(0.12, 0.2 + i * 0.2, 2 * D - 0.12, 0.28 + i * 0.2) for i in range(5)])
        d.engrave(G.inter(f(left(lv, -D, H, -W)), lf), "gunmetal", lf, depth=0.6)
    render(d, [box] + duct, [dec])


def _tilted_axis():
    return solid._norm((-0.42, 0.52, 1.0))


def coated_optics(d):
    """Coated objective lens: steel barrel, knurled ring, and a large glass element with the
    violet/teal coating sheen that coated optics show."""
    ax = _tilted_axis()
    c = (0.0, 0.0, 0.0)
    prof = [(-0.55, 0.9, "steel"), (0.10, 0.9, "steel"), (0.10, 0.97, "gunmetal"), (0.30, 0.97, "gunmetal"),
            (0.30, 0.0, "steel")]
    lens = solid.revolve(prof, axis=ax, centre=c, n=48, name="lens")

    def dec(d, f, tags):
        cc = solid._add(c, solid._mul(ax, 0.30))
        rim = f(on_axis_plane(G.circle(0, 0, 0.86, n=64), cc, ax))
        d.path(rim, MATERIALS["gunmetal"][2])
        glass_disc(d, f, cc, ax, 0.78, coat=True)
        knurl = G.union([G.R(G.rect(0.9, -0.012, 1.0, 0.012), a, (0, 0)) for a in range(0, 360, 12)])
        _ = knurl
    render(d, lens, [dec])


def binoculars(d):
    """Binoculars: two barrels on a hinge bridge, objective glass toward the viewer."""
    ax = solid._norm((-0.30, 0.34, 1.0))
    ss = []
    fronts = []
    for i, x in enumerate((-0.52, 0.52)):
        base = (x, 0.0, 0.0)
        prof = [(-0.85, 0.20, "gunmetal"), (-0.62, 0.20, "gunmetal"), (-0.62, 0.36, "gunmetal"), (0.40, 0.36, "gunmetal"),
                (0.40, 0.42, "steel"), (0.62, 0.42, "steel"), (0.62, 0.0, "steel")]
        sol = solid.revolve(prof, axis=ax, centre=base, n=40, name=f"barrel{i}")
        order(sol, i * 10)
        ss += sol
        fronts.append(solid._add(base, solid._mul(ax, 0.62)))
    bridge = order(solid.extrude([(-0.3, -0.16), (0.3, -0.16), (0.3, 0.16), (-0.3, 0.16)], solid._mul(ax, -0.2),
                                 (1, 0, 0), (0, 1, 0), solid._mul(ax, 0.42), "steel", name="bridge"), 5)
    focus = order(solid.cylinder(solid._add(solid._mul(ax, -0.1), (0, 0.16, 0)), solid._add(solid._mul(ax, -0.1), (0, 0.34, 0)),
                                 0.13, "steel", n=16), 6)

    def dec(d, f, tags):
        for c in fronts:
            glass_disc(d, f, c, ax, 0.33)
    render(d, ss + [bridge] + focus, [dec])


def camo_net(d):
    """Camouflage net rolled and strapped: olive roll with camo blotches, a spiral end, khaki straps."""
    R = 0.48
    octo = [(R * math.cos(math.radians(a)), R * math.sin(math.radians(a))) for a in range(0, 360, 45)]
    roll = solid.extrude(octo, (-1.0, R, 0.0), (0, 0, 1), (0, 1, 0), (2.0, 0, 0), "olive", name="roll")
    order(roll, 0)
    straps = []
    for i, x in enumerate((-0.55, 0.45)):
        oc = [(1.07 * px, 1.07 * py) for px, py in octo]
        st = solid.extrude(oc, (x, R, 0.0), (0, 0, 1), (0, 1, 0), (0.16, 0, 0), "khaki", name="strap")
        order(st, 1 + i)
        straps.append(st)

    def pre(d, f):
        pass

    def dec(d, f, tags):
        body = f(solid.Scene().add([roll]).silhouette())
        blotches = []
        rnd = [(-0.7, 0.62, 0.20), (-0.15, 0.30, 0.17), (0.25, 0.70, 0.22), (0.72, 0.38, 0.18), (-0.45, 0.20, 0.13),
               (0.55, 0.80, 0.12)]
        for i, (x, y, r) in enumerate(rnd):
            g = solid.plane_map(G.ngon(0, 0, r, 7, rot_deg=i * 17), (x, y, R * 0.9), (1, 0, 0), (0, -1, 0.0))
            blotches.append((g, "khaki" if i % 2 == 0 else "obsidian"))
        straps_sil = f(solid.Scene().add(straps).silhouette())
        for g, m in blotches:
            gg = G.diff(G.inter(f(g), G.shrink(body, 0.9)), straps_sil)
            d.path(gg, MATERIALS[m][1], 0.9)
        # spiral on the visible end
        pts = []
        for i in range(0, 60):
            t = i / 59
            ang = t * 2.6 * 2 * math.pi
            rr = 0.05 + t * (R * 0.82)
            pts.append((rr * math.cos(ang), rr * math.sin(ang)))
        sp = kit.stroke(pts, 0.06)
        end = solid.plane_map(sp, (-1.0, R, 0.0), (0, 0, 1), (0, -1, 0))
        cap = tags.get("cap0")
        g = f(end)
        if cap is not None:
            g = G.inter(g, cap)
        d.path(g, INK, 0.75)
    render(d, [roll] + straps, [dec], pre=pre)


def spall_liner(d):
    """Spall liner: a quilted aramid pad on a steel backing plate, standing on its edge."""
    back = order(solid.box(-0.9, 0.0, -0.10, 0.9, 1.5, 0.02, "gunmetal", chamfer=0.03), 0)
    pad = order(solid.box(-0.80, 0.08, 0.02, 0.80, 1.42, 0.22, "khaki", chamfer=0.03), 1)

    def dec(d, f, tags):
        face = f(front(G.rect(-0.76, 0.04, 0.76, 1.30), 0, 1.42, 0.22))
        seams = G.union([G.rect(-0.76, y, 0.76, y + 0.045) for y in (0.33, 0.66, 0.99)] +
                        [G.rect(x, 0.04, x + 0.045, 1.30) for x in (-0.28, 0.24)])
        d.engrave(G.inter(f(front(seams, 0, 1.42, 0.22)), face), "khaki", face, depth=0.6)
        bolts = G.union([G.circle(x, y, 0.045, n=12) for x in (-0.84, 0.84) for y in (0.12, 1.38)])
        _ = bolts
    bolts = []
    for x in (-0.86, 0.86):
        for y in (0.16, 1.34):
            b = order(solid.cylinder((x, y, 0.02), (x, y, 0.09), 0.05, "steel", n=6), 2)
            bolts += b
    render(d, [back, pad] + bolts, [dec])


def hardening(d):
    """Hardened armor: a thick bolted steel plate with an enemy shot stuck in it, base toward the
    viewer, cracks radiating round the impact: the hit did not get through."""
    W, H, T = 0.95, 1.5, 0.22
    plate = order(solid.box(-W, 0.0, -T, W, H, T, "steel", chamfer=0.06), 0)
    bolts = []
    for x in (-0.78, 0.78):
        for y in (0.18, 1.32):
            b = order(solid.cylinder((x, y, T), (x, y, T + 0.07), 0.08, "gunmetal", n=6), 1)
            bolts += b
    hit = (0.28, 0.70, T)
    ax = solid._norm((-1.0, 0.42, 0.62))
    prof = [(0.0, 0.21, "ap"), (0.28, 0.21, "ap"), (0.28, 0.22, "copper"), (0.40, 0.22, "copper"),
            (0.40, 0.24, "brass"), (1.08, 0.24, "brass"), (1.08, 0.28, "brass"), (1.18, 0.28, "brass"), (1.18, 0.0, "brass")]
    shell = order(solid.revolve(prof, axis=ax, centre=hit, n=36, name="stuck"), 5)

    def dec(d, f, tags):
        face = f(front(G.rect(-W + 0.06, 0.06, W - 0.06, H - 0.06), 0, H, T))
        c = (hit[0], H - hit[1])
        cracks = G.union([G.R(G.poly([(0.16, -0.035), (0.62 if i % 2 else 0.46, 0.0), (0.16, 0.035)]), a, (0, 0))
                          for i, a in enumerate((10, 70, 130, 190, 250, 310))])
        d.engrave(G.inter(f(front(G.T(cracks, *c), 0, H, T)), face), "steel", face, depth=0.8)
        crater = G.diff(G.circle(*c, 0.27, n=40), G.circle(*c, 0.18, n=40))
        d.path(G.inter(f(front(crater, 0, H, T)), face), MATERIALS["steel"][2], 0.85)
        primer = f(on_axis_plane(G.circle(0, 0, 0.08, n=16), solid._add(hit, solid._mul(ax, 1.18)), ax))
        d.path(primer, MATERIALS["copper"][1])
    render(d, [plate] + bolts + shell, [dec])


def turbocharger(d):
    """Turbocharger: snail-shell volute, compressor intake with blades, tangential outlet duct."""
    c = (0.0, 0.75, 0.0)
    vol = order(solid.cylinder((0.0, 0.75, -0.32), (0.0, 0.75, 0.30), 0.78, "gunmetal", n=48,
                               profile=[(0.0, 0.72), (0.12, 0.78), (0.88, 0.78), (1.0, 0.72)]), 0)
    intake = order(solid.cylinder((0.0, 0.75, 0.30), (0.0, 0.75, 0.58), 0.40, "steel", n=40,
                                  profile=[(0.0, 0.42), (0.7, 0.42), (0.7, 0.46), (1.0, 0.46)]), 2)
    outlet = order(solid.box(0.10, 1.18, -0.24, 1.15, 1.53, 0.22, "gunmetal"), -1)
    flange = order(solid.box(1.05, 1.10, -0.30, 1.18, 1.61, 0.28, "steel"), -0.5)
    foot = order(solid.box(-0.55, 0.0, -0.3, 0.55, 0.16, 0.3, "gunmetal"), -2)

    def dec(d, f, tags):
        cc = (0.0, 0.75, 0.58)
        mouth = f(on_axis_plane(G.circle(0, 0, 0.36, n=48), cc, (0, 0, 1)))
        d.path(G.grow(mouth, 0.3), INK)
        blades = []
        for i in range(7):
            bl = G.poly([(0.04, 0.0), (0.33, -0.10), (0.34, -0.02), (0.06, 0.06)])
            blades.append(G.R(bl, i * 360 / 7, (0, 0)))
        bg = f(on_axis_plane(G.union(blades + [G.circle(0, 0, 0.08, n=16)]), cc, (0, 0, 1)))
        d.path(G.inter(bg, mouth), MATERIALS["steel"][1])
        d.path(G.inter(G.T(bg, -0.4, -0.4), mouth), MATERIALS["steel"][0], 0.5)
    render(d, [foot, outlet, flange] + vol + intake, [dec])


def rotation_mechanism(d):
    """Traverse mechanism: a ring gear lying flat with a rotation arrow, driven by a pinion motor."""
    gear2d = G.gear(0, 0, 1.0, 1.12, 30, tooth_frac=0.5, tip_frac=0.32)
    pts = list(gear2d.exterior.coords)[:-1]
    ring = solid.extrude(pts, (0, 0.0, 0), (1, 0, 0), (0, 0, 1), (0, 0.22, 0), "steel", top_tag="top", name="ring")
    order(ring, 0)
    motor = order(solid.cylinder((-0.95, 0.0, 0.95), (-0.95, 0.85, 0.95), 0.27, "gunmetal", n=32), 5)
    mcap = order(solid.cylinder((-0.95, 0.85, 0.95), (-0.95, 0.98, 0.95), 0.2, "steel", n=24), 6)
    pin2d = G.gear(0, 0, 0.17, 0.25, 9, tooth_frac=0.5, tip_frac=0.32)
    pin = solid.extrude(list(pin2d.exterior.coords)[:-1], (-0.95, 0.02, 0.95), (1, 0, 0), (0, 0, 1), (0, 0.18, 0),
                        "steel", top_tag="pin", name="pinion")
    order(pin, 4)

    def dec(d, f, tags):
        tf = tags.get("top")
        hole = f(top(G.circle(0, 0, 0.62, n=72), 0, 0, 0.22))
        d.path(G.inter(G.grow(hole, 0.4), tf), MATERIALS["steel"][2])
        d.path(G.inter(hole, tf), INK)
        arr = kit.arc_arrow(0, 0, 0.82, 0.13, 150, 330, head_len=0.26, head_half=0.17)
        g = G.inter(f(top(arr, 0, 0, 0.22)), tf)
        d.keyline(g, 0.8)
        d.plate(g, "dusk", bevel=0.6)
    render(d, [ring, pin] + motor + mcap, [dec])


def configuration(d):
    """Field configuration: a calibration gauge on a T-fitting (fine-tuning of every system)."""
    c = (0.0, 0.92, 0.0)
    bez = order(solid.cylinder((0.0, 0.92, -0.18), (0.0, 0.92, 0.12), 0.78, "steel", n=48,
                               profile=[(0.0, 0.7), (0.2, 0.78), (1.0, 0.78)]), 2)
    stem = order(solid.cylinder((0.0, 0.0, -0.03), (0.0, 0.2, -0.03), 0.15, "brass", n=6), 0)
    neck = order(solid.cylinder((0.0, 0.18, -0.03), (0.0, 0.3, -0.03), 0.09, "brass", n=16), 1)
    pipe = order(solid.cylinder((-0.75, 0.08, -0.03), (0.75, 0.08, -0.03), 0.10, "brass", n=16), -1)

    def dec(d, f, tags):
        cc = (0.0, 0.92, 0.12)
        face = f(on_axis_plane(G.circle(0, 0, 0.64, n=72), cc, (0, 0, 1)))
        d.path(G.grow(face, 0.4), INK)
        d.path(face, MATERIALS["bone"][1])
        ticks = []
        for i in range(9):
            a = math.radians(150 + i * 30)
            p0 = (0.44 * math.cos(a), 0.44 * math.sin(a))
            p1 = (0.56 * math.cos(a), 0.56 * math.sin(a))
            ticks.append(G.thick_line(p0, p1, 0.06 if i % 2 else 0.09))
        d.path(G.inter(f(on_axis_plane(G.union(ticks), cc, (0, 0, 1))), face), INK)
        zone = kit.arc(0, 0, 0.5, 0.1, 330, 390, n=16)
        d.path(G.inter(f(on_axis_plane(zone, cc, (0, 0, 1))), face), MATERIALS["verdant"][1])
        ndl = G.union(G.poly([(-0.05, 0.05), (0.46, -0.30), (0.03, -0.06)]), G.circle(0, 0, 0.08, n=16))
        d.path(f(on_axis_plane(ndl, cc, (0, 0, 1))), MATERIALS["ember"][1])
        gl = f(on_axis_plane(G.arc_band(0, 0, 0.6, 0.52, 200, 250, n=12), cc, (0, 0, 1)))
        d.path(gl, "#FFFFFF", 0.7)
    render(d, pipe + stem + neck + bez, [dec])


def low_noise_exhaust(d):
    """Low-noise exhaust: an oval silencer drum with clamp bands, baffle cap and an angled tailpipe."""
    prof = [(-0.85, 0.50, "gunmetal"), (-0.78, 0.58, "gunmetal"), (0.78, 0.58, "gunmetal"), (0.85, 0.50, "gunmetal")]
    drum = order(solid.revolve(prof, axis=(1, 0, 0), centre=(0, 0.62, 0), n=40), 0)
    bands = []
    for i, x in enumerate((-0.45, 0.40)):
        bands += order(solid.revolve([(x - 0.07, 0.61, "steel"), (x + 0.07, 0.61, "steel")], axis=(1, 0, 0),
                                     centre=(0, 0.62, 0), n=40), 1 + i)
    tail = order(solid.cylinder((-0.82, 0.62, 0.0), (-1.22, 0.62, 0.0), 0.16, "steel", n=20), 4)
    tip = order(solid.cylinder((-1.22, 0.62, 0.0), (-1.35, 0.86, 0.0), 0.16, "steel", n=20), 5)
    feet = [order(solid.box(x - 0.12, 0.0, -0.28, x + 0.12, 0.24, 0.28, "gunmetal"), -1) for x in (-0.5, 0.45)]
    inlet = order(solid.cylinder((0.95, 0.62, 0.0), (1.25, 0.62, 0.0), 0.13, "steel", n=16), -2)

    def dec(d, f, tags):
        # muffled waves: two short arcs at the tailpipe, fading
        tp = proj.project((-1.35, 0.92, 0.0))
        for i, (r, a) in enumerate(((0.32, 0.85), (0.52, 0.5))):
            arc_g = G.arc_band(tp[0], tp[1], r + 0.04, r - 0.04, 195, 255, n=12)
            d.path(f(arc_g), MATERIALS["steel"][0], a)
    render(d, inlet + feet + drum + bands + tail + tip, [dec])


def toolbox(d):
    """Mechanic's tool chest (repair speed): three drawers with brass pulls, lid with a handle."""
    W, H, D = 0.95, 1.15, 0.5
    body = order(solid.box(-W, 0.0, -D, W, H, D, "cobalt", chamfer=0.05), 0)
    lid = order(solid.box(-W - 0.03, H, -D - 0.03, W + 0.03, H + 0.16, D + 0.03, "cobalt", chamfer=0.06), 1)
    posts = [order(solid.box(x - 0.05, H + 0.16, -0.06, x + 0.05, H + 0.34, 0.06, "steel"), 2) for x in (-0.45, 0.45)]
    bar = order(solid.box(-0.52, H + 0.30, -0.08, 0.52, H + 0.40, 0.08, "steel"), 3)

    def dec(d, f, tags):
        face = f(front(G.rect(-W + 0.05, 0.04, W - 0.05, H - 0.04), 0, H, D))
        drawers = G.union([G.diff(G.rect(-W + 0.1, 0.1 + i * 0.35, W - 0.1, 0.38 + i * 0.35),
                                  G.rect(-W + 0.14, 0.14 + i * 0.35, W - 0.14, 0.34 + i * 0.35)) for i in range(3)])
        d.engrave(G.inter(f(front(drawers, 0, H, D)), face), "cobalt", face, depth=0.6)
        pulls = G.union([G.cbox(-0.24, 0.2 + i * 0.35, 0.24, 0.29 + i * 0.35, 0.03, 0.03, 0.03, 0.03) for i in range(3)])
        d.inlay(G.inter(f(front(pulls, 0, H, D)), face), "brass", face, bevel=0.5, shadow=(0.6, 0.7))
    render(d, [body, lid] + posts + [bar], [dec])


def reinforced_suspension(d):
    """Coil-over suspension strut: damper body, rod, mounting eyes and a heavy ember coil spring."""
    body = order(solid.cylinder((0.0, 0.18, 0.0), (0.0, 1.15, 0.0), 0.22, "gunmetal", n=32), 0)
    rod = order(solid.cylinder((0.0, 1.15, 0.0), (0.0, 1.62, 0.0), 0.09, "steel", n=16), 1)
    seat_lo = order(solid.cylinder((0.0, 0.26, 0.0), (0.0, 0.34, 0.0), 0.48, "steel", n=40), -5)
    seat_hi = order(solid.cylinder((0.0, 1.56, 0.0), (0.0, 1.64, 0.0), 0.48, "steel", n=40), 20)
    eye_lo = order(solid.box(-0.24, 0.0, -0.13, 0.24, 0.20, 0.13, "steel"), -6)
    eye_hi = order(solid.box(-0.24, 1.64, -0.13, 0.24, 1.86, 0.13, "steel"), 21)
    R, y0, y1, turns, wire = 0.40, 0.34, 1.56, 3.0, 0.075

    def helix(front_part):
        segs = []
        N = 220
        cur = []
        for i in range(N + 1):
            t = i / N
            ang = t * turns * 2 * math.pi
            p = (R * math.cos(ang), y0 + (y1 - y0) * t, R * math.sin(ang))
            fr = solid._dot((math.cos(ang), 0, math.sin(ang)), solid.VIEW) > 0
            if fr == front_part:
                cur.append(proj.project(p))
            elif cur:
                if len(cur) > 1:
                    segs.append(cur)
                cur = []
        if len(cur) > 1:
            segs.append(cur)
        return segs

    sc = solid.Scene().add([eye_lo] + seat_lo + body + rod + seat_hi + [eye_hi])
    back_lines = helix(False)
    front_lines = helix(True)
    k_scale = 1.0

    def shapes(lines, f, w):
        return G.union([f(kit.stroke(l, w * 2, cap="flat")) for l in lines])

    extra = G.union([kit.stroke(l, wire * 2) for l in back_lines + front_lines])
    f = sc.fitter(BOX, extra=extra)
    sil = G.union(f(sc.silhouette()), f(extra))
    kit.check(sil, "reinforced_suspension", lo=BOX[0] - 0.05, hi=BOX[2] + 0.05)
    d.path(sil.buffer(kit.KEY, join_style=3), INK)
    back = shapes(back_lines, f, wire)
    d.path(back, MATERIALS["ember"][2])
    # paint the strut without its own outer keyline (already drawn), then the front coils over it
    sc.render(d, f, draw_keyline=False)
    fr = shapes(front_lines, f, wire)
    d.keyline(fr, 0.8, INK, 0.9)
    d.plate(fr, "ember", bevel=0.8)
    _ = k_scale


def radio_upgrade(d):
    """Upgraded radio: an olive set with an amplifier stacked on top, a tall whip antenna on an
    insulator, and broadcast arcs at the tip."""
    W, H, D = 0.9, 0.9, 0.45
    setb = order(solid.box(-W, 0.0, -D, W, H, D, "olive", chamfer=0.05), 0)
    amp = order(solid.box(-0.75, H, -0.36, 0.45, H + 0.36, 0.36, "gunmetal", chamfer=0.04), 1)
    ins = order(solid.cylinder((0.68, H, 0.0), (0.68, H + 0.2, 0.0), 0.11, "bone", n=16), 2)
    mast = order(solid.cylinder((0.68, H + 0.2, 0.0), (0.68, H + 1.15, 0.0), 0.04, "steel", n=8), 3)
    tipb = order(solid.cylinder((0.68, H + 1.15, 0.0), (0.68, H + 1.23, 0.0), 0.07, "steel", n=12), 4)
    tp = proj.project((0.68, H + 1.2, 0.0))
    arcs = G.union([G.arc_band(tp[0], tp[1], r + 0.05, r - 0.05, a0, a1, n=12) for r in (0.22, 0.40)
                    for a0, a1 in ((-40, 40), (140, 220))])

    def dec(d, f, tags):
        face = f(front(G.rect(-W + 0.05, 0.04, W - 0.05, H - 0.04), 0, H, D))
        dial = G.diff(G.circle(-0.45, 0.45, 0.24, n=40), G.circle(-0.45, 0.45, 0.17, n=40))
        d.engrave(G.inter(f(front(dial, 0, H, D)), face), "olive", face, depth=0.6)
        d.inlay(G.inter(f(front(G.circle(-0.45, 0.45, 0.1, n=20), 0, H, D)), face), "bone", face, bevel=0.4, shadow=(0.4, 0.5))
        gr = G.union([G.rect(0.0, 0.25 + i * 0.13, 0.7, 0.31 + i * 0.13) for i in range(4)])
        d.engrave(G.inter(f(front(gr, 0, H, D)), face), "olive", face, depth=0.5)
        af = f(front(G.rect(-0.7, 0.04, 0.4, 0.32), 0, H + 0.36, 0.36))
        lamp = f(front(G.cbox(0.1, 0.1, 0.28, 0.24, 0.03, 0.03, 0.03, 0.03), 0, H + 0.36, 0.36))
        d.path(G.inter(lamp, af), MATERIALS["verdant"][1])
        g = f(arcs)
        d.keyline(g, 1.2)
        d.path(g, MATERIALS["bone"][1])
    render(d, [setb, amp] + ins + mast + tipb, [dec], extra=arcs)


ITEMS = [
    ("rammer", "Gun rammer", "firepower", "Reload time", rammer),
    ("stabilizer", "Gun stabilizer", "firepower", "Dispersion on the move", stabilizer),
    ("improved_aiming", "Improved aiming drive", "firepower", "Aiming time", improved_aiming),
    ("ventilation", "Improved ventilation", "all", "Crew skill (all categories)", ventilation),
    ("coated_optics", "Coated optics", "scouting", "View range", coated_optics),
    ("binoculars", "Binoculars", "scouting", "View range while stationary", binoculars),
    ("camo_net", "Camouflage net", "scouting", "Concealment while stationary", camo_net),
    ("spall_liner", "Spall liner", "survivability", "HE / ramming protection, stun", spall_liner),
    ("hardening", "Improved hardening", "survivability", "Vehicle and module HP", hardening),
    ("turbocharger", "Turbocharger", "mobility", "Engine power, top speed", turbocharger),
    ("rotation_mechanism", "Rotation mechanism", "mobility", "Turret and hull traverse", rotation_mechanism),
    ("configuration", "Field configuration", "all", "Small bonus to every system", configuration),
    ("low_noise_exhaust", "Low-noise exhaust", "scouting", "Concealment on the move", low_noise_exhaust),
    ("toolbox", "Toolbox", "survivability", "Repair speed", toolbox),
    ("reinforced_suspension", "Reinforced suspension", "survivability", "Track HP, load capacity", reinforced_suspension),
    ("radio_upgrade", "Radio upgrade", "scouting", "Signal range", radio_upgrade),
]


# ---------------------------------------------------------------------------
# Categories (flat symbols)
# ---------------------------------------------------------------------------
CATS = {
    "firepower": ("ember", "Firepower"),
    "survivability": ("cobalt", "Survivability"),
    "mobility": ("jade", "Mobility"),
    "scouting": ("scout", "Scouting"),
}


def _cat_glyph(cat):
    if cat == "firepower":
        # reticle: heavy ring, four ticks, centre pip
        c = (32, 32)
        g = G.union(kit.ring(*c, 12.0, 4.6, n=72), G.circle(*c, 3.4, n=32),
                    G.rect(29.6, 10, 34.4, 20.5), G.rect(29.6, 43.5, 34.4, 54), G.rect(10, 29.6, 20.5, 34.4),
                    G.rect(43.5, 29.6, 54, 34.4))
    elif cat == "survivability":
        # armoured heart: angular heart split by a horizontal armour band (vehicle HP, protection)
        heart = G.poly([(32, 54), (10, 32), (10, 22), (17, 14), (25, 14), (32, 21), (39, 14), (47, 14), (54, 22), (54, 32)])
        band = G.rect(0, 29.5, 64, 33.5)
        g = G.diff(heart, band)
    elif cat == "mobility":
        # road wheel with speed lines
        c = (38, 32)
        wheel = G.diff(G.circle(*c, 15.5, n=72), G.circle(*c, 5.0, n=40))
        holes = G.union([G.circle(c[0] + 9.6 * math.cos(math.radians(a)), c[1] + 9.6 * math.sin(math.radians(a)), 2.4, n=20)
                         for a in (45, 135, 225, 315)])
        lines = G.union(G.rect(8, 22.5, 20, 26.5), G.rect(6, 30, 19, 34), G.rect(8, 37.5, 20, 41.5))
        g = G.union(G.diff(wheel, holes), lines)
    elif cat == "scouting":
        # binoculars, front view
        l = G.cbox(10, 20, 29, 52, 5, 5, 6, 6)
        r = G.cbox(35, 20, 54, 52, 5, 5, 6, 6)
        br = G.rect(27, 26, 37, 40)
        knob = G.cbox(28.5, 13, 35.5, 22, 1.5, 1.5, 0, 0)
        lens = G.union(G.circle(19.5, 41, 6.4, n=48), G.circle(44.5, 41, 6.4, n=48))
        g = G.diff(G.union(l, r, br, knob), lens)
    else:
        raise KeyError(cat)
    return g


def draw_category(d, cat):
    mat, _ = CATS[cat]
    tile = G.cbox(7, 7, 57, 57, 11, 3, 11, 3)
    kit.check(tile, f"cat_{cat}")
    d.keyline(tile, kit.KEY)
    face = d.plate(tile, mat, bevel=kit.BEV)
    g = _cat_glyph(cat)
    g, = kit.shrink_to(g, box=(14, 14, 50, 50))
    d.inlay(G.inter(g, G.shrink(face, 0.5)), "bone", face, bevel=1.0, shadow=(1.1, 1.3))


# ---------------------------------------------------------------------------
# Grade overlays
# ---------------------------------------------------------------------------
def grade_shapes(grade):
    if grade == "improved":
        return kit.corner_brackets(4.2, 4.2, 59.8, 59.8, 15.0, 3.6, chamfer=4.0)
    outer = G.cbox(4.2, 4.2, 59.8, 59.8, 9, 9, 9, 9)
    inner = G.cbox(7.8, 7.8, 56.2, 56.2, 6.6, 6.6, 6.6, 6.6)
    ring = G.diff(outer, inner)
    tabs = G.union([G.T(G.R(G.rect(-4.5, -1.3, 4.5, 1.3), 45 + 90 * i, (0, 0)), *c) for i, c in
                    enumerate(((9.4, 9.4), (54.6, 9.4), (54.6, 54.6), (9.4, 54.6)))])
    return G.union(ring, G.diff(tabs, G.EMPTY))


def draw_grade(d, grade):
    g = grade_shapes(grade)
    mat = "silver" if grade == "improved" else "dusk"
    d.path(G.grow(g, 1.3), INK)
    d.plate(g, mat, bevel=1.0)
    if grade == "experimental":
        for c in ((9.4, 9.4), (54.6, 9.4), (54.6, 54.6), (9.4, 54.6)):
            b = G.circle(*c, 1.5, n=16)
            d.path(G.grow(b, 0.6), INK)
            d.path(b, MATERIALS["dusk"][0])


def _register():
    note("equipment", "Equipment: items (3/4 objects inside 10..54), category tiles `cat_*`, and grade "
                      "overlays `grade_improved` / `grade_experimental` (composite on top of the item at the "
                      "same size; standard = no overlay). `examples/` are pre-composited previews.")
    for cat, (mat, name) in CATS.items():
        add("equipment", f"cat_{cat}", f"Equipment category: {name}",
            f"{name} category: slot chip, equipment filter tab, bonus-slot marker",
            lambda d, c=cat: draw_category(d, c))
    for key, name, cat, effect, fn in ITEMS:
        cat_txt = "all-round" if cat == "all" else cat
        add("equipment", key, f"Equipment: {name}", f"{name} ({cat_txt}): {effect}", fn)
    add("equipment", "grade_improved", "Equipment grade overlay: improved (silver brackets)",
        "Overlay for Improved grade: composite over any item icon at the same size", lambda d: draw_grade(d, "improved"))
    add("equipment", "grade_experimental", "Equipment grade overlay: experimental (dusk frame)",
        "Overlay for Experimental grade: composite over any item icon at the same size",
        lambda d: draw_grade(d, "experimental"))
    fns = {k: fn for k, _, _, _, fn in ITEMS}
    for key, grade in (("rammer", "improved"), ("rammer", "experimental"), ("turbocharger", "improved"),
                       ("coated_optics", "experimental"), ("spall_liner", "improved"), ("stabilizer", "experimental")):
        add("equipment", f"{key}_{grade}", f"Equipment example: {key} ({grade})",
            f"Preview only: `{key}` + `grade_{grade}` composited", lambda d, k=key, g=grade: (fns[k](d), draw_grade(d, g)),
            subdir="examples")


_register()
