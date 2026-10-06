#!/usr/bin/env python3
"""HULLDOWN audio QA: independent, objective checks of every delivered audio file.

This is the CI gate for ``assets/audio`` (SFX) and ``assets/music`` (score). It deliberately does
**not** import the generator's DSP library (``tools/audio/synth``): every measurement here (sample
and true peak, DC, BS.1770 loudness, seam and click detectors, spectral features) is implemented
locally, so a bug shared by the generator and its own validators cannot hide a failure.

Checks (``ERROR`` fails the run, ``WARN`` is reported; ``--strict`` fails on warnings too):

catalog     both catalogues parse with no duplicate JSON keys; keys are snake_case and unique
            across SFX and music; every listed file exists, is OGG Vorbis at 44.1/48 kHz, decodes,
            and matches its declared channels and duration (music loops: exact sample count); file
            names follow ``<key>[_<variant>].ogg``; no file is listed twice; no orphan .ogg files;
            the catalogue's own peak/loudness figures are not stale
channels    positional (3D) sounds are mono; UI / Voice / Music and ambience beds are stereo; no
            dead channel; no anti-phase stereo (mono-downmix safety)
signal      sample peak <= -1 dBFS; true peak <= -0.5 dBTP (warn); |DC| <= 0.01 (warn > 0.001);
            no NaN/Inf; not silent; no clipped runs; one-shots: <= 30 ms leading silence (-60 dBFS),
            no hard start, no truncated tail; lengths inside the brief's windows
loops       seam: sample step and slope change vs the local signal motion, HF burst at the seam vs
            its +-100 ms neighbourhood, level continuity; starts near a zero crossing; music loops
            hold whole bars; battle stems share sample length, grid and sum under the ceiling
clicks      every file (loops scanned circularly, across the seam): truncation clicks - a smooth,
            sustained oscillation cut off mid-cycle (designed impulsive textures are not flagged;
            the count of raw isolated steps is kept in the JSON for reference)
loudness    per-bus spread (approx. LUFS: momentary-max for one-shots, integrated for loops, and
            "effective" = LUFS + 20log10(suggested volume)); robust outliers; variants of a key
            within 3 dB of each other; music within 1 dB of its target
distinct    armor results (penetration / ricochet / blocked / critical, every variant): spectral
            centroid, phone-speaker centroid, flatness, attack / decay shape, log-mel and envelope
            distances; every class pair must differ clearly and every variant must classify to
            its own class (leave-one-out nearest neighbour)
coverage    every key, category, engine family layer, track surface, gun distance band, radio
            command, biome bed / spot (with variant counts), music cue and director state named in
            docs/design/audio.md exists, and every catalogue key is listed in the document
uploads     bank regions lie inside their bank, do not overlap and match the standalone length;
            bank gaps are silent; total uploads <= 100 (unverified-account quota); file size and
            length within Roblox upload limits

Contact sheets (``--sheets``, default on) are written to ``build/audio_review/qa_*.png``: one or more
pages per SFX category, the music cues, every loop seam zoomed, and the armor-result comparison.

    python3 tools/audio/qa_audio.py                # all checks + sheets, report -> build/audio_review/qa_report.json
    python3 tools/audio/qa_audio.py --no-sheets    # CI: checks only
    python3 tools/audio/qa_audio.py --strict       # warnings also fail
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import math
import os
import re
import sys
import time
from collections import defaultdict

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt, stft

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SFX_ROOT = os.path.join(REPO, "assets", "audio")
MUSIC_ROOT = os.path.join(REPO, "assets", "music")
DOC = os.path.join(REPO, "docs", "design", "audio.md")
OUT = os.path.join(REPO, "build", "audio_review")

# ----------------------------------------------------------------------------- policy (from the brief)
PEAK_MAX_DB = -1.0
TRUE_PEAK_WARN_DB = -0.5
DC_ERROR = 0.01
DC_WARN = 0.001
SILENT_DB = -60.0  # a file whose peak is below this is "silent"
LEAD_SILENCE_DB = -60.0  # leading samples below this count as silence
LEAD_SILENCE_MAX_S = 0.030
SAMPLE_RATES = (44100, 48000)
ONESHOT_MAX_S = {"ui": 3.5, "cues": 3.5, "radio": 2.5, "default": 10.0}
LOOP_WINDOWS_S = {"bed": (20.0, 60.0), "default": (2.0, 8.0)}  # beds = ambience/weather/hangar loops
BED_CATEGORIES = {"ambience", "weather", "hangar"}
MUSIC_LOOP_S = (60.0, 150.0)
MUSIC_STINGER_S = (5.0, 40.0)
UPLOAD_QUOTA = 100  # Roblox audio uploads per 30 days, unverified account (research 08)
UPLOAD_MAX_BYTES = 20 * 1024 * 1024
UPLOAD_MAX_S = 420.0
KEY_RE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
ARMOR_CLASSES = ("armor_penetration", "armor_ricochet", "armor_blocked", "armor_critical")


# ============================================================================= report
class Report:
    def __init__(self) -> None:
        self.items: list[dict] = []
        self.metrics: dict = {}

    def add(self, sev: str, check: str, subject: str, msg: str) -> None:
        self.items.append({"severity": sev, "check": check, "subject": subject, "message": msg})

    def err(self, check, subject, msg):
        self.add("ERROR", check, subject, msg)

    def warn(self, check, subject, msg):
        self.add("WARN", check, subject, msg)

    def count(self, sev: str, check: str | None = None) -> int:
        return sum(1 for i in self.items if i["severity"] == sev and (check is None or i["check"] == check))


def load_json_strict(path: str, rep: Report, label: str) -> dict:
    """json.load that reports duplicate object keys (json silently keeps the last one)."""

    def hook(pairs):
        seen = {}
        for k, v in pairs:
            if k in seen:
                rep.err("catalog", label, f"duplicate JSON key {k!r}")
            seen[k] = v
        return seen

    with open(path, encoding="utf-8") as fh:
        return json.load(fh, object_pairs_hook=hook)


# ============================================================================= measurement (independent)
def mono(x: np.ndarray) -> np.ndarray:
    return x if x.ndim == 1 else x.mean(axis=1)


def db(v: float, floor: float = 1e-12) -> float:
    return 20.0 * math.log10(max(float(v), floor))


def pdb(p: float, floor: float = 1e-20) -> float:
    return 10.0 * math.log10(max(float(p), floor))


def true_peak(x: np.ndarray, chunk: int = 1 << 18) -> float:
    """Inter-sample peak via 4x polyphase oversampling, processed in overlapping chunks."""
    pk = 0.0
    n = x.shape[0]
    pad = 64
    for s in range(0, n, chunk):
        a, b = max(0, s - pad), min(n, s + chunk + pad)
        up = resample_poly(x[a:b], 4, 1, axis=0)
        lo = (s - a) * 4
        hi = up.shape[0] - (b - min(n, s + chunk)) * 4
        pk = max(pk, float(np.max(np.abs(up[lo:hi]))) if hi > lo else 0.0)
    return pk


def _k_sos(sr: int) -> np.ndarray:
    """ITU-R BS.1770-4 K-weighting (high-shelf pre-filter + RLB high-pass) for any sample rate."""
    f0, gain, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    k = math.tan(math.pi * f0 / sr)
    vh = 10 ** (gain / 20)
    vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    s1 = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0,
          1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    f0, q = 38.13547087602444, 0.5003270373238773
    k = math.tan(math.pi * f0 / sr)
    a0 = 1 + k / q + k * k
    s2 = [1.0, -2.0, 1.0, 1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    return np.array([s1, s2])


def _blocks(x: np.ndarray, sr: int, win_s: float, hop_s: float, circular: bool) -> np.ndarray:
    y = sosfilt(_k_sos(sr), x, axis=0)
    p = y * y if y.ndim == 1 else (y * y).sum(axis=1)  # channel weights 1.0 (L/R/C)
    w = int(round(win_s * sr))
    h = max(1, int(round(hop_s * sr)))
    if circular:
        p = np.concatenate([p, p[: w - 1]])
    elif p.shape[0] < w:
        p = np.concatenate([p, np.zeros(w - p.shape[0])])
    c = np.concatenate([[0.0], np.cumsum(p)])
    starts = np.arange(0, p.shape[0] - w + 1, h)
    return (c[starts + w] - c[starts]) / w


def lufs_integrated(x: np.ndarray, sr: int, circular: bool = False) -> float:
    blk = _blocks(x, sr, 0.4, 0.1, circular)
    lk = -0.691 + 10 * np.log10(np.maximum(blk, 1e-20))
    blk = blk[lk > -70]
    if not blk.size:
        return -70.0
    rel = -0.691 + 10 * math.log10(blk.mean()) - 10
    blk = blk[-0.691 + 10 * np.log10(blk) > rel]
    return -0.691 + 10 * math.log10(blk.mean()) if blk.size else -70.0


def lufs_momentary_max(x: np.ndarray, sr: int) -> float:
    blk = _blocks(x, sr, 0.4, 0.01, False)
    return -0.691 + 10 * math.log10(max(float(blk.max()), 1e-20))


def leading_silence_s(x: np.ndarray, sr: int, thr_db: float = LEAD_SILENCE_DB) -> float:
    a = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=1)
    above = np.flatnonzero(a > 10 ** (thr_db / 20))
    return (above[0] if above.size else a.size) / sr


def step_clicks(m: np.ndarray, sr: int, circular: bool, k: float = 14.0, abs_min: float = 0.004,
                iso_ms: float = 4.0) -> list[dict]:
    """Isolated step discontinuities (clicks): a single sample-to-sample step that is ``k`` times
    larger than the signal's own motion just before *and* just after it, with no comparable step
    within +-``iso_ms`` (so periodic waveforms, drum attacks and ringing transients are not
    flagged). Returns [{t, step, ratio}] for the worst few."""
    n = m.shape[0]
    pad = int(0.01 * sr)
    if circular:
        xx = np.concatenate([m[-pad:], m, m[:pad]])
    else:
        xx = np.concatenate([np.zeros(pad), m, np.zeros(pad)])
    d = np.abs(np.diff(xx))
    b = max(8, int(0.001 * sr))  # 1 ms blocks
    nb = d.shape[0] // b
    blk = d[: nb * b].reshape(nb, b)
    bmax = blk.max(axis=1)
    bmed = np.median(blk, axis=1)
    pre = np.maximum.reduce([np.roll(bmed, s) for s in (1, 2, 3)])  # loudest local motion before
    post = np.maximum.reduce([np.roll(bmed, -s) for s in (1, 2, 3)])
    ref = np.maximum(np.maximum(pre, post), 2e-5)
    cand = np.flatnonzero((bmax > k * ref) & (bmax > abs_min))
    out = []
    iso = int(iso_ms * 0.001 * sr)
    guard = max(2, int(0.0004 * sr))
    for c in cand:
        if c < 3 or c > nb - 4:
            continue
        i = c * b + int(np.argmax(blk[c]))
        step = d[i]
        lo, hi = max(0, i - iso), min(d.shape[0], i + iso)
        win = d[lo:hi].copy()
        win[max(0, i - guard - lo) : i + guard + 1 - lo] = 0.0
        if win.size and win.max() > 0.5 * step:
            continue  # periodic or ringing: part of the sound
        t = (i - pad + 1) / sr
        if circular:
            t %= n / sr
        out.append({"t": round(t, 4), "step": round(float(step), 4), "ratio": round(float(step / ref[c]), 1)})
    out.sort(key=lambda r: -r["ratio"])
    return out[:5]


def abrupt_stops(c: np.ndarray, sr: int, circular: bool, abs_min: float = 0.003) -> list[dict]:
    """Truncated oscillations: a smooth, sustained (tonal) waveform that snaps to near-silence in one
    sample - the click left by a voice or layer whose envelope ends at non-zero amplitude.

    A step is flagged when, over the 3 ms before it, the signal is a sustained (RMS >= 0.4 x peak
    deviation) and smooth (90th pct of |diff| <= 0.15 x peak deviation, i.e. below ~1.5 kHz)
    oscillation, the step is >= 0.4 x that oscillation's amplitude and >= 6x the local motion on
    both sides, and the 3 ms after it are <= 0.35 x as large. Designed impulsive textures (rain,
    grit, knock, drum attacks, bursts of HF ringing) fail the smoothness/sustain tests and pass."""
    n = c.shape[0]
    pad = int(0.01 * sr)
    xx = np.concatenate([c[-pad:], c, c[:pad]]) if circular else np.concatenate([np.zeros(pad), c, np.zeros(pad)])
    d = np.abs(np.diff(xx))
    b = max(8, int(0.001 * sr))
    nb = d.shape[0] // b
    blk = d[: nb * b].reshape(nb, b)
    bmax, bmed = blk.max(axis=1), np.median(blk, axis=1)
    pre = np.maximum.reduce([np.roll(bmed, s) for s in (1, 2, 3)])
    post = np.maximum.reduce([np.roll(bmed, -s) for s in (1, 2, 3)])
    cand = np.flatnonzero((bmax > 6 * np.maximum(post, 2e-5)) & (bmax > 6 * np.maximum(pre, 2e-5)) & (bmax > abs_min))
    w = int(0.003 * sr)
    out, seen = [], set()
    for cb in cand:
        if cb < 4 or cb > nb - 5:
            continue
        i = cb * b + int(np.argmax(blk[cb]))
        pr, po = xx[i - w : i + 1], xx[i + 1 : i + 1 + w]
        pre_a = float(np.max(np.abs(pr - pr.mean())))
        po_a = float(np.max(np.abs(po - po.mean())))
        smooth = float(np.percentile(np.abs(np.diff(pr[:-1])), 90))
        sustain = float(np.sqrt(np.mean((pr - pr.mean()) ** 2)))
        if pre_a > 0 and po_a <= 0.35 * pre_a and d[i] >= 0.4 * pre_a and smooth <= 0.15 * pre_a and sustain >= 0.4 * pre_a:
            t = (i - pad + 1) / sr
            if circular:
                t %= n / sr
            if round(t, 3) in seen:
                continue
            seen.add(round(t, 3))
            out.append({"t": round(t, 4), "step": round(float(d[i]), 4), "amp": round(pre_a, 4), "after": round(po_a, 4)})
    return out


def seam_report(x: np.ndarray, sr: int) -> dict:
    """Seam quality of a loop (the boundary between the last and the first sample).

    * jumpLocal  - |x[0]-x[-1]| / 99th pct of |diff| within +-20 ms of the seam (per channel, max)
    * slopeLocal - largest 2nd difference across the seam / 99th pct of |2nd diff| within +-20 ms
    * hfDb       - 2nd-difference (HF) energy in the 2 ms around the seam relative to the loudest
                   2 ms window elsewhere within +-100 ms (a click stands out above its neighbours)
    * levelDb    - |RMS(first 50 ms) - RMS(last 50 ms)| and (levelRefDb) the largest such change at
                   any other point of the loop (10 ms hop); silence is floored at LEVEL_FLOOR_DB
    """
    xs = x[:, None] if x.ndim == 1 else x
    n = xs.shape[0]
    w20 = int(0.02 * sr)
    jl, sl = 0.0, 0.0
    for ch in range(xs.shape[1]):
        c = xs[:, ch]
        ring = np.concatenate([c[-w20:], c[:w20]])  # seam between index w20-1 and w20
        d = np.abs(np.diff(ring))
        d_ex = np.delete(d, [w20 - 1])
        jl = max(jl, d[w20 - 1] / max(np.percentile(d_ex, 99), 1e-6))
        d2 = np.abs(np.diff(ring, 2))
        d2_ex = np.delete(d2, [w20 - 2, w20 - 1])
        sl = max(sl, max(d2[w20 - 2], d2[w20 - 1]) / max(np.percentile(d2_ex, 99), 1e-6))
    m = mono(x)
    w100 = int(0.1 * sr)
    ring = np.concatenate([m[-w100:], m[:w100]])
    e = np.diff(ring, 2) ** 2
    bw = int(0.002 * sr)
    nb = e.shape[0] // bw
    eb = e[: nb * bw].reshape(nb, bw).sum(axis=1)
    centre = (w100 - 1) // bw
    seam_e = eb[max(0, centre - 1) : centre + 2].max()
    others = np.concatenate([eb[: max(0, centre - 2)], eb[centre + 3 :]])
    hf = pdb(seam_e) - pdb(others.max() if others.size else seam_e)
    w50 = int(0.05 * sr)
    lvl = level_change(m, 0, w50)
    # reference: the largest before/after change anywhere else in the loop (10 ms hop, so every onset
    # of a pulsed or rhythmic loop is caught whatever its alignment)
    c = np.concatenate([[0.0], np.cumsum(np.concatenate([m, m[:w50]]) ** 2)])
    pos = np.arange(w50, n, int(0.01 * sr))
    pos = pos[(pos > w50) & (pos < n - w50)]
    before = np.maximum(10 * np.log10((c[pos] - c[pos - w50]) / w50 + 1e-20), LEVEL_FLOOR_DB)
    after = np.maximum(10 * np.log10((c[pos + w50] - c[pos]) / w50 + 1e-20), LEVEL_FLOOR_DB)
    ref = float(np.max(np.abs(after - before))) if pos.size else 0.0
    return {"jumpLocal": round(float(jl), 2), "slopeLocal": round(float(sl), 2), "hfDb": round(float(hf), 1),
            "levelDb": round(float(lvl), 2), "levelRefDb": round(ref, 2), "firstAbs": round(float(np.max(np.abs(xs[0]))), 4)}


LEVEL_FLOOR_DB = -70.0  # RMS below this counts as silence for level-continuity checks


def level_change(m: np.ndarray, pos: int, w: int) -> float:
    """|RMS of the ``w`` samples after ``pos`` - RMS of the ``w`` before| in dB (loop indices wrap;
    silence floored at LEVEL_FLOOR_DB so a gap in a pulsed cue is not an "infinite" jump)."""
    n = m.shape[0]
    a = m[np.arange(pos - w, pos) % n]
    b = m[np.arange(pos, pos + w) % n]
    return abs(max(pdb(np.mean(b ** 2)), LEVEL_FLOOR_DB) - max(pdb(np.mean(a ** 2)), LEVEL_FLOOR_DB))


def stereo_report(x: np.ndarray, sr: int) -> dict:
    l, r = x[:, 0], x[:, 1]
    sl, sr_ = float(np.std(l)), float(np.std(r))
    corr = float(np.corrcoef(l, r)[0, 1]) if sl > 1e-9 and sr_ > 1e-9 else 1.0
    sos = butter(4, 150.0, "low", fs=sr, output="sos")
    lo = sosfilt(sos, x[: min(x.shape[0], 30 * sr)], axis=0)
    a, b = lo[:, 0], lo[:, 1]
    lcorr = float(np.corrcoef(a, b)[0, 1]) if np.std(a) > 1e-7 and np.std(b) > 1e-7 else 1.0
    st = (np.mean(l ** 2) + np.mean(r ** 2)) / 2
    mo = np.mean(((l + r) / 2) ** 2)
    return {"corr": round(corr, 3), "lowCorr": round(lcorr, 3), "monoLossDb": round(pdb(mo) - pdb(st), 2),
            "chPeakDb": [round(db(np.max(np.abs(l))), 1), round(db(np.max(np.abs(r))), 1)]}


# ----------------------------------------------------------------------------- spectral features
def _mel_edges(bands: int = 40, lo: float = 40.0, hi: float = 16000.0) -> np.ndarray:
    mel = lambda f: 2595 * np.log10(1 + f / 700.0)  # noqa: E731
    e = np.linspace(mel(lo), mel(hi), bands + 1)
    return 700 * (10 ** (e / 2595) - 1)


def logmel(m: np.ndarray, sr: int, bands: int = 40) -> np.ndarray:
    f, _, z = stft(m, sr, nperseg=2048, noverlap=1536)
    p = np.abs(z) ** 2
    e = _mel_edges(bands)
    prof = np.array([p[(f >= a) & (f < b)].mean() if np.any((f >= a) & (f < b)) else 1e-20 for a, b in zip(e[:-1], e[1:])])
    return 10 * np.log10(prof + 1e-20)


def envelope_db(m: np.ndarray, sr: int, span_s: float = 1.2, hop_s: float = 0.005) -> np.ndarray:
    h = int(hop_s * sr)
    n = int(span_s * sr)
    mm = np.concatenate([m, np.zeros(max(0, n - m.size))])[:n]
    blk = mm[: (n // h) * h].reshape(-1, h)
    e = 10 * np.log10(np.mean(blk ** 2, axis=1) + 1e-12)
    return np.maximum(e - e.max(), -60.0)


def features(m: np.ndarray, sr: int) -> dict:
    spec = np.abs(np.fft.rfft(m * np.hanning(m.size))) ** 2
    f = np.fft.rfftfreq(m.size, 1 / sr)
    tot = spec.sum() + 1e-20
    cen = float((f * spec).sum() / tot)
    cum = np.cumsum(spec) / tot
    roll = float(f[min(np.searchsorted(cum, 0.85), f.size - 1)])
    band = (f >= 50) & (f <= 16000)
    flat = float(np.exp(np.mean(np.log(spec[band] + 1e-20))) / (np.mean(spec[band]) + 1e-20))
    # "phone speaker": band-limit to 300 Hz - 8 kHz before the centroid
    ph = (f >= 300) & (f <= 8000)
    pcen = float((f[ph] * spec[ph]).sum() / (spec[ph].sum() + 1e-20))
    env = envelope_db(m, sr, span_s=max(1.2, m.size / sr), hop_s=0.002)
    ipk = int(np.argmax(env))
    t_peak = ipk * 0.002
    first10 = int(np.argmax(env > -20.0))
    attack = max(0.0, t_peak - first10 * 0.002)

    def decay_to(level):
        below = np.flatnonzero(env[ipk:] < level)
        # time after the peak until the envelope stays below ``level``
        if not below.size:
            return env.size * 0.002 - t_peak
        above = np.flatnonzero(env[ipk:] >= level)
        return (above[-1] + 1) * 0.002 if above.size else 0.0

    rms = math.sqrt(float(np.mean(m * m)))
    lo = float(spec[f < 250].sum() / tot)
    hi = float(spec[f >= 2500].sum() / tot)
    tc = float((np.arange(env.size) * 0.002 * 10 ** (env / 10)).sum() / (10 ** (env / 10)).sum())
    return {"centroidHz": round(cen, 0), "phoneCentroidHz": round(pcen, 0), "rolloff85Hz": round(roll, 0),
            "flatness": round(flat, 4), "lowShare": round(lo, 3), "highShare": round(hi, 3),
            "attackMs": round(attack * 1000, 1), "decay20S": round(decay_to(-20.0), 3), "decay40S": round(decay_to(-40.0), 3),
            "temporalCentroidS": round(tc, 3), "crestDb": round(db(np.max(np.abs(m))) - db(rms), 1)}


# ============================================================================= loading
class Asset:
    __slots__ = ("lib", "key", "rel", "path", "entry", "variant_idx", "x", "sr", "info", "kind", "category", "bus",
                 "loop", "declared_dur", "declared_ch", "declared_samples", "stats")

    def __init__(self, **kw):
        for k in self.__slots__:
            setattr(self, k, kw.get(k))
        self.stats = {}

    @property
    def tag(self) -> str:
        return f"{self.key} [{self.rel}]"


def collect_assets(sfx: dict, music: dict, rep: Report) -> list[Asset]:
    assets: list[Asset] = []
    seen_files: dict[str, str] = {}
    for key, e in sfx.get("sounds", {}).items():
        files = e.get("variants") or [e["file"]]
        if e.get("variants") and e["file"] != e["variants"][0]:
            rep.err("catalog", key, f"'file' {e['file']} is not variants[0]")
        vstats = {v["file"]: v for v in e.get("variantStats", [])}
        for i, rel in enumerate(files):
            if rel in seen_files and seen_files[rel] != key:
                rep.err("catalog", key, f"file {rel} also listed by {seen_files[rel]}")
            seen_files[rel] = key
            dur = vstats.get(rel, {}).get("durationS", e["durationS"] if i == 0 else None)
            assets.append(Asset(lib="sfx", key=key, rel=rel, path=os.path.join(SFX_ROOT, rel), entry=e, variant_idx=i,
                                kind="loop" if e["loop"] else "oneshot", category=e["category"], bus=e["bus"],
                                loop=bool(e["loop"]), declared_dur=dur, declared_ch=e["channels"]))
    for key, e in music.get("cues", {}).items():
        rel = e["file"]
        if rel in seen_files:
            rep.err("catalog", key, f"file {rel} also listed by {seen_files[rel]}")
        seen_files["music:" + rel] = key
        assets.append(Asset(lib="music", key=key, rel=rel, path=os.path.join(MUSIC_ROOT, rel), entry=e, variant_idx=0,
                            kind=e["kind"], category="music", bus=music.get("bus", "Music"), loop=e["kind"] == "loop",
                            declared_dur=e["durationS"], declared_ch=e.get("channels", music.get("channels")),
                            declared_samples=e.get("samples")))
    return assets


def decode(a: Asset, rep: Report) -> bool:
    if not os.path.exists(a.path):
        rep.err("catalog", a.tag, "file missing")
        return False
    try:
        info = sf.info(a.path)
        x, sr = sf.read(a.path, dtype="float64", always_2d=False)
    except Exception as exc:  # noqa: BLE001
        rep.err("catalog", a.tag, f"does not decode: {exc!r}")
        return False
    a.info, a.x, a.sr = info, x, sr
    return True


# ============================================================================= checks
def check_keys(sfx: dict, music: dict, rep: Report) -> None:
    sk, mk = set(sfx.get("sounds", {})), set(music.get("cues", {}))
    for k in sorted(sk | mk):
        if not KEY_RE.match(k):
            rep.err("catalog", k, "key is not snake_case")
    for k in sorted(sk & mk):
        rep.err("catalog", k, "key used by both the SFX and the music catalogue")
    for k, e in sfx.get("sounds", {}).items():
        files = e.get("variants") or [e["file"]]
        for rel in files:
            base = os.path.basename(rel)
            ok = base == f"{k}.ogg" or re.fullmatch(re.escape(k) + r"_[a-z]\.ogg", base)
            if not ok:
                rep.err("catalog", k, f"file name {base} does not follow <key>[_<variant>].ogg")
            if not rel.startswith(f"{e['category']}/"):
                rep.err("catalog", k, f"file {rel} is not under its category folder {e['category']}/")
    for k, e in music.get("cues", {}).items():
        if os.path.basename(e["file"]) != f"{k}.ogg":
            rep.err("catalog", k, f"file name {e['file']} does not match key")


def check_file(a: Asset, rep: Report, sfx_sr: int) -> None:
    x, sr = a.x, a.sr
    st = a.stats
    ch = 1 if x.ndim == 1 else x.shape[1]
    n = x.shape[0]
    dur = n / sr
    st.update({"durationS": round(dur, 4), "channels": ch, "sampleRate": sr})
    # --- format
    if a.info.format != "OGG" or a.info.subtype != "VORBIS":
        rep.err("catalog", a.tag, f"format {a.info.format}/{a.info.subtype}, expected OGG/VORBIS")
    if sr not in SAMPLE_RATES:
        rep.err("catalog", a.tag, f"sample rate {sr} not 44.1/48 kHz")
    if sr != sfx_sr:
        rep.warn("catalog", a.tag, f"sample rate {sr} differs from the catalogue's {sfx_sr}")
    if ch != a.declared_ch:
        rep.err("catalog", a.tag, f"{ch} channels, catalogue says {a.declared_ch}")
    if a.declared_samples is not None:
        if n != a.declared_samples:
            rep.err("catalog", a.tag, f"{n} samples, catalogue says {a.declared_samples}")
    elif a.declared_dur is not None and abs(dur - a.declared_dur) > 0.002:
        rep.err("catalog", a.tag, f"duration {dur:.4f} s, catalogue says {a.declared_dur}")
    elif a.declared_dur is None:
        rep.warn("catalog", a.tag, "no declared duration for this variant")
    # --- channel policy
    e = a.entry
    positional = a.lib == "sfx" and e["suggested"].get("rollOffMaxStuds") is not None
    if positional and ch != 1:
        rep.err("channels", a.tag, "positional (3D) sound must be mono")
    if a.bus in ("UI", "Voice", "Music") and ch != 2:
        rep.err("channels", a.tag, f"{a.bus} sound must be stereo")
    if a.lib == "sfx" and a.loop and a.category in BED_CATEGORIES and ch != 2:
        rep.err("channels", a.tag, "ambience / weather bed must be stereo")
    # --- signal hygiene
    if not np.all(np.isfinite(x)):
        rep.err("signal", a.tag, "NaN/Inf samples")
        return
    pk = float(np.max(np.abs(x)))
    st["peakDb"] = round(db(pk), 2)
    tp = true_peak(x)
    st["truePeakDb"] = round(db(tp), 2)
    dc = float(np.max(np.abs(x.mean(axis=0))))
    st["dc"] = round(dc, 6)
    if st["peakDb"] > PEAK_MAX_DB:
        rep.err("signal", a.tag, f"sample peak {st['peakDb']:.2f} dBFS > {PEAK_MAX_DB}")
    if st["truePeakDb"] > TRUE_PEAK_WARN_DB:
        rep.warn("signal", a.tag, f"true peak {st['truePeakDb']:.2f} dBTP > {TRUE_PEAK_WARN_DB}")
    if dc > DC_ERROR:
        rep.err("signal", a.tag, f"DC offset {dc:.4f} > {DC_ERROR}")
    elif dc > DC_WARN:
        rep.warn("signal", a.tag, f"DC offset {dc:.4f} > {DC_WARN}")
    if st["peakDb"] < SILENT_DB:
        rep.err("signal", a.tag, f"silent (peak {st['peakDb']:.1f} dBFS)")
    full = (np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=1)) >= 0.999
    if full.any():
        dd = np.diff(np.concatenate([[0], full.astype(np.int8), [0]]))
        runs = int(np.sum((np.flatnonzero(dd == -1) - np.flatnonzero(dd == 1)) >= 3))
        if runs:
            rep.err("signal", a.tag, f"{runs} clipped runs")
    if ch == 2:
        s = stereo_report(x, sr)
        st["stereo"] = s
        if min(s["chPeakDb"]) < SILENT_DB and max(s["chPeakDb"]) > SILENT_DB + 20:
            rep.err("channels", a.tag, f"dead channel (channel peaks {s['chPeakDb']} dBFS)")
        if s["corr"] < -0.1 or s["lowCorr"] < -0.1:
            rep.warn("channels", a.tag, f"anti-phase stereo: L/R correlation {s['corr']}, below 150 Hz {s['lowCorr']} "
                                        f"(mono downmix {s['monoLossDb']} dB)")
    # --- loudness (approximate LUFS)
    if a.loop:
        st["lufs"] = round(lufs_integrated(x, sr, circular=True), 2)
    elif a.lib == "music":
        st["lufs"] = round(lufs_integrated(x, sr), 2)
    else:
        st["lufs"] = round(lufs_momentary_max(x, sr), 2)
    st["rmsDb"] = round(pdb(float(np.mean(x ** 2))), 2)
    # --- length windows
    if a.lib == "sfx":
        if a.loop:
            lo, hi = LOOP_WINDOWS_S["bed" if a.category in BED_CATEGORIES else "default"]
        else:
            lo, hi = 0.02, ONESHOT_MAX_S.get(a.category, ONESHOT_MAX_S["default"])
    else:
        lo, hi = MUSIC_LOOP_S if a.loop else MUSIC_STINGER_S
    if not (lo - 1e-6 <= dur <= hi + 1e-6):
        rep.err("signal", a.tag, f"length {dur:.2f} s outside the {'loop' if a.loop else 'one-shot'} window [{lo:g}, {hi:g}] s")
    # --- one-shot edges
    if not a.loop:
        lead = leading_silence_s(x, sr)
        st["leadingSilenceMs"] = round(lead * 1000, 1)
        lead_allowed = LEAD_SILENCE_MAX_S
        if a.lib == "music":
            lead_allowed = max(LEAD_SILENCE_MAX_S, e.get("stinger", {}).get("leadS", 0.0) + 0.005)
        if lead > lead_allowed:
            rep.err("signal", a.tag, f"leading silence {lead * 1000:.0f} ms (> {lead_allowed * 1000:.0f} ms below "
                                     f"{LEAD_SILENCE_DB:.0f} dBFS)")
        if a.lib == "music" and e.get("stinger", {}).get("leadS"):
            # bar 1 starts at stinger.leadS: nothing (notes, codec pre-echo) may sound before it
            n_lead = max(1, int(round(e["stinger"]["leadS"] * sr)) - int(0.002 * sr))
            head = db(float(np.max(np.abs(x[:n_lead]))))
            st["leadInPeakDb"] = round(head, 1)
            if head > LEAD_SILENCE_DB:
                rep.err("signal", a.tag, f"stinger lead-in (before bar 1 at {e['stinger']['leadS']} s) peaks at "
                                         f"{head:.1f} dBFS (> {LEAD_SILENCE_DB:.0f})")
        first = float(np.max(np.abs(np.atleast_1d(x[0]))))
        st["firstAbs"] = round(first, 4)
        if first > 0.05:
            rep.warn("signal", a.tag, f"hard start: first sample {first:.3f}")
        m = mono(x)
        tail = m[-int(0.01 * sr):]
        tail_rel = pdb(np.mean(tail ** 2)) - db(pk)
        st["tailRelDb"] = round(tail_rel, 1)
        impact_at_end = bool((e.get("meta") or {}).get("impactAtEnd"))
        if tail_rel > -40 and not impact_at_end:
            rep.err("signal", a.tag, f"truncated tail: last 10 ms at {tail_rel:.1f} dB re peak")
        if abs(float(m[-1])) > 0.01:
            rep.warn("signal", a.tag, f"ends on a non-zero sample ({m[-1]:.3f})")


def check_loop(a: Asset, rep: Report) -> None:
    x, sr = a.x, a.sr
    s = seam_report(x, sr)
    a.stats["seam"] = s
    t = a.tag
    if s["jumpLocal"] > 3.0:
        rep.err("loops", t, f"seam step {s['jumpLocal']}x the local sample motion (> 3)")
    if s["slopeLocal"] > 3.0:
        rep.err("loops", t, f"seam slope change {s['slopeLocal']}x the local 2nd-difference motion (> 3)")
    if s["hfDb"] > 6.0:
        rep.err("loops", t, f"click at seam: HF burst {s['hfDb']} dB above the loudest neighbouring 2 ms (> 6)")
    if a.lib == "music":
        # music: the seam is a bar line, so compare it with the cue's own bar lines (accented downbeats)
        e = a.entry
        bar = e["samplesPerBeat"] * e["beatsPerBar"]
        off = e["loop"]["gridOffsetSamples"]
        w50 = int(0.05 * sr)
        m = mono(x)
        bars = [level_change(m, int(round(off + b * bar)), w50) for b in range(1, e["bars"])]
        s["levelRefDb"] = round(max(bars), 2) if bars else 0.0
        s["levelSeamAtBarDb"] = round(level_change(m, off, w50), 2)
        if s["levelSeamAtBarDb"] > s["levelRefDb"] + 1.5:
            rep.warn("loops", t, f"level change at the loop's bar 1 {s['levelSeamAtBarDb']} dB, largest at any other "
                                 f"bar line {s['levelRefDb']} dB")
    elif s["levelDb"] > max(s["levelRefDb"], 1.5) + 1.5:  # seam must not be the loop's biggest level step
        rep.warn("loops", t, f"level jump at seam {s['levelDb']} dB (largest change elsewhere in the loop {s['levelRefDb']} dB)")
    if s["firstAbs"] > 0.05:
        rep.warn("loops", t, f"loop starts at |x|={s['firstAbs']} (not near a zero crossing)")
    # informational: isolated steps include designed impulsive content (knock, grit, rain, drum attacks)
    a.stats["isolatedSteps"] = len(step_clicks(mono(x), sr, circular=True))
    if a.lib == "music":
        e = a.entry
        spb = e["samplesPerBeat"] * e["beatsPerBar"]
        bars = x.shape[0] / spb
        if abs(bars - round(bars)) > 1e-9 or round(bars) != e["bars"]:
            rep.err("loops", t, f"loop is {bars:.4f} bars, catalogue says {e['bars']} whole bars")


def check_clicks(a: Asset, rep: Report) -> None:
    """Truncation clicks anywhere in any file (loops are scanned circularly, across the seam)."""
    xs = a.x[:, None] if a.x.ndim == 1 else a.x
    found = []
    for ch in range(xs.shape[1]):
        for c in abrupt_stops(xs[:, ch], a.sr, circular=a.loop):
            if all(abs(c["t"] - f["t"]) > 0.002 for f in found):
                found.append(c)
    a.stats["clicks"] = found
    for c in found[:6]:
        rep.err("clicks", a.tag,
                f"click: oscillation of amplitude {c['amp']} truncated at {c['t']:.3f} s (step {c['step']}, "
                f"{c['after']} after)")


def check_stems(music: dict, assets: dict[str, Asset], rep: Report) -> dict:
    out = {}
    for g, grp in music.get("groups", {}).items():
        stems = [assets.get(k) for k in grp["stems"]]
        if any(s is None or s.x is None for s in stems):
            rep.err("stems", g, "missing stem")
            continue
        lens = {s.key: s.x.shape[0] for s in stems}
        offs = {s.key: s.entry["loop"]["gridOffsetSamples"] for s in stems}
        srs = {s.key: s.sr for s in stems}
        if len(set(lens.values())) != 1:
            rep.err("stems", g, f"stem lengths differ: {lens}")
        if grp.get("samples") is not None and set(lens.values()) != {grp["samples"]}:
            rep.err("stems", g, f"stem length {lens} != group samples {grp['samples']}")
        if len(set(offs.values())) != 1:
            rep.err("stems", g, f"grid offsets differ: {offs}")
        if len(set(srs.values())) != 1:
            rep.err("stems", g, f"sample rates differ: {srs}")
        n = min(lens.values())
        tot = sum(s.x[:n] for s in stems)
        spk = db(np.max(np.abs(tot)))
        slufs = lufs_integrated(tot, stems[0].sr, circular=True)
        if spk > PEAK_MAX_DB:
            rep.err("stems", g, f"stems summed peak {spk:.2f} dBFS > {PEAK_MAX_DB}")
        tgt = grp.get("targetLufsAllLayers")
        if tgt is not None and abs(slufs - tgt) > 1.0:
            rep.warn("stems", g, f"all layers {slufs:.2f} LUFS vs target {tgt}")
        # cues that declare the same tempo must share the bar length (endgame joins on a bar line)
        bar = stems[0].entry["samplesPerBeat"] * stems[0].entry["beatsPerBar"]
        for k, a in assets.items():
            if a.lib == "music" and a.loop and a.entry.get("bpm") == grp.get("bpm") and k not in grp["stems"]:
                b2 = a.entry["samplesPerBeat"] * a.entry["beatsPerBar"]
                if b2 != bar:
                    rep.err("stems", k, f"bar length {b2} samples != {g} stems' {bar}")
        out[g] = {"lengths": lens, "gridOffsets": offs, "sumPeakDb": round(spk, 2), "sumLufs": round(slufs, 2)}
    return out


def check_catalog_stats(a: Asset, rep: Report) -> None:
    """The catalogue's own measurements must describe the files that are actually there."""
    e, st = a.entry, a.stats
    if a.lib == "sfx":
        vs = {v["file"]: v for v in e.get("variantStats", [])}
        src = vs.get(a.rel) if vs else (e if a.variant_idx == 0 else None)
        if src is None:
            return
        if abs(src["peakDb"] - st["peakDb"]) > 0.5:
            rep.warn("catalog", a.tag, f"catalogue peakDb {src['peakDb']} vs file {st['peakDb']} (stale catalogue?)")
        if abs(src["loudnessLufs"] - st["lufs"]) > 1.0:
            rep.warn("catalog", a.tag, f"catalogue loudnessLufs {src['loudnessLufs']} vs measured {st['lufs']}")
    else:
        if abs(e["peakDb"] - st["peakDb"]) > 0.5:
            rep.warn("catalog", a.tag, f"catalogue peakDb {e['peakDb']} vs file {st['peakDb']} (stale catalogue?)")
        if abs(e["loudnessLufs"] - st["lufs"]) > 1.0:
            rep.warn("catalog", a.tag, f"catalogue loudnessLufs {e['loudnessLufs']} vs measured {st['lufs']}")


def check_orphans(sfx: dict, music: dict, assets: list[Asset], rep: Report) -> None:
    listed = {os.path.normpath(a.path) for a in assets}
    for b in sfx.get("banks", {}).values():
        listed.add(os.path.normpath(os.path.join(SFX_ROOT, b["file"])))
    for b in music.get("banks", {}).values():
        listed.add(os.path.normpath(os.path.join(MUSIC_ROOT, b["file"])))
    for root in (SFX_ROOT, MUSIC_ROOT):
        for dp, _, files in os.walk(root):
            for f in files:
                p = os.path.normpath(os.path.join(dp, f))
                if f.endswith((".ogg", ".wav", ".mp3", ".flac")) and p not in listed:
                    rep.err("catalog", os.path.relpath(p, REPO), "orphan audio file (not in any catalogue)")


# ----------------------------------------------------------------------------- loudness consistency
def check_loudness(assets: list[Asset], rep: Report) -> dict:
    groups: dict[str, list[Asset]] = defaultdict(list)
    for a in assets:
        if "lufs" not in a.stats:
            continue
        kind = "loop" if a.loop else ("stinger" if a.lib == "music" else "shot")
        groups[f"{a.bus}/{kind}"].append(a)
    table = {}
    for g, items in sorted(groups.items()):
        vals = np.array([a.stats["lufs"] for a in items])
        vol = np.array([(a.entry.get("suggested") or {}).get("volume", 1.0) or 1.0 for a in items])
        eff = vals + 20 * np.log10(vol)
        rms = np.array([a.stats["rmsDb"] for a in items])
        med = float(np.median(eff))
        mad = float(np.median(np.abs(eff - med))) * 1.4826
        outliers = []
        for a, v in zip(items, eff):
            z = (v - med) / max(mad, 1.0)
            if abs(z) > 3.5 and abs(v - med) > 8.0:
                outliers.append(a.tag)
                rep.warn("loudness", a.tag, f"bus outlier: effective {v:.1f} LUFS vs {g} median {med:.1f} (z {z:+.1f})")
        table[g] = {"n": len(items), "lufsMin": round(float(vals.min()), 1), "lufsMedian": round(float(np.median(vals)), 1),
                    "lufsMax": round(float(vals.max()), 1), "spreadDb": round(float(vals.max() - vals.min()), 1),
                    "iqrDb": round(float(np.subtract(*np.percentile(vals, [75, 25]))), 1),
                    "effectiveMedian": round(med, 1), "effectiveSpreadDb": round(float(eff.max() - eff.min()), 1),
                    "rmsMedianDb": round(float(np.median(rms)), 1), "outliers": outliers}
    # variants of one key must be interchangeable in level
    by_key: dict[str, list[Asset]] = defaultdict(list)
    for a in assets:
        if a.lib == "sfx" and "lufs" in a.stats:
            by_key[a.key].append(a)
    worst = 0.0
    for k, items in by_key.items():
        if len(items) < 2:
            continue
        v = [a.stats["lufs"] for a in items]
        spread = max(v) - min(v)
        worst = max(worst, spread)
        if spread > 3.0:
            rep.err("loudness", k, f"variants differ by {spread:.1f} dB ({', '.join(f'{x:.1f}' for x in v)})")
        elif spread > 1.5:
            rep.warn("loudness", k, f"variants differ by {spread:.1f} dB")
    # music against its own targets
    for a in assets:
        if a.lib == "music" and "lufs" in a.stats:
            tgt = a.entry.get("master", {}).get("targetLufs")
            if a.entry.get("group"):
                continue  # stems are judged as the summed group
            if tgt is not None and abs(a.stats["lufs"] - tgt) > 1.0:
                rep.warn("loudness", a.tag, f"{a.stats['lufs']:.1f} LUFS vs target {tgt}")
    return {"buses": table, "worstVariantSpreadDb": round(worst, 2)}


# ----------------------------------------------------------------------------- distinctness
def check_distinctness(sfx: dict, by_rel: dict[str, Asset], rep: Report) -> dict:
    sounds = sfx.get("sounds", {})
    samples: list[tuple[str, str, np.ndarray, int]] = []
    for cls in ARMOR_CLASSES:
        e = sounds.get(cls)
        if e is None:
            rep.err("distinct", cls, "missing")
            continue
        for rel in e.get("variants") or [e["file"]]:
            a = by_rel.get(rel)
            if a is not None and a.x is not None:
                samples.append((cls, rel, mono(a.x), a.sr))
    if len({s[0] for s in samples}) < len(ARMOR_CLASSES):
        return {}
    feats = {rel: features(m, sr) for _, rel, m, sr in samples}
    mels = {rel: logmel(m, sr) for _, rel, m, sr in samples}
    phone = butter(4, [300.0, 8000.0], "bandpass", fs=samples[0][3], output="sos")
    mels_ph = {rel: logmel(sosfilt(phone, m), sr) for _, rel, m, sr in samples}
    envs = {rel: envelope_db(m, sr) for _, rel, m, sr in samples}

    def mel_d(p, q):
        a_, b_ = p - p.mean(), q - q.mean()
        return float(np.sqrt(np.mean((a_ - b_) ** 2)))

    def env_d(p, q):
        return float(np.sqrt(np.mean((p - q) ** 2)))

    cls_of = {rel: c for c, rel, _, _ in samples}
    pairs = {}
    classes = list(ARMOR_CLASSES)
    for i, c1 in enumerate(classes):
        for c2 in classes[i + 1 :]:
            r1 = [r for r in feats if cls_of[r] == c1]
            r2 = [r for r in feats if cls_of[r] == c2]
            mel_min = min(mel_d(mels[a], mels[b]) for a in r1 for b in r2)
            ph_min = min(mel_d(mels_ph[a], mels_ph[b]) for a in r1 for b in r2)
            env_min = min(env_d(envs[a], envs[b]) for a in r1 for b in r2)
            c1c = np.median([feats[r]["centroidHz"] for r in r1])
            c2c = np.median([feats[r]["centroidHz"] for r in r2])
            p1c = np.median([feats[r]["phoneCentroidHz"] for r in r1])
            p2c = np.median([feats[r]["phoneCentroidHz"] for r in r2])
            oct_ = abs(math.log2(c1c / c2c))
            ph_oct = abs(math.log2(p1c / p2c))
            # three independent dimensions: spectral balance, spectral shape, temporal shape
            dims = {"centroid>=0.5oct": oct_ >= 0.5 or ph_oct >= 0.5, "logMel>=6dB": mel_min >= 6.0,
                    "envelope>=6dB": env_min >= 6.0}
            pairs[f"{c1} vs {c2}"] = {"centroidOct": round(oct_, 2), "phoneCentroidOct": round(ph_oct, 2),
                                      "logMelMinDb": round(mel_min, 2), "phoneLogMelMinDb": round(ph_min, 2),
                                      "envelopeMinDb": round(env_min, 2), "differsIn": [k for k, v in dims.items() if v]}
            n_dims = sum(dims.values())
            if n_dims < 2 or mel_min < 4.0 or ph_min < 4.0:
                rep.err("distinct", f"{c1} vs {c2}", f"not clearly distinct: differs in {n_dims}/3 dimensions "
                                                     f"(centroid {oct_:.2f} oct, log-mel {mel_min:.1f} dB, phone log-mel "
                                                     f"{ph_min:.1f} dB, envelope {env_min:.1f} dB)")
    # leave-one-out nearest neighbour on standardised features + profiles
    keys = list(feats)
    vec_names = ["centroidHz", "phoneCentroidHz", "rolloff85Hz", "flatness", "lowShare", "highShare", "decay20S",
                 "temporalCentroidS", "crestDb"]
    mat = np.array([[math.log(max(feats[r][n], 1e-6)) if n.endswith("Hz") else feats[r][n] for n in vec_names] for r in keys])
    mat = (mat - mat.mean(axis=0)) / (mat.std(axis=0) + 1e-9)
    confusions = []
    for i, r in enumerate(keys):
        best, best_d = None, 1e18
        for j, q in enumerate(keys):
            if i == j:
                continue
            d = float(np.sqrt(np.mean((mat[i] - mat[j]) ** 2))) + 0.1 * mel_d(mels[r], mels[q]) + 0.05 * env_d(envs[r], envs[q])
            if d < best_d:
                best, best_d = q, d
        if cls_of[best] != cls_of[r]:
            confusions.append(f"{r} -> {best}")
            rep.err("distinct", r, f"nearest neighbour is {best} ({cls_of[best]}), not its own class")
    per_class, margins = {}, {}
    for c in classes:
        rs = [r for r in keys if cls_of[r] == c]
        per_class[c] = {n: round(float(np.median([feats[r][n] for r in rs])), 3) for n in feats[rs[0]]}
        # separation margin: the closest variant of any other class must be further away (log-mel) than
        # the two most different variants of this class - i.e. the a/b/c variation never blurs a class
        within = max((mel_d(mels[a], mels[b]) for i, a in enumerate(rs) for b in rs[i + 1 :]), default=0.0)
        other = min(mel_d(mels[a], mels[b]) for a in rs for b in keys if cls_of[b] != c)
        margins[c] = {"withinMaxDb": round(within, 2), "nearestOtherDb": round(other, 2)}
        if other <= within + 1.0:
            rep.err("distinct", c, f"variants overlap other classes: within-class spread {within:.1f} dB, "
                                   f"nearest other class {other:.1f} dB (need a 1 dB margin)")
    return {"perClassMedian": per_class, "pairs": pairs, "separation": margins, "nnConfusions": confusions,
            "perFile": feats}


# ----------------------------------------------------------------------------- coverage vs design doc
def parse_doc_tables(text: str, begin: str, end: str) -> dict[str, list[list[str]]]:
    """Rows of every markdown table between ``begin`` and ``end`` markers, grouped by '#### heading'."""
    i, j = text.find(begin), text.find(end)
    if i < 0 or j < 0:
        return {}
    out: dict[str, list[list[str]]] = {}
    head = "_"
    for line in text[i:j].splitlines():
        if line.startswith("#### "):
            head = line[5:].strip()
            out.setdefault(head, [])
        elif line.startswith("| `"):
            out.setdefault(head, []).append([c.strip() for c in line.strip().strip("|").split("|")])
    return out


HEADING_CATEGORY = {"Engines": {"engines"}, "Tracks": {"tracks"}, "Turret and gun laying": {"turret"},
                    "Gun firing": {"guns"}, "Reload": {"reload"}, "Shell flight": {"shells"},
                    "Shell ground impacts": {"impacts"}, "Armor results": {"armor"}, "Damage": {"damage"},
                    "Environment destruction": {"destruction"}, "UI": {"ui"}, "Battle information cues": {"cues"},
                    "Radio / Voice": {"radio"}, "Ambience beds and spots": {"ambience"}, "Weather": {"weather"},
                    "Hangar / garage": {"hangar"}}
REQUIRED_CATEGORIES = sorted({c for v in HEADING_CATEGORY.values() for c in v})
KEY_PREFIXES = ("engine_", "track_", "turret_", "gun_", "reload_", "shell_", "impact_", "armor_", "dmg_", "env_", "ui_",
                "cue_", "radio_", "amb_", "wx_", "hangar_", "transmission_", "map_", "battle_")
MUSIC_KEYS_PLAIN = ("main_theme", "garage_theme", "loading_theme", "results_theme", "victory", "defeat", "draw")


def check_coverage(sfx: dict, music: dict, rep: Report) -> dict:
    if not os.path.exists(DOC):
        rep.err("coverage", "docs/design/audio.md", "design document missing")
        return {}
    text = open(DOC, encoding="utf-8").read()
    sounds, cues = sfx.get("sounds", {}), music.get("cues", {})
    all_keys = set(sounds) | set(cues)
    res: dict = {"requiredCategories": {}, "unresolvedRefs": []}
    # 1. categories required by the brief and the doc's sound list
    tables = parse_doc_tables(text, "<!-- BEGIN SOUND LIST -->", "<!-- END SOUND LIST -->")
    cat_counts = defaultdict(int)
    for e in sounds.values():
        cat_counts[e["category"]] += 1
    for c in REQUIRED_CATEGORIES:
        res["requiredCategories"][c] = cat_counts.get(c, 0)
        if not cat_counts.get(c):
            rep.err("coverage", c, "required category has no sounds")
    if not music.get("cues"):
        rep.err("coverage", "music", "no music cues")
    doc_keys = set()
    for head, rows in tables.items():
        name = re.sub(r"\s*\(\d+\)$", "", head)
        m = re.search(r"\((\d+)\)$", head)
        if m and int(m.group(1)) != len(rows):
            rep.err("coverage", head, f"heading count {m.group(1)} != {len(rows)} rows")
        for r in rows:
            k = r[0].strip("`")
            doc_keys.add(k)
            e = sounds.get(k)
            if e is None:
                rep.err("coverage", k, f"listed in the doc ({name}) but missing from the catalogue")
                continue
            if name in HEADING_CATEGORY and e["category"] not in HEADING_CATEGORY[name] and not (
                    name in ("Turret and gun laying", "Radio / Voice")):
                rep.warn("coverage", k, f"doc lists it under '{name}' but its category is {e['category']}")
            nvar = len(e.get("variants") or []) or 1
            if r[1].isdigit() and int(r[1]) != nvar:
                rep.err("coverage", k, f"doc says {r[1]} variants, catalogue has {nvar}")
    for k in sorted(set(sounds) - doc_keys):
        rep.err("coverage", k, "in the catalogue but not listed in the design doc's sound list (run doc_sound_list.py)")
    mt = parse_doc_tables(text, "<!-- BEGIN MUSIC LIST -->", "<!-- END MUSIC LIST -->")
    mkeys = {r[0].strip("`") for rows in mt.values() for r in rows}
    for k in sorted(mkeys - set(cues)):
        rep.err("coverage", k, "music cue listed in the doc but missing from the music catalogue")
    for k in sorted(set(cues) - mkeys):
        rep.err("coverage", k, "music cue in the catalogue but not in the doc's music list")
    # 2. structural requirements spelled out in the doc
    fams = re.findall(r"^\| `([a-z0-9_]+)` \| [^|]+\| [^|]+ / [^|]+\|", text[text.find("### 5.1"):text.find("### 5.2")], re.M)
    for fam in fams:
        for layer in ("idle", "low", "mid", "high", "damaged", "overload", "start", "stop"):
            if f"engine_{fam}_{layer}" not in sounds:
                rep.err("coverage", f"engine_{fam}_{layer}", f"engine family '{fam}' (doc 5.1) lacks its {layer} sound")
    res["engineFamilies"] = fams
    surf_txt = text[text.find("### 5.2"):text.find("## 6.")]
    surfaces = sorted(set(re.findall(r"→ ([a-z]+)[.\s]", surf_txt)))
    for s in surfaces:
        if f"track_{s}" not in sounds:
            rep.err("coverage", f"track_{s}", "track surface named in doc 5.2 has no loop")
    res["trackSurfaces"] = surfaces
    for k, e in sounds.items():
        if k.startswith("gun_") and k.endswith(("_close", "_mid", "_far")):
            base = k.rsplit("_", 1)[0]
            for band in ("close", "mid", "far"):
                if f"{base}_{band}" not in sounds:
                    rep.err("coverage", f"{base}_{band}", "gun class lacks a distance band variant (doc 4.1)")
    radio_txt = text[text.find("### 6.12"):text.find("## 7.")]
    for cmd in re.findall(r"^\| ([a-z]+) \| ", radio_txt, re.M):
        if cmd != "Command" and f"radio_cmd_{cmd}" not in sounds:
            rep.err("coverage", f"radio_cmd_{cmd}", "radio command in doc 6.12 has no sound")
    biome_txt = text[text.find("## 8."):text.find("## 9.")]
    biomes = []
    for row in re.findall(r"^\| `([a-z_]+)` \|[^|]*\| ([^|]*) \|", biome_txt, re.M):
        biome, spots = row
        biomes.append(biome)
        if f"amb_{biome}_bed" not in sounds:
            rep.err("coverage", f"amb_{biome}_bed", "biome in doc 8 has no bed")
        for spot, cnt in re.findall(r"`([a-z_]+)`(?: \((\d+)\))?", spots):
            k = f"amb_{biome}_spot_{spot}"
            if k not in sounds:
                rep.err("coverage", k, f"ambient spot listed for biome {biome} (doc 8) is missing")
            elif cnt and len(sounds[k].get("variants") or []) != int(cnt):
                rep.err("coverage", k, f"doc 8 says {cnt} variants, catalogue has {len(sounds[k].get('variants') or [])}")
    res["biomes"] = biomes
    for row in re.findall(r"^\| `([a-z_]+)` \| ([a-z_]+) \| [^|]+\| [^|]+\|$", text[text.find("### 11.2"):text.find("### 11.3")], re.M):
        if f"map_{row[0]}" not in cues:
            rep.err("coverage", f"map_{row[0]}", "map stinger named in doc 11.2 is missing")
        if f"amb_{row[1]}_bed" not in sounds:
            rep.err("coverage", f"amb_{row[1]}_bed", f"map {row[0]}'s biome has no ambience bed")
    director = music.get("director", {}).get("states", {})
    for state, spec in director.items():
        for v in (spec.values() if isinstance(spec, dict) else []):
            for k in (v if isinstance(v, list) else [v]):
                if isinstance(k, str) and "<" not in k and k not in cues:
                    rep.err("coverage", k, f"director state {state} refers to a missing cue")
    for st in ("MENU", "GARAGE", "LOADING", "BATTLE", "BATTLE_ENDGAME", "RESULT_STINGER", "RESULTS"):
        if st not in director:
            rep.err("coverage", st, "music director state from doc 11.4 is not defined")
    # 3. every backticked reference in the doc resolves
    refs = set()
    for tok in re.findall(r"`([^`\s]+)`", text):
        tok = tok.strip()
        if tok.startswith(KEY_PREFIXES) or tok in MUSIC_KEYS_PLAIN or tok.startswith("*_"):
            refs.add(tok)
    for tok in sorted(refs):
        pat = re.sub(r"<[^>]+>", "*", tok).replace("{", "[").replace("}", "]")
        if "/" in pat or "." in pat or "(" in pat:
            continue
        if any(ch in pat for ch in "*?["):
            if not any(fnmatch.fnmatch(k, pat) for k in all_keys):
                res["unresolvedRefs"].append(tok)
                rep.err("coverage", tok, "pattern referenced in the doc matches no sound")
        elif tok not in all_keys and not any(k.startswith(tok + "_") for k in all_keys):
            res["unresolvedRefs"].append(tok)
            rep.err("coverage", tok, "key referenced in the doc does not exist")
    res["docRefsChecked"] = len(refs)
    return res


# ----------------------------------------------------------------------------- uploads / banks
def check_banks(sfx: dict, music: dict, by_rel: dict[str, Asset], rep: Report) -> dict:
    res = {}
    bank_cache: dict[str, tuple[np.ndarray, int]] = {}

    def load(path):
        if path not in bank_cache:
            x, sr = sf.read(path, dtype="float64", always_2d=False)
            bank_cache[path] = (x, sr)
        return bank_cache[path]

    regions: dict[str, list[tuple[float, float, str]]] = defaultdict(list)
    for lib, cat, root in (("sfx", sfx, SFX_ROOT), ("music", music, MUSIC_ROOT)):
        for name, b in cat.get("banks", {}).items():
            p = os.path.join(root, b["file"])
            if not os.path.exists(p):
                rep.err("uploads", name, "bank file missing")
                continue
            x, sr = load(p)
            pk = db(np.max(np.abs(x)))
            size = os.path.getsize(p)
            dur = x.shape[0] / sr
            res[name] = {"durationS": round(dur, 2), "peakDb": round(pk, 2), "bytes": size}
            if pk > PEAK_MAX_DB:
                rep.err("uploads", name, f"bank peak {pk:.2f} dBFS > {PEAK_MAX_DB}")
            if size > UPLOAD_MAX_BYTES or dur > UPLOAD_MAX_S:
                rep.err("uploads", name, f"bank exceeds upload limits ({size / 1e6:.1f} MB, {dur:.0f} s)")
        if lib == "sfx":
            for k, e in cat.get("sounds", {}).items():
                files = e.get("variants") or [e["file"]]
                regs = e.get("bankRegions") or []
                if e["loop"]:
                    if regs:
                        rep.err("uploads", k, "loops must not be banked")
                    continue
                if len(regs) != len(files):
                    rep.err("uploads", k, f"{len(regs)} bank regions for {len(files)} files")
                    continue
                for rel, r in zip(files, regs):
                    regions[os.path.join(root, r["bank"])].append((r["startS"], r["endS"], f"{k} [{rel}]"))
                    a = by_rel.get(rel)
                    if a is not None and a.x is not None:
                        ln = r["endS"] - r["startS"]
                        if abs(ln - a.x.shape[0] / a.sr) > 2.5 / a.sr:
                            rep.err("uploads", a.tag, f"bank region {ln:.5f} s != file {a.x.shape[0] / a.sr:.5f} s")
        else:
            for k, e in cat.get("cues", {}).items():
                r = e.get("bankRegion")
                if e["kind"] == "loop":
                    if r:
                        rep.err("uploads", k, "music loops must not be banked")
                    continue
                if not r:
                    rep.warn("uploads", k, "stinger is not in a bank (costs an extra upload)")
                    continue
                regions[os.path.join(root, r["bank"])].append((r["startS"], r["endS"], k))
                ln = r["endS"] - r["startS"]
                if abs(ln - e["durationS"]) > 0.001:
                    rep.err("uploads", k, f"bank region {ln:.4f} s != cue {e['durationS']} s")
    for path, regs in regions.items():
        if not os.path.exists(path):
            continue
        x, sr = load(path)
        dur = x.shape[0] / sr
        regs.sort()
        prev_end = 0.0
        for s, e_, tag in regs:
            if s < -1e-6 or e_ > dur + 1e-6:
                rep.err("uploads", tag, f"bank region {s:.3f}-{e_:.3f} s outside bank ({dur:.3f} s)")
            if s < prev_end - 1e-6:
                rep.err("uploads", tag, "bank region overlaps the previous one")
            gap = x[int(prev_end * sr) + int(0.02 * sr) : max(int(prev_end * sr) + int(0.02 * sr), int(s * sr) - int(0.02 * sr))]
            if gap.size and pdb(np.mean(gap ** 2)) > -70:
                rep.err("uploads", tag, f"gap before bank region not silent ({pdb(np.mean(gap ** 2)):.1f} dB)")
            prev_end = e_
    sfx_loops = sum(1 for e in sfx.get("sounds", {}).values() if e["loop"])
    mus_loops = sum(1 for e in music.get("cues", {}).values() if e["kind"] == "loop")
    uploads = sfx_loops + len(sfx.get("banks", {})) + mus_loops + len(music.get("banks", {}))
    unbanked = sum(1 for e in music.get("cues", {}).values() if e["kind"] != "loop" and not e.get("bankRegion"))
    uploads += unbanked
    res["_uploads"] = {"sfxLoops": sfx_loops, "sfxBanks": len(sfx.get("banks", {})), "musicLoops": mus_loops,
                       "musicBanks": len(music.get("banks", {})), "unbankedStingers": unbanked, "total": uploads,
                       "quota": UPLOAD_QUOTA}
    if uploads > UPLOAD_QUOTA:
        rep.err("uploads", "total", f"{uploads} uploads > {UPLOAD_QUOTA} per 30 days")
    return res


# ============================================================================= contact sheets
def _font(size):
    from PIL import ImageFont

    try:
        return ImageFont.load_default(size=size)
    except TypeError:
        return ImageFont.load_default()


_CMAP = np.array([[0, 0, 4], [31, 12, 72], [85, 15, 109], [136, 34, 106], [186, 54, 85], [227, 89, 51],
                  [249, 140, 10], [249, 201, 50], [252, 255, 164]], dtype=np.float64)


def _cmap(v):
    v = np.clip(v, 0, 1) * (len(_CMAP) - 1)
    i = np.clip(np.floor(v).astype(int), 0, len(_CMAP) - 2)
    f = (v - i)[..., None]
    return (_CMAP[i] * (1 - f) + _CMAP[i + 1] * f).astype(np.uint8)


def spec_rgb(m: np.ndarray, sr: int, w: int, h: int, fmin=30.0, fmax=20000.0, rng=90.0) -> np.ndarray:
    nper = 2048 if m.size > 4096 else 512
    hop = max(16, m.size // w)
    f, _, z = stft(m, sr, nperseg=nper, noverlap=max(0, nper - hop), boundary="zeros")
    mag = 20 * np.log10(np.abs(z) + 1e-9)
    norm = (mag - (mag.max() - rng)) / rng
    edges = np.geomspace(fmin, min(fmax, sr / 2), h + 1)
    rows = []
    for a, b in zip(edges[:-1], edges[1:]):
        sel = (f >= a) & (f < b)
        rows.append(norm[sel].max(axis=0) if np.any(sel) else norm[int(np.argmin(np.abs(f - (a + b) / 2)))])
    img = np.array(rows)[::-1]
    cols = np.linspace(0, img.shape[1] - 1, w).astype(int)
    return _cmap(img[:, cols])


def panel(label: str, x: np.ndarray, sr: int, w: int, h_spec: int, h_wave: int, marks=(), sub: str = ""):
    from PIL import Image, ImageDraw

    m = mono(x)
    lab_h = 30
    img = Image.new("RGB", (w, lab_h + h_wave + h_spec), (12, 12, 16))
    d = ImageDraw.Draw(img)
    d.text((3, 1), label[:70], fill=(240, 240, 240), font=_font(13))
    d.text((3, 16), sub[:90], fill=(170, 170, 180), font=_font(11))
    # waveform (min/max per column)
    edges = np.linspace(0, m.size, w + 1).astype(int)
    mid = lab_h + h_wave / 2
    sc = max(float(np.max(np.abs(m))), 1e-9)
    for i in range(w):
        seg = m[edges[i] : max(edges[i] + 1, edges[i + 1])]
        d.line([(i, mid - seg.max() / sc * h_wave * 0.45), (i, mid - seg.min() / sc * h_wave * 0.45)], fill=(110, 190, 250))
    rgb = spec_rgb(m, sr, w, h_spec)
    img.paste(Image.fromarray(rgb, "RGB"), (0, lab_h + h_wave))
    for fz in (100, 1000, 10000):
        yy = lab_h + h_wave + h_spec - 1 - int(np.log(fz / 30.0) / np.log(20000 / 30.0) * (h_spec - 1))
        d.line([(0, yy), (6, yy)], fill=(220, 220, 220))
        d.text((8, yy - 6), f"{fz // 1000}k" if fz >= 1000 else str(fz), fill=(200, 200, 200), font=_font(9))
    for t in marks:
        xx = int(t * w)
        d.line([(xx, lab_h), (xx, lab_h + h_wave + h_spec)], fill=(80, 255, 120))
    return img


def sheet(path: str, title: str, panels_, cols: int) -> None:
    from PIL import Image, ImageDraw

    if not panels_:
        return
    pw, ph = panels_[0].size
    rows = math.ceil(len(panels_) / cols)
    W, H = cols * (pw + 8) + 8, 34 + rows * (ph + 8)
    can = Image.new("RGB", (W, H), (4, 4, 6))
    d = ImageDraw.Draw(can)
    d.text((10, 7), title, fill=(255, 255, 255), font=_font(18))
    for i, p in enumerate(panels_):
        r, c = divmod(i, cols)
        can.paste(p, (8 + c * (pw + 8), 34 + r * (ph + 8)))
    can.save(path)


def render_sheets(assets: list[Asset], sfx: dict, rep: Report) -> list[str]:
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.startswith("qa_") and f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    written = []
    by_cat: dict[str, list[Asset]] = defaultdict(list)
    for a in assets:
        if a.x is not None:
            by_cat[a.category].append(a)
    per_page, cols = 24, 4
    for cat, items in sorted(by_cat.items()):
        items.sort(key=lambda a: (a.key, a.rel))
        pages = math.ceil(len(items) / per_page)
        for pg in range(pages):
            chunk = items[pg * per_page : (pg + 1) * per_page]
            ps = []
            for a in chunk:
                st = a.stats
                sub = (f"{'LOOP' if a.loop else a.kind} {st.get('durationS', 0):.2f}s {st.get('channels')}ch "
                       f"pk {st.get('peakDb', 0):.1f} {st.get('lufs', 0):.1f}LUFS")
                if not a.loop and "leadingSilenceMs" in st:
                    sub += f" lead {st['leadingSilenceMs']:.0f}ms"
                flag = "!! " if any(i["severity"] == "ERROR" and i["subject"].startswith(a.key) and a.rel in i["subject"]
                                    for i in rep.items) else ""
                ps.append(panel(flag + os.path.basename(a.rel), a.x, a.sr, 460 if cat != "music" else 700, 120, 34, sub=sub))
            name = f"qa_{cat}{'' if pages == 1 else f'_{pg + 1}'}.png"
            sheet(os.path.join(OUT, name), f"QA contact sheet - {cat} ({pg + 1}/{pages}, {len(items)} files)", ps,
                  cols if cat != "music" else 3)
            written.append(name)
    # loop seams: +-0.5 s around the boundary, seam marked
    loops = [a for a in assets if a.loop and a.x is not None]
    loops.sort(key=lambda a: (a.lib, a.key))
    pages = math.ceil(len(loops) / per_page)
    for pg in range(pages):
        ps = []
        for a in loops[pg * per_page : (pg + 1) * per_page]:
            h = int(0.5 * a.sr)
            x = np.concatenate([a.x[-h:], a.x[:h]])
            s = a.stats.get("seam", {})
            sub = f"step {s.get('jumpLocal')}x slope {s.get('slopeLocal')}x HF {s.get('hfDb')}dB lvl {s.get('levelDb')}dB"
            ps.append(panel(f"{a.key} seam (+-0.5 s)", x, a.sr, 460, 110, 40, marks=(0.5,), sub=sub))
        name = f"qa_loop_seams_{pg + 1}.png"
        sheet(os.path.join(OUT, name), f"QA loop seams ({pg + 1}/{pages}): last 0.5 s | first 0.5 s, green = seam", ps, cols)
        written.append(name)
    # armor results side by side, common 1.4 s axis
    ps = []
    for cls in ARMOR_CLASSES:
        e = sfx["sounds"].get(cls)
        for rel in (e.get("variants") or [e["file"]]) if e else []:
            a = next((z for z in assets if z.rel == rel and z.lib == "sfx"), None)
            if a is None or a.x is None:
                continue
            n = int(1.4 * a.sr)
            x = np.concatenate([a.x, np.zeros(max(0, n - a.x.shape[0]))])[:n]
            f = features(mono(a.x), a.sr)
            ps.append(panel(os.path.basename(rel), x, a.sr, 460, 140, 40,
                            sub=f"centroid {f['centroidHz']:.0f} Hz phone {f['phoneCentroidHz']:.0f} Hz flat {f['flatness']:.3f} "
                                f"T-20 {f['decay20S']:.2f}s"))
    sheet(os.path.join(OUT, "qa_armor_distinctness.png"), "Armor results: rows = penetration / ricochet / blocked / critical", ps, 3)
    written.append("qa_armor_distinctness.png")
    return written


# ============================================================================= main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-sheets", action="store_true", help="skip the contact-sheet PNGs")
    ap.add_argument("--strict", action="store_true", help="warnings also fail the run")
    ap.add_argument("--json", default=os.path.join(OUT, "qa_report.json"))
    ap.add_argument("--verbose", "-v", action="store_true", help="print every issue (default: first 80)")
    args = ap.parse_args(argv)
    t0 = time.time()
    rep = Report()

    sfx_path, mus_path = os.path.join(SFX_ROOT, "catalog.json"), os.path.join(MUSIC_ROOT, "catalog.json")
    sfx = load_json_strict(sfx_path, rep, "assets/audio/catalog.json") if os.path.exists(sfx_path) else {}
    music = load_json_strict(mus_path, rep, "assets/music/catalog.json") if os.path.exists(mus_path) else {}
    if not sfx:
        rep.err("catalog", "assets/audio/catalog.json", "missing")
    if not music:
        rep.err("catalog", "assets/music/catalog.json", "missing")
    check_keys(sfx, music, rep)
    assets = collect_assets(sfx, music, rep)
    for a in assets:
        if decode(a, rep):
            check_file(a, rep, sfx.get("sampleRate", 48000) if a.lib == "sfx" else music.get("sampleRate", 48000))
            if a.loop:
                check_loop(a, rep)
            check_clicks(a, rep)
            check_catalog_stats(a, rep)
    check_orphans(sfx, music, assets, rep)
    by_rel = {a.rel: a for a in assets if a.lib == "sfx"}
    music_assets = {a.key: a for a in assets if a.lib == "music"}
    stems = check_stems(music, music_assets, rep)
    loud = check_loudness(assets, rep)
    dist = check_distinctness(sfx, by_rel, rep)
    cov = check_coverage(sfx, music, rep)
    banks = check_banks(sfx, music, by_rel, rep)
    sheets = [] if args.no_sheets else render_sheets(assets, sfx, rep)

    ok = [a for a in assets if a.x is not None]
    loops = [a for a in ok if a.loop]
    shots = [a for a in ok if not a.loop and a.lib == "sfx"]
    summary = {
        "files": len(assets), "decoded": len(ok), "sfxKeys": len(sfx.get("sounds", {})), "musicCues": len(music.get("cues", {})),
        "maxPeakDb": max(a.stats["peakDb"] for a in ok) if ok else None,
        "maxTruePeakDb": max(a.stats["truePeakDb"] for a in ok) if ok else None,
        "maxDc": max(a.stats["dc"] for a in ok) if ok else None,
        "maxLeadingSilenceMs": max(a.stats.get("leadingSilenceMs", 0) for a in shots) if shots else None,
        "loops": len(loops),
        "worstSeam": {k: max(a.stats["seam"][k] for a in loops) for k in ("jumpLocal", "slopeLocal", "hfDb")} if loops else {},
        "loopClicks": sum(len(a.stats.get("clicks", [])) for a in loops),
        "errors": rep.count("ERROR"), "warnings": rep.count("WARN"),
        "seconds": round(time.time() - t0, 1),
    }
    report = {"summary": summary, "stems": stems, "loudness": loud, "distinctness": dist, "coverage": cov, "banks": banks,
              "sheets": sheets, "issues": rep.items,
              "files": {f"{a.lib}:{a.rel}": a.stats for a in ok}}
    os.makedirs(os.path.dirname(args.json), exist_ok=True)
    with open(args.json, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)

    # ------------------------------------------------------------------ printed report
    line = "=" * 100
    print(line)
    print(f"HULLDOWN audio QA  {summary['files']} files ({summary['sfxKeys']} SFX keys, {summary['musicCues']} music cues), "
          f"{summary['seconds']} s")
    print(line)
    checks = ["catalog", "channels", "signal", "loops", "clicks", "stems", "loudness", "distinct", "coverage", "uploads"]
    for c in checks:
        e, w = rep.count("ERROR", c), rep.count("WARN", c)
        print(f"  {c:10s} {'PASS' if e == 0 else 'FAIL':4s}  {e:3d} errors  {w:3d} warnings")
    print(f"\nheadroom   max sample peak {summary['maxPeakDb']} dBFS, max true peak {summary['maxTruePeakDb']} dBTP, "
          f"max |DC| {summary['maxDc']}")
    print(f"one-shots  max leading silence {summary['maxLeadingSilenceMs']} ms (limit {LEAD_SILENCE_MAX_S * 1000:.0f})")
    print(f"loops      {summary['loops']} loops, worst seam: step {summary['worstSeam'].get('jumpLocal')}x, slope "
          f"{summary['worstSeam'].get('slopeLocal')}x, HF {summary['worstSeam'].get('hfDb')} dB; body clicks {summary['loopClicks']}")
    for g, s in stems.items():
        print(f"stems      {g}: lengths {sorted(set(s['lengths'].values()))} grid {sorted(set(s['gridOffsets'].values()))} "
              f"sum peak {s['sumPeakDb']} dBFS, {s['sumLufs']} LUFS")
    print("\nloudness per bus (LUFS: momentary-max one-shots / integrated loops; effective = + 20log10 volume)")
    print(f"  {'bus/kind':18s} {'n':>3s} {'min':>6s} {'median':>7s} {'max':>6s} {'spread':>7s} {'IQR':>5s} {'eff.med':>8s} "
          f"{'eff.spread':>10s} {'RMS med':>8s}")
    for g, s in loud.get("buses", {}).items():
        print(f"  {g:18s} {s['n']:3d} {s['lufsMin']:6.1f} {s['lufsMedian']:7.1f} {s['lufsMax']:6.1f} {s['spreadDb']:7.1f} "
              f"{s['iqrDb']:5.1f} {s['effectiveMedian']:8.1f} {s['effectiveSpreadDb']:10.1f} {s['rmsMedianDb']:8.1f}"
              f"{'  outliers: ' + ', '.join(s['outliers']) if s['outliers'] else ''}")
    print(f"  worst variant-to-variant spread {loud.get('worstVariantSpreadDb')} dB")
    if dist:
        print("\ndistinctness: armor results (median of variants)")
        print(f"  {'class':18s} {'centroid':>9s} {'phone c.':>9s} {'rolloff':>8s} {'flat':>6s} {'low':>5s} {'high':>5s} "
              f"{'attack':>7s} {'T-20':>6s} {'T-40':>6s} {'crest':>6s}")
        for c, f in dist["perClassMedian"].items():
            print(f"  {c:18s} {f['centroidHz']:8.0f}Hz {f['phoneCentroidHz']:7.0f}Hz {f['rolloff85Hz']:7.0f}Hz "
                  f"{f['flatness']:6.3f} {f['lowShare']:5.2f} {f['highShare']:5.2f} {f['attackMs']:5.1f}ms "
                  f"{f['decay20S']:5.2f}s {f['decay40S']:5.2f}s {f['crestDb']:5.1f}")
        print(f"  {'pair':40s} {'cent.oct':>8s} {'phone':>6s} {'logmel':>7s} {'phone':>6s} {'env':>6s}  differs in")
        for p, v in dist["pairs"].items():
            print(f"  {p:40s} {v['centroidOct']:8.2f} {v['phoneCentroidOct']:6.2f} {v['logMelMinDb']:7.2f} "
                  f"{v['phoneLogMelMinDb']:6.2f} {v['envelopeMinDb']:6.2f}  {', '.join(v['differsIn'])}")
        print("  separation (log-mel): " + ", ".join(f"{c.replace('armor_', '')} within {m['withinMaxDb']} / nearest "
                                                     f"other {m['nearestOtherDb']} dB" for c, m in dist["separation"].items()))
        print(f"  leave-one-out nearest neighbour: {len(dist['nnConfusions'])} confusions of "
              f"{len(dist['perFile'])} variants")
    if cov:
        rc = cov.get("requiredCategories", {})
        print(f"\ncoverage   {sum(1 for v in rc.values() if v)}/{len(rc)} required SFX categories present "
              f"({', '.join(f'{k} {v}' for k, v in rc.items())}); engine families {len(cov.get('engineFamilies', []))}, "
              f"track surfaces {len(cov.get('trackSurfaces', []))}, biomes {len(cov.get('biomes', []))}; "
              f"{cov.get('docRefsChecked')} doc references checked, {len(cov.get('unresolvedRefs', []))} unresolved")
    if "_uploads" in banks:
        u = banks["_uploads"]
        print(f"uploads    {u['total']} / {u['quota']} (SFX loops {u['sfxLoops']} + SFX banks {u['sfxBanks']} + music loops "
              f"{u['musicLoops']} + music banks {u['musicBanks']} + unbanked stingers {u['unbankedStingers']})")
    if sheets:
        print(f"sheets     {len(sheets)} PNGs in {os.path.relpath(OUT, REPO)}/ (qa_*.png)")
    print(f"\n{summary['errors']} errors, {summary['warnings']} warnings  ->  report {os.path.relpath(args.json, REPO)}")
    lim = None if args.verbose else 80
    for sev in ("ERROR", "WARN"):
        items = [i for i in rep.items if i["severity"] == sev]
        for i in items[:lim]:
            print(f"  {sev:5s} [{i['check']}] {i['subject']}: {i['message']}")
        if lim is not None and len(items) > lim:
            print(f"  ... {len(items) - lim} more {sev} (see the JSON report or use -v)")
    failed = summary["errors"] > 0 or (args.strict and summary["warnings"] > 0)
    print(line)
    print("QA " + ("FAILED" if failed else "PASSED"))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
