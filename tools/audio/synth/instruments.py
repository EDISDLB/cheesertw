"""Musical instruments for the HULLDOWN score - every voice is synthesised, no samples.

Conventions (shared with the rest of :mod:`synth`):

* Pitched voices: ``fn(rng, f0, dur, vel=0.8, sr=SR, **params) -> np.ndarray`` where ``f0`` is
  in Hz, ``dur`` is the *gate* length in seconds (key held / bow moving) and ``vel`` is 0..1.
  The returned buffer includes the release tail, so it is usually longer than ``dur``.
* Unpitched voices: ``fn(rng, vel=0.8, sr=SR, **params)``; most accept ``f0``/``size`` tuning.
* Ensembles (string sections, brass sections, choir) return stereo ``(n, 2)`` with their players
  spread across the section's seat; solo voices return mono and are panned by the score.
* Loudness of every instrument is roughly calibrated so ``vel=1`` gives a similar perceived level
  (sustained voices ~ -16 dBFS RMS, percussion ~ -3 dBFS peak); the score balances parts with
  per-part gains on top of that.

Synthesis methods (all band-limited):

======================= ==================================================================
strings                 detuned PolyBLEP-saw ensemble (bowed Helmholtz motion), per-player
                        vibrato, body resonances; legato / spiccato / tremolo / flautando
brass                   additive harmonic stack whose brightness tracks the envelope
                        (``a_k ~ e(t)^(1+beta(k-1))``), pitch scoop, section of players
choir                   saw ensemble -> glottal tilt -> 5-formant resonator bank per vowel
organ, flute, reed      additive pipes with chiff; breathy flute; duduk/accordion reeds
pluck, piano            modal strings with inharmonicity, pluck-position comb, two-stage decay
bell                    modal tables (tubular, glockenspiel, celesta, church, glass)
timpani, taiko, drums   membrane modes with tension pitch glide, mallet noise, snares
cymbal                  inharmonic partial cloud + filtered noise wash, mallet swells
fx                      Shepard-Risset riser grains, sub bass, clock ticks, anvils
======================= ==================================================================
"""

from __future__ import annotations

import numpy as np

from . import filters, fx, mix, noise, osc
from .core import LN1000, SR, TWO_PI, n_of, t_of

# --------------------------------------------------------------------------- helpers


def vel_amp(vel: float, curve: float = 1.5) -> float:
    """Velocity (0..1) to linear amplitude (perceptual curve)."""
    return float(np.clip(vel, 0.0, 1.25)) ** curve


def hz_curve(
    f0: float,
    n: int,
    sr: int = SR,
    detune_cents: float = 0.0,
    scoop_cents: float = 0.0,
    scoop_tau: float = 0.04,
    vib_rate: float = 5.0,
    vib_cents: float = 0.0,
    vib_delay: float = 0.3,
    vib_rise: float = 0.4,
    vib_phase: float = 0.0,
    glide_to: float | None = None,
    glide_s: float = 0.0,
) -> np.ndarray:
    """Per-sample frequency: detune, onset scoop (decaying), delayed vibrato, optional glide."""
    t = t_of(n, sr)
    cents = np.full(n, float(detune_cents))
    if scoop_cents:
        cents += scoop_cents * np.exp(-t / max(scoop_tau, 1e-4))
    if vib_cents:
        depth = vib_cents * np.clip((t - vib_delay) / max(vib_rise, 1e-3), 0.0, 1.0)
        cents += depth * np.sin(TWO_PI * vib_rate * t + vib_phase)
    f = f0 * np.power(2.0, cents / 1200.0)
    if glide_to is not None and glide_s > 0:
        g = np.clip(t / glide_s, 0.0, 1.0)
        g = 0.5 - 0.5 * np.cos(np.pi * g)
        f = f * np.power(glide_to / f0, g)
    return f


def sustain_env(n_gate: int, attack: float, release: float, sr: int = SR, overshoot: float = 0.0,
                overshoot_tau: float = 0.12, swell: float = 0.0, decay_db_s: float = 0.0) -> np.ndarray:
    """Envelope for held notes: exponential-ish attack, optional overshoot, slow swell/decay
    while held, then an exponential release (``release`` = T60) after ``n_gate`` samples.
    Length is ``n_gate + T60`` so the tail reaches -60 dB."""
    n_rel = n_of(release, sr)
    n = int(n_gate) + n_rel
    t = t_of(n, sr)
    a = 1.0 - np.exp(-t * 5.0 / max(attack, 1e-4))
    held = np.ones(n)
    if overshoot:
        held += overshoot * np.exp(-np.maximum(t - attack, 0.0) / overshoot_tau) * np.clip(t / max(attack, 1e-4), 0, 1)
    if swell:
        g = np.clip(t / max(n_gate / sr, 1e-3), 0.0, 1.0)
        held *= (1.0 - swell) + swell * g**1.5
    if decay_db_s:
        held *= 10 ** (-decay_db_s * np.minimum(t, n_gate / sr) / 20.0)
    e = a * held
    if n_rel:
        tr = t[n_gate:] - t[n_gate] if n_gate < n else np.zeros(0)
        e[n_gate:] *= np.exp(-LN1000 * tr / max(release, 1e-4))
        k = min(n, n_of(0.004, sr))
        e[n - k :] *= np.linspace(1.0, 0.0, k)
    return e


def harmonic_stack(ph: np.ndarray, amps, k_max: int | None = None, phases=None) -> np.ndarray:
    """Sum ``amps[k-1] * sin(2*pi*k*ph + phases[k-1])`` for k = 1..K using the Chebyshev
    recurrences ``s_k = 2 cos(theta) s_{k-1} - s_{k-2}`` (and the same for ``c_k``), i.e. one or
    two multiply-adds per partial and sample instead of a ``sin`` call.

    ``amps`` is a list of scalars or per-sample arrays, or a callable ``amps(k)`` (called in
    order k = 1..K). Random ``phases`` lower the crest factor and stop detuned copies from beating
    as one block (each partial then beats at its own rate, as in a real section)."""
    th = TWO_PI * ph
    s1 = np.sin(th)
    c1 = np.cos(th)
    c2 = 2.0 * c1
    count = k_max if k_max is not None else len(amps)
    get = amps if callable(amps) else (lambda k: amps[k - 1])
    if phases is None:
        out = get(1) * s1
        s_prev = np.zeros_like(s1)
        s_cur = s1
        for k in range(2, count + 1):
            s_next = c2 * s_cur - s_prev
            a = get(k)
            if not (np.isscalar(a) and a == 0.0):
                out = out + a * s_next
            s_prev, s_cur = s_cur, s_next
        return out
    cp, sp = np.cos(phases), np.sin(phases)
    out = get(1) * (s1 * cp[0] + c1 * sp[0])
    s_prev, s_cur = np.zeros_like(s1), s1
    c_prev, c_cur = np.ones_like(c1), c1
    for k in range(2, count + 1):
        s_next = c2 * s_cur - s_prev
        c_next = c2 * c_cur - c_prev
        a = get(k)
        if not (np.isscalar(a) and a == 0.0):
            out = out + a * (s_next * cp[k - 1] + c_next * sp[k - 1])
        s_prev, s_cur = s_cur, s_next
        c_prev, c_cur = c_cur, c_next
    return out


def spread_positions(count: int, lo: float, hi: float, rng: np.random.Generator) -> np.ndarray:
    if count == 1:
        return np.array([(lo + hi) / 2])
    pos = np.linspace(lo, hi, count)
    return np.clip(pos + rng.uniform(-0.05, 0.05, count), -1, 1)


def _eq(x: np.ndarray, bands, sr: int = SR) -> np.ndarray:
    for f, q, g in bands:
        x = filters.peaking(x, f, g, q, sr)
    return x


def _ramp_in(x: np.ndarray, seconds: float = 0.0015, sr: int = SR) -> np.ndarray:
    k = min(x.shape[0], max(1, n_of(seconds, sr)))
    w = np.linspace(0.0, 1.0, k)
    x[:k] *= w if x.ndim == 1 else w[:, None]
    return x


def _fade_end(x: np.ndarray, seconds: float = 0.01, sr: int = SR) -> np.ndarray:
    k = min(x.shape[0], max(1, n_of(seconds, sr)))
    w = np.linspace(1.0, 0.0, k)
    x[-k:] *= w if x.ndim == 1 else w[:, None]
    return x


# --------------------------------------------------------------------------- strings

STRING_SECTIONS = {
    #            players  seat (pan lo, hi)   lp Hz  hp Hz  body resonances (Hz, Q, dB)
    "violins": dict(players=6, seat=(-0.8, -0.2), lp=7000.0, hp=170.0,
                    body=[(290, 1.3, 3.0), (480, 1.6, 1.5), (1500, 1.2, -2.0), (2700, 1.1, 3.5)]),
    "violas": dict(players=4, seat=(-0.35, 0.15), lp=5200.0, hp=110.0,
                   body=[(230, 1.3, 2.5), (430, 1.5, 1.5), (1300, 1.2, -1.5), (2200, 1.1, 2.5)]),
    "celli": dict(players=4, seat=(0.1, 0.55), lp=4200.0, hp=50.0,
                  body=[(110, 1.1, 2.0), (230, 1.3, 2.5), (620, 1.4, 1.0), (1700, 1.0, 2.0)]),
    "basses": dict(players=3, seat=(0.4, 0.8), lp=2200.0, hp=28.0,
                   body=[(70, 1.0, 2.5), (150, 1.3, 2.0), (420, 1.4, 0.5)]),
}


def strings(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.8, sr: int = SR,
            section: str = "violins", art: str = "legato", players: int | None = None,
            attack: float | None = None, release: float | None = None, tremolo_hz: float = 14.0,
            bright: float = 1.0) -> np.ndarray:
    """Bowed string section (stereo).

    ``art``: ``legato`` (sustained), ``spiccato`` (short bounced bow), ``marcato`` (accented
    long), ``tremolo`` (fast bowed repeats), ``flautando`` (airy, near-sinusoidal) or
    ``swell`` (crescendo over the gate)."""
    p = STRING_SECTIONS[section]
    short = art == "spiccato"
    count = players or (3 if short else p["players"])
    amp = vel_amp(vel)
    if short:
        atk, rel = 0.004, release or 0.09
    elif art == "marcato":
        atk, rel = 0.03, release or 0.3
    else:
        atk = attack if attack is not None else float(np.interp(vel, [0.2, 1.0], [0.45, 0.12]))
        rel = release or 0.55
    n_gate = n_of(dur, sr)
    seat = spread_positions(count, *p["seat"], rng)
    out = None
    for i in range(count):
        e = sustain_env(n_gate, atk, rel, sr, overshoot=0.35 if art == "marcato" else 0.0, overshoot_tau=0.15,
                        swell=0.75 if art == "swell" else 0.0)
        n = e.shape[0]
        if out is None:
            out = np.zeros((n, 2))
        f = hz_curve(f0, n, sr, detune_cents=rng.normal(0.0, 5.0), scoop_cents=0.0 if short else rng.uniform(-12, -4),
                     scoop_tau=0.06, vib_rate=rng.uniform(4.6, 6.0), vib_cents=0.0 if short else rng.uniform(6.0, 13.0),
                     vib_delay=rng.uniform(0.15, 0.35), vib_rise=0.5, vib_phase=rng.uniform(0, TWO_PI))
        if art == "flautando":
            y = osc.additive(f, [1.0, 0.18, 0.06, 0.02], n, sr, rng=rng)
        else:
            y = osc.saw(f, n, sr, phase0=rng.random())
        if short:
            ee = np.exp(-LN1000 * t_of(n, sr) / rng.uniform(0.22, 0.32))
            e = e * ee
        if art == "tremolo":
            r = tremolo_hz * rng.uniform(0.9, 1.1)
            e = e * (0.55 + 0.45 * np.abs(np.sin(np.pi * r * t_of(n, sr) + rng.uniform(0, np.pi))) ** 0.7)
        y = y * e
        out += mix.pan(y, seat[i]) / np.sqrt(2.0)
    # bow noise (rosin hiss) and bite on short notes
    n = out.shape[0]
    bow = noise.band(n, rng, 1800.0, 7000.0, sr) * sustain_env(n_gate, atk, rel, sr)[:n] * 0.035
    if short or art == "marcato":
        k = min(n, n_of(0.018, sr))
        bite = filters.bandpass(rng.standard_normal(k), 2200.0, 0.8, sr) * np.exp(-np.linspace(0, 5, k)) * 0.35
        bow[:k] += bite
    out += mix.pan(bow, float(np.mean(seat)))[:n] / np.sqrt(2.0) * np.sqrt(count)
    lp = p["lp"] * bright * (0.55 + 0.45 * vel) if art != "flautando" else min(p["lp"], 6.0 * f0)
    out = filters.lowpass(out, lp, 4, sr=sr)
    out = filters.highpass(out, p["hp"], 2, sr=sr)
    out = _eq(out, p["body"], sr)
    return out * amp * (0.42 / np.sqrt(count))


# --------------------------------------------------------------------------- brass

BRASS = {
    # formant peak, rolloff corner, slope above corner (dB/oct), brightening beta, scoop cents,
    # vibrato cents, players, seat, attack (s at vel 1), release T60, breath noise
    "horn": dict(peak=440.0, corner=1050.0, slope=-20.0, beta=0.20, scoop=-40.0, vib=3.0, players=4,
                 seat=(-0.45, -0.05), attack=0.05, release=0.35, breath=0.012),
    "trumpet": dict(peak=1250.0, corner=2800.0, slope=-15.0, beta=0.12, scoop=-28.0, vib=7.0, players=3,
                    seat=(0.05, 0.4), attack=0.025, release=0.2, breath=0.012),
    "trombone": dict(peak=560.0, corner=1500.0, slope=-16.0, beta=0.16, scoop=-30.0, vib=3.0, players=3,
                     seat=(0.3, 0.65), attack=0.035, release=0.3, breath=0.01),
    "tuba": dict(peak=240.0, corner=620.0, slope=-17.0, beta=0.22, scoop=-25.0, vib=2.0, players=2,
                 seat=(0.45, 0.7), attack=0.05, release=0.35, breath=0.008),
    "alphorn": dict(peak=380.0, corner=900.0, slope=-22.0, beta=0.24, scoop=-55.0, vib=2.0, players=1,
                    seat=(0.0, 0.0), attack=0.09, release=0.6, breath=0.02),
}


def _brass_spectrum(freqs: np.ndarray, peak: float, corner: float, slope: float) -> np.ndarray:
    lf = np.log2(np.maximum(freqs, 1.0))
    db = np.where(freqs < peak, -7.0 * (np.log2(peak) - lf), -2.5 * (lf - np.log2(peak)))
    db = np.where(freqs > corner, db + slope * (lf - np.log2(corner)), db)
    return 10 ** (db / 20.0)


def brass(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.8, sr: int = SR,
          kind: str = "horn", art: str = "sustain", players: int | None = None, mute: bool = False) -> np.ndarray:
    """Brass section (stereo). ``art``: ``sustain``, ``stab`` (accented, fading), ``staccato``,
    ``swell`` (crescendo through the gate), ``fall`` (pitch falls off at the end)."""
    p = BRASS[kind]
    count = players or (p["players"] if art != "staccato" else max(1, p["players"] - 1))
    amp = vel_amp(vel, 1.3)
    atk = p["attack"] * (1.6 - 0.6 * vel)
    rel = p["release"] if art != "staccato" else 0.12
    over, dec, sw = 0.0, 0.0, 0.0
    if art == "stab":
        atk, over, dec = atk * 0.6, 0.45, 9.0
    elif art == "staccato":
        atk, over = atk * 0.7, 0.25
    elif art == "swell":
        atk, sw = max(atk, 0.25), 0.8
    else:
        over = 0.12 * vel
    n_gate = n_of(dur, sr)
    seat = spread_positions(count, *p["seat"], rng)
    out = None
    for i in range(count):
        e = sustain_env(n_gate, atk, rel, sr, overshoot=over, overshoot_tau=0.1, swell=sw, decay_db_s=dec)
        n = e.shape[0]
        if out is None:
            out = np.zeros((n, 2))
        off = n_of(rng.uniform(0.0, 0.012), sr)
        e = np.concatenate([np.zeros(off), e[: n - off]])
        f = hz_curve(f0, n, sr, detune_cents=rng.normal(0.0, 3.0), scoop_cents=p["scoop"] * rng.uniform(0.6, 1.2),
                     scoop_tau=0.035, vib_rate=rng.uniform(4.8, 5.8), vib_cents=p["vib"], vib_delay=0.45, vib_rise=0.6,
                     vib_phase=rng.uniform(0, TWO_PI))
        if art == "fall":
            t = t_of(n, sr)
            fall = np.clip((t - 0.75 * n_gate / sr) / max(0.25 * n_gate / sr + rel, 1e-3), 0, 1)
            f = f * np.power(2.0, -5.0 * fall**2 / 12.0)
        ph = osc.phase(f, n, sr, rng.random())
        k_max = int(min(48, np.floor(0.44 * sr / (f0 * 1.03))))
        ks = np.arange(1, k_max + 1)
        spec = _brass_spectrum(ks * f0, p["peak"], p["corner"], p["slope"])
        if mute:
            spec = spec * _brass_spectrum(ks * f0, 1700.0, 2600.0, -18.0) * 2.0
        ee = np.clip(e * amp, 0.0, 1.5)
        # brightness follows the envelope but saturates at full level (no runaway upper partials)
        r = np.power(np.clip(ee, 1e-9, 1.0), p["beta"])
        state = {"a": ee}

        def amps(k, spec=spec, r=r, state=state):
            if k > 1:
                state["a"] = state["a"] * r
            return spec[k - 1] * state["a"]

        y = harmonic_stack(ph, amps, k_max, phases=rng.uniform(0, TWO_PI, k_max))
        out += mix.pan(y, seat[i]) / np.sqrt(2.0)
    n = out.shape[0]
    br = noise.band(n, rng, p["peak"] * 0.8, p["corner"] * 2.5, sr) * sustain_env(n_gate, atk, rel, sr)[:n] * p["breath"] * amp
    out += mix.pan(br, float(np.mean(seat)))[:n] / np.sqrt(2.0)
    out = filters.highpass(out, max(25.0, f0 * 0.5), 2, sr=sr)
    return out * (0.36 / np.sqrt(count))


# --------------------------------------------------------------------------- choir

# Formant tables (Hz, dB, bandwidth Hz) per register and vowel (classic singing-voice data).
FORMANTS = {
    ("bass", "ah"): [(600, 0, 60), (1040, -7, 70), (2250, -9, 110), (2450, -9, 120), (2750, -20, 130)],
    ("bass", "oh"): [(400, 0, 40), (750, -11, 80), (2400, -21, 100), (2600, -20, 120), (2900, -40, 120)],
    ("bass", "oo"): [(350, 0, 40), (600, -20, 80), (2400, -32, 100), (2675, -28, 120), (2950, -36, 120)],
    ("bass", "eh"): [(400, 0, 40), (1620, -12, 80), (2400, -9, 100), (2800, -12, 120), (3100, -18, 120)],
    ("tenor", "ah"): [(650, 0, 80), (1080, -6, 90), (2650, -7, 120), (2900, -8, 130), (3250, -22, 140)],
    ("tenor", "oh"): [(400, 0, 40), (800, -10, 80), (2600, -12, 100), (2800, -12, 120), (3000, -26, 120)],
    ("tenor", "oo"): [(350, 0, 40), (600, -20, 60), (2700, -17, 100), (2900, -14, 120), (3300, -26, 120)],
    ("tenor", "eh"): [(400, 0, 70), (1700, -14, 80), (2600, -12, 100), (3200, -14, 120), (3580, -20, 120)],
    ("alto", "ah"): [(800, 0, 80), (1150, -4, 90), (2800, -20, 120), (3500, -36, 130), (4950, -60, 140)],
    ("alto", "oh"): [(450, 0, 70), (800, -9, 80), (2830, -16, 100), (3500, -28, 130), (4950, -55, 135)],
    ("alto", "oo"): [(325, 0, 50), (700, -12, 60), (2530, -30, 170), (3500, -40, 180), (4950, -64, 200)],
    ("alto", "eh"): [(400, 0, 60), (1600, -24, 80), (2700, -30, 120), (3300, -35, 150), (4950, -60, 200)],
    ("soprano", "ah"): [(800, 0, 80), (1150, -6, 90), (2900, -32, 120), (3900, -20, 130), (4950, -50, 140)],
    ("soprano", "oh"): [(450, 0, 70), (800, -11, 80), (2830, -22, 100), (3800, -22, 130), (4950, -50, 135)],
    ("soprano", "oo"): [(325, 0, 50), (700, -16, 60), (2700, -35, 170), (3800, -40, 180), (4950, -60, 200)],
    ("soprano", "eh"): [(350, 0, 60), (2000, -20, 100), (2800, -15, 120), (3600, -40, 150), (4950, -56, 200)],
}


def register_of(f0: float) -> str:
    if f0 < 170.0:
        return "bass"
    if f0 < 270.0:
        return "tenor"
    if f0 < 420.0:
        return "alto"
    return "soprano"


def choir(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.7, sr: int = SR,
          vowel: str = "ah", register: str | None = None, singers: int = 6, attack: float | None = None,
          release: float = 0.7, breath: float = 0.05, width: float = 0.8) -> np.ndarray:
    """Choir section (stereo): detuned glottal-ish sources through a 5-formant vowel filter."""
    reg = register or register_of(f0)
    table = FORMANTS[(reg, vowel)]
    atk = attack if attack is not None else float(np.interp(vel, [0.2, 1.0], [0.6, 0.2]))
    n_gate = n_of(dur, sr)
    amp = vel_amp(vel, 1.2)
    seat = spread_positions(singers, -width, width, rng)
    out = None
    for i in range(singers):
        e = sustain_env(n_gate, atk * rng.uniform(0.85, 1.15), release, sr)
        n = e.shape[0]
        if out is None:
            out = np.zeros((n, 2))
        f = hz_curve(f0, n, sr, detune_cents=rng.normal(0.0, 7.0), scoop_cents=rng.uniform(-25, -8), scoop_tau=0.08,
                     vib_rate=rng.uniform(4.8, 5.9), vib_cents=rng.uniform(12.0, 26.0), vib_delay=rng.uniform(0.2, 0.5),
                     vib_rise=0.6, vib_phase=rng.uniform(0, TWO_PI))
        # slow random pitch drift (no two singers lock)
        drift = noise.smooth_random(n, rng, 1.5, sr) * rng.uniform(3.0, 6.0)
        f = f * np.power(2.0, drift / 1200.0)
        y = osc.saw(f, n, sr, phase0=rng.random()) * e
        out += mix.pan(y, seat[i]) / np.sqrt(2.0)
    n = out.shape[0]
    out = filters.onepole_lp(out, max(180.0, 1.6 * f0), sr) * 3.0  # extra -6 dB/oct: glottal tilt
    env0 = sustain_env(n_gate, atk, release, sr)[:n]
    air = noise.white(n, rng) * env0 * breath
    out += mix.pan(air, 0.0)[:n] / np.sqrt(2.0)
    freqs = [fq for fq, _, _ in table]
    qs = [fq / bw for fq, _, bw in table]
    gains = [10 ** (db / 20.0) for _, db, _ in table]
    y = filters.resonators(out, freqs, qs, gains, sr)
    y = filters.highpass(y, max(60.0, 0.6 * f0), 2, sr=sr)
    return y * amp * (2.2 / np.sqrt(singers))


# --------------------------------------------------------------------------- organ / winds

def organ(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.7, sr: int = SR,
          stops=(("16", 0.35), ("8", 1.0), ("4", 0.55), ("2.67", 0.25), ("2", 0.3)), chiff: float = 0.25,
          attack: float = 0.05, release: float = 0.25) -> np.ndarray:
    """Pipe organ (stereo): additive ranks with small detune, attack chiff and wind noise."""
    feet = {"16": 0.5, "8": 1.0, "4": 2.0, "2.67": 3.0, "2": 4.0, "1.6": 5.0, "1": 8.0}
    n_gate = n_of(dur, sr)
    e = sustain_env(n_gate, attack, release, sr)
    n = e.shape[0]
    out = np.zeros((n, 2))
    for j, (stop, g) in enumerate(stops):
        ratio = feet[stop]
        f = f0 * ratio * 2 ** (rng.normal(0, 1.5) / 1200.0)
        if f > 0.42 * sr:
            continue
        k_max = int(min(8, 0.42 * sr // f))
        tone = osc.additive(f, [1.0, 0.45, 0.22, 0.12, 0.07, 0.04, 0.02, 0.01][:k_max], n, sr, rng=rng)
        out += mix.pan(tone * g, (-0.4 + 0.8 * j / max(1, len(stops) - 1)) * 0.6) / np.sqrt(2.0)
    out *= e[:, None]
    k = min(n, n_of(0.06, sr))
    ch = filters.bandpass(rng.standard_normal(k), min(0.45 * sr, 3.0 * f0), 2.0, sr) * np.exp(-np.linspace(0, 4, k)) * chiff
    out[:k] += ch[:, None]
    wind = filters.lowpass(noise.white(n, rng), 2500.0, 2, sr=sr) * e * 0.01
    out += wind[:, None]
    return out * vel_amp(vel, 1.0) * 0.18


def flute(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.7, sr: int = SR, breath: float = 0.12,
          vib_cents: float = 9.0, kind: str = "flute") -> np.ndarray:
    """Breathy flute / whistle / shakuhachi-like end-blown pipe (mono)."""
    shaku = kind == "shakuhachi"
    n_gate = n_of(dur, sr)
    atk = 0.07 if not shaku else 0.12
    e = sustain_env(n_gate, atk, 0.18, sr, overshoot=0.1)
    n = e.shape[0]
    f = hz_curve(f0, n, sr, scoop_cents=-30.0 if shaku else -10.0, scoop_tau=0.08 if shaku else 0.03,
                 vib_rate=rng.uniform(4.8, 5.4), vib_cents=vib_cents, vib_delay=0.25, vib_rise=0.5,
                 vib_phase=rng.uniform(0, TWO_PI))
    amps = [1.0, 0.16, 0.08, 0.03] if not shaku else [1.0, 0.3, 0.1, 0.05]
    tone = osc.additive(f, amps, n, sr, rng=rng)
    air = noise.white(n, rng)
    air_tone = filters.bandpass(air, f0, 6.0, sr) * 1.2 + filters.highpass(air, 2500.0, 2, sr=sr) * 0.15
    y = (tone + air_tone * breath * (2.5 if shaku else 1.0)) * e
    k = min(n, n_of(0.05, sr))
    chiff = filters.bandpass(rng.standard_normal(k), min(0.45 * sr, 2.0 * f0), 1.5, sr) * np.exp(-np.linspace(0, 5, k))
    y[:k] += chiff * 0.12
    return y * vel_amp(vel, 1.2) * 0.32


REEDS = {
    # duduk: cylindrical double reed, warm & nasal; accordion: 3 free reeds (musette)
    "duduk": dict(formants=[(520, 2.0, 7.0), (1350, 2.5, 4.0)], lp=2400.0, vib=14.0, scoop=-60.0, attack=0.09),
    "accordion": dict(formants=[(1100, 1.2, 4.0), (2600, 1.5, 3.0)], lp=4800.0, vib=0.0, scoop=0.0, attack=0.03),
    "bagpipe_drone": dict(formants=[(700, 1.5, 4.0), (1900, 2.0, 4.0)], lp=4000.0, vib=0.0, scoop=0.0, attack=0.15),
}


def reed(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.7, sr: int = SR, kind: str = "duduk",
         attack: float | None = None) -> np.ndarray:
    """Reed voices (mono): ``duduk`` (warm double reed with bends), ``accordion`` (three detuned free
    reeds, musette beating), ``bagpipe_drone`` (steady bright drone)."""
    p = REEDS[kind]
    n_gate = n_of(dur, sr)
    atk = attack if attack is not None else p["attack"]
    e = sustain_env(n_gate, atk, 0.15 if kind == "accordion" else 0.25, sr, overshoot=0.08)
    n = e.shape[0]
    if kind == "accordion":
        y = np.zeros(n)
        for c in (-11.0, 0.0, 12.5):
            f = f0 * 2 ** ((c + rng.normal(0, 0.8)) / 1200.0)
            y += osc.square(f, n, sr, pw=0.32, phase0=rng.random())
        y /= 3.0
        y *= 1.0 + 0.05 * np.sin(TWO_PI * rng.uniform(0.3, 0.6) * t_of(n, sr))  # bellows
    else:
        f = hz_curve(f0, n, sr, scoop_cents=p["scoop"], scoop_tau=0.07, vib_rate=rng.uniform(4.5, 5.5),
                     vib_cents=p["vib"], vib_delay=0.3, vib_rise=0.5, vib_phase=rng.uniform(0, TWO_PI))
        k_max = int(min(30, 0.42 * sr // (f0 * 1.05)))
        amps = [(1.0 / k**1.3) * (1.0 if k % 2 else 0.55) for k in range(1, k_max + 1)]
        y = harmonic_stack(osc.phase(f, n, sr, rng.random()), amps, k_max, phases=rng.uniform(0, TWO_PI, k_max))
        y += 0.03 * filters.bandpass(noise.white(n, rng), 1800.0, 1.0, sr)
    y = filters.lowpass(y * e, p["lp"], 4, sr=sr)
    y = filters.highpass(y, max(60.0, 0.5 * f0), 2, sr=sr)
    y = _eq(y, p["formants"], sr)
    return y * vel_amp(vel, 1.1) * 0.3


# --------------------------------------------------------------------------- plucked / struck strings

PLUCKS = {
    #           inharm B   pluck pos  T60 fund  hf exp  partials  body (Hz, Q, dB)                       noise
    "guitar": dict(B=8e-5, pos=0.17, t60=3.2, hf=0.85, partials=30, body=[(100, 2.0, 5), (210, 2.2, 3), (420, 1.8, 2)], pick=0.03),
    "oud": dict(B=2e-4, pos=0.11, t60=1.8, hf=0.95, partials=26, body=[(140, 2.0, 5), (300, 2.0, 3), (950, 1.4, 2)], pick=0.06),
    "harp": dict(B=3e-5, pos=0.45, t60=4.5, hf=1.1, partials=16, body=[(180, 1.4, 3)], pick=0.01),
    "mandolin": dict(B=1.2e-4, pos=0.11, t60=1.1, hf=0.75, partials=26, body=[(320, 2.0, 3), (820, 1.5, 2)], pick=0.05),
    "pizz": dict(B=5e-5, pos=0.22, t60=0.6, hf=1.25, partials=18, body=[(280, 1.3, 3), (480, 1.5, 2)], pick=0.02),
    "bass_pizz": dict(B=3e-5, pos=0.2, t60=1.4, hf=1.2, partials=14, body=[(80, 1.2, 3), (160, 1.4, 2)], pick=0.015),
}


def pluck(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.8, sr: int = SR, kind: str = "guitar",
          courses: int = 1, damp: bool | None = None, bright: float = 1.0) -> np.ndarray:
    """Plucked string (mono): stiff-string partials (``f_k = k f0 sqrt(1+B k^2)``), pluck-position
    comb, frequency-dependent decay, pick noise and body resonances. ``damp`` mutes the string at
    the end of the gate (pizzicato and short notes default to damped)."""
    p = PLUCKS[kind]
    damp = (kind in ("pizz", "mandolin")) if damp is None else damp
    t60 = p["t60"] * (220.0 / max(f0, 30.0)) ** 0.3
    total = (dur + 0.25) if damp else max(dur + 0.25, t60 * 1.1)
    n = n_of(total, sr)
    ks = np.arange(1, p["partials"] + 1)
    out = np.zeros(n)
    soft = 1.0 + (1.0 - np.clip(vel * bright, 0.0, 1.2)) * 0.9
    for c in range(courses):
        det = 2 ** (rng.normal(0.0, 2.5 if courses > 1 else 0.3) / 1200.0)
        freqs = ks * f0 * det * np.sqrt(1.0 + p["B"] * ks**2)
        amps = np.abs(np.sin(np.pi * ks * p["pos"])) / ks**soft
        t60s = t60 * ks ** (-p["hf"])
        out += osc.modal(freqs, t60s, amps, n, sr, rng=rng)
    out /= courses
    k = min(n, n_of(0.004, sr))
    pick = filters.bandpass(rng.standard_normal(k), 2800.0, 0.9, sr) * np.exp(-np.linspace(0, 6, k))
    out[:k] += pick * p["pick"] * 4.0
    out = _ramp_in(out, 0.001, sr)
    if damp:
        g = n_of(dur, sr)
        if g < n:
            out[g:] *= np.exp(-LN1000 * t_of(n - g, sr) / 0.12)
    out = _eq(out, p["body"], sr)
    return _fade_end(out, 0.02, sr) * vel_amp(vel, 1.4) * 0.35


def piano(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.7, sr: int = SR, pedal: float = 0.0) -> np.ndarray:
    """Piano-like struck string (mono): 2 detuned strings, inharmonicity, hammer-position notch,
    two-stage (prompt + aftersound) decay, damper at the end of the gate (``pedal`` adds ring)."""
    B = 4e-4 * (f0 / 261.6) ** 0.6
    n_part = int(min(28, 9000.0 // max(f0, 30.0)))
    ks = np.arange(1, n_part + 1)
    t60 = 7.0 * (261.6 / f0) ** 0.55
    hold = dur + pedal
    total = min(hold + 0.35, t60 * 1.2)
    n = n_of(total, sr)
    hardness = 0.75 + 0.9 * (1.0 - vel)
    amps = (np.abs(np.sin(np.pi * ks / 7.3)) ** 0.6 + 0.15) / ks**hardness
    out = np.zeros(n)
    for s, cents in enumerate((-0.7, 0.8)):
        freqs = ks * f0 * 2 ** (cents / 1200.0) * np.sqrt(1.0 + B * ks**2)
        prompt = osc.modal(freqs, 0.22 * t60 * ks**-0.7, amps * 0.7, n, sr, rng=rng)
        after = osc.modal(freqs, t60 * ks**-0.55, amps * 0.3, n, sr, rng=rng)
        out += prompt + after
    out *= 0.5
    k = min(n, n_of(0.012, sr))
    thump = filters.lowpass(rng.standard_normal(k), 400.0, 2, sr=sr) * np.exp(-np.linspace(0, 5, k))
    out[:k] += thump * 0.05 * vel
    out = _ramp_in(out, 0.0015, sr)
    g = n_of(hold, sr)
    if g < n:
        out[g:] *= np.exp(-LN1000 * t_of(n - g, sr) / 0.28)
    out = filters.highshelf(out, 4500.0, -5.0 + 3.0 * vel, sr=sr)
    return _fade_end(out, 0.02, sr) * vel_amp(vel, 1.3) * 0.32


# --------------------------------------------------------------------------- bells

BELLS = {
    "tubular": dict(ratios=[1.0, 2.0, 3.0, 4.07, 5.43, 6.84, 8.4], amps=[1.0, 0.55, 0.32, 0.25, 0.18, 0.12, 0.08],
                    t60=[5.5, 3.6, 2.5, 1.8, 1.2, 0.9, 0.7], click=0.04),
    "glock": dict(ratios=[1.0, 2.756, 5.404, 8.933], amps=[1.0, 0.22, 0.1, 0.04], t60=[1.9, 0.7, 0.35, 0.2], click=0.08),
    "celesta": dict(ratios=[1.0, 2.0, 3.92, 5.1], amps=[1.0, 0.1, 0.05, 0.02], t60=[1.3, 0.7, 0.35, 0.25], click=0.03),
    "church": dict(ratios=[0.5, 1.0, 1.183, 1.506, 2.0, 2.514, 2.662, 3.011, 4.166, 5.433],
                   amps=[0.55, 0.8, 0.6, 0.35, 1.0, 0.3, 0.3, 0.2, 0.15, 0.08],
                   t60=[9.0, 6.5, 5.0, 3.5, 4.0, 2.4, 2.2, 1.8, 1.2, 0.8], click=0.05),
    "glass": dict(ratios=[1.0, 2.32, 4.25, 6.63], amps=[1.0, 0.3, 0.12, 0.05], t60=[4.0, 2.2, 1.2, 0.7], click=0.01),
}


def bell(rng: np.random.Generator, f0: float, dur: float = 2.0, vel: float = 0.8, sr: int = SR, kind: str = "tubular",
         decay: float = 1.0, attack: float = 0.0) -> np.ndarray:
    """Modal bells (mono). Each partial is doubled with a slightly detuned twin (slow beating)."""
    p = BELLS[kind]
    ratios = np.array(p["ratios"])
    amps = np.array(p["amps"]) * (vel ** (np.arange(ratios.size) * 0.25))
    t60s = np.array(p["t60"]) * decay
    ok = ratios * f0 < 0.45 * sr
    ratios, amps, t60s = ratios[ok], amps[ok], t60s[ok]
    n = n_of(max(dur, float(t60s.max()) * 1.05), sr)
    jit = 1.0 + rng.normal(0.0, 0.0015, ratios.size)
    fr = np.concatenate([f0 * ratios * jit, f0 * ratios * jit * (1.0 + rng.uniform(0.0006, 0.002, ratios.size))])
    y = osc.modal(fr, np.concatenate([t60s, t60s * 0.9]), np.concatenate([amps, amps * 0.45]), n, sr, rng=rng)
    k = min(n, n_of(0.003, sr))
    y[:k] += filters.bandpass(rng.standard_normal(k), min(0.45 * sr, 4.0 * f0), 1.0, sr) * p["click"] * 4.0
    y = _ramp_in(y, attack if attack > 0 else 0.0008, sr)
    return _fade_end(y, 0.05, sr) * vel_amp(vel, 1.2) * 0.3


# --------------------------------------------------------------------------- membranes

def _glide_modal(f0: float, ratios, amps, t60s, n: int, glide: np.ndarray, rng: np.random.Generator, sr: int = SR) -> np.ndarray:
    """Damped modes sharing one relative pitch-glide curve (membrane tension modulation)."""
    base = np.cumsum(glide) / sr
    t = t_of(n, sr)
    out = np.zeros(n)
    for r, a, t60 in zip(ratios, amps, t60s):
        if a == 0 or f0 * r >= 0.45 * sr:
            continue
        m = min(n, int(1.5 * t60 * sr) + 1)
        out[:m] += a * np.exp(-LN1000 * t[:m] / t60) * np.sin(TWO_PI * (f0 * r * base[:m] + rng.random()))
    return out


def timpani(rng: np.random.Generator, f0: float, dur: float = 4.0, vel: float = 0.8, sr: int = SR,
            muffle: bool = False) -> np.ndarray:
    """Timpani (mono): nearly-harmonic kettle modes, tension pitch glide, felt-mallet noise."""
    ratios = [0.64, 1.0, 1.5, 1.98, 2.44, 2.9, 3.36, 1.68]
    base_amps = np.array([0.45, 1.0, 0.5, 0.3, 0.17, 0.1, 0.06, 0.07])
    T = 3.2 * (100.0 / f0) ** 0.3
    t60s = [0.16, T, 0.75 * T, 0.6 * T, 0.45 * T, 0.35 * T, 0.3 * T, 0.25 * T]
    if muffle:
        t60s = [min(x, 0.45) for x in t60s]
    amps = base_amps * vel ** (np.arange(len(ratios)) * 0.35)
    n = n_of(max(dur, 0.6) if muffle else max(dur, T * 1.1), sr)
    t = t_of(n, sr)
    glide = 1.0 + (0.012 + 0.03 * vel) * np.exp(-t / 0.1)
    y = _glide_modal(f0, ratios, amps, t60s, n, glide, rng, sr)
    k = min(n, n_of(0.008, sr))
    mallet = filters.lowpass(rng.standard_normal(k), 500.0 + 2500.0 * vel, 2, sr=sr) * np.exp(-np.linspace(0, 5, k))
    y[:k] += mallet * 0.35
    y = _ramp_in(y, 0.0008, sr)
    return _fade_end(y, 0.03, sr) * vel_amp(vel, 1.3) * 0.55


def taiko(rng: np.random.Generator, vel: float = 0.9, sr: int = SR, f0: float = 62.0, size: float = 1.0,
          stroke: str = "don") -> np.ndarray:
    """Big war drum (mono). ``stroke``: ``don`` (centre hit) or ``ka`` (rim/shell click)."""
    if stroke == "ka":
        n = n_of(0.25, sr)
        y = osc.modal([1150.0, 2950.0, 4100.0], [0.08, 0.05, 0.03], [1.0, 0.5, 0.3], n, sr, rng=rng)
        y += filters.bandpass(rng.standard_normal(n), 2500.0, 1.2, sr) * np.exp(-LN1000 * t_of(n, sr) / 0.03) * 0.5
        return _fade_end(_ramp_in(y, 0.0005, sr), 0.02, sr) * vel_amp(vel) * 0.45
    T = 0.9 * size
    n = n_of(T * 1.6, sr)
    t = t_of(n, sr)
    f = f0 * (1.0 + 1.1 * np.exp(-t / 0.016) + 0.22 * np.exp(-t / 0.11))
    body = np.sin(TWO_PI * np.cumsum(f) / sr) * np.exp(-LN1000 * t / T)
    head = _glide_modal(f0 * 1.65, [1.0, 1.59, 2.14, 2.30, 2.65, 2.92], [1.0, 0.7, 0.5, 0.45, 0.3, 0.2],
                        [0.35, 0.26, 0.2, 0.17, 0.13, 0.1], n, 1.0 + 0.05 * np.exp(-t / 0.05), rng, sr)
    slap = filters.lowpass(rng.standard_normal(n), 900.0 + 900.0 * vel, 2, sr=sr) * np.exp(-LN1000 * t / 0.06)
    slap = filters.highpass(slap, 70.0, 2, sr=sr)
    k = min(n, n_of(0.004, sr))
    click = np.zeros(n)
    click[:k] = filters.bandpass(rng.standard_normal(k), 2300.0, 1.0, sr) * np.exp(-np.linspace(0, 6, k))
    y = body * 1.0 + head * 0.28 * vel + slap * 0.45 * vel + click * 0.15
    y = fx.saturate(y * 0.9, 1.4, "tanh")
    return _fade_end(_ramp_in(y, 0.0005, sr), 0.03, sr) * vel_amp(vel, 1.3) * 0.8


def bass_drum(rng: np.random.Generator, vel: float = 0.8, sr: int = SR, f0: float = 44.0) -> np.ndarray:
    """Orchestral concert bass drum (mono): deep, felt beater, long bloom."""
    n = n_of(2.6, sr)
    t = t_of(n, sr)
    f = f0 * (1.0 + 0.5 * np.exp(-t / 0.03))
    body = np.sin(TWO_PI * np.cumsum(f) / sr) * np.exp(-LN1000 * t / 1.9)
    head = _glide_modal(f0 * 1.9, [1.0, 1.59, 2.14, 2.65], [1.0, 0.6, 0.4, 0.25], [0.6, 0.45, 0.35, 0.25], n,
                        np.ones(n), rng, sr)
    felt = filters.lowpass(rng.standard_normal(n), 300.0 + 500.0 * vel, 2, sr=sr) * np.exp(-LN1000 * t / 0.12)
    y = body + 0.25 * head + 0.5 * felt * vel
    a = min(n, n_of(0.006, sr))
    y[:a] *= np.linspace(0.0, 1.0, a) ** 0.7
    return _fade_end(y, 0.05, sr) * vel_amp(vel, 1.3) * 0.75


SNARES = {
    #          tone modes (Hz)      tone T60  snare band (Hz)   snare T60  click
    "military": dict(tone=(158.0, 282.0), tone_t60=0.2, band=(900.0, 7500.0), snare_t60=0.36, click=0.12, tone_g=0.5),
    "orchestral": dict(tone=(188.0, 335.0), tone_t60=0.13, band=(1600.0, 10000.0), snare_t60=0.22, click=0.15, tone_g=0.45),
    "field": dict(tone=(140.0, 251.0), tone_t60=0.26, band=(700.0, 6000.0), snare_t60=0.42, click=0.08, tone_g=0.6),
    "brush": dict(tone=(180.0, 320.0), tone_t60=0.08, band=(1500.0, 9000.0), snare_t60=0.22, click=0.0, tone_g=0.12),
}


def snare(rng: np.random.Generator, vel: float = 0.8, sr: int = SR, kind: str = "military", rim: bool = False) -> np.ndarray:
    """Snare / field drum (mono): head tone modes, wire-snare noise band, stick click."""
    p = SNARES[kind]
    n = n_of(0.8, sr)
    t = t_of(n, sr)
    glide = 1.0 + 0.04 * np.exp(-t / 0.02)
    tone = _glide_modal(p["tone"][0], [1.0, p["tone"][1] / p["tone"][0], 2.3], [1.0, 0.65, 0.25],
                        [p["tone_t60"], p["tone_t60"] * 0.8, p["tone_t60"] * 0.5], n, glide, rng, sr)
    w = noise.white(n, rng)
    sn = filters.band(w, p["band"][0], min(p["band"][1] * (0.6 + 0.4 * vel), 0.45 * sr), 2, sr)
    t60 = p["snare_t60"] * (0.75 + 0.35 * vel)
    se = np.exp(-LN1000 * t / t60)
    if kind == "brush":
        se *= np.clip(t / 0.006, 0, 1)
    # wire rattle: slightly irregular amplitude flutter
    se *= 1.0 + 0.25 * noise.smooth_random(n, rng, 90.0, sr)
    y = tone * p["tone_g"] + sn * se * 0.55
    if p["click"]:
        k = min(n, n_of(0.003, sr))
        y[:k] += filters.bandpass(rng.standard_normal(k), 4500.0, 1.0, sr) * np.exp(-np.linspace(0, 5, k)) * p["click"] * 4
    if rim:
        y += osc.modal([1650.0, 3200.0], [0.05, 0.03], [0.5, 0.25], n, sr, rng=rng)
    y = _ramp_in(y, 0.0004, sr)
    return _fade_end(y, 0.03, sr) * vel_amp(vel, 1.4) * 0.55


def tom(rng: np.random.Generator, f0: float = 110.0, dur: float = 1.0, vel: float = 0.8, sr: int = SR) -> np.ndarray:
    """Concert tom / low tom (mono), pitched membrane with downward glide."""
    n = n_of(max(dur, 0.9), sr)
    t = t_of(n, sr)
    glide = 1.0 + 0.12 * vel * np.exp(-t / 0.04)
    y = _glide_modal(f0, [1.0, 1.59, 2.14, 2.65], [1.0, 0.45, 0.3, 0.15], [0.55, 0.3, 0.2, 0.12], n, glide, rng, sr)
    k = min(n, n_of(0.005, sr))
    y[:k] += filters.lowpass(rng.standard_normal(k), 2500.0, 2, sr=sr) * np.exp(-np.linspace(0, 5, k)) * 0.4
    return _fade_end(_ramp_in(y, 0.0005, sr), 0.03, sr) * vel_amp(vel, 1.3) * 0.6


def frame_drum(rng: np.random.Generator, vel: float = 0.8, sr: int = SR, stroke: str = "doum") -> np.ndarray:
    """Frame drum / goblet drum strokes (mono): ``doum`` (deep centre), ``tek`` (rim slap), ``ka``."""
    n = n_of(0.7 if stroke == "doum" else 0.25, sr)
    t = t_of(n, sr)
    if stroke == "doum":
        glide = 1.0 + 0.25 * np.exp(-t / 0.02)
        y = _glide_modal(88.0, [1.0, 1.59, 2.14, 2.3, 2.65], [1.0, 0.5, 0.35, 0.3, 0.2], [0.45, 0.25, 0.18, 0.15, 0.1],
                         n, glide, rng, sr)
        y += filters.lowpass(rng.standard_normal(n), 700.0, 2, sr=sr) * np.exp(-LN1000 * t / 0.04) * 0.3
    else:
        f = 720.0 if stroke == "tek" else 980.0
        y = osc.modal([f, f * 1.52, f * 2.1, f * 2.9], [0.09, 0.06, 0.05, 0.04], [1.0, 0.6, 0.4, 0.3], n, sr, rng=rng)
        y += filters.bandpass(rng.standard_normal(n), 3200.0, 0.9, sr) * np.exp(-LN1000 * t / 0.05) * 0.6
    return _fade_end(_ramp_in(y, 0.0004, sr), 0.02, sr) * vel_amp(vel, 1.3) * 0.6


# --------------------------------------------------------------------------- metal

def cymbal(rng: np.random.Generator, vel: float = 0.8, sr: int = SR, kind: str = "crash", dur: float = 2.0) -> np.ndarray:
    """Cymbals (stereo). ``kind``: ``crash`` (stick crash), ``swell`` (mallet roll crescendo that
    peaks at ``dur`` then rings), ``hat`` (short closed tick), ``ride`` (ping with wash)."""
    if kind == "hat":
        n = n_of(0.12, sr)
        t = t_of(n, sr)
        y = filters.highpass(noise.white(n, rng), 7000.0, 2, sr=sr) * np.exp(-LN1000 * t / 0.05)
        fr = rng.uniform(5200.0, 12000.0, 10)
        y += osc.modal(fr, rng.uniform(0.03, 0.07, 10), rng.uniform(0.2, 0.5, 10), n, sr, rng=rng)
        y = _fade_end(_ramp_in(y, 0.0003, sr), 0.01, sr) * vel_amp(vel) * 0.18
        return mix.pan(y, rng.uniform(-0.15, 0.15)) / np.sqrt(2.0)
    count = 70
    fr = np.exp(rng.uniform(np.log(560.0), np.log(13000.0), count))
    amps = np.clip(fr / 2500.0, 0.25, 1.0) ** 0.8 * rng.uniform(0.3, 1.0, count)
    t60s = rng.uniform(1.4, 3.6, count) * (1.0 if kind != "ride" else 1.4)
    tail = 3.6 if kind != "ride" else 4.0
    if kind == "swell":
        n = n_of(dur + tail, sr)
        t = t_of(n, sr)
        g = n_of(dur, sr)
        exc_env = np.where(t < dur, (t / max(dur, 1e-3)) ** 2.6, np.exp(-LN1000 * (t - dur) / 1.4))
        exc = noise.white(n, rng) * exc_env
        sides = []
        for _c in range(2):
            idx = rng.permutation(count)[: count // 2]
            r = filters.resonators(exc, fr[idx], np.clip(fr[idx] / 60.0, 6.0, 80.0), amps[idx] * 0.4, sr)
            wash = filters.highpass(exc, 2500.0, 2, sr=sr) * 0.25
            y = r + wash
            sides.append(y)
        out = np.stack(sides, axis=1)
        out = filters.lowpass(out, 9000.0 + 5000.0 * vel, 2, sr=sr)
        out = _fade_end(out, 0.08, sr)
        return out * vel_amp(vel) * 0.6
    n = n_of(tail * 1.1, sr)
    t = t_of(n, sr)
    sides = []
    for _c in range(2):
        idx = rng.permutation(count)[: int(count * 0.7)]
        y = osc.modal(fr[idx] * (1 + rng.normal(0, 0.002, idx.size)), t60s[idx], amps[idx], n, sr, rng=rng)
        wash = filters.highpass(noise.white(n, rng), 3000.0 if kind == "crash" else 5000.0, 2, sr=sr)
        y = y * 0.12 + wash * np.exp(-LN1000 * t / (2.4 if kind == "crash" else 1.2)) * 0.22 * (1 - np.exp(-t / 0.01))
        sides.append(y)
    out = np.stack(sides, axis=1)
    k = min(n, n_of(0.02, sr))
    hit = filters.bandpass(rng.standard_normal(k), 5000.0, 0.8, sr) * np.exp(-np.linspace(0, 5, k))
    out[:k] += hit[:, None] * (0.6 if kind == "crash" else 0.25)
    out = filters.lowpass(out, 8000.0 + 7000.0 * vel, 2, sr=sr)
    out = _fade_end(_ramp_in(out, 0.0004, sr), 0.08, sr)
    return out * vel_amp(vel) * (0.75 if kind == "crash" else 0.45)


def anvil(rng: np.random.Generator, vel: float = 0.8, sr: int = SR, f0: float = 1050.0, t60: float = 1.4) -> np.ndarray:
    """Anvil / struck steel bar (mono) for industrial percussion."""
    n = n_of(t60 * 1.2, sr)
    ratios = np.array([1.0, 2.756, 5.404, 1.012, 2.79, 8.93])
    amps = np.array([1.0, 0.6, 0.35, 0.5, 0.25, 0.15])
    fr = f0 * ratios * (1 + rng.normal(0, 0.003, ratios.size))
    y = osc.modal(fr, t60 * np.array([1.0, 0.6, 0.35, 0.9, 0.55, 0.2]), amps, n, sr, rng=rng)
    k = min(n, n_of(0.003, sr))
    y[:k] += filters.highpass(rng.standard_normal(k), 2000.0, 2, sr=sr) * np.exp(-np.linspace(0, 5, k)) * 1.5
    y += filters.bandpass(rng.standard_normal(n), 900.0, 1.0, sr) * np.exp(-LN1000 * t_of(n, sr) / 0.05) * 0.3
    return _fade_end(_ramp_in(y, 0.0003, sr), 0.05, sr) * vel_amp(vel) * 0.35


def clock_tick(rng: np.random.Generator, vel: float = 0.6, sr: int = SR, f0: float = 1900.0) -> np.ndarray:
    """Dry wooden/mechanical tick (mono): short modal wood block."""
    n = n_of(0.12, sr)
    y = osc.modal(f0 * np.array([1.0, 2.57, 4.21]), [0.035, 0.02, 0.012], [1.0, 0.4, 0.2], n, sr, rng=rng)
    y += filters.bandpass(rng.standard_normal(n), 5000.0, 1.0, sr) * np.exp(-LN1000 * t_of(n, sr) / 0.008) * 0.4
    return _fade_end(_ramp_in(y, 0.0003, sr), 0.01, sr) * vel_amp(vel) * 0.35


# --------------------------------------------------------------------------- synth layers

def sub_bass(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.8, sr: int = SR, attack: float = 0.008,
             release: float = 0.25, drive: float = 1.6, pluck: float = 0.0) -> np.ndarray:
    """Hybrid-score sub layer (mono): sine + 2nd harmonic through soft saturation.
    ``pluck`` (0..1) adds a decaying envelope for pulsing ostinatos."""
    n_gate = n_of(dur, sr)
    e = sustain_env(n_gate, attack, release, sr)
    n = e.shape[0]
    if pluck:
        e = e * ((1 - pluck) + pluck * np.exp(-LN1000 * t_of(n, sr) / max(dur * 1.5, 0.1)))
    ph = osc.phase(f0, n, sr, 0.0)
    y = np.sin(TWO_PI * ph) + 0.18 * np.sin(2 * TWO_PI * ph)
    y = fx.saturate(y * e, drive, "tanh")
    return filters.lowpass(y, 400.0, 2, sr=sr) * vel_amp(vel) * 0.5


def pad(rng: np.random.Generator, f0: float, dur: float, vel: float = 0.6, sr: int = SR, voices: int = 5,
        detune: float = 14.0, cutoff: float = 1800.0, attack: float = 1.2, release: float = 2.0, width: float = 0.8) -> np.ndarray:
    """Soft supersaw pad (stereo) used under the orchestra for sustain and width."""
    n_gate = n_of(dur, sr)
    e = sustain_env(n_gate, attack, release, sr)
    n = e.shape[0]
    out = np.zeros((n, 2))
    pos = spread_positions(voices, -width, width, rng)
    for i in range(voices):
        c = (i - (voices - 1) / 2) / max(1, (voices - 1) / 2) * detune + rng.normal(0, 1.5)
        f = f0 * 2 ** (c / 1200.0)
        y = osc.saw(f, n, sr, phase0=rng.random())
        out += mix.pan(y, pos[i]) / np.sqrt(2.0)
    out *= e[:, None]
    out = filters.lowpass(out, cutoff, 2, sr=sr)
    out = filters.lowpass(out, cutoff * 1.5, 2, sr=sr)
    out = filters.highpass(out, 60.0, 2, sr=sr)
    return out * vel_amp(vel) * (0.5 / np.sqrt(voices))


def shepard_grain(rng: np.random.Generator, f_lo: float, octaves: float, dur: float, vel: float = 0.6, sr: int = SR,
                  direction: float = 1.0) -> np.ndarray:
    """One component of a Shepard-Risset glissando (mono): a sine gliding ``octaves`` over ``dur``
    under a raised-cosine (in log-frequency) loudness window. Overlapping grains started every
    ``dur / octaves`` seconds form an endlessly rising (or falling) tone that loops seamlessly."""
    n = n_of(dur, sr)
    x = np.linspace(0.0, 1.0, n, endpoint=False)
    oct_pos = x * octaves if direction > 0 else (1.0 - x) * octaves
    f = f_lo * np.power(2.0, oct_pos)
    w = 0.5 - 0.5 * np.cos(TWO_PI * x)
    y = np.sin(TWO_PI * osc.phase(f, n, sr, rng.random())) * w
    return y * vel_amp(vel) * 0.3


# --------------------------------------------------------------------------- registry

PITCHED = {
    "strings": strings, "brass": brass, "choir": choir, "organ": organ, "flute": flute, "reed": reed,
    "pluck": pluck, "piano": piano, "bell": bell, "timpani": timpani, "tom": tom, "sub_bass": sub_bass,
    "pad": pad,
}

UNPITCHED = {
    "taiko": taiko, "bass_drum": bass_drum, "snare": snare, "cymbal": cymbal, "frame_drum": frame_drum,
    "anvil": anvil, "clock_tick": clock_tick,
}


def play(name: str, rng: np.random.Generator, f0: float | None, dur: float, vel: float, sr: int = SR, **params) -> np.ndarray:
    """Uniform entry point used by the score renderer."""
    if name == "shepard":
        return shepard_grain(rng, params.pop("f_lo", 40.0), params.pop("octaves", 8.0), dur, vel, sr, **params)
    if name in UNPITCHED:
        fn = UNPITCHED[name]
        if name == "cymbal":
            return fn(rng, vel, sr, dur=dur, **params)
        if name in ("anvil", "clock_tick") and f0 is not None:
            return fn(rng, vel, sr, f0=f0, **params)
        if name == "taiko" and f0 is not None:
            return fn(rng, vel, sr, f0=f0, **params)
        return fn(rng, vel, sr, **params)
    fn = PITCHED.get(name)
    if fn is None:
        raise ValueError(f"unknown instrument {name!r}")
    return fn(rng, float(f0), dur, vel, sr, **params)
