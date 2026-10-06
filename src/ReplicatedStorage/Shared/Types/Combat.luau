--!strict
--[[
	Types/Combat — the COMBAT contract: vehicle pose, armor ray crossings, plate results, shot input/outcome, splash,
	projectiles, aiming state, and the per-vehicle combat state (HP, modules, crew, fire, stun, drowning).

	Purpose:          Shared by Shared/Combat/* (producers) and the server ProjectileSystem / BattleInstance, bots,
	                  VehicleSim / TurretSim / GunState / Spotting (consumers of effect multipliers) and the client
	                  Armor Inspector / reticle (consumers of ArmorGeometry, Penetration, Ballistics, Dispersion).
	Dependencies:     Types/Content, Types/Vehicle, Types/Battle (type-only).
	State:            None (type-only).
	Validation:       Producers keep the invariants documented per field (finite numbers, unit vectors, hp in range).
	Error handling:   N/A.
	Performance notes: Erased at runtime. Crossing / CrossingBuffer / Projectile / AimState records are mutable and
	                  reused by their producers in hot paths: copy what you need before the next call.

	Units: world positions and distances along rays are STUDS (as ArmorModel); everything else is real-world (mm,
	m, m/s, deg, s, kg) like Config. Angles in poses are degrees (hull-relative, + = clockwise for yaw, + = up for
	elevation), matching the Types/Vehicle coordinate conventions.
]]

local Content = require("./Content")
local Vehicle = require("./Vehicle")
local Battle = require("./Battle")

type ShellKind = Content.ShellKind
type InternalModuleKind = Content.InternalModuleKind
type ArmorZone = Content.ArmorZone
type CrewRole = Content.CrewRole
type StunSpec = Content.StunSpec
type ArmorGroup = Vehicle.ArmorGroup
type ArmorVolumeKind = Vehicle.ArmorVolumeKind
type ArmorVolume = Vehicle.ArmorVolume
type ArmorFace = Vehicle.ArmorFace
type ArmorModel = Vehicle.ArmorModel
type ModuleState = Vehicle.ModuleState
type BloomStats = Vehicle.BloomStats
type DamageKind = Battle.DamageKind

--- Battle entity id of whoever caused damage (Types/Battle EntityId); nil = environment (falls, drowning).
export type AttackerId = number

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

--- Where a vehicle's armor groups are this tick (Types/Vehicle "Coordinate conventions").
---   Turret = hullCFrame * pivots.turretRing * Ry(−turretYaw)
---   Gun    = Turret * pivots.gunTrunnion * Ry(−gunYaw) * Rx(gunElevation)
--- Turreted vehicles leave gunYawDeg nil/0; casemates keep turretYawDeg = 0 and yaw the gun.
export type VehiclePose = {
	hullCFrame: CFrame, -- hull space -> world (studs)
	turretYawDeg: number, -- hull-relative bearing, + = clockwise
	gunElevationDeg: number, -- + = up
	gunYawDeg: number?, -- casemate gun yaw inside the mount, + = clockwise
}

--- World frames of each armor group for one pose (ArmorGeometry.groupFrames; Armor Inspector).
export type GroupFrames = { Hull: CFrame, Turret: CFrame, Gun: CFrame }

--- One surface crossing of a ray with a convex ArmorVolume (ArmorGeometry.raycast). Records are pooled.
export type Crossing = {
	distance: number, -- studs along the normalized ray from its origin
	point: Vector3, -- world studs
	normal: Vector3, -- world, unit, OUTWARD from the volume (for an exit crossing it points along the ray)
	entering: boolean, -- true = the ray enters the volume here
	thicknessMm: number, -- nominal thickness of the crossed face (0 for Module/Crew)
	zone: ArmorZone,
	spaced: boolean,
	volumeId: number,
	volumeKind: ArmorVolumeKind,
	group: ArmorGroup,
	module: InternalModuleKind?,
	crewSlot: number?,
	volume: ArmorVolume,
	face: ArmorFace,
	faceIndex: number,
	rank: number, -- tie-break order at equal distance (see ArmorGeometry); internal
}

--- Reusable result list: items[1..count] are valid and sorted by distance, then rank, then volume id.
export type CrossingBuffer = { count: number, items: { Crossing } }

--- A volume found near a point (ArmorGeometry.volumesNear): spall spheres and splash.
export type NearVolume = { volume: ArmorVolume, distance: number } -- distance: studs (lower bound, 0 if inside)
export type NearBuffer = { count: number, items: { NearVolume } }

--------------------------------------------------------------------------------
-- Shells, plates, shots
--------------------------------------------------------------------------------

--- The resolved shell fields Combat needs (Types/Vehicle ShellStats is a supertype and can be passed directly).
export type CombatShell = {
	kind: ShellKind,
	caliberMm: number,
	damage: number, -- mean alpha
	moduleDamage: number,
	penetrationMm: number, -- mean pen at <= 100 m
	penetrationAt500Mm: number,
	velocityMps: number, -- in-game muzzle velocity (already × 0.6)
	gravityMps2: number,
	maxRangeM: number,
	explosionRadiusM: number, -- HE/HESH splash/spall radius; 0 for AP/APCR/HEAT
	normalizationDeg: number,
	ricochetAngleDeg: number, -- 90 = never
	stun: StunSpec?,
}

--- How one plate takes the shell: Main = the body (Armor volume), Layered = main armor outside the body, Spaced =
--- screens / tracks / barrel (Types/Vehicle ArmorVolumeKind).
export type PlateKind = "Main" | "Layered" | "Spaced"
export type PlateOutcome = "Penetrated" | "Stopped" | "Ricochet"
--- Result of one plate interaction (Penetration.resolvePlate). Reusable via its `out` argument.
export type PlateResult = {
	outcome: PlateOutcome,
	angleDeg: number, -- raw impact angle θ from the plate normal
	normalizationDeg: number, -- n' actually applied (0 for HE/HESH and ricochets)
	effectiveMm: number, -- T_eff (HE/HESH on Spaced: the 3 T cost)
	overmatch: boolean, -- kinetic caliber > 3 T: could not ricochet
	twoCaliber: boolean, -- kinetic caliber > 2 T: normalization boosted
	penBefore: number,
	penAfter: number, -- remaining pen (may be <= 0 when Stopped)
}

export type ShotResultKind = "Penetration" | "Ricochet" | "NonPenetration" | "HEBlast" | "Miss"

export type ModuleHitRecord = {
	kind: InternalModuleKind,
	damage: number, -- whole HP, already capped at MODULE_DAMAGE_CAP_MUL × maxHp when the target state is known
	external: boolean, -- Spaced external module (tracks, barrel) vs internal Module volume
	volumeId: number,
}
export type CrewHitRecord = { slot: number, damage: number, volumeId: number }

--- The first plate the shell struck on this target.
export type ShotImpact = {
	point: Vector3,
	normal: Vector3,
	distance: number, -- studs from the ShotInput origin
	zone: ArmorZone,
	thicknessMm: number,
	effectiveMm: number,
	angleDeg: number,
	volumeId: number,
	volumeKind: ArmorVolumeKind,
	group: ArmorGroup,
}

--- Continuation after a ricochet that left the target: the caller keeps flying the shell along this ray and passes
--- penetrationMm / damage / ricochets back in the next ShotInput (pen is not re-rolled).
export type RicochetRay = {
	origin: Vector3,
	direction: Vector3,
	penetrationMm: number,
	damage: number,
	ricochets: number,
}

export type SplashCandidate = {
	armor: ArmorModel,
	pose: VehiclePose,
	state: VehicleCombatState?, -- destroyed targets are skipped; module caps use its maxHp
	spallFactor: number?, -- K_spall (default: state.spallFactor, else Config SPALL_FACTOR_BASE)
	id: any?, -- caller key, echoed in SplashHit
}
export type SplashHit = {
	index: number, -- position in the caller's `nearby` list
	id: any?,
	damage: number, -- whole HP
	distanceM: number, -- burst to nearest armor surface
	thicknessMm: number, -- T_min used
	stunS: number, -- artillery stun duration (0 = none)
	modulesHit: { ModuleHitRecord },
}

export type ShotTarget = {
	armor: ArmorModel,
	pose: VehiclePose,
	state: VehicleCombatState?,
	spallFactor: number?,
	crewInjuryChanceMul: number?,
}

export type ShotInput = {
	shell: CombatShell,
	origin: Vector3, -- world studs (e.g. the start of this tick's swept segment)
	direction: Vector3, -- any length > 0 (normalized internally)
	maxDistance: number?, -- the first impact must lie within this many studs of origin (nil = unbounded)
	firedFrom: Vector3?, -- muzzle position (falloff distance); nil = origin
	penetrationMm: number?, -- carried after the first impact (continuations); nil = roll now
	damage: number?, -- carried rolled alpha; nil = roll now
	ricochets: number?, -- ricochets so far (default 0)
	spread: number?, -- RNG spread (nil = Config ROLL_SPREAD)
	nearby: { SplashCandidate }?, -- HE splash candidates (exclude the direct target)
}

--- Everything a shot did to one target. DamageModel.apply fills fireStarted, ammoRackDetonation, damageApplied and
--- killed (the resolver only computes the hit; the target state decides consequences).
export type ShotOutcome = {
	result: ShotResultKind,
	hit: boolean, -- a plate of the target was struck
	noop: boolean, -- target already destroyed: impact geometry only, nothing to apply
	absorbed: boolean, -- stopped by spaced armor / tracks before reaching the body
	deleted: boolean, -- a ricochet beyond RICOCHET_MAX removed the shell
	damage: number, -- HP damage to apply (whole HP; 0 for ricochets/non-pens of AP/APCR/HEAT)
	potentialDamage: number, -- rolled alpha (DamageEvent.potentialDamage)
	penetrationMm: number, -- rolled pen at the first impact (after falloff)
	penetrationRemainingMm: number,
	effectiveArmorMm: number, -- T_eff of the plate that decided the result
	decidingZone: ArmorZone?,
	plates: number, -- plates struck
	ricochets: number,
	impact: ShotImpact?,
	modulesHit: { ModuleHitRecord },
	crewHit: { CrewHitRecord },
	engineHit: boolean,
	ricochetRay: RicochetRay?,
	burstPoint: Vector3?, -- HE/HESH detonation point (world studs)
	splash: { SplashHit },
	fireStarted: boolean,
	ammoRackDetonation: boolean,
	damageApplied: number,
	killed: boolean,
}

--------------------------------------------------------------------------------
-- Ballistics
--------------------------------------------------------------------------------

--- A shell in flight (mutable; Ballistics.step advances it). All values in studs / seconds.
export type Projectile = {
	origin: Vector3, -- launch point of the current arc (re-based on ricochet)
	velocity0: Vector3, -- studs/s at origin
	gravity: number, -- studs/s², acting along −Y
	t: number, -- seconds since origin
	position: Vector3,
	traveled: number, -- path length so far (studs, chord sum)
	maxRange: number, -- studs
	expired: boolean,
}

--------------------------------------------------------------------------------
-- Aiming
--------------------------------------------------------------------------------

export type DispersionModel = "radial" | "gauss2d"

--- Server/client aiming circle (Dispersion). `multiplier` is M (1 = fully aimed).
export type AimState = {
	baseRadiusM100: number, -- GunStats.dispersionM100
	aimTimeS: number, -- τ
	bloom: BloomStats,
	multiplier: number, -- current M
	target: number, -- last M_target
	extraMul: number, -- last factors.dispersionMul (crew/stun/mechanics) applied to the radius
}

--- Per-tick inputs to Dispersion.update (real units).
export type AimFactors = {
	hullSpeedKmh: number,
	hullTraverseDegS: number,
	turretTraverseDegS: number,
	gunDamaged: boolean?,
	wheeledMoving: boolean?,
	stunned: boolean?,
	dispersionMul: number?, -- × radius (crew injury, siege, volley…)
	aimTimeMul: number?, -- × τ (crew injury, damaged gun, stun…)
}

--------------------------------------------------------------------------------
-- Vehicle combat state (DamageModel)
--------------------------------------------------------------------------------

export type ModuleCombatState = {
	kind: InternalModuleKind,
	hp: number,
	maxHp: number,
	state: ModuleState,
	repairS: number, -- field repair time Destroyed -> Damaged (crew-scaled at battle start)
	repairRemainingS: number, -- > 0 while a Destroyed module is being field-repaired
}

export type CrewCombatState = {
	slot: number,
	role: CrewRole,
	also: { CrewRole },
	level: number, -- healthy level L at battle start
	hp: number,
	maxHp: number,
	injured: boolean,
}

export type FireState = {
	burning: boolean,
	remainingS: number,
	tickAccum: number, -- seconds accumulated toward the next FIRE_TICK_S
	carry: number, -- fractional HP not yet applied
	elapsedS: number, -- since ignition
	igniter: AttackerId?, -- credited with fire damage
}

export type VehicleCombatState = {
	hp: number,
	maxHp: number,
	destroyed: boolean,
	cause: DamageKind?,
	killer: AttackerId?,
	modules: { [InternalModuleKind]: ModuleCombatState },
	moduleOrder: { InternalModuleKind }, -- deterministic iteration order
	crew: { CrewCombatState },
	crewLevels: { [CrewRole]: number }, -- L each duty was resolved with in VehicleStats
	fire: FireState,
	stunRemainingS: number,
	stunAttacker: AttackerId?,
	drownS: number,
	ammoStored: number, -- shells in the rack (GunState keeps it in sync); detonation needs >= 1
	autoExtinguisher: boolean, -- armed Automatic Extinguisher
	fireChance: number,
	fireDurationS: number,
	spallFactor: number,
	crewInjuryChanceMul: number,
	stunDurationMul: number,
	ramDamageDealtMul: number,
	ramDamageTakenMul: number,
	fallDamageMul: number,
	massKg: number,
	wheeled: boolean,
	contacts: { [any]: boolean }, -- recent ram/fall contact ids (REG-ARM-10)
	contactRing: { any },
	contactNext: number,
}

--- The subset of Types/Vehicle VehicleStats DamageModel.new needs (VehicleStats itself can be passed).
export type DamageModelInit = {
	hp: number,
	massKg: number,
	modules: { [InternalModuleKind]: { maxHp: number, repairS: number } },
	crew: { { slot: number, role: CrewRole, also: { CrewRole }, level: number, maxHp: number } },
	crewLevels: { [CrewRole]: number },
	fireChance: number,
	fireDurationS: number,
	spallFactor: number,
	crewInjuryChanceMul: number,
	stunDurationMul: number,
	ramDamageDealtMul: number,
	ramDamageTakenMul: number,
	fallDamageMul: number,
	wheeled: any?, -- WheeledStats when the vehicle runs on wheels
}

export type FireReason = "Ignited" | "BurnedOut" | "Extinguished" | "AutoExtinguisher" | "Destroyed"

--- State changes DamageModel reports (the caller stamps time/target and maps them to Types/Battle BattleEvents).
export type CombatEvent =
	{ type: "Damage", kind: DamageKind, damage: number, attacker: AttackerId? }
	| { type: "ModuleState", module: InternalModuleKind, state: ModuleState, attacker: AttackerId? }
	| { type: "CrewInjured", slot: number, role: CrewRole, attacker: AttackerId? }
	| { type: "CrewHealed", slot: number, role: CrewRole }
	| { type: "Fire", burning: boolean, reason: FireReason, attacker: AttackerId? }
	| { type: "Stunned", durationS: number, attacker: AttackerId? }
	| { type: "Drowning", active: boolean, remainingS: number }
	| { type: "Destroyed", cause: DamageKind, attacker: AttackerId? }

--- Runtime multipliers from module states, crew injuries and stun (DamageModel.effects), applied by the systems
--- that own each stat on top of VehicleStats. 1 = unchanged.
export type EffectMultipliers = {
	enginePowerMul: number, -- VehicleSim
	topSpeedMul: number, -- wheeled lost sides, stun
	canMove: boolean, -- false: engine or (tracked) a track destroyed
	hullTraverseMul: number, -- driver injury, stun
	turretTraverseMul: number, -- ring damaged/destroyed, gunner injury, stun (0 = no traverse)
	reloadTimeMul: number, -- damaged ammo rack, loader injury, stun
	canFire: boolean, -- gun not destroyed
	aimTimeMul: number, -- damaged gun, gunner injury, stun (Dispersion AimFactors.aimTimeMul)
	dispersionMul: number, -- gunner injury, stun (damaged-gun bloom is AimFactors.gunDamaged)
	gunDamaged: boolean,
	viewRangeMul: number, -- optics, commander injury, stun
	repairTimeMul: number, -- driver injury (applied by DamageModel.update itself)
	fireChanceMul: number, -- fuel tank damaged
	sixthSense: boolean, -- commander not injured
	stunned: boolean,
	burning: boolean,
}

--------------------------------------------------------------------------------
-- Ramming
--------------------------------------------------------------------------------

export type RamParty = {
	massKg: number,
	contactThicknessMm: number, -- nominal armor at the contact point
	spallFactor: number?,
	frontArc: boolean, -- contact on this vehicle's front arc (takes × RAM_FRONT_ARC_TAKEN_MUL)
	ramDamageDealtMul: number?,
	ramDamageTakenMul: number?,
}

return {}
