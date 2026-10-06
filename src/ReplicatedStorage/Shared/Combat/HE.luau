--!strict
--[[
	Combat/HE — the HE / HESH damage formulas (00-DECISIONS §1 "HE (1.13 adapted)" and "Splash", §7.4 SPG stun):
	non-penetration damage at the impact point, splash on nearby vehicles, screen/destructible pen cost, burst
	radius, spall/splash module damage and artillery stun duration.

	Purpose:          Pure formulas used by ShotResolver (direct hits, screen bursts, splash lists) and by the Armor
	                  Inspector / damage log to explain HE results (REG-ARM-13).
	Dependencies:     Config (Combat), Types/Combat.
	State:            None.
	Validation:       Distances beyond the radius give 0; negative / non-finite inputs give 0 damage.
	Error handling:   No throws.
	Performance notes: Arithmetic only.

	Formulas (α = mean alpha, α_r = rolled alpha, T in mm, K = K_spall, d and R in metres):
	  non-pen direct hit : D = max(0.05 α, 0.5 α_r − 1.1 T_nominal K) × (HESH 1.15)
	  splash (others)    : D = max(0, 0.5 α_r (1 − d/R) − 1.1 T_min K)
	  screen cost        : 3 T (screens, tracks, external modules); destructibles 1 T
	  radius R           : explosionRadiusM, else caliber / 100 (direct) or 3 + 0.03 caliber (artillery)
	All HP results are whole numbers (halves round up).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")

type CombatShell = CombatTypes.CombatShell

local HE = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function wholeHp(x: number): number
	if not (x > 0) or not isFinite(x) then
		return 0
	end
	return math.floor(x + 0.5)
end

--- Pen cost (mm) of a screen / track / external module of nominal thickness `thicknessMm`.
function HE.screenCost(thicknessMm: number): number
	return Config.Combat.HE_SCREEN_PEN_MUL * thicknessMm
end

--- Pen cost (mm) of a destructible map object of thickness `thicknessMm`.
function HE.destructibleCost(thicknessMm: number): number
	return Config.Combat.HE_DESTRUCTIBLE_PEN_MUL * thicknessMm
end

--- Default burst radius (m) for a caliber: caliber/100 for direct fire, 3 + 0.03 × caliber for artillery.
function HE.defaultRadiusM(caliberMm: number, artillery: boolean?): number
	local C = Config.Combat
	if artillery then
		return C.ARTILLERY_SPLASH_BASE_M + C.ARTILLERY_SPLASH_PER_MM * caliberMm
	end
	return caliberMm * C.SPLASH_RADIUS_M_PER_MM
end

--- The shell's burst / spall radius (m): its explosionRadiusM, else the direct-fire default from its caliber.
function HE.radiusM(shell: CombatShell): number
	local r = shell.explosionRadiusM
	if isFinite(r) and r > 0 then
		return r
	end
	local fallback = HE.defaultRadiusM(shell.caliberMm, false)
	return if isFinite(fallback) and fallback > 0 then fallback else 0
end

--- Non-penetrating direct-hit HP damage at the impact point (nominal thickness of the struck plate).
function HE.nonPenDamage(
	alphaMean: number,
	alphaRolled: number,
	thicknessMm: number,
	spallFactor: number,
	kind: string
): number
	local C = Config.Combat
	local floor = C.HE_NONPEN_FLOOR * alphaMean
	local raw = C.HE_NONPEN_ALPHA_FACTOR * alphaRolled - C.HE_ARMOR_FACTOR * thicknessMm * spallFactor
	local d = if raw > floor then raw else floor
	if kind == "HESH" then
		d *= C.HESH_NONPEN_MUL
	end
	return wholeHp(d)
end

--- Splash HP damage on a vehicle whose nearest armor is `distanceM` from the burst (T_min = `thicknessMm`).
function HE.splashDamage(
	alphaRolled: number,
	distanceM: number,
	radiusM: number,
	thicknessMm: number,
	spallFactor: number
): number
	local C = Config.Combat
	if not (radiusM > 0) or not (distanceM >= 0) or distanceM >= radiusM then
		return 0
	end
	local falloff = 1 - distanceM / radiusM
	local raw = C.SPLASH_ALPHA_FACTOR * alphaRolled * falloff - C.HE_ARMOR_FACTOR * thicknessMm * spallFactor
	return wholeHp(raw)
end

--- Module damage dealt by splash to an external module `distanceM` from the burst.
function HE.splashModuleDamage(moduleDamage: number, distanceM: number, radiusM: number): number
	if not (radiusM > 0) or not (distanceM >= 0) or distanceM >= radiusM then
		return 0
	end
	return wholeHp(moduleDamage * (1 - distanceM / radiusM) * Config.Combat.SPLASH_MODULE_MUL)
end

--- Artillery stun (s) at `distanceM` from the burst: lerp(maxS, minS, d/R) × `durationMul`; 0 outside R or without
--- a stun spec.
function HE.stunDuration(shell: CombatShell, distanceM: number, radiusM: number, durationMul: number?): number
	local stun = shell.stun
	if stun == nil or not (radiusM > 0) or not (distanceM >= 0) or distanceM > radiusM then
		return 0
	end
	local f = distanceM / radiusM
	local s = (stun.maxS + (stun.minS - stun.maxS) * f) * (durationMul or 1)
	return if s > 0 and isFinite(s) then s else 0
end

return HE
