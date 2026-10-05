"""Map identity stingers for loading screens (10-20 s each).

Each map quotes the HULLDOWN motif in an instrumentation and mode that matches its biome:

==================  ==========================================================================
iron_valley         industrial: anvils on 3+3+2, low brass motif, Phrygian Eb menace, taiko
dust_basin          Phrygian dominant (Hijaz): oud with tremolo, duduk, maqsum frame drum
frozen_front        glassy celesta + glass bells, airy choir "oo", harmonics, cathedral reverb
old_fortress        D Dorian organum: male choir in parallel fifths, organ, church bell, timpani
harbor_district     6/8 sway in D Dorian: accordion, pizzicato bass, low "foghorn" tuba, buoy bell
mountain_pass       alphorn on natural harmonics (7th partial) with valley echo, Lydian answer
river_town          3/4 waltz: mandolin tremolo, accordion oom-pah-pah, church bell
open_plains         D Mixolydian: open-string guitar, wide strings, horn in major, soft timpani
==================  ==========================================================================
"""

from __future__ import annotations

from synth.music import Cue, Note, arp, bass, chords, hits, prog, roll, seq

from .common import B, P, brass, comp, harmonic, head, motif, pitched, strings, tremolo, with_params


def _cue(key, title, bpm, bpb, bars, key_sig, meter, parts, desc, tail=3.0, space="scoring_stage", target=-18.0, map_id=None,
         biome=None):
    return Cue(key, title, "stinger", bpm, bpb, bars, key_sig, meter, parts, target, tail_s=tail, space=space,
               description=desc, state="LOADING_MAP_STINGER", volume=0.8, meta={"map": map_id, "biome": biome})


def iron_valley() -> Cue:
    harm = prog("Dm:4 | Bb:4 | Eb/D:4 | A7:4 | Dm:4")
    anv = []
    for b in range(1, 5):
        anv += with_params(hits("X.....x.....x...", B(b), 0.25, vel=0.8), f0=1050.0)
        anv += with_params(hits("..........o.....", B(b), 0.25, vel=0.6), f0=1420.0)
    anv += with_params(hits("X", B(5), vel=1.0), f0=1050.0)
    pulse = []
    for b in range(1, 5):
        root = {1: "D2", 2: "Bb1", 3: "D2", 4: "A1"}[b]
        pulse += seq(" ".join([f"{root}:1/2"] * 8), B(b), vel=0.6)
    low = motif(B(1), "D3", vel=0.9)
    menace = with_params(head(B(3), "Eb4", vel=0.9, last=2.0), art="stab")
    stab4 = with_params(chords(prog("A7:2", B(4)), 60, 4, vel=0.9), art="stab")
    hit = with_params(chords(prog("Dm:2", B(5)), 50, 4, vel=1.0), art="stab")
    taiko = []
    for b in range(1, 5):
        taiko += hits("X.......x.....x." if b < 4 else "X.......X.x.XxXx", B(b), 0.25, vel=0.85)
    taiko += hits("X", B(5))
    timp = pitched(hits("X", B(5)), "D2") + roll(B(4) + 2, 2, 8, 0.3, 0.9, pitch=45)
    crash = hits("X", B(5))
    parts = [
        P("anvil", "anvil", anv, -22.0, reverb=0.3, pan=0.25),
        strings("pulse", "celli", pulse, -21.0, art="spiccato", reverb=0.15),
        brass("low_brass", "trombone", low + hit, -18.5, reverb=0.3),
        brass("tuba", "tuba", [Note(n.beat, n.dur, n.pitch - 12, n.vel) for n in low], -22.0, reverb=0.25),
        brass("horns", "horn", menace + stab4, -20.0, reverb=0.3),
        strings("pad", "violas", chords(harm, 57, 3, vel=0.55), -24.0, reverb=0.3),
        P("taiko", "taiko", taiko, -20.0, reverb=0.3, params={"f0": 55.0}),
        P("timpani", "timpani", timp, -22.0, reverb=0.3, rr=6),
        P("crash", "cymbal", crash, -24.0, params={"kind": "crash"}, reverb=0.2),
    ]
    return _cue("map_iron_valley", "Iron Valley", 100, 4, 5, "D minor (Phrygian)", "4/4", parts,
                "Industrial valley: anvils on a 3+3+2 grid, the motif in trombones and tuba over a celli pulse, a "
                "Phrygian Eb call in the horns, and a tutti D-minor hit.", map_id="iron_valley",
                biome="temperate_valley_industrial")


def dust_basin() -> Cue:
    harm = prog("D:4 | Gm:4 | Cm:2 D:2 | Eb:1 D:3 | D:4")
    m = motif(B(1), "D4", vel=0.85)
    oud = m[:-1] + tremolo([m[-1]], 0.25)
    oud += seq("A4:1 Bb4:1/2 A4:1/2 G4:1 F#4:1 | Eb4:1 F#4:1 D4:2 | D4+A4:1/2 r:1/2 D4+A4:1/2", B(3), vel=0.8)
    duduk = seq("D3:8", B(1), vel=0.55) + seq("A4:1 Bb4:1/2 A4:1/2 G4:1 F#4:1 | Eb4:1 F#4:1 D4:6", B(3), vel=0.7)
    doum, tek = [], []
    for b in range(1, 5):
        doum += hits("X.......X.......", B(b), 0.25, vel=0.85)
        tek += hits("..x...x.....x..g" if b % 2 else "..x...x.....x.xx", B(b), 0.25, vel=0.7)
    doum += hits("X", B(5))
    pad = chords(harm, 52, 2, vel=0.45)
    parts = [
        P("oud", "pluck", oud, -19.0, params={"kind": "oud"}, reverb=0.25, pan=-0.2),
        P("duduk", "reed", duduk, -20.0, params={"kind": "duduk"}, reverb=0.3, pan=0.15, gate=0.98),
        P("doum", "frame_drum", doum, -22.0, params={"stroke": "doum"}, reverb=0.2),
        P("tek", "frame_drum", tek, -25.0, params={"stroke": "tek"}, reverb=0.2, pan=0.25),
        strings("pad", "celli", pad, -26.0, reverb=0.3),
    ]
    return _cue("map_dust_basin", "Dust Basin", 90, 4, 5, "D Phrygian dominant", "4/4", parts,
                "Desert basin: the motif on an oud (with tremolo on the held A) over a maqsum frame-drum rhythm, a "
                "duduk drone and a Hijaz answer resolving Eb-D.", map_id="dust_basin", biome="desert")


def frozen_front() -> Cue:
    harm = prog("Dmadd9:4 | Bbmaj7:4 | Gmadd9:4 | Dmadd9:4")
    cel = motif(B(1), "D6", vel=0.7)
    glass = motif(B(1), "D5", vel=0.5)
    flute = seq("F5:1 E5:1 D5:2", B(3), vel=0.5) + seq("A4:4", B(4), vel=0.45)
    choir = chords(harm, 60, 4, vel=0.45)
    harm_hi = with_params(seq("D6:8 | A5:8", B(1), vel=0.35), art="flautando")
    drone = seq("D2:16", B(1), vel=0.4)
    bells = [Note(B(4), 4, 74, 0.5)]
    parts = [
        P("celesta", "bell", cel, -19.0, params={"kind": "celesta"}, reverb=0.45, pan=0.2),
        P("glass", "bell", glass, -21.5, params={"kind": "glass"}, reverb=0.5, pan=-0.25),
        P("flute", "flute", flute, -23.0, params={"kind": "shakuhachi"}, reverb=0.5, pan=0.3),
        P("choir", "choir", choir, -24.5, params={"vowel": "oo"}, reverb=0.55, eq=(("peak", 300.0, -3.0, 0.8),)),
        strings("harmonics", "violins", harm_hi, -24.0, reverb=0.5),
        P("drone", "pad", drone, -28.0, params={"cutoff": 600.0, "attack": 2.0, "release": 3.0}, reverb=0.3),
        P("bell", "bell", bells, -25.0, params={"kind": "tubular"}, reverb=0.5),
    ]
    return _cue("map_frozen_front", "Frozen Front", 72, 4, 4, "D minor (add9)", "4/4", parts,
                "Winter front: the motif high on celesta doubled by glass bells, an airy choir and string harmonics in "
                "a long cold reverb, a breathy end-blown flute answer.", tail=4.0, space="cathedral", map_id="frozen_front",
                biome="winter")


def old_fortress() -> Cue:
    harm = prog("Dm:2 G:2 | Am:2 C:2 | Dm:2 G:2 | D5:4")
    bass_v = motif(B(1), "D3", form="major", vel=0.8, tag="motif_dorian")
    tenor_v = motif(B(1), "A3", form="major", vel=0.7, tag="motif_dorian")
    organ = chords(harm, 55, 4, vel=0.6)
    call = head(B(3), "D4", vel=0.75, last=2.0)
    final_choir = chords(prog("D5:4", B(4)), 50, 3, vel=0.7)
    bell = [Note(B(3), 4, 62, 0.7), Note(B(4) + 2, 4, 62, 0.55)]
    timp = pitched(hits("X", B(3), vel=0.8), "D2") + roll(B(4), 4, 7, 0.5, 0.1, pitch=38)
    parts = [
        P("choir_bass", "choir", bass_v + final_choir, -20.0, params={"vowel": "ah", "register": "bass"}, reverb=0.45),
        P("choir_tenor", "choir", tenor_v, -22.0, params={"vowel": "ah", "register": "tenor"}, reverb=0.45),
        P("organ", "organ", organ, -22.0, reverb=0.45),
        brass("horns", "horn", call, -22.0, reverb=0.4),
        P("church_bell", "bell", bell, -21.0, params={"kind": "church"}, reverb=0.5, pan=0.2),
        P("timpani", "timpani", timp, -24.0, reverb=0.35),
    ]
    return _cue("map_old_fortress", "Old Fortress", 64, 4, 4, "D Dorian", "4/4", parts,
                "Old fortress: the motif in Dorian sung by male choir in parallel fifths (organum) over organ, a horn "
                "call, a church bell and timpani in a stone nave.", tail=3.5, space="cathedral", map_id="old_fortress",
                biome="fortress_old")


def harbor_district() -> Cue:
    harm = prog("Dm:3 | Dm:3 | C:3 | C:3 | Dm:3 | G:3 | Am:3 | Dm:3")
    acc = (motif(B(1, 3), "D4", form="major", meter="6/8", vel=0.75, tag="motif_dorian")
           + seq("C5:1 B4:1/2 A4:1 G4:1/2 | E4:3 | F4:1 A4:1/2 D5:1 C5:1/2 | B4:3/2 G4:3/2 | A4:1 C5:1/2 E5:1 C5:1/2 | D5:3",
                 B(3, 3), vel=0.72, bar=3))
    left = comp(harm, [0.5, 1.0, 2.0, 2.5], 55, 3, dur=0.4, vel=0.4)
    pizz = bass(harm, 2, "root5", vel=0.7, step=1.5)
    fog = seq("D2:6", B(1, 3), vel=0.6) + seq("A1:6", B(7, 3), vel=0.55)
    buoy = [Note(B(2, 3) + 1.5, 2, 81, 0.4), Note(B(4, 3) + 1.5, 2, 81, 0.35), Note(B(6, 3) + 1.5, 2, 81, 0.35)]
    drum = []
    for b in range(1, 9):
        drum += hits("X..x.x" if b % 2 else "X..x..", B(b, 3), 0.5, vel=0.55)
    parts = [
        P("accordion", "reed", acc, -19.5, params={"kind": "accordion"}, reverb=0.25, pan=-0.15),
        P("accordion_left", "reed", left, -25.0, params={"kind": "accordion"}, reverb=0.2, pan=-0.3),
        P("pizz_bass", "pluck", pizz, -22.0, params={"kind": "bass_pizz"}, reverb=0.2, pan=0.2),
        brass("foghorn", "tuba", fog, -24.0, art="swell", reverb=0.4),
        P("buoy_bell", "bell", buoy, -27.0, params={"kind": "tubular"}, reverb=0.45, pan=0.45),
        P("frame_drum", "frame_drum", drum, -26.0, params={"stroke": "doum"}, reverb=0.2),
    ]
    return _cue("map_harbor_district", "Harbor District", 120, 3, 8, "D Dorian", "6/8", parts,
                "Harbor: a 6/8 sway in D Dorian - the motif on accordion over pizzicato bass and accordion comping, a "
                "low tuba 'foghorn' swell and a buoy bell.", map_id="harbor_district", biome="harbor")


def mountain_pass() -> Cue:
    harm = prog("D5:4 | D:4 | D:2 E/D:2 | D:4")
    h = harmonic
    call = [Note(0.0, 0.75, h(4), 0.8, {}, "motif_head"), Note(0.75, 0.25, h(4), 0.7, {}, "motif_head"),
            Note(1.0, 1.0, h(6), 0.85, {}, "motif_head"), Note(2.0, 2.0, h(8), 0.8)]
    fall = [Note(B(2), 1.0, h(8), 0.7), Note(B(2) + 1, 1.0, h(7), 0.65), Note(B(2) + 2, 1.0, h(6), 0.65),
            Note(B(2) + 3, 1.0, h(5), 0.6)]
    answer = motif(B(3), "D5", form="lydian", vel=0.6)
    vln = motif(B(3), "D5", form="lydian", vel=0.5)
    pad = chords(harm[1:], 62, 4, vel=0.45)
    basses = seq("D2:16", B(1), vel=0.45)
    timp = roll(B(4), 4, 7, 0.08, 0.35, pitch=38)
    parts = [
        brass("alphorn", "alphorn", call + fall, -19.0, reverb=0.6),
        P("flute", "flute", answer, -22.0, reverb=0.5, pan=0.25),
        strings("violins", "violins", vln, -24.0, art="flautando", reverb=0.5),
        strings("pad", "violas", pad, -24.0, reverb=0.45),
        strings("basses", "basses", basses, -26.0, reverb=0.3),
        P("timpani", "timpani", timp, -28.0, reverb=0.35),
    ]
    return _cue("map_mountain_pass", "Mountain Pass", 60, 4, 4, "D Lydian", "4/4", parts,
                "Mountain pass: an alphorn call on natural harmonics (with the flat 7th partial) echoing off the valley "
                "walls, answered by flute and violins with the motif in Lydian (G#).", space="valley_echo",
                map_id="mountain_pass", biome="mountain")


def river_town() -> Cue:
    harm = prog("Dm:3 | Gm:3 | A:3 | Dm:3 | Bb:3 | Gm:3 | A:3 | A7:3 | Dm:3 | Dm:3")
    mel = (motif(B(1, 3), "D4", meter="3/4", vel=0.75)
           + seq("F4:1 A4:1 D5:1 | D5:2 C5:1 | Bb4:2 A4:1 | G4:2 E4:1 | C#5:3 | D5:3", B(4, 3), vel=0.75, bar=3))
    mando = tremolo(mel, 0.25, 0.1)
    oom = bass(harm, 2, "hold", vel=0.7)
    for n in oom:
        n.dur = 1.0
    pah = comp(harm, [1.0, 2.0], 57, 3, dur=0.5, vel=0.45)
    bell = [Note(B(9, 3), 4, 62, 0.55)]
    parts = [
        P("mandolin", "pluck", mando, -19.5, params={"kind": "mandolin", "courses": 2}, reverb=0.25, pan=0.15, rr=6),
        P("accordion", "reed", pah, -24.0, params={"kind": "accordion"}, reverb=0.2, pan=-0.25),
        P("bass", "pluck", oom, -22.0, params={"kind": "bass_pizz"}, reverb=0.2),
        strings("pad", "violas", chords(harm, 55, 3, vel=0.35), -27.0, reverb=0.3),
        P("church_bell", "bell", bell, -23.0, params={"kind": "church"}, reverb=0.45, pan=0.3),
    ]
    return _cue("map_river_town", "River Town", 144, 3, 10, "D minor", "3/4", parts,
                "River town: a 3/4 waltz - the motif on tremolo mandolin over an accordion oom-pah-pah and pizzicato "
                "bass, closing on a church bell.", map_id="river_town", biome="river_town")


def open_plains() -> Cue:
    harm = prog("D:2 G:2 | Asus4:2 A:2 | C:2 G/B:2 | D:4")
    horn = motif(B(1), "D4", form="major", vel=0.7)
    answer = seq("E5:1 D5:1 C5:1 B4:1 | A4:4", B(3), vel=0.55)
    guitar = arp(harm, 57, [0, 1, 2, 3, 2, 1, 2, 3], 0.5, n=4, vel=0.5, dur=1.0)
    pad = chords(harm, 64, 4, vel=0.45)
    basses = bass(harm, 2, "hold", vel=0.45)
    timp = pitched(hits("o", B(1), vel=0.45), "D2") + roll(B(4), 4, 7, 0.12, 0.4, pitch=38)
    parts = [
        brass("horn", "horn", horn, -19.5, reverb=0.4, params={"players": 2}),
        strings("violins", "violins", answer, -22.0, reverb=0.4),
        P("guitar", "pluck", guitar, -22.0, params={"kind": "guitar"}, reverb=0.3, pan=-0.3),
        strings("pad", "violas", pad, -24.0, reverb=0.4, params={"bright": 0.8}),
        strings("basses", "basses", basses, -26.0, reverb=0.25),
        P("timpani", "timpani", timp, -27.0, reverb=0.35),
    ]
    return _cue("map_open_plains", "Open Plains", 72, 4, 4, "D Mixolydian", "4/4", parts,
                "Open plains: the motif in D major on horns over open-string guitar arpeggios and wide strings, a "
                "Mixolydian C-major answer, soft timpani.", tail=4.0, map_id="open_plains", biome="plains")


MAPS = [iron_valley, dust_basin, frozen_front, old_fortress, harbor_district, mountain_pass, river_town, open_plains]
