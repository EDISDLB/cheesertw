--!strict
--[[
	Vehicle/Mechanics/SiegeMode — the TD Sniper/Support siege toggle (00-DECISIONS §4: on 2.0 s / off 1.25 s, aim
	×0.4, dispersion ×0.85, +8° dep / +6° elev, ≤ 10 km/h, hull traverse ×0.5; 03-R7 travel reverse = forward ×0.9,
	optional auto-engage after 0.5 s stationary).

	Purpose:          Pure state machine Off → Engaging (engageS) → On → Disengaging (disengageS) → Off with the
	                  speed cap (while not Off), the travel-mode reverse ratio (while Off), the siege modifiers
	                  (while On) and the player's auto-engage option.
	Dependencies:     Mechanics/Common, Types/Content (type-only).
	State:            One record per vehicle (phase, exact phase start/end times, auto-engage flags).
	Validation:       Non-finite / non-positive transition times fall back to the 00-DECISIONS defaults; activation
	                  is rejected while dead or mid-transition (as VehicleSim: a key press only acts from Off or On).
	Error handling:   No throws; rejected requests return (false, reason).
	Performance notes: O(1), allocation-free (modifiers() returns the spec's own frozen list).

	Auto-engage (player option): engages once the hull has been stationary for autoEngageS. A manual disengage
	suppresses it until the hull moves again (so it never fights the player). Placement: Mechanics/Controller runs
	this machine and writes its phase into VehicleSim's external mode (VehicleSim applies the speed cap, travel
	reverse and the mobility/arc modifiers of the phase); modifiers() also feed StatsCalculator's runtime, which
	applies the non-mobility ones (aim, dispersion).
]]

local Common = require("./Common")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatModifier = ContentTypes.StatModifier
type Phase = Common.Phase
type Context = Common.Context
type Snapshot = Common.Snapshot

export type Spec = {
	kind: "SiegeMode",
	engageS: number,
	disengageS: number,
	maxSpeedKmh: number,
	autoEngageS: number?,
	travelReverseRatio: number?,
	modifiers: { StatModifier },
}

export type State = {
	kind: "SiegeMode",
	spec: Spec,
	phase: Phase,
	phaseStart: number,
	phaseEnd: number, -- math.huge while the phase is untimed (Off, On)
	time: number,
	engageS: number,
	disengageS: number,
	autoEngage: boolean, -- player option (needs spec.autoEngageS)
	autoArmed: boolean, -- false after a manual disengage until the hull moves
}

local SiegeMode = {}

local DEFAULT_ENGAGE_S = 2.0
local DEFAULT_DISENGAGE_S = 1.25

local function setPhase(state: State, phase: Phase, startT: number, duration: number?)
	state.phase = phase
	state.phaseStart = startT
	state.phaseEnd = if duration ~= nil then startT + duration else math.huge
end

--- A new siege machine in travel mode. `opts.autoEngage` = the player's auto-engage option (default true when the
--- spec defines autoEngageS).
function SiegeMode.new(spec: Spec, now: number?, opts: { autoEngage: boolean? }?): State
	local t = Common.time(now, 0)
	local auto = spec.autoEngageS ~= nil
	if opts ~= nil and opts.autoEngage ~= nil then
		auto = opts.autoEngage and spec.autoEngageS ~= nil
	end
	return {
		kind = "SiegeMode",
		spec = spec,
		phase = "Off",
		phaseStart = t,
		phaseEnd = math.huge,
		time = t,
		engageS = Common.positive(spec.engageS, DEFAULT_ENGAGE_S),
		disengageS = Common.positive(spec.disengageS, DEFAULT_DISENGAGE_S),
		autoEngage = auto,
		autoArmed = true,
	}
end

--- Advances the transitions to `now` (exact phase-end times) and runs auto-engage. Returns true on a phase change.
function SiegeMode.update(state: State, now: number, ctx: Context?): boolean
	local t = Common.time(now, state.time)
	if t < state.time then
		t = state.time
	end
	state.time = t
	local changed = false
	if state.phase == "Engaging" and Common.reached(t, state.phaseEnd) then
		setPhase(state, "On", state.phaseEnd, nil)
		changed = true
	elseif state.phase == "Disengaging" and Common.reached(t, state.phaseEnd) then
		setPhase(state, "Off", state.phaseEnd, nil)
		changed = true
	end
	if ctx ~= nil then
		local autoS = state.spec.autoEngageS
		if autoS ~= nil and ctx.stationaryForS < autoS then
			state.autoArmed = true -- the hull moved (or has not settled): re-arm auto-engage
		end
		if
			state.autoEngage
			and state.autoArmed
			and autoS ~= nil
			and state.phase == "Off"
			and ctx.alive
			and ctx.stationaryForS >= autoS
		then
			setPhase(state, "Engaging", t, state.engageS)
			changed = true
		end
	end
	return changed
end

--- Starts engaging (from Off). Rejected while dead ("DEAD"), engaged ("ALREADY_ACTIVE") or disengaging
--- ("IN_TRANSITION").
function SiegeMode.activate(state: State, now: number, ctx: Context?): (boolean, string?)
	SiegeMode.update(state, now, nil)
	if ctx ~= nil and not ctx.alive then
		return false, "DEAD"
	end
	if state.phase == "Engaging" or state.phase == "On" then
		return false, "ALREADY_ACTIVE"
	elseif state.phase == "Disengaging" then
		return false, "IN_TRANSITION"
	end
	setPhase(state, "Engaging", state.time, state.engageS)
	return true, nil
end

--- Starts disengaging (from On). Rejected when not sieged ("NOT_ACTIVE") or mid-engage ("IN_TRANSITION").
function SiegeMode.deactivate(state: State, now: number, ctx: Context?): (boolean, string?)
	SiegeMode.update(state, now, nil)
	if ctx ~= nil and not ctx.alive then
		return false, "DEAD"
	end
	if state.phase == "Off" or state.phase == "Disengaging" then
		return false, "NOT_ACTIVE"
	elseif state.phase == "Engaging" then
		return false, "IN_TRANSITION"
	end
	setPhase(state, "Disengaging", state.time, state.disengageS)
	state.autoArmed = false
	return true, nil
end

--- The mechanic key: engages from Off, disengages from On (a press mid-transition is ignored, as in VehicleSim).
function SiegeMode.toggle(state: State, now: number, ctx: Context?): (boolean, string?)
	SiegeMode.update(state, now, nil)
	if state.phase == "On" then
		return SiegeMode.deactivate(state, now, ctx)
	end
	return SiegeMode.activate(state, now, ctx)
end

--- Sieged ("MechanicActive"): the transition has completed.
function SiegeMode.isActive(state: State): boolean
	return state.phase == "On"
end

--- Speed cap (km/h) in both directions: maxSpeedKmh from the moment engaging starts until fully disengaged.
function SiegeMode.speedCapKmh(state: State): number
	if state.phase == "Off" then
		return math.huge
	end
	return Common.nonNegative(state.spec.maxSpeedKmh, 10)
end

--- Travel-mode reverse ratio (reverse = forward × ratio) while Off; nil otherwise or when the spec has none.
function SiegeMode.travelReverseRatio(state: State): number?
	if state.phase ~= "Off" then
		return nil
	end
	return state.spec.travelReverseRatio
end

--- The siege modifiers while sieged (the spec's list), else nil.
function SiegeMode.modifiers(state: State): { StatModifier }?
	if state.phase == "On" then
		return state.spec.modifiers
	end
	return nil
end

--- Absolute time of the next scheduled phase change (math.huge = none).
function SiegeMode.nextChange(state: State): number
	return state.phaseEnd
end

--- HUD / replication view at `now` (call update first).
function SiegeMode.snapshot(state: State, now: number, out: Snapshot?): Snapshot
	local timed = state.phase == "Engaging" or state.phase == "Disengaging"
	return Common.fill(
		out or Common.newSnapshot(),
		"SiegeMode",
		state.phase,
		state.phase == "On",
		state.phaseStart,
		state.phaseEnd,
		timed,
		Common.time(now, state.time),
		math.huge,
		math.huge,
		0
	)
end

return SiegeMode
