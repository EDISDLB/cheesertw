"""Oscillators: band-limited classic waveforms, additive and modal synthesis, chirps.

Every oscillator accepts either a constant frequency or a per-sample frequency array,
so pitch sweeps, vibrato and Doppler curves use the same code path.  Saw and square
use PolyBLEP correction; the triangle is the leaky integral of the PolyBLEP square, so
all three are alias-suppressed.  :func:`additive` and :func:`modal` are band-limited by
construction (partials above ~0.47*SR are faded out).
"""

from __future__ import annotations

import numpy as np
from scipy.signal import lfilter

from .core import LN1000, SR, TWO_PI, as_signal, t_of


def phase(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
    """Running phase in *cycles* for a constant or time-varying frequency."""
    f = np.asarray(freq, dtype=np.float64)
    if f.ndim == 0:
        return phase0 + np.arange(n, dtype=np.float64) * (float(f) / sr)
    f = as_signal(f, n)
    ph = np.empty(n, dtype=np.float64)
    ph[0] = 0.0
    np.cumsum(f[:-1] / sr, out=ph[1:])
    return ph + phase0


def sine(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
    return np.sin(TWO_PI * phase(freq, n, sr, phase0))


def _polyblep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    out = np.zeros_like(t)
    m = t < dt
    if np.any(m):
        x = t[m] / dt[m]
        out[m] = x + x - x * x - 1.0
    m2 = t > 1.0 - dt
    if np.any(m2):
        x = (t[m2] - 1.0) / dt[m2]
        out[m2] = x * x + x + x + 1.0
    return out


def saw(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
    """Band-limited (PolyBLEP) rising sawtooth in [-1, 1]."""
    ph = phase(freq, n, sr, phase0)
    t = ph - np.floor(ph)
    dt = np.clip(as_signal(freq, n) / sr, 1e-9, 0.5)
    return 2.0 * t - 1.0 - _polyblep(t, dt)


def square(freq, n: int, sr: int = SR, pw=0.5, phase0: float = 0.0) -> np.ndarray:
    """Band-limited (PolyBLEP) pulse wave with pulse width ``pw`` (scalar or array)."""
    ph = phase(freq, n, sr, phase0)
    t = ph - np.floor(ph)
    dt = np.clip(as_signal(freq, n) / sr, 1e-9, 0.5)
    pwa = np.clip(as_signal(pw, n), 0.02, 0.98)
    y = np.where(t < pwa, 1.0, -1.0)
    y = y + _polyblep(t, dt)
    t2 = t + 1.0 - pwa
    t2 -= np.floor(t2)
    y = y - _polyblep(t2, dt)
    return y


def triangle(freq, n: int, sr: int = SR, phase0: float = 0.0) -> np.ndarray:
    """Band-limited triangle: leaky integration of the PolyBLEP square."""
    sq = square(freq, n, sr, 0.5, phase0)
    dt = as_signal(freq, n) / sr
    leak = 1.0 - np.exp(-TWO_PI * 4.0 / sr)
    a = 1.0 - leak
    y, _ = lfilter([1.0], [1.0, -a], 4.0 * dt * sq, zi=[-a])
    # remove residual drift from the leak
    y = y - lfilter([1.0 - a], [1.0, -a], y)
    peak = np.max(np.abs(y)) if n else 1.0
    return y / max(peak, 1e-9)


def additive(
    freq,
    amps,
    n: int,
    sr: int = SR,
    ratios=None,
    phases=None,
    rng: np.random.Generator | None = None,
) -> np.ndarray:
    """Sum of partials ``amps[k] * sin(2*pi*ratios[k]*phase)``.

    ``amps`` may be a list of scalars or a list of per-sample envelopes. ``ratios``
    defaults to the harmonic series. Partials are faded out as they approach Nyquist,
    which keeps sweeps alias-free.
    """
    ph = phase(freq, n, sr)
    f = as_signal(freq, n)
    count = len(amps)
    if ratios is None:
        ratios = np.arange(1, count + 1, dtype=np.float64)
    if phases is None:
        phases = rng.random(count) if rng is not None else np.zeros(count)
    out = np.zeros(n)
    nyq_lo, nyq_hi = 0.43 * sr, 0.47 * sr
    for k in range(count):
        a = amps[k]
        if np.isscalar(a) and a == 0.0:
            continue
        fk = f * ratios[k]
        guard = np.clip((nyq_hi - fk) / (nyq_hi - nyq_lo), 0.0, 1.0)
        if not np.any(guard):
            continue
        out += as_signal(a, n) * guard * np.sin(TWO_PI * (ph * ratios[k] + phases[k]))
    return out


def modal(
    freqs,
    t60s,
    amps,
    n: int,
    sr: int = SR,
    phases=None,
    rng: np.random.Generator | None = None,
    attack: float = 0.0,
) -> np.ndarray:
    """Modal synthesis: a sum of exponentially damped sinusoids (struck objects).

    ``t60s`` is the per-mode time to decay by 60 dB. Rendering of each mode stops once
    it has decayed by 90 dB, which keeps long sparse renders cheap.
    """
    freqs = np.atleast_1d(np.asarray(freqs, dtype=np.float64))
    t60s = np.broadcast_to(np.asarray(t60s, dtype=np.float64), freqs.shape)
    amps = np.broadcast_to(np.asarray(amps, dtype=np.float64), freqs.shape)
    if phases is None:
        phases = rng.random(freqs.shape[0]) if rng is not None else np.zeros(freqs.shape[0])
    out = np.zeros(n)
    for f, t60, a, p in zip(freqs, t60s, amps, phases):
        if f <= 0 or f >= 0.47 * sr or a == 0:
            continue
        m = min(n, int(1.5 * t60 * sr) + 1)
        t = t_of(m, sr)
        out[:m] += a * np.exp(-LN1000 * t / t60) * np.sin(TWO_PI * (f * t + p))
    if attack > 0:
        k = min(n, max(1, int(attack * sr)))
        out[:k] *= np.linspace(0.0, 1.0, k)
    return out


def chirp(f0: float, f1: float, n: int, sr: int = SR, curve: str = "exp", shape: float = 1.0) -> np.ndarray:
    """Frequency curve from ``f0`` to ``f1`` over ``n`` samples (``exp``, ``lin`` or ``pow``)."""
    x = np.linspace(0.0, 1.0, n)
    if curve == "lin":
        return f0 + (f1 - f0) * x
    if curve == "pow":
        return f0 + (f1 - f0) * x**shape
    return f0 * (f1 / f0) ** x


def fm(
    carrier,
    ratio: float,
    index,
    n: int,
    sr: int = SR,
    feedback: float = 0.0,
) -> np.ndarray:
    """Two-operator FM (phase modulation): ``sin(2*pi*fc*t + index*sin(2*pi*fc*ratio*t))``."""
    pc = phase(carrier, n, sr)
    pm = phase(as_signal(carrier, n) * ratio, n, sr)
    mod = np.sin(TWO_PI * pm)
    if feedback:
        mod = np.sin(TWO_PI * pm + feedback * mod)
    return np.sin(TWO_PI * pc + as_signal(index, n) * mod)


def pulse_shape(n: int, tau: float, sr: int = SR, kind: str = "gamma") -> np.ndarray:
    """Single pressure-pulse kernel used for combustion/exhaust excitation."""
    t = t_of(n, sr)
    if kind == "gamma":
        k = (t / tau) * np.exp(1.0 - t / tau)
    elif kind == "exp":
        k = np.exp(-t / tau)
    else:  # "nwave": compression followed by rarefaction
        k = (t / tau) * np.exp(1.0 - t / tau) - 0.6 * (t / (2 * tau)) * np.exp(1.0 - t / (2 * tau))
    return k
