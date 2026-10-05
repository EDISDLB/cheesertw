"""Shared sound-design building blocks (layers reused by several categories).

Everything here is pure synthesis: blasts, booms, modal metal/wood/brass hits, debris
showers, whooshes, bubbles, creaks, crackle, radio processing, bells and wind.
"""

from __future__ import annotations

import numpy as np

from synth import env, filters, fx, mix, mod, noise, osc, reverb
from synth.core import LN1000, SR, child_rng, n_of, t_of

# --------------------------------------------------------------------------- modal tables
MODE_RATIOS = {
    # free-free bar (struck rod / gun barrel / track pin)
    "bar": [1.0, 2.756, 5.404, 8.933, 13.344, 18.638],
    # thick steel plate: dense, inharmonic
    "plate": [1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.50, 4.15, 4.62, 5.40, 6.21, 7.08],
    # thin-walled tube (brass shell case): close pairs produce beating
    "tube": [1.0, 1.012, 2.32, 2.345, 4.25, 4.28, 6.63, 9.38],
    # church-bell-like partials (hum, prime, tierce, quint, nominal, ...)
    "bell": [0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166, 5.433, 6.796, 8.215],
    # wooden plank / beam
    "wood": [1.0, 2.57, 4.21, 6.13, 8.5],
    # rock / brick chunk
    "rock": [1.0, 1.71, 2.53, 3.31, 4.42],
    # heavy hollow container / hull
    "hull": [1.0, 1.31, 1.73, 2.08, 2.61, 3.17, 3.86, 4.9, 6.2],
}


def finish_layer(x: np.ndarray, fade_out: float = 0.01) -> np.ndarray:
    return env.fade(x, 0.0, fade_out)


def modal_hit(
    rng: np.random.Generator,
    dur: float,
    f0: float,
    kind: str = "plate",
    t60: float = 0.6,
    modes: int | None = None,
    bright: float = 0.5,
    jitter: float = 0.03,
    damping: float = 0.7,
    click: float = 0.3,
    click_hz: float = 4000.0,
    sr: int = SR,
) -> np.ndarray:
    """Struck-object hit: inharmonic damped modes plus a short contact click.

    ``bright`` (0..1) tilts energy toward upper modes; ``damping`` makes higher modes decay
    faster (t60_k = t60 * (f0/f_k)**damping).
    """
    n = n_of(dur, sr)
    ratios = np.array(MODE_RATIOS[kind] if isinstance(kind, str) else kind, dtype=np.float64)
    if modes is not None:
        ratios = ratios[:modes]
    freqs = f0 * ratios * (1.0 + jitter * rng.standard_normal(ratios.size))
    t60s = t60 * (f0 / np.maximum(freqs, 1.0)) ** damping
    k = np.arange(ratios.size)
    amps = np.exp(-k * (1.0 - bright) * 0.6) * (0.5 + rng.random(ratios.size))
    y = osc.modal(freqs, t60s, amps, n, sr, rng=rng)
    if click > 0:
        cn = min(n, n_of(0.004, sr))
        c = noise.white(cn, rng) * np.exp(-np.linspace(0, 8, cn))
        c = filters.bandpass(c, click_hz, 0.9, sr)
        y[:cn] += click * c * np.max(np.abs(y)) * 3.0
    return y


def noise_burst(
    rng: np.random.Generator,
    dur: float,
    attack: float,
    t60: float,
    lo: float | None = None,
    hi: float | None = None,
    color: str = "white",
    sr: int = SR,
) -> np.ndarray:
    n = n_of(dur, sr)
    src = {"white": noise.white, "pink": noise.pink, "brown": noise.brown}[color](n, rng)
    e = env.perc(n, attack, t60, sr)
    y = src * e
    if lo and hi:
        y = filters.band(y, lo, hi, 2, sr)
    elif hi:
        y = filters.lowpass(y, hi, 2, sr=sr)
    elif lo:
        y = filters.highpass(y, lo, 2, sr=sr)
    return y


def boom(dur: float, f_hi: float, f_lo: float, sweep: float, t60: float, attack: float = 0.002, sr: int = SR) -> np.ndarray:
    """Sub/low 'thump': a sine whose pitch falls exponentially from ``f_hi`` to ``f_lo``."""
    n = n_of(dur, sr)
    t = t_of(n, sr)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / max(sweep, 1e-4))
    y = osc.sine(f, n, sr) * env.perc(n, attack, t60, sr)
    return y


def crack(dur_ms: float = 1.2, sr: int = SR, hp: float = 250.0) -> np.ndarray:
    """N-wave pressure pulse (supersonic crack / muzzle blast front)."""
    T = max(4, n_of(dur_ms / 1000.0, sr))
    rise = max(1, T // 12)
    pulse = np.concatenate([np.linspace(0, 1, rise, endpoint=False), np.linspace(1, -1, T), np.linspace(-1, 0, rise)])
    pulse = np.concatenate([pulse, np.zeros(n_of(0.01, sr))])
    return filters.highpass(pulse, hp, 2, sr=sr)


def debris(
    rng: np.random.Generator,
    dur: float,
    rate: float,
    kind: str = "metal",
    decay: float = 0.6,
    f_range: tuple[float, float] = (900.0, 5000.0),
    start: float = 0.0,
    gain_spread_db: float = 18.0,
    sr: int = SR,
) -> np.ndarray:
    """Shower of small impacts whose density decays exponentially (falling debris, gravel, dirt)."""
    n = n_of(dur, sr)
    out = np.zeros(n)
    t = start
    times = []
    while True:
        lam = rate * np.exp(-(t - start) / max(decay, 1e-3))
        if lam < 0.5:
            break
        t += rng.exponential(1.0 / lam)
        if t >= dur:
            break
        times.append(t)
    for ti in times:
        age = (ti - start) / max(decay, 1e-3)
        g = 10 ** (-(rng.random() * gain_spread_db + 6 * age) / 20.0)
        f = np.exp(rng.uniform(np.log(f_range[0]), np.log(f_range[1])))
        if kind == "metal":
            grain = modal_hit(rng, 0.25, f, "bar", t60=rng.uniform(0.06, 0.22), modes=3, bright=0.7, click=0.4, sr=sr)
        elif kind == "rock":
            grain = modal_hit(rng, 0.06, f, "rock", t60=rng.uniform(0.012, 0.04), modes=3, bright=0.6, click=1.0, click_hz=f * 1.5, sr=sr)
        elif kind == "wood":
            grain = modal_hit(rng, 0.12, f, "wood", t60=rng.uniform(0.03, 0.08), modes=3, bright=0.4, click=0.8, click_hz=f * 2, sr=sr)
        elif kind == "brick":
            grain = modal_hit(rng, 0.08, f, "rock", t60=rng.uniform(0.02, 0.05), modes=4, bright=0.5, click=1.2, click_hz=f, sr=sr)
            grain = filters.lowpass(grain, 4000, 2, sr=sr)
        elif kind == "crunch":  # crushed/torn steel: very short inharmonic grains, no ringing
            grain = modal_hit(rng, 0.05, f, "plate", t60=rng.uniform(0.006, 0.025), modes=5, bright=0.6, click=1.4, click_hz=f * 1.3, sr=sr)
        elif kind == "glass":
            grain = modal_hit(rng, 0.2, f * 1.8, "bar", t60=rng.uniform(0.05, 0.15), modes=4, bright=0.9, click=0.5, sr=sr)
        else:  # dirt / soil / sand clumps: short filtered noise ticks
            gn = n_of(rng.uniform(0.004, 0.02), sr)
            grain = noise.white(gn, rng) * np.exp(-np.linspace(0, 6, gn))
            grain = filters.bandpass(grain, f, 1.2, sr)
        mix.place(out, grain / max(np.max(np.abs(grain)), 1e-9), n_of(ti, sr), g)
    return out


def whoosh(
    rng: np.random.Generator,
    dur: float,
    f_start: float,
    f_end: float,
    q: float = 1.5,
    attack: float = 0.3,
    color: str = "pink",
    shape: str = "bell",
    sr: int = SR,
) -> np.ndarray:
    """Band-pass swept noise with a swell envelope (air movement, passes, fireballs)."""
    n = n_of(dur, sr)
    src = {"white": noise.white, "pink": noise.pink, "brown": noise.brown}[color](n, rng)
    fc = osc.chirp(f_start, f_end, n, sr)
    y = filters.tv_biquad(src, "bandpass", fc, q, block=64, sr=sr)
    if shape == "bell":
        x = np.linspace(0, 1, n)
        a = max(min(attack, 0.95), 0.05)
        e = np.where(x < a, (x / a) ** 2, np.exp(-((x - a) / (1 - a)) * 4.0))
    else:
        e = env.perc(n, attack * dur, dur * 0.8, sr)
    return env.fade(y * e, 0.0, dur * 0.15, sr)


def bubble(f0: float, dur: float, rise: float = 0.5, amp: float = 1.0, sr: int = SR) -> np.ndarray:
    """Minnaert-style bubble: a damped sine whose pitch rises as it decays (water)."""
    n = n_of(dur, sr)
    t = t_of(n, sr)
    tau = 0.003 + 7.0 / f0
    f = f0 * (1.0 + rise * (1.0 - np.exp(-t / (tau * 1.5))))
    return amp * osc.sine(f, n, sr) * np.exp(-t / tau) * (1 - np.exp(-t / 0.0004))


def bubbles(rng: np.random.Generator, dur: float, rate: float, f_range=(300.0, 2500.0), decay: float = 1e9,
            rise=(0.1, 0.8), sr: int = SR, loop: bool = False) -> np.ndarray:
    n = n_of(dur, sr)
    out = np.zeros(n)
    t = rng.exponential(1.0 / rate)
    while t < dur:
        lam_scale = np.exp(-t / decay)
        f = np.exp(rng.uniform(np.log(f_range[0]), np.log(f_range[1])))
        b = bubble(f, 0.06, rng.uniform(*rise), 10 ** (-rng.random() * 18 / 20) * lam_scale, sr)
        if loop:
            mix.place_wrapped(out, b, n_of(t, sr))
        else:
            mix.place(out, b, n_of(t, sr))
        t += rng.exponential(1.0 / max(rate * lam_scale, 1e-3))
    return out


def creak(
    rng: np.random.Generator,
    dur: float,
    rate_curve,
    body: list[tuple[float, float, float]],
    jitter: float = 0.15,
    grain_tau: float = 0.0015,
    sr: int = SR,
) -> np.ndarray:
    """Stick-slip creak: irregular pulse train (``rate_curve`` Hz) exciting resonant bodies.

    ``body`` is a list of ``(freq, q, gain)`` resonances (wood beam, metal sheet, hinge...).
    """
    n = n_of(dur, sr)
    rate = np.asarray(rate_curve, dtype=np.float64) if np.ndim(rate_curve) else np.full(n, float(rate_curve))
    rate = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, rate.size), rate)
    ph = osc.phase(rate * (1 + jitter * noise.smooth_random(n, rng, 40.0, sr)), n, sr)
    idx = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    imp = np.zeros(n)
    imp[idx] = 1.0 + 0.5 * rng.standard_normal(idx.size)
    k = np.exp(-t_of(n_of(grain_tau * 6, sr), sr) / grain_tau)
    exc = np.convolve(imp, k)[:n] * (0.6 + 0.4 * noise.white(n, rng))
    y = np.zeros(n)
    for f, q, g in body:
        y += g * filters.bandpass(exc, f, q, sr)
    return y


def crackle(rng: np.random.Generator, n: int, rate: float, lo: float = 1500.0, hi: float = 9000.0,
            heavy_tail: float = 1.6, sr: int = SR) -> np.ndarray:
    """Fire/arc crackle: sparse impulses with heavy-tailed amplitudes, shaped as tiny noise pops."""
    out = np.zeros(n)
    idx = noise.events(n, rate, rng, sr)
    if idx.size == 0:
        return out
    amps = rng.pareto(heavy_tail, idx.size) + 0.2
    amps = np.minimum(amps, 12.0) * rng.choice([-1.0, 1.0], idx.size)
    np.add.at(out, idx, amps)
    k = n_of(0.0025, sr)
    kern = np.exp(-np.linspace(0, 7, k)) * noise.white(k, rng)
    out = np.convolve(out, kern)[:n]
    return filters.band(out, lo, hi, 2, sr)


def radio(x: np.ndarray, rng: np.random.Generator, lo: float = 380.0, hi: float = 2900.0, drive: float = 2.5,
          bits: float = 9.0, hiss: float = 0.015, sr: int = SR) -> np.ndarray:
    """Military radio voice-channel colouring: narrow band, saturation, grit and hiss."""
    y = filters.band(x, lo, hi, 3, sr)
    y = filters.peaking(y, 1700, 5.0, 1.2, sr)
    y = fx.saturate(y / max(np.max(np.abs(y)), 1e-9), drive, "tanh")
    y = fx.bitcrush(y, bits, 2)
    y = filters.band(y, lo * 0.9, hi * 1.1, 2, sr)
    h = filters.band(noise.white(y.shape[0], rng), lo, hi * 1.3, 2, sr)
    return y + hiss * h / max(np.max(np.abs(h)), 1e-9)


def static_burst(rng: np.random.Generator, dur: float, density: float = 60.0, sr: int = SR) -> np.ndarray:
    """Radio static: band-limited noise gated by fast random crackle and a squelch envelope."""
    n = n_of(dur, sr)
    base = filters.band(noise.white(n, rng), 300, 5000, 2, sr)
    gate = np.abs(noise.smooth_random(n, rng, density, sr))
    gate = 0.35 + 0.65 * gate**0.5
    crk = crackle(rng, n, density * 4, 800, 6000, sr=sr)
    y = base * gate + 0.6 * crk / max(np.max(np.abs(crk)), 1e-9)
    return y * env.ar(n, 0.004, min(0.05, dur / 3), sr)


def squelch_tail(rng: np.random.Generator, dur: float = 0.12, sr: int = SR) -> np.ndarray:
    """Short 'kssht' at the end of a radio transmission."""
    n = n_of(dur, sr)
    y = filters.band(noise.white(n, rng), 1200, 7000, 2, sr)
    return y * env.perc(n, 0.002, dur * 0.9, sr)


def bell(rng: np.random.Generator, f0: float, dur: float, t60: float = 4.0, bright: float = 0.6,
         kind: str = "bell", strike: float = 0.5, sr: int = SR) -> np.ndarray:
    """Bell strike built from bell partial ratios with doublet beating."""
    n = n_of(dur, sr)
    ratios = np.array(MODE_RATIOS[kind])
    freqs = []
    amps = []
    t60s = []
    for i, r in enumerate(ratios):
        a = (0.9 if r in (1.0, 2.0) else 0.55) * np.exp(-i * (1 - bright) * 0.35)
        for d in (0.0, rng.uniform(0.6, 2.2)):  # doublet (beating)
            freqs.append(f0 * r + d)
            amps.append(a * (1.0 if d == 0 else 0.6))
            t60s.append(t60 * (1.0 / max(r, 0.5)) ** 0.7)
    y = osc.modal(np.array(freqs), np.array(t60s), np.array(amps), n, sr, rng=rng)
    # strike transient
    k = n_of(0.006, sr)
    s = noise.white(k, rng) * np.exp(-np.linspace(0, 7, k))
    y[:k] += strike * filters.bandpass(s, f0 * 4, 1.0, sr) * np.max(np.abs(y))
    return y


def fm_bell(f0: float, dur: float, t60: float = 1.2, ratio: float = 3.5, index: float = 2.5, sr: int = SR) -> np.ndarray:
    """Clean FM bell/chime (UI)."""
    n = n_of(dur, sr)
    e = env.exp_decay(n, t60, sr)
    idx = index * env.exp_decay(n, t60 * 0.5, sr)
    y = osc.fm(f0, ratio, idx, n, sr) * e
    return env.fade(y, 0.0015, 0.0)


def wind_loop(
    rng: np.random.Generator,
    n: int,
    base_hz: float = 500.0,
    spread_oct: float = 1.2,
    gust_rate: float = 0.12,
    gust_depth: float = 0.7,
    q: float = 0.9,
    color: str = "pink",
    whistle: float = 0.0,
    whistle_hz: float = 900.0,
    sr: int = SR,
) -> np.ndarray:
    """Seamless (periodic over ``n``) mono wind: band-pass noise whose centre and level follow a
    smooth random gust curve; optional resonant whistle layer."""
    src = {"white": noise.white, "pink": noise.pink, "brown": noise.brown}[color](n, rng)
    gust = noise.smooth_random(n, rng, gust_rate, sr)
    gust2 = noise.smooth_random(n, rng, gust_rate * 4, sr)
    g = 0.5 + 0.5 * (0.75 * gust + 0.25 * gust2)
    fc = base_hz * 2 ** (spread_oct * (g - 0.5))
    y = loop_tv(src, "bandpass", fc, q, sr)
    lvl = (1.0 - gust_depth) + gust_depth * g**1.5
    y = y * lvl
    if whistle > 0:
        wf = whistle_hz * 2 ** (0.6 * (noise.smooth_random(n, rng, gust_rate * 2, sr)))
        w = loop_tv(noise.white(n, rng), "bandpass", wf, 18.0, sr)
        y = y + whistle * w * (np.clip(g - 0.35, 0, 1) / 0.65) ** 2 * np.std(y) / max(np.std(w), 1e-9)
    return y


def loop_tv(x: np.ndarray, kind: str, f_curve, q, sr: int = SR, block: int = 128) -> np.ndarray:
    """Time-varying biquad applied circularly so a periodic input/control gives a periodic output."""
    n = x.shape[0]
    fc = np.broadcast_to(np.asarray(f_curve, dtype=np.float64), (n,)) if np.ndim(f_curve) else np.full(n, float(f_curve))
    qq = np.broadcast_to(np.asarray(q, dtype=np.float64), (n,)) if np.ndim(q) else np.full(n, float(q))
    xt = np.concatenate([x, x], axis=0)
    y = filters.tv_biquad(xt, kind, np.concatenate([fc, fc]), np.concatenate([qq, qq]), block=block, sr=sr)
    return np.array(y[n:], copy=True)


def cconv(x: np.ndarray, k: np.ndarray) -> np.ndarray:
    """Circular convolution of a loop with a (shorter or longer) kernel."""
    n = x.shape[0]
    reps = int(np.ceil(k.shape[0] / n))
    kp = np.zeros(reps * n)
    kp[: k.shape[0]] = k
    kf = kp.reshape(reps, n).sum(axis=0)
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(kf), n)


def stereo_space(x: np.ndarray, rng: np.random.Generator, space: str = "small_room", wet: float = 0.15,
                 sr: int = SR) -> np.ndarray:
    """Give a mono UI/cue sound a subtle stereo room (mono-compatible)."""
    ir = reverb.impulse_response(space, rng, sr, stereo=True)
    return reverb.convolve(x, ir, wet=wet, dry=1.0, sr=sr)


def space(x: np.ndarray, rng: np.random.Generator, space_name: str = "outdoor_slapback", level_db: float = -12.0,
          stereo: bool = False, sr: int = SR) -> np.ndarray:
    """Add a reverb send whose *peak* sits ``level_db`` relative to the dry peak.

    Peak-relative scaling keeps the direct sound dominant regardless of how much low-frequency
    energy the source has (energy-normalised IRs otherwise make bass-heavy sources swim)."""
    ir = reverb.impulse_response(space_name, rng, sr, stereo=stereo)
    wet = reverb.convolve(x, ir, wet=1.0, dry=0.0, sr=sr)
    g = 10 ** (level_db / 20.0) * np.max(np.abs(x)) / max(np.max(np.abs(wet)), 1e-12)
    out = wet * g
    if out.ndim == 2 and x.ndim == 1:
        out[: x.shape[0]] += x[:, None]
    else:
        out[: x.shape[0]] += x
    return out


def distance_far(x: np.ndarray, rng: np.random.Generator, lp: float = 900.0, soften: float = 0.03, echo_db: float = -6.0,
                 space_name: str = "valley_echo", sr: int = SR) -> np.ndarray:
    """Turn a close one-shot into a far variant: air-absorption low-pass, softened attack, echo tail."""
    y = filters.lowpass(x, lp, 4, sr=sr)
    y = filters.lowpass(y, lp * 1.6, 2, sr=sr)
    k = n_of(soften, sr)
    if k > 1:
        kern = np.hanning(2 * k)[:k]
        kern = np.concatenate([kern, np.exp(-np.linspace(0, 4, k))])
        y = np.convolve(y, kern / kern.sum())[: y.shape[0]]
    return space(y, rng, space_name, echo_db, sr=sr)


def ensure_mono(x: np.ndarray) -> np.ndarray:
    return x if x.ndim == 1 else x.mean(axis=1)


def rand_choice(rng: np.random.Generator, seq):
    return seq[int(rng.integers(0, len(seq)))]


__all__ = [name for name in dir() if not name.startswith("_")] + ["child_rng", "LN1000", "mod"]
