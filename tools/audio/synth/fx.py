"""Effects: saturation/distortion, bit reduction, delay, dynamics, resampling pitch shift,
variable-speed playback (Doppler/spool curves) and granular textures."""

from __future__ import annotations

from fractions import Fraction

import numpy as np
from scipy.ndimage import maximum_filter1d, minimum_filter1d, uniform_filter1d
from scipy.signal import lfilter, resample_poly

from .core import SR, as_signal, n_of
from .filters import onepole_lp


# --------------------------------------------------------------------------- distortion
def saturate(x: np.ndarray, drive: float = 2.0, kind: str = "tanh", bias: float = 0.0) -> np.ndarray:
    """Memoryless waveshaper. ``kind``: tanh | soft (cubic) | hard | asym | fold | diode.

    The output is scaled so that a full-scale input maps near full scale, so ``drive``
    changes the *character* more than the level.
    """
    d = max(float(drive), 1e-6)
    if kind == "tanh":
        y = np.tanh(d * x + bias) - np.tanh(bias)
        return y / np.tanh(d)
    if kind == "soft":
        z = np.clip(d * x, -1.5, 1.5)
        return (z - (4.0 / 27.0) * z**3) / (1.5 - (4.0 / 27.0) * 3.375)
    if kind == "hard":
        return np.clip(d * x, -1.0, 1.0)
    if kind == "asym":  # tube-ish: even harmonics
        z = d * x + bias
        y = np.where(z >= 0, np.tanh(z), np.tanh(0.6 * z) / 0.6 * 0.8) - (np.tanh(bias) if bias >= 0 else np.tanh(0.6 * bias) / 0.6 * 0.8)
        return y / np.tanh(d)
    if kind == "fold":
        return np.sin(0.5 * np.pi * d * x)
    if kind == "diode":
        return (np.sign(x) * (1.0 - np.exp(-d * np.abs(x)))) / (1.0 - np.exp(-d))
    raise ValueError(kind)


def bitcrush(x: np.ndarray, bits: float = 8.0, downsample: int = 1) -> np.ndarray:
    """Quantisation to ``bits`` and sample-and-hold decimation (radio/lo-fi grit)."""
    y = np.array(x, dtype=np.float64, copy=True)
    if downsample > 1:
        idx = (np.arange(y.shape[0]) // downsample) * downsample
        y = y[idx]
    q = 2.0 ** (bits - 1)
    return np.round(y * q) / q


# --------------------------------------------------------------------------- delay
def delay(
    x: np.ndarray,
    time_s: float,
    feedback: float = 0.35,
    mix: float = 0.3,
    lp_hz: float | None = 4000.0,
    tail_s: float | None = None,
    sr: int = SR,
) -> np.ndarray:
    """Feedback delay with an optional low-pass in the loop; output is extended by the tail."""
    d = max(1, n_of(time_s, sr))
    if tail_s is None:
        repeats = int(np.ceil(np.log(1e-3) / np.log(max(abs(feedback), 1e-3)))) if feedback else 1
        tail = d * max(1, repeats)
    else:
        tail = n_of(tail_s, sr)
    n = x.shape[0]
    out_shape = (n + tail,) + x.shape[1:]
    wet = np.zeros(out_shape)
    echo = np.array(x, dtype=np.float64, copy=True)
    g = 1.0
    k = 1
    while k * d < n + tail:
        if lp_hz:
            echo = onepole_lp(echo, lp_hz, sr)
        start = k * d
        m = min(n, n + tail - start)
        wet[start : start + m] += g * echo[:m]
        g *= feedback
        if abs(g) < 1e-4:
            break
        k += 1
    out = np.zeros(out_shape)
    out[:n] += x
    return out + mix * wet


# --------------------------------------------------------------------------- dynamics
def envelope_follower(x: np.ndarray, attack: float, release: float, sr: int = SR, rms: bool = False) -> np.ndarray:
    """Peak (or RMS) envelope with distinct attack/release (vectorised approximation)."""
    mono = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    if rms:
        mono = mono * mono
    a_att = np.exp(-1.0 / max(attack * sr, 1.0))
    a_rel = np.exp(-1.0 / max(release * sr, 1.0))
    fast = lfilter([1 - a_att], [1, -a_att], mono)
    slow = lfilter([1 - a_rel], [1, -a_rel], maximum_filter1d(mono, size=max(1, int(attack * sr) * 4 + 1)))
    env = np.maximum(fast, slow)
    return np.sqrt(env) if rms else env


def compressor_gain(
    x: np.ndarray,
    threshold_db: float = -18.0,
    ratio: float = 4.0,
    attack: float = 0.005,
    release: float = 0.12,
    knee_db: float = 6.0,
    makeup_db: float = 0.0,
    sr: int = SR,
) -> np.ndarray:
    """Per-sample linear gain of a feed-forward soft-knee compressor detecting on ``x``.

    Returning the gain (instead of the processed signal) lets several stems share one detector
    (linked compression of music stems that must still sum to the mastered mix)."""
    env = envelope_follower(x, attack, release, sr)
    lvl = 20.0 * np.log10(np.maximum(env, 1e-9))
    over = lvl - threshold_db
    gr = np.where(
        over <= -knee_db / 2,
        0.0,
        np.where(
            over >= knee_db / 2,
            over * (1.0 - 1.0 / ratio),
            (1.0 - 1.0 / ratio) * (over + knee_db / 2) ** 2 / (2 * max(knee_db, 1e-6)),
        ),
    )
    return 10.0 ** ((makeup_db - gr) / 20.0)


def compressor(
    x: np.ndarray,
    threshold_db: float = -18.0,
    ratio: float = 4.0,
    attack: float = 0.005,
    release: float = 0.12,
    knee_db: float = 6.0,
    makeup_db: float = 0.0,
    sr: int = SR,
) -> np.ndarray:
    """Feed-forward soft-knee compressor."""
    g = compressor_gain(x, threshold_db, ratio, attack, release, knee_db, makeup_db, sr)
    return x * (g if x.ndim == 1 else g[:, None])


def limiter_gain(x: np.ndarray, ceiling_db: float = -1.0, lookahead: float = 0.002, release: float = 0.06,
                 sr: int = SR) -> np.ndarray:
    """Per-sample gain of the look-ahead brick-wall limiter (``x * g`` stays under the ceiling).
    ``x`` may be a detector signal (e.g. the max of several stems) rather than the audio itself."""
    ceiling = 10.0 ** (ceiling_db / 20.0)
    peak = np.max(np.abs(x), axis=1) if x.ndim == 2 else np.abs(x)
    need = np.minimum(1.0, ceiling / np.maximum(peak, 1e-12))
    L = max(1, int(lookahead * sr))
    held = minimum_filter1d(need, size=2 * L + 1, mode="nearest")
    # moving average of the held gain: smooth attack that still reaches the required gain in time
    smooth_g = uniform_filter1d(held, size=L, mode="nearest") if L > 1 else held
    # slow release: a lagging one-pole copy; taking the minimum keeps attacks fast, releases slow
    a = np.exp(-1.0 / max(release * sr, 1.0))
    rel = lfilter([1 - a], [1, -a], smooth_g, zi=[a * smooth_g[0]])[0] if x.shape[0] else smooth_g
    return np.minimum(np.minimum(smooth_g, rel), need)


def limiter(x: np.ndarray, ceiling_db: float = -1.0, lookahead: float = 0.002, release: float = 0.06, sr: int = SR) -> np.ndarray:
    """Look-ahead brick-wall limiter. Guarantees ``|y| <= ceiling`` (sample peak)."""
    ceiling = 10.0 ** (ceiling_db / 20.0)
    g = limiter_gain(x, ceiling_db, lookahead, release, sr)
    y = x * (g if x.ndim == 1 else g[:, None])
    return np.clip(y, -ceiling, ceiling)


def transient_shaper(x: np.ndarray, attack_gain_db: float = 6.0, sustain_gain_db: float = 0.0, sr: int = SR) -> np.ndarray:
    """Boost/cut attacks vs sustain using fast/slow envelope difference."""
    fast = envelope_follower(x, 0.0005, 0.02, sr)
    slow = envelope_follower(x, 0.02, 0.2, sr)
    diff = np.clip((fast - slow) / np.maximum(fast, 1e-9), 0.0, 1.0)
    gdb = attack_gain_db * diff + sustain_gain_db * (1.0 - diff)
    g = 10.0 ** (gdb / 20.0)
    return x * (g if x.ndim == 1 else g[:, None])


# --------------------------------------------------------------------------- resampling
def pitch_shift(x: np.ndarray, semitones: float = 0.0, ratio: float | None = None) -> np.ndarray:
    """Pitch shift by resampling (changes duration, like tape/PlaybackSpeed)."""
    r = ratio if ratio is not None else 2.0 ** (semitones / 12.0)
    if abs(r - 1.0) < 1e-6:
        return np.array(x, copy=True)
    frac = Fraction(r).limit_denominator(480)
    # playing back r times faster == resample to 1/r of the length
    return resample_poly(x, frac.denominator, frac.numerator, axis=0)


def varispeed(x: np.ndarray, rate, out_n: int | None = None) -> np.ndarray:
    """Variable-speed playback (``rate`` = per-output-sample speed, 1 = original).

    Used for Doppler, spool-up/down and tape-like pitch bends. Cubic (Catmull-Rom)
    interpolation keeps it clean enough for SFX.
    """
    n_in = x.shape[0]
    if out_n is None:
        mean_rate = float(np.mean(np.asarray(rate))) if np.ndim(rate) else float(rate)
        out_n = int(n_in / max(mean_rate, 1e-6))
    r = as_signal(rate, out_n)
    pos = np.concatenate([[0.0], np.cumsum(r[:-1])])
    pos = np.clip(pos, 0, n_in - 1.001)
    i = np.floor(pos).astype(np.int64)
    f = pos - i
    xp = np.concatenate([x[:1], x, x[-1:], x[-1:]], axis=0)
    p0, p1, p2, p3 = xp[i], xp[i + 1], xp[i + 2], xp[i + 3]
    if x.ndim == 2:
        f = f[:, None]
    return p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0)))


# --------------------------------------------------------------------------- granular
def granular(
    source: np.ndarray,
    out_n: int,
    rng: np.random.Generator,
    grain_s: float = 0.05,
    density_hz: float = 60.0,
    pitch_jitter_st: float = 2.0,
    amp_jitter_db: float = 6.0,
    position=None,
    position_jitter_s: float = 0.05,
    sr: int = SR,
) -> np.ndarray:
    """Granular texture from ``source`` (mono).

    ``position`` is a curve (0..1, per output sample) choosing where in the source each
    grain is read; ``None`` scatters grains uniformly. Grain pitch/amp are jittered.
    """
    src = source if source.ndim == 1 else source.mean(axis=1)
    out = np.zeros(int(out_n))
    g_n = max(16, n_of(grain_s, sr))
    starts = np.sort(rng.integers(0, max(1, out_n - 1), int(density_hz * out_n / sr) + 1))
    pos_curve = None if position is None else as_signal(position, out_n)
    win_cache: dict[int, np.ndarray] = {}
    for s in starts:
        ratio = 2.0 ** (rng.uniform(-pitch_jitter_st, pitch_jitter_st) / 12.0)
        read_n = int(g_n * ratio) + 4
        if pos_curve is None:
            p = rng.uniform(0, 1)
        else:
            p = pos_curve[s] + rng.normal(0, position_jitter_s * sr / max(src.shape[0], 1))
        p0 = int(np.clip(p, 0, 1) * max(0, src.shape[0] - read_n - 1))
        seg = src[p0 : p0 + read_n]
        if seg.shape[0] < 4:
            continue
        grain = np.interp(np.arange(g_n) * ratio, np.arange(seg.shape[0]), seg)
        if g_n not in win_cache:
            win_cache[g_n] = np.hanning(g_n)
        amp = 10.0 ** (-rng.uniform(0, amp_jitter_db) / 20.0)
        e = min(out_n, s + g_n)
        out[s:e] += amp * grain[: e - s] * win_cache[g_n][: e - s]
    return out
