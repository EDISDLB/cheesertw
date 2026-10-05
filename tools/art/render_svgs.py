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
from hdart.tokens import TEAM_CVD, hexrgb  # noqa: E402  (pure data module, no shapely needed)
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


@dataclass
class Asset:
    path: str  # absolute path of the svg
    rel: str  # path relative to assets/, without extension
    group: str
    width: float
    height: float


def find_font(size: int):
    for cand in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        if os.path.exists(cand):
            return ImageFont.truetype(cand, size)
    return ImageFont.load_default()


def svg_size(path: str) -> tuple[float, float]:
    with open(path, encoding="utf-8") as fh:
        head = fh.read(600)
    m = re.search(r'viewBox="([-\d.]+)\s+([-\d.]+)\s+([\d.]+)\s+([\d.]+)"', head)
    if not m:
        raise ValueError(f"{path}: missing viewBox")
    return float(m.group(3)), float(m.group(4))


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
            w, h = svg_size(p)
            out.append(Asset(p, rel, group_of(rel), w, h))
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
def _panel_icons(assets: list[Asset], bg, fg, title: str, minimap: bool) -> Image.Image:
    big = 128
    font = find_font(13)
    tfont = find_font(18)
    small_w = sum(LEGIBILITY_SIZES) + 6 * (len(LEGIBILITY_SIZES) - 1)
    cell_w = max(big, small_w) + 24
    cell_h = big + 12 + max(LEGIBILITY_SIZES) + 12 + 18
    if minimap:
        cell_h += 24 + 8
    if minimap:
        cell_w = max(cell_w, 6 * 27 + 8 + 24)
    cols = min(len(assets), 6 if not minimap else 5)
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
        img.alpha_composite(im, (cx + (cell_w - 24 - im.width) // 2, cy + (big - im.height) // 2))
        x = cx + (cell_w - 24 - small_w) // 2
        y = cy + big + 12
        for s in LEGIBILITY_SIZES:
            sm = render(a, s)
            img.alpha_composite(sm, (x, y + (max(LEGIBILITY_SIZES) - sm.height)))
            x += s + 6
        y += max(LEGIBILITY_SIZES) + 6
        if minimap:
            x = cx + (cell_w - 24 - (len(TINTS) * 27 + 8)) // 2
            for i, rgb in enumerate(TINTS.values()):
                sm = tint(render(a, 24), rgb)
                img.alpha_composite(sm, (x, y))
                x += 27 + (8 if i == 2 else 0)
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


def contact_sheet(group: str, assets: list[Asset], out_dir: str) -> str:
    minimap = group == "minimap"
    panels = []
    for bg, fg, tag in ((DARK_BG, DARK_FG, "dark"), (LIGHT_BG, LIGHT_FG, "light")):
        title = f"HULLDOWN / {group} / on {tag}: review size, true 48/32/24/16 px"
        title += ", tinted 24 px (default / deutan)" if minimap else ""
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
    dst = os.path.join(out_dir, f"contact_sheet_{group}.png")
    sheet.convert("RGB").save(dst)
    return dst


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--assets", default=os.path.join(ROOT, "assets"))
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "png"))
    ap.add_argument("--only", help="render a single group (brand, factions, classes, minimap, tiers, ranks, currency)")
    ap.add_argument("--no-sheets", action="store_true")
    ap.add_argument("--sheets-only", action="store_true")
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
            print("sheet:", os.path.relpath(contact_sheet(g, lst, args.out), ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
