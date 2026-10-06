# Spotting — design and implementation

> Owner: spotting package. Code: `src/ReplicatedStorage/Shared/Spotting/{VisibilityModel,SpottingSystem}.luau`,
> `Shared/Types/Spotting.luau`, `Shared/Config/Spotting.luau`. Tests: `tests/Unit/ReplicatedStorage/Shared/Spotting/`.
> Authority: `docs/research/00-DECISIONS.md` §5 (values and rules), research 02 (detail), ARCHITECTURE §6.1 step 7
> and §6.4 (World). Every number below is a `Config.Spotting` key (real units: m, s, km/h, deg).

## 1. Purpose

Spotting is the information war: which enemy each team may know about. The battle server runs it once per 30 Hz
tick (ARCHITECTURE §6.1 step 7). Its output is **the anti-wallhack invariant source**: replication sends an enemy's
state to a client only when `SpottingSystem:isVisibleTo(clientTeam, enemyId)` is true, and full state only within
`ENEMY_DRAW_RANGE_M` (564 m) of the receiving vehicle (`replicationTier`). Scoring reads the `Spotted` events
(first-detection credit) and `spottersOf` (assist split). The HUD reads the `SixthSense` events, the effective view
range (VR circle) and the last-known markers.

Both modules are pure Shared code: no services, no `task.*`, no clock. Time comes in as `now`, the map comes in as a
`Types.World`, and iteration is in id order, so a battle replays bit-for-bit.

## 2. Rules and formulas

### 2.1 Spot distance (`VisibilityModel.spotDistance`)

```
spotDist(VR, camo) = min(MAX_SPOT_RANGE_M, VR − (VR − FORMULA_FLOOR_M) · camo)     -- 445, 50
camo (per ray)     = min(CAMO_TOTAL_CAP, body + min(FOLIAGE_STACK_CAP, foliage))   -- 0.90, 0.80
spotted            = d <= PROXIMITY_RADIUS_M (50, no ray)  or  (LOS ray clear and d <= spotDist)
```

* `d` is hull centre to hull centre, 3-D, metres. The hull centre is the hull CFrame raised by `hullSize.Y / 2`.
* VR is **not** capped (VR above 445 m eats into camouflage). VR at or below the floor spots nothing beyond itself.
* The 0.90 total cap means a 445 m observer always spots a clear-LOS target at ≥ 89.5 m (no invisible TDs).
* Worked examples (research 02 §3, all unit-tested): 445/0 → 445; 445/0.12 → 397.6; 445/1 → 50; 500/0.43 → 306.5;
  500/0.93 → 81.5 raw, 95.0 with the cap; 520/0.10 → 445; 300/0.18 → 255.

### 2.2 Body camouflage (`bodyCamo`, `composeBodyCamo`)

```
body = base[moving ? camo.moving : camo.stationary] × (afterShotMul while < SHOT_CAMO_PENALTY_S after a shot)
     + camo.paint + (camo.net once stationary >= STATIONARY_ARM_S)
moving = speed > STOP_SPEED_KMH (0.5) or |yaw rate| > MOVING_YAW_RATE_DEG_S (2)    -- VisibilityModel.isMoving
```

Crew skills, equipment, role trims and the paint bonus are already folded into `VehicleStats.camo` by StatsCalculator.
Spotting owns the runtime conditions: the after-shot window, the 3 s stationary arming of nets (and masts), and the
conditional modifiers of `VehicleStats.conditionalModifiers` on `viewRange`, `camoStationary` and `camoMoving` with
the conditions `Stationary`, `StationaryArmed`, `Moving`, `Spotted` ((base + Σadd) × Πmul; other conditions belong to
other systems). Nets/masts drop the tick the hull moves.

`VisibilityModel.defaultShotCamoMul(cal) = clamp(0.40 − 0.0025 (cal − 20), 0.05, 0.40)` (`SHOT_CAMO_MUL_*`) is the
decided calibre default for `GunStats.camoAfterShotMul` (75 mm → 0.2625, ≥ 160 mm → 0.05).

### 2.3 View range (`effectiveViewRange`)

`VR = (viewRangeM after conditional modifiers) × viewRangeMul × (SMOKE_INSIDE_VR_MULT if inSmoke) × visibilityMult`.
`viewRangeM` is `VehicleStats.viewRangeM` (base × class × f(L_cmd) × always-on equipment/skills). `viewRangeMul` is
the Combat runtime ratio (`EffectMultipliers.viewRangeMul`: optics damaged/destroyed, commander injury, stun).
`visibilityMult` is the per-map-variant weather hook (`VISIBILITY_MULT_DEFAULT` = 1; `setVisibilityMult`).

### 2.4 LOS: ports, checkpoints, foliage, smoke

* Observer ports (00-DECISIONS §5 "LOS points"), turret port first: (1) the gun-axis view point
  `hullCFrame * turretRing * Angles(0, −turretYaw, 0) * viewPoint`; (2) the static roof port over the hull centre at
  the top of the hull + turret box (highest of hull height, view point and checkpoints).
* Target checkpoints: `VehiclePivots.camoPoints` in hull space (turret roof, mantlet, 4 hull faces at 80 % height,
  inset 0.1 m), at most `MAX_CHECKPOINTS` (8). A vehicle without checkpoints uses its hull centre.
* One `World:sightLine(port, checkpoint)` per (port, checkpoint), both ports every check (no alternation), first
  success wins ("best ray wins": a bush over the hull but not the turret leaves the turret rays deciding). Vehicles
  and wrecks never block (the World is map-only).
* `blocked` fails the ray; `smoke` fails it when `SMOKE_BLOCKS_LOS`; a non-finite foliage value is treated as blocked.
* **15 m rules.** Foliage crossed within `FOLIAGE_OBSERVER_CLEAR_M` (15) of the port never conceals. For
  `SHOT_FOLIAGE_PENALTY_S` (3 s) after the target fires, foliage crossed within `FOLIAGE_SHOOTER_CLEAR_M` (15) of the
  checkpoint stops concealing it. `World:sightLine` returns only a sum, so the system measures the clear zones with
  sub-segment queries **only when foliage decides the ray** (clear-ray spots cost one query):
  `effective = min(FOLIAGE_STACK_CAP, max(0, total − nearObserver − nearShooter))`. When the ray is shorter than the
  clear zones together, all of it is clear. If the World implements the optional `FoliageProbe.foliageAlong`, the
  sub-segments are analytic and cost no ray; otherwise they are `sightLine` calls counted against the budget.
* Foliage concealment per kind (`FOLIAGE_CONCEALMENT`, `VisibilityModel.foliageConcealment`): light bush .25, hedgerow
  .40, dense bush .50, tree crown .30, felled tree .30, thicket .60; a single volume never above
  `FOLIAGE_CONCEALMENT_MAX` (.64); grass is never a volume.

### 2.5 Scheduling and the ray budget

* Directed pairs (observer, target) exist for every two vehicles of different teams (450 for 15 v 15).
* Every update, every live pair computes `d` (numbers only, no allocation). `d <= 50 m` spots immediately.
* Otherwise a pair is checked when due: `nextCheck = lastCheck + checkInterval(d) × (1 − CHECK_JITTER_FRACTION ×
  phase)`, with `checkInterval` piecewise linear over `CHECK_INTERVAL_CURVE` (50 m .10 s, 150 .50, 270 1.00,
  445 2.00) clamped to `CHECK_INTERVAL_MAX_S` (1.0 s). The jitter only shortens intervals (never above 1.0 s); its
  phase is a golden-ratio sequence seeded by `RNG.hash(observerId, targetId)` (deterministic, allocation-free).
* Forced checks (`EVENT_CHECK_ON_*`): every pair where the shooter is the target when `lastShotAt` advances; every
  pair of a vehicle that stops or (re)spawns; `forceCheck(id)`.
* Cheap reject without rays: `d > MAX_SPOT_RANGE_M` or `d > spotDist(VR, min(CAMO_TOTAL_CAP, body))` (the capped camo,
  research 02-R2 fact-check: an uncapped reject would drop 0.95-camo targets that the cap guarantees at 89.5 m).
* At most `MAX_RAYS_PER_TICK` (400) world queries per update. Due pairs are served: forced pairs nearest first,
  then pairs overdue by `DEFER_PRIORITY_S` (0.5 s) **oldest first** (FIFO, so no pair starves under sustained
  overload), then the rest nearest first. A pair the budget cannot finish is aborted (partial rays discarded) and
  stays due. The smallest allowed budget (48) covers one worst-case pair (2 ports × 8 checkpoints × 3 queries).

### 2.6 Team visibility, linger, markers, Sixth Sense

* A team sees target `t` while some observer of the team succeeded within `SPOT_LINGER_S` (10 s) — team-wide
  vision, no radio (`SIGNAL_RELAY_ENABLED = false`; `SpottingSystem.new` raises if it is set, relay is not
  implemented).
* Transitions emit `Spotted {team, target, spotter, first}` (spotter = the latest sighting, lowest id on ties;
  `first` = first time this team saw it this battle) and `Lost {team, target, position}`. `Lost` leaves a last-known
  marker (position at the moment of loss) for `LAST_KNOWN_MARKER_S` (30 s, conflict #11); re-spotting or the target's
  death removes it.
* Sixth Sense: one `SixthSense {team = the vehicle's own team, target}` event `SIXTH_SENSE_DELAY_S` (3 s) after the
  vehicle first becomes visible to any enemy team, while it still is and `sixthSense ~= false` (commander not
  injured). There is no unspotted cue. A new alert needs a fully unspotted period first. If the commander is injured
  at the 3 s mark, the alert fires when he recovers, if the vehicle is still spotted (OUR DESIGN CHOICE). The HUD shows
  it for `SIXTH_SENSE_ALERT_S` (2 s, brand chevron).

### 2.7 Destroyed vehicles and attribution

* Wrecks (`alive = false`) are visible to every team (`isVisibleTo` true, `replicationTier` by distance), leave the
  visible sets **silently** (the battle's `VehicleDestroyed` event tells clients, REG-MINI-01), are never targets of
  checks and never observe. A revived vehicle starts unseen (old sightings of it are discarded) and is force-checked.
* Dead observers stop spotting at once. Their past sightings keep the targets lit for the rest of the linger
  (`DEAD_SPOTTER_KEEPS_LINGER`, OUR DESIGN CHOICE: the information was already relayed) and keep assist credit within
  `ASSIST_WINDOW_S` (`DEAD_SPOTTER_ASSIST_CREDIT`, REG-SPT-07 design choice).
* `spottersOf(target, now, team?)` = observers whose last success is within `ASSIST_WINDOW_S` (10 s) of `now`: the
  allies who share the 0.5 × damage-reward assist pool (00-DECISIONS §5 "Rewards"; the split itself is Scoring's).
* A vehicle missing from the `update` list is removed: teams that saw it get `Lost`, and whatever only it was seeing
  is lost too.

## 3. Data flow

```
BattleInstance tick (30 Hz)
  steps 1–6: inputs, VehicleSim, TurretSim, GunState, projectiles (sets lastShotAt), damage (alive, viewRangeMul,
             sixthSense from DamageModel.effects)
  step 7:    events = spotting:update(now, spottingVehicles, world)       -- one reused record per entity
             -> Spotted/Lost: reliable event stream to the team; Spotted.first -> first-detection reward (§5 Rewards)
             -> SixthSense: to the alerted vehicle's owner (HUD chevron + sound)
  step 9:    for each client c, each enemy e: tier = spotting:replicationTier(c.vehicleId, e)
             "Full" -> snapshot state; "Minimap" -> 2 Hz record (MINIMAP_RECORD_HZ); "None" -> nothing
             (spectators without a vehicle: isVisibleTo(team, e) + VisibilityModel.replicationTier(visible, d))
Damage events (any step): spotters = spotting:spottersOf(target, now, shooterTeam) -> assist split
```

## 4. API (exact signatures)

```lua
-- Spotting/VisibilityModel (pure, reads Config.Spotting at call time)
spotDistance(viewRangeM: number, camo: number): number
totalCamo(bodyCamo: number, foliage: number): number
isWithinProximity(distanceM: number): boolean
isSpotted(distanceM: number, viewRangeM: number, camo: number): boolean
isMoving(speedKmh: number, yawRateDegS: number?): boolean
isStationaryArmed(moving: boolean, stationaryForS: number): boolean
isShotCamoPenaltyActive(sinceShotS: number?): boolean
isShotFoliagePenaltyActive(sinceShotS: number?): boolean
composeBodyCamo(base: number, afterShotMul: number, paint: number, net: number, armed: boolean, shotActive: boolean): number
bodyCamo(camo: CamoStats, moving: boolean, stationaryForS: number, sinceShotS: number?): number
defaultShotCamoMul(caliberMm: number): number
foliageConcealment(kind: FoliageKind | string, concealment: number?): number
effectiveFoliage(total: number, nearObserver: number, nearShooter: number): number
applyConditional(base: number, stat: StatKey, modifiers: { StatModifier }?, moving: boolean, armed: boolean, exposed: boolean): number
effectiveViewRange(viewRangeM: number, viewRangeMul: number?, inSmoke: boolean?, visibilityMult: number?): number
rawCheckInterval(distanceM: number): number
checkInterval(distanceM: number): number
scheduledInterval(distanceM: number, phase: number): number
replicationTier(teamVisible: boolean, distanceM: number): ReplicationTier   -- "Full" | "Minimap" | "None"

-- Spotting/SpottingSystem
SpottingSystem.new(options: SpottingOptions?): SpottingSystem             -- { visibilityMult: number? }
system:update(now: number, vehicles: { SpottingVehicle }, world: World): { SpottingEvent }
system:isVisibleTo(team: number, vehicleId: number): boolean
system:visibleSet(team: number): { number }                               -- live enemies, ascending, read-only
system:replicationTier(observerId: number, targetId: number): ReplicationTier
system:isExposed(vehicleId: number): boolean
system:spottersOf(targetId: number, now: number, team: number?, out: { number }?): { number }
system:lastSeenBy(observerId: number, targetId: number): number?
system:lastKnown(team: number, vehicleId: number): (Vector3?, number?)
system:lastKnownIds(team: number, out: { number }?): { number }
system:viewRangeOf(vehicleId: number): number?
system:bodyCamoOf(vehicleId: number): number?
system:forceCheck(vehicleId: number)
system:setVisibilityMult(mult: number)
system:stats(): SpottingStats
system:pairInfo(observerId: number, targetId: number): PairInfo?            -- debug / tests (allocates)
```

`SpottingVehicle` (Types/Spotting): `id, team, alive, cframe (hull, studs), turretYawRad?, pivots {turretRing,
viewPoint, camoPoints, hullSize} (a VehiclePivots satisfies it), viewRangeM, viewRangeMul?, camo (CamoStats), moving,
lastShotAt?, inSmoke?, sixthSense?, conditionalModifiers?`. `SpottingEvent = {kind, t, team, target, spotter?,
first, position?}`; records, `visibleSet` arrays and the stats record are reused — copy what you keep.

## 5. Edge cases

| Case | Behaviour |
|---|---|
| `now` NaN/inf or decreasing; duplicate id; team change; record without CFrame/pivots/camo | error (programming mistake) |
| Non-finite pose | the vehicle's pairs are skipped that tick (no spot either way; linger continues) |
| NaN/negative VR, NaN multipliers | VR 0 / multiplier 1 (VisibilityModel) |
| NaN ray camo passed to `spotDistance` | treated as 1 (fully concealed); camo clamped to [0, 1] |
| NaN / negative `CamoStats` parts | count as 0 (body camo is never NaN) |
| World returns NaN foliage / probe returns garbage | ray treated as blocked / probe discounts nothing (conservative) |
| Ray shorter than both 15 m zones | all foliage on it is see-through |
| A foliage volume crossing both clear zones | subtracted twice, clamped at 0 (only possible on rays < 30 m + 2 radii, i.e. inside proximity in practice; the oracle test's volumes cannot) |
| Observer inside event smoke | VR × 0.70; its own rays still cross its cloud, so it is blind except proximity (see limitations) |
| Shot recorded before spawn / in the future | no forced check; penalties start when `now >= lastShotAt` |
| Vehicle first passed with `alive = false` | a wreck: visible to all, never checked |

## 6. Mapping to 00-DECISIONS §5

| Decision row | Implementation |
|---|---|
| Formula, 0.90 cap, VR uncapped | `spotDistance`, `totalCamo`, `CAMO_TOTAL_CAP`; per-ray camo, best ray wins |
| Ranges 50 / 445 / 564, 2 Hz minimap | `PROXIMITY_RADIUS_M`, `MAX_SPOT_RANGE_M`, `ENEMY_DRAW_RANGE_M`, `MINIMAP_RECORD_HZ`, `replicationTier` |
| Schedule curve, 1.0 s clamp, jitter, forced checks, ≤ 400 rays, nearest first | `CHECK_INTERVAL_CURVE`, `CHECK_INTERVAL_MAX_S`, `CHECK_JITTER_FRACTION`, `EVENT_CHECK_ON_*`, `MAX_RAYS_PER_TICK`; FIFO for long-deferred pairs added (OUR DESIGN CHOICE, starvation) |
| LOS points: 2 ports × 6 checkpoints, Sight ray, vehicles/wrecks don't block | §2.4 (ports built from `VehiclePivots`) |
| Foliage values, stack ≤ .80 | `FOLIAGE_CONCEALMENT`, `FOLIAGE_STACK_CAP`, `foliageConcealment` |
| 15 m rules, 3 s | `FOLIAGE_*_CLEAR_M`, `SHOT_FOLIAGE_PENALTY_S`, sub-segment queries |
| Body camo, moving thresholds, class table | `bodyCamo`, `STOP_SPEED_KMH`, `MOVING_YAW_RATE_DEG_S`; class values live in `Content/Classes` |
| Paint +.04 (0 ranked), camoAtShot, 3 s arming | `PAINT_CAMO_BONUS(_COMPETITIVE)`, `defaultShotCamoMul`, `SHOT_CAMO_PENALTY_S`, `STATIONARY_ARM_S` |
| VR composition, stun/smoke, lenses vs mast | `effectiveViewRange` + `applyConditional`; StatsCalculator folds the rest; "don't stack" via one exclusive group |
| Linger 10 s, last-known 30 s | `SPOT_LINGER_S`, `LAST_KNOWN_MARKER_S` |
| Sixth Sense 3 s, no unspotted cue, off if commander injured | `SIXTH_SENSE_DELAY_S`, `sixthSense` flag |
| Signal range off | `SIGNAL_RELAY_ENABLED = false` (raises if enabled) |
| Smoke blocks, VR ×.70 inside, `visibilityMult` hook | `SMOKE_BLOCKS_LOS`, `SMOKE_INSIDE_VR_MULT`, `setVisibilityMult` |
| Rewards: first detection, assist pool among allies who saw ≤ 10 s ago | `Spotted.first/spotter`, `spottersOf`, `ASSIST_WINDOW_S` |

OUR DESIGN CHOICE refinements (not fixed by the decisions doc): FIFO service of long-deferred pairs; aborting (not
resuming) a pair the budget cannot finish; proximity evaluated every update instead of every 0.1 s (free, exact);
dead spotters keep linger and assist credit; Sixth Sense fires on commander recovery while still spotted; the roof
port height is the highest known point of the vehicle; removed vehicles drop their sightings at once.

## 7. Performance

* Per update: O(vehicles) pose/camo work, O(pairs) numeric distance work (no allocation), a sort of the due pairs,
  and the world queries. Ports and checkpoints are built lazily once per vehicle per update (CFrame ops only for
  vehicles in a LOS check). Events, visible sets and stats are reused.
* Lune (interpreted, no `--!native`): ≈ 0.4 ms per update for 30 moving vehicles with a stub World (excluding World
  cost). Soak on `HeightmapWorld`: ≈ 45 queries per tick on average over 10 s, peak 400 at spawn (all pairs forced).
* Worst case per pair: 2 × 6 × 3 = 36 queries without a FoliageProbe, 12 with one.

## 8. Tests (67)

* `VisibilityModel.spec` (24): config values and bounds; every worked example of research 02 §3; cap vs cheap reject
  (02-R11); monotonicity properties (seeded); camo composition hand calcs; after-shot calibre curve (75 → .2625,
  160 → .05); penalty windows and arming (REG-SPT-04/-09); foliage defaults, 15 m arithmetic, stack cap; VR
  composition and conditional modifiers; interval table (30 m .10, 100 .30, 200 .708, 350 1.457 → 1.0, 445 2.0 →
  1.0) and jitter bounds; replication tiers (REG-SPT-08).
* `SpottingSystem.spec` (38): first-update spotting; the 358 m edge; no rays beyond range; proximity through walls
  (49/51 m) and 10,000 random wall pairs (REG-SPT-03); 10,000 random open pairs (REG-SPT-02); crossing into range at
  50/150/300/445 m spotted within 1.0 s + 1 tick (REG-SPT-01); interval/jitter scheduling at 200 and 350 m; forced
  shot/stop/spawn checks in the same tick; ray budget never exceeded, forced pairs nearest first, no starvation under
  sustained overload; camo cap (85/95 m), foliage stack (125/135 m), best ray wins, observer and shooter 15 m rules
  (REG-SPT-10) with and without a FoliageProbe; smoke; net/mast arming and after-shot window (REG-SPT-04/-09,
  REG-MINI-03); linger, Lost once, last-known marker life and clearing; edge flicker (REG-SPT-06); Sixth Sense timing,
  re-arming, suppression (REG-SPT-05); attribution incl. dead spotters (REG-SPT-07); wrecks, revive, removal;
  replication tiers; input validation; NaN poses; weather multiplier; event-record reuse; order-independent
  determinism.
* `SpottingSoak.spec` (5): 30 vehicles on a hilly `HeightmapWorld` with buildings and foliage, moving, stopping,
  firing and dying: every tick the counted `sightLine` calls stay ≤ the budget and the invariants hold (visible sets
  sorted and consistent with `isVisibleTo`, `replicationTier` and the client mirror rebuilt from events; every visible
  enemy justified by a sighting within the linger; dead observers never gain sightings; `spottersOf` exact; one
  Sixth Sense per exposure; `Spotted.spotter` alive and seeing this tick); the same soak under a 48-ray budget with
  bounded re-check gaps; same-seed determinism; 100 flat + 20 hilly random static scenes agree **exactly** with an
  independent brute-force oracle (per-volume 15 m rules).

## 9. Known limitations

* `World:sightLine` returns a foliage sum, not per-volume hits, so the 15 m rules cost extra sub-segment queries
  (up to 3 per ray) unless the World implements `FoliageProbe.foliageAlong` (requested from the World/map team).
* Checkpoints are hull-space points (contract): the mantlet point does not follow the turret yaw.
* Smoke is all-or-nothing per ray; an observer inside a cloud is blinded by its own cloud (plus the 0.70 VR penalty).
  Event smoke is not in Random battles; revisit with a per-cloud "inside" exemption if a mode needs it.
* No signal relay (raises if enabled). No `spottingScale` for small maps (research 02-R10) — add if a map needs it.
* Per-vehicle linger modifiers (Improved Radio Set / Jamming style) are not modelled; `SPOT_LINGER_S` is global.
* Team change mid-battle is rejected (modes that swap teams must rebuild the system).

## 10. In-engine verification needed

* Server cost of `RobloxWorld:sightLine` (00-DECISIONS §22 Q3): if > 8 µs, set `MAX_RAYS_PER_TICK` to 200 and check
  pop-in under load; measure `update` time with 30 vehicles (target ≤ 2 ms, else Parallel Luau LOS actors).
* Port/checkpoint placement on real blueprints (no checkpoint buried in the hull or terrain on slopes; REG-SPT-02
  self-occlusion is impossible by construction because vehicles are not in the World).
* Perceived pop-in at 445 m with the 1.0 s clamp plus 100 ms interpolation; Sixth Sense latency feel.
* Foliage authoring: every foliage visual has a matching analytic volume (map lint), client fade within 15 m.
