#!/usr/bin/env python3
"""Regenerate every HULLDOWN brand/icon SVG under assets/ from code.

    python3 tools/art/generate_svgs.py            # write all SVGs, assets/brand/tokens.json and
                                                  # assets/icons/INDEX.md
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
    write_index(out("icons", "INDEX.md"))
    return written


def load_registry():
    import importlib

    for m in GROUP_MODULES:
        importlib.import_module(f"hdart.{m}")
    return registry.REGISTRY


# ---------------------------------------------------------------------------
# assets/icons/INDEX.md
# ---------------------------------------------------------------------------
LEGACY_NOTES = {
    "factions": "Faction emblems: tech-tree headers, faction filter chips, garage faction wash, loading cards.",
    "classes": "Vehicle class symbols (bone; tint premium gold / elite dusk with ImageColor3 multiply).",
    "minimap": "Minimap class pips, 24 x 24, white: tint with the team colour of the active CVD scheme.",
    "tiers": "Tier badges I-XI: vehicle cards, tech tree, matchmaking spread.",
    "ranks": "Account rank insignia (shoulder tabs): profile, results, chat tags.",
    "currency": "Currency icons: always paired with an amount (brand-art.md 3.6).",
}


def legacy_entries():
    out = []
    for fid in FACTION_IDS:
        out.append(("factions", fid, f"icons/factions/{fid}.svg", "64", False,
                    f"Faction emblem: {tokens.FACTIONS[fid]['name'].title()}"))
    for cid in CLASS_IDS:
        out.append(("classes", cid, f"icons/classes/{cid}.svg", "64", False, f"Vehicle class symbol: {CLASS_NAMES[cid]}"))
    for cid in CLASS_IDS:
        out.append(("minimap", f"class_{cid}", f"icons/minimap/class_{cid}.svg", "24", True,
                    f"Minimap pip: {CLASS_NAMES[cid]} (destroyed: 60 % opacity in team.destroyed + ink X)"))
    for n in range(1, 12):
        out.append(("tiers", f"tier_{n:02d}", f"icons/tiers/tier_{n:02d}.svg", "64", False, f"Tier {icons.ROMAN[n - 1]} badge"))
    for i, (rid, title, abbr) in enumerate(icons.RANKS, start=1):
        out.append(("ranks", rid, f"icons/ranks/{rid}.svg", "64", False, f"Rank {i}: {title} ({abbr})"))
    cur = {"credits": "Credits (earned currency)", "bullion": "Bullion (premium currency)", "vehicle_xp": "Vehicle XP",
           "free_xp": "Free XP", "crew_xp": "Crew XP", "campaign_token": "Campaign Tokens (event currency)"}
    for cid in CURRENCY_IDS:
        out.append(("currency", cid, f"icons/currency/{cid}.svg", "64", False, cur[cid]))
    return out


def write_index(path):
    reg = registry.REGISTRY
    rows = legacy_entries()
    for ic in reg:
        size = f"{ic.w:g}" if ic.w == ic.h else f"{ic.w:g} x {ic.h:g}"
        rows.append((ic.group, ic.key, ic.rel, size, ic.tint, ic.use))
    groups = []
    for r in rows:
        if r[0] not in groups:
            groups.append(r[0])
    lines = [
        "# HULLDOWN icon index",
        "",
        "> Generated by `tools/art/generate_svgs.py` from the icon registry. Do not edit by hand: change the",
        "> generator (`tools/art/hdart/`) and re-run it. Art direction: [`docs/design/brand-art.md`](../../docs/design/brand-art.md).",
        "",
        "Conventions:",
        "",
        "* **Key** = file stem = the content key client code uses (`assets/icons/<group>/<key>.svg`).",
        "* **Size** = SVG canvas in px (the grid it was drawn on). Upload the PNG renders "
        "(`tools/art/render_svgs.py`): `@64` for 16-24 px display, `@128` up to 64 px, `@256` above.",
        "* **Tint** = white art with an ink keyline, meant for `ImageLabel.ImageColor3` "
        "(team colour from the active CVD scheme, or the UI token named in the use column). "
        "Never upload pre-tinted copies.",
        "* Overlays and composites: equipment `grade_*` frames and achievement `frame_*` + `emblem_*` are layered "
        "at the same size by the client; `examples/` files are previews only.",
        "",
        f"{len(rows)} icons in {len(groups)} groups.",
        "",
        "| Group | Count |",
        "|---|---|",
    ]
    for g in groups:
        lines.append(f"| [{g}](#{g}) | {sum(1 for r in rows if r[0] == g)} |")
    for g in groups:
        lines += ["", f"## {g}", ""]
        nt = registry.GROUP_NOTES.get(g) or LEGACY_NOTES.get(g)
        if nt:
            lines += [nt, ""]
        lines += ["| Key | File | Size | Tint | Intended use |", "|---|---|---|---|---|"]
        for grp, key, rel, size, tint, use in rows:
            if grp != g:
                continue
            rel_link = rel[len("icons/"):]
            lines.append(f"| `{key}` | [`{rel_link}`]({rel_link}) | {size} | {'yes' if tint else ''} | {use} |")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return rows


FORBIDDEN = re.compile(r"<(text|tspan|image|use|foreignObject|script|style)\b|xlink:href|href=|url\((?!#)", re.I)


def validate(written) -> list[str]:
    problems = []
    # every SVG under assets/icons must be listed in INDEX.md (and nothing stale may linger)
    with open(os.path.join(ASSETS, "icons", "INDEX.md"), encoding="utf-8") as fh:
        index = fh.read()
    on_disk = []
    for dirpath, _dirs, files in os.walk(os.path.join(ASSETS, "icons")):
        for fn in files:
            if fn.endswith(".svg"):
                on_disk.append(os.path.relpath(os.path.join(dirpath, fn), os.path.join(ASSETS, "icons")).replace(os.sep, "/"))
    written_set = {os.path.abspath(p) for p, _ in written}
    for rel in sorted(on_disk):
        if f"]({rel})" not in index:
            problems.append(f"assets/icons/{rel}: not listed in INDEX.md")
        if os.path.abspath(os.path.join(ASSETS, "icons", rel)) not in written_set:
            problems.append(f"assets/icons/{rel}: stale file (not produced by the generator)")
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
