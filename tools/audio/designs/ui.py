"""UI sounds, battle information cues and radio quick-command chirps.

Sonic identity: crisp mechanical switch clicks plus clean sine/triangle and FM-bell tones
tuned to D (D-F#-A positive, D-F-A / tritone for warnings). Every UI/cue sound is stereo
with a small, mono-compatible room so it sits "in front of" the 3D world.

Battle cues are designed to cut through combat: each owns a distinct pitch/rhythm signature
(sixth sense = tritone-to-semitone motif over a low drone; spotted = sonar ping; reload =
clack-ding; lock = two rising beeps; capture = two-tone pulse).
"""

from __future__ import annotations

import numpy as np

from synth import env, filters, fx, mix, noise, osc
from synth.core import n_of, note_hz, t_of

from . import kit
from .registry import sound


def _n(x):
    return x / max(np.max(np.abs(x)), 1e-12)


def stereo(y, rng, wet: float = 0.1, space: str = "small_room"):
    return kit.stereo_space(y, rng, space, wet)


def tick(rng, f: float = 3500.0, dur: float = 0.004) -> np.ndarray:
    k = n_of(dur)
    c = noise.white(k, rng) * np.exp(-np.linspace(0, 8, k))
    return _n(filters.bandpass(c, f, 1.2))


def switch_click(rng, low: float = 1.0) -> np.ndarray:
    """Physical-feeling switch: down click, up click, faint body thock."""
    n = n_of(0.09)
    y = np.zeros(n)
    mix.place(y, tick(rng, 3600, 0.004), 0.0, 1.0)
    mix.place(y, _n(kit.modal_hit(rng, 0.03, 4200, "bar", t60=0.01, modes=2, click=0.0)), 0.0, 0.4)
    mix.place(y, tick(rng, 2300, 0.004), 0.028, 0.6)
    th = osc.sine(185, n_of(0.03)) * env.perc(n_of(0.03), 0.001, 0.025)
    mix.place(y, th, 0.0, 0.35 * low)
    return y


def tone(f, dur: float, kind: str = "soft", t60: float | None = None, attack: float = 0.003) -> np.ndarray:
    n = n_of(dur)
    if kind == "soft":
        y = osc.sine(f, n) + 0.25 * osc.triangle(f * 2, n)
    elif kind == "bell":
        y = kit.fm_bell(f, dur, t60 or dur, 3.5, 1.8) + 0.4 * osc.sine(f, n)
    elif kind == "metal":
        y = kit.fm_bell(f, dur, t60 or dur, 1.41, 2.5)
    elif kind == "square":
        y = filters.lowpass(osc.square(f, n, pw=0.35), 3000, 2)
    elif kind == "brass":
        fe = np.asarray(f) if np.ndim(f) else f
        sw = osc.saw(mixvib(fe, n), n) + 0.5 * osc.saw(mixvib(fe, n) * 1.003, n)
        cut = env.breakpoints([(0, 700), (0.05, 3800), (0.25, 1800), (dur, 1200)], n, kind="exp")
        y = filters.tv_lowpass(sw, cut, 0.9)
    else:
        raise ValueError(kind)
    e = env.perc(n, attack, t60 or dur * 0.9)
    return y * e


def mixvib(f, n):
    return np.full(n, float(f)) * 2 ** (6 * np.clip(t_of(n) - 0.18, 0, None) / 0.4 * np.sin(2 * np.pi * 5.5 * t_of(n)) / 1200)


def whoosh_ui(rng, dur: float, f0: float, f1: float) -> np.ndarray:
    return _n(kit.whoosh(rng, dur, f0, f1, 1.8, 0.6 if f1 > f0 else 0.25, "pink"))


def drum(rng, f: float = 90.0, dur: float = 1.0, t60: float = 0.6) -> np.ndarray:
    y = kit.boom(dur, f * 1.3, f, 0.02, t60, 0.002)
    y += 0.3 * kit.noise_burst(rng, dur, 0.001, 0.15, 80, 1200, "pink")
    return _n(y)


# --------------------------------------------------------------------------- UI
def ui_hover(rng, v):
    n = n_of(0.07)
    y = np.zeros(n)
    mix.place(y, filters.highpass(tick(rng, 4500, 0.003), 2500, 2), 0, 0.5)
    mix.place(y, osc.sine(note_hz("D7"), n_of(0.03)) * env.perc(n_of(0.03), 0.001, 0.02), 0, 0.35)
    return stereo(y, rng, 0.06)


def ui_click(rng, v):
    return stereo(switch_click(rng), rng, 0.08)


def ui_confirm(rng, v):
    n = n_of(0.6)
    y = np.zeros(n)
    mix.place(y, switch_click(rng), 0, 0.6)
    mix.place(y, tone(note_hz("D5"), 0.12, "bell", 0.12), 0.015, 0.5)
    mix.place(y, tone(note_hz("A5"), 0.45, "bell", 0.4), 0.09, 0.6)
    return stereo(y, rng, 0.12)


def ui_back(rng, v):
    n = n_of(0.4)
    y = np.zeros(n)
    mix.place(y, switch_click(rng, 0.5), 0, 0.45)
    mix.place(y, filters.lowpass(tone(note_hz("A5"), 0.1, "soft", 0.09), 2500, 2), 0.01, 0.4)
    mix.place(y, filters.lowpass(tone(note_hz("D5"), 0.25, "soft", 0.22), 2500, 2), 0.08, 0.45)
    return stereo(y, rng, 0.1)


def ui_error(rng, v):
    n = n_of(0.38)
    y = np.zeros(n)
    for t in (0.0, 0.15):
        m = n_of(0.1)
        b = (osc.square(196.0, m, pw=0.45) + 0.5 * osc.square(207.65, m, pw=0.45)) * env.ar(m, 0.004, 0.02)
        mix.place(y, filters.lowpass(b, 1800, 2), t, 0.5)
    return stereo(y, rng, 0.08)


def ui_toggle(direction: str):
    def render(rng, v):
        n = n_of(0.16)
        y = np.zeros(n)
        mix.place(y, switch_click(rng), 0, 0.6)
        m = n_of(0.06)
        f = np.geomspace(900, 1400, m) if direction == "on" else np.geomspace(1400, 900, m)
        mix.place(y, osc.sine(f, m) * env.perc(m, 0.002, 0.05), 0.02, 0.35)
        return stereo(y, rng, 0.08)

    return render


def ui_tab_switch(rng, v):
    n = n_of(0.18)
    y = np.zeros(n)
    mix.place(y, whoosh_ui(rng, 0.1, 2500, 6000), 0, 0.25)
    mix.place(y, tick(rng, 3000, 0.004), 0.05, 0.5)
    mix.place(y, osc.sine(1760, n_of(0.04)) * env.perc(n_of(0.04), 0.001, 0.035), 0.05, 0.25)
    return stereo(y, rng, 0.1)


def ui_purchase(rng, v):
    n = n_of(1.1)
    y = np.zeros(n)
    stamp = mix.mix(kit.modal_hit(rng, 0.2, 230, "plate", t60=0.06, modes=6, bright=0.3, click=0.8), (kit.boom(0.1, 160, 110, 0.01, 0.05), 0.8))
    mix.place(y, _n(stamp), 0, 0.6)
    latch = kit.modal_hit(rng, 0.12, 2800, "bar", t60=0.03, modes=3, click=1.2)
    mix.place(y, _n(latch), 0.07, 0.4)
    mix.place(y, _n(kit.fm_bell(note_hz("E7"), 0.8, 0.6, 1.41, 3.0)), 0.12, 0.35)
    mix.place(y, _n(kit.fm_bell(note_hz("A7") * 0.995, 0.8, 0.5, 1.41, 2.5)), 0.14, 0.25)
    mix.place(y, tone(note_hz("D6"), 0.5, "bell", 0.45), 0.2, 0.25)
    return stereo(y, rng, 0.12)


def arpeggio(notes, step: float, kind: str = "bell", dur: float = 0.6, gain: float = 0.5):
    total = step * len(notes) + dur
    y = np.zeros(n_of(total))
    for i, nm in enumerate(notes):
        mix.place(y, tone(note_hz(nm), dur, kind, dur * 0.8), i * step, gain)
    return y


def pad(notes, dur: float, attack: float = 0.3, release: float = 0.8, cutoff: float = 1600.0, rng=None):
    n = n_of(dur)
    y = np.zeros(n)
    for nm in notes:
        f = note_hz(nm)
        y += osc.saw(f, n) + osc.saw(f * 1.004, n)
    y = filters.lowpass(y, cutoff, 2) * env.ar(n, attack, release)
    return _n(y)


def ui_research_complete(rng, v):
    y = np.zeros(n_of(2.0))
    mix.place(y, arpeggio(["D5", "F#5", "A5", "D6"], 0.085, "bell", 0.9), 0, 0.5)
    mix.place(y, pad(["D4", "A4", "F#5"], 1.6, 0.25, 0.9, 1800), 0.2, 0.18)
    return stereo(y, rng, 0.15)


def ui_vehicle_unlocked(rng, v):
    y = np.zeros(n_of(2.7))
    seq = [("A4", 0.0, 0.16), ("D5", 0.17, 0.16), ("F#5", 0.34, 0.16), ("A5", 0.51, 1.3)]
    for nm, t, d in seq:
        mix.place(y, tone(note_hz(nm), d + 0.15, "brass", d + 0.1, 0.012), t, 0.45)
    mix.place(y, tone(note_hz("D5"), 1.4, "brass", 1.2, 0.02), 0.51, 0.25)
    mix.place(y, tone(note_hz("F#4"), 1.4, "brass", 1.2, 0.02), 0.51, 0.2)
    mix.place(y, drum(rng, 98, 1.2, 0.8), 0.51, 0.5)
    mix.place(y, drum(rng, 98, 0.5, 0.3), 0.0, 0.25)
    mix.place(y, _n(kit.fm_bell(note_hz("A6"), 1.4, 1.2, 3.5, 1.5)), 0.52, 0.12)
    return stereo(y, rng, 0.2, "stone_hall")


def ui_notification(rng, v):
    y = np.zeros(n_of(0.9))
    mix.place(y, tone(note_hz("A5"), 0.5, "bell", 0.45), 0, 0.45)
    mix.place(y, tone(note_hz("D6"), 0.7, "bell", 0.6), 0.12, 0.5)
    return stereo(y, rng, 0.15)


def ui_mission_complete(rng, v):
    y = np.zeros(n_of(3.0))
    for nm, t, d in [("D5", 0.0, 0.12), ("A5", 0.13, 0.12), ("D6", 0.27, 1.6)]:
        mix.place(y, tone(note_hz(nm), d + 0.15, "brass", d + 0.1, 0.01), t, 0.45)
    for nm in ("D4", "A4", "F#5"):
        mix.place(y, tone(note_hz(nm), 1.8, "brass", 1.5, 0.03), 0.27, 0.22)
    roll = noise.pink(n_of(0.3), rng) * np.linspace(0, 1, n_of(0.3)) ** 2
    mix.place(y, _n(filters.band(roll, 60, 900, 2)), 0.0, 0.3)
    mix.place(y, drum(rng, 82, 1.6, 1.1), 0.27, 0.6)
    mix.place(y, arpeggio(["D6", "F#6", "A6"], 0.05, "bell", 1.0, 0.3), 0.3, 0.6)
    return stereo(y, rng, 0.22, "stone_hall")


def ui_achievement(rng, v):
    y = np.zeros(n_of(2.3))
    mix.place(y, arpeggio(["D6", "F#6", "A6", "D7"], 0.045, "bell", 1.2, 0.45), 0, 1.0)
    m = n_of(1.6)
    shimmer = np.zeros(m)
    for f in (note_hz("A7"), note_hz("D8") * 0.998, note_hz("F#7") * 1.002):
        shimmer += osc.sine(f, m) * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(9, 14) * t_of(m)))
    mix.place(y, _n(shimmer * env.ar(m, 0.15, 1.0)), 0.15, 0.12)
    mix.place(y, pad(["D4", "A4", "D5", "F#5"], 1.8, 0.2, 1.0, 2200), 0.1, 0.18)
    return stereo(y, rng, 0.2)


def ui_battle_found(rng, v):
    y = np.zeros(n_of(2.1))
    mix.place(y, drum(rng, 70, 1.2, 0.7), 0.0, 0.7)
    m = n_of(0.45)
    rise = filters.lowpass(osc.saw(np.geomspace(180, 620, m), m), 2500, 2) * np.linspace(0.2, 1.0, m) ** 2
    mix.place(y, _n(rise), 0.0, 0.25)
    for nm in ("D4", "F4", "A4", "D5"):
        mix.place(y, tone(note_hz(nm), 1.3, "brass", 1.1, 0.008), 0.45, 0.22)
    mix.place(y, drum(rng, 70, 1.4, 0.9), 0.45, 0.8)
    return stereo(y, rng, 0.2, "stone_hall")


def ui_countdown_tick(rng, v):
    y = np.zeros(n_of(0.22))
    mix.place(y, tone(note_hz("E6"), 0.18, "soft", 0.12, 0.001), 0, 0.6)
    mix.place(y, tick(rng, 3000, 0.003), 0, 0.3)
    return stereo(y, rng, 0.08)


def ui_countdown_go(rng, v):
    y = np.zeros(n_of(1.1))
    mix.place(y, tone(note_hz("A6"), 0.7, "soft", 0.5, 0.001), 0, 0.45)
    mix.place(y, tone(note_hz("A5"), 0.8, "bell", 0.6, 0.001), 0, 0.4)
    mix.place(y, drum(rng, 75, 0.9, 0.5), 0, 0.6)
    mix.place(y, whoosh_ui(rng, 0.5, 800, 4000), 0, 0.12)
    return stereo(y, rng, 0.15)


def ui_level_up(rng, v):
    y = np.zeros(n_of(1.9))
    riser = filters.tv_bandpass(noise.pink(n_of(0.35), rng), np.geomspace(500, 6000, n_of(0.35)), 2.0)
    riser *= np.linspace(0, 1, riser.shape[0]) ** 2
    mix.place(y, _n(riser), 0.0, 0.2)
    mix.place(y, arpeggio(["A4", "D5", "F#5", "A5", "D6"], 0.06, "bell", 0.9, 0.4), 0.3, 1.0)
    mix.place(y, pad(["D4", "A4", "F#5"], 1.3, 0.1, 0.8, 2000), 0.5, 0.18)
    return stereo(y, rng, 0.15)


def ui_slider_tick(rng, v):
    n = n_of(0.03)
    y = np.zeros(n)
    mix.place(y, filters.highpass(tick(rng, 5000, 0.002), 3000, 2), 0, 0.5)
    mix.place(y, osc.sine(3520, n_of(0.012)) * env.perc(n_of(0.012), 0.0005, 0.01), 0, 0.2)
    return stereo(y, rng, 0.04)


def ui_panel(direction: str):
    def render(rng, v):
        n = n_of(0.34)
        y = np.zeros(n)
        if direction == "open":
            mix.place(y, whoosh_ui(rng, 0.2, 700, 3600), 0, 0.35)
            mix.place(y, switch_click(rng, 0.6), 0.17, 0.4)
        else:
            mix.place(y, switch_click(rng, 0.6), 0.0, 0.4)
            mix.place(y, whoosh_ui(rng, 0.2, 3600, 700), 0.02, 0.35)
        return stereo(y, rng, 0.08)

    return render


# --------------------------------------------------------------------------- battle cues
def cue_sixth_sense(rng, v):
    """Original 3-note warning: A4 -> D#5 (tritone up) -> D5 (semitone down, held) over a low drone."""
    y = np.zeros(n_of(1.45))
    notes = [(note_hz("A4"), 0.0, 0.16), (note_hz("D#5"), 0.13, 0.16), (note_hz("D5"), 0.26, 0.85)]
    for f, t, d in notes:
        m = n_of(d + 0.2)
        metal = kit.fm_bell(f, d + 0.2, d + 0.15, 1.41, 2.2)
        sq = filters.band(osc.square(f, m, pw=0.3), 600, 4000, 2) * env.perc(m, 0.002, d + 0.05)
        layer = _n(metal) + 0.35 * _n(sq)
        if d > 0.5:
            layer *= 0.75 + 0.25 * np.sin(2 * np.pi * 7.0 * t_of(m))
        mix.place(y, layer, t, 0.5)
    m = n_of(1.3)
    # dark drone an octave above sub range so it survives phone/laptop speakers
    drone = (osc.sine(note_hz("D3"), m) + 0.6 * osc.sine(note_hz("A3") * 1.004, m) + 0.25 * osc.saw(note_hz("D3") * 0.997, m))
    drone = filters.highpass(filters.lowpass(drone, 900, 2), 110, 2) * env.ar(m, 0.06, 0.6)
    mix.place(y, _n(drone), 0.0, 0.16)
    mix.place(y, tick(rng, 5000, 0.003), 0.0, 0.3)
    return stereo(y, rng, 0.18)


def cue_enemy_spotted(rng, v):
    n = n_of(0.75)
    y = np.zeros(n)
    m = n_of(0.4)
    f = note_hz("G6") * (1 + 0.04 * (1 - np.exp(-t_of(m) / 0.01)))
    ping = (osc.sine(f, m) + 0.2 * osc.triangle(f * 2, m)) * env.perc(m, 0.001, 0.35)
    mix.place(y, ping, 0, 0.6)
    y = fx.delay(y, 0.11, 0.35, 0.5, 3000)[:n]
    return stereo(y, rng, 0.12)


def cue_capture_warning(rng, v):
    n = n_of(2.0)
    y = np.zeros(n)
    for t, nm in ((0.0, "A5"), (0.25, "F5"), (1.0, "A5"), (1.25, "F5")):
        m = n_of(0.19)
        b = filters.lowpass(osc.square(note_hz(nm), m, pw=0.3), 3200, 2) * 0.5 + osc.sine(note_hz(nm), m)
        mix.place(y, b * env.ar(m, 0.005, 0.03), t + 0.002, 0.5)
    return y  # stereo room added below in loop-safe way


def cue_capture_warning_loop(rng, v):
    y = cue_capture_warning(rng, v)
    st = mix.circular(lambda z: kit.stereo_space(z, rng, "small_room", 0.1)[: z.shape[0]], y, 2)
    return st


def cue_capture_complete(rng, v):
    y = np.zeros(n_of(2.0))
    mix.place(y, drum(rng, 80, 1.4, 0.9), 0, 0.7)
    for nm in ("D4", "A4", "D5"):
        mix.place(y, tone(note_hz(nm), 1.5, "brass", 1.2, 0.006), 0.0, 0.25)
    mix.place(y, tone(note_hz("D6"), 1.5, "bell", 1.3), 0.02, 0.3)
    return stereo(y, rng, 0.2, "stone_hall")


def cue_low_hp_heartbeat(rng, v):
    n = n_of(3.2)
    y = np.zeros(n)
    for b in range(4):
        t0 = b * 0.8
        for dt, f, a in ((0.0, 52.0, 1.0), (0.13, 64.0, 0.75)):
            m = n_of(0.3)
            beat = (osc.sine(f, m) + 0.35 * osc.sine(2 * f, m)) * env.perc(m, 0.006, 0.14)
            beat += 0.15 * filters.lowpass(noise.white(m, rng), 300, 2) * env.perc(m, 0.002, 0.05)
            mix.place_wrapped(y, beat, n_of(t0 + dt + 0.02), a)
    y = mix.circular(lambda z: filters.lowpass(z, 260, 2), y, 2)
    return np.stack([y, y], axis=1)


def cue_low_hp_alarm(rng, v):
    y = np.zeros(n_of(0.55))
    for i, nm in enumerate(("C6", "A5", "F#5")):
        m = n_of(0.09)
        b = filters.lowpass(osc.square(note_hz(nm), m, pw=0.4), 2500, 2) * env.ar(m, 0.004, 0.02)
        mix.place(y, b, i * 0.13, 0.5)
    return stereo(y, rng, 0.1)


def cue_reload_complete(rng, v):
    y = np.zeros(n_of(0.5))
    latch = kit.modal_hit(rng, 0.1, 2800, "bar", t60=0.03, modes=3, click=1.4)
    mix.place(y, _n(latch), 0, 0.6)
    mix.place(y, tone(note_hz("E6"), 0.35, "bell", 0.28, 0.001), 0.035, 0.5)
    return stereo(y, rng, 0.1)


def cue_target(locked: bool):
    def render(rng, v):
        y = np.zeros(n_of(0.25))
        seq = (("C6", 0.0), ("G6", 0.075)) if locked else (("G6", 0.0),)
        for nm, t in seq:
            m = n_of(0.05 if locked else 0.08)
            f = note_hz(nm) if locked else np.geomspace(note_hz("G6"), note_hz("C6"), m)
            b = (osc.sine(f, m) + 0.3 * osc.triangle(np.asarray(f) * 2, m)) * env.ar(m, 0.002, 0.015)
            mix.place(y, b, t, 0.5 if locked else 0.35)
        mix.place(y, tick(rng, 4000, 0.003), 0, 0.25)
        return stereo(y, rng, 0.06)

    return render


def cue_ally_destroyed(rng, v):
    y = np.zeros(n_of(1.4))
    mix.place(y, tone(note_hz("D4"), 0.45, "brass", 0.4, 0.02), 0, 0.4)
    mix.place(y, tone(note_hz("A3"), 0.9, "brass", 0.8, 0.02), 0.32, 0.45)
    mix.place(y, filters.lowpass(drum(rng, 60, 0.9, 0.6), 400, 2), 0.32, 0.4)
    return stereo(filters.lowpass(y, 2200, 2), rng, 0.2)


def cue_enemy_destroyed(rng, v):
    y = np.zeros(n_of(0.9))
    mix.place(y, tick(rng, 3000, 0.004), 0, 0.5)
    mix.place(y, tone(note_hz("A4"), 0.15, "brass", 0.13, 0.004), 0, 0.4)
    mix.place(y, tone(note_hz("E5"), 0.6, "brass", 0.5, 0.004), 0.1, 0.45)
    mix.place(y, tone(note_hz("E6"), 0.5, "bell", 0.4), 0.1, 0.2)
    return stereo(y, rng, 0.12)


def cue_objective_update(rng, v):
    y = np.zeros(n_of(1.2))
    mix.place(y, arpeggio(["D5", "F#5", "A5"], 0.065, "bell", 0.7, 0.45), 0, 1.0)
    blip = kit.radio(osc.sine(1600, n_of(0.05)) * env.ar(n_of(0.05), 0.003, 0.01), rng, hiss=0.0)
    mix.place(y, _n(blip), 0.75, 0.25)
    return stereo(y, rng, 0.15)


# --------------------------------------------------------------------------- radio
RADIO_PATTERNS = {
    "attack": ([(800, 0.08), (1000, 0.08), (1300, 0.12)], 0.03, "Attack! - three fast rising beeps"),
    "defend": ([(520, 0.22), (520, 0.22)], 0.08, "Defend the base! - two long low tones"),
    "help": ([(1200, 0.06), (900, 0.06)] * 4, 0.015, "Help! - rapid alternating hi-lo"),
    "retreat": ([(1200, 0.11), (900, 0.11), (650, 0.16)], 0.04, "Fall back! - three descending tones"),
    "spotted": ([(1500, 0.1), (1000, 0.05), (1000, 0.05)], 0.05, "Enemy spotted - ping and two short beeps"),
    "capture": ([(900, 0.2), (900, 0.07), (1100, 0.2)], 0.05, "Capture the base! - long-short-long rising"),
    "follow": ([(700, 0.09), (1000, 0.09), (700, 0.09), (1000, 0.09)], 0.02, "Follow me! - up-down pairs"),
}


def radio_command(name: str):
    pattern, gap, _ = RADIO_PATTERNS[name]

    def render(rng, v):
        body = sum(d + gap for _, d in pattern)
        total = 0.06 + 0.12 + body + 0.25
        y = np.zeros(n_of(total))
        chirp = osc.sine(1600, n_of(0.035)) * env.ar(n_of(0.035), 0.002, 0.01)
        mix.place(y, chirp, 0.0, 0.4)
        mix.place(y, _n(kit.static_burst(rng, 0.12, 80)), 0.04, 0.35)
        t = 0.16
        for f, d in pattern:
            m = n_of(d)
            b = (osc.sine(f, m) + 0.3 * osc.square(f, m, pw=0.4)) * env.ar(m, 0.004, 0.012)
            mix.place(y, b, t, 0.6)
            t += d + gap
        hiss = filters.band(noise.white(y.shape[0], rng), 400, 3500, 2) * 0.03
        y = kit.radio(y + hiss, rng, drive=2.0, hiss=0.01)
        mix.place(y, _n(kit.squelch_tail(rng)), t + 0.02, 0.3)
        return stereo(y, rng, 0.08)

    return render


def radio_static(rng, v):
    dur = {"a": 0.3, "b": 0.45, "c": 0.6}.get(v, 0.4)
    y = np.zeros(n_of(dur + 0.15))
    mix.place(y, _n(kit.radio(kit.static_burst(rng, dur, 70), rng)), 0, 0.6)
    mix.place(y, _n(kit.squelch_tail(rng)), dur, 0.3)
    return stereo(y, rng, 0.06)


# --------------------------------------------------------------------------- registration
def _register() -> None:
    ui = [
        ("ui_hover", ui_hover, "Soft high tick.", "Pointer/selection moves onto an interactive element.", -32.0, 40),
        ("ui_click", ui_click, "Mechanical switch click (down/up).", "Button pressed.", -24.0, 60),
        ("ui_confirm", ui_confirm, "Click plus rising fifth (D5-A5) bell.", "Confirm / accept / apply.", -20.0, 70),
        ("ui_back", ui_back, "Soft click plus falling fifth, darker.", "Back / cancel / dismiss.", -23.0, 60),
        ("ui_error", ui_error, "Two low buzzy pulses (G3 + semitone).", "Invalid action / insufficient funds / locked.", -21.0, 75),
        ("ui_toggle_on", ui_toggle("on"), "Click with upward blip.", "Toggle switched on.", -25.0, 50),
        ("ui_toggle_off", ui_toggle("off"), "Click with downward blip.", "Toggle switched off.", -25.0, 50),
        ("ui_tab_switch", ui_tab_switch, "Short air swish and tick.", "Tab / carousel page changed.", -25.0, 50),
        ("ui_purchase", ui_purchase, "Military 'cash register': stamp, latch, coin-like ching.", "Purchase completed (credits/gold).", -18.0, 80),
        ("ui_research_complete", ui_research_complete, "Rising D-major bell arpeggio over a soft pad.", "Module/vehicle researched.", -17.0, 82),
        ("ui_vehicle_unlocked", ui_vehicle_unlocked, "Fanfare-lite: brass motif A-D-F#-A with timpani.", "New vehicle unlocked / bought.", -16.0, 85),
        ("ui_notification", ui_notification, "Two-note chime A5-D6.", "Toast notification arrives.", -20.0, 65),
        ("ui_mission_complete", ui_mission_complete, "Triumphant brass motif, chord, drum.", "Mission / campaign task complete.", -15.5, 85),
        ("ui_achievement_unlocked", ui_achievement, "Sparkly fast bell arpeggio with shimmer and pad.", "Achievement / medal earned.", -17.0, 82),
        ("ui_battle_found", ui_battle_found, "Drum hit, rising tone, D-minor brass stab.", "Matchmaking found a battle.", -15.0, 90),
        ("ui_countdown_tick", ui_countdown_tick, "Clean E6 tick.", "Pre-battle countdown second.", -20.0, 85),
        ("ui_countdown_go", ui_countdown_go, "Bright A tone with drum and whoosh.", "Battle starts.", -15.0, 90),
        ("ui_level_up", ui_level_up, "Riser into a rising arpeggio and pad.", "Crew/vehicle/account level up.", -17.0, 80),
        ("ui_slider_tick", ui_slider_tick, "Tiny detent tick.", "Slider step changed (rate-limit to 30/s).", -33.0, 30),
        ("ui_open_panel", ui_panel("open"), "Upward swish then soft click.", "Panel/modal opens.", -25.0, 55),
        ("ui_close_panel", ui_panel("close"), "Soft click then downward swish.", "Panel/modal closes.", -25.0, 55),
    ]
    for key, fn, desc, ev, lvl, pri in ui:
        sound(key, "ui", fn, desc, ev, level=lvl, priority=pri)
    cues = [
        ("cue_sixth_sense", cue_sixth_sense, "SPOTTED WARNING: original ominous 3-note motif (A4, D#5, D5 held) over a low drone.",
         "Own vehicle has been spotted by the enemy (highest-priority cue; ducks everything else ~4 dB).", -13.0, 100),
        ("cue_enemy_spotted", cue_enemy_spotted, "Sonar-like G6 ping with echo.", "An enemy is newly spotted by your team.", -17.0, 88),
        ("cue_capture_complete", cue_capture_complete, "Drum, D power-chord brass and bell.", "Base capture completed.", -14.0, 92),
        ("cue_low_hp_alarm", cue_low_hp_alarm, "Three descending filtered-square pulses.", "Own HP drops below 25 %.", -18.0, 86),
        ("cue_reload_complete", cue_reload_complete, "Latch clack plus E6 'ding'.", "Own gun loaded and ready.", -18.0, 87),
        ("cue_target_locked", cue_target(True), "Two quick rising beeps.", "Auto-aim/target lock acquired.", -21.0, 75),
        ("cue_target_unlocked", cue_target(False), "Single falling blip.", "Target lock lost/released.", -24.0, 60),
        ("cue_ally_destroyed", cue_ally_destroyed, "Somber falling D4-A3 muted brass with low thud.", "Teammate destroyed.", -17.0, 88),
        ("cue_enemy_destroyed", cue_enemy_destroyed, "Punchy rising fifth A4-E5 with snap.", "Enemy destroyed (louder variant when it was your kill: +3 dB).", -16.0, 90),
        ("cue_objective_update", cue_objective_update, "D-F#-A chime and radio blip.", "Objective/mission progress updated in battle.", -18.0, 80),
    ]
    for key, fn, desc, ev, lvl, pri in cues:
        sound(key, "cues", fn, desc, ev, level=lvl, priority=pri)
    sound("cue_capture_warning_loop", "cues", cue_capture_warning_loop, "Two-tone pulse (A5/F5) alarm loop.",
          "Your base is being captured (loop while capture points > 0).", loop=True, loop_s=2.0, level=-19.0, priority=92)
    sound("cue_low_hp_heartbeat_loop", "cues", cue_low_hp_heartbeat, "Low heartbeat loop (75 bpm).",
          "Own HP below 15 % (volume rises as HP falls).", loop=True, loop_s=3.2, level=-21.0, priority=84)
    for name, (_, _, desc) in RADIO_PATTERNS.items():
        sound(f"radio_cmd_{name}", "radio", radio_command(name), f"Radio quick command: {desc} (chirp, static, tones, squelch; no speech).",
              f"Teammate issues the '{name}' quick command (pair with minimap ping).", level=-18.0, priority=80)
    sound("radio_static", "radio", radio_static, "Radio static burst with squelch tail.", "Generic radio chatter texture / comms noise.",
          variants="abc", level=-22.0, priority=40)


_register()
