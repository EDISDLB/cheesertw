"""Filters: RBJ biquads (fixed and time-varying), one-poles, Butterworth, resonator banks, combs.

All filters operate along axis 0, so they work unchanged on mono ``(n,)`` and stereo
``(n, 2)`` signals.  Time-varying filters (resonant sweeps, wind, wah-like motion) are
processed in short blocks with the DF2T state carried across blocks.
"""

from __future__ import annotations

import numpy as np
from scipy.signal import butter, lfilter, lfilter_zi, sosfilt  # noqa: F401  (lfilter_zi re-exported)

from .core import SR, TWO_PI, as_signal

KINDS = ("lowpass", "highpass", "bandpass", "notch", "peaking", "lowshelf", "highshelf", "allpass")


def biquad_coeffs(kind: str, f0: float, q: float = 0.7071, gain_db: float = 0.0, sr: int = SR):
    """RBJ Audio-EQ-Cookbook coefficients ``(b, a)`` normalised so ``a[0] == 1``."""
    f0 = float(np.clip(f0, 1.0, 0.495 * sr))
    q = max(float(q), 1e-3)
    w0 = TWO_PI * f0 / sr
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2.0 * q)
    A = 10.0 ** (gain_db / 40.0)
    if kind == "lowpass":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "highpass":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bandpass":  # constant 0 dB peak gain
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "notch":
        b = [1.0, -2 * cw, 1.0]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "allpass":
        b = [1 - alpha, -2 * cw, 1 + alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peaking":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        sa = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + sa), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sa)]
        a = [(A + 1) + (A - 1) * cw + sa, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sa]
    elif kind == "highshelf":
        sa = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sa), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sa)]
        a = [(A + 1) - (A - 1) * cw + sa, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sa]
    else:
        raise ValueError(f"unknown biquad kind {kind!r}")
    b = np.asarray(b, dtype=np.float64)
    a = np.asarray(a, dtype=np.float64)
    return b / a[0], a / a[0]


def biquad(x: np.ndarray, kind: str, f0: float, q: float = 0.7071, gain_db: float = 0.0, sr: int = SR) -> np.ndarray:
    b, a = biquad_coeffs(kind, f0, q, gain_db, sr)
    return lfilter(b, a, x, axis=0)


def butter_filter(x: np.ndarray, kind: str, f, order: int = 4, sr: int = SR) -> np.ndarray:
    """Butterworth low/high/band-pass (``f`` is a scalar or a ``(lo, hi)`` pair)."""
    if np.ndim(f) == 0:
        wn = float(np.clip(f, 1.0, 0.49 * sr))
    else:
        wn = [float(np.clip(f[0], 1.0, 0.49 * sr)), float(np.clip(f[1], 2.0, 0.49 * sr))]
    btype = {"lowpass": "lowpass", "highpass": "highpass", "bandpass": "bandpass", "bandstop": "bandstop"}[kind]
    sos = butter(order, wn, btype=btype, fs=sr, output="sos")
    return sosfilt(sos, x, axis=0)


def lowpass(x: np.ndarray, f: float, order: int = 2, q: float | None = None, sr: int = SR) -> np.ndarray:
    if order == 1:
        return onepole_lp(x, f, sr)
    if q is not None and order == 2:
        return biquad(x, "lowpass", f, q, sr=sr)
    return butter_filter(x, "lowpass", f, order, sr)


def highpass(x: np.ndarray, f: float, order: int = 2, q: float | None = None, sr: int = SR) -> np.ndarray:
    if order == 1:
        return onepole_hp(x, f, sr)
    if q is not None and order == 2:
        return biquad(x, "highpass", f, q, sr=sr)
    return butter_filter(x, "highpass", f, order, sr)


def bandpass(x: np.ndarray, f: float, q: float = 1.0, sr: int = SR) -> np.ndarray:
    return biquad(x, "bandpass", f, q, sr=sr)


def band(x: np.ndarray, lo: float, hi: float, order: int = 2, sr: int = SR) -> np.ndarray:
    """Butterworth band-pass between ``lo`` and ``hi`` Hz."""
    return butter_filter(x, "bandpass", (lo, hi), order, sr)


def notch(x: np.ndarray, f: float, q: float = 4.0, sr: int = SR) -> np.ndarray:
    return biquad(x, "notch", f, q, sr=sr)


def peaking(x: np.ndarray, f: float, gain_db: float, q: float = 1.0, sr: int = SR) -> np.ndarray:
    return biquad(x, "peaking", f, q, gain_db, sr)


def lowshelf(x: np.ndarray, f: float, gain_db: float, q: float = 0.7071, sr: int = SR) -> np.ndarray:
    return biquad(x, "lowshelf", f, q, gain_db, sr)


def highshelf(x: np.ndarray, f: float, gain_db: float, q: float = 0.7071, sr: int = SR) -> np.ndarray:
    return biquad(x, "highshelf", f, q, gain_db, sr)


def onepole_lp(x: np.ndarray, fc: float, sr: int = SR) -> np.ndarray:
    a = np.exp(-TWO_PI * float(np.clip(fc, 0.01, 0.49 * sr)) / sr)
    return lfilter([1.0 - a], [1.0, -a], x, axis=0)


def onepole_hp(x: np.ndarray, fc: float, sr: int = SR) -> np.ndarray:
    return x - onepole_lp(x, fc, sr)


def smooth(x: np.ndarray, seconds: float, sr: int = SR) -> np.ndarray:
    """One-pole smoothing with a time constant in seconds (for control curves)."""
    a = np.exp(-1.0 / max(seconds * sr, 1e-9))
    return lfilter([1.0 - a], [1.0, -a], x, axis=0)


def tv_biquad(
    x: np.ndarray,
    kind: str,
    f0,
    q=0.7071,
    gain_db=0.0,
    block: int = 64,
    sr: int = SR,
) -> np.ndarray:
    """Time-varying biquad (resonant sweeps): ``f0``/``q``/``gain_db`` may be per-sample arrays."""
    n = x.shape[0]
    f = as_signal(f0, n)
    qa = as_signal(q, n)
    ga = as_signal(gain_db, n)
    y = np.empty_like(x, dtype=np.float64)
    zi = np.zeros((2,) + x.shape[1:])
    for s in range(0, n, block):
        e = min(n, s + block)
        m = (s + e - 1) // 2
        b, a = biquad_coeffs(kind, f[m], qa[m], ga[m], sr)
        y[s:e], zi = lfilter(b, a, x[s:e], axis=0, zi=zi)
    return y


def tv_lowpass(x: np.ndarray, f0, q=0.7071, block: int = 64, sr: int = SR) -> np.ndarray:
    return tv_biquad(x, "lowpass", f0, q, 0.0, block, sr)


def tv_bandpass(x: np.ndarray, f0, q=1.0, block: int = 64, sr: int = SR) -> np.ndarray:
    return tv_biquad(x, "bandpass", f0, q, 0.0, block, sr)


def tv_onepole_lp(x: np.ndarray, fc, sr: int = SR, block: int = 64) -> np.ndarray:
    """Time-varying one-pole low-pass (gentle distance/occlusion style darkening)."""
    n = x.shape[0]
    f = as_signal(fc, n)
    y = np.empty_like(x, dtype=np.float64)
    zi = np.zeros((1,) + x.shape[1:])
    for s in range(0, n, block):
        e = min(n, s + block)
        a = np.exp(-TWO_PI * float(np.clip(f[(s + e - 1) // 2], 1.0, 0.49 * sr)) / sr)
        y[s:e], zi = lfilter([1.0 - a], [1.0, -a], x[s:e], axis=0, zi=zi)
    return y


def resonators(x: np.ndarray, freqs, qs, gains, sr: int = SR) -> np.ndarray:
    """Parallel band-pass resonator bank (formants, body resonances)."""
    freqs = np.atleast_1d(freqs)
    qs = np.broadcast_to(np.asarray(qs, dtype=np.float64), freqs.shape)
    gains = np.broadcast_to(np.asarray(gains, dtype=np.float64), freqs.shape)
    out = np.zeros_like(x, dtype=np.float64)
    for f, q, g in zip(freqs, qs, gains):
        if g == 0:
            continue
        out += g * biquad(x, "bandpass", f, q, sr=sr)
    return out


def comb(x: np.ndarray, delay_s: float, feedback: float, sr: int = SR, damp_hz: float | None = None) -> np.ndarray:
    """Feedback comb filter (pitched metallic/tube resonance). Optional damping LP in the loop."""
    d = max(1, int(round(delay_s * sr)))
    if damp_hz is None:
        a = np.zeros(d + 1)
        a[0] = 1.0
        a[d] = -feedback
        return lfilter([1.0], a, x, axis=0)
    # damped comb: iterate echoes explicitly (cheap for the short signals it is used on)
    n = x.shape[0]
    out = np.array(x, dtype=np.float64, copy=True)
    echo = np.array(x, dtype=np.float64, copy=True)
    g = 1.0
    k = 1
    while True:
        g *= feedback
        if abs(g) < 1e-4 or k * d >= n:
            break
        echo = onepole_lp(echo, damp_hz, sr)
        out[k * d :] += g * echo[: n - k * d]
        k += 1
    return out


def dc_block(x: np.ndarray, fc: float = 12.0, sr: int = SR) -> np.ndarray:
    """2nd-order Butterworth high-pass at ``fc`` (removes DC and sub-sonic drift)."""
    return butter_filter(x, "highpass", fc, 2, sr)


def tilt(x: np.ndarray, db_per_oct: float, pivot: float = 1000.0, sr: int = SR) -> np.ndarray:
    """Approximate spectral tilt using a pair of opposite shelves around ``pivot``."""
    g = db_per_oct * 3.0
    y = lowshelf(x, pivot / 4, -g / 2, sr=sr)
    return highshelf(y, pivot * 4, g / 2, sr=sr)
