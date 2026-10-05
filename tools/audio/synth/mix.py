"""Mixing, panning, loudness measurement/normalisation and seamless-loop tools."""

from __future__ import annotations

import numpy as np
from scipy.signal import lfilter, resample_poly

from .core import SR, n_of, to_mono, to_stereo
from .env import fade
from .filters import dc_block


# --------------------------------------------------------------------------- assembly
def place(dst: np.ndarray, src: np.ndarray, at, gain: float = 1.0, sr: int = SR) -> np.ndarray:
    """Add ``src`` into ``dst`` at time ``at`` (seconds, float) or sample index (int). In place."""
    i = at if isinstance(at, (int, np.integer)) else n_of(at, sr)
    if i >= dst.shape[0] or i + src.shape[0] <= 0:
        return dst
    s0 = max(0, -i)
    i = max(0, i)
    m = min(src.shape[0] - s0, dst.shape[0] - i)
    seg = src[s0 : s0 + m]
    if dst.ndim == 2 and seg.ndim == 1:
        seg = seg[:, None]
    elif dst.ndim == 1 and seg.ndim == 2:
        seg = seg.mean(axis=1)
    dst[i : i + m] += gain * seg
    return dst


def place_wrapped(dst: np.ndarray, src: np.ndarray, at_n: int, gain: float = 1.0) -> np.ndarray:
    """Add ``src`` into a loop buffer at ``at_n``, wrapping anything past the end to the start."""
    n = dst.shape[0]
    seg = src
    if dst.ndim == 2 and seg.ndim == 1:
        seg = seg[:, None] * np.ones((1, dst.shape[1]))
    elif dst.ndim == 1 and seg.ndim == 2:
        seg = seg.mean(axis=1)
    pos = at_n % n
    remaining = seg
    while remaining.shape[0] > 0:
        m = min(remaining.shape[0], n - pos)
        dst[pos : pos + m] += gain * remaining[:m]
        remaining = remaining[m:]
        pos = 0
    return dst


def mix(*layers, n: int | None = None) -> np.ndarray:
    """Sum layers given as arrays or ``(array, gain)`` tuples (zero-padded, stereo-promoted)."""
    items = [(l, 1.0) if isinstance(l, np.ndarray) else (l[0], l[1]) for l in layers]
    length = n if n is not None else max(a.shape[0] for a, _ in items)
    stereo = any(a.ndim == 2 for a, _ in items)
    out = np.zeros((length, 2)) if stereo else np.zeros(length)
    for a, g in items:
        place(out, to_stereo(a) if stereo else a, 0, g)
    return out


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if x.shape[0] >= n:
        return x[:n]
    out = np.zeros((n,) + x.shape[1:])
    out[: x.shape[0]] = x
    return out


def pan(x: np.ndarray, position: float | np.ndarray) -> np.ndarray:
    """Equal-power pan of a mono signal; ``position`` in [-1 (left), +1 (right)]."""
    m = to_mono(x)
    p = np.clip(np.asarray(position, dtype=np.float64), -1, 1)
    ang = (p + 1.0) * np.pi / 4.0
    return np.stack([m * np.cos(ang), m * np.sin(ang)], axis=1) * np.sqrt(2.0)


def haas(x: np.ndarray, delay_ms: float = 8.0, side: str = "right", sr: int = SR) -> np.ndarray:
    """Widen a mono source by delaying one channel a few milliseconds (precedence effect)."""
    m = to_mono(x)
    d = n_of(delay_ms / 1000.0, sr)
    delayed = np.concatenate([np.zeros(d), m])[: m.shape[0]]
    return np.stack([m, delayed] if side == "right" else [delayed, m], axis=1)


def stereo_from(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    n = max(left.shape[0], right.shape[0])
    return np.stack([pad_to(left, n), pad_to(right, n)], axis=1)


def width(x: np.ndarray, amount: float) -> np.ndarray:
    """Mid/side width control (0 = mono, 1 = unchanged, >1 wider)."""
    if x.ndim == 1:
        return x
    mid = 0.5 * (x[:, 0] + x[:, 1])
    side = 0.5 * (x[:, 0] - x[:, 1]) * amount
    return np.stack([mid + side, mid - side], axis=1)


# --------------------------------------------------------------------------- measurement
def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if x.size else 0.0


def peak_db(x: np.ndarray) -> float:
    return float(20 * np.log10(max(peak(x), 1e-12)))


def true_peak_db(x: np.ndarray, oversample: int = 4) -> float:
    """Inter-sample peak estimate via polyphase oversampling (BS.1770-style)."""
    up = resample_poly(x, oversample, 1, axis=0)
    return float(20 * np.log10(max(np.max(np.abs(up)), 1e-12)))


def rms_db(x: np.ndarray) -> float:
    if not x.size:
        return -150.0
    return float(10 * np.log10(max(np.mean(np.asarray(x, dtype=np.float64) ** 2), 1e-15)))


def _k_filter(x: np.ndarray, sr: int) -> np.ndarray:
    # ITU-R BS.1770 K-weighting (pre-filter shelf + RLB high-pass), any sample rate
    f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    K = np.tan(np.pi * f0 / sr)
    Vh, Vb = 10 ** (G / 20.0), 10 ** (G / 20.0) ** 0.4996667741545416
    a0 = 1.0 + K / Q + K * K
    b1 = [(Vh + Vb * K / Q + K * K) / a0, 2.0 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0]
    a1 = [1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0]
    f0, Q = 38.13547087602444, 0.5003270373238773
    K = np.tan(np.pi * f0 / sr)
    a0 = 1.0 + K / Q + K * K
    b2 = [1.0, -2.0, 1.0]
    a2 = [1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0]
    return lfilter(b2, a2, lfilter(b1, a1, x, axis=0), axis=0)


def _block_power(x: np.ndarray, sr: int, block_s: float, hop_s: float) -> np.ndarray:
    y = _k_filter(x, sr)
    sq = y * y if y.ndim == 1 else (y * y).sum(axis=1)
    blk = n_of(block_s, sr)
    hop = max(1, n_of(hop_s, sr))
    if sq.shape[0] < blk:
        sq = np.concatenate([sq, np.zeros(blk - sq.shape[0])])
    c = np.concatenate([[0.0], np.cumsum(sq)])
    starts = np.arange(0, sq.shape[0] - blk + 1, hop)
    return (c[starts + blk] - c[starts]) / blk


def loudness_integrated(x: np.ndarray, sr: int = SR) -> float:
    """Gated integrated loudness (LUFS, BS.1770-4)."""
    p = _block_power(x, sr, 0.4, 0.1)
    lk = -0.691 + 10 * np.log10(np.maximum(p, 1e-15))
    p = p[lk > -70.0]
    if not p.size:
        return -70.0
    rel = -0.691 + 10 * np.log10(np.mean(p)) - 10.0
    lk = -0.691 + 10 * np.log10(np.maximum(p, 1e-15))
    p = p[lk > rel]
    return float(-0.691 + 10 * np.log10(max(np.mean(p), 1e-15))) if p.size else -70.0


def loudness_momentary_max(x: np.ndarray, sr: int = SR) -> float:
    """Maximum momentary loudness (400 ms window, 10 ms hop) in LUFS - used for one-shots."""
    p = _block_power(x, sr, 0.4, 0.01)
    return float(-0.691 + 10 * np.log10(max(np.max(p), 1e-15)))


def loudness_short_term_max(x: np.ndarray, sr: int = SR) -> float:
    p = _block_power(x, sr, 3.0, 0.1)
    return float(-0.691 + 10 * np.log10(max(np.max(p), 1e-15)))


def dc_offset(x: np.ndarray) -> float:
    return float(np.max(np.abs(np.mean(x, axis=0)))) if x.size else 0.0


# --------------------------------------------------------------------------- normalisation
def gain_db(x: np.ndarray, db: float) -> np.ndarray:
    return x * (10.0 ** (db / 20.0))


def normalize_peak(x: np.ndarray, target_db: float = -1.0) -> np.ndarray:
    p = peak(x)
    return x if p <= 0 else x * (10 ** (target_db / 20.0) / p)


def normalize_rms(x: np.ndarray, target_db: float = -20.0) -> np.ndarray:
    return gain_db(x, target_db - rms_db(x))


def normalize_loudness(x: np.ndarray, target_lufs: float, mode: str = "momentary", sr: int = SR) -> np.ndarray:
    cur = loudness_momentary_max(x, sr) if mode == "momentary" else loudness_integrated(x, sr)
    return gain_db(x, target_lufs - cur)


# --------------------------------------------------------------------------- clean-up
def remove_dc(x: np.ndarray, fc: float = 12.0, sr: int = SR) -> np.ndarray:
    return dc_block(x, fc, sr)


def trim_tail(x: np.ndarray, threshold_db: float = -72.0, min_len: float = 0.02, fade_s: float = 0.03, sr: int = SR) -> np.ndarray:
    """Remove trailing near-silence (relative to the peak) and fade the new end."""
    mag = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    pk = mag.max() if mag.size else 0.0
    if pk <= 0:
        return x[: n_of(min_len, sr)]
    thr = pk * 10 ** (threshold_db / 20.0)
    above = np.nonzero(mag > thr)[0]
    end = int(above[-1]) + 1 if above.size else n_of(min_len, sr)
    end = min(x.shape[0], max(end + n_of(0.01, sr), n_of(min_len, sr)))
    return fade(x[:end], 0.0, min(fade_s, end / sr / 2), sr)


def trim_head(x: np.ndarray, threshold_db: float = -60.0, sr: int = SR) -> np.ndarray:
    mag = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    pk = mag.max() if mag.size else 0.0
    if pk <= 0:
        return x
    above = np.nonzero(mag > pk * 10 ** (threshold_db / 20.0))[0]
    start = max(0, int(above[0]) - n_of(0.002, sr)) if above.size else 0
    return x[start:]


# --------------------------------------------------------------------------- loops
def circular(fn, x: np.ndarray, reps: int = 3) -> np.ndarray:
    """Apply a stateful process (filters, compressors) to a loop so the result wraps cleanly.

    The loop is tiled ``reps`` times, processed, and the final repetition is returned, by
    which point filter state has reached its periodic steady state.
    """
    n = x.shape[0]
    tiled = np.concatenate([x] * reps, axis=0)
    y = fn(tiled)
    return np.array(y[(reps - 1) * n : reps * n], copy=True)


def loop_crossfade(x: np.ndarray, loop_n: int, fade_n: int, curve: str = "equal_power") -> np.ndarray:
    """Make a seamless loop of ``loop_n`` samples from a render of at least ``loop_n + fade_n``.

    The material that runs past the loop end is crossfaded into the loop start, so the last
    sample flows into the first exactly as the original render flowed on.
    ``curve``: ``equal_power`` (uncorrelated material such as noise) or ``linear``
    (phase-coherent material).
    """
    if x.shape[0] < loop_n + fade_n:
        raise ValueError("render too short for requested loop + crossfade")
    y = np.array(x[:loop_n], dtype=np.float64, copy=True)
    if fade_n <= 0:
        return y
    tail = x[loop_n : loop_n + fade_n]
    w = np.linspace(0.0, 1.0, fade_n, endpoint=False) + 0.5 / fade_n
    if curve == "linear":
        g_in, g_out = w, 1.0 - w
    else:
        g_in, g_out = np.sin(w * np.pi / 2), np.cos(w * np.pi / 2)
    if y.ndim == 2:
        g_in, g_out = g_in[:, None], g_out[:, None]
    y[:fade_n] = y[:fade_n] * g_in + tail * g_out
    return y


def rotate_to_zero_crossing(x: np.ndarray, search_s: float = 0.25, sr: int = SR) -> tuple[np.ndarray, int]:
    """Rotate a seamless loop so it starts at a quiet, rising zero-crossing.

    Rotation of a seamless loop is lossless, and starting on a zero-crossing guarantees the
    first buffer the engine plays (and any hard loop restart) does not click.
    Returns ``(rotated, offset)``.
    """
    n = x.shape[0]
    m = to_mono(x) if x.ndim == 2 else x
    pk = float(np.max(np.abs(x))) if n else 0.0
    if pk > 0 and float(np.max(np.abs(np.atleast_1d(x[0])))) < 1e-4 * pk and float(np.max(np.abs(np.atleast_1d(x[-1])))) < 1e-4 * pk:
        return x, 0  # already starts and ends in (near) silence
    lim = min(n - 1, n_of(search_s, sr))
    seg = m[: lim + 1]
    cand = np.nonzero((seg[:-1] <= 0) & (seg[1:] > 0))[0] + 1
    if cand.size == 0:
        return x, 0
    if x.ndim == 2:
        score = np.abs(x[cand, 0]) + np.abs(x[cand, 1]) + 0.25 * np.abs(x[cand, 0] - x[cand - 1, 0]) + 0.25 * np.abs(x[cand, 1] - x[cand - 1, 1])
    else:
        score = np.abs(x[cand]) + 0.25 * np.abs(x[cand] - x[cand - 1])
    off = int(cand[int(np.argmin(score))])
    return np.roll(x, -off, axis=0), off


def seam_metrics(x: np.ndarray) -> dict:
    """Objective loop-seam quality.

    * ``jumpRatio`` - |x[0] - x[-1]| divided by the 99th percentile of normal sample-to-sample
      steps (<= 1 means the seam step is no larger than ordinary signal motion).
    * ``hfBurstDb`` - high-frequency (2nd-difference) energy in a 10 ms window around the seam
      relative to the 95th percentile of 10 ms windows across the loop (a click shows up as a
      large positive value; normal material sits at or below 0 dB).
    """
    m = to_mono(x) if x.ndim == 2 else np.asarray(x, dtype=np.float64)
    n = m.shape[0]
    d = np.abs(np.diff(m))
    typical = float(np.percentile(d, 99)) if d.size else 1.0
    jump = float(abs(m[0] - m[-1]))
    circ = np.concatenate([m[-240:], m[:240]])
    hf_seam = np.mean(np.diff(circ, 2) ** 2)
    win = 480
    dd = np.diff(np.concatenate([m, m[:2]]), 2) ** 2
    usable = (dd.shape[0] // win) * win
    per_win = dd[:usable].reshape(-1, win).mean(axis=1) if usable else np.array([hf_seam])
    ref = float(np.percentile(per_win, 95))
    return {
        "jumpRatio": jump / max(typical, 1e-12),
        "hfBurstDb": float(10 * np.log10(max(hf_seam, 1e-20) / max(ref, 1e-20))),
        "n": int(n),
    }
