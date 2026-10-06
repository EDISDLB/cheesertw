--!strict
--[[
	Vehicle/Mechanics/RocketBoost — the charge-based thrust signature (00-DECISIONS §4 Tier XI: 2 × 2.5 s, +20 km/h,
	30 s cooldown; 03-R7 "cooldownS 30 per charge"; roster §2.7 `mr_updraft`: one charge per press, two boost pips
	with cooldown sweeps).

	Purpose:          Charge machine: a press spends one charge and burns for durationS (topSpeed + speedBonusKmh
	                  while On); each spent charge comes back cooldownS after ITS burn ended (independent recharge
	                  timers, OUR DESIGN CHOICE from "per charge" + the two-pip HUD). Phase: On while burning,
	                  Cooldown while no charge is available, Off when a charge is ready.
	Dependencies:     Mechanics/Common, Types/Content (type-only).
	State:            One record per vehicle with a preallocated recharge-time array (one entry per charge).
	Validation:       charges are floored to whole numbers >= 1 (mechanicCharges adds are already resolved by
	                  StatsCalculator); a destroyed engine/track (ctx.mobile = false) or death ends a burn at once
	                  and blocks presses (roster §2.7).
	Error handling:   No throws; rejected presses return (false, "DEAD" | "IMMOBILE" | "ACTIVE" | "NO_CHARGES").
	Performance notes: O(charges) per update (<= 10), allocation-free after new().

	Note: VehicleSim's built-in copy treats `charges` as per-battle uses with one global cooldown; the recharge rule
	here is the one the HUD spec describes. Battles run this machine through Mechanics/Controller (VehicleSim's
	external mode), so this rule is the live one (docs/design/vehicle-stats.md §5).
]]

local Common = require("./Common")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatModifier = ContentTypes.StatModifier
type Phase = Common.Phase
type Context = Common.Context
type Snapshot = Common.Snapshot

export type Spec = {
	kind: "RocketBoost",
	charges: number,
	durationS: number,
	speedBonusKmh: number,
	cooldownS: number,
}

export type State = {
	kind: "RocketBoost",
	spec: Spec,
	phase: Phase,
	phaseStart: number, -- burn start while On
	phaseEnd: number, -- burn end while On, else math.huge
	time: number,
	durationS: number,
	cooldownS: number,
	charges: number, -- available now
	maxCharges: number,
	rechargeAt: { number }, -- absolute return time of each spent charge (math.huge = slot unused)
	boost: { StatModifier },
}

local RocketBoost = {}

function RocketBoost.new(spec: Spec, now: number?): State
	local t = Common.time(now, 0)
	local maxCharges = math.max(1, math.floor(Common.nonNegative(spec.charges, 1)))
	local bonus = Common.nonNegative(spec.speedBonusKmh, 0)
	return {
		kind = "RocketBoost",
		spec = spec,
		phase = "Off",
		phaseStart = t,
		phaseEnd = math.huge,
		time = t,
		durationS = Common.nonNegative(spec.durationS, 0),
		cooldownS = Common.nonNegative(spec.cooldownS, 0),
		charges = maxCharges,
		maxCharges = maxCharges,
		rechargeAt = table.create(maxCharges, math.huge),
		boost = table.freeze({ { stat = "topSpeed", op = "add", value = bonus } :: StatModifier }),
	}
end

local function schedule(state: State, at: number)
	for i, v in state.rechargeAt do
		if v == math.huge then
			state.rechargeAt[i] = at
			return
		end
	end
end

local function idlePhase(state: State)
	state.phase = if state.charges >= 1 then "Off" else "Cooldown"
	state.phaseEnd = math.huge
end

local function endBurn(state: State, at: number)
	schedule(state, at + state.cooldownS)
	state.phaseStart = at
	idlePhase(state)
end

--- Advances burns and recharges to `now` (exact times); ends a burn when dead or immobile. True on a change.
function RocketBoost.update(state: State, now: number, ctx: Context?): boolean
	local t = Common.time(now, state.time)
	if t < state.time then
		t = state.time
	end
	state.time = t
	local before, chargesBefore = state.phase, state.charges
	if state.phase == "On" and Common.reached(t, state.phaseEnd) then
		endBurn(state, state.phaseEnd)
	end
	for i, at in state.rechargeAt do
		if at ~= math.huge and Common.reached(t, at) then
			state.rechargeAt[i] = math.huge
			state.charges = math.min(state.maxCharges, state.charges + 1)
		end
	end
	if state.phase == "On" and ctx ~= nil and (not ctx.alive or not ctx.mobile) then
		endBurn(state, t)
	elseif state.phase ~= "On" then
		idlePhase(state)
	end
	return state.phase ~= before or state.charges ~= chargesBefore
end

--- Spends one charge and starts a burn.
function RocketBoost.activate(state: State, now: number, ctx: Context?): (boolean, string?)
	RocketBoost.update(state, now, nil)
	if ctx ~= nil and not ctx.alive then
		return false, "DEAD"
	elseif ctx ~= nil and not ctx.mobile then
		return false, "IMMOBILE"
	elseif state.phase == "On" then
		return false, "ACTIVE"
	elseif state.charges < 1 then
		return false, "NO_CHARGES"
	end
	state.charges -= 1
	state.phase = "On"
	state.phaseStart = state.time
	state.phaseEnd = state.time + state.durationS
	return true, nil
end

--- Ends a burn early (its charge starts recharging now).
function RocketBoost.deactivate(state: State, now: number, _ctx: Context?): (boolean, string?)
	RocketBoost.update(state, now, nil)
	if state.phase ~= "On" then
		return false, "NOT_ACTIVE"
	end
	endBurn(state, state.time)
	return true, nil
end

function RocketBoost.isActive(state: State): boolean
	return state.phase == "On"
end

--- { topSpeed + speedBonusKmh } while burning, else nil (VehicleSim adds the extra thrust itself).
function RocketBoost.modifiers(state: State): { StatModifier }?
	if state.phase == "On" then
		return state.boost
	end
	return nil
end

--- Earliest scheduled change: burn end or the next charge's return.
function RocketBoost.nextChange(state: State): number
	local soonest = state.phaseEnd
	for _, at in state.rechargeAt do
		if at < soonest then
			soonest = at
		end
	end
	return soonest
end

function RocketBoost.snapshot(state: State, now: number, out: Snapshot?): Snapshot
	local t = Common.time(now, state.time)
	local nextCharge = math.huge
	for _, at in state.rechargeAt do
		if at < nextCharge then
			nextCharge = at
		end
	end
	return Common.fill(
		out or Common.newSnapshot(),
		"RocketBoost",
		state.phase,
		state.phase == "On",
		state.phaseStart,
		state.phaseEnd,
		state.phase == "On",
		t,
		state.charges,
		state.maxCharges,
		if nextCharge == math.huge then 0 else nextCharge - t
	)
end

return RocketBoost
