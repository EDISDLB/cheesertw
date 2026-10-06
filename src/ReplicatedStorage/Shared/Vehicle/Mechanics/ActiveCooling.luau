--!strict
--[[
	Vehicle/Mechanics/ActiveCooling — the reload/aim window signature (00-DECISIONS §4 Tier XI: 5 s, 45 s cooldown,
	reload ×0.85, aim ×0.85; roster §2.7 `ci_aurelline`: may be started mid-reload, reload progress runs at
	1 ÷ 0.85 speed while active).

	Purpose:          Timed machine Off → On (durationS) → Cooldown (cooldownS) → Off. Exposes the reload factor
	                  GunState integrates exactly (it splits reload progress at phaseEnd), the full modifier list and
	                  the list WITHOUT reloadTime for StatsCalculator's runtime (GunState already applies reloadTime,
	                  so handing both to the runtime would double it).
	Dependencies:     Mechanics/Common, Vehicle/Modifiers, Types/Content (type-only).
	State:            One record per vehicle (owned by GunState, which runs this mechanic: 00-DECISIONS §4 placement).
	Validation:       Durations fall back to 0; the reload factor is (1 + Σadd) × Πmul over reloadTime modifiers,
	                  floored at 0.05 so a bad number can never freeze or reverse a reload.
	Error handling:   No throws; rejected activations return (false, "DEAD" | "ACTIVE" | "COOLDOWN").
	Performance notes: O(1); factor and filtered list are computed once in new().
]]

local Common = require("./Common")
local Modifiers = require("../Modifiers")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type StatModifier = ContentTypes.StatModifier
type Phase = Common.Phase
type Context = Common.Context
type Snapshot = Common.Snapshot

export type Spec = { kind: "ActiveCooling", durationS: number, cooldownS: number, modifiers: { StatModifier } }

export type State = {
	kind: "ActiveCooling",
	spec: Spec,
	phase: Phase,
	phaseStart: number,
	phaseEnd: number,
	time: number,
	durationS: number,
	cooldownS: number,
	reloadFactor: number, -- × reload timers while On
	aimFactor: number, -- × aim time while On (HUD; Dispersion reads it through runtimeModifiers)
	runtime: { StatModifier }, -- spec.modifiers minus reloadTime
}

local ActiveCooling = {}

local MIN_FACTOR = 0.05

function ActiveCooling.new(spec: Spec, now: number?): State
	local t = Common.time(now, 0)
	local reload = math.max(MIN_FACTOR, Modifiers.resolve(1, "reloadTime", spec.modifiers))
	local aim = math.max(MIN_FACTOR, Modifiers.resolve(1, "aimTime", spec.modifiers))
	local _, rest = Modifiers.partition(spec.modifiers, { reloadTime = true })
	return {
		kind = "ActiveCooling",
		spec = spec,
		phase = "Off",
		phaseStart = t,
		phaseEnd = math.huge,
		time = t,
		durationS = Common.nonNegative(spec.durationS, 0),
		cooldownS = Common.nonNegative(spec.cooldownS, 0),
		reloadFactor = reload,
		aimFactor = aim,
		runtime = table.freeze(rest),
	}
end

--- Advances to `now` (exact phase ends). Death ends an active window. True on a phase change.
function ActiveCooling.update(state: State, now: number, ctx: Context?): boolean
	local changed = Common.timedUpdate(state, now)
	if state.phase == "On" and ctx ~= nil and not ctx.alive then
		Common.timedCancel(state)
		changed = true
	end
	return changed
end

--- Starts the cooling window (from Off); allowed mid-reload.
function ActiveCooling.activate(state: State, now: number, ctx: Context?): (boolean, string?)
	Common.timedUpdate(state, now)
	if ctx ~= nil and not ctx.alive then
		return false, "DEAD"
	elseif state.phase == "On" then
		return false, "ACTIVE"
	elseif state.phase == "Cooldown" then
		return false, "COOLDOWN"
	end
	Common.timedStart(state)
	return true, nil
end

--- Ends an active window early (the cooldown starts now).
function ActiveCooling.deactivate(state: State, now: number, _ctx: Context?): (boolean, string?)
	Common.timedUpdate(state, now)
	if state.phase ~= "On" then
		return false, "NOT_ACTIVE"
	end
	Common.timedCancel(state)
	return true, nil
end

function ActiveCooling.isActive(state: State): boolean
	return state.phase == "On"
end

--- Reload-timer factor at the machine's current time (1 unless active).
function ActiveCooling.currentReloadFactor(state: State): number
	return if state.phase == "On" then state.reloadFactor else 1
end

--- The full modifier list while active (garage/HUD), else nil.
function ActiveCooling.modifiers(state: State): { StatModifier }?
	if state.phase == "On" then
		return state.spec.modifiers
	end
	return nil
end

--- The modifiers StatsCalculator's runtime should apply (everything but reloadTime) while active, else nil.
function ActiveCooling.runtimeModifiers(state: State): { StatModifier }?
	if state.phase == "On" then
		return state.runtime
	end
	return nil
end

function ActiveCooling.nextChange(state: State): number
	return state.phaseEnd
end

function ActiveCooling.snapshot(state: State, now: number, out: Snapshot?): Snapshot
	local t = Common.time(now, state.time)
	local cooldownLeft = 0
	if state.phase == "Cooldown" then
		cooldownLeft = state.phaseEnd - t
	elseif state.phase == "On" then
		cooldownLeft = state.phaseEnd - t + state.cooldownS
	end
	return Common.fill(
		out or Common.newSnapshot(),
		"ActiveCooling",
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

return ActiveCooling
