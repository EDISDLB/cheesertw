--!strict
--[[
	Vehicle/Mechanics/Hydropneumatic — passive suspension pitch for Medium tanks (00-DECISIONS §4: +4° depression /
	+3° elevation after 0.75 s still; 03-R7).

	Purpose:          Passive machine: Off (moving or airborne) → Engaging (stationary, settling) → On (settled for
	                  settleS) with the gun-arc bonus while On (gunDepression / gunElevation adds).
	Dependencies:     Mechanics/Common, Types/Content (type-only).
	State:            One record per vehicle (phase, exact settle-complete time, prebuilt modifier list).
	Validation:       Negative / non-finite bonuses count as 0 and settleS falls back to 0.75 s. There is nothing to
	                  activate: activate/deactivate always return (false, "PASSIVE").
	Error handling:   No throws.
	Performance notes: O(1); the two bonus modifiers are built once in new().

	The settle point is exact: when the context reports stationaryForS (time since the hull stopped), the bonus
	starts at now − stationaryForS + settleS, not at the next tick boundary. VehicleSim applies the same rule to the
	gun arcs it hands TurretSim (state.gunDepressionBonusDeg).
]]

local Common = require("./Common")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatModifier = ContentTypes.StatModifier
type Phase = Common.Phase
type Context = Common.Context
type Snapshot = Common.Snapshot

export type Spec = {
	kind: "Hydropneumatic",
	depressionBonusDeg: number,
	elevationBonusDeg: number,
	settleS: number,
}

export type State = {
	kind: "Hydropneumatic",
	spec: Spec,
	phase: Phase,
	phaseStart: number, -- when the hull stopped (Engaging/On) or started moving (Off)
	phaseEnd: number, -- settle-complete time while Engaging, else math.huge
	time: number,
	settleS: number,
	depressionBonusDeg: number,
	elevationBonusDeg: number,
	bonus: { StatModifier }, -- prebuilt: gunDepression add, gunElevation add
}

local Hydropneumatic = {}

local DEFAULT_SETTLE_S = 0.75

function Hydropneumatic.new(spec: Spec, now: number?): State
	local t = Common.time(now, 0)
	local dep = Common.nonNegative(spec.depressionBonusDeg, 0)
	local elev = Common.nonNegative(spec.elevationBonusDeg, 0)
	local bonus: { StatModifier } = {
		{ stat = "gunDepression", op = "add", value = dep },
		{ stat = "gunElevation", op = "add", value = elev },
	}
	return {
		kind = "Hydropneumatic",
		spec = spec,
		phase = "Off",
		phaseStart = t,
		phaseEnd = math.huge,
		time = t,
		settleS = Common.nonNegative(spec.settleS, DEFAULT_SETTLE_S),
		depressionBonusDeg = dep,
		elevationBonusDeg = elev,
		bonus = table.freeze(bonus),
	}
end

--- Follows the hull: stationary and grounded for settleS → On; stationary for less → Engaging; moving → Off.
--- Without a context the phase only completes a pending settle. Returns true on a phase change.
function Hydropneumatic.update(state: State, now: number, ctx: Context?): boolean
	local t = Common.time(now, state.time)
	if t < state.time then
		t = state.time
	end
	state.time = t
	local before = state.phase
	if ctx ~= nil then
		local still = Common.nonNegative(ctx.stationaryForS, 0)
		if not ctx.alive or not ctx.grounded or still <= 0 then
			if state.phase ~= "Off" then
				state.phase = "Off"
				state.phaseStart = t
				state.phaseEnd = math.huge
			end
		else
			local stopped = t - still
			local settled = stopped + state.settleS
			if Common.reached(t, settled) then
				if state.phase ~= "On" then
					state.phase = "On"
					state.phaseStart = math.max(stopped, settled)
					state.phaseEnd = math.huge
				end
			else
				state.phase = "Engaging"
				state.phaseStart = stopped
				state.phaseEnd = settled
			end
		end
	elseif state.phase == "Engaging" and Common.reached(t, state.phaseEnd) then
		state.phase = "On"
		state.phaseStart = state.phaseEnd
		state.phaseEnd = math.huge
	end
	return state.phase ~= before
end

--- Passive mechanic: nothing to activate.
function Hydropneumatic.activate(_state: State, _now: number, _ctx: Context?): (boolean, string?)
	return false, "PASSIVE"
end

--- Passive mechanic: nothing to deactivate.
function Hydropneumatic.deactivate(_state: State, _now: number, _ctx: Context?): (boolean, string?)
	return false, "PASSIVE"
end

--- Settled: the arc bonus applies.
function Hydropneumatic.isActive(state: State): boolean
	return state.phase == "On"
end

--- (depression bonus, elevation bonus) in degrees right now (0, 0 unless settled).
function Hydropneumatic.bonusDeg(state: State): (number, number)
	if state.phase == "On" then
		return state.depressionBonusDeg, state.elevationBonusDeg
	end
	return 0, 0
end

--- The arc bonus as StatModifiers while settled, else nil.
function Hydropneumatic.modifiers(state: State): { StatModifier }?
	if state.phase == "On" then
		return state.bonus
	end
	return nil
end

function Hydropneumatic.nextChange(state: State): number
	return state.phaseEnd
end

function Hydropneumatic.snapshot(state: State, now: number, out: Snapshot?): Snapshot
	return Common.fill(
		out or Common.newSnapshot(),
		"Hydropneumatic",
		state.phase,
		state.phase == "On",
		state.phaseStart,
		state.phaseEnd,
		state.phase == "Engaging",
		Common.time(now, state.time),
		math.huge,
		math.huge,
		0
	)
end

return Hydropneumatic
