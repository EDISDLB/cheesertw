"""Result stingers: victory, defeat, draw (one-shots that end on a held chord and ring out)."""

from __future__ import annotations

from synth.music import Cue, Note, bass, chords, hits, prog, roll, seq

from .common import B, P, brass, head, motif, pitched, strings, with_params


def victory() -> Cue:
    """D major fanfare on the motif. 80 BPM, 8 bars (24 s) + 4.5 s ring-out."""
    harm = prog("A:4 | D:2 G:2 | Em:2 A:2 | D:2 Bm:2 | G:2 A:2 | G:2 D/F#:2 | Em:2 A:2 | D:4", B(1))
    mel = (motif(B(2), "D5", form="major", vel=0.95)
           + seq("D5:3/4 D5:1/4 A5:1 D6:3/2 C#6:1/2 | B5:2 A5:2 | B5:3/2 A5:1/2 G5:1 F#5:1 | E5:2 A5:2 | D6:4",
                 B(4), vel=1.0, bar=4))
    horns = [Note(n.beat, n.dur, n.pitch - 12, n.vel * 0.95, {}, n.tag) for n in mel]
    vln = [Note(n.beat, n.dur, n.pitch + 12 if n.pitch < 84 else n.pitch, n.vel * 0.8) for n in mel]
    trem = with_params(seq("A4:4", B(1), vel=0.6) + seq("A5:4", B(1), vel=0.55), art="tremolo")
    pad = chords(harm[1:], 57, 4, vel=0.75)
    low = chords(harm[1:], 48, 3, vel=0.8)
    bs = seq("A1:4 | D2:2 G1:2 | E2:2 A1:2 | D2:2 B1:2 | G1:2 A1:2 | G1:2 F#1:2 | E1:2 A1:2 | D2:4", B(1), vel=0.8, bar=4)
    timp = roll(B(1), 4, 8, 0.15, 0.9, pitch=45) + pitched(hits("X...x...", B(2), 0.5), "D2") + \
        pitched(hits("x...", B(3) + 2, 0.5), "A2") + pitched(hits("X", B(4)), "D2") + \
        pitched(hits("X", B(6)), "G2") + roll(B(7) + 2, 2, 8, 0.4, 0.9, pitch=45) + pitched(hits("X", B(8), vel=1.0), "D2") + \
        roll(B(8), 4, 9, 0.6, 0.25, pitch=38)
    snare = roll(B(1), 4, 8, 0.15, 0.95) + hits("X..x x.x. X..x X...", B(2), 0.25) + hits("X..x x.x. X..x x.xx", B(4), 0.25) + \
        hits("X..x x.x. X..x x.x.", B(6), 0.25) + roll(B(7) + 2, 2, 8, 0.5, 1.0) + hits("X", B(8))
    crash = hits("X", B(2)) + hits("x", B(4)) + hits("X", B(8))
    swell = [Note(B(1), 4, None, 0.85)]
    bells = [Note(B(8), 4, 74, 0.7), Note(B(8), 4, 81, 0.5)]
    choir = chords(prog("D:4", B(8)), 64, 4, vel=0.85)
    parts = [
        brass("trumpets", "trumpet", mel, -16.5, reverb=0.28),
        brass("horns", "horn", horns, -18.0, reverb=0.3),
        strings("violins", "violins", vln, -21.0, reverb=0.3),
        strings("tremolo", "violins", trem, -24.0, art="tremolo", reverb=0.3),
        strings("pad", "violas", pad, -21.5, reverb=0.3),
        brass("low_brass", "trombone", low, -21.5, reverb=0.28),
        strings("basses", "basses", bs, -22.0, reverb=0.2),
        P("timpani", "timpani", timp, -20.5, reverb=0.3, pan=-0.15, rr=6),
        P("snare", "snare", snare, -23.0, params={"kind": "military"}, reverb=0.2, pan=0.1, rr=8),
        P("crash", "cymbal", crash, -23.0, params={"kind": "crash"}, reverb=0.2),
        P("swell", "cymbal", swell, -25.0, params={"kind": "swell"}, reverb=0.25, rr=0),
        P("bells", "bell", bells, -24.0, params={"kind": "tubular"}, reverb=0.35, pan=0.3),
        P("choir", "choir", choir, -22.0, params={"vowel": "ah"}, reverb=0.4),
    ]
    return Cue("victory", "Victory", "stinger", 80, 4, 8, "D major", "4/4", parts, -16.0, tail_s=4.5,
               description="Victory: snare and timpani roll on the dominant, the motif as a D-major brass fanfare, "
                           "a rising answer, and a held tutti D-major chord with bells and choir.",
               state="RESULT_STINGER", volume=0.9)


def defeat() -> Cue:
    """Somber minor: solo horn states the motif and cannot finish it. 60 BPM, 6 bars (24 s) + 4.5 s."""
    harm = prog("Dm:2 Bb/D:2 | Gm/D:2 A7/C#:2 | Dm:2 Gm/Bb:2 | Bb:2 Gm:2 | Gm:2 Asus4:2 | Dm:4", B(1))
    horn = seq("D4:3/4 D4:1/4 A4:1 Bb4:2 | A4:3/2 G4:1/2 F4:1 E4:1 | D4:2 r:2 | D4:3/4 D4:1/4 A4:2 r:1 | "
               "Bb4:2 A4:2", B(1), vel=0.6, bar=4)
    for n in horn[:4]:
        n.tag = "motif_lament"  # the call and the minor sixth, then it falls instead of rising
    for n in horn[9:12]:
        n.tag = "motif_head"
    cello = seq("r:2 E4:1 C#4:1 | D4:2 Bb3:2 | F3:1 D3:1 G3:2 | Bb3:2 A3:2 | D3:4", B(2), vel=0.5, bar=4)
    pad = chords(harm, 55, 3, vel=0.45)
    bs = seq("D2:4 | D2:2 C#2:2 | D2:2 Bb1:2 | Bb1:2 G1:2 | G1:2 A1:2 | D1:4", B(1), vel=0.5, bar=4)
    choir = chords(harm, 52, 3, vel=0.42)
    timp = pitched(hits("o", B(1), vel=0.6), "D2") + pitched(hits("o", B(6), vel=0.55), "D2") + \
        roll(B(6) + 0.5, 3.5, 6, 0.3, 0.05, pitch=38)
    for n in timp:
        n.params = {"muffle": True}
    bells = [Note(B(5), 4, 62, 0.45), Note(B(6), 4, 62, 0.4)]
    parts = [
        brass("horn", "horn", horn, -18.5, reverb=0.45, params={"players": 1}),
        strings("cello_solo", "celli", cello, -21.0, reverb=0.35, params={"players": 2}),
        strings("pad", "violas", pad, -23.5, reverb=0.4, params={"bright": 0.65}),
        strings("basses", "basses", bs, -23.0, reverb=0.25),
        P("choir", "choir", choir, -25.0, params={"vowel": "oo"}, reverb=0.5),
        P("timpani", "timpani", timp, -24.0, reverb=0.3, rr=4),
        P("bells", "bell", bells, -26.0, params={"kind": "tubular"}, reverb=0.5, pan=0.3),
    ]
    return Cue("defeat", "Defeat", "stinger", 60, 4, 6, "D minor", "4/4", parts, -18.0, tail_s=4.5,
               description="Defeat: a lone horn states the motif and sighs downward; it tries the call again but "
                           "stalls on Bb-A over a muffled timpani, a distant bell and a dark choir; ends on D minor.",
               state="RESULT_STINGER", volume=0.85)


def draw() -> Cue:
    """Neither major nor minor: the motif over suspended chords, ending on an open fifth. 72 BPM, 4 bars + 3.5 s."""
    harm = prog("Dsus2:2 Bbsus2:2 | Gsus2:2 Asus4:2 | Dsus2:4 | D5:4", B(1))
    horn = motif(B(1), "D4", vel=0.65)
    echo = head(B(3), "D5", vel=0.45, last=2.0)
    pad = chords(harm, 57, 3, vel=0.5)
    bs = seq("D2:2 Bb1:2 | G1:2 A1:2 | D2:4 | D2:4", B(1), vel=0.55, bar=4)
    fifth = seq("D3+A3:4", B(4), vel=0.6)
    timp = pitched(hits("o", B(1), vel=0.55), "D2") + roll(B(4), 4, 8, 0.25, 0.1, pitch=38)
    parts = [
        brass("horn", "horn", horn, -19.0, reverb=0.4, params={"players": 2}),
        strings("echo", "violins", echo, -22.5, reverb=0.45),
        strings("pad", "violas", pad, -22.0, reverb=0.35),
        strings("basses", "basses", bs, -23.0, reverb=0.25),
        brass("open_fifth", "trombone", fifth, -22.0, reverb=0.35),
        P("timpani", "timpani", timp, -25.0, reverb=0.3, rr=4),
    ]
    return Cue("draw", "Draw", "stinger", 72, 4, 4, "D (open)", "4/4", parts, -18.5, tail_s=3.5,
               description="Draw: the motif in the horns over suspended harmony (sus2/sus4), a soft echo of the call, "
                           "ending on a bare D-A fifth - neither major nor minor.",
               state="RESULT_STINGER", volume=0.8)
