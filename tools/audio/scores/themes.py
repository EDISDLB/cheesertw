"""Menu, garage, loading and results themes."""

from __future__ import annotations

from synth.music import Cue, Note, arp, bass, chords, hits, ostinato, prog, ramp, roll, scale_vel, seq, shift

from .common import B, P, brass, head, motif, pitched, strings, with_params


# =========================================================================== main theme
def main_theme() -> Cue:
    """Login / main menu: cinematic statement of the HULLDOWN motif. 72 BPM, 32 bars (106.7 s), loop."""
    bpb = 4
    intro = prog("Dm:4 | Bb/D:4 | Gm/D:4 | A:4")
    sec_a = prog("Dm:2 Bb:2 | Gm:2 A:2 | Dm:2 F:2 | Bbmaj7:2 C:2 | Gm:4 | Bb:2 F/A:2 | Gm:2 A7:2 | Dm:4", B(5))
    sec_b = prog("Dm:2 Bb:2 | Gm:2 A:2 | Dm:2 F:2 | Bbmaj7:2 C:2 | Gm:4 | Bb:2 F/A:2 | Gm:2 A7:2 | Dm:4", B(13))
    sec_c = prog("F:4 | C/E:4 | Dm:4 | Bb:4 | F/A:4 | Gm:2 C:2 | Bb:4 | A:4", B(21))
    sec_d = prog("Dm:2 Bb:2 | Gm:2 A:2 | Dm:4 | Dm:4", B(29))
    whole = intro + sec_a + sec_b + sec_c + sec_d

    a_mel = ("D4:3/4 D4:1/4 A4:1 Bb4:3/2 G4:1/2 | A4:4 | D4:3/4 D4:1/4 A4:1 C5:3/2 Bb4:1/2 | A4:2 G4:1 F4:1 | "
             "G4:3/2 A4:1/2 Bb4:1 G4:1 | F4:3/2 G4:1/2 A4:2 | Bb4:3/2 A4:1/2 G4:1 E4:1 | D4:4")
    c_mel = ("C5:3/2 D5:1/2 F5:2 | E5:3/2 D5:1/2 C5:2 | D5:1 F5:1 A5:2 | G5:3/2 F5:1/2 D5:2 | "
             "C5:3/2 D5:1/2 F5:2 | Bb4:1 D5:1 E5:1 G5:1 | F5:3/2 E5:1/2 D5:2 | E5:2 C#5:2")

    def tag_first_two_bars(notes, start):
        for n in notes:
            if start - 1e-9 <= n.beat < start + 8 - 1e-9:
                n.tag = "motif"
        return notes

    horn_a = tag_first_two_bars(seq(a_mel, B(5), vel=0.62, bar=4), B(5))
    horn_b = tag_first_two_bars(seq(a_mel, B(13), vel=0.86, bar=4), B(13))
    trp_b = tag_first_two_bars(seq(a_mel, B(13), vel=0.84, transpose=12, bar=4), B(13))
    horn_call = head(B(3), "D4", vel=0.4, last=2.0)  # distant call in the intro
    horn_aug = motif(B(25), "D4", scale=2.0, vel=0.66)  # augmentation under the bridge melody
    coda_trp = motif(B(29), "D5", vel=0.95)
    coda_horn = motif(B(29), "D4", vel=0.92)

    # strings
    basses = seq("D2:4 | D2:4 | D2:4 | A1:4 |"
                 " D2:2 Bb1:2 | G1:2 A1:2 | D2:2 F2:2 | Bb1:2 C2:2 | G1:4 | Bb1:2 A1:2 | G1:2 A1:2 | D2:4 |"
                 " D2:2 Bb1:2 | G1:2 A1:2 | D2:2 F2:2 | Bb1:2 C2:2 | G1:4 | Bb1:2 A1:2 | G1:2 A1:2 | D2:4 |"
                 " F1:4 | E1:4 | D2:4 | Bb1:4 | A1:4 | G1:2 C2:2 | Bb1:4 | A1:4 |"
                 " D2:2 Bb1:2 | G1:2 A1:2 | D2:4 | D2:4", 0.0, vel=0.62, bar=4)
    dyn = ramp([(0, 0.55), (B(5), 0.7), (B(13), 1.0), (B(21), 0.75), (B(29), 1.05), (B(31), 0.7), (B(33), 0.55)])
    basses = scale_vel(basses, 1.0, dyn)
    celli = shift(scale_vel(basses, 0.95), 0.0)
    celli = [Note(n.beat, n.dur, n.pitch + 12, n.vel, n.params, n.tag) for n in celli if n.beat >= B(5)]
    celli_intro = with_params(seq("D3:4 | D3:4 | D3:4 | C#3:4", 0.0, vel=0.42), art="tremolo")
    pad_lo = scale_vel(chords(sec_a + sec_b + sec_c + sec_d, 55, 3, vel=0.6), 1.0, dyn)
    halo = chords(sec_a, 74, 2, vel=0.33) + chords(sec_c, 72, 2, vel=0.42)
    vln_c = seq(c_mel, B(21), vel=0.68, bar=4)
    vln_coda = seq("D6:3/4 D6:1/4 A6:1 Bb6:3/2 G6:1/2 | A6:4", B(29), vel=0.8)
    vla_pulse = ostinato(sec_b, ["r", "5", "8", "5"], octave=3, step=0.5, vel=0.55, accents=[0.15, 0, 0.05, 0])

    # brass
    low_brass = chords(sec_b + sec_d[:4], 50, 3, vel=0.62)
    tuba = [n for n in basses if B(13) <= n.beat < B(21) or B(29) <= n.beat < B(31)]

    # choir
    choir_intro = chords(intro, 57, 4, vel=0.42) + chords(prog("Dm:4 | Dm:4", B(31)), 57, 4, vel=0.4)
    choir_c = chords(sec_c, 62, 4, vel=0.6)

    # percussion
    timp = []
    timp += pitched(hits("o", B(1), 1.0, vel=0.7), "D2")
    timp += roll(B(4), 4, 10, 0.18, 0.5, pitch=45)  # A2 roll into bar 5
    timp += pitched(hits("x", B(5)), "D2")
    timp += roll(B(12), 4, 10, 0.25, 0.85, pitch=45)
    for b in (13, 15, 17, 19):
        timp += pitched(hits("X.......o.......", B(b), 0.25, vel=0.85), "D2")
        timp += pitched(hits("........x.......", B(b + 1), 0.25, vel=0.8), "A2")
    timp += roll(B(28), 4, 10, 0.25, 0.95, pitch=45)
    timp += pitched(hits("X.......", B(29), 0.5), "D2") + pitched(hits("x...x...", B(30), 0.5), "G2")
    timp += pitched(hits("x", B(31)), "D2") + roll(B(31) + 1, 7, 9, 0.35, 0.08, pitch=38)

    march = "X..g x.g. x..g x.xx"
    march_fill = "X..g x.g. x.xx xxxx"
    snare_n = []
    for i, b in enumerate(range(13, 21)):
        pat = march_fill if b in (16, 19) else march
        snare_n += hits(pat, B(b), 0.25, vel=0.62 + 0.04 * (i % 4))
    snare_n += hits(march, B(29), 0.25, vel=0.85) + roll(B(30), 4, 8, 0.4, 1.0)
    bd = []
    for b in range(13, 21):
        bd += hits("X.......x.......", B(b), 0.25, vel=0.7)
    bd += hits("X.......x.......", B(29), 0.25, vel=0.9) + hits("X", B(31), vel=0.95)
    crash = hits("X", B(13), vel=0.75) + hits("X", B(29), vel=1.0) + hits("o", B(21), vel=0.5)
    swell = [Note(B(12) + 2, 2, None, 0.7), Note(B(28), 4, None, 0.85), Note(B(20) + 1, 3, None, 0.35)]
    bells = [Note(B(1), 2, 74, 0.45), Note(B(3), 2, 69, 0.35), Note(B(21), 2, 77, 0.4), Note(B(31), 2, 74, 0.4)]
    harp = arp(sec_c, 62, [0, 1, 2, 3, 2, 3, 1, 2], step=0.5, vel=0.45, dur=1.5)

    parts = [
        strings("basses", "basses", basses, -22.0, reverb=0.18, gate=0.97),
        strings("celli", "celli", celli, -23.5, reverb=0.2, gate=0.97),
        strings("celli_intro", "celli", celli_intro, -29.0, art="tremolo", reverb=0.3),
        strings("pad_violas", "violas", pad_lo, -23.0, reverb=0.3, gate=1.02),
        strings("violins_halo", "violins", halo, -28.0, reverb=0.4, gate=1.02, params={"bright": 0.8}),
        strings("violins_bridge", "violins", vln_c + vln_coda, -20.5, reverb=0.35),
        strings("violas_pulse", "violas", vla_pulse, -26.0, art="spiccato", reverb=0.25),
        brass("horn_solo", "horn", horn_call + horn_a, -20.0, reverb=0.4, params={"players": 2}),
        brass("horns", "horn", horn_b + horn_aug + coda_horn, -19.5, reverb=0.35),
        brass("trumpets", "trumpet", trp_b + coda_trp, -20.0, reverb=0.32),
        brass("low_brass", "trombone", low_brass, -24.0, reverb=0.3),
        brass("tuba", "tuba", tuba, -25.0, reverb=0.25),
        P("choir_oo", "choir", choir_intro, -28.0, params={"vowel": "oo"}, reverb=0.45),
        P("choir_ah", "choir", choir_c, -23.0, params={"vowel": "ah"}, reverb=0.45),
        P("timpani", "timpani", timp, -23.0, reverb=0.3, pan=-0.15, rr=6),
        P("snare", "snare", snare_n, -27.0, params={"kind": "military"}, reverb=0.22, pan=0.1),
        P("bass_drum", "bass_drum", bd, -26.0, reverb=0.3),
        P("crash", "cymbal", crash, -27.0, params={"kind": "crash"}, reverb=0.25),
        P("cym_swell", "cymbal", swell, -29.0, params={"kind": "swell"}, reverb=0.3, rr=0),
        P("bells", "bell", bells, -28.0, params={"kind": "tubular"}, reverb=0.45, pan=0.3),
        P("harp", "pluck", harp, -26.0, params={"kind": "harp"}, reverb=0.35, pan=-0.35),
    ]
    return Cue("main_theme", "HULLDOWN Main Theme", "loop", 72, bpb, 32, "D minor", "4/4", parts, -18.0,
               description="Login/main menu. Cinematic: distant horn call over a D pedal, horn statement of the motif, "
                           "full brass and military snare restatement, lyrical relative-major bridge with the motif "
                           "augmented in the horns, tutti coda that winds back into the intro.",
               state="MENU", volume=0.8, meta={"sections": {"intro": 1, "A": 5, "B": 13, "C": 21, "coda": 29}})


# =========================================================================== garage theme
def garage_theme() -> Cue:
    """Garage: calm military theme, 80 BPM, 44 bars (132 s), seamless loop."""
    bpb = 4
    vamp = "Dm9:4 | Bbmaj7:4 | F:4 | C:4 | Dm9:4 | Bbmaj7:4 | Gm7:4 | A7sus4:2 A7:2"
    intro = prog("Dm9:4 | Bbmaj7:4 | F:4 | C:4", B(1))
    a1 = prog(vamp, B(5))
    b_sec = prog("Gm7:4 | F/A:4 | Bbmaj7:4 | C:4 | Gm7:4 | Dm/F:4 | Ebmaj7:4 | A7sus4:2 A7:2", B(13))
    a2 = prog(vamp, B(21))
    c_sec = prog("Bbmaj7:4 | F/A:4 | Gm7:4 | Dm:4 | Bbmaj7:4 | F/A:4 | Gm7:4 | Asus4:2 A:2", B(29))
    a3 = prog(vamp, B(37))
    whole = intro + a1 + b_sec + a2 + c_sec + a3

    horn_mel = ("D4:3/4 D4:1/4 A4:1 Bb4:3/2 G4:1/2 | A4:4 | C5:3/2 Bb4:1/2 A4:1 F4:1 | G4:3 r:1 | "
                "D4:3/4 D4:1/4 A4:1 D5:3/2 C5:1/2 | A4:4 | Bb4:3/2 A4:1/2 G4:1 F4:1 | E4:3 C#4:1")

    def tag2(notes, start):
        for n in notes:
            if start - 1e-9 <= n.beat < start + 8 - 1e-9:
                n.tag = "motif"
        return notes

    horn1 = tag2(seq(horn_mel, B(5), vel=0.5, bar=4), B(5))
    horn2 = tag2(seq(horn_mel, B(21), vel=0.56, bar=4), B(21))
    horn3 = tag2(seq(horn_mel, B(37), vel=0.66, bar=4), B(37))
    vln_b = seq("Bb4:3/2 C5:1/2 D5:2 | C5:3/2 A4:1/2 F4:2 | D5:1 F5:1 A5:2 | G5:3/2 E5:1/2 C5:2 | "
                "Bb4:3/2 C5:1/2 D5:2 | F5:3/2 E5:1/2 D5:2 | G5:1 Bb5:1 D5:2 | D5:2 C#5:2", B(13), vel=0.55, bar=4)
    vln_counter = seq("F5:4 | D5:4 | C5:4 | E5:4 | F5:4 | D5:4 | D5:4 | C#5:4", B(21), vel=0.42, bar=4)
    vln_a3 = [Note(n.beat, n.dur, n.pitch + 12, n.vel * 0.85, n.params, n.tag) for n in horn3]
    celesta = motif(B(29), "D5", vel=0.55)
    flute_m = motif(B(33), "D5", vel=0.5)

    piano_cell = [0, 1, 2, 3, 2, 3, 1, 2]
    piano = (arp(intro, 60, piano_cell, 0.5, vel=0.42, dur=0.5, pedal=0.9)
             + arp(a1, 60, piano_cell, 0.5, vel=0.34, dur=0.5, pedal=0.9)
             + arp(a2, 60, piano_cell, 0.5, vel=0.36, dur=0.5, pedal=0.9)
             + arp(c_sec, 62, piano_cell, 0.5, vel=0.4, dur=0.5, pedal=0.9)
             + arp(a3, 60, piano_cell, 0.5, vel=0.36, dur=0.5, pedal=0.9))
    harp = arp(b_sec, 60, [0, 1, 2, 3, 1, 2, 3, 2], 0.5, vel=0.42, dur=1.5) + arp(a3, 64, [0, 2, 1, 3], 1.0, vel=0.35, dur=2)
    pad = chords(whole, 55, 3, vel=0.42, legato=1.02)
    pad = scale_vel(pad, 1.0, ramp([(0, 0.75), (B(13), 1.0), (B(29), 0.8), (B(37), 1.05), (B(44), 0.9)]))
    basses = bass(whole, 2, "hold", vel=0.45)
    pizz = bass(a2 + a3, 2, "root5", vel=0.6, step=1.0)
    brush = []
    for b in range(21, 29):
        brush += hits("x..g x.g. x..g x.g." if b % 4 else "x..g x.g. x.gg x.xg", B(b), 0.25, vel=0.42)
    for b in range(37, 44):
        brush += hits("x..g x.g. x..g x.g.", B(b), 0.25, vel=0.48)
    timp = pitched(hits("o", B(5), vel=0.5), "D2") + pitched(hits("o", B(21), vel=0.5), "D2") + \
        pitched(hits("o", B(37), vel=0.55), "D2") + roll(B(44) + 2, 2, 8, 0.15, 0.3, pitch=45)

    parts = [
        P("piano", "piano", piano, -21.0, reverb=0.3, pan=-0.1, rr=3),
        P("harp", "pluck", harp, -25.0, params={"kind": "harp"}, reverb=0.35, pan=-0.4),
        strings("pad", "violas", pad, -24.0, reverb=0.35, params={"bright": 0.75}),
        strings("basses", "basses", basses, -26.0, reverb=0.2),
        P("pizz", "pluck", pizz, -26.0, params={"kind": "bass_pizz"}, reverb=0.2, pan=0.3),
        brass("horn", "horn", horn1 + horn2 + horn3, -21.0, reverb=0.4, params={"players": 1}),
        strings("violins", "violins", vln_b + vln_counter + vln_a3, -23.0, reverb=0.35),
        P("celesta", "bell", celesta, -25.0, params={"kind": "celesta"}, reverb=0.4, pan=0.35),
        P("flute", "flute", flute_m, -24.0, reverb=0.4, pan=0.25),
        P("brush", "snare", brush, -31.0, params={"kind": "brush"}, reverb=0.2, pan=0.15),
        P("timpani", "timpani", timp, -28.0, reverb=0.3, pan=-0.15),
    ]
    return Cue("garage_theme", "Garage", "loop", 80, bpb, 44, "D minor", "4/4", parts, -20.0,
               description="Garage/hangar. Calm military theme: piano arpeggios over an i-VI-III-VII vamp, a solo horn "
                           "with the motif, a lyrical string section, brushed march snare, celesta and flute quoting "
                           "the motif, and a fuller final statement that returns to the piano intro.",
               state="GARAGE", volume=0.6, meta={"sections": {"intro": 1, "A1": 5, "B": 13, "A2": 21, "C": 29, "A3": 37}})


# =========================================================================== loading theme
def loading_theme() -> Cue:
    """Loading screen: tension build, 96 BPM, 20 bars (50 s), seamless loop (build -> hit -> rebuild)."""
    bpb = 4
    s1 = prog("Dm:4 | Dm:4 | Bb/D:4 | Gm/D:4", B(1))
    s2 = prog("Dm:4 | Bb:4 | Gm:4 | A:4", B(5))
    s3 = prog("Dm:4 | Bb:4 | Gm:4 | A:4", B(9))
    s4 = prog("Dm:4 | Eb:4 | Dm:4 | Eb:4", B(13))
    s5 = prog("Bb:4 | Gm:4 | Asus4:2 A:2 | A7:4", B(17))
    whole = s1 + s2 + s3 + s4 + s5
    pedal = seq("D2:4 | D2:4 | D2:4 | D2:4 | D2:4 | Bb1:4 | G1:4 | A1:4 | D2:4 | Bb1:4 | G1:4 | A1:4 | "
                "D2:4 | Eb2:4 | D2:4 | Eb2:4 | Bb1:4 | G1:4 | A1:4 | A1:4", 0, vel=0.55, bar=4)
    dyn = ramp([(0, 0.6), (B(5), 0.7), (B(9), 0.85), (B(13), 1.0), (B(17), 1.05), (B(18), 0.75), (B(21), 1.0)])
    pedal = scale_vel(pedal, 1.0, dyn)
    sub = scale_vel(bass(whole, 1, "pulse", vel=0.55, step=1.0, pluck=0.7), 1.0, dyn)
    ticks = []
    for b in range(1, 21):
        for i in range(8):
            ticks.append(Note(B(b) + i * 0.5, 0.25, 94.7 if i % 2 == 0 else 90.6, 0.55 if i % 2 == 0 else 0.4))
    ost_cell = "D3:1/2 D3 A3 D3 Bb3 A3 G3 A3"
    ost = []
    for b in range(5, 21):
        if b == 17:
            continue
        ost += seq(ost_cell, B(b), vel=0.58 + 0.03 * ((b - 5) // 4))
    vla16 = ostinato(s3 + s4 + s5[1:], ["r", "r", "5", "r", "3", "r", "5", "8"], octave=4, step=0.25, vel=0.5,
                     accents=[0.15, 0, 0, 0, 0.1, 0, 0, 0])
    harmonics = with_params(seq("A5:8 | Bb5:8 |", B(1), vel=0.4), art="flautando") + \
        with_params(seq("A5:4 | Bb5:4 | A5:4 | Bb5:4 | A5:4 | Bb5:4 | A5:4 | Bb5:4", B(9), vel=0.5), art="tremolo")
    choir = chords(s2 + s3, 52, 3, vel=0.5)
    horn_call = head(B(7), "D4", vel=0.45, last=2.0)
    trb_motif = motif(B(9), "D3", vel=0.75)
    menace = (head(B(13), "D3", vel=0.85, last=2.0) + head(B(14), "Eb3", vel=0.85, last=2.0)
              + head(B(15), "D3", vel=0.9, last=2.0) + head(B(16), "Eb3", vel=0.95, last=2.0))
    for n in menace:
        n.params = {"art": "stab"}
    hit17 = chords(prog("Bb:2", B(17)), 50, 3, vel=1.0)
    for n in hit17:
        n.params = {"art": "stab"}
    timp = pitched(hits("X", B(1), vel=0.9), "D2") + roll(B(4), 4, 8, 0.1, 0.45, pitch=38) + \
        roll(B(8), 4, 8, 0.15, 0.6, pitch=45) + roll(B(12), 4, 8, 0.2, 0.75, pitch=45) + \
        pitched(hits("X", B(17), vel=1.0), "Bb2") + roll(B(20), 4, 9, 0.2, 0.95, pitch=45)
    taiko = []
    for b in range(9, 13):
        taiko += hits("X.......x.......", B(b), 0.25, vel=0.7)
    for b in range(13, 17):
        taiko += hits("X.x.X.x.X.x.Xxxx" if b == 16 else "X...x.x.X...x...", B(b), 0.25, vel=0.85)
    taiko += hits("X", B(17), vel=1.0) + hits("x.......x.......", B(19), 0.25, vel=0.6) + \
        hits("X.x.X.x.XxxxXXXX", B(20), 0.25, vel=0.85)
    snare = roll(B(16), 4, 8, 0.1, 0.8) + roll(B(20), 4, 8, 0.1, 0.9)
    swell = [Note(B(16), 4, None, 0.7), Note(B(20), 4, None, 0.85)]
    crash = hits("X", B(17), vel=0.9) + hits("o", B(1), vel=0.5)
    shepard = [Note(i * 10.0, 80.0, None, 0.5) for i in range(8)]  # one octave per 4 bars; 8-octave grains

    parts = [
        strings("pedal_basses", "basses", pedal, -23.0, reverb=0.2),
        P("sub", "sub_bass", sub, -27.0, reverb=0.0),
        P("ticks", "clock_tick", ticks, -31.0, reverb=0.15, pan=0.25, rr=4),
        strings("ostinato_celli", "celli", ost, -23.0, art="spiccato", reverb=0.22),
        strings("ostinato_violas", "violas", vla16, -26.0, art="spiccato", reverb=0.25),
        strings("violins_high", "violins", harmonics, -28.0, reverb=0.45),
        P("choir", "choir", choir, -27.0, params={"vowel": "oo"}, reverb=0.45),
        brass("horn_call", "horn", horn_call, -25.0, reverb=0.45, params={"players": 2}),
        brass("trombones", "trombone", trb_motif + menace + hit17, -21.0, reverb=0.3),
        P("timpani", "timpani", timp, -23.0, reverb=0.3, pan=-0.1, rr=6),
        P("taiko", "taiko", taiko, -23.0, reverb=0.3, params={"f0": 55.0}),
        P("snare_roll", "snare", snare, -29.0, params={"kind": "field"}, reverb=0.25, pan=0.15, rr=8),
        P("cym_swell", "cymbal", swell, -28.0, params={"kind": "swell"}, reverb=0.3, rr=0),
        P("crash", "cymbal", crash, -28.0, params={"kind": "crash"}, reverb=0.25),
        P("riser", "shepard", shepard, -31.0, params={"f_lo": 35.0, "octaves": 8.0}, reverb=0.4, rr=0, humanize=0.0,
          vel_jitter=0.0),
    ]
    return Cue("loading_theme", "Loading", "loop", 96, bpb, 20, "D minor", "4/4", parts, -19.0,
               description="Battle loading screen. Tension build: ticking pulse, D pedal and an endless Shepard-Risset "
                           "riser; a motif ostinato in the celli, the horn call, trombone motif, then a menacing "
                           "D/Eb Phrygian section, a hit at bar 17 and a rebuild into the loop point.",
               state="LOADING", volume=0.7, meta={"sections": {"pedal": 1, "ostinato": 5, "motif": 9, "menace": 13, "hit": 17}})


# =========================================================================== results theme
def results_theme() -> Cue:
    """Post-battle results screen: calm and reflective, works after a win or a loss. 64 BPM, 16 bars (60 s)."""
    bpb = 4
    p1 = prog("Bbmaj7:4 | F/A:4 | Gm7:4 | Dm:4 | Bbmaj7:4 | F/A:4 | Gm7:4 | Asus4:2 A:2", B(1))
    p2 = prog("Dm:4 | Bb:4 | F:4 | C:4 | Gm7:4 | Dm/F:4 | Bbmaj7:4 | C:4", B(9))
    whole = p1 + p2
    piano = arp(whole, 60, [0, 1, 2, 3, 2, 1, 2, 3], 0.5, vel=0.4, dur=0.5, pedal=1.2)
    pad = chords(whole, 55, 3, vel=0.4, legato=1.02)
    halo = chords(p1 + p2[4:], 74, 2, vel=0.3)  # sounding across the loop point (bars 13-16 -> 1-8)
    basses = bass(whole, 2, "hold", vel=0.4)
    horn = motif(B(9), "D4", vel=0.45)
    flute = seq("A5:3/2 G5:1/2 F5:1 D5:1 | F5:2 E5:2", B(13), vel=0.45, bar=4)
    bells = [Note(B(9), 2, 69, 0.3)]
    timp = pitched(hits("o", B(9), vel=0.35), "D2")
    parts = [
        P("piano", "piano", piano, -21.0, reverb=0.32, pan=-0.1, rr=3),
        strings("pad", "violas", pad, -24.5, reverb=0.35, params={"bright": 0.7}),
        strings("halo", "violins", halo, -29.0, reverb=0.45, params={"bright": 0.7}),
        strings("basses", "basses", basses, -27.0, reverb=0.2),
        brass("horn", "horn", horn, -23.0, reverb=0.45, params={"players": 1}),
        P("flute", "flute", flute, -25.0, reverb=0.45, pan=0.25),
        P("bells", "bell", bells, -30.0, params={"kind": "tubular"}, reverb=0.5, pan=0.3),
        P("timpani", "timpani", timp, -30.0, reverb=0.3),
    ]
    return Cue("results_theme", "Results", "loop", 64, bpb, 16, "D minor / F major", "4/4", parts, -21.0,
               description="Results screen. Calm piano and strings in a Bb-F-Gm-Dm cycle, the motif softly on a solo "
                           "horn, a flute reply; neutral enough to follow victory, defeat or a draw.",
               state="RESULTS", volume=0.6)
