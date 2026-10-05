"""Core constants and helpers for the HULLDOWN DSP library.

Conventions used across the whole library:

* Sample rate defaults to :data:`SR` (48 kHz).
* Mono signals are 1-D ``float64`` arrays of shape ``(n,)``.
* Stereo signals are 2-D arrays of shape ``(n, 2)`` (the layout soundfile uses).
* Every function that needs randomness takes an explicit ``numpy.random.Generator``;
  :func:`make_rng` derives one deterministically from string parts, so a sound key
  always renders bit-identically.
"""

from __future__ import annotations

import hashlib
from typing import Iterable

import numpy as np

SR = 48000
TWO_PI = 2.0 * np.pi
LN1000 = 6.907755278982137  # ln(1000): converts T60 to an exponential time constant


def n_of(seconds: float, sr: int = SR) -> int:
    """Number of samples for a duration (rounded, never negative)."""
    return max(0, int(round(float(seconds) * sr)))


def t_of(n: int, sr: int = SR) -> np.ndarray:
    """Time axis in seconds for ``n`` samples."""
    return np.arange(int(n), dtype=np.float64) / sr


def seed_of(*parts: object) -> int:
    """Stable 64-bit seed from arbitrary parts (independent of PYTHONHASHSEED)."""
    text = "::".join(str(p) for p in parts).encode("utf-8")
    return int.from_bytes(hashlib.sha256(text).digest()[:8], "little")


def make_rng(*parts: object) -> np.random.Generator:
    """Deterministic PCG64 generator seeded from ``parts``."""
    return np.random.Generator(np.random.PCG64(seed_of(*parts)))


def child_rng(rng: np.random.Generator) -> np.random.Generator:
    """Independent generator spawned from ``rng`` (keeps layer streams decoupled)."""
    return np.random.Generator(np.random.PCG64(int(rng.integers(0, 2**63 - 1))))


def db_to_amp(db):
    return np.power(10.0, np.asarray(db, dtype=np.float64) / 20.0)


def amp_to_db(amp, floor: float = -150.0):
    a = np.maximum(np.abs(np.asarray(amp, dtype=np.float64)), 1e-30)
    return np.maximum(20.0 * np.log10(a), floor)


def as_signal(value, n: int) -> np.ndarray:
    """Broadcast a scalar or array to a float64 control signal of length ``n``."""
    arr = np.asarray(value, dtype=np.float64)
    if arr.ndim == 0:
        return np.full(int(n), float(arr))
    if arr.shape[0] != n:
        # Resample control curves of a different length (linear) so callers can pass coarse curves.
        src = np.linspace(0.0, 1.0, arr.shape[0])
        dst = np.linspace(0.0, 1.0, int(n))
        return np.interp(dst, src, arr)
    return arr


def is_stereo(x: np.ndarray) -> bool:
    return x.ndim == 2


def to_stereo(x: np.ndarray) -> np.ndarray:
    if x.ndim == 2:
        return x
    return np.stack([x, x], axis=1)


def to_mono(x: np.ndarray) -> np.ndarray:
    if x.ndim == 1:
        return x
    return x.mean(axis=1)


def match_channels(a: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Promote both signals to stereo if either one is stereo."""
    if a.ndim == b.ndim:
        return a, b
    return to_stereo(a), to_stereo(b)


def silence(n: int, channels: int = 1) -> np.ndarray:
    return np.zeros(int(n)) if channels == 1 else np.zeros((int(n), channels))


def semitones(st: float) -> float:
    """Frequency ratio for a number of semitones."""
    return float(2.0 ** (st / 12.0))


def note_hz(name: str) -> float:
    """Equal-tempered frequency for a note name such as ``"A4"``, ``"F#3"`` or ``"Bb5"``."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    letter = name[0].upper()
    rest = name[1:]
    offset = 0
    while rest and rest[0] in "#b":
        offset += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    octave = int(rest)
    midi = 12 * (octave + 1) + names[letter] + offset
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


def chunks(n: int, size: int) -> Iterable[tuple[int, int]]:
    for s in range(0, n, size):
        yield s, min(n, s + size)
