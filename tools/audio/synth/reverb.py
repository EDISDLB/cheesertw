"""Convolution reverb with synthesised impulse responses.

IRs are built from band-split exponentially decaying noise (frequency-dependent RT60),
discrete early reflections and - for outdoor spaces - discrete, progressively darker and
more diffuse echoes.  All IRs are unit-energy so ``wet`` is a predictable send level.

Available spaces (see :data:`SPACES`): ``small_room``, ``tank_interior``, ``hangar``,
``outdoor_slapback``, ``valley_echo``, ``forest`` (soft diffuse outdoor), ``stone_hall``.
"""

from __future__ import annotations

import numpy as np
from scipy import fft as sfft
from scipy.signal import oaconvolve

from .core import LN1000, SR, n_of, t_of, to_stereo
from .filters import butter_filter, onepole_lp


def _band_noise_tail(n: int, rng: np.random.Generator, bands, sr: int, onset: float = 0.0) -> np.ndarray:
    t = t_of(n, sr)
    w = rng.standard_normal(n)
    out = np.zeros(n)
    for lo, hi, t60 in bands:
        if lo <= 20:
            b = butter_filter(w, "lowpass", hi, 4, sr)
        elif hi >= 0.45 * sr:
            b = butter_filter(w, "highpass", lo, 4, sr)
        else:
            b = butter_filter(w, "bandpass", (lo, hi), 3, sr)
        out += b * np.exp(-LN1000 * t / t60)
    if onset > 0:
        k = min(n, n_of(onset, sr))
        out[:k] *= np.linspace(0.0, 1.0, k) ** 2
    return out


def _smear(n: int, rng: np.random.Generator, length_s: float, sr: int) -> np.ndarray:
    k = max(1, n_of(length_s, sr))
    burst = rng.standard_normal(k) * np.exp(-np.linspace(0, 5, k))
    return burst / np.sqrt(np.sum(burst**2))


def _normalise(ir: np.ndarray) -> np.ndarray:
    e = np.sqrt(np.sum(ir**2))
    return ir / max(e, 1e-12)


def _build(rng: np.random.Generator, sr: int, length: float, early, bands, tail_gain: float, tail_start: float,
           echoes=(), predelay: float = 0.0, onset: float = 0.01, modes=()) -> np.ndarray:
    n = n_of(length, sr)
    ir = np.zeros(n)
    for t_s, g in early:
        i = n_of(predelay + t_s, sr)
        if i < n:
            ir[i] += g * (1 if rng.random() > 0.3 else -1)
    for t_s, g, lp, smear in echoes:
        i = n_of(predelay + t_s, sr)
        if i >= n:
            continue
        e = _smear(n, rng, smear, sr) * g
        e = onepole_lp(e, lp, sr)
        m = min(e.shape[0], n - i)
        ir[i : i + m] += e[:m]
    s = n_of(predelay + tail_start, sr)
    if s < n:
        tail = _band_noise_tail(n - s, rng, bands, sr, onset)
        tail = tail / max(np.sqrt(np.mean(tail[: max(1, n_of(0.05, sr))] ** 2)), 1e-9)
        ir[s:] += tail_gain * tail * 0.05
    t = t_of(n, sr)
    for f, t60, g in modes:
        ir += g * 0.02 * np.exp(-LN1000 * t / t60) * np.sin(2 * np.pi * f * t + rng.random() * 6.28)
    return _normalise(ir)


def impulse_response(space: str, rng: np.random.Generator, sr: int = SR, stereo: bool = False) -> np.ndarray:
    """Synthesise the IR for a named space (mono, or decorrelated stereo ``(n, 2)``)."""
    if stereo:
        left = impulse_response(space, rng, sr, False)
        right = impulse_response(space, rng, sr, False)
        m = min(left.shape[0], right.shape[0])
        return np.stack([left[:m], right[:m]], axis=1)
    if space == "small_room":
        early = [(0.0031, 0.7), (0.0053, 0.55), (0.0079, 0.45), (0.0112, 0.4), (0.0146, 0.3), (0.0193, 0.22)]
        bands = [(20, 500, 0.45), (500, 2000, 0.38), (2000, 8000, 0.26), (8000, 24000, 0.14)]
        return _build(rng, sr, 0.6, early, bands, 1.0, 0.006, onset=0.006)
    if space == "tank_interior":
        early = [(0.0012, 0.8), (0.0021, 0.7), (0.0034, 0.5), (0.0047, 0.45)]
        bands = [(20, 300, 0.32), (300, 1500, 0.22), (1500, 6000, 0.1), (6000, 24000, 0.05)]
        modes = [(95, 0.45, 1.0), (142, 0.4, 0.8), (213, 0.35, 0.7), (287, 0.3, 0.5), (431, 0.25, 0.4)]
        return _build(rng, sr, 0.5, early, bands, 1.2, 0.002, onset=0.002, modes=modes)
    if space == "hangar":
        early = [(0.021, 0.5), (0.037, 0.45), (0.052, 0.4), (0.068, 0.35), (0.083, 0.3), (0.101, 0.25)]
        bands = [(20, 250, 3.8), (250, 1000, 3.3), (1000, 4000, 2.5), (4000, 12000, 1.3), (12000, 24000, 0.6)]
        modes = [(73, 3.0, 0.4), (118, 2.8, 0.35), (161, 2.5, 0.3), (227, 2.2, 0.25)]
        return _build(rng, sr, 4.2, early, bands, 1.4, 0.03, predelay=0.012, onset=0.07, modes=modes)
    if space == "stone_hall":
        early = [(0.013, 0.5), (0.027, 0.42), (0.041, 0.35), (0.058, 0.3)]
        bands = [(20, 400, 2.6), (400, 2000, 2.2), (2000, 8000, 1.4), (8000, 24000, 0.6)]
        return _build(rng, sr, 3.0, early, bands, 1.2, 0.02, predelay=0.008, onset=0.04)
    if space == "outdoor_slapback":
        echoes = [(0.085, 0.42, 6000, 0.006), (0.142, 0.3, 4200, 0.012), (0.214, 0.22, 3000, 0.02), (0.331, 0.14, 2000, 0.035)]
        bands = [(20, 500, 1.3), (500, 2000, 0.9), (2000, 24000, 0.45)]
        return _build(rng, sr, 1.6, [(0.0, 0.0)], bands, 0.35, 0.06, echoes=echoes, onset=0.05)
    if space == "valley_echo":
        echoes = [
            (0.38, 0.55, 3200, 0.02), (0.71, 0.42, 2200, 0.045), (1.12, 0.32, 1500, 0.08),
            (1.58, 0.24, 1100, 0.12), (2.2, 0.17, 800, 0.18), (2.9, 0.11, 600, 0.25),
        ]
        bands = [(20, 300, 4.0), (300, 1500, 2.6), (1500, 24000, 0.9)]
        return _build(rng, sr, 4.5, [(0.0, 0.0)], bands, 0.3, 0.25, echoes=echoes, onset=0.35)
    if space == "forest":
        echoes = [(0.06, 0.2, 5000, 0.03), (0.12, 0.15, 3500, 0.05), (0.2, 0.1, 2500, 0.08)]
        bands = [(20, 600, 1.1), (600, 3000, 0.8), (3000, 24000, 0.4)]
        return _build(rng, sr, 1.4, [(0.0, 0.0)], bands, 0.5, 0.03, echoes=echoes, onset=0.08)
    raise ValueError(f"unknown space {space!r}")


SPACES = ("small_room", "tank_interior", "hangar", "stone_hall", "outdoor_slapback", "valley_echo", "forest")


def convolve(x: np.ndarray, ir: np.ndarray, wet: float = 0.3, dry: float = 1.0, predelay: float = 0.0,
             sr: int = SR, keep_length: bool = False) -> np.ndarray:
    """Convolution reverb. Mono input + stereo IR yields stereo output. Output includes the tail
    unless ``keep_length``."""
    stereo_out = x.ndim == 2 or ir.ndim == 2
    xs = to_stereo(x) if stereo_out else x
    irs = to_stereo(ir) if stereo_out else ir
    pd = n_of(predelay, sr)
    if stereo_out:
        wet_sig = np.stack([oaconvolve(xs[:, c], irs[:, c]) for c in range(2)], axis=1)
    else:
        wet_sig = oaconvolve(xs, irs)
    n_out = xs.shape[0] if keep_length else xs.shape[0] + irs.shape[0] - 1 + pd
    out = np.zeros((n_out,) + xs.shape[1:])
    out[: xs.shape[0]] += dry * xs
    m = min(wet_sig.shape[0], n_out - pd)
    out[pd : pd + m] += wet * wet_sig[:m]
    return out


def convolve_circular(x: np.ndarray, ir: np.ndarray, wet: float = 0.3, dry: float = 1.0) -> np.ndarray:
    """Circular convolution: the reverb tail wraps around, so a loop stays seamless."""
    n = x.shape[0]
    stereo_out = x.ndim == 2 or ir.ndim == 2
    xs = to_stereo(x) if stereo_out else x
    irs = to_stereo(ir) if stereo_out else ir
    # fold IR modulo n
    reps = int(np.ceil(irs.shape[0] / n))
    pad = np.zeros((reps * n,) + irs.shape[1:])
    pad[: irs.shape[0]] = irs
    folded = pad.reshape((reps, n) + irs.shape[1:]).sum(axis=0)
    X = sfft.rfft(xs, axis=0)
    H = sfft.rfft(folded, axis=0)
    w = sfft.irfft(X * H, n, axis=0)
    return dry * xs + wet * w
