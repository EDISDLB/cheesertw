--!strict
--[[
	Combat/Penetration — one shell vs one plate: normalization (incl. the 2-calibre rule), overmatch (3-calibre
	rule), ricochet threshold and decision, effective thickness, HEAT air-gap loss, the HE/HESH screen cost, and the
	truncated-normal penetration / damage rolls.

	Purpose:          The per-plate rules of 00-DECISIONS §1 in one place, shared by ShotResolver (server), the Armor
	                  Inspector and the client reticle's pen indicator (same numbers everywhere: REG-ARM-02/03).
	Dependencies:     Config (Combat), Combat/ArmorGeometry (effectiveThickness), Combat/Ballistics (falloff),
	                  Core/RNG (type), Types/Combat.
	State:            None.
	Validation:       Unknown shell kinds behave like HEAT-less non-kinetic shells (no 2-/3-calibre rules, no
	                  ricochet unless the shell's own ricochetAngleDeg < 90). Non-finite rolls fall back to 0.
	Error handling:   No throws; NaN thickness/pen yields "Stopped" (a shell never penetrates on garbage input).
	Performance notes: resolvePlate() writes into a caller-owned PlateResult when `out` is given (no allocation).
	                  roll() consumes 2 RNG draws per attempt (Box–Muller); 95.4 % of rolls take one attempt.

	Rules (θ = raw impact angle from the plate normal, T = nominal thickness, cal = caliber, all mm/deg):
	  * Ricochet: θ > ricochetAngleDeg (AP/APCR 70, HEAT 85, HE/HESH never) unless kinetic and cal > 3 T.
	    The ricochet test uses the raw angle (normalization never moves the threshold). Pen × RICOCHET_PEN_MUL.
	  * n' = n, or n × 1.4 × cal / (2 T) for kinetic shells with cal > 2 T (strict; REG-ARM-03).
	  * T_eff = T / max(0.05, cos(max(0, θ − n'))); Main/Layered/Spaced penetrate when pen >= T_eff.
	  * Spaced and Layered plates subtract T_eff from the remaining pen; HE/HESH pay 3 T on Spaced plates.
	  * HEAT after any plate: pen × max(0, 1 − 0.5 × gap_m) (applied by the caller across each air gap).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local ArmorGeometry = require("./ArmorGeometry")
local Ballistics = require("./Ballistics")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")
local RNGModule = require("@game/ReplicatedStorage/Shared/Core/RNG")

type RNG = RNGModule.RNG
type CombatShell = CombatTypes.CombatShell
type PlateKind = CombatTypes.PlateKind
type PlateResult = CombatTypes.PlateResult

local Penetration = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

--- True for AP / APCR.
function Penetration.isKinetic(kind: string): boolean
	return (Config.Combat.KINETIC :: any)[kind] == true
end

--- True for HE / HESH.
function Penetration.isExplosive(kind: string): boolean
	return (Config.Combat.EXPLOSIVE :: any)[kind] == true
end

--------------------------------------------------------------------------------
-- RNG
--------------------------------------------------------------------------------

--- The roll spread for a mode: ROLL_SPREAD (±25 %) or COMPETITIVE_SPREAD (±10 %).
function Penetration.spreadFor(competitive: boolean?): number
	local C = Config.Combat
	return if competitive then C.COMPETITIVE_SPREAD else C.ROLL_SPREAD
end

--- Truncated-normal roll around `mean`: σ = spread / ROLL_SPREAD_SIGMAS × mean, re-rolled while |z| exceeds
--- ROLL_SPREAD_SIGMAS (up to ROLL_RESAMPLE_TRIES draws), then clamped. Always within mean × (1 ± spread).
function Penetration.roll(mean: number, rng: RNG, spread: number?): number
	local C = Config.Combat
	if not isFinite(mean) then
		return 0
	end
	local s = spread or C.ROLL_SPREAD
	if not (s > 0) or mean == 0 then
		return mean
	end
	local limit = C.ROLL_SPREAD_SIGMAS
	local z = 0
	for _ = 1, C.ROLL_RESAMPLE_TRIES do
		z = rng:normal(0, 1)
		if math.abs(z) <= limit then
			return mean * (1 + s * z / limit)
		end
	end
	z = math.clamp(z, -limit, limit)
	return mean * (1 + s * z / limit)
end

--- Rolled penetration (mm) at `distanceM` from the muzzle (falloff first, then the roll).
function Penetration.rollPenetration(shell: CombatShell, distanceM: number, rng: RNG, spread: number?): number
	return Penetration.roll(Ballistics.penetrationAt(shell, distanceM), rng, spread)
end

--- Rolled HP damage, rounded to whole HP (halves up). Never negative.
function Penetration.rollDamage(alpha: number, rng: RNG, spread: number?): number
	local value = Penetration.roll(alpha, rng, spread)
	if not (value > 0) then
		return 0
	end
	return math.floor(value + 0.5)
end

--------------------------------------------------------------------------------
-- Plate rules
--------------------------------------------------------------------------------

--- Overmatch (3-calibre rule): kinetic shell with caliber > THREE_CALIBER_RATIO × T (strict) never ricochets.
function Penetration.isOvermatch(kind: string, caliberMm: number, thicknessMm: number): boolean
	return Penetration.isKinetic(kind) and caliberMm > Config.Combat.THREE_CALIBER_RATIO * thicknessMm
end

--- 2-calibre rule: kinetic shell with caliber > TWO_CALIBER_RATIO × T (strict) gets boosted normalization.
function Penetration.isTwoCaliber(kind: string, caliberMm: number, thicknessMm: number): boolean
	return Penetration.isKinetic(kind) and caliberMm > Config.Combat.TWO_CALIBER_RATIO * thicknessMm
end

--- Normalization n' (deg) this shell gets on a plate of `thicknessMm`, and whether the 2-calibre rule applied.
function Penetration.normalizationDeg(shell: CombatShell, thicknessMm: number): (number, boolean)
	local C = Config.Combat
	local n = shell.normalizationDeg
	if not isFinite(n) or n < 0 then
		n = 0
	end
	if Penetration.isExplosive(shell.kind) or shell.kind == "HEAT" then
		return if shell.kind == "HEAT" then n else 0, false
	end
	if Penetration.isTwoCaliber(shell.kind, shell.caliberMm, thicknessMm) then
		return n * C.TWO_CALIBER_FACTOR * shell.caliberMm / (C.TWO_CALIBER_RATIO * thicknessMm), true
	end
	return n, false
end

--- True when this shell can ricochet off a plate of `thicknessMm` at all (family allows it, not overmatched).
function Penetration.canRicochet(shell: CombatShell, thicknessMm: number): boolean
	if Penetration.isExplosive(shell.kind) then
		return false
	end
	if not (shell.ricochetAngleDeg < 90) then
		return false
	end
	return not Penetration.isOvermatch(shell.kind, shell.caliberMm, thicknessMm)
end

--- True when the raw impact angle exceeds the shell's ricochet angle (strict) and the shell can ricochet.
function Penetration.ricochets(shell: CombatShell, thicknessMm: number, angleDeg: number): boolean
	return Penetration.canRicochet(shell, thicknessMm) and angleDeg > shell.ricochetAngleDeg
end

--- Pen multiplier after a ricochet (AP/APCR 0.75, HEAT 1.0; unknown kinds 1.0).
function Penetration.ricochetPenMul(kind: string): number
	local mul = (Config.Combat.RICOCHET_PEN_MUL :: any)[kind]
	return if type(mul) == "number" then mul else 1
end

--- HEAT jet factor across an air gap of `gapM` metres: max(0, 1 − HEAT_GAP_LOSS_PER_M × gap).
function Penetration.heatGapFactor(gapM: number): number
	if not (gapM > 0) then
		return 1
	end
	return math.max(0, 1 - Config.Combat.HEAT_GAP_LOSS_PER_M * gapM)
end

--- Effective thickness (mm) this shell sees on a plate: T / max(floor, cos(max(0, θ − n'))).
function Penetration.effectiveThickness(shell: CombatShell, thicknessMm: number, angleDeg: number): number
	local n = Penetration.normalizationDeg(shell, thicknessMm)
	return ArmorGeometry.effectiveThickness(thicknessMm, angleDeg, n)
end

--- An empty PlateResult for reuse.
function Penetration.newPlateResult(): PlateResult
	return {
		outcome = "Stopped",
		angleDeg = 0,
		normalizationDeg = 0,
		effectiveMm = 0,
		overmatch = false,
		twoCaliber = false,
		penBefore = 0,
		penAfter = 0,
	}
end

--- One plate interaction. `pen` is the remaining (already rolled) penetration in mm. Outcomes:
---   Ricochet   — penAfter = pen × RICOCHET_PEN_MUL (the caller reflects the ray and enforces RICOCHET_MAX).
---   Penetrated — Spaced/Layered: penAfter = pen − T_eff (HE/HESH on Spaced: pen − 3 T, must stay > 0);
---                Main: penAfter = pen − T_eff.
---   Stopped    — not enough pen (penAfter = pen − cost, <= 0 for Spaced HE).
function Penetration.resolvePlate(
	shell: CombatShell,
	plateKind: PlateKind,
	thicknessMm: number,
	angleDeg: number,
	pen: number,
	out: PlateResult?
): PlateResult
	local C = Config.Combat
	local r = out or Penetration.newPlateResult()
	local t = thicknessMm
	r.angleDeg = angleDeg
	r.penBefore = pen
	r.overmatch = Penetration.isOvermatch(shell.kind, shell.caliberMm, t)
	r.twoCaliber = false
	r.normalizationDeg = 0

	if Penetration.isExplosive(shell.kind) then
		if plateKind == "Spaced" then
			local cost = C.HE_SCREEN_PEN_MUL * t
			r.effectiveMm = cost
			r.penAfter = pen - cost
			r.outcome = if r.penAfter > 0 then "Penetrated" else "Stopped"
			return r
		end
		local tEff = ArmorGeometry.effectiveThickness(t, angleDeg, 0)
		r.effectiveMm = tEff
		r.penAfter = pen - tEff
		r.outcome = if pen >= tEff then "Penetrated" else "Stopped"
		return r
	end

	if Penetration.ricochets(shell, t, angleDeg) then
		r.outcome = "Ricochet"
		r.effectiveMm = ArmorGeometry.effectiveThickness(t, angleDeg, 0)
		r.penAfter = pen * Penetration.ricochetPenMul(shell.kind)
		return r
	end

	local n, twoCaliber = Penetration.normalizationDeg(shell, t)
	r.normalizationDeg = n
	r.twoCaliber = twoCaliber
	local tEff = ArmorGeometry.effectiveThickness(t, angleDeg, n)
	r.effectiveMm = tEff
	r.penAfter = pen - tEff
	r.outcome = if pen >= tEff then "Penetrated" else "Stopped"
	return r
end

return Penetration
