"""Vehicle engine families: RPM-layer loops, start/stop one-shots, damaged and overload layers.

Piston engines are synthesised from first principles: every combustion event of every
cylinder (4-stroke firing order, bank split for V engines, per-cylinder imbalance, timing
jitter) emits a tonal exhaust pressure pulse plus a noisy combustion burst; these drive an
exhaust-formant resonator bank. On top sit diesel knock clatter, turbo/supercharger whine,
intake rasp, crankcase rumble, gear whine and panel rattle. Gas turbines are built from
compressor blade-pass tones, shaft hum, combustion roar and intake hiss.

Loops are periodic by construction: the cycle frequency is snapped so the loop holds an
integer number of engine cycles, noise is FFT-periodic, and filtering/convolution is
circular - so the seam is mathematically continuous before the generic crossfade step.
"""

from __future__ import annotations

import numpy as np

from synth import env, filters, fx, mix, noise, osc
from synth.core import SR, as_signal, make_rng, n_of, t_of
from synth.mod import snap_freq

from . import kit
from .registry import sound

LOOP_S = 4.0
LAYERS = ("idle", "low", "mid", "high")
LOAD = {"idle": 0.12, "low": 0.4, "mid": 0.65, "high": 0.92}
LAYER_LUFS = {"idle": -21.5, "low": -20.0, "mid": -18.5, "high": -17.0}

PISTON = {
    "heavy_diesel": dict(
        label="Heavy V12 diesel (heavy tanks, heavy tank destroyers)",
        cyl=12, banks=2, rpm={"idle": 600, "low": 1000, "mid": 1500, "high": 2050},
        pulse_tau=0.0010, noise_tau=0.0042, noise_mix=0.5, direct=0.12,
        formants=[(44, 0.9, 1.0), (95, 1.5, 0.9), (205, 2.2, 0.6), (480, 2.8, 0.32), (1100, 2.5, 0.12)],
        knock=0.24, knock_band=(1600, 4800), turbo=(0.025, 2100, 5400), intake=0.05,
        rumble=0.75, gear=(0.010, 37), rattle=0.08, drive=1.6, lp=(1500, 5200),
        uneven=0.03, imbalance=0.15, rough=0.12, jitter_ms=0.25,
    ),
    "medium_diesel": dict(
        label="Medium V8 diesel (medium tanks, SPGs)",
        cyl=8, banks=2, rpm={"idle": 700, "low": 1200, "mid": 1800, "high": 2500},
        pulse_tau=0.00085, noise_tau=0.0035, noise_mix=0.45, direct=0.15,
        formants=[(78, 1.0, 0.9), (175, 1.6, 1.0), (400, 2.4, 0.7), (950, 3.0, 0.4), (2100, 2.5, 0.18)],
        knock=0.55, knock_band=(2200, 7000), turbo=(0.07, 3200, 7800), intake=0.18,
        rumble=0.25, gear=(0.012, 31), rattle=0.18, drive=2.2, lp=(2400, 8000),
        uneven=0.12, imbalance=0.22, rough=0.14, jitter_ms=0.3,
    ),
    "light_highrpm": dict(
        label="High-revving inline-6 petrol (light tanks, scouts)",
        cyl=6, banks=1, rpm={"idle": 900, "low": 2200, "mid": 3600, "high": 5200},
        pulse_tau=0.0005, noise_tau=0.0020, noise_mix=0.35, direct=0.2,
        formants=[(120, 1.2, 0.8), (260, 1.8, 1.0), (560, 2.5, 0.7), (1250, 3.0, 0.45), (2900, 2.5, 0.25)],
        knock=0.05, knock_band=(3000, 8000), turbo=None, intake=0.25,
        rumble=0.20, gear=(0.008, 23), rattle=0.08, drive=2.6, lp=(3000, 10000),
        uneven=0.01, imbalance=0.08, rough=0.08, jitter_ms=0.08,
    ),
    "large_v12": dict(
        label="Large petrol V12, aero-derived (fast heavies, mediums)",
        cyl=12, banks=2, rpm={"idle": 650, "low": 1300, "mid": 2100, "high": 2900},
        pulse_tau=0.0007, noise_tau=0.0030, noise_mix=0.38, direct=0.14,
        formants=[(70, 1.0, 0.9), (165, 1.4, 1.0), (380, 2.0, 0.7), (850, 2.6, 0.4), (1900, 2.4, 0.18)],
        knock=0.06, knock_band=(2500, 7000), turbo=(0.025, 1800, 5200), intake=0.15,
        rumble=0.45, gear=(0.009, 41), rattle=0.05, drive=2.0, lp=(2400, 8000),
        uneven=0.015, imbalance=0.07, rough=0.06, jitter_ms=0.1,
    ),
    "small_engine": dict(
        label="Small 4-cylinder petrol (armoured cars, light utility)",
        cyl=4, banks=1, rpm={"idle": 850, "low": 2000, "mid": 3200, "high": 4600},
        pulse_tau=0.00045, noise_tau=0.0018, noise_mix=0.32, direct=0.25,
        formants=[(160, 1.4, 0.8), (380, 2.0, 1.0), (900, 2.8, 0.6), (2100, 3.0, 0.35), (4200, 2.5, 0.15)],
        knock=0.08, knock_band=(2500, 7500), turbo=None, intake=0.2,
        rumble=0.15, gear=(0.010, 19), rattle=0.35, drive=3.0, lp=(3500, 11000),
        uneven=0.02, imbalance=0.18, rough=0.12, jitter_ms=0.15,
    ),
}

TURBINE = dict(
    label="Gas turbine (special vehicles)",
    n1={"idle": 0.55, "low": 0.70, "mid": 0.85, "high": 1.0},
    bp_hz=7600.0, bp2=(9800.0, 0.35), shaft_hz=520.0, gearbox_hz=1300.0,
)


# --------------------------------------------------------------------------- piston engine core
def _family_rng(family: str) -> np.random.Generator:
    return make_rng("engine-identity", family)


def _firing_offsets(spec: dict, frng: np.random.Generator) -> np.ndarray:
    cyl = spec["cyl"]
    base = np.arange(cyl) / cyl
    dev = spec["uneven"] * frng.standard_normal(cyl) / cyl
    dev[0] = 0.0
    return np.sort((base + dev) % 1.0)


def _events(f_cyc: np.ndarray, n: int, offsets: np.ndarray, sr: int = SR):
    ph = osc.phase(f_cyc, n, sr)
    k = int(np.floor(ph[-1])) + 2
    targets = (np.arange(k)[:, None] + offsets[None, :]).ravel()
    cyl = np.tile(np.arange(offsets.size), k)
    idx = np.searchsorted(ph, targets)
    keep = idx < n
    return idx[keep], cyl[keep]


def _norm(x: np.ndarray) -> np.ndarray:
    r = np.sqrt(np.mean(x * x))
    return x / max(r, 1e-12)


def render_piston(
    family: str,
    rng: np.random.Generator,
    n: int,
    rpm,
    load,
    loop: bool,
    misfire: float = 0.0,
    combustion=None,
    extra_knock: float = 0.0,
    layers: dict | None = None,
    sr: int = SR,
) -> np.ndarray:
    """Render a piston engine. ``rpm``/``load``/``combustion`` are scalars or per-sample curves.

    ``layers`` optionally scales individual layers (exhaust, knock, turbo, intake, rumble, gear, rattle).
    """
    spec = PISTON[family]
    lay = {"exhaust": 1.0, "knock": 1.0, "turbo": 1.0, "intake": 1.0, "rumble": 1.0, "gear": 1.0, "rattle": 1.0}
    if layers:
        lay.update(layers)
    frng = _family_rng(family)
    offsets = _firing_offsets(spec, frng)
    cyl_amp = 1.0 + spec["imbalance"] * frng.standard_normal(spec["cyl"])
    bank_shift = 1.0 + 0.07 * frng.random()

    rpm_c = as_signal(rpm, n)
    load_c = as_signal(load, n)
    f_cyc = rpm_c / 120.0
    idx, cyl = _events(f_cyc, n, offsets, sr)
    jit = n_of(spec["jitter_ms"] / 1000.0, sr)
    if jit > 0:
        idx = idx + rng.integers(-jit, jit + 1, idx.size)
        idx = np.mod(idx, n) if loop else np.clip(idx, 0, n - 1)
    amp = cyl_amp[cyl] * (1.0 + spec["rough"] * rng.standard_normal(idx.size))
    amp *= 0.45 + 0.55 * load_c[idx]
    if combustion is not None:
        amp *= as_signal(combustion, n)[idx]
    if misfire > 0:
        m = rng.random(idx.size) < misfire
        amp[m] *= rng.uniform(0.0, 0.25, int(m.sum()))
    amp = np.maximum(amp, 0.0)

    def conv(x, k):
        if loop:
            return kit.cconv(x, k)
        from scipy.signal import oaconvolve

        return oaconvolve(x, k)[:n]

    def filt(fn, x):
        return mix.circular(fn, x, 2) if loop else fn(x)

    out = np.zeros(n)
    banks = spec["banks"]
    kp = osc.pulse_shape(n_of(spec["pulse_tau"] * 12, sr), spec["pulse_tau"], sr, "nwave")
    kn_len = n_of(spec["noise_tau"] * 7, sr)
    kn = np.exp(-t_of(kn_len, sr) / spec["noise_tau"])
    env_total = np.zeros(n)
    for b in range(banks):
        sel = (cyl % banks) == b
        imp = np.zeros(n)
        np.add.at(imp, idx[sel], amp[sel])
        tonal = conv(imp, kp)
        e_train = conv(imp, kn)
        env_total += e_train
        noisy = e_train * noise.white(n, rng)
        exc = (1 - spec["noise_mix"]) * _norm(tonal) + spec["noise_mix"] * _norm(noisy)
        shift = 1.0 if b == 0 else bank_shift
        fr = [f * shift for f, _, _ in spec["formants"]]
        qs = [q for _, q, _ in spec["formants"]]
        gs = [g for _, _, g in spec["formants"]]
        body = filt(lambda z: filters.resonators(z, fr, qs, gs, sr), exc) + spec["direct"] * exc
        out += body
    out = _norm(out) * lay["exhaust"]

    # load-dependent brightness
    lp_lo, lp_hi = spec["lp"]
    if loop:
        cutoff = lp_lo + (lp_hi - lp_lo) * float(np.mean(load_c))
        out = filt(lambda z: filters.lowpass(z, cutoff, 2, sr=sr), out)
    else:
        out = filters.tv_onepole_lp(out, lp_lo + (lp_hi - lp_lo) * load_c, sr)
        out = filters.tv_onepole_lp(out, 1.4 * (lp_lo + (lp_hi - lp_lo) * load_c), sr)

    env_n = env_total / max(np.max(env_total), 1e-9)

    # diesel knock / injector clatter (follows each combustion, short and metallic)
    if spec["knock"] + extra_knock > 0:
        kimp = np.zeros(n)
        kd = n_of(0.0009, sr)
        kidx = np.mod(idx + kd, n) if loop else np.clip(idx + kd, 0, n - 1)
        np.add.at(kimp, kidx, amp * (0.6 + 0.8 * rng.random(idx.size)))
        kk = np.exp(-t_of(n_of(0.006, sr), sr) / 0.0012)
        k_env = conv(kimp, kk)
        lo, hi = spec["knock_band"]
        clat = filt(lambda z: filters.band(z, lo, hi, 2, sr), k_env * noise.white(n, rng))
        clat = filt(lambda z: filters.peaking(z, lo * 1.6, 6.0, 4.0, sr), clat)
        out += (spec["knock"] + extra_knock) * lay["knock"] * _norm(clat) * (0.6 + 0.4 * float(np.mean(load_c)))

    # turbo / supercharger whine
    if spec["turbo"] is not None and lay["turbo"] > 0:
        t_amp, t_lo, t_hi = spec["turbo"]
        r0, r1 = spec["rpm"]["idle"], spec["rpm"]["high"]
        frac = np.clip((rpm_c - r0) / (r1 - r0), -0.2, 1.3)
        f_t = t_lo + (t_hi - t_lo) * frac
        if loop:
            f0 = snap_freq(float(np.mean(f_t)), n, sr)
            f_t = f0 * (1.0 + 0.004 * noise.smooth_random(n, rng, 0.75, sr))
        wh = osc.sine(f_t, n, sr) + 0.25 * osc.sine(f_t * 2.0, n, sr)
        hiss = filt(lambda z: filters.bandpass(z, float(np.mean(f_t)) * 0.6, 1.2, sr), noise.white(n, rng))
        lvl = t_amp * (0.25 + 0.9 * load_c) * (0.4 + 0.6 * np.clip(frac + 0.2, 0, 1.2))
        out += lay["turbo"] * lvl * (wh + 0.5 * _norm(hiss) * 0.4)

    # intake rasp: band noise modulated by the firing envelope
    if spec["intake"] > 0:
        ib = filt(lambda z: filters.band(z, 700, 3200, 2, sr), noise.white(n, rng))
        out += spec["intake"] * lay["intake"] * _norm(ib) * (0.3 + 0.7 * env_n) * (0.3 + 0.9 * load_c)

    # crankcase rumble: low brown noise breathing with the firing
    if spec["rumble"] > 0:
        rb = filt(lambda z: filters.lowpass(z, 130, 2, sr=sr), noise.brown(n, rng, sr))
        sm = filt(lambda z: filters.smooth(z, 0.01, sr), env_n)
        out += spec["rumble"] * lay["rumble"] * _norm(rb) * (0.5 + 0.8 * sm / max(np.max(sm), 1e-9))

    # gear / accessory whine locked to crank speed
    g_amp, teeth = spec["gear"]
    if g_amp > 0:
        f_g = rpm_c / 60.0 * teeth
        if loop:
            f_g = np.full(n, snap_freq(float(np.mean(f_g)), n, sr))
        out += g_amp * lay["gear"] * (osc.sine(f_g, n, sr) + 0.3 * osc.sine(f_g * 2, n, sr)) * (0.5 + load_c)

    # loose panel rattle
    if spec["rattle"] > 0:
        d = noise.dust(n, 900.0, rng, sr)
        rat = filt(lambda z: filters.band(z, 600, 2600, 2, sr), d)
        rat = filt(lambda z: filters.resonators(z, [820, 1310, 2050], [12, 14, 10], [1, 0.7, 0.5], sr), rat) + 0.3 * rat
        out += spec["rattle"] * lay["rattle"] * _norm(rat) * (0.2 + env_n)

    out = fx.saturate(out / max(np.max(np.abs(out)), 1e-9), spec["drive"], "asym", 0.15)
    out = filt(lambda z: filters.highpass(z, 24, 2, sr=sr), out)
    return out


# --------------------------------------------------------------------------- turbine core
def render_turbine(rng: np.random.Generator, n: int, n1, fuel, loop: bool, stall: float = 0.0, extra_whine: float = 0.0,
                   sr: int = SR) -> np.ndarray:
    spec = TURBINE
    n1c = np.maximum(as_signal(n1, n), 0.0)
    fuelc = as_signal(fuel, n)

    def filt(fn, x):
        return mix.circular(fn, x, 2) if loop else fn(x)

    def snapped(f_curve):
        if not loop:
            return f_curve
        f0 = snap_freq(float(np.mean(f_curve)), n, sr)
        return f0 * (f_curve / max(float(np.mean(f_curve)), 1e-9))

    wob = noise.smooth_random(n, rng, 0.6, sr)
    f_bp = snapped(spec["bp_hz"] * n1c * (1 + 0.002 * wob))
    f_bp2 = snapped(spec["bp2"][0] * n1c * (1 + 0.002 * wob))
    f_sh = snapped(spec["shaft_hz"] * n1c * (1 + 0.002 * wob))
    f_gb = snapped(spec["gearbox_hz"] * n1c)
    whine = osc.sine(f_bp, n, sr) + 0.5 * osc.sine(snapped(f_bp * 1.0035), n, sr) + spec["bp2"][1] * osc.sine(f_bp2, n, sr)
    whine *= (0.2 + n1c) ** 1.5 * (1.0 + extra_whine)
    hum = osc.additive(f_sh, [1.0, 0.55, 0.3, 0.18, 0.1], n, sr, rng=rng) * (0.25 + n1c)
    gear = 0.3 * osc.sine(f_gb, n, sr) * n1c
    roar = filt(lambda z: filters.band(z, 120, 2600, 2, sr), noise.pink(n, rng, sr))
    roar = filt(lambda z: filters.peaking(z, 420, 5.0, 0.8, sr), roar)
    roar_lvl = (n1c**2.2) * (0.25 + 0.75 * fuelc)
    hiss = filt(lambda z: filters.highpass(z, 4500, 2, sr=sr), noise.white(n, rng)) * n1c**2
    rumble = filt(lambda z: filters.lowpass(z, 180, 2, sr=sr), noise.brown(n, rng, sr))
    rumble *= (0.15 + 0.85 * fuelc) * (0.2 + n1c) * (0.8 + 0.2 * noise.smooth_random(n, rng, 3.0, sr))
    out = 0.16 * whine + 0.22 * hum + 0.06 * gear + 0.9 * _norm(roar) * 0.35 * roar_lvl + 0.12 * _norm(hiss) * 0.3 + 0.5 * _norm(rumble) * 0.3
    if stall > 0:
        grind = filt(lambda z: filters.band(z, 900, 3200, 2, sr), noise.white(n, rng))
        grind *= 0.5 + 0.5 * np.abs(noise.smooth_random(n, rng, 25.0, sr))
        out += stall * 0.08 * _norm(grind)
    out = fx.saturate(out / max(np.max(np.abs(out)), 1e-9), 1.3, "tanh")
    return filt(lambda z: filters.highpass(z, 24, 2, sr=sr), out)


# --------------------------------------------------------------------------- piston variants
def _loop_n() -> int:
    return n_of(LOOP_S)


def _snapped_rpm(rpm: float, cyl: int, n: int) -> float:
    f_cyc = snap_freq(rpm / 120.0, n)
    return f_cyc * 120.0


def piston_layer(family: str, layer: str):
    def render(rng, variant):
        n = _loop_n()
        rpm = _snapped_rpm(PISTON[family]["rpm"][layer], PISTON[family]["cyl"], n)
        return render_piston(family, rng, n, rpm, LOAD[layer], loop=True)

    return render


def piston_damaged(family: str):
    def render(rng, variant):
        n = _loop_n()
        spec = PISTON[family]
        rpm0 = _snapped_rpm(0.5 * (spec["rpm"]["low"] + spec["rpm"]["mid"]) * 0.85, spec["cyl"], n)
        hunt = noise.smooth_random(n, rng, 0.9, SR)
        rpm = rpm0 * (1.0 + 0.07 * hunt)
        y = render_piston(family, rng, n, rpm, 0.55, loop=True, misfire=0.28, extra_knock=0.25,
                          layers={"rattle": 2.5, "turbo": 0.6})
        y = y / max(np.max(np.abs(y)), 1e-9)
        # metallic knocks and backfire pops, wrapped into the loop
        for _ in range(int(rng.integers(5, 8))):
            hit = kit.modal_hit(rng, 0.25, rng.uniform(1100, 2600), "bar", t60=0.12, modes=4, bright=0.6, click=0.6)
            mix.place_wrapped(y, hit / max(np.max(np.abs(hit)), 1e-9), int(rng.integers(0, n)), 0.35)
        for _ in range(2):
            pop = mix.mix(kit.noise_burst(rng, 0.12, 0.0005, 0.06, 80, 2500, "white"), (kit.boom(0.15, 140, 60, 0.02, 0.08), 0.8))
            mix.place_wrapped(y, pop / max(np.max(np.abs(pop)), 1e-9), int(rng.integers(0, n)), 0.8)
        return y

    return render


def piston_overload(family: str):
    def render(rng, variant):
        n = _loop_n()
        spec = PISTON[family]
        rpm = _snapped_rpm(spec["rpm"]["high"] * 1.04, spec["cyl"], n)
        base = render_piston(family, rng, n, rpm, 1.0, loop=True,
                             layers={"exhaust": 0.35, "knock": 0.6, "turbo": 3.0, "intake": 2.5, "rumble": 0.4, "gear": 6.0, "rattle": 0.3})
        # transmission strain whine (straight-cut gears), slight wavering
        f_tr = snap_freq(rpm / 60.0 * 0.55 * 27, n)
        wav = 1.0 + 0.003 * noise.smooth_random(n, rng, 1.2, SR)
        tr = osc.sine(f_tr * wav, n) + 0.35 * osc.sine(2 * f_tr * wav, n) + 0.12 * osc.sine(3 * f_tr * wav, n)
        tr *= 0.8 + 0.2 * noise.smooth_random(n, rng, 2.0, SR)
        y = base / max(np.max(np.abs(base)), 1e-9) + 0.22 * tr
        return mix.circular(lambda z: filters.highpass(z, 120, 2), y, 2)

    return render


def piston_start(family: str):
    def render(rng, variant):
        spec = PISTON[family]
        idle = spec["rpm"]["idle"]
        dur = 4.6
        n = n_of(dur)
        t_catch = 1.25
        rpm = env.breakpoints([(0, 120), (t_catch - 0.05, 170), (t_catch + 0.25, idle * 0.9), (t_catch + 0.65, idle * 1.55),
                               (t_catch + 1.5, idle * 1.08), (t_catch + 2.3, idle), (dur, idle)], n, kind="smooth")
        comb = env.breakpoints([(0, 0), (t_catch - 0.02, 0), (t_catch + 0.05, 0.6), (t_catch + 0.4, 1.0), (dur, 1.0)], n)
        load = env.breakpoints([(0, 0.2), (t_catch + 0.6, 0.85), (t_catch + 1.6, 0.25), (dur, LOAD["idle"])], n)
        eng = render_piston(family, rng, n, rpm, load, loop=False, combustion=comb, misfire=0.12)
        eng = eng / max(np.max(np.abs(eng)), 1e-9) * comb
        # electric starter: whine with compression-stroke loading ("rur-rur-rur")
        sn = n_of(t_catch + 0.35)
        st_f = env.breakpoints([(0, 90), (0.25, 210), (t_catch, 240), (t_catch + 0.35, 300)], sn, kind="smooth")
        comp_rate = (st_f / 240.0) * (spec["cyl"] / 2.0) * 1.1
        comp = 0.5 + 0.5 * np.sin(2 * np.pi * osc.phase(comp_rate, sn))
        starter = (osc.saw(st_f, sn) * 0.6 + osc.square(st_f * 2, sn) * 0.15)
        starter = filters.lowpass(starter, 1800, 2) * (0.45 + 0.55 * comp**2)
        grind = filters.band(noise.white(sn, rng), 1500, 5000, 2) * (0.3 + 0.7 * comp) * 0.15
        st = (starter + grind) * env.ar(sn, 0.03, 0.2)
        thump = filters.lowpass(noise.brown(sn, rng), 160, 2) * comp**3
        sol = kit.modal_hit(rng, 0.15, 2300, "bar", t60=0.05, modes=3, bright=0.8, click=1.0)
        y = np.zeros(n)
        mix.place(y, sol / np.max(np.abs(sol)), 0.0, 0.35)
        mix.place(y, st / max(np.max(np.abs(st)), 1e-9), 0.03, 0.42)
        mix.place(y, thump / max(np.max(np.abs(thump)), 1e-9), 0.03, 0.35)
        mix.place(y, eng, 0.0, 0.95)
        # catch "chuff"
        chuff = kit.noise_burst(rng, 0.4, 0.01, 0.25, 60, 900, "pink")
        mix.place(y, chuff / np.max(np.abs(chuff)), t_catch, 0.45)
        return env.fade(y, 0.0, 0.5)

    return render


def piston_stop(family: str):
    def render(rng, variant):
        spec = PISTON[family]
        idle = spec["rpm"]["idle"]
        dur = 3.4
        n = n_of(dur)
        t_cut = 0.35
        rpm = env.breakpoints([(0, idle), (t_cut, idle), (t_cut + 0.5, idle * 0.65), (t_cut + 1.3, idle * 0.25),
                               (t_cut + 1.7, 40), (dur, 30)], n, kind="smooth")
        comb = env.breakpoints([(0, 1.0), (t_cut, 1.0), (t_cut + 0.12, 0.15), (t_cut + 0.6, 0.05), (dur, 0.0)], n)
        eng = render_piston(family, rng, n, rpm, LOAD["idle"], loop=False, combustion=comb, misfire=0.2)
        # after the fuel cut the engine still pumps air: soft wheezing chuffs
        pump = render_piston(family, rng, n, rpm, 0.1, loop=False,
                             layers={"knock": 0.0, "turbo": 0.0, "gear": 0.0, "rattle": 0.0})
        pump = filters.lowpass(pump, 500, 2) * env.breakpoints([(0, 0), (t_cut, 0.0), (t_cut + 0.2, 1.0), (t_cut + 1.6, 0.4), (t_cut + 1.9, 0.0), (dur, 0.0)], n)
        y = eng / max(np.max(np.abs(eng)), 1e-9) * comb ** 0.5 + 0.35 * pump / max(np.max(np.abs(pump)), 1e-9)
        if spec["turbo"] is not None:
            f = env.breakpoints([(0, spec["turbo"][1]), (t_cut, spec["turbo"][1]), (dur, 500)], n, kind="exp")
            wh = osc.sine(f, n) * env.breakpoints([(0, 1), (t_cut, 1), (dur, 0)], n) ** 1.5
            y += 0.05 * wh
        settle = kit.modal_hit(rng, 0.8, 120, "hull", t60=0.35, modes=6, bright=0.3, click=0.2)
        mix.place(y, settle / np.max(np.abs(settle)), t_cut + 1.75, 0.5)
        tick = kit.modal_hit(rng, 0.2, 3100, "bar", t60=0.04, modes=2, bright=0.8, click=0.6)
        mix.place(y, tick / np.max(np.abs(tick)), t_cut + 2.4, 0.08)
        return env.fade(y, 0.0, 0.3)

    return render


# --------------------------------------------------------------------------- turbine variants
def turbine_layer(layer: str):
    def render(rng, variant):
        n = _loop_n()
        n1 = TURBINE["n1"][layer]
        return render_turbine(rng, n, n1, LOAD[layer] + 0.1, loop=True)

    return render


def turbine_start(rng, variant):
    dur = 6.5
    n = n_of(dur)
    t_light = 1.6
    idle = TURBINE["n1"]["idle"]
    n1 = env.breakpoints([(0, 0.0), (0.4, 0.03), (t_light, 0.14), (t_light + 0.8, 0.24), (t_light + 2.6, 0.48), (t_light + 3.8, idle), (dur, idle)], n, kind="smooth")
    fuel = env.breakpoints([(0, 0), (t_light - 0.01, 0), (t_light + 0.15, 1.0), (dur, 0.3)], n)
    y = render_turbine(rng, n, n1, fuel, loop=False)
    y /= max(np.max(np.abs(y)), 1e-9)
    sn = n_of(t_light + 1.0)
    st_f = env.breakpoints([(0, 120), (t_light, 900), (t_light + 1.0, 1100)], sn, kind="smooth")
    starter = filters.lowpass(osc.saw(st_f, sn), 3000, 2) * env.ar(sn, 0.2, 0.8)
    mix.place(y, starter, 0.0, 0.18)
    light = mix.mix(kit.noise_burst(rng, 0.9, 0.04, 0.6, 50, 700, "brown"), (kit.boom(0.6, 110, 45, 0.08, 0.4, 0.02), 0.6))
    mix.place(y, light / np.max(np.abs(light)), t_light, 0.6)
    click = kit.modal_hit(rng, 0.1, 2800, "bar", t60=0.04, modes=2, click=1.0)
    mix.place(y, click / np.max(np.abs(click)), 0.0, 0.2)
    return env.fade(y, 0.0, 0.5)


def turbine_stop(rng, variant):
    dur = 6.5
    n = n_of(dur)
    idle = TURBINE["n1"]["idle"]
    n1 = idle * np.exp(-np.maximum(t_of(n) - 0.3, 0) / 1.9)
    fuel = env.breakpoints([(0, 0.3), (0.3, 0.3), (0.45, 0.0), (dur, 0.0)], n)
    y = render_turbine(rng, n, n1, fuel, loop=False)
    y /= max(np.max(np.abs(y)), 1e-9)
    y *= env.breakpoints([(0, 1.0), (0.3, 1.0), (0.6, 0.7), (dur, 0.25)], n)
    for k in range(3):
        tick = kit.modal_hit(rng, 0.15, rng.uniform(2500, 3800), "bar", t60=0.03, modes=2, click=0.8)
        mix.place(y, tick / np.max(np.abs(tick)), 4.6 + 0.55 * k, 0.05)
    return env.fade(y, 0.0, 0.4)


def turbine_damaged(rng, variant):
    n = _loop_n()
    n1_0 = 0.72
    surge = noise.smooth_random(n, rng, 0.8, SR)
    n1 = n1_0 * (1 + 0.09 * surge)
    y = render_turbine(rng, n, n1, 0.7, loop=True, stall=1.0)
    y /= max(np.max(np.abs(y)), 1e-9)
    for _ in range(3):
        bang = mix.mix(kit.noise_burst(rng, 0.25, 0.0005, 0.12, 60, 3000, "white"), kit.boom(0.3, 160, 55, 0.03, 0.2))
        mix.place_wrapped(y, bang / np.max(np.abs(bang)), int(rng.integers(0, n)), 0.7)
    return y


def turbine_overload(rng, variant):
    n = _loop_n()
    y = render_turbine(rng, n, 1.05, 1.0, loop=True, extra_whine=1.5)
    return mix.circular(lambda z: filters.highpass(z, 300, 2), y, 2)


# --------------------------------------------------------------------------- transmission
def reverse_whine(rng, variant):
    n = n_of(3.0)
    f = snap_freq(780.0, n)
    am = snap_freq(26.0, n)
    wob = 1 + 0.002 * noise.smooth_random(n, rng, 0.7, SR)
    tone = osc.sine(f * wob, n) + 0.4 * osc.sine(2 * f * wob, n) + 0.15 * osc.sine(3 * f * wob, n)
    tone *= 1.0 + 0.3 * np.sin(2 * np.pi * am * t_of(n))
    whirr = mix.circular(lambda z: filters.band(z, 900, 3200, 2), noise.white(n, rng))
    rumble = mix.circular(lambda z: filters.lowpass(z, 200, 2), noise.brown(n, rng))
    return 0.5 * tone + 0.08 * _norm(whirr) + 0.15 * _norm(rumble)


def gear_shift(rng, variant):
    n = n_of(0.9)
    y = np.zeros(n)
    clunk = kit.modal_hit(rng, 0.7, rng.uniform(140, 180), "hull", t60=0.25, modes=7, bright=0.35, click=0.6, click_hz=2500)
    mix.place(y, clunk / np.max(np.abs(clunk)), 0.06, 0.9)
    engage = kit.modal_hit(rng, 0.2, rng.uniform(1800, 2400), "bar", t60=0.06, modes=3, bright=0.7, click=0.8)
    mix.place(y, engage / np.max(np.abs(engage)), 0.0, 0.3)
    air = kit.whoosh(rng, 0.35, 600, 2200, 1.2, 0.3)
    mix.place(y, air / np.max(np.abs(air)), 0.1, 0.15)
    return y


# --------------------------------------------------------------------------- registration
def _register() -> None:
    families = list(PISTON) + ["turbine"]
    for fam in families:
        is_turb = fam == "turbine"
        label = TURBINE["label"] if is_turb else PISTON[fam]["label"]
        for i, layer in enumerate(LAYERS):
            if is_turb:
                n1 = TURBINE["n1"]
                meta = {"family": fam, "layer": layer, "n1": n1[layer], "n1Range": [n1[LAYERS[max(i - 1, 0)]], n1[LAYERS[min(i + 1, 3)]]]}
                render = turbine_layer(layer)
            else:
                rpm = PISTON[fam]["rpm"]
                native = round(_snapped_rpm(rpm[layer], PISTON[fam]["cyl"], _loop_n()), 2)
                lo = rpm[LAYERS[i - 1]] if i > 0 else int(rpm["idle"] * 0.85)
                hi = rpm[LAYERS[i + 1]] if i < 3 else int(rpm["high"] * 1.1)
                meta = {"family": fam, "layer": layer, "rpm": native, "rpmRange": [lo, hi], "cylinders": PISTON[fam]["cyl"],
                        "playbackSpeed": "rpm / rpm_native"}
                render = piston_layer(fam, layer)
            sound(f"engine_{fam}_{layer}", "engines", render,
                  f"{label}: steady {layer} RPM layer for RPM crossfading.",
                  f"Own/other vehicle engine at {layer} RPM (crossfaded by RPM; PlaybackSpeed tracks RPM).",
                  loop=True, loop_s=LOOP_S, level=LAYER_LUFS[layer], group=f"engine_{fam}", meta=meta,
                  priority=62 if layer != "idle" else 58)
        if is_turb:
            start, stop, dmg, ovl = turbine_start, turbine_stop, turbine_damaged, turbine_overload
        else:
            start, stop, dmg, ovl = piston_start(fam), piston_stop(fam), piston_damaged(fam), piston_overload(fam)
        sound(f"engine_{fam}_start", "engines", start, f"{label}: start-up (starter, catch, flare, settle to idle).",
              "Engine start (garage preview, battle start, after repair). Crossfade into idle loop at the last 0.6 s.",
              level=-17.0, group=f"engine_{fam}", meta={"family": fam, "crossfadeToIdleAtS": "duration - 0.6"}, priority=65)
        sound(f"engine_{fam}_stop", "engines", stop, f"{label}: shut-down (fuel cut, run-down, settle clunk).",
              "Engine shut-down (destroyed, battle end, garage exit).", level=-18.0, group=f"engine_{fam}",
              meta={"family": fam}, priority=60)
        sound(f"engine_{fam}_damaged", "engines", dmg, f"{label}: damaged engine loop (misfires, knocking, hunting RPM, backfires).",
              "Replaces the RPM layers while the engine module is damaged.", loop=True, loop_s=LOOP_S, level=-18.5,
              group=f"engine_{fam}", meta={"family": fam}, priority=66)
        sound(f"engine_{fam}_overload", "engines", ovl, f"{label}: overload strain layer (transmission/turbo whine, intake roar).",
              "Layered on top when climbing / pushing at max power with low speed (load > 0.85).", loop=True, loop_s=LOOP_S,
              level=-23.0, group=f"engine_{fam}", meta={"family": fam, "layer": "overload"}, priority=50)
    sound("transmission_reverse_whine", "engines", reverse_whine, "Straight-cut reverse gear whine loop.",
          "Layered while driving in reverse (PlaybackSpeed tracks speed).", loop=True, loop_s=3.0, level=-26.0, priority=45)
    sound("transmission_gear_shift", "engines", gear_shift, "Gear change clunk with clutch air.",
          "Automatic gear change event.", variants="ab", level=-22.0, priority=40)


_register()
