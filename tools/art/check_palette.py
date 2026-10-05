#!/usr/bin/env python3
"""Validate HULLDOWN colour tokens: WCAG contrast of text/state colours on UI surfaces and
colour-vision-deficiency (CVD) separation of the team-colour schemes. Also renders
build/png/contact_sheet_palette.png (token swatches + each team scheme under simulated CVD).

    python3 tools/art/check_palette.py          # report + sheet; exit 1 if a rule fails

CVD simulation: Machado, Oliveira & Fernandes (2009) matrices at severity 1.0, applied in linear
sRGB. Separation metric: CIEDE2000 in CIELAB (D65).
"""

from __future__ import annotations

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from hdart.tokens import TEAM_CVD, UI, hexrgb  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))

MACHADO = {
    "normal": np.eye(3),
    "protanopia": np.array([[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]]),
    "deuteranopia": np.array([[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]]),
    "tritanopia": np.array([[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]]),
}

MIN_TEXT_CONTRAST = 4.5  # WCAG AA body text
MIN_MARKER_CONTRAST = 3.0  # non-text UI (markers, icons) vs the HUD/map background
MIN_TEAM_DE = 20.0  # CIEDE2000 between any two team roles for the intended viewer


def lin(c):
    c = np.asarray(c, dtype=float) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def delin(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255.0


def simulate(rgb, kind):
    return tuple(int(round(v)) for v in delin(MACHADO[kind] @ lin(rgb)))


def luminance(rgb):
    r, g, b = lin(rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def to_lab(rgb):
    r, g, b = lin(rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116

    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def de2000(c1, c2):
    L1, a1, b1 = to_lab(c1)
    L2, a2, b2 = to_lab(c2)
    C1, C2 = math.hypot(a1, b1), math.hypot(a2, b2)
    Cb = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cb ** 7 / (Cb ** 7 + 25 ** 7)))
    a1p, a2p = (1 + G) * a1, (1 + G) * a2
    C1p, C2p = math.hypot(a1p, b1), math.hypot(a2p, b2)
    h1p = math.degrees(math.atan2(b1, a1p)) % 360
    h2p = math.degrees(math.atan2(b2, a2p)) % 360
    dLp = L2 - L1
    dCp = C2p - C1p
    dhp = 0.0
    if C1p * C2p != 0:
        dhp = h2p - h1p
        if dhp > 180:
            dhp -= 360
        elif dhp < -180:
            dhp += 360
    dHp = 2 * math.sqrt(C1p * C2p) * math.sin(math.radians(dhp / 2))
    Lbp = (L1 + L2) / 2
    Cbp = (C1p + C2p) / 2
    if C1p * C2p == 0:
        hbp = h1p + h2p
    elif abs(h1p - h2p) <= 180:
        hbp = (h1p + h2p) / 2
    else:
        hbp = (h1p + h2p + 360) / 2 if h1p + h2p < 360 else (h1p + h2p - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hbp - 30)) + 0.24 * math.cos(math.radians(2 * hbp))
         + 0.32 * math.cos(math.radians(3 * hbp + 6)) - 0.20 * math.cos(math.radians(4 * hbp - 63)))
    dtheta = 30 * math.exp(-(((hbp - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(Cbp ** 7 / (Cbp ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lbp - 50) ** 2 / math.sqrt(20 + (Lbp - 50) ** 2)
    Sc = 1 + 0.045 * Cbp
    Sh = 1 + 0.015 * Cbp * T
    Rt = -math.sin(math.radians(2 * dtheta)) * Rc
    return math.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))


def rgb_of(token_hex):
    return hexrgb(token_hex[:7])


def run_checks():
    failures = []
    lines = []
    panel = rgb_of(UI["bg.panel"])
    base = rgb_of(UI["bg.base"])
    raised = rgb_of(UI["bg.raised"])
    lines.append("== Text contrast (WCAG) on bg.panel / bg.raised ==")
    for tok, need in (("text.primary", 4.5), ("text.secondary", 4.5), ("text.tertiary", 3.0), ("text.brand", 4.5),
                      ("accent.dusk", 3.0), ("state.success", 3.0), ("state.warning", 3.0), ("state.danger", 3.0),
                      ("state.info", 3.0)):
        c = rgb_of(UI[tok])
        r1, r2 = contrast(c, panel), contrast(c, raised)
        ok = min(r1, r2) >= need
        lines.append(f"  {tok:16s} {UI[tok]}  panel {r1:5.2f}  raised {r2:5.2f}  need {need}  {'ok' if ok else 'FAIL'}")
        if not ok:
            failures.append(f"{tok} contrast {min(r1, r2):.2f} < {need}")
    inv = contrast(rgb_of(UI["text.inverse"]), rgb_of(UI["accent.dusk"]))
    lines.append(f"  text.inverse on accent.dusk (CTA label) {inv:5.2f}  need 4.5  {'ok' if inv >= 4.5 else 'FAIL'}")
    if inv < 4.5:
        failures.append("CTA label contrast")

    lines.append("")
    lines.append("== Team schemes: min CIEDE2000 between roles (ally/enemy/platoon/self) per viewer ==")
    roles = ("ally", "enemy", "platoon", "self")
    viewers = ("normal", "protanopia", "deuteranopia", "tritanopia")
    intended = {"default": "normal", "deuteranopia": "deuteranopia", "protanopia": "protanopia", "tritanopia": "tritanopia"}
    for scheme, cols in TEAM_CVD.items():
        row = []
        for v in viewers:
            sim = {r: simulate(rgb_of(cols[r]), v) for r in roles}
            worst = min((de2000(sim[a], sim[b]), f"{a}/{b}") for i, a in enumerate(roles) for b in roles[i + 1:])
            row.append((v, worst))
        desc = "  ".join(f"{v[:4]} {w[0]:5.1f} ({w[1]})" for v, w in row)
        lines.append(f"  {scheme:13s} {desc}")
        target = intended[scheme]
        w = dict(row)[target]
        if w[0] < MIN_TEAM_DE:
            failures.append(f"team scheme {scheme}: {w[1]} only dE {w[0]:.1f} for {target}")
        for r in roles:
            cr = contrast(simulate(rgb_of(cols[r]), target), base)
            if cr < MIN_MARKER_CONTRAST:
                failures.append(f"team scheme {scheme}: {r} marker contrast {cr:.2f} on bg.base")
    lines.append(f"  (rule: intended viewer min dE >= {MIN_TEAM_DE}; every role >= {MIN_MARKER_CONTRAST}:1 on bg.base)")
    return lines, failures


def render_sheet(path):
    font = None
    for cand in ("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(cand):
            font = ImageFont.truetype(cand, 12)
            tfont = ImageFont.truetype(cand, 16)
            break
    if font is None:
        font = tfont = ImageFont.load_default()
    groups = {}
    for k, v in UI.items():
        groups.setdefault(k.split(".")[0], []).append((k, v))
    sw, sh = 128, 56
    cols = 8
    rows = sum((len(v) + cols - 1) // cols for v in groups.values())
    team_rows = len(TEAM_CVD)
    W = 24 + cols * (sw + 8) + 8
    H = 40 + rows * (sh + 30) + len(groups) * 24 + 60 + team_rows * 70 + 40
    img = Image.new("RGB", (W, H), rgb_of(UI["bg.base"]))
    dr = ImageDraw.Draw(img)
    dr.text((14, 10), "HULLDOWN / palette tokens (tokens.py) + team schemes under simulated CVD", fill=rgb_of(UI["text.brand"]), font=tfont)
    y = 40
    for g, items in groups.items():
        dr.text((14, y), g, fill=rgb_of(UI["text.secondary"]), font=tfont)
        y += 24
        for i, (k, v) in enumerate(items):
            x = 14 + (i % cols) * (sw + 8)
            if i and i % cols == 0:
                y += sh + 30
            c = rgb_of(v)
            dr.rectangle([x, y, x + sw, y + sh], fill=c, outline=rgb_of(UI["border.strong"]))
            dr.text((x, y + sh + 2), k, fill=rgb_of(UI["text.primary"]), font=font)
            dr.text((x, y + sh + 15), v, fill=rgb_of(UI["text.tertiary"]), font=font)
        y += sh + 34
    dr.text((14, y), "team schemes (rows) as seen by: normal | protanopia | deuteranopia | tritanopia", fill=rgb_of(UI["text.secondary"]), font=tfont)
    y += 26
    for scheme, cols_ in TEAM_CVD.items():
        dr.text((14, y + 20), scheme, fill=rgb_of(UI["text.primary"]), font=font)
        x = 130
        for v in ("normal", "protanopia", "deuteranopia", "tritanopia"):
            for r in ("ally", "enemy", "platoon", "self"):
                c = simulate(rgb_of(cols_[r]), v)
                dr.rectangle([x, y, x + 34, y + 50], fill=c)
                x += 38
            x += 24
        y += 70
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


def main() -> int:
    lines, failures = run_checks()
    print("\n".join(lines))
    sheet = render_sheet(os.path.join(ROOT, "build", "png", "contact_sheet_palette.png"))
    print("\nsheet:", os.path.relpath(sheet, ROOT))
    if failures:
        print("\nFAILURES:")
        for f in failures:
            print("  -", f)
        return 1
    print("\nall palette checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
