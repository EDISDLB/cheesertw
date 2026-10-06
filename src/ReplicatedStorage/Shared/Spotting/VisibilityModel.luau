--!strict
--[[
	Spotting/VisibilityModel — the spotting math (00-DECISIONS §5): spot distance with its caps, camouflage
	composition (stationary/moving, after-shot multiplier, paint, armed net), foliage with the 15 m discounts and the
	stack cap, view range composition (runtime multiplier, smoke, weather, conditional modifiers), proximity, the
	pair check interval curve and the replication tier.

	Purpose:          Pure formulas shared by SpottingSystem (server), the client HUD (VR circle, own camo readout) and
	                  bots/tools. Every number comes from Config.Spotting (read at call time, live-override aware).
	Dependencies:     Config (Spotting), Types/Vehicle (CamoStats), Types/Content (StatModifier, FoliageKind),
	                  Types/Spotting (ReplicationTier).
	State:            None.
	Validation:       Non-finite or negative inputs degrade safely: NaN/inf view range counts as 0, camo is clamped to
	                  [0, 1], negative foliage counts as 0, NaN distances never spot.
	Error handling:   No throws.
	Performance notes: Allocation-free; called per pair check and per LOS ray by SpottingSystem.

	Formulas (m, s):
	  spotDistance(VR, camo) = min(MAX_SPOT_RANGE_M, VR − (VR − FORMULA_FLOOR_M)·camo)   (VR <= floor: VR)
	  totalCamo(body, foliage) = min(CAMO_TOTAL_CAP, body + min(FOLIAGE_STACK_CAP, foliage))
	  bodyCamo = base[moving|stationary] × (afterShotMul while < SHOT_CAMO_PENALTY_S after a shot) + paint
	             + (net once stationary >= STATIONARY_ARM_S)
	  effectiveFoliage(total, nearObserver, nearShooter) = min(FOLIAGE_STACK_CAP, max(0, total − near…))
	  checkInterval(d) = min(CHECK_INTERVAL_MAX_S, piecewiseLinear(CHECK_INTERVAL_CURVE, d))
	  scheduledInterval(d, phase) = checkInterval(d) × (1 − CHECK_JITTER_FRACTION × phase), phase ∈ [0, 1)
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local VehicleTypes = require("@game/ReplicatedStorage/Shared/Types/Vehicle")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local SpottingTypes = require("@game/ReplicatedStorage/Shared/Types/Spotting")

type CamoStats = VehicleTypes.CamoStats
type StatModifier = ContentTypes.StatModifier
type StatKey = ContentTypes.StatKey
type FoliageKind = ContentTypes.FoliageKind
type ReplicationTier = SpottingTypes.ReplicationTier

local VisibilityModel = {}

-- Tolerance for durations built from tick times (101/30 − 11/30 = 2.9999999999999996): a window of 3 s armed at
-- tick k is armed at tick k + 90 exactly.
local TIME_EPS = 1e-6

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function nonNegative(n: any): number
	if finite(n) and n > 0 then
		return n
	end
	return 0
end

--------------------------------------------------------------------------------
-- Spot distance and camouflage caps
--------------------------------------------------------------------------------

--- Spot distance (m) of an observer with effective view range `viewRangeM` against a target whose total camo on the
--- ray is `camo` (0..1, clamped). VR is not capped; the result is (00-DECISIONS §5). An observer with VR at or
--- below FORMULA_FLOOR_M spots nothing beyond its own VR (proximity still applies).
function VisibilityModel.spotDistance(viewRangeM: number, camo: number): number
	local C = Config.Spotting
	local vr = nonNegative(viewRangeM)
	local floor = C.FORMULA_FLOOR_M
	if vr <= floor then
		return math.min(C.MAX_SPOT_RANGE_M, vr)
	end
	local k = if camo == camo then math.clamp(camo, 0, 1) else 1
	return math.min(C.MAX_SPOT_RANGE_M, vr - (vr - floor) * k)
end

--- Total camo of one ray: min(CAMO_TOTAL_CAP, body + min(FOLIAGE_STACK_CAP, foliage)).
function VisibilityModel.totalCamo(bodyCamo: number, foliage: number): number
	local C = Config.Spotting
	return math.min(C.CAMO_TOTAL_CAP, nonNegative(bodyCamo) + math.min(C.FOLIAGE_STACK_CAP, nonNegative(foliage)))
end

--- True when a target at `distanceM` is inside the proximity radius (spotted through any cover).
function VisibilityModel.isWithinProximity(distanceM: number): boolean
	return distanceM <= Config.Spotting.PROXIMITY_RADIUS_M
end

--- Whether a target at `distanceM` with ray camo `camo` is spotted, assuming the ray is clear (proximity or formula).
function VisibilityModel.isSpotted(distanceM: number, viewRangeM: number, camo: number): boolean
	if not (distanceM == distanceM) then
		return false
	end
	return distanceM <= Config.Spotting.PROXIMITY_RADIUS_M
		or distanceM <= VisibilityModel.spotDistance(viewRangeM, camo)
end

--------------------------------------------------------------------------------
-- Camouflage composition
--------------------------------------------------------------------------------

--- Moving per 00-DECISIONS §5: hull speed above STOP_SPEED_KMH or hull yaw rate above MOVING_YAW_RATE_DEG_S.
function VisibilityModel.isMoving(speedKmh: number, yawRateDegS: number?): boolean
	local C = Config.Spotting
	local v = if finite(speedKmh) then math.abs(speedKmh) else 0
	local w = if finite(yawRateDegS) then math.abs(yawRateDegS :: number) else 0
	return v > C.STOP_SPEED_KMH or w > C.MOVING_YAW_RATE_DEG_S
end

--- Nets and masts are armed after STATIONARY_ARM_S stationary and drop the moment the hull moves.
function VisibilityModel.isStationaryArmed(moving: boolean, stationaryForS: number): boolean
	return not moving and finite(stationaryForS) and stationaryForS >= Config.Spotting.STATIONARY_ARM_S - TIME_EPS
end

--- After-shot camo multiplier active `sinceShotS` seconds after a shot (nil = never fired).
function VisibilityModel.isShotCamoPenaltyActive(sinceShotS: number?): boolean
	return sinceShotS ~= nil
		and finite(sinceShotS)
		and (sinceShotS :: number) >= -TIME_EPS
		and (sinceShotS :: number) < Config.Spotting.SHOT_CAMO_PENALTY_S - TIME_EPS
end

--- Shooter-side 15 m foliage rule active `sinceShotS` seconds after a shot (nil = never fired).
function VisibilityModel.isShotFoliagePenaltyActive(sinceShotS: number?): boolean
	return sinceShotS ~= nil
		and finite(sinceShotS)
		and (sinceShotS :: number) >= -TIME_EPS
		and (sinceShotS :: number) < Config.Spotting.SHOT_FOLIAGE_PENALTY_S - TIME_EPS
end

--- Body camo from already-resolved parts: base × (afterShotMul if shotActive) + paint + (net if armed).
function VisibilityModel.composeBodyCamo(
	base: number,
	afterShotMul: number,
	paint: number,
	net: number,
	armed: boolean,
	shotActive: boolean
): number
	local b = nonNegative(base)
	if shotActive then
		local mul = if finite(afterShotMul) then math.clamp(afterShotMul, 0, 1) else 1
		b *= mul
	end
	local total = b + nonNegative(paint)
	if armed then
		total += nonNegative(net)
	end
	return total
end

--- Body camo of a vehicle (00-DECISIONS §5): base[moving|stationary] × shotMult + paint + armed net. Crew and
--- equipment are already folded into CamoStats by StatsCalculator. `stationaryForS` = time since the hull stopped
--- (ignored while moving); `sinceShotS` = time since the last shot (nil = never fired).
function VisibilityModel.bodyCamo(camo: CamoStats, moving: boolean, stationaryForS: number, sinceShotS: number?): number
	local base = if moving then camo.moving else camo.stationary
	return VisibilityModel.composeBodyCamo(
		base,
		camo.afterShotMul,
		camo.paint,
		camo.net,
		VisibilityModel.isStationaryArmed(moving, stationaryForS),
		VisibilityModel.isShotCamoPenaltyActive(sinceShotS)
	)
end

--- Default after-shot camo multiplier by calibre (00-DECISIONS §5 "Paint / shot"): clamp(.40 − .0025(cal − 20),
--- .05, .40). StatsCalculator uses it when a gun has no explicit `camoAfterShotMul`.
function VisibilityModel.defaultShotCamoMul(caliberMm: number): number
	local C = Config.Spotting
	local cal = if finite(caliberMm) then caliberMm else C.SHOT_CAMO_REF_CALIBER_MM
	local raw = C.SHOT_CAMO_MUL_MAX - C.SHOT_CAMO_MUL_PER_MM * (cal - C.SHOT_CAMO_REF_CALIBER_MM)
	return math.clamp(raw, C.SHOT_CAMO_MUL_MIN, C.SHOT_CAMO_MUL_MAX)
end

--------------------------------------------------------------------------------
-- Foliage
--------------------------------------------------------------------------------

--- Concealment of one foliage volume: its explicit `concealment` if set, else the kind default; capped at
--- FOLIAGE_CONCEALMENT_MAX. Unknown kinds conceal nothing (grass is never a volume).
function VisibilityModel.foliageConcealment(kind: FoliageKind | string, concealment: number?): number
	local C = Config.Spotting
	local value = if finite(concealment) then concealment :: number else C.FOLIAGE_CONCEALMENT[kind]
	if value == nil then
		return 0
	end
	return math.clamp(value, 0, C.FOLIAGE_CONCEALMENT_MAX)
end

--- Foliage that conceals on one ray after the 15 m rules, capped at FOLIAGE_STACK_CAP. `total` is the sum over the
--- whole ray (World:sightLine), `nearObserver` the sum over its first FOLIAGE_OBSERVER_CLEAR_M, `nearShooter` the
--- sum over its last FOLIAGE_SHOOTER_CLEAR_M (pass 0 unless the target fired within SHOT_FOLIAGE_PENALTY_S).
--- A volume crossing both clear zones is subtracted twice (clamped at 0): it can only happen on rays shorter than
--- 30 m + 2 radii, i.e. inside the proximity radius in practice.
function VisibilityModel.effectiveFoliage(total: number, nearObserver: number, nearShooter: number): number
	local remaining = nonNegative(total) - nonNegative(nearObserver) - nonNegative(nearShooter)
	return math.min(Config.Spotting.FOLIAGE_STACK_CAP, math.max(0, remaining))
end

--------------------------------------------------------------------------------
-- View range
--------------------------------------------------------------------------------

--- Applies the conditional modifiers Spotting owns to one stat: (base + Σadd) × Πmul over modifiers on `stat` whose
--- condition holds. Conditions: Stationary (not moving), StationaryArmed (armed), Moving, Spotted (exposed). Other
--- conditions ("Always" is pre-folded; AfterShot, NearEnemy… belong to other systems) are ignored.
function VisibilityModel.applyConditional(
	base: number,
	stat: StatKey,
	modifiers: { StatModifier }?,
	moving: boolean,
	armed: boolean,
	exposed: boolean
): number
	if modifiers == nil or #modifiers == 0 then
		return base
	end
	local add, mul = 0, 1
	for _, m in modifiers do
		if m.stat ~= stat or not finite(m.value) then
			continue
		end
		local cond = m.condition
		local holds = (cond == "Stationary" and not moving)
			or (cond == "StationaryArmed" and armed)
			or (cond == "Moving" and moving)
			or (cond == "Spotted" and exposed)
		if holds then
			if m.op == "add" then
				add += m.value
			elseif m.op == "mul" then
				mul *= m.value
			end
		end
	end
	return (base + add) * mul
end

--- Effective view range (m): VR × runtime multiplier × (SMOKE_INSIDE_VR_MULT inside smoke) × visibilityMult.
--- Non-finite or negative parts count as 0 (VR) / 1 (multipliers). VR is never capped.
function VisibilityModel.effectiveViewRange(
	viewRangeM: number,
	viewRangeMul: number?,
	inSmoke: boolean?,
	visibilityMult: number?
): number
	local C = Config.Spotting
	local vr = nonNegative(viewRangeM)
	local mul = if finite(viewRangeMul) and (viewRangeMul :: number) >= 0 then viewRangeMul :: number else 1
	local weather = if finite(visibilityMult) and (visibilityMult :: number) >= 0
		then visibilityMult :: number
		else C.VISIBILITY_MULT_DEFAULT
	local smoke = if inSmoke == true then C.SMOKE_INSIDE_VR_MULT else 1
	return vr * mul * smoke * weather
end

--------------------------------------------------------------------------------
-- Scheduling and replication
--------------------------------------------------------------------------------

--- Unclamped interval (s) from CHECK_INTERVAL_CURVE (piecewise linear, constant beyond the end anchors).
function VisibilityModel.rawCheckInterval(distanceM: number): number
	local curve = Config.Spotting.CHECK_INTERVAL_CURVE
	local n = #curve
	local first = curve[1]
	if not (distanceM > first[1]) then
		return first[2] -- also NaN: check as often as possible
	end
	for i = 2, n do
		local hi = curve[i]
		if distanceM <= hi[1] then
			local lo = curve[i - 1]
			local span = hi[1] - lo[1]
			if span <= 0 then
				return hi[2]
			end
			return lo[2] + (hi[2] - lo[2]) * (distanceM - lo[1]) / span
		end
	end
	return curve[n][2]
end

--- Pair check interval (s) at a hull distance, clamped to CHECK_INTERVAL_MAX_S.
function VisibilityModel.checkInterval(distanceM: number): number
	return math.min(Config.Spotting.CHECK_INTERVAL_MAX_S, VisibilityModel.rawCheckInterval(distanceM))
end

--- The interval actually scheduled: checkInterval shortened by the pair jitter (`phase` in [0, 1)).
function VisibilityModel.scheduledInterval(distanceM: number, phase: number): number
	local j = math.clamp(Config.Spotting.CHECK_JITTER_FRACTION, 0, 1)
	local p = if phase == phase then math.clamp(phase, 0, 1) else 0
	return VisibilityModel.checkInterval(distanceM) * (1 - j * p)
end

--- What replication may send about an enemy at `distanceM` from the receiving vehicle: full state only when
--- team-visible and within ENEMY_DRAW_RANGE_M, minimap records when team-visible beyond it, nothing otherwise.
function VisibilityModel.replicationTier(teamVisible: boolean, distanceM: number): ReplicationTier
	if not teamVisible then
		return "None"
	end
	if distanceM <= Config.Spotting.ENEMY_DRAW_RANGE_M then
		return "Full"
	end
	return "Minimap"
end

return VisibilityModel
