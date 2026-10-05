"""Track loops per surface, track squeal / broken-track one-shots, turret and gun-laying drives.

Track loops are built at a native speed of 25 km/h with a 0.16 m link pitch (link-pass rate
~43 Hz). Each loop combines a periodic link-clank train (sprocket and road-wheel accents),
road-wheel rumble, a hull body resonance and a surface layer with its own texture
(granular crunch, swish, squelch, hiss, slosh, plank knocks, plate ring).  The engine scales
``PlaybackSpeed`` with ground speed (0.5x-1.6x) and volume with speed.
"""

from __future__ import annotations

import numpy as np

from synth import env, filters, fx, mix, noise, osc
from synth.core import SR, n_of, t_of
from synth.mod import snap_freq

from . import kit
from .registry import sound

LOOP_S = 4.0
NATIVE_KMH = 25.0
LINK_PITCH_M = 0.16

# clank: level, low-pass (muffling), ring time; surface-specific extras handled in _surface()
SURFACES = {
    "dirt": dict(clank=0.55, clank_lp=3200, ring=0.05, rumble=0.8, desc="packed earth: crunchy soil, solid rumble"),
    "grass": dict(clank=0.40, clank_lp=2200, ring=0.04, rumble=0.6, desc="turf: soft swish and rustle, damped clank"),
    "concrete": dict(clank=1.0, clank_lp=10000, ring=0.09, rumble=0.5, desc="hard paving: bright clatter and scrape"),
    "gravel": dict(clank=0.6, clank_lp=5000, ring=0.06, rumble=0.7, desc="loose stones: dense granular crunch"),
    "mud": dict(clank=0.28, clank_lp=900, ring=0.03, rumble=0.9, desc="deep mud: squelch, suction, wet splats"),
    "snow": dict(clank=0.32, clank_lp=1500, ring=0.035, rumble=0.5, desc="packed snow: squeaky crunch, muffled"),
    "sand": dict(clank=0.35, clank_lp=1700, ring=0.035, rumble=0.6, desc="sand: hiss and pour, muffled clank"),
    "water": dict(clank=0.18, clank_lp=600, ring=0.03, rumble=0.7, desc="wading: slosh, bubbles and splashes"),
    "wood": dict(clank=0.6, clank_lp=4500, ring=0.06, rumble=0.5, desc="timber bridge: hollow plank knocks and creaks"),
    "metal": dict(clank=0.9, clank_lp=12000, ring=0.25, rumble=0.4, desc="steel deck: ringing plate and clang"),
}


def _clank_bank(rng: np.random.Generator, count: int, ring: float, bright: float) -> list[np.ndarray]:
    bank = []
    for _ in range(count):
        g = kit.modal_hit(rng, 0.25, rng.uniform(550, 1500), "bar", t60=ring * rng.uniform(0.7, 1.4), modes=4,
                          bright=bright, click=0.8, click_hz=rng.uniform(2500, 5000))
        low = kit.modal_hit(rng, 0.2, rng.uniform(150, 320), "plate", t60=0.06, modes=4, bright=0.3, click=0.0)
        g = mix.mix(g / np.max(np.abs(g)), (low / np.max(np.abs(low)), 0.6))
        bank.append(g / np.max(np.abs(g)))
    return bank


def _grain_layer(rng, n: int, rate: float, kind: str, f_range, gain_db_spread: float = 15.0, dur_range=(0.003, 0.02)) -> np.ndarray:
    """Uniform-density granular layer, wrapped for loops."""
    out = np.zeros(n)
    count = int(rate * n / SR)
    pos = rng.integers(0, n, count)
    for p in pos:
        f = np.exp(rng.uniform(np.log(f_range[0]), np.log(f_range[1])))
        g = 10 ** (-rng.random() * gain_db_spread / 20)
        if kind == "noise":
            gn = n_of(rng.uniform(*dur_range))
            grain = noise.white(gn, rng) * np.exp(-np.linspace(0, 6, gn))
            grain = filters.bandpass(grain, f, 1.3)
        elif kind == "rock":
            grain = kit.modal_hit(rng, 0.05, f, "rock", t60=rng.uniform(0.008, 0.03), modes=3, bright=0.6, click=1.0, click_hz=f * 1.4)
        elif kind == "squeak":
            gn = n_of(rng.uniform(0.008, 0.03))
            grain = noise.white(gn, rng) * np.hanning(gn)
            grain = filters.bandpass(grain, f, 7.0)
        else:
            raise ValueError(kind)
        grain = grain / max(np.max(np.abs(grain)), 1e-9)
        mix.place_wrapped(out, grain, int(p), g)
    return out


def _surface(name: str, rng: np.random.Generator, n: int, wheel_hz: float, link_hz: float) -> np.ndarray:
    t = t_of(n)
    wheel = 0.5 + 0.5 * np.sin(2 * np.pi * wheel_hz * t + rng.random() * 6.28)
    slow = 0.5 + 0.5 * noise.smooth_random(n, rng, 1.5)
    circ = lambda fn, x: mix.circular(fn, x, 2)  # noqa: E731
    if name == "dirt":
        crunch = _grain_layer(rng, n, 650, "noise", (300, 2600))
        rumble = circ(lambda z: filters.lowpass(z, 260, 2), noise.brown(n, rng))
        return 0.55 * crunch * (0.6 + 0.4 * wheel) + 0.09 * rumble / np.std(rumble)
    if name == "grass":
        swish = circ(lambda z: filters.band(z, 2000, 9000, 2), noise.pink(n, rng))
        swish = swish / np.std(swish) * 0.12 * (0.35 + 0.65 * wheel * slow)
        rustle = _grain_layer(rng, n, 260, "noise", (2500, 8000), dur_range=(0.01, 0.04))
        soft = _grain_layer(rng, n, 120, "noise", (250, 900))
        return swish + 0.35 * rustle + 0.3 * soft
    if name == "concrete":
        scrape = circ(lambda z: filters.band(z, 1500, 6500, 2), noise.white(n, rng))
        scrape = scrape / np.std(scrape) * 0.06 * (0.6 + 0.4 * (0.5 + 0.5 * np.sin(2 * np.pi * link_hz / 3 * t)))
        grit = _grain_layer(rng, n, 220, "rock", (2500, 7000))
        return scrape + 0.25 * grit
    if name == "gravel":
        crunch = _grain_layer(rng, n, 1400, "rock", (900, 5000), 20.0)
        dirt = _grain_layer(rng, n, 500, "noise", (400, 2500))
        return (0.6 * crunch + 0.35 * dirt) * (0.55 + 0.45 * wheel)
    if name == "mud":
        out = kit.bubbles(rng, n / SR, 28.0, (120, 520), rise=(0.3, 1.2), loop=True) * 1.6
        slurp_src = noise.pink(n, rng)
        fc = 380 * 2 ** (1.2 * noise.smooth_random(n, rng, 3.0))
        slurp = kit.loop_tv(slurp_src, "bandpass", fc, 4.0)
        slurp = slurp / np.std(slurp) * 0.18 * (0.2 + 0.8 * wheel**2)
        splat = np.zeros(n)
        k = int(wheel_hz * n / SR)
        for i in range(max(1, k)):
            b = kit.noise_burst(rng, 0.12, 0.004, 0.08, 150, 1400, "pink")
            mix.place_wrapped(splat, b / np.max(np.abs(b)), int(i * n / max(1, k) + rng.integers(0, n // 40)), rng.uniform(0.4, 0.8))
        sub = circ(lambda z: filters.lowpass(z, 120, 2), noise.brown(n, rng))
        return out + slurp + 0.45 * splat + 0.25 * sub / np.std(sub) * 0.3
    if name == "snow":
        crunch = _grain_layer(rng, n, 380, "squeak", (1400, 4200), 14.0)
        packed = _grain_layer(rng, n, 300, "noise", (500, 2000))
        hiss = circ(lambda z: filters.band(z, 3000, 10000, 2), noise.white(n, rng))
        return (0.55 * crunch + 0.35 * packed) * (0.5 + 0.5 * wheel) + 0.04 * hiss / np.std(hiss)
    if name == "sand":
        hiss = circ(lambda z: filters.band(z, 2500, 12000, 2), noise.white(n, rng))
        hiss = hiss / np.std(hiss) * 0.12 * (0.45 + 0.55 * wheel * (0.6 + 0.4 * slow))
        fine = _grain_layer(rng, n, 900, "noise", (2000, 8000), dur_range=(0.002, 0.008))
        pour = circ(lambda z: filters.band(z, 500, 2500, 2), noise.pink(n, rng))
        return hiss + 0.25 * fine + 0.03 * pour / np.std(pour)
    if name == "water":
        slosh = circ(lambda z: filters.lowpass(z, 700, 2), noise.brown(n, rng))
        sw = 0.5 + 0.5 * np.sin(2 * np.pi * snap_freq(0.6, n) * t)
        slosh = slosh / np.std(slosh) * 0.2 * (0.3 + 0.7 * wheel * sw)
        bub = kit.bubbles(rng, n / SR, 70.0, (250, 1800), rise=(0.1, 0.6), loop=True)
        splash = np.zeros(n)
        k = int(wheel_hz * 1.5 * n / SR)
        for i in range(max(1, k)):
            b = kit.noise_burst(rng, 0.35, 0.01, 0.25, 1200, 9000, "white")
            mix.place_wrapped(splash, b / np.max(np.abs(b)), int(i * n / max(1, k) + rng.integers(0, n // 30)), rng.uniform(0.15, 0.4))
        return slosh + 0.6 * bub + 0.5 * splash
    if name == "wood":
        out = np.zeros(n)
        plank_hz = snap_freq(18.0, n)
        count = int(plank_hz * n / SR)
        for i in range(count):
            h = kit.modal_hit(rng, 0.25, rng.uniform(140, 380), "wood", t60=rng.uniform(0.08, 0.16), modes=4, bright=0.35,
                              click=0.6, click_hz=1800)
            mix.place_wrapped(out, h / np.max(np.abs(h)), int(i * n / count + rng.integers(-200, 200)), rng.uniform(0.35, 1.0))
        cr = kit.creak(rng, 1.2, np.linspace(35, 70, 50), [(320, 8, 1.0), (780, 10, 0.6), (1450, 12, 0.3)])
        cr *= env.ar(cr.shape[0], 0.3, 0.5)
        mix.place_wrapped(out, cr / np.max(np.abs(cr)), int(rng.integers(0, n)), 0.35)
        return 0.6 * out
    if name == "metal":
        out = np.zeros(n)
        for _ in range(int(3 * n / SR)):
            h = kit.modal_hit(rng, 1.0, rng.uniform(210, 480), "plate", t60=rng.uniform(0.4, 0.8), modes=10, bright=0.55, click=0.4)
            mix.place_wrapped(out, h / np.max(np.abs(h)), int(rng.integers(0, n)), rng.uniform(0.3, 0.7))
        scrape = circ(lambda z: filters.band(z, 2000, 7000, 2), noise.white(n, rng))
        return 0.5 * out + 0.04 * scrape / np.std(scrape)
    raise ValueError(name)


def track_loop(surface: str):
    def render(rng, variant):
        p = SURFACES[surface]
        n = n_of(LOOP_S)
        speed = NATIVE_KMH / 3.6
        link_hz = snap_freq(speed / LINK_PITCH_M, n)
        wheel_hz = snap_freq(speed / (np.pi * 0.75), n)  # 0.75 m road wheels
        period = SR / link_hz
        count = int(round(link_hz * n / SR))
        bank = _clank_bank(rng, 10, p["ring"], 0.65 if p["clank_lp"] > 4000 else 0.4)
        clank = np.zeros(n)
        accent_every = 11  # sprocket teeth
        base_amp = np.exp(rng.normal(0, 0.45, count))
        for i in range(count):
            pos = int(i * period + rng.normal(0, 0.12) * period)
            a = base_amp[i] * (1.8 if i % accent_every == 0 else 1.0)
            mix.place_wrapped(clank, bank[int(rng.integers(0, len(bank)))], pos, a)
        clank = mix.circular(lambda z: filters.lowpass(z, p["clank_lp"], 2), clank, 2)
        clank = clank / max(np.max(np.abs(clank)), 1e-9)
        # pins rattle (dense, quiet) and hull body resonance excited by the clank train
        rattle = _grain_layer(rng, n, 500, "noise", (1200, 4000))
        body = mix.circular(lambda z: filters.resonators(z, [95, 150, 230], [6, 7, 8], [1.0, 0.7, 0.4]), clank, 2)
        rumble = mix.circular(lambda z: filters.lowpass(z, 160, 2), noise.brown(n, rng))
        t = t_of(n)
        wheel_mod = 0.6 + 0.4 * np.sin(2 * np.pi * wheel_hz * t)
        rumble = rumble / np.std(rumble) * wheel_mod
        surf = _surface(surface, rng, n, wheel_hz, link_hz)
        y = (p["clank"] * clank * 0.6 + 0.12 * rattle * p["clank"] + 0.25 * body / max(np.max(np.abs(body)), 1e-9)
             + p["rumble"] * 0.18 * rumble + surf)
        y = fx.saturate(y / max(np.max(np.abs(y)), 1e-9), 1.4, "tanh")
        return mix.circular(lambda z: filters.highpass(z, 28, 2), y, 2)

    return render


def track_squeal(rng, variant):
    dur = rng.uniform(1.1, 1.6)
    n = n_of(dur)
    f0 = rng.uniform(900, 1700)
    walk = 1.0 + 0.035 * noise.smooth_random(n, rng, 7.0) + 0.008 * noise.smooth_random(n, rng, 40.0)
    f = f0 * walk
    tone = osc.additive(f, [1.0, 0.55, 0.32, 0.18, 0.1], n, rng=rng)
    rough = 0.65 + 0.35 * noise.smooth_random(n, rng, 35.0)
    e = env.adsr(n, rng.uniform(0.04, 0.12), 0.1, 0.8, 0.45)
    y = tone * rough * e
    y = filters.peaking(y, 2600, 6, 2.0)
    grit = filters.band(noise.white(n, rng), 3000, 9000, 2) * e * 0.08
    return y + grit


def broken_track_clatter(rng, variant):
    dur = 2.2
    n = n_of(dur)
    y = np.zeros(n)
    snap = kit.modal_hit(rng, 0.8, rng.uniform(1300, 1800), "bar", t60=0.5, modes=5, bright=0.8, click=1.5)
    mix.place(y, snap / np.max(np.abs(snap)), 0.0, 0.9)
    cr = kit.crack(0.8)
    mix.place(y, cr / np.max(np.abs(cr)), 0.0, 0.6)
    t = 0.05
    while t < 1.7:
        rate = 26 * np.exp(-t / 0.55) + 3
        a = np.exp(-t / 0.9)
        h = kit.modal_hit(rng, 0.3, rng.uniform(380, 1300), "bar", t60=rng.uniform(0.06, 0.15), modes=4, bright=0.55, click=0.8)
        mix.place(y, h / np.max(np.abs(h)), t, a * rng.uniform(0.4, 1.0))
        t += rng.exponential(1.0 / rate)
    slap = mix.mix(kit.noise_burst(rng, 0.4, 0.002, 0.2, None, 700, "brown"),
                   (kit.modal_hit(rng, 0.4, 260, "plate", t60=0.15, modes=6, bright=0.4, click=0.5), 0.5))
    mix.place(y, slap / np.max(np.abs(slap)), rng.uniform(0.45, 0.6), 0.8)
    m = n_of(1.3)
    drag = filters.band(noise.white(m, rng), 900, 3500, 2) * env.breakpoints([(0, 0), (0.1, 1), (1.3, 0)], m) * 0.18
    mix.place(y, drag, 0.6)
    return y


# --------------------------------------------------------------------------- turret
def traverse(size: str):
    def render(rng, variant):
        n = n_of(3.0)
        t = t_of(n)
        circ = lambda fn, x: mix.circular(fn, x, 2)  # noqa: E731
        if size == "small":
            f = snap_freq(380.0, n)
            wob = 1 + 0.003 * noise.smooth_random(n, rng, 1.0)
            motor = osc.additive(f * wob, [1.0, 0.35, 0.5, 0.1, 0.15, 0.05], n, rng=rng)
            brush = circ(lambda z: filters.highpass(z, 3000, 2), noise.white(n, rng))
            brush *= 0.5 + 0.5 * np.sin(2 * np.pi * snap_freq(f / 6, n) * t)
            gear = osc.sine(snap_freq(f * 2.7, n) * wob, n)
            tooth = snap_freq(11.0, n)
            ring_rumble = circ(lambda z: filters.band(z, 60, 260, 2), noise.brown(n, rng))
            ring_rumble *= 0.5 + 0.5 * np.sin(2 * np.pi * tooth * t) ** 2
            y = 0.5 * motor + 0.05 * brush / np.std(brush) + 0.08 * gear + 0.35 * ring_rumble / np.std(ring_rumble)
        else:
            f = snap_freq(210.0, n)
            wob = 1 + 0.004 * noise.smooth_random(n, rng, 0.8)
            pump = osc.additive(f * wob, [1.0, 0.6, 0.35, 0.25, 0.12, 0.08], n, rng=rng)
            pump *= 0.75 + 0.25 * np.sin(2 * np.pi * snap_freq(f / 6, n) * t)
            hiss = circ(lambda z: filters.band(z, 2000, 7000, 2), noise.white(n, rng))
            ring_rumble = circ(lambda z: filters.band(z, 40, 200, 2), noise.brown(n, rng))
            ring_rumble *= 0.3 + 0.7 * (0.5 + 0.5 * np.sin(2 * np.pi * snap_freq(6.0, n) * t)) ** 2
            y = 0.45 * pump + 0.06 * hiss / np.std(hiss) + 0.5 * ring_rumble / np.std(ring_rumble)
            for _ in range(3):
                c = kit.modal_hit(rng, 0.3, rng.uniform(140, 220), "hull", t60=0.12, modes=6, bright=0.3, click=0.3)
                mix.place_wrapped(y, c / np.max(np.abs(c)), int(rng.integers(0, n)), 0.25)
        return fx.saturate(y / np.max(np.abs(y)), 1.3, "tanh")

    return render


def traverse_start(rng, variant):
    n = n_of(0.7)
    y = np.zeros(n)
    relay = kit.modal_hit(rng, 0.08, rng.uniform(2800, 3600), "bar", t60=0.02, modes=2, click=1.5)
    mix.place(y, relay / np.max(np.abs(relay)), 0.0, 0.35)
    clunk = kit.modal_hit(rng, 0.5, rng.uniform(170, 230), "hull", t60=0.18, modes=7, bright=0.35, click=0.8, click_hz=2000)
    mix.place(y, clunk / np.max(np.abs(clunk)), 0.03, 0.9)
    m = n_of(0.45)
    f = env.breakpoints([(0, 120), (0.25, 380), (0.45, 380)], m, kind="smooth")
    whine = osc.additive(f, [1, 0.3, 0.45, 0.1], m, rng=rng) * env.ar(m, 0.05, 0.25)
    mix.place(y, whine, 0.04, 0.25)
    return y


def traverse_stop(rng, variant):
    n = n_of(0.7)
    y = np.zeros(n)
    m = n_of(0.3)
    f = env.breakpoints([(0, 380), (0.3, 130)], m, kind="exp")
    whine = osc.additive(f, [1, 0.3, 0.45, 0.1], m, rng=rng) * env.ar(m, 0.01, 0.2)
    mix.place(y, whine, 0.0, 0.25)
    brake = kit.modal_hit(rng, 0.55, rng.uniform(140, 190), "hull", t60=0.22, modes=8, bright=0.4, click=1.0, click_hz=2400)
    mix.place(y, brake / np.max(np.abs(brake)), 0.08, 1.0)
    rat = kit.debris(rng, 0.5, 30, "metal", 0.12, (1500, 4000))
    mix.place(y, rat / max(np.max(np.abs(rat)), 1e-9), 0.1, 0.12)
    return y


def elevation_servo(rng, variant):
    n = n_of(2.0)
    f = snap_freq(950.0, n)
    wob = 1 + 0.005 * noise.smooth_random(n, rng, 1.5)
    whine = osc.additive(f * wob, [1.0, 0.3, 0.1], n, rng=rng)
    chatter = mix.circular(lambda z: filters.bandpass(z, 2500, 2.0), noise.dust(n, 300, rng), 2)
    hiss = mix.circular(lambda z: filters.band(z, 3000, 9000, 2), noise.white(n, rng), 2)
    low = mix.circular(lambda z: filters.band(z, 80, 300, 2), noise.brown(n, rng), 2)
    return 0.5 * whine + 0.08 * chatter / np.std(chatter) + 0.03 * hiss / np.std(hiss) + 0.12 * low / np.std(low)


# --------------------------------------------------------------------------- registration
def _register() -> None:
    for s, p in SURFACES.items():
        sound(f"track_{s}", "tracks", track_loop(s), f"Tracks on {p['desc']} (native {NATIVE_KMH:.0f} km/h).",
              f"Vehicle moving on '{s}' material (PlaybackSpeed = speed/{NATIVE_KMH:.0f} km/h, 0.5-1.6x; volume follows speed).",
              loop=True, loop_s=LOOP_S, group="tracks", meta={"surface": s, "nativeSpeedKmh": NATIVE_KMH, "linkPitchM": LINK_PITCH_M},
              level=-20.0 if s not in ("concrete", "metal", "gravel") else -19.0)
    sound("track_squeal", "tracks", track_squeal, "Track/idler friction squeal (stick-slip).",
          "Sharp turns / pivot steering / braking at speed (rate-limited, random variant).", variants="abc", level=-22.0, priority=40)
    sound("track_broken_clatter", "tracks", broken_track_clatter, "Track snaps and links flail, slap the ground and drag.",
          "Track module destroyed while moving (pairs with dmg_track_broken).", variants="ab", level=-15.0, priority=75,
          max_m=200)
    sound("turret_traverse_small", "turret", traverse("small"), "Electric turret traverse motor (light/medium turrets).",
          "Turret rotating (PlaybackSpeed 0.8-1.2 with traverse rate).", loop=True, loop_s=3.0, level=-25.0)
    sound("turret_traverse_large", "turret", traverse("large"), "Hydraulic turret traverse drive with ring-gear rumble (heavy turrets).",
          "Turret rotating (heavy).", loop=True, loop_s=3.0, level=-24.0)
    sound("turret_traverse_start", "turret", traverse_start, "Traverse engage: relay click, gear clunk, motor spin-up.",
          "Turret starts rotating.", variants="ab", level=-24.0)
    sound("turret_traverse_stop", "turret", traverse_stop, "Traverse stop: spin-down and brake clunk.",
          "Turret stops rotating.", variants="ab", level=-23.0)
    sound("gun_elevation_servo", "turret", elevation_servo, "Gun elevation servo whine with gear chatter.",
          "Gun elevating/depressing.", loop=True, loop_s=2.0, level=-28.0, priority=35)


_register()
