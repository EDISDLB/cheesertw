--!strict
--[[
	Combat/CrewEffects — crew level curves and the crew-injury effects table (00-DECISIONS §2 "Crew injury",
	§4 "L", "Reload", "Other stats").

	Purpose:          One definition of how crew level L scales stats, shared by StatsCalculator (battle-start
	                  resolution), GunState (reload), Dispersion (aim/dispersion), TurretSim/VehicleSim (traverse),
	                  Spotting (view range) and DamageModel (runtime injury ratios).
	Dependencies:     Config (Combat), Types/Content, Types/Combat.
	State:            None (INJURY_EFFECTS / DUTY_OF_STAT are frozen data).
	Validation:       Levels are clamped so a curve never reaches 0 or goes negative.
	Error handling:   No throws.
	Performance notes: Arithmetic over <= 6 crew members; multipliers() writes into a caller-owned table.

	Curves:  reloadFactor(L) = 0.875 / (0.00375 L + 0.5)   (× reload time; 1.000 at L 100, 1.273 at L 50)
	         statFactor(L)   = 0.57 + 0.0043 L               (1.000 at L 100, 0.785 at L 50)
	Duties:  Commander -> view range; Gunner -> aim time, dispersion, turret traverse; Driver -> hull traverse,
	         repair time (OUR DESIGN CHOICE: the driver doubles as mechanic); Loader -> reload (loaders averaged).
	Injury:  an injured member works at CREW_INJURED_LEVEL (50); an injured commander costs every other member
	         COMMANDER_INJURED_PENALTY (10) levels and turns Sixth Sense off. Never killed.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")

type CrewRole = ContentTypes.CrewRole
type CrewCombatState = CombatTypes.CrewCombatState

export type CrewStat =
	"reloadTime"
	| "aimTime"
	| "dispersion"
	| "turretTraverse"
	| "hullTraverse"
	| "viewRange"
	| "repairTime"
--- "mul" = stat × statFactor(L); "div" = stat ÷ statFactor(L); "reload" = stat × reloadFactor(L).
export type CrewCurve = "mul" | "div" | "reload"
export type CrewMultipliers = {
	reloadTime: number,
	aimTime: number,
	dispersion: number,
	turretTraverse: number,
	hullTraverse: number,
	viewRange: number,
	repairTime: number,
	sixthSense: boolean,
}

local CrewEffects = {}

--- The crew-injury effects table (exported for StatsCalculator / GunState): each stat, the duty that drives it
--- and how the duty's level enters it.
CrewEffects.INJURY_EFFECTS = table.freeze({
	reloadTime = table.freeze({ duty = "Loader", curve = "reload" }),
	aimTime = table.freeze({ duty = "Gunner", curve = "div" }),
	dispersion = table.freeze({ duty = "Gunner", curve = "div" }),
	turretTraverse = table.freeze({ duty = "Gunner", curve = "mul" }),
	hullTraverse = table.freeze({ duty = "Driver", curve = "mul" }),
	viewRange = table.freeze({ duty = "Commander", curve = "mul" }),
	repairTime = table.freeze({ duty = "Driver", curve = "div" }),
}) :: { [CrewStat]: { duty: CrewRole, curve: CrewCurve } }

local STATS: { CrewStat } = {
	"reloadTime",
	"aimTime",
	"dispersion",
	"turretTraverse",
	"hullTraverse",
	"viewRange",
	"repairTime",
}
--- Stats in deterministic order.
CrewEffects.STATS = table.freeze(STATS)

local MIN_FACTOR = 1e-3

--- Reload multiplier at crew level L (× base reload).
function CrewEffects.reloadFactor(level: number): number
	local C = Config.Combat
	local denom = C.RELOAD_CURVE_PER_LEVEL * level + C.RELOAD_CURVE_BASE
	if not (denom > MIN_FACTOR) then
		denom = MIN_FACTOR
	end
	return C.RELOAD_CURVE_NUMERATOR / denom
end

--- f(L) = STAT_CURVE_BASE + STAT_CURVE_PER_LEVEL × L (× view range / traverse, ÷ aim / dispersion / repair).
function CrewEffects.statFactor(level: number): number
	local C = Config.Combat
	local f = C.STAT_CURVE_BASE + C.STAT_CURVE_PER_LEVEL * level
	if not (f > MIN_FACTOR) then
		return MIN_FACTOR
	end
	return f
end

--- Multiplier on a stat when its duty's level changes from `baseLevel` to `level`.
function CrewEffects.ratio(curve: CrewCurve, baseLevel: number, level: number): number
	if curve == "reload" then
		return CrewEffects.reloadFactor(level) / CrewEffects.reloadFactor(baseLevel)
	elseif curve == "div" then
		return CrewEffects.statFactor(baseLevel) / CrewEffects.statFactor(level)
	end
	return CrewEffects.statFactor(level) / CrewEffects.statFactor(baseLevel)
end

local function holdsDuty(member: CrewCombatState, duty: CrewRole): boolean
	if member.role == duty then
		return true
	end
	for _, r in member.also do
		if r == duty then
			return true
		end
	end
	return false
end

--- True when the crew's commander (any member with Commander duty) is injured.
function CrewEffects.commanderInjured(crew: { CrewCombatState }): boolean
	for _, member in crew do
		if member.injured and holdsDuty(member, "Commander") then
			return true
		end
	end
	return false
end

--- Current effective level of one member (injury and the injured-commander penalty applied).
function CrewEffects.memberLevel(member: CrewCombatState, commanderInjured: boolean): number
	local C = Config.Combat
	if member.injured then
		return C.CREW_INJURED_LEVEL
	end
	if commanderInjured and not holdsDuty(member, "Commander") then
		return member.level - C.COMMANDER_INJURED_PENALTY
	end
	return member.level
end

--- Average current level of the members holding `duty` (nil when nobody holds it). `healthy` ignores injuries.
function CrewEffects.dutyLevel(crew: { CrewCombatState }, duty: CrewRole, healthy: boolean?): number?
	local commanderDown = if healthy then false else CrewEffects.commanderInjured(crew)
	local sum, n = 0, 0
	for _, member in crew do
		if holdsDuty(member, duty) then
			sum += if healthy then member.level else CrewEffects.memberLevel(member, commanderDown)
			n += 1
		end
	end
	if n == 0 then
		return nil
	end
	return sum / n
end

--- Runtime multipliers from injuries relative to the levels VehicleStats was resolved with (`crewLevels`, else the
--- healthy crew). Writes into `out` when given.
function CrewEffects.multipliers(
	crew: { CrewCombatState },
	crewLevels: { [CrewRole]: number }?,
	out: CrewMultipliers?
): CrewMultipliers
	local m: CrewMultipliers = out
		or {
			reloadTime = 1,
			aimTime = 1,
			dispersion = 1,
			turretTraverse = 1,
			hullTraverse = 1,
			viewRange = 1,
			repairTime = 1,
			sixthSense = true,
		}
	for _, stat: CrewStat in STATS do
		local effect = CrewEffects.INJURY_EFFECTS[stat]
		local now = CrewEffects.dutyLevel(crew, effect.duty)
		local value = 1
		if now ~= nil then
			local base = (if crewLevels ~= nil then crewLevels[effect.duty] else nil)
				or CrewEffects.dutyLevel(crew, effect.duty, true)
				or now
			value = CrewEffects.ratio(effect.curve, base, now)
		end
		(m :: any)[stat] = value
	end
	m.sixthSense = not CrewEffects.commanderInjured(crew)
	return m
end

return CrewEffects
