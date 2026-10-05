# 00 — HULLDOWN Design Decisions (read first)

> **Authoritative for values and rules** (2026-10-05, Game/Technical Director), distilled from fact-checked reports
> 01–09, `docs/ARCHITECTURE.md`, `docs/design/brand-art.md`, `docs/design/audio.md`.
> **Use:** each row = decision · basis/confidence · source (`01-R2` report 01 recommendation R2, `-S7` summary item,
> `§` finding). **Precedence:** this doc > research reports; `ARCHITECTURE.md` > this doc on code structure/data flow,
> this doc > it on numbers; `brand-art.md` rules visuals/copy, `audio.md` sound design. Change a value here and in
> `Shared/Config` in one commit. Config uses real units; studs only at the boundary (`Units.STUDS_PER_METER = 3`;
> report 01's 0.28 m stud is converted).
> **B/C legend:** **W** WoT-faithful · **O** OUR DESIGN CHOICE (reason given) · **P** Roblox platform fact (creator-docs
> 2026-10-02) · **A** architecture. **H** sourced · **M** single source / unverified WoT value · **L** recollection or
> untested (tune by playtest/telemetry). Abbrev.: α alpha, T plate thickness, L crew level, cd cooldown, VR view range,
> LT/MT/HT/TD/SPG = `light`/`medium`/`heavy`/`td`/`artillery`.

## 0. Locked

HULLDOWN · factions `iron_union`, `crown_industries`, `eastern_armor`, `desert_corps`, `mountain_republic`,
`northern_federation` · 5 classes · Tiers I–XI · Credits, Bullion, Vehicle XP, Free XP, Crew XP, Campaign Tokens
(**Merit rejected**, §11) · 15 v 15 Random + labelled bot fill · server-authoritative 30 Hz, spotting-filtered
replication, pure Shared modules tested in Lune · 3 studs/m (50 m = 150 studs, 445 = 1,335, 564 = 1,692, 1 km = 3,000).

## 1. Ballistics and penetration

| Topic | Decision | B/C | Src |
|---|---|---|---|
| Families | AP, APCR, HEAT, HE, HESH; "premium" = same family, more pen | W·H | 01-S1 |
| Defaults | Premium α = AP α, pen ×1.30; HE α = 1.30 AP α, pen cal/2; HESH pen 1.6 cal; per-gun overrides | W ratios·M | 01-R1 |
| Normalization | AP 5°, APCR 2°, others 0° | W·M | 01-S2 |
| 2-cal / 3-cal | Kinetic, cal > 2T (strict): n' = n·1.4·cal/(2T). cal > 3T: never ricochets (not HEAT) | W·M | 01-S3/S4 |
| Ricochet | θ > 70° AP/APCR, > 85° HEAT; HE/HESH never | W·M | 01-S5 |
| Continuation | Reflect, fly on; max 1 (2nd deletes); kinetic pen ×0.75, HEAT ×1; no HP dmg (hit external module still damaged); can hit anyone but the shooter; ally = consumed, 0 dmg | O (WoT rule unverified)·L | 01-R2 |
| Effective T | T_eff = T / max(0.05, cos(max(0, θ − n'))); pen ≥ T_eff penetrates | W·H | 01-S7 |
| Order | Roll pen once at 1st impact → ricochet → normalize → spaced/track/external subtract T_eff, continue → main plate; ≤ 8 plates | O·H | 01-R2 |
| RNG | Truncated normal σ = 0.125·mean (±25 % = 2σ), resample (8 tries, then clamp); pen and damage; match-seeded substream per system. `COMPETITIVE_SPREAD` 0.10 off | bounds W·H, shape O | 01-R3 |
| Falloff | AP/APCR only, linear 100→500 m, then flat: AP ×0.90, APCR ×0.75 | W shape·M | 01-R7 |
| Velocity | 0.6 × authored real m/s; APCR 1.25 AP, HE = AP, HEAT 0.85 AP (800 → 480 m/s = 48 studs/tick) | O readable at 50–445 m·M | 01-R7 |
| Gravity / range | g_shell 19.62 m/s² (58.86 studs/s²), not `Workspace.Gravity`. Direct fire despawns at 600 m (HE bursts on terrain); SPG per gun ≥ 900 m | O·M | 01-R7 |
| Simulation | 30 Hz swept segment vs map (`World:raycast` `Shell`) + analytic `ArmorGeometry`; no armor Instances | A·H | ARCH §6 |
| HEAT spaced | After any plate: pen −= T_eff, × max(0, 1 − 0.5·gap_m) | W·M | 01-S10 |
| HE (1.13 adapted) | Pen: rolled α + internal spall sphere (R_splash) rolling modules/crew. Non-pen: D = max(0.05α, 0.5α_rolled − 1.1·T_nominal·K_spall), HESH ×1.15, spall module rolls ×0.5. Screens/tracks/external modules cost 3T pen, destructibles 1T | W shape, O floor·M | 01-R4 |
| Splash | R = cal_mm/100 m; others: D = max(0, 0.5α(1 − d/R) − 1.1·T_min·K_spall); external modules in R damaged; allies 0. K_spall = 1 + Spall Lining (.50/.60 slot) | O·L | 01-R4 |

## 2. Damage, modules, crew, environment

| Topic | Decision | B/C | Src |
|---|---|---|---|
| Modules | Engine, Ammo rack, Fuel, Gun, Turret ring, Optics; external Tracks (wheel pairs). **No radio** | O·H | 03-R4 |
| HP | k × ref α (MT α of tier, §7.4): engine 1.0, ammo .9, fuel 1.0, gun 1.0, ring 1.0, optics .8, tracks 1.4; crew .8 | O·L | 01-R5 |
| States | OK > 50 %, Damaged ≤ 50 %, Destroyed 0 | W·H | 01-S13 |
| Internal path | max(0.5 m, 10 cal); each volume rolls: engine/fuel/ring/optics .45, gun .33, crew .33, ammo .27, external 1.0 | W 10 cal·L | 01-R5 |
| Module dmg | 0.5α kinetic/HEAT, 0.75α HE; cap 1.2 × module HP | O·L | 01-R5 |
| Repair | Destroyed → 50 %: tracks 10 s, engine 14, gun 12, ring 12, optics 8, fuel 10, ÷ f(L); kit → 100 % | W shape·M | 01-R5 |
| Effects (Dmg / Destr) | Engine power ×.5 / immobile · Ammo reload ×1.25 / **detonation** if ≥ 1 shell stored · Fuel fire ×1.5 / fire · Gun disp ×1.5, aim ×1.25 / can't fire · Ring traverse ×.5 / none · Optics VR ×.80 / ×.50 · Tracks — / immobile (wheeled −25 % speed per pair) | W shape, O nums·M | 01-R5 |
| Fire | Engine hit 15 % (petrol 20, diesel 12); fuel destroyed 100 %. 8 s × 2.5 % HP/s; bay modules/crew hit; credited to igniter; Fire Fighting −25 % time; DCS −65 % chance | W chance·H | 01-R5 |
| Crew injury | HP 0 → **injured** (never killed): role L 50; commander: others −10 L, Sixth Sense off | O·M | 01-R5 |
| Ramming | ≥ 3 m/s: D_B = max(0, 0.05·m_A[t]·v² − 1.1·T_B·K_spall), symmetric; rammer's front arc ×.5; both roll tracks; allies 0 | O·M | 01-R6 |
| Falls | v_y > 7 m/s: 0.6·m[t]·(v_y − 7)², ×2 inverted; tracks chance min(1, (v_y − 7)/5); on a tank = ram at v_y (40 t, 10 m/s → 216) | O·M | REG-VEH-11 |
| Drowning | Water over turret roof → 10 s + warning (reset on exit) → destroyed, no kill credit | O·L | 04-R8 |
| Overturn | roll/pitch > 70° for 3 s → immobile, gun off, allies can push; self-righted after 10 s, no HP loss, capture points reset | O never stuck·L | REG-VEH-05 |
| Friendly fire | 0 (shells, splash, rams, fire); allies consume shells | O griefing·H | 04-R7 |

## 3. Aiming

| Topic | Decision | B/C | Src |
|---|---|---|---|
| Model | R = radius (m @ 100 m), linear in distance. σ = R/2; miss = abs(N(0, σ)) at a uniform angle, re-roll > 2σ. `DISPERSION_MODEL "radial"` (`"gauss2d"` kept) | O fits WoT 2σ data·M | 01-R8 |
| Converge | M = max(M_target, M·e^(−Δt/τ)), τ = aim time (crew-scaled) | W·M | 01-R8 |
| Bloom | M_target = √(1 + (.07·v_kmh)² + (.075·ω_hull)² + (.03·ω_tur)²) × 1.5 if gun damaged; per-vehicle k; Gyro −20 % k; Snap Shot −7.5 % k_tur; wheeled moving ×1.15; stun ×1.20 | O·L | 01-R8 |
| After shot | M = max(M, M_target) × 3.0 LT/MT/TD, 3.5 HT, 4.0 derp/SPG | O·L | 01-R8 |
| Arcs | Per vehicle, default −8°/+20°, yaw sectors optional; casemate yaw ±11° | W·M | 03-R1 |
| Authority | Server rolls shots; client predicted reticle + "server reticle" option | A·H | 01-R8 |

## 4. Crew effect, reload, gun mechanics

| Topic | Decision | B/C | Src |
|---|---|---|---|
| L | Healthy 100 (always trained); +5 Ventilation (+6 slot), +10 Rations, +5 Brothers in Arms × crew share; injured 50; injured commander −10 others | O·M | 05-R7 |
| Reload | base × 0.875/(0.00375·L + 0.5), loaders averaged (L 120 ×.921, 50 ×1.273) | W·H | 01-S17 |
| Other stats | f(L) = 0.57 + 0.0043·L: × VR, hull/turret traverse; ÷ aim, dispersion, repair time | O·L | 02-R4 |
| Modifiers | Rammer −10 % (−11.5 slot; not magazines); damaged ammo ×1.25; stun ×1.25; ActiveCooling ×.85; ammo swap when loaded = full reload (Intuition 40 %) | W/O·M | 05-R8 |
| Magazine | 3–5 shells, 1.5–3 s apart; sustained DPM .85 × class; burst ≤ .85 × same-tier MT HP; no rammer; not HT Assault | O·M | 03-R7 |
| Autoreloader | 2–4 shells, per-shell timers, first refill after empty longest; sustained .92; firing never resets a slot; MT/TD | W shape·M | 03-R7 |
| Dual gun | HT VII+, 1 line: singles or volley (1.0 s charge, 1.5 s between barrels, disp ×1.5); reload each 2.3 × class; early release cancels | W shape·M | 01-R9 |
| I–X mechanics | SiegeMode (TD Sniper/Support: on 2.0/off 1.25 s, aim ×.4, disp ×.85, +8° dep/+6° elev, ≤ 10 km/h, hull trav ×.5); Hydropneumatic (MT: +4°/+3° after .75 s still); Wheeled (LT, ≤ 1/team: speed mode +30 %, steering ×.6, 1 s toggle). ≤ 20 % of I–X roster special | W shape·M | 03-R7 |
| Tier XI signatures | One per Apex, never I–X: RocketBoost (2 × 2.5 s, +20 km/h, 30 s cd), ChargedShot (1.5 s → disp ×.6 **or** +10 % dmg), ActiveCooling (5 s, 45 s cd, reload/aim ×.85), active Turbo (power ×1.25, 6 s, 40 s cd), adaptive Magazine. Airstrike/smoke/minefield only in `Events.luau` | O (WoT 2.0)·M | 03-R5 |
| Placement | `GunState`: Single, Magazine, Autoreloader, DualGun, ChargedShot, ActiveCooling. `VehicleSim`: SiegeMode, Hydropneumatic, Wheeled, Turbo, RocketBoost. Data-driven | A·H | 03-R7 |

## 5. Spotting

| Topic | Decision | B/C | Src |
|---|---|---|---|
| Formula | spotDist = min(445, VR − (VR − 50)·camo), camo = min(**0.90**, body + foliage) per ray, best ray wins; VR uncapped | W·H; cap O (no invisible TDs) | 02-S2 |
| Ranges | ≤ 50 m always spotted; max 445 m; full state ≤ 564 m, team-visible beyond = 2 Hz minimap records | W·H | 02-R1 |
| Schedule | 50 m .10 s, 150 .50, 270 1.00, 445 2.00, **clamped 1.0 s** + pair jitter; both ports; forced checks on shot, stop (< .5 km/h), spawn; ≤ 400 rays/tick, nearest first | W·M; O clamp (pop-in reads as a bug) | 02-R2 |
| LOS points | 2 ports (top of box over hull centre; gun axis) × 6 checkpoints (turret roof, mantlet, 4 hull faces at 80 % height, inset .1 m); one `Sight` ray each vs map solids + terrain; vehicles/wrecks don't block | O·M | 02-R2 |
| Foliage | Analytic volumes (16 m grid): light bush .25, hedgerow .40, dense .50, crown .30, felled .30, thicket .60; stack ≤ .80; grass none; `Terrain.Decoration = false` | O·M | 02-R5 |
| 15 m rules | Observer sees through foliage ≤ 15 m; 3 s after firing, foliage ≤ 15 m of the shooter stops concealing | W·H, O 3 s | 02-S8 |
| Body camo | base × (1 + .80·concealment share) × shotMult + paint + net; moving > .5 km/h or yaw > 2°/s. Still/moving/net: LT .18/.18/.10, MT .12/.07/.10, HT .05/.025/.05, TD turretless .28/.16/.15, turreted .18/.11/.15, SPG .10/.05/.05 | O·L | 02-R3 |
| Paint / shot | Paint +.04 flat (0 ranked). camoAtShot = clamp(.40 − .0025(cal − 20), .05, .40) for 3 s. Net/mast arm after 3 s still | O no pay-for-stealth·M | 02-R3 |
| VR | baseVR (§7.4) × class (LT 1.10, MT 1, HT .95, TD .95, SPG .85) × f(L_cmd) × (1 + optics) × (1 + perks) × optics module × stun .90 × smoke .70; lenses and mast don't stack | O (WoT flat)·M | 02-R4 |
| Linger | Visible 10 s after last success; last-known marker 30 s | W·H / O | 02-R1 |
| Sixth Sense | Built in, 3 s after first team-visible; no unspotted cue; off if commander injured | W·H | 02-S9 |
| Signal range | **Off** (team-wide vision, no radio); `SIGNAL_RELAY_ENABLED` for special modes | O·H | 02-S11 |
| Smoke/weather | None in Random; event smoke blocks LOS, VR ×.70 inside; `visibilityMult` hook | W/O·M | 02-S12 |
| Rewards | First detection: flat XP/CR (×2 vs SPG). Assist pool .5 × shooter's damage reward split among allies who saw the target ≤ 10 s ago; shooter keeps 100 % | O·M | 02-R8 |

## 6. Movement (no report covered it: O·L, calibrate)

- a = P/(m·max(v, 1 m/s)) − g·(0.10·R·cos θ + sin θ), traction-limited to μ·g·cos θ, capped by top speeds; engine hp tuned to class hp/t.
- **R** hard/medium/soft: LT .8/1.0/1.7, MT .9/1.1/1.9, HT 1.1/1.3/2.3, TD/SPG 1.0/1.2/2.1. Hard = Concrete, Asphalt, Pavement, Cobblestone, Brick, Slate, Rock, Basalt; medium = Grass, LeafyGrass, Ground, Sandstone; soft = Sand, Mud, Snow, Glacier; fordable water ≤ 1 m = soft ×1.5, speed ×.5.
- μ .75/.70/.60; `MAX_CLIMB_DEG` 35. Hull traverse × R_hard/R, down to ×.6 at top speed; tracked pivot, wheeled turn radius. Reverse default clamp(.35 × forward, 12, 25) km/h.
- Heightfield bilinear (1 sample/2 studs), 4 samples per track → height/pitch/roll; structures via `World:raycast`; obstacles `sweepBox`; vehicle–vehicle OBB, energy never increases.

## 7. Classes, roles, factions, tiers

**7.1 Class multipliers vs MT** (03-R1, W medians unless noted)

| Stat | LT | HT | TD | SPG |
|---|---|---|---|---|
| HP / α | .80 / .85 | 1.20 / 1.25 | .85 / **1.50** (O: data .80/1.68, no LT one-shots) | .30 / 2.0 HE |
| Pen / reload | .90 / .95 | 1.03 / 1.27 | 1.18 / 1.45 | .25 / 4.0 |
| Aim / dispersion | .90 / 1.05 | 1.20 / 1.05 | 1.05 / .92 | 2.3 / 1.75 |
| Speed / hp/t | 1.20 / 1.6 | .72 / .77 | .80 / .80 | .75 / .80 |
| Hull / turret trav | 1.18 / 1.15 | .60 / .65 | .67 / .50 | .55 / — |
| Hull-front armor | .50 | 1.60 | 1.1 (Assault ≈1.75, Sniper ≈.65) | .6 |

80 % of TDs turretless (yaw ±11°, depression −5 to −8°).

**7.2 Roles** (03-R2, O on WoT's shape): badge, category slot, Role Score, soft MM mirror.
LT Scout (camo +.03, VR +10 m, α ×.9) · Support (pen ×1.05, α ×1.05, speed ×.95) · Versatile; `Wheeled` = mechanic flag.
MT Assault (armor ×1.15, HP ×1.05, speed ×.92) · Sniper (disp ×.9, pen ×1.07, VR +10 m, reload ×1.05) · Support (reload ×.92, camo +.02, armor ×.9) · Versatile.
HT Assault (armor ×1.15, speed ×.85, hull trav ×.9) · Breakthrough (speed ×1.15, hp/t ×1.15, armor ×.95) · Support (armor ×.85, pen ×1.05, dep +2°, aim ×.9) · Versatile.
TD Assault (armor ×1.6, speed ×.85, camo −.08) · Sniper (camo +.04, disp ×.9, α ×1.05, armor ×.6) · Support (reload ×.9, speed ×1.1) · **Versatile — added** (360° turret, α ×.9). SPG Support (stun) · AreaControl.
- **Category slot** (VI+, +15 %): Firepower TD/MT Sniper+Support, HT Support · Survivability HT Assault/Breakthrough, MT/TD Assault · Mobility all Versatile, LT Support · Scouting LT Scout, SPG.
- **Role Score** (components ÷ 30-day class×tier median): HT Assault/Brk dmg .4, blocked .3, cap .1, first-3-min dmg .2 · HT Sup/Vers dmg .6, blocked .2, assist .2 · MT dmg .6, assist .25, cap .15 · TD dmg .75, assist .15, kills .1 · LT Scout spot .6, detections .15, dmg .15, cap .1 · LT Sup/Vers dmg .4, spot .4, track .2 · SPG stun .5, dmg .4, kills .1. **Defeat protection:** top 5 losers XP ×1.25.

**7.3 Faction kits** (O; ±5–15 % core, armor/arcs further; included in the lint baseline)

| Faction (brand identity) | Kit | Signature |
|---|---|---|
| `iron_union` (industry, armor) | α ×1.10, reload ×1.10, turret armor ×1.10, disp ×1.06, aim ×1.05, dep −5° | DualGun HTs |
| `crown_industries` (precision) | disp ×.93, aim ×.94, α ×.92, reload ×.92, dep −10° | HESH HT/TD |
| `eastern_armor` (mobility, alpha strike) | hp/t ×1.10, speed ×1.06, turret armor ×.80 | Magazines, Wheeled LTs |
| `desert_corps` (long range) | aim ×.94, reload ×.95, turret armor ×1.08, lower plate ×.85, dep −10° | Autoreloader MT/TD |
| `mountain_republic` (terrain) | speed ×1.15, dep −12°, hull armor ×.60 | Siege TDs, Hydropneumatic MTs |
| `northern_federation` (survival) | HP ×1.05, hull armor ×1.06, disp ×.94, hp/t ×.94 | Assault TDs |

**7.4 MT baseline per tier** (03-R3; gun columns = 01-R10)

| Tier | HP | α | Pen | Reload | Aim | Disp | km/h | hp/t | Hull°/s | Tur°/s | VR | Hull F/S/R | Tur F |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I | 280 | 40 | 45 | 1.9 | 1.9 | .48 | 40 | 12 | 38 | 40 | 300 | 20/15/15 | 25 |
| II | 360 | 50 | 55 | 2.3 | 1.95 | .47 | 42 | 13 | 38 | 40 | 310 | 25/20/15 | 30 |
| III | 440 | 60 | 65 | 2.6 | 2.0 | .45 | 45 | 14 | 37 | 40 | 320 | 30/25/20 | 35 |
| IV | 530 | 85 | 85 | 3.4 | 2.1 | .44 | 47 | 15 | 36 | 40 | 330 | 45/30/25 | 45 |
| V | 640 | 115 | 100 | 4.2 | 2.2 | .42 | 50 | 16 | 36 | 40 | 340 | 50/35/30 | 55 |
| VI | 820 | 160 | 130 | 5.6 | 2.25 | .40 | 52 | 17 | 37 | 40 | 355 | 60/40/35 | 75 |
| VII | 1,060 | 220 | 160 | 7.4 | 2.3 | .38 | 54 | 17 | 38 | 42 | 370 | 75/45/40 | 85 |
| VIII | 1,350 | 260 | 195 | 8.0 | 2.3 | .37 | 55 | 18 | 40 | 42 | 380 | 85/55/40 | 110 |
| IX | 1,650 | 320 | 225 | 8.6 | 2.2 | .35 | 55 | 19 | 42 | 42 | 390 | 100/60/40 | 130 |
| X | 1,950 | 400 | 255 | 9.5 | 2.2 | .34 | 55 | 20 | 45 | 42 | 400 | 105/65/40 | 160 |
| XI | 2,200 | 440 | 275 | 9.8 | 2.1 | .33 | 56 | 21 | 46 | 44 | 410 | 115/70/45 | 180 |

- **Armor vs our pen P(tier)**, effective at 0° yaw: HT turret 1.15–1.35 P, upper plate .95–1.15, weak spots .55–.70; MT turret .85–1.0, hull .50–.70; TD Assault 1.1–1.4, Sniper/Support ≤ .45; LT ≤ .35; sides .35–.45 (HT) or .2–.3; rear .2–.3.
- **Balance lint:** stat ÷ (class × role × tier × kit) outside [.85, 1.15] fails, outside [.92, 1.08] warns unless `balanceException`.
- **Research (03-R4):** Gun, Turret (if meaningful), Engine, Tracks; upgrades II–III 1–2, IV–IX 2–4, X sold elite; Tracks → Turret → Gun, next vehicles from the top gun; stock tracks 1–3 % spare load; stock ≈ 85 % (top/stock pen 1.20, hp/t 1.15).
- **SPG (03-R6):** IV–X; HE α 2 × MT, direct hit ≤ 45 % MT HP; R = 3 + .03·cal m; stun max V 6 s … X 16 s, ×.5 at the edge; reload/aim ×1.25, disp ×1.20, traverse ×.80, speed ×.85, VR ×.90; medkit clears it. Team-spotted targets only; flight ≥ 2.5 s; impact warning 1 s ahead; 5 s minimap ring on the shooter; kills .8 × XP.
- **Tier XI Apex:** 1 per faction at launch; X × (HP 1.13, α 1.10, pen 1.08, DPM 1.07); one signature (§4); X–XI only.
- **Premiums:** II–VIII (VIII core), ≤ 2 at IX, none X/XI; 40–55th percentile, nothing above tech-tree P60; credits ×1.35 (II–VII) / ×1.5 (VIII), crew XP ×1.5; any same faction+class crew; no preferential MM; nerf > 5 % → 14-day Bullion refund window.

## 8. Matchmaking (04-R1…R6, 03-R2/R3, 08-R3)

| Topic | Decision | B/C |
|---|---|---|
| Templates | Per team 15 · 5/10 · 3/5/7, mirrored; weights 1/1/.6 (prefer ±1) | W·H |
| Spread | I–II one tier; III–IV ±1; V–X ≤ ±2, never above X; XI only in X–XI | O·H |
| Caps/team | LT ≤ 3 (Wheeled ≤ 1), **TD ≤ 4**, SPG ≤ 2 (≤ 1 if team ≤ 10, 0 competitive); smaller teams ceil(cap·size/15) | O·M (§21) |
| Mirror | Classes exact while relax < .5, then ±1; roles soft penalty; bots pick class/role fixing the mirror | W 2.0·M |
| Platoons | ≤ 3, same tier, ≤ 1 SPG, count diff ≤ 1; bots never platooned | O·M |
| Score | 10·humans − 6·bots·(1 − relax) − 7.5·(1 − weight) − 2·classErr − roleErr − platoonImbalance; humans to upper slots; after 2 bottom-tier battles prefer non-bottom; no preferential MM | O·M |
| Relaxation | Oldest ticket 0–10 s no bots, own region · 10–25 s ≤ 10 bots, adjacent · 25–45 s ≤ 20, global, mirror ±1 · ≥ 45 s fill all (≥ 1 human). "Start now with bots" from 15 s | O·M |
| Pool key | (mode, region NA/SA/EU/APAC/OCE, `game.MatchmakingType`); type never relaxed | P·H |
| Leader/tickets | Lease HashMap item, 15 s TTL; tick 3 s (5 s < 30 CCU); ticket TTL 120 s refreshed every 30 s by state-guarded `UpdateAsync`; claim/cancel atomic Q→M / Q→C | O within P·H |
| Bots | Labelled; Recruit (humans < 20 battles), Veteran (VIII+), else Regular; obey Attack, Defend base, Follow me, Focus fire. Normal rewards; 0 human enemies ×.75; > 50 % bots excluded from leaderboards/ranked/`pvpOnly` achievements | O·M |
| Maps/modes | Map after teams; ×.25 per play in last 5; blacklist 1 (2 with Premium Time) once ≥ 8 maps; Standard .70 / Encounter .20 / Assault .10, Enc/Assault from IV; opt-outs lower weight, never split | W/O·M |

## 9. Battle rules and lifecycle (04-R7, -R9, -R10)

| Topic | Decision | B/C |
|---|---|---|
| Timers | Standard/Encounter 12:00, Assault 8:00; > 5 % timeouts → 15 min or capture ×1.25 | O (WoT 15/15/10)·M |
| Victory | Wipe or capture; timeout draw (Assault: defender win); same-tick double result draw | W·H |
| Capture | r 50 m, 100 pts, += rate·dt·min(1, 3/n); 1.0 pt/s (.5 Encounter) → 100/50/33 s; Encounter blocked when contested; HP damage or module crit resets that capper (stun no); 1 s leave grace | W shape·M |
| Load | **20 s** countdown once all humans loaded or 30 s after ready; absentees' vehicles bot-driven until arrival; after the **45 s** window the slot stays a bot, Hub re-queues the player | O·M |
| Disconnect | 5 s → bot; reconnect until end via "Return to battle" (`profile.activeBattle`); rewards only for human-controlled share | O·M |
| AFK/leave | No input 60 s warn, 90 s bot + strike + XP 0; strikes/24 h: 1 no rewards, 2 10-min lock, 3 60-min. Leaving alive: confirm, bot, no win bonus, strike | O·M |
| End | Destroyed: spectate or Hub, vehicle locked to the end. End: 6 s banner → inbox (§19) → teleport; results shown in the Hub | W/O·H |
| Comms | 12 presets, no end punctuation: Attack, Defend base, Need help, Affirmative, Negative, Reloading, Thanks, Hold position, Follow me, Enemy spotted here, Moving here, Focus fire. T context ping; minimap LMB attention / RMB moving. Chat presets 1/10 s ("system preset", filtered); markers 3/5 s, ≤ 12/min; replies marker-only. `RBXTeam` chat, all-chat off | P·H |

## 10. Maps (04-R8, 07-R-MAP-1, 08-R1, 09-R7)

| Topic | Decision | B/C |
|---|---|---|
| Size/grid | 1,000 m (800 m city and Tier I–III pool) + 150 m skirt, red-line edge; grid A–K (no I) × 1–9, 0 | W·H |
| Lanes | 3: Heavy (200–300 m wide, ≥ 60 % hard cover ≤ 30 m, sight ≤ 150 m), Flex (≥ 3 hull-down spots/side, 100–300 m), Open (foliage islands, 200–445 m); ≥ 2 links per half; 100–150 m rear band | W shape·M |
| Spawns/bases | 15 slots (≥ 3 rear); centroids ≥ .7 × size apart; no spawn-spawn LOS; first contact ≥ 40 s; no protection. Std base 100–200 m ahead; Encounter equidistant (≤ 5 %); Assault = defender base; ≥ 60 m from edge | O·M |
| Fairness | Lane path asymmetry ≤ 10 %; per-spawn win rate 47–53 % over ≥ 1,000 battles | O·M |
| Terrain | Relief ≤ 80 m; water ≤ 1 m fordable. Destructibles light (contact), medium (15 t at 10 km/h or 1 HE), heavy (40 t ram or 2 HE); buildings/rocks/bridges permanent | O·M |
| Events/weather | No gameplay random events at launch (validated `randomEvents` hook); weather cosmetic only | O·H |
| QA | Flood-fill reachability (2 m), stuck soak, collision/visual parity ≤ .25 m, border seal, spawn exposure, minimap hash | O·H |
| Build | v1 one Battle place; server builds map from `Content/Maps` before arrivals (≥ 9 `WriteVoxels` chunks), clients wait for `MapReady`; per-map places later via `Places.luau` if needed | A/O·M |

## 11. Economy and progression

**Currencies** (05-R1, O): Credits (soft sink) · Bullion (Robux products, small pass/event grants → premium vehicles, Premium Time, XP conversion, clean retrain, pass, cosmetics; never random items or extra power) · Vehicle XP · Free XP · Crew XP · **Campaign Tokens** (earned only, no expiry: campaigns, hero 10, epic 50, Ace 25, Hard daily 30, events → Token Shop: Refined equipment, books, cosmetics, event items; absorbs 05's Merit and per-event tokens). 1 BUL → 200 CR; elite XP → Free XP 10 per BUL; 2.5 BUL per R$ base.

```
baseXP  = Σ(action·xpCoef)·tierScale × (win 1.5 [W] | else 1.0 | top-5 losing Role Score 1.25) × survived 1.05 + .25·blockedHP·xpCoef.dmg
totalXP = baseXP × first win ×2 per vehicle/day [W] × Premium Time 1.5 [W] × Plus booster 1.2 (one vehicle)
freeXP  = .05·baseXP × Premium Time 1.5   (first win excluded; flag freeXPIncludesFirstWin = false)
crewXP  = totalXP × 1.5 on premium vehicles
grossCR = Σ(action·crCoef)·tierScale × vehicleCreditCoef × win 1.5 × Premium Time 1.5 × Roblox Premium 1.1
netCR   = grossCR − repairFull·HPlost/HPmax − shells − consumables, floored at 0 (auto-repair waives the rest)
```
XP mix ≈ damage 55 %, spot/track assist 25 % (50 % of damage XP per HP), kills 10 %, cap/def 5 %, crits 5 %. Spot XP
first detection only; capture XP only while advancing; none for ally damage. First win resets at a fixed UTC hour.

| Tier | Research XP | Price CR | Module XP | XP/battle | Battles | Full repair | Shell | Net CR/battle |
|---|---|---|---|---|---|---|---|---|
| I | — | 0 | 100 | 150 | 3 | 0 | 0 | 15,000 |
| II | 350 | 35,000 | 250 | 200 | 5 | 3,000 | 50 | 20,000 |
| III | 750 | 100,000 | 500 | 260 | 8 | 6,000 | 100 | 26,000 |
| IV | 1,550 | 220,000 | 1,000 | 330 | 12 | 11,000 | 200 | 32,000 |
| V | 3,000 | 400,000 | 1,750 | 410 | 17 | 18,000 | 300 | 38,000 |
| VI | 5,200 | 650,000 | 2,900 | 500 | 23 | 28,000 | 450 | 42,000 |
| VII | 8,600 | 1,000,000 | 4,500 | 600 | 30 | 42,000 | 650 | 44,000 |
| VIII | 13,500 | 1,400,000 | 7,000 | 700 | 40 | 60,000 | 900 | 42,000 |
| IX | 21,000 | 1,800,000 | 10,500 | 800 | 52 | 85,000 | 1,200 | 30,000 |
| X | 31,000 | 2,600,000 | 16,000 | 900 | 70 | 115,000 | 1,600 | 10,000 |
| XI | 47,000 on X | 3,600,000 | 60,000 nodes | 1,000 | — | 150,000 | 2,000 | −15,000 |

(05-R3, O: ≈ 260 battles I → first XI. IX–XI are a soft sink without Premium Time; VIII premiums earn credits.)
- Module price 6 % of vehicle; special ammo 2.5 × standard (credits only). Sell 50 % (W); premium refund 50 % × BUL × 200 CR; buyback 72 h at +10 %. **Garage slots unlimited.** Out of credits → "play a lower tier" hint.
- Elite unlocks XP conversion and Field Kits (VI–VII 3 levels, VIII 4, IX–X 5; per level VI 1,000 XP, VII 1,800, VIII 2,800, IX 4,000, X 5,500; two free-swap choices).
- **Tier XI:** 47,000 XP + 3.6 M CR (WoT 325k/7.4 M, unverified). 10 nodes: 6 × 4,000 (+2 %), 3 × 8,000 (+4 % or mechanic tier), 1 × 12,000 (signature) = 60,000 XP, ≤ +12 %, Free XP allowed; cosmetic Elite levels every 25 battles.
- **Premium Time** (BUL): +50 % XP/CR/crew XP, +1 reroll, 2 blacklist slots; 1 d 250, 7 d 1,250, 30 d 2,000. **HULLDOWN Plus** (Robux subscription ≈ 449 R$/mo, repriceable per 60 d): +25 BUL/day played, free demount, 100 crew XP per 5 min online (≤ 3,000/day), +20 % on one tech-tree vehicle; same on all platforms, never revoked mid-term. Roblox Premium +10 % CR.

## 12. Crew (modern, simplified; WoT "Crew 2.0" never shipped)

- **Roles:** Commander, Gunner, Driver, Loader (radio perks fold into Commander; small vehicles double up). No qualification levels: L = 100 always; free trained recruits (W 2024).
- **Perks:** 5 slots; 12k/24k/48k/96k/192k crew XP (≈ 17 battles first, ≈ 530 all); work from 1 %, linear; group perks (Brothers in Arms +5 L, Field Repairs, Concealment +80 % body camo) scale by crew share; overflow → Free XP 10:1. Starters (O·L): Cmd Recon, Practicality, Mentor; Gunner Snap Shot, Deadeye, Quick Aiming; Driver Clutch Braking, Smooth Ride, Engineer; Loader Intuition, Close Combat, Ammo Tuck (WoT-sized effects, 05-R7); 6 individual + 3 group per role.
- **Reset/retrain:** reset first free then 50,000 CR (free ≤ 7 days after buying). Retrain same faction+class: 5 % of price with −25 % perk efficiency recovered over 20,000 XP, or 100 BUL clean; cross-class keeps 90 %. Books 5k XP (60,000 CR), 25k (missions/pass), 60k (events). Injuries are battle-only.

## 13. Equipment and consumables (05-R8/R9)

Slots I–III 2, IV–XI 3; VI+ slot 1 = role category, match +15 %. Classes C (II–IV) 25,000 CR, B (V–VII) 150,000,
A (VIII–XI) 300,000; **Refined** ≈ 1.2× effect for 3,000 Campaign Tokens; no Bullion-only items. Demount free with
Plus, else 5 BUL or 10 % of price.

| Item | Std / slot | Item | Std / slot |
|---|---|---|---|
| Rammer Assist (FP) | −10/−11.5 % reload | Coated Lenses (Sc) | +10/+11.5 % VR |
| Laying Drive (FP) | +10/+11.5 % aim speed | Periscope Mast (Sc) | +25/+27.5 % VR after 3 s still |
| Gyro Stabiliser (FP) | −20/−23 % bloom | Cam Netting (Sc) | +.15 TD, +.10 LT/MT, +.05 HT (+15 % slot) |
| Traverse Gearing (Mob+FP) | +10/+12.5 % traverse | Turbo Kit (Mob) | +7.5/+10 % power, +4/+5 km/h |
| Crew Ventilation (all) | +5/+6 L | Torsion Bars (Sv) | +8/+10 % HP, +50 % track HP |
| Spall Lining (Sv) | K_spall +.50/+.60, −30 % stun | Damage Control Suite (Sv) | +45 % repair, +150 % ammo/engine HP, −65 % fire |

Consumables: Repair Kit, Medkit (also clears stun), Extinguisher — 3,000 CR, 90 s cd, reusable. Large Repair Kit /
Large Medkit — 20,000 CR or 100 BUL, 60 s cd, passive +10 % repair / +15 % injury resistance. Automatic Extinguisher —
same price, fires 0.5 s after ignition, −10 % fire chance, 60 s cd. Rations (+10 L) / Quality Fuel (+5 % power) — 20,000
CR. Resupply charged once per used item; auto-resupply on, falling back to cheapest kits.

## 14. Missions, pass, achievements, results

| Topic | Decision | B/C | Src |
|---|---|---|---|
| Daily | Easy/Medium/Hard + Bonus; 1–3 battles each; 1 free reroll (+1 Premium Time). By top owned tier: Easy 2–8k CR + 150 Free XP · Medium 3–10k + 300 + Booklet · Hard 5–12k + 500 + 30 Tokens · Bonus 5–15k + 1,000 + Large Repair Kit. **Total 15–45k CR/day** (fact-checked) | O·M | 05-R10 |
| Weekly | 3 missions (5–10 battles): Booklet + 10 Tokens + 60 pass pts each; all 3 → Guide. **No credits** (keeps §11 closure) | O·L | — |
| Campaigns | 3 operations × 3 role series (Assault, Overwatch, Support) × 10; primary + "with honors"; unique non-sold rewards | O·M | 05-R10 |
| Season Pass | 8 weeks; 3 × 30 stages × 30 pts = 2,700. Per battle by team XP rank: top 3 8/6 (win/loss), 4–10 6/4, rest 3/2; +15 per daily. Paid track fixed rewards only | O·M | 05-R10 |
| Mastery | Ace/I/II/III = 99/95/80/50th pct of base XP, 7 days; pooled tier×class if < 300 samples; servers batch histogram writes ~60 s | W·H | 05-R11 |
| Gun Marks | V–XI; EMA k = 2/101 of dmg + max(spot, track assist); 65/85/95th pct, 14 days | W·M | 05-R11 |
| Battle Heroes (15 v 15) | Top Gun most kills ≥ 6 · Steel Wall most blocked, ≥ 11 hits, ≥ 1,000, survive · Defender ≥ 70 reset · Invader ≥ 80 in a won cap · Scout most detections ≥ 9 · Patrol Duty sole spotter of ≥ 6 · Confederate ≥ 6 · High Caliber most dmg, ≥ 20 % enemy HP and ≥ 1,000 | W·H | 05 §7.3 |
| Epics | Last Stand (alone vs ≥ 5, win), Ace Hunter (≥ 10 kills, V+), Last Round (final kill, final shell); ribbons + Tokens | O·M | 05-R11 |
| Results | Full screen, tabs **Summary** (result, kills, dmg, assist, blocked, spotted, XP, CR, awards, Role Score) · **Team** (row → per-enemy hits) · **Report** (ledger) · **Progress** (missions, pass, research, perks, Marks, Mastery); "Battle again" on each; lines only from `BattleResult.ledger[]`; negative net `state.danger` + "Why?"; last 20 kept | W pattern·H | 05-R12 |

## 15. Store and monetization

- **No paid random items**, trading, Bullion-only power or timed combat offers; crates only from free play (bought/rerolled/boosted = paid, P). Call `PolicyService:GetPolicyInfoForPlayerAsync` on join.
- **Products:** Bullion packs at base 49/99/249/499/999/1,999 R$ (+0…25 %). **Managed Pricing** default: client shows `GetProductInfoAsync` prices, never hard-coded R$; BUL per product fixed.
- **Receipts:** `MarketplaceService:BindReceiptHandler(Enum.ReceiptType.DeveloperProduct, handler)` in the Hub only (+ `ProcessReceipt` fallback → `NotProcessedYet`); Battle places always return `NotProcessedYet` and hide `ExperienceShop`. Grant + `PurchaseId` in **one** `UpdateAsync`, then `Enum.ReceiptDecision.Processed` (receipts may run on two servers at once).
- **Plus:** prompt only if `IsEligibleToPurchaseSubscription`; status via `GetUserSubscriptionStatusAsync` + `Players.UserSubscriptionStatusChanged` on the server.
- **Premium vehicles (BUL):** II 250, III 400, IV 600, V 1,000, VI 1,600, VII 2,400, VIII 3,500.

## 16. UI and UX (brand-art wins on visuals)

| Topic | Decision |
|---|---|
| Scale | 1920×1080; `UIScale = clamp(vh/1080, .75, 1.5)`, ×1.25 TV (brand §4.1). **Compact** when vh < 600 px (not `DisplaySize.Small`, which includes tablets), authored 844×390; TV +5 % margin; `CoreUISafeInsets`, `SafeAreaCompatibility = None` |
| Kit | In-house `UI/Kit`, Luau `Theme` from brand tokens; **no engine StyleSheets v1**; no `TextScaled` body text; no beta UI props; markers = one pooled overlay in `PreRender` (no `BillboardGui`) |
| Garage (06-B1) | Top bar: Back · vehicle/tier/XP · currencies, premium timer. Left vertical nav (Garage, Tech Tree, Crew, Missions, Pass, Store, Profile, Settings); right column dailies/events. `TO BATTLE` top-centre (Compact bottom-right) with mode + queue state. Service strip above the carousel (Modules, Equipment, Ammo, Consumables, Crew, Appearance → drawers). Carousel filters, share-code Playlists, Space/Y grid. About Vehicle: Overview, Modules, Armor Inspector (attacker/gun/shell), Compare ≤ 6 |
| HUD (06-B2) | Score + team-HP bars top-centre; timer (warn < 2:00, crit < 0:30 + pulse); team panels top corners; minimap bottom-right 224–480 px (352 default, VR/445/564 circles, last-known); damage panel bottom-left; log 8 lines; ammo 1–3 + consumables 4–6 bottom-centre; hit arcs ≤ 10/10–30/> 30 % HP; ribbons; kill feed 5 × 6 s; markers/reticles brand §8.6–8.7 |
| Pen indicator | Client runs the **shared** `Penetration` code on the aimed face (angle, normalization, 2/3-cal, ricochet, spaced, HEAT gap, falloff): green T_eff ≤ .875 pen, yellow to 1.125, red ≥ 1.125 or ricochet; brand ring segments 3/2/1, colour secondary; allies hollow |
| Alerts/colours | Spotted: brand crest chevron top-centre 2 s + sound. Team colours: brand §3.4 schemes (default green/red, deutan, protan, tritan), chooser at first launch; shapes never change |
| Mobile | Dynamic stick left 40 %, aim drag right 60 %, Fire 104 px bottom-right, sniper 72 px, ammo 3 × 56 arc, consumables 3 × 56 right edge, minimap 160 px top-left; battle targets ≥ 48 px, others ≥ 44 |
| Input (09-R5) | Input Action System contexts Battle/Sniper/Menu/Spectate/Garage; `PreferredInput` drives layout and glyphs (`GetImageForKeyCode`; not beta `InputActionLabel`). KBM WASD, mouse, LMB fire, Shift sniper, RMB lock, 1–6, Tab, M, T; pad R2 fire, L2 sniper, L1 lock, R1 ammo, Y radial, View scoreboard. **Never bind** Esc/ButtonStart, F9, F11, F12, PrintScreen |
| Camera | `Scriptable`, `BindToRenderStep` at `Camera + 1`; orbit 5–25 m, pitch −35…+60°, one `Spherecast`/frame; sniper ×2/4/8 (16/25 by optics), sensitivity × tan(FOV/2)/tan(FOV₀/2), own model hidden; SPG top-down 100–200 m |
| Accessibility | CVD schemes + shapes; HUD 80–150 %; honour `PreferredTextSize`, `PreferredTransparency`, `ReducedMotionEnabled`; ≤ 3 flashes/s; captions (offered at first launch); directional glyphs for audible gunfire ≤ 300 m; mono; remap; hold/toggle sniper; FOV 60–90; sensitivities; invert Y |

## 17. Audio (`audio.md` authoritative; cross-doc fixes)

| Topic | Decision |
|---|---|
| API | New Audio API only: `AudioPlayer` → `AudioEmitter`/`AudioListener` → `Wire` → `AudioFader` buses → `AudioCompressor` → `AudioLimiter` (−1 dBFS) → `AudioDeviceOutput` (+ `AudioFilter`/`AudioEqualizer`/`AudioReverb`); no `Sound`/`SoundGroup`. Client-built `AudioEngine`, listeners on camera, `DefaultListenerLocation = None`; server plays no SFX |
| Buses/voices | Master, Music, Ambience, Vehicles, Weapons, Impacts, UI, Voice; 3-D buses = listeners per `AudioInteractionGroup` (one group per emitter). **32 voices PC/console, 20 mobile**; layers/tails count; own vehicle, cues, voice never stolen; loops owned by entity scopes |
| Distance | Close 0–120 m, mid 120–450, far 450–1,500, thump beyond; variant fixed at fire time; `Play(GetMixerTime() + d/343)` beyond 150 m (≤ 2.5 s), never for own results/hits taken |
| Occlusion | Acoustic simulation **off** v1; raycast occlusion ≤ 24 rays/frame PC, ≤ 8 mobile |
| Unspotted | Anonymous `ShotHeard` ≤ 1,500 m: calibre class, position snapped 50 m + ±15° bearing noise, no identity; no engines of unspotted vehicles |
| Music | GARAGE → LOADING → PREBATTLE (downbeat at GO via `atTime`) → EARLY → COMBAT (shots ≤ 150 m in 10 s) → ENDGAME_WIN/LOSE/EVEN (≤ 6 alive, ≤ 120 s left or HP-share gap ≥ .4) → RESULTS_*; bar-quantised, 2-bar crossfades; −6 dB + 2 kHz LP when dead |
| Callouts | 1 voice, queue 3: P0 fire/ammo/crew/engine/low HP · P1 own shot result · P2 first spot, track · P3 reload, repaired; captioned |

## 18. Rendering and performance (09-R7…R11, O)

| Budget | Mobile (Low) | PC/console (High) |
|---|---|---|
| Draw calls / triangles | 1,000 / 1.0 M | 2,500 / 3.0 M |
| Vehicle parts | 1,500 (LOD0 ≤ 2, LOD1 ≤ 3) | 3,000 (LOD0 ≤ 4, LOD1 ≤ 12; Medium 3/8) |
| Map | 20,000 anchored parts, 150 meshes, 48 textures ≤ 1024², 1.5 M tris | same |
| Particles / emitters / lights | 600 / 24 / 0 | 2,000 / 64 / 6 (no shadows) |
| Highlights / CanvasGroups / Viewports | 2 / 1 / 2 | 16 / 3 / 6 |
| Voices / queries per frame | 20 / 24 | 32 / 48 |
| Memory after load | 1,100 MB (tex 150, sound 48) | 2,500 MB |
| Frame | ≥ 30 FPS 15 min, our Luau ≤ 6 ms | 60 FPS, ≤ 3 ms |

- **Rig:** one anchored invisible `Root` per vehicle, LOD models welded to it, turret/gun `Motor6D` (`Transform`, fallback `C0`); all roots moved by one `workspace:BulkMoveTo(..., Enum.BulkMoveMode.FireCFrameChanged)` per frame; parts massless, no collide/query/touch, ≤ 4 materials; under client-created `Workspace.ClientVehicles`.
- **LOD** (distance ÷ zoom, 10 % hysteresis, ≤ 1 switch/.25 s, reparent one model): LOD0 ≤ 400 parts < 150 studs · LOD1 ≤ 80 to 600 · LOD2 ≤ 16 to 2,400 · LOD3 marker only. Own vehicle LOD0; ≤ 10 wrecks LOD1; spotted enemies always have a 2-D marker.
- **Effects:** pooled attachments, `Emit(n)` only; shed exhaust → dust → muzzle smoke first, never own feedback.
- **Server:** ≤ 6 ms avg / 12 ms p99 per tick (30 vehicles, ≤ 120 shells); ≤ 600 world queries/tick (typ. ≤ 250, ground via heightfield); memory < 4.5 GiB; `--!native` allow-list; Parallel Luau (16 LOS Actors) only if Spotting > 2 ms or Projectiles > 1.5 ms.
- **Network:** snapshots 20 Hz ≤ 900 B; ≤ 20 KB/s avg, 40 peak S2C, ≤ 3 KB/s C2S; remotes interpolated 100 ms behind.
- **Lighting:** `LightingStyle = Realistic`, `PrioritizeLightingQuality = false` (view distance first), shadows, softness .2, Atmosphere density ≤ .30, haze ≤ 1.5, no battle DOF.

## 19. Roblox platform rules (08, 09; P)

| Rule | Decision |
|---|---|
| Places | Hub public, 50 players. Battle reserved-only, 32, "Secure within universe only", no third-party teleports. Dev in a separate universe |
| Reserve | `TeleportService:ReserveServerAsync(placeId)` → (code, privateServerId); `ReserveServer` deprecated |
| Stale codes | Codes never expire; reuse = fresh empty server. Battle bounces to Hub if `PrivateServerId` empty, `PrivateServerOwnerId ≠ 0`, manifest missing/tombstoned or `game.MatchmakingType ≠ mmType`; admits only roster UserIds from a Hub `SourcePlaceId` |
| Manifest | HashMap `match`/`<privateServerId>`, **≤ 8 KB**: matchId, mode, mapId, placeId, mmType, createdAt, term, roster[u, team, ticket, loadout], botSeed, botSlots; TTL 1,800 s; tombstone `{ended = true}` 7,200 s. Loadouts = compact Hub snapshots at enqueue (vehicle locked) |
| MemoryStore | 64 KB + 1.2 KB × users; 1,000 + 120 × CCU RU/min; ≈ 30k RU/min/partition; value ≤ 32 KB, key ≤ 128; empty scans cost 1 RU (index non-empty buckets) |
| Teleport | Server-only, ≤ 50/call; 5 attempts 1 s apart, 15 s on `Flooded`, no retry on GameFull/Unauthorized/GameNotFound/GameEnded; Hub deadline 40 s (< 45 s window) → re-queue at original `enqueuedAt`; TeleportData untrusted |
| DataStore | ≤ 4,194,304 chars, keys ≤ 50; Read and Write 60 + 40 × players/min per server (`UpdateAsync` uses both); design to experience Write 250 + 20 × CCU; queue 30; `BindToClose` 30 s (we use 25). Profile ≤ 200 KB, warn 512 KB, fail 2 MB |
| Session lock | `Profiles_v1`/`Player_<UserId>`, `MetaData.ActiveSession {placeId, jobId, sessionGuid, at}` in the value; autosave 60 s, random first offset; conflict → MessagingService release ping, retry 5 s then 10 s, **steal at 40 s**; lock > **300 s** old taken at once; saves re-check `sessionGuid` (loser aborts, kicks). Load fail → kick at 120 s, never default data. Per-key serial queue, backoff 2→32 s, 5 tries |
| Reward inbox | Battle servers **never** open profile sessions. At end: `UpdateAsync` append `{battleId, issuedAt, rewards, stats}` to `RewardInbox_v1`/`u_<UserId>` (≤ 20, no-op if present) before teleport. Hub drains on load and every 30 s while `pendingBattles`: apply if battleId ∉ `processed.battles`, save, then remove. Vehicle lock expires after 30 min unrewarded |
| Rings | `processed.receipts` 200, `processed.battles` 200, `requestId` last 50/session |
| Remotes | Unreliable `InputPacket` ≤ 64 B @ 30 Hz (40/s b60), `SnapshotPacket` ≤ 900 B (engine drops > 1,000). Token buckets: Fire 6/s · consumable/ammo 4/s · ping 3/5 s · queue 1/s · garage tx 5/s · platoon .2/s (08-R2). `math.isfinite`; never `InvokeClient`; honeypots |
| Characters off | `CharacterAutoLoads = false`; empty `StarterGui`; `PlayerCharacterDestroyBehavior = Enabled` (NotScriptable → project) + `task.defer(player.Destroy, player)`; `CreateDefaultPlayerModule = false`; `EnableMouseLockOption = false`; `TouchControlsEnabled = false` |
| Streaming | `StreamingEnabled = false` in Hub and Battle v1: no character → per-player server focus Part would leak positions; prediction and 445–564 m sightlines need the whole map; map is static and public. Gate ≤ 1,100 MB on 3–4 GB Android; fallback 09-R7.1 |
| Lighting | `Technology` deprecated/unscriptable → `LightingStyle` + `PrioritizeLightingQuality`; Rojo 7.4.4 lacks both, so the project uses typed values `{"Enum": 0}` (Realistic), `{"Bool": false}` |
| Live config | Experience Configs; one snapshot per battle at creation |
| Audience | **Mild** label (bloodless vehicle combat, crew "injured"); no paid random items/trading; genre Shooter; Kids/Select needs age-checked creator + 2FA, fee, 250 engaged plays/60 d, safety review |

## 20. QA must-pass invariants (07-R-QA; P0 in `scripts/check.sh`, < 3 min)

`tests/Harness/Invariants.check(battle)` after **every tick** of every headless battle/soak: (1) no NaN/±inf in any
vehicle, projectile or capture state; (2) 0 ≤ hp ≤ maxHp, valid module states, ammo ≥ 0, reload ≥ 0; (3) hull bottom ≥
ground − .05 m unless `Falling`, inside bounds; (4) **replication filter**: full enemy state only if team-visible and
≤ 564 m, minimap records only for team-visible beyond, nothing carrying an unspotted enemy's identity or exact position
(REG-SPT-08); (5) ledger sum = HP lost, damage dealt ≤ HP removed, capture ∈ [0, 100]; (6) no input from destroyed
vehicles or after the end; (7) client: no voices/effects on destroyed entities, voices ≤ budget.

P0 per commit: REG-NET-01/-03/-05 (rate limits; no C2S damage/HP/hit/reward/currency/position fields; 10k fuzz),
REG-ARM-01 (0 leaks in 10k rays/config), REG-ARM-03…07 goldens; battleId/`PurchaseId` applied once even concurrently;
failed load never writes; stolen lock rejects stale saves; `BindToClose` ≤ 25 s; results = `Scoring` goldens;
matchmaker at 1–100 players × 50 seeds obeys every rule and never mixes `MatchmakingType`; determinism (seed + inputs +
content hash → same event hash). P1 nightly: 30-bot soaks per map (0 stuck), map scanners, 100k fuzz. P2: UI/audio/devices.

## 21. Conflicts resolved

| # | Conflict | Decision (why) |
|---|---|---|
| 1 | 01 stud = 0.28 m | 3 studs/m; metres in config; 06's 3.33 audio curves use 3 |
| 2 | 01-R7 armor parts, Heartbeat shells | Analytic `ArmorGeometry` (parts replicate → leak); 30 Hz swept casts |
| 3 | 01 ally splash 50 %, ram ×.25 vs 04 FF off | FF fully off; allies block shells |
| 4 | 01-R10 role modifiers vs 03-R1 | 03-R1 (measured) |
| 5 | TD 4 (03) vs 5 (04, WoT 2.0); LT 3 vs WoT 2.4's 2 | TD 4 (12-min timer punishes camping; bots fill classes); LT 3 (bot scouts help) |
| 6 | Spread I–II single (03) vs I–III ±1 (04) | I–II single, III–IV ±1 (newcomers; bots make it cheap) |
| 7 | Radio module (01, ARCH); suspension-only (05) | Gun, Turret (opt.), Engine, Tracks; no radio; signal off |
| 8 | Radio operator (01) vs 4 crew (05) | 4 roles |
| 9 | LT VR bonus (02) vs flat (03) | Class VR factors on 03's tier column (scout identity) |
| 10 | Optics ×.80/×.50 (01) vs .60 (02) | 01 (two states) |
| 11 | Last-known 60 s (02) vs 30 s (06) | 30 s (stale info misleads) |
| 12 | Sixth Sense lamp + 10 s ring (02), 3 s (06), brand chevron 2 s | Brand; REG-SPT-05 "lamp 10 s" → "alert 2 s" |
| 13 | Ally blue default (06) vs brand green/red + CVD schemes | Brand (ΔE ≥ 20 per viewer, shape cues) + first-launch scheme prompt |
| 14 | Pen shapes solid/dashed/crossed (06) vs brand segments | Brand segments, 06's ±12.5 %; 06's CVD pen colours proposed to brand owner as `pen.cb.*` |
| 15 | UI scale formulas 06 / 09 / brand | Brand; 06's height-based Compact |
| 16 | Touch 48 (06/07/09) vs brand 44/48 | Battle ≥ 48, else ≥ 44 |
| 17 | StyleSheets (06) vs Luau Theme (09) | Theme v1 (Lune-testable) |
| 18 | `BillboardGui` (06) vs pooled overlay (09); fire 96/104 px, minimap 180/160 | Overlay; 104; 160 |
| 19 | Audio graphs 06 / 09 / audio.md; voices 32 vs 20; acoustic sim on/off | audio.md buses; 32/20; off v1 |
| 20 | Client queries 16/32 (09) vs 24 occlusion rays (audio.md); delay from 100 m (06) vs 150 (audio.md) | 24/48 budget, occlusion 8/24; 150 m |
| 21 | Unspotted shots: REG-SPT-08 "no sounds" vs audio.md fuzzed events vs brand "glint, no tracer" | Anonymous fuzzed `ShotHeard`; tracer only last ≤ 100 m; never identity/origin |
| 22 | Countdown 20 s (04/06) vs 30 s (08); arrival 60 s (08) vs 45 s (07); Hub deadline 60 vs 40 s; end 6 s vs 10 s | 20 s; 45 s; 40 s; 6 s banner, results in Hub |
| 23 | Lock stale 180 s (07) vs steal 40 s / dead 300 s (08) | 08 (ProfileStore-proven); REG-DATA-01 refusal window 40 s |
| 24 | Receipt ring 100/200; inbox `Pending_` vs `RewardInbox_v1`; reconnect via MemoryStore `active:` vs profile | 200; `RewardInbox_v1`; `profile.activeBattle` + tombstone |
| 25 | MM tick 2 vs 3 s; ticket TTL 120 vs 600 s; teleport tries 3 vs 5 | 3 s; 120 s refreshed 30 s (dead hubs' tickets expire fast); 5 |
| 26 | Premium as Bullion days (05) vs Robux sub (08); slots unlimited vs slot pass | Bullion days + Plus sub for conveniences; unlimited slots |
| 27 | Premium credits ×1.35 (05) vs ×1.5 VIII (03) | 03 |
| 28 | Merit (05) vs locked currencies/brand icons | Rejected; Campaign Tokens take the role |
| 29 | Battle Heroes for 10 v 10, 6-min battles (05) | WoT 15 v 15 values; cap 12 min, economy assumes ≈ 6 min avg |
| 30 | Splash cal/100 (01) vs 3 + .03 cal (03) | Direct fire 01, SPG 03 |
| 31 | Ping rates 3/5 s (06), 1/s b3 + 12/min (08), chat 1/10 s (04) | Markers 3/5 s + 12/min; chat 1/10 s; marker-only replies (Q/A rule) |
| 32 | `Technology = Future` (project, brand §10.3) vs deprecation | `LightingStyle`/`PrioritizeLightingQuality`; brand wording to update |
| 33 | Project `StreamingEnabled = true` vs off (08/09) | Off in Hub and Battle |
| 34 | ARCH `ReserveServer`, battle-side rewards; one vs per-map places | `ReserveServerAsync`, inbox; one place v1, per-map allowed |
| 35 | Doc numbers: write 300 vs 250 + 20·CCU; audio quota 2,000/30 d vs 100/mo; profile 200 KB/1 MB vs 512 KB/2 MB | Lower figures; 200 / 512 KB / 2 MB |

## 22. Open questions needing in-engine verification

1. `BulkMoveTo` roots + `Motor6D.Transform` without an Animator (fallback `C0`) for 30 vehicles at 60 FPS.
2. Client memory with streaming off on a 3–4 GB Android (gate 1,100 MB); join replication of the built map + terrain; `WriteVoxels` speed.
3. Server cost per `Raycast`/`Blockcast` (≤ 600/tick in 6 ms? if > 8 µs each, spotting cap → 200).
4. Unreliable 1,000 B limit before or after `buffer` compression; real bandwidth vs 20/40 KB/s.
5. Engine draw distance at low quality vs 564 m; Part instancing with 30 tanks at LOD1.
6. Rojo typed values give `LightingStyle` Realistic / `PrioritizeLightingQuality` false in Studio. Still to add to the project: `PlayerCharacterDestroyBehavior`, `CreateDefaultPlayerModule`, `PlayerScriptsUseInputActionSystem`, `DefaultListenerLocation`, `EnableMouseLockOption`.
7. Character-less places: camera, chat, core UI, `TouchControlsEnabled`; `ButtonSelect` with `AutoSelectGuiEnabled = false`; `GetImageForKeyCode`; touch via `InputBinding:Fire()`/`UIButton`.
8. Audio: mobile voice cost, one `AudioInteractionGroup` per emitter, `GetAudibilityFor`, `Play(atTime)` accuracy; `Highlight` with a shared `Adornee`.
9. Reserved servers: stale-code reuse, mixed-region placement, idle shutdown, cross-play splits sharing a `PrivateServerId`; `BindReceiptHandler` precedence and redelivery after Battle's `NotProcessedYet`.
10. Luau Execution (`IsRunning = false`) raycasts for static map scanners; client gain from `--!native`.
11. Policy reviews: icon markers vs preset rules, marker-only replies, Mild label for realistic tanks, Kids/Select safety review.
12. Telemetry to tune this doc: draws < 5 %, ≈ 6 min battles, spawn win 47–53 %, credit closure per tier, MemoryStore RU at real CCU, class win rates under TD 4 / LT 3.
