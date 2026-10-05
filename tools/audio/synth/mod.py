"""Modulation sources and operators: LFOs, AM/ring modulation, vibrato, loop-safe frequency snapping."""

from __future__ import annotations

import numpy as np

from .core import SR, TWO_PI, as_signal, t_of
from .osc import phase


def snap_freq(freq: float, loop_n: int, sr: int = SR, min_cycles: int = 1) -> float:
    """Nearest frequency that completes an integer number of cycles in ``loop_n`` samples.

    Any periodic component built from snapped frequencies wraps seamlessly at the loop point.
    """
    cycles = max(min_cycles, int(round(freq * loop_n / sr)))
    return cycles * sr / loop_n


def lfo(n: int, rate, shape: str = "sine", depth: float = 1.0, offset: float = 0.0, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
    """Low-frequency oscillator: ``offset + depth * wave``; shapes sine/tri/saw/square/sh(sample&hold)."""
    ph = phase(rate, n, sr, phase0)
    frac = ph - np.floor(ph)
    if shape == "sine":
        w = np.sin(TWO_PI * ph)
    elif shape == "tri":
        w = 1.0 - 4.0 * np.abs(frac - 0.5)
    elif shape == "saw":
        w = 2.0 * frac - 1.0
    elif shape == "square":
        w = np.where(frac < 0.5, 1.0, -1.0)
    elif shape == "sh":
        steps = np.floor(ph).astype(np.int64)
        rng = np.random.default_rng(int(abs(phase0) * 1e6) + 7)
        vals = rng.uniform(-1, 1, steps.max() + 2 if n else 1)
        w = vals[steps - steps.min()]
    else:
        raise ValueError(shape)
    return offset + depth * w


def am(x: np.ndarray, mod: np.ndarray, depth: float = 1.0) -> np.ndarray:
    """Amplitude modulation: ``x * (1 - depth + depth * (mod+1)/2)`` for ``mod`` in [-1, 1]."""
    g = 1.0 - depth + depth * 0.5 * (np.asarray(mod) + 1.0)
    return x * (g if x.ndim == 1 else g[:, None])


def ring(x: np.ndarray, freq, mix: float = 1.0, sr: int = SR) -> np.ndarray:
    """Ring modulation with a sine carrier (``mix`` blends with the dry signal)."""
    c = np.sin(TWO_PI * phase(freq, x.shape[0], sr))
    if x.ndim == 2:
        c = c[:, None]
    return (1.0 - mix) * x + mix * x * c


def vibrato(freq, n: int, rate: float, cents: float, sr: int = SR, delay: float = 0.0, rise: float = 0.0) -> np.ndarray:
    """Frequency curve with sinusoidal vibrato (optionally delayed and faded in)."""
    f = as_signal(freq, n)
    depth = np.ones(n)
    if delay or rise:
        t = t_of(n, sr)
        depth = np.clip((t - delay) / max(rise, 1e-6), 0.0, 1.0)
    return f * 2.0 ** (cents * depth * np.sin(TWO_PI * rate * t_of(n, sr)) / 1200.0)


def tremolo(x: np.ndarray, rate, depth: float, sr: int = SR, shape: str = "sine") -> np.ndarray:
    return am(x, lfo(x.shape[0], rate, shape, sr=sr), depth)


def doppler_curve(n: int, f_source: float, speed: float, miss_distance: float, t_closest: float, sr: int = SR, c: float = 343.0):
    """Received frequency and 1/r gain for a source passing a listener in a straight line.

    Returns ``(freq_curve, gain_curve)``; ``gain`` is normalised to 1 at closest approach.
    """
    t = t_of(n, sr) - t_closest
    x = speed * t  # along-track position relative to closest point
    r = np.sqrt(x * x + miss_distance**2)
    v_radial = speed * x / r  # positive when receding
    v_radial = np.clip(v_radial, -0.95 * c, 0.95 * c)
    freq = f_source * c / (c + v_radial)
    gain = miss_distance / r
    return freq, gain
