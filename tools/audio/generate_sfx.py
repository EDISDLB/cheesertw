#!/usr/bin/env python3
"""Generate the HULLDOWN sound-effect catalogue.

Renders every sound registered in ``tools/audio/designs`` (all procedurally synthesised,
deterministically seeded per key/variant), masters it (DC removal, loop seam handling,
loudness normalisation, peak limiting), encodes OGG Vorbis into
``assets/audio/<category>/<key>[_<variant>].ogg`` and writes ``assets/audio/catalog.json``.

Usage::

    python3 tools/audio/generate_sfx.py                 # everything
    python3 tools/audio/generate_sfx.py --only 'engine_*,ui_*' --jobs 4
    python3 tools/audio/generate_sfx.py --list          # print keys and exit
    python3 tools/audio/generate_sfx.py --wav build/audio_review/wav   # also write 24-bit WAVs
    python3 tools/audio/generate_sfx.py --no-banks      # skip re-packing the upload banks

Rendering is deterministic: the same code produces byte-identical OGG files.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from synth import fx, io, mix  # noqa: E402
from synth.core import SR, make_rng, n_of, to_stereo  # noqa: E402
from synth.env import fade  # noqa: E402
from synth.filters import dc_block  # noqa: E402

import designs  # noqa: E402,F401  (populates the registry)
from designs.registry import BUSES, DISTANCE_BANDS_M, REGISTRY, STUDS_PER_METER, Sound  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
DEFAULT_OUT = os.path.join(REPO, "assets", "audio")
MASTERS = os.path.join(REPO, "build", "audio_masters")
PRE_CEILING_DB = -1.5  # sample-peak ceiling before encoding
MAX_PEAK_DB = -1.0  # hard requirement on the decoded file (sample peak)
MAX_TRUE_PEAK_DB = -0.5  # inter-sample peak guard (device resampling headroom)
MAX_GR_DB = 12.0  # most transient peak reduction (clipper + limiter) allowed on a one-shot
MAX_ONESHOT_S = {"ui": 3.5, "cues": 3.5, "radio": 2.5, "default": 9.5}  # hard caps (tails faded)
SCHEMA = "hulldown.audio.catalog/1"


# --------------------------------------------------------------------------- mastering
def conform_channels(x: np.ndarray, channels: int) -> np.ndarray:
    if channels == 1 and x.ndim == 2:
        return x.mean(axis=1)
    if channels == 2 and x.ndim == 1:
        return to_stereo(x)
    return x


def soft_clip_peaks(x: np.ndarray, knee_db: float, max_db: float) -> np.ndarray:
    """Clipper-before-limiter: samples above ``knee_db`` are bent smoothly so nothing exceeds
    ``max_db``. Only the sharpest transient peaks (muzzle cracks, impact clicks) are touched, which
    keeps the following look-ahead limiter from pumping the body of the sound."""
    k = 10 ** (knee_db / 20.0)
    c = 10 ** (max_db / 20.0)
    a = np.abs(x)
    over = a > k
    if not np.any(over):
        return x
    y = np.array(x, copy=True)
    y[over] = np.sign(x[over]) * (k + (c - k) * np.tanh((a[over] - k) / (c - k)))
    return y


def zero_mean(x: np.ndarray) -> np.ndarray:
    """Remove residual DC from a finite one-shot without creating end discontinuities.

    A high-pass leaves a non-zero mean once a sound is truncated; subtracting a scaled Hann
    window (zero at both ends) cancels the mean exactly with an inaudible sub-sonic bump."""
    n = x.shape[0]
    if n < 8:
        return x
    w = np.hanning(n)
    corr = np.mean(x, axis=0) / np.mean(w)
    return x - (np.outer(w, corr) if x.ndim == 2 else w * corr)


def master(s: Sound, x: np.ndarray) -> tuple[np.ndarray, dict]:
    """Bring a raw render to a deliverable: channels, DC, seam, loudness, ceiling."""
    x = np.asarray(x, dtype=np.float64)
    if not np.all(np.isfinite(x)):
        raise ValueError(f"{s.key}: render produced non-finite samples")
    x = conform_channels(x, s.channels)
    notes: dict = {}
    if s.loop:
        n = n_of(s.loop_s)
        if x.shape[0] > n:  # render included run-out material: crossfade it into the loop start
            notes["crossfadeS"] = round((x.shape[0] - n) / SR, 3)
            x = mix.loop_crossfade(x, n, x.shape[0] - n, "equal_power")
        elif x.shape[0] < n:
            raise ValueError(f"{s.key}: loop render shorter than {s.loop_s}s")
        x = mix.circular(lambda z: dc_block(z, 15.0), x, 2)
        x = x - np.mean(x, axis=0)
        x, off = mix.rotate_to_zero_crossing(x)
        notes["rotation"] = off
        x = mix.normalize_loudness(x, s.level, "integrated")
        pk = mix.peak_db(x)
        if pk > PRE_CEILING_DB:
            notes["peakReductionDb"] = round(pk - PRE_CEILING_DB, 2)
            x = mix.circular(lambda z: fx.limiter(z, PRE_CEILING_DB, 0.002, 0.08), x, 3)
    else:
        x = dc_block(x, 15.0)
        x = mix.trim_tail(x, -60.0, 0.02, 0.03)
        cap = MAX_ONESHOT_S.get(s.category, MAX_ONESHOT_S["default"])
        if x.shape[0] > n_of(cap):
            x = fade(x[: n_of(cap)], 0.0, 0.6)
        if abs(float(np.max(np.abs(x[:1])))) > 1e-5:
            x = fade(x, 0.0006, 0.0)
        # loudness first, then a peak clipper + look-ahead limiter; if peak control cost loudness,
        # make it up - bounded so a transient is never reduced by more than MAX_GR_DB in total
        x = mix.normalize_loudness(x, s.level, "momentary")
        y = x
        for _ in range(5):
            pk = mix.peak_db(x)
            y = soft_clip_peaks(x, PRE_CEILING_DB + 2.0, PRE_CEILING_DB + 6.0)
            if mix.peak_db(y) > PRE_CEILING_DB:
                y = fx.limiter(y, PRE_CEILING_DB, 0.0015, 0.05)
            short = s.level - mix.loudness_momentary_max(y)
            if short < 0.5 or pk - PRE_CEILING_DB >= MAX_GR_DB:
                break
            x = mix.gain_db(x, min(short, MAX_GR_DB - (pk - PRE_CEILING_DB)))
        if mix.peak_db(x) > PRE_CEILING_DB:
            notes["peakReductionDb"] = round(mix.peak_db(x) - PRE_CEILING_DB, 2)
        x = zero_mean(y)
    return x, notes


def encode_checked(path: str, x: np.ndarray, key: str, quality: float) -> tuple[np.ndarray, float]:
    """Encode, decode, and trim gain until the decoded peak satisfies the ceiling."""
    trim = 0.0
    for _ in range(4):
        y = x * 10 ** (trim / 20.0)
        io.write_ogg(path, y, SR, quality=quality, key=key)
        dec, sr = io.read(path)
        if sr != SR:
            raise RuntimeError(f"{path}: decoded sample rate {sr}")
        pk = mix.peak_db(dec)
        tp = mix.true_peak_db(dec)
        if pk <= MAX_PEAK_DB - 0.05 and tp <= MAX_TRUE_PEAK_DB:
            return dec, trim
        trim -= max(pk - (MAX_PEAK_DB - 0.25), tp - (MAX_TRUE_PEAK_DB - 0.2), 0.1)
    raise RuntimeError(f"{path}: could not satisfy peak ceiling")


def render_sound(key: str, out_root: str, wav_dir: str | None) -> dict:
    s = REGISTRY[key]
    variants = s.variants or ("",)
    stats = []
    t0 = time.time()
    for v, rel in zip(variants, s.files):
        rng = make_rng("hulldown-sfx", s.key, v)
        raw = s.render(rng, v)
        x, notes = master(s, raw)
        path = os.path.join(out_root, rel)
        dec, trim = encode_checked(path, x, f"{s.key}_{v}", s.quality)
        # lossless master (post-trim) for the bank packer; build/ is git-ignored
        io.write_flac(os.path.join(MASTERS, rel.replace(".ogg", ".flac")), x * 10 ** (trim / 20.0))
        if wav_dir:
            io.write_wav(os.path.join(wav_dir, rel.replace(".ogg", ".wav")), x)
        st = {
            "file": rel,
            "durationS": round(dec.shape[0] / SR, 4),
            "channels": 1 if dec.ndim == 1 else int(dec.shape[1]),
            "peakDb": round(mix.peak_db(dec), 2),
            "rmsDb": round(mix.rms_db(dec), 2),
            "loudnessLufs": round(mix.loudness_integrated(dec) if s.loop else mix.loudness_momentary_max(dec), 2),
        }
        if s.loop:
            sm = mix.seam_metrics(dec)
            st["seam"] = {"jumpRatio": round(sm["jumpRatio"], 3), "hfBurstDb": round(sm["hfBurstDb"], 2)}
        if notes.get("peakReductionDb"):
            st["peakReductionDb"] = notes["peakReductionDb"]
        if trim:
            st["encodeTrimDb"] = round(trim, 2)
        stats.append(st)
    return {"key": key, "stats": stats, "seconds": round(time.time() - t0, 2)}


# --------------------------------------------------------------------------- catalogue
def catalog_entry(s: Sound, stats: list[dict]) -> dict:
    first = stats[0]
    entry = {
        "file": first["file"],
        "category": s.category,
        "bus": s.bus,
        "loop": s.loop,
        "durationS": first["durationS"],
        "channels": first["channels"],
        "peakDb": max(st["peakDb"] for st in stats),
        "rmsDb": round(float(np.mean([st["rmsDb"] for st in stats])), 2),
        "loudnessLufs": round(float(np.mean([st["loudnessLufs"] for st in stats])), 2),
        "loudnessMode": "integrated" if s.loop else "momentaryMax",
        "suggested": s.suggested(),
        "variants": [st["file"] for st in stats] if s.variants else [],
        "description": s.description,
        "event": s.event,
    }
    if s.group:
        entry["group"] = s.group
    if s.loop:
        entry["loopSeam"] = {
            "jumpRatioMax": max(st["seam"]["jumpRatio"] for st in stats),
            "hfBurstDbMax": max(st["seam"]["hfBurstDb"] for st in stats),
        }
    if s.meta:
        entry["meta"] = s.meta
    if len(stats) > 1:
        entry["variantStats"] = [
            {k: st[k] for k in ("file", "durationS", "peakDb", "rmsDb", "loudnessLufs")} for st in stats
        ]
    return entry


def write_catalog(path: str, entries: dict) -> None:
    doc = {
        "schema": SCHEMA,
        "generator": "tools/audio/generate_sfx.py",
        "root": "assets/audio",
        "format": "ogg/vorbis",
        "sampleRate": SR,
        "studsPerMeter": STUDS_PER_METER,
        "buses": list(BUSES),
        "distanceBandsMeters": {k: list(v) for k, v in DISTANCE_BANDS_M.items()},
        "distanceBandsStuds": {k: [int(a * STUDS_PER_METER), int(b * STUDS_PER_METER)] for k, (a, b) in DISTANCE_BANDS_M.items()},
        "notes": {
            "file": "Paths are relative to 'root'. 'variants' lists interchangeable files to randomise between (empty = single file).",
            "loudness": "loudnessLufs is momentary-max (400 ms) for one-shots and integrated for loops (BS.1770 K-weighting).",
            "suggested": "volume = Sound.Volume; rollOff*Studs = RollOffMinDistance/RollOffMaxDistance (InverseTapered); null for 2D sounds.",
        },
        "sounds": {k: entries[k] for k in sorted(entries)},
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")


# --------------------------------------------------------------------------- CLI
def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma-separated glob patterns of keys to render")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--wav", default=None, help="also write mastered 24-bit WAVs into this directory")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--no-banks", action="store_true", help="skip packing one-shots into upload banks")
    args = ap.parse_args(argv)

    keys = sorted(REGISTRY)
    if args.only:
        pats = [p.strip() for p in args.only.split(",") if p.strip()]
        keys = [k for k in keys if any(fnmatch.fnmatch(k, p) for p in pats)]
    if args.list:
        for k in keys:
            s = REGISTRY[k]
            print(f"{k:48s} {s.category:12s} {s.bus:9s} {'loop' if s.loop else 'shot'} {len(s.files)} file(s)")
        print(f"{len(keys)} keys, {sum(len(REGISTRY[k].files) for k in keys)} files")
        return 0

    os.makedirs(args.out, exist_ok=True)
    cat_path = os.path.join(args.out, "catalog.json")
    entries: dict = {}
    if os.path.exists(cat_path) and args.only:
        with open(cat_path, encoding="utf-8") as fh:
            entries = json.load(fh).get("sounds", {})
    entries = {k: v for k, v in entries.items() if k in REGISTRY}

    t0 = time.time()
    failures = []
    done = 0
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futs = {pool.submit(render_sound, k, args.out, args.wav): k for k in keys}
        for fut in as_completed(futs):
            k = futs[fut]
            try:
                res = fut.result()
            except Exception as exc:  # noqa: BLE001
                failures.append((k, repr(exc)))
                print(f"FAIL {k}: {exc!r}", flush=True)
                continue
            entries[k] = catalog_entry(REGISTRY[k], res["stats"])
            done += 1
            st = res["stats"][0]
            gr = max((s.get("peakReductionDb", 0) for s in res["stats"]), default=0)
            print(f"[{done:3d}/{len(keys)}] {k:46s} {st['durationS']:6.2f}s  peak {st['peakDb']:6.2f}  "
                  f"lufs {st['loudnessLufs']:6.1f}{'  GR %.1f' % gr if gr else ''}  ({res['seconds']}s)", flush=True)

    # drop stale files of keys that no longer exist
    valid = {f for s in REGISTRY.values() for f in s.files}
    for root, _, files in os.walk(args.out):
        for f in files:
            if f.endswith(".ogg"):
                rel = os.path.relpath(os.path.join(root, f), args.out).replace(os.sep, "/")
                if rel not in valid:
                    os.remove(os.path.join(root, f))
                    print(f"removed stale {rel}")
    write_catalog(cat_path, entries)
    if not args.no_banks and not failures:
        import pack_banks

        pack_banks.main([])
    total_files = sum(len(e["variants"]) or 1 for e in entries.values())
    print(f"\n{len(entries)} catalogue keys, {total_files} files, {time.time() - t0:.1f}s, failures: {len(failures)}")
    for k, e in failures:
        print(f"  {k}: {e}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
