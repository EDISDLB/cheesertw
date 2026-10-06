# Vehicle stats, gun state and special mechanics

Status: v1 (Phase B). Owner: gameplay (package `gunstats`). Authority: `docs/research/00-DECISIONS.md` §2–§4, §7, §12,
§13; contracts `docs/design/content-schema.md` §5.5–§7 and `Types/{Content,Vehicle,Combat,VehicleSim}.luau`;
neighbours `docs/design/combat.md` (DamageModel, CrewEffects, Dispersion) and `docs/design/movement.md` §4.10
(VehicleSim mechanics, external mode). All numbers are real-world units; nothing here converts to studs.

| File | Role |
|---|---|
| `Shared/Vehicle/Modifiers.luau` | StatModifier aggregation, share scaling, condition rules, allocation-free accumulator |
| `Shared/Vehicle/StatsCalculator.luau` | `compute` (content → `VehicleStats`), loadout helpers, the 30 Hz runtime cache |
| `Shared/Vehicle/GunState.luau` | Server-authoritative reload / fire / ammo state machine (+ ChargedShot, ActiveCooling, AdaptiveMagazine) |
| `Shared/Vehicle/Mechanics/*.luau` | `Common`, `SiegeMode`, `Hydropneumatic`, `Turbo`, `RocketBoost`, `ChargedShot`, `ActiveCooling`, `ReserveTracks`, `Controller` |

---

## 1. Modifiers (content-schema §7)

**Rule.** Per stat: `result = (base + Σ add) × Π mul`. Adds are in the stat's unit (km/h, m, deg, crew-level
points, camo factor); muls are factors. Order never matters (tested property).

**Module qualifier.** Only `moduleHp`, `repairTime`, `damagedModulePenalty` take `module`. A qualified read combines the
every-module slot and the named module's slot: `(base + add_all + add_K) × mul_all × mul_K`.

**Share scaling** (OUR DESIGN CHOICE, 00-DECISIONS §12/§13 "work from 1 %, linear", "+15 % slot"): a modifier applied
at share `s` scales its *delta*: `add → v·s`, `mul → max(0, 1 + (v − 1)·s)`. Examples: rammer ×0.90 in the category
slot (s = 1.15) → ×0.885; Brothers in Arms +5 L at crew share 0.5 → +2.5 L; Concealment ×1.8 at 0.25 → ×1.2.

**Conditions** (`StatCondition`): `Stationary`/`Moving` (Spotting's moving rule), `StationaryArmed`
(`stationaryForS ≥ Config.Spotting.STATIONARY_ARM_S` = 3 s), `TurretTraversing`, timed windows `AfterShot`,
`AfterTakingDamage`, `AfterSpotting` (half-open `[0, durationS)`; never fired = false), `NearEnemy` (≤ `rangeM`,
inclusive), `Spotted`, `LowHp` (hp ≤ 25 % max, `Modifiers.LOW_HP_FRACTION`), `MechanicActive`.

**Validation.** Unknown stat/op/condition, non-finite value or a qualifier on a stat without modules: ignored and
counted (`acc.ignored`). ContentRegistry rejects these in shipped content.

API: `newAccumulator()`, `reset(acc)`, `push(acc, mod, scale?) -> boolean`, `pushList(acc, list?, scale?, "always"|"all"|
"conditional")`, `pushHolding(acc, list?, conditions, scale?)`, `apply(acc, stat, base, module?)`, `addOf`, `mulOf`,
`touches`, `resolve(base, stat, list?, scale?)`, `scaledValue(mod, scale?)`, `scaledCopy(mod, scale?)`, `holds(mod,
conditions)`, `newConditions()`, `partition(list?, stats)`, `isValid`, `isAlways`, `statIndex`, `isQualified`;
constants `STAT_KEYS` (mirrors `Content.StatKey`, spec-checked), `MODULE_KINDS`, `QUALIFIED_STATS`.

---

## 2. `StatsCalculator.compute`

```lua
StatsCalculator.compute(def, configuration, loadout?, registry, opts?) -> Result<VehicleStats>
StatsCalculator.fromLoadout(loadout, registry, opts?) -> Result<VehicleStats>     -- loadout's own config
StatsCalculator.defaultLoadout(def, registry, configuration?) -> Loadout          -- trained crew, standard ammo
StatsCalculator.resolveShell(shellDef, indirect, acc?) -> ShellStats
StatsCalculator.oneReload(reloadSpec) -> number                                   -- the swap reference
-- opts: { competitive: boolean?, mutable: boolean? }
```

`compute` is the one function the garage, the Hub and the battle server use, so displayed stats equal battle stats
(REG-CRW-01, REG-EQP-01). It returns `Err` instead of throwing (ARCHITECTURE §3.6): `checkConfiguration` errors
(`NOT_FOUND` / `INVALID_ARGS` incl. over the load limit), a loadout for another vehicle (`INVALID_ARGS`), an unknown
equipment / skill / consumable / Field Kit option / Apex node (`NOT_FOUND`). Unknown cosmetics are ignored (they never
block a battle). Results are deep-frozen unless `opts.mutable`. `configuration` may differ from
`loadout.configuration` (garage module preview).

### 2.1 Resolution order

1. **Collect modifiers** (only when a loadout is given), in this order: equipment (by slot), crew skills, consumables,
   Field Kit options, Apex nodes. "Always" modifiers go into one accumulator; every other condition is copied, already
   scaled, into `VehicleStats.conditionalModifiers`.
   * **Equipment.** `effectsByClass[class]` replaces `effects` when present. Category slot: exists from Tier VI
     (`tier.categorySlot`, or a `slots.categorySlot` override); category = `slots.categorySlot` or the role's. An item
     in **slot 1** whose `categories` contain it gets `categorySlotEffects` (if authored and the item is not
     class-scaled) or every delta × (1 + `CATEGORY_SLOT_BONUS` = 0.15). A second item of an `exclusiveGroup` is skipped.
   * **Skills.** Individual: share = average training of the members holding one of the skill's duties (members
     without the skill count 0; two loaders, one trained → ½). Group: share = Σ training ÷ crew size
     (00-DECISIONS §12 "scale by crew share"). Both × `crewPerkEfficiency` (0.75..1, default 1).
   * **Consumables.** `passiveEffects` while mounted; `effects` of `Passive` items (Rations +10 L, Quality Fuel +5 %
     power). Manual/Automatic `effects` are timed: the runtime applies them (§3).
   * **Field Kit / Apex.** Option / node effects at share 1.
2. **Crew level** per member: `L_i = clamp((L_snapshot + Σ crewLevel add) × Π mul, MIN_CREW_LEVEL, MAX_CREW_LEVEL)`;
   default snapshot level `Config.Combat.CREW_BASE_LEVEL` (100). `crewLevels[duty]` = average L of the members holding
   the duty (same averaging as `CrewEffects.dutyLevel`, spec-checked).
3. **Crew curves** (00-DECISIONS §4, `Config.Combat.RELOAD_CURVE_*`, `STAT_CURVE_*`): `r(L) = 0.875 / (0.00375 L + 0.5)`,
   `f(L) = 0.57 + 0.0043 L`. Loader → reload ×r; Commander → view range ×f; Gunner → aim ÷f, dispersion ÷f, turret
   traverse ×f; Driver → hull traverse ×f, repair ÷f (`CrewEffects.INJURY_EFFECTS`).
4. **Every stat** = `(crew-scaled base + Σ add) × Π mul` with the homes of `Types/Vehicle`:

| Stat (VehicleStats) | Base | StatKey |
|---|---|---|
| `hp` (whole) | `hull.hp + turret.hpBonus` | `hp` |
| `massKg` | `checkConfiguration` mass | — |
| `enginePowerHp`, `specificPowerHpT` | `engine.powerHp`; power ÷ (mass/1000) | `enginePower` |
| `topSpeedKmh` / `reverseSpeedKmh` | `mobility.forwardKmh` / `reverseKmh` or clamp(0.35 × fwd, 12, 25) (`Config.Movement.REVERSE_*`) | `topSpeed` / `reverseSpeed` |
| `hullTraverseDegS` | `tracks.traverseDegS × f(L_drv)` | `hullTraverse` |
| `terrainResistance`, `loadLimitKg` | tracks | `terrainResistance` (each class), `loadLimit` |
| `pivot`, `wheeled` | `mobility.pivot` else not wheeled; `Wheeled` spec (speed-mode speeds = resolved speeds × muls) | — |
| `turretTraverseDegS` | `turret.traverseDegS × f(L_gun)` | `turretTraverse` |
| `yawLimitsDeg` | turret; casemate default ±`Config.Movement.CASEMATE_DEFAULT_YAW_DEG` | — |
| `gun.reload` | every **reload** timer × r(L_ldr) (`reloadS`, `perShellReloadS[*]`, `reloadEachS`); intra-clip, salvo and charge times are not reloads | `reloadTime` |
| `gun.aimTimeS`, `gun.dispersionM100` | gun ÷ f(L_gun) | `aimTime`, `dispersion` |
| `gun.bloom` | gun overrides, else `Config.Combat.BLOOM_*` (movement and hull terms × `tracks.bloomMul`); afterShot = `class.afterShotBloom` | `bloom*` |
| `gun.depressionDeg/elevationDeg`, `arcSectors` | `gun.arcs`; vehicle `arcSectors` (copied) | `gunDepression/Elevation` |
| `gun.shellSwapS` | (`gun.shellSwapS` or one reload) × r(L_ldr) → reloadTime → shellSwapTime (00-DECISIONS §4 "swap = full reload", Intuition) | `shellSwapTime` |
| `gun.ammoCapacity` (whole) | gun | `ammoCapacity` |
| `gun.camoAfterShotMul` | gun or `VisibilityModel.defaultShotCamoMul(cal)` = clamp(.40 − .0025(cal − 20), .05, .40) | — |
| `gun.damageRollMinAdd/penetrationRollMinAdd` | 0 | `damageRollMin/penetrationRollMin` |
| `gun.shells[*]` | §2.2 | `damage`, `penetration`, `shellVelocity` |
| `modules[K].maxHp` (whole) | `DamageModel.moduleHpFor(K, tier.moduleHpRefAlpha)` | `moduleHp` (+K) |
| `modules[K].repairS` | `Config.Combat.REPAIR_S[K] ÷ f(L_drv)` | `repairTime` (+K) |
| `modules[K].damagedPenaltyMul` | 1 | `damagedModulePenalty` (+K) |
| `crew[*].maxHp` | `DamageModel.crewHpFor(refAlpha)` (0.8 × refAlpha) | — |
| `fireChance` | `engine.fireChance` or `Config.Combat.FIRE_CHANCE[fuel]` (clamped 0..1) | `fireChance` |
| `fireDurationS`, `spallFactor` | `FIRE_DURATION_S`, `SPALL_FACTOR_BASE` | `fireDuration`, `spallFactor` |
| `crewInjuryChanceMul`, `stunDurationMul`, `ram*Mul`, `fallDamageMul`, `consumableCooldownMul`, `crewXpMul` | 1 | same names |
| `repairTimeMul` | `1 ÷ f(L_drv)` | `repairTime` (unqualified) |
| `viewRangeM` | `turret.viewRangeM × class.viewRangeMul × f(L_cmd)` | `viewRange` |
| `signalRangeM` | `class.signalRangeM` | `signalRange` |
| `camo.stationary/moving` | `vehicle.camouflage`, else `class.camoCasemate` for casemates, else `class.camo` | `camoStationary/Moving` |
| `camo.afterShotMul` | `gun.camoAfterShotMul` | `camoAfterShot` |
| `camo.net` | 0 (the net item's `camoNet` adds give it; class `camo.net` is the authoring reference) | `camoNet` |
| `camo.paint` | `Config.Spotting.PAINT_CAMO_BONUS` once if the style (or paint/camouflage) has `camoBonus`; `PAINT_CAMO_BONUS_COMPETITIVE` with `opts.competitive` | — |
| `mechanics` | resolved copies, §2.3 | `mechanic*` |

Faction kits, class baselines and role trims are never applied (they are baked into the authored numbers).

### 2.2 Shells (00-DECISIONS §1, `Config.Combat`)

`damage`, `penetrationMm`, `velocityMps` get their modifiers. `moduleDamage` = authored × (resolved/authored damage) or
`MODULE_DAMAGE_FACTOR[kind]` × resolved damage (0.5 kinetic/HEAT, 0.75 HE/HESH). `penetrationAt500Mm` (AP/APCR only)
= authored × pen ratio or `FALLOFF_AT_END` (AP ×0.90, APCR ×0.75); other kinds = pen. Gravity
`SHELL_GRAVITY_MPS2`, range `MAX_RANGE_M`, normalization `NORMALIZATION_DEG[kind]`, ricochet `RICOCHET_ANGLE_DEG[kind]`
(HE/HESH always 90). Explosion radius (HE/HESH): authored, else `cal × SPLASH_RADIUS_M_PER_MM` (direct) or
`ARTILLERY_SPLASH_BASE_M + ARTILLERY_SPLASH_PER_MM × cal` (indirect); 0 otherwise. Tracer: authored, "Artillery" on
indirect guns, else by kind (HESH → HE).

### 2.3 Mechanic copies (content-schema §5.6, §7.6)

`mechanicChargeTime` → ChargedShot `chargeTimeS`; `mechanicFactor` → ChargedShot `dispersionMul`/`damageMul` (the
chosen effect), Turbo `powerMul`, AdaptiveMagazine `partialReloadFactor`; `mechanicDuration` → Turbo / RocketBoost /
ActiveCooling `durationS`, ReserveTracks `repairS`; `mechanicCooldown` → `cooldownS` of Turbo / RocketBoost /
ActiveCooling / ReserveTracks; `mechanicCharges` → RocketBoost / ReserveTracks `charges` (rounded). SiegeMode,
Hydropneumatic and Wheeled copies are unchanged. The definition is never mutated.

---

## 3. Runtime (30 Hz, dirty-flag cache)

```lua
local rt = StatsCalculator.newRuntime(stats)                    -- once per vehicle at spawn
StatsCalculator.conditions(rt)                                 -- caller-owned Conditions, update fields in place
StatsCalculator.setEffects(rt, DamageModel.effects(combat, eff), combat.modules)
StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Mechanic, Controller.modifiers(ctrl))
StatsCalculator.setActive(rt, StatsCalculator.SOURCE.GunMechanic, GunState.mechanicModifiers(gun))
StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Consumable1, activeEffectsOrNil)
local out, changed = StatsCalculator.update(rt)                -- recomputes only on a change
StatsCalculator.writeSimModifiers(rt, sim.modifiers)           -- instead of VehicleSim.applyEffects
StatsCalculator.writeTurretModifiers(rt, turret.modifiers)     -- instead of TurretSim.applyEffects
StatsCalculator.writeAimFactors(rt, aimFactors)                -- + caller's speeds
GunState.applyRuntime(gun, out, now)                           -- reloadMul + canFire
-- Spotting: viewRangeM = out.viewRangeM, viewRangeMul = out.viewRangeMul, camo = out.camo, conditionalModifiers = nil
```

`SOURCE` slots: Mechanic 1, GunMechanic 2, Consumable1–4 3–6, Event 7, Custom 8 (fixed array: no per-tick
allocation; passing the same list again is free).

**What the cache tracks.** Each `update` re-evaluates every conditional / active modifier's condition (O(n), no
allocation) and recomputes only when one flipped, an effect value or module state changed (`setEffects` compares
field by field) or an active list was replaced. `out.version` increments on every recompute.

**Outputs** (`RuntimeStats`): ratios against the VehicleStats value (`reloadMul`, `aimTimeMul`, `dispersionMul`,
`turretTraverseMul`, `enginePowerMul`, `topSpeedMul` + `topSpeedBonusKmh`, `reverseSpeedMul`, `hullTraverseMul`,
`viewRangeMul`, `fireChanceMul`, `repairTimeMul`, `damageMul`, `penetrationMul`) and the absolute values for the HUD /
bots / garage (`aimTimeS`, `dispersionM100`, `turretTraverseDegS`, `enginePowerHp`, `hullTraverseDegS`, `viewRangeM`,
`camo`, `bloom`), plus `canFire`, `canMove`, `gunDamaged`, `sixthSense`, `stunned`, `burning`, `mechanicActive`,
`depressionBonusDeg`/`elevationBonusDeg`.

Formulas (`e` = DamageModel effects, `ratio(stat, v) = (v + Σadd) × Πmul ÷ v` over the holding modifiers):
`reloadMul = e.reloadTimeMul × penalty(AmmoRack) × ratio(reloadTime, one reload)`;
`aimTimeMul = e.aimTimeMul × penalty(Gun) × ratio(aimTime)`; `dispersionMul = e.dispersionMul × ratio(dispersion)`;
`turretTraverseMul = e.turretTraverseMul × penalty(TurretRing) × ratio(turretTraverse)`;
`enginePowerMul = e.enginePowerMul × penalty(Engine) × ratio(enginePower)`; `topSpeedMul = e.topSpeedMul × Πmul`,
`topSpeedBonusKmh = Σadd`; `reverseSpeedMul = e.topSpeedMul × ratio(reverseSpeed)` (stun and lost wheel sides slow
reverse too); `viewRangeMul = e.viewRangeMul × penalty(Optics)`, `viewRangeM = apply(viewRange, stats.viewRangeM)`;
`fireChanceMul = e.fireChanceMul × penalty(FuelTank) × ratio(fireChance)`; bloom terms = `apply(bloom*)`,
`bloom.damagedMul = 1 + (base − 1) × damagedPenaltyMul(Gun)`.

**Damaged-module penalty** (`damagedModulePenalty`, Recon / Engineer): with `p = modules[K].damagedPenaltyMul` and
DamageModel's multiplier `m`, the effective multiplier is `1 + (m − 1)·p`, applied as the correction `(1 + (m − 1)p)/m`.
Engine / TurretRing / Optics: only in the `Damaged` state; AmmoRack / Gun / FuelTank: whenever DamageModel applies its
penalty (not Ok). Recon on optics (p = 0.5): VR ×0.80 → ×0.90.

**Ownership (never double-applied).** VehicleSim applies the mechanic's mobility and arc effects (siege speed cap,
travel reverse, siege `modifiers` for `enginePower/topSpeed/reverseSpeed/hullTraverse/gunDepression/gunElevation`,
Turbo power, RocketBoost bonus, Hydropneumatic arcs) and `MechanicActive` conditionals on those stats; the runtime
skips exactly those (`StatsCalculator.SIM_OWNED`) for the Mechanic source and `MechanicActive` conditions. GunState
applies ActiveCooling's `reloadTime` itself; `GunState.mechanicModifiers` already excludes it. Spotting receives the
resolved view range / camo and `conditionalModifiers = nil`. `writeAimFactors` leaves `stunned = false` because the
stun dispersion factor is already inside `e.dispersionMul` (see §8).

---

## 4. GunState (00-DECISIONS §4; ARCHITECTURE §6.1 step 3)

```lua
GunState.new(gunStats, ammoLoads?, { now?, mechanics?, startLoaded?, resetChargeOnMove?, reloadMul? }) -> GunState
GunState.canFire(g, now) -> (boolean, reason?)          GunState.fire(g, now) -> (ShotInfo?, reason?)
GunState.setTrigger(g, held, now) -> ShotInfo?          GunState.update(g, now) -> ShotInfo?   -- auto volley
GunState.selectShell(g, slot, now) / switchShell / selectShellById(g, id, now) -> (boolean, reason?)
GunState.reload(g, now)          GunState.mechanicKey(g, now)          GunState.activateCooling(g, now)
GunState.setReloadMul(g, mul, now)   setEnabled(g, ok, now)   setOverturned(g, flag, now)   setMoving(g, flag, now)
GunState.applyRuntime(g, { reloadMul, canFire }, now)        GunState.kill(g, now)
GunState.ammoOf(g, slot)  totalAmmo(g)  storedAmmo(g)  roundsLoaded(g)  currentReloadMul(g)
GunState.syncAmmoStored(g, combat) -> number             -- DamageModel.setAmmoStored(storedAmmo)
GunState.mechanicModifiers(g)  mechanicActive(g)  newSnapshot(g)  snapshot(g, now, out?)  mechanicSnapshot(g, now, out?)
```

**Time model.** Timers hold remaining *base* seconds; real time = base × `reloadMul` × ActiveCooling factor,
re-evaluated at every change, advancing event-to-event (exact completion instants; tick-rate independent). A
multiplier change mid-reload rescales only the rest (REG-RET-05).

| Kind | Rule |
|---|---|
| Single | One chambered round; firing starts `reloadS` |
| Magazine | `intraClipS` between shots; empty → full `reloadS`; a manual reload of a partial magazine costs the full `reloadS`; AdaptiveMagazine top-off `reloadS × (f + (1 − f) × missing ÷ size)`, cancelled by firing (reserved rounds return) |
| Autoreloader | One round at a time: refill of slot k = `perShellReloadS[k]` (first refill after empty is the longest); firing never resets a running refill; `intraClipS` between shots |
| DualGun | Two barrels reload independently (`reloadEachS`), `salvoDelayS` between single shots; a press < `DUAL_GUN_TAP_S` (0.25 s) fires one barrel on release; holding with both barrels loaded charges a volley that fires automatically `chargeTimeS` after the later of the press and the second barrel loading (2 rounds, × `volleyDispersionMul`); releasing a charging volley cancels it (ui-ux H-05) |

**Shell swap** (00-DECISIONS §4 "ammo swap when loaded = full reload"): selecting another shell while a round of the
old one is loaded unloads it to the rack and starts a full reload of the new shell with every timer × `swapFactor =
shellSwapS ÷ one reload` (Intuition shortens it). Switching while nothing is loaded only changes what the running
reload loads (progress kept). Out of the selected shell → next shell with rounds (hotkey order). Unknown slot
`UNKNOWN_SHELL`, empty shell `NO_AMMO`.

**ChargedShot** (roster §2.7, ui-ux H-05): charges only while loaded and held (holding through a reload starts the
charge at the load instant); release fires; bonus only at a full charge (inclusive); hull movement above the stop
speed resets the charge to 0 and it resumes when the hull stops (`CHARGED_SHOT_RESET_ON_MOVE = true`); an ammo swap,
a destroyed gun, overturning or death cancel it. **ActiveCooling**: may start mid-reload; the rest of the window runs
at ×0.85, split exactly at the window end.

**Blocking.** `DEAD` (kill), `GUN_DESTROYED` (`setEnabled(false)` / `canFire = false`), `OVERTURNED` (`setOverturned`,
00-DECISIONS §2 "gun off"): firing refused and charges dropped; reloads keep running. A timer completing exactly at
the death time completes (inclusive); nothing fires after `kill`.

**Ammo-rack sync.** `storedAmmo = total − roundsLoaded` (rack + rounds being loaded). Call `syncAmmoStored` after each
shot / swap / reload start so DamageModel only detonates with ≥ 1 stored shell.

**Snapshot** (`GunSnapshot`, caller-owned): phase (`Ready`, `Reloading`, `IntraClip`, `Charging`, `Empty`, `Disabled`,
`Dead`), `canFire`, `selectedSlot`, `loadedSlot`, `reloadProgress`, `reloadRemainingS`, `reloadDurationS`,
`nextShotS`, `intraClipRemainingS`, `roundsLoaded`, `magazineSize`, `toppingOff`, `refillSlotIndex`,
`chargeProgress`, `reloadMul`, `ammo[]`, `totalAmmo`, `barrelProgress[]`, `overturned`. Refusal reasons map to
`NOT_ALLOWED` at the remote boundary.

---

## 5. Special mechanics (`Vehicle/Mechanics`)

Every machine: `new(spec, now)`, `update(state, now, ctx?)`, `activate/deactivate(state, now, ctx?) -> (ok, reason)`,
`isActive`, `modifiers`, `nextChange`, `snapshot(state, now, out?)`; exact absolute phase times (`Common.EPS`
inclusive); `Context = { alive, mobile, grounded, speedKmh, stationaryForS }`.

| Machine | Phases and numbers (00-DECISIONS §4, roster §2.7) | Effects |
|---|---|---|
| SiegeMode | Off → Engaging 2.0 s → On → Disengaging 1.25 s → Off; key press acts from Off/On only; optional auto-engage after `autoEngageS` still (a manual disengage suppresses it until the hull moves) | cap `maxSpeedKmh` while not Off; travel reverse ratio while Off; `modifiers` while On (aim ×0.4, disp ×0.85, +8°/+6°, hull trav ×0.5) |
| Hydropneumatic | passive: Off (moving / airborne / dead) → Engaging (still) → On at stop time + 0.75 s exactly | +4° dep / +3° elev |
| Turbo | Off → On 6 s → Cooldown 40 s → Off; immobile or dead cancels (cooldown from then) and blocks | enginePower ×1.25 |
| RocketBoost | press spends a charge → On 2.5 s; each charge returns 30 s after **its** burn ended (two pips); Cooldown while none is available | topSpeed +20 km/h (+ VehicleSim thrust) |
| ChargedShot | Off → Engaging (charging) → On (full) on the fire trigger (GunState) | shot × 0.6 dispersion or × 1.10 damage |
| ActiveCooling | Off → On 5 s → Cooldown 45 s (GunState) | reload ×0.85 (GunState), aim ×0.85 (runtime) |
| ReserveTracks | a destroyed track starts a `repairS` job (the other side joins); charge spent at completion; cooldown; a job repaired by other means is cancelled free | caller restores the modules (`update` reports sides) |

**Controller and VehicleSim's external mode** (movement.md §4.10). `Controller.new(stats.mechanics, now, {
autoEngage? })` builds the VehicleSim-side machines; `owns` = it has a keyed (SiegeMode/Turbo/RocketBoost) or
Hydropneumatic machine and the vehicle is not Wheeled (VehicleSim's built-in Wheeled machine stays in charge).
`attach(ctrl, sim)` sets `sim.mechanic.external`. Tick order: `input(ctrl, cmd.mechanic, now)` (edge) →
`readSim(ctrl, sim)` (alive = not wrecked, mobile = not immobilized, grounded, |speed|, stillTime) → `update(ctrl, now)
-> (changed, leftReplaced, rightReplaced)` → `writeSim(ctrl, sim)` (phase, timer, charges, hydroActive) →
`VehicleSim.step`. `modifiers(ctrl)` feeds the runtime's Mechanic source; `isActive` is `MechanicActive`. The spec
proves the controller-driven siege timeline equals the built-in one tick for tick.

---

## 6. Edge cases (all tested)

Switch mid-reload (progress kept), swap with a round loaded (full reload × swapFactor, round returned), swap to an
empty shell (`NO_AMMO`), out of ammo for every kind, automatic fall-through to the next shell, death mid-reload
(frozen), reload completing exactly at death (counts), magazine/autoreloader completion at death, death while a volley
charges (no volley), gun destroyed / overturned mid-charge (cancelled), reload multiplier change mid-reload, hostile
multipliers clamped `[MIN_RELOAD_MUL, MAX_RELOAD_MUL]`, NaN / backwards times ignored, forged fire spam
(REG-SEC-01), random action sequences conserve ammo (seeded property test), allocation-free 30 Hz paths (GunState,
runtime, accumulator).

## 7. Mapping to 00-DECISIONS

§2 module HP / effects / crew injury (via DamageModel + CrewEffects) · §4 crew L and curves, reload modifiers, swap rule,
Magazine / Autoreloader / DualGun / ChargedShot / ActiveCooling / Turbo / RocketBoost / SiegeMode / Hydropneumatic
numbers and placement · §5 camo and VR composition inputs · §7.3/§7.4 kits/baselines **not** applied (lint only) ·
§12 crew (no qualification, perks linear from 1 %, group perks × crew share) · §13 equipment (+15 % category slot,
exclusive groups, consumables). OUR DESIGN CHOICES: delta scaling (§1), Individual-skill averaging over duty holders,
damaged-penalty formula `1 + (m − 1)p`, RocketBoost per-charge recharge, moduleDamage / pen-at-500 follow their
resolved parents, stun also slows reverse.

## 8. Config keys

Read: `Config.Combat` (`CREW_BASE_LEVEL`, `RELOAD_CURVE_*`, `STAT_CURVE_*`, `MODULE_HP_K`, `CREW_HP_K`, `REPAIR_S`,
`FIRE_CHANCE`, `FIRE_CHANCE_DEFAULT`, `FIRE_DURATION_S`, `SPALL_FACTOR_BASE`, `BLOOM_*`, `MODULE_DAMAGE_FACTOR`,
`FALLOFF_AT_END`, `KINETIC`, `EXPLOSIVE`, `SHELL_GRAVITY_MPS2`, `MAX_RANGE_M`, `SPLASH_RADIUS_M_PER_MM`,
`ARTILLERY_SPLASH_*`, `NORMALIZATION_DEG`, `RICOCHET_ANGLE_DEG`, `WHEELED_*`, `*_DAMAGED_*`), `Config.Movement`
(`REVERSE_DEFAULT_RATIO`, `REVERSE_MIN_KMH`, `REVERSE_MAX_KMH`, `CASEMATE_DEFAULT_YAW_DEG`), `Config.Spotting`
(`STATIONARY_ARM_S`, `SHOT_CAMO_*`, `PAINT_CAMO_BONUS`, `PAINT_CAMO_BONUS_COMPETITIVE`).

Module defaults, read through an optional `Config.VehicleStats` section when it exists (requested, §9):
`CATEGORY_SLOT_BONUS` 0.15, `MIN_CREW_LEVEL` 1, `MAX_CREW_LEVEL` 300 (StatsCalculator); `DUAL_GUN_TAP_S` 0.25,
`CHARGED_SHOT_RESET_ON_MOVE` true, `START_LOADED` true, `MIN_RELOAD_MUL` 0.05, `MAX_RELOAD_MUL` 20, `MIN_TIMER_S` 0.001
(GunState).

## 9. Known limitations, requests, in-engine checks

* `compute` returns `Result<VehicleStats>` (not a bare record) so bad loadouts never throw.
* Runtime modifiers apply on top of the battle-start values (Types/Vehicle contract), so a conditional *add* combines
  with "Always" *muls* slightly differently from a single `(base + Σadd)·Πmul` pass. No shipped content mixes them.
* Conditional modifiers on stats without a runtime consumer (`hp`, `moduleHp`, `ammoCapacity`, `shellVelocity`,
  `loadLimit`, `terrainResistance`, `crewXp`, `consumableCooldown`, roll minimums, `mechanic*`) are evaluated but not
  exposed; `damageMul` / `penetrationMul` are ratios of the standard shell.
* REG-CRW-01's "group perk applies iff every member has it" is superseded by 00-DECISIONS §12 (crew share).
* Requests: **Config** — add `Config/VehicleStats.luau` with the §8 keys (+ BOUNDS). **Combat** — Dispersion multiplies
  `STUN_DISPERSION_MUL` when `factors.stunned` while `DamageModel.effects.dispersionMul` already includes it (double
  count; `writeAimFactors` passes `stunned = false` meanwhile); `VehicleSim.applyEffects` does not slow reverse under
  stun (`writeSimModifiers` does). **Battle** — use `Mechanics/Controller` (external mode) so RocketBoost recharges per
  charge (VehicleSim's built-in copy uses one global cooldown); call `GunState.syncAmmoStored` after shots/swaps.
* In-engine verification: HUD reload ring vs `GunSnapshot` under latency (REG-RET-05 ± 1 tick), DualGun tap latency
  feel (0.25 s), charged-shot reset threshold on slopes (stop speed 0.5 km/h), 30-vehicle runtime cost per tick.

## 10. Tests

`tests/Unit/ReplicatedStorage/Shared/Vehicle/`: `Modifiers.spec` (key mirrors, aggregation table, scaling, validation,
conditions table, order-independence property, allocation), `StatsCalculator.spec` (hand-computed Kolmal / Ostmal /
Bulmal, crew duties and curves, skill/equipment/consumable/Field Kit/Apex tables, category slot, shells, validation,
determinism over random loadouts, runtime effects / penalties / conditions / sources / writers / allocation),
`GunState.spec` (timelines for every kind, swaps, triggers, mechanics, blocking, ammo sync, death edges, property and
allocation tests), `Mechanics/*.spec` (each machine + Controller integration with VehicleSim).
