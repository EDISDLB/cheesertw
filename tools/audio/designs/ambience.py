"""Map ambience beds, positional ambient spots, weather layers and the hangar/garage.

Beds are 40 s stereo loops built to be *periodic by construction*: FFT noise, periodic
random control curves, circular filtering/convolution and wrapped event placement. Each
biome has an identity (see ``BIOMES``) made of a wind/water base, a tonal or rhythmic
"signature" layer and sparse, distance-treated events. Spots are mono one-shots meant to be
positioned in 3D around the listener by the AudioEngine's ambient emitter.

No recorded animals: birds, crows, gulls and insects are abstract synthetic calls (FM
chirps, formant-filtered rasps, pulsed carriers).
"""

from __future__ import annotations

import numpy as np

from synth import env, filters, mix, noise, osc, reverb
from synth.core import SR, n_of, note_hz, t_of
from synth.mod import snap_freq

from . import kit
from .registry import sound

BED_S = 40.0
WEATHER_S = 30.0


def _n(x):
    return x / max(np.max(np.abs(x)), 1e-12)


# --------------------------------------------------------------------------- loop helpers
class Bed:
    """Stereo loop buffer with a near bus and a distant bus (low-passed + circular reverb)."""

    def __init__(self, rng, seconds: float = BED_S):
        self.rng = rng
        self.n = n_of(seconds)
        self.near = np.zeros((self.n, 2))
        self.far = np.zeros((self.n, 2))

    def put(self, ev: np.ndarray, t_s: float, pan: float, gain: float, far: bool = False) -> None:
        st = mix.pan(ev, pan)
        mix.place_wrapped(self.far if far else self.near, st, n_of(t_s) % self.n, gain)

    def add(self, x: np.ndarray, gain: float = 1.0) -> None:
        self.near += gain * (x if x.ndim == 2 else np.stack([x, x], axis=1))

    def render(self, far_lp: float = 2500.0, space: str = "valley_echo", far_wet: float = 0.8) -> np.ndarray:
        far = self.far
        if np.any(far):
            far = mix.circular(lambda z: filters.lowpass(z, far_lp, 2), far, 2)
            ir = reverb.impulse_response(space, self.rng, stereo=True)
            far = reverb.convolve_circular(far, ir, wet=far_wet, dry=1.0)
        return self.near + far


def circ(fn, x):
    return mix.circular(fn, x, 2)


def wind_stereo(rng, n: int, base: float, spread: float, gust_rate: float, depth: float, q: float = 0.9,
                color: str = "pink", whistle: float = 0.0, whistle_hz: float = 900.0) -> np.ndarray:
    """Coherent stereo wind: shared gust curve, decorrelated noise per channel."""
    gust = noise.smooth_random(n, rng, gust_rate)
    gust2 = noise.smooth_random(n, rng, gust_rate * 4)
    g = 0.5 + 0.5 * (0.75 * gust + 0.25 * gust2)
    chans = []
    for c in range(2):
        src = {"white": noise.white, "pink": noise.pink, "brown": noise.brown}[color](n, rng)
        shift = np.roll(g, int(0.15 * SR) * c)
        fc = base * 2 ** (spread * (shift - 0.5))
        y = kit.loop_tv(src, "bandpass", fc, q)
        y = y / np.std(y) * ((1.0 - depth) + depth * shift**1.5)
        if whistle > 0:
            wf = whistle_hz * 2 ** (0.6 * noise.smooth_random(n, rng, gust_rate * 2))
            w = kit.loop_tv(noise.white(n, rng), "bandpass", wf, 20.0)
            y = y + whistle * w / np.std(w) * np.clip(shift - 0.35, 0, 1) ** 2 * 1.8
        chans.append(y)
    return np.stack(chans, axis=1), g


def gust_mod(n: int, g: np.ndarray, lo: float = 0.3) -> np.ndarray:
    return lo + (1 - lo) * g


def stereo_noise_layer(rng, n: int, fn) -> np.ndarray:
    return np.stack([fn(noise.white(n, rng)), fn(noise.white(n, rng))], axis=1)


# --------------------------------------------------------------------------- synthetic calls & events
def bird_phrase(rng) -> np.ndarray:
    notes = int(rng.integers(3, 9))
    base = rng.uniform(2400, 4600)
    out = np.zeros(n_of(1.6))
    t = 0.0
    for _ in range(notes):
        d = rng.uniform(0.03, 0.12)
        fa = base * rng.uniform(0.8, 1.25)
        fb = fa * rng.uniform(0.6, 1.6)
        m = n_of(d)
        f = np.geomspace(fa, fb, m)
        s = osc.sine(f, m) + 0.12 * osc.sine(2 * f, m)
        if rng.random() < 0.35:
            s *= 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(35, 65) * t_of(m))
        s *= np.hanning(m) ** 0.7
        mix.place(out, s, t)
        t += d + rng.uniform(0.02, 0.12)
        if t > 1.4:
            break
    return mix.trim_tail(out, -60)


def caw(rng, dur: float = 0.32) -> np.ndarray:
    m = n_of(dur)
    t = t_of(m)
    f = np.geomspace(rng.uniform(640, 800), rng.uniform(470, 560), m)
    src = osc.saw(f, m) + 0.6 * osc.square(f * 1.003, m, pw=0.3)
    src *= 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(55, 85) * t)
    y = filters.resonators(src, [1150, 2300, 3300], [5, 6, 7], [1.0, 0.6, 0.3])
    y += 0.2 * _n(filters.band(noise.white(m, rng), 1000, 4000, 2)) * np.std(y) * 3
    return y * env.adsr(m, 0.02, 0.05, 0.85, 0.1)


def crow_call(rng) -> np.ndarray:
    k = int(rng.integers(2, 4))
    out = np.zeros(n_of(0.45 * k + 0.4))
    for i in range(k):
        mix.place(out, _n(caw(rng, rng.uniform(0.25, 0.36))), i * rng.uniform(0.38, 0.48), rng.uniform(0.7, 1.0))
    return out


def gull_call(rng) -> np.ndarray:
    k = int(rng.integers(2, 5))
    out = np.zeros(n_of(0.5 * k + 0.5))
    t = 0.0
    for i in range(k):
        d = rng.uniform(0.35, 0.55) if i == 0 else rng.uniform(0.2, 0.32)
        m = n_of(d)
        peak = rng.uniform(2000, 2500)
        f = env.breakpoints([(0, peak * 0.58), (0.07, peak), (d * 0.45, peak * 0.85), (d, peak * 0.48)], m, kind="smooth")
        s = osc.additive(f, [1.0, 0.6, 0.45, 0.3, 0.2, 0.12], m, rng=rng)
        s *= 0.85 + 0.15 * np.sin(2 * np.pi * rng.uniform(28, 40) * t_of(m))
        s = filters.peaking(s, 2800, 6.0, 1.5) * env.ar(m, 0.03, d * 0.4)
        mix.place(out, _n(s), t, 1.0 if i == 0 else 0.8)
        t += d + rng.uniform(0.06, 0.14)
    return mix.trim_tail(out, -60)


def foghorn(rng, dur: float = 3.4) -> np.ndarray:
    m = n_of(dur)
    f = 110.0 * (1 + 0.003 * noise.smooth_random(m, rng, 2.0))
    src = osc.saw(f, m) + 0.6 * osc.square(f * 1.002, m) + 0.3 * osc.saw(2 * f * 0.999, m)
    y = filters.peaking(filters.lowpass(src, 700, 2), 250, 6.0, 1.2)
    return y * env.breakpoints([(0, 0), (0.35, 1.0), (dur - 0.9, 0.9), (dur, 0.0)], m, kind="smooth")


def ice_crack(rng) -> np.ndarray:
    out = np.zeros(n_of(1.2))
    mix.place(out, _n(kit.crack(0.5, hp=1500)), 0, 0.5)
    for k in range(int(rng.integers(2, 4))):
        d = rng.uniform(0.08, 0.18)
        m = n_of(d)
        f = np.geomspace(rng.uniform(5500, 8000), rng.uniform(220, 400), m)
        p = osc.sine(f, m) * np.exp(-t_of(m) / (d * 0.5))
        mix.place(out, p, k * rng.uniform(0.09, 0.16), 0.7 * 0.6**k)
    mix.place(out, _n(kit.boom(0.4, 120, 70, 0.02, 0.15)), 0, 0.2)
    return out


def metal_creak(rng, dur: float = 2.0) -> np.ndarray:
    rate = np.concatenate([np.linspace(10, 38, 30), np.linspace(38, 14, 30)])
    cr = kit.creak(rng, dur, rate, [(300, 12, 1.0), (750, 14, 0.7), (1700, 16, 0.45), (2900, 18, 0.2)], jitter=0.25, grain_tau=0.001)
    wob = 1 + 0.3 * np.sin(2 * np.pi * rng.uniform(3, 6) * t_of(cr.shape[0]))
    return cr * wob * env.ar(cr.shape[0], 0.25, 0.5)


def clank(rng, f0=None) -> np.ndarray:
    f = f0 or rng.uniform(260, 600)
    y = kit.modal_hit(rng, 1.4, f, "plate", t60=rng.uniform(0.6, 1.1), modes=10, bright=0.5, click=0.6)
    if rng.random() < 0.6:
        y = mix.mix(y, (kit.debris(rng, 1.0, 40, "metal", 0.25, (900, 3000)), 0.3))
    return y


def rockfall(rng, dur: float = 3.2) -> np.ndarray:
    y = kit.debris(rng, dur, 70, "rock", 1.1, (400, 3000))
    for t in np.sort(rng.uniform(0.0, dur * 0.6, 6)):
        mix.place(y, _n(kit.modal_hit(rng, 0.4, rng.uniform(150, 350), "rock", t60=0.1, modes=4, click=1.0, click_hz=900)) * 0.6, t)
    rum = kit.noise_burst(rng, dur, 0.3, dur * 0.6, 30, 220, "brown")
    return _n(y) + 0.5 * _n(rum)


def cricket_layer(rng, n: int) -> np.ndarray:
    f = snap_freq(rng.uniform(4200, 4900), n)
    period = rng.uniform(0.55, 0.8)
    pulses = int(rng.integers(3, 5))
    e = np.zeros(n)
    pw = n_of(0.014)
    win = np.hanning(pw)
    t = rng.uniform(0, period)
    while t < n / SR:
        for k in range(pulses):
            mix.place_wrapped(e, win * rng.uniform(0.7, 1.0), n_of(t + k * 0.035))
        t += period * rng.uniform(0.93, 1.07)
    return osc.sine(f, n) * e


def thunder(rng, kind: str, stereo: bool = True) -> np.ndarray:
    """Thunder: crackling leader (close only) + many rolling low-passed bursts."""
    dur = {"close": 7.0, "mid": 8.0, "far": 9.0}[kind]
    n = n_of(dur)
    chans = []
    for _c in range(2 if stereo else 1):
        y = np.zeros(n)
        if kind == "close":
            cr = kit.crackle(rng, n_of(0.25), 500, 800, 9000) * env.perc(n_of(0.25), 0.001, 0.2)
            mix.place(y, _n(cr), 0.0, 0.6)
            mix.place(y, _n(kit.crack(3.0, hp=120)), 0.0, 0.9)
        lp = {"close": 900, "mid": 450, "far": 260}[kind]
        count = {"close": 45, "mid": 40, "far": 30}[kind]
        start = {"close": 0.03, "mid": 0.2, "far": 0.4}[kind]
        for _ in range(count):
            t = start + rng.exponential(dur * 0.22)
            if t > dur * 0.8:
                continue
            d = rng.uniform(0.6, 2.2)
            b = kit.noise_burst(rng, d, rng.uniform(0.03, 0.3), d * 0.7, 25, lp * rng.uniform(0.6, 1.3), "brown")
            mix.place(y, _n(b), t, np.exp(-t / (dur * 0.35)) * rng.lognormal(0, 0.4))
        chans.append(y)
    y = np.stack(chans, axis=1) if stereo else chans[0]
    y = filters.highpass(y, 30, 2)
    return kit.space(y, rng, "valley_echo", -8.0 if kind != "close" else -10.0, stereo=stereo)


# --------------------------------------------------------------------------- biome beds
def bed_temperate_valley_industrial(rng, v):
    b = Bed(rng)
    n = b.n
    w, g = wind_stereo(rng, n, 450, 1.2, 0.08, 0.6)
    b.add(w, 0.12)
    hum = sum(a * osc.sine(snap_freq(f, n), n) for f, a in ((50, 1.0), (100, 0.5), (150, 0.3), (49.6, 0.4), (200, 0.15)))
    hum *= 0.8 + 0.2 * noise.smooth_random(n, rng, 0.2)
    b.add(np.stack([hum, np.roll(hum, n_of(0.012))], axis=1), 0.02)
    period = BED_S / 16
    for i in range(16):
        th = mix.mix(kit.boom(0.6, 95, 62, 0.02, 0.25), (kit.noise_burst(rng, 0.5, 0.004, 0.2, 60, 600, "brown"), 0.8))
        b.put(_n(th), i * period + 1.1, -0.35, 0.1, far=True)
    for t in np.sort(rng.uniform(0, BED_S, 5)):
        b.put(_n(clank(rng)), t, rng.uniform(-0.8, 0.8), 0.05, far=True)
    for t in np.sort(rng.uniform(0, BED_S, 8)):
        b.put(_n(bird_phrase(rng)), t, rng.uniform(-0.9, 0.9), rng.uniform(0.02, 0.05))
    rum = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.lowpass(q, 110, 2), z))
    b.add(rum / np.std(rum), 0.015)
    return b.render(2200, "valley_echo", 0.9)


def bed_desert(rng, v):
    b = Bed(rng)
    n = b.n
    w, g = wind_stereo(rng, n, 900, 1.5, 0.12, 0.75, 0.8, "white")
    b.add(w, 0.1)
    hiss = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.band(q, 4000, 12000, 2), z))
    b.add(hiss / np.std(hiss) * gust_mod(n, g, 0.15)[:, None] ** 2, 0.05)
    roar = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.lowpass(q, 150, 2), noise.brown(n, rng)))
    b.add(roar / np.std(roar) * gust_mod(n, g, 0.4)[:, None], 0.03)
    for t in np.sort(rng.uniform(0, BED_S, 3)):
        b.put(_n(metal_creak(rng)), t, rng.uniform(-0.8, 0.8), 0.06, far=True)
    for t in np.sort(rng.uniform(0, BED_S, 6)):
        patter = kit.debris(rng, 1.2, 150, "dirt", 0.6, (2500, 8000))
        b.put(_n(patter), t, rng.uniform(-0.9, 0.9), 0.02)
    return b.render(3000, "valley_echo", 0.6)


def bed_winter(rng, v):
    b = Bed(rng)
    n = b.n
    w, g = wind_stereo(rng, n, 600, 1.3, 0.1, 0.7, 0.9, "pink", whistle=0.5, whistle_hz=1100)
    b.add(w, 0.11)
    drone = osc.sine(snap_freq(55, n), n) + 0.6 * osc.sine(snap_freq(82.6, n), n) + 0.3 * osc.sine(snap_freq(110.3, n), n)
    drone *= 0.7 + 0.3 * noise.smooth_random(n, rng, 0.1)
    b.add(np.stack([drone, np.roll(drone, n_of(0.02))], axis=1), 0.03)
    hiss = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.band(q, 5000, 12000, 2), z))
    b.add(hiss / np.std(hiss), 0.008)
    for t in np.sort(rng.uniform(0, BED_S, 4)):
        b.put(_n(ice_crack(rng)), t, rng.uniform(-0.9, 0.9), 0.06, far=True)
    return b.render(6000, "valley_echo", 1.0)


def bed_fortress_old(rng, v):
    b = Bed(rng)
    n = b.n
    w, g = wind_stereo(rng, n, 700, 1.0, 0.09, 0.6, 0.8)
    b.add(w, 0.06)
    for f0, gain in ((280, 1.0), (410, 0.7)):
        chans = []
        for _c in range(2):
            fc = f0 * 2 ** (0.5 * noise.smooth_random(n, rng, 0.15))
            howl = kit.loop_tv(noise.pink(n, rng), "bandpass", fc, 6.0)
            chans.append(howl / np.std(howl) * gust_mod(n, g, 0.2) ** 2)
        b.add(np.stack(chans, axis=1), 0.04 * gain)
    for t in np.sort(rng.uniform(0, BED_S, 4)):
        b.put(_n(crow_call(rng)), t, rng.uniform(-0.9, 0.9), 0.05, far=True)
    for t, f in ((rng.uniform(5, 15), 247.0), (rng.uniform(22, 34), 330.0)):
        b.put(_n(kit.bell(rng, f, 5.0, 4.0)), t, rng.uniform(-0.6, 0.6), 0.05, far=True)
    return b.render(3500, "stone_hall", 1.2)


def lapping(rng, n: int) -> np.ndarray:
    chans = []
    for c in range(2):
        base = circ(lambda q: filters.lowpass(q, 600, 2), noise.brown(n, rng))
        swell = 0.5 + 0.5 * np.sin(2 * np.pi * snap_freq(0.23, n) * t_of(n) + c * 1.3)
        swell = swell * (0.7 + 0.3 * noise.smooth_random(n, rng, 0.5))
        y = base / np.std(base) * 0.25 * swell
        laps = np.zeros(n)
        for t in np.sort(rng.uniform(0, n / SR, int(1.4 * n / SR))):
            lap = kit.noise_burst(rng, 0.18, 0.01, 0.12, 200, 1800, "pink")
            mix.place_wrapped(laps, _n(lap), n_of(t), rng.uniform(0.2, 0.6))
        bub = kit.bubbles(rng, n / SR, 6.0, (200, 900), rise=(0.2, 0.8), loop=True)
        chans.append(y + 0.12 * laps + 0.15 * bub)
    return np.stack(chans, axis=1)


def bed_harbor(rng, v):
    b = Bed(rng)
    n = b.n
    w, g = wind_stereo(rng, n, 550, 1.0, 0.07, 0.5)
    b.add(w, 0.06)
    b.add(lapping(rng, n), 0.5)
    for t in np.sort(rng.uniform(0, BED_S, 5)):
        b.put(_n(gull_call(rng)), t, rng.uniform(-0.9, 0.9), 0.05, far=rng.random() < 0.5)
    b.put(_n(foghorn(rng)), rng.uniform(10, 16), -0.4, 0.09, far=True)
    for t in np.sort(rng.uniform(0, BED_S, 4)):
        b.put(_n(clank(rng, rng.uniform(150, 300))), t, rng.uniform(-0.7, 0.7), 0.05, far=True)
    for t in np.sort(rng.uniform(0, BED_S, 3)):
        b.put(_n(kit.bell(rng, rng.uniform(600, 700), 3.0, 2.5)), t, 0.6, 0.02, far=True)
    return b.render(4000, "valley_echo", 0.9)


def bed_mountain(rng, v):
    b = Bed(rng)
    n = b.n
    w, g = wind_stereo(rng, n, 500, 1.8, 0.15, 0.9, 0.9, "pink", whistle=0.3, whistle_hz=1400)
    b.add(w, 0.14)
    roar = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.lowpass(q, 200, 2), noise.brown(n, rng)))
    b.add(roar / np.std(roar) * gust_mod(n, g, 0.1)[:, None] ** 2, 0.06)
    for t in (rng.uniform(4, 14), rng.uniform(24, 34)):
        b.put(_n(rockfall(rng)), t, rng.uniform(-0.8, 0.8), 0.07, far=True)
    return b.render(3000, "valley_echo", 1.4)


def bed_river_town(rng, v):
    b = Bed(rng)
    n = b.n
    flow = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.band(q, 200, 6000, 2), noise.pink(n, rng)))
    flow *= (0.85 + 0.15 * noise.smooth_random(n, rng, 0.3))[:, None]
    b.add(flow / np.std(flow), 0.05)
    babble = np.stack([kit.bubbles(rng, BED_S, 260, (400, 2600), rise=(0.1, 0.6), loop=True) for _ in range(2)], axis=1)
    b.add(babble / np.std(babble), 0.02)
    low = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.lowpass(q, 200, 2), noise.brown(n, rng)))
    b.add(low / np.std(low), 0.02)
    murmur = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.band(q, 200, 800, 2), z))
    murmur *= (0.6 + 0.4 * noise.smooth_random(n, rng, 0.8))[:, None]
    b.add(murmur / np.std(murmur), 0.006)
    t0 = rng.uniform(16, 22)
    for k in range(3):
        b.put(_n(kit.bell(rng, 196.0, 5.0, 4.5)), t0 + 2.2 * k, -0.3, 0.06, far=True)
    for t in np.sort(rng.uniform(0, BED_S, 3)):
        b.put(_n(bird_phrase(rng)), t, rng.uniform(-0.9, 0.9), 0.025)
    w, _ = wind_stereo(rng, n, 700, 0.8, 0.08, 0.4)
    b.add(w, 0.03)
    return b.render(2500, "valley_echo", 1.0)


def bed_plains(rng, v):
    b = Bed(rng)
    n = b.n
    w, g = wind_stereo(rng, n, 1500, 1.0, 0.1, 0.6, 0.7, "white")
    b.add(w, 0.06)
    rustle = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.band(q, 3000, 9000, 2), z))
    rustle *= (gust_mod(n, g, 0.2) ** 2 * (0.7 + 0.3 * np.abs(noise.smooth_random(n, rng, 12.0))))[:, None]
    b.add(rustle / np.std(rustle), 0.025)
    for _k in range(4):
        cr = cricket_layer(rng, n)
        b.add(mix.pan(cr, rng.uniform(-0.9, 0.9)), 0.012)
    buzz = circ(lambda q: filters.bandpass(q, 6000, 4.0), noise.white(n, rng)) * (0.6 + 0.4 * np.sin(2 * np.pi * snap_freq(120, n) * t_of(n)))
    b.add(np.stack([buzz, np.roll(buzz, n_of(0.3))], axis=1) / np.std(buzz), 0.003)
    for t in (rng.uniform(6, 14), rng.uniform(26, 34)):
        th = thunder(rng, "far", stereo=False)
        b.put(_n(th), t, rng.uniform(-0.6, 0.6), 0.12)
    return b.render(2500, "valley_echo", 0.5)


BIOMES = {
    "temperate_valley_industrial": (bed_temperate_valley_industrial, "Temperate valley with industry: soft wind, 50 Hz plant hum, distant press thumps every 2.5 s, far clanks, synthetic bird phrases."),
    "desert": (bed_desert, "Desert: dry hissing gusts, sand hiss on gust peaks, low roar, distant corrugated-metal creaks, grain patter."),
    "winter": (bed_winter, "Winter: cold wind with gliding whistles, low drone, fine snow hiss, distant dispersive ice cracks."),
    "fortress_old": (bed_fortress_old, "Old fortress: hollow moaning wind through stone, crow-like rasping caws, distant bells in stone reverb."),
    "harbor": (bed_harbor, "Harbor: water lapping and gurgles, gull-like cries, a distant foghorn, crane clanks, buoy bell."),
    "mountain": (bed_mountain, "Mountain: strong wide gusts with whistle, deep wind roar, distant rockfalls rolling through valley echo."),
    "river_town": (bed_river_town, "River town: river flow and babble, abstract town murmur, church-bell-like tolls, a few birds."),
    "plains": (bed_plains, "Plains: grass wind and rustle, synthetic cricket chorus, faint insect buzz, distant thunder rolls."),
}


# --------------------------------------------------------------------------- spots (mono one-shots)
def far_spot(y, rng, lp=3000.0, echo_db=-8.0, space="valley_echo"):
    return kit.space(filters.lowpass(y, lp, 2), rng, space, echo_db)


SPOTS = {
    "temperate_valley_industrial": [
        ("machinery_clank", "ab", lambda rng, v: far_spot(clank(rng), rng, 2500), "Distant factory clank with chain rattle."),
        ("bird", "abc", lambda rng, v: kit.space(bird_phrase(rng), rng, "forest", -14.0), "Synthetic bird phrase (FM chirps/trills)."),
    ],
    "desert": [
        ("metal_creak", "ab", lambda rng, v: far_spot(metal_creak(rng), rng, 3500, -10.0), "Wind-stressed corrugated metal creak."),
        ("sand_gust", "", lambda rng, v: mix.mix(kit.whoosh(rng, 2.6, 500, 2600, 0.9, 0.4),
                                                 (filters.band(noise.white(n_of(2.6), rng), 3000, 10000, 2) * env.ar(n_of(2.6), 0.8, 1.2) * 0.4, 1.0)),
         "Passing sand gust with hiss."),
    ],
    "winter": [
        ("ice_crack", "abc", lambda rng, v: far_spot(ice_crack(rng), rng, 7000, -8.0), "Dispersive ice-sheet crack ('pew') with echo."),
        ("wind_whistle", "", lambda rng, v: kit.loop_tv(noise.white(n_of(3.0), rng), "bandpass",
                                                        env.breakpoints([(0, 900), (1.2, 1400), (3.0, 1000)], n_of(3.0), kind="smooth"), 20.0)
         * env.ar(n_of(3.0), 0.8, 1.2), "Resonant wind whistle glide."),
    ],
    "fortress_old": [
        ("crow", "ab", lambda rng, v: kit.space(crow_call(rng), rng, "stone_hall", -10.0), "Crow-like rasping caws (synthetic)."),
        ("bell_toll", "", lambda rng, v: far_spot(kit.bell(rng, 247.0, 6.0, 5.0), rng, 4000, -8.0), "Distant single bell toll."),
    ],
    "harbor": [
        ("gull", "abc", lambda rng, v: kit.space(gull_call(rng), rng, "outdoor_slapback", -14.0), "Gull-like cry series (synthetic)."),
        ("foghorn", "", lambda rng, v: far_spot(foghorn(rng), rng, 900, -5.0), "Distant foghorn blast."),
        ("crane_clank", "ab", lambda rng, v: far_spot(clank(rng, rng.uniform(150, 300)), rng, 2500, -8.0), "Crane/hook clank with chain."),
        ("buoy_bell", "", lambda rng, v: far_spot(mix.mix(kit.bell(rng, 650, 3.0, 2.5), (np.concatenate([np.zeros(n_of(1.1)), kit.bell(rng, 650, 3.0, 2.5)]), 0.7)),
                                                  rng, 5000, -10.0), "Buoy bell, two irregular dings."),
    ],
    "mountain": [
        ("rockfall", "ab", lambda rng, v: far_spot(rockfall(rng), rng, 3000, -5.0), "Distant rockfall tumbling, valley echo."),
        ("gust_howl", "", lambda rng, v: kit.whoosh(rng, 3.5, 300, 700, 4.0, 0.45), "Howling gust through rock."),
    ],
    "river_town": [
        ("church_bell", "ab", None, "Church-bell-like toll(s) (a: single, b: three)."),
        ("shutter_bang", "ab", None, "Loose wooden shutter banging in the wind."),
    ],
    "plains": [
        ("distant_thunder", "ab", lambda rng, v: thunder(rng, "far", stereo=False), "Distant thunder roll."),
        ("insect_flyby", "", None, "Insect buzz passing by (Doppler)."),
    ],
}


def church_bell(rng, v):
    tolls = 1 if v == "a" else 3
    y = np.zeros(n_of(5.5 + 2.2 * (tolls - 1)))
    for k in range(tolls):
        mix.place(y, _n(kit.bell(rng, 196.0, 5.5, 4.5)), 2.2 * k, 0.8)
    return far_spot(y, rng, 3500, -8.0)


def shutter_bang(rng, v):
    y = np.zeros(n_of(1.6))
    for t, a in ((0.0, 1.0), (rng.uniform(0.25, 0.5), 0.5)):
        h = kit.modal_hit(rng, 0.5, rng.uniform(170, 300), "wood", t60=0.12, modes=5, bright=0.4, click=1.0)
        mix.place(y, _n(h), t, a)
    cr = kit.creak(rng, 0.5, np.linspace(30, 60, 10), [(500, 10, 1.0), (1200, 12, 0.5)])
    mix.place(y, _n(cr) * env.ar(cr.shape[0], 0.1, 0.2), 0.6, 0.2)
    return kit.space(y, rng, "outdoor_slapback", -10.0)


def insect_flyby(rng, v):
    n = n_of(2.5)
    f, gain = kit.mod.doppler_curve(n, rng.uniform(190, 230), 3.0, 0.5, 1.2)
    wing = osc.saw(f * (1 + 0.02 * np.sin(2 * np.pi * 30 * t_of(n))), n)
    y = filters.band(wing, 300, 4000, 2) * gain**1.5
    return env.fade(y, 0.3, 0.3)


SPOT_FN_OVERRIDES = {("river_town", "church_bell"): church_bell, ("river_town", "shutter_bang"): shutter_bang,
                     ("plains", "insect_flyby"): insect_flyby}


# --------------------------------------------------------------------------- weather
def rain_loop(rng, v):
    n = n_of(WEATHER_S)
    chans = []
    for _c in range(2):
        hiss = circ(lambda q: filters.band(q, 300, 8000, 2), noise.pink(n, rng))
        hiss = hiss / np.std(hiss) * (0.85 + 0.15 * noise.smooth_random(n, rng, 0.2))
        # individual drops: sparse signed impulses, each smoothed (no shared kernel -> no fixed colouration)
        d = noise.dust(n, 2200, rng, signed=True, amp_spread=1.5)
        drops = circ(lambda q: filters.band(filters.onepole_lp(q, 7000), 1200, 9000, 2), d)
        drops = circ(lambda q: filters.peaking(q, 3500, 3.0, 0.7), drops)
        plinks = kit.bubbles(rng, WEATHER_S, 22, (1500, 5000), rise=(0.05, 0.4), loop=True)
        low = circ(lambda q: filters.lowpass(q, 300, 2), noise.brown(n, rng))
        chans.append(0.45 * hiss + 0.3 * drops / np.std(drops) + 0.1 * plinks / max(np.std(plinks), 1e-9) + 0.15 * low / np.std(low))
    return np.stack(chans, axis=1)


def snowstorm_loop(rng, v):
    n = n_of(WEATHER_S)
    w, g = wind_stereo(rng, n, 700, 1.6, 0.18, 0.85, 1.0, "pink", whistle=0.9, whistle_hz=1250)
    hiss = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.band(q, 3000, 10000, 2), z))
    buffet = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.lowpass(q, 100, 2), noise.brown(n, rng)))
    fast = np.abs(noise.smooth_random(n, rng, 4.0))
    return w + 0.3 * hiss / np.std(hiss) * gust_mod(n, g, 0.3)[:, None] + 0.5 * buffet / np.std(buffet) * (fast * gust_mod(n, g))[:, None]


def sandstorm_loop(rng, v):
    n = n_of(WEATHER_S)
    w, g = wind_stereo(rng, n, 380, 1.8, 0.16, 0.8, 0.7, "pink")
    hiss = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.band(q, 2000, 12000, 2), z))
    grit = np.stack([circ(lambda q: filters.highpass(q, 3000, 2), noise.dust(n, 2500, rng)) for _ in range(2)], axis=1)
    buffet = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.lowpass(q, 120, 2), noise.brown(n, rng)))
    gm = gust_mod(n, g, 0.25)[:, None]
    return w + 0.8 * hiss / np.std(hiss) * gm**2 + 0.25 * grit / np.std(grit) * gm + 0.6 * buffet / np.std(buffet) * gm


# --------------------------------------------------------------------------- hangar
def hangar_room_tone(rng, v):
    b = Bed(rng)
    n = b.n
    air = stereo_noise_layer(rng, n, lambda z: circ(lambda q: filters.lowpass(q, 1200, 2), noise.pink(n, rng)))
    b.add(air / np.std(air), 0.03)
    hum = sum(a * osc.sine(snap_freq(f, n), n) for f, a in ((60, 1.0), (120, 0.6), (180, 0.3), (240, 0.12)))
    b.add(np.stack([hum, np.roll(hum, n_of(0.01))], axis=1), 0.01)
    buzz = circ(lambda q: filters.highpass(q, 1000, 2), osc.square(snap_freq(120, n), n, pw=0.1))
    b.add(np.stack([buzz, buzz], axis=1), 0.0015)
    for t in np.sort(rng.uniform(0, BED_S, 9)):
        kind = rng.integers(0, 3)
        if kind == 0:
            ev = clank(rng, rng.uniform(300, 700))
        elif kind == 1:
            ev = kit.modal_hit(rng, 0.5, rng.uniform(800, 1600), "bar", t60=0.3, modes=4, click=0.8)
        else:
            ev = kit.whoosh(rng, 1.2, 300, 900, 1.0, 0.4)
        b.put(_n(ev), t, rng.uniform(-0.9, 0.9), 0.05, far=True)
    return b.render(4000, "hangar", 1.6)


def hangar_tools(rng, v):
    if v == "a":  # impact wrench bursts
        y = np.zeros(n_of(1.8))
        for t in (0.0, 0.75):
            m = n_of(rng.uniform(0.35, 0.5))
            rate = rng.uniform(26, 34)
            ham = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rate * t_of(m)))) * noise.white(m, rng)
            ham = filters.band(ham, 800, 6000, 2)
            whine = osc.sine(rng.uniform(1700, 2100), m) * 0.3
            mix.place(y, _n(ham + whine) * env.ar(m, 0.02, 0.05), t, 1.0)
    elif v == "b":  # hammer on metal
        y = np.zeros(n_of(2.2))
        for k in range(int(rng.integers(3, 5))):
            mix.place(y, _n(kit.modal_hit(rng, 1.0, rng.uniform(700, 900), "plate", t60=0.5, modes=8, bright=0.6, click=1.0)), k * rng.uniform(0.35, 0.45), 1.0)
    else:  # ratchet
        y = np.zeros(n_of(1.6))
        for burst in range(2):
            for k in range(int(rng.integers(6, 10))):
                c = kit.modal_hit(rng, 0.05, rng.uniform(2800, 3600), "bar", t60=0.015, modes=2, click=1.2)
                mix.place(y, _n(c), burst * 0.7 + k * 0.045, 0.8)
    return kit.space(y, rng, "hangar", -4.0)


def compressor_cycle(rng, v):
    dur = 5.6
    n = n_of(dur)
    run = env.breakpoints([(0, 0), (0.4, 1.0), (4.0, 1.0), (4.3, 0.0), (dur, 0.0)], n, kind="smooth")
    speed = env.breakpoints([(0, 0.3), (0.4, 1.0), (4.0, 1.0), (4.5, 0.2), (dur, 0.2)], n, kind="smooth")
    motor = osc.additive(118 * speed, [1.0, 0.5, 0.3, 0.15], n, rng=rng)
    thump_rate = 18 * speed
    thump = 0.5 + 0.5 * np.sin(2 * np.pi * osc.phase(thump_rate, n))
    piston = filters.lowpass(noise.brown(n, rng), 220, 2) * thump**4
    y = (0.5 * motor + 0.8 * _n(piston)) * run
    m = n_of(1.3)
    hiss = filters.highpass(noise.white(m, rng), 1800, 2) * env.perc(m, 0.01, 1.1)
    mix.place(y, _n(hiss) * 0.6, 4.25)
    mix.place(y, _n(kit.modal_hit(rng, 0.2, 900, "bar", t60=0.05, modes=3, click=1.0)) * 0.3, 4.22)
    return kit.space(y, rng, "hangar", -6.0)


def pa_chime(rng, v):
    notes = ["A4", "D5", "F#5"] if v == "a" else ["F#5", "D5", "A4"]
    y = np.zeros(n_of(2.6))
    for i, nm in enumerate(notes):
        tone = kit.bell(rng, note_hz(nm) / 2, 1.6, 1.4, bright=0.4, kind="tube", strike=0.2)
        tone += 0.6 * kit.fm_bell(note_hz(nm), 1.6, 1.3, 2.0, 1.2)
        mix.place(y, _n(tone), 0.42 * i, 0.6)
    y = filters.band(y, 300, 5000, 2)  # PA loudspeaker band
    return kit.space(y, rng, "hangar", -4.0, stereo=True)


# --------------------------------------------------------------------------- registration
def _register() -> None:
    for biome, (fn, desc) in BIOMES.items():
        sound(f"amb_{biome}_bed", "ambience", fn, f"Ambience bed - {desc}", f"Map '{biome}' biome: always-on 2D bed (crossfade 3 s on load).",
              loop=True, loop_s=BED_S, level=-27.0 if biome not in ("mountain", "harbor") else -26.0, group=f"amb_{biome}",
              meta={"biome": biome}, quality=0.55)
        for spot, variants, fn_spot, sdesc in SPOTS[biome]:
            render = SPOT_FN_OVERRIDES.get((biome, spot), fn_spot)
            sound(f"amb_{biome}_spot_{spot}", "ambience", render, f"Ambient spot ({biome}): {sdesc}",
                  f"Random 3D emitter around the listener on '{biome}' maps (every 8-30 s, 60-300 m away).",
                  variants=variants, channels=1, level=-24.0, min_m=20, max_m=500, priority=15, group=f"amb_{biome}",
                  meta={"biome": biome})
    sound("wx_rain_loop", "weather", rain_loop, "Rain: hiss bed, dense droplets, puddle plinks, low wash.", "Weather layer: rain (2D).",
          loop=True, loop_s=WEATHER_S, level=-25.0, quality=0.55)
    sound("wx_snowstorm_loop", "weather", snowstorm_loop, "Snowstorm: howling whistling gusts, snow hiss, buffeting.",
          "Weather layer: snowstorm (2D).", loop=True, loop_s=WEATHER_S, level=-23.0, quality=0.55)
    sound("wx_sandstorm_loop", "weather", sandstorm_loop, "Sandstorm: roaring gusts, heavy sand hiss and grit, buffeting.",
          "Weather layer: sandstorm (2D).", loop=True, loop_s=WEATHER_S, level=-23.0, quality=0.55)
    sound("wx_thunder", "weather", lambda rng, v: thunder(rng, {"a": "close", "b": "mid", "c": "far"}[v]),
          "Thunder: a = close strike (crackle + crack + roll), b = mid roll, c = distant rumble.",
          "Storm weather: random every 15-60 s (a rarely).", variants="abc", level=-18.0, priority=30)
    sound("hangar_room_tone", "hangar", hangar_room_tone, "Large hangar room tone: HVAC air, mains hum, faint lamp buzz, distant activity in a big metal room.",
          "Garage/hangar scene: always-on 2D bed.", loop=True, loop_s=BED_S, level=-30.0, quality=0.55)
    sound("hangar_distant_tools", "hangar", hangar_tools, "Distant workshop tools in hangar reverb (a impact wrench, b hammer on metal, c ratchet).",
          "Garage: random 3D emitters every 10-40 s.", variants="abc", channels=1, level=-28.0, min_m=5, max_m=80)
    sound("hangar_compressor_cycle", "hangar", compressor_cycle, "Air compressor run cycle ending in a pressure-release hiss.",
          "Garage: occasional (every 60-120 s).", channels=1, level=-28.0, min_m=5, max_m=80)
    sound("hangar_pa_chime", "hangar", pa_chime, "PA tone chime through a loudspeaker band in hangar reverb (a rising, b falling). No speech.",
          "Garage: before/after notifications such as 'battle found' or events (2D).", variants="ab", level=-22.0, priority=40)


_register()
