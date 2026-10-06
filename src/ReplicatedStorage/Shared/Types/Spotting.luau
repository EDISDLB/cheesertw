--!strict
--[[
	Types/Spotting — the SPOTTING contract: the per-tick vehicle record the battle feeds to SpottingSystem, the events
	it emits (Spotted / Lost / SixthSense), replication tiers, telemetry and the optional World extension.

	Purpose:          Shared by Shared/Spotting/* (producer) and the server BattleInstance / replication / Scoring /
	                  bots (consumers). See docs/design/spotting.md.
	Dependencies:     Types/Content, Types/Vehicle, Types/Battle (type-only).
	State:            None (type-only).
	Validation:       SpottingSystem:update validates records (structure errors raise; non-finite numbers degrade
	                  safely as documented per field).
	Error handling:   N/A.
	Performance notes: Erased at runtime. SpottingEvent records and the arrays returned by SpottingSystem are reused
	                  by the producer: copy what you need before the next update.

	Units: positions/CFrames are STUDS (world space, like VehiclePivots); ranges, speeds and times are real-world
	(m, km/h, s) like Config.Spotting.
]]

local Content = require("./Content")
local Vehicle = require("./Vehicle")
local Battle = require("./Battle")

type EntityId = Battle.EntityId
type TeamId = Battle.TeamId
type CamoStats = Vehicle.CamoStats
type StatModifier = Content.StatModifier

--- The subset of Types/Vehicle.VehiclePivots spotting reads (a VehiclePivots value satisfies it). Studs, hull space
--- (viewPoint in turret space).
export type SpottingPivots = {
	turretRing: CFrame,
	--- Observation port, turret space: the DYNAMIC spotting port that follows the turret yaw (00-DECISIONS "gun axis";
	--- research 02 §2). The STATIC port (top of the hull + turret box over the hull centre) is derived by Spotting.
	viewPoint: Vector3,
	--- Visibility checkpoints in hull space (turret roof, mantlet, 4 hull faces at 80 % height, inset 0.1 m).
	camoPoints: { Vector3 },
	--- Hull box (width, height, length) incl. tracks, centred at y = size.Y / 2: the hull centre used for distances.
	hullSize: Vector3,
}

--- One vehicle as the battle sees it this tick (BattleInstance keeps one record per entity and updates it in place).
export type SpottingVehicle = {
	id: EntityId,
	team: TeamId, -- must not change during a battle
	alive: boolean, -- false = wreck: visible to every team, never observes
	cframe: CFrame, -- hull CFrame (studs; origin at ground-contact centre). Non-finite = skipped this tick
	turretYawRad: number?, -- hull-relative turret yaw (+ = clockwise), places the gun-axis port; nil = 0
	pivots: SpottingPivots,
	viewRangeM: number, -- VehicleStats.viewRangeM ("Always" modifiers folded)
	viewRangeMul: number?, -- runtime ratio (Combat EffectMultipliers.viewRangeMul: optics, commander, stun); nil = 1
	camo: CamoStats, -- VehicleStats.camo (crew/equipment/paint folded)
	moving: boolean, -- hull speed > STOP_SPEED_KMH or yaw rate > MOVING_YAW_RATE_DEG_S (VisibilityModel.isMoving)
	lastShotAt: number?, -- battle time of the last shot (forced check + after-shot penalties)
	inSmoke: boolean?, -- observer inside event smoke: VR × SMOKE_INSIDE_VR_MULT
	sixthSense: boolean?, -- false while the commander is injured (EffectMultipliers.sixthSense); nil = true
	--- VehicleStats.conditionalModifiers; Spotting evaluates viewRange / camoStationary / camoMoving with the
	--- conditions Stationary, StationaryArmed, Moving and Spotted (others belong to other systems). Pass them only
	--- when viewRangeM / camo are the battle-start values: if a runtime resolver (StatsCalculator runtime) already
	--- applied those conditions, pass nil here, never both (double counting).
	conditionalModifiers: { StatModifier }?,
}

export type SpottingEventKind = "Spotted" | "Lost" | "SixthSense"

--- Emitted by SpottingSystem:update into a reused buffer (records are recycled next update).
export type SpottingEvent = {
	kind: SpottingEventKind,
	t: number, -- battle time of the update that produced it
	--- Spotted / Lost: the team that gained / lost sight. SixthSense: the alerted vehicle's own team.
	team: TeamId,
	target: EntityId, -- the vehicle seen / lost / alerted
	spotter: EntityId?, -- Spotted: the observer whose check revealed the target (first-detection credit)
	first: boolean, -- Spotted: first time this team saw this target in the battle
	position: Vector3?, -- Lost: last-known position (hull CFrame position, studs)
}

--- What replication may send about a vehicle to one observer (anti-wallhack, REG-SPT-08).
export type ReplicationTier = "Full" | "Minimap" | "None"

--- Per-update telemetry (reused record; values describe the last update).
export type SpottingStats = {
	tick: number, -- number of updates so far
	now: number,
	rays: number, -- World:sightLine calls this update (always <= MAX_RAYS_PER_TICK)
	foliageProbes: number, -- analytic FoliageProbe calls (no raycast)
	peakRays: number, -- max rays over all updates
	pairs: number, -- directed enemy pairs tracked
	pairsDue: number, -- pairs that needed a LOS check this update
	pairsChecked: number, -- LOS checks completed
	pairsDeferred: number, -- due pairs left for the next update (budget)
	proximitySpots: number, -- pairs spotted by the proximity rule
	cheapRejects: number, -- due pairs rejected by range/formula without rays
}

--- Debug / test view of one directed pair (allocated per call).
export type PairInfo = {
	nextCheck: number,
	lastCheck: number?,
	lastSeen: number?,
	forced: boolean,
	checks: number,
	distanceM: number,
}

--- Optional World extension: analytic foliage concealment summed along [from, to] (same volumes and rules as
--- World:sightLine's `foliage`, no raycast). Used for the 15 m sub-segments when present; otherwise SpottingSystem
--- falls back to extra sightLine calls counted against the ray budget.
export type FoliageProbe = {
	foliageAlong: (self: any, from: Vector3, to: Vector3) -> number,
}

--- SpottingSystem.new options. (The battle ledger's AttributionState is new's second argument: it is a Battle type.)
export type SpottingOptions = {
	visibilityMult: number?, -- per-map-variant VR multiplier (default Config.Spotting.VISIBILITY_MULT_DEFAULT)
}

return {}
