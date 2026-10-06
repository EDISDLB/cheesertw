--!strict
--[[
	Vehicle/StatsCalculator — resolves a vehicle definition + configuration + loadout into the per-battle
	VehicleStats (docs/design/content-schema.md §7, docs/design/vehicle-stats.md), and keeps the RUNTIME view of
	those stats (module damage, crew injuries, stun, active consumables, mechanics, conditional modifiers) behind a
	dirty-flag cache for the 30 Hz battle loop.

	Purpose:          compute() is the ONE function the garage, the Hub (manifest preview) and the battle server use,
	                  so displayed stats equal battle stats (REG-CRW-01, REG-EQP-01). The runtime turns the
	                  battle-start values into effective numbers each tick and writes them into the owners' records
	                  (VehicleSim / TurretSim modifiers, GunState reload multiplier, Dispersion aim factors,
	                  Spotting view range / camo).
	Dependencies:     Config (Combat, Movement, Spotting; optional VehicleStats section, see DEFAULTS),
	                  Config/ContentRegistry (registry type + checkConfiguration), Core/Result, Core/Freeze,
	                  Net/ErrorCodes, Combat/DamageModel (module/crew HP), Combat/CrewEffects (crew curves),
	                  Combat/Ballistics (falloff default), Spotting/VisibilityModel (after-shot camo default),
	                  Vehicle/Modifiers, Types/*.
	State:            None at module level. compute() returns a new (deep-frozen by default) VehicleStats. A Runtime
	                  is a caller-owned record (one per vehicle) holding a Modifiers accumulator, condition flags,
	                  copied effect multipliers and the reused RuntimeStats output.
	Validation:       compute(): configuration via ContentRegistry:checkConfiguration (Err NOT_FOUND / INVALID_ARGS),
	                  loadout.vehicleId must match, every equipment / skill / consumable / Field Kit / Apex id must
	                  exist (Err NOT_FOUND). Items repeating an exclusiveGroup are skipped (checkLoadout rejects them
	                  upstream). Crew levels are clamped to [MIN_CREW_LEVEL, MAX_CREW_LEVEL]; HP rounds to whole HP.
	Error handling:   compute() returns Result (never throws on bad data). Runtime functions never throw.
	Performance notes: compute() allocates (once per vehicle per battle / garage change). Runtime update() is
	                  allocation-free: O(#conditional + #active modifiers) condition checks per tick, and a full
	                  recompute (~60 slot reads) only when a condition, an effect or an active list changed.

	Resolution order (per stat, content-schema §7): base from modules / vehicle / class / tier → crew curve of the
	duty that drives it (L from the loadout's crew snapshot + crewLevel modifiers) → every "Always" modifier:
	(base + Σ add) × Π mul. Modifier sources: equipment (category slot × (1 + CATEGORY_SLOT_BONUS) on each delta or
	`categorySlotEffects`), crew skills (Individual: average training of the members holding one of the skill's
	duties; Group: Σ training ÷ crew size; × crewPerkEfficiency), consumables (`passiveEffects` while mounted,
	`effects` of Passive items), Field Kit options, Apex nodes. Conditional modifiers are copied, already scaled,
	into VehicleStats.conditionalModifiers and evaluated by the runtime.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local ContentRegistryModule = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local Freeze = require("@game/ReplicatedStorage/Shared/Core/Freeze")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")
local DamageModel = require("@game/ReplicatedStorage/Shared/Combat/DamageModel")
local CrewEffects = require("@game/ReplicatedStorage/Shared/Combat/CrewEffects")
local Ballistics = require("@game/ReplicatedStorage/Shared/Combat/Ballistics")
local VisibilityModel = require("@game/ReplicatedStorage/Shared/Spotting/VisibilityModel")
local Modifiers = require("./Modifiers")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local VehicleTypes = require("@game/ReplicatedStorage/Shared/Types/Vehicle")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")
local SimTypes = require("@game/ReplicatedStorage/Shared/Types/VehicleSim")

type ContentRegistry = ContentRegistryModule.ContentRegistry
type Result<T> = Result.Result<T>
type VehicleDefinition = ContentTypes.VehicleDefinition
type Configuration = ContentTypes.Configuration
type GunDefinition = ContentTypes.GunDefinition
type ShellDefinition = ContentTypes.ShellDefinition
type ClassDefinition = ContentTypes.ClassDefinition
type StatModifier = ContentTypes.StatModifier
type StatKey = ContentTypes.StatKey
type SpecialMechanic = ContentTypes.SpecialMechanic
type CrewRole = ContentTypes.CrewRole
type InternalModuleKind = ContentTypes.InternalModuleKind
type ReloadSpec = ContentTypes.ReloadSpec
type CamoSpec = ContentTypes.CamoSpec
type VehicleStats = VehicleTypes.VehicleStats
type GunStats = VehicleTypes.GunStats
type ShellStats = VehicleTypes.ShellStats
type BloomStats = VehicleTypes.BloomStats
type ModuleStats = VehicleTypes.ModuleStats
type CrewSlotStats = VehicleTypes.CrewSlotStats
type CamoStats = VehicleTypes.CamoStats
type WheeledStats = VehicleTypes.WheeledStats
type Loadout = VehicleTypes.Loadout
type CrewMemberSnapshot = VehicleTypes.CrewMemberSnapshot
type ModuleState = VehicleTypes.ModuleState
type EffectMultipliers = CombatTypes.EffectMultipliers
type AimFactors = CombatTypes.AimFactors
type VehicleSimModifiers = SimTypes.VehicleSimModifiers
type TurretSimModifiers = SimTypes.TurretSimModifiers
type Accumulator = Modifiers.Accumulator
type Conditions = Modifiers.Conditions

export type ComputeOptions = {
	--- Ranked / competitive queue: the paint camo bonus is Config.Spotting.PAINT_CAMO_BONUS_COMPETITIVE (0).
	competitive: boolean?,
	--- Skip Freeze.deep on the result (tools that post-process stats). Default false.
	mutable: boolean?,
}

--- Effective stats right now (runtime). `*Mul` fields are ratios against the VehicleStats value (what the owning
--- systems multiply in); the absolute fields are VehicleStats × that ratio (HUD, bots, garage "in battle" preview).
export type RuntimeStats = {
	version: number, -- +1 every time the record is recomputed
	-- gun (GunState, Dispersion)
	reloadMul: number, -- GunState.setReloadMul (ActiveCooling's reloadTime excluded: GunState applies it)
	canFire: boolean, -- GunState.setEnabled (gun module not destroyed)
	aimTimeS: number,
	aimTimeMul: number,
	dispersionM100: number,
	dispersionMul: number,
	bloom: BloomStats,
	gunDamaged: boolean,
	damageMul: number, -- conditional damage modifiers as a ratio of the standard shell's alpha (ShotResolver)
	penetrationMul: number, -- conditional penetration modifiers as a ratio of the standard shell's pen
	-- turret (TurretSim)
	turretTraverseDegS: number,
	turretTraverseMul: number,
	depressionBonusDeg: number, -- conditional gunDepression adds (mechanic arc bonuses stay with VehicleSim)
	elevationBonusDeg: number,
	-- mobility (VehicleSim)
	enginePowerHp: number,
	enginePowerMul: number,
	topSpeedMul: number,
	topSpeedBonusKmh: number,
	reverseSpeedMul: number,
	hullTraverseDegS: number,
	hullTraverseMul: number,
	canMove: boolean,
	-- spotting (SpottingVehicle.viewRangeM / viewRangeMul / camo; pass conditionalModifiers = nil there)
	viewRangeM: number, -- VehicleStats.viewRangeM with the conditional modifiers that hold now
	viewRangeMul: number, -- module / crew / stun ratio (DamageModel.effects, damaged-penalty corrected)
	camo: CamoStats,
	sixthSense: boolean,
	-- survivability
	fireChanceMul: number,
	repairTimeMul: number,
	stunned: boolean,
	burning: boolean,
	mechanicActive: boolean,
}

--- Per-vehicle runtime cache (newRuntime). Fields prefixed `_` are internal.
export type Runtime = {
	stats: VehicleStats,
	conditions: Conditions, -- caller-owned facts (update in place every tick before update())
	out: RuntimeStats,
	dirty: boolean,
	_acc: Accumulator,
	_cond: { StatModifier },
	_condHold: { boolean },
	_sources: { any }, -- [slot] = { StatModifier } | false
	_srcHold: { { boolean } },
	_eff: EffectMultipliers,
	_modState: { [string]: string },
	_reloadBase: number,
}

local StatsCalculator = {}

--- Tunables. Read through `Config.VehicleStats` when that section exists (live-overridable), else these defaults.
local DEFAULTS = table.freeze({
	--- Equipment in the role's category slot (Tier VI+): each delta × (1 + this) (00-DECISIONS §7.2, §13: +15 %).
	CATEGORY_SLOT_BONUS = 0.15,
	--- Crew level clamp after modifiers (loadout levels are 1..200; injuries are battle-only).
	MIN_CREW_LEVEL = 1,
	MAX_CREW_LEVEL = 300,
})
StatsCalculator.DEFAULTS = DEFAULTS

local function setting(key: string): any
	local section = (Config :: any).VehicleStats
	if type(section) == "table" then
		local v = section[key]
		if v ~= nil then
			return v
		end
	end
	return (DEFAULTS :: any)[key]
end

--- Runtime source slots for setActive (fixed so the per-tick path never allocates).
StatsCalculator.SOURCE = table.freeze({
	Mechanic = 1, -- Mechanics/Controller.modifiers (siege aim/dispersion; mobility parts stay with VehicleSim)
	GunMechanic = 2, -- GunState.mechanicModifiers (ActiveCooling minus reloadTime)
	Consumable1 = 3, -- active consumable effects, one slot per consumable slot
	Consumable2 = 4,
	Consumable3 = 5,
	Consumable4 = 6,
	Event = 7, -- event-mode abilities / scripted buffs
	Custom = 8,
})
local MAX_SOURCES = 8
local SOURCE_MECHANIC = 1

--- Stats whose MechanicActive / mechanic-source modifiers VehicleSim applies itself (movement.md §4.10):
--- the runtime skips them there so nothing is applied twice.
local SIM_OWNED: { [string]: boolean } = table.freeze({
	enginePower = true,
	topSpeed = true,
	reverseSpeed = true,
	hullTraverse = true,
	gunDepression = true,
	gunElevation = true,
})
StatsCalculator.SIM_OWNED = SIM_OWNED

local DUTIES: { CrewRole } = { "Commander", "Gunner", "Driver", "Loader" }
local MODULE_KINDS: { InternalModuleKind } = Modifiers.MODULE_KINDS :: any

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if finite(x) then x else default
end

local function wholeHp(x: number): number
	if not (x > 0) or not finite(x) then
		return 0
	end
	return math.floor(x + 0.5)
end

local function holdsDuty(role: string, also: { any }?, duty: string): boolean
	if role == duty then
		return true
	end
	if also ~= nil then
		for _, r in also do
			if r == duty then
				return true
			end
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Modifier collection
--------------------------------------------------------------------------------

type Collect = {
	acc: Accumulator,
	conditional: { StatModifier },
}

-- Folds a list at `scale`: Always modifiers into the accumulator, the others as scaled copies into `conditional`.
local function collect(c: Collect, list: { StatModifier }?, scale: number)
	if list == nil then
		return
	end
	for _, mod in list do
		if not Modifiers.isValid(mod) then
			continue
		end
		if Modifiers.isAlways(mod) then
			Modifiers.push(c.acc, mod, scale)
		else
			table.insert(c.conditional, Modifiers.scaledCopy(mod, scale))
		end
	end
end

local function containsCategory(categories: { any }?, category: string?): boolean
	if categories == nil or category == nil then
		return false
	end
	return table.find(categories, category) ~= nil
end

local function sortedBySlot<T>(list: { T }?): { T }
	local copy: { T } = if list ~= nil then table.clone(list) else {}
	table.sort(copy, function(a: any, b: any)
		return (tonumber(a.slot) or 0) < (tonumber(b.slot) or 0)
	end)
	return copy
end

local function collectEquipment(
	c: Collect,
	def: VehicleDefinition,
	loadout: Loadout,
	registry: ContentRegistry,
	categorySlot: string?
): (boolean, string?)
	local groups: { [string]: boolean } = {}
	local bonus = num(setting("CATEGORY_SLOT_BONUS"), DEFAULTS.CATEGORY_SLOT_BONUS)
	for _, entry in sortedBySlot(loadout.equipment) do
		local item = registry:getEquipment(entry.id)
		if item == nil then
			return false, `equipment slot {entry.slot}: unknown equipment {tostring(entry.id)}`
		end
		if groups[item.exclusiveGroup] then
			continue -- never stacks (checkLoadout rejects the second item upstream)
		end
		groups[item.exclusiveGroup] = true
		local byClass = if item.effectsByClass ~= nil then item.effectsByClass[def.class] else nil
		local effects = byClass or item.effects
		local matched = categorySlot ~= nil and entry.slot == 1 and containsCategory(item.categories, categorySlot)
		if matched then
			if byClass == nil and item.categorySlotEffects ~= nil then
				collect(c, item.categorySlotEffects, 1)
			else
				collect(c, effects, 1 + bonus)
			end
		else
			collect(c, effects, 1)
		end
	end
	return true, nil
end

-- Crew member snapshot for seat `i` (nil = default member at CREW_BASE_LEVEL, no skills).
local function memberFor(loadout: Loadout?, i: number): CrewMemberSnapshot?
	if loadout == nil or type(loadout.crew) ~= "table" then
		return nil
	end
	for _, m in loadout.crew do
		if m.slot == i then
			return m
		end
	end
	return loadout.crew[i]
end

local function collectSkills(
	c: Collect,
	def: VehicleDefinition,
	loadout: Loadout,
	registry: ContentRegistry
): (boolean, string?)
	local seats = def.crew
	local n = #seats
	if n == 0 then
		return true, nil
	end
	local efficiency = math.clamp(num(loadout.crewPerkEfficiency, 1), 0, 1)
	local order: { string } = {}
	local seen: { [string]: boolean } = {}
	for i = 1, n do
		local member = memberFor(loadout, i)
		if member ~= nil and type(member.skills) == "table" then
			for _, s in member.skills do
				if type(s) == "table" and type(s.id) == "string" and not seen[s.id] then
					seen[s.id] = true
					table.insert(order, s.id)
				end
			end
		end
	end
	for _, id in order do
		local skill = registry:getSkill(id)
		if skill == nil then
			return false, `crew: unknown crew skill {id}`
		end
		local sum, holders = 0, 0
		for i = 1, n do
			local seat = seats[i]
			local member = memberFor(loadout, i)
			local training = 0
			if member ~= nil and type(member.skills) == "table" then
				for _, s in member.skills do
					if type(s) == "table" and s.id == id then
						training = math.clamp(num(s.training, 0), 0, 1)
					end
				end
			end
			if skill.kind == "Group" then
				sum += training
				holders += 1
			else
				local holds = false
				for _, duty in skill.roles do
					if holdsDuty(seat.role, seat.also, duty) then
						holds = true
						break
					end
				end
				if holds then
					sum += training
					holders += 1
				end
			end
		end
		local share = if holders > 0 then sum / holders else 0
		if share > 0 then
			collect(c, skill.effects, share * efficiency)
		end
	end
	return true, nil
end

local function collectConsumables(c: Collect, loadout: Loadout, registry: ContentRegistry): (boolean, string?)
	local groups: { [string]: boolean } = {}
	for _, entry in sortedBySlot(loadout.consumables) do
		local item = registry:getConsumable(entry.id)
		if item == nil then
			return false, `consumable slot {entry.slot}: unknown consumable {tostring(entry.id)}`
		end
		if groups[item.exclusiveGroup] then
			continue
		end
		groups[item.exclusiveGroup] = true
		collect(c, item.passiveEffects, 1)
		if item.activation == "Passive" then
			collect(c, item.effects, 1)
		end
	end
	return true, nil
end

local function collectFieldKit(
	c: Collect,
	def: VehicleDefinition,
	loadout: Loadout,
	registry: ContentRegistry
): (boolean, string?)
	if loadout.fieldKit == nil then
		return true, nil
	end
	local role = registry:getRole(def.role)
	local kit = if role ~= nil then role.fieldKit else nil
	for i, optionId in loadout.fieldKit do
		local level = if kit ~= nil then kit[i] else nil
		local found = nil
		if level ~= nil then
			for _, option in level.options do
				if option.id == optionId then
					found = option
					break
				end
			end
		end
		if found == nil then
			return false, `fieldKit[{i}]: unknown option {tostring(optionId)}`
		end
		collect(c, found.effects, 1)
	end
	return true, nil
end

local function collectApex(c: Collect, def: VehicleDefinition, loadout: Loadout): (boolean, string?)
	if loadout.apexNodes == nil then
		return true, nil
	end
	local nodes: { any } = if def.apex ~= nil then def.apex.nodes else {}
	local done: { [string]: boolean } = {}
	for i, nodeId in loadout.apexNodes do
		if done[nodeId] then
			continue
		end
		local found = nil
		for _, node in nodes do
			if node.id == nodeId then
				found = node
				break
			end
		end
		if found == nil then
			return false, `apexNodes[{i}]: unknown node {tostring(nodeId)}`
		end
		done[nodeId] = true
		collect(c, found.effects, 1)
	end
	return true, nil
end

--------------------------------------------------------------------------------
-- Resolution helpers
--------------------------------------------------------------------------------

local function apply(acc: Accumulator, stat: StatKey, base: number, module: InternalModuleKind?): number
	return Modifiers.apply(acc, stat, base, module)
end

-- One reload of the gun in base seconds (the swap reference, 00-DECISIONS §4 "ammo swap = full reload").
local function oneReload(reload: ReloadSpec): number
	if reload.kind == "Single" or reload.kind == "Magazine" then
		return reload.reloadS
	elseif reload.kind == "Autoreloader" then
		return reload.perShellReloadS[1] or 0
	end
	return reload.reloadEachS
end
StatsCalculator.oneReload = oneReload

-- Reload timers × crew factor, then the reloadTime modifiers (intra-clip, salvo and charge times are not reloads).
local function resolveReload(reload: ReloadSpec, acc: Accumulator, crewFactor: number): ReloadSpec
	local function t(x: number): number
		return math.max(0, apply(acc, "reloadTime", x * crewFactor))
	end
	if reload.kind == "Single" then
		return { kind = "Single", reloadS = t(reload.reloadS) }
	elseif reload.kind == "Magazine" then
		return { kind = "Magazine", size = reload.size, intraClipS = reload.intraClipS, reloadS = t(reload.reloadS) }
	elseif reload.kind == "Autoreloader" then
		local per: { number } = {}
		for i, x in reload.perShellReloadS do
			per[i] = t(x)
		end
		return { kind = "Autoreloader", size = reload.size, perShellReloadS = per, intraClipS = reload.intraClipS }
	end
	return {
		kind = "DualGun",
		reloadEachS = t(reload.reloadEachS),
		salvoDelayS = reload.salvoDelayS,
		chargeTimeS = reload.chargeTimeS,
		volleyDispersionMul = reload.volleyDispersionMul,
	}
end

local DEFAULT_TRACER: { [string]: string } = { AP = "AP", APCR = "APCR", HEAT = "HEAT", HE = "HE", HESH = "HE" }

--- ShellStats with every content default resolved (00-DECISIONS §1; Config.Combat) and the damage /
--- penetration / shellVelocity modifiers applied. `acc` nil = no modifiers.
function StatsCalculator.resolveShell(shell: ShellDefinition, indirect: boolean, acc: Accumulator?): ShellStats
	local C = Config.Combat
	local kind = shell.kind
	local a = acc or Modifiers.newAccumulator()
	local damage = math.max(0, apply(a, "damage", shell.damage))
	local damageRatio = if shell.damage > 0 then damage / shell.damage else 1
	local moduleDamage = if shell.moduleDamage ~= nil
		then shell.moduleDamage * damageRatio
		else num((C.MODULE_DAMAGE_FACTOR :: any)[kind], 0.5) * damage
	local pen = math.max(0, apply(a, "penetration", shell.penetrationMm))
	local penRatio = if shell.penetrationMm > 0 then pen / shell.penetrationMm else 1
	local kinetic = (C.KINETIC :: any)[kind] == true
	local at500 = pen
	if kinetic then
		at500 = if shell.penetrationAt500Mm ~= nil
			then shell.penetrationAt500Mm * penRatio
			else Ballistics.defaultPenetrationAt500(kind, pen)
	end
	local explosive = (C.EXPLOSIVE :: any)[kind] == true
	local radius = 0
	if explosive then
		radius = shell.explosionRadiusM
			or (
				if indirect
					then C.ARTILLERY_SPLASH_BASE_M + C.ARTILLERY_SPLASH_PER_MM * shell.caliberMm
					else C.SPLASH_RADIUS_M_PER_MM * shell.caliberMm
			)
	end
	local ricochet = if explosive then 90 else shell.ricochetAngleDeg or num((C.RICOCHET_ANGLE_DEG :: any)[kind], 90)
	local tracer = shell.tracer or (if indirect then "Artillery" else DEFAULT_TRACER[kind] or "AP") :: any
	return {
		id = shell.id,
		kind = shell.kind,
		special = shell.special,
		caliberMm = shell.caliberMm,
		damage = damage,
		moduleDamage = moduleDamage,
		penetrationMm = pen,
		penetrationAt500Mm = at500,
		velocityMps = math.max(0, apply(a, "shellVelocity", shell.velocityMps)),
		gravityMps2 = shell.gravityMps2 or C.SHELL_GRAVITY_MPS2,
		maxRangeM = shell.maxRangeM or C.MAX_RANGE_M,
		explosionRadiusM = radius,
		normalizationDeg = shell.normalizationDeg or num((C.NORMALIZATION_DEG :: any)[kind], 0),
		ricochetAngleDeg = ricochet,
		stun = if shell.stun ~= nil then { maxS = shell.stun.maxS, minS = shell.stun.minS } else nil,
		priceCredits = shell.priceCredits,
		tracer = tracer,
	}
end

-- Resolved copies of the vehicle's mechanics with the Apex `mechanic*` StatKeys applied (content-schema §7.6).
local function resolveMechanics(list: { SpecialMechanic }?, acc: Accumulator): { SpecialMechanic }
	local out: { SpecialMechanic } = {}
	if list == nil then
		return out
	end
	for _, spec in list do
		local m = table.clone(spec) :: any
		local kind = m.kind
		if kind == "ChargedShot" then
			m.chargeTimeS = apply(acc, "mechanicChargeTime", m.chargeTimeS)
			if m.effect == "Accuracy" and m.dispersionMul ~= nil then
				m.dispersionMul = apply(acc, "mechanicFactor", m.dispersionMul)
			elseif m.effect == "Damage" and m.damageMul ~= nil then
				m.damageMul = apply(acc, "mechanicFactor", m.damageMul)
			end
		elseif kind == "Turbo" then
			m.powerMul = apply(acc, "mechanicFactor", m.powerMul)
			m.durationS = apply(acc, "mechanicDuration", m.durationS)
			m.cooldownS = apply(acc, "mechanicCooldown", m.cooldownS)
		elseif kind == "RocketBoost" then
			m.charges = math.max(0, math.floor(apply(acc, "mechanicCharges", m.charges) + 0.5))
			m.durationS = apply(acc, "mechanicDuration", m.durationS)
			m.cooldownS = apply(acc, "mechanicCooldown", m.cooldownS)
		elseif kind == "ActiveCooling" then
			m.durationS = apply(acc, "mechanicDuration", m.durationS)
			m.cooldownS = apply(acc, "mechanicCooldown", m.cooldownS)
		elseif kind == "ReserveTracks" then
			m.charges = math.max(0, math.floor(apply(acc, "mechanicCharges", m.charges) + 0.5))
			m.repairS = apply(acc, "mechanicDuration", m.repairS)
			m.cooldownS = apply(acc, "mechanicCooldown", m.cooldownS)
		elseif kind == "AdaptiveMagazine" then
			m.partialReloadFactor = apply(acc, "mechanicFactor", m.partialReloadFactor)
		end
		table.insert(out, m :: SpecialMechanic)
	end
	return out
end

local function camoBaseOf(def: VehicleDefinition, class: ClassDefinition, casemate: boolean): CamoSpec
	if def.camouflage ~= nil then
		return def.camouflage
	end
	if casemate and class.camoCasemate ~= nil then
		return class.camoCasemate
	end
	return class.camo
end

-- Flat paint camo bonus: a Style replaces paint + camouflage; any applied item with camoBonus grants it once.
local function paintBonus(loadout: Loadout?, registry: ContentRegistry, competitive: boolean): number
	if loadout == nil or type(loadout.customization) ~= "table" then
		return 0
	end
	local custom = loadout.customization
	local ids: { string } = {}
	if custom.style ~= nil then
		table.insert(ids, custom.style)
	else
		if custom.paint ~= nil then
			table.insert(ids, custom.paint)
		end
		if custom.camouflage ~= nil then
			table.insert(ids, custom.camouflage)
		end
	end
	for _, id in ids do
		local item = registry:getCustomization(id)
		if item ~= nil and item.camoBonus == true then
			local S = Config.Spotting
			return if competitive then S.PAINT_CAMO_BONUS_COMPETITIVE else S.PAINT_CAMO_BONUS
		end
	end
	return 0
end

--------------------------------------------------------------------------------
-- compute
--------------------------------------------------------------------------------

--- Resolves `def` with `configuration` and `loadout` (nil = trained default crew, no equipment, consumables or
--- skills) into VehicleStats. `configuration` may differ from loadout.configuration (garage module preview).
--- Returns Ok(VehicleStats) (deep-frozen unless opts.mutable) or Err(NOT_FOUND | INVALID_ARGS, detail).
function StatsCalculator.compute(
	def: VehicleDefinition,
	configuration: Configuration,
	loadout: Loadout?,
	registry: ContentRegistry,
	opts: ComputeOptions?
): Result<VehicleStats>
	if type(def) ~= "table" or type(def.id) ~= "string" then
		return Result.err(ErrorCodes.INVALID_ARGS, "vehicle definition expected")
	end
	local check = registry:checkConfiguration(def.id, configuration)
	if not check.ok then
		return check :: any
	end
	local massKg: number = (check :: any).value
	if loadout ~= nil and loadout.vehicleId ~= def.id then
		return Result.err(ErrorCodes.INVALID_ARGS, `loadout is for {tostring(loadout.vehicleId)}, not {def.id}`)
	end
	local gunDef = registry:getGun(configuration.gun)
	local turret = registry:getTurret(configuration.turret)
	local engine = registry:getEngine(configuration.engine)
	local tracks = registry:getTracks(configuration.tracks)
	local class = registry:getClass(def.class)
	local tier = registry:getTier(def.tier)
	local role = registry:getRole(def.role)
	if gunDef == nil or turret == nil or engine == nil or tracks == nil then
		return Result.err(ErrorCodes.NOT_FOUND, "configuration module missing")
	end
	if class == nil or tier == nil or role == nil then
		return Result.err(ErrorCodes.NOT_FOUND, `class/tier/role of {def.id} missing`)
	end
	local gun: GunDefinition = gunDef
	local C = Config.Combat

	-- 1. Always modifiers + conditional copies
	local c: Collect = { acc = Modifiers.newAccumulator(), conditional = {} }
	if loadout ~= nil then
		local categorySlot: string? = nil
		local slotsOverride = def.slots
		if tier.categorySlot or (slotsOverride ~= nil and slotsOverride.categorySlot ~= nil) then
			categorySlot = if slotsOverride ~= nil and slotsOverride.categorySlot ~= nil
				then slotsOverride.categorySlot
				else role.categorySlot
		end
		local steps: { () -> (boolean, string?) } = {
			function()
				return collectEquipment(c, def, loadout, registry, categorySlot)
			end,
			function()
				return collectSkills(c, def, loadout, registry)
			end,
			function()
				return collectConsumables(c, loadout, registry)
			end,
			function()
				return collectFieldKit(c, def, loadout, registry)
			end,
			function()
				return collectApex(c, def, loadout)
			end,
		}
		for _, step in steps do
			local ok, detail = step()
			if not ok then
				return Result.err(ErrorCodes.NOT_FOUND, detail)
			end
		end
	end
	local acc = c.acc

	-- 2. Crew levels (00-DECISIONS §4 "L"; §12: no qualification levels, injuries are battle-only)
	local minL = num(setting("MIN_CREW_LEVEL"), DEFAULTS.MIN_CREW_LEVEL)
	local maxL = num(setting("MAX_CREW_LEVEL"), DEFAULTS.MAX_CREW_LEVEL)
	local refAlpha = tier.moduleHpRefAlpha
	local crewHp = DamageModel.crewHpFor(refAlpha)
	local crew: { CrewSlotStats } = {}
	for i, seat in def.crew do
		local member = memberFor(loadout, i)
		local base = if member ~= nil then num(member.level, C.CREW_BASE_LEVEL) else C.CREW_BASE_LEVEL
		local level = math.clamp(apply(acc, "crewLevel", base), minL, maxL)
		table.insert(crew, {
			slot = i,
			role = seat.role,
			also = if seat.also ~= nil then table.clone(seat.also) else {},
			level = level,
			maxHp = crewHp,
		})
	end
	local levels: { [string]: number } = {}
	for _, duty in DUTIES do
		local sum, n = 0, 0
		for _, m in crew do
			if holdsDuty(m.role, m.also, duty) then
				sum += m.level
				n += 1
			end
		end
		levels[duty] = if n > 0 then sum / n else C.CREW_BASE_LEVEL
	end
	local crewLevels: { [CrewRole]: number } = levels :: any
	local reloadF = CrewEffects.reloadFactor(levels.Loader)
	local commanderF = CrewEffects.statFactor(levels.Commander)
	local gunnerF = CrewEffects.statFactor(levels.Gunner)
	local driverF = CrewEffects.statFactor(levels.Driver)

	-- 3. Gun
	local indirect = gun.indirect == true
	local shells: { ShellStats } = {}
	for _, shellId in gun.shells do
		local shell = registry:getShell(shellId)
		if shell == nil then
			return Result.err(ErrorCodes.NOT_FOUND, `gun {gun.id}: unknown shell {shellId}`)
		end
		table.insert(shells, StatsCalculator.resolveShell(shell, indirect, acc))
	end
	local bloomDef = gun.bloom
	local tracksBloom = num(tracks.bloomMul, 1)
	local bloom: BloomStats = {
		movementPerKmh = apply(
			acc,
			"bloomMovement",
			(
				if bloomDef ~= nil and bloomDef.movementPerKmh ~= nil
					then bloomDef.movementPerKmh
					else C.BLOOM_MOVEMENT_PER_KMH
			) * tracksBloom
		),
		hullTraversePerDegS = apply(
			acc,
			"bloomHullTraverse",
			(
				if bloomDef ~= nil and bloomDef.hullTraversePerDegS ~= nil
					then bloomDef.hullTraversePerDegS
					else C.BLOOM_HULL_TRAVERSE_PER_DEGS
			) * tracksBloom
		),
		turretTraversePerDegS = apply(
			acc,
			"bloomTurretTraverse",
			if bloomDef ~= nil and bloomDef.turretTraversePerDegS ~= nil
				then bloomDef.turretTraversePerDegS
				else C.BLOOM_TURRET_TRAVERSE_PER_DEGS
		),
		afterShot = apply(
			acc,
			"bloomAfterShot",
			if bloomDef ~= nil and bloomDef.afterShot ~= nil then bloomDef.afterShot else class.afterShotBloom
		),
		damagedMul = if bloomDef ~= nil and bloomDef.damagedMul ~= nil
			then bloomDef.damagedMul
			else C.BLOOM_DAMAGED_MUL,
	}
	local reload = resolveReload(gun.reload, acc, reloadF)
	local swapBase = if gun.shellSwapS ~= nil then gun.shellSwapS else oneReload(gun.reload)
	local shellSwapS =
		math.max(0, apply(acc, "shellSwapTime", math.max(0, apply(acc, "reloadTime", swapBase * reloadF))))
	local camoAfterShotMul = gun.camoAfterShotMul or VisibilityModel.defaultShotCamoMul(gun.caliberMm)
	local arcSectors = {}
	if def.arcSectors ~= nil then
		for _, sector in def.arcSectors do
			table.insert(arcSectors, table.clone(sector))
		end
	end
	local gunStats: GunStats = {
		id = gun.id,
		caliberMm = gun.caliberMm,
		reload = reload,
		dispersionM100 = math.max(0, apply(acc, "dispersion", gun.dispersionM100 / gunnerF)),
		aimTimeS = math.max(0, apply(acc, "aimTime", gun.aimTimeS / gunnerF)),
		bloom = bloom,
		depressionDeg = apply(acc, "gunDepression", gun.arcs.depressionDeg),
		elevationDeg = apply(acc, "gunElevation", gun.arcs.elevationDeg),
		arcSectors = arcSectors,
		shells = shells,
		ammoCapacity = math.max(0, math.floor(apply(acc, "ammoCapacity", gun.ammoCapacity) + 0.5)),
		camoAfterShotMul = camoAfterShotMul,
		shellSwapS = shellSwapS,
		indirect = indirect,
		damageRollMinAdd = apply(acc, "damageRollMin", 0),
		penetrationRollMinAdd = apply(acc, "penetrationRollMin", 0),
	}

	-- 4. Modules (one HP pool per kind; field repair ÷ f(L_driver); 00-DECISIONS §2)
	local modules: { [InternalModuleKind]: ModuleStats } = {}
	for _, k in MODULE_KINDS do
		local kind: InternalModuleKind = k :: any
		local repairBase = num((C.REPAIR_S :: any)[kind], 10)
		modules[kind] = {
			maxHp = wholeHp(apply(acc, "moduleHp", DamageModel.moduleHpFor(kind, refAlpha), kind)),
			repairS = math.max(0, apply(acc, "repairTime", repairBase / driverF, kind)),
			damagedPenaltyMul = math.max(0, apply(acc, "damagedModulePenalty", 1, kind)),
		}
	end

	-- 5. Mobility
	local mobility = def.mobility
	local mechanics = resolveMechanics(def.mechanics, acc)
	local wheeledSpec: any = nil
	for _, m in mechanics do
		if m.kind == "Wheeled" then
			wheeledSpec = m
			break
		end
	end
	local M = Config.Movement
	local topSpeed = math.max(0, apply(acc, "topSpeed", mobility.forwardKmh))
	local reverseBase = mobility.reverseKmh
		or math.clamp(mobility.forwardKmh * M.REVERSE_DEFAULT_RATIO, M.REVERSE_MIN_KMH, M.REVERSE_MAX_KMH)
	local reverseSpeed = math.max(0, apply(acc, "reverseSpeed", reverseBase))
	local enginePower = math.max(0, apply(acc, "enginePower", engine.powerHp))
	local wheeled: WheeledStats? = nil
	if wheeledSpec ~= nil then
		wheeled = {
			wheelPairs = wheeledSpec.wheelPairs,
			speedModeTopSpeedKmh = topSpeed * num(wheeledSpec.speedModeTopSpeedMul, 1),
			speedModeSteeringMul = num(wheeledSpec.speedModeSteeringMul, 1),
			speedModeReverseKmh = reverseSpeed * num(wheeledSpec.speedModeReverseMul, 1),
			toggleS = num(wheeledSpec.toggleS, 1),
			lostPairSpeedMul = num(wheeledSpec.lostPairSpeedMul, C.WHEELED_LOST_SIDE_SPEED_MUL),
			movingDispersionMul = num(wheeledSpec.movingDispersionMul, C.WHEELED_MOVING_BLOOM_MUL),
			turnRadiusM = num(wheeledSpec.turnRadiusM, 0),
		}
	end
	local isWheeled = tracks.wheeled == true or wheeled ~= nil
	local pivot = if mobility.pivot ~= nil then mobility.pivot else not isWheeled
	local resistance = tracks.terrainResistance

	-- 6. Turret, spotting, camo
	local casemate = turret.mount == "Casemate"
	local yawLimits: { left: number, right: number }? = nil
	if turret.yawLimitsDeg ~= nil then
		yawLimits = { left = turret.yawLimitsDeg.left, right = turret.yawLimitsDeg.right }
	elseif casemate then
		yawLimits = { left = M.CASEMATE_DEFAULT_YAW_DEG, right = M.CASEMATE_DEFAULT_YAW_DEG }
	end
	local camoBase = camoBaseOf(def, class, casemate)
	local camo: CamoStats = {
		stationary = math.max(0, apply(acc, "camoStationary", camoBase.stationary)),
		moving = math.max(0, apply(acc, "camoMoving", camoBase.moving)),
		afterShotMul = math.max(0, apply(acc, "camoAfterShot", camoAfterShotMul)),
		net = math.max(0, apply(acc, "camoNet", 0)),
		paint = paintBonus(loadout, registry, opts ~= nil and opts.competitive == true),
	}
	local fireBase = engine.fireChance or num((C.FIRE_CHANCE :: any)[engine.fuel], C.FIRE_CHANCE_DEFAULT)
	local slotsOverride = def.slots

	local stats: VehicleStats = {
		vehicleId = def.id,
		faction = def.faction,
		tier = def.tier,
		class = def.class,
		role = def.role,
		configuration = {
			gun = configuration.gun,
			turret = configuration.turret,
			engine = configuration.engine,
			tracks = configuration.tracks,
		},
		premium = def.acquisition == "Premium",
		hp = wholeHp(apply(acc, "hp", def.hull.hp + turret.hpBonus)),
		massKg = massKg,
		dimensionsM = Vector3.new(def.visual.hull.widthM, def.visual.hull.heightM, def.visual.hull.lengthM),
		modules = modules,
		fireChance = math.clamp(apply(acc, "fireChance", fireBase), 0, 1),
		fireDurationS = math.max(0, apply(acc, "fireDuration", C.FIRE_DURATION_S)),
		crewInjuryChanceMul = math.max(0, apply(acc, "crewInjuryChance", 1)),
		spallFactor = math.max(0, apply(acc, "spallFactor", C.SPALL_FACTOR_BASE)),
		stunDurationMul = math.max(0, apply(acc, "stunDuration", 1)),
		ramDamageDealtMul = math.max(0, apply(acc, "ramDamageDealt", 1)),
		ramDamageTakenMul = math.max(0, apply(acc, "ramDamageTaken", 1)),
		fallDamageMul = math.max(0, apply(acc, "fallDamage", 1)),
		repairTimeMul = math.max(0, apply(acc, "repairTime", 1 / driverF)),
		enginePowerHp = enginePower,
		specificPowerHpT = if massKg > 0 then enginePower / (massKg / 1000) else 0,
		topSpeedKmh = topSpeed,
		reverseSpeedKmh = reverseSpeed,
		hullTraverseDegS = math.max(0, apply(acc, "hullTraverse", tracks.traverseDegS * driverF)),
		terrainResistance = {
			hard = math.max(0, apply(acc, "terrainResistance", resistance.hard)),
			medium = math.max(0, apply(acc, "terrainResistance", resistance.medium)),
			soft = math.max(0, apply(acc, "terrainResistance", resistance.soft)),
		},
		loadLimitKg = math.max(0, apply(acc, "loadLimit", tracks.loadLimitKg)),
		pivot = pivot,
		wheeled = wheeled,
		turretMount = turret.mount,
		turretTraverseDegS = math.max(0, apply(acc, "turretTraverse", turret.traverseDegS * gunnerF)),
		yawLimitsDeg = yawLimits,
		gun = gunStats,
		viewRangeM = math.max(0, apply(acc, "viewRange", turret.viewRangeM * class.viewRangeMul * commanderF)),
		signalRangeM = math.max(0, apply(acc, "signalRange", class.signalRangeM)),
		camo = camo,
		crew = crew,
		crewLevels = crewLevels,
		consumableSlots = if slotsOverride ~= nil and slotsOverride.consumables ~= nil
			then slotsOverride.consumables
			else tier.consumableSlots,
		consumableCooldownMul = math.max(0, apply(acc, "consumableCooldown", 1)),
		crewXpMul = math.max(0, apply(acc, "crewXp", 1)),
		mechanics = mechanics,
		conditionalModifiers = c.conditional,
	}
	if opts == nil or opts.mutable ~= true then
		Freeze.deep(stats)
	end
	return Result.ok(stats)
end

--- compute() for a loadout's own vehicle and configuration (battle server / Hub manifest path).
function StatsCalculator.fromLoadout(
	loadout: Loadout,
	registry: ContentRegistry,
	opts: ComputeOptions?
): Result<VehicleStats>
	if type(loadout) ~= "table" then
		return Result.err(ErrorCodes.INVALID_ARGS, "loadout expected")
	end
	local def = registry:getVehicle(loadout.vehicleId)
	if def == nil then
		return Result.err(ErrorCodes.NOT_FOUND, `unknown vehicle {tostring(loadout.vehicleId)}`)
	end
	return StatsCalculator.compute(def, loadout.configuration, loadout, registry, opts)
end

--- A legal minimal loadout (bots, garage defaults, tests): trained crew at CREW_BASE_LEVEL without skills, no
--- equipment or consumables, the rack filled with the standard (first) shell. `configuration` default = `def.top`.
function StatsCalculator.defaultLoadout(
	def: VehicleDefinition,
	registry: ContentRegistry,
	configuration: Configuration?
): Loadout
	local cfg = configuration or def.top
	local gun = registry:getGun(cfg.gun)
	local crew: { CrewMemberSnapshot } = {}
	for i, seat in def.crew do
		table.insert(crew, {
			slot = i,
			role = seat.role,
			also = if seat.also ~= nil then table.clone(seat.also) else nil,
			level = Config.Combat.CREW_BASE_LEVEL,
			skills = {},
		})
	end
	return {
		vehicleId = def.id,
		configuration = { gun = cfg.gun, turret = cfg.turret, engine = cfg.engine, tracks = cfg.tracks },
		equipment = {},
		ammo = if gun ~= nil then { { shell = gun.shells[1], count = gun.ammoCapacity } } else {},
		consumables = {},
		crew = crew,
		customization = {},
	}
end

--------------------------------------------------------------------------------
-- Runtime (30 Hz): effective stats with a dirty-flag cache
--------------------------------------------------------------------------------

-- Module kinds whose Damaged-state penalty `damagedModulePenalty` rescales.
local PENALTY_KINDS: { InternalModuleKind } = { "Engine", "AmmoRack", "FuelTank", "Gun", "TurretRing", "Optics" }

local function newRuntimeStats(stats: VehicleStats): RuntimeStats
	local b = stats.gun.bloom
	local cam = stats.camo
	return {
		version = 0,
		reloadMul = 1,
		canFire = true,
		aimTimeS = stats.gun.aimTimeS,
		aimTimeMul = 1,
		dispersionM100 = stats.gun.dispersionM100,
		dispersionMul = 1,
		bloom = {
			movementPerKmh = b.movementPerKmh,
			hullTraversePerDegS = b.hullTraversePerDegS,
			turretTraversePerDegS = b.turretTraversePerDegS,
			afterShot = b.afterShot,
			damagedMul = b.damagedMul,
		},
		gunDamaged = false,
		damageMul = 1,
		penetrationMul = 1,
		turretTraverseDegS = stats.turretTraverseDegS,
		turretTraverseMul = 1,
		depressionBonusDeg = 0,
		elevationBonusDeg = 0,
		enginePowerHp = stats.enginePowerHp,
		enginePowerMul = 1,
		topSpeedMul = 1,
		topSpeedBonusKmh = 0,
		reverseSpeedMul = 1,
		hullTraverseDegS = stats.hullTraverseDegS,
		hullTraverseMul = 1,
		canMove = true,
		viewRangeM = stats.viewRangeM,
		viewRangeMul = 1,
		camo = {
			stationary = cam.stationary,
			moving = cam.moving,
			afterShotMul = cam.afterShotMul,
			net = cam.net,
			paint = cam.paint,
		},
		sixthSense = true,
		fireChanceMul = 1,
		repairTimeMul = 1,
		stunned = false,
		burning = false,
		mechanicActive = false,
	}
end

--- A runtime cache for one vehicle (allocate once at spawn). Starts dirty: call update() before reading `out`.
function StatsCalculator.newRuntime(stats: VehicleStats): Runtime
	local cond = stats.conditionalModifiers or {}
	local srcHold: { { boolean } } = {}
	for s = 1, MAX_SOURCES do
		srcHold[s] = table.create(16, false)
	end
	local modState: { [string]: string } = {}
	for _, kind in PENALTY_KINDS do
		modState[kind] = "Ok"
	end
	return {
		stats = stats,
		conditions = Modifiers.newConditions(),
		out = newRuntimeStats(stats),
		dirty = true,
		_acc = Modifiers.newAccumulator(),
		_cond = cond,
		_condHold = table.create(#cond, false),
		_sources = table.create(MAX_SOURCES, false),
		_srcHold = srcHold,
		_eff = DamageModel.newEffects(),
		_modState = modState,
		_reloadBase = oneReload(stats.gun.reload),
	}
end

--- The caller-owned Conditions record (moving, stationaryForS, sinceShotS, nearestEnemyM, spotted, hpFraction,
--- mechanicActive, …): update its fields in place every tick, then call update().
function StatsCalculator.conditions(rt: Runtime): Conditions
	return rt.conditions
end

local EFFECT_KEYS = {
	"enginePowerMul",
	"topSpeedMul",
	"canMove",
	"hullTraverseMul",
	"turretTraverseMul",
	"reloadTimeMul",
	"canFire",
	"aimTimeMul",
	"dispersionMul",
	"gunDamaged",
	"viewRangeMul",
	"repairTimeMul",
	"fireChanceMul",
	"sixthSense",
	"stunned",
	"burning",
}

--- Copies DamageModel.effects (module states, crew injuries, stun) and, optionally, the module states
--- (`combat.modules`, for the damagedModulePenalty correction). Marks the cache dirty only when something changed.
function StatsCalculator.setEffects(
	rt: Runtime,
	effects: EffectMultipliers,
	modules: { [InternalModuleKind]: { state: ModuleState } }?
)
	local mine = rt._eff :: any
	local theirs = effects :: any
	for _, key in EFFECT_KEYS do
		local v = theirs[key]
		if v ~= nil and mine[key] ~= v then
			mine[key] = v
			rt.dirty = true
		end
	end
	if modules ~= nil then
		local states = rt._modState
		local byKind = modules :: any
		for _, kind in PENALTY_KINDS do
			local m = byKind[kind]
			local s = if m ~= nil then m.state else "Ok"
			if states[kind] ~= s then
				states[kind] = s
				rt.dirty = true
			end
		end
	end
end

--- Sets (or clears with nil) the active modifier list of a source slot (StatsCalculator.SOURCE). Passing the same
--- list again is free; a different list marks the cache dirty.
function StatsCalculator.setActive(rt: Runtime, slot: number, mods: { StatModifier }?)
	if slot < 1 or slot > MAX_SOURCES then
		return
	end
	local current = rt._sources[slot]
	local nextList: any = if mods ~= nil then mods else false
	if current == nextList then
		return
	end
	rt._sources[slot] = nextList
	local hold = rt._srcHold[slot]
	table.clear(hold)
	if mods ~= nil then
		for j, mod in mods do
			hold[j] = Modifiers.holds(mod, rt.conditions)
		end
	end
	rt.dirty = true
end

--- Forces a recompute on the next update().
function StatsCalculator.invalidate(rt: Runtime)
	rt.dirty = true
end

local function refreshHolds(rt: Runtime)
	local c = rt.conditions
	local hold = rt._condHold
	for i, mod in rt._cond do
		local h = Modifiers.holds(mod, c)
		if hold[i] ~= h then
			hold[i] = h
			rt.dirty = true
		end
	end
	for s = 1, MAX_SOURCES do
		local list = rt._sources[s]
		if list then
			local sh = rt._srcHold[s]
			for j, mod in list :: { StatModifier } do
				local h = Modifiers.holds(mod, c)
				if sh[j] ~= h then
					sh[j] = h
					rt.dirty = true
				end
			end
		end
	end
	if rt.out.mechanicActive ~= c.mechanicActive then
		rt.dirty = true
	end
end

-- Ratio (base + Σ add) × Π mul ÷ base (exactly 1 without modifiers); base 0 → Π mul.
local function ratio(acc: Accumulator, stat: StatKey, base: number): number
	if base == 0 then
		return Modifiers.mulOf(acc, stat)
	end
	return Modifiers.apply(acc, stat, base) / base
end

-- Rescales a module's Damaged-state multiplier `m` by the vehicle's damagedPenaltyMul `p`: returns the correction
-- factor to multiply into DamageModel's value (1 when the module is Ok or p = 1).
local function penalty(rt: Runtime, kind: InternalModuleKind, m: number, damagedOnly: boolean): number
	local state = rt._modState[kind]
	if state == "Ok" or (damagedOnly and state ~= "Damaged") then
		return 1
	end
	local mod = rt.stats.modules[kind]
	local p = if mod ~= nil then mod.damagedPenaltyMul else 1
	if p == 1 or m == 0 then
		return 1
	end
	return (1 + (m - 1) * p) / m
end

local function recompute(rt: Runtime)
	local acc = rt._acc
	Modifiers.reset(acc)
	local c = rt.conditions
	for i, mod in rt._cond do
		if rt._condHold[i] and not (mod.condition == "MechanicActive" and SIM_OWNED[mod.stat]) then
			Modifiers.push(acc, mod, nil)
		end
	end
	for s = 1, MAX_SOURCES do
		local list = rt._sources[s]
		if list then
			local sh = rt._srcHold[s]
			for j, mod in list :: { StatModifier } do
				if
					sh[j]
					and not ((s == SOURCE_MECHANIC or mod.condition == "MechanicActive") and SIM_OWNED[mod.stat])
				then
					Modifiers.push(acc, mod, nil)
				end
			end
		end
	end

	local C = Config.Combat
	local stats = rt.stats
	local gun = stats.gun
	local e = rt._eff
	local out = rt.out

	-- gun
	out.canFire = e.canFire
	out.gunDamaged = e.gunDamaged
	out.reloadMul = e.reloadTimeMul
		* penalty(rt, "AmmoRack", C.AMMO_DAMAGED_RELOAD_MUL, false)
		* ratio(acc, "reloadTime", rt._reloadBase)
	out.aimTimeMul = e.aimTimeMul
		* penalty(rt, "Gun", C.GUN_DAMAGED_AIM_MUL, false)
		* ratio(acc, "aimTime", gun.aimTimeS)
	out.aimTimeS = gun.aimTimeS * out.aimTimeMul
	out.dispersionMul = e.dispersionMul * ratio(acc, "dispersion", gun.dispersionM100)
	out.dispersionM100 = gun.dispersionM100 * out.dispersionMul
	local b, ob = gun.bloom, out.bloom
	ob.movementPerKmh = math.max(0, Modifiers.apply(acc, "bloomMovement", b.movementPerKmh))
	ob.hullTraversePerDegS = math.max(0, Modifiers.apply(acc, "bloomHullTraverse", b.hullTraversePerDegS))
	ob.turretTraversePerDegS = math.max(0, Modifiers.apply(acc, "bloomTurretTraverse", b.turretTraversePerDegS))
	ob.afterShot = math.max(0, Modifiers.apply(acc, "bloomAfterShot", b.afterShot))
	local gunModule: ModuleStats? = (stats.modules :: any).Gun
	local pGun = if gunModule ~= nil then gunModule.damagedPenaltyMul else 1
	ob.damagedMul = 1 + (b.damagedMul - 1) * pGun
	local standard = gun.shells[1]
	out.damageMul = if standard ~= nil then ratio(acc, "damage", standard.damage) else Modifiers.mulOf(acc, "damage")
	out.penetrationMul = if standard ~= nil
		then ratio(acc, "penetration", standard.penetrationMm)
		else Modifiers.mulOf(acc, "penetration")

	-- turret
	out.turretTraverseMul = e.turretTraverseMul
		* penalty(rt, "TurretRing", C.RING_DAMAGED_TRAVERSE_MUL, true)
		* ratio(acc, "turretTraverse", stats.turretTraverseDegS)
	out.turretTraverseDegS = stats.turretTraverseDegS * out.turretTraverseMul
	out.depressionBonusDeg = Modifiers.apply(acc, "gunDepression", gun.depressionDeg) - gun.depressionDeg
	out.elevationBonusDeg = Modifiers.apply(acc, "gunElevation", gun.elevationDeg) - gun.elevationDeg

	-- mobility
	out.enginePowerMul = e.enginePowerMul
		* penalty(rt, "Engine", C.ENGINE_DAMAGED_POWER_MUL, true)
		* ratio(acc, "enginePower", stats.enginePowerHp)
	out.enginePowerHp = stats.enginePowerHp * out.enginePowerMul
	out.topSpeedMul = e.topSpeedMul * Modifiers.mulOf(acc, "topSpeed")
	out.topSpeedBonusKmh = Modifiers.addOf(acc, "topSpeed")
	out.reverseSpeedMul = e.topSpeedMul * ratio(acc, "reverseSpeed", stats.reverseSpeedKmh)
	out.hullTraverseMul = e.hullTraverseMul * ratio(acc, "hullTraverse", stats.hullTraverseDegS)
	out.hullTraverseDegS = stats.hullTraverseDegS * out.hullTraverseMul
	out.canMove = e.canMove

	-- spotting
	out.viewRangeM = math.max(0, Modifiers.apply(acc, "viewRange", stats.viewRangeM))
	out.viewRangeMul = e.viewRangeMul * penalty(rt, "Optics", C.OPTICS_DAMAGED_VR_MUL, true)
	local cam, oc = stats.camo, out.camo
	oc.stationary = math.max(0, Modifiers.apply(acc, "camoStationary", cam.stationary))
	oc.moving = math.max(0, Modifiers.apply(acc, "camoMoving", cam.moving))
	oc.afterShotMul = math.max(0, Modifiers.apply(acc, "camoAfterShot", cam.afterShotMul))
	oc.net = math.max(0, Modifiers.apply(acc, "camoNet", cam.net))
	oc.paint = cam.paint
	out.sixthSense = e.sixthSense

	-- survivability
	out.fireChanceMul = e.fireChanceMul
		* penalty(rt, "FuelTank", C.FUEL_DAMAGED_FIRE_MUL, false)
		* ratio(acc, "fireChance", stats.fireChance)
	out.repairTimeMul = e.repairTimeMul * ratio(acc, "repairTime", 1)
	out.stunned = e.stunned
	out.burning = e.burning
	out.mechanicActive = c.mechanicActive
	out.version += 1
	rt.dirty = false
end

--- Re-evaluates the conditions and, only when a condition flipped or an input changed since the last call,
--- recomputes `rt.out`. Returns (out, changed). Allocation-free.
function StatsCalculator.update(rt: Runtime): (RuntimeStats, boolean)
	refreshHolds(rt)
	if not rt.dirty then
		return rt.out, false
	end
	recompute(rt)
	return rt.out, true
end

--- Writes the mobility runtime into VehicleSim's modifiers (the same contract as VehicleSim.applyEffects: module
--- states reset to Ok because they are already folded into the multipliers; `immobilized` = not canMove).
function StatsCalculator.writeSimModifiers(rt: Runtime, mods: VehicleSimModifiers)
	local out = rt.out
	mods.engine = "Ok"
	mods.trackLeft = "Ok"
	mods.trackRight = "Ok"
	mods.lostWheelPairs = 0
	mods.powerMul = out.enginePowerMul
	mods.topSpeedMul = out.topSpeedMul
	mods.topSpeedBonusKmh = out.topSpeedBonusKmh
	mods.reverseSpeedMul = out.reverseSpeedMul
	mods.hullTraverseMul = out.hullTraverseMul
	mods.immobilized = not out.canMove
end

--- Writes the turret runtime into TurretSim's modifiers (ring state folded into traverseMul, as applyEffects).
function StatsCalculator.writeTurretModifiers(rt: Runtime, mods: TurretSimModifiers)
	local out = rt.out
	mods.ring = "Ok"
	mods.traverseMul = out.turretTraverseMul
	mods.depressionBonusDeg = out.depressionBonusDeg
	mods.elevationBonusDeg = out.elevationBonusDeg
end

--- Writes the aim multipliers into Dispersion's AimFactors (speeds are the caller's). `stunned` is left false: the
--- stun dispersion factor is already inside dispersionMul (DamageModel.effects), so passing both would double it.
function StatsCalculator.writeAimFactors(rt: Runtime, factors: AimFactors)
	local out = rt.out
	factors.dispersionMul = out.dispersionMul
	factors.aimTimeMul = out.aimTimeMul
	factors.gunDamaged = out.gunDamaged
	factors.stunned = false
end

return StatsCalculator
