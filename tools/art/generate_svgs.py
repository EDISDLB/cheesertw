#!/usr/bin/env python3
"""Regenerate every HULLDOWN brand/icon SVG under assets/ from code.

    python3 tools/art/generate_svgs.py            # write all SVGs + assets/brand/tokens.json
    python3 tools/art/generate_svgs.py --check    # also validate constraints, non-zero exit on failure

The SVGs are committed; this generator is the editable source. Requires shapely
(pip install shapely) in addition to the render tool's dependencies.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from hdart import brand, icons, tokens  # noqa: E402
from hdart import registry  # noqa: E402
from hdart.svgdoc import Doc  # noqa: E402

# Group modules register their icons on import (order = INDEX.md order).
GROUP_MODULES = ["ammo", "modules", "crew", "consumables", "equipment", "ui", "battle", "achievements",
                 "missions", "markers"]

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(ROOT, "assets")

FACTION_IDS = list(tokens.FACTIONS.keys())
CLASS_IDS = ["light", "medium", "heavy", "td", "artillery"]
CLASS_NAMES = {"light": "Light", "medium": "Medium", "heavy": "Heavy", "td": "Tank Destroyer", "artillery": "Artillery"}
CURRENCY_IDS = ["credits", "bullion", "vehicle_xp", "free_xp", "crew_xp", "campaign_token"]
MAX_BYTES = 40 * 1024


def out(*parts):
    return os.path.join(ASSETS, *parts)


def build() -> list[tuple[str, int]]:
    written = []

    def rec(path, n):
        written.append((path, n))

    # brand ------------------------------------------------------------------
    rec(out("brand", "logo_primary.svg"), brand.logo_primary(out("brand", "logo_primary.svg")))
    rec(out("brand", "logo_primary_light.svg"), brand.logo_primary(out("brand", "logo_primary_light.svg"), on_light=True))
    rec(out("brand", "logo_stacked.svg"), brand.logo_stacked(out("brand", "logo_stacked.svg")))
    rec(out("brand", "logo_stacked_light.svg"), brand.logo_stacked(out("brand", "logo_stacked_light.svg"), on_light=True))
    rec(out("brand", "emblem.svg"), brand.emblem(out("brand", "emblem.svg")))
    rec(out("brand", "emblem_flat.svg"), brand.emblem(out("brand", "emblem_flat.svg"), flat=True))
    rec(out("brand", "loading_logo.svg"), brand.loading_logo(out("brand", "loading_logo.svg")))
    rec(out("brand", "garage_logo.svg"), brand.garage_logo(out("brand", "garage_logo.svg")))
    rec(out("brand", "battle_logo.svg"), brand.battle_logo(out("brand", "battle_logo.svg")))

    # factions ---------------------------------------------------------------
    for fid in FACTION_IDS:
        d = Doc(64, 64, f"Faction emblem: {tokens.FACTIONS[fid]['name']}")
        icons.FACTION_DRAW[fid](d)
        p = out("icons", "factions", f"{fid}.svg")
        rec(p, d.save(p))

    # classes + minimap --------------------------------------------------------
    for cid in CLASS_IDS:
        d = Doc(64, 64, f"Vehicle class: {CLASS_NAMES[cid]}")
        icons.draw_class(d, cid)
        p = out("icons", "classes", f"{cid}.svg")
        rec(p, d.save(p))
        d = Doc(24, 24, f"Minimap marker: {CLASS_NAMES[cid]} (white, tint with ImageColor3)")
        icons.draw_minimap(d, cid)
        p = out("icons", "minimap", f"class_{cid}.svg")
        rec(p, d.save(p))

    # tiers ------------------------------------------------------------------
    for n in range(1, 12):
        d = Doc(64, 64, f"Tier {icons.ROMAN[n - 1]}")
        icons.draw_tier(d, n)
        p = out("icons", "tiers", f"tier_{n:02d}.svg")
        rec(p, d.save(p))

    # ranks ------------------------------------------------------------------
    for i, (rid, title, _abbr) in enumerate(icons.RANKS, start=1):
        d = Doc(64, 64, f"Rank {i}: {title}")
        icons.draw_rank(d, i)
        p = out("icons", "ranks", f"{rid}.svg")
        rec(p, d.save(p))

    # currencies ---------------------------------------------------------------
    names = {"credits": "Credits", "bullion": "Bullion", "vehicle_xp": "Vehicle XP", "free_xp": "Free XP",
             "crew_xp": "Crew XP", "campaign_token": "Campaign Tokens"}
    for cid in CURRENCY_IDS:
        d = Doc(64, 64, f"Currency: {names[cid]}")
        if cid == "credits":
            icons.currency_credits(d)
        elif cid == "bullion":
            icons.currency_bullion(d)
        elif cid == "campaign_token":
            icons.currency_campaign_token(d)
        else:
            icons.currency_xp(d, cid)
        p = out("icons", "currency", f"{cid}.svg")
        rec(p, d.save(p))

    # registered gameplay / UI groups ----------------------------------------
    for ic in load_registry():
        title = ic.title + (registry.TINT_NOTE if ic.tint else "")
        d = Doc(ic.w, ic.h, title)
        ic.draw(d)
        p = os.path.join(ASSETS, *ic.rel.split("/"))
        rec(p, d.save(p))

    # tokens -------------------------------------------------------------------
    tp = out("brand", "tokens.json")
    with open(tp, "w", encoding="utf-8") as fh:
        json.dump(tokens.as_json(), fh, indent=2)
        fh.write("\n")
    return written


def load_registry():
    import importlib

    for m in GROUP_MODULES:
        try:
            importlib.import_module(f"hdart.{m}")
        except ModuleNotFoundError as e:
            if e.name != f"hdart.{m}":
                raise
    return registry.REGISTRY


FORBIDDEN = re.compile(r"<(text|tspan|image|use|foreignObject|script|style)\b|xlink:href|href=|url\((?!#)", re.I)


def validate(written) -> list[str]:
    problems = []
    for path, n in written:
        rel = os.path.relpath(path, ROOT)
        if n > MAX_BYTES:
            problems.append(f"{rel}: {n} bytes > 40 KB")
        with open(path, encoding="utf-8") as fh:
            s = fh.read()
        if 'viewBox="' not in s:
            problems.append(f"{rel}: no viewBox")
        m = FORBIDDEN.search(s)
        if m:
            problems.append(f"{rel}: forbidden construct {m.group(0)!r}")
    return problems


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="validate size/structure constraints")
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args(argv)
    written = build()
    if not args.quiet:
        for p, n in written:
            print(f"{n:6d}  {os.path.relpath(p, ROOT)}")
        print(f"{len(written)} svg files written")
    problems = validate(written)
    for pr in problems:
        print("PROBLEM:", pr, file=sys.stderr)
    return 1 if (problems and args.check) else 0


if __name__ == "__main__":
    sys.exit(main())
