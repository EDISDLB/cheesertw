#!/usr/bin/env python3
"""Compose and render the HULLDOWN music (original, procedurally synthesised).

The scores are data in ``tools/audio/scores/`` (tempo, meter, key, chord progressions, motif
statements, parts); this script renders them with the instrument models in
``tools/audio/synth/instruments.py`` via ``synth.music.render_cue``, masters every cue, encodes
OGG Vorbis (48 kHz stereo) into ``assets/music/`` and writes ``assets/music/catalog.json``.

Mastering
    * 28 Hz high-pass, linked glue compression and a linked look-ahead limiter computed from the
      full mix *and* every stem, so battle stems keep their balance and still sum without clipping.
    * Loops are processed circularly (filters, compressor, limiter and reverb wrap around), then all
      stems of a cue are rotated by one common offset so the file starts on a quiet zero-crossing
      just before the bar-1 downbeat (``loop.gridOffsetSamples`` in the catalogue).
    * Stingers end on their natural ring-out (trimmed at -70 dB, 250 ms fade).
    * Decoded files must stay <= -1.0 dBFS sample peak and <= -0.5 dBTP; gain is trimmed for the whole
      stem group if needed so stems keep identical gain.

Uploads: the 8 loops are uploaded individually; the 11 stingers (results + map identities) are
also packed into ``assets/music/banks/`` (<= 120 s each) so the whole score costs 10 uploads.

Usage::

    python3 tools/audio/generate_music.py              # everything (~2-4 min on 4 cores)
    python3 tools/audio/generate_music.py --only 'map_*,draw'
    python3 tools/audio/generate_music.py --list
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

from synth import filters, fx, io, mix, music  # noqa: E402
from synth.core import SR, n_of  # noqa: E402
from synth.env import fade  # noqa: E402

import scores  # noqa: E402
from scores.common import MOTIF_TEXT  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "music")
MASTERS = os.path.join(REPO, "build", "music_masters")
SCHEMA = "hulldown.music.catalog/1"
PRE_CEILING_DB = -1.5
MAX_PEAK_DB = -1.0
MAX_TRUE_PEAK_DB = -0.5
QUALITY = 0.6
BANK_MAX_S = 120.0
BANK_LEAD_S = 0.05
BANK_GAP_S = 0.5
ROTATE_SEARCH_S = 0.02
STINGER_LEAD_S = 0.01  # silent lead-in before beat 1 of a stinger (clean decoder start)
# Vorbis pre-echo smears a stinger's first downbeat back into the 10 ms lead-in (the lossless master is
# exactly zero there). A short raised-cosine fade on the downbeat keeps it below LEAD_SILENT_DB; the
# shortest fade that passes on the decoded file is used (QA found map_old_fortress at -59 dBFS with 2 ms).
STINGER_ONSET_FADES_S = (0.005, 0.01, 0.02)
LEAD_SILENT_DB = -62.0  # decoded lead-in ceiling (validate_music.py fails above -60 dBFS)

# --------------------------------------------------------------------------- music director data
# The client MusicDirector reads these tables from the catalogue; docs/design/audio.md section 11
# describes them. Times in seconds; thresholds on the 0..1 intensity value.
DIRECTOR = {
    "states": {
        "MENU": {"cue": "main_theme"},
        "GARAGE": {"cue": "garage_theme"},
        "LOADING": {"stinger": "map_<mapId>", "then": "loading_theme"},
        "BATTLE": {"stems": ["battle_base", "battle_mid", "battle_high"]},
        "BATTLE_ENDGAME": {"cue": "battle_endgame"},
        "RESULT_STINGER": {"victory": "victory", "defeat": "defeat", "draw": "draw"},
        "RESULTS": {"cue": "results_theme"},
    },
    "transitions": [
        {"from": "BOOT", "to": "MENU", "fadeInS": 2.0, "quantize": "none"},
        {"from": "MENU", "to": "GARAGE", "crossfadeS": 3.0, "quantize": "none"},
        {"from": "GARAGE", "to": "LOADING", "fadeOutS": 1.5, "quantize": "none",
         "note": "map stinger starts at once; loading_theme starts at the stinger's bodyEndS with a 1.5 s overlap"},
        {"from": "LOADING", "to": "BATTLE", "fadeOutS": 0.6, "quantize": "countdownGo",
         "note": "all three stems start together, scheduled so bar 1 lands on GO; base fades in over 1 bar"},
        {"from": "BATTLE", "to": "BATTLE_ENDGAME", "crossfadeS": 2.0, "quantize": "bar",
         "note": "same tempo and grid: endgame starts on the next bar line at the same bar position modulo its length"},
        {"from": "BATTLE|BATTLE_ENDGAME", "to": "RESULT_STINGER", "fadeOutS": 0.5, "quantize": "beat"},
        {"from": "RESULT_STINGER", "to": "RESULTS", "crossfadeS": 3.0, "quantize": "stingerBodyEnd"},
        {"from": "RESULTS", "to": "GARAGE", "crossfadeS": 3.0, "quantize": "none"},
        {"from": "*", "to": "MENU", "crossfadeS": 2.0, "quantize": "none"},
    ],
    "intensity": {
        "inputs": {
            "combat": {"weight": 0.35, "desc": "shots fired/received by own tank or within 150 m in the last 10 s, /6, capped at 1"},
            "threat": {"weight": 0.25, "desc": "spotted enemies within 300 m, /3, capped at 1"},
            "ownDamage": {"weight": 0.20, "desc": "1 - ownHP/maxHP"},
            "closeness": {"weight": 0.10, "desc": "1 - |teamHpShare - 0.5| * 2 (a close fight is tense)"},
            "time": {"weight": 0.10, "desc": "elapsed / battle length"},
        },
        "smoothing": {"riseS": 1.5, "fallS": 8.0},
        "layers": {
            "battle_base": {"always": True, "volume": 1.0},
            "battle_mid": {"on": 0.30, "off": 0.20, "fadeInS": 4.0, "fadeOutS": 8.0, "quantize": "bar"},
            "battle_high": {"on": 0.60, "off": 0.45, "fadeInS": 2.0, "fadeOutS": 8.0, "quantize": "bar"},
        },
        "minHoldBars": 4,
        "spectating": {"volumeDb": -6.0, "lowpassHz": 2000.0},
    },
    "endgame": {"timeLeftS": 120, "aliveTotalMax": 6, "teamAliveMax": 2, "hpShareDiff": 0.4, "exit": "never"},
    "ducking": [
        {"trigger": "Voice bus active", "depthDb": -6.0, "attackS": 0.02, "releaseS": 0.4},
        {"trigger": "own gun fired", "depthDb": -4.0, "attackS": 0.005, "holdS": 0.15, "releaseS": 0.5},
        {"trigger": "armor_hit_taken_*", "depthDb": -6.0, "attackS": 0.005, "holdS": 0.3, "releaseS": 0.8},
        {"trigger": "explosion within 60 m", "depthDb": -6.0, "attackS": 0.005, "holdS": 0.5, "releaseS": 1.2},
        {"trigger": "cue_sixth_sense", "depthDb": -4.0, "attackS": 0.01, "holdS": 1.0, "releaseS": 0.6},
        {"trigger": "garage fanfares (ui_vehicle_unlocked, ...)", "depthDb": -5.0, "attackS": 0.02, "releaseS": 0.6},
        {"trigger": "low-HP heartbeat", "depthDb": -3.0, "attackS": 0.2, "releaseS": 1.0},
    ],
    "busFader": {"menu": 0.6, "garage": 0.5, "battle": 0.45},
}

STEM_ORDER = {"base": 0, "mid": 1, "high": 2}


# --------------------------------------------------------------------------- mastering helpers
def circ_gain(fn, det: np.ndarray, reps: int = 3) -> np.ndarray:
    """Gain curve of a stateful detector applied to a loop: tile, process, keep the last copy."""
    n = det.shape[0]
    g = fn(np.concatenate([det] * reps, axis=0))
    return np.array(g[(reps - 1) * n : reps * n], copy=True)


def apply_gain(x: np.ndarray, g) -> np.ndarray:
    g = np.asarray(g)
    return x * (g[:, None] if g.ndim == 1 and x.ndim == 2 else g)


def zero_mean(x: np.ndarray) -> np.ndarray:
    n = x.shape[0]
    w = np.hanning(n)
    corr = np.mean(x, axis=0) / np.mean(w)
    return x - np.outer(w, corr)


def master(cue: music.Cue, stems: dict[str, np.ndarray]) -> tuple[dict[str, np.ndarray], dict]:
    loop = cue.kind == "loop"
    info: dict = {}

    def proc(fn, x):
        return mix.circular(fn, x, 2) if loop else fn(x)

    stems = {k: proc(lambda z: filters.highpass(z, 28.0, 2), v) for k, v in stems.items()}
    total = sum(stems.values())
    g0 = cue.target_lufs - mix.loudness_integrated(total)
    stems = {k: mix.gain_db(v, g0) for k, v in stems.items()}
    total = sum(stems.values())

    thr = cue.target_lufs + 7.0

    def comp_fn(z):
        return fx.compressor_gain(z, threshold_db=thr, ratio=2.0, attack=0.02, release=0.25, knee_db=8.0)

    gc = circ_gain(comp_fn, total) if loop else comp_fn(total)
    info["glueMaxGrDb"] = round(float(-20 * np.log10(max(gc.min(), 1e-9))), 2)
    stems = {k: apply_gain(v, gc) for k, v in stems.items()}
    total = sum(stems.values())
    g1 = cue.target_lufs - mix.loudness_integrated(total)
    stems = {k: mix.gain_db(v, g1) for k, v in stems.items()}
    total = sum(stems.values())

    det = np.max(np.abs(np.stack([total] + list(stems.values()), axis=0)), axis=0)

    def lim_fn(z):
        return fx.limiter_gain(z, PRE_CEILING_DB, 0.003, 0.08)

    gl = circ_gain(lim_fn, det) if loop else lim_fn(det)
    info["limiterMaxGrDb"] = round(float(-20 * np.log10(max(gl.min(), 1e-9))), 2)
    ceil = 10 ** (PRE_CEILING_DB / 20.0)
    stems = {k: np.clip(apply_gain(v, gl), -ceil, ceil) for k, v in stems.items()}

    if loop:
        stems = {k: v - np.mean(v, axis=0) for k, v in stems.items()}
        stems, off = common_rotation(stems)
        info["gridOffsetSamples"] = off
    else:
        total = sum(stems.values())
        mag = np.max(np.abs(total), axis=1)
        thr_a = mag.max() * 10 ** (-70 / 20.0)
        above = np.nonzero(mag > thr_a)[0]
        end = min(total.shape[0], int(above[-1]) + n_of(0.05)) if above.size else total.shape[0]
        end = max(end, cue.n_body + n_of(0.5))
        lead = np.zeros((n_of(STINGER_LEAD_S), 2))
        stems = {k: np.concatenate([lead, fade(zero_mean(v[:end]), 0.002, 0.25)], axis=0) for k, v in stems.items()}
        info["gridOffsetSamples"] = n_of(STINGER_LEAD_S)
    return stems, info


def common_rotation(stems: dict[str, np.ndarray]) -> tuple[dict[str, np.ndarray], int]:
    """Rotate all stems by one offset ``k`` (0..20 ms) so the file starts on the quietest, smoothest
    common point just before the downbeat; bar 1 then begins at sample ``k``. Each stem (and the
    full mix) is scored relative to its own RMS and 99th-percentile sample step, so a quiet stem
    is held to the same standard as a loud one. Rotation of a periodic loop is lossless, so seams
    and stem alignment are untouched."""
    arrs = list(stems.values())
    arrs = arrs + ([sum(arrs)] if len(arrs) > 1 else [])
    n = arrs[0].shape[0]
    k_max = n_of(ROTATE_SEARCH_S)
    ks = np.arange(0, k_max + 1)
    i = (n - ks) % n
    j = (i - 1) % n
    score = np.zeros(ks.size)
    for a in arrs:
        rms = float(np.sqrt(np.mean(a**2))) + 1e-9
        step = float(np.percentile(np.abs(np.diff(a, axis=0)), 99)) + 1e-12
        sc = np.max(np.abs(a[i]), axis=1) / rms + 2.0 * np.max(np.abs(a[i] - a[j]), axis=1) / step
        score = np.maximum(score, sc)
    best_k = int(ks[int(np.argmin(score))])
    return {name: np.roll(x, best_k, axis=0) for name, x in stems.items()}, best_k


def out_name(cue: music.Cue, stem: str) -> str:
    return cue.key if len(cue.stems) == 1 else f"{cue.key}_{stem}"


def encode_group(cue: music.Cue, stems: dict[str, np.ndarray], out_dir: str) -> tuple[dict, float]:
    """Encode every stem; if any decoded file breaks the ceiling, trim *all* stems equally."""
    trim = 0.0
    for _ in range(6):
        decoded = {}
        worst = 0.0
        for stem, x in stems.items():
            name = out_name(cue, stem)
            path = os.path.join(out_dir, f"{name}.ogg")
            io.write_ogg(path, x * 10 ** (trim / 20.0), SR, quality=QUALITY, key=f"music:{name}")
            dec, sr = io.read(path)
            if sr != SR:
                raise RuntimeError(f"{path}: decoded sample rate {sr}")
            pk, tp = mix.peak_db(dec), mix.true_peak_db(dec)
            worst = max(worst, pk - (MAX_PEAK_DB - 0.05), tp - MAX_TRUE_PEAK_DB)
            decoded[stem] = dec
        if worst <= 0.0:
            return decoded, trim
        trim -= max(worst + 0.15, 0.1)
    raise RuntimeError(f"{cue.key}: could not satisfy the peak ceiling")


# --------------------------------------------------------------------------- per-cue job
def render_job(name: str, out_dir: str) -> list[dict]:
    t0 = time.time()
    cue = scores.CUES[name]()
    stems = music.render_cue(cue)
    t_render = time.time() - t0
    stems, info = master(cue, stems)
    if cue.kind == "stinger":
        lead = n_of(STINGER_LEAD_S)
        for fade_s in STINGER_ONSET_FADES_S:
            trial = {k: np.concatenate([v[:lead], fade(v[lead:], fade_s, 0.0)], axis=0) for k, v in stems.items()}
            decoded, trim = encode_group(cue, trial, out_dir)
            head = max(float(np.max(np.abs(d[: max(1, lead - n_of(0.002))]))) for d in decoded.values())
            if 20 * np.log10(max(head, 1e-12)) <= LEAD_SILENT_DB:
                break
        stems = trial
        info["onsetFadeS"] = fade_s
    else:
        decoded, trim = encode_group(cue, stems, out_dir)
    os.makedirs(MASTERS, exist_ok=True)
    entries = []
    for stem, dec in decoded.items():
        key = out_name(cue, stem)
        io.write_flac(os.path.join(MASTERS, f"{key}.flac"), stems[stem] * 10 ** (trim / 20.0))
        statements = music.motif_statements(cue, stem if len(cue.stems) > 1 else None)
        insts = sorted({p.inst for p in cue.parts if len(cue.stems) == 1 or p.stem == stem})
        e = catalog_entry(cue, stem, key, dec, info, trim, statements, insts)
        e["_seconds"] = {"render": round(t_render, 1), "total": round(time.time() - t0, 1)}
        entries.append(e)
    return entries


def catalog_entry(cue, stem, key, dec, info, trim, statements, insts) -> dict:
    beat_s = 60.0 / cue.bpm
    bar_s = beat_s * cue.beats_per_bar
    e = {
        "file": f"{key}.ogg",
        "title": cue.title if len(cue.stems) == 1 else f"{cue.title} - {stem}",
        "description": cue.meta.get("stemDescriptions", {}).get(stem, cue.description),
        "state": cue.state,
        "kind": cue.kind,
        "durationS": round(dec.shape[0] / SR, 6),
        "samples": int(dec.shape[0]),
        "channels": 2,
        "bpm": cue.bpm,
        "meter": cue.meter,
        "beatsPerBar": cue.beats_per_bar,
        "bars": cue.bars,
        "beatS": round(beat_s, 6),
        "barS": round(bar_s, 6),
        "samplesPerBeat": round(cue.spb, 3),
        "key": cue.key_sig,
        "suggested": {"volume": cue.volume},
        "loudnessLufs": round(mix.loudness_integrated(dec), 2),
        "peakDb": round(mix.peak_db(dec), 2),
        "truePeakDb": round(mix.true_peak_db(dec), 2),
        "master": dict(info, encodeTrimDb=round(trim, 2), targetLufs=cue.target_lufs),
        "motif": statements,
        "instruments": insts,
    }
    if cue.kind == "loop":
        off = info["gridOffsetSamples"]
        sm = mix.seam_metrics(dec)
        e["loop"] = {
            "startS": 0.0,
            "endS": e["durationS"],
            "gridOffsetSamples": off,
            "gridOffsetS": round(off / SR, 6),
            "seamless": True,
            "seam": {"jumpRatio": round(sm["jumpRatio"], 3), "hfBurstDb": round(sm["hfBurstDb"], 2),
                     "firstSampleAbs": round(float(np.max(np.abs(dec[0]))), 5)},
        }
        e["suggested"].update({"fadeInS": 2.0, "fadeOutS": 2.0, "quantize": "bar"})
    else:
        lead = info["gridOffsetSamples"]
        e["stinger"] = {"leadS": round(lead / SR, 6), "bodyEndS": round((lead + cue.n_body) / SR, 6),
                        "tailS": round((dec.shape[0] - lead - cue.n_body) / SR, 3)}
        e["suggested"].update({"fadeInS": 0.0, "fadeOutS": 0.5})
    if len(cue.stems) > 1:
        e["group"] = cue.group
        e["stem"] = stem
        e["layer"] = STEM_ORDER.get(stem, 0)
    if cue.meta.get("sections"):
        e["sectionsBar"] = cue.meta["sections"]
    if cue.meta.get("map"):
        e["map"] = cue.meta["map"]
        e["biome"] = cue.meta["biome"]
    return e


# --------------------------------------------------------------------------- banks
def pack_banks(entries: dict, out_dir: str) -> dict:
    """Concatenate stinger masters into <= BANK_MAX_S banks (one lossy generation)."""
    order = ["victory", "defeat", "draw"] + sorted(k for k in entries if k.startswith("map_"))
    order = [k for k in order if k in entries and entries[k]["kind"] == "stinger"]
    banks, chunk, total, index = {}, [], BANK_LEAD_S, 1

    def flush(chunk, index):
        name = f"music_stingers_{index}"
        rel = f"banks/{name}.ogg"
        length = n_of(BANK_LEAD_S) + sum(x.shape[0] + n_of(BANK_GAP_S) for _, x in chunk)
        buf = np.zeros((length, 2))
        pos = n_of(BANK_LEAD_S)
        regions = []
        for key, x in chunk:
            buf[pos : pos + x.shape[0]] = x
            entries[key]["bankRegion"] = {"bank": rel, "startS": round(pos / SR, 6), "endS": round((pos + x.shape[0]) / SR, 6)}
            regions.append(key)
            pos += x.shape[0] + n_of(BANK_GAP_S)
        path = os.path.join(out_dir, rel)
        io.write_ogg(path, buf, SR, quality=QUALITY, key=f"music-bank:{name}")
        dec, _ = io.read(path)
        if mix.peak_db(dec) > MAX_PEAK_DB or mix.true_peak_db(dec) > MAX_TRUE_PEAK_DB + 0.2:
            raise RuntimeError(f"bank {name} exceeds the ceiling")
        banks[name] = {"file": rel, "durationS": round(dec.shape[0] / SR, 3), "channels": 2, "contents": regions,
                       "peakDb": round(mix.peak_db(dec), 2)}

    for key in order:
        x, sr = io.read(os.path.join(MASTERS, f"{key}.flac"))
        dur = x.shape[0] / SR + BANK_GAP_S
        if chunk and total + dur > BANK_MAX_S:
            flush(chunk, index)
            chunk, total, index = [], BANK_LEAD_S, index + 1
        chunk.append((key, x))
        total += dur
    if chunk:
        flush(chunk, index)
    return banks


# --------------------------------------------------------------------------- catalogue
def write_catalog(path: str, entries: dict, banks: dict) -> None:
    groups = {}
    for k, e in entries.items():
        if e.get("group"):
            g = groups.setdefault(e["group"], {"stems": [], "bpm": e["bpm"], "key": e["key"], "samples": e["samples"],
                                               "gridOffsetSamples": e["loop"]["gridOffsetSamples"], "bars": e["bars"],
                                               "barS": e["barS"], "targetLufsAllLayers": e["master"]["targetLufs"]})
            g["stems"].append(k)
    for g in groups.values():
        g["stems"].sort(key=lambda k: entries[k]["layer"])
    doc = {
        "schema": SCHEMA,
        "generator": "tools/audio/generate_music.py",
        "root": "assets/music",
        "format": "ogg/vorbis",
        "sampleRate": SR,
        "channels": 2,
        "bus": "Music",
        "motif": {
            "name": "HULLDOWN call",
            "notation": MOTIF_TEXT,
            "degrees": "1 1 5 b6 4 5 (D minor)",
            "description": "Dotted bugle pickup on the tonic, heroic rising fifth, somber minor sixth sighing back to "
                           "the fifth through the fourth, open ending on the dominant.",
        },
        "notes": {
            "loop": "Loops are seamless over the whole file. Bar 1 beat 1 is at loop.gridOffsetSamples; bar n starts at "
                    "gridOffsetSamples + (n-1)*barS*sampleRate (wrapping). Stems of a group share length and grid.",
            "stinger": "One-shots. stinger.bodyEndS is the end of the last bar (start the next cue there); the rest is ring-out.",
            "volume": "suggested.volume is the AudioPlayer volume; the Music bus fader is separate (director.busFader).",
            "banks": "Upload the loops and the banks (not the individual stingers): play a stinger from its bank with "
                     "PlaybackRegion = NumberRange.new(bankRegion.startS, bankRegion.endS).",
        },
        "director": DIRECTOR,
        "groups": groups,
        "banks": banks,
        "cues": {k: {kk: vv for kk, vv in entries[k].items() if not kk.startswith("_")} for k in sorted(entries)},
    }
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2)
        fh.write("\n")


# --------------------------------------------------------------------------- CLI
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma-separated glob patterns of score names")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 2)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(argv)
    names = list(scores.CUES)
    if args.only:
        pats = [p.strip() for p in args.only.split(",") if p.strip()]
        names = [k for k in names if any(fnmatch.fnmatch(k, p) for p in pats)]
    if args.list:
        for k in names:
            c = scores.CUES[k]()
            dur = c.n_body / SR + (c.tail_s if c.kind == "stinger" else 0)
            print(f"{k:22s} {c.kind:8s} {c.bpm:5.0f} bpm {c.meter:4s} {c.bars:3d} bars {dur:6.1f}s  stems {','.join(c.stems)}"
                  f"  parts {len(c.parts)}  notes {sum(len(p.notes) for p in c.parts)}")
        return 0
    os.makedirs(args.out, exist_ok=True)
    cat_path = os.path.join(args.out, "catalog.json")
    entries: dict = {}
    if args.only and os.path.exists(cat_path):
        with open(cat_path, encoding="utf-8") as fh:
            entries = json.load(fh).get("cues", {})
    t0 = time.time()
    failures = []
    # longest jobs first so the pool stays busy
    weight = {"battle": 0, "garage_theme": 1, "main_theme": 2, "battle_endgame": 3, "loading_theme": 4}
    names.sort(key=lambda k: weight.get(k, 10))
    with ProcessPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futs = {pool.submit(render_job, k, args.out): k for k in names}
        for fut in as_completed(futs):
            k = futs[fut]
            try:
                res = fut.result()
            except Exception as exc:  # noqa: BLE001
                import traceback

                traceback.print_exc()
                failures.append((k, repr(exc)))
                continue
            for e in res:
                key = e["file"][:-4]
                entries[key] = e
                lp = e.get("loop", {})
                print(f"{key:24s} {e['durationS']:7.2f}s  {e['loudnessLufs']:6.1f} LUFS  peak {e['peakDb']:6.2f}  "
                      f"tp {e['truePeakDb']:6.2f}  glue {e['master']['glueMaxGrDb']:4.1f} lim {e['master']['limiterMaxGrDb']:4.1f}"
                      f"{'  seam %.2f off %d' % (lp['seam']['jumpRatio'], lp['gridOffsetSamples']) if lp else ''}"
                      f"  motif x{len(e['motif'])}  ({e['_seconds']['render']}s/{e['_seconds']['total']}s)", flush=True)
    valid = {e["file"] for e in entries.values()}
    for f in os.listdir(args.out):
        if f.endswith(".ogg") and f not in valid:
            os.remove(os.path.join(args.out, f))
            print(f"removed stale {f}")
    banks = pack_banks(entries, args.out) if not failures else {}
    write_catalog(cat_path, entries, banks)
    print(f"\n{len(entries)} music files, {len(banks)} banks, {time.time() - t0:.1f}s, failures: {len(failures)}")
    for k, e in failures:
        print(f"  {k}: {e}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
