# HULLDOWN: Audio Design

> Status: **authoritative** for every sound effect, the client mix, and the audio asset pipeline.
> The AudioEngine (`ReplicatedStorage/Client/Audio`), the `Shared/Config/Audio.luau` tunables and the
> map `audio` fields must follow this document. To deviate, update this document in the same change.
>
> Sources of truth: the sound designs in `tools/audio/designs/*.py`, the DSP library in
> `tools/audio/synth/`, the generated catalogue `assets/audio/catalog.json`, and the validation report
> `build/audio_review/validation.json`. Research background is in
> [`docs/research/06-ui-ux-audio.md`](../research/06-ui-ux-audio.md) and
> [`docs/research/08-roblox-platform-backend.md`](../research/08-roblox-platform-backend.md).
> Music (score, cues, stems and the MusicDirector state machine) is specified in §11; its sources are
> `tools/audio/scores/`, `tools/audio/generate_music.py` and `assets/music/catalog.json`.

---

## 1. Pillars

1. **Audio communicates gameplay.** The player should be able to tell what happened from sound alone,
   within about 150 ms: whether they were spotted, whether a shot went in, what hit them, where the
   shooting is and how far away. Realism matters less than readability.
2. **One sound, one meaning.** Each gameplay outcome has its own spectral and temporal signature, and
   no other sound reuses it. Penetration, ricochet, non-penetration and critical hits must never be
   confused (§6.8).
3. **Information hierarchy.** The mix ranks threats to me first (spotted, incoming fire, hits taken),
   then my own action feedback (shot results, reload), then teammates, then the world (engines,
   ambience). Ducking and voice stealing enforce that order (§3).
4. **Distance is information.** Close, mid and far are different sounds, not just quieter ones. A far
   shot is a dark, rolling thump with an echo. A close shot is a sharp crack with a body and a slap-back
   (§4).
5. **Original and reproducible.** Every sound is synthesised by our own code. There are no recordings,
   no sample libraries and nothing taken from other games. Every render is deterministic: the same
   code gives byte-identical OGG files.
6. **Respect the information war.** Audio never leaks what spotting hides. Unspotted enemies are heard
   only through coarse, anonymised events (§4.7).

---

## 2. Technical standards (validated by `tools/audio/validate_audio.py` and `tools/audio/qa_audio.py`)

| Property | Standard |
|---|---|
| Format | OGG Vorbis, **48 kHz**, quality ~0.65 (ambience beds 0.55) |
| Channels | **mono** for every positional (3D) sound. **Stereo** for UI, cues, radio, ambience beds, weather beds and the hangar room tone |
| Headroom | Sample peak **≤ −1.0 dBFS** on the decoded file (hard). Inter-sample true peak **≤ −0.5 dBTP** (the encoder trims gain automatically) |
| DC | \|mean\| < 0.001 per channel. One-shots get an end-safe Hann DC correction |
| Loops | Built periodic by construction, then rotated to a quiet rising zero-crossing. Seam jump ≤ 1.0× the 99th-percentile sample step, measured on the **decoded** OGG |
| Lengths | One-shots ≤ 9.5 s (UI and cues ≤ 3.5 s, radio ≤ 2.5 s). Engine, track, turret, fire and cue loops 2–8 s. Ambience and weather beds 30–40 s |
| One-shot heads | A one-shot speaks the moment it is triggered: lead-in below −60 dBFS is trimmed to 2 ms at mastering (`trim_lead`), except files whose timing is anchored to their start (`meta.closestApproachS`). QA limit: 30 ms of leading silence |
| Loudness | One-shots are normalised on **max momentary loudness** (400 ms, BS.1770 K-weighting). Loops are normalised on **integrated loudness**. Targets are per sound (§3.4). The K-weighting in `synth/mix.py` reproduces the BS.1770 48 kHz reference coefficients exactly, and `qa_audio.py` re-measures every file with its own independent implementation |
| Peak control | Clipper-before-limiter (soft knee 2 dB over the ceiling, maximum 6 dB), then a 1.5 ms look-ahead limiter. Total transient reduction is capped at 12 dB |
| Determinism | Seed = SHA-256(key, variant) → PCG64. The Ogg stream serial is derived from the key, so files are byte-reproducible |

Current validation (206 keys, 321 files, 19 banks): `validate_audio.py` **0 errors, 0 warnings**;
`qa_audio.py` (SFX and music) **0 errors**. Highest sample peak −1.05 dBFS. Highest true peak −0.59 dBTP.
Worst loop seam jump ratio 0.23 (validator) / 0.41× the local sample motion (QA). Longest one-shot
lead-in 7.6 ms. No truncation clicks. Banks match their standalone files (envelope correlation ≥ 0.997).
Re-renders are byte-identical (12/12 keys checked).

> **Loudness meter fix (QA, 2026-10).** The K-weighting pre-filter had an operator-precedence slip
> (`10 ** (G/20) ** 0.4997` evaluates as `10 ** ((G/20) ** 0.4997)`), which over-weighted 0.5–3 kHz by
> up to +6.9 dB. Every file had been normalised with it, so midrange sounds (UI, cues, radio, the
> ricochet ping) sat up to ~4 dB under their targets relative to bass-heavy ones. It is fixed and
> every SFX and music file was re-rendered; the numbers in §3.4 and §11 are true BS.1770 values.

---

## 3. Bus and mix plan

### 3.1 Buses

The client builds the audio graph with the **modular Audio API** (`AudioPlayer` → `AudioEmitter` /
`AudioListener` → `AudioFader` per bus → master `AudioCompressor` → `AudioLimiter` → `AudioDeviceOutput`).
The legacy `Sound`/`SoundGroup` path is discouraged by Roblox (research 06 §25). Each bus is one
`AudioFader`. 3D buses are separate `AudioListener`s grouped by `AudioInteractionGroup`, so each one
gets its own fader and sidechain.

| Bus | Contents | Space | Default fader | Bus processing |
|---|---|---|---|---|
| **Master** | everything | n/a | 1.00 | Glue compressor (2:1, −18 dB, 10/150 ms). Limiter at −1 dBFS. "Night mode" preset (§7) |
| **Music** | music cues and battle stems (§11) | 2D | 0.45 | Sidechain: ducked by Voice, cues and hits taken (§11.6) |
| **Ambience** | biome beds, weather, spots, hangar | 2D beds + 3D spots | 0.60 | Ducked by own gunfire, explosions, cues and hits taken |
| **Vehicles** | engines, tracks, turret, transmission | 3D (own vehicle 2D) | 0.80 | Sub-faders `Vehicles/Own` (0.85) and `Vehicles/Others` (1.0) |
| **Weapons** | gun firing, reload, flybys, distant thumps | 3D (own gun 2D) | 1.00 | Sub-faders `Weapons/Own` and `Weapons/Others` |
| **Impacts** | armor results, ground impacts, damage, destruction | 3D (shooter's result and hits taken 2D) | 1.00 | none (needs maximum transient clarity) |
| **UI** | menus, garage, battle information cues | 2D | 0.70 | none |
| **Voice** (Radio) | radio quick commands, crew stingers | 2D | 0.85 | Band-limited at the source. Sidechain key for ducking Music and Ambience |

### 3.2 Priorities and voice limits

Roblox documents no polyphony cap, so the AudioEngine runs its own **32-voice budget**:

| Bus | Voices | Reserved |
|---|---|---|
| Weapons | 7 | 1 for own gun |
| Impacts | 7 | 2 for armor results / hits taken |
| Vehicles | 8 | 4 for own vehicle (2 RPM layers, tracks, turret). The other 4 go to the two nearest other vehicles |
| Ambience | 4 | bed, weather, 2 spots |
| UI | 3 | 1 for `cue_sixth_sense` |
| Voice | 1 | radio and crew stingers queue |
| Music | 2 | crossfade pair |

* **Effective priority** = catalogue `suggested.priority` + 10·log10(current gain). The voice with the
  lowest effective priority is stolen first. A voice with priority ≥ 95 is never stolen by a lower one.
* **Instance caps per key:** gun close ×3, gun mid/far ×2, each armor result ×2, ground impact
  material ×3, explosions ×2, `ui_hover` ×1 (restart), `ui_slider_tick` 30/s maximum, ambient spots ×2.
* **Anti-repetition:** pick variants round-robin with no immediate repeat. Randomise pitch by ±3 %
  (one-shots only, never on UI or cues) and volume by ±1.5 dB.
* **Virtual voices:** a loop whose gain is below −40 dB keeps its timeline but releases its
  `AudioPlayer`. It resumes at the right `TimePosition` when it becomes audible again.

### 3.3 Ducking (sidechain or scripted fader moves)

| Trigger | Ducked buses | Depth | Attack | Hold | Release |
|---|---|---|---|---|---|
| `cue_sixth_sense` | all except UI and Voice | −4 dB | 10 ms | 1.0 s | 600 ms |
| `armor_hit_taken_*` | Vehicles, Ambience, Music | −6 dB | 5 ms | 0.3 s | 800 ms |
| ↳ `armor_hit_taken_pen` only | Master low-pass 2.5 kHz ("concussion") | n/a | 5 ms | 0.4 s | 900 ms |
| Own gun fired | Ambience, Music. Weapons/Others −2 dB | −4 dB | 5 ms | 0.15 s | 500 ms |
| Explosion within 60 m (`dmg_*_close`) | Ambience, Music, Vehicles | −6 dB | 5 ms | 0.5 s | 1.2 s |
| Voice bus active | Music −6 dB, Ambience −4 dB | n/a | 20 ms | while playing | 400 ms |
| Garage fanfares (`ui_vehicle_unlocked`, `ui_mission_complete`, ...) | Music | −5 dB | 20 ms | sound length | 600 ms |
| Low-HP heartbeat active | Music, Ambience | −3 dB | 200 ms | while active | 1 s |

Long releases avoid pumping. Ducks of the same bus do not add up: the deepest active one wins.

### 3.4 Loudness map (authoring targets, LUFS)

These are the levels written into the files. The faders in §3.1 then set the final balance.

| Group | Target | Measured min / median / max (all variants) |
|---|---|---|
| Armor results and hits taken (one-shot, M-max) | hits taken −11 to −13.5; penetration −12, critical −13, ricochet / blocked −13.5 | −14.7 / −13.6 / −11.3 |
| Gun close | −10.5 (huge, howitzer) to −12.5 (small) | −13.0 / −11.8 / −10.8 |
| Gun mid / far | close −5 dB / close −10 dB | −17.5 / −16.2 / −15.4 and −22.5 / −21.2 / −20.4 |
| Explosions close / far | −9 to −11 / −16 to −17 | −11.4 / −10.5 / −9.4 and −17.4 / −16.9 / −15.9 |
| Ground impacts | −13 (snow −15) | −15.2 / −13.4 / −13.2 |
| Battle cues | −13 (sixth sense) to −24 (target lost) | −24.0 / −17.5 / −13.0 |
| UI | −33 (hover, slider) to −15 (fanfares) | −32.9 / −20.0 / −15.0 |
| Radio / Voice | −17 to −22 | −22.4 / −17.9 / −16.9 |
| Engine loops (integrated) | idle −21.5, low −20, mid −18.5, high −17, damaged −18.5, overload −23, reverse −26 | −26.0 / −19.9 / −17.0 |
| Track loops | −19 (hard surfaces) / −20 | −20.4 / −20.1 / −19.3 |
| Turret loops | −24 to −28 | −28.0 / −25.0 / −24.0 |
| Ambience beds / spots | −26 to −27 / −24 | −27.4 / −27.2 / −26.2 and −24.5 / −24.0 / −23.9 |
| Weather loops / hangar room tone | −23 to −25 / −30 | −25.4 / −23.3 / −23.3 and −30.2 |

The validator enforces bus windows and warns when a sound drifts more than 3 dB from its own target.

The armor-result targets keep the authored spacing (penetration 1.5 dB above ricochet / blocked,
critical 0.5 dB above them) at the highest level the 12 dB transient-reduction cap allows: these
sounds are all crack and snap, and with a correct meter the old −10 / −11 / −11.5 targets were
unreachable (critical was stuck 4.5 dB short while ricochet, the one tonal sound, hit its target).
Hits taken stay the loudest results (threat to me first, pillar 3). `qa_audio.py` also flags
per-bus loudness outliers; the remaining flags are intentional quiet foley (`env_bush_rustle`,
`env_bridge_creak`, `turret_traverse_start`), which sit with their own families.

---

## 4. Distance model

Scale: **1 stud = 1/3 m** (3 studs per metre). The catalogue gives `rollOffMinStuds` and
`rollOffMaxStuds` for every positional sound. Use them with an `InverseTapered` attenuation curve
(the `AudioEmitter` distance-attenuation preset, or the equivalent `Sound.RollOffMode`).

### 4.1 Distance bands

| Band | Metres | Studs | Used for |
|---|---|---|---|
| close | 0–120 | 0–360 | `*_close` variants: crack, full body, slap-back |
| mid | 120–450 | 360–1350 | `*_mid` variants: crack mostly gone, ~3 kHz air absorption, more echo |
| far | 450–1500 | 1350–4500 | `*_far` variants: no crack, ~0.85 kHz, soft onset, valley echo and a delayed rolling rumble |
| beyond | > 1500 | > 4500 | `shell_distant_thump` only (rate-limited) |

**Variant crossfade:** each variant's attenuation range overlaps its neighbour's (gun close is 8–200 m,
mid 100–600 m, far 400–1500 m). The engine picks variants **when the shot fires**. Inside a band, only
that band's variant plays. In an overlap zone (close↔mid 100–140 m, mid↔far 400–500 m), both variants
start together with an equal-power crossfade by distance. No variant switches mid-sound.

### 4.2 Air absorption low-pass

Continuous sounds (engines, tracks, turret, fire loops) and non-variant one-shots get a 12 dB/oct
`AudioFilter` low-pass:

```
fc(d) = clamp(20000 * (d / 25 m) ^ -0.75, 1200 Hz, 20000 Hz)
```

| d (m) | 25 | 50 | 100 | 200 | 400 | 800 |
|---|---|---|---|---|---|---|
| fc (Hz) | 20000 | 11900 | 7070 | 4200 | 2500 | 1490 |

Variant sounds already have absorption baked in. For them, use `d_eff = d − bandStart` in the formula
so the filtering is not applied twice.

### 4.3 Speed of sound

For `d > 150 m`, delay gun, explosion and impact events by `d / 343 m/s` (maximum 2.5 s) with
`AudioPlayer:Play(atTime = SoundService:GetMixerTime() + delay)`. The muzzle flash leads the sound,
which is itself a distance cue. Hits that matter to the local player (their own shot result, hits
taken, flybys) are **never** delayed.

### 4.4 Occlusion

* **Rays:** on a 24-rays-per-frame round-robin budget, cast from the listener's head to each active 3D
  emitter. Use a collision group that contains terrain, buildings and large props only (no vehicles,
  no foliage).
* **One occluder:** −6 dB and a low-pass at 1.2 kHz. **Two or more occluders, or terrain:** −10 dB and
  0.7 kHz. Smooth every change over 150 ms to avoid zipper noise.
* **Partial occlusion (cheap diffraction):** cast two extra rays offset ±1.5 m sideways. If any of them
  is clear, apply half the effect.
* Own-vehicle sounds, 2D sounds and hit results meant for the local player are never occluded.

### 4.5 Own vehicle and listener perspective

* Own engine, tracks, turret and reload play **2D** on the `Vehicles/Own` and `Weapons/Own`
  sub-faders. Use the same assets with an interior tilt in sniper mode: low shelf +2 dB, high shelf
  −4 dB above 4 kHz.
* Own gun: the close variant plays 2D, plus `reload_breech_close` or `reload_autoloader_cycle` when
  the reload ends.
* `armor_hit_taken_*` plays 2D with the ducking in §3.3. The shooter hears the matching
  `armor_*` result **2D** at priority 95. Everyone else hears it 3D at the impact point.

### 4.6 Doppler

Roblox documents no Doppler on `AudioEmitter`, so Doppler is **baked** into the files that need it
(`shell_flyby_*`, `amb_plains_spot_insect_flyby`). Fast vehicles get a small `PlaybackSpeed` nudge
(±4 % from radial velocity, smoothed).

### 4.7 Unspotted enemies (information warfare)

The server never sends enemy state to a team that cannot see the enemy (ARCHITECTURE §1). For audio:

* **Gunfire and explosions** of unspotted vehicles reach clients inside the audible range (≤ 1500 m)
  as anonymous *audio events*. Each event carries the class (`gun_<class>`, explosion size), a
  position snapped to a 50 m grid plus ±15° of bearing noise, and nothing that identifies the vehicle.
  The client plays the band-appropriate variant at that fuzzed position.
* **Engines and tracks** of unspotted vehicles are not played (there is no state to drive them).
* **Flybys** come from the shell itself, which is already replicated as a projectile.

---

## 5. Engine and track runtime models

### 5.1 Engines (RPM crossfade)

Each family has four steady loops at native RPMs (`meta.rpm`), plus `_start`, `_stop`, `_damaged`
and `_overload`.

```
layers L0..L3 at native rpm n0<n1<n2<n3 (catalogue meta.rpm)
for current rpm r: pick i with n_i <= r <= n_i+1, x = (r - n_i) / (n_i+1 - n_i)
gain_i = cos(x*pi/2), gain_i+1 = sin(x*pi/2)                  (equal power)
PlaybackSpeed_k = clamp(r / n_k, 0.75, 1.35)                  (pitch follows rpm)
throttle: +0..3 dB on the active pair; overload layer gain = smoothstep(0.8, 1.0, load) * (1 - speed/vmax)
damaged module: replace the RPM layers with *_damaged (PlaybackSpeed = r / meta.rpm of the mid layer)
start: play *_start, then start the idle loop 0.6 s before it ends (crossfade 0.5 s)
stop:  fade the loops over 0.3 s, then play *_stop
reverse: transmission_reverse_whine gain = |v| / 15 km/h (cap 1), PlaybackSpeed 0.8..1.3 with |v|
gear change: transmission_gear_shift (random variant)
```

| Family | Cylinders | idle / low / mid / high rpm | Character |
|---|---|---|---|
| `heavy_diesel` | V12 diesel | 600 / 1000 / 1500 / 2050 | Deepest: 44–480 Hz exhaust formants, heavy crankcase rumble, soft knock, low turbo |
| `medium_diesel` | V8 diesel | 700 / 1200 / 1800 / 2500 | Lumpy cross-plane burble, strong injector clatter, bright turbo whistle |
| `light_highrpm` | inline-6 petrol | 900 / 2200 / 3600 / 5200 | Raspy, revvy, intake rasp, little knock |
| `large_v12` | V12 petrol | 650 / 1300 / 2100 / 2900 | Smooth throaty roar, supercharger whine |
| `small_engine` | inline-4 petrol | 850 / 2000 / 3200 / 4600 | Buzzy, loose-panel rattle |
| `turbine` | gas turbine | N1 0.55 / 0.70 / 0.85 / 1.00 | Blade-pass whine (7.6 kHz × N1), shaft hum, combustion roar, intake hiss |

### 5.2 Tracks

* **Surface:** the material under the tracks (`RaycastResult.Material`) maps to a loop.
  Grass/LeafyGrass → grass. Ground → dirt. Mud → mud. Sand → sand. Snow/Glacier/Ice → snow.
  Concrete/Asphalt/Pavement/Brick/Cobblestone/Slate → concrete. Rock/Basalt/Pebble/Limestone/Salt →
  gravel. WoodPlanks/Wood → wood. Metal/DiamondPlate/CorrodedMetal → metal. Water depth > 0.4 m →
  water. Crossfade between surfaces over 0.25 s.
* **Speed:** native speed is 25 km/h. `PlaybackSpeed = clamp(v / 25, 0.5, 1.6)`. Volume rises with
  smoothstep from 0 to 8 km/h, then follows `0.6 + 0.4 · v / vmax`.
* **One-shots:** `track_squeal` on pivot turns above 10 km/h (at most one every 2 s).
  `track_broken_clatter` with `dmg_track_broken` when the track breaks while moving.
* **Turret:** `turret_traverse_small` or `_large` loops while rotating, with `PlaybackSpeed` 0.8–1.2
  from the traverse rate. `_start` and `_stop` play on rotation edges. `gun_elevation_servo` plays
  while the gun elevates.

---

## 6. Per-category design notes

All designs live in `tools/audio/designs/` and use the shared kit `designs/kit.py` (blasts, booms,
modal metal/wood/brass/rock hits, debris showers, whooshes, bubbles, stick-slip creaks, crackle,
radio colouring, bells, wind). Reverbs are synthesised IRs (`synth/reverb.py`): `small_room`,
`tank_interior`, `hangar`, `stone_hall`, `outdoor_slapback`, `valley_echo` and `forest`. Reverb sends
are scaled **peak-relative** to the dry signal, so bass-heavy sources never drown in their tails.

### 6.1 Engines

These are physical models, not samples. Each combustion event of each cylinder is
modelled: 4-stroke firing order, V-bank split, per-cylinder imbalance and timing jitter. Each event
emits a tonal exhaust pulse plus a noisy combustion burst into an exhaust-formant resonator bank.
Layered on top are diesel knock, turbo or supercharger whine, intake rasp, crankcase rumble, gear
whine and panel rattle. Loops hold an integer number of engine cycles, so the seam is continuous.

### 6.2 Tracks

Each loop has four parts. A periodic link-clank train at about 43 Hz (0.16 m pitch at
25 km/h, sprocket accents every 11 links). Road-wheel rumble. A hull body resonance. A surface
texture: granular crunch for dirt and gravel, swish for grass, Minnaert-bubble squelch for mud,
squeaky crunch for snow, hiss for sand, slosh for water, hollow plank knocks for wood, and a ringing
plate for metal.

### 6.3 Gun firing

A shot is built from eight layers: an N-wave muzzle crack, a blast burst, a mid
"punch", a pitch-dropping boom, a propellant body, a roar, a breech clank and a rolling rumble. Each
class scales frequencies down and decays up from small (175 → 82 Hz boom) to howitzer (82 → 38 Hz).
Infrasonics are removed (high-pass at 38 Hz) so guns read on small speakers. The autocannon is a
3/4/5-round burst (variants a/b/c) with bolt clatter and ejected-case pings.

### 6.4 Reload

Brass-tube modal clanks, a sliding breech "chunk" with a latch click, autoloader
ratchet and rammer, a full drum or magazine sequence (3.5 s), and the dual-gun ready double click.
All play in the `tank_interior` IR.

### 6.5 Shell flight

An AP flyby is a supersonic crack followed by a tearing band-noise whoosh with a
Doppler drop. An HE flyby is a lower, fluttering whoosh with no crack. The artillery whistle falls
in pitch with a crescendo and stops at the impact (`meta.impactAtEnd`). Flybys carry
`meta.closestApproachS`. Start playback that long before the round's closest approach.

### 6.6 Ground impacts

A shared impact core plus a material layer: dirt patter, rock chips, concrete
crumble and rebar ping, water plunge with bubbles and falling droplets, snow "poof", sand shower,
wood splinters, and a wobbling sheet-metal clang.

### 6.7 Damage

Each event has its own signature:
* module damaged: crunch and sparks
* track broken: a bright snap and link clatter
* engine damaged: coughs and backfires from the engine model
* fire ignition: "fwoomp"
* fire loop: roar, flutter and crackle
* extinguisher: gas hiss and choke
* ammo rack damaged: an alarm-like pulsing metal shriek
* ammo rack detonation and vehicle destroyed (medium/large, close/far): crack, boom, cook-offs,
  turret toss and crash, debris rain
* wreck burning loop: low roar with thermal ticks
* crew injured: radio crackle and a two-tone alert, no voice

### 6.8 Armor results: readability contract

| Result | Signature (must stay unique) | Spectrum | Envelope | Measured centroid |
|---|---|---|---|---|
| `armor_penetration` | heavy boom + **dense granular steel crunch** + **tearing** sweep (2.8 → 0.7 kHz) | broadband, strong lows | 0.3 s dense, 1.15 s total | ~420 Hz (energy-weighted) |
| `armor_ricochet` | **bright ping** (2.4–3 kHz bar modes, long ring) + **falling tumbling whine** (3.3 → 1.1 kHz) | tonal, high, almost no lows | ping then 0.8 s glide | ~2360 Hz |
| `armor_blocked` | **dull, short, low-mid clang** (175–1200 Hz plate modes, low-passed) + thud | low-mid tonal, no highs | 0.3 s ring, 1.1 s total | ~200 Hz |
| `armor_critical` | razor snap + **electric zap** sweep (4 kHz → 400 Hz) + **arcing buzz** (square 115–150 Hz, gated, harmonics 0.5–7 kHz) + sparks. No low end (high-passed at 200 Hz): it always layers on the penetration, which owns the boom | buzz harmonics + HF crackle | 0.55 s buzz | ~1290 Hz |
| `armor_hit_taken_pen` | interior: muffled sub thud, hull "bong", muffled crunch, faint ring | below 2.6 kHz | 1.05 s | ~170 Hz |
| `armor_hit_taken_blocked` | interior: thud and ringing hull bong only | below 1.9 kHz | 1.05 s | ~135 Hz |
| `armor_hit_taken_ricochet` | interior: glancing thud, brighter hull ring, muffled whine | below 3 kHz | 1.0 s | n/a |

The validator checks pairwise log-mel spectral distance between these results (minimum 5.9 dB today,
threshold 4 dB). `qa_audio.py` checks penetration / ricochet / blocked / critical on every variant: each
class pair must differ in at least two of spectral centroid (≥ 0.5 octave, also on a 300 Hz–8 kHz
"phone speaker" band), log-mel shape (≥ 6 dB, and ≥ 4 dB on the phone band) and attack/decay envelope
(≥ 6 dB); the nearest other class must be further away than the class's own a/b/c spread (today:
nearest other class ≥ 8.7 dB, own spread ≤ 6.0 dB); and every variant must classify to its own class
(leave-one-out nearest neighbour). See `build/audio_review/armor_results.png` and
`qa_armor_distinctness.png`.

### 6.9 Environment destruction

Fence snap and planks, wooden building collapse (cracks, groan,
crashing timbers), brick wall collapse (rumble and brick clatter), tree fall (split crack, creak,
leaf swish, ground thud), bush rustle, metal container boom, and bridge creak (stick-slip on wood
resonances).

### 6.10 UI language

Crisp mechanical switch clicks plus clean sine, triangle and FM-bell tones tuned to
**D**. Positive events use D-F#-A (rising fifths, arpeggios, brass-like fanfare-lite motifs).
Errors use G3 plus a semitone buzz. Back is a falling fifth. Purchase is a "military cash register":
stamp, latch and a coin-like FM ching. Every UI sound is stereo with a small mono-compatible room.

### 6.11 Battle cues

* `cue_sixth_sense` is an **original** 3-note motif: A4 → D#5 (tritone up) → D5 (semitone down,
  held with tremolo) over a dark D3/A3 drone. It is the only use of the tritone in the game.
* `cue_enemy_spotted`: a sonar G6 ping with echo.
* `cue_capture_warning_loop`: an A5/F5 pulse pair every second.
* `cue_reload_complete`: a latch clack and an E6 "ding".
* `cue_target_locked`: two rising beeps.
* `cue_ally_destroyed`: falling D4 → A3 muted brass.
* `cue_enemy_destroyed`: rising A4 → E5.
* `cue_low_hp_heartbeat_loop`: 75 bpm. Low-pitch content (52/64 Hz), so pair it with the visual
  vignette.

### 6.12 Radio

Each quick command is a key-up chirp, a static burst, a unique tone rhythm, a squelch
tail and a band-limited, saturated radio chain. There is no speech.

| Command | Pattern |
|---|---|
| attack | 3 fast rising beeps |
| defend | 2 long low tones |
| help | rapid hi-lo ×4 |
| retreat | 3 falling tones |
| spotted | ping and 2 short beeps |
| capture | long-short-long rising |
| follow | up-down pairs |

Use them together with minimap pings and captions.

### 6.13 Ambience, weather and hangar

Beds are 40 s stereo loops, periodic by construction (FFT
noise, periodic random control curves, circular filtering and convolution, wrapped events). Their
side (L−R) signal is high-passed at 120 Hz (`mono_bass`), so the rumble survives mono and phone
playback (independent per-channel noise had come out anti-correlated below 150 Hz on the harbor bed). Spots
are mono one-shots for random 3D emitters 60–300 m away. Animals are abstract synthetic calls (FM
bird chirps, formant-filtered "caws", gull glides, pulsed cricket carriers), never imitations of
real recordings. Thunder is a crackling leader (close only) plus many rolling low-passed bursts in
valley echo.

---

## 7. Accessibility and options

* **Visual twins:** every gameplay-critical sound also has a visual event.

  | Sound | Visual |
  |---|---|
  | sixth sense | lamp icon |
  | armor result | result text and colour |
  | hit taken | damage direction indicator |
  | flyby | near-miss arc |
  | radio command | minimap ping and caption |
  | capture warning | flashing base marker |
  | low HP | vignette |

* **Captions** for radio commands and crew stingers, for example "[Radio] Attack!" or
  "[Crew] Gunner injured".
* **Sliders:** Master, Music, Ambience, Vehicles, Weapons, Impacts, UI and Voice. Plus **Mono output**
  and **Night mode**. Night mode sets the master compressor to 3:1 at −24 dB and adds a −6 dB shelf
  below 100 Hz.
* **Reduced audio fatigue:** halves the heartbeat and capture-warning loop volumes after 10 s.
* Because of the low-frequency content in hits taken and explosions, the **Device preset**
  (Speakers / Headphones / Phone) changes Master EQ. The Phone preset adds +3 dB at 150–400 Hz so
  booms still read.

---

## 8. Map audio identity

Each `Maps/<MapId>.luau` sets an `audio` table. Example:

```lua
audio = {
  biome = "harbor",                    -- selects amb_<biome>_bed and amb_<biome>_spot_*
  spotIntervalS = { 8, 30 },           -- random delay between ambient spots
  spotDistanceM = { 60, 300 },         -- spot emitter ring around the listener
  weather = { "wx_rain_loop" },        -- optional weather layers (2D)
  thunder = true,                      -- schedule wx_thunder variants every 15-60 s
  reflections = "open",                -- "open" | "mountain" | "urban" | "hangar": Weapons-bus AudioEcho/AudioReverb preset
  bedVolume = 0.5,
}
```

| Biome | Bed signature | Spots (variants) | Suggested weather | Gun reflections |
|---|---|---|---|---|
| `temperate_valley_industrial` | soft wind, 50 Hz plant hum, press thumps every 2.5 s, far clanks, birds | `bird` (3), `machinery_clank` (2) | rain | mountain (valley echo) |
| `desert` | dry hissing gusts, sand hiss on gust peaks, low roar, far metal creaks | `metal_creak` (2), `sand_gust` | sandstorm | open |
| `winter` | cold wind with gliding whistles, low drone, snow hiss, far ice cracks | `ice_crack` (3), `wind_whistle` | snowstorm | mountain |
| `fortress_old` | hollow moaning stone wind, rasping crow-like caws, far bells in stone reverb | `crow` (2), `bell_toll` | rain | urban (stone) |
| `harbor` | water lapping and gurgles, gull-like cries, far foghorn, crane clanks, buoy bell | `gull` (3), `foghorn`, `crane_clank` (2), `buoy_bell` | rain / fog | open + water |
| `mountain` | strong wide gusts, whistle, deep roar, rockfalls through valley echo | `rockfall` (2), `gust_howl` | snowstorm | mountain (strong) |
| `river_town` | river flow and babble, abstract town murmur, church-bell tolls, a few birds | `church_bell` (2: single, triple), `shutter_bang` (2) | rain | urban |
| `plains` | grass wind and rustle, cricket chorus, insect buzz, distant thunder rolls | `distant_thunder` (2), `insect_flyby` | storm (thunder) | open |
| *(garage)* | `hangar_room_tone`: HVAC air, mains hum, lamp buzz, distant activity | `hangar_distant_tools` (3), `hangar_compressor_cycle`, `hangar_pa_chime` (2) | none | hangar |

---

## 9. Pipeline: regenerate, validate, review, upload

```bash
python3 tools/audio/generate_sfx.py            # render + master + encode all keys, write catalog.json, pack banks (~45 s on 4 cores)
python3 tools/audio/generate_sfx.py --only 'armor_*,gun_large_*'   # partial re-render (catalogue is merged)
python3 tools/audio/generate_sfx.py --list     # list keys
python3 tools/audio/validate_audio.py          # all checks -> build/audio_review/validation.json (exit 1 on error)
python3 tools/audio/qa_audio.py                # independent QA gate, SFX + music (CI: --no-sheets; --strict fails on warnings)
python3 tools/audio/review_audio.py            # spectrogram sheets -> build/audio_review/*.png
python3 tools/audio/doc_sound_list.py          # refresh section 10 of this document from the catalogue
```

Requirements (`tools/audio/requirements.txt`): Python 3.11 with numpy, scipy, soundfile (libsndfile ≥ 1.1
with Vorbis) and Pillow for the review sheets.

* **Layout:** sounds are written to `assets/audio/<category>/<key>[_<variant>].ogg`. Banks go to
  `assets/audio/banks/`. The catalogue is `assets/audio/catalog.json`. Lossless masters go to
  `build/audio_masters/` (git-ignored).
* **Catalogue entry:** `file`, `category`, `bus`, `loop`, `durationS`, `channels`, `peakDb`, `rmsDb`,
  `suggested{volume, rollOffMinStuds, rollOffMaxStuds, distanceVariant, priority}` and `variants[]`.
  Also `loudnessLufs` and `loudnessMode`, `description`, `event`, `group`, `meta` (rpm, surface,
  timing), `loopSeam` for loops, `variantStats[]`, and `bankRegions[]` for one-shots.
* **Banks:** Roblox audio uploads are quota-limited (research 08 found 100 per 30 days for unverified
  accounts). `pack_banks.py` therefore concatenates the 255 one-shot files into **19 banks** of up to
  120 s each, grouped by category and channel count, with 0.25 s silent gaps. The result is
  **85 uploads (66 loops + 19 banks) instead of 321**. Play a one-shot from its bank with
  `AudioPlayer.PlaybackRegion = NumberRange.new(startS, endS)`, using `bankRegions[i]` for
  `variants[i]`. Loops are never banked.
* **Upload:** `tools/upload_assets` (asset pipeline) uploads the 66 loop files and 19 bank files via
  Open Cloud, plus the music's 8 loops and 2 stinger banks (§11.8): **95 uploads in total**. It writes asset ids to `assets/manifest.json` and to the generated
  `Shared/Assets/AssetManifest.luau`, keyed by sound key with `{ assetId, region? }`. Encoding is
  byte-reproducible, so upload only files whose SHA-256 changed. `AssetResolver` returns silence plus a
  one-time warning for any missing id.
* **Adding a sound:** add a render function and a `sound(...)` registration in the right
  `tools/audio/designs/*.py` module (key, category, description, gameplay event, variants, loop
  length, level, priority, attenuation range). Then regenerate, validate, run `qa_audio.py`, review the
  spectrogram if the sound is gameplay-critical, and run `doc_sound_list.py`. Do not import recordings.
  Every layer must come from `synth/` or `designs/kit.py`.
* **QA gate (`tools/audio/qa_audio.py`, CI):** independent of the generator's DSP code. It checks both
  catalogues against the files (exist, OGG Vorbis 44.1/48 kHz, declared channels and duration, music
  loops to the sample, `<key>[_<variant>].ogg` naming, snake_case keys unique across SFX and music, no
  orphans, catalogue figures not stale); channel policy and mono-downmix safety; sample peak ≤ −1 dBFS,
  DC, NaN, silence, clipping, one-shot lead-in ≤ 30 ms, truncated tails and the brief's length windows
  (music loops 60–150 s); loop seams (sample step and slope vs the local motion, HF burst vs the
  neighbourhood, level step vs the loop's own largest, or vs its bar lines for music) and truncation
  clicks anywhere; battle stems (identical length and grid, summed peak and loudness); per-bus
  loudness spread and outliers and variant-to-variant level; armor-result distinctness; coverage of
  every key, family, surface, band, command, biome spot and music state named in this document; and
  banks and the upload quota. It writes `build/audio_review/qa_report.json` and the contact sheets
  `qa_<category>.png`, `qa_loop_seams_*.png` and `qa_armor_distinctness.png` (skip them with
  `--no-sheets`). Exit 1 on any error.

---

## 10. Full sound list (mapped to gameplay events)

<!-- BEGIN SOUND LIST -->
_Generated from `assets/audio/catalog.json` by `tools/audio/doc_sound_list.py` - 206 keys, 321 files._

#### Engines (50)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `engine_heavy_diesel_damaged` | 1 | Vehicles | loop 4s | 4.00 | 1 | 66 | Replaces the RPM layers while the engine module is damaged. |
| `engine_heavy_diesel_high` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at high RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_heavy_diesel_idle` | 1 | Vehicles | loop 4s | 4.00 | 1 | 58 | Own/other vehicle engine at idle RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_heavy_diesel_low` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at low RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_heavy_diesel_mid` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at mid RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_heavy_diesel_overload` | 1 | Vehicles | loop 4s | 4.00 | 1 | 50 | Layered on top when climbing / pushing at max power with low speed (load > 0.85). |
| `engine_heavy_diesel_start` | 1 | Vehicles | one-shot | 4.59 | 1 | 65 | Engine start (garage preview, battle start, after repair). Crossfade into idle loop at the last 0.6 s. |
| `engine_heavy_diesel_stop` | 1 | Vehicles | one-shot | 3.29 | 1 | 60 | Engine shut-down (destroyed, battle end, garage exit). |
| `engine_large_v12_damaged` | 1 | Vehicles | loop 4s | 4.00 | 1 | 66 | Replaces the RPM layers while the engine module is damaged. |
| `engine_large_v12_high` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at high RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_large_v12_idle` | 1 | Vehicles | loop 4s | 4.00 | 1 | 58 | Own/other vehicle engine at idle RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_large_v12_low` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at low RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_large_v12_mid` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at mid RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_large_v12_overload` | 1 | Vehicles | loop 4s | 4.00 | 1 | 50 | Layered on top when climbing / pushing at max power with low speed (load > 0.85). |
| `engine_large_v12_start` | 1 | Vehicles | one-shot | 4.59 | 1 | 65 | Engine start (garage preview, battle start, after repair). Crossfade into idle loop at the last 0.6 s. |
| `engine_large_v12_stop` | 1 | Vehicles | one-shot | 3.23 | 1 | 60 | Engine shut-down (destroyed, battle end, garage exit). |
| `engine_light_highrpm_damaged` | 1 | Vehicles | loop 4s | 4.00 | 1 | 66 | Replaces the RPM layers while the engine module is damaged. |
| `engine_light_highrpm_high` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at high RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_light_highrpm_idle` | 1 | Vehicles | loop 4s | 4.00 | 1 | 58 | Own/other vehicle engine at idle RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_light_highrpm_low` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at low RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_light_highrpm_mid` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at mid RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_light_highrpm_overload` | 1 | Vehicles | loop 4s | 4.00 | 1 | 50 | Layered on top when climbing / pushing at max power with low speed (load > 0.85). |
| `engine_light_highrpm_start` | 1 | Vehicles | one-shot | 4.57 | 1 | 65 | Engine start (garage preview, battle start, after repair). Crossfade into idle loop at the last 0.6 s. |
| `engine_light_highrpm_stop` | 1 | Vehicles | one-shot | 3.19 | 1 | 60 | Engine shut-down (destroyed, battle end, garage exit). |
| `engine_medium_diesel_damaged` | 1 | Vehicles | loop 4s | 4.00 | 1 | 66 | Replaces the RPM layers while the engine module is damaged. |
| `engine_medium_diesel_high` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at high RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_medium_diesel_idle` | 1 | Vehicles | loop 4s | 4.00 | 1 | 58 | Own/other vehicle engine at idle RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_medium_diesel_low` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at low RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_medium_diesel_mid` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at mid RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_medium_diesel_overload` | 1 | Vehicles | loop 4s | 4.00 | 1 | 50 | Layered on top when climbing / pushing at max power with low speed (load > 0.85). |
| `engine_medium_diesel_start` | 1 | Vehicles | one-shot | 4.57 | 1 | 65 | Engine start (garage preview, battle start, after repair). Crossfade into idle loop at the last 0.6 s. |
| `engine_medium_diesel_stop` | 1 | Vehicles | one-shot | 3.21 | 1 | 60 | Engine shut-down (destroyed, battle end, garage exit). |
| `engine_small_engine_damaged` | 1 | Vehicles | loop 4s | 4.00 | 1 | 66 | Replaces the RPM layers while the engine module is damaged. |
| `engine_small_engine_high` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at high RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_small_engine_idle` | 1 | Vehicles | loop 4s | 4.00 | 1 | 58 | Own/other vehicle engine at idle RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_small_engine_low` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at low RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_small_engine_mid` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at mid RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_small_engine_overload` | 1 | Vehicles | loop 4s | 4.00 | 1 | 50 | Layered on top when climbing / pushing at max power with low speed (load > 0.85). |
| `engine_small_engine_start` | 1 | Vehicles | one-shot | 4.57 | 1 | 65 | Engine start (garage preview, battle start, after repair). Crossfade into idle loop at the last 0.6 s. |
| `engine_small_engine_stop` | 1 | Vehicles | one-shot | 3.23 | 1 | 60 | Engine shut-down (destroyed, battle end, garage exit). |
| `engine_turbine_damaged` | 1 | Vehicles | loop 4s | 4.00 | 1 | 66 | Replaces the RPM layers while the engine module is damaged. |
| `engine_turbine_high` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at high RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_turbine_idle` | 1 | Vehicles | loop 4s | 4.00 | 1 | 58 | Own/other vehicle engine at idle RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_turbine_low` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at low RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_turbine_mid` | 1 | Vehicles | loop 4s | 4.00 | 1 | 62 | Own/other vehicle engine at mid RPM (crossfaded by RPM; PlaybackSpeed tracks RPM). |
| `engine_turbine_overload` | 1 | Vehicles | loop 4s | 4.00 | 1 | 50 | Layered on top when climbing / pushing at max power with low speed (load > 0.85). |
| `engine_turbine_start` | 1 | Vehicles | one-shot | 6.49 | 1 | 65 | Engine start (garage preview, battle start, after repair). Crossfade into idle loop at the last 0.6 s. |
| `engine_turbine_stop` | 1 | Vehicles | one-shot | 6.44 | 1 | 60 | Engine shut-down (destroyed, battle end, garage exit). |
| `transmission_gear_shift` | 2 | Vehicles | one-shot | 0.44 | 1 | 40 | Automatic gear change event. |
| `transmission_reverse_whine` | 1 | Vehicles | loop 3s | 3.00 | 1 | 45 | Layered while driving in reverse (PlaybackSpeed tracks speed). |

#### Tracks (12)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `track_broken_clatter` | 2 | Vehicles | one-shot | 1.90 | 1 | 75 | Track module destroyed while moving (pairs with dmg_track_broken). |
| `track_concrete` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'concrete' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_dirt` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'dirt' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_grass` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'grass' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_gravel` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'gravel' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_metal` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'metal' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_mud` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'mud' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_sand` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'sand' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_snow` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'snow' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_squeal` | 3 | Vehicles | one-shot | 1.60 | 1 | 40 | Sharp turns / pivot steering / braking at speed (rate-limited, random variant). |
| `track_water` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'water' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |
| `track_wood` | 1 | Vehicles | loop 4s | 4.00 | 1 | 55 | Vehicle moving on 'wood' material (PlaybackSpeed = speed/25 km/h, 0.5-1.6x; volume follows speed). |

#### Turret and gun laying (5)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `gun_elevation_servo` | 1 | Vehicles | loop 2s | 2.00 | 1 | 35 | Gun elevating/depressing. |
| `turret_traverse_large` | 1 | Vehicles | loop 3s | 3.00 | 1 | 45 | Turret rotating (heavy). |
| `turret_traverse_small` | 1 | Vehicles | loop 3s | 3.00 | 1 | 45 | Turret rotating (PlaybackSpeed 0.8-1.2 with traverse rate). |
| `turret_traverse_start` | 2 | Vehicles | one-shot | 0.49 | 1 | 45 | Turret starts rotating. |
| `turret_traverse_stop` | 2 | Vehicles | one-shot | 0.41 | 1 | 45 | Turret stops rotating. |

#### Gun firing (18)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `gun_artillery_howitzer_close` | 3 | Weapons | one-shot / close | 3.87 | 1 | 92 | Weapon fired (any vehicle). Pick variant by listener distance band 'close' and crossfade at band edges. |
| `gun_artillery_howitzer_far` | 3 | Weapons | one-shot / far | 4.60 | 1 | 60 | Weapon fired (any vehicle). Pick variant by listener distance band 'far' and crossfade at band edges. |
| `gun_artillery_howitzer_mid` | 3 | Weapons | one-shot / mid | 4.29 | 1 | 78 | Weapon fired (any vehicle). Pick variant by listener distance band 'mid' and crossfade at band edges. |
| `gun_autocannon_burst_close` | 3 | Weapons | one-shot / close | 1.53 | 1 | 92 | Weapon fired (any vehicle). Pick variant by listener distance band 'close' and crossfade at band edges. |
| `gun_autocannon_burst_far` | 3 | Weapons | one-shot / far | 4.32 | 1 | 60 | Weapon fired (any vehicle). Pick variant by listener distance band 'far' and crossfade at band edges. |
| `gun_autocannon_burst_mid` | 3 | Weapons | one-shot / mid | 4.16 | 1 | 78 | Weapon fired (any vehicle). Pick variant by listener distance band 'mid' and crossfade at band edges. |
| `gun_huge_130_183mm_close` | 3 | Weapons | one-shot / close | 3.72 | 1 | 92 | Weapon fired (any vehicle). Pick variant by listener distance band 'close' and crossfade at band edges. |
| `gun_huge_130_183mm_far` | 3 | Weapons | one-shot / far | 4.25 | 1 | 60 | Weapon fired (any vehicle). Pick variant by listener distance band 'far' and crossfade at band edges. |
| `gun_huge_130_183mm_mid` | 3 | Weapons | one-shot / mid | 3.88 | 1 | 78 | Weapon fired (any vehicle). Pick variant by listener distance band 'mid' and crossfade at band edges. |
| `gun_large_88_122mm_close` | 3 | Weapons | one-shot / close | 1.58 | 1 | 92 | Weapon fired (any vehicle). Pick variant by listener distance band 'close' and crossfade at band edges. |
| `gun_large_88_122mm_far` | 3 | Weapons | one-shot / far | 4.29 | 1 | 60 | Weapon fired (any vehicle). Pick variant by listener distance band 'far' and crossfade at band edges. |
| `gun_large_88_122mm_mid` | 3 | Weapons | one-shot / mid | 4.27 | 1 | 78 | Weapon fired (any vehicle). Pick variant by listener distance band 'mid' and crossfade at band edges. |
| `gun_medium_50_85mm_close` | 3 | Weapons | one-shot / close | 1.27 | 1 | 92 | Weapon fired (any vehicle). Pick variant by listener distance band 'close' and crossfade at band edges. |
| `gun_medium_50_85mm_far` | 3 | Weapons | one-shot / far | 4.27 | 1 | 60 | Weapon fired (any vehicle). Pick variant by listener distance band 'far' and crossfade at band edges. |
| `gun_medium_50_85mm_mid` | 3 | Weapons | one-shot / mid | 4.07 | 1 | 78 | Weapon fired (any vehicle). Pick variant by listener distance band 'mid' and crossfade at band edges. |
| `gun_small_20_45mm_close` | 3 | Weapons | one-shot / close | 1.19 | 1 | 92 | Weapon fired (any vehicle). Pick variant by listener distance band 'close' and crossfade at band edges. |
| `gun_small_20_45mm_far` | 3 | Weapons | one-shot / far | 4.51 | 1 | 60 | Weapon fired (any vehicle). Pick variant by listener distance band 'far' and crossfade at band edges. |
| `gun_small_20_45mm_mid` | 3 | Weapons | one-shot / mid | 3.96 | 1 | 78 | Weapon fired (any vehicle). Pick variant by listener distance band 'mid' and crossfade at band edges. |

#### Reload (5)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `reload_autoloader_cycle` | 2 | Weapons | one-shot | 1.62 | 1 | 60 | Autoloader cycles a round (single-shot autoloaders, between drum shots). |
| `reload_breech_close` | 3 | Weapons | one-shot | 0.45 | 1 | 70 | Breech closes at the end of a manual reload. |
| `reload_dual_gun_ready` | 1 | Weapons | one-shot | 0.29 | 1 | 75 | Dual-gun salvo ready. |
| `reload_magazine_sequence` | 1 | Weapons | one-shot | 3.43 | 1 | 65 | Drum/magazine refill started (length ~3.9 s; stretch timing by playing in segments if the reload is longer). |
| `reload_shell_clank` | 3 | Weapons | one-shot | 0.54 | 1 | 60 | Manual loader handling a round (own vehicle, interior perspective). |

#### Shell flight (4)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `shell_distant_thump` | 3 | Weapons | one-shot / far | 4.36 | 1 | 35 | Shot fired beyond the far band (>1.2 km) or from unspotted artillery. |
| `shell_flyby_ap` | 3 | Weapons | one-shot | 1.21 | 1 | 82 | Enemy kinetic round passes within ~15 m of the listener. |
| `shell_flyby_he` | 3 | Weapons | one-shot | 1.53 | 1 | 80 | Enemy HE/HEAT round passes within ~15 m of the listener. |
| `shell_whistle_artillery` | 2 | Weapons | one-shot | 2.44 | 1 | 85 | Artillery shell inbound near listener; ends right before impact (schedule impact at file end). |

#### Shell ground impacts (8)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `impact_concrete` | 3 | Impacts | one-shot | 1.97 | 1 | 70 | Shell (any type) hits terrain/prop of material 'concrete' (HE adds its explosion layer separately if desired). |
| `impact_dirt` | 3 | Impacts | one-shot | 2.32 | 1 | 70 | Shell (any type) hits terrain/prop of material 'dirt' (HE adds its explosion layer separately if desired). |
| `impact_metal_building` | 3 | Impacts | one-shot | 2.45 | 1 | 70 | Shell (any type) hits terrain/prop of material 'metal_building' (HE adds its explosion layer separately if desired). |
| `impact_rock` | 3 | Impacts | one-shot | 2.00 | 1 | 70 | Shell (any type) hits terrain/prop of material 'rock' (HE adds its explosion layer separately if desired). |
| `impact_sand` | 3 | Impacts | one-shot | 2.39 | 1 | 70 | Shell (any type) hits terrain/prop of material 'sand' (HE adds its explosion layer separately if desired). |
| `impact_snow` | 3 | Impacts | one-shot | 1.67 | 1 | 70 | Shell (any type) hits terrain/prop of material 'snow' (HE adds its explosion layer separately if desired). |
| `impact_water` | 3 | Impacts | one-shot | 2.62 | 1 | 70 | Shell (any type) hits terrain/prop of material 'water' (HE adds its explosion layer separately if desired). |
| `impact_wood` | 3 | Impacts | one-shot | 1.77 | 1 | 70 | Shell (any type) hits terrain/prop of material 'wood' (HE adds its explosion layer separately if desired). |

#### Armor results (7)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `armor_blocked` | 3 | Impacts | one-shot | 1.13 | 1 | 95 | Shell hits but does not penetrate (blocked / absorbed by spaced armor). |
| `armor_critical` | 3 | Impacts | one-shot | 0.92 | 1 | 96 | Penetration that damages a module or crew (plays with/after the penetration cue). |
| `armor_hit_taken_blocked` | 3 | Impacts | one-shot | 1.03 | 1 | 94 | Own vehicle hit without penetration (2D). |
| `armor_hit_taken_pen` | 3 | Impacts | one-shot | 1.04 | 1 | 97 | Own vehicle penetrated (2D, interior perspective; duck Vehicles/Ambience). |
| `armor_hit_taken_ricochet` | 3 | Impacts | one-shot | 0.83 | 1 | 92 | Own vehicle hit, shell ricocheted (2D). |
| `armor_penetration` | 3 | Impacts | one-shot | 1.15 | 1 | 96 | Shell penetrates a vehicle (shooter hears it 2D at priority 95; others positional). |
| `armor_ricochet` | 3 | Impacts | one-shot | 1.03 | 1 | 95 | Shell ricochets off armor. |

#### Damage (14)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `dmg_ammo_rack_damaged` | 1 | Impacts | one-shot | 1.74 | 1 | 90 | Ammo rack module damaged (warning: next hit may detonate). |
| `dmg_ammo_rack_detonation_close` | 1 | Impacts | one-shot / close | 5.46 | 1 | 93 | Vehicle destroyed by ammo rack detonation. |
| `dmg_ammo_rack_detonation_far` | 1 | Impacts | one-shot / far | 5.45 | 1 | 70 | Vehicle destroyed by ammo rack detonation. |
| `dmg_engine_damaged` | 2 | Impacts | one-shot | 2.39 | 1 | 82 | Engine module damaged (then switch to the family's _damaged loop). |
| `dmg_fire_extinguished` | 1 | Impacts | one-shot | 2.52 | 1 | 80 | Fire put out (automatic or consumable). |
| `dmg_fire_ignition` | 1 | Impacts | one-shot | 2.73 | 1 | 88 | Vehicle catches fire (then start dmg_fire_loop). |
| `dmg_fire_loop` | 1 | Impacts | loop 5s | 5.00 | 1 | 70 | While a vehicle is burning. |
| `dmg_module_damaged` | 2 | Impacts | one-shot | 0.38 | 1 | 80 | Any module (gun, turret ring, optics, radio, fuel tank) damaged. |
| `dmg_track_broken` | 2 | Impacts | one-shot | 1.38 | 1 | 85 | Track module destroyed. |
| `dmg_vehicle_destroyed_large_close` | 1 | Impacts | one-shot / close | 5.77 | 1 | 90 | Vehicle destroyed (large = light/medium hulls, large = heavy/TD hulls). |
| `dmg_vehicle_destroyed_large_far` | 1 | Impacts | one-shot / far | 5.24 | 1 | 65 | Vehicle destroyed (large = light/medium hulls, large = heavy/TD hulls). |
| `dmg_vehicle_destroyed_medium_close` | 1 | Impacts | one-shot / close | 4.02 | 1 | 90 | Vehicle destroyed (medium = light/medium hulls, large = heavy/TD hulls). |
| `dmg_vehicle_destroyed_medium_far` | 1 | Impacts | one-shot / far | 4.33 | 1 | 65 | Vehicle destroyed (medium = light/medium hulls, large = heavy/TD hulls). |
| `dmg_wreck_burning_loop` | 1 | Impacts | loop 6s | 6.00 | 1 | 30 | Wreck of a destroyed vehicle (fade out after 30-60 s). |

#### Environment destruction (7)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `env_brick_wall_collapse` | 1 | Impacts | one-shot | 3.08 | 1 | 60 | Destructible masonry wall destroyed. |
| `env_bridge_creak` | 2 | Impacts | one-shot | 2.35 | 1 | 35 | Heavy vehicle on a wooden bridge (random every few seconds). |
| `env_bush_rustle` | 3 | Impacts | one-shot | 0.99 | 1 | 25 | Vehicle pushes through bushes/foliage. |
| `env_fence_break` | 3 | Impacts | one-shot | 1.56 | 1 | 50 | Vehicle drives through a fence. |
| `env_metal_container_impact` | 2 | Impacts | one-shot | 1.66 | 1 | 50 | Vehicle rams / shell hits a metal container or tank. |
| `env_tree_fall` | 2 | Impacts | one-shot | 4.05 | 1 | 50 | Vehicle fells a tree. |
| `env_wooden_building_collapse` | 1 | Impacts | one-shot | 3.71 | 1 | 60 | Destructible wooden building destroyed. |

#### UI (21)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `ui_achievement_unlocked` | 1 | UI | one-shot | 1.88 | 2 | 82 | Achievement / medal earned. |
| `ui_back` | 1 | UI | one-shot | 0.43 | 2 | 60 | Back / cancel / dismiss. |
| `ui_battle_found` | 1 | UI | one-shot | 2.56 | 2 | 90 | Matchmaking found a battle. |
| `ui_click` | 1 | UI | one-shot | 0.24 | 2 | 60 | Button pressed. |
| `ui_close_panel` | 1 | UI | one-shot | 0.35 | 2 | 55 | Panel/modal closes. |
| `ui_confirm` | 1 | UI | one-shot | 0.42 | 2 | 70 | Confirm / accept / apply. |
| `ui_countdown_go` | 1 | UI | one-shot | 0.52 | 2 | 90 | Battle starts. |
| `ui_countdown_tick` | 1 | UI | one-shot | 0.24 | 2 | 85 | Pre-battle countdown second. |
| `ui_error` | 1 | UI | one-shot | 0.56 | 2 | 75 | Invalid action / insufficient funds / locked. |
| `ui_hover` | 1 | UI | one-shot | 0.18 | 2 | 40 | Pointer/selection moves onto an interactive element. |
| `ui_level_up` | 1 | UI | one-shot | 1.75 | 2 | 80 | Crew/vehicle/account level up. |
| `ui_mission_complete` | 1 | UI | one-shot | 2.48 | 2 | 85 | Mission / campaign task complete. |
| `ui_notification` | 1 | UI | one-shot | 0.64 | 2 | 65 | Toast notification arrives. |
| `ui_open_panel` | 1 | UI | one-shot | 0.38 | 2 | 55 | Panel/modal opens. |
| `ui_purchase` | 1 | UI | one-shot | 0.71 | 2 | 80 | Purchase completed (credits/gold). |
| `ui_research_complete` | 1 | UI | one-shot | 1.81 | 2 | 82 | Module/vehicle researched. |
| `ui_slider_tick` | 1 | UI | one-shot | 0.11 | 2 | 30 | Slider step changed (rate-limit to 30/s). |
| `ui_tab_switch` | 1 | UI | one-shot | 0.26 | 2 | 50 | Tab / carousel page changed. |
| `ui_toggle_off` | 1 | UI | one-shot | 0.24 | 2 | 50 | Toggle switched off. |
| `ui_toggle_on` | 1 | UI | one-shot | 0.26 | 2 | 50 | Toggle switched on. |
| `ui_vehicle_unlocked` | 1 | UI | one-shot | 2.72 | 2 | 85 | New vehicle unlocked / bought. |

#### Battle information cues (12)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `cue_ally_destroyed` | 1 | UI | one-shot | 1.09 | 2 | 88 | Teammate destroyed. |
| `cue_capture_complete` | 1 | UI | one-shot | 2.08 | 2 | 92 | Base capture completed. |
| `cue_capture_warning_loop` | 1 | UI | loop 2s | 2.00 | 2 | 92 | Your base is being captured (loop while capture points > 0). |
| `cue_enemy_destroyed` | 1 | UI | one-shot | 0.60 | 2 | 90 | Enemy destroyed (louder variant when it was your kill: +3 dB). |
| `cue_enemy_spotted` | 1 | UI | one-shot | 0.68 | 2 | 88 | An enemy is newly spotted by your team. |
| `cue_low_hp_alarm` | 1 | UI | one-shot | 0.68 | 2 | 86 | Own HP drops below 25 %. |
| `cue_low_hp_heartbeat_loop` | 1 | UI | loop 3s | 3.20 | 2 | 84 | Own HP below 15 % (volume rises as HP falls). |
| `cue_objective_update` | 1 | UI | one-shot | 1.03 | 2 | 80 | Objective/mission progress updated in battle. |
| `cue_reload_complete` | 1 | UI | one-shot | 0.35 | 2 | 87 | Own gun loaded and ready. |
| `cue_sixth_sense` | 1 | UI | one-shot | 1.38 | 2 | 100 | Own vehicle has been spotted by the enemy (highest-priority cue; ducks everything else ~4 dB). |
| `cue_target_locked` | 1 | UI | one-shot | 0.37 | 2 | 75 | Auto-aim/target lock acquired. |
| `cue_target_unlocked` | 1 | UI | one-shot | 0.34 | 2 | 60 | Target lock lost/released. |

#### Radio / Voice (9)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `dmg_crew_injured` | 1 | Voice | one-shot | 1.36 | 2 | 88 | Crew member injured (2D, own vehicle). |
| `radio_cmd_attack` | 1 | Voice | one-shot | 0.90 | 2 | 80 | Teammate issues the 'attack' quick command (pair with minimap ping). |
| `radio_cmd_capture` | 1 | Voice | one-shot | 1.15 | 2 | 80 | Teammate issues the 'capture' quick command (pair with minimap ping). |
| `radio_cmd_defend` | 1 | Voice | one-shot | 1.14 | 2 | 80 | Teammate issues the 'defend' quick command (pair with minimap ping). |
| `radio_cmd_follow` | 1 | Voice | one-shot | 0.98 | 2 | 80 | Teammate issues the 'follow' quick command (pair with minimap ping). |
| `radio_cmd_help` | 1 | Voice | one-shot | 1.15 | 2 | 80 | Teammate issues the 'help' quick command (pair with minimap ping). |
| `radio_cmd_retreat` | 1 | Voice | one-shot | 1.03 | 2 | 80 | Teammate issues the 'retreat' quick command (pair with minimap ping). |
| `radio_cmd_spotted` | 1 | Voice | one-shot | 0.87 | 2 | 80 | Teammate issues the 'spotted' quick command (pair with minimap ping). |
| `radio_static` | 3 | Voice | one-shot | 0.54 | 2 | 40 | Generic radio chatter texture / comms noise. |

#### Ambience beds and spots (26)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `amb_desert_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'desert' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_desert_spot_metal_creak` | 2 | Ambience | one-shot | 4.96 | 1 | 15 | Random 3D emitter around the listener on 'desert' maps (every 8-30 s, 60-300 m away). |
| `amb_desert_spot_sand_gust` | 1 | Ambience | one-shot | 2.52 | 1 | 15 | Random 3D emitter around the listener on 'desert' maps (every 8-30 s, 60-300 m away). |
| `amb_fortress_old_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'fortress_old' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_fortress_old_spot_bell_toll` | 1 | Ambience | one-shot | 7.13 | 1 | 15 | Random 3D emitter around the listener on 'fortress_old' maps (every 8-30 s, 60-300 m away). |
| `amb_fortress_old_spot_crow` | 2 | Ambience | one-shot | 2.63 | 1 | 15 | Random 3D emitter around the listener on 'fortress_old' maps (every 8-30 s, 60-300 m away). |
| `amb_harbor_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'harbor' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_harbor_spot_buoy_bell` | 1 | Ambience | one-shot | 5.01 | 1 | 15 | Random 3D emitter around the listener on 'harbor' maps (every 8-30 s, 60-300 m away). |
| `amb_harbor_spot_crane_clank` | 2 | Ambience | one-shot | 3.99 | 1 | 15 | Random 3D emitter around the listener on 'harbor' maps (every 8-30 s, 60-300 m away). |
| `amb_harbor_spot_foghorn` | 1 | Ambience | one-shot | 6.78 | 1 | 15 | Random 3D emitter around the listener on 'harbor' maps (every 8-30 s, 60-300 m away). |
| `amb_harbor_spot_gull` | 3 | Ambience | one-shot | 1.95 | 1 | 15 | Random 3D emitter around the listener on 'harbor' maps (every 8-30 s, 60-300 m away). |
| `amb_mountain_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'mountain' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_mountain_spot_gust_howl` | 1 | Ambience | one-shot | 3.31 | 1 | 15 | Random 3D emitter around the listener on 'mountain' maps (every 8-30 s, 60-300 m away). |
| `amb_mountain_spot_rockfall` | 2 | Ambience | one-shot | 5.13 | 1 | 15 | Random 3D emitter around the listener on 'mountain' maps (every 8-30 s, 60-300 m away). |
| `amb_plains_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'plains' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_plains_spot_distant_thunder` | 2 | Ambience | one-shot | 7.87 | 1 | 15 | Random 3D emitter around the listener on 'plains' maps (every 8-30 s, 60-300 m away). |
| `amb_plains_spot_insect_flyby` | 1 | Ambience | one-shot | 2.43 | 1 | 15 | Random 3D emitter around the listener on 'plains' maps (every 8-30 s, 60-300 m away). |
| `amb_river_town_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'river_town' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_river_town_spot_church_bell` | 2 | Ambience | one-shot | 5.66 | 1 | 15 | Random 3D emitter around the listener on 'river_town' maps (every 8-30 s, 60-300 m away). |
| `amb_river_town_spot_shutter_bang` | 2 | Ambience | one-shot | 1.92 | 1 | 15 | Random 3D emitter around the listener on 'river_town' maps (every 8-30 s, 60-300 m away). |
| `amb_temperate_valley_industrial_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'temperate_valley_industrial' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_temperate_valley_industrial_spot_bird` | 3 | Ambience | one-shot | 1.04 | 1 | 15 | Random 3D emitter around the listener on 'temperate_valley_industrial' maps (every 8-30 s, 60-300 m away). |
| `amb_temperate_valley_industrial_spot_machinery_clank` | 2 | Ambience | one-shot | 3.64 | 1 | 15 | Random 3D emitter around the listener on 'temperate_valley_industrial' maps (every 8-30 s, 60-300 m away). |
| `amb_winter_bed` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Map 'winter' biome: always-on 2D bed (crossfade 3 s on load). |
| `amb_winter_spot_ice_crack` | 3 | Ambience | one-shot | 3.48 | 1 | 15 | Random 3D emitter around the listener on 'winter' maps (every 8-30 s, 60-300 m away). |
| `amb_winter_spot_wind_whistle` | 1 | Ambience | one-shot | 2.91 | 1 | 15 | Random 3D emitter around the listener on 'winter' maps (every 8-30 s, 60-300 m away). |

#### Weather (4)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `wx_rain_loop` | 1 | Ambience | loop 30s | 30.00 | 2 | 25 | Weather layer: rain (2D). |
| `wx_sandstorm_loop` | 1 | Ambience | loop 30s | 30.00 | 2 | 25 | Weather layer: sandstorm (2D). |
| `wx_snowstorm_loop` | 1 | Ambience | loop 30s | 30.00 | 2 | 25 | Weather layer: snowstorm (2D). |
| `wx_thunder` | 3 | Ambience | one-shot | 7.23 | 2 | 30 | Storm weather: random every 15-60 s (a rarely). |

#### Hangar / garage (4)

| Key | Var | Bus | Type | Len s | Ch | Prio | Gameplay event |
|---|---|---|---|---|---|---|---|
| `hangar_compressor_cycle` | 1 | Ambience | one-shot | 7.18 | 1 | 20 | Garage: occasional (every 60-120 s). |
| `hangar_distant_tools` | 3 | Ambience | one-shot | 3.53 | 1 | 20 | Garage: random 3D emitters every 10-40 s. |
| `hangar_pa_chime` | 2 | Ambience | one-shot | 4.10 | 2 | 40 | Garage: before/after notifications such as 'battle found' or events (2D). |
| `hangar_room_tone` | 1 | Ambience | loop 40s | 40.00 | 2 | 20 | Garage/hangar scene: always-on 2D bed. |

<!-- END SOUND LIST -->

---

## 11. Music

All music is original and composed **as data** in `tools/audio/scores/` (tempo, meter, key, chord
progressions, motif statements, parts and dynamics). `tools/audio/generate_music.py` renders it with
the instrument models in `tools/audio/synth/instruments.py` through the loop-safe renderer in
`tools/audio/synth/music.py`. No samples, sample libraries or recordings are used: every voice is a
synthesis model (detuned-saw string sections, additive brass, formant choir, modal bells, piano and
plucked strings, membrane drums). Files go to `assets/music/` with `assets/music/catalog.json`.

### 11.1 Identity: the HULLDOWN call

One motif carries the identity of the whole score. It is two bars of 4/4 in D minor:

```
D4 (dotted 8th)  D4 (16th)  A4 (quarter)  Bb4 (dotted quarter)  G4 (8th) | A4 (whole)
degrees 1 1 5 b6 4 5
```

* **Military:** the dotted pickup on the tonic is a bugle and drum call.
* **Heroic:** the rising fifth.
* **Somber:** the minor sixth sighs back to the fifth through the fourth.
* **Unresolved:** it ends open on the dominant. The fight is not over.

Every cue quotes it, and the score tags each quotation, so the catalogue lists each statement (`motif[]`:
part, form, bar, beat). Forms used:

| Form | Where |
|---|---|
| prime (minor) | main theme horns and trumpets, garage horn, results horn, battle A′ section, endgame, loading trombones, iron valley, frozen front, dust basin (oud), river town |
| augmented (×2) | main theme bridge (horns under the violin melody), endgame climax (trumpets) |
| major (raised 6th) | victory fanfare, open plains, battle anthem (in F, the relative major) |
| Dorian | old fortress (male choir in parallel fifths), harbor district (6/8, accordion) |
| Lydian (raised 4th) | mountain pass (flute and violins answer the alphorn) |
| call head (1 1 5) | battle brass stabs, Phrygian D/Eb "menace" in the battle, endgame and loading, horn calls, echoes |
| lament (falls instead of rising) | defeat (the horn cannot finish the call) |
| 3/4 and 6/8 rhythms | river town waltz, harbor sway |

### 11.2 Cues

Every cue is in D: D minor for the core score, with modal colours for the maps. All files are
48 kHz stereo OGG Vorbis.

<!-- BEGIN MUSIC LIST -->
_Generated from `assets/music/catalog.json` by `tools/audio/doc_sound_list.py` - 19 files, 2 stinger banks._

| Key | State | Type | Len s | Tempo / meter | Key | Bar 1 at | LUFS | Vol | Motif | Upload as |
|---|---|---|---|---|---|---|---|---|---|---|
| `main_theme` | MENU | loop | 106.67 | 72 BPM 4/4 | D minor | 591 smp | -18.0 | 0.8 | 7x (aug, full, head) | `main_theme.ogg` |
| `garage_theme` | GARAGE | loop | 132.00 | 80 BPM 4/4 | D minor | 690 smp | -20.0 | 0.6 | 6x (full) | `garage_theme.ogg` |
| `loading_theme` | LOADING | loop | 60.00 | 96 BPM 4/4 | D minor | 764 smp | -19.0 | 0.7 | 8x (full, head) | `loading_theme.ogg` |
| `battle_base` | BATTLE | loop (base stem) | 80.00 | 120 BPM 4/4 | D minor | 203 smp | -22.4 | 0.8 | - | `battle_base.ogg` |
| `battle_mid` | BATTLE | loop (mid stem) | 80.00 | 120 BPM 4/4 | D minor | 203 smp | -22.6 | 0.8 | - | `battle_mid.ogg` |
| `battle_high` | BATTLE | loop (high stem) | 80.00 | 120 BPM 4/4 | D minor | 203 smp | -20.7 | 0.8 | 22x (full, head, relmajor, transposed) | `battle_high.ogg` |
| `battle_endgame` | BATTLE_ENDGAME | loop | 64.00 | 120 BPM 4/4 | D minor | 537 smp | -17.0 | 0.85 | 10x (aug, full, head) | `battle_endgame.ogg` |
| `victory` | RESULT_STINGER | stinger | 26.89 | 80 BPM 4/4 | D major | 10 ms | -16.0 | 0.9 | 2x (full) | `banks/music_stingers_1.ogg` |
| `defeat` | RESULT_STINGER | stinger | 26.68 | 60 BPM 4/4 | D minor | 10 ms | -18.0 | 0.85 | 2x (head, lament) | `banks/music_stingers_1.ogg` |
| `draw` | RESULT_STINGER | stinger | 16.60 | 72 BPM 4/4 | D (open, sus) | 10 ms | -18.5 | 0.8 | 2x (full, head) | `banks/music_stingers_1.ogg` |
| `results_theme` | RESULTS | loop | 60.00 | 64 BPM 4/4 | D minor / F major | 498 smp | -21.0 | 0.6 | 1x (full) | `results_theme.ogg` |
| `map_dust_basin` | LOADING_MAP_STINGER | stinger | 15.46 | 90 BPM 4/4 | D Phrygian dominant | 10 ms | -18.0 | 0.8 | 1x (full) | `banks/music_stingers_1.ogg` |
| `map_frozen_front` | LOADING_MAP_STINGER | stinger | 17.34 | 72 BPM 4/4 | D minor (add9) | 10 ms | -18.0 | 0.8 | 2x (full) | `banks/music_stingers_1.ogg` |
| `map_harbor_district` | LOADING_MAP_STINGER | stinger | 14.64 | 120 BPM 6/8 | D Dorian | 10 ms | -18.0 | 0.8 | 1x (dorian) | `banks/music_stingers_2.ogg` |
| `map_iron_valley` | LOADING_MAP_STINGER | stinger | 14.04 | 100 BPM 4/4 | D minor (Phrygian) | 10 ms | -18.1 | 0.8 | 2x (full, head) | `banks/music_stingers_2.ogg` |
| `map_mountain_pass` | LOADING_MAP_STINGER | stinger | 19.01 | 60 BPM 4/4 | D Lydian | 10 ms | -18.0 | 0.8 | 3x (full, head) | `banks/music_stingers_2.ogg` |
| `map_old_fortress` | LOADING_MAP_STINGER | stinger | 18.51 | 64 BPM 4/4 | D Dorian | 10 ms | -18.0 | 0.8 | 3x (dorian, head) | `banks/music_stingers_2.ogg` |
| `map_open_plains` | LOADING_MAP_STINGER | stinger | 16.76 | 72 BPM 4/4 | D Mixolydian | 10 ms | -18.0 | 0.8 | 1x (full) | `banks/music_stingers_2.ogg` |
| `map_river_town` | LOADING_MAP_STINGER | stinger | 15.51 | 144 BPM 3/4 | D minor | 10 ms | -18.0 | 0.8 | 1x (full) | `banks/music_stingers_2.ogg` |
<!-- END MUSIC LIST -->

* **`main_theme`** (login and main menu): a distant horn call over a D pedal, then the motif as a horn
  solo. Full brass and a military snare restate it, followed by a lyrical relative-major bridge with
  the motif augmented in the horns. A tutti coda winds back into the intro.
* **`garage_theme`**: calm military theme. Piano arpeggios run over an i–VI–III–VII vamp with a solo
  horn on the motif, then a string interlude, a brushed march snare, and celesta and flute quotes. It
  is 132 s long so it does not wear out in the garage.
* **`loading_theme`** (tension build, 24 bars / 60 s): ticking pulse, D pedal and an endless
  Shepard-Risset riser, with a motif ostinato in the celli. Then come the horn call, the trombone motif
  answered by the full call in the horns (bars 13–16), a Phrygian D/Eb menace, a hit at bar 21, and a
  rebuild into the loop point. (QA extended it from 20 bars / 50 s, which was under the 60–150 s window
  for music loops.)
* **Battle stems**: `battle_base` (low pulse and percussion), `battle_mid` (ostinato and harmony) and
  `battle_high` (full drums, brass with the motif, choir). They share one tempo, key, length and
  sample grid, and are mastered together, so base + mid + high is the full mix at −17 LUFS.
* **`battle_endgame`**: the last 2 minutes or a few tanks left. A 16th-note lament bass (D–C–Bb–A)
  drives a ticking clock and a timpani ostinato, the Phrygian menace returns, and the motif is
  augmented in the trumpets over full choir. It uses the same grid as the stems.
* **`victory`** / **`defeat`** / **`draw`**:
  * **Victory:** a D-major brass fanfare of the motif ending in a held tutti chord.
  * **Defeat:** a lone horn that stalls on Bb–A over a muffled timpani and a distant bell.
  * **Draw:** the motif over suspended chords on a D pedal, ending on a bare fifth.
* **`results_theme`**: a calm piano-and-strings cycle (Bb–F–Gm–Dm) with the motif on a soft horn.
  It is neutral enough to follow any result.
* **Map stingers** (`map_<mapId>`, 10–20 s, for the loading screen). Each map has its own
  instrumentation and mode:

| Map | Biome | Mode | Instrumentation |
|---|---|---|---|
| `iron_valley` | temperate_valley_industrial | D minor / Phrygian Eb | anvils on 3+3+2, trombone and tuba motif, celli pulse, taiko |
| `dust_basin` | desert | D Phrygian dominant (Hijaz) | oud (tremolo on the held A), duduk, maqsum frame drum |
| `frozen_front` | winter | D minor (add9) | celesta and glass bells, choir "oo", string harmonics, end-blown flute, cathedral reverb |
| `old_fortress` | fortress_old | D Dorian | male choir in parallel fifths (organum), organ, church bell, timpani |
| `harbor_district` | harbor | D Dorian, 6/8 | accordion and comping, pizzicato bass, low tuba "foghorn" swell, buoy bell |
| `mountain_pass` | mountain | D Lydian | alphorn on natural harmonics (flat 7th partial) through the valley-echo IR, flute and violins |
| `river_town` | river_town | D minor, 3/4 waltz | mandolin tremolo, accordion oom-pah-pah, pizzicato bass, church bell |
| `open_plains` | plains | D Mixolydian | horn (major form), open-string guitar, wide strings, soft timpani |

### 11.3 Technical standards (validated by `tools/audio/validate_music.py`)

| Property | Standard |
|---|---|
| Format | OGG Vorbis, 48 kHz, **stereo**, quality 0.6 (18 MB for all 19 files plus 2 banks) |
| Headroom | Sample peak ≤ −1.0 dBFS and true peak ≤ −0.5 dBTP on the decoded file. This applies to every stem *and* to base + mid + high summed |
| Loudness (integrated) | main −18, garage −20, loading −19, battle all layers −17 (base −22.4, mid −22.7, high −20.7 alone), endgame −17, victory −16, defeat −18, draw −18.5, results −21, maps −18 LUFS |
| Mastering | 28 Hz high-pass, then linked glue compression (2:1). Then a linked 3 ms look-ahead limiter detecting on the full mix and every stem, so stems keep their balance and still sum cleanly |
| Loops | Rendered **periodic by construction**. Note releases and reverb tails wrap into the loop start (an overlap-add seam). Reverb is circular convolution, and filters, compressor and limiter run circularly. The loop never relies on a crossfade at runtime |
| Loop start | All stems of a cue are rotated by one common offset (0–20 ms) to the quietest, smoothest common point just before bar 1. Bar 1 beat 1 is at `loop.gridOffsetSamples` |
| Stingers | 10 ms silent lead-in (`stinger.leadS`). Bar 1 starts there. `stinger.bodyEndS` = end of the last bar. Natural ring-out trimmed at −70 dB with a 250 ms fade. The first downbeat gets a 5 ms fade-in (10 or 20 ms if needed), chosen so that Vorbis pre-echo leaves the decoded lead-in below −62 dBFS |
| Grid | Tempos give an integer number of samples per beat (72 BPM = 40 000, 120 BPM = 24 000). Battle stems and endgame share 120 BPM: 96 000 samples per bar |
| Determinism | Seeded per cue, part and note. Byte-identical re-renders (checked on `draw`) |

### 11.4 MusicDirector state machine

The client `MusicDirector` reads `director` from the music catalogue (the same table as below).

```
BOOT ─► MENU (main_theme) ─► GARAGE (garage_theme) ─► LOADING (map_<mapId> stinger ─► loading_theme)
                                   ▲                              │ countdown "GO" (bar 1 lands on GO)
                                   │                              ▼
          RESULTS (results_theme) ◄─ RESULT_STINGER ◄── BATTLE (base / +mid / +high by intensity)
                                     (victory|defeat|draw)        │ endgame trigger (one way)
                                                    ▲             ▼
                                                    └──── BATTLE_ENDGAME (battle_endgame)
```

| Transition | Timing |
|---|---|
| BOOT → MENU | 2 s fade-in |
| MENU → GARAGE, RESULTS → GARAGE, * → MENU | 3 s (2 s to MENU) equal-power crossfade, unquantised |
| GARAGE → LOADING | Garage fades out over 1.5 s. The map stinger plays at once from its bank. `loading_theme` starts at the stinger's `bodyEndS` with a 1.5 s overlap |
| LOADING → BATTLE | `loading_theme` fades out over 0.6 s. All three stems start **together** at volume 0, scheduled so bar 1 lands on "GO" (`Play(atTime)` against `GetMixerTime()` where available). Base fades in over 1 bar |
| BATTLE → BATTLE_ENDGAME | Crossfade over 2 s (1 bar), starting on the next bar line. Same grid, so the endgame enters in time. One-way |
| BATTLE / ENDGAME → RESULT_STINGER | Battle music fades out over 0.5 s, quantised to the next beat (at most 0.5 s wait). The stinger plays from its bank region |
| RESULT_STINGER → RESULTS | `results_theme` starts at the stinger's `bodyEndS` with a 3 s crossfade into the stinger's ring-out |

### 11.5 Battle intensity (vertical layering)

Intensity `I` (0–1) is a weighted sum. It rises with a 1.5 s time constant and falls with an 8 s
time constant.

| Input | Weight | Definition |
|---|---|---|
| combat | 0.35 | Shots fired or received by the own tank or within 150 m in the last 10 s, ÷ 6, capped at 1 |
| threat | 0.25 | Spotted enemies within 300 m, ÷ 3, capped at 1 |
| ownDamage | 0.20 | 1 − ownHP / maxHP |
| closeness | 0.10 | 1 − \|teamHpShare − 0.5\| × 2 (a close fight is tense) |
| time | 0.10 | Elapsed / battle length |

| Layer | On | Off | Fade in / out | Rule |
|---|---|---|---|---|
| `battle_base` | always | n/a | 1 bar at GO | — |
| `battle_mid` | I ≥ 0.30 | I < 0.20 | 4 s / 8 s | Changes start on a bar line |
| `battle_high` | I ≥ 0.60 | I < 0.45 | 2 s / 8 s | Changes start on a bar line |

* **Hold:** after any layer change, the layer set is held for at least **4 bars** (8 s). The on/off
  gap is hysteresis, so layers do not flutter.
* **Stem sync:** the three stems always play, and inactive ones sit at volume 0, so they never drift
  apart. If the reported `TimePosition`s differ by more than 20 ms, the director re-seeks mid and
  high to base on the next bar line, while they are silent.
* **Endgame trigger** (any one): time left ≤ 120 s, ≤ 6 vehicles alive in total, one team with ≤ 2
  alive, or \|team HP share difference\| ≥ 0.4. There is no way back to the stems.
* **Own tank destroyed (spectating):** music −6 dB and a 2 kHz low-pass on the Music bus.
* **Bar maths:** bar `n` of a loop starts at `gridOffsetS + (n − 1) × barS`, modulo `durationS`.
  The next bar line is found from the player's `TimePosition`.

### 11.6 Ducking and mix

The Music bus fader is **0.6 in menus, 0.5 in the garage and 0.45 in battle** (`director.busFader`).
Music is the first thing players turn off, so it never masks gameplay cues.

| Trigger | Music duck | Attack / hold / release |
|---|---|---|
| Voice bus active (radio, crew) | −6 dB | 20 ms / while active / 400 ms |
| Own gun fired | −4 dB | 5 ms / 150 ms / 500 ms |
| `armor_hit_taken_*` | −6 dB | 5 ms / 300 ms / 800 ms |
| Explosion within 60 m | −6 dB | 5 ms / 500 ms / 1.2 s |
| `cue_sixth_sense` | −4 dB | 10 ms / 1 s / 600 ms |
| Garage fanfares (`ui_vehicle_unlocked`, ...) | −5 dB | 20 ms / sound length / 600 ms |
| Low-HP heartbeat | −3 dB | 200 ms / while active / 1 s |

These match §3.3. Ducks of the Music bus do not add up: the deepest active one wins. Result
stingers and map stingers play on the Music bus at their `suggested.volume` and are never ducked by
UI sounds.

### 11.7 Roblox playback notes

* **Loops:** `AudioPlayer.Looping = true` on the whole file. The files are seamless, so never set
  `LoopRegion` on music. Start a loop with a fade of at least 50 ms (every transition above already
  fades). Loop files start close to zero (largest first sample 0.041 of full scale).
* **Stingers** play from their bank: `PlaybackRegion = NumberRange.new(bankRegion.startS, bankRegion.endS)`.
* The `suggested.volume` in the catalogue is the `AudioPlayer` volume. Bus faders and ducking are
  applied on top.

### 11.8 Pipeline and uploads

```bash
python3 tools/audio/generate_music.py           # compose + render + master + encode all cues, pack stinger banks, write catalog (~4.5 min on 4 cores)
python3 tools/audio/generate_music.py --only 'map_*,draw'   # partial re-render (catalogue is merged)
python3 tools/audio/generate_music.py --list    # cue list: tempo, meter, bars, length, parts, notes
python3 tools/audio/validate_music.py           # all checks + review sheets -> build/audio_review/music_validation.json, music_*.png
python3 tools/audio/doc_sound_list.py           # refresh the generated tables in this document
```

* **Uploads:** upload the **8 loops** individually. The 11 stingers (results plus maps) are packed
  into **2 banks** (`assets/music/banks/music_stingers_{1,2}.ogg`, ≤ 120 s each, 0.5 s gaps), and
  `bankRegion` in each catalogue entry locates them. That is 10 music uploads, and 95 together with
  the SFX, which fits the 100-per-30-days limit for unverified accounts. The individual stinger files
  stay in the repository for review and for verified accounts.
* Lossless masters are written to `build/music_masters/*.flac` (git-ignored). The bank packer reads
  them, so banks are a single lossy generation.
* **Adding a cue:** write a function returning a `Cue` in `tools/audio/scores/*.py` and register it in
  `scores/__init__.py`. Quote the motif with `scores.common.motif()` or `head()` so it is tagged.
  Regenerate, validate, view the sheets, and run `doc_sound_list.py`.

### 11.9 Validation (current run)

`python3 tools/audio/validate_music.py`: **0 errors, 1 warning** (19 files, 2 banks).

* **Headroom:** highest sample peak −1.40 dBFS and highest true peak −1.40 dBTP. The summed battle
  stems peak at −1.28 dBFS. Largest DC offset is 0.00008, and there are no clipped runs. Every
  stinger's decoded lead-in is at or below −67.6 dBFS (§11.3).
* **Loudness:** every cue is within 0.1 dB of its target, measured with the corrected BS.1770 meter
  (§2). Battle base + mid + high measures −17.03 LUFS.
* **Loop seams** (decoded files): worst jump ratio 0.14 (limit 1.0). The spectral and level change
  across each seam is no larger than at the same loop's ordinary bar lines (results_theme: level
  change 6.6 dB, against up to 6.4 dB at bar lines from its accented piano downbeats, within the
  1 dB allowance). `qa_audio.py` measures the same seam against every bar line with 50 ms windows:
  10.2 dB against up to 12.2 dB elsewhere.
* **Stem alignment:**
  * Identical lengths (3 840 000 samples = 40 bars) and identical grid offset (203 samples).
  * Onset cross-correlation lags between stems are 0 and 1 hop (2.5 ms).
  * Folded on the 16th-note grid, onset energy lands within 2.5–5 ms of the declared grid on every
    stem, after calibrating the detector with a synthetic click train. Bowed and blown attacks speak
    slightly after a click.
  * The stems agree with each other within 2.5 ms.
* **Tempo:** onset-autocorrelation tempo matches the declared tempo at a metrical level on every loop
  (the 3+3+2 battle_base pulse reads as its dotted level, 80 = 2/3 × 120).
* **Tonality:** the declared key (or its relative or same-pitch-set mode) ranks in the top 3 of the 24
  Krumhansl–Kessler key profiles for every cue except `draw`. The draw is open fifths and sus chords
  by design: it ranks 4th, with D as the strongest bass pitch class. That is the one warning.
* **Motif:** every cue states it. At the statement points, the audio's chroma shows the call's tonic
  and fifth among the three strongest pitch classes in 140 of 148 windows.
* **Banks:** each region matches its standalone file (envelope correlation ≥ 0.9995).
* **Determinism:** a re-render is byte-identical.
* **Melody salience** (measured during development, on dry parts): leads hold 88–97 % of their
  energy in time–frequency cells where they dominate the rest of the mix.
* **Review sheets:** `build/audio_review/music_themes.png`, `music_battle_stems.png`,
  `music_battle_grid.png`, `music_stingers.png`, `music_maps.png`, `music_seams.png` and
  `music_motif_pitch.png` (semitone axis).

### 11.10 Still to verify by ear

These are measured, not listened to. Before shipping, someone should listen for:

* **Brass realism:** the additive horns and trumpets are the most synthetic-sounding voices.
* **Fatigue:** the balance of the battle layers on laptop and phone speakers, and fatigue from the
  80 s battle loop over a 7–10 minute match. If it fatigues, add a second battle loop variant on the
  same grid.
* **Map stinger character:** whether each stinger reads as its biome.
