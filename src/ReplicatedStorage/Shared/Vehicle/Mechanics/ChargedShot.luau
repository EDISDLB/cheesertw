--!strict
--[[
	Vehicle/Mechanics/ChargedShot — the hold-to-charge fire signature (00-DECISIONS §4 Tier XI: 1.5 s → dispersion
	×0.6 OR +10 % damage; roster §2.7 `iu_gorrtund` / `dc_zenith`).

	Purpose:          Charge machine Off → Engaging (charging) → On (fully charged) run by GunState on the fire
	                  trigger: hold to charge while the gun is loaded, release to fire; the bonus applies only when the
	                  charge was full. Releasing early fires a normal shot with no penalty (GunState decides).
	Dependencies:     Mechanics/Common, Types/Content (type-only).
	State:            One record per vehicle (owned by GunState).
	Validation:       chargeTimeS falls back to 1.5 s; the bonus factor of the effect not chosen is 1 (content
	                  validation rejects specs that set both).
	Error handling:   No throws; begin() while dead returns (false, "DEAD").
	Performance notes: O(1), allocation-free.

	Movement rule: roster §2.7 (the mechanic spec) allows moving while charging; the HUD spec (ui-ux H-05) resets
	the arc on hull movement. Default follows roster §2.7; `opts.resetOnMove = true` switches to the HUD rule (the
	charge restarts at 0 while the hull moves > Config.Spotting.STOP_SPEED_KMH and resumes when it stops).
]]

local Common = require("./Common")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatModifier = ContentTypes.StatModifier
type Phase = Common.Phase
type Context = Common.Context
type Snapshot = Common.Snapshot

export type Spec = {
	kind: "ChargedShot",
	chargeTimeS: number,
	effect: "Accuracy" | "Damage",
	dispersionMul: number?,
	damageMul: number?,
}

export type State = {
	kind: "ChargedShot",
	spec: Spec,
	phase: Phase,
	phaseStart: number, -- charge start while charging/charged
	phaseEnd: number, -- full-charge time while charging, else math.huge
	time: number,
	chargeTimeS: number,
	dispersionMul: number, -- applied to a fully charged shot
	damageMul: number,
	resetOnMove: boolean,
}

local ChargedShot = {}

local DEFAULT_CHARGE_S = 1.5

function ChargedShot.new(spec: Spec, now: number?, opts: { resetOnMove: boolean? }?): State
	local t = Common.time(now, 0)
	local accuracy = spec.effect == "Accuracy"
	return {
		kind = "ChargedShot",
		spec = spec,
		phase = "Off",
		phaseStart = t,
		phaseEnd = math.huge,
		time = t,
		chargeTimeS = Common.positive(spec.chargeTimeS, DEFAULT_CHARGE_S),
		dispersionMul = if accuracy then Common.positive(spec.dispersionMul, 1) else 1,
		damageMul = if accuracy then 1 else Common.positive(spec.damageMul, 1),
		resetOnMove = opts ~= nil and opts.resetOnMove == true,
	}
end

--- Advances the charge to `now`; with resetOnMove, a moving hull (ctx.stationaryForS = 0, i.e. faster than the
--- stop speed) holds the charge at 0 until it stops. Death drops the charge. True on a phase change.
function ChargedShot.update(state: State, now: number, ctx: Context?): boolean
	local t = Common.time(now, state.time)
	if t < state.time then
		t = state.time
	end
	state.time = t
	local before = state.phase
	if state.phase ~= "Off" and ctx ~= nil and not ctx.alive then
		state.phase = "Off"
		state.phaseEnd = math.huge
	elseif state.phase ~= "Off" and state.resetOnMove and ctx ~= nil and ctx.stationaryForS <= 0 then
		state.phase = "Engaging"
		state.phaseStart = t
		state.phaseEnd = t + state.chargeTimeS
	elseif state.phase == "Engaging" and Common.reached(t, state.phaseEnd) then
		state.phase = "On"
	end
	return state.phase ~= before
end

--- Starts charging at `at` (<= now; GunState passes the exact moment the gun became loaded while the trigger was
--- held). No-op while already charging.
function ChargedShot.begin(state: State, at: number, ctx: Context?): (boolean, string?)
	if ctx ~= nil and not ctx.alive then
		return false, "DEAD"
	end
	if state.phase ~= "Off" then
		return false, "ACTIVE"
	end
	local t = Common.time(at, state.time)
	state.phase = "Engaging"
	state.phaseStart = t
	state.phaseEnd = t + state.chargeTimeS
	if t > state.time then
		state.time = t
	end
	ChargedShot.update(state, state.time, nil)
	return true, nil
end

--- Releases the trigger at `now`: returns true when the charge was full, and resets to Off.
function ChargedShot.release(state: State, now: number): boolean
	ChargedShot.update(state, now, nil)
	local full = state.phase == "On"
	state.phase = "Off"
	state.phaseEnd = math.huge
	return full
end

--- Drops the charge without firing (ammo swap, destroyed gun, death).
function ChargedShot.cancel(state: State)
	state.phase = "Off"
	state.phaseEnd = math.huge
end

--- Generic contract: activate = begin now; deactivate = cancel.
function ChargedShot.activate(state: State, now: number, ctx: Context?): (boolean, string?)
	return ChargedShot.begin(state, now, ctx)
end

function ChargedShot.deactivate(state: State, _now: number, _ctx: Context?): (boolean, string?)
	if state.phase == "Off" then
		return false, "NOT_ACTIVE"
	end
	ChargedShot.cancel(state)
	return true, nil
end

--- Charging or charged.
function ChargedShot.isActive(state: State): boolean
	return state.phase ~= "Off"
end

--- Charge progress 0..1 at `now` (0 when idle).
function ChargedShot.progress(state: State, now: number): number
	if state.phase == "Off" then
		return 0
	elseif state.phase == "On" then
		return 1
	end
	return Common.progress(state.phaseStart, state.phaseEnd, Common.time(now, state.time))
end

--- Shot multipliers for a shot released with (`charged` = true) or without a full charge: (dispersion, damage).
function ChargedShot.shotMultipliers(state: State, charged: boolean): (number, number)
	if charged then
		return state.dispersionMul, state.damageMul
	end
	return 1, 1
end

--- No standing stat modifiers: the bonus rides the shot (ShotInfo.dispersionMul / damageMul).
function ChargedShot.modifiers(_state: State): { StatModifier }?
	return nil
end

function ChargedShot.nextChange(state: State): number
	return if state.phase == "Engaging" then state.phaseEnd else math.huge
end

function ChargedShot.snapshot(state: State, now: number, out: Snapshot?): Snapshot
	local t = Common.time(now, state.time)
	local snap = Common.fill(
		out or Common.newSnapshot(),
		"ChargedShot",
		state.phase,
		state.phase ~= "Off",
		state.phaseStart,
		state.phaseEnd,
		state.phase == "Engaging",
		t,
		math.huge,
		math.huge,
		0
	)
	if state.phase == "Off" then
		snap.progress = 0
	end
	return snap
end

return ChargedShot
