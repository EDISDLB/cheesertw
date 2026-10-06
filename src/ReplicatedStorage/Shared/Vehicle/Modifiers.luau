--!strict
--[[
	Vehicle/Modifiers — StatModifier aggregation (docs/design/content-schema.md §7): per stat, result =
	(base + Σ add) × Π mul, with module qualifiers, training/category-slot scaling and runtime conditions.

	Purpose:          One aggregation rule shared by StatsCalculator.compute (battle-start "Always" modifiers from
	                  equipment, skills, consumables, Field Kit, Apex nodes), StatsCalculator runtime (conditional
	                  and active modifiers at 30 Hz) and the Mechanics state machines (resolved mechanic numbers).
	Dependencies:     Config (Spotting: STATIONARY_ARM_S), Types/Content (type-only).
	State:            None at module level. An Accumulator is a caller-owned pair of flat arrays (one slot per StatKey
	                  plus one per (module-qualified stat, InternalModuleKind)); `reset` reuses it.
	Validation:       Invalid modifiers (unknown stat or op, non-finite value, module qualifier on a stat that takes
	                  none) are ignored and counted in `acc.ignored` (ContentRegistry rejects them in shipped content).
	                  Scaled `mul` values are floored at 0 so an over-scaled reduction never flips a sign.
	Error handling:   No throws.
	Performance notes: push/apply are O(1) array writes/reads with no allocation; pushList is O(n) over the list.
	                  Conditions are evaluated without allocation (Conditions is a caller-owned record).

	Scaling (OUR DESIGN CHOICE, 00-DECISIONS §12/§13): a modifier applied at share s (skill training × crew perk
	efficiency, group-skill crew share, category slot 1.15) scales its DELTA: add → value × s, mul → 1 + (value − 1) × s.
	So a −10 % rammer in the category slot becomes −11.5 % and a 50 %-trained +2 % skill gives +1 %.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatKey = ContentTypes.StatKey
type StatModifier = ContentTypes.StatModifier
type StatCondition = ContentTypes.StatCondition
type InternalModuleKind = ContentTypes.InternalModuleKind

--- Caller-owned aggregation buffer: `add[slot]` sums adds, `mul[slot]` multiplies muls.
export type Accumulator = {
	add: { number },
	mul: { number },
	applied: number, -- modifiers folded in since the last reset
	ignored: number, -- invalid modifiers skipped since the last reset
}

--- Runtime facts the StatCondition rules read (caller-owned, updated in place each tick).
export type Conditions = {
	moving: boolean, -- hull speed > STOP_SPEED_KMH or yawing (VisibilityModel.isMoving)
	stationaryForS: number, -- time since the hull stopped (0 while moving)
	turretTraversing: boolean,
	sinceShotS: number, -- seconds since this vehicle last fired (math.huge = never)
	sinceDamageS: number, -- seconds since it last lost HP (math.huge = never)
	sinceSpottingS: number, -- seconds since its last first-detection of an enemy (math.huge = never)
	nearestEnemyM: number, -- distance to the nearest enemy vehicle (math.huge = none)
	spotted: boolean, -- team-visible to the enemy
	hpFraction: number, -- hp / maxHp
	mechanicActive: boolean, -- siege engaged, speed mode on, boost/turbo/cooling active
}

local Modifiers = {}

local STAT_KEYS: { StatKey } = {
	"damage",
	"damageRollMin",
	"penetration",
	"penetrationRollMin",
	"reloadTime",
	"aimTime",
	"dispersion",
	"bloomMovement",
	"bloomHullTraverse",
	"bloomTurretTraverse",
	"bloomAfterShot",
	"shellVelocity",
	"shellSwapTime",
	"ammoCapacity",
	"turretTraverse",
	"gunDepression",
	"gunElevation",
	"enginePower",
	"topSpeed",
	"reverseSpeed",
	"hullTraverse",
	"terrainResistance",
	"loadLimit",
	"hp",
	"moduleHp",
	"repairTime",
	"damagedModulePenalty",
	"fireChance",
	"fireDuration",
	"crewInjuryChance",
	"spallFactor",
	"stunDuration",
	"ramDamageDealt",
	"ramDamageTaken",
	"fallDamage",
	"viewRange",
	"camoStationary",
	"camoMoving",
	"camoAfterShot",
	"camoNet",
	"signalRange",
	"crewLevel",
	"consumableCooldown",
	"crewXp",
	"mechanicChargeTime",
	"mechanicCooldown",
	"mechanicDuration",
	"mechanicCharges",
	"mechanicFactor",
}
--- Every Content.StatKey in declaration order (Modifiers.spec checks it against Types/Content).
Modifiers.STAT_KEYS = table.freeze(STAT_KEYS)

local MODULE_KINDS: { InternalModuleKind } = {
	"Engine",
	"AmmoRack",
	"FuelTank",
	"Gun",
	"TurretRing",
	"Optics",
	"TrackLeft",
	"TrackRight",
}
--- Internal module kinds in deterministic order (the module-qualifier slots).
Modifiers.MODULE_KINDS = table.freeze(MODULE_KINDS)

--- Stats that accept a `module` qualifier (content-schema §7: moduleHp, repairTime, damagedModulePenalty).
local QUALIFIED: { StatKey } = { "moduleHp", "repairTime", "damagedModulePenalty" }
Modifiers.QUALIFIED_STATS = table.freeze(QUALIFIED)

local NUM_STATS = #STAT_KEYS
local NUM_MODULES = #MODULE_KINDS
local NUM_SLOTS = NUM_STATS + #QUALIFIED * NUM_MODULES

local STAT_INDEX: { [string]: number } = {}
for i, key in STAT_KEYS do
	STAT_INDEX[key] = i
end
local MODULE_INDEX: { [string]: number } = {}
for i, kind in MODULE_KINDS do
	MODULE_INDEX[kind] = i
end
local QUALIFIED_INDEX: { [string]: number } = {}
for i, key in QUALIFIED do
	QUALIFIED_INDEX[key] = i
end

local CONDITIONS: { [string]: boolean } = {
	Always = true,
	Stationary = true,
	StationaryArmed = true,
	Moving = true,
	TurretTraversing = true,
	AfterShot = true,
	AfterTakingDamage = true,
	AfterSpotting = true,
	NearEnemy = true,
	Spotted = true,
	LowHp = true,
	MechanicActive = true,
}

--- hp <= LOW_HP_FRACTION × maxHp counts as "LowHp" (Types/Content StatCondition).
Modifiers.LOW_HP_FRACTION = 0.25

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

--- 1-based index of a StatKey (nil for unknown keys).
function Modifiers.statIndex(stat: string): number?
	return STAT_INDEX[stat]
end

--- True when `stat` takes a module qualifier.
function Modifiers.isQualified(stat: string): boolean
	return QUALIFIED_INDEX[stat] ~= nil
end

-- Accumulator slot of (stat, module); module nil = the unqualified slot. nil for unknown stat/module pairs.
local function slotOf(stat: string, module: string?): number?
	local index = STAT_INDEX[stat]
	if index == nil then
		return nil
	end
	if module == nil then
		return index
	end
	local q = QUALIFIED_INDEX[stat]
	local m = MODULE_INDEX[module]
	if q == nil or m == nil then
		return nil
	end
	return NUM_STATS + (q - 1) * NUM_MODULES + m
end

--- True when the modifier is well-formed (known stat and op, finite value, qualifier only where allowed, known
--- condition).
function Modifiers.isValid(mod: StatModifier): boolean
	if type(mod) ~= "table" or STAT_INDEX[mod.stat] == nil or not finite(mod.value) then
		return false
	end
	if mod.op ~= "add" and mod.op ~= "mul" then
		return false
	end
	if mod.module ~= nil and slotOf(mod.stat, mod.module) == nil then
		return false
	end
	return mod.condition == nil or CONDITIONS[mod.condition] == true
end

--- True for unconditional modifiers (condition nil or "Always").
function Modifiers.isAlways(mod: StatModifier): boolean
	return mod.condition == nil or mod.condition == "Always"
end

--- The modifier's value applied at share `scale` (nil = 1): add → value × s, mul → max(0, 1 + (value − 1) × s).
function Modifiers.scaledValue(mod: StatModifier, scale: number?): number
	local s = if scale ~= nil and finite(scale) then scale else 1
	if mod.op == "mul" then
		return math.max(0, 1 + (mod.value - 1) * s)
	end
	return mod.value * s
end

--- A fresh accumulator (identity: every add 0, every mul 1).
function Modifiers.newAccumulator(): Accumulator
	local add = table.create(NUM_SLOTS, 0)
	local mul = table.create(NUM_SLOTS, 1)
	return { add = add, mul = mul, applied = 0, ignored = 0 }
end

--- Resets every slot to the identity (no allocation).
function Modifiers.reset(acc: Accumulator)
	local add, mul = acc.add, acc.mul
	for i = 1, NUM_SLOTS do
		add[i] = 0
		mul[i] = 1
	end
	acc.applied = 0
	acc.ignored = 0
end

--- Folds one modifier at share `scale` into the accumulator (condition is NOT checked here). Returns false (and
--- counts it in `acc.ignored`) when the modifier is invalid.
function Modifiers.push(acc: Accumulator, mod: StatModifier, scale: number?): boolean
	if not Modifiers.isValid(mod) then
		acc.ignored += 1
		return false
	end
	local slot = slotOf(mod.stat, mod.module) :: number
	local value = Modifiers.scaledValue(mod, scale)
	if mod.op == "mul" then
		acc.mul[slot] *= value
	else
		acc.add[slot] += value
	end
	acc.applied += 1
	return true
end

--- Folds every modifier of `list` (nil = none). `which` selects by condition: "always" (default) = only
--- unconditional ones, "all" = every modifier regardless of condition, "conditional" = only conditional ones.
--- Returns how many were applied.
function Modifiers.pushList(
	acc: Accumulator,
	list: { StatModifier }?,
	scale: number?,
	which: ("always" | "all" | "conditional")?
): number
	if list == nil then
		return 0
	end
	local mode = which or "always"
	local n = 0
	for _, mod in list do
		local always = Modifiers.isAlways(mod)
		local take = mode == "all" or (mode == "always" and always) or (mode == "conditional" and not always)
		if take and Modifiers.push(acc, mod, scale) then
			n += 1
		end
	end
	return n
end

--- Σ add of a stat (the unqualified slot plus the `module` slot when given).
function Modifiers.addOf(acc: Accumulator, stat: StatKey, module: InternalModuleKind?): number
	local slot = slotOf(stat, nil)
	if slot == nil then
		return 0
	end
	local total = acc.add[slot]
	if module ~= nil then
		local q = slotOf(stat, module)
		if q ~= nil then
			total += acc.add[q]
		end
	end
	return total
end

--- Π mul of a stat (the unqualified slot times the `module` slot when given).
function Modifiers.mulOf(acc: Accumulator, stat: StatKey, module: InternalModuleKind?): number
	local slot = slotOf(stat, nil)
	if slot == nil then
		return 1
	end
	local total = acc.mul[slot]
	if module ~= nil then
		local q = slotOf(stat, module)
		if q ~= nil then
			total *= acc.mul[q]
		end
	end
	return total
end

--- (base + Σ add) × Π mul for one stat (qualified stats combine the "every module" and the `module` slots).
function Modifiers.apply(acc: Accumulator, stat: StatKey, base: number, module: InternalModuleKind?): number
	return (base + Modifiers.addOf(acc, stat, module)) * Modifiers.mulOf(acc, stat, module)
end

--- True when the accumulator holds any modifier for `stat` (either slot).
function Modifiers.touches(acc: Accumulator, stat: StatKey, module: InternalModuleKind?): boolean
	return Modifiers.addOf(acc, stat, module) ~= 0 or Modifiers.mulOf(acc, stat, module) ~= 1
end

--- One-shot resolution without an accumulator: (base + Σ add) × Π mul over the modifiers of `list` on `stat`
--- (every condition counts; callers pre-filter). Allocation-free.
function Modifiers.resolve(base: number, stat: StatKey, list: { StatModifier }?, scale: number?): number
	if list == nil then
		return base
	end
	local add, mul = 0, 1
	for _, mod in list do
		if mod.stat == stat and mod.module == nil and Modifiers.isValid(mod) then
			local value = Modifiers.scaledValue(mod, scale)
			if mod.op == "mul" then
				mul *= value
			else
				add += value
			end
		end
	end
	return (base + add) * mul
end

--------------------------------------------------------------------------------
-- Conditions
--------------------------------------------------------------------------------

--- A neutral Conditions record: stationary since spawn (0 s), nothing fired/hit/spotted, no enemy near, healthy.
function Modifiers.newConditions(): Conditions
	return {
		moving = false,
		stationaryForS = 0,
		turretTraversing = false,
		sinceShotS = math.huge,
		sinceDamageS = math.huge,
		sinceSpottingS = math.huge,
		nearestEnemyM = math.huge,
		spotted = false,
		hpFraction = 1,
		mechanicActive = false,
	}
end

local function within(since: number, duration: number?): boolean
	return duration ~= nil and finite(since) and since >= 0 and since < duration
end

--- Whether `mod`'s condition holds for `c` (StatCondition rules in Types/Content). Timed conditions hold for
--- `durationS` after the event (half-open: [0, durationS)); NearEnemy holds within `rangeM` (inclusive).
function Modifiers.holds(mod: StatModifier, c: Conditions): boolean
	local cond = mod.condition
	if cond == nil or cond == "Always" then
		return true
	elseif cond == "Stationary" then
		return not c.moving
	elseif cond == "StationaryArmed" then
		return not c.moving and c.stationaryForS >= Config.Spotting.STATIONARY_ARM_S
	elseif cond == "Moving" then
		return c.moving
	elseif cond == "TurretTraversing" then
		return c.turretTraversing
	elseif cond == "AfterShot" then
		return within(c.sinceShotS, mod.durationS)
	elseif cond == "AfterTakingDamage" then
		return within(c.sinceDamageS, mod.durationS)
	elseif cond == "AfterSpotting" then
		return within(c.sinceSpottingS, mod.durationS)
	elseif cond == "NearEnemy" then
		return mod.rangeM ~= nil and c.nearestEnemyM <= mod.rangeM
	elseif cond == "Spotted" then
		return c.spotted
	elseif cond == "LowHp" then
		return c.hpFraction <= Modifiers.LOW_HP_FRACTION
	elseif cond == "MechanicActive" then
		return c.mechanicActive
	end
	return false
end

--- Folds the modifiers of `list` whose condition holds for `c` (unconditional ones included). Returns the count.
function Modifiers.pushHolding(acc: Accumulator, list: { StatModifier }?, c: Conditions, scale: number?): number
	if list == nil then
		return 0
	end
	local n = 0
	for _, mod in list do
		if Modifiers.holds(mod, c) and Modifiers.push(acc, mod, scale) then
			n += 1
		end
	end
	return n
end

--- Splits `list` into the modifiers on `stats` and the rest (setup-time helper, allocates two arrays): used to hand
--- a system only the stats it does not apply itself (e.g. GunState applies ActiveCooling's reloadTime).
function Modifiers.partition(
	list: { StatModifier }?,
	stats: { [string]: boolean }
): ({ StatModifier }, { StatModifier })
	local inside, outside = {}, {}
	if list ~= nil then
		for _, mod in list do
			if stats[mod.stat] then
				table.insert(inside, mod)
			else
				table.insert(outside, mod)
			end
		end
	end
	return inside, outside
end

return Modifiers
