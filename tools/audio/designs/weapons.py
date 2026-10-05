"""Gun firing (per calibre class and distance band), reload mechanics, shell flybys.

A close gunshot is layered from: the muzzle-blast N-wave crack, a broadband blast burst, a
pitch-dropping sub boom, a low body (propellant gas), a mid 'roar', the recoil/breech
clank and an outdoor slap-back tail with a rolling low rumble. Calibre classes scale
frequencies down and decays up. Distance variants are derived from the same dry layers:

* ``mid``  - crack attenuated, air-absorption low-pass ~3.2 kHz, more slap-back and echo;
* ``far``  - no crack, 4th-order low-pass ~0.9 kHz, softened attack, valley echo and a
  delayed low rumble (the sound "rolls" in rather than snapping).
"""

from __future__ import annotations

import numpy as np

from synth import env, filters, fx, mix, noise, osc, reverb
from synth.core import n_of, t_of

from . import kit
from .registry import sound

GUNS = {
    "small_20_45mm": dict(label="Small calibre (20-45 mm)", boom=(175, 82, 0.010, 0.14), punch=(220, 2400, 0.07), body=(0.25, 900),
                          roar=(450, 5000, 0.18), crack_ms=0.7, crack=1.0, burst=0.035, mech=(1900, 0.6), tail=0.8, length=1.8),
    "medium_50_85mm": dict(label="Medium calibre (50-85 mm)", boom=(135, 64, 0.016, 0.2), punch=(170, 2000, 0.1), body=(0.4, 760),
                           roar=(300, 4000, 0.28), crack_ms=1.0, crack=0.9, burst=0.05, mech=(1300, 0.55), tail=1.2, length=2.4),
    "large_88_122mm": dict(label="Large calibre (88-122 mm)", boom=(110, 52, 0.022, 0.28), punch=(140, 1700, 0.14), body=(0.6, 620),
                           roar=(220, 3200, 0.4), crack_ms=1.4, crack=0.8, burst=0.065, mech=(950, 0.5), tail=1.7, length=3.0),
    "huge_130_183mm": dict(label="Huge calibre (130-183 mm)", boom=(92, 44, 0.03, 0.38), punch=(120, 1400, 0.18), body=(0.85, 520),
                           roar=(170, 2600, 0.55), crack_ms=1.9, crack=0.75, burst=0.085, mech=(700, 0.45), tail=2.3, length=3.6),
    "artillery_howitzer": dict(label="Artillery howitzer", boom=(82, 38, 0.04, 0.48), punch=(100, 1200, 0.24), body=(1.1, 440),
                               roar=(130, 2200, 0.7), crack_ms=2.3, crack=0.6, burst=0.11, mech=(600, 0.4), tail=3.0, length=4.6),
}
AUTOCANNON = dict(label="Autocannon (20-40 mm) burst", boom=(200, 105, 0.007, 0.08), punch=(260, 3000, 0.045), body=(0.14, 1200),
                  roar=(600, 6500, 0.09), crack_ms=0.5, crack=1.0, burst=0.022, mech=(2400, 0.4), tail=0.6, length=0.8)

DIST_LEVEL = {"close": 0.0, "mid": -5.0, "far": -10.0}
BASE_LEVEL = {"small_20_45mm": -12.5, "medium_50_85mm": -11.5, "large_88_122mm": -11.0, "huge_130_183mm": -10.5,
              "autocannon_burst": -12.0, "artillery_howitzer": -10.5}
DIST_RANGE_M = {"close": (8, 200), "mid": (100, 600), "far": (400, 1500)}


def shot_layers(rng: np.random.Generator, p: dict, pitch: float = 1.0) -> dict:
    """Dry layers of a single shot (keyed so distance variants can re-weight them)."""
    L = p["length"]
    n = n_of(L)
    f_hi, f_lo, sweep, t60 = p["boom"]
    layers = {}
    cr = kit.crack(p["crack_ms"] / pitch)
    layers["crack"] = cr / np.max(np.abs(cr))
    b = kit.noise_burst(rng, 0.3, 0.0002, p["burst"], 600, 12000, "white")
    layers["burst"] = b / np.max(np.abs(b))
    plo, phi, pt60 = p["punch"]
    pu = kit.noise_burst(rng, L, 0.0005, pt60, plo * pitch, phi * pitch, "pink")
    layers["punch"] = pu / np.max(np.abs(pu))
    bm = kit.boom(L, f_hi * pitch, f_lo * pitch, sweep, t60, 0.0015)
    layers["boom"] = bm / np.max(np.abs(bm))
    body_t60, body_lp = p["body"]
    bd = kit.noise_burst(rng, L, 0.002, body_t60, 45, body_lp * pitch, "brown")
    layers["body"] = bd / np.max(np.abs(bd))
    lo, hi, rt60 = p["roar"]
    rr = kit.noise_burst(rng, L, 0.003, rt60, lo * pitch, hi, "pink")
    layers["roar"] = rr / np.max(np.abs(rr))
    mf, mt = p["mech"]
    mech = kit.modal_hit(rng, 0.6, mf * pitch * rng.uniform(0.95, 1.05), "plate", t60=mt, modes=8, bright=0.5, click=0.4)
    m = np.zeros(n)
    mix.place(m, mech / np.max(np.abs(mech)), rng.uniform(0.025, 0.05))
    layers["mech"] = m
    # rolling rumble tail (low-mid, not sub: must read on small speakers)
    rum = filters.band(noise.brown(n, rng), 45, 260, 2) * env.perc(n, 0.06, p["tail"])
    rum *= 0.65 + 0.35 * noise.smooth_random(n, rng, 6.0)
    layers["rumble"] = rum / np.max(np.abs(rum))
    return layers


def mix_shot(layers: dict, weights: dict, n: int) -> np.ndarray:
    y = np.zeros(n)
    for k, w in weights.items():
        if w:
            mix.place(y, layers[k], 0, w)
    return y


CLOSE_W = dict(crack=0.5, burst=0.45, punch=0.8, boom=0.7, body=0.5, roar=0.5, mech=0.12, rumble=0.3)


def _clean_low(x: np.ndarray) -> np.ndarray:
    """Remove infrasonic energy that small speakers cannot reproduce but that eats headroom."""
    return filters.highpass(x, 38, 2)


def gun_shot(cls: str, dist: str):
    p = GUNS[cls]

    def render(rng, variant):
        pitch = rng.uniform(0.94, 1.06)
        lay = shot_layers(rng, p, pitch)
        n = n_of(p["length"])
        w = dict(CLOSE_W)
        w["crack"] *= p["crack"]
        if dist == "close":
            dry = mix_shot(lay, w, n)
            dry = _clean_low(fx.saturate(dry / np.max(np.abs(dry)), 2.4, "tanh"))
            y = kit.space(dry, rng, "outdoor_slapback", -13.0)
            if cls in ("huge_130_183mm", "artillery_howitzer"):
                y = kit.space(y, rng, "valley_echo", -16.0)
            return y
        if dist == "mid":
            w2 = dict(w, crack=w["crack"] * 0.2, burst=w["burst"] * 0.3, rumble=w["rumble"] * 1.5)
            d2 = mix_shot(lay, w2, n)
            d2 = _clean_low(fx.saturate(d2 / np.max(np.abs(d2)), 1.6, "tanh"))
            d2 = kit.distance_far(d2, rng, lp=3200, soften=0.004, echo_db=-12.0, space_name="valley_echo")
            return kit.space(d2, rng, "outdoor_slapback", -10.0)
        # far: no crack, dark, softened onset, valley echo and a delayed rolling rumble
        w3 = dict(w, crack=0.0, burst=0.0, mech=0.0, rumble=w["rumble"] * 1.2)
        d3 = _clean_low(mix_shot(lay, w3, n))
        y = kit.distance_far(d3, rng, lp=850, soften=0.03, echo_db=-7.0, space_name="valley_echo")
        m = n_of(p["tail"] * 1.6 + 0.5)
        late = filters.band(noise.brown(m, rng), 40, 160, 2) * env.perc(m, 0.25, p["tail"] * 1.3)
        late *= 0.7 + 0.3 * noise.smooth_random(m, rng, 3.0)
        mix.place(y, late / np.max(np.abs(late)) * np.max(np.abs(y)), rng.uniform(0.18, 0.32), 0.4)
        return y

    return render


def autocannon(dist: str):
    def render(rng, variant):
        rounds = {"a": 3, "b": 4, "c": 5}.get(variant, 4)
        interval = rng.uniform(0.12, 0.15)
        total = interval * rounds + 1.6
        n = n_of(total)
        dry = np.zeros(n)
        mechs = np.zeros(n)
        for i in range(rounds):
            lay = shot_layers(rng, AUTOCANNON, rng.uniform(0.96, 1.04))
            w = dict(CLOSE_W)
            if dist != "close":
                w["crack"] *= 0.2 if dist == "mid" else 0.0
                w["burst"] *= 0.3 if dist == "mid" else 0.0
            s = mix_shot(lay, w, n_of(AUTOCANNON["length"]))
            s = fx.saturate(s / np.max(np.abs(s)), 2.0, "tanh")
            t = i * interval + rng.normal(0, 0.004)
            mix.place(dry, s / np.max(np.abs(s)), max(t, 0.0), rng.uniform(0.85, 1.0))
            bolt = kit.modal_hit(rng, 0.2, rng.uniform(2200, 2800), "bar", t60=0.05, modes=3, bright=0.7, click=0.8)
            mix.place(mechs, bolt / np.max(np.abs(bolt)), t + 0.045, 0.18)
            case = kit.modal_hit(rng, 0.4, rng.uniform(3000, 4200), "tube", t60=0.3, modes=6, bright=0.8, click=0.3)
            mix.place(mechs, case / np.max(np.abs(case)), t + rng.uniform(0.25, 0.45), 0.06)
        dry = _clean_low(dry)
        if dist == "close":
            return kit.space(dry + mechs, rng, "outdoor_slapback", -12.0)
        if dist == "mid":
            y = filters.lowpass(dry, 3500, 2)
            return kit.space(kit.distance_far(y, rng, lp=4000, soften=0.003, echo_db=-12.0), rng, "outdoor_slapback", -10.0)
        return kit.distance_far(dry, rng, lp=950, soften=0.02, echo_db=-7.0)

    return render


# --------------------------------------------------------------------------- reload
def interior(x: np.ndarray, rng: np.random.Generator, wet: float = 0.25) -> np.ndarray:
    return reverb.convolve(x, reverb.impulse_response("tank_interior", rng), wet=wet)


def shell_clank(rng, variant):
    n = n_of(1.0)
    y = np.zeros(n)
    case = kit.modal_hit(rng, 0.9, rng.uniform(620, 880), "tube", t60=rng.uniform(0.45, 0.65), modes=8, bright=0.7, click=0.6)
    thud = kit.modal_hit(rng, 0.3, rng.uniform(220, 300), "plate", t60=0.08, modes=6, bright=0.3, click=0.5)
    mix.place(y, case / np.max(np.abs(case)), 0.0, 0.8)
    mix.place(y, thud / np.max(np.abs(thud)), 0.0, 0.7)
    b2 = kit.modal_hit(rng, 0.6, rng.uniform(620, 880), "tube", t60=0.35, modes=6, bright=0.6, click=0.4)
    mix.place(y, b2 / np.max(np.abs(b2)), rng.uniform(0.07, 0.13), 0.35)
    return interior(y, rng, 0.3)


def breech_close(rng, variant):
    n = n_of(0.8)
    y = np.zeros(n)
    m = n_of(0.08)
    slide = filters.band(noise.white(m, rng), 700, 3000, 2) * np.linspace(0.2, 1.0, m) ** 2
    mix.place(y, slide, 0.0, 0.25)
    chunk = kit.modal_hit(rng, 0.5, rng.uniform(160, 200), "hull", t60=0.15, modes=8, bright=0.35, click=0.7, click_hz=1800)
    steel = kit.modal_hit(rng, 0.3, rng.uniform(900, 1200), "bar", t60=0.08, modes=4, bright=0.6, click=0.6)
    thump = kit.boom(0.2, 140, 80, 0.01, 0.07)
    mix.place(y, chunk / np.max(np.abs(chunk)), 0.08, 1.0)
    mix.place(y, steel / np.max(np.abs(steel)), 0.08, 0.5)
    mix.place(y, thump / np.max(np.abs(thump)), 0.08, 0.6)
    latch = kit.modal_hit(rng, 0.1, rng.uniform(2800, 3400), "bar", t60=0.025, modes=2, bright=0.8, click=1.2)
    mix.place(y, latch / np.max(np.abs(latch)), 0.08 + rng.uniform(0.035, 0.05), 0.35)
    return interior(y, rng, 0.25)


def autoloader_cycle(rng, variant):
    dur = 1.6
    n = n_of(dur)
    y = np.zeros(n)
    m = n_of(0.75)
    f = env.breakpoints([(0, 260), (0.3, 520), (0.55, 520), (0.75, 300)], m, kind="smooth")
    whir = osc.additive(f, [1.0, 0.4, 0.3, 0.12], m, rng=rng) * env.ar(m, 0.06, 0.2)
    whir += 0.1 * filters.band(noise.white(m, rng), 1500, 5000, 2) * env.ar(m, 0.06, 0.2)
    mix.place(y, whir, 0.0, 0.3)
    for i in range(6):
        c = kit.modal_hit(rng, 0.1, rng.uniform(2200, 2900), "bar", t60=0.03, modes=2, click=1.0)
        mix.place(y, c / np.max(np.abs(c)), 0.06 + i * 0.065, 0.25)
    ram = mix.mix(kit.modal_hit(rng, 0.6, rng.uniform(650, 800), "tube", t60=0.45, modes=8, bright=0.6, click=0.6),
                  (kit.modal_hit(rng, 0.4, 190, "hull", t60=0.15, modes=6, bright=0.3), 0.8))
    mix.place(y, ram / np.max(np.abs(ram)), 0.72, 0.9)
    br = breech_close(rng, variant)
    mix.place(y, br / np.max(np.abs(br)), 1.02, 0.8)
    lock = kit.modal_hit(rng, 0.1, 3200, "bar", t60=0.03, modes=2, click=1.2)
    mix.place(y, lock / np.max(np.abs(lock)), 1.32, 0.3)
    return interior(y, rng, 0.2)


def magazine_reload(rng, variant):
    dur = 3.9
    n = n_of(dur)
    y = np.zeros(n)
    rel = kit.modal_hit(rng, 0.5, 170, "hull", t60=0.18, modes=8, bright=0.35, click=0.8)
    mix.place(y, rel / np.max(np.abs(rel)), 0.0, 0.9)
    m = n_of(0.5)
    f = env.breakpoints([(0, 200), (0.2, 420), (0.5, 380)], m, kind="smooth")
    whir = osc.additive(f, [1.0, 0.45, 0.25], m, rng=rng) * env.ar(m, 0.05, 0.15)
    mix.place(y, whir, 0.15, 0.25)
    for i in range(7):
        c = kit.modal_hit(rng, 0.1, rng.uniform(2000, 2700), "bar", t60=0.03, modes=2, click=1.0)
        mix.place(y, c / np.max(np.abs(c)), 0.18 + i * 0.06, 0.2)
    for t in (0.85, 1.4, 1.95, 2.5):
        case = kit.modal_hit(rng, 0.6, rng.uniform(640, 860), "tube", t60=0.4, modes=7, bright=0.6, click=0.5)
        cha = kit.modal_hit(rng, 0.3, rng.uniform(230, 280), "plate", t60=0.07, modes=6, bright=0.35, click=0.6)
        chunk = kit.modal_hit(rng, 0.3, rng.uniform(1100, 1300), "bar", t60=0.05, modes=3, bright=0.6, click=0.8)
        mix.place(y, case / np.max(np.abs(case)), t, 0.6)
        mix.place(y, cha / np.max(np.abs(cha)), t, 0.6)
        mix.place(y, chunk / np.max(np.abs(chunk)), t + 0.09, 0.5)
    lock = mix.mix(kit.modal_hit(rng, 0.6, 150, "hull", t60=0.2, modes=8, bright=0.4, click=1.0),
                   (kit.boom(0.2, 150, 90, 0.01, 0.08), 0.6))
    mix.place(y, lock / np.max(np.abs(lock)), 3.05, 1.0)
    rdy = kit.modal_hit(rng, 0.1, 3300, "bar", t60=0.03, modes=2, click=1.2)
    mix.place(y, rdy / np.max(np.abs(rdy)), 3.35, 0.4)
    return interior(y, rng, 0.2)


def dual_gun_ready(rng, variant):
    n = n_of(0.45)
    y = np.zeros(n)
    for i, f in enumerate((2500, 2850)):
        c = kit.modal_hit(rng, 0.12, f, "bar", t60=0.035, modes=3, bright=0.8, click=1.3)
        mix.place(y, c / np.max(np.abs(c)), 0.0 + 0.07 * i, 0.6)
    m = n_of(0.06)
    tick = osc.sine(2200, m) * env.perc(m, 0.001, 0.05)
    mix.place(y, tick, 0.17, 0.35)
    return interior(y, rng, 0.15)


# --------------------------------------------------------------------------- flybys
def flyby(kind: str):
    def render(rng, variant):
        if kind == "ap":
            dur, t0, f_hi, f_lo, tau = 1.25, 0.42, rng.uniform(4200, 5200), rng.uniform(700, 950), 0.09
        elif kind == "he":
            dur, t0, f_hi, f_lo, tau = 1.55, 0.55, rng.uniform(1900, 2400), rng.uniform(420, 560), 0.16
        else:
            raise ValueError(kind)
        n = n_of(dur)
        t = t_of(n) - t0
        f = np.where(t < 0, f_hi * (1 + 0.08 * np.clip(-t / t0, 0, 1)), f_lo + (f_hi - f_lo) * np.exp(-np.maximum(t, 0) / tau))
        # perceptual pass envelope: short approach (supersonic rounds give little warning),
        # longer wake behind the round
        tau_in, tau_out = (0.035, 0.13) if kind == "ap" else (0.09, 0.22)
        tau = np.where(t < 0, tau_in, tau_out) * rng.uniform(0.85, 1.15)
        gain = 1.0 / np.sqrt(1.0 + (t / tau) ** 2)
        gain = gain ** (2.0 if kind == "ap" else 1.5)
        src = noise.white(n, rng) if kind == "ap" else noise.pink(n, rng)
        band = filters.tv_biquad(src, "bandpass", f, 2.5 if kind == "ap" else 3.5, block=32)
        turb = 0.55 + 0.45 * noise.smooth_random(n, rng, 90.0 if kind == "ap" else 40.0)
        y = band / np.std(band) * turb * gain
        tone = osc.sine(f, n) + 0.2 * osc.sine(2 * f, n)
        if kind == "he":
            flutter = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(24, 34) * t_of(n))
            y = 0.6 * y + 0.55 * tone * gain * flutter
        else:
            y = y + 0.12 * tone * gain
            cr = kit.crack(0.45, hp=1500)
            yy = np.zeros(n)
            mix.place(yy, cr / np.max(np.abs(cr)), max(0.0, t0 - 0.012))
            y = y / np.max(np.abs(y)) + 0.45 * yy
        return env.fade(y, 0.02, 0.3)

    return render


def artillery_whistle(rng, variant):
    dur = rng.uniform(2.2, 2.6)
    n = n_of(dur)
    x = np.linspace(0, 1, n)
    f0, f1 = rng.uniform(1700, 2100), rng.uniform(560, 700)
    f = f1 + (f0 - f1) * (1 - x) ** 1.4
    f = f * (1 + 0.006 * np.sin(2 * np.pi * 6.0 * t_of(n)))
    tone = osc.sine(f, n) + 0.18 * osc.sine(2 * f, n) + 0.06 * osc.sine(3 * f, n)
    breath = filters.tv_biquad(noise.white(n, rng), "bandpass", f, 6.0, block=32)
    amp = 0.08 + 0.92 * x**2.2
    y = (tone + 0.6 * breath / np.std(breath) * 0.3) * amp
    return env.fade(y, 0.05, 0.03)


def distant_thump(rng, variant):
    n = n_of(1.5)
    y = np.zeros(n)
    b = kit.boom(1.5, rng.uniform(85, 100), 48, 0.08, 0.35, 0.012)
    body = kit.noise_burst(rng, 1.5, 0.015, 0.8, None, 300, "brown")
    mix.place(y, b / np.max(np.abs(b)), 0, 1.0)
    mix.place(y, body / np.max(np.abs(body)), 0, 0.7)
    return kit.distance_far(filters.highpass(y, 35, 2), rng, lp=420, soften=0.02, echo_db=-8.0)


# --------------------------------------------------------------------------- registration
def _register() -> None:
    for cls, p in list(GUNS.items()) + [("autocannon_burst", AUTOCANNON)]:
        for dist in ("close", "mid", "far"):
            render = autocannon(dist) if cls == "autocannon_burst" else gun_shot(cls, dist)
            lo, hi = DIST_RANGE_M[dist]
            sound(f"gun_{cls}_{dist}", "guns", render,
                  f"{p['label']} firing, {dist} distance variant.",
                  f"Weapon fired (any vehicle). Pick variant by listener distance band '{dist}' and crossfade at band edges.",
                  variants="abc", level=BASE_LEVEL[cls] + DIST_LEVEL[dist], distance_variant=dist, min_m=lo, max_m=hi,
                  group=f"gun_{cls}", priority={"close": 92, "mid": 78, "far": 60}[dist],
                  meta={"class": cls})
    sound("reload_shell_clank", "reload", shell_clank, "Brass shell case knocking steel during loading.",
          "Manual loader handling a round (own vehicle, interior perspective).", variants="abc", level=-21.0)
    sound("reload_breech_close", "reload", breech_close, "Sliding breech block: slide, heavy chunk, latch click.",
          "Breech closes at the end of a manual reload.", variants="abc", level=-18.0, priority=70)
    sound("reload_autoloader_cycle", "reload", autoloader_cycle, "Autoloader: carousel ratchet, rammer slam, breech close, lock.",
          "Autoloader cycles a round (single-shot autoloaders, between drum shots).", variants="ab", level=-19.0)
    sound("reload_magazine_sequence", "reload", magazine_reload, "Full magazine/drum reload sequence (release, rotate, 4 rounds, lock, ready).",
          "Drum/magazine refill started (length ~3.9 s; stretch timing by playing in segments if the reload is longer).",
          level=-19.0, priority=65)
    sound("reload_dual_gun_ready", "reload", dual_gun_ready, "Two crisp latch clicks and a tick: both barrels ready.",
          "Dual-gun salvo ready.", level=-20.0, priority=75)
    sound("shell_flyby_ap", "shells", flyby("ap"), "Supersonic AP near miss: shock crack then tearing whoosh with Doppler drop.",
          "Enemy kinetic round passes within ~15 m of the listener.", variants="abc", level=-14.0, priority=82, min_m=5, max_m=50,
          meta={"closestApproachS": 0.42, "note": "start playback closestApproachS before the round's closest approach"})
    sound("shell_flyby_he", "shells", flyby("he"), "HE/HEAT near miss: lower fluttering whoosh, no crack.",
          "Enemy HE/HEAT round passes within ~15 m of the listener.", variants="abc", level=-14.0, priority=80, min_m=5, max_m=50,
          meta={"closestApproachS": 0.55, "note": "start playback closestApproachS before the round's closest approach"})
    sound("shell_whistle_artillery", "shells", artillery_whistle, "Incoming artillery whistle (falling pitch, crescendo).",
          "Artillery shell inbound near listener; ends right before impact (schedule impact at file end).",
          variants="ab", level=-15.0, priority=85, min_m=15, max_m=250, meta={"impactAtEnd": True})
    sound("shell_distant_thump", "shells", distant_thump, "Very distant gun report: dark thump with valley echo.",
          "Shot fired beyond the far band (>1.2 km) or from unspotted artillery.", variants="abc", level=-22.0, priority=35,
          min_m=600, max_m=3000, distance_variant="far")


_register()
