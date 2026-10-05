#!/usr/bin/env python3
"""Pack one-shot SFX into upload banks (fewer Roblox audio assets).

Roblox limits audio uploads per account per month (see docs/research/08: as low as 100 per 30
days for unverified uploaders), while HULLDOWN ships ~250 one-shot files. The AudioEngine can
play a slice of an asset (``AudioPlayer.PlaybackRegion``), so one-shots are concatenated into
banks of at most ``BANK_MAX_S`` seconds, grouped by category and channel count, with silent
gaps that keep Vorbis block overlap from bleeding between neighbours.

Loops stay as individual assets (seamless looping must not depend on region accuracy).

Inputs are the lossless masters written by ``generate_sfx.py`` (``build/audio_masters``), so
banks are a single lossy generation, identical in level to the standalone files.
Outputs: ``assets/audio/banks/<category>_<m|s><n>.ogg`` plus ``bankRegions`` per catalogue entry
and a top-level ``banks`` table in ``assets/audio/catalog.json``.
"""

from __future__ import annotations

import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from synth import io, mix  # noqa: E402
from synth.core import SR, n_of  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(REPO, "assets", "audio")
MASTERS = os.path.join(REPO, "build", "audio_masters")
BANK_DIR = "banks"
BANK_MAX_S = 120.0
LEAD_S = 0.05
GAP_S = 0.25


def main(argv=None) -> int:
    from generate_sfx import encode_checked  # shared encoder with peak/true-peak guard

    cat_path = os.path.join(AUDIO, "catalog.json")
    with open(cat_path, encoding="utf-8") as fh:
        doc = json.load(fh)
    sounds = doc["sounds"]

    groups: dict[tuple[str, int], list[tuple[str, int, str]]] = {}
    for key in sorted(sounds):
        e = sounds[key]
        e.pop("bankRegions", None)
        if e["loop"]:
            continue
        files = e["variants"] or [e["file"]]
        for i, rel in enumerate(files):
            groups.setdefault((e["category"], e["channels"]), []).append((key, i, rel))

    banks = {}
    regions: dict[str, list] = {}
    written = set()
    for (category, ch), items in sorted(groups.items()):
        chunk: list[tuple[str, int, str, np.ndarray]] = []
        total = LEAD_S
        index = 1

        def flush(chunk, index):
            name = f"{category}_{'m' if ch == 1 else 's'}{index}"
            rel = f"{BANK_DIR}/{name}.ogg"
            length = n_of(LEAD_S) + sum(x.shape[0] + n_of(GAP_S) for *_, x in chunk)
            buf = np.zeros(length) if ch == 1 else np.zeros((length, ch))
            pos = n_of(LEAD_S)
            for key, i, _frel, x in chunk:
                buf[pos : pos + x.shape[0]] = x
                regions.setdefault(key, []).append((i, {"bank": rel, "startS": round(pos / SR, 6), "endS": round((pos + x.shape[0]) / SR, 6)}))
                pos += x.shape[0] + n_of(GAP_S)
            dec, trim = encode_checked(os.path.join(AUDIO, rel), buf, f"bank:{name}", 0.65)
            if trim < -1.0:
                raise RuntimeError(f"bank {name} needed a gain trim of {trim:.2f} dB; masters exceed ceiling")
            buses = sorted({sounds[k]["bus"] for k, *_ in chunk})
            banks[name] = {"file": rel, "channels": ch, "durationS": round(dec.shape[0] / SR, 3), "buses": buses,
                           "sounds": len(chunk), "peakDb": round(mix.peak_db(dec), 2), "trimDb": round(trim, 2)}
            written.add(rel)

        for key, i, rel in items:
            mpath = os.path.join(MASTERS, rel.replace(".ogg", ".flac"))
            if not os.path.exists(mpath):
                print(f"pack_banks: missing master {mpath}; run generate_sfx.py first", file=sys.stderr)
                return 1
            x, sr = io.read(mpath)
            dur = x.shape[0] / SR + GAP_S
            if chunk and total + dur > BANK_MAX_S:
                flush(chunk, index)
                index += 1
                chunk, total = [], LEAD_S
            chunk.append((key, i, rel, x))
            total += dur
        if chunk:
            flush(chunk, index)

    for key, regs in regions.items():
        sounds[key]["bankRegions"] = [r for _, r in sorted(regs, key=lambda t: t[0])]
    doc["banks"] = dict(sorted(banks.items()))
    doc.setdefault("notes", {})["banks"] = (
        "One-shots are also packed into 'banks' (upload-quota friendly). bankRegions[i] matches variants[i] "
        "(or 'file'); play with AudioPlayer.PlaybackRegion = NumberRange.new(startS, endS). Loops are never banked."
    )
    with open(cat_path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")
    bank_root = os.path.join(AUDIO, BANK_DIR)
    for f in os.listdir(bank_root):
        if f.endswith(".ogg") and f"{BANK_DIR}/{f}" not in written:
            os.remove(os.path.join(bank_root, f))
    loops = sum(1 for e in sounds.values() if e["loop"])
    print(f"pack_banks: {len(banks)} banks ({sum(b['sounds'] for b in banks.values())} one-shot files), "
          f"{loops} loop assets -> {len(banks) + loops} uploads instead of {sum(len(e['variants']) or 1 for e in sounds.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
