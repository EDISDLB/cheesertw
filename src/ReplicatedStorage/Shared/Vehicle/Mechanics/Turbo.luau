--!strict
--[[
	Vehicle/Mechanics/Turbo — the active engine boost signature (00-DECISIONS §4 Tier XI: power ×1.25 for 6 s, 40 s
	cooldown; roster §2.7 `nf_rimeburst`).

	Purpose:          Timed machine Off → On (durationS) → Cooldown (cooldownS) → Off with the enginePower
	                  modifier while On. A destroyed engine or track (ctx.mobile = false) or death cancels an active
	                  boost (the cooldown starts at that moment) and blocks new activations (roster §2.7).
	Dependencies:     Mechanics/Common, Types/Content (type-only).
	State:            One record per vehicle.
	Validation:       powerMul <= 0 / non-finite → 1 (no effect); durations fall back to 0.
	Error handling:   No throws; rejected activations return (false, "DEAD" | "IMMOBILE" | "ACTIVE" | "COOLDOWN").
	Performance notes: O(1); the modifier list is built once in new().

	Exotic (Tier XI / Event only, Common.allowedOn). VehicleSim currently runs its own copy of this machine for the
	power factor; this module is the reusable contract (same phases and timings).
]]

local Common = require("./Common")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatModifier = ContentTypes.StatModifier
type Phase = Common.Phase
type Context = Common.Context
type Snapshot = Common.Snapshot

export type Spec = { kind: "Turbo", powerMul: number, durationS: number, cooldownS: number }

export type State = {
	kind: "Turbo",
	spec: Spec,
	phase: Phase,
	phaseStart: number,
	phaseEnd: number,
	time: number,
	durationS: number,
	cooldownS: number,
	powerMul: number,
	boost: { StatModifier },
}

local Turbo = {}

function Turbo.new(spec: Spec, now: number?): State
	local t = Common.time(now, 0)
	local mul = Common.positive(spec.powerMul, 1)
	return {
		kind = "Turbo",
		spec = spec,
		phase = "Off",
		phaseStart = t,
		phaseEnd = math.huge,
		time = t,
		durationS = Common.nonNegative(spec.durationS, 0),
		cooldownS = Common.nonNegative(spec.cooldownS, 0),
		powerMul = mul,
		boost = table.freeze({ { stat = "enginePower", op = "mul", value = mul } :: StatModifier }),
	}
end

--- Advances to `now`; cancels an active boost when the vehicle is dead or immobile. True on a phase change.
function Turbo.update(state: State, now: number, ctx: Context?): boolean
	local changed = Common.timedUpdate(state, now)
	if state.phase == "On" and ctx ~= nil and (not ctx.alive or not ctx.mobile) then
		Common.timedCancel(state)
		changed = true
	end
	return changed
end

--- Starts the boost (from Off).
function Turbo.activate(state: State, now: number, ctx: Context?): (boolean, string?)
	Common.timedUpdate(state, now)
	if ctx ~= nil and not ctx.alive then
		return false, "DEAD"
	elseif ctx ~= nil and not ctx.mobile then
		return false, "IMMOBILE"
	elseif state.phase == "On" then
		return false, "ACTIVE"
	elseif state.phase == "Cooldown" then
		return false, "COOLDOWN"
	end
	Common.timedStart(state)
	return true, nil
end

--- Ends an active boost early (the cooldown starts now).
function Turbo.deactivate(state: State, now: number, _ctx: Context?): (boolean, string?)
	Common.timedUpdate(state, now)
	if state.phase ~= "On" then
		return false, "NOT_ACTIVE"
	end
	Common.timedCancel(state)
	return true, nil
end

function Turbo.isActive(state: State): boolean
	return state.phase == "On"
end

--- { enginePower × powerMul } while boosting, else nil.
function Turbo.modifiers(state: State): { StatModifier }?
	if state.phase == "On" then
		return state.boost
	end
	return nil
end

function Turbo.nextChange(state: State): number
	return state.phaseEnd
end

function Turbo.snapshot(state: State, now: number, out: Snapshot?): Snapshot
	local t = Common.time(now, state.time)
	local cooldownLeft = 0
	if state.phase == "Cooldown" then
		cooldownLeft = state.phaseEnd - t
	elseif state.phase == "On" then
		cooldownLeft = state.phaseEnd - t + state.cooldownS
	end
	return Common.fill(
		out or Common.newSnapshot(),
		"Turbo",
		state.phase,
		state.phase == "On",
		state.phaseStart,
		state.phaseEnd,
		state.phase ~= "Off",
		t,
		math.huge,
		math.huge,
		cooldownLeft
	)
end

return Turbo
