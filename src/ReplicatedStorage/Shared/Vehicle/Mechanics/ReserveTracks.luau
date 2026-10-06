--!strict
--[[
	Vehicle/Mechanics/ReserveTracks — automatic track replacement (content-schema §5.5: destroyed tracks replaced
	after `repairS` instead of the field repair, `charges` per battle, `cooldownS` between uses; Tier XI / Event
	only and not assigned to a launch Apex).

	Purpose:          Replacement machine Off (armed) → On (replacing, repairS) → Cooldown (cooldownS) → Off. A track
	                  destroyed while armed starts a replacement job; the other side destroyed during the job joins it
	                  (one charge per job). The charge is consumed when the job completes; a job whose sides were all
	                  repaired by other means (repair kit, field repair) is cancelled without spending the charge.
	Dependencies:     Mechanics/Common, Types/Content (type-only).
	State:            One record per vehicle (pending sides, job end, charges).
	Validation:       charges floor to whole numbers >= 0; only TrackLeft / TrackRight are accepted.
	Error handling:   No throws; onTrackDestroyed returns false (field repair applies) when unarmed, out of charges,
	                  cooling down or dead.
	Performance notes: O(1), allocation-free.

	The caller (BattleInstance / DamageModel owner) restores the module when update() reports a side as replaced
	(OUR DESIGN CHOICE: to the same state a field repair gives, Damaged at REPAIR_RESTORE_FRACTION).
]]

local Common = require("./Common")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatModifier = ContentTypes.StatModifier
type InternalModuleKind = ContentTypes.InternalModuleKind
type Phase = Common.Phase
type Context = Common.Context
type Snapshot = Common.Snapshot

export type Spec = { kind: "ReserveTracks", charges: number, repairS: number, cooldownS: number }

export type State = {
	kind: "ReserveTracks",
	spec: Spec,
	phase: Phase,
	phaseStart: number,
	phaseEnd: number,
	time: number,
	repairS: number,
	cooldownS: number,
	charges: number,
	maxCharges: number,
	left: boolean, -- TrackLeft is part of the running job
	right: boolean,
}

local ReserveTracks = {}

function ReserveTracks.new(spec: Spec, now: number?): State
	local t = Common.time(now, 0)
	local charges = math.floor(Common.nonNegative(spec.charges, 0))
	return {
		kind = "ReserveTracks",
		spec = spec,
		phase = "Off",
		phaseStart = t,
		phaseEnd = math.huge,
		time = t,
		repairS = Common.nonNegative(spec.repairS, 0),
		cooldownS = Common.nonNegative(spec.cooldownS, 0),
		charges = charges,
		maxCharges = charges,
		left = false,
		right = false,
	}
end

local function setSide(state: State, side: InternalModuleKind, value: boolean): boolean
	if side == "TrackLeft" then
		state.left = value
		return true
	elseif side == "TrackRight" then
		state.right = value
		return true
	end
	return false
end

--- Advances the job/cooldown to `now`. Returns (left replaced, right replaced) for a job that completed during this
--- call (exact completion time = phaseStart + repairS).
function ReserveTracks.update(state: State, now: number, _ctx: Context?): (boolean, boolean)
	local t = Common.time(now, state.time)
	if t < state.time then
		t = state.time
	end
	state.time = t
	local doneLeft, doneRight = false, false
	if state.phase == "On" and Common.reached(t, state.phaseEnd) then
		doneLeft, doneRight = state.left, state.right
		state.left, state.right = false, false
		state.charges = math.max(0, state.charges - 1)
		state.phase = "Cooldown"
		state.phaseStart = state.phaseEnd
		state.phaseEnd = state.phaseStart + state.cooldownS
	end
	if state.phase == "Cooldown" and Common.reached(t, state.phaseEnd) then
		state.phase = "Off"
		state.phaseStart = state.phaseEnd
		state.phaseEnd = math.huge
	end
	return doneLeft, doneRight
end

--- A track was destroyed at `now`. Returns true when the reserve took it over (job started or joined).
function ReserveTracks.onTrackDestroyed(state: State, side: InternalModuleKind, now: number, ctx: Context?): boolean
	ReserveTracks.update(state, now, nil)
	if ctx ~= nil and not ctx.alive then
		return false
	end
	if side ~= "TrackLeft" and side ~= "TrackRight" then
		return false
	end
	if state.phase == "On" then
		return setSide(state, side, true)
	end
	if state.phase ~= "Off" or state.charges < 1 then
		return false
	end
	setSide(state, side, true)
	state.phase = "On"
	state.phaseStart = state.time
	state.phaseEnd = state.time + state.repairS
	return true
end

--- A track left the Destroyed state by other means: it leaves the job; an empty job is cancelled (no charge spent).
function ReserveTracks.onTrackRepaired(state: State, side: InternalModuleKind, now: number)
	ReserveTracks.update(state, now, nil)
	if state.phase ~= "On" then
		return
	end
	setSide(state, side, false)
	if not state.left and not state.right then
		state.phase = "Off"
		state.phaseStart = state.time
		state.phaseEnd = math.huge
	end
end

--- Automatic mechanic: no manual activation.
function ReserveTracks.activate(_state: State, _now: number, _ctx: Context?): (boolean, string?)
	return false, "AUTOMATIC"
end

function ReserveTracks.deactivate(_state: State, _now: number, _ctx: Context?): (boolean, string?)
	return false, "AUTOMATIC"
end

--- A replacement is running.
function ReserveTracks.isActive(state: State): boolean
	return state.phase == "On"
end

--- Armed: a destroyed track would be taken over right now.
function ReserveTracks.isArmed(state: State): boolean
	return state.phase == "Off" and state.charges >= 1
end

function ReserveTracks.modifiers(_state: State): { StatModifier }?
	return nil
end

function ReserveTracks.nextChange(state: State): number
	return state.phaseEnd
end

function ReserveTracks.snapshot(state: State, now: number, out: Snapshot?): Snapshot
	local t = Common.time(now, state.time)
	local cooldownLeft = 0
	if state.phase == "Cooldown" then
		cooldownLeft = state.phaseEnd - t
	elseif state.phase == "On" then
		cooldownLeft = state.phaseEnd - t + state.cooldownS
	end
	return Common.fill(
		out or Common.newSnapshot(),
		"ReserveTracks",
		state.phase,
		state.phase == "On",
		state.phaseStart,
		state.phaseEnd,
		state.phase ~= "Off",
		t,
		state.charges,
		state.maxCharges,
		cooldownLeft
	)
end

return ReserveTracks
