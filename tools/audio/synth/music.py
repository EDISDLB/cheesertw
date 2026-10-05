"""Music: theory helpers, score data structures and the note renderer behind ``generate_music.py``.

A cue is written as *data*: tempo, meter, key, a list of :class:`Part` objects (instrument name,
parameters, mix level, stem) each holding :class:`Note` events in beats. Helpers turn compact
text into notes:

* :func:`seq`        melodic lines - ``"D4:.75 D4:.25 A4 Bb4:1.5 G4:.5 | A4:4"`` (durations in beats,
  default = previous duration, ``r`` = rest, ``+`` joins chord tones, ``!`` accent, ``?`` soft)
* :func:`hits`       drum grids - ``"X..x ..x. X.x. x..g"`` (one char per step; X/x/o/g = velocities)
* :func:`prog`       chord progressions - ``"Dm:2 Bb:2 | Gm:2 A:2"``
* :func:`chords`, :func:`bass`, :func:`arp`, :func:`ostinato` derive voiced parts from a progression
  with simple voice leading.

:func:`render_cue` renders every part, normalises each part to its mix level (integrated LUFS of
the dry part, so balance is set by numbers rather than instrument calibration), sums parts into
stems with a shared convolution reverb, and returns the stems. Loop cues are rendered *loop-safe*:
note tails, reverb tails and filter states wrap around the loop point (``place_wrapped``,
``convolve_circular``, ``mix.circular``), so the loop is periodic by construction and every stem
shares the same sample-exact beat grid.
"""

from __future__ import annotations

import itertools
import re
from dataclasses import dataclass, field
from fractions import Fraction

import numpy as np

from . import filters, instruments, mix, reverb
from .core import SR, make_rng, n_of

# --------------------------------------------------------------------------- pitch & theory

PITCH_CLASS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
NAMES_SHARP = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
NAMES_FLAT = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

SCALES = {
    "major": [0, 2, 4, 5, 7, 9, 11],
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "phrygian_dominant": [0, 1, 4, 5, 7, 8, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "harmonic_minor": [0, 2, 3, 5, 7, 8, 11],
    "pentatonic_minor": [0, 3, 5, 7, 10],
    "pentatonic_major": [0, 2, 4, 7, 9],
}

CHORD_QUALITIES = {
    "": [0, 4, 7], "m": [0, 3, 7], "dim": [0, 3, 6], "aug": [0, 4, 8], "5": [0, 7],
    "sus2": [0, 2, 7], "sus4": [0, 5, 7], "add9": [0, 4, 7, 14], "madd9": [0, 3, 7, 14],
    "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11],
    "m7b5": [0, 3, 6, 10], "dim7": [0, 3, 6, 9], "7sus4": [0, 5, 7, 10], "mmaj7": [0, 3, 7, 11],
    "maj9": [0, 4, 7, 11, 14], "m9": [0, 3, 7, 10, 14], "7b9": [0, 4, 7, 10, 13],
}


def pc_of(name: str) -> int:
    """Pitch class of a note name without octave (``"Bb"`` -> 10)."""
    pc = PITCH_CLASS[name[0].upper()]
    for ch in name[1:]:
        pc += 1 if ch == "#" else -1 if ch == "b" else 0
    return pc % 12


def midi(name: str) -> int:
    """MIDI number of ``"D4"``, ``"Bb3"``, ``"F#5"`` (C4 = 60)."""
    m = re.fullmatch(r"([A-Ga-g])([#b]*)(-?\d+)", name.strip())
    if not m:
        raise ValueError(f"bad note name {name!r}")
    pc = PITCH_CLASS[m.group(1).upper()] + m.group(2).count("#") - m.group(2).count("b")
    return 12 * (int(m.group(3)) + 1) + pc


def hz(m: float) -> float:
    return 440.0 * 2.0 ** ((float(m) - 69.0) / 12.0)


def name_of(m: int, flats: bool = True) -> str:
    return f"{(NAMES_FLAT if flats else NAMES_SHARP)[int(m) % 12]}{int(m) // 12 - 1}"


def parse_chord(sym: str) -> tuple[int, list[int], int | None]:
    """``"Bb/D"`` -> (root pc, intervals, bass pc or None)."""
    m = re.fullmatch(r"([A-G][#b]?)([a-z0-9#]*)(?:/([A-G][#b]?))?", sym.strip())
    if not m or m.group(2) not in CHORD_QUALITIES:
        raise ValueError(f"bad chord symbol {sym!r}")
    root = pc_of(m.group(1))
    return root, list(CHORD_QUALITIES[m.group(2)]), (pc_of(m.group(3)) if m.group(3) else None)


def chord_pcs(sym: str) -> list[int]:
    root, iv, _ = parse_chord(sym)
    return [(root + i) % 12 for i in iv]


def scale_pcs(tonic: str, mode: str) -> list[int]:
    t = pc_of(tonic)
    return [(t + s) % 12 for s in SCALES[mode]]


def voicing(sym: str, center: float, n: int = 4, prev: list[int] | None = None, lo: int | None = None,
            hi: int | None = None) -> list[int]:
    """Voice a chord with ``n`` notes near ``center`` (MIDI), minimising motion from ``prev``.

    Scoring favours complete chords (root, third, then fifth/extensions), avoids doubled thirds and
    close intervals in the low register (mud), and keeps the span within ~1.5 octaves."""
    root, iv, _ = parse_chord(sym)
    pcs = [(root + i) % 12 for i in iv]
    third = next(((root + i) % 12 for i in iv if i in (3, 4)), None)
    lo = int(center - 12) if lo is None else lo
    hi = int(center + 12) if hi is None else hi
    cands = [p for p in range(lo, hi + 1) if p % 12 in pcs]
    best, best_s = None, 1e18
    for combo in itertools.combinations(cands, min(n, len(cands))):
        got = [p % 12 for p in combo]
        s = 0.0
        if root not in got:
            s += 10
        if third is not None and third not in got:
            s += 8
        for pc in pcs:
            if pc not in got and pc not in (root, third):
                s += 3
        if third is not None and got.count(third) > 1:
            s += 4
        for a, b in zip(combo, combo[1:]):
            if b - a <= 2:
                s += 3 if a >= 55 else 6
            if a < 52 and b - a < 5:
                s += 4
        if combo[-1] - combo[0] > 19:
            s += (combo[-1] - combo[0] - 19) * 0.8
        if prev and len(prev) == len(combo):
            s += 0.45 * sum(abs(a - b) for a, b in zip(sorted(prev), combo))
        s += 0.25 * abs(float(np.mean(combo)) - center)
        if s < best_s:
            best, best_s = list(combo), s
    return best or []


# --------------------------------------------------------------------------- score data


@dataclass
class Note:
    beat: float
    dur: float
    pitch: float | None
    vel: float = 0.8
    params: dict = field(default_factory=dict)
    tag: str = ""


def _num(tok: str) -> float:
    return float(Fraction(tok)) if "/" in tok else float(tok)


def seq(text: str, start: float = 0.0, vel: float = 0.8, transpose: int = 0, tag: str = "",
        bar: float | None = None, **params) -> list[Note]:
    """Parse a melodic line. Tokens: ``NOTE[:dur][!|?]``, ``r[:dur]``, chord ``D4+F4+A4:2``.
    ``|`` marks bar lines; with ``bar`` (beats per bar) each completed bar is checked."""
    notes: list[Note] = []
    t = start
    dur = 1.0
    bar_start = start
    for tok in text.split():
        if tok == "|":
            if bar is not None and abs((t - bar_start) - bar) > 1e-6:
                raise ValueError(f"bar of {t - bar_start} beats (expected {bar}) before '|' in: {text}")
            bar_start = t
            continue
        accent = 0.0
        while tok and tok[-1] in "!?":
            accent += 0.15 if tok[-1] == "!" else -0.2
            tok = tok[:-1]
        name, _, d = tok.partition(":")
        if d:
            dur = _num(d)
        if name != "r":
            for nm in name.split("+"):
                notes.append(Note(t, dur, midi(nm) + transpose, float(np.clip(vel + accent, 0.05, 1.2)), dict(params), tag))
        t += dur
    return notes


def hits(pattern: str, start: float = 0.0, step: float = 0.25, pitch: float | None = None, vel: float = 1.0,
         dur: float | None = None, tag: str = "", **params) -> list[Note]:
    """Drum grid: one character per ``step`` beats; ``X``=1.0 ``x``=0.78 ``o``=0.55 ``g``=0.32
    (ghost) times ``vel``; ``.``/``-`` rest; spaces and ``|`` ignored."""
    vmap = {"X": 1.0, "x": 0.78, "o": 0.55, "g": 0.32}
    notes = []
    i = 0
    for ch in pattern:
        if ch in " |":
            continue
        if ch in vmap:
            notes.append(Note(start + i * step, dur if dur is not None else step, pitch, vmap[ch] * vel, dict(params), tag))
        elif ch not in ".-":
            raise ValueError(f"bad drum char {ch!r}")
        i += 1
    return notes


def prog(text: str, start: float = 0.0, default: float = 4.0) -> list[tuple[float, float, str]]:
    """``"Dm:2 Bb:2 | Gm A"`` -> [(beat, dur, symbol), ...]."""
    out = []
    t = start
    for tok in text.split():
        if tok == "|":
            continue
        sym, _, d = tok.partition(":")
        dur = _num(d) if d else default
        out.append((t, dur, sym))
        t += dur
    return out


def shift(notes: list[Note], beats: float) -> list[Note]:
    return [Note(n.beat + beats, n.dur, n.pitch, n.vel, dict(n.params), n.tag) for n in notes]


def transpose(notes: list[Note], semis: int) -> list[Note]:
    return [Note(n.beat, n.dur, None if n.pitch is None else n.pitch + semis, n.vel, dict(n.params), n.tag) for n in notes]


def repeat(notes: list[Note], times: int, period: float) -> list[Note]:
    out = []
    for i in range(times):
        out += shift(notes, i * period)
    return out


def scale_vel(notes: list[Note], factor: float = 1.0, curve=None) -> list[Note]:
    """Scale velocities by ``factor`` and optionally by ``curve(beat)`` (dynamics/crescendo)."""
    out = []
    for n in notes:
        g = factor * (curve(n.beat) if curve else 1.0)
        out.append(Note(n.beat, n.dur, n.pitch, float(np.clip(n.vel * g, 0.03, 1.25)), dict(n.params), n.tag))
    return out


def ramp(points):
    """Piecewise-linear dynamics curve over beats: ``ramp([(0, .5), (16, 1.0)])``."""
    xs = np.array([p[0] for p in points], dtype=float)
    ys = np.array([p[1] for p in points], dtype=float)
    return lambda b: float(np.interp(b, xs, ys))


def window(notes: list[Note], lo: float, hi: float) -> list[Note]:
    return [n for n in notes if lo - 1e-9 <= n.beat < hi - 1e-9]


def chords(progression, center: float, n: int = 4, vel: float = 0.7, legato: float = 1.0, lo=None, hi=None,
           **params) -> list[Note]:
    """Sustained voiced chords following ``progression`` with voice leading."""
    out, prev = [], None
    for beat, dur, sym in progression:
        v = voicing(sym, center, n, prev, lo, hi)
        prev = v
        for p in v:
            out.append(Note(beat, dur * legato, p, vel, dict(params)))
    return out


def bass(progression, octave: int = 2, pattern: str = "hold", vel: float = 0.8, step: float = 1.0,
         **params) -> list[Note]:
    """Bass notes on chord roots (or slash bass). ``pattern``: ``hold`` | ``pulse`` (every ``step``)
    | ``root5`` (alternating root/fifth every ``step``) | ``octaves`` (root / root+12)."""
    out = []
    for beat, dur, sym in progression:
        root, iv, b = parse_chord(sym)
        pc = b if b is not None else root
        base = 12 * (octave + 1) + pc
        if pattern == "hold":
            out.append(Note(beat, dur, base, vel, dict(params)))
            continue
        k = int(round(dur / step))
        for i in range(k):
            p = base
            if pattern == "root5" and i % 2:
                p = 12 * (octave + 1) + (root + 7) % 12
                if p < base - 5:
                    p += 12
            elif pattern == "octaves" and i % 2:
                p = base + 12
            out.append(Note(beat + i * step, step, p, vel * (1.0 if i == 0 else 0.85), dict(params)))
    return out


def arp(progression, center: float, cell, step: float = 0.5, n: int = 4, vel: float = 0.6, accent_first: float = 0.15,
        dur: float | None = None, **params) -> list[Note]:
    """Arpeggiate voiced chords: ``cell`` is a list of voice indices (0 = lowest; negative values
    count from the top; ``None`` = rest), cycled through each chord's duration."""
    out, prev = [], None
    for beat, cdur, sym in progression:
        v = voicing(sym, center, n, prev)
        prev = v
        k = int(round(cdur / step))
        for i in range(k):
            idx = cell[i % len(cell)]
            if idx is None:
                continue
            p = v[idx] if -len(v) <= idx < len(v) else v[idx % len(v)] + 12
            out.append(Note(beat + i * step, dur if dur is not None else step, p,
                            vel + (accent_first if i % len(cell) == 0 else 0.0), dict(params)))
    return out


def ostinato(progression, degrees, octave: int = 3, step: float = 0.25, vel: float = 0.7, accents=None,
             slash: bool = False, **params) -> list[Note]:
    """Rhythmic figure on each chord: ``degrees`` are semitone offsets from the chord root (or
    strings ``"r"`` root, ``"3"`` chord third, ``"5"`` fifth, ``"8"`` octave, ``"b2"`` etc.;
    ``None`` = rest). With ``slash`` the figure is built on the slash bass (pedal points)."""
    out = []
    for beat, dur, sym in progression:
        root, iv, sb = parse_chord(sym)
        if slash and sb is not None:
            root, iv = sb, [0, 3, 7]
        third = next((i for i in iv if i in (3, 4)), iv[1] if len(iv) > 1 else 0)
        fifth = next((i for i in iv if i in (6, 7, 8)), 7)
        named = {"r": 0, "3": third, "5": fifth, "8": 12, "b2": 1, "2": 2, "4": 5, "6": 9, "b6": 8, "b7": 10, "7": 11,
                 "-5": fifth - 12, "-r": -12, "10": third + 12}
        base = 12 * (octave + 1) + root
        if base > 12 * (octave + 1) + 6:
            base -= 12
        k = int(round(dur / step))
        for i in range(k):
            d = degrees[i % len(degrees)]
            if d is None:
                continue
            off = named[d] if isinstance(d, str) else d
            a = accents[i % len(accents)] if accents else 0.0
            out.append(Note(beat + i * step, step, base + off, float(np.clip(vel + a, 0.05, 1.2)), dict(params)))
    return out


def roll(start: float, dur: float, rate_per_beat: float, v0: float, v1: float, pitch: float | None = None,
         curve: float = 1.0, **params) -> list[Note]:
    """Drum roll: strokes every ``1/rate_per_beat`` beats with a velocity ramp v0 -> v1."""
    k = max(1, int(round(dur * rate_per_beat)))
    out = []
    for i in range(k):
        x = (i / max(1, k - 1)) ** curve
        out.append(Note(start + i / rate_per_beat, 1.0 / rate_per_beat, pitch, v0 + (v1 - v0) * x, dict(params)))
    return out


@dataclass
class Part:
    name: str
    inst: str
    notes: list[Note]
    params: dict = field(default_factory=dict)
    level: float = -20.0  # integrated loudness (LUFS) of the dry part within the cue
    pan: float = 0.0
    width: float = 1.0
    reverb: float = 0.25  # send to the cue's convolution reverb
    stem: str = "main"
    eq: tuple = ()  # (("hp", f), ("lp", f), ("peak", f, gain_db, q), ("lowshelf"|"highshelf", f, gain_db))
    humanize: float = 0.004  # timing jitter (s, std dev)
    vel_jitter: float = 0.04
    gate: float = 1.0  # sounding fraction of the written duration
    rr: int = 4  # round-robin renders cached per (pitch, duration, velocity, params)


@dataclass
class Cue:
    key: str
    title: str
    kind: str  # "loop" | "stinger"
    bpm: float
    beats_per_bar: float
    bars: int
    key_sig: str
    meter: str
    parts: list[Part]
    target_lufs: float
    description: str = ""
    state: str = ""
    space: str = "scoring_stage"
    reverb_wet: float = 1.0
    tail_s: float = 0.0
    group: str | None = None
    stems: tuple = ("main",)
    volume: float = 0.6
    meta: dict = field(default_factory=dict)

    @property
    def spb(self) -> float:
        """Samples per beat (exact for the tempi used: 60*SR/bpm is an integer)."""
        return 60.0 * SR / self.bpm

    @property
    def n_body(self) -> int:
        return int(round(self.bars * self.beats_per_bar * self.spb))


def motif_statements(cue: Cue, stem: str | None = None) -> list[dict]:
    """Statements of the HULLDOWN motif: contiguous runs of notes tagged ``motif*`` per part
    (only parts of ``stem`` when given)."""
    out = []
    for p in cue.parts:
        if stem is not None and p.stem != stem:
            continue
        tagged = sorted((n for n in p.notes if n.tag.startswith("motif")), key=lambda n: n.beat)
        end, tag = None, None
        for n in tagged:
            if end is None or n.beat > end + 1e-6 or n.tag != tag:
                out.append({"part": p.name, "form": n.tag, "bar": int(n.beat // cue.beats_per_bar) + 1,
                            "beat": round(n.beat % cue.beats_per_bar, 3) + 1,
                            "tonicPc": None if n.pitch is None else int(round(n.pitch)) % 12})
            end = max(end or 0.0, n.beat + n.dur) if n.tag == tag else n.beat + n.dur
            tag = n.tag
    return sorted(out, key=lambda d: (d["bar"], d["beat"], d["part"]))


# --------------------------------------------------------------------------- rendering


def _apply_eq(x: np.ndarray, eq, sr: int = SR) -> np.ndarray:
    for band in eq:
        kind = band[0]
        if kind == "hp":
            x = filters.highpass(x, band[1], band[2] if len(band) > 2 else 2, sr=sr)
        elif kind == "lp":
            x = filters.lowpass(x, band[1], band[2] if len(band) > 2 else 2, sr=sr)
        elif kind == "peak":
            x = filters.peaking(x, band[1], band[2], band[3] if len(band) > 3 else 1.0, sr)
        elif kind in ("lowshelf", "highshelf"):
            x = getattr(filters, kind)(x, band[1], band[2], sr=sr)
        else:
            raise ValueError(f"bad eq band {band!r}")
    return x


def _place_note(buf: np.ndarray, y: np.ndarray, pos: int, loop: bool) -> None:
    if loop:
        mix.place_wrapped(buf, y, pos)
    else:
        mix.place(buf, y, max(0, pos))


def render_part(part: Part, cue: Cue, n_buf: int, loop: bool) -> np.ndarray:
    """Render all notes of a part into a stereo buffer (wrapping tails when ``loop``)."""
    buf = np.zeros((n_buf, 2))
    spb = cue.spb
    hum = make_rng("hulldown-music", cue.key, part.name, "humanize")
    cache: dict = {}
    counts: dict = {}
    for i, note in enumerate(sorted(part.notes, key=lambda n: (n.beat, n.pitch or 0))):
        params = {**part.params, **note.params}
        gate = params.pop("gate", part.gate)
        dur_s = max(0.02, note.dur * gate * spb / SR)
        vel = float(np.clip(note.vel + hum.normal(0.0, part.vel_jitter), 0.03, 1.25)) if part.vel_jitter else note.vel
        vel = round(vel * 50.0) / 50.0
        ckey = (note.pitch, round(dur_s, 3), vel, tuple(sorted((k, str(v)) for k, v in params.items())))
        if part.rr:
            c = counts.get(ckey, 0)
            counts[ckey] = c + 1
            ckey = ckey + (c % part.rr,)
            y = cache.get(ckey)
        else:
            ckey = ckey + (i,)
            y = None
        if y is None:
            rng = make_rng("hulldown-music", cue.key, part.name, *ckey)
            f0 = None if note.pitch is None else hz(note.pitch)
            if "f0" in params:  # fixed tuning (Hz) given as a part/note parameter
                f0 = float(params.pop("f0")) if f0 is None else f0
                params.pop("f0", None)
            y = instruments.play(part.inst, rng, f0, dur_s, vel, SR, **params)
            if y.ndim == 1:
                y = mix.pan(y, part.pan) / np.sqrt(2.0)
            else:
                if part.width != 1.0:
                    y = mix.width(y, part.width)
                if part.pan:
                    g = np.array([np.cos((part.pan + 1) * np.pi / 4), np.sin((part.pan + 1) * np.pi / 4)]) * np.sqrt(2.0)
                    y = y * g[None, :]
            if part.rr:
                cache[ckey] = y
        pos = int(round(note.beat * spb))
        if part.humanize:
            pos += int(round(hum.normal(0.0, part.humanize) * SR))
        _place_note(buf, y, pos, loop)
    if part.eq:
        buf = mix.circular(lambda z: _apply_eq(z, part.eq), buf, 2) if loop else _apply_eq(buf, part.eq)
    return buf


def part_loudness(x: np.ndarray) -> float:
    return mix.loudness_integrated(x)


def render_cue(cue: Cue, log=None, parts_out: dict | None = None) -> dict[str, np.ndarray]:
    """Render a cue to its stems (dict stem -> stereo float array), before mastering.
    ``parts_out`` (optional dict) receives each part's dry, level-normalised buffer for analysis.

    Loops: every stem has exactly ``cue.n_body`` samples and is periodic. Stingers: the body plus
    ``cue.tail_s`` of ring-out."""
    loop = cue.kind == "loop"
    n_body = cue.n_body
    n_buf = n_body if loop else n_body + n_of(cue.tail_s)
    ir = reverb.impulse_response(cue.space, make_rng("hulldown-music", cue.key, "ir", cue.space), SR, stereo=True)
    dry = {s: np.zeros((n_buf, 2)) for s in cue.stems}
    send = {s: np.zeros((n_buf, 2)) for s in cue.stems}
    levels = {}
    for part in cue.parts:
        if part.stem not in dry:
            raise ValueError(f"{cue.key}: part {part.name} targets unknown stem {part.stem}")
        if not part.notes:
            continue
        x = render_part(part, cue, n_buf, loop)
        cur = part_loudness(x)
        if cur > -69.0:
            x = mix.gain_db(x, part.level - cur)
        levels[part.name] = round(cur, 1)
        if parts_out is not None:
            parts_out[part.name] = x
        dry[part.stem] += x
        if part.reverb:
            send[part.stem] += x * part.reverb
        if log:
            log(f"  {cue.key}: {part.name:18s} {part.inst:10s} notes {len(part.notes):4d}")
    stems = {}
    for s in cue.stems:
        if loop:
            wet = reverb.convolve_circular(send[s], ir, wet=1.0, dry=0.0)
        else:
            wet = reverb.convolve(send[s], ir, wet=1.0, dry=0.0, keep_length=True)
        stems[s] = dry[s] + cue.reverb_wet * wet
    cue.meta["partRawLufs"] = levels
    return stems


__all__ = [
    "Note", "Part", "Cue", "seq", "hits", "prog", "chords", "bass", "arp", "ostinato", "roll", "shift", "transpose",
    "repeat", "scale_vel", "ramp", "window", "voicing", "midi", "hz", "name_of", "parse_chord", "chord_pcs",
    "scale_pcs", "SCALES", "render_cue", "render_part", "motif_statements",
]
