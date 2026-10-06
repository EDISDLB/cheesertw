--!strict
--[[
	Vehicle/Mechanics/Common — shared vocabulary of the special-mechanic state machines (00-DECISIONS §4 "I–X
	mechanics", "Tier XI signatures"; content-schema §5.5): phases, the per-tick context, the HUD/replication
	snapshot record, the Tier XI / Event-only eligibility rule and small timing helpers.

	Purpose:          Keeps SiegeMode, Hydropneumatic, Turbo, RocketBoost, ChargedShot, ActiveCooling and
	                  ReserveTracks on one contract: `new(spec, now)`, `activate/deactivate(state, now, ctx?)`,
	                  `update(state, now, ctx?)`, `modifiers(state)`, `isActive(state)`, `nextChange(state)`,
	                  `snapshot(state, now, out?)`.
	Dependencies:     Types/Content, Types/VehicleSim (MechanicPhase, type-only).
	State:            None (frozen sets only).
	Validation:       Helpers coerce non-finite / negative durations to 0 so a bad number can never stall a timer.
	Error handling:   No throws. Rejected activations return (false, reason) with a SCREAMING_SNAKE reason.
	Performance notes: Allocation-free helpers; snapshots write into caller-owned records.

	Phases mirror Types/VehicleSim MechanicPhase so VehicleSim, GunState and the HUD read one vocabulary:
	  toggles (SiegeMode):            Off → Engaging → On → Disengaging → Off
	  timed (Turbo, ActiveCooling):   Off → On (durationS) → Cooldown (cooldownS) → Off
	  charges (RocketBoost):          Off ⇄ On (burn); Cooldown while no charge is available
	  passive (Hydropneumatic):       Off (moving) → Engaging (settling) → On (settled)
	  charge (ChargedShot):           Off → Engaging (charging) → On (fully charged)
	  replacement (ReserveTracks):    Off (armed) → On (replacing) → Cooldown → Off
	All phase changes happen at exact absolute times (phaseEnd), never at tick boundaries.
]]

local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local SimTypes = require("@game/ReplicatedStorage/Shared/Types/VehicleSim")

type MechanicKind = ContentTypes.MechanicKind

export type Phase = SimTypes.MechanicPhase

--- What a mechanic needs to know about its vehicle this tick (caller-owned, updated in place).
export type Context = {
	alive: boolean,
	mobile: boolean, -- engine working and (tracked) both tracks working: boosts need it
	grounded: boolean, -- on the ground (Hydropneumatic settles only when grounded)
	speedKmh: number, -- |hull speed|
	stationaryForS: number, -- time since the hull stopped (0 while moving)
}

--- HUD / replication view of one mechanic (caller-owned, reused).
export type Snapshot = {
	kind: string,
	phase: Phase,
	active: boolean, -- StatCondition "MechanicActive" for this mechanic
	progress: number, -- 0..1 through the current timed phase (1 when the phase is untimed)
	remainingS: number, -- seconds left in the current timed phase (0 when untimed)
	charges: number, -- charges available now (math.huge = unlimited)
	maxCharges: number,
	cooldownRemainingS: number, -- seconds until the mechanic (or its next charge) is available again
}

local Common = {}

--- Tolerance (s) for "a timer ends exactly now" comparisons.
Common.EPS = 1e-7

local EXOTIC: { [string]: boolean } = {
	Turbo = true,
	RocketBoost = true,
	ChargedShot = true,
	ActiveCooling = true,
	AdaptiveMagazine = true,
	ReserveTracks = true,
}
--- Tier XI signature mechanics (00-DECISIONS §4): never on Tier I–X tech-tree/premium/reward vehicles.
Common.EXOTIC = table.freeze(EXOTIC)

--- Mechanics driven by the InputCommand.mechanic key (at most one per vehicle; content-schema §5.5).
Common.KEYED = table.freeze({
	SiegeMode = true,
	Wheeled = true,
	Turbo = true,
	RocketBoost = true,
	ActiveCooling = true,
} :: { [string]: boolean })

--- True for the Tier XI signature mechanics.
function Common.isExotic(kind: MechanicKind | string): boolean
	return EXOTIC[kind] == true
end

--- 00-DECISIONS §4: exotic mechanics only on Tier XI (Apex) or Event vehicles; Tier I–X mechanics never on an Apex.
function Common.allowedOn(kind: MechanicKind | string, tier: number, acquisition: string): boolean
	if EXOTIC[kind] then
		return tier == 11 or acquisition == "Event"
	end
	return tier ~= 11
end

--- A neutral context: alive, mobile, grounded, stationary since 0 s.
function Common.newContext(): Context
	return { alive = true, mobile = true, grounded = true, speedKmh = 0, stationaryForS = 0 }
end

--- A blank snapshot record to reuse.
function Common.newSnapshot(): Snapshot
	return {
		kind = "",
		phase = "Off",
		active = false,
		progress = 1,
		remainingS = 0,
		charges = math.huge,
		maxCharges = math.huge,
		cooldownRemainingS = 0,
	}
end

--- `x` when finite and >= 0, else `default`.
function Common.nonNegative(x: any, default: number): number
	if type(x) == "number" and x == x and x >= 0 and x ~= math.huge then
		return x
	end
	return default
end

--- `x` when finite and > 0, else `default`.
function Common.positive(x: any, default: number): number
	if type(x) == "number" and x == x and x > 0 and x ~= math.huge then
		return x
	end
	return default
end

--- `now` when it is a usable time, else `fallback` (NaN / ±inf never enter a state machine).
function Common.time(now: any, fallback: number): number
	if type(now) == "number" and now == now and now ~= math.huge and now ~= -math.huge then
		return now
	end
	return fallback
end

--- Progress 0..1 of a phase that runs from `startT` to `endT` at time `now` (1 for zero-length phases).
function Common.progress(startT: number, endT: number, now: number): number
	local span = endT - startT
	if not (span > 0) then
		return 1
	end
	return math.clamp((now - startT) / span, 0, 1)
end

--- True when a phase ending at `endT` is over at `now` (inclusive within EPS).
function Common.reached(now: number, endT: number): boolean
	return now >= endT - Common.EPS
end

--------------------------------------------------------------------------------
-- Timed machine (Off → On (durationS) → Cooldown (cooldownS) → Off): Turbo, ActiveCooling
--------------------------------------------------------------------------------

--- The fields a timed machine shares (Turbo.State and ActiveCooling.State carry them).
export type Timed = {
	phase: Phase,
	phaseStart: number,
	phaseEnd: number, -- math.huge while Off
	time: number,
	durationS: number,
	cooldownS: number,
}

local function enter(state: Timed, phase: Phase, startT: number)
	state.phase = phase
	state.phaseStart = startT
	if phase == "On" then
		state.phaseEnd = startT + state.durationS
	elseif phase == "Cooldown" then
		state.phaseEnd = startT + state.cooldownS
	else
		state.phaseEnd = math.huge
	end
end

--- Advances a timed machine to `now` through every phase end it passes (exact times). Returns true on a change.
function Common.timedUpdate(state: Timed, now: number): boolean
	local t = Common.time(now, state.time)
	if t < state.time then
		t = state.time
	end
	state.time = t
	local changed = false
	for _ = 1, 4 do
		if state.phase == "On" and Common.reached(t, state.phaseEnd) then
			enter(state, "Cooldown", state.phaseEnd)
			changed = true
		elseif state.phase == "Cooldown" and Common.reached(t, state.phaseEnd) then
			enter(state, "Off", state.phaseEnd)
			changed = true
		else
			break
		end
	end
	return changed
end

--- Starts the active phase at the machine's current time (caller checked eligibility and called timedUpdate).
function Common.timedStart(state: Timed)
	enter(state, "On", state.time)
end

--- Ends an active phase early at the current time: the cooldown starts now.
function Common.timedCancel(state: Timed)
	if state.phase == "On" then
		enter(state, "Cooldown", state.time)
	end
end

--- Fills a snapshot record (allocation-free).
function Common.fill(
	out: Snapshot,
	kind: string,
	phase: Phase,
	active: boolean,
	startT: number,
	endT: number,
	timed: boolean,
	now: number,
	charges: number,
	maxCharges: number,
	cooldownRemainingS: number
): Snapshot
	out.kind = kind
	out.phase = phase
	out.active = active
	if timed then
		out.progress = Common.progress(startT, endT, now)
		out.remainingS = math.max(0, endT - now)
	else
		out.progress = 1
		out.remainingS = 0
	end
	out.charges = charges
	out.maxCharges = maxCharges
	out.cooldownRemainingS = math.max(0, cooldownRemainingS)
	return out
end

return Common
