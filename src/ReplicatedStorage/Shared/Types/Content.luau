--!strict
--[[
	Types/Content — the CONTENT SCHEMA: typed definitions for every authored data kind (factions, classes, roles,
	tiers, shells, modules, vehicles, loadout items, cosmetics, missions, achievements, maps, store, live events).

	Purpose:          The data contract that content authors write (Config/Content/*) and that combat, vehicle sim,
	                  spotting, progression, economy, matchmaking, UI and the map builder read. Field-by-field guide,
	                  units, defaults and examples: docs/design/content-schema.md.
	Dependencies:     None (type-only; bottom of the Types graph: Vehicle, Battle and Profile build on it).
	State:            None (type-only).
	Validation:       Config/ContentRegistry:validate() enforces every constraint written in these comments.
	Error handling:   N/A.
	Performance notes: Erased at runtime.

	Conventions (apply to every type below):
	  * Ids are lowercase snake_case strings (`^[a-z][a-z0-9_]*$`, <= 48 chars), unique per kind. Module ids (guns,
	    turrets, engines, tracks) are unique across all four module kinds because research is global
	    (`profile.researchedModules`). Ids never encode a tier (vehicles move tiers; ids must not).
	  * Units are real-world: armor mm, distances/sizes m, speeds km/h, velocities m/s, angles deg (depression and
	    elevation are positive magnitudes), times s, mass kg, power hp, accelerations m/s². Studs appear only in the
	    Blueprint output (Types/Vehicle ArmorModel). Map positions are metres in map space (see Vec2).
	  * Optional fields (`?`) fall back to a documented default (class, tier or Config.Combat), so authors only write
	    what differs. Enumerations that code branches on are PascalCase literal unions; registry ids (factions,
	    classes, roles) are snake_case and double as icon file names.
	  * Text fields are English source strings (sentence case, brand-art §2); localization keys derive from ids.
]]

--------------------------------------------------------------------------------
-- Ids and keys
--------------------------------------------------------------------------------

export type ContentId = string
--- The six locked factions (00-DECISIONS §0, brand-art §3.7).
export type FactionId =
	"iron_union"
	| "crown_industries"
	| "eastern_armor"
	| "desert_corps"
	| "mountain_republic"
	| "northern_federation"
--- Vehicle classes; ids match `assets/icons/classes/<id>.svg` (brand-art §6.6).
export type VehicleClass = "light" | "medium" | "heavy" | "td" | "artillery"
--- Roles, four per direct-fire class plus two artillery roles (00-DECISIONS §7.2). `<class>_<role>`.
export type RoleId =
	"light_scout"
	| "light_support"
	| "light_versatile"
	| "medium_assault"
	| "medium_sniper"
	| "medium_support"
	| "medium_versatile"
	| "heavy_assault"
	| "heavy_breakthrough"
	| "heavy_support"
	| "heavy_versatile"
	| "td_assault"
	| "td_sniper"
	| "td_support"
	| "td_versatile"
	| "artillery_support"
	| "artillery_area_control"
--- 1..11 (XI = "Apex").
export type Tier = number
export type VehicleId = string
export type ModuleId = string
export type ShellId = string
export type EquipmentId = string
export type ConsumableId = string
export type CrewSkillId = string
export type CrewBookId = string
export type BoosterId = string
export type CustomizationId = string
export type MissionId = string
export type CampaignId = string
export type AchievementId = string
export type MapId = string
export type StoreItemId = string
export type EventId = string
export type SeasonId = string
--- Tech-tree branch id, `<faction prefix>_<branch>` (e.g. "iu_bulwark"; roster.md §1 branch tables).
export type BranchId = string
--- "<folder>/<file>" under assets/icons without extension (e.g. "classes/heavy", "factions/iron_union"). The
--- AssetResolver returns the uploaded image or a vector glyph fallback (ARCHITECTURE §11).
export type IconKey = string
--- Key in assets/audio/catalog.json (e.g. "engine_heavy_diesel", "gun_medium_50_85mm").
export type SoundKey = string
--- Map builder prop kind (owned by the map/builder team, e.g. "house_small", "rock_large", "fence_wood").
export type PropKind = string

--- Every registry kind (ContentRegistry getters, ordinals, issue paths).
export type ContentKind =
	"Faction"
	| "Class"
	| "Role"
	| "Tier"
	| "Shell"
	| "Gun"
	| "Turret"
	| "Engine"
	| "Tracks"
	| "Vehicle"
	| "Equipment"
	| "Consumable"
	| "CrewSkill"
	| "CrewBook"
	| "Booster"
	| "Customization"
	| "Mission"
	| "Achievement"
	| "Map"
	| "StoreItem"
	| "Event"
	| "Season"
	| "Branch"

--------------------------------------------------------------------------------
-- Engine enumerations
--------------------------------------------------------------------------------

--- Four crew roles; radio-operator duties fold into the Commander (00-DECISIONS §12, §21 #8).
export type CrewRole = "Commander" | "Gunner" | "Driver" | "Loader"
--- Shell families (00-DECISIONS §1). "Special" rounds are the same family with `special = true`.
export type ShellKind = "AP" | "APCR" | "HEAT" | "HE" | "HESH"
--- Researchable module kinds. There is NO radio module (00-DECISIONS §2, §21 #7; ARCHITECTURE §9).
export type ModuleKind = "Gun" | "Turret" | "Engine" | "Tracks"
--- Damageable internal/external modules (00-DECISIONS §2). Tracks are external; wheeled vehicles use the same
--- two sides (a side = all wheel pairs on it). One HP pool per kind: a layout with two ammo racks or two fuel tanks
--- produces several volumes that all damage the same module. The transmission is part of the Engine module (a front
--- transmission is an Engine volume behind the lower plate: engine damage and fire chance).
export type InternalModuleKind =
	"Engine"
	| "AmmoRack"
	| "FuelTank"
	| "Gun"
	| "TurretRing"
	| "Optics"
	| "TrackLeft"
	| "TrackRight"
--- Armor zones (Armor Inspector labels, Blueprint face tagging, hit logs).
export type ArmorZone =
	"HullUpperFront"
	| "HullLowerFront"
	| "HullSide"
	| "HullRear"
	| "HullRoof"
	| "HullFloor"
	| "EngineDeck"
	| "SuperstructureFront"
	| "SuperstructureSide"
	| "TurretFront"
	| "TurretSide"
	| "TurretRear"
	| "TurretRoof"
	| "Mantlet"
	| "Cupola"
	| "Track"
	| "Wheel"
	| "Skirt"
	| "GunBarrel"
export type EquipmentCategory = "Firepower" | "Survivability" | "Mobility" | "Scouting"
--- How a vehicle is obtained. TechTree = researched with XP + bought with Credits; Premium = Bullion; Reward =
--- missions/campaigns/pass (never sold); Event = event-only.
export type Acquisition = "TechTree" | "Premium" | "Reward" | "Event"
--- Battle modes (queues / server kinds). Random battles have a BattleType.
export type BattleMode = "Random" | "Training" | "Bootcamp" | "Practice" | "Event"
--- Random-battle objective types (00-DECISIONS §8, §9).
export type BattleType = "Standard" | "Encounter" | "Assault"
export type Currency = "Credits" | "Bullion" | "VehicleXP" | "FreeXP" | "CrewXP" | "CampaignTokens" | "EventTokens"
--- Brand rarity tokens (brand-art §3.5): Standard, Field, Veteran, Elite, Legendary, Prototype.
export type Rarity = "common" | "uncommon" | "rare" | "epic" | "legendary" | "prototype"
--- Climate strip colours of brand-art §9.
export type Biome = "temperate" | "desert" | "winter" | "urban" | "alpine"

--------------------------------------------------------------------------------
-- Shared value types
--------------------------------------------------------------------------------

--- Inclusive numeric range.
export type Range = { min: number, max: number }
--- Price in one or more currencies (all fields optional; at least one > 0 unless the thing is free).
--- Robux prices are never stored (Managed Pricing; StoreItem.robux names the developer product instead).
export type Price = {
	credits: number?,
	bullion: number?,
	campaignTokens: number?,
	eventTokens: { eventId: EventId, amount: number }?,
}
--- Map-space position in metres: origin = map centre, +x = east, +z = south (world studs = metres × 3, same X/Z axes).
export type Vec2 = { x: number, z: number }

--------------------------------------------------------------------------------
-- Stat modifiers (equipment, crew skills, consumables, mechanics, field kits, Tier XI nodes)
--------------------------------------------------------------------------------

--- Every resolvable stat a modifier may touch. `mul` multiplies, `add` adds in the stat's own unit
--- (km/h, m, deg, crew-level points, camo factor 0..1, K_spall factor).
export type StatKey =
	-- firepower
	"damage"
	| "damageRollMin" -- raises the low end of the ±25 % damage roll (Ammo Tuck)
	| "penetration"
	| "penetrationRollMin" -- raises the low end of the penetration roll
	| "reloadTime"
	| "aimTime"
	| "dispersion"
	| "bloomMovement"
	| "bloomHullTraverse"
	| "bloomTurretTraverse"
	| "bloomAfterShot"
	| "shellVelocity"
	| "shellSwapTime"
	| "ammoCapacity"
	| "turretTraverse"
	| "gunDepression"
	| "gunElevation"
	-- mobility
	| "enginePower"
	| "topSpeed"
	| "reverseSpeed"
	| "hullTraverse"
	| "terrainResistance"
	| "loadLimit"
	-- survivability
	| "hp"
	| "moduleHp" -- `module` qualifier = one module kind (nil = every module)
	| "repairTime" -- `module` qualifier as moduleHp
	| "damagedModulePenalty" -- × the Damaged-state penalty of `module` (Recon: optics, Engineer: engine)
	| "fireChance"
	| "fireDuration"
	| "crewInjuryChance"
	| "spallFactor"
	| "stunDuration"
	| "ramDamageDealt"
	| "ramDamageTaken"
	| "fallDamage"
	-- scouting
	| "viewRange"
	| "camoStationary"
	| "camoMoving"
	| "camoAfterShot"
	| "camoNet"
	| "signalRange"
	-- crew, consumables, economy
	| "crewLevel"
	| "consumableCooldown"
	| "crewXp"
	-- the vehicle's SpecialMechanic (Apex nodes upgrade the signature, 00-DECISIONS §11; roster §2.7)
	| "mechanicChargeTime" -- ChargedShot chargeTimeS
	| "mechanicCooldown" -- cooldownS of Turbo / RocketBoost / ActiveCooling / ReserveTracks
	| "mechanicDuration" -- durationS of Turbo / RocketBoost / ActiveCooling (ReserveTracks: repairS)
	| "mechanicCharges" -- RocketBoost / ReserveTracks charges (add)
	| "mechanicFactor" -- main factor: AdaptiveMagazine partialReloadFactor, Turbo powerMul, ChargedShot mul
export type StatOp = "mul" | "add"
--- When a modifier applies. "Always" modifiers are folded into VehicleStats at battle start; every other condition
--- is carried in VehicleStats.conditionalModifiers and evaluated by the runtime system that owns the stat.
export type StatCondition =
	"Always"
	| "Stationary" -- hull speed < Config.Spotting.STOP_SPEED_KMH
	| "StationaryArmed" -- stationary for >= Config.Spotting.STATIONARY_ARM_S (nets, masts)
	| "Moving"
	| "TurretTraversing"
	| "AfterShot" -- for `durationS` after firing
	| "AfterTakingDamage" -- for `durationS` after losing HP
	| "AfterSpotting" -- for `durationS` after the team first spots an enemy thanks to this vehicle
	| "NearEnemy" -- an enemy vehicle within `rangeM`
	| "Spotted" -- this vehicle is team-visible to the enemy
	| "LowHp" -- hp <= 25 % of max
	| "MechanicActive" -- siege engaged, speed mode on, boost/cooling active
export type StatModifier = {
	stat: StatKey,
	op: StatOp,
	value: number,
	condition: StatCondition?, -- default "Always"
	durationS: number?, -- AfterShot / AfterTakingDamage / AfterSpotting window
	rangeM: number?, -- NearEnemy radius
	module: InternalModuleKind?, -- qualifier for moduleHp / repairTime / damagedModulePenalty only (nil = all)
}

--------------------------------------------------------------------------------
-- Balance reference (class baselines, role trims, faction kits) — read by the balance lint, never at runtime
--------------------------------------------------------------------------------

--- Stats compared by the balance lint (00-DECISIONS §7: stat ÷ (class × role × tier × kit) in [0.85, 1.15]).
export type BalanceStat =
	"hp"
	| "alpha"
	| "penetration"
	| "reload"
	| "dpm"
	| "aimTime"
	| "dispersion"
	| "topSpeed"
	| "specificPower"
	| "hullTraverse"
	| "turretTraverse"
	| "viewRange"
	| "hullArmor"
	| "turretArmor"
	| "lowerPlateArmor"
--- Multipliers relative to the Medium baseline (classes), trims (roles) or kits (factions).
export type BalanceKit = {
	mul: { [BalanceStat]: number }?,
	camoAdd: number?, -- added to class camo (role trims: Scout +0.03…)
	viewRangeAddM: number?, -- added to base view range
	depressionDeg: number?, -- typical depression magnitude for a faction (e.g. 5 for iron_union)
	depressionAddDeg: number?, -- role trim (heavy_support +2)
}

--------------------------------------------------------------------------------
-- Factions, classes, roles, tiers
--------------------------------------------------------------------------------

export type FactionSignature =
	"DualGun"
	| "HESH"
	| "Magazine"
	| "Wheeled"
	| "Autoreloader"
	| "SiegeMode"
	| "Hydropneumatic"
	| "AssaultTD"
export type FactionDefinition = {
	id: FactionId,
	name: string, -- Title Case body name ("Iron Union"); UI upper-cases for headings
	shortName: string, -- 2-4 letter display designation ("IU", "EAG")
	idPrefix: string, -- id prefix of this faction's vehicles, modules and branches ("iu" -> "iu_kolmal")
	motto: string,
	description: string,
	focus: { string }, -- 2-4 identity bullets
	emblem: IconKey, -- "factions/<id>"
	order: number, -- tech-tree / filter order (1..6)
	--- UI colours from brand-art §3.7 (primary = enamel, secondary = trim, textTint = name on dark panels).
	palette: { primary: Color3, secondary: Color3, textTint: Color3 },
	--- Default vehicle paint (VehicleRenderer); `camo` = pattern colours for faction camouflage cosmetics.
	vehiclePaint: { base: Color3, secondary: Color3, accent: Color3, camo: { Color3 } },
	kit: BalanceKit, -- 00-DECISIONS §7.3 faction kit (balance lint baseline)
	signatures: { FactionSignature },
	--- Blueprint shape grammar used by this faction's vehicles unless VisualSpec.preset overrides it
	--- ("iu_foundry", roster.md §1.x builder tables).
	builderPreset: string,
}

--- Body camouflage factors (0..1) with a trained crew, before skills/equipment/paint (00-DECISIONS §5).
export type CamoSpec = { stationary: number, moving: number, net: number? }
export type TerrainResistance = { hard: number, medium: number, soft: number }
export type ClassDefinition = {
	id: VehicleClass,
	name: string, -- "Heavy tank"
	shortName: string, -- "HT"
	description: string,
	icon: IconKey, -- "classes/<id>"
	minimapIcon: IconKey, -- "minimap/class_<id>"
	order: number,
	tiers: Range, -- tiers this class may exist at (artillery IV–X)
	roles: { RoleId }, -- UI order; every role's `class` must be this id
	baseline: BalanceKit, -- class multipliers vs the Medium baseline (00-DECISIONS §7.1)
	camo: CamoSpec, -- turreted default
	camoCasemate: CamoSpec?, -- casemate (turretless) default; td only
	viewRangeMul: number, -- × tier base view range (LT 1.10 … SPG 0.85)
	afterShotBloom: number, -- default GunBloom.afterShot (LT/MT/TD 3.0, HT 3.5, SPG 4.0)
	terrainResistance: TerrainResistance, -- default for new tracks (00-DECISIONS §6)
	signalRangeM: number, -- used only when Config.Spotting.SIGNAL_RELAY_ENABLED (special modes)
}

--- Role Score components (00-DECISIONS §7.2); each normalised by the class×tier median before weighting.
export type RoleScoreComponent =
	"damageDealt"
	| "damageBlocked"
	| "capture"
	| "firstContactDamage"
	| "assist"
	| "assistSpotting"
	| "assistTracking"
	| "assistStun"
	| "kills"
	| "detections"
--- Soft matchmaking mirror groups (Assault-type vs Sniper-type …).
export type RoleGroup = "Frontline" | "Ranged" | "Support" | "Versatile" | "Recon" | "Indirect"
export type FieldKitOption = { id: string, name: string, description: string, effects: { StatModifier } }
--- One Field Kit level: a free-swap choice between two options (00-DECISIONS §11, Elite VI–X).
export type FieldKitLevel = { options: { FieldKitOption } }
export type RoleDefinition = {
	id: RoleId,
	class: VehicleClass,
	name: string, -- "Scout"
	description: string, -- one-line tooltip
	playstyle: string, -- recommended playstyle paragraph (garage "About role")
	tips: { string }, -- exactly 3 "do this" tips
	statEmphasis: { StatKey }, -- stats the garage highlights for this role (2-4)
	trims: BalanceKit, -- role trims on top of the class baseline (balance lint)
	categorySlot: EquipmentCategory, -- Tier VI+ specialised equipment slot (+15 % effect)
	roleScore: { [RoleScoreComponent]: number }, -- weights sum to 1
	group: RoleGroup,
	badge: IconKey, -- "roles/<id>"
	--- The role's Field Kit levels (Elite Tier VI–X; level i = fieldKit[i]). There is no class-wide fallback: nil is
	--- legal only while no Tier VI–X vehicle has this role, and a role with Tier VI–X vehicles needs at least as many
	--- levels as their tiers grant (TierDefinition.fieldKit.levels; FIELD_KIT).
	fieldKit: FieldKit?,
}

--- The Medium-tank reference row of a tier (00-DECISIONS §7.4).
export type MediumBaseline = {
	hp: number,
	alpha: number,
	penetrationMm: number,
	reloadS: number,
	aimTimeS: number,
	dispersionM100: number,
	topSpeedKmh: number,
	specificPowerHpT: number,
	hullTraverseDegS: number,
	turretTraverseDegS: number,
	viewRangeM: number,
	hullArmorMm: { front: number, side: number, rear: number },
	turretFrontMm: number,
}
--- Economy reference row of a tier (00-DECISIONS §11). Config.Economy owns live formulas; these are the authoring
--- targets the balance report checks vehicles and modules against.
export type TierEconomy = {
	researchXp: number, -- XP to research a tech-tree vehicle of this tier
	priceCredits: number, -- credit price of a tech-tree vehicle of this tier
	moduleXpTotal: number, -- XP for all module upgrades on one vehicle of this tier
	xpPerBattle: number,
	battlesAtTier: number,
	fullRepairCredits: number,
	shellCredits: number, -- standard shell price
	netCreditsPerBattle: number,
	xpScale: number, -- Scoring tierScaleXP (placeholder 1.0 until Economy tunes it)
	creditScale: number, -- Scoring tierScaleCR (placeholder 1.0)
	premiumBullion: number?, -- premium vehicle Bullion price at this tier (nil = premiums not sold)
	premiumCreditMul: number?, -- premium vehicle credit coefficient
}
export type TierDefinition = {
	tier: Tier,
	numeral: string, -- "I".."XI"
	name: string?, -- "Apex" for XI
	badge: IconKey, -- "tiers/tier_01"
	--- Matchmaking hint: tiers a vehicle of this tier may meet. Two vehicles can share a battle only when each
	--- range contains the other's tier (Matchmaking.luau owns templates; 00-DECISIONS §8).
	matchmaking: Range,
	baseline: MediumBaseline,
	economy: TierEconomy,
	equipmentSlots: number, -- I–III 2, IV–XI 3
	consumableSlots: number, -- 3
	categorySlot: boolean, -- VI+ has the role-specialised slot
	equipmentBand: "C" | "B" | "A", -- equipment price/grade band mountable at this tier
	fieldKit: { levels: number, xpPerLevel: number }?, -- VI–X
	stunMaxS: number, -- artillery stun at the splash centre (IV 0 … X 16)
	moduleHpRefAlpha: number, -- module HP = k × this (00-DECISIONS §2)
}

--------------------------------------------------------------------------------
-- Ammunition
--------------------------------------------------------------------------------

--- Artillery HE stun: duration lerps from maxS at the splash centre to minS at the edge.
export type StunSpec = { maxS: number, minS: number }
export type TracerStyle = "AP" | "APCR" | "HEAT" | "HE" | "Artillery"
export type ShellDefinition = {
	id: ShellId,
	name: string, -- display designation ("AP-T 45")
	kind: ShellKind,
	special: boolean, -- special round (more pen or utility); costs 2.5 × credits (00-DECISIONS §11)
	caliberMm: number, -- must equal every gun that lists it
	damage: number, -- mean HP damage (alpha); rolled ±25 % (Config.Combat)
	penetrationMm: number, -- mean pen at <= 100 m
	velocityMps: number, -- in-game muzzle velocity = 0.6 × the real-world figure (00-DECISIONS §1)
	priceCredits: number,
	moduleDamage: number?, -- default 0.5 × damage (AP/APCR/HEAT) or 0.75 × damage (HE/HESH)
	penetrationAt500Mm: number?, -- AP/APCR falloff endpoint override (default AP ×0.90, APCR ×0.75)
	gravityMps2: number?, -- default Config.Combat shell gravity (19.62)
	maxRangeM: number?, -- default 600 (direct fire); artillery shells >= 900
	explosionRadiusM: number?, -- HE/HESH only; default caliber/100 (direct) or 3 + 0.03 × caliber (artillery)
	normalizationDeg: number?, -- override of the per-kind default (AP 5, APCR 2, others 0)
	ricochetAngleDeg: number?, -- override (AP/APCR 70, HEAT 85; HE/HESH never ricochet)
	stun: StunSpec?, -- artillery HE only
	tracer: TracerStyle?, -- default by kind
	icon: IconKey?, -- default "ammo/<kind>[_special]"
}

--------------------------------------------------------------------------------
-- Modules (shared across vehicles; each module carries its own visuals so mounting it changes the model)
--
-- Common module fields: id, kind, name, tier (1..11, the tier it is balanced for), massKg (counts against the
-- tracks' load limit), priceCredits (bought separately for any vehicle that can mount it), researchXp (global:
-- once researched on any vehicle it is researched everywhere; 0 for modules only ever used as stock).
--------------------------------------------------------------------------------

--- Reload model (GunState). Magazine/Autoreloader/DualGun are the Tier I–X special guns (00-DECISIONS §4).
--- Autoreloader `perShellReloadS` lists one timer per slot in refill order after the magazine empties; the first
--- refill is the longest (00-DECISIONS §4), so the list never starts with a shorter timer than the rest. DualGun
--- needs ammoCapacity >= 2 (a volley fires both barrels).
export type ReloadSpec =
	{ kind: "Single", reloadS: number }
	| { kind: "Magazine", size: number, intraClipS: number, reloadS: number }
	| { kind: "Autoreloader", size: number, perShellReloadS: { number }, intraClipS: number }
	| { kind: "DualGun", reloadEachS: number, salvoDelayS: number, chargeTimeS: number, volleyDispersionMul: number }
export type ReloadKind = "Single" | "Magazine" | "Autoreloader" | "DualGun"
export type GunArcs = { depressionDeg: number, elevationDeg: number }
--- Dispersion bloom factors (00-DECISIONS §3). nil fields use Config.Combat / class defaults.
export type GunBloom = {
	movementPerKmh: number?, -- default 0.07
	hullTraversePerDegS: number?, -- default 0.075
	turretTraversePerDegS: number?, -- default 0.03
	afterShot: number?, -- default ClassDefinition.afterShotBloom
	damagedMul: number?, -- default 1.5 (gun module Damaged)
}
export type MuzzleBrake = "None" | "Single" | "Double" | "Slotted" | "Pepperpot"
export type MantletStyle = "Box" | "Rounded" | "Pig" | "Narrow" | "Cast"
export type GunVisual = {
	barrelLengthM: number, -- from trunnion to muzzle
	barrelDiameterM: number?, -- default caliber × 2.2
	muzzleBrake: MuzzleBrake,
	fumeExtractor: boolean?,
	thermalSleeve: boolean?,
	mantlet: MantletStyle,
	mantletWidthM: number?, -- default caliber × 6 (clamped to the turret width)
}
--- Gun sound families present in assets/audio/guns (audio.md).
export type GunAudioFamily =
	"small_20_45mm"
	| "medium_50_85mm"
	| "large_88_122mm"
	| "huge_130_183mm"
	| "autocannon_burst"
	| "artillery_howitzer"
export type GunDefinition = {
	id: ModuleId,
	kind: "Gun",
	name: string,
	tier: Tier,
	massKg: number,
	priceCredits: number,
	researchXp: number,
	caliberMm: number,
	shells: { ShellId }, -- 1..3, unique; the first is the standard (non-special) round
	reload: ReloadSpec, -- base times at crew level 100
	dispersionM100: number, -- aiming-circle radius in m at 100 m, fully aimed
	aimTimeS: number, -- convergence time constant τ
	arcs: GunArcs,
	ammoCapacity: number,
	bloom: GunBloom?,
	camoAfterShotMul: number?, -- default clamp(0.40 − 0.0025·(cal − 20), 0.05, 0.40)
	shellSwapS: number?, -- default = one reload (00-DECISIONS §4)
	--- Artillery howitzer (strategic view, elevation >= 45°): required for artillery vehicles, never on others; its
	--- shells are HE/HESH only (standard + special HE, roster.md §0.2) with maxRangeM >= 900.
	indirect: boolean?,
	visual: GunVisual,
	audio: GunAudioFamily,
}

export type TurretMount = "Turret" | "Casemate"
export type TurretArmor = {
	front: number,
	side: number,
	rear: number,
	roof: number,
	mantlet: number,
	cupola: number?, -- default = roof (a classic weak spot when thinner than the face)
}
export type TurretStyle =
	"Box"
	| "Cast"
	| "Welded"
	| "Wedge"
	| "Hexagonal"
	| "Dome"
	| "FacetedDome"
	| "Oscillating"
	| "Casemate"
	| "Open"
export type TurretVisual = {
	style: TurretStyle,
	lengthM: number,
	widthM: number,
	heightM: number,
	bustleLengthM: number?, -- rear overhang behind the ring (ammo-rack placement "Bustle" goes here)
	frontAngleDeg: number?, -- face slope from vertical (default by style)
	sideAngleDeg: number?,
	rearAngleDeg: number?,
	cupola: boolean?,
}
export type TurretDefinition = {
	id: ModuleId,
	kind: "Turret",
	name: string,
	tier: Tier,
	massKg: number,
	priceCredits: number,
	researchXp: number,
	--- "Turret" = a rotating turret (Turret group yaws about pivots.turretRing). "Casemate" = turretless TD/SPG: the
	--- module is the fixed GUN MOUNT set into the vehicle's fighting compartment, which belongs to the HULL — either
	--- `HullVisual.superstructure` (armor `superstructureFront/Side`, zones Superstructure*) or a `HullStyle`
	--- "Casemate" hull (MOUNT). The mount's `visual` is the gun housing (style "Casemate", sized to the housing, not
	--- the compartment), `armor.front` its gun shield and `armor.mantlet` the mantlet; it sits at `turretRing`, never
	--- yaws, and only the gun yaws within `yawLimitsDeg` (required). A vehicle never mixes the two mounts.
	mount: TurretMount,
	armor: TurretArmor,
	traverseDegS: number, -- turret (or casemate gun) traverse speed at crew level 100
	viewRangeM: number, -- base view range before class factor, crew, equipment
	hpBonus: number, -- added to hull HP
	guns: { ModuleId }, -- guns this turret can mount (>= 1)
	--- Traverse limits as positive magnitudes from hull-forward: `left` counter-clockwise, `right` clockwise
	--- (degrees, 0..180). nil = 360°; casemate default ±11.
	yawLimitsDeg: { left: number, right: number }?,
	visual: TurretVisual,
}

export type EngineFuel = "Petrol" | "Diesel" | "Turbine"
--- Engine sound families present in assets/audio/engines (audio.md §5.1).
export type EngineAudioFamily =
	"heavy_diesel"
	| "medium_diesel"
	| "light_highrpm"
	| "large_v12"
	| "small_engine"
	| "turbine"
export type EngineDefinition = {
	id: ModuleId,
	kind: "Engine",
	name: string,
	tier: Tier,
	massKg: number,
	priceCredits: number,
	researchXp: number,
	powerHp: number,
	fuel: EngineFuel,
	fireChance: number?, -- chance per engine hit; default Petrol 0.20, Diesel 0.12, Turbine 0.15
	audio: EngineAudioFamily,
	visual: { exhausts: number?, exhaustPlacement: ("Rear" | "Sides" | "Deck")? }?,
}

export type TrackLinkStyle = "Plain" | "Grousered" | "Rubber" | "Chevron"
export type TracksDefinition = {
	id: ModuleId,
	kind: "Tracks",
	name: string,
	tier: Tier,
	massKg: number,
	priceCredits: number,
	researchXp: number,
	loadLimitKg: number, -- total vehicle mass (hull + all mounted modules incl. these tracks) must not exceed it
	traverseDegS: number, -- hull traverse at crew level 100
	terrainResistance: TerrainResistance, -- hard <= medium <= soft
	armorMm: number, -- track/wheel thickness (spaced armor; Blueprint "Track" zone)
	bloomMul: number?, -- × movement/hull-traverse bloom (default 1)
	wheeled: boolean?, -- wheels instead of tracks (requires the Wheeled mechanic)
	visual: { trackWidthM: number?, linkStyle: TrackLinkStyle? }?,
}

export type ModuleDefinition = GunDefinition | TurretDefinition | EngineDefinition | TracksDefinition

--------------------------------------------------------------------------------
-- Vehicles
--------------------------------------------------------------------------------

export type Configuration = { gun: ModuleId, turret: ModuleId, engine: ModuleId, tracks: ModuleId }
--- A researchable module on this vehicle. `requires` = modules (of this vehicle) that must be researched first.
--- Default WoT order: Tracks(top) -> Turret(top) -> Gun(top); Engine independent (03-R4).
export type ModuleNode = { module: ModuleId, requires: { ModuleId }? }
--- Tech-tree edge from this vehicle to `vehicle` (same faction, same or next tier). `requires` = module of THIS
--- vehicle that must be researched first (usually the top gun). The XP cost is the target's researchXp.
export type VehicleUnlock = { vehicle: VehicleId, requires: ModuleId? }
--- Flattened edge returned by ContentRegistry:techTreeEdges().
export type TechTreeEdge = { from: VehicleId, to: VehicleId, requires: ModuleId?, xp: number }
--- One crew seat. `also` = secondary duties of the same person (small crews double up; never Commander).
export type CrewSlot = { role: CrewRole, also: CrewRoles? }

--- Nominal plate thickness (mm) by hull zone. Effective thickness comes from the plate angles in HullVisual.
export type HullArmor = {
	upperFront: number,
	lowerFront: number,
	side: number,
	rear: number,
	roof: number,
	floor: number,
	engineDeck: number?, -- default = roof
	superstructureFront: number?, -- required when HullVisual.superstructure is set
	superstructureSide: number?,
	skirts: number?, -- spaced side skirts (required when HullVisual.skirts ~= "None")
}
export type HullDefinition = { hp: number, massKg: number, armor: HullArmor }
export type MobilityDefinition = {
	forwardKmh: number, -- top speed (set by the hull; modules never change it, 03 §3.3)
	reverseKmh: number?, -- default clamp(0.35 × forward, 12, 25)
	pivot: boolean?, -- neutral steer (default true for tracks, false for wheels)
}
--- Per-yaw gun-arc limits (rear deck etc.). Yaw is the turret bearing relative to the hull, 0 = forward,
--- positive = clockwise (right), in (−180, 180]. A sector is swept CLOCKWISE from fromDeg to toDeg, so
--- { fromDeg = 150, toDeg = -150 } is the 60° rear sector through 180 and { fromDeg = -150, toDeg = 150 } is the 300°
--- around the front. fromDeg ~= toDeg. Within a sector the gun's arcs are capped (a sector never widens them).
export type ArcSector = { fromDeg: number, toDeg: number, depressionDeg: number?, elevationDeg: number? }

--- "Casemate" = the whole hull is the fighting compartment of a casemate TD/SPG (no superstructure needed); it
--- is used only with Casemate gun mounts, and a Casemate mount needs this style or a `superstructure` (MOUNT).
export type HullStyle = "Boxy" | "Stepped" | "Sloped" | "Pike" | "Rounded" | "Wedge" | "Slab" | "Casemate" | "LowProfile"
--- Turret ring placement on this hull (a turret module may be shared by hulls with different rings).
export type TurretRingSpec = {
	positionFraction: number, -- 0 = front plate, 1 = rear plate (ring centre along the hull length)
	diameterM: number,
	heightOffsetM: number?, -- ring above the hull roof (default 0)
}
--- Raised superstructure / casemate box on top of the hull (casemate TDs, SPG fighting compartments). It is part
--- of the Hull group (zones SuperstructureFront/Side, HullArmor.superstructure*); a Casemate gun mount sits in its
--- front plate.
export type SuperstructureVisual = {
	lengthM: number,
	heightM: number,
	positionFraction: number, -- centre along the hull (0 front .. 1 rear)
	frontAngleDeg: number,
	sideAngleDeg: number?,
}
export type HullVisual = {
	lengthM: number, -- overall hull length (front to rear plate)
	widthM: number, -- overall width across the outer track edges (vehicle footprint)
	heightM: number, -- hull roof above the ground (ground clearance + hull body)
	groundClearanceM: number,
	style: HullStyle,
	upperFrontAngleDeg: number, -- upper glacis slope from vertical
	lowerFrontAngleDeg: number,
	upperFrontFraction: number, -- share of the front height taken by the upper plate (0..1)
	rearAngleDeg: number?,
	sideSlopeDeg: number?, -- sponson/side slope from vertical (default 0)
	turretRing: TurretRingSpec,
	superstructure: SuperstructureVisual?,
	engineDeck: "Flat" | "Raised" | "Louvered",
	fenders: boolean,
	skirts: "None" | "Plates" | "Mesh" | "Full",
	sponsons: boolean?, -- hull body widens over the tracks (default false)
}
export type SuspensionStyle = "Torsion" | "Christie" | "Bogie" | "Leaf" | "Hydro" | "Wheeled"
export type RunningGearVisual = {
	roadWheels: number, -- per side (wheel pairs = roadWheels for wheeled vehicles)
	wheelDiameterM: number,
	returnRollers: number,
	sprocket: "Front" | "Rear",
	trackWidthM: number, -- default when the tracks module has no visual override
	suspension: SuspensionStyle,
}
--- Decorative details (LOD0/LOD1 only; never armor). All optional, default 0/false.
export type DetailVisual = {
	exhausts: number?,
	antennas: number?,
	toolboxes: number?,
	spareTracks: boolean?,
	fuelDrums: number?,
	smokeDischargers: boolean?,
	headlights: number?,
	towCables: boolean?,
	jerrycans: number?,
	machineGun: boolean?,
	stowage: boolean?,
	logs: boolean?,
	camoNet: boolean?,
}
export type AmmoRackPlacement = "Turret" | "Bustle" | "HullFront" | "HullMiddle" | "Sponsons" | "Floor"
--- Explicit internal volume (overrides a preset): centre/size in metres in hull or turret space (same axes as the
--- ArmorModel: -Z forward, +Y up; hull origin = footprint centre at ground level, turret origin = ring centre).
export type InternalVolumeSpec = {
	kind: InternalModuleKind,
	group: "Hull" | "Turret",
	centerM: Vector3,
	sizeM: Vector3,
}
--- Explicit crew seat (overrides the preset placement of one seat). `centerM` is in metres in the space of `group`
--- (default: "Hull" for the Driver and for casemate vehicles, "Turret" otherwise, so turret crew turn with the
--- turret). The Driver always sits in the hull, and casemate vehicles have no turret seats (LAYOUT).
export type CrewSeatSpec = { slot: number, centerM: Vector3, group: ("Hull" | "Turret")? }
--- Where the internal modules sit. The Blueprint turns presets into module volumes; crew seats follow the crew
--- roles (driver hull-front, gunner/commander/loader in the turret, or all in the hull for casemates). Weak
--- points emerge from this layout (front transmission behind the lower plate, bustle racks, side fuel…).
export type InternalLayout = {
	engine: "Rear" | "Front" | "Middle",
	transmission: "Front" | "Rear",
	ammoRacks: { AmmoRackPlacement }, -- 1..3
	fuel: "Rear" | "Front" | "Sides" | "Middle",
	optics: ("Cupola" | "TurretRoof" | "HullRoof")?, -- default Cupola for turreted, HullRoof for casemates
	overrides: InternalVolumes?,
	crewSeats: CrewSeats?, -- explicit crew seats, each slot at most once
}
export type VehiclePalette = { base: Color3?, secondary: Color3?, accent: Color3? }
--- Everything the Blueprint needs besides module visuals (turret/gun/tracks/engine carry their own).
export type VisualSpec = {
	hull: HullVisual,
	running: RunningGearVisual,
	details: DetailVisual?,
	layout: InternalLayout,
	palette: VehiclePalette?, -- nil = faction vehiclePaint
	preset: string?, -- Blueprint shape grammar (nil = FactionDefinition.builderPreset)
	--- Named silhouette features the preset knows how to build ("pike_nose", "drum_bulge", "sunshade_frame"…;
	--- roster.md "visual hook" column). snake_case keys owned by the Blueprint; unknown keys are ignored by it.
	hooks: { string }?,
}

--- Vehicle mechanics (00-DECISIONS §4). Placement: VehicleSim runs SiegeMode, Hydropneumatic, Wheeled, Turbo,
--- RocketBoost, ReserveTracks; GunState runs ChargedShot, ActiveCooling, AdaptiveMagazine (Magazine/Autoreloader/
--- DualGun are gun reload kinds). Turbo, RocketBoost, ChargedShot, ActiveCooling, AdaptiveMagazine and ReserveTracks
--- are Tier XI signatures only (or Event vehicles); ReserveTracks is not assigned to any launch Apex.
export type SpecialMechanic =
	{
		kind: "SiegeMode",
		engageS: number, -- 2.0
		disengageS: number, -- 1.25
		maxSpeedKmh: number, -- 10 while sieged
		autoEngageS: number?, -- player option: engage after this long stationary (0.5)
		travelReverseRatio: number?, -- travel-mode reverse = forward × ratio (0.9)
		modifiers: { StatModifier }, -- applied while sieged (aim ×0.4, dispersion ×0.85, depression +8 …)
	}
	| {
		kind: "Hydropneumatic",
		depressionBonusDeg: number,
		elevationBonusDeg: number,
		settleS: number,
	}
	| {
		--- Needs wheeled tracks (TracksDefinition.wheeled), RunningGearVisual.suspension "Wheeled" with
		--- roadWheels = wheelPairs, and no neutral steer (mobility.pivot ~= true) (MECHANIC).
		kind: "Wheeled",
		wheelPairs: number, -- per side; = visual.running.roadWheels
		speedModeTopSpeedMul: number, -- 1.30
		speedModeSteeringMul: number, -- 0.60
		speedModeReverseMul: number, -- 0.70
		toggleS: number, -- 1.0
		--- × top speed per destroyed wheel SIDE (TrackLeft / TrackRight module: a side holds all its wheel pairs,
		--- one HP pool); wheel damage never immobilises a wheeled vehicle.
		lostPairSpeedMul: number, -- 0.75
		movingDispersionMul: number, -- 1.15
		turnRadiusM: number,
	}
	| { kind: "Turbo", powerMul: number, durationS: number, cooldownS: number }
	| {
		kind: "RocketBoost",
		charges: number,
		durationS: number,
		speedBonusKmh: number,
		cooldownS: number,
	}
	| {
		--- Rides the fire trigger (hold to charge), so every gun of the vehicle must be a Single reload gun (a
		--- DualGun volley and a magazine burst would fight over the same trigger; MECHANIC).
		kind: "ChargedShot",
		chargeTimeS: number,
		effect: "Accuracy" | "Damage",
		dispersionMul: number?, -- effect Accuracy (0.6)
		damageMul: number?, -- effect Damage (1.10)
	}
	| {
		kind: "ActiveCooling",
		durationS: number,
		cooldownS: number,
		modifiers: { StatModifier },
	}
	| { kind: "AdaptiveMagazine", partialReloadFactor: number } -- reload scales with shells missing
	| {
		kind: "ReserveTracks",
		charges: number, -- destroyed tracks replaced automatically, per battle
		repairS: number, -- time from destroyed to working again (instead of the field repair)
		cooldownS: number, -- between uses
	}
export type MechanicKind =
	"SiegeMode"
	| "Hydropneumatic"
	| "Wheeled"
	| "Turbo"
	| "RocketBoost"
	| "ChargedShot"
	| "ActiveCooling"
	| "AdaptiveMagazine"
	| "ReserveTracks"

--- Tier XI upgrade track (replaces modules and Field Kits; 00-DECISIONS §11: 6 small, 3 large, 1 final).
export type ApexNode = {
	id: string,
	name: string,
	kind: "Small" | "Large" | "Final",
	xp: number,
	effects: { StatModifier },
}
export type ApexTrack = { nodes: { ApexNode } }

--- Slot overrides (defaults: TierDefinition.equipmentSlots/consumableSlots, RoleDefinition.categorySlot from VI).
--- `categorySlot` overrides the role's category and is only legal from Tier VI (the slot exists from VI).
export type VehicleSlots = { equipment: number?, consumables: number?, categorySlot: EquipmentCategory? }
--- Economy overrides (defaults: tier economy; premiums use TierEconomy.premiumCreditMul and crew XP ×1.5).
export type VehicleEconomy = { creditMul: number?, xpMul: number?, crewXpMul: number?, repairMul: number? }
--- Tech-tree layout: column = tier, `row` = vertical lane within the faction tree (unique per faction+tier for
--- tech-tree vehicles). Premium/reward vehicles sit in the faction's side panel and ignore `row` collisions.
export type TreePosition = { row: number, branch: BranchId? }

--- A named line of a faction's tech tree (TechTree.luau). Vehicles join a branch through `tree.branch`; research
--- edges stay on the vehicles (`unlocks`), so the branch only carries identity and layout.
export type BranchDefinition = {
	id: BranchId,
	faction: FactionId,
	name: string, -- "Bulwark heavy line"
	description: string, -- identity line (roster.md branch tables)
	classes: { VehicleClass }, -- classes its vehicles may have
	tiers: Range, -- full design range
	row: number, -- fixed tech-tree lane (roster.md §2.11; 2 = the spine); its tech-tree vehicles sit on this row
}

export type VehicleDefinition = {
	id: VehicleId, -- "<faction idPrefix>_<name>"; never equal to a BranchId
	name: string, -- full designation (<= 32 chars)
	shortName: string, -- markers / kill feed (<= 12 chars, REG-MRK-03)
	faction: FactionId,
	tier: Tier,
	class: VehicleClass,
	role: RoleId, -- must belong to `class`
	acquisition: Acquisition,
	description: string, -- garage blurb (1-2 sentences)
	lore: string, -- original fictional history (never a real-world unit or conflict)
	strengths: { string }, -- 1..4
	weaknesses: { string }, -- 1..4
	hull: HullDefinition,
	mobility: MobilityDefinition,
	camouflage: CamoSpec?, -- nil = class default (casemate default for casemate TDs)
	crew: { CrewSlot }, -- 2..6 seats, exactly one Commander; Gunner, Driver and Loader duties covered
	modules: { guns: { ModuleId }, turrets: { ModuleId }, engines: { ModuleId }, tracks: { ModuleId } },
	stock: Configuration, -- what the vehicle arrives with
	--- Fully upgraded configuration (balance lint, Compare "top"): in every slot where the vehicle lists a
	--- researchable module, top mounts one of them, not the stock module (CONFIG_INVALID warning).
	top: Configuration,
	moduleTree: { ModuleNode }, -- every non-stock module exactly once
	unlocks: { VehicleUnlock },
	researchXp: number?, -- tech tree tier >= II only
	price: Price, -- tech tree: credits (tier I = 0); premium: bullion; reward/event: {}
	arcSectors: { ArcSector }?,
	slots: VehicleSlots?,
	mechanics: Mechanics?,
	apex: ApexTrack?, -- Tier XI only (required there)
	visual: VisualSpec,
	audio: { engine: EngineAudioFamily? }?, -- override of the engine module's family
	economy: VehicleEconomy?,
	tree: TreePosition,
	icon: IconKey?, -- default "vehicles/<id>" (tech-tree silhouette rendered from the blueprint)
	balanceException: string?, -- reason a stat may leave the [0.92, 1.08] lint envelope
	hidden: boolean?, -- not shown in tree/store (testing, retired)
	tags: { string }?,
}

--------------------------------------------------------------------------------
-- Loadout items
--------------------------------------------------------------------------------

export type EquipmentDefinition = {
	id: EquipmentId,
	name: string,
	description: string,
	icon: IconKey, -- "equipment/<file>"
	categories: { EquipmentCategory }, -- 1..4; the category slot bonus applies when any matches
	grade: "Standard" | "Refined", -- Refined ≈ 1.2 × effect, Campaign Tokens only
	tiers: Range, -- mountable tier band inside ONE TierDefinition.equipmentBand (C: II–IV, B: V–VII, A: VIII–XI)
	exclusiveGroup: string, -- at most one item per group per vehicle (same family; lenses vs mast)
	effects: { StatModifier },
	categorySlotEffects: Modifiers?, -- explicit category-slot values; default each delta × 1.15
	effectsByClass: { [VehicleClass]: { StatModifier } }?, -- class-scaled items (camo net) replace `effects`
	compatibility: {
		classes: VehicleClasses?,
		roles: RoleIds?,
		requiresTurret: boolean?,
		minMassKg: number?, -- <= maxMassKg
		maxMassKg: number?,
		excludeMechanics: MechanicKinds?,
		excludeReload: ReloadKinds?, -- e.g. rammers do not fit Magazine guns
	}?,
	price: Price, -- credits or campaign tokens; never Bullion-only (00-DECISIONS §13)
}

--- "Smoke" is event-only (no smoke in Random battles, 00-DECISIONS §5): a Smoke consumable sets eventOnly = true.
export type ConsumableKind = "RepairKit" | "MedKit" | "Extinguisher" | "Ration" | "Fuel" | "Smoke" | "Utility"
export type ConsumableDefinition = {
	id: ConsumableId,
	name: string,
	description: string,
	icon: IconKey, -- "consumables/<file>"
	kind: ConsumableKind,
	--- Manual = player activates (cooldown); Automatic = triggers itself (`triggerDelayS` after the event);
	--- Passive = active the whole battle (rations, fuel).
	activation: "Manual" | "Automatic" | "Passive",
	cooldownS: number?, -- required for Manual/Automatic (reusable within a battle)
	charges: number?, -- uses per battle (nil = unlimited: reusable whenever the cooldown allows; Manual/Automatic)
	durationS: number?, -- for timed `effects` (required when a Manual/Automatic item has `effects`)
	triggerDelayS: number?, -- Automatic only (auto extinguisher 0.5)
	repairs: { modules: boolean?, crew: boolean?, fire: boolean?, stun: boolean? }?,
	stunImmunityS: number?, -- after a medkit clears stun (5)
	effects: Modifiers?, -- while active (durationS) or for the battle (Passive)
	passiveEffects: Modifiers?, -- while merely mounted (large kits: +10 % repair speed)
	exclusiveGroup: string, -- one per group per vehicle (repair, medical, fire, ration, fuel)
	tiers: Range?,
	classes: VehicleClasses?,
	eventOnly: boolean?, -- event-mode consumables (smoke)
	--- Always carries a credit price (resupply is charged once per battle if used, 00-DECISIONS §13); an optional
	--- Bullion price never undercuts it at 1 Bullion = 200 credits (PRICE).
	price: Price,
}

export type CrewSkillDefinition = {
	id: CrewSkillId,
	name: string,
	description: string,
	icon: IconKey,
	roles: { CrewRole }, -- roles that may learn it
	--- Individual = works from the learning member; Group = scales with the share of crew members who learned it
	--- (Brothers in Arms, Field Repairs, Concealment). Works from 1 % training, linear (00-DECISIONS §12).
	kind: "Individual" | "Group",
	effects: { StatModifier }, -- at 100 % training
}
export type CrewBookDefinition = {
	id: CrewBookId,
	name: string,
	description: string,
	icon: IconKey,
	xpPerMember: number, -- 5,000 / 25,000 / 60,000
	price: Price?, -- nil = not sold (missions, pass, events)
}
export type BoosterDefinition = {
	id: BoosterId,
	name: string,
	description: string,
	icon: IconKey,
	target: "VehicleXP" | "FreeXP" | "CrewXP" | "Credits",
	multiplier: number, -- e.g. 1.5
	durationS: number?, -- real-time duration once activated
	battles: number?, -- or a number of battles
	price: Price?,
}

--------------------------------------------------------------------------------
-- Cosmetics
--------------------------------------------------------------------------------

--- Paint/Camouflage colour the hull; Emblem/Inscription/Decal are projected marks; Attachment = 3-D add-ons (nets,
--- stowage, antennas: never armor, never gameplay); Effect = cosmetic shot/tracer/destruction effects; Style = a
--- full set that replaces paint + camouflage; GunSleeve/StatTracker = barrel marks and the kill counter.
export type CustomizationKind =
	"Paint"
	| "Camouflage"
	| "Emblem"
	| "Inscription"
	| "Decal"
	| "Attachment"
	| "Effect"
	| "Style"
	| "GunSleeve"
	| "StatTracker"
export type CustomizationDefinition = {
	id: CustomizationId,
	name: string,
	description: string?,
	icon: IconKey,
	kind: CustomizationKind,
	rarity: Rarity,
	colors: { Color3 }?, -- paint / camouflage / style colours (required for Paint and Camouflage)
	pattern: string?, -- camouflage pattern, decal or attachment model key (renderer)
	camoBonus: boolean?, -- grants the flat paint camo bonus (Config.Spotting; 0 in ranked)
	scope: { factions: FactionIds?, classes: VehicleClasses?, vehicles: { VehicleId }? }?,
	source: "Store" | "Mission" | "Pass" | "Event" | "Achievement",
	price: Price?,
}

--------------------------------------------------------------------------------
-- Missions, achievements, rewards
--------------------------------------------------------------------------------

--- Per-battle stats that missions/achievements count: every numeric/boolean Types/Battle BattleStats counter
--- (booleans count 1/0) plus battles, wins, xp, medals and the derived totals damageDealtPlusBlocked,
--- assistTotal (spotting + tracking + stun) and damagePlusAssist. Battle Hero rules read the hit/spot counters
--- (Steel Wall: hitsReceived, Patrol Duty: soleSpotterDamaged, Confederate: hitsOnLaterKilled).
export type BattleStatKey =
	"battles"
	| "wins"
	| "survived"
	| "xp"
	| "teamXpRank" -- 1 = best on the team; use atMost
	| "roleScore" -- normalised Role Score (1.0 = class × tier median); SingleBattle only
	| "damageDealt"
	| "damageBlocked"
	| "damageDealtPlusBlocked"
	| "damageReceived"
	| "potentialDamageReceived"
	| "assistSpotting"
	| "assistTracking"
	| "assistStun"
	| "assistTotal"
	| "damagePlusAssist"
	| "stuns"
	| "kills"
	| "spotted"
	| "shotsFired"
	| "hits"
	| "penetrations"
	| "criticalHits"
	| "hitsReceived"
	| "penetrationsReceived"
	| "ricochetsReceived"
	| "nonPensReceived"
	| "capturePoints"
	| "defensePoints"
	| "ramDamageDealt"
	| "firesStarted"
	| "distanceM"
	| "timeAliveS"
	| "firstBlood"
	| "firstContactDamage"
	| "soleSpotterDamaged"
	| "hitsOnLaterKilled"
	| "medals"
--- `teamXpRank` is a per-battle rank: SingleBattle with atMost only; `roleScore` is SingleBattle only. `against`
--- narrows damageDealt, kills, spotted, assistTotal and damagePlusAssist to enemies of these classes
--- (BattleStats.byTargetClass). `medal` narrows stat "medals" to one BattleMedal achievement ("earn Steel Wall").
export type MissionCondition = {
	stat: BattleStatKey,
	atLeast: number?, -- one of atLeast / atMost is required
	atMost: number?,
	aggregate: "SingleBattle" | "Cumulative",
	against: { classes: VehicleClasses? }?, -- only count the stat against enemies of these classes
	medal: AchievementId?, -- stat "medals" only: count this BattleMedal achievement only
}
export type MissionCadence = "Daily" | "Weekly" | "Campaign" | "Event" | "Tutorial" | "Special"
export type MissionScope = {
	classes: VehicleClasses?,
	roles: RoleIds?,
	minTier: Tier?,
	maxTier: Tier?,
	factions: FactionIds?,
	vehicles: { VehicleId }?,
	modes: BattleModes?, -- default { "Random" }
	battleTypes: BattleTypes?,
	maps: { MapId }?,
	excludeBotHeavy: boolean?, -- ignore battles with > 50 % bots (00-DECISIONS §8)
}
export type RewardKind =
	"Credits"
	| "Bullion"
	| "FreeXP"
	| "CrewXP"
	| "CampaignTokens"
	| "EventTokens" -- id = EventId
	| "PremiumDays"
	| "PassPoints"
	| "Equipment"
	| "Consumable"
	| "Vehicle"
	| "Customization"
	| "Booster"
	| "CrewBook"
--- `id` is required for item kinds (Equipment, Consumable, Vehicle, Customization, Booster, CrewBook, EventTokens).
export type Reward = { kind: RewardKind, id: string?, amount: number }
export type CampaignSeries = "Assault" | "Overwatch" | "Support"
export type MissionDefinition = {
	id: MissionId,
	name: string,
	description: string,
	icon: IconKey?,
	cadence: MissionCadence,
	difficulty: ("Easy" | "Medium" | "Hard" | "Bonus")?, -- required for Daily, never set on other cadences
	match: "All" | "Any", -- how `conditions` combine
	conditions: { MissionCondition },
	requireWin: boolean?,
	requireSurvive: boolean?,
	scope: MissionScope?,
	rewards: { Reward },
	scaleRewardsByTier: boolean?, -- daily credits scale with the player's top owned tier
	honors: { match: "All" | "Any", conditions: { MissionCondition }, rewards: { Reward } }?, -- "with honors"
	campaign: { campaignId: CampaignId, operation: number, series: CampaignSeries, index: number }?,
	eventId: EventId?, -- required for cadence Event
	weight: number?, -- random-pool weight for Daily/Weekly assignment (default 1)
}

export type AchievementCategory =
	"BattleHero"
	| "Epic"
	| "Mastery"
	| "Marks"
	| "Milestone"
	| "Series"
	| "Event"
	| "Commemorative"
export type AchievementKind = "BattleMedal" | "Milestone" | "Streak" | "Mastery" | "Marks"
export type AchievementDefinition = {
	id: AchievementId,
	name: string,
	description: string,
	icon: IconKey,
	category: AchievementCategory, -- kind Mastery <=> category Mastery, kind Marks <=> category Marks
	kind: AchievementKind,
	--- Evaluator key implemented in Shared/Progression/Achievements (e.g. "mostOnTeam", "threshold", "lastStand");
	--- `stat` names the battle stat it reads and `params` its numeric arguments (e.g. { min = 6 }).
	rule: string,
	stat: BattleStatKey?, -- the stat the rule reads (when it reads one)
	params: { [string]: number }?,
	thresholds: { number }?, -- tiered milestones, strictly increasing (required for kind Milestone and Streak)
	perVehicle: boolean?, -- true for kind Mastery / Marks (progress lives in VehicleCareerStats)
	repeatable: boolean?, -- medals counted every time
	scope: { minTier: Tier?, maxTier: Tier?, modes: BattleModes?, pvpOnly: boolean? }?, -- pvpOnly: botShare <= 0.5
	rarity: Rarity,
	rewards: { Reward }, -- {} when none
	hidden: boolean?,
}

--------------------------------------------------------------------------------
-- Maps (00-DECISIONS §10, 04-R8)
--------------------------------------------------------------------------------

export type TerrainNoise = { scaleM: number, amplitudeM: number }
export type TerrainFeatureKind =
	"Hill"
	| "Ridge"
	| "Valley"
	| "Plateau"
	| "Cliff"
	| "Riverbed"
	| "Crater"
	| "Flatten"
	| "Road"
	| "Dune"
export type TerrainFeature = {
	kind: TerrainFeatureKind,
	points: { Vec2 }, -- 1 point = round feature, >= 2 = along a polyline
	radiusM: number,
	heightM: number, -- relative (negative carves)
	falloff: number?, -- 0..1 edge softness (default 0.5)
}
--- Terrain materials (Enum.Material names) allowed in recipes; movement maps them to hard/medium/soft (§6).
export type TerrainMaterial =
	"Grass"
	| "LeafyGrass"
	| "Ground"
	| "Mud"
	| "Sand"
	| "Sandstone"
	| "Rock"
	| "Basalt"
	| "Slate"
	| "Snow"
	| "Glacier"
	| "Ice"
	| "Concrete"
	| "Asphalt"
	| "Pavement"
	| "Cobblestone"
	| "Brick"
	| "Pebble"
	| "Limestone"
	| "Salt"
export type MaterialRule = {
	material: TerrainMaterial,
	rule: "Default" | "Slope" | "Height" | "Feature",
	min: number?, -- Slope: degrees; Height: metres above baseHeightM
	max: number?,
	feature: TerrainFeatureKind?, -- rule Feature: paint the footprint of this feature kind (roads, riverbeds…)
}
export type TerrainRecipe = {
	seed: number,
	baseHeightM: number,
	noise: { TerrainNoise },
	features: { TerrainFeature },
	materials: { MaterialRule }, -- first matching rule wins; exactly one "Default"
	waterLevelM: number?,
}
export type SpawnPoint = { at: Vec2, facingDeg: number, rear: boolean? } -- facing: 0 = north (-z), clockwise
--- 15 slots per team, >= 3 flagged `rear` (SPG/TD), centroids >= 0.7 × sizeM apart (00-DECISIONS §10).
export type MapSpawns = { team1: { SpawnPoint }, team2: { SpawnPoint } }
--- Capture circle. Standard: one per team (`team` = owner); Encounter: one neutral (team nil); Assault: the
--- defender's base (`team` = defending team). >= 60 m inside the boundary.
export type CaptureBase = { id: string, battleType: BattleType, team: number?, center: Vec2, radiusM: number? }
export type LaneKind = "Heavy" | "Flex" | "Open"
export type Lane = { id: string, kind: LaneKind, points: { Vec2 }, widthM: number }
export type FoliageKind = "LightBush" | "DenseBush" | "Hedgerow" | "TreeCrown" | "FelledTree" | "Thicket"
--- Analytic concealment volume used by Spotting (never engine geometry): a sphere at `at`, or a capsule from
--- `at` to `to`, centred `heightM` above the ground. Concealment default by kind (Config.Spotting).
export type FoliageVolume = {
	kind: FoliageKind,
	at: Vec2,
	to: Vec2?,
	heightM: number,
	radiusM: number,
	concealment: number?,
}
--- Tactical points for bots, minimap hints and map QA (00-DECISIONS §10: >= 3 hull-down spots per side on the
--- Flex lane). HullDown = ridge/reverse slope for MT/HT; Brawl = hard cover for close fights; Sniper = long
--- sightline for TD/MT snipers; Scout = passive-spotting bush for LT; Flank = route waypoint for flankers;
--- Artillery = SPG firing pit in the rear band.
export type MapPositionKind = "HullDown" | "Brawl" | "Sniper" | "Scout" | "Flank" | "Artillery"
export type MapPosition = {
	id: string,
	kind: MapPositionKind,
	at: Vec2,
	facingDeg: number, -- where the position looks (0 = north (-z), clockwise)
	team: number?, -- 1 or 2 = that team's side; nil = contested (does not count toward a side's minimum)
	lane: string?, -- Lane.id it belongs to
	classes: VehicleClasses?, -- classes that should use it (nil = the kind's usual classes)
}
export type DestructibleClass = "Light" | "Medium" | "Heavy" | "Permanent"
--- Builder prop. Bridges, large buildings and rocks are props with `destructible = "Permanent"` (structures: ground
--- under them comes from World:raycast, not the heightfield).
export type PropPlacement = {
	prop: PropKind,
	at: Vec2,
	rotationDeg: number?,
	scale: number?,
	variant: number?,
	destructible: DestructibleClass?, -- default from the prop kind
}
export type WaterBody = { id: string, points: { Vec2 }, surfaceHeightM: number, depthM: number }
--- Cosmetic lighting/weather variant (no gameplay weather).
export type MapVariant = { id: string, lighting: string, weather: string, weight: number }
--- Reserved hook for WoT-2.0-style layout events (none at launch; every state must pass the map validators).
export type MapRandomEvent = { id: string, chance: number, props: { PropPlacement } }
export type MapDefinition = {
	id: MapId,
	name: string,
	description: string,
	biome: Biome,
	sizeM: number, -- playable square side (1000; 800 city / Tier I–III pool)
	skirtM: number?, -- non-playable scenery beyond the red line (default 150)
	tierRange: Range,
	battleTypes: { BattleType },
	modes: { BattleMode },
	terrain: TerrainRecipe,
	spawns: MapSpawns,
	bases: { CaptureBase },
	lanes: { Lane }, -- at least one Heavy, one Flex and one Open
	positions: { MapPosition }, -- per team: >= 3 HullDown, >= 1 Sniper, >= 1 Scout (+ >= 1 Artillery when SPGs play)
	foliage: { FoliageVolume },
	props: { PropPlacement },
	water: { WaterBody }?,
	variants: { MapVariant }, -- >= 1
	randomEvents: MapRandomEvents?,
	audio: { ambience: SoundKey, music: SoundKey? },
	thumbnail: IconKey?, -- loading screen / map picker image
	--- Top-down minimap image covering the playable square (north up, tools pipeline). nil = the client renders the
	--- minimap from the terrain recipe; either way the A–K × 1–0 grid is derived from sizeM.
	minimap: IconKey?,
	tips: { string },
	revision: number, -- bump on every geometry change (map content hash, REG-MAP-07)
}

--------------------------------------------------------------------------------
-- Store and live events (data-driven; implementation lives in services)
--------------------------------------------------------------------------------

export type StoreItemKind =
	"BullionPack"
	| "PremiumTime"
	| "PremiumVehicle"
	| "Bundle"
	| "Customization"
	| "CrewBook"
	| "Consumable"
	| "Booster"
	| "SeasonPass"
--- Robux-priced items name a Roblox product; the client shows GetProductInfoAsync prices (Managed Pricing).
--- A GamePass is owned once per account, so only an item with purchaseLimit = 1 may use one (STORE); everything
--- bought repeatedly (Bullion, Premium Time, pass seasons) is a DeveloperProduct.
export type RobuxProduct = { kind: "DeveloperProduct" | "GamePass", productId: number }
--- Fixed grants only: no paid random items, ever (00-DECISIONS §15).
export type StoreItem = {
	id: StoreItemId,
	name: string,
	description: string,
	icon: IconKey?,
	kind: StoreItemKind,
	price: Price?, -- in-game currency price (exactly one of price / robux)
	robux: RobuxProduct?,
	grants: { Reward },
	startsAt: number?, -- unix seconds (nil = always)
	endsAt: number?,
	purchaseLimit: number?, -- per account
	sortOrder: number?,
	featured: boolean?,
}

--- Ranked = a competitive season: an event whose mode carries a `ladder` (04 §1: Onslaught-style 7 v 7, seasonal).
export type EventKind = "Seasonal" | "Weekend" | "MedalHunt" | "Mode" | "Campaign" | "XpFever" | "Ranked"
export type EventModifiers = {
	xpMul: number?,
	creditMul: number?,
	freeXpMul: number?,
	crewXpMul: number?,
	firstWinMul: number?,
}
--- Mode-only abilities (never in Random battles or vehicle definitions; 00-DECISIONS §4).
export type EventAbility = {
	id: string,
	name: string,
	kind: "Airstrike" | "Smoke" | "Minefield" | "RepairZone" | "ReconFlight",
	cooldownS: number,
	charges: number?,
	radiusM: number?,
	durationS: number?,
	damage: number?,
	icon: IconKey?,
}
--- One step of a ranked ladder. Points carry over between ranks; a `protected` rank cannot be lost once reached.
export type LadderRank = { id: string, name: string, pointsToAdvance: number, protected: boolean?, rewards: Rewards? }
--- Ladder points per battle by team XP rank (ascending maxTeamRank; the last rule covers the rest; loss may be < 0).
export type LadderPointsRule = { maxTeamRank: number, win: number, loss: number }
--- Ranked/competitive progression of an event mode (season = the event window). The player's rank and points
--- live in Profile.events[eventId].ranked.
export type RankLadder = {
	ranks: { LadderRank }, -- lowest first; the last rank has pointsToAdvance 0 (top of the ladder)
	points: { LadderPointsRule },
	finalRewards: Rewards?, -- granted at season end by the highest rank reached (per-rank `rewards` on promotion)
}
export type EventModeDefinition = {
	id: string,
	name: string,
	baseMode: BattleMode,
	teamSize: number,
	maps: { MapId },
	tierRange: Range?,
	vehicles: { VehicleId }?, -- rental/event vehicles (nil = own garage)
	abilities: EventAbilities?,
	respawns: number?,
	durationS: number?,
	battleTypes: BattleTypes?, -- objective types this mode plays (default { "Standard" }); maps must have their bases
	--- Competitive rules: Config.Combat COMPETITIVE_SPREAD (±10 % rolls), no paint camo bonus, no SPG, labelled
	--- bots never fill, > 50 % bot battles never count (00-DECISIONS §1, §5, §8).
	competitive: boolean?,
	--- Per-team class limits overriding Config.Matchmaking (0 = banned); a competitive mode never allows artillery.
	classCaps: { [VehicleClass]: number }?,
	ladder: RankLadder?, -- required for EventKind "Ranked"
}
export type EventDefinition = {
	id: EventId,
	name: string,
	description: string,
	icon: IconKey?,
	kind: EventKind,
	startsAt: number, -- unix seconds
	endsAt: number,
	shopClosesAt: number?, -- default endsAt + 7 days
	missions: { MissionId },
	modifiers: EventModifiers?,
	modes: EventModes?,
	shop: { StoreItemId }?, -- items priced in this event's tokens
	tokenConversionCredits: number?, -- leftover tokens -> credits after the shop closes
}

export type PassTrack = "Free" | "Paid"
export type PassReward = { stage: number, track: PassTrack, rewards: { Reward } } -- Paid = fixed rewards only
export type PassChapter = {
	id: string,
	name: string,
	stages: number, -- 30
	pointsPerStage: number, -- 30
	rewards: { PassReward },
	finalReward: Rewards?,
}
--- Points per battle by team XP rank (00-DECISIONS §14: top 3 8/6, 4–10 6/4, rest 3/2).
export type PassPointsRule = { maxTeamRank: number, win: number, loss: number }
--- One Season Pass season. Seasons never overlap (Profile.pass tracks one seasonId at a time; SEASON).
export type SeasonDefinition = {
	id: SeasonId,
	name: string,
	startsAt: number,
	endsAt: number,
	chapters: { PassChapter },
	pointsByRank: { PassPointsRule }, -- ascending maxTeamRank; the last rule covers the rest of the team
	pointsPerDailyMission: number,
	paidUnlock: StoreItemId?, -- StoreItem of kind SeasonPass
}

--------------------------------------------------------------------------------
-- Authoring list aliases
--
-- Luau's strict checker cannot infer string-literal lists through an OPTIONAL field (`also: { CrewRole }?` given
-- `{ "Loader" }` infers `{ string }` and fails). Optional enum or tagged-table lists therefore use these aliases and
-- authors write a checked cast: `also = { "Loader" } :: Content.CrewRoles` (a typo inside still fails the type
-- check). Required lists need no cast.
--------------------------------------------------------------------------------

export type CrewRoles = { CrewRole }
export type Rewards = { Reward }
export type VehicleClasses = { VehicleClass }
export type RoleIds = { RoleId }
export type FactionIds = { FactionId }
export type BattleModes = { BattleMode }
export type BattleTypes = { BattleType }
export type Modifiers = { StatModifier }
export type Mechanics = { SpecialMechanic }
export type MechanicKinds = { MechanicKind }
export type ReloadKinds = { ReloadKind }
export type InternalVolumes = { InternalVolumeSpec }
export type CrewSeats = { CrewSeatSpec }
export type FieldKit = { FieldKitLevel }
export type EventModes = { EventModeDefinition }
export type EventAbilities = { EventAbility }
export type MapRandomEvents = { MapRandomEvent }

--------------------------------------------------------------------------------
-- Bundles
--------------------------------------------------------------------------------

--- Flat, fully-resolved content (what ContentRegistry indexes and what test fixtures are built from).
export type ContentBundle = {
	factions: { FactionDefinition },
	classes: { ClassDefinition },
	roles: { RoleDefinition },
	tiers: { TierDefinition },
	shells: { ShellDefinition },
	guns: { GunDefinition },
	turrets: { TurretDefinition },
	engines: { EngineDefinition },
	tracks: { TracksDefinition },
	vehicles: { VehicleDefinition },
	equipment: { EquipmentDefinition },
	consumables: { ConsumableDefinition },
	crewSkills: { CrewSkillDefinition },
	crewBooks: { CrewBookDefinition },
	boosters: { BoosterDefinition },
	customization: { CustomizationDefinition },
	missions: { MissionDefinition },
	achievements: { AchievementDefinition },
	maps: { MapDefinition },
	store: { StoreItem },
	events: { EventDefinition },
	seasons: { SeasonDefinition },
	branches: { BranchDefinition },
}

--- The Config/Content manifest: explicit registration lists. Multi-file kinds list one module per file
--- (each module returns a list; vehicles and maps return one definition per file).
export type ContentSources = {
	factions: { FactionDefinition },
	classes: { ClassDefinition },
	roles: { RoleDefinition },
	tiers: { TierDefinition },
	shells: { { ShellDefinition } },
	guns: { { GunDefinition } },
	turrets: { { TurretDefinition } },
	engines: { { EngineDefinition } },
	tracks: { { TracksDefinition } },
	vehicles: { VehicleDefinition },
	equipment: { EquipmentDefinition },
	consumables: { ConsumableDefinition },
	crewSkills: { CrewSkillDefinition },
	crewBooks: { CrewBookDefinition },
	boosters: { BoosterDefinition },
	customization: { CustomizationDefinition },
	missions: { MissionDefinition },
	achievements: { AchievementDefinition },
	maps: { MapDefinition },
	store: { StoreItem },
	events: { EventDefinition },
	seasons: { SeasonDefinition },
	branches: { BranchDefinition },
}

return {}
