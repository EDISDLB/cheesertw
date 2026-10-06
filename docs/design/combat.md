# HULLDOWN combat core — design

> Owner: combat package. Code: `src/ReplicatedStorage/Shared/Combat/*`, `Types/Combat.luau`, `Config/Combat.luau`.
> Tests: `tests/Unit/ReplicatedStorage/Shared/Combat/*`. Authoritative values: `docs/research/00-DECISIONS.md`
> §1–§4 (this doc says where we refined an **O** row); detail: research 01 (R1–R9).

## 1. Purpose and scope

Pure, deterministic Luau that answers every combat question the server (and the client's Armor Inspector /
reticle) asks:

| Module | Answers |
|---|---|
| `ArmorGeometry` | Where does a world ray cross a vehicle's armor at this pose? What is near a point (spall, splash)? Is the model watertight? |
| `Ballistics` | Where is a shell at time t, what segment did it sweep this tick, when does it despawn, what pen does it keep at distance d, what elevation hits a target? |
| `Penetration` | What does one plate do to one shell (normalization, 2/3-calibre rules, ricochet, T_eff, HEAT gap, HE screen cost) and the ±25 % rolls |
| `HE` | HE/HESH formulas: non-pen blast, splash, radius, spall/splash module damage, stun |
| `ShotResolver` | What did a shell do to a target: walk all plates, ricochet continuation, internal path, HE model, splash list |
| `DamageModel` | How the target's state changes: HP, modules, crew, fire, ammo rack, repairs, consumables, stun, rams, falls, drowning; runtime effect multipliers |
| `CrewEffects` | Crew level curves and the crew-injury effects table (exported for StatsCalculator / GunState) |
| `Fire` | Fire state machine (ignite, DoT ticks with carry, extinguish) |
| `Dispersion` | Aiming circle: bloom, convergence, after-shot bloom, radius at distance, shot sampling |

Everything is server-authoritative by use (the server owns the RNG and the states); nothing here touches services,
`task.*`, clocks or Instances. Friendly fire is **not** decided here: the resolver is team-agnostic and the caller
applies 00-DECISIONS §2 "Friendly fire 0" (allies consume shells for 0 damage, splash/rams/fire never hurt allies).

## 2. Units and conventions

* Config and content are real-world (mm, m, m/s, m/s², deg, s, kg). Rays, positions, ArmorModel and Projectile are
  **studs** (3 studs = 1 m, `Core/Units`). Distances returned by ray queries are studs along the unit ray;
  splash / falloff distances are converted to metres before formulas.
* Poses (`Types/Combat.VehiclePose`): `hullCFrame`, `turretYawDeg` (hull-relative, + clockwise), `gunPitchDeg`
  (+ up), optional `gunYawDeg` (casemate). Same names and units as `Vehicle/TurretSim` state, so a TurretSim state +
  hull CFrame is a pose. Group frames (Types/Vehicle conventions):
  `Turret = Hull * turretRing * Ry(−yaw)`, `Gun = Turret * gunTrunnion * Ry(−gunYaw) * Rx(pitch)`.
* Vector3/CFrame are float32 in Roblox and Lune: geometry is exact to ~1e-4 studs at map scale (tests use that).
* All HP and module damage values are whole numbers (halves round up); penetration stays fractional (mm).

## 3. Data flow (one shell)

```
fire:   dir = Dispersion.sampleDirection(muzzle.LookVector, Dispersion.radiusM100(aim), rng)
        p   = Ballistics.launch(muzzle.Position, dir, shell);  Dispersion.onShot(aim)
tick:   from, to, expired = Ballistics.step(p, dt)                      -- swept segment, studs
        mapHit = World:raycast(from, to − from, "Shell")                 -- map (caller)
        i, d = ShotResolver.nearestTarget(vehicles, from, to − from, min(segLen, mapHit.distance), {[shooter]=true})
        if i: if ally(i) -> shell consumed, 0 damage ("AllyBlocked")      -- caller policy
              else o = ShotResolver.resolve(vehicles[i], {shell, origin=from, direction=to−from, maxDistance=…,
                       firedFrom=muzzle, penetrationMm=carry.pen, damage=carry.dmg, ricochets=carry.n,
                       nearby=enemiesNear(burst)}, rng)
                   DamageModel.apply(state[i], o, rng, shooterId, events)   -- decides fire / detonation / kill
                   for s in o.splash: DamageModel.applySplash(state[s.index], s, rng, shooterId, events)
                   if o.ricochetRay: Ballistics.redirect(p, ray.origin, ray.direction); carry = ray
        elif mapHit and HE: hits = ShotResolver.burst(shell, mapHit.position, nearby, rng, carry.dmg)
        if expired and HE: ShotResolver.burst(shell, p.position, …)
per tick, step 6: consumable hooks (extinguish/useRepairKit/useMedkit) then DamageModel.update(state, dt, rng, events)
                  DamageModel.updateDrowning(state, submerged, dt, events)
consumers: e = DamageModel.effects(state) -> VehicleSim (enginePowerMul, canMove, topSpeedMul, hullTraverseMul),
           TurretSim (turretTraverseMul), GunState (reloadTimeMul, canFire), Dispersion (aimTimeMul, dispersionMul,
           gunDamaged, stunned), Spotting (viewRangeMul, sixthSense)
```

Two shells resolved in the same tick are applied **in order** (resolve → apply → resolve → apply): the second sees
the first's state (a destroyed target turns it into a no-op). The target's pose is whatever the caller passes at
resolution time; nothing is cached across ticks, so pose changes mid-flight are handled by re-posing each tick.

## 4. ArmorGeometry

* **Model**: `Types/Vehicle.ArmorModel` — convex volumes (≥ 4 half-space faces `n·p <= d`, outward unit normals)
  grouped Hull / Turret / Gun, with kinds Armor (body), Layered (main armor outside the body: mantlet), Spaced
  (screens, tracks, barrel; `module` = external module), Module, Crew.
* **raycast(model, pose, origin, dir, maxDistance?, out?)**: whole-model bounding-sphere broadphase in hull space,
  then per-volume sphere test and slab clipping (max entering t / min exiting t over faces). Every crossing in
  `[0, maxDistance]` is written into a pooled `CrossingBuffer` record `{distance, point, normal (outward, world),
  entering, thicknessMm, zone, spaced, volumeId, volumeKind, group, module?, crewSlot?, volume, face, faceIndex}` and
  insertion-sorted by distance. Ties within 1e-4 studs use **rank**: Spaced/Layered exit 0 · Spaced/Layered entry 1 ·
  Armor entry 2 · Armor exit 3 · Module/Crew entry 4 · exit 5 — walkers see outer layers first, a spaced exit before
  the plate behind it (HEAT gap 0), and never "leave" the body at a face shared by two Armor volumes.
* **Allocation**: each model is compiled once (weak-keyed cache) into flat number arrays; the inner loop is pure
  arithmetic. Per query: ≤ 3 CFrame compositions (turret/gun only after the broadphase hits) and one pooled record
  per crossing. `invalidate(model)` drops the cache if a model table is ever mutated.
* **Helpers**: `groupFrames/groupFrame/muzzleFrame` (the pose transform shared with the Armor Inspector and
  renderer), `firstHit`, `firstHitDistance`, `containsPoint`, `volumeAt`, `volumesNear` (spall/splash; distance =
  max face-plane distance, exact on faces, slightly generous near edges), `nearestArmor` (splash T_min: thinnest
  face facing the point within R), `impactAngleDeg`, `effectiveThickness`, `reflect`, `validate` (contract checks
  for the Blueprint team), `sampleInteriorPoint`, `probeLeaks` (REG-ARM-01 probe, optional visual-surface sampler).

## 5. Ballistics

| Rule | Formula | Keys |
|---|---|---|
| Velocity | authored ShellDefinition.velocityMps is already 0.6 × real; families APCR 1.25, HEAT 0.85, HE 1.0 × AP | `VELOCITY_SCALE`, `VELOCITY_RATIO` |
| Flight | `p(t) = o + v₀t − ½ g t² ŷ`, no drag, g = shell gravity (19.62 m/s² = 58.86 studs/s²) | `SHELL_GRAVITY_MPS2` |
| Despawn | path length (chord sum) ≥ maxRange: the last segment is cut at the remaining length | `MAX_RANGE_M`, `ARTILLERY_MIN_RANGE_M` |
| Falloff | AP/APCR: pen to 100 m, linear to `penetrationAt500Mm` at 500 m, flat beyond; others constant | `FALLOFF_START_M`, `FALLOFF_END_M`, `FALLOFF_AT_END` |
| Solver | `tanθ = (v² ∓ √(v⁴ − g(gx² + 2yv²)))/(gx)`, tof = x/(v cosθ); nil when unreachable | — |

`step()` is analytic (same arc at any tick rate, so client tracers match server shells: REG-PRJ-02) and returns the
swept segment for `World:raycast` + `ArmorGeometry` (no tunnelling at 50 m/tick: REG-PRJ-06). `redirect()` re-bases
the arc for ricochet continuation, keeping speed and range budget.

## 6. Penetration (one plate)

θ = raw impact angle from the outward normal (0 head-on). T = nominal thickness, cal = caliber.

| Step | Rule | Keys |
|---|---|---|
| Ricochet | kinetic/HEAT: θ > ricochetAngle (AP/APCR 70, HEAT 85; strict) and not (kinetic and cal > 3T) → ricochet, pen × 0.75 (HEAT × 1). HE/HESH never | `RICOCHET_ANGLE_DEG`, `THREE_CALIBER_RATIO`, `RICOCHET_PEN_MUL` |
| Normalization | n' = n (AP 5, APCR 2, HEAT/HE 0); kinetic cal > 2T (strict): n' = n·1.4·cal/(2T) | `NORMALIZATION_DEG`, `TWO_CALIBER_*` |
| T_eff | T / max(0.05, cos(max(0, θ − n'))) | `EFFECTIVE_COS_FLOOR` |
| Main / Layered / Spaced | pen ≥ T_eff penetrates; Layered/Spaced subtract T_eff and continue | — |
| HE/HESH on Spaced | pen −= 3T (nominal); ≤ 0 → burst there | `HE_SCREEN_PEN_MUL` |
| HEAT gap | pen × max(0, 1 − 0.5·gap_m) across each air gap after a plate (and the internal path stops at 2 m) | `HEAT_GAP_LOSS_PER_M` |
| Rolls | truncated normal, σ = spread/2 · mean, re-roll (8 tries) beyond 2σ then clamp; always within ±spread | `ROLL_SPREAD`, `ROLL_SPREAD_SIGMAS`, `ROLL_RESAMPLE_TRIES`, `COMPETITIVE_SPREAD` |

## 7. ShotResolver

Walk (00-DECISIONS §1 "Order"): roll pen (falloff from `firedFrom` to the first plate) and damage **once**; then in
ray order, outside the body: Spaced/Layered entries are plates; the first Armor entry is the body (Main plate);
`MAX_PLATES` (8) caps the walk.

* **Ricochet**: reflect about the plate normal, start 0.01 studs off the surface, pen × 0.75; the reflected ray is
  re-cast against the **same** vehicle first (it can hit the turret after bouncing off the glacis); if it misses, the
  outcome carries `ricochetRay {origin, direction, penetrationMm, damage, ricochets}` for the caller to keep flying
  (it can hit anyone but the shooter: caller). A ricochet beyond `RICOCHET_MAX` (1) deletes the shell. A ricochet
  deals no HP damage; an external module (track, barrel) struck is still damaged.
* **Penetration** of the body: damage = rolled alpha. Kinetic/HEAT: internal path from the entry along the shell's
  ray for max(0.5 m, 10 cal) (HEAT ≤ 2 m), ending where the ray leaves the union of Armor volumes; each Module volume
  entered rolls `MODULE_HIT_CHANCE[kind]` (engine/fuel/ring/optics .45, gun .33, ammo .27), each Crew volume
  `CREW_HIT_CHANCE` (.33) × crewInjuryChanceMul. Module damage = shell.moduleDamage × (rolled α / α), capped at
  1.2 × module max HP.
* **Spaced armor** (tracks, skirts, barrel): `EXTERNAL_HIT_CHANCE` (1.0) external module damage on every strike,
  never HP damage on its own; a shell stopped there is `absorbed` (Battle "Absorbed"). A shell that passes only
  through spaced volumes and leaves the vehicle is consumed as absorbed (OUR choice: it would hit terrain).
* **HE/HESH** (1.13 adapted, research R4): penetration = rolled α + spall sphere (R = explosionRadiusM, default
  cal/100 m) rolling Module/Crew volumes at full module damage. Non-pen on main/layered armor = `HE.nonPenDamage`
  (max(0.05α, 0.5α_r − 1.1·T_nominal·K_spall), HESH × 1.15) + spall rolls × 0.5. Burst on a screen/track = splash on
  its own body (distance along the ray to the next main plate, that plate's T) + external module damage. Every HE
  burst splashes the caller's `nearby` list: D = max(0, 0.5α_r(1 − d/R) − 1.1·T_min·K), external modules within R take
  moduleDamage × (1 − d/R); artillery shells with `stun` add a stun lerped maxS → minS.
* **Outcome** (`Types/Combat.ShotOutcome`): `result` Penetration | Ricochet | NonPenetration | HEBlast | Miss, flags
  `hit / noop / absorbed / deleted`, `damage`, `potentialDamage`, `penetrationMm` (rolled), `penetrationRemainingMm`,
  `effectiveArmorMm` + `decidingZone` (plate that decided), `impact {point, normal, distance, zone, thicknessMm,
  effectiveMm, angleDeg, volumeId, volumeKind, group}` (first plate), `modulesHit {kind, damage, external, volumeId}`,
  `crewHit {slot, damage, volumeId}`, `engineHit`, `ricochetRay?`, `burstPoint?`, `splash {index, id, damage,
  distanceM, thicknessMm, stunS, modulesHit}`, and — filled by `DamageModel.apply` — `fireStarted`,
  `ammoRackDetonation`, `damageApplied`, `killed`. `toShotResultKind()` maps to `Types/Battle.ShotResultKind`.
* **No-op**: a target whose state is destroyed gets `noop = true` with impact geometry only (spark on the wreck).
* **RNG draw order** (determinism): pen roll, damage roll, then hit-chance draws in ray/distance order.

## 8. DamageModel

* **State** (`VehicleCombatState`): hp/maxHp, modules `{hp, maxHp, state Ok|Damaged|Destroyed, repairS,
  repairRemainingS}`, crew `{slot, role, also, level, hp, maxHp, injured}`, fire `{burning, remainingS, tickAccum,
  carry, elapsedS, igniter}`, stun, drowning timer, ammoStored, destroyed/cause/killer, copied VehicleStats
  multipliers, ram/fall contact-id ring. Built by `DamageModel.new(VehicleStats)` (any `DamageModelInit`).
* **States**: Ok while hp > 50 % (`MODULE_DAMAGED_FRACTION`), Damaged ≤ 50 %, Destroyed at 0; Destroyed starts a field
  repair of `repairS` (× driver-injury ratio) back to Damaged at 50 % (`REPAIR_RESTORE_FRACTION`).
* **apply(state, outcome, rng, attacker, events)**: modules (each Engine hit rolls fireChance × 1.5 if fuel damaged;
  fuel destroyed → fire; rack destroyed with ≥ 1 shell stored → **detonation**, cause AmmoRack) → crew (0 HP →
  injured, never killed) → HP (clamped to remaining; destroyed at 0). Returns HP removed; the damage ledger therefore
  always equals HP lost.
* **Fire**: 8 s (VehicleStats.fireDurationS) × 2.5 %/s of max HP in whole-HP ticks every `FIRE_TICK_S` (1 s) with a
  fractional carry, credited to the igniter; engine bay modules −5 %/s; each tick one random uninjured crew member is
  hit with chance 0.10 for 25 % of crew HP (OUR choice for "bay modules/crew hit"); the Automatic Extinguisher
  (armed flag) puts it out 0.5 s after ignition and disarms. Fire never ticks on a destroyed vehicle.
* **Consumables**: `extinguish`, `useRepairKit` (all modules 100 %, timers cleared), `useMedkit` (all crew healed,
  stun cleared), `armAutoExtinguisher`. Cooldowns belong to the consumable system.
* **Effects** (`effects(state)` → `EffectMultipliers`): engine Damaged power × .5 / Destroyed immobile; ammo Damaged
  reload × 1.25; fuel Damaged fire chance × 1.5; gun Damaged aim × 1.25 (+ `gunDamaged` for the × 1.5 bloom) /
  Destroyed can't fire; ring Damaged traverse × .5 / Destroyed 0; optics VR × .8 / × .5; tracks Destroyed immobile
  (wheeled: top speed × .75 per side); crew injuries via `CrewEffects`; stun reload/aim × 1.25, dispersion × 1.2,
  traverse × .8, speed × .85, VR × .9.
* **Crew** (`CrewEffects`): reload × 0.875/(0.00375·L + 0.5); f(L) = 0.57 + 0.0043·L × VR/traverse, ÷ aim/dispersion/
  repair. Duties: Commander → VR; Gunner → aim, dispersion, turret traverse; Driver → hull traverse, repair (OUR);
  Loader → reload (loaders averaged). Injured = L 50; injured commander −10 L to the others, Sixth Sense off. Ratios
  are relative to `VehicleStats.crewLevels` so equipment/rations already folded in are respected.
  `CrewEffects.INJURY_EFFECTS` / `DamageModel.INJURY_EFFECTS` is the exported table.
* **Ramming**: D_B = max(0, 0.05·m_A[t]·v² · dealtMul − 1.1·T_B·K_B) × (B front arc ½) × takenMul for closing speed
  v ≥ 3 m/s (symmetric `resolveRam`); `applyRam` applies a contact id once (REG-ARM-10) and rolls the contact-side
  track (`RAM_TRACK_HIT_CHANCE` .5, damage .5 × raw energy term; OUR). `isFrontArc` = ±45° of the hull's −Z.
* **Falls**: v_y > 7 m/s: 0.6·m[t]·(v_y − 7)² (× 2 inverted, × fallDamageMul); a random track destroyed with chance
  min(1, (v_y − 7)/5); no kill credit; landing on a tank = `resolveRam` at v_y (caller).
* **Drowning**: `updateDrowning(state, submerged, dt)`: 10 s submerged → destroyed (cause Drown, no credit), warning
  events on enter/exit, reset on exit.
* **Events** (`CombatEvent`): Damage, ModuleState, CrewInjured, CrewHealed, Fire, Stunned, Drowning, Destroyed — the
  caller stamps time/target and maps them to `Types/Battle.BattleEvent`. Nothing is emitted after Destroyed.

## 9. Dispersion

M_target = √(1 + (k_mv·v_kmh)² + (k_hull·ω_hull)² + (k_tur·ω_tur)²) × damagedMul (gun damaged) × 1.15 (wheeled
moving) × 1.2 (stunned), clamped to `DISPERSION_MAX_MULTIPLIER`; `update`: M = max(M_target, M·e^(−dt/τ)) with
τ = aimTime × aimTimeMul; `onShot`: M = max(M, M_target) × afterShot (LT/MT/TD 3, HT 3.5, SPG/derp 4; override for
volleys); radius at d = dispersionM100 × M × dispersionMul × d/100. Sampling (`DISPERSION_MODEL` "radial"): miss
radius |N(0, R/2)| at a uniform angle, re-rolled beyond R (8 tries, then the rim); "gauss2d" kept. The shot direction
deviates by atan(r100/100), independent of target distance. `timeToAim` = τ·ln(M/M_target) (bots, HUD).

## 10. Config keys (`Config/Combat.luau`)

Families: `KINETIC`, `EXPLOSIVE`, `NORMALIZATION_DEG`, `RICOCHET_ANGLE_DEG`, `TWO_CALIBER_RATIO`, `TWO_CALIBER_FACTOR`,
`THREE_CALIBER_RATIO`, `EFFECTIVE_COS_FLOOR`, `MAX_PLATES`, `RICOCHET_MAX`, `RICOCHET_PEN_MUL`,
`RICOCHET_SURFACE_OFFSET_STUDS`, authoring `SPECIAL_PEN_RATIO`, `HE_ALPHA_RATIO`, `HE_PEN_PER_CALIBER`,
`HESH_PEN_PER_CALIBER`. RNG: `ROLL_SPREAD`, `ROLL_SPREAD_SIGMAS`, `ROLL_RESAMPLE_TRIES`, `COMPETITIVE_SPREAD`.
Flight: `FALLOFF_START_M`, `FALLOFF_END_M`, `FALLOFF_AT_END`, `VELOCITY_SCALE`, `VELOCITY_RATIO`, `SHELL_GRAVITY_MPS2`,
`MAX_RANGE_M`, `ARTILLERY_MIN_RANGE_M`. HEAT: `HEAT_GAP_LOSS_PER_M`. HE: `HE_SCREEN_PEN_MUL`, `HE_DESTRUCTIBLE_PEN_MUL`,
`HE_NONPEN_ALPHA_FACTOR`, `HE_ARMOR_FACTOR`, `HE_NONPEN_FLOOR`, `HESH_NONPEN_MUL`, `HE_SPALL_MODULE_MUL`,
`SPLASH_RADIUS_M_PER_MM`, `ARTILLERY_SPLASH_BASE_M`, `ARTILLERY_SPLASH_PER_MM`, `SPLASH_ALPHA_FACTOR`,
`SPLASH_MODULE_MUL`, `SPALL_FACTOR_BASE`. Modules: `MODULE_HP_K`, `CREW_HP_K`, `MODULE_DAMAGED_FRACTION`,
`INTERNAL_PATH_MIN_M`, `INTERNAL_PATH_CALIBERS`, `MODULE_HIT_CHANCE`, `CREW_HIT_CHANCE`, `EXTERNAL_HIT_CHANCE`,
`MODULE_DAMAGE_FACTOR`, `MODULE_DAMAGE_CAP_MUL`, `REPAIR_S`, `REPAIR_RESTORE_FRACTION`, `ENGINE_DAMAGED_POWER_MUL`,
`AMMO_DAMAGED_RELOAD_MUL`, `FUEL_DAMAGED_FIRE_MUL`, `GUN_DAMAGED_AIM_MUL`, `RING_DAMAGED_TRAVERSE_MUL`,
`OPTICS_DAMAGED_VR_MUL`, `OPTICS_DESTROYED_VR_MUL`, `WHEELED_LOST_SIDE_SPEED_MUL`, `AMMO_RACK_DETONATION_MIN_SHELLS`.
Fire: `FIRE_CHANCE`, `FIRE_CHANCE_DEFAULT`, `FIRE_DURATION_S`, `FIRE_DAMAGE_PER_S`, `FIRE_TICK_S`,
`FIRE_MODULE_DAMAGE_PER_S`, `FIRE_CREW_HIT_CHANCE`, `FIRE_CREW_DAMAGE_FRACTION`, `FIRE_FIGHTING_DURATION_MUL`,
`DCS_FIRE_CHANCE_MUL`, `AUTO_EXTINGUISHER_FIRE_CHANCE_MUL`, `AUTO_EXTINGUISHER_DELAY_S`. Crew: `CREW_BASE_LEVEL`,
`CREW_INJURED_LEVEL`, `COMMANDER_INJURED_PENALTY`, `RELOAD_CURVE_*`, `STAT_CURVE_*`. Ram/fall/drown:
`RAM_MIN_SPEED_MPS`, `RAM_ENERGY_FACTOR`, `RAM_ARMOR_FACTOR`, `RAM_FRONT_ARC_TAKEN_MUL`, `RAM_FRONT_ARC_HALF_DEG`,
`RAM_TRACK_HIT_CHANCE`, `RAM_TRACK_DAMAGE_MUL`, `FALL_MIN_SPEED_MPS`, `FALL_DAMAGE_FACTOR`, `FALL_INVERTED_MUL`,
`FALL_TRACK_SPAN_MPS`, `DROWN_TIME_S`, `CONTACT_MEMORY`. Stun: `STUN_*_MUL`. Aiming: `DISPERSION_MODEL`,
`DISPERSION_EDGE_SIGMAS`, `DISPERSION_RESAMPLE_TRIES`, `BLOOM_*`, `AFTER_SHOT_BLOOM`, `DERP_AFTER_SHOT_BLOOM`,
`WHEELED_MOVING_BLOOM_MUL`, `GYRO_BLOOM_MUL`, `SNAP_SHOT_TURRET_BLOOM_MUL`, `DISPERSION_MAX_MULTIPLIER`.
`BOUNDS` makes ~80 numeric keys live-overridable (nested keys as `"MODULE_HIT_CHANCE.AmmoRack"`); every module reads
`Config.Combat` at call time, so overrides take effect immediately.

## 11. Mapping to 00-DECISIONS

| Decision row | Where | Notes |
|---|---|---|
| §1 Families, Defaults | `KINETIC/EXPLOSIVE`, authoring ratios, `Ballistics.familyVelocityMps`, `defaultPenetrationAt500` | per-gun overrides stay in content |
| §1 Normalization, 2-/3-cal | `Penetration.normalizationDeg/isTwoCaliber/isOvermatch` | strict `>` (REG-ARM-03) |
| §1 Ricochet, Continuation | `Penetration.ricochets`, ShotResolver ricochet branch | re-cast on the same vehicle first |
| §1 Effective T, Order, ≤ 8 plates | `ArmorGeometry.effectiveThickness`, ShotResolver walk | cos floor 0.05 |
| §1 RNG | `Penetration.roll/rollDamage` | 8 tries then clamp; competitive spread selectable |
| §1 Falloff, Velocity, Gravity/range, Simulation | `Ballistics` | analytic arc, chord-sum range |
| §1 HEAT spaced | `Penetration.heatGapFactor`, walk gap from spaced exit | internal path ≤ 2 m |
| §1 HE (1.13), Splash, §21 #30 | `HE`, ShotResolver HE branches, `burst` | radius cal/100 direct, 3 + .03 cal SPG |
| §2 Modules, HP, States, Internal path, Module dmg, Repair, Effects | `DamageModel`, `MODULE_*`, `REPAIR_*` | AmmoRack repair 10 s is OUR (0-shell case only) |
| §2 Fire | `Fire`, `DamageModel.update/apply` | bay module/crew damage numbers OUR |
| §2 Crew injury, §4 L / Reload / Other stats | `CrewEffects` | driver = repair duty OUR |
| §2 Ramming, Falls, Drowning | `DamageModel.ramDamage/applyRam/fallDamage/applyFall/updateDrowning` | track roll numbers OUR |
| §2 Friendly fire | caller | resolver is team-agnostic |
| §3 Model, Converge, Bloom, After shot | `Dispersion` | wheeled/stun multipliers on M_target |
| §7.4 SPG stun | `HE.stunDuration`, `DamageModel.applyStun`, `effects` | medkit clears stun |
| §20 REG-ARM-01 | `ArmorGeometry.probeLeaks` | used by the 10,000-ray spec |

## 12. Edge cases handled

Rays: zero/NaN/inf → no crossings / Miss; ray starting inside a volume reports exits only; maxDistance bounds the
first impact. Shells: second ricochet deletes; MAX_PLATES; pass-through spaced = absorbed; destroyed target = no-op;
two shells same tick = ordered application; pen/damage carried across continuations (rolled once). State: overkill
impossible (clamped), no events after Destroyed, fire stops on destruction, extinguish before update = no damage
that tick, repeated contact ids ignored, NaN damage = 0, module damage capped per hit, empty rack never detonates.

## 13. Tests (`tests/Unit/ReplicatedStorage/Shared/Combat`)

`CombatFixtures` builds a closed hull + turret with every volume kind. Specs: ArmorGeometry (21: hand-computed
crossings, pose transforms, tie ranks, NaN, buffer reuse, 2,000-ray plane/pairing property, **10,000-ray
watertightness = 0 leaks (REG-ARM-01)**, leak detection on a gapped model), Ballistics (16: falloff goldens and
10,000-shell property REG-ARM-06, analytic flight, max range REG-PRJ-04, no tunnelling REG-PRJ-06, solver), Penetration
(20: 100,000-roll bounds/mean REG-ARM-07, clamp path, REG-ARM-03 table, ricochet thresholds, plates, HE 3 T
REG-ARM-05), HE (6), ShotResolver (31: pen/non-pen, multi-plate, glacis ricochet into the turret, ricochet ray,
deletion REG-ARM-04, track ricochet with external damage, overmatch, HEAT gap REG-ARM-05, HE/HESH REG-ARM-13, splash and
stun, bustle-rack detonation REG-ARM-08, internal path length, no-op, same-tick shells, mid-flight pose changes,
determinism, 1,000-ray "always hits", 2,000-case NaN fuzz), DamageModel (31: thresholds, caps, fire REG-ARM-09, auto
extinguisher, repairs, consumables, effects, crew curves, ram goldens REG-ARM-10, falls REG-VEH-11, drowning,
150-sequence invariant property), Dispersion (13), CrewEffects (7), Fire (4), CombatConfig (4).

## 14. Known limitations

* The internal path follows the shell's incoming ray (normalization does not bend it; ≤ n' ≈ 5–14° over ≤ 2 m).
* `volumesNear` / `nearestArmor` use face-plane distances (exact on faces, generous near edges/corners); T_min counts
  faces whose plane faces the burst within R, including faces shared between volumes (they carry the continued plate's
  thickness, so the value stays meaningful).
* HE bursting on a screen splashes its own body along the ray only (not the thinnest plate in the sphere).
* `ShellStats` has no `damageRollMin`/`penetrationRollMin` (Ammo Tuck); rolls accept a spread but no floor yet.
* `RamParty.contactThicknessMm` and the contact side come from the caller's collision system.
