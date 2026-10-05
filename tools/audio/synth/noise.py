"""Noise generators and random control signals.

The coloured noises are generated in the frequency domain, which makes them *exactly
periodic over their length* - a property the loop builders rely on: a pink-noise bed of
``n`` samples wraps around seamlessly.
"""

from __future__ import annotations

import numpy as np
from scipy import fft as sfft

from .core import SR


def white(n: int, rng: np.random.Generator) -> np.ndarray:
    """Gaussian white noise, unit RMS."""
    return rng.standard_normal(int(n))


def _shaped(n: int, rng: np.random.Generator, weight) -> np.ndarray:
    n = int(n)
    if n < 4:
        return np.zeros(n)
    spec = sfft.rfft(rng.standard_normal(n))
    f = np.arange(spec.shape[0], dtype=np.float64)
    spec *= weight(f)
    spec[0] = 0.0
    y = sfft.irfft(spec, n)
    rms = np.sqrt(np.mean(y * y))
    return y / max(rms, 1e-12)


def pink(n: int, rng: np.random.Generator, sr: int = SR, f_lo: float = 10.0) -> np.ndarray:
    """1/f noise (-3 dB/oct), unit RMS, periodic over ``n``."""
    bin_lo = max(1.0, f_lo * n / sr)
    return _shaped(n, rng, lambda f: 1.0 / np.sqrt(np.maximum(f, bin_lo)))


def brown(n: int, rng: np.random.Generator, sr: int = SR, f_lo: float = 15.0) -> np.ndarray:
    """1/f^2 noise (-6 dB/oct), unit RMS, periodic over ``n``."""
    bin_lo = max(1.0, f_lo * n / sr)
    return _shaped(n, rng, lambda f: 1.0 / np.maximum(f, bin_lo))


def colored(n: int, rng: np.random.Generator, slope_db_oct: float, sr: int = SR, f_ref: float = 1000.0) -> np.ndarray:
    """Noise with an arbitrary spectral slope in dB/octave (periodic)."""
    ref_bin = f_ref * n / sr
    expo = slope_db_oct / 6.0206

    def w(f):
        return np.power(np.maximum(f, 1.0) / ref_bin, expo)

    return _shaped(n, rng, w)


def band(n: int, rng: np.random.Generator, lo: float, hi: float, sr: int = SR, soft: float = 0.15) -> np.ndarray:
    """Band-limited noise between ``lo`` and ``hi`` Hz with soft (log-cosine) skirts. Periodic."""
    freqs = lambda b: b * sr / n  # noqa: E731

    def w(b):
        f = np.maximum(freqs(b), 1e-3)
        lf = np.log2(f)
        lo_l, hi_l = np.log2(max(lo, 1.0)), np.log2(max(hi, lo + 1.0))
        g = np.ones_like(f)
        g = np.where(lf < lo_l, np.cos(np.clip((lo_l - lf) / max(soft, 1e-3), 0, 1) * np.pi / 2) ** 2, g)
        g = np.where(lf > hi_l, np.cos(np.clip((lf - hi_l) / max(soft, 1e-3), 0, 1) * np.pi / 2) ** 2, g)
        return g

    return _shaped(n, rng, w)


def smooth_random(n: int, rng: np.random.Generator, rate_hz: float, sr: int = SR) -> np.ndarray:
    """Smooth random control curve in [-1, 1] with content up to ``rate_hz``.

    Generated spectrally, so it is periodic over ``n`` (loop-safe modulation source).
    """
    n = int(n)
    if n < 4:
        return np.zeros(n)
    bins = n // 2 + 1
    spec = np.zeros(bins, dtype=np.complex128)
    kmax = max(1, int(rate_hz * n / sr))
    kmax = min(kmax, bins - 1)
    k = np.arange(1, kmax + 1)
    mag = 1.0 / np.sqrt(k)  # gentle 1/f so slow motion dominates
    ph = rng.random(kmax) * 2 * np.pi
    spec[1 : kmax + 1] = mag * np.exp(1j * ph)
    y = sfft.irfft(spec, n)
    peak = np.max(np.abs(y))
    return y / max(peak, 1e-12)


def events(
    duration_n: int,
    rate_hz: float,
    rng: np.random.Generator,
    sr: int = SR,
    regular: float = 0.0,
    start_n: int = 0,
) -> np.ndarray:
    """Event times (sample indices) of a Poisson process (``regular`` in [0,1] blends toward a grid)."""
    if rate_hz <= 0:
        return np.zeros(0, dtype=np.int64)
    mean_gap = sr / rate_hz
    times = []
    t = rng.exponential(mean_gap) * (1 - regular) + regular * mean_gap * rng.random()
    while t < duration_n:
        times.append(int(t) + start_n)
        gap = (1 - regular) * rng.exponential(mean_gap) + regular * mean_gap
        t += max(1.0, gap)
    return np.asarray(times, dtype=np.int64)


def dust(n: int, rate_hz: float, rng: np.random.Generator, sr: int = SR, signed: bool = True, amp_spread: float = 1.0) -> np.ndarray:
    """Sparse random impulses ("crackle" excitation)."""
    out = np.zeros(int(n))
    idx = events(n, rate_hz, rng, sr)
    if idx.size == 0:
        return out
    amps = np.exp(-amp_spread * rng.random(idx.size) * 3.0)
    if signed:
        amps *= rng.choice([-1.0, 1.0], idx.size)
    np.add.at(out, idx, amps)
    return out


def velvet(n: int, density_hz: float, rng: np.random.Generator, sr: int = SR) -> np.ndarray:
    """Velvet noise: one +/-1 impulse per grid cell at random position (smooth, sparse)."""
    out = np.zeros(int(n))
    step = max(1, int(sr / density_hz))
    starts = np.arange(0, n, step)
    pos = starts + rng.integers(0, step, starts.size)
    pos = pos[pos < n]
    out[pos] = rng.choice([-1.0, 1.0], pos.size)
    return out
