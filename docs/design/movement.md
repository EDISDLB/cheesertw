# Movement — vehicle simulation design (VehicleSim, TurretSim, Collision)

Status: implemented (package `vehiclesim`). Code: `src/ReplicatedStorage/Shared/Vehicle/{VehicleSim,TurretSim,Collision}.luau`,
types `Shared/Types/VehicleSim.luau`, tunables `Shared/Config/Movement.luau`, specs
`tests/Unit/ReplicatedStorage/Shared/Vehicle/{VehicleSim,TurretSim,Collision}.spec.luau`.
Authority: `docs/research/00-DECISIONS.md` §2 (drowning, overturn, falls, ramming), §3 (arcs), §4 (mechanic placement),
§6 (movement) and `docs/ARCHITECTURE.md` §6.1–6.2. Values marked **O** are OUR DESIGN CHOICE (calibrate by playtest).

## 1. Purpose and scope

One pure, deterministic model of how a vehicle moves, shared unchanged by the server (authority, 30 Hz) and the owning
client (prediction + reconciliation). It covers:

* **VehicleSim** — hull kinematics: power-to-weight acceleration, terrain resistance and traction, slopes and the climb
  limit, speed caps, braking, hull traverse (pivot, wheels), module effects, ground fit of pitch/roll, side slip,
  falling and landing, static obstacles (sweep + slide), map bounds, fording and drowning, overturning, and the
  sim-placed mechanics (SiegeMode, Hydropneumatic, Wheeled speed mode, Turbo, RocketBoost).
* **TurretSim** — turret yaw and gun elevation toward the aim point: ballistic laying, traverse/elevation drives,
  yaw arcs (casemates), depression/elevation limits in the hull frame, arc sectors, the muzzle aim ray.
* **Collision** — vehicle-vs-vehicle box contacts for the server `CollisionSystem` (ramming, pushing, landing on a
  tank) and the momentum-conserving impulse.

Damage (fall, ram, drowning HP) is **not** computed here: the sim reports physical facts (impact speeds, closing
speeds, faces, submersion) and `Combat/DamageModel` turns them into HP (combat-owned `Config.Combat`).

## 2. Units and conventions

* Config: real units (m, m/s, m/s², km/h, deg, s, kg, hp). State: **studs** (3 per metre) and **radians**. Events,
  depths and timers: real units (m/s, m, s). Turret angles: **degrees** (Types/Vehicle contract).
* Heading `yaw`: 0 = −Z (north), + = clockwise seen from above (same as spawn `facingDeg` and turret bearings).
  `forward = (sin yaw, 0, −cos yaw)`, `right = (cos yaw, 0, sin yaw)`.
* Attitude is Tait-Bryan YXZ: `hullCFrame = CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, −yaw, roll)`.
  `pitch` + = nose up, `roll` + = right side up. In the yaw frame (right, up, back) the hull axes are
  `forward = (0, sin p, −cos p)` and `right = (cos r, sin r·cos p, sin r·sin p)`.
* `position` = the ArmorModel hull origin: centre of the footprint at track-bottom level. The collision box spans
  `[position.Y, position.Y + height]`.
* Vector3/CFrame are float32 in Roblox and Lune; every comparison in tests uses float32-appropriate tolerances.

## 3. Data flow

```
server tick (ARCHITECTURE §6.1)                                client (§6.2)
1 inputs   cmd = VehicleSim.sanitizeInput(raw, cmd, bounds, lastAim) -> (cmd, valid)  (strike on not valid)
           mods <- DamageModel module states (or VehicleSim.applyEffects(state, DamageModel.effects(...)))
2 vehicles events = VehicleSim.step(state, cmd, stats, world, dt)       same step on predicted state, input history
           Landed -> DamageModel.applyFall(id, speedMps, inverted)      on snapshot: VehicleSim.copyState(server, pred),
           Obstacle(destructible) -> destructible rules, world:destroyObject   replay unacknowledged inputs
           Drowned / OverturnDestroyed / FellOut -> destroy (no kill credit)
           CollisionSystem: Collision.bodyFromSim -> Collision.test(a, b) -> DamageModel.resolveRam(closingSpeedMps,
             frontArc = faceA == "Front") -> Collision.resolveVelocities -> VehicleSim.applyVelocityChange,
             Collision.separation -> VehicleSim.displace
3 turret   ωtur = TurretSim.step(turret, cmd.aimPoint, cmd.holdTurret, VehicleSim.hullCFrame(state), stats, pivots,
           dt, state)                                                   same on the client (predicted reticle)
4 aiming   Dispersion bloom inputs: |VehicleSim.speedKmh|, |yawRate| (deg/s), ωtur
5 shots    origin, dir = TurretSim.aimRay(turret, hullCFrame, stats, pivots)
7 spotting stationary checks: state.stillTime, state.mechanicActive
```

The battle owns one `VehicleSimState` + `TurretSimState` per vehicle, the `VehicleStats` (StatsCalculator) and the
`VehiclePivots` (Blueprint). Pass the pivots and the map bounds at construction:
`VehicleSim.newState(spawnCFrame, { bounds = VehicleSim.boundsFromSize(map.sizeM), pivots = model.pivots })`.

## 4. Hull model (VehicleSim)

### 4.1 Longitudinal dynamics (00-DECISIONS §6)

Along the hull forward axis (speed along the slope, m/s), with θ = hull pitch, R = terrain resistance, μ = traction:

```
a_drive  = min(P / (m · max(|v|, MIN_POWER_SPEED_MPS)), μ·g·cos θ)           toward the throttle direction
a_resist = g · ROLLING_RESISTANCE · R · cos θ                                 opposes motion
a_slope  = −g · sin θ
P = (enginePowerHp + Σadd) · Πmul · WATTS_PER_HP · modifiers.powerMul · (ENGINE_DAMAGED_POWER_MUL if Damaged)
```

* **Caps.** Top cap = `topSpeedKmh` (forward) / `reverseSpeedKmh` (or `clamp(REVERSE_DEFAULT_RATIO × top,
  REVERSE_MIN_KMH, REVERSE_MAX_KMH)` when missing), × runtime and mechanic multipliers, × `WATER_SPEED_MUL` in water,
  `min`ed with `modifiers.speedCapKmh`, a SiegeMode cap and `ABSOLUTE_MAX_SPEED_KMH`. Partial throttle scales the cap
  (`|throttle| × cap`). The cap is **hard**: gravity never pushes a vehicle past it ("capped by top speeds"); at the
  cap the engine keeps driving (it holds the speed against resistance, no oscillation).
* **Braking.** Throttle against the motion: service brakes `min(BRAKE_DECEL_MPS2 × |throttle|, μ g cos θ)`; the
  `brake` input or immobilisation: full service brakes; no throttle (or above the throttle cap): engine braking
  `min(ENGINE_BRAKE_DECEL_MPS2, μ g cos θ)`. Opposing forces stop the vehicle at 0, they never reverse it.
* **Static hold.** At rest the vehicle moves only if the net force exceeds rolling resistance; when nothing drives
  it (or the drive loses against gravity — a stall uphill), the locked tracks also hold up to μ g cos θ. A vehicle
  therefore parks on slopes up to ≈ atan(μ + 0.1 R) and slides down steeper ones.
* **Climb limit (REG-VEH-03).** If the ground pitch along the throttle direction exceeds `MAX_CLIMB_DEG` (35°) there is
  no uphill drive at all (`cap = 0`). The traction limit already stops climbs at tan θ = μ − 0.1 R (≈ 33° hard,
  30° medium, 22° soft); the explicit limit binds when traction is tuned higher.
* Integration is explicit per tick (30 Hz) with the acceleration from the start-of-step speed; zero crossings caused
  by opposing forces snap to 0.

Calibration examples (tests): 18 t / 600 hp LT on hard ground reaches 95 % of 60 km/h in the analytic time (±3 %);
a 30 t / 480 hp MT tops out on grass at `P/(m·g·0.1·1.1)` = 39.8 km/h (below its 50 km/h cap) — power-limited
vehicles do not reach the top speed on soft ground, as in the reference game.

### 4.2 Terrain and water

* `Config.Movement.MATERIAL_CLASS` maps materials to `hard`/`medium`/`soft` (00-DECISIONS §6 list + **O** mappings
  for props: Wood/Metal/… hard, Pebble/Salt medium, Ice soft; unknown = `DEFAULT_TERRAIN_CLASS`).
* R comes from the vehicle's tracks (`VehicleStats.terrainResistance`), μ from `TRACTION` (.75/.70/.60). Both are
  **averaged over the track contact samples** (half on a road, half in mud = in between). `state.terrainClass` is
  the majority class (HUD/audio), `state.material` the material under the hull centre.
* **Fording** (00-DECISIONS §6): from `WATER_EFFECT_MIN_DEPTH_M` of water over the hull bottom, R = soft ×
  `WATER_RESISTANCE_MUL` (1.5), μ = soft, caps × `WATER_SPEED_MUL` (0.5).

### 4.3 Hull traverse

`ω_max = hullTraverseDegS × modifiers.hullTraverseMul × Πmul + Σadd` (deg/s), then × `R_hard / R` (terrain, ≤ 1) ×
`lerp(1, HULL_TRAVERSE_TOP_SPEED_MUL, |v| / topCap)` (×0.6 at top speed) × speed-mode steering; `yawRate` moves toward
`steer × ω_max` with an angular acceleration of `base / HULL_TRAVERSE_RESPONSE_S`. `steer > 0` is clockwise in every
case (contract of `InputCommand.steer`).
* Tracked with neutral steer (`pivot = true`): turns in place about the centre.
* Tracked without it (`pivot = false`): below `NON_PIVOT_SPEED_KMH` it turns about the inner track centre line
  (`TRACK_CENTRELINE_FRACTION` × width from the centre), so the hull swings around one track.
* Wheeled (`stats.wheeled`): `ω ≤ |v| / turnRadiusM` — no turning on the spot.
* No rotation while braking, immobilised or airborne (angular velocity is kept in the air).

### 4.4 Side slip

Gravity across the slope `g·sin(roll)·cos(pitch)` against `μ·g·cos(roll)·cos(pitch)·LATERAL_FRICTION_MUL`: vehicles
slide sideways off slopes steeper than atan μ (≈ 37° on hard ground) and lateral velocity from impacts decays by the
same friction.

### 4.5 Ground fit (pitch, roll, height)

Samples: `VehiclePivots.trackContacts` (4 per side, hull space) or, without pivots, 4 per side on the track centre
lines over 85 % of the hull length; plus the **hull centre** as a support-only sample. Each step:

1. Every sample is rotated by the current attitude and probed with `world:groundAt(x, z, fromY)` from
   `STEP_HEIGHT_M + GROUND_PROBE_UP_M` above its predicted contact point. A probe that starts inside geometry (returns
   nil) is recast from `GROUND_RECAST_UP_M` higher (walls vs. holes). Still nothing while supported ⇒ a wall.
2. **Contacts** are the track samples not more than `GROUND_SNAP_M` below their predicted contact height (samples
   over a cliff edge or past a crest at speed do not tilt the hull). A least-squares plane `h = h0 + gx·u + gz·w`
   (u right, w back, hull-flat axes) through the contacts gives the target attitude
   `pitch = atan(−gz)`, `roll = atan(gx / √(1 + gz²))` (exact YXZ for a hull lying on that plane).
3. If the contacts leave an axis undetermined (one row or one side touching — rolling off a kerb, teetering on an
   edge) that axis follows **all** valid samples, clamped to `OVERHANG_MAX_TILT_DEG`: the hull tips toward the
   unsupported side instead of hanging in the air.
4. pitch/roll approach the target with `1 − e^(−GROUND_FIT_RATE·dt)` (grounded only).
5. **Rest height** = `max over valid samples (H_i − ly_i)` with the new attitude: no sample is ever above its contact
   point and the centre sample keeps the origin above crests narrower than the sample spacing (REG-VEH-02).
6. **Contact** is judged with the attitude the motion was predicted with: if the predicted height is more than
   `GROUND_SNAP_M` above that support, the vehicle is airborne (it keeps its surface vertical velocity, e.g. a jump
   off a crest); otherwise it snaps to the rest height (the attitude change pivots it onto its supports).
7. **Step / wall check**: a rise of the support above the predicted height by more than `STEP_HEIGHT_M` in one tick
   (terrain seams, banks, rubble too high) blocks the move: position and heading revert, speed 0, `Obstacle` event
   with `objectId = nil`.

### 4.6 Static obstacles and bounds

* Sweep box: the hull footprint from `STEP_HEIGHT_M` up to the roof, oriented with the hull (`world:sweepBox`).
  Boxes lower than the step are driven over (the ground fit climbs them), taller ones block.
* Hit at distance d > 0: advance to `d − OBSTACLE_SKIN_M`, remove the velocity component into the surface normal,
  then **slide** the remaining displacement along the surface (one more sweep). Glancing hits keep most speed; head-on
  hits stop. `Obstacle` events for every destructible contact and for others ≥ `OBSTACLE_EVENT_MIN_MPS`.
* Destructibles keep `DESTRUCTIBLE_SPEED_KEEP` of the closing velocity and do not slide; the server applies the
  destructible rules (00-DECISIONS §10) and calls `world:destroyObject`, after which the vehicle passes (REG-VEH-08).
* Rotation into an obstacle: if the new heading overlaps and the old one did not, the rotation is cancelled.
* Already overlapping (spawned inside, pushed in by `CollisionSystem`): motion away from the obstacle is allowed and
  the hull is pushed out along the normal at `DEPENETRATION_SPEED_MPS`, even without input (`displace`/`teleport`
  arm the check) — no permanent stuck state (REG-VEH-01).
* Map edge: the hull centre is clamped to `state.bounds` and the outward velocity removed (REG-VEH-02).

### 4.7 Falling and landing

Airborne vehicles integrate exact constant-gravity ballistics (`GRAVITY_MPS2`, terminal `MAX_FALL_SPEED_MPS`), keep
their horizontal velocity and attitude, and land when the predicted height reaches the rest height. The impact speed
is `√(v_y² + 2·g·drop)` (exact between ticks) and is reported as `Landed{speedMps, inverted}` from
`LANDED_EVENT_MIN_MPS` — the fall-damage input of `DamageModel.applyFall` (threshold 7 m/s and formula are combat's,
REG-VEH-11). `inverted` = overturned or upside down at touchdown. With no ground at all, falling below
`KILL_PLANE_Y_M` loses the vehicle (`FellOut`).

### 4.8 Drowning (00-DECISIONS §2; REG-VEH-10)

`waterDepthAt(position)` (hull bottom) ≥ drown depth (inclusive) ⇒ `submerged`; the timer runs (`Drowning{t =
DROWN_TIME_S}` once at the start, `DrowningEnded` + reset on exit) and after `DROWN_TIME_S` the vehicle is wrecked
(`Drowned`, no kill credit). Drown depth = turret roof: `options.drownDepthM`, else `pivots.turretRing.Y +
pivots.viewPoint.Y`, else hull height + `DEFAULT_TURRET_HEIGHT_M`.

### 4.9 Overturn (00-DECISIONS §2; REG-VEH-05)

Tilt = `acos(cos pitch · cos roll)` (combined). Beyond `OVERTURN_DEG` for `OVERTURN_TIME_S` ⇒ `overturned`
(immobile; TurretSim freezes; GunState should block firing) and `Overturned{t}`. Rule `OVERTURN_RULE = "SelfRight"`
(default, 00-DECISIONS): back on its tracks after `SELF_RIGHT_S`, attitude snapped to the ground fit, `Righted`; a
vehicle still on a > 70° face tips again after another `OVERTURN_TIME_S`. Rule `"Destroy"` (special modes): wrecked
after `OVERTURN_DESTROY_S` (`OverturnDestroyed`). Allies push an overturned vehicle through `CollisionSystem`
(`displace`). With the slip and climb rules a vehicle only reaches 70° on near-vertical faces.

### 4.10 Mechanics run by VehicleSim (00-DECISIONS §4)

`InputCommand.mechanic` is edge-triggered. Data from `VehicleStats.mechanics` (resolved copies):

| Mechanic | Phases | Effect while active |
|---|---|---|
| SiegeMode | Off → Engaging (`engageS`) → On → Disengaging (`disengageS`) → Off | speed cap `maxSpeedKmh` in every non-Off phase; On: its `modifiers` (mobility stats here, gun bonuses exported); travel reverse = forward × `travelReverseRatio` |
| Wheeled | Off → Engaging (`toggleS`) → On → Disengaging → Off | top/reverse = `speedModeTopSpeedKmh`/`speedModeReverseKmh`, steering × `speedModeSteeringMul` |
| Turbo | Off → On (`durationS`) → Cooldown (`cooldownS`) → Off | power × `powerMul` |
| RocketBoost | same, one `charges` per activation | top speed + `speedBonusKmh`, thrust + `ROCKET_BOOST_ACCEL_MPS2` |
| Hydropneumatic | passive | after `settleS` still: gun depression/elevation bonuses |

**External owner.** `Vehicle/Mechanics/*` (another package) implements richer, time-based machines (auto-engage,
HUD snapshots, non-mobility modifiers). To avoid two machines drifting apart, set `state.mechanic.external = true`
and write `state.mechanic.phase` (and `state.mechanic.hydroActive`) from that machine every tick: VehicleSim then
ignores the mechanic key and its own timers and only applies the mobility effects of the given phase. Without an
owner, VehicleSim's built-in machine (same phases and durations) runs.

`state.mechanicActive` is the `StatCondition "MechanicActive"`; `stats.conditionalModifiers` with that condition are
applied for mobility stats (enginePower, topSpeed, reverseSpeed, hullTraverse). Gun bonuses
(`gunDepressionBonusDeg`/`gunElevationBonusDeg`) are read by TurretSim. Every phase change emits `MechanicChanged`.
ReserveTracks belongs to the module/repair system (not here).

### 4.11 Runtime modifiers and DamageModel

`state.modifiers` is written by the owning systems, never by the sim: `engine`, `trackLeft`, `trackRight`
(ModuleState), `lostWheelPairs`, `powerMul`, `topSpeedMul`, `topSpeedBonusKmh`, `reverseSpeedMul`, `speedCapKmh`,
`hullTraverseMul`, `immobilized`. Engine Damaged ⇒ power × 0.5; engine Destroyed or (tracked) a track Destroyed ⇒
immobile (`immobileReason` "Engine"/"Tracks"); wheels lose `lostPairSpeedMul` per destroyed pair and stop when all are
lost. **Alternatively** `VehicleSim.applyEffects(state, DamageModel.effects(...))` maps the combat multipliers
(`enginePowerMul`, `topSpeedMul`, `hullTraverseMul`, `canMove`) and resets the module states so nothing is applied
twice — use one path, not both. `TurretSim.applyEffects` does the same for `turretTraverseMul`.

### 4.12 Resting

A grounded vehicle with no motion, no input, a converged attitude and no pending overlap check skips its probes and
sweeps, re-probing every `REST_REPROBE_S` (destroyed ground is noticed within that time). Timers still run.

### 4.13 Robustness

* Inputs are re-sanitised every step (`throttle`/`steer` clamped, NaN → 0); `dt ≤ 0`/NaN is a no-op, `dt >
  MAX_DT_S` is clamped. Stats are guarded (non-finite or non-positive mass/power/speeds fall back to safe values).
* NaN guard: a non-finite result restores the pre-step pose, zeroes the velocities and increments
  `state.nanResets` (Invariants should assert 0).
* Determinism: only arithmetic on the state, the inputs and world answers; no RNG, no clocks, no table iteration
  order. Identical inputs give bit-identical states (tested every tick), `copyState` replays identically.

## 5. TurretSim

* **Desired direction**: from the trunnion (at the current bearing) to the aim point; with a selected shell
  (`TurretSim.setShell(turret, velocityMps, gravityMps2)`) the ballistic solution (low arc; high arc when
  `GunStats.indirect` or `modifiers.highArc`), solved from the trunnion and re-solved from the muzzle point on the
  barrel axis (drop is quadratic in range: 0.26 m at 300 m otherwise). Out of range ⇒ 45° and `reachable = false`.
* **Frames**: bearing in the turret-ring frame (casemates: the trunnion frame), elevation in the trunnion frame at
  that bearing ⇒ all limits are **hull-relative**: a nose-up hull (hull-down on a reverse slope) loses world
  depression; facing the rear it gains it.
* **Traverse**: `turretTraverseDegS × traverseMul`, Damaged ring × `TURRET_RING_DAMAGED_MUL`, Destroyed ring 0;
  shortest way for 360° turrets; yaw-limited turrets and casemate guns (`yawLimitsDeg`, default
  `CASEMATE_DEFAULT_YAW_DEG` ±11°) move linearly inside the arc and stop at the angularly nearer limit.
* **Elevation**: `GUN_ELEVATION_SPEED_DEGS × elevationSpeedMul` (× `GUN_DAMAGED_ELEVATION_MUL` when damaged) toward
  the desired pitch clamped to `limitsAt(stats, bearing, bonuses)`: the gun's arcs, overridden by every arc sector
  containing the bearing (most restrictive wins; sectors may wrap through 180°), plus mechanic bonuses. The clamp is
  applied every step, so rotating over the rear deck lifts the gun immediately.
* **Hold / frozen**: `hold` (free look) keeps the hull-relative angles; `modifiers.enabled = false` or a vehicle that
  is overturned/wrecked freezes the turret (limits still hold).
* **Outputs**: `bearingSpeedDegS` (returned; Dispersion ω_tur), `pitchSpeedDegS`, `desiredBearingDeg/PitchDeg`,
  `aimErrorDeg`, `outOfArc`, `outOfElevation`, `reachable`; `TurretSim.onTarget`.
* **Aim ray**: `aimRay = muzzle.Position, muzzle.LookVector` with
  `hull * turretRing * Ry(−yaw) * gunTrunnion * Rx(pitch) * muzzle` (casemate: `hull * turretRing * gunTrunnion *
  Ry(−gunYaw) * Rx(pitch) * muzzle`), exactly the Types/Vehicle formulas (Combat uses the same pose names).
* **Casemate hull assist**: `TurretSim.autoHullSteer(turret, stats)` ∈ [−1, 1] — full steer when the aim is
  `AUTO_HULL_TURN_FULL_DEG` outside the arc; the client/bot adds it when the player is not steering.

## 6. Collision

* `Collision.test(a, b, out?)`: separating-axis test on the 4 XZ box axes + the vertical intervals. Result: normal
  (unit, A → B), depth (minimum translation = normal × depth), `closingSpeedMps` = (vA − vB)·n in m/s, contact point
  = vertex average of the footprints' intersection polygon (inside both, mid overlap height), `faceA`/`faceB`
  ("Front" = rammer front arc for `DamageModel.resolveRam`). Stacked boxes (one bottom above the other's mid-height
  and the vertical overlap shallower) give a vertical normal (landing on a tank = ram at v_y); side-by-side boxes
  always separate horizontally.
* `Collision.resolveVelocities(mA, mB, vA, vB, n, e?)`: impulse `j = (1 + e)·v_n / (1/mA + 1/mB)` only when
  approaching; e ∈ [0, 1] (`COLLISION_RESTITUTION` 0.1) ⇒ momentum conserved, kinetic energy never increases,
  horizontal normals never create vertical velocity (REG-VEH-04, 10,000 random pairs). Infinite/≤ 0 mass =
  immovable.
* `Collision.separation(mA, mB, contact, skin?)`: the separation split by inverse mass, applied with
  `VehicleSim.displace`; `bodyFromSim` builds the box from the sim's own hull box (wreck box = live box, REG-VEH-06).

## 7. API (exact signatures)

```lua
-- VehicleSim
VehicleSim.newState(spawnCFrame: CFrame, options: VehicleSimOptions?): VehicleSimState
VehicleSim.newModifiers(): VehicleSimModifiers
VehicleSim.boundsFromSize(sizeM: number): MapBounds
VehicleSim.settle(state, stats: VehicleStats, world: World)
VehicleSim.step(state, input: InputCommand, stats: VehicleStats, world: World, dt: number): { SimEvent }
VehicleSim.sanitizeInput(raw: unknown, out: InputCommand?, bounds: MapBounds?, fallbackAim: Vector3?): (InputCommand, boolean)
VehicleSim.neutralInput(out: InputCommand?): InputCommand
VehicleSim.terrainClassOf(material: string?): TerrainClass
VehicleSim.hullCFrame(state): CFrame
VehicleSim.velocity(state): Vector3                 -- world studs/s
VehicleSim.speedKmh(state): number
VehicleSim.hullSize(state, stats): Vector3          -- studs
VehicleSim.drownDepthM(state, stats): number
VehicleSim.applyVelocityChange(state, dv: Vector3)
VehicleSim.displace(state, offset: Vector3)
VehicleSim.teleport(state, position: Vector3, yaw: number?)
VehicleSim.applyEffects(state, effects: MobilityEffects)
VehicleSim.copyState(src, dst: VehicleSimState?): VehicleSimState
-- TurretSim
TurretSim.newState(): TurretSimState
TurretSim.newModifiers(): TurretSimModifiers
TurretSim.setShell(turret, velocityMps: number, gravityMps2: number)
TurretSim.applyEffects(turret, effects: TurretEffects)
TurretSim.step(turret, aimPoint: Vector3, hold: boolean, hullCFrame: CFrame, stats, pivots: VehiclePivots,
	dt: number, vehicle: VehicleSimState?): number          -- bearing speed deg/s
TurretSim.yawRange(stats): (boolean, number, number)
TurretSim.limitsAt(stats, bearingDeg: number, depressionBonusDeg: number?, elevationBonusDeg: number?): (number, number)
TurretSim.ballisticDirection(origin: Vector3, target: Vector3, v: number, g: number, highArc: boolean?): (Vector3, boolean)
TurretSim.turretCFrame / gunCFrame / muzzleCFrame(turret, hullCFrame, stats, pivots): CFrame
TurretSim.aimRay(turret, hullCFrame, stats, pivots): (Vector3, Vector3)
TurretSim.onTarget(turret): boolean
TurretSim.autoHullSteer(turret, stats): number
TurretSim.copyState(src, dst: TurretSimState?): TurretSimState
-- Collision
Collision.newBody(): CollisionBody
Collision.newContact(): CollisionContact
Collision.bodyFromSim(state, stats, out: CollisionBody?): CollisionBody
Collision.test(a: CollisionBody, b: CollisionBody, out: CollisionContact?): (boolean, CollisionContact)
Collision.faceOf(yaw: number, direction: Vector3): BoxFace
Collision.resolveVelocities(massA, massB, velocityA, velocityB, normal, restitution: number?): (Vector3, Vector3)
Collision.separation(massA, massB, contact, skin: number?): (Vector3, Vector3)
Collision.kineticEnergy(massKg: number, velocity: Vector3): number
```

Events (`SimEvent`, pooled — read before the next step): `Landed{speedMps, inverted}`, `Obstacle{normal, speedMps,
objectId, destructible, position}`, `Drowning{t}`, `DrowningEnded`, `Drowned`, `Overturned{t}`, `Righted`,
`OverturnDestroyed`, `FellOut`, `MechanicChanged{t}`.

## 8. Config keys (Config/Movement.luau, live-overridable numbers in BOUNDS)

| Key | Default | Source |
|---|---|---|
| `MATERIAL_CLASS`, `DEFAULT_TERRAIN_CLASS` | §6 list + props | W/O |
| `TRACTION.{hard,medium,soft}` | .75 / .70 / .60 | §6 |
| `ROLLING_RESISTANCE`, `MIN_POWER_SPEED_MPS`, `WATTS_PER_HP`, `GRAVITY_MPS2` | .10, 1, 745.7, 9.81 | §6 |
| `MAX_CLIMB_DEG` | 35 | §6 |
| `REVERSE_DEFAULT_RATIO`, `REVERSE_MIN_KMH`, `REVERSE_MAX_KMH` | .35, 12, 25 | §6 |
| `BRAKE_DECEL_MPS2`, `ENGINE_BRAKE_DECEL_MPS2` | 8, 3.5 | O |
| `ENGINE_DAMAGED_POWER_MUL` | .5 | §2 |
| `ABSOLUTE_MAX_SPEED_KMH`, `MAX_DT_S` | 160, .1 | O (guards) |
| `HULL_TRAVERSE_TOP_SPEED_MUL`, `HULL_TRAVERSE_RESPONSE_S` | .6, .15 | §6 / O |
| `TRACK_CENTRELINE_FRACTION`, `NON_PIVOT_SPEED_KMH` | .4, 2 | O |
| `GROUND_FIT_RATE`, `GROUND_SNAP_M`, `STEP_HEIGHT_M`, `OVERHANG_MAX_TILT_DEG` | 10, .3, .6, 45 | O |
| `GROUND_PROBE_UP_M`, `GROUND_RECAST_UP_M`, `SETTLE_PROBE_UP_M`, `REST_REPROBE_S` | 1, 60, 100, .5 | O |
| `STILL_SPEED_KMH`, `STILL_YAW_DEGS`, `LATERAL_FRICTION_MUL` | .5, 2, 1 | O (.5 km/h = §5) |
| `MAX_FALL_SPEED_MPS`, `LANDED_EVENT_MIN_MPS`, `KILL_PLANE_Y_M` | 60, 1, −150 | O |
| `OBSTACLE_SKIN_M`, `OBSTACLE_EVENT_MIN_MPS`, `DESTRUCTIBLE_SPEED_KEEP`, `DEPENETRATION_SPEED_MPS` | .01, 1, .85, 2 | O |
| `WATER_EFFECT_MIN_DEPTH_M`, `WATER_RESISTANCE_MUL`, `WATER_SPEED_MUL` | .2, 1.5, .5 | §6 |
| `DROWN_TIME_S`, `DEFAULT_TURRET_HEIGHT_M` | 10, .9 | §2 / O |
| `OVERTURN_DEG`, `OVERTURN_TIME_S`, `OVERTURN_RULE`, `SELF_RIGHT_S`, `OVERTURN_DESTROY_S` | 70, 3, SelfRight, 10, 10 | §2 |
| `DEFAULT_MAP_SIZE_M`, `AIM_POINT_MARGIN_M`, `MAX_AIM_HEIGHT_M` | 1000, 1000, 2000 | §10 / O |
| `ROCKET_BOOST_ACCEL_MPS2` | 3 | O |
| `GUN_ELEVATION_SPEED_DEGS`, `TURRET_RING_DAMAGED_MUL`, `GUN_DAMAGED_ELEVATION_MUL` | 20, .5, 1 | O / §2 |
| `ON_TARGET_DEG`, `AUTO_HULL_TURN_FULL_DEG`, `CASEMATE_DEFAULT_YAW_DEG` | .1, 5, 11 | O / §3 |
| `COLLISION_RESTITUTION` | .1 | O |

## 9. Edge cases covered

Spawns above/below the ground (settle), NaN spawn, slopes of 0–60°, side slopes, crests narrower than the sample
spacing, kerbs and platforms, terrain walls taller than a step or than the recast, cliffs (tip over the edge, fall,
land), drops under the snap distance, no ground at all (kill plane), head-on and glancing walls, rotation against a
wall, starting/pushed inside an obstacle, destructibles before/after destruction, map edges, fording, drowning at
depth −0.01/±0/+0.01 m, leaving deep water, overturn on a 75° face (self-right and re-tip, Destroy rule), wrecked
states (no-op steps), dt 0/negative/NaN/huge, garbage inputs and stats, ±180° turret wrap, rear-deck sectors,
casemate arcs, reverse slopes, unreachable ballistic aims, stacked and deeply overlapping vehicles.

## 10. Mapping to 00-DECISIONS

§6 formula, R table, material lists, μ, MAX_CLIMB_DEG 35, hull traverse × R_hard/R down to ×.6, pivot / wheeled turn
radius, default reverse clamp, heightfield ground with 4 samples per track, sweepBox obstacles and OBB vehicle
contacts with non-increasing energy — implemented as written. §2 drowning (10 s, warning, reset, no kill credit),
overturn (70°, 3 s, immobile, gun off, self-right 10 s, allies push) and falls/ramming inputs (v_y, front arc,
closing speed) — implemented; HP is DamageModel's. §3 arcs (−8/+20 default from content, casemate ±11°). §4 mechanic
placement — VehicleSim runs SiegeMode, Hydropneumatic, Wheeled, Turbo, RocketBoost. **O** refinements: braking
values, response times, ground-fit smoothing, step height, overhang tipping, side slip, destructible speed keep,
gun elevation speed, restitution (all in Config.Movement with bounds).

## 11. Known limitations

* Kinematic, not rigid-body: no suspension, no pitching under acceleration, no tumbling; crest jumps keep a fixed
  attitude in the air; overturn only from terrain (> 70° faces), not from impacts.
* Turret yaw parallax: the bearing is taken from the trunnion's current position (exact once on target).
* Vehicle–vehicle contacts are resolved by the server CollisionSystem after the sim step (one tick of overlap is
  possible); the sim's sweep ignores vehicles.
* Destructible obstacles block until the server destroys them (one-tick stop on light objects).
* Geometry (contacts, box, drown depth, mechanic indices) is resolved from the first `VehicleStats` a state sees.
* Per-step world cost: 9 ground probes (+ recasts at walls), ≤ 2 sweeps, 1 water query; resting vehicles ~2 probes/s.

## 12. In-engine verification needed

1. `RobloxWorld.sweepBox` must exclude Terrain (terrain is handled by `groundAt`); otherwise slopes block.
2. `RobloxWorld.groundAt` (heightfield lookup + structure raycasts, ARCHITECTURE §6.4) may either return the surface
   above a probe that starts inside geometry or nil (HeightmapWorld semantics): both are handled (rise > step, or a
   recast / void sample ⇒ wall). It must honour "Ground" mode (no destructibles) for structures.
3. Cost of 9 `groundAt` + 1–2 `Blockcast` per vehicle per tick at 30 vehicles (budget ≤ 600 queries/tick).
4. Prediction error with real RTT/jitter (REG-VEH-07) using `copyState` + replay.
5. Feel: acceleration, braking, traverse response and slide behaviour need a playtest pass (all values are config).
