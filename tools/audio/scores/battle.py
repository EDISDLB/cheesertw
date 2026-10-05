"""Battle music: three sample-aligned intensity stems and the endgame loop.

All battle music is 120 BPM, 4/4, D minor, so stems and the endgame share one beat grid
(24000 samples per beat, 96000 per bar at 48 kHz) and the client can switch on bar lines.

Stems (one cue, three outputs, mastered together so base+mid+high is the full mix):

* ``base`` - low pulse: celli/basses 8ths with 3+3+2 accents, sub, taiko groove, timpani downbeats, tom fills
* ``mid``  - ostinato and harmony: violas 16ths, violins 8ths (later sections), horn chords, celli pad,
  trombone 3+3+2 stabs
* ``high`` - full drums (military snare, bass drum, crashes, swells, taiko fills), brass with the motif
  (stabs, countermelody, full statements, relative-major anthem), violins doubling, choir
"""

from __future__ import annotations

from synth.music import Cue, Note, chords, hits, ostinato, parse_chord, prog, ramp, roll, scale_vel, seq

from .common import B, P, brass, head, motif, pitched, strings, with_params

BPM = 120
BARS = 40

SEC_A = "Dm Bb Gm A Dm Bb Gm A"
SEC_B = "Dm C Bb A Dm C Bb:2 Gm:2 A"
SEC_C = "F C Gm Bb F C Bb A"
SEC_D = "Dm Eb/D Dm Eb/D Bb Gm Asus4:2 A:2 A7"


def _p(text: str, bar: int):
    return prog(" ".join(t if ":" in t else t + ":4" for t in text.split()), B(bar))


def battle() -> Cue:
    a1, b1, a2, c1, d1 = _p(SEC_A, 1), _p(SEC_B, 9), _p(SEC_A, 17), _p(SEC_C, 25), _p(SEC_D, 33)
    whole = a1 + b1 + a2 + c1 + d1
    sec_dyn = ramp([(0, 0.85), (B(9), 0.9), (B(17), 1.0), (B(25), 1.05), (B(33), 1.0), (B(41), 1.0)])

    # ------------------------------------------------------------------ base: low pulse + percussion
    acc8 = [0.3, -0.05, -0.05, 0.3, -0.05, -0.05, 0.25, -0.05]
    pulse_c = scale_vel(ostinato(whole, ["r"] * 8, octave=3, step=0.5, vel=0.62, accents=acc8, slash=True), 1.0, sec_dyn)
    pulse_b = scale_vel(ostinato(whole, ["r"] * 8, octave=2, step=0.5, vel=0.6, accents=acc8, slash=True), 1.0, sec_dyn)
    for n in pulse_c:
        if n.pitch >= 60:
            n.pitch -= 12
    for n in pulse_b:
        if n.pitch >= 48:
            n.pitch -= 12
    sub = []
    for beat, dur, sym in whole:
        root, _, sb = parse_chord(sym)
        pc = sb if sb is not None else root
        m = 24 + pc if pc >= 5 else 36 + pc  # F1..B1 or C2..E2
        sub.append(Note(beat, dur, m, 0.6))
    taiko = []
    for b in range(1, BARS + 1):
        pat = "X.....x.x......." if b % 2 else "X.....x.x...x.x."
        if b in (8, 16, 24, 32, 40):
            pat = "X.....x.x.x.xxxx"
        taiko += hits(pat, B(b), 0.25, vel=0.8)
    toms = []
    for b in (8, 16, 24, 32, 40):
        toms += pitched(hits("........x.x.x.xx", B(b), 0.25, vel=0.75), "A2")
        toms += pitched(hits("..............x.", B(b), 0.25, vel=0.8), "E2")
    timp = []
    for b, nm in ((1, "D2"), (9, "D2"), (17, "D2"), (25, "F2"), (33, "D2")):
        timp += pitched(hits("X", B(b), vel=0.9), nm)
    timp += roll(B(40) + 2, 2, 8, 0.25, 0.8, pitch=45)

    # ------------------------------------------------------------------ mid: ostinato + harmony
    cell16 = ["r", "r", "5", "r", "3", "r", "5", "r", "r", "r", "5", "r", "8", "5", "3", "5"]
    acc16 = [0.2, 0, 0, 0, 0.12, 0, 0, 0, 0.18, 0, 0, 0, 0.12, 0, 0, 0]
    vla = scale_vel(ostinato(whole, cell16, octave=4, step=0.25, vel=0.55, accents=acc16), 1.0, sec_dyn)
    for n in vla:
        if n.pitch > 72:
            n.pitch -= 12
    vln8 = ostinato(a2 + c1 + d1, ["8", "5", "10", "5"], octave=4, step=0.5, vel=0.5, accents=[0.12, 0, 0.06, 0])
    horns_pad = scale_vel(chords(whole, 57, 3, vel=0.5, legato=0.98), 1.0, sec_dyn)
    celli_pad = chords(whole, 50, 2, vel=0.5, legato=0.98, lo=43, hi=60)
    stab_cell = ["r"] + [None] * 5 + ["r"] + [None] * 5 + ["r"] + [None] * 3
    trb = ostinato(whole, stab_cell, octave=2, step=0.25, vel=0.62, accents=[0.2] + [0] * 15, slash=True)
    trb5 = ostinato(whole, [d if d is None else "5" for d in stab_cell], octave=2, step=0.25, vel=0.55, slash=True)

    # ------------------------------------------------------------------ high: drums, brass, motif
    trp, hrn, vln_hi, low_brass_hi = [], [], [], []
    # A (1-8): call stabs on the tonic and subdominant
    for b, ton in ((1, "D5"), (3, "G4"), (5, "D5"), (7, "G4")):
        trp += head(B(b), ton, vel=0.9, last=1.5)
        hrn += head(B(b), ton, vel=0.85, last=1.5, transpose=-12)
    # B (9-16): descending countermelody (horns, violins 8va)
    cm = seq("F4:4 | E4:4 | D4:4 | C#4:4 | F4:4 | G4:4 | F4:2 D4:2 | E4:4", B(9), vel=0.78, bar=4)
    hrn += cm
    vln_hi += [Note(n.beat, n.dur, n.pitch + 12, n.vel * 0.85) for n in cm]
    # A' (17-24): the motif in octaves
    mel_a2 = (motif(B(17), "D5", vel=0.95, last=2.0)
              + seq("F5:2 | Bb5:3/2 A5:1/2 G5:1 D5:1 | E5:2 C#5:2", B(18) + 2, vel=0.9)
              + motif(B(21), "D5", vel=0.95, last=2.0)
              + seq("F5:2 | G5:3/2 A5:1/2 Bb5:1 D6:1 | C#6:2 A5:2", B(22) + 2, vel=0.95))
    trp += mel_a2
    hrn += [Note(n.beat, n.dur, n.pitch - 12, n.vel * 0.95, {}, n.tag) for n in mel_a2]
    vln_hi += [Note(n.beat, n.dur, n.pitch, n.vel * 0.8) for n in mel_a2]
    # C (25-32): the motif shape in the relative major - the anthem
    anthem = (motif(B(25), "F4", form="major", vel=0.95, tag="motif_relmajor")
              + motif(B(27), "G4", form="prime", vel=0.95, tag="motif_transposed")
              + seq("F4:3/4 F4:1/4 C5:1 D5:3/2 E5:1/2 | F5:2 E5:2 | D5:3/2 E5:1/2 F5:2 | E5:2 C#5:2", B(29), vel=1.0,
                    bar=4))
    trp += anthem
    hrn += [Note(n.beat, n.dur, n.pitch, n.vel * 0.95, {}, n.tag) for n in anthem]
    vln_hi += [Note(n.beat, n.dur, n.pitch + 12, n.vel * 0.85) for n in anthem]
    low_brass_hi += chords(c1, 50, 3, vel=0.85)
    # D (33-40): menace - the call on D and on the Phrygian Eb, then the motif and turnaround
    for b, ton in ((33, "D3"), (34, "Eb3"), (35, "D3"), (36, "Eb3")):
        low_brass_hi += with_params(head(B(b), ton, vel=0.95, last=2.0), art="stab")
    trp += motif(B(37), "D5", vel=1.0) + seq("A5:2 G5:1 E5:1 | C#5:2 E5:1 G5:1", B(39), vel=0.95)
    hrn += motif(B(37), "D4", vel=0.95) + seq("A4:2 G4:1 E4:1 | C#4:2 E4:1 G4:1", B(39), vel=0.9)
    choir = chords(c1, 62, 4, vel=0.75) + chords(d1, 52, 3, vel=0.6)

    snare = []
    for b in range(1, BARS + 1):
        if b in (8, 16, 24, 32, 40):
            pat = "X.xxX.xxXxxxXXXX"
        elif 25 <= b <= 32:
            pat = "X.gxX.gxX.gxX.xx"
        else:
            pat = "x.g.X.g.x.g.X.gg" if b % 2 else "x.g.X.g.x.ggX.xx"
        snare += hits(pat, B(b), 0.25, vel=0.85)
    bd = []
    for b in range(1, BARS + 1):
        bd += hits("X.....x.X......." if 25 <= b <= 32 else "X.......X.......", B(b), 0.25, vel=0.8)
    crash = []
    for b in (1, 9, 17, 25, 33):
        crash += hits("X", B(b), vel=0.95)
    swells = [Note(B(b) + 2, 2, None, 0.8) for b in (8, 16, 24, 32, 40)]
    taiko_hi = []
    for b in range(33, 37):
        taiko_hi += hits("X.xxX.x.X.xxX.x.", B(b), 0.25, vel=0.75)
    for b in range(25, 33):
        taiko_hi += hits("x.x.x.x.x.x.x.x.", B(b), 0.25, vel=0.55)

    parts = [
        # base
        strings("pulse_celli", "celli", pulse_c, -22.0, art="spiccato", stem="base", reverb=0.15),
        strings("pulse_basses", "basses", pulse_b, -23.0, art="spiccato", stem="base", reverb=0.12),
        P("sub", "sub_bass", sub, -26.0, stem="base", reverb=0.0, params={"attack": 0.05, "release": 0.4}),
        P("taiko", "taiko", taiko, -21.0, stem="base", reverb=0.25, params={"f0": 55.0}, rr=6),
        P("toms", "tom", toms, -25.0, stem="base", reverb=0.25, pan=-0.2),
        P("timpani", "timpani", timp, -24.0, stem="base", reverb=0.3, pan=-0.15),
        # mid
        strings("ost_violas", "violas", vla, -22.5, art="spiccato", stem="mid", reverb=0.22),
        strings("ost_violins", "violins", vln8, -25.0, art="spiccato", stem="mid", reverb=0.25),
        brass("horn_chords", "horn", horns_pad, -23.5, stem="mid", reverb=0.32, gate=0.98),
        strings("celli_pad", "celli", celli_pad, -25.0, stem="mid", reverb=0.25),
        brass("trb_stabs", "trombone", trb + trb5, -24.5, art="staccato", stem="mid", reverb=0.25),
        # high
        brass("trumpets", "trumpet", trp, -19.5, stem="high", reverb=0.3),
        brass("horns", "horn", hrn, -20.5, stem="high", reverb=0.32),
        brass("low_brass", "trombone", low_brass_hi, -22.0, stem="high", reverb=0.28),
        strings("violins_hi", "violins", vln_hi, -22.5, stem="high", reverb=0.3),
        P("choir", "choir", choir, -24.0, stem="high", params={"vowel": "ah"}, reverb=0.4),
        P("snare", "snare", snare, -23.0, stem="high", params={"kind": "military"}, reverb=0.2, pan=0.1, rr=6),
        P("bass_drum", "bass_drum", bd, -24.0, stem="high", reverb=0.25),
        P("crash", "cymbal", crash, -25.0, stem="high", params={"kind": "crash"}, reverb=0.2),
        P("swell", "cymbal", swells, -27.0, stem="high", params={"kind": "swell"}, reverb=0.25),
        P("taiko_hi", "taiko", taiko_hi, -24.0, stem="high", params={"f0": 74.0, "size": 0.7}, reverb=0.25, pan=0.2),
    ]
    return Cue("battle", "Battle (stems)", "loop", BPM, 4, BARS, "D minor", "4/4", parts, -17.0,
               description="Battle stems for dynamic intensity: base (low pulse/percussion), mid (ostinato + harmony), "
                           "high (full drums, brass with the motif, choir). Same tempo, key and length; sample-aligned.",
               state="BATTLE", group="battle", stems=("base", "mid", "high"), volume=0.8,
               meta={"sections": {"A": 1, "B": 9, "A2": 17, "C": 25, "D": 33},
                     "stemDescriptions": {
                         "base": "Battle layer 1 (always on): celli/basses 8th-note pulse with 3+3+2 accents, sub, taiko "
                                 "groove, timpani on section downbeats, tom fills into each section.",
                         "mid": "Battle layer 2 (medium intensity): violas 16th ostinato, violins 8ths in later sections, horn "
                                "and celli harmony, trombone 3+3+2 stabs.",
                         "high": "Battle layer 3 (high intensity): military snare, bass drum, crashes and swells, taiko "
                                 "fills, brass with the motif (calls, countermelody, full statements, relative-major "
                                 "anthem, Phrygian menace), violins doubling, choir.",
                     }})


def battle_endgame() -> Cue:
    """Last two minutes / few tanks left: driving lament-bass loop. 120 BPM, 32 bars (64 s)."""
    p1 = _p("Dm Dm/C Gm/Bb A Dm Dm/C Bb A7", 1)
    p2 = _p("Dm Dm/C Gm/Bb A Dm Dm/C Bb A7", 9)
    p3 = _p("Dm Eb Dm Eb Bb C Asus4:2 A:2 A7", 17)
    p4 = _p("Dm Dm/C Gm/Bb A Dm Dm/C Bb A7", 25)
    whole = p1 + p2 + p3 + p4
    dyn = ramp([(0, 0.85), (B(9), 0.92), (B(17), 1.0), (B(25), 1.08), (B(33), 1.08)])
    acc = [0.3, 0, 0, 0.25, 0, 0, 0.25, 0, 0.3, 0, 0, 0.25, 0, 0, 0.2, 0]
    drive = scale_vel(ostinato(whole, ["r"] * 16, octave=2, step=0.25, vel=0.6, accents=acc, slash=True), 1.0, dyn)
    for n in drive:
        if n.pitch >= 50:
            n.pitch -= 12
    drive_hi = [Note(n.beat, n.dur, n.pitch + 12, n.vel * 0.9) for n in drive]
    vla = scale_vel(ostinato(whole, ["r", "5", "8", "5"], octave=3, step=0.25, vel=0.5, accents=[0.15, 0, 0.05, 0]), 1.0, dyn)
    trem = with_params(seq(" ".join(["A5:6 Bb5:2"] * 8), B(1), vel=0.45) + seq(" ".join(["A5:6 Bb5:2"] * 8), B(17), vel=0.55),
                       art="tremolo")
    sub = []
    for beat, dur, sym in whole:
        root, _, sb = parse_chord(sym)
        pc = sb if sb is not None else root
        sub.append(Note(beat, dur, (24 + pc) if pc >= 5 else (36 + pc), 0.6))
    ticks = []
    for b in range(1, 33):
        for i in range(8):
            ticks.append(Note(B(b) + i * 0.5, 0.25, 94.7 if i % 2 == 0 else 90.6, 0.6 if i % 2 == 0 else 0.45))
    taiko = []
    for b in range(1, 33):
        pat = "X.x.X.x.X.x.X.x." if b < 17 else "X.xxX.x.X.xxX.xx"
        if b % 8 == 0:
            pat = "X.xxX.xxXxxxXXXX"
        taiko += hits(pat, B(b), 0.25, vel=0.8)
    timp = []
    for b in range(17, 25):
        timp += pitched(hits("X.x.", B(b), 1.0, vel=0.85), "D2") + pitched(hits(".x.x", B(b), 1.0, vel=0.7), "A2")
    for b in (1, 9, 25):
        timp += pitched(hits("X", B(b), vel=0.95), "D2")
    snare = []
    for b in range(1, 33):
        if b % 4 == 0:
            snare += roll(B(b), 4, 8, 0.25, 0.95)
        else:
            snare += hits("....X.......X..g", B(b), 0.25, vel=0.8)
    crash = []
    for b in (1, 9, 17, 25):
        crash += hits("X", B(b), vel=0.95)
    swells = [Note(B(b) + 2, 2, None, 0.8) for b in (8, 16, 24, 32)]
    hrn = (motif(B(9), "D4", vel=0.9, last=2.0) + seq("F4:2 | Bb4:3/2 A4:1/2 G4:1 F4:1 | E4:4", B(10) + 2, vel=0.88)
           + motif(B(13), "D4", vel=0.92, last=2.0) + seq("F4:2 | D5:3/2 C5:1/2 Bb4:1 G4:1 | A4:2 C#5:2", B(14) + 2, vel=0.9))
    low = []
    for b, ton in ((17, "D3"), (18, "Eb3"), (19, "D3"), (20, "Eb3")):
        low += with_params(head(B(b), ton, vel=0.95, last=2.0), art="stab")
    trp = (motif(B(25), "D5", scale=2.0, vel=1.0)
           + motif(B(29), "D5", vel=1.0, last=2.0) + seq("F5:2 | D5:3/2 C5:1/2 Bb4:1 G4:1 | A4:2 C#5:1 E5:1", B(30) + 2, vel=0.95))
    hrn += [Note(n.beat, n.dur, n.pitch - 12, n.vel * 0.95, {}, n.tag) for n in trp]
    choir = chords(p1 + p2, 52, 3, vel=0.5) + chords(p3, 55, 3, vel=0.6) + chords(p4, 62, 4, vel=0.8)
    parts = [
        strings("drive_basses", "basses", drive, -22.0, art="spiccato", reverb=0.12),
        strings("drive_celli", "celli", drive_hi, -22.0, art="spiccato", reverb=0.15),
        strings("violas_16", "violas", vla, -24.5, art="spiccato", reverb=0.2),
        strings("violins_trem", "violins", trem, -26.0, reverb=0.35),
        P("sub", "sub_bass", sub, -26.0, reverb=0.0, params={"attack": 0.05, "release": 0.4}),
        P("ticks", "clock_tick", ticks, -27.0, reverb=0.12, pan=0.3),
        P("taiko", "taiko", taiko, -20.5, reverb=0.25, params={"f0": 55.0}, rr=6),
        P("timpani", "timpani", timp, -23.0, reverb=0.3, pan=-0.15, rr=6),
        P("snare", "snare", snare, -24.0, params={"kind": "military"}, reverb=0.2, pan=0.1, rr=8),
        P("crash", "cymbal", crash, -25.5, params={"kind": "crash"}, reverb=0.2),
        P("swell", "cymbal", swells, -27.0, params={"kind": "swell"}, reverb=0.25),
        brass("horns", "horn", hrn, -20.5, reverb=0.32),
        brass("trumpets", "trumpet", trp, -20.0, reverb=0.3),
        brass("low_brass", "trombone", low, -21.5, reverb=0.28),
        P("choir", "choir", choir, -23.5, params={"vowel": "ah"}, reverb=0.4),
    ]
    return Cue("battle_endgame", "Battle Endgame", "loop", BPM, 4, 32, "D minor", "4/4", parts, -17.0,
               description="Endgame (last 2 minutes or few tanks left): 16th-note lament-bass drive (D-C-Bb-A), "
                           "ticking clock, timpani ostinato, Phrygian D/Eb menace, the motif augmented in the "
                           "trumpets over full choir. Same tempo/key/grid as the battle stems.",
               state="BATTLE_ENDGAME", volume=0.85, meta={"sections": {"lament": 1, "motif": 9, "menace": 17, "climax": 25}})
