"""Shell ground impacts, armor results, damage events and environment destruction.

Armor results are the most gameplay-critical sounds in the game, so each one owns a
different region of the spectrum/time plane:

=============  ==========================================================================
penetration    heavy low boom + dense granular metal *crunch* + tonal-noisy *tear* sweep
ricochet       bright high *ping* (2.4-3 kHz modes, long ring) + falling tumbling *whine*
blocked        dull, short, low-mid *clang* (180-1200 Hz plate modes, low-passed) + thud
critical       razor *snap* + electric *zap* sweep + arcing *buzz* + spark crackle
hit taken      interior perspective: muffled sub thud, hull "bong", cabin resonance
=============  ==========================================================================
"""

from __future__ import annotations

import numpy as np

from synth import env, filters, fx, mix, noise, osc
from synth.core import SR, n_of, t_of

from . import kit
from .engines import render_piston
from .registry import sound


def _n(x: np.ndarray) -> np.ndarray:
    return x / max(np.max(np.abs(x)), 1e-12)


# --------------------------------------------------------------------------- ground impacts
def impact_core(rng, dur: float, scale: float = 1.0, crack: float = 0.6, lp: float | None = None) -> np.ndarray:
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(kit.boom(dur, 120 * scale, 55 * scale, 0.02, 0.3)), 0, 0.8)
    mix.place(y, _n(kit.noise_burst(rng, dur, 0.002, 0.45, 50, 600, "brown")), 0, 0.6)
    mix.place(y, _n(kit.noise_burst(rng, dur, 0.001, 0.18, 200, 2500, "pink")), 0, 0.55)
    if crack:
        mix.place(y, _n(kit.crack(0.8)), 0, 0.5 * crack)
        mix.place(y, _n(kit.noise_burst(rng, 0.2, 0.0002, 0.03, 800, 10000, "white")), 0, 0.4 * crack)
    y = fx.saturate(_n(y), 1.8, "tanh")
    if lp:
        y = filters.lowpass(y, lp, 2)
    return filters.highpass(y, 38, 2)


def ground_impact(material: str):
    def render(rng, variant):
        if material == "dirt":
            dur = 2.4
            y = impact_core(rng, dur, 1.0, 0.5)
            mix.place(y, _n(kit.noise_burst(rng, 1.0, 0.004, 0.6, 150, 1400, "pink")), 0.0, 0.45)
            mix.place(y, _n(kit.debris(rng, 2.3, 260, "dirt", 0.55, (300, 2600), start=0.07)), 0, 0.4)
            mix.place(y, _n(kit.debris(rng, 2.3, 40, "dirt", 0.8, (180, 600), start=0.15)), 0, 0.3)
        elif material == "rock":
            dur = 2.0
            y = impact_core(rng, dur, 1.1, 1.3)
            mix.place(y, _n(kit.noise_burst(rng, 0.2, 0.0001, 0.025, 2000, 14000, "white")), 0, 0.6)
            mix.place(y, _n(kit.debris(rng, 1.9, 130, "rock", 0.6, (1200, 5000), start=0.04)), 0, 0.45)
            mix.place(y, _n(kit.debris(rng, 1.9, 25, "rock", 0.7, (500, 1200), start=0.1)), 0, 0.35)
        elif material == "concrete":
            dur = 2.4
            y = impact_core(rng, dur, 1.05, 1.1)
            mix.place(y, _n(kit.debris(rng, 2.3, 170, "brick", 0.5, (800, 3500), start=0.04)), 0, 0.45)
            dust = kit.noise_burst(rng, 2.0, 0.06, 1.2, 2000, 9000, "pink")
            mix.place(y, _n(dust), 0.05, 0.12)
            rebar = kit.modal_hit(rng, 0.8, rng.uniform(1600, 2100), "bar", t60=0.35, modes=4, bright=0.7, click=0.3)
            mix.place(y, _n(rebar), rng.uniform(0.05, 0.2), 0.12)
        elif material == "water":
            dur = 2.8
            n = n_of(dur)
            y = np.zeros(n)
            mix.place(y, impact_core(rng, dur, 0.85, 0.15, lp=900), 0, 0.7)
            sn = n_of(1.6)
            spl = noise.white(sn, rng)
            spl = filters.tv_lowpass(spl, np.geomspace(9000, 1300, sn), 0.8) * env.perc(sn, 0.012, 1.1)
            mix.place(y, _n(spl), 0.0, 0.7)
            mix.place(y, _n(kit.bubbles(rng, 0.8, 380, (300, 2000), decay=0.15)), 0.01, 0.45)
            fall = kit.bubbles(rng, 2.0, 140, (900, 3800), decay=0.8, rise=(0.05, 0.4))
            mix.place(y, _n(fall), 0.45, 0.35)
            spray = filters.band(noise.white(n_of(1.6), rng), 2000, 9000, 2) * env.breakpoints([(0, 0), (0.15, 1), (1.6, 0)], n_of(1.6))
            mix.place(y, _n(spray), 0.35, 0.18)
        elif material == "snow":
            dur = 2.0
            y = impact_core(rng, dur, 0.95, 0.2, lp=1400)
            mix.place(y, _n(kit.whoosh(rng, 1.2, 600, 2400, 0.8, 0.08)), 0, 0.5)
            mix.place(y, _n(kit.debris(rng, 1.9, 120, "dirt", 0.45, (1500, 4500), start=0.08)), 0, 0.18)
        elif material == "sand":
            dur = 2.6
            y = impact_core(rng, dur, 1.0, 0.4)
            hiss = noise.white(n_of(2.2), rng)
            hiss = filters.band(hiss, 2200, 10000, 2) * env.perc(n_of(2.2), 0.05, 1.5)
            hiss *= 0.6 + 0.4 * np.abs(noise.smooth_random(hiss.shape[0], rng, 30.0))
            mix.place(y, _n(hiss), 0.03, 0.3)
            mix.place(y, _n(kit.debris(rng, 2.4, 420, "dirt", 0.6, (2000, 7000), start=0.06)), 0, 0.25)
        elif material == "wood":
            dur = 1.8
            y = impact_core(rng, dur, 1.1, 1.0)
            snap = kit.modal_hit(rng, 0.4, rng.uniform(260, 420), "wood", t60=0.12, modes=5, bright=0.5, click=1.5, click_hz=2500)
            mix.place(y, _n(snap), 0, 0.7)
            mix.place(y, _n(kit.debris(rng, 1.7, 110, "wood", 0.4, (600, 2600), start=0.03)), 0, 0.4)
        elif material == "metal_building":
            dur = 3.0
            y = impact_core(rng, dur, 1.0, 1.0)
            clang = kit.modal_hit(rng, dur, rng.uniform(170, 250), "plate", t60=1.4, modes=12, bright=0.6, click=0.8)
            wob = 1.0 + 0.35 * np.sin(2 * np.pi * rng.uniform(5, 9) * t_of(clang.shape[0]))
            mix.place(y, _n(clang * wob), 0, 0.75)
            mix.place(y, _n(kit.debris(rng, 2.8, 45, "metal", 0.5, (900, 3500), start=0.05)), 0, 0.3)
        else:
            raise ValueError(material)
        return kit.space(y, rng, "outdoor_slapback", -12.0)

    return render


# --------------------------------------------------------------------------- armor results
def tear_layer(rng, dur: float, f0: float = 2800, f1: float = 700, rate=(140, 60)) -> np.ndarray:
    """Metal tearing: stick-slip pulse train through steel resonances + rough swept noise."""
    n = n_of(dur)
    cr = kit.creak(rng, dur, np.linspace(rate[0], rate[1], 64), [(820, 9, 1.0), (1650, 11, 0.7), (2900, 12, 0.5), (4100, 14, 0.3)],
                   jitter=0.35, grain_tau=0.0008)
    sw = filters.tv_biquad(noise.white(n, rng), "bandpass", np.geomspace(f0, f1, n), 5.0, block=32)
    rough = 0.4 + 0.6 * np.abs(noise.smooth_random(n, rng, 110.0))
    e = env.perc(n, 0.015, dur * 0.75)
    return (_n(cr) * 0.8 + _n(sw) * 0.6 * rough) * e


def armor_penetration(rng, variant):
    dur = 1.5
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(kit.crack(1.0)), 0, 0.55)
    mix.place(y, _n(kit.noise_burst(rng, 0.2, 0.0003, 0.05, 500, 9000, "white")), 0, 0.5)
    mix.place(y, _n(kit.boom(0.9, rng.uniform(110, 130), 48, 0.03, 0.4)), 0, 0.9)
    mix.place(y, _n(kit.noise_burst(rng, 0.8, 0.002, 0.35, 45, 500, "brown")), 0, 0.5)
    crunch = kit.debris(rng, 0.5, 1400, "crunch", 0.09, (600, 4000))
    grit = kit.noise_burst(rng, 0.4, 0.001, 0.14, 400, 3000, "white")
    grit = fx.bitcrush(fx.saturate(_n(grit), 4.0), 6, 3)
    mix.place(y, _n(crunch), 0.003, 0.8)
    mix.place(y, _n(grit), 0.0, 0.4)
    mix.place(y, tear_layer(rng, 0.8, rng.uniform(2500, 3100), rng.uniform(550, 750)), 0.03, 0.8)
    hull = kit.modal_hit(rng, 1.0, rng.uniform(100, 125), "hull", t60=0.6, modes=8, bright=0.4, click=0.0)
    mix.place(y, _n(filters.lowpass(hull, 1500, 2)), 0.0, 0.35)
    mix.place(y, _n(kit.debris(rng, 1.2, 12, "metal", 0.4, (2000, 5000), start=0.3)), 0, 0.07)
    y = filters.highpass(fx.saturate(_n(y), 2.0, "tanh"), 40, 2)
    return kit.space(y, rng, "outdoor_slapback", -14.0)


def ricochet_whine(rng, dur: float, f_start: float, f_end: float) -> np.ndarray:
    n = n_of(dur)
    t = t_of(n)
    f = f_end + (f_start - f_end) * np.exp(-t / rng.uniform(0.18, 0.28))
    tumble = 0.55 + 0.45 * np.sin(2 * np.pi * rng.uniform(26, 44) * t + rng.random() * 6)
    tone = osc.sine(f, n) + 0.25 * osc.sine(2 * f, n)
    air = filters.tv_biquad(noise.white(n, rng), "bandpass", f, 3.0, block=32)
    e = env.perc(n, 0.012, dur * 0.95)
    return (tone + 0.35 * _n(air)) * tumble * e


def armor_ricochet(rng, variant):
    dur = 1.15
    n = n_of(dur)
    y = np.zeros(n)
    ping = kit.modal_hit(rng, 1.0, rng.uniform(2350, 2950), "bar", t60=0.75, modes=5, bright=0.85, click=1.0, click_hz=7000)
    mix.place(y, _n(ping), 0, 0.85)
    mix.place(y, _n(kit.boom(0.25, 320, 190, 0.01, 0.07)), 0, 0.2)
    mix.place(y, _n(kit.noise_burst(rng, 0.08, 0.0001, 0.012, 3000, 14000, "white")), 0, 0.35)
    wh = ricochet_whine(rng, 0.85, rng.uniform(3000, 3600), rng.uniform(1000, 1250))
    mix.place(y, _n(wh), 0.018, 0.75)
    y = filters.highpass(y, 150, 2)
    return kit.space(y, rng, "outdoor_slapback", -14.0)


def armor_blocked(rng, variant):
    dur = 0.95
    n = n_of(dur)
    y = np.zeros(n)
    clang = kit.modal_hit(rng, dur, rng.uniform(175, 235), "plate", t60=0.32, modes=10, bright=0.35, damping=1.0, click=0.6, click_hz=1400)
    mix.place(y, _n(filters.lowpass(clang, 2400, 2)), 0, 0.9)
    mix.place(y, _n(kit.boom(0.4, 135, 72, 0.02, 0.17)), 0, 0.8)
    mix.place(y, _n(kit.noise_burst(rng, 0.2, 0.0005, 0.06, 150, 1500, "pink")), 0, 0.55)
    y = fx.saturate(_n(y), 1.5, "tanh")
    y = filters.lowpass(filters.highpass(y, 45, 2), 3500, 2)
    return kit.space(y, rng, "outdoor_slapback", -16.0)


def armor_critical(rng, variant):
    dur = 0.95
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(kit.crack(0.35, hp=2000)), 0, 0.7)
    mix.place(y, _n(kit.noise_burst(rng, 0.06, 0.0001, 0.012, 3000, 15000, "white")), 0, 0.6)
    zn = n_of(0.09)
    zf = np.geomspace(rng.uniform(3200, 4000), 250, zn)
    zap = (osc.square(zf, zn) * 0.5 + osc.sine(zf, zn)) * env.perc(zn, 0.0005, 0.085)
    mix.place(y, _n(filters.lowpass(zap, 7000, 2)), 0.002, 0.55)
    bn = n_of(0.5)
    hum = osc.square(rng.uniform(115, 150) * (1 + 0.04 * noise.smooth_random(bn, rng, 20.0)), bn, pw=0.3)
    gate = (noise.smooth_random(bn, rng, 45.0) > -0.1).astype(float)
    gate = filters.smooth(gate, 0.0015)
    buzz = filters.band(fx.saturate(hum * gate, 3.0, "hard"), 300, 6000, 2) * env.perc(bn, 0.004, 0.42)
    mix.place(y, _n(buzz), 0.012, 0.45)
    sparks = kit.crackle(rng, n_of(0.7), 700, 2000, 12000) * env.perc(n_of(0.7), 0.002, 0.45)
    mix.place(y, _n(sparks), 0.005, 0.4)
    tink = kit.modal_hit(rng, 0.5, rng.uniform(3600, 4200), "bar", t60=0.25, modes=3, bright=0.9, click=0.5)
    mix.place(y, _n(tink), 0.0, 0.3)
    mix.place(y, _n(kit.boom(0.2, 220, 120, 0.01, 0.07)), 0, 0.3)
    y = filters.highpass(y, 80, 2)
    return kit.space(y, rng, "outdoor_slapback", -16.0)


def _interior(y: np.ndarray, rng, wet_db: float = -8.0, lp: float = 2400.0) -> np.ndarray:
    y = kit.space(y, rng, "tank_interior", wet_db)
    return filters.lowpass(y, lp, 2)


def hit_taken_pen(rng, variant):
    dur = 1.9
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(kit.boom(1.2, rng.uniform(80, 92), 42, 0.05, 0.7)), 0, 1.0)
    mix.place(y, _n(kit.noise_burst(rng, 1.0, 0.004, 0.6, 40, 350, "brown")), 0, 0.8)
    hull = kit.modal_hit(rng, 1.6, rng.uniform(105, 125), "hull", t60=1.1, modes=9, bright=0.4, click=0.0)
    mix.place(y, _n(hull), 0.0, 0.55)
    crunch = filters.lowpass(kit.debris(rng, 0.4, 900, "crunch", 0.08, (500, 2500)), 2200, 2)
    mix.place(y, _n(crunch), 0.004, 0.5)
    mix.place(y, _n(filters.lowpass(tear_layer(rng, 0.5, 2000, 600), 2500, 2)), 0.03, 0.35)
    mix.place(y, _n(filters.lowpass(kit.debris(rng, 1.4, 20, "crunch", 0.5, (800, 2500), start=0.15), 3000, 2)), 0, 0.15)
    ring = osc.sine(rng.uniform(3700, 3900), n_of(1.6)) * env.perc(n_of(1.6), 0.06, 1.5)
    y = filters.highpass(fx.saturate(_n(y), 1.6), 32, 2)
    y = _interior(y, rng, -7.0, 2600)
    mix.place(y, ring, 0.05, 0.02)
    return y


def hit_taken_blocked(rng, variant):
    dur = 1.7
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(kit.boom(1.0, rng.uniform(90, 100), 48, 0.04, 0.5)), 0, 0.9)
    hull = kit.modal_hit(rng, 1.6, rng.uniform(120, 150), "hull", t60=1.3, modes=9, bright=0.5, click=0.3, click_hz=900)
    mix.place(y, _n(hull), 0, 0.9)
    mix.place(y, _n(kit.noise_burst(rng, 0.6, 0.003, 0.35, 40, 320, "brown")), 0, 0.5)
    y = filters.highpass(fx.saturate(_n(y), 1.4), 32, 2)
    return _interior(y, rng, -8.0, 1900)


def hit_taken_ricochet(rng, variant):
    dur = 1.4
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(kit.boom(0.6, 120, 62, 0.02, 0.28)), 0, 0.6)
    hull = kit.modal_hit(rng, 1.2, rng.uniform(160, 190), "hull", t60=0.9, modes=9, bright=0.55, click=0.5, click_hz=1500)
    mix.place(y, _n(hull), 0, 0.7)
    wh = ricochet_whine(rng, 0.8, rng.uniform(2600, 3000), rng.uniform(900, 1100))
    mix.place(y, _n(filters.lowpass(wh, 2400, 2)), 0.02, 0.4)
    y = filters.highpass(y, 32, 2)
    return _interior(y, rng, -9.0, 3000)


# --------------------------------------------------------------------------- damage
def module_damaged(rng, variant):
    n = n_of(0.9)
    y = np.zeros(n)
    mix.place(y, _n(kit.debris(rng, 0.3, 900, "crunch", 0.06, (700, 4000))), 0, 0.7)
    mix.place(y, _n(kit.modal_hit(rng, 0.6, rng.uniform(380, 520), "plate", t60=0.25, modes=8, bright=0.5, click=0.8)), 0, 0.7)
    sp = kit.crackle(rng, n_of(0.4), 500, 1800, 10000) * env.perc(n_of(0.4), 0.002, 0.3)
    mix.place(y, _n(sp), 0.02, 0.45)
    mix.place(y, _n(kit.boom(0.3, 160, 90, 0.01, 0.12)), 0, 0.4)
    return kit.space(y, rng, "small_room", -14.0)


def track_broken(rng, variant):
    n = n_of(1.4)
    y = np.zeros(n)
    snap = kit.modal_hit(rng, 1.0, rng.uniform(1400, 1700), "bar", t60=0.6, modes=5, bright=0.8, click=1.5)
    mix.place(y, _n(snap), 0, 0.8)
    mix.place(y, _n(kit.crack(0.9)), 0, 0.6)
    mix.place(y, _n(kit.debris(rng, 1.2, 45, "metal", 0.35, (400, 1600), start=0.04)), 0, 0.55)
    slap = mix.mix(kit.noise_burst(rng, 0.4, 0.002, 0.2, 40, 600, "brown"), (kit.modal_hit(rng, 0.4, 240, "plate", t60=0.12, modes=6), 0.4))
    mix.place(y, _n(slap), rng.uniform(0.2, 0.3), 0.8)
    return kit.space(y, rng, "outdoor_slapback", -14.0)


def engine_damaged(rng, variant):
    dur = 2.4
    n = n_of(dur)
    rpm = env.breakpoints([(0, 1500), (0.25, 1200), (0.6, 700), (0.9, 1100), (1.3, 600), (1.8, 850), (dur, 750)], n, kind="smooth")
    comb = env.breakpoints([(0, 1.0), (0.4, 0.7), (1.0, 0.5), (dur, 0.6)], n)
    eng = render_piston("medium_diesel", rng, n, rpm, 0.6, loop=False, misfire=0.55, combustion=comb, extra_knock=0.3)
    y = _n(eng) * 0.8
    for t in sorted(rng.uniform(0.15, 2.0, 4)):
        pop = mix.mix(kit.noise_burst(rng, 0.2, 0.0004, 0.07, 80, 3000, "white"), (kit.boom(0.2, 150, 70, 0.015, 0.1), 0.8))
        mix.place(y, _n(pop), t, rng.uniform(0.6, 1.0))
    clunk = kit.modal_hit(rng, 0.5, rng.uniform(300, 400), "hull", t60=0.2, modes=6, click=0.6)
    mix.place(y, _n(clunk), 0.05, 0.6)
    return env.fade(y, 0.0, 0.4)


def fire_ignition(rng, variant):
    dur = 2.4
    n = n_of(dur)
    src = noise.pink(n, rng)
    fc = env.breakpoints([(0, 250), (0.22, 2600), (0.8, 900), (dur, 700)], n, kind="exp")
    fw = filters.tv_lowpass(src, fc, 0.9) * env.breakpoints([(0, 0), (0.06, 0.5), (0.25, 1.0), (0.9, 0.55), (dur, 0.35)], n, kind="smooth")
    y = _n(fw) * 0.9
    mix.place(y, _n(kit.boom(1.0, 95, 42, 0.08, 0.6, 0.025)), 0.02, 0.7)
    cr = kit.crackle(rng, n, 40, 1200, 9000) * env.breakpoints([(0, 0), (0.25, 0.3), (1.0, 1.0), (dur, 1.0)], n)
    mix.place(y, _n(cr), 0, 0.35)
    y = env.fade(y, 0.0, 0.9)  # the dry layers must die away before the reverb tail takes over
    return env.fade(kit.space(y, rng, "outdoor_slapback", -16.0), 0.0, 0.5)


def fire_texture(rng, n: int, crackle_rate: float, roar_lp: float, loop: bool) -> np.ndarray:
    circ = (lambda fn, x: mix.circular(fn, x, 2)) if loop else (lambda fn, x: fn(x))
    roar = circ(lambda z: filters.lowpass(z, roar_lp, 2), noise.brown(n, rng))
    roar *= 0.55 + 0.45 * noise.smooth_random(n, rng, 8.0)
    mid = circ(lambda z: filters.band(z, 200, 1500, 2), noise.pink(n, rng))
    mid *= 0.5 + 0.5 * noise.smooth_random(n, rng, 3.0)
    hiss = circ(lambda z: filters.highpass(z, 5000, 2), noise.white(n, rng))
    cr = np.zeros(n)
    count = int(crackle_rate * n / SR)
    for p in rng.integers(0, n, count):
        k = n_of(rng.uniform(0.001, 0.006))
        pop = noise.white(k, rng) * np.exp(-np.linspace(0, 6, k))
        pop = filters.bandpass(pop, rng.uniform(1500, 6000), 1.5)
        a = min(rng.pareto(1.5) + 0.2, 8.0)
        if loop:
            mix.place_wrapped(cr, _n(pop), int(p), a)
        else:
            mix.place(cr, _n(pop), int(p), a)
    return 0.5 * roar / np.std(roar) * 0.25 + 0.35 * mid / np.std(mid) * 0.2 + 0.04 * hiss / np.std(hiss) + 0.25 * _n(cr)


def fire_loop(rng, variant):
    n = n_of(5.0)
    return fire_texture(rng, n, 22.0, 420.0, True)


def fire_extinguished(rng, variant):
    dur = 2.6
    n = n_of(dur)
    y = np.zeros(n)
    valve = kit.modal_hit(rng, 0.2, 650, "hull", t60=0.06, modes=5, click=1.0)
    mix.place(y, _n(valve), 0, 0.5)
    gas = filters.highpass(noise.white(n, rng), 1500, 2) * env.breakpoints([(0, 0), (0.02, 1.0), (0.9, 0.8), (dur, 0.0)], n, kind="smooth")
    gas = filters.peaking(gas, 4500, 4, 1.0)
    mix.place(y, _n(gas), 0.01, 0.6)
    fire = fire_texture(rng, n, 30.0, 500.0, False) * env.breakpoints([(0, 1.0), (0.3, 0.6), (1.2, 0.0), (dur, 0.0)], n)
    mix.place(y, _n(fire), 0, 0.5)
    sizzle = kit.crackle(rng, n, 400, 3000, 12000) * env.breakpoints([(0, 0), (0.2, 1.0), (1.6, 0.0), (dur, 0)], n)
    mix.place(y, _n(sizzle), 0, 0.25)
    return env.fade(y, 0.0, 0.3)


def ammo_rack_damaged(rng, variant):
    dur = 1.7
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(kit.debris(rng, 0.25, 700, "metal", 0.05, (900, 4500))), 0, 0.6)
    f = env.breakpoints([(0, 1050), (0.25, 1500), (0.7, 1250), (1.2, 900), (dur, 820)], n, kind="smooth")
    f = f * (1 + 0.02 * noise.smooth_random(n, rng, 9.0))
    shriek = osc.additive(f, [1.0, 0.6, 0.45, 0.3, 0.2, 0.12], n, rng=rng)
    shriek *= 0.6 + 0.4 * np.abs(noise.smooth_random(n, rng, 40.0))
    shriek *= 0.7 + 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * 7.0 * t_of(n)))  # alarm-ish pulsing
    shriek *= env.adsr(n, 0.04, 0.2, 0.7, 0.6)
    mix.place(y, _n(filters.peaking(shriek, 2800, 6, 2.0)), 0.03, 0.6)
    for k in range(2):
        ping = kit.modal_hit(rng, 0.5, 2900 + 400 * k, "bar", t60=0.3, modes=3, bright=0.9)
        mix.place(y, _n(ping), 0.35 + 0.18 * k, 0.35)
    return kit.space(y, rng, "small_room", -12.0)


def explosion(rng, size: str) -> np.ndarray:
    """Dry vehicle explosion; size in medium | large | ammo."""
    cfg = {
        "medium": dict(dur=4.2, boom=(80, 42, 0.04, 0.55), body=1.2, roar=0.8, cookoffs=0, debris=60, toss=False),
        "large": dict(dur=5.0, boom=(70, 38, 0.05, 0.7), body=1.6, roar=1.0, cookoffs=1, debris=80, toss=True),
        "ammo": dict(dur=6.0, boom=(62, 34, 0.06, 0.85), body=2.2, roar=1.3, cookoffs=5, debris=110, toss=True),
    }[size]
    n = n_of(cfg["dur"])
    y = np.zeros(n)
    mix.place(y, _n(kit.crack(2.4)), 0, 0.6)
    mix.place(y, _n(kit.noise_burst(rng, 0.5, 0.0003, 0.12, 300, 12000, "white")), 0, 0.6)
    f_hi, f_lo, sw, t60 = cfg["boom"]
    mix.place(y, _n(kit.boom(cfg["dur"], f_hi, f_lo, sw, t60, 0.004)), 0, 0.9)
    mix.place(y, _n(kit.noise_burst(rng, cfg["dur"], 0.004, cfg["body"], 40, 450, "brown")), 0, 0.8)
    mix.place(y, _n(kit.noise_burst(rng, cfg["dur"], 0.006, cfg["roar"], 120, 2500, "pink")), 0, 0.6)
    mix.place(y, _n(kit.whoosh(rng, 1.6, 300, 1500, 0.9, 0.2)), 0.05, 0.4)
    crunch = kit.debris(rng, 0.5, 1200, "crunch", 0.1, (500, 3500))
    mix.place(y, _n(crunch), 0.004, 0.45)
    mix.place(y, _n(tear_layer(rng, 0.9, 2400, 500, (110, 45))), 0.05, 0.3)
    for _i in range(cfg["cookoffs"]):
        t = rng.uniform(0.25, 2.4) if size == "ammo" else 0.22
        c = mix.mix(kit.crack(1.2), kit.noise_burst(rng, 0.6, 0.0005, 0.25, 80, 6000, "pink"), (kit.boom(0.6, 110, 55, 0.02, 0.3), 1.2))
        mix.place(y, _n(c), t, rng.uniform(0.35, 0.7))
    mix.place(y, _n(kit.debris(rng, cfg["dur"], cfg["debris"], "metal", 0.9, (500, 3500), start=0.3)), 0, 0.3)
    if cfg["toss"]:
        tl = rng.uniform(2.1, 2.8)
        land = mix.mix(kit.modal_hit(rng, 1.5, rng.uniform(90, 120), "hull", t60=0.9, modes=9, bright=0.4, click=0.8),
                       (kit.noise_burst(rng, 0.8, 0.003, 0.3, 40, 500, "brown"), 0.9))
        mix.place(y, _n(land), tl, 0.55)
        mix.place(y, _n(kit.debris(rng, 1.2, 60, "metal", 0.3, (700, 3000))), tl + 0.02, 0.25)
    y = fx.saturate(_n(y), 2.0, "tanh")
    return filters.highpass(y, 35, 2)


def explosion_variant(size: str, dist: str):
    def render(rng, variant):
        dry = explosion(rng, size)
        if dist == "close":
            return kit.space(kit.space(dry, rng, "outdoor_slapback", -12.0), rng, "valley_echo", -16.0)
        y = kit.distance_far(dry, rng, lp=800, soften=0.03, echo_db=-6.0)
        return y

    return render


def wreck_burning(rng, variant):
    n = n_of(6.0)
    y = fire_texture(rng, n, 9.0, 300.0, True) * 0.8
    for _ in range(5):
        tick = kit.modal_hit(rng, 0.4, rng.uniform(2000, 4200), "bar", t60=rng.uniform(0.1, 0.3), modes=3, bright=0.8, click=0.4)
        mix.place_wrapped(y, _n(tick), int(rng.integers(0, n)), rng.uniform(0.08, 0.18))
    cr = kit.creak(rng, 1.0, np.linspace(25, 50, 30), [(380, 10, 1.0), (900, 12, 0.6), (2100, 14, 0.3)])
    cr *= env.ar(cr.shape[0], 0.3, 0.4)
    mix.place_wrapped(y, _n(cr), int(rng.integers(0, n)), 0.15)
    return y


def crew_injured(rng, variant):
    n = n_of(1.25)
    y = np.zeros(n)
    st = kit.static_burst(rng, 0.28, 70)
    mix.place(y, _n(kit.radio(st, rng)), 0, 0.5)
    for k, (f, t) in enumerate(((880.0, 0.26), (622.0, 0.46), (880.0, 0.66), (622.0, 0.86))):
        m = n_of(0.17)
        tone = osc.square(f, m, pw=0.4) * 0.4 + osc.sine(f, m)
        tone *= env.ar(m, 0.006, 0.03) * (1.0 if k < 2 else 0.6)
        mix.place(y, kit.radio(tone, rng, drive=1.5, hiss=0.0), t, 0.7)
    mix.place(y, _n(kit.squelch_tail(rng)), 1.08, 0.35)
    return kit.stereo_space(y, rng, "small_room", 0.12)


# --------------------------------------------------------------------------- destruction
def fence_break(rng, variant):
    n = n_of(1.4)
    y = np.zeros(n)
    snap = kit.modal_hit(rng, 0.4, rng.uniform(300, 600), "wood", t60=0.06, modes=5, bright=0.6, click=1.6, click_hz=3000)
    mix.place(y, _n(snap), 0, 0.9)
    mix.place(y, _n(kit.crack(0.6, hp=800)), 0, 0.5)
    mix.place(y, _n(kit.debris(rng, 1.0, 90, "wood", 0.25, (700, 2600))), 0.01, 0.45)
    for t in sorted(rng.uniform(0.2, 0.9, int(rng.integers(3, 6)))):
        h = kit.modal_hit(rng, 0.3, rng.uniform(180, 420), "wood", t60=0.1, modes=4, bright=0.4, click=0.8)
        mix.place(y, _n(h), t, rng.uniform(0.3, 0.6))
    if variant == "c":
        tw = kit.modal_hit(rng, 1.2, rng.uniform(500, 700), "bar", t60=0.7, modes=3, bright=0.5)
        mix.place(y, _n(tw), 0.02, 0.25)
    return kit.space(y, rng, "forest", -14.0)


def wooden_building_collapse(rng, variant):
    dur = 3.8
    n = n_of(dur)
    y = np.zeros(n)
    for t in (0.0, rng.uniform(0.12, 0.2), rng.uniform(0.3, 0.42)):
        c = mix.mix(kit.crack(0.8, hp=600), (kit.modal_hit(rng, 0.4, rng.uniform(200, 400), "wood", t60=0.08, modes=5, click=1.4), 0.9))
        mix.place(y, _n(c), t, rng.uniform(0.6, 0.9))
    gr = kit.creak(rng, 1.1, np.linspace(18, 55, 40), [(180, 8, 1.0), (430, 10, 0.7), (980, 12, 0.35)])
    mix.place(y, _n(gr * env.ar(gr.shape[0], 0.2, 0.4)), 0.2, 0.4)
    for t in np.sort(rng.uniform(0.9, 2.1, 9)):
        h = mix.mix(kit.modal_hit(rng, 0.6, rng.uniform(90, 250), "wood", t60=0.2, modes=5, bright=0.35, click=0.8),
                    (kit.noise_burst(rng, 0.4, 0.002, 0.2, 40, 600, "brown"), 0.8))
        mix.place(y, _n(h), t, rng.uniform(0.4, 0.9))
    mix.place(y, _n(kit.debris(rng, 2.6, 160, "wood", 0.9, (400, 2500), start=0.1)), 1.0, 0.4)
    mix.place(y, _n(kit.whoosh(rng, 2.0, 400, 1800, 0.8, 0.3)), 1.0, 0.2)
    mix.place(y, _n(kit.noise_burst(rng, 2.5, 0.08, 1.4, 40, 300, "brown")), 0.95, 0.5)
    return kit.space(fx.saturate(_n(y), 1.4), rng, "outdoor_slapback", -12.0)


def brick_wall_collapse(rng, variant):
    dur = 3.2
    n = n_of(dur)
    y = np.zeros(n)
    mix.place(y, _n(mix.mix(kit.crack(1.2), kit.noise_burst(rng, 0.2, 0.0003, 0.04, 800, 9000, "white"))), 0, 0.6)
    mix.place(y, _n(kit.noise_burst(rng, dur, 0.1, 1.5, 35, 220, "brown")), 0.05, 0.85)
    mix.place(y, _n(kit.debris(rng, 3.0, 320, "brick", 0.8, (700, 3200), start=0.12)), 0, 0.6)
    for t in np.sort(rng.uniform(0.2, 1.4, 7)):
        h = kit.modal_hit(rng, 0.3, rng.uniform(280, 650), "rock", t60=0.07, modes=4, bright=0.4, click=1.2, click_hz=1500)
        mix.place(y, _n(h), t, rng.uniform(0.4, 0.8))
    mix.place(y, _n(kit.noise_burst(rng, 2.4, 0.2, 1.6, 2000, 8000, "pink")), 0.3, 0.1)
    return kit.space(fx.saturate(_n(y), 1.5), rng, "outdoor_slapback", -12.0)


def tree_fall(rng, variant):
    dur = 4.6
    n = n_of(dur)
    y = np.zeros(n)
    split = mix.mix(kit.crack(0.7, hp=700), (kit.modal_hit(rng, 0.5, rng.uniform(250, 380), "wood", t60=0.1, modes=5, bright=0.6, click=2.0), 1.0))
    mix.place(y, _n(split), 0, 0.9)
    cr = kit.creak(rng, 1.7, np.concatenate([np.linspace(14, 30, 30), np.linspace(30, 48, 20)]), [(170, 8, 1.0), (440, 10, 0.7), (1100, 12, 0.35)],
                   jitter=0.3)
    mix.place(y, _n(cr * env.ar(cr.shape[0], 0.25, 0.4)), 0.12, 0.55)
    for t in sorted(rng.uniform(0.4, 1.7, 3)):
        mix.place(y, _n(kit.modal_hit(rng, 0.3, rng.uniform(400, 800), "wood", t60=0.05, modes=4, click=1.5, click_hz=3000)), t, 0.4)
    t_hit = rng.uniform(2.75, 3.0)
    leaves = kit.whoosh(rng, 1.4, 1800, 6000, 0.7, 0.75, "white")
    mix.place(y, _n(leaves), t_hit - 1.05, 0.4)
    thud = mix.mix(kit.boom(1.2, 85, 40, 0.05, 0.5, 0.006), (kit.noise_burst(rng, 1.0, 0.004, 0.45, 40, 500, "brown"), 0.8))
    mix.place(y, _n(thud), t_hit, 0.95)
    mix.place(y, _n(kit.debris(rng, 1.4, 70, "wood", 0.3, (700, 3000))), t_hit, 0.35)
    rustle = filters.band(noise.white(n_of(1.2), rng), 2000, 9000, 2) * env.perc(n_of(1.2), 0.01, 1.0)
    mix.place(y, _n(rustle), t_hit + 0.02, 0.3)
    return kit.space(y, rng, "forest", -12.0)


def bush_rustle(rng, variant):
    dur = rng.uniform(0.75, 1.1)
    n = n_of(dur)
    out = np.zeros(n)
    count = int(450 * dur)
    for p in rng.integers(0, n, count):
        k = n_of(rng.uniform(0.006, 0.03))
        g = noise.white(k, rng) * np.hanning(k)
        g = filters.bandpass(g, rng.uniform(1800, 8500), 1.4)
        mix.place(out, _n(g), int(p), 10 ** (-rng.random() * 18 / 20))
    out *= env.breakpoints([(0, 0), (dur * 0.2, 1.0), (dur * 0.55, 0.8), (dur, 0.0)], n, kind="smooth")
    for t in sorted(rng.uniform(0.05, dur * 0.6, 2)):
        tw = kit.modal_hit(rng, 0.08, rng.uniform(1800, 3200), "wood", t60=0.02, modes=3, click=1.5, click_hz=4000)
        mix.place(out, _n(tw), t, 0.3)
    return out


def container_impact(rng, variant):
    dur = 2.8
    n = n_of(dur)
    y = np.zeros(n)
    hull = kit.modal_hit(rng, dur, rng.uniform(58, 75), "hull", t60=1.8, modes=9, bright=0.5, click=0.6, click_hz=1200)
    mix.place(y, _n(hull), 0, 0.9)
    sheet = kit.modal_hit(rng, 1.8, rng.uniform(280, 340), "plate", t60=0.9, modes=12, bright=0.6, click=0.5)
    mix.place(y, _n(sheet), 0, 0.5)
    mix.place(y, _n(kit.boom(1.0, 110, 55, 0.02, 0.4)), 0, 0.6)
    mix.place(y, _n(kit.debris(rng, 1.5, 35, "metal", 0.4, (900, 3000), start=0.05)), 0, 0.2)
    y = filters.highpass(y, 40, 2)
    return kit.space(y, rng, "outdoor_slapback", -12.0)


def bridge_creak(rng, variant):
    dur = 2.4
    n = n_of(dur)
    rate = np.concatenate([np.linspace(8, 30, 40), np.linspace(30, 12, 30)])
    cr = kit.creak(rng, dur, rate, [(180, 9, 1.0), (420, 10, 0.7), (950, 12, 0.4)], jitter=0.3, grain_tau=0.002)
    y = _n(cr) * env.ar(n, 0.3, 0.6)
    groan = osc.sine(rng.uniform(60, 75) * (1 + 0.05 * noise.smooth_random(n, rng, 2.0)), n) * env.ar(n, 0.5, 0.8)
    mix.place(y, groan, 0, 0.15)
    trickle = kit.debris(rng, dur, 40, "dirt", 3.0, (1500, 5000), start=0.6)
    mix.place(y, _n(trickle), 0, 0.12)
    return y


# --------------------------------------------------------------------------- registration
def _register() -> None:
    mats = {
        "dirt": "earth: thump, soil clods and long dirt patter",
        "rock": "rock: sharp crack and stone chips",
        "concrete": "concrete: crack, crumble, dust and a rebar ping",
        "water": "water: plunge, splash spray, bubble cluster and falling droplets",
        "snow": "snow: muffled thump and soft powder 'poof'",
        "sand": "sand: thump and hissing sand shower",
        "wood": "wood: splintering crack and timber debris",
        "metal_building": "sheet-metal structure: big wobbling clang and rattle",
    }
    for m, d in mats.items():
        sound(f"impact_{m}", "impacts", ground_impact(m), f"Shell ground impact on {d}.",
              f"Shell (any type) hits terrain/prop of material '{m}' (HE adds its explosion layer separately if desired).",
              variants="abc", level=-13.0 if m != "snow" else -15.0, min_m=8, max_m=450, group="impact")
    sound("armor_penetration", "armor", armor_penetration, "PENETRATION: heavy boom, dense metal crunch and a tearing metal sweep.",
          "Shell penetrates a vehicle (shooter hears it 2D at priority 95; others positional).", variants="abc", level=-10.0,
          priority=96, group="armor_result")
    sound("armor_ricochet", "armor", armor_ricochet, "RICOCHET: bright high ping and a falling, tumbling whine.",
          "Shell ricochets off armor.", variants="abc", level=-11.5, priority=95, group="armor_result")
    sound("armor_blocked", "armor", armor_blocked, "NON-PENETRATION: dull, short, low-mid clang with a thud.",
          "Shell hits but does not penetrate (blocked / absorbed by spaced armor).", variants="abc", level=-11.5, priority=95,
          group="armor_result")
    sound("armor_critical", "armor", armor_critical, "CRITICAL MODULE HIT: razor snap, electric zap, arcing buzz and sparks.",
          "Penetration that damages a module or crew (plays with/after the penetration cue).", variants="abc", level=-11.0,
          priority=96, group="armor_result")
    sound("armor_hit_taken_pen", "armor", hit_taken_pen, "HIT TAKEN (inside, penetrated): muffled heavy thud, hull bong, interior crunch.",
          "Own vehicle penetrated (2D, interior perspective; duck Vehicles/Ambience).", variants="abc", level=-11.0, priority=97,
          min_m=None, max_m=None, group="hit_taken")
    sound("armor_hit_taken_blocked", "armor", hit_taken_blocked, "HIT TAKEN (inside, blocked): muffled thud and ringing hull bong.",
          "Own vehicle hit without penetration (2D).", variants="abc", level=-12.5, priority=94, min_m=None, max_m=None, group="hit_taken")
    sound("armor_hit_taken_ricochet", "armor", hit_taken_ricochet, "HIT TAKEN (inside, ricochet): glancing thud, bright hull ring, muffled whine.",
          "Own vehicle hit, shell ricocheted (2D).", variants="abc", level=-13.5, priority=92, min_m=None, max_m=None, group="hit_taken")

    sound("dmg_module_damaged", "damage", module_damaged, "Module damaged: short metal crunch, sparks, clank.",
          "Any module (gun, turret ring, optics, radio, fuel tank) damaged.", variants="ab", level=-15.0)
    sound("dmg_track_broken", "damage", track_broken, "Track snaps: loud metallic ping/crack, link clatter, slap.",
          "Track module destroyed.", variants="ab", level=-13.0, priority=85)
    sound("dmg_engine_damaged", "damage", engine_damaged, "Engine damaged: coughing, misfiring, backfire pops.",
          "Engine module damaged (then switch to the family's _damaged loop).", variants="ab", level=-15.0, priority=82)
    sound("dmg_fire_ignition", "damage", fire_ignition, "Fire starts: fuel 'fwoomp' and rising crackle.",
          "Vehicle catches fire (then start dmg_fire_loop).", level=-13.0, priority=88)
    sound("dmg_fire_loop", "damage", fire_loop, "Vehicle fire loop: roaring flames, fluttering, crackle pops.",
          "While a vehicle is burning.", loop=True, loop_s=5.0, level=-20.0, priority=70, max_m=150)
    sound("dmg_fire_extinguished", "damage", fire_extinguished, "Fire extinguisher discharge, flames choke out, sizzle.",
          "Fire put out (automatic or consumable).", level=-15.0, priority=80)
    sound("dmg_ammo_rack_damaged", "damage", ammo_rack_damaged, "Ammo rack damaged: alarm-like metal shriek with pulsing and pings.",
          "Ammo rack module damaged (warning: next hit may detonate).", level=-13.0, priority=90)
    for dist in ("close", "far"):
        lo, hi = (8, 450) if dist == "close" else (300, 2000)
        sound(f"dmg_ammo_rack_detonation_{dist}", "damage", explosion_variant("ammo", dist),
              f"Ammo rack detonation ({dist}): enormous blast, cook-offs, turret toss and crash.",
              "Vehicle destroyed by ammo rack detonation.", level=-9.0 if dist == "close" else -16.0, priority=93 if dist == "close" else 70,
              distance_variant=dist, min_m=lo, max_m=hi, group="dmg_ammo_rack_detonation")
        for size in ("medium", "large"):
            sound(f"dmg_vehicle_destroyed_{size}_{dist}", "damage", explosion_variant(size, dist),
                  f"Vehicle destroyed explosion, {size} vehicle, {dist} variant.",
                  f"Vehicle destroyed ({size} = light/medium hulls, large = heavy/TD hulls).",
                  level=(-10.0 if size == "large" else -11.0) if dist == "close" else -17.0, priority=90 if dist == "close" else 65,
                  distance_variant=dist, min_m=lo, max_m=hi, group=f"dmg_vehicle_destroyed_{size}")
    sound("dmg_wreck_burning_loop", "damage", wreck_burning, "Burning wreck: low roar, sparse crackle, thermal metal ticks and creaks.",
          "Wreck of a destroyed vehicle (fade out after 30-60 s).", loop=True, loop_s=6.0, level=-24.0, priority=30, max_m=90)
    sound("dmg_crew_injured", "radio", crew_injured, "Crew injured stinger: radio crackle then a two-tone alert (no voice).",
          "Crew member injured (2D, own vehicle).", level=-17.0, priority=88)

    sound("env_fence_break", "destruction", fence_break, "Wooden fence smashed: snap, splinters, falling planks.",
          "Vehicle drives through a fence.", variants="abc", level=-17.0)
    sound("env_wooden_building_collapse", "destruction", wooden_building_collapse, "Wooden building collapse: cracks, groan, crashing timbers, debris.",
          "Destructible wooden building destroyed.", level=-13.0, priority=60, max_m=500)
    sound("env_brick_wall_collapse", "destruction", brick_wall_collapse, "Brick wall collapse: crack, rumble, brick clatter, dust.",
          "Destructible masonry wall destroyed.", level=-13.0, priority=60, max_m=500)
    sound("env_tree_fall", "destruction", tree_fall, "Tree knocked down: split crack, creaking, leaf swish, ground thud.",
          "Vehicle fells a tree.", variants="ab", level=-15.0)
    sound("env_bush_rustle", "destruction", bush_rustle, "Bush rustle: leaves and small twigs.", "Vehicle pushes through bushes/foliage.",
          variants="abc", level=-23.0, priority=25, max_m=80)
    sound("env_metal_container_impact", "destruction", container_impact, "Metal shipping container hit: huge hollow boom and ring.",
          "Vehicle rams / shell hits a metal container or tank.", variants="ab", level=-14.0)
    sound("env_bridge_creak", "destruction", bridge_creak, "Timber bridge creak and groan with dust trickle.",
          "Heavy vehicle on a wooden bridge (random every few seconds).", variants="ab", level=-21.0, priority=35, max_m=150)


_register()
