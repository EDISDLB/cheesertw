--!strict
--[[
	Types/Vehicle — what a vehicle IS in a battle: fully resolved VehicleStats, the player's Loadout, the per-tick
	InputCommand, and the ARMOR MODEL contract between the Blueprint producer and the Combat consumer.

	Purpose:          Shared contract for StatsCalculator (producer of VehicleStats), VehicleSim / TurretSim / GunState
	                  / Dispersion / Spotting / DamageModel (consumers), Garage + matchmaking manifest (Loadout),
	                  Input codecs (InputCommand), Blueprint (producer of ArmorModel) and ArmorGeometry/Penetration/
	                  Armor Inspector (consumers).
	Dependencies:     Types/Content.
	State:            None (type-only).
	Validation:       Producers guarantee the invariants documented per field (finite numbers, unit normals, …).
	Error handling:   N/A.
	Performance notes: Erased at runtime. VehicleStats is built once per vehicle per battle (and on loadout change
	                  in the garage); hot loops read it, never rebuild it.

	VehicleStats units are REAL-WORLD (mm, m, km/h, m/s, deg, s, kg, hp) like content; simulation converts at the
	boundary with Core/Units. The ArmorModel is the one exception: it is in STUDS (Units.STUDS_PER_METER = 3)
	because it is consumed by per-tick ray tests in vehicle-local space.

	Coordinate conventions (ArmorModel, VehiclePivots, InternalVolumeSpec):
	  * Hull space: origin = centre of the hull footprint at ground-contact level (bottom of the tracks); -Z = forward
	    (Roblox LookVector), +Y = up, +X = right (vehicle's right-hand side). The hull CFrame in the world maps hull
	    space to world space.
	  * Turret space: origin = turret-ring centre at the ring plane, axes aligned with hull space at turret yaw 0.
	    world = hullCFrame * pivots.turretRing * CFrame.Angles(0, -yaw, 0) * p   (yaw in radians, + = clockwise).
	  * Gun space: origin = trunnion (elevation axis = X), -Z = barrel direction at elevation 0.
	    world = turretWorld * pivots.gunTrunnion * CFrame.Angles(elevation, 0, 0) * p   (+ elevation = up).
	  * Casemate mounts: the Turret group is fixed (yaw always 0); the gun yaws inside `yawLimitsDeg` about the
	    trunnion's Y axis, then elevates:
	    world = hullCFrame * pivots.turretRing * pivots.gunTrunnion * CFrame.Angles(0, -gunYaw, 0)
	            * CFrame.Angles(elevation, 0, 0) * p   (gunYaw radians, + = clockwise, |gunYaw| <= yaw limit).
	  * Yaw sectors (ArcSector, yawLimitsDeg) are hull-relative bearings in degrees: 0 = forward, + = clockwise,
	    range (-180, 180].
]]

local Content = require("./Content")

type VehicleId = Content.VehicleId
type ModuleId = Content.ModuleId
type ShellId = Content.ShellId
type EquipmentId = Content.EquipmentId
type ConsumableId = Content.ConsumableId
type CrewSkillId = Content.CrewSkillId
type CustomizationId = Content.CustomizationId
type FactionId = Content.FactionId
type VehicleClass = Content.VehicleClass
type RoleId = Content.RoleId
type CrewRole = Content.CrewRole
type ShellKind = Content.ShellKind
type InternalModuleKind = Content.InternalModuleKind
type ArmorZone = Content.ArmorZone
type Configuration = Content.Configuration
type ReloadSpec = Content.ReloadSpec
type StunSpec = Content.StunSpec
type TracerStyle = Content.TracerStyle
type ArcSector = Content.ArcSector
type TerrainResistance = Content.TerrainResistance
type TurretMount = Content.TurretMount
type SpecialMechanic = Content.SpecialMechanic
type StatModifier = Content.StatModifier

--------------------------------------------------------------------------------
-- Resolved stats
--------------------------------------------------------------------------------

--- Module / crew health state (ARCHITECTURE §6.1): Ok > 50 %, Damaged <= 50 %, Destroyed at 0.
export type ModuleState = "Ok" | "Damaged" | "Destroyed"

--- A shell with every content default resolved (no optional fields left).
export type ShellStats = {
	id: ShellId,
	kind: ShellKind,
	special: boolean,
	caliberMm: number,
	damage: number, -- mean alpha after equipment/skills
	moduleDamage: number,
	penetrationMm: number, -- mean pen at <= 100 m
	penetrationAt500Mm: number, -- falloff endpoint (= penetrationMm for HEAT/HE/HESH)
	velocityMps: number,
	gravityMps2: number,
	maxRangeM: number,
	explosionRadiusM: number, -- 0 for AP/APCR/HEAT
	normalizationDeg: number,
	ricochetAngleDeg: number, -- 90 = never ricochets (HE/HESH)
	stun: StunSpec?,
	priceCredits: number,
	tracer: TracerStyle,
}

export type BloomStats = {
	movementPerKmh: number,
	hullTraversePerDegS: number,
	turretTraversePerDegS: number,
	afterShot: number,
	damagedMul: number,
}

export type GunStats = {
	id: ModuleId,
	caliberMm: number,
	--- Reload model with times already scaled by crew level (loaders averaged), equipment and skills.
	reload: ReloadSpec,
	dispersionM100: number,
	aimTimeS: number,
	bloom: BloomStats,
	depressionDeg: number, -- positive magnitude
	elevationDeg: number,
	arcSectors: { ArcSector }, -- hull-relative limits (rear deck); empty = none
	shells: { ShellStats }, -- same order as GunDefinition.shells (hotkeys 1..3)
	ammoCapacity: number,
	camoAfterShotMul: number,
	shellSwapS: number,
	indirect: boolean,
	--- Shift of the lower bound of the damage / penetration roll, as a fraction of the mean, added to the
	--- Config.Combat spread (0 = none; Ammo Tuck `damageRollMin` / `penetrationRollMin` add 0.05 → 0.75 becomes 0.80).
	damageRollMinAdd: number,
	penetrationRollMinAdd: number,
}

--- Per-module health and repair at battle start.
export type ModuleStats = {
	maxHp: number,
	repairS: number, -- field repair Destroyed -> Damaged (50 %), after crew level and equipment
	--- × the Damaged-state penalty of this module (1 = Config.Combat's; Recon on Optics 0.5 turns VR ×0.80 into ×0.90).
	damagedPenaltyMul: number,
}

export type CrewSlotStats = {
	slot: number,
	role: CrewRole,
	also: { CrewRole },
	level: number, -- effective crew level L at battle start (100 + ventilation/rations/brothers in arms)
	maxHp: number, -- crew HP (0.8 × tier reference alpha, 00-DECISIONS §2); 0 HP = injured (L 50), never killed
}

export type CamoStats = {
	stationary: number,
	moving: number,
	afterShotMul: number, -- camo multiplier for Config.Spotting.SHOT_CAMO_PENALTY_S after firing
	net: number, -- added while StationaryArmed (camo net); 0 without
	paint: number, -- flat bonus from cosmetics (0 in ranked)
}

export type WheeledStats = {
	wheelPairs: number,
	speedModeTopSpeedKmh: number,
	speedModeSteeringMul: number,
	speedModeReverseKmh: number,
	toggleS: number,
	lostPairSpeedMul: number,
	movingDispersionMul: number,
	turnRadiusM: number,
}

--- Fully resolved per-battle stats in REAL units. Built by Shared/Vehicle/StatsCalculator from
--- (VehicleDefinition, Loadout, ContentRegistry, Config) with every "Always" modifier already applied (crew level,
--- equipment incl. category-slot bonus, skills at their training share, passive consumables, field kit, Tier XI
--- nodes). Conditional modifiers are listed in `conditionalModifiers` for the runtime system that owns the stat.
--- Mid-battle changes (module damage, injured crew, stun, consumables, siege) are applied by the systems as
--- ratios on top of these values; `crewLevels` records the L each duty was resolved with so an injury can rescale
--- (f(L_injured) / f(L)).
---
--- Where each Content.StatKey lands (every key has exactly one home; Types/Vehicle.spec checks the table):
---   damage, penetration, shellVelocity -> gun.shells[*].damage / penetrationMm (+ penetrationAt500Mm) / velocityMps
---   damageRollMin, penetrationRollMin -> gun.damageRollMinAdd / penetrationRollMinAdd
---   reloadTime -> gun.reload (every timer)  · aimTime -> gun.aimTimeS  · dispersion -> gun.dispersionM100
---   bloomMovement / bloomHullTraverse / bloomTurretTraverse / bloomAfterShot -> gun.bloom.*
---   shellSwapTime -> gun.shellSwapS  · ammoCapacity -> gun.ammoCapacity  · gunDepression / gunElevation -> gun.*Deg
---   turretTraverse -> turretTraverseDegS  · enginePower -> enginePowerHp  · topSpeed / reverseSpeed -> *SpeedKmh
---   hullTraverse -> hullTraverseDegS  · terrainResistance -> terrainResistance  · loadLimit -> loadLimitKg
---   hp -> hp  · moduleHp -> modules[*].maxHp  · repairTime -> modules[*].repairS (+ repairTimeMul)
---   damagedModulePenalty -> modules[*].damagedPenaltyMul  · fireChance -> fireChance  · fireDuration -> fireDurationS
---   crewInjuryChance -> crewInjuryChanceMul  · spallFactor -> spallFactor  · stunDuration -> stunDurationMul
---   ramDamageDealt / ramDamageTaken / fallDamage -> *Mul  · viewRange -> viewRangeM  · signalRange -> signalRangeM
---   camoStationary / camoMoving / camoAfterShot / camoNet -> camo.stationary / moving / afterShotMul / net
---   crewLevel -> crew[*].level + crewLevels  · consumableCooldown -> consumableCooldownMul  · crewXp -> crewXpMul
---   mechanicChargeTime / mechanicCooldown / mechanicDuration / mechanicCharges / mechanicFactor -> mechanics[*]
export type VehicleStats = {
	vehicleId: VehicleId,
	faction: FactionId,
	tier: number,
	class: VehicleClass,
	role: RoleId,
	configuration: Configuration,
	premium: boolean,

	-- survivability
	hp: number, -- hull hp + turret hpBonus, × equipment
	massKg: number, -- hull + mounted modules
	dimensionsM: Vector3, -- (width, height, length) of the hull box incl. tracks; collision OBB
	modules: { [InternalModuleKind]: ModuleStats }, -- one HP pool per kind (every volume of that kind shares it)
	fireChance: number, -- per engine hit
	fireDurationS: number,
	crewInjuryChanceMul: number,
	spallFactor: number, -- K_spall (1 + Spall Lining)
	stunDurationMul: number,
	ramDamageDealtMul: number,
	ramDamageTakenMul: number,
	fallDamageMul: number,
	repairTimeMul: number, -- already folded into modules[*].repairS; kept for consumable math

	-- mobility
	enginePowerHp: number,
	specificPowerHpT: number, -- enginePowerHp / (massKg / 1000)
	topSpeedKmh: number,
	reverseSpeedKmh: number,
	hullTraverseDegS: number,
	terrainResistance: TerrainResistance,
	loadLimitKg: number,
	pivot: boolean,
	wheeled: WheeledStats?,

	-- turret
	turretMount: TurretMount,
	turretTraverseDegS: number,
	yawLimitsDeg: { left: number, right: number }?, -- nil = 360°

	-- firepower
	gun: GunStats,

	-- spotting
	viewRangeM: number, -- base VR × class factor × crew curve × optics module × equipment/skills (Always only)
	signalRangeM: number, -- only meaningful when Config.Spotting.SIGNAL_RELAY_ENABLED
	camo: CamoStats,

	-- crew and loadout
	crew: { CrewSlotStats },
	crewLevels: { [CrewRole]: number }, -- per duty (multiple loaders averaged; doubled duties use that member)
	consumableSlots: number,
	consumableCooldownMul: number,
	crewXpMul: number, -- × crew XP earned (Mentor); Scoring reads it for XpReport.crewXp
	mechanics: { SpecialMechanic }, -- resolved copies: Apex `mechanic*` StatKeys already applied to their numbers
	conditionalModifiers: { StatModifier },
}

--------------------------------------------------------------------------------
-- Loadout (what a player brings to battle)
--------------------------------------------------------------------------------

export type EquipmentSlot = { slot: number, id: EquipmentId } -- slot 1 is the category slot from Tier VI
export type AmmoLoad = { shell: ShellId, count: number } -- list order = hotkeys 1..3
export type ConsumableSlot = { slot: number, id: ConsumableId }
--- `training` = share of the skill's effect (0..1); skills work from 1 %, linear (00-DECISIONS §12).
export type CrewSkillTraining = { id: CrewSkillId, training: number }
export type CrewMemberSnapshot = {
	slot: number, -- index into VehicleDefinition.crew
	role: CrewRole,
	also: { CrewRole }?,
	level: number, -- base level L before equipment/consumables (100; 50 never appears here: injuries are battle-only)
	skills: { CrewSkillTraining },
}
--- Applied cosmetics, one id per slot (each must be a CustomizationDefinition of the matching kind whose scope
--- admits the vehicle). A Style replaces paint + camouflage while applied. Never affects gameplay except the flat
--- paint/camouflage camo bonus (`camoBonus`, 0 in competitive modes).
export type CustomizationLoadout = {
	paint: CustomizationId?,
	camouflage: CustomizationId?,
	emblem: CustomizationId?,
	inscription: CustomizationId?,
	decal: CustomizationId?,
	attachments: { CustomizationId }?, -- <= 4, distinct
	effect: CustomizationId?,
	style: CustomizationId?,
	gunSleeve: CustomizationId?,
	statTracker: CustomizationId?,
}
--- Taken by the Hub at enqueue while the vehicle is locked, carried in the match manifest (ARCHITECTURE §2.1;
--- the manifest codec packs ids to ContentRegistry ordinals to stay under 8 KB). The battle server validates it
--- against content again (configuration mountable, ammo <= capacity, slots in range) and never trusts the client.
export type Loadout = {
	vehicleId: VehicleId,
	configuration: Configuration,
	equipment: { EquipmentSlot },
	ammo: { AmmoLoad }, -- Σ count <= GunStats.ammoCapacity
	consumables: { ConsumableSlot },
	crew: { CrewMemberSnapshot }, -- one per VehicleDefinition.crew seat
	crewPerkEfficiency: number?, -- retrain penalty multiplier on skill effects (0.75..1, default 1)
	customization: CustomizationLoadout,
	fieldKit: { string }?, -- chosen FieldKitOption ids (Elite VI–X)
	apexNodes: { string }?, -- completed ApexNode ids (Tier XI)
}

--------------------------------------------------------------------------------
-- Input (client -> server, 30 Hz; decoded form of the InputPacket codec, ARCHITECTURE §5.2/§6)
--------------------------------------------------------------------------------

--- Bounded per-tick intent. The codec packs the booleans into one flags byte and the aim point as quantised
--- studs; the server validates (finite, |throttle|,|steer| <= 1, aim point inside map bounds) before use.
--- Ammo selection, consumables and quick commands travel on reliable remotes, not here.
export type InputCommand = {
	seq: number, -- client input sequence (monotonic; the codec wraps it at 2^16)
	throttle: number, -- [-1, 1]: + forward
	steer: number, -- [-1, 1]: + right (clockwise)
	aimPoint: Vector3, -- world studs the player aims at (turret/gun track it within traverse and arc limits)
	fire: boolean, -- trigger held: fires on press (Single/Magazine/Autoreloader); charges while held (DualGun
	-- volley, ChargedShot) and releases on let-go
	holdTurret: boolean, -- free look: turret and gun keep their bearing instead of tracking aimPoint
	brake: boolean, -- hold position (tracks locked)
	mechanic: boolean, -- edge-triggered: toggle siege / speed mode, fire boost or cooling (the vehicle's mechanic)
}
export type InputFlag = "fire" | "holdTurret" | "brake" | "mechanic"

--------------------------------------------------------------------------------
-- Armor model (Blueprint producer -> ArmorGeometry / Penetration / DamageModel / Armor Inspector consumers)
--------------------------------------------------------------------------------

export type ArmorGroup = "Hull" | "Turret" | "Gun"
--- How a volume takes a shell (00-DECISIONS §1 "Order", 01-R2), walked in ray order along the shell's path:
---   Armor   = the BODY of a group (hull box, sponsons, superstructure, turret shell, cupola). The interior of the
---             vehicle is the union of the Armor volumes. Penetrating an Armor face puts the shell inside: rolled HP
---             damage plus the internal path (Module/Crew volumes within max(0.5 m, 10 cal)). From inside, Armor
---             faces stop the path (shells never exit); faces shared by adjoining Armor volumes are unreachable from
---             outside and carry the thickness of the plate they continue.
---   Layered = main armor OUTSIDE the body (gun mantlet, appliqué plates): the shell must penetrate it and then the
---             body behind it (pen −= T_eff, continue); penetrating only it deals no HP damage; HE/HESH stopped
---             here deal non-penetration damage from this plate's nominal thickness.
---   Spaced  = screens, skirts, tracks/wheels, the gun barrel: pen −= T_eff (HE/HESH: 3 T), continue; never HP
---             damage on its own; `module` names the external module it damages (TrackLeft/TrackRight, Gun).
---   Module / Crew = internal volumes (thickness 0), reached only on the post-penetration path.
export type ArmorVolumeKind = "Armor" | "Layered" | "Spaced" | "Module" | "Crew"

--- One bounding plane of a convex volume, in the local space of the volume's group (studs).
--- Points p inside the volume satisfy normal:Dot(p) <= distance for every face.
export type ArmorFace = {
	normal: Vector3, -- outward, unit length
	distance: number, -- plane offset: normal:Dot(p) = distance on the face
	thicknessMm: number, -- nominal plate thickness of this face (0 for Module/Crew volumes)
	zone: ArmorZone,
	spaced: boolean, -- = (volume.kind == "Spaced"), copied so face-level consumers (inspector, hit log) need no lookup
}

--- Convex polyhedron = intersection of its faces' half-spaces.
export type ArmorVolume = {
	id: number, -- unique within the model, stable for a given (vehicle, configuration)
	group: ArmorGroup,
	kind: ArmorVolumeKind,
	faces: { ArmorFace }, -- >= 4
	center: Vector3, -- bounding-sphere centre (group space, studs)
	radius: number, -- bounding-sphere radius (studs)
	module: InternalModuleKind?, -- Module volumes; Spaced volumes that are external modules (tracks, gun barrel)
	crewSlot: number?, -- Crew volumes: index into VehicleDefinition.crew
	label: string, -- Armor Inspector / debug label ("Upper glacis", "Ammo rack (bustle)")
}

--- Attachment frames, all in studs.
export type VehiclePivots = {
	turretRing: CFrame, -- turret-ring frame in hull space (position = ring centre at the ring plane)
	gunTrunnion: CFrame, -- trunnion frame in turret space
	muzzle: CFrame, -- muzzle frame in gun space (-Z = shot direction)
	viewPoint: Vector3, -- observation port in turret space (spotting port 2 is the gun axis)
	camoPoints: { Vector3 }, -- visibility checkpoints in hull space (turret roof, mantlet, 4 hull faces at 80 % height)
	trackContacts: { left: { Vector3 }, right: { Vector3 } }, -- ground-contact samples in hull space (4 per side)
	exhausts: { CFrame }, -- hull space (VFX)
	hullSize: Vector3, -- (width, height, length) of the hull box incl. tracks (collision OBB, centred at y = size.Y/2)
}

--- Complete armor + module + crew geometry of one vehicle configuration (turret/gun swaps rebuild it).
--- Invariants (REG-ARM-01): the union of Armor volumes per group is watertight against 10,000 random rays; every
--- Module and Crew volume lies inside its group's Armor volumes; Layered and Spaced volumes lie outside them;
--- faces are unit-normal and finite; volume ids are unique. Gun-group volumes move with the gun (yaw on casemates,
--- elevation always); the Armor Inspector reads the same volumes (zone, thickness, label, module) as Combat.
export type ArmorModel = {
	volumes: { ArmorVolume },
	boundsCenter: Vector3, -- hull space, studs (broadphase sphere covering every group at any turret yaw)
	boundsRadius: number,
	pivots: VehiclePivots,
}

return {}
