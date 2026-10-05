"""The HULLDOWN motif and shared score helpers.

The motif ("the HULLDOWN call") - two bars of 4/4 in D minor::

    D4 (dotted 8th)  D4 (16th)  A4 (quarter)  Bb4 (dotted quarter)  G4 (8th)  |  A4 (whole)
    degrees 1 1 5 b6 4 5

* the dotted pickup on the tonic is a bugle/drum call (military),
* the rising fifth is the heroic gesture,
* the minor sixth leaning back to the fifth through the fourth is the somber sigh,
* it ends open, on the dominant: the fight is not over.

Every cue quotes it (prime, major, Lydian, relative-major or Phrygian-coloured forms, augmented,
3/4 and 6/8 rhythms, or the three-note "call" head) and tags those notes ``motif*`` so the
catalogue can list where it is stated.
"""

from __future__ import annotations

from synth.music import Note, Part, midi

MOTIF_STEPS = {
    "prime": [0, 0, 7, 8, 5, 7],      # aeolian: 1 1 5 b6 4 5
    "major": [0, 0, 7, 9, 5, 7],      # raised sixth (victory, plains, harbor dorian)
    "lydian": [0, 0, 7, 9, 6, 7],     # raised fourth (mountain pass)
    "descent": [0, 0, 7, 8, 7, 5],    # sighs downward (defeat)
}
RHYTHMS = {
    "4/4": [0.75, 0.25, 1.0, 1.5, 0.5, 4.0],
    "3/4": [0.75, 0.25, 2.0, 2.0, 1.0, 3.0],
    "6/8": [0.75, 0.25, 0.5, 1.0, 0.5, 3.0],
}
MOTIF_TEXT = "D4:3/4 D4:1/4 A4:1 Bb4:3/2 G4:1/2 | A4:4"


def B(bar: int, bpb: float = 4.0) -> float:
    """Beat offset of 1-indexed ``bar``."""
    return (bar - 1) * bpb


def motif(start: float, tonic: str = "D4", form: str = "prime", meter: str = "4/4", scale: float = 1.0,
          vel: float = 0.85, last: float | None = None, transpose: int = 0, tag: str | None = None,
          steps=None, **params) -> list[Note]:
    """Full motif statement starting at beat ``start``; ``scale`` = 2 gives the augmentation."""
    root = midi(tonic) + transpose
    st = steps if steps is not None else MOTIF_STEPS[form]
    rh = [d * scale for d in RHYTHMS[meter]]
    if last is not None:
        rh[-1] = last
    tg = tag or ("motif_aug" if scale > 1.5 else "motif")
    out, t = [], start
    for i, (s, d) in enumerate(zip(st, rh)):
        accent = 0.12 if i in (0, 2) else (-0.05 if i == 1 else 0.0)
        out.append(Note(t, d, root + s, min(1.2, vel + accent), dict(params), tg))
        t += d
    return out


def head(start: float, tonic: str = "D4", meter: str = "4/4", scale: float = 1.0, vel: float = 0.85,
         last: float | None = None, transpose: int = 0, **params) -> list[Note]:
    """The three-note call (1 1 5) - used as stabs, fragments and echoes."""
    n = motif(start, tonic, "prime", meter, scale, vel, None, transpose, "motif_head", **params)[:3]
    if last is not None:
        n[-1].dur = last
    return n


def P(name: str, inst: str, notes, level: float, stem: str = "main", **kw) -> Part:
    params = kw.pop("params", {})
    return Part(name, inst, list(notes), params=params, level=level, stem=stem, **kw)


def strings(name: str, section: str, notes, level: float, art: str = "legato", stem: str = "main", **kw) -> Part:
    params = {"section": section, "art": art}
    params.update(kw.pop("params", {}))
    return Part(name, "strings", list(notes), params=params, level=level, stem=stem, **kw)


def brass(name: str, kind: str, notes, level: float, art: str = "sustain", stem: str = "main", **kw) -> Part:
    params = {"kind": kind, "art": art}
    params.update(kw.pop("params", {}))
    return Part(name, "brass", list(notes), params=params, level=level, stem=stem, **kw)


def with_params(notes, **params) -> list[Note]:
    out = []
    for n in notes:
        q = dict(n.params)
        q.update(params)
        out.append(Note(n.beat, n.dur, n.pitch, n.vel, q, n.tag))
    return out


def pitched(notes, name: str) -> list[Note]:
    """Give unpitched hits a fixed pitch (e.g. timpani tuning or clock tick frequency)."""
    m = midi(name)
    return [Note(n.beat, n.dur, m, n.vel, dict(n.params), n.tag) for n in notes]


def hz_to_midi(f: float) -> float:
    import math

    return 69.0 + 12.0 * math.log2(f / 440.0)


def tremolo(notes, step: float = 0.25, accent: float = 0.08) -> list[Note]:
    """Split each note into repeated strokes (mandolin/oud tremolo); tags are preserved."""
    out = []
    for n in notes:
        k = max(1, int(round(n.dur / step)))
        for i in range(k):
            out.append(Note(n.beat + i * step, step, n.pitch, n.vel + (accent if i % 2 == 0 else -accent), dict(n.params), n.tag))
    return out


def comp(progression, offsets, center: float, n: int = 3, dur: float = 0.5, vel: float = 0.5, **params) -> list[Note]:
    """Chordal comping: the voiced chord struck at each offset (beats) within every chord span."""
    from synth.music import voicing

    out, prev = [], None
    for beat, cdur, sym in progression:
        v = voicing(sym, center, n, prev)
        prev = v
        for off in offsets:
            if off < cdur - 1e-9:
                for p in v:
                    out.append(Note(beat + off, dur, p, vel, dict(params)))
    return out


def harmonic(partial: int, fundamental: str = "D2") -> float:
    """MIDI pitch (fractional) of a natural-harmonic partial, e.g. the alphorn's 7th and 11th."""
    import math

    return midi(fundamental) + 12.0 * math.log2(partial)
