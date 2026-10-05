#!/usr/bin/env python3
"""Validate the generated HULLDOWN music and render its review sheets.

Checks every cue in ``assets/music/catalog.json``:

* integrity     - file exists, decodes, 48 kHz stereo, length matches the catalogue, within the
                  duration window for its role (menu 90-120 s, garage 120-150 s, battle 60-90 s, ...)
* headroom      - sample peak <= -1.0 dBFS, true peak <= -0.5 dBTP, DC < 0.001, no clipped runs
* loudness      - integrated loudness within 1.5 dB of the cue's target and inside the music window
* loops         - seam jump ratio <= 1 (decoded file), no HF burst at the seam, spectral and loudness
                  continuity across the seam no worse than between any two adjacent frames of the
                  loop, start sample near zero
* stems         - identical length, sample rate and grid offset; onset energy of every stem folds onto
                  the declared 16th-note grid at the declared offset; pairwise onset cross-correlation
                  peaks at lag 0; base+mid+high stays under the ceiling and hits the group target
* tempo         - onset-autocorrelation tempo of rhythmic loops matches the declared BPM (or x2 / /2)
* tonality      - the declared key (or relative / same-pitch-set mode) ranks in the top 3 of the 24
                  Krumhansl-Kessler key profiles, or the declared mode's pitch set is the best match,
                  or (open/suspended harmony) the strongest bass pitch class is the tonic
* motif         - every cue states the motif (score annotation); at each statement the audio's
                  chroma shows the call's tonic and fifth
* stingers      - start from silence, end decayed (< -60 dBFS RMS in the last 50 ms)
* banks         - every stinger's bank region matches its standalone file
* determinism   - one short cue is re-rendered and byte-compared

Writes ``build/audio_review/music_validation.json`` and ``build/audio_review/music_*.png``.
Exit code 1 on any error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile

import numpy as np
from scipy.signal import stft

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from synth import analysis, io, mix  # noqa: E402
from synth.core import SR  # noqa: E402
from synth.music import SCALES, pc_of  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
MUSIC = os.path.join(REPO, "assets", "music")
OUT = os.path.join(REPO, "build", "audio_review")

DURATION = {  # role windows (seconds)
    "main_theme": (90, 120), "garage_theme": (120, 150), "loading_theme": (45, 60), "battle_": (60, 90),
    "results_theme": (55, 65), "victory": (20, 40), "defeat": (20, 40), "draw": (15, 30), "map_": (10, 20),
}
LUFS_WINDOW = (-24.0, -14.0)
MODE_OF = {  # declared key text -> (tonic, scale) used for the pitch-set check
    "D minor": ("D", "aeolian"), "D major": ("D", "major"), "D minor / F major": ("D", "aeolian"),
    "D minor (Phrygian)": ("D", "aeolian"), "D Phrygian dominant": ("D", "phrygian_dominant"),
    "D minor (add9)": ("D", "aeolian"), "D Dorian": ("D", "dorian"), "D Lydian": ("D", "lydian"),
    "D Mixolydian": ("D", "mixolydian"), "D (open, sus)": ("D", "aeolian"),
}


ACCEPT_KEYS = {  # K-K labels that count as the declared mode (tonic, relative, or same pitch set)
    "aeolian": {"D minor", "F major"}, "harmonic_minor": {"D minor"}, "major": {"D major", "B minor"},
    "dorian": {"D minor", "C major", "A minor"}, "lydian": {"D major", "A major"},
    "mixolydian": {"D major", "G major"}, "phrygian_dominant": {"D major", "D minor", "G minor"},
}


def duration_window(key: str):
    for k, v in DURATION.items():
        if key == k or (k.endswith("_") and key.startswith(k)):
            return v
    return None


def clip_runs(x: np.ndarray) -> int:
    a = np.max(np.abs(x), axis=1) >= 0.999
    if not a.any():
        return 0
    d = np.diff(np.concatenate([[0], a.astype(int), [0]]))
    starts, ends = np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]
    return int(np.sum((ends - starts) >= 3))


def logmel_frames(m: np.ndarray, nper: int = 2048, hop: int = 1024) -> np.ndarray:
    f, _, Z = stft(m, SR, nperseg=nper, noverlap=nper - hop, boundary=None, padded=False)
    p = np.abs(Z) ** 2
    edges = np.geomspace(60, 16000, 33)
    bands = np.array([p[(f >= lo) & (f < hi)].sum(axis=0) for lo, hi in zip(edges[:-1], edges[1:])])
    return 10 * np.log10(bands + 1e-12)


def _bar_change(m: np.ndarray, pos: int, win: int) -> tuple[float, float]:
    """Spectral (log-band RMS dB) and level (dB) change between the ``win`` samples before and after
    sample ``pos`` of a loop (indices wrap)."""
    n = m.shape[0]
    a = m[np.arange(pos - win, pos) % n]
    b = m[np.arange(pos, pos + win) % n]
    fa, fb = logmel_frames(a).mean(axis=1), logmel_frames(b).mean(axis=1)
    return float(np.sqrt(np.mean((fb - fa) ** 2))), float(abs(mix.rms_db(b) - mix.rms_db(a)))


def seam_continuity(x: np.ndarray, e: dict) -> dict:
    """The loop seam must behave like an ordinary bar line of the same piece: the spectral and level
    change across it (0.5 s either side) is compared with the same measure at every other bar line.
    (Sample continuity is checked separately by the jump ratio.)"""
    m = x.mean(axis=1)
    off = e["loop"]["gridOffsetSamples"]
    bar = e["barS"] * SR
    win = int(0.5 * SR)
    seam_pos = 0  # the file boundary
    seam = _bar_change(m, seam_pos, win)
    others = [_bar_change(m, int(round(off + b * bar)), win) for b in range(1, e["bars"])]
    spec = np.array([o[0] for o in others])
    lev = np.array([o[1] for o in others])
    return {
        "seamSpectralChangeDb": round(seam[0], 2),
        "barlineSpectralChangeMaxDb": round(float(spec.max()), 2),
        "barlineSpectralChangeP90Db": round(float(np.percentile(spec, 90)), 2),
        "seamLevelChangeDb": round(seam[1], 2),
        "barlineLevelChangeMaxDb": round(float(lev.max()), 2),
        "barlineLevelChangeP90Db": round(float(np.percentile(lev, 90)), 2),
    }


def in_scale_ratio(ch: np.ndarray, tonic: str, scale: str) -> tuple[float, bool]:
    t = pc_of(tonic)
    pcs = [(t + s) % 12 for s in SCALES[scale]]
    ratio = float(ch[pcs].sum())
    best = max(range(12), key=lambda r: ch[[(r + s) % 12 for s in SCALES[scale]]].sum())
    same_set = sorted((best + s) % 12 for s in SCALES[scale]) == sorted(pcs)
    return ratio, same_set


def motif_check(x: np.ndarray, e: dict) -> dict:
    """At each motif statement: is the call's tonic among the strongest pitch classes during the
    repeated-note pickup, and its fifth during the following beat? (whole mix, so other parts count)."""
    off = e["loop"]["gridOffsetSamples"] if "loop" in e else int(round(e["stinger"]["leadS"] * SR))
    beat = e["beatS"] * SR
    hits = total = 0
    for st in e["motif"]:
        if st["form"] not in ("motif", "motif_aug", "motif_head", "motif_dorian", "motif_relmajor", "motif_transposed",
                              "motif_lament"):
            continue
        tonic = st.get("tonicPc")
        if tonic is None:
            continue
        scale = 2.0 if st["form"] == "motif_aug" else 1.0
        start = off + ((st["bar"] - 1) * e["beatsPerBar"] + (st["beat"] - 1)) * beat
        for pcs, a, b in ((tonic, 0.0, 1.0), ((tonic + 7) % 12, 1.0, 2.0)):
            s0, s1 = int(start + a * scale * beat), int(start + b * scale * beat)
            idx = np.arange(s0, s1) % x.shape[0] if "loop" in e else np.arange(s0, min(s1, x.shape[0]))
            if idx.size < 2048:
                continue
            ch = analysis.chroma(x[idx], nperseg=4096)
            total += 1
            hits += int(pcs in np.argsort(ch)[-3:])
    return {"checked": total, "hits": hits, "rate": round(hits / total, 3) if total else None}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-sheets", action="store_true")
    ap.add_argument("--no-determinism", action="store_true")
    ap.add_argument("--music", default=None, help="music directory to validate (default assets/music)")
    args = ap.parse_args(argv)
    global MUSIC, OUT
    if args.music:
        MUSIC = os.path.abspath(args.music)
        OUT = os.path.join(MUSIC, "_review")
    with open(os.path.join(MUSIC, "catalog.json"), encoding="utf-8") as fh:
        cat = json.load(fh)
    cues = cat["cues"]
    errors, warnings = [], []
    report: dict = {}
    loaded: dict = {}

    for key, e in cues.items():
        path = os.path.join(MUSIC, e["file"])
        tag = key
        if not os.path.exists(path):
            errors.append(f"{tag}: missing file")
            continue
        x, sr = io.read(path)
        loaded[key] = x
        r = {"durationS": round(x.shape[0] / sr, 3)}
        if sr != SR or x.ndim != 2 or x.shape[1] != 2:
            errors.append(f"{tag}: expected 48 kHz stereo, got {sr} Hz {x.shape}")
        if x.shape[0] != e["samples"]:
            errors.append(f"{tag}: {x.shape[0]} samples, catalogue says {e['samples']}")
        win = duration_window(key)
        if win and not (win[0] <= x.shape[0] / SR <= win[1]):
            errors.append(f"{tag}: duration {x.shape[0] / SR:.1f}s outside {win}")
        pk, tp, dc = mix.peak_db(x), mix.true_peak_db(x), mix.dc_offset(x)
        lufs = mix.loudness_integrated(x)
        r.update(peakDb=round(pk, 2), truePeakDb=round(tp, 2), dc=round(dc, 6), lufs=round(lufs, 2))
        if pk > -1.0:
            errors.append(f"{tag}: peak {pk:.2f} dBFS > -1.0")
        if tp > -0.5:
            errors.append(f"{tag}: true peak {tp:.2f} dBTP > -0.5")
        if dc > 1e-3:
            errors.append(f"{tag}: DC offset {dc:.4f}")
        if clip_runs(x):
            errors.append(f"{tag}: clipped runs")
        if not np.all(np.isfinite(x)):
            errors.append(f"{tag}: non-finite samples")
        if not (LUFS_WINDOW[0] <= lufs <= LUFS_WINDOW[1]) and not e.get("group"):
            errors.append(f"{tag}: loudness {lufs:.1f} LUFS outside {LUFS_WINDOW}")
        if not e.get("group") and abs(lufs - e["master"]["targetLufs"]) > 1.5:
            errors.append(f"{tag}: loudness {lufs:.1f} vs target {e['master']['targetLufs']}")
        if e["kind"] == "loop":
            sm = mix.seam_metrics(x)
            sc = seam_continuity(x, e)
            r["seam"] = {"jumpRatio": round(sm["jumpRatio"], 3), "hfBurstDb": round(sm["hfBurstDb"], 2), **sc,
                         "firstSampleAbs": round(float(np.max(np.abs(x[0]))), 5)}
            if sm["jumpRatio"] > 1.0:
                errors.append(f"{tag}: seam jump ratio {sm['jumpRatio']:.2f} > 1")
            if sm["hfBurstDb"] > 10.0:
                errors.append(f"{tag}: HF burst at seam {sm['hfBurstDb']:.1f} dB")
            if sc["seamSpectralChangeDb"] > sc["barlineSpectralChangeMaxDb"] + 1.0:
                errors.append(f"{tag}: spectral change across the seam {sc['seamSpectralChangeDb']} dB exceeds every "
                              f"bar line (max {sc['barlineSpectralChangeMaxDb']})")
            if sc["seamLevelChangeDb"] > max(sc["barlineLevelChangeMaxDb"], 1.0) + 1.0:
                errors.append(f"{tag}: level change across the seam {sc['seamLevelChangeDb']} dB exceeds every bar line "
                              f"(max {sc['barlineLevelChangeMaxDb']})")
            if r["seam"]["firstSampleAbs"] > 0.05:
                warnings.append(f"{tag}: loop starts at |x|={r['seam']['firstSampleAbs']}")
            # tempo (rhythmic loops)
            env = analysis.onset_envelope(x)
            bpm = analysis.estimate_tempo(env)
            ratio = bpm / e["bpm"]
            r["tempoEstimateBpm"] = round(bpm, 2)
            # accept the beat or a neighbouring metrical level (half/double, and the dotted level a
            # 3+3+2 accent pattern produces)
            ok = any(abs(ratio - k) < 0.02 * k for k in (0.5, 2.0 / 3.0, 1.0, 1.5, 2.0))
            if not ok:
                (errors if e["state"].startswith("BATTLE") or e["state"] == "LOADING" else warnings).append(
                    f"{tag}: tempo estimate {bpm:.1f} vs declared {e['bpm']}")
        else:
            lead = int(round(e["stinger"]["leadS"] * SR))
            head = float(np.max(np.abs(x[: max(1, lead - int(0.002 * SR))])))
            tail = mix.rms_db(x[-int(0.05 * SR) :])
            r["startAbs"], r["endRmsDb"] = round(head, 5), round(tail, 1)
            if head > 1e-3:
                errors.append(f"{tag}: stinger lead-in is not silent (|x|={head:.4f})")
            if tail > -60:
                errors.append(f"{tag}: stinger tail not decayed ({tail:.1f} dBFS)")
        # tonality: the declared key (or its relative / modal equivalent) must rank in the top 3 of the
        # 24 Krumhansl-Kessler key profiles, or the declared mode's pitch set must be the best match
        ch = analysis.chroma(x)
        tonic, scale = MODE_OF.get(e["key"], ("D", "aeolian"))
        inr, same = in_scale_ratio(ch, tonic, scale)
        ke = analysis.estimate_key(ch)
        ranked = sorted(ke["scores"], key=ke["scores"].get, reverse=True)
        accept = ACCEPT_KEYS.get(scale, {"D minor", "F major"})
        rank = min((ranked.index(k) + 1 for k in accept), default=99)
        bass_pc = int(np.argmax(analysis.chroma(x, fmin=30.0, fmax=140.0)))
        r["tonality"] = {"inScaleEnergy": round(inr, 3), "pitchSetMatches": same, "krumhansl": ke["key"],
                         "r": ke["r"], "declaredRank": rank, "bassPc": analysis.PC_NAMES[bass_pc]}
        bass_ok = bass_pc == pc_of(tonic) and rank <= 6  # open/suspended harmony: the bass carries the centre
        if rank > 3 and not same and not bass_ok:
            errors.append(f"{tag}: key {e['key']} not supported by the audio (K-K rank {rank}, best {ke['key']})")
        elif rank > 3:
            warnings.append(f"{tag}: K-K key rank {rank} for {e['key']} (pitch set matches)")
        # motif (stems: checked once on the group's full mix below)
        if not e.get("group"):
            if not e["motif"]:
                errors.append(f"{tag}: no motif statement")
            mc = motif_check(x, e)
            if mc["rate"] is not None and mc["rate"] < 0.6:
                warnings.append(f"{tag}: motif tonic/fifth visible in only {mc['rate']:.0%} of statement windows")
        else:
            mc = {"checked": 0, "hits": 0, "rate": None, "note": "see group"}
        r["motifAudio"] = mc
        report[key] = r

    # ------------------------------------------------------------------ stem groups
    groups = {}
    for gname, g in cat.get("groups", {}).items():
        stems = [loaded[k] for k in g["stems"] if k in loaded]
        if len(stems) != len(g["stems"]):
            errors.append(f"group {gname}: missing stems")
            continue
        lens = {s.shape[0] for s in stems}
        offs = {cues[k]["loop"]["gridOffsetSamples"] for k in g["stems"]}
        grp = {"lengths": sorted(lens), "gridOffsets": sorted(offs)}
        if len(lens) != 1:
            errors.append(f"group {gname}: stem lengths differ {sorted(lens)}")
        if len(offs) != 1:
            errors.append(f"group {gname}: grid offsets differ {sorted(offs)}")
        bars = g["bars"]
        spb = cues[g["stems"][0]]["samplesPerBeat"]
        if abs(stems[0].shape[0] - bars * 4 * spb) > 0.5:
            errors.append(f"group {gname}: length {stems[0].shape[0]} != {bars} bars x {spb * 4} samples")
        off = next(iter(offs))
        sixteenth = spb / 4
        hop = 120

        def wrap(v):
            return (v + sixteenth / 2) % sixteenth - sixteenth / 2

        # calibrate the detector: a synthetic click train placed exactly on the declared grid
        rng = np.random.default_rng(1)
        clicks = np.zeros((stems[0].shape[0], 2))
        burst = rng.standard_normal(240) * np.exp(-np.linspace(0, 6, 240))
        for pos in np.arange(off, clicks.shape[0] - 240, sixteenth).astype(int):
            clicks[pos : pos + 240] += burst[:, None] * 0.3
        ph_ref, _ = analysis.grid_phase(analysis.onset_envelope(clicks, hop=hop), sixteenth, hop, 1024)
        bias = wrap(ph_ref - off % sixteenth)
        grp["detectorBiasSamples"] = round(float(bias), 1)
        envs = [analysis.onset_envelope(s, hop=hop) for s in stems]
        phases = {}
        for k, env in zip(g["stems"], envs):
            ph, conc = analysis.grid_phase(env, sixteenth, hop, 1024)
            err = wrap(ph - off % sixteenth - bias)
            phases[k] = {"phaseSamples": round(ph, 1), "errorSamples": round(float(err), 1), "concentration": round(conc, 3)}
            # tolerance 10 ms: bowed/blown attacks speak a few ms after a click, humanisation is ~4 ms RMS
            if abs(err) > 0.010 * SR:
                errors.append(f"group {gname}: {k} onsets off the declared grid by {err:.0f} samples")
        spread = max(p["errorSamples"] for p in phases.values()) - min(p["errorSamples"] for p in phases.values())
        grp["gridPhaseSpreadSamples"] = round(float(spread), 1)
        if spread > 2 * hop + 1:  # stems must agree with each other to within two 2.5 ms bins
            errors.append(f"group {gname}: stems disagree on the grid phase by {spread:.0f} samples")
        grp["gridPhase"] = phases
        lags = {}
        for i in range(len(envs)):
            for j in range(i + 1, len(envs)):
                a, b = envs[i] - envs[i].mean(), envs[j] - envs[j].mean()
                w = int(0.05 * SR / hop)
                cc = [float(np.dot(a[w : -w], np.roll(b, L)[w : -w])) for L in range(-w, w + 1)]
                lag = (int(np.argmax(cc)) - w) * hop
                lags[f"{g['stems'][i]}~{g['stems'][j]}"] = lag
                if abs(lag) > hop:
                    errors.append(f"group {gname}: onset cross-correlation lag {lag} samples between {g['stems'][i]} and {g['stems'][j]}")
        grp["onsetLagSamples"] = lags
        total = sum(stems)
        statements = [st for k in g["stems"] for st in cues[k]["motif"]]
        if not statements:
            errors.append(f"group {gname}: no motif statement in any stem")
        grp["motifAudio"] = motif_check(total, dict(cues[g["stems"][0]], motif=statements))
        if grp["motifAudio"]["rate"] is not None and grp["motifAudio"]["rate"] < 0.6:
            warnings.append(f"group {gname}: motif tonic/fifth visible in only {grp['motifAudio']['rate']:.0%} of windows")
        grp["sumPeakDb"] = round(mix.peak_db(total), 2)
        grp["sumLufs"] = round(mix.loudness_integrated(total), 2)
        grp["stemLufs"] = {k: report[k]["lufs"] for k in g["stems"]}
        tgt = cues[g["stems"][0]]["master"]["targetLufs"]
        if grp["sumPeakDb"] > -0.5:
            errors.append(f"group {gname}: summed stems peak {grp['sumPeakDb']} dBFS")
        if abs(grp["sumLufs"] - tgt) > 1.0:
            errors.append(f"group {gname}: summed loudness {grp['sumLufs']} vs target {tgt}")
        sm = mix.seam_metrics(total)
        grp["sumSeamJumpRatio"] = round(sm["jumpRatio"], 3)
        if sm["jumpRatio"] > 1.0:
            errors.append(f"group {gname}: summed seam jump {sm['jumpRatio']:.2f}")
        # partial layer combinations must also be seamless and clean
        for combo in (stems[:1], stems[:2]):
            pk = mix.peak_db(sum(combo))
            if pk > -1.0:
                errors.append(f"group {gname}: {len(combo)}-layer mix peaks at {pk:.2f}")
        groups[gname] = grp

    # ------------------------------------------------------------------ banks
    banks = {}
    for name, b in cat.get("banks", {}).items():
        bx, _ = io.read(os.path.join(MUSIC, b["file"]))
        worst = 1.0
        for key in b["contents"]:
            reg = cues[key]["bankRegion"]
            a, z = int(round(reg["startS"] * SR)), int(round(reg["endS"] * SR))
            seg, ref = bx[a:z], loaded[key]
            m = min(seg.shape[0], ref.shape[0])
            k = int(0.01 * SR)
            ea = np.convolve(np.abs(seg[:m].mean(axis=1)), np.ones(k) / k, "same")
            eb = np.convolve(np.abs(ref[:m].mean(axis=1)), np.ones(k) / k, "same")
            corr = float(np.corrcoef(ea, eb)[0, 1])
            worst = min(worst, corr)
            if corr < 0.98 or abs(seg.shape[0] - ref.shape[0]) > 2:
                errors.append(f"bank {name}: region {key} differs from its file (corr {corr:.3f})")
        if mix.peak_db(bx) > -1.0:
            errors.append(f"bank {name}: peak {mix.peak_db(bx):.2f}")
        banks[name] = {"durationS": round(bx.shape[0] / SR, 2), "minEnvelopeCorr": round(worst, 4), "contents": b["contents"]}

    # ------------------------------------------------------------------ determinism
    det = None
    if not args.no_determinism:
        import generate_music as gen

        with tempfile.TemporaryDirectory() as tmp:
            masters = gen.MASTERS
            gen.MASTERS = tmp
            try:
                ent = gen.render_job("draw", tmp)
            finally:
                gen.MASTERS = masters
            a = open(os.path.join(tmp, ent[0]["file"]), "rb").read()
            b = open(os.path.join(MUSIC, ent[0]["file"]), "rb").read()
            det = hashlib.sha256(a).hexdigest() == hashlib.sha256(b).hexdigest()
            if not det:
                errors.append("draw: re-render is not byte-identical")

    summary = {
        "cues": len(cues), "errors": errors, "warnings": warnings,
        "maxPeakDb": max(r["peakDb"] for r in report.values()),
        "maxTruePeakDb": max(r["truePeakDb"] for r in report.values()),
        "maxSeamJumpRatio": max((r["seam"]["jumpRatio"] for r in report.values() if "seam" in r), default=None),
        "groups": groups, "banks": banks, "determinism": det, "files": report,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "music_validation.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)
    if not args.no_sheets:
        render_sheets(cat, loaded)

    print(f"cues {len(cues)}  max peak {summary['maxPeakDb']} dBFS  max true peak {summary['maxTruePeakDb']} dBTP  "
          f"max seam jump {summary['maxSeamJumpRatio']}")
    for k, r in report.items():
        s = r.get("seam", {})
        extra = (f" seam {s['jumpRatio']:.2f} spec {s['seamSpectralChangeDb']}/{s['barlineSpectralChangeMaxDb']} "
                 f"lvl {s['seamLevelChangeDb']}/{s['barlineLevelChangeMaxDb']} tempo {r['tempoEstimateBpm']}") if s else \
            f" start {r['startAbs']} end {r['endRmsDb']} dB"
        print(f"  {k:22s} {r['durationS']:7.2f}s {r['lufs']:6.1f} LUFS pk {r['peakDb']:6.2f} tp {r['truePeakDb']:6.2f} "
              f"key#{r['tonality']['declaredRank']} ({r['tonality']['krumhansl']}, bass {r['tonality']['bassPc']}) "
              f"motif {r['motifAudio']['hits']}/{r['motifAudio']['checked']}{extra}")
    for gname, g in groups.items():
        print(f"group {gname}: lengths {g['lengths']} offsets {g['gridOffsets']} sum {g['sumLufs']} LUFS pk {g['sumPeakDb']} "
              f"lags {g['onsetLagSamples']} motif {g['motifAudio']['hits']}/{g['motifAudio']['checked']}")
        for k, p in g["gridPhase"].items():
            print(f"    {k:14s} grid phase err {p['errorSamples']:+.0f} samples after detector bias "
                  f"{g['detectorBiasSamples']:+.0f} (conc {p['concentration']})")
    for name, b in banks.items():
        print(f"bank {name}: {b['durationS']} s, {len(b['contents'])} stingers, min corr {b['minEnvelopeCorr']}")
    print(f"determinism: {det}")
    print(f"{len(errors)} errors, {len(warnings)} warnings")
    for e_ in errors:
        print("  ERROR", e_)
    for w in warnings:
        print("  warn ", w)
    return 1 if errors else 0


# --------------------------------------------------------------------------- review sheets
def _bars(x: np.ndarray, e: dict, b0: int, nb: int) -> np.ndarray:
    off = e["loop"]["gridOffsetSamples"] if "loop" in e else int(round(e["stinger"]["leadS"] * SR))
    s = off + int(round((b0 - 1) * e["barS"] * SR))
    n = int(round(nb * e["barS"] * SR))
    idx = np.arange(s, s + n)
    return x[idx % x.shape[0]] if e["kind"] == "loop" else x[idx[idx < x.shape[0]]]


def render_sheets(cat: dict, loaded: dict) -> None:
    cues = cat["cues"]
    rp = analysis.render_panels
    os.makedirs(OUT, exist_ok=True)
    loops = [k for k in ("main_theme", "garage_theme", "loading_theme", "battle_endgame", "results_theme") if k in loaded]
    rp([(f"{k}  ({cues[k]['bpm']:g} BPM {cues[k]['meter']}, {cues[k]['key']})", loaded[k]) for k in loops],
       os.path.join(OUT, "music_themes.png"), width=1500, spec_h=170, wave_h=34, title="Music loops - full length")
    g = cat["groups"].get("battle")
    if g:
        stems = [loaded[k] for k in g["stems"]]
        items = [(k, x) for k, x in zip(g["stems"], stems)] + [("base+mid", stems[0] + stems[1]),
                                                                  ("base+mid+high (full)", sum(stems))]
        rp(items, os.path.join(OUT, "music_battle_stems.png"), width=1500, spec_h=150, wave_h=34,
           title="Battle stems (80 s, 40 bars @120 BPM) and their sums")
        e0 = cues[g["stems"][0]]
        zoom = [(f"{k} bars 17-18", _bars(x, e0, 17, 2)) for k, x in zip(g["stems"], stems)] + \
            [("full bars 17-18", _bars(sum(stems), e0, 17, 2))]
        rp(zoom, os.path.join(OUT, "music_battle_grid.png"), width=1500, spec_h=150, wave_h=40,
           title="Battle stems zoomed to 2 bars (ticks 0.5 s = 1 beat): onsets line up across stems")
    rp([(k, loaded[k]) for k in ("victory", "defeat", "draw") if k in loaded], os.path.join(OUT, "music_stingers.png"),
       width=1500, spec_h=170, wave_h=34, title="Result stingers")
    maps = sorted(k for k in loaded if k.startswith("map_"))
    rp([(f"{k} ({cues[k]['key']}, {cues[k]['meter']})", loaded[k]) for k in maps], os.path.join(OUT, "music_maps.png"),
       width=820, spec_h=170, wave_h=34, columns=2, duration=20.0, title="Map identity stingers")
    seams = []
    for k, e in cues.items():
        if e["kind"] == "loop" and k in loaded:
            x = loaded[k]
            seams.append((f"{k}: last 1 s | first 1 s (seam at centre)", np.concatenate([x[-SR:], x[:SR]])))
    rp(seams, os.path.join(OUT, "music_seams.png"), width=820, spec_h=130, wave_h=40, columns=2, title="Loop seams")
    # motif statements on a semitone axis (D and A rows marked)
    picks = [("main_theme", 5, 2), ("main_theme", 13, 2), ("garage_theme", 5, 2), ("battle_high", 17, 2),
             ("battle_endgame", 25, 4), ("victory", 2, 2), ("defeat", 1, 2), ("map_dust_basin", 1, 2)]
    items = []
    for k, b0, nb in picks:
        if k in loaded:
            e = cues[k]
            items.append((f"{k} bars {b0}-{b0 + nb - 1}", _bars(loaded[k], e, b0, nb), (0.0, e["beatS"])))
    analysis.render_pitch_panels(items, os.path.join(OUT, "music_motif_pitch.png"), width=1200, lo_midi=45, hi_midi=93,
                                 row_h=4, title="The HULLDOWN motif (D D A Bb G A) on a semitone axis - D rows gold, A rows blue")


if __name__ == "__main__":
    raise SystemExit(main())
