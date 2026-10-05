"""Envelopes: ADSR, exponential/percussive decays, breakpoint curves and fades."""

from __future__ import annotations

import numpy as np

from .core import LN1000, SR, n_of, t_of


def adsr(n: int, attack: float, decay: float, sustain: float, release: float, sr: int = SR, curve: float = 3.0) -> np.ndarray:
    """ADSR spanning exactly ``n`` samples; the release starts at ``n - release``.

    ``curve`` > 0 makes decay and release exponential-looking (0 = linear).
    """
    n = int(n)
    a = min(n_of(attack, sr), n)
    r = min(n_of(release, sr), n - a)
    d = min(n_of(decay, sr), n - a - r)
    s = n - a - d - r
    out = np.empty(n)
    out[:a] = np.linspace(0.0, 1.0, a, endpoint=False) if a else []

    def shaped(k, v0, v1):
        if k <= 0:
            return np.zeros(0)
        x = np.linspace(0.0, 1.0, k, endpoint=False)
        if curve > 0:
            x = (1 - np.exp(-curve * x)) / (1 - np.exp(-curve))
        return v0 + (v1 - v0) * x

    out[a : a + d] = shaped(d, 1.0, sustain)
    out[a + d : a + d + s] = sustain
    out[a + d + s :] = shaped(r, sustain if (a + d) < n else 1.0, 0.0)
    return out


def exp_decay(n: int, t60: float, sr: int = SR) -> np.ndarray:
    """Exponential decay reaching -60 dB after ``t60`` seconds."""
    return np.exp(-LN1000 * t_of(n, sr) / max(t60, 1e-6))


def perc(n: int, attack: float, t60: float, sr: int = SR, hold: float = 0.0) -> np.ndarray:
    """Percussive envelope: linear attack, optional hold, exponential decay (T60)."""
    n = int(n)
    a = min(n_of(attack, sr), n)
    h = min(n_of(hold, sr), n - a)
    out = np.empty(n)
    if a:
        out[:a] = np.linspace(0.0, 1.0, a, endpoint=False) ** 1.5
    out[a : a + h] = 1.0
    out[a + h :] = exp_decay(n - a - h, t60, sr)
    return out


def ar(n: int, attack: float, release: float, sr: int = SR) -> np.ndarray:
    """Attack/release (raised-cosine) envelope over ``n`` samples."""
    n = int(n)
    out = np.ones(n)
    a = min(n_of(attack, sr), n)
    r = min(n_of(release, sr), n - a)
    if a:
        out[:a] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    if r:
        out[n - r :] = 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return out


def breakpoints(points, n: int, sr: int = SR, kind: str = "linear") -> np.ndarray:
    """Piecewise curve through ``[(time_s, value), ...]``; ``kind`` = ``linear`` | ``exp`` | ``smooth``."""
    pts = sorted(points)
    ts = np.array([p[0] for p in pts], dtype=np.float64) * sr
    vs = np.array([p[1] for p in pts], dtype=np.float64)
    idx = np.arange(int(n), dtype=np.float64)
    if kind == "exp":
        lv = np.log(np.maximum(vs, 1e-6))
        return np.exp(np.interp(idx, ts, lv))
    if kind == "smooth":
        out = np.interp(idx, ts, vs)
        # cosine-interpolate between points for C1-ish smoothness
        seg = np.clip(np.searchsorted(ts, idx, side="right") - 1, 0, len(ts) - 2)
        t0, t1 = ts[seg], ts[seg + 1]
        frac = np.clip((idx - t0) / np.maximum(t1 - t0, 1e-9), 0.0, 1.0)
        frac = 0.5 - 0.5 * np.cos(np.pi * frac)
        out = vs[seg] + (vs[seg + 1] - vs[seg]) * frac
        out[idx < ts[0]] = vs[0]
        out[idx > ts[-1]] = vs[-1]
        return out
    return np.interp(idx, ts, vs)


def fade(x: np.ndarray, fade_in: float = 0.0, fade_out: float = 0.0, sr: int = SR) -> np.ndarray:
    """Raised-cosine fades applied in place on a copy."""
    y = np.array(x, dtype=np.float64, copy=True)
    n = y.shape[0]
    fi = min(n_of(fade_in, sr), n)
    fo = min(n_of(fade_out, sr), n)
    if fi:
        w = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, fi))
        y[:fi] *= w if y.ndim == 1 else w[:, None]
    if fo:
        w = 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, fo))
        y[n - fo :] *= w if y.ndim == 1 else w[:, None]
    return y


def gate_pattern(n: int, pattern, sr: int = SR, attack: float = 0.004, release: float = 0.01) -> np.ndarray:
    """Envelope that is 1 during ``[(start_s, dur_s), ...]`` segments with soft edges."""
    out = np.zeros(int(n))
    for start, dur in pattern:
        s = n_of(start, sr)
        k = n_of(dur, sr)
        if s >= n:
            continue
        k = min(k, n - s)
        out[s : s + k] = np.maximum(out[s : s + k], ar(k, attack, release, sr))
    return out
