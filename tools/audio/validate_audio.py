#!/usr/bin/env python3
"""Validate the generated HULLDOWN audio catalogue.

Checks every file listed in ``assets/audio/catalog.json`` (and the registry) for:

* integrity      - file exists, decodes, 48 kHz, channel count matches catalogue and bus policy
                   (positional = mono, 2D UI/Voice/beds = stereo), no orphans, no NaN, not silent
* headroom       - sample peak <= -1.0 dBFS (hard), inter-sample true peak reported (warn > -0.3)
* DC offset      - |mean| < 0.001 per channel
* clipping       - no runs of >= 3 identical full-scale samples
* duration       - per-category ranges (one-shots short; loops 2-8 s; beds 20-60 s)
* loop seams     - decoded OGG seam jump <= 1.0x the 99th-percentile sample step (no click)
* loudness       - within the bus window and within +-3 dB of the sound's own target
* distinctness   - armor results and engine families: pairwise log-mel spectral distance
* determinism    - (``--determinism N``) re-render N keys to a temp dir and compare bytes

Writes ``build/audio_review/validation.json``; exit code 1 if any hard check fails.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from synth import io, mix  # noqa: E402
from synth.analysis import log_mel_profile, spectral_features  # noqa: E402
from synth.core import SR  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(REPO, "assets", "audio")
OUT = os.path.join(REPO, "build", "audio_review")

# Loudness windows per bus (LUFS): one-shots use momentary-max, loops integrated.
BUS_WINDOWS = {
    "Weapons": {"shot": (-28, -8), "loop": (-34, -14)},
    "Impacts": {"shot": (-28, -8), "loop": (-30, -16)},
    "Vehicles": {"shot": (-30, -12), "loop": (-32, -14)},
    "UI": {"shot": (-36, -12), "loop": (-26, -14)},
    "Voice": {"shot": (-26, -14), "loop": (-28, -16)},
    "Ambience": {"shot": (-34, -14), "loop": (-34, -20)},
}
# (min, max) seconds
DURATION_RULES = {
    "loop:default": (2.0, 8.0),
    "loop:ambience": (20.0, 60.0),
    "loop:weather": (20.0, 60.0),
    "loop:hangar": (20.0, 60.0),
    "shot:ui": (0.02, 3.5),
    "shot:cues": (0.1, 3.5),
    "shot:radio": (0.2, 2.5),
    "shot:default": (0.02, 10.0),
}
POSITIONAL_BUSES = {"Vehicles", "Weapons", "Impacts"}


def duration_rule(cat: str, loop: bool) -> tuple[float, float]:
    key = f"{'loop' if loop else 'shot'}:{cat}"
    return DURATION_RULES.get(key, DURATION_RULES[f"{'loop' if loop else 'shot'}:default"])


def clip_runs(x: np.ndarray) -> int:
    a = np.abs(x if x.ndim == 1 else x.max(axis=1))
    full = a >= 0.999
    if not np.any(full):
        return 0
    runs = 0
    count = 0
    for v in full:
        count = count + 1 if v else 0
        if count == 3:
            runs += 1
    return runs


def region_match(seg: np.ndarray, ref: np.ndarray) -> tuple[float, float]:
    """Compare a bank region with its standalone file (two independent lossy encodes of one master).

    Returns (amplitude-envelope correlation, mean absolute band-energy difference in dB). Waveform
    correlation is not used because Vorbis does not preserve noise-like waveforms."""
    from scipy.signal import stft

    m = min(seg.shape[0], ref.shape[0])
    a = seg[:m] if seg.ndim == 1 else seg[:m].mean(axis=1)
    b = ref[:m] if ref.ndim == 1 else ref[:m].mean(axis=1)
    k = max(1, int(0.01 * SR))
    ea = np.convolve(np.abs(a), np.ones(k) / k, mode="same")
    eb = np.convolve(np.abs(b), np.ones(k) / k, mode="same")
    corr = float(np.corrcoef(ea, eb)[0, 1]) if m > k else 1.0
    f, _, A = stft(a, SR, nperseg=1024)
    _, _, B = stft(b, SR, nperseg=1024)
    edges = np.geomspace(50, 16000, 25)
    pa, pb = np.abs(A) ** 2, np.abs(B) ** 2
    da, db = [], []
    for lo, hi in zip(edges[:-1], edges[1:]):
        sel = (f >= lo) & (f < hi)
        da.append(pa[sel].sum(axis=0))
        db.append(pb[sel].sum(axis=0))
    da, db = 10 * np.log10(np.array(da) + 1e-20), 10 * np.log10(np.array(db) + 1e-20)
    mask = db > db.max() - 50
    sdiff = float(np.mean(np.abs(da[mask] - db[mask]))) if np.any(mask) else 0.0
    return corr, sdiff


def distinctness(group: dict[str, np.ndarray]) -> dict:
    """Pairwise distance between mean-removed log-mel profiles (dB RMS) and centroid/crest table."""
    profs = {k: log_mel_profile(x) for k, x in group.items()}
    keys = list(group)
    mat = {}
    min_d = None
    for i, a in enumerate(keys):
        for b in keys[i + 1 :]:
            pa = profs[a] - profs[a].mean()
            pb = profs[b] - profs[b].mean()
            d = float(np.sqrt(np.mean((pa - pb) ** 2)))
            mat[f"{a} vs {b}"] = round(d, 2)
            min_d = d if min_d is None else min(min_d, d)
    feats = {k: {kk: round(v, 3) for kk, v in spectral_features(x).items()} for k, x in group.items()}
    return {"pairwiseLogMelDistanceDb": mat, "minDistanceDb": round(min_d or 0.0, 2), "features": feats}


def check_determinism(keys: list[str]) -> dict:
    import generate_sfx as gen  # local import: heavy

    res = {}
    with tempfile.TemporaryDirectory() as tmp:
        for k in keys:
            out = gen.render_sound(k, tmp, None)
            same = True
            for st in out["stats"]:
                a = open(os.path.join(tmp, st["file"]), "rb").read()
                b = open(os.path.join(AUDIO, st["file"]), "rb").read()
                if hashlib.sha256(a).digest() != hashlib.sha256(b).digest():
                    same = False
            res[k] = same
    return res


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--determinism", type=int, default=6, help="number of keys to re-render and byte-compare (0 = skip)")
    args = ap.parse_args(argv)

    with open(os.path.join(AUDIO, "catalog.json"), encoding="utf-8") as fh:
        cat = json.load(fh)
    sounds = cat["sounds"]
    errors: list[str] = []
    warnings: list[str] = []
    per_file = {}
    loaded: dict[str, np.ndarray] = {}

    # registry vs catalogue
    try:
        import designs  # noqa: F401
        from designs.registry import REGISTRY

        missing = sorted(set(REGISTRY) - set(sounds))
        extra = sorted(set(sounds) - set(REGISTRY))
        for k in missing:
            errors.append(f"{k}: registered but missing from catalog")
        for k in extra:
            errors.append(f"{k}: in catalog but not registered")
    except Exception as exc:  # noqa: BLE001
        warnings.append(f"could not import registry: {exc!r}")

    listed = set()
    bus_stats: dict[str, list[float]] = {}
    for key, e in sounds.items():
        files = e["variants"] or [e["file"]]
        target = None
        try:
            target = REGISTRY[key].level  # type: ignore[name-defined]
        except Exception:  # noqa: BLE001
            pass
        for rel in files:
            listed.add(rel)
            path = os.path.join(AUDIO, rel)
            tag = f"{key} [{rel}]"
            if not os.path.exists(path):
                errors.append(f"{tag}: file missing")
                continue
            try:
                x, sr = io.read(path)
            except Exception as exc:  # noqa: BLE001
                errors.append(f"{tag}: failed to decode: {exc!r}")
                continue
            loaded[rel] = x
            ch = 1 if x.ndim == 1 else x.shape[1]
            dur = x.shape[0] / sr
            pk = mix.peak_db(x)
            tp = mix.true_peak_db(x)
            dc = mix.dc_offset(x)
            lufs = mix.loudness_integrated(x, sr) if e["loop"] else mix.loudness_momentary_max(x, sr)
            rec = {"durationS": round(dur, 3), "channels": ch, "peakDb": round(pk, 2), "truePeakDb": round(tp, 2),
                   "dc": round(dc, 6), "lufs": round(lufs, 2)}
            if sr != SR:
                errors.append(f"{tag}: sample rate {sr}")
            if not np.all(np.isfinite(x)):
                errors.append(f"{tag}: non-finite samples")
            if ch != e["channels"]:
                errors.append(f"{tag}: channels {ch} != catalog {e['channels']}")
            positional = e["suggested"]["rollOffMaxStuds"] is not None
            if positional and ch != 1:
                errors.append(f"{tag}: positional sound must be mono")
            if e["bus"] in ("UI", "Voice") and ch != 2:
                errors.append(f"{tag}: {e['bus']} sound should be stereo")
            if e["bus"] == "Ambience" and e["loop"] and ch != 2:
                errors.append(f"{tag}: ambience bed should be stereo")
            if pk > -1.0:
                errors.append(f"{tag}: peak {pk:.2f} dBFS > -1.0")
            if tp > -0.3:
                warnings.append(f"{tag}: true peak {tp:.2f} dBTP")
            if pk < -45:
                errors.append(f"{tag}: nearly silent (peak {pk:.1f})")
            if dc > 1e-3:
                errors.append(f"{tag}: DC offset {dc:.4f}")
            cr = clip_runs(x)
            if cr:
                errors.append(f"{tag}: {cr} clipped runs")
            lo, hi = duration_rule(e["category"], e["loop"])
            if not (lo - 1e-3 <= dur <= hi + 1e-3):
                errors.append(f"{tag}: duration {dur:.2f}s outside [{lo}, {hi}]")
            if e["loop"]:
                sm = mix.seam_metrics(x)
                rec["seamJumpRatio"] = round(sm["jumpRatio"], 3)
                rec["seamHfBurstDb"] = round(sm["hfBurstDb"], 2)
                if sm["jumpRatio"] > 1.0:
                    errors.append(f"{tag}: loop seam jump ratio {sm['jumpRatio']:.2f} > 1.0")
                if sm["hfBurstDb"] > 10.0:
                    warnings.append(f"{tag}: HF energy at seam {sm['hfBurstDb']:.1f} dB above median")
                # start must be near a zero crossing
                first = float(np.max(np.abs(np.atleast_1d(x[0]))))
                if first > 0.05:
                    warnings.append(f"{tag}: loop starts at |x|={first:.3f}")
            win = BUS_WINDOWS.get(e["bus"], {}).get("loop" if e["loop"] else "shot")
            if win and not (win[0] <= lufs <= win[1]):
                errors.append(f"{tag}: loudness {lufs:.1f} LUFS outside {e['bus']} window {win}")
            if target is not None and abs(lufs - target) > 3.0:
                warnings.append(f"{tag}: loudness {lufs:.1f} vs target {target:.1f}")
            bus_stats.setdefault(f"{e['bus']}/{'loop' if e['loop'] else 'shot'}", []).append(lufs)
            per_file[rel] = rec

    for root, _, files in os.walk(AUDIO):
        for f in files:
            if f.endswith(".ogg"):
                rel = os.path.relpath(os.path.join(root, f), AUDIO).replace(os.sep, "/")
                if rel not in listed and rel not in {b["file"] for b in cat.get("banks", {}).values()}:
                    errors.append(f"orphan file {rel}")

    # upload banks: every region must match its standalone file and gaps must be silent
    bank_report = {}
    bank_files = {b["file"] for b in cat.get("banks", {}).values()}
    for name, b in cat.get("banks", {}).items():
        path = os.path.join(AUDIO, b["file"])
        if not os.path.exists(path):
            errors.append(f"bank {name}: missing file")
            continue
        bx, bsr = io.read(path)
        bpk = mix.peak_db(bx)
        if bpk > -1.0:
            errors.append(f"bank {name}: peak {bpk:.2f} dBFS > -1.0")
        if (1 if bx.ndim == 1 else bx.shape[1]) != b["channels"]:
            errors.append(f"bank {name}: channel mismatch")
        bank_report[name] = {"peakDb": round(bpk, 2), "durationS": round(bx.shape[0] / bsr, 2), "minCorrelation": 1.0}
    covered = 0
    for key, e in sounds.items():
        regs = e.get("bankRegions")
        files = e["variants"] or [e["file"]]
        if e["loop"]:
            if regs:
                errors.append(f"{key}: loops must not be banked")
            continue
        if not regs or len(regs) != len(files):
            errors.append(f"{key}: missing/mismatched bankRegions")
            continue
        for rel, r in zip(files, regs):
            if r["bank"] not in bank_files or rel not in loaded:
                errors.append(f"{key}: bad bank reference {r['bank']}")
                continue
            bname = os.path.splitext(os.path.basename(r["bank"]))[0]
            bx, _ = io.read(os.path.join(AUDIO, r["bank"]))
            a, b_ = int(round(r["startS"] * SR)), int(round(r["endS"] * SR))
            seg = bx[a:b_]
            ref = loaded[rel]
            corr, sdiff = region_match(seg, ref)
            bank_report[bname]["minCorrelation"] = round(min(bank_report[bname]["minCorrelation"], corr), 4)
            bank_report[bname]["maxSpectralDiffDb"] = round(max(bank_report[bname].get("maxSpectralDiffDb", 0.0), sdiff), 2)
            if corr < 0.98 or sdiff > 1.5 or abs(seg.shape[0] - ref.shape[0]) > 2:
                errors.append(f"{key}: bank region differs from standalone file (envelope corr {corr:.3f}, "
                              f"spectral diff {sdiff:.2f} dB, len {seg.shape[0]} vs {ref.shape[0]})")
            gap = bx[max(0, a - int(0.2 * SR)) : max(0, a - int(0.05 * SR))]
            if gap.size and mix.rms_db(gap) > -70:
                errors.append(f"{key}: bank gap before region not silent ({mix.rms_db(gap):.1f} dB)")
            covered += 1

    # distinctness of gameplay-critical families
    def pick(keys_variants):
        out = {}
        for label, rel in keys_variants:
            if rel in loaded:
                out[label] = loaded[rel]
        return out

    armor = pick([(k, f"armor/{k}_a.ogg") for k in ("armor_penetration", "armor_ricochet", "armor_blocked", "armor_critical",
                                                    "armor_hit_taken_pen", "armor_hit_taken_blocked")])
    engines = pick([(f, f"engines/engine_{f}_mid.ogg") for f in ("heavy_diesel", "medium_diesel", "light_highrpm", "large_v12",
                                                                 "small_engine", "turbine")])
    cues = pick([(k, f"cues/{k}.ogg") for k in ("cue_sixth_sense", "cue_enemy_spotted", "cue_reload_complete", "cue_target_locked",
                                                "cue_ally_destroyed", "cue_enemy_destroyed")])
    dist = {}
    for name, grp, thr in (("armorResults", armor, 4.0), ("engineFamilies", engines, 3.0), ("battleCues", cues, 4.0)):
        if len(grp) >= 2:
            dist[name] = distinctness(grp)
            if dist[name]["minDistanceDb"] < thr:
                errors.append(f"distinctness {name}: min pairwise log-mel distance {dist[name]['minDistanceDb']} dB < {thr}")

    det = check_determinism(sorted(sounds)[:: max(1, len(sounds) // max(args.determinism, 1))][: args.determinism]) if args.determinism else {}
    for k, same in det.items():
        if not same:
            errors.append(f"{k}: re-render is not byte-identical")

    summary = {
        "keys": len(sounds),
        "files": len(per_file),
        "errors": errors,
        "warnings": warnings,
        "busLoudness": {b: {"count": len(v), "min": round(min(v), 1), "median": round(float(np.median(v)), 1), "max": round(max(v), 1)}
                        for b, v in sorted(bus_stats.items())},
        "maxPeakDb": round(max(r["peakDb"] for r in per_file.values()), 2) if per_file else None,
        "maxTruePeakDb": round(max(r["truePeakDb"] for r in per_file.values()), 2) if per_file else None,
        "maxDc": max(r["dc"] for r in per_file.values()) if per_file else None,
        "loops": {
            "count": sum(1 for r in per_file.values() if "seamJumpRatio" in r),
            "maxSeamJumpRatio": max((r["seamJumpRatio"] for r in per_file.values() if "seamJumpRatio" in r), default=None),
            "maxSeamHfBurstDb": max((r["seamHfBurstDb"] for r in per_file.values() if "seamHfBurstDb" in r), default=None),
        },
        "banks": {"count": len(bank_report), "regionsChecked": covered, "detail": bank_report},
        "distinctness": dist,
        "determinism": det,
        "files_detail": per_file,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "validation.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)

    print(f"keys {summary['keys']}  files {summary['files']}  max peak {summary['maxPeakDb']} dBFS  "
          f"max true-peak {summary['maxTruePeakDb']} dBTP  max DC {summary['maxDc']}")
    print(f"loops {summary['loops']}")
    for b, s in summary["busLoudness"].items():
        print(f"  {b:16s} n={s['count']:3d}  LUFS min {s['min']:6.1f}  median {s['median']:6.1f}  max {s['max']:6.1f}")
    if bank_report:
        print(f"banks: {len(bank_report)} banks, {covered} regions match standalone files "
              f"(min correlation {min(b['minCorrelation'] for b in bank_report.values())})")
    for name, d in dist.items():
        print(f"distinctness {name}: min pairwise {d['minDistanceDb']} dB")
    if det:
        print(f"determinism: {sum(det.values())}/{len(det)} byte-identical")
    print(f"{len(errors)} errors, {len(warnings)} warnings")
    for e_ in errors[:60]:
        print("  ERROR", e_)
    for w in warnings[:60]:
        print("  warn ", w)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
