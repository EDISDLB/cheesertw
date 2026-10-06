--!strict
--[[
	Types/VehicleSim — runtime state of the shared vehicle simulation: hull kinematics (VehicleSim), turret/gun
	angles (TurretSim), vehicle–vehicle contacts (Collision) and the events the hull simulation emits.

	Purpose:          One contract between Shared/Vehicle/{VehicleSim, TurretSim, Collision} (producers) and their
	                  consumers: BattleInstance + CollisionSystem + DamageModel (server authority), the client
	                  VehicleController (prediction/reconciliation), Dispersion (speeds), Spotting (stationary
	                  checks), the snapshot codec and the HUD (timers, immobilisation).
	Dependencies:     Types/Vehicle (ModuleState, VehiclePivots).
	State:            None (type-only).
	Validation:       Producers keep every number finite (VehicleSim/TurretSim NaN guards) and angles wrapped.
	Error handling:   N/A.
	Performance notes: Erased at runtime. States are created once per vehicle and mutated in place every tick; event
	                  records are pooled inside the state (no per-tick allocation).

	Units and conventions (see docs/design/movement.md):
	  * Kinematic state is in STUDS (Units.STUDS_PER_METER = 3) and RADIANS; event payloads, depths and timers are in
	    real units (m/s, m, s) because their consumers (fall/ram damage, HUD) work in real units.
	  * Heading `yaw`: 0 = -Z (north), + = clockwise seen from above (same as map spawn facing and turret bearings).
	    forward = (sin yaw, 0, -cos yaw), right = (cos yaw, 0, sin yaw).
	  * Attitude is Tait-Bryan YXZ: hullCFrame = CFrame.new(position) * CFrame.fromEulerAnglesYXZ(pitch, -yaw, roll).
	    `pitch` + = nose up, `roll` + = right side up (left side down).
	  * `position` is the hull origin of the ArmorModel: centre of the footprint at track-bottom level.
	  * Turret angles are in DEGREES, hull-relative, + = clockwise (bearing) / + = up (elevation), as in Types/Vehicle.
]]

local Vehicle = require("./Vehicle")

type ModuleState = Vehicle.ModuleState
type VehiclePivots = Vehicle.VehiclePivots

--------------------------------------------------------------------------------
-- Hull simulation (VehicleSim)
--------------------------------------------------------------------------------

--- Terrain resistance class of a ground material (Config.Movement.MATERIAL_CLASS, 00-DECISIONS §6).
export type TerrainClass = "hard" | "medium" | "soft"

--- Axis-aligned playable square in world STUDS (the red line). Vehicles never leave it.
export type MapBounds = { minX: number, maxX: number, minZ: number, maxZ: number }

--- Why a vehicle cannot drive (nil = mobile). Precedence: Wrecked > Drowned/FellOut > Overturned > Engine > Tracks >
--- External.
export type ImmobileReason = "Tracks" | "Engine" | "Overturned" | "Drowned" | "FellOut" | "Wrecked" | "External"

--- Events emitted by VehicleSim.step (pooled records: read them before the next step of the same vehicle).
---   Landed           speedMps = vertical impact speed (m/s, > 0), inverted = landed upside down / on its side.
---                    Emitted when speedMps >= Config.Movement.LANDED_EVENT_MIN_MPS. Fall damage is the
---                    server's (00-DECISIONS §2 "Falls": v_y > 7 m/s).
---   Obstacle         normal = horizontal unit normal of the blocking surface (points toward the vehicle),
---                    speedMps = closing speed into it, objectId/destructible from the WorldHit (nil objectId =
---                    terrain step or map edge). Emitted for every destructible contact and for others at
---                    >= Config.Movement.OBSTACLE_EVENT_MIN_MPS.
---   Drowning         t = seconds left before Drowned (emitted once when the water reaches the drown depth).
---   DrowningEnded    the vehicle left the deep water before drowning (timer reset).
---   Drowned          the drowning timer expired: the vehicle is destroyed (no kill credit, 00-DECISIONS §2).
---   Overturned       t = seconds until the configured rule resolves (self-righting or destruction).
---   Righted          self-righted after Config.Movement.SELF_RIGHT_S (no HP loss).
---   OverturnDestroyed rule "Destroy" only: overturned for Config.Movement.OVERTURN_DESTROY_S.
---   FellOut          no ground below and under the kill plane: the vehicle is lost (treat like Drowned).
---   MechanicChanged  the vehicle mechanic changed phase (see VehicleSimState.mechanic).
export type SimEventKind =
	"Landed"
	| "Obstacle"
	| "Drowning"
	| "DrowningEnded"
	| "Drowned"
	| "Overturned"
	| "Righted"
	| "OverturnDestroyed"
	| "FellOut"
	| "MechanicChanged"

--- One uniform, pooled record for every event kind; fields not used by a kind are left at neutral values
--- (0, false, nil, Vector3.zero).
export type SimEvent = {
	kind: SimEventKind,
	t: number,
	speedMps: number,
	normal: Vector3,
	position: Vector3,
	objectId: string?,
	destructible: boolean,
	inverted: boolean,
}

--- Runtime effects written by the systems that own them (module damage, crew, consumables, mechanics from outside
--- the sim, scripted phases). VehicleSim reads them every step and never writes them. Defaults: newModifiers().
export type VehicleSimModifiers = {
	engine: ModuleState, -- Damaged: power × Config.Movement.ENGINE_DAMAGED_POWER_MUL; Destroyed: immobile
	trackLeft: ModuleState, -- Destroyed: immobile (tracked vehicles)
	trackRight: ModuleState,
	lostWheelPairs: number, -- wheeled vehicles: top speed × lostPairSpeedMul ^ n
	powerMul: number, -- consumables (Quality Fuel), conditional equipment, stun …
	topSpeedMul: number,
	topSpeedBonusKmh: number,
	reverseSpeedMul: number,
	speedCapKmh: number, -- hard cap in both directions (math.huge = none)
	hullTraverseMul: number, -- driver injury f(L) ratio, conditional skills …
	immobilized: boolean, -- external hard stop (pre-battle countdown, scripted events)
}

--- Sim-placed vehicle mechanic (00-DECISIONS §4 placement): SiegeMode, Wheeled (speed mode), Turbo, RocketBoost.
--- Phases: "Off" → "Engaging" → "On" → "Disengaging" → "Off" (toggles: SiegeMode, Wheeled);
---         "Off" → "On" (duration) → "Cooldown" → "Off" (Turbo, RocketBoost).
export type MechanicPhase = "Off" | "Engaging" | "On" | "Disengaging" | "Cooldown"
export type MechanicRuntime = {
	kind: string, -- Content.MechanicKind of the keyed mechanic ("" when the vehicle has none)
	phase: MechanicPhase,
	timer: number, -- seconds left in the current timed phase
	charges: number, -- RocketBoost charges left (math.huge for unlimited mechanics)
	lastInput: boolean, -- previous InputCommand.mechanic (edge detection)
}

--- Optional per-vehicle construction data (newState). Geometry defaults derive from VehicleStats.dimensionsM.
export type VehicleSimOptions = {
	bounds: MapBounds?, -- default: square of Config.Movement.DEFAULT_MAP_SIZE_M centred on the origin
	pivots: VehiclePivots?, -- trackContacts + hullSize (studs) from the Blueprint
	drownDepthM: number?, -- water depth over the hull bottom that drowns the crew (default: turret roof height)
}

export type VehicleSimState = {
	-- kinematics (studs, radians, studs/s, rad/s)
	position: Vector3,
	yaw: number,
	pitch: number,
	roll: number,
	speed: number, -- along the hull forward axis (along the slope), + = forward
	lateralSpeed: number, -- sideways slip along the hull right axis (steep side slopes, impacts)
	yawRate: number, -- + = clockwise
	verticalVelocity: number, -- + = up (meaningful while airborne)
	-- ground contact
	grounded: boolean,
	groundPitch: number, -- target attitude of the last ground fit (radians); pitch/roll smooth toward it
	groundRoll: number,
	terrainClass: TerrainClass, -- dominant class under the tracks (HUD/audio)
	terrainResistance: number, -- effective R under the tracks (averaged, water included)
	traction: number, -- effective μ under the tracks
	material: string, -- material under the hull centre
	waterDepthM: number, -- water depth over the hull bottom (m)
	-- timers (s)
	airborneTime: number,
	submergedTime: number, -- time with water at or over the drown depth (resets on exit)
	tiltTime: number, -- time tilted beyond Config.Movement.OVERTURN_DEG before becoming overturned
	overturnedTime: number, -- time spent overturned
	-- status flags
	overturned: boolean,
	drowned: boolean,
	wrecked: boolean, -- terminal (drowned, overturn-destroyed, fell out, or set by the server): step is a no-op
	immobilized: boolean,
	immobileReason: ImmobileReason?,
	mechanicActive: boolean, -- StatCondition "MechanicActive": siege engaged, speed mode on, boost/turbo active
	gunDepressionBonusDeg: number, -- from SiegeMode / Hydropneumatic, read by TurretSim
	gunElevationBonusDeg: number,
	stillTime: number, -- time spent stationary (|speed| and yaw rate below Config.Movement.STILL_*)
	-- inputs and owners
	modifiers: VehicleSimModifiers,
	mechanic: MechanicRuntime,
	bounds: MapBounds,
	lastInputSeq: number,
	tick: number, -- steps simulated (determinism checks, debug)
	nanResets: number, -- times the NaN guard restored the pre-step state (must stay 0; Invariants)
	events: { SimEvent }, -- events of the last step (pooled; length = count)
	-- internal caches (owned by VehicleSim; copied by copyState)
	_options: VehicleSimOptions,
	_geometryReady: boolean,
	_settled: boolean,
	_size: Vector3, -- collision box (width, height, length) in studs
	_contactX: { number }, -- hull-space contact samples (studs): x right, z back; index n+1 = hull centre
	_contactZ: { number },
	_drownDepthM: number,
	_sampleH: { number }, -- scratch: ground heights per sample
	_sampleU: { number }, -- scratch: horizontal hull-flat offsets per sample
	_sampleW: { number },
	_sampleOk: { boolean },
	_contact: { boolean }, -- scratch: sample used by the ground-fit plane
	_eventPool: { SimEvent },
	_restTimer: number, -- time since the last ground probe while resting
	_resting: boolean,
	_restPosition: Vector3,
	_restYaw: number,
	_hydroSettle: number,
	_mechanicIndex: number, -- index into VehicleStats.mechanics of the keyed mechanic (0 = none)
	_hydroIndex: number, -- index of the Hydropneumatic mechanic (0 = none)
}

--------------------------------------------------------------------------------
-- Turret and gun (TurretSim)
--------------------------------------------------------------------------------

--- Runtime effects on the turret/gun, written by their owners (DamageModel, crew, mechanics, ammo selection).
export type TurretSimModifiers = {
	ring: ModuleState, -- TurretRing: Damaged traverse × Config.Movement.TURRET_RING_DAMAGED_MUL, Destroyed jammed
	gun: ModuleState, -- Gun: Damaged elevation speed × Config.Movement.GUN_DAMAGED_ELEVATION_MUL
	traverseMul: number, -- gunner injury f(L) ratio, conditional skills/equipment
	elevationSpeedMul: number,
	depressionBonusDeg: number, -- added to every limit (in addition to the vehicle's mechanic bonus)
	elevationBonusDeg: number,
	enabled: boolean, -- false = frozen (also frozen while the vehicle is overturned or wrecked)
	shellVelocityMps: number, -- selected shell (ShellStats.velocityMps); 0 = aim the barrel straight at the point
	shellGravityMps2: number, -- selected shell (ShellStats.gravityMps2)
	highArc: boolean?, -- use the high ballistic solution (default: GunStats.indirect)
}

export type TurretSimState = {
	turretYawDeg: number, -- turret bearing relative to the hull (0 for casemates)
	gunYawDeg: number, -- casemate gun yaw inside yawLimitsDeg (0 for turrets)
	gunPitchDeg: number, -- elevation relative to the turret (+ up)
	bearingSpeedDegS: number, -- |d(turretYaw + gunYaw)/dt| of the last step (Dispersion ω_tur)
	pitchSpeedDegS: number,
	desiredBearingDeg: number, -- hull-relative bearing that would put the barrel on the aim (unclamped)
	desiredPitchDeg: number, -- elevation that would put the shell on the aim (unclamped)
	aimErrorDeg: number, -- angle between the barrel and the desired direction after the step
	outOfArc: boolean, -- desired bearing beyond the yaw limits (casemate auto hull turn)
	outOfElevation: boolean, -- desired elevation beyond the depression/elevation limits at this bearing
	reachable: boolean, -- false when the shell cannot reach the aim point (ballistic range)
	modifiers: TurretSimModifiers,
}

--------------------------------------------------------------------------------
-- Vehicle–vehicle contacts (Collision)
--------------------------------------------------------------------------------

--- A yaw-oriented collision box. `position` is the hull origin (footprint centre at track-bottom level).
export type CollisionBody = {
	position: Vector3, -- studs
	yaw: number, -- radians, VehicleSimState convention
	size: Vector3, -- (width, height, length) studs
	velocity: Vector3, -- world studs/s
}

--- Face of a box hit by a contact, in that box's own frame.
export type BoxFace = "Front" | "Rear" | "Left" | "Right" | "Top" | "Bottom"

export type CollisionContact = {
	overlapping: boolean,
	normal: Vector3, -- unit, from A toward B (horizontal, or ±Y for stacked boxes)
	depth: number, -- penetration along `normal` (studs); minimum translation = normal * depth
	closingSpeedMps: number, -- (vA - vB) · normal in m/s; > 0 = approaching
	contactPoint: Vector3, -- centre of the overlap region (studs)
	faceA: BoxFace, -- face of A that is hit (rammer front arc: faceA == "Front")
	faceB: BoxFace,
}

return {}
