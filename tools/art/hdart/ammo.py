"""Ammunition icons (assets/icons/ammo/).

Shells are physical objects: bodies of revolution standing on their case base, seen through the fixed
3/4 camera. Every type owns a unique NOSE SILHOUETTE, so the five types read apart in solid black:

    ap    full-calibre shot, long sharp tangent ogive
    apcr  sub-calibre: a short full-calibre sabot collar, tapered petals, a thin penetrator needle
    he    full-calibre, short blunt ogive cut flat for a protruding point-detonating fuze
    heat  full-calibre, straight cone shoulder plus a thin stand-off probe with a small crown
    hesh  short body with a wide, blunt squash dome (shortest round of the set)

The projectile is painted in the type colour (ammo.* tokens) with a copper driving band; standard
cases are lacquered steel. Special (premium) rounds keep the same silhouette but take a gold case and
the gold-rim treatment (kit.rim_keyline). All rounds share one scale and one base line, so their
heights compare honestly when shown side by side in the ammo bar.
"""

from __future__ import annotations

import math

from shapely import affinity

from . import geom as G
from . import kit, solid
from .registry import add, note

TYPES = ["ap", "apcr", "he", "heat", "hesh"]
NAMES = {"ap": "AP (armor-piercing)", "apcr": "APCR (sub-calibre composite)", "he": "HE (high-explosive)",
         "heat": "HEAT (shaped charge)", "hesh": "HESH (squash head)"}
CASE_TOP = 1.25
CASE_STD = "gunmetal"


def _ogive(s0, length, r0, r_end=0.0, steps=14):
    """Tangent ogive from radius r0 at s0, closing to the tip over `length` (optionally truncated at
    r_end). Returns list of (s, r)."""
    rho = (r0 * r0 + length * length) / (2 * r0)
    out = []
    for i in range(1, steps + 1):
        x = length * i / steps
        r = math.sqrt(max(rho * rho - x * x, 0.0)) - (rho - r0)
        if r <= r_end:
            # solve for the exact truncation point
            xe = math.sqrt(max(rho * rho - (r_end + rho - r0) ** 2, 0.0))
            out.append((s0 + xe, r_end))
            break
        out.append((s0 + x, max(r, 0.0)))
    return out


def _case(mat):
    """Cartridge case: rim, extractor groove, slightly tapered body, mouth. Returns profile points."""
    return [
        (0.00, 1.16, mat), (0.12, 1.16, mat), (0.12, 0.98, mat), (0.21, 0.98, mat), (0.21, 1.08, mat),
        (CASE_TOP, 1.05, mat),
    ]


def _band(s):
    """Copper driving band just above the case mouth."""
    return [(s, 1.0, "copper"), (s, 1.03, "copper"), (s + 0.19, 1.03, "copper"), (s + 0.19, 1.0, "copper")]


def profile(kind: str, case_mat: str):
    p = _case(case_mat)
    s = CASE_TOP
    if kind == "ap":
        paint = "ap"
        p += _band(s) + [(s + 0.19, 1.0, paint), (s + 1.05, 1.0, paint)]
        p += [(ss, rr, paint) for ss, rr in _ogive(s + 1.05, 2.55, 1.0, steps=16)]
    elif kind == "apcr":
        sab = "gunmetal"
        p += [(s, 1.0, sab), (s + 0.12, 1.0, sab)] + _band(s + 0.12)[1:3] + [(s + 0.31, 1.0, sab), (s + 0.62, 1.0, sab),
              (s + 0.98, 0.56, sab), (s + 0.98, 0.43, "apcr"), (s + 3.05, 0.43, "apcr")]
        p += [(ss, rr, "apcr") for ss, rr in _ogive(s + 3.05, 0.78, 0.43, steps=8)]
    elif kind == "he":
        paint = "he"
        p += _band(s) + [(s + 0.19, 1.0, paint), (s + 1.0, 1.0, paint)]
        og = _ogive(s + 1.0, 2.2, 1.0, r_end=0.31, steps=14)
        p += [(ss, rr, paint) for ss, rr in og]
        top = og[-1][0]
        # point-detonating fuze: steel body, then a short cone to a flat nub
        p += [(top, 0.29, "steel"), (top + 0.30, 0.29, "steel"), (top + 0.52, 0.13, "steel")]
    elif kind == "heat":
        paint = "heat"
        p += _band(s) + [(s + 0.19, 1.0, paint), (s + 0.80, 1.0, paint), (s + 1.85, 0.33, paint),
                          (s + 1.85, 0.17, "steel"), (s + 3.35, 0.17, "steel"), (s + 3.35, 0.31, "steel"),
                          (s + 3.55, 0.31, "steel"), (s + 3.70, 0.12, "steel")]
    elif kind == "hesh":
        p += _band(s) + [(s + 0.19, 1.0, "olive"), (s + 0.55, 1.0, "olive"), (s + 0.55, 1.0, "he"),
                          (s + 0.78, 1.0, "he"), (s + 0.78, 1.0, "olive"), (s + 0.98, 1.0, "olive")]
        L = 1.15
        for i in range(1, 15):
            x = L * i / 14
            r = math.sqrt(max(1 - (x / L) ** 2, 0.0))
            p.append((s + 0.98 + x, max(r, 0.0), "olive"))
    else:
        raise KeyError(kind)
    if p[-1][1] > 1e-6:
        p.append((p[-1][0], 0.0, p[-1][2]))
    return p


def scene(kind: str, special: bool):
    sc = solid.Scene()
    prof = profile(kind, "gold" if special else CASE_STD)
    sc.add(solid.revolve(prof, n=36, name=kind, theta0=0.0))
    return sc


def _common_fit():
    """One transform for the whole family: shared scale and base line, every round centred."""
    sils = {k: scene(k, False).silhouette() for k in TYPES}
    allb = [s.bounds for s in sils.values()]
    w = max(b[2] - b[0] for b in allb)
    y_min = min(b[1] for b in allb)
    y_max = max(b[3] for b in allb)
    # special rounds add 3.1 px of rim around the keyline, so the art box is 9.1..54.9 for everyone
    box_h = 54.9 - 9.1
    s = min(box_h / (y_max - y_min), 40.0 / w)
    return s, y_max


_FIT = None


def _fitter(kind):
    global _FIT
    if _FIT is None:
        _FIT = _common_fit()
    s, y_max = _FIT
    sil = scene(kind, False).silhouette()
    bx0, by0, bx1, by1 = sil.bounds
    cx = (bx0 + bx1) / 2
    ox = 32 - cx * s
    oy = 54.9 - y_max * s  # shared base line
    mtx = [s, 0, 0, s, ox, oy]
    f = lambda g: affinity.affine_transform(g, mtx)  # noqa: E731
    f.scale = s
    return f


def draw_shell(d, kind: str, special: bool = False):
    sc = scene(kind, special)
    f = _fitter(kind)
    sil = f(sc.silhouette())
    kit.check(sil, f"ammo {kind}", lo=9.0, hi=55.0)
    if special:
        kit.rim_keyline(d, sil, "gold")
    sc.render(d, f, keyline=kit.KEY)


def _register():
    note("ammo", "Shell icons for the ammo bar, loadout screen, damage log and shop. Upload @128 for "
                 "slots up to 64 px. Same scale and base line across the family. `_special` = premium "
                 "round (gold case + gold rim); its silhouette matches the standard round of that type.")
    uses = {
        "ap": "Standard AP round: ammo bar slot, loadout, shop; AP damage-log tag",
        "apcr": "Standard APCR round (fast sub-calibre)",
        "he": "Standard HE round",
        "heat": "Standard HEAT round",
        "hesh": "Standard HESH round (no special variant)",
    }
    for k in TYPES:
        add("ammo", k, f"Ammo: {NAMES[k]}", uses[k], lambda d, k=k: draw_shell(d, k, False))
    for k in ("ap", "apcr", "he", "heat"):
        add("ammo", f"{k}_special", f"Ammo: special {NAMES[k]}",
            f"Special (premium) {k.upper()} round: same slot uses as `{k}`, gold-rim treatment",
            lambda d, k=k: draw_shell(d, k, True))


_register()
