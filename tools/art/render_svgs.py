#!/usr/bin/env python3
"""Render every HULLDOWN SVG asset to PNG and build labelled review contact sheets.

    python3 tools/art/render_svgs.py                 # all groups
    python3 tools/art/render_svgs.py --only tiers    # one group
    python3 tools/art/render_svgs.py --no-sheets     # PNGs only

Output (git-ignored, under build/):
    build/png/<path relative to assets>@<size>.png     icons: 64/128/256, brand: 64/128/256/512/1024
                                                        (size = longest edge, aspect preserved)
    build/png/contact_sheet_<group>.png                dark + light panels, each asset at review
                                                        size plus true 48/32/24/16 px renders

Requires: cairosvg, Pillow, numpy (no shapely; that is only needed to regenerate the SVGs).
"""

from __future__ import annotations

import argparse
import io
import os
import re
import sys
from dataclasses import dataclass

import cairosvg
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from hdart.tokens import TEAM_CVD, UI, hexrgb  # noqa: E402  (pure data module, no shapely needed)
ICON_SIZES = (64, 128, 256)
BRAND_SIZES = (64, 128, 256, 512, 1024)
LEGIBILITY_SIZES = (48, 32, 24, 16)

DARK_BG = (15, 20, 24)  # bg.base
LIGHT_BG = (233, 238, 242)  # text.primary used as a light page
DARK_FG = (168, 181, 192)
LIGHT_FG = (60, 70, 80)
SHEET_TITLE_DARK = (233, 223, 198)

# Minimap glyphs are authored white + black keyline and tinted in-engine with ImageColor3.
# Preview tints: default ally/enemy/platoon, then the deuteranopia scheme's ally/enemy/platoon.
TINTS = {f"{scheme}:{role}": hexrgb(TEAM_CVD[scheme][role]) for scheme in ("default", "deuteranopia")
         for role in ("ally", "enemy", "platoon")}
# White UI / HUD glyphs (title says "tint") preview with typical UI tints instead of team colours.
UI_TINTS = {t: hexrgb(UI[t]) for t in ("text.secondary", "accent.dusk", "state.success", "state.warning",
                                        "state.danger", "state.info")}
TEAM_TINT_GROUPS = {"minimap", "battle", "markers"}
PAGE = 18  # assets per paged review sheet (6 columns x 3 rows)


@dataclass
class Asset:
    path: str  # absolute path of the svg
    rel: str  # path relative to assets/, without extension
    group: str
    width: float
    height: float
    tint: bool = False  # white art meant for ImageColor3 (the <title> says so)


def find_font(size: int):
    for cand in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        if os.path.exists(cand):
            return ImageFont.truetype(cand, size)
    return ImageFont.load_default()


def svg_size(path: str) -> tuple[float, float, bool]:
    with open(path, encoding="utf-8") as fh:
        head = fh.read(800)
    m = re.search(r'viewBox="([-\d.]+)\s+([-\d.]+)\s+([\d.]+)\s+([\d.]+)"', head)
    if not m:
        raise ValueError(f"{path}: missing viewBox")
    t = re.search(r"<title>(.*?)</title>", head)
    tint = bool(t and "tint" in t.group(1).lower())
    return float(m.group(3)), float(m.group(4)), tint


def group_of(rel: str) -> str:
    parts = rel.split("/")
    if parts[0] == "icons" and len(parts) > 2:
        return parts[1]
    return parts[0]


def collect(assets_dir: str) -> list[Asset]:
    out = []
    for dirpath, _dirs, files in os.walk(assets_dir):
        for fn in sorted(files):
            if not fn.endswith(".svg"):
                continue
            p = os.path.join(dirpath, fn)
            rel = os.path.relpath(p, assets_dir)[:-4].replace(os.sep, "/")
            w, h, tint = svg_size(p)
            out.append(Asset(p, rel, group_of(rel), w, h, tint))
    out.sort(key=lambda a: a.rel)
    return out


def render(asset: Asset, longest: int) -> Image.Image:
    if asset.width >= asset.height:
        w = longest
        h = max(1, round(longest * asset.height / asset.width))
    else:
        h = longest
        w = max(1, round(longest * asset.width / asset.height))
    png = cairosvg.svg2png(url=asset.path, output_width=w, output_height=h)
    return Image.open(io.BytesIO(png)).convert("RGBA")


def tint(img: Image.Image, rgb) -> Image.Image:
    a = np.asarray(img).astype(np.float32)
    a[..., :3] *= np.array(rgb, dtype=np.float32) / 255.0
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


def write_pngs(assets: list[Asset], out_dir: str) -> int:
    n = 0
    for a in assets:
        sizes = BRAND_SIZES if a.group == "brand" else ICON_SIZES
        for s in sizes:
            dst = os.path.join(out_dir, f"{a.rel}@{s}.png")
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            render(a, s).save(dst)
            n += 1
    return n


# ---------------------------------------------------------------------------
# Contact sheets
# ---------------------------------------------------------------------------
def _tints_for(a: Asset):
    if not a.tint:
        return None
    return TINTS if a.group in TEAM_TINT_GROUPS else UI_TINTS


def _panel_icons(assets: list[Asset], bg, fg, title: str, minimap: bool = False) -> Image.Image:
    """One panel: each asset at review size (128 px longest edge, 192 for wide assets), then true
    48/32/24/16 px renders (wide assets: 128/96/64 px wide), then tinted 24 px renders for white
    tintable art."""
    font = find_font(13)
    tfont = find_font(18)
    any_tint = any(a.tint for a in assets) or minimap
    wide = any(a.width > a.height * 1.6 for a in assets)
    big = 192 if wide else 128
    sizes = (128, 96, 64) if wide else LEGIBILITY_SIZES
    small_w = sum(sizes) + 6 * (len(sizes) - 1)
    small_h = max(round(s * min(1.0, a.height / a.width)) for s in sizes for a in assets)
    big_h = max(round(big * min(1.0, a.height / a.width)) for a in assets)
    cell_w = max(big, small_w) + 24
    cell_h = big_h + 12 + small_h + 12 + 18
    if any_tint:
        cell_h += 24 + 8
        cell_w = max(cell_w, 6 * 27 + 8 + 24)
    cols = min(len(assets), 6 if not wide else 3)
    rows = (len(assets) + cols - 1) // cols
    W = cols * cell_w + 24
    H = rows * cell_h + 50
    img = Image.new("RGBA", (W, H), bg + (255,))
    dr = ImageDraw.Draw(img)
    dr.text((14, 12), title, fill=fg, font=tfont)
    for i, a in enumerate(assets):
        cx = 12 + (i % cols) * cell_w + 12
        cy = 44 + (i // cols) * cell_h
        im = render(a, big)
        img.alpha_composite(im, (cx + (cell_w - 24 - im.width) // 2, cy + (big_h - im.height) // 2))
        x = cx + (cell_w - 24 - small_w) // 2
        y = cy + big_h + 12
        for s in sizes:
            sm = render(a, s)
            img.alpha_composite(sm, (x, y + (small_h - sm.height)))
            x += s + 6
        y += small_h + 6
        tints = TINTS if (minimap and not a.tint) else _tints_for(a)
        if any_tint:
            if tints:
                n = len(tints)
                x = cx + (cell_w - 24 - (n * 27 + 8)) // 2
                for j, rgb in enumerate(tints.values()):
                    sm = tint(render(a, 24 if not wide else 48), rgb)
                    if wide:
                        sm = sm.resize((sm.width // 2, sm.height // 2), Image.LANCZOS)
                    img.alpha_composite(sm, (x, y))
                    x += 27 + (8 if j == 2 else 0)
            y += 24 + 8
        label = a.rel.split("/")[-1]
        tw = dr.textlength(label, font=font)
        dr.text((cx + (cell_w - 24 - tw) / 2, y), label, fill=fg, font=font)
    return img


def _panel_brand(assets: list[Asset], bg, fg, title: str) -> Image.Image:
    font = find_font(13)
    tfont = find_font(18)
    rows = []
    for a in assets:
        big = 512 if a.width > a.height * 1.5 else 256
        im = render(a, big)
        sm = render(a, 160 if a.width > a.height * 1.5 else 48)
        rows.append((a, im, sm))
    W = max(r[1].width + r[2].width for r in rows) + 80
    H = sum(max(r[1].height, r[2].height) + 40 for r in rows) + 50
    img = Image.new("RGBA", (W, H), bg + (255,))
    dr = ImageDraw.Draw(img)
    dr.text((14, 12), title, fill=fg, font=tfont)
    y = 44
    for a, im, sm in rows:
        img.alpha_composite(im, (20, y))
        img.alpha_composite(sm, (20 + im.width + 40, y + (im.height - sm.height) // 2))
        dr.text((20, y + max(im.height, sm.height) + 6), a.rel.split("/")[-1], fill=fg, font=font)
        y += max(im.height, sm.height) + 40
    return img


def contact_sheet(group: str, assets: list[Asset], out_dir: str, suffix: str = "", page_note: str = "") -> str:
    minimap = group == "minimap"
    panels = []
    for bg, fg, tag in ((DARK_BG, DARK_FG, "dark"), (LIGHT_BG, LIGHT_FG, "light")):
        title = f"HULLDOWN / {group}{page_note} / on {tag}: review size, true px"
        if any(a.tint for a in assets) or minimap:
            title += ", tinted 24 px"
        if group == "brand":
            panels.append(_panel_brand(assets, bg, fg, title))
        else:
            panels.append(_panel_icons(assets, bg, fg, title, minimap))
    W = max(p.width for p in panels)
    H = sum(p.height for p in panels)
    sheet = Image.new("RGBA", (W, H), DARK_BG + (255,))
    y = 0
    for p in panels:
        bgc = p.getpixel((0, 0))
        band = Image.new("RGBA", (W, p.height), bgc)
        sheet.alpha_composite(band, (0, y))
        sheet.alpha_composite(p, (0, y))
        y += p.height
    dst = os.path.join(out_dir, f"contact_sheet_{group}{suffix}.png")
    sheet.convert("RGB").save(dst)
    return dst


def sheets_for(group: str, assets: list[Asset], out_dir: str, page: int = PAGE) -> list[str]:
    """Full sheet for the group, plus paged sheets (contact_sheet_<group>_pN.png) for big groups so
    every page can be reviewed at 1:1 on one screen."""
    out = [contact_sheet(group, assets, out_dir)]
    if group != "brand" and len(assets) > page:
        n = (len(assets) + page - 1) // page
        for i in range(n):
            chunk = assets[i * page:(i + 1) * page]
            out.append(contact_sheet(group, chunk, out_dir, suffix=f"_p{i + 1}", page_note=f" (page {i + 1}/{n})"))
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--assets", default=os.path.join(ROOT, "assets"))
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "png"))
    ap.add_argument("--only", help="render a single group (brand, factions, classes, minimap, tiers, ranks, currency, ammo, "
                         "modules, crew, consumables, equipment, ui, battle, achievements, missions, markers)")
    ap.add_argument("--no-sheets", action="store_true")
    ap.add_argument("--sheets-only", action="store_true")
    ap.add_argument("--page", type=int, default=PAGE, help="assets per paged review sheet (default %(default)s)")
    args = ap.parse_args(argv)

    assets = collect(args.assets)
    if args.only:
        assets = [a for a in assets if a.group == args.only]
    if not assets:
        print("no svg assets found", file=sys.stderr)
        return 1
    os.makedirs(args.out, exist_ok=True)
    if not args.sheets_only:
        n = write_pngs(assets, args.out)
        print(f"rendered {n} png files from {len(assets)} svg assets -> {os.path.relpath(args.out, ROOT)}")
    if not args.no_sheets:
        groups: dict[str, list[Asset]] = {}
        for a in assets:
            groups.setdefault(a.group, []).append(a)
        for g, lst in groups.items():
            for pth in sheets_for(g, lst, args.out, args.page):
                print("sheet:", os.path.relpath(pth, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
