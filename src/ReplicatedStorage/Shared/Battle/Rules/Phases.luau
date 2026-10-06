--!strict
--[[
	Battle/Rules/Phases — the battle lifecycle state machine (00-DECISIONS §9 "Load"/"End", §19 "Stale codes",
	§21 #22; ARCHITECTURE §2.1):

	  Preparing ──ready──▶ Loading ──all loaded / LOAD_TIMEOUT──▶ Countdown ──COUNTDOWN──▶ Active
	      │                   │ (fewer than MIN_HUMANS arrived → abort)                     │ finish(outcome)
	      └─timeout/abort─────┴──────────────abort───────────────────────────────────────▶ Ending ──banner──▶
	  Results ──delivered / RESULTS_TIMEOUT──▶ Closed

	Purpose:          BattleInstance drives it with the server clock (`now`, monotonic seconds); it answers what is
	                  allowed (movement/fire are rejected in the countdown, turrets may rotate — REG-BTL-06), the
	                  battle time t (0 = GO, the time base of every BattleEvent) and the timer (REG-BTL-03: clients
	                  show endsAt − estimated server now). Arrivals are admitted only for roster users coming from a
	                  Hub within ARRIVAL_WINDOW_S of server creation (first arrival) or until the battle ends
	                  (reconnect). checkAccess() is the stale-access-code hook run before anything else.
	Dependencies:     Rules/ModeRules (settings), Rules/Outcome (abort outcome), Core/Result, Net/ErrorCodes,
	                  Types/Battle (types only).
	State:            PhaseState records owned by the caller (one per battle). Transitions are pushed into an
	                  optional PhaseOutput (transitions, BattleEvents "Started"/"Ended", expired user ids).
	Validation:       Non-finite `now` is ignored by step(); a `now` earlier than the last one never moves backwards.
	                  Unknown user ids are rejected by admit(); finish() only works in Active and only once.
	Error handling:   admit()/checkAccess() return Result (NOT_ALLOWED / NOT_FOUND with a detail reason); the other
	                  functions return booleans. No throws.
	Performance notes: O(humans) per step (≤ 30); no allocation unless an output list receives an entry.

	Time stamps are exact (not the tick that noticed them): countdownAt = max(readyAt, last human resolved) or
	readyAt + LOAD_TIMEOUT_S; goAt = countdownAt + COUNTDOWN_S; endsAt = goAt + durationS. So a timeline is identical
	whatever the tick phase, which keeps the event stream deterministic.
]]

local ModeRules = require("./ModeRules")
local Outcome = require("./Outcome")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type ModeSettings = ModeRules.ModeSettings
type Result<T> = Result.Result<T>
type EntityId = BattleTypes.EntityId
type TeamId = BattleTypes.TeamId
type BattleEvent = BattleTypes.BattleEvent
type BattleOutcome = BattleTypes.BattleOutcome

export type Phase = "Preparing" | "Loading" | "Countdown" | "Active" | "Ending" | "Results" | "Closed"
export type AbortReason = "PrepareTimeout" | "TooFewHumans" | "StaleAccessCode" | "ServerClosing" | "Internal"
export type TransitionReason =
	"Ready"
	| "AllLoaded"
	| "LoadTimeout"
	| "CountdownDone"
	| "Finished"
	| "Aborted"
	| "BannerDone"
	| "ResultsDelivered"
	| "ResultsTimeout"
export type PhaseTransition = { from: Phase, to: Phase, at: number, reason: TransitionReason }
export type PhaseOutput = { transitions: { PhaseTransition }, events: { BattleEvent }, expired: { number } }
export type Action = "Move" | "Fire" | "Turret" | "Consumable" | "Chat"

export type RosterSlot = { participantId: EntityId, team: TeamId, userId: number? }
export type HumanSlot = {
	userId: number,
	participantId: EntityId,
	arrived: boolean, -- arrived at least once
	present: boolean, -- currently in the server
	loaded: boolean, -- client reported MapReady since its last arrival
	expired: boolean, -- never arrived within the arrival window (slot stays a bot)
	arrivedAt: number?, -- first arrival
	resolvedAt: number?, -- when it stopped blocking the early start (loaded, gone or expired)
}
export type PhaseState = {
	settings: ModeSettings,
	phase: Phase,
	createdAt: number,
	phaseAt: number,
	lastNow: number,
	readyAt: number?,
	countdownAt: number?,
	goAt: number?,
	endsAt: number?,
	endedAt: number?,
	resultsAt: number?,
	closedAt: number?,
	deliveredAt: number?,
	outcome: BattleOutcome?,
	abortReason: AbortReason?,
	teams: { TeamId },
	humans: { [number]: HumanSlot },
	humanIds: { number }, -- sorted user ids
}

--- What the battle server knows about its own reservation (stale-access-code check, ARCHITECTURE §2.1 step 4).
export type ManifestView = { mmType: (number | string)?, ended: boolean? }
export type AccessInfo = {
	privateServerId: string, -- game.PrivateServerId ("" on public servers)
	privateServerOwnerId: number, -- game.PrivateServerOwnerId (≠ 0 on player-owned private servers)
	matchmakingType: number | string, -- game.MatchmakingType of this server
	manifest: ManifestView?, -- MemoryStore match:<PrivateServerId> (nil = missing)
}

local EPS = 1e-9
local MAX_TRANSITIONS_PER_STEP = 16

local Phases = {}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

--- A new battle in Preparing, created at `now` (the arrival window counts from here: a reserved server starts when
--- its first player arrives, after the Hub's teleport began).
function Phases.new(settings: ModeSettings, roster: { RosterSlot }, now: number): PhaseState
	local humans: { [number]: HumanSlot } = {}
	local humanIds: { number } = {}
	local teams: { TeamId } = {}
	for _, slot in roster do
		if table.find(teams, slot.team) == nil then
			table.insert(teams, slot.team)
		end
		local userId = slot.userId
		if userId ~= nil and humans[userId] == nil then
			humans[userId] = {
				userId = userId,
				participantId = slot.participantId,
				arrived = false,
				present = false,
				loaded = false,
				expired = false,
				arrivedAt = nil,
				resolvedAt = nil,
			}
			table.insert(humanIds, userId)
		end
	end
	table.sort(humanIds)
	table.sort(teams)
	return {
		settings = settings,
		phase = "Preparing",
		createdAt = now,
		phaseAt = now,
		lastNow = now,
		readyAt = nil,
		countdownAt = nil,
		goAt = nil,
		endsAt = nil,
		endedAt = nil,
		resultsAt = nil,
		closedAt = nil,
		deliveredAt = nil,
		outcome = nil,
		abortReason = nil,
		teams = teams,
		humans = humans,
		humanIds = humanIds,
	}
end

--- A reusable output record for step()/finish()/abort() (clear it with clearOutput between ticks).
function Phases.newOutput(): PhaseOutput
	return { transitions = {}, events = {}, expired = {} }
end

function Phases.clearOutput(out: PhaseOutput)
	table.clear(out.transitions)
	table.clear(out.events)
	table.clear(out.expired)
end

--------------------------------------------------------------------------------
-- Internals
--------------------------------------------------------------------------------

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function transition(state: PhaseState, to: Phase, at: number, reason: TransitionReason, out: PhaseOutput?)
	local from: Phase = state.phase
	state.phase = to
	state.phaseAt = at
	if out then
		table.insert(out.transitions, { from = from, to = to, at = at, reason = reason })
	end
end

local function battleTimeAt(state: PhaseState, at: number): number
	local goAt = state.goAt
	if goAt == nil then
		return 0
	end
	return math.max(0, at - goAt)
end

local function enterEnding(
	state: PhaseState,
	outcome: BattleOutcome,
	at: number,
	reason: TransitionReason,
	out: PhaseOutput?
)
	state.outcome = outcome
	state.endedAt = at
	transition(state, "Ending", at, reason, out)
	if out then
		table.insert(out.events, { type = "Ended", t = battleTimeAt(state, at), outcome = outcome })
	end
end

local function abortAt(state: PhaseState, reason: AbortReason, at: number, out: PhaseOutput?): boolean
	local phase = state.phase
	if phase == "Ending" or phase == "Results" or phase == "Closed" then
		return false
	end
	state.abortReason = reason
	enterEnding(state, Outcome.aborted(state.teams), at, "Aborted", out)
	return true
end

-- Marks humans that never arrived within the arrival window as expired.
local function expireLate(state: PhaseState, now: number, out: PhaseOutput?)
	local deadline = state.createdAt + state.settings.arrivalWindowS
	if now <= deadline + EPS then
		return
	end
	for _, userId in state.humanIds do
		local slot = state.humans[userId]
		if not slot.arrived and not slot.expired then
			slot.expired = true
			slot.resolvedAt = deadline
			if out then
				table.insert(out.expired, userId)
			end
		end
	end
end

-- Time at which every human stopped blocking the early start, or nil while someone still blocks it.
local function allResolvedAt(state: PhaseState): number?
	local latest = -math.huge
	for _, userId in state.humanIds do
		local slot = state.humans[userId]
		local resolvedAt = slot.resolvedAt
		if resolvedAt == nil then
			return nil
		end
		latest = math.max(latest, resolvedAt)
	end
	return latest
end

local function arrivedHumans(state: PhaseState): number
	local n = 0
	for _, userId in state.humanIds do
		if state.humans[userId].arrived then
			n += 1
		end
	end
	return n
end

-- One transition if one is due at `now`; returns true when the phase changed.
local function advance(state: PhaseState, now: number, out: PhaseOutput?): boolean
	local s = state.settings
	local phase = state.phase
	if phase == "Preparing" then
		local deadline = state.createdAt + s.prepareTimeoutS
		if now >= deadline - EPS then
			return abortAt(state, "PrepareTimeout", deadline, out)
		end
	elseif phase == "Loading" then
		local readyAt = state.readyAt :: number
		local gateAt: number? = nil
		local reason: TransitionReason = "LoadTimeout"
		if s.earlyStart then
			local resolvedAt = allResolvedAt(state)
			if resolvedAt ~= nil then
				local at = math.max(readyAt, resolvedAt)
				if at <= now + EPS then
					gateAt = at
					reason = "AllLoaded"
				end
			end
		end
		local timeoutAt = readyAt + s.loadTimeoutS
		if (gateAt == nil or timeoutAt < gateAt) and now >= timeoutAt - EPS then
			gateAt = timeoutAt
			reason = "LoadTimeout"
		end
		if gateAt ~= nil then
			if arrivedHumans(state) < s.minHumans then
				return abortAt(state, "TooFewHumans", gateAt, out)
			end
			state.countdownAt = gateAt
			transition(state, "Countdown", gateAt, reason, out)
			return true
		end
	elseif phase == "Countdown" then
		local goAt = (state.countdownAt :: number) + s.countdownS
		if now >= goAt - EPS then
			state.goAt = goAt
			state.endsAt = goAt + s.durationS
			transition(state, "Active", goAt, "CountdownDone", out)
			if out then
				table.insert(out.events, { type = "Started", t = 0 })
			end
			return true
		end
	elseif phase == "Ending" then
		local resultsAt = (state.endedAt :: number) + s.endBannerS
		if now >= resultsAt - EPS then
			state.resultsAt = resultsAt
			transition(state, "Results", resultsAt, "BannerDone", out)
			return true
		end
	elseif phase == "Results" then
		local resultsAt = state.resultsAt :: number
		local deliveredAt = state.deliveredAt
		if deliveredAt ~= nil then
			local at = math.max(resultsAt, deliveredAt)
			state.closedAt = at
			transition(state, "Closed", at, "ResultsDelivered", out)
			return true
		end
		local closeAt = resultsAt + s.resultsTimeoutS
		if now >= closeAt - EPS then
			state.closedAt = closeAt
			transition(state, "Closed", closeAt, "ResultsTimeout", out)
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Access and arrivals
--------------------------------------------------------------------------------

--- Stale/foreign access-code check (ARCHITECTURE §2.1 step 4, 00-DECISIONS §19). Access codes never expire and
--- reusing one starts a fresh empty server, so a battle server without a live manifest for its own
--- PrivateServerId must send everyone back to the Hub (then call abort(state, "StaleAccessCode", now)).
--- Errors: NOT_ALLOWED "NO_PRIVATE_SERVER" | "PLAYER_OWNED_SERVER" | "MANIFEST_ENDED" | "MATCHMAKING_TYPE_MISMATCH",
--- NOT_FOUND "MANIFEST_MISSING". The Dev role (in-process battles) skips this check.
function Phases.checkAccess(info: AccessInfo): Result<boolean>
	if type(info.privateServerId) ~= "string" or info.privateServerId == "" then
		return Result.err(ErrorCodes.NOT_ALLOWED, "NO_PRIVATE_SERVER")
	end
	if info.privateServerOwnerId ~= 0 then
		return Result.err(ErrorCodes.NOT_ALLOWED, "PLAYER_OWNED_SERVER")
	end
	local manifest = info.manifest
	if manifest == nil then
		return Result.err(ErrorCodes.NOT_FOUND, "MANIFEST_MISSING")
	end
	if manifest.ended == true then
		return Result.err(ErrorCodes.NOT_ALLOWED, "MANIFEST_ENDED")
	end
	if manifest.mmType == nil or manifest.mmType ~= info.matchmakingType then
		return Result.err(ErrorCodes.NOT_ALLOWED, "MATCHMAKING_TYPE_MISMATCH")
	end
	return Result.ok(true)
end

--- Admits `userId` arriving at `now`; `fromHub` = its SourcePlaceId is a Hub place (TeleportData is never trusted).
--- First arrivals are accepted until ARRIVAL_WINDOW_S after creation; returning players (disconnect / "Return to
--- battle") until the battle ends. Ok(participantId) or Err NOT_ALLOWED with detail "BATTLE_OVER" |
--- "NOT_IN_ROSTER" | "FOREIGN_SOURCE" | "ARRIVAL_WINDOW_CLOSED".
function Phases.admit(state: PhaseState, userId: number, now: number, fromHub: boolean): Result<EntityId>
	local phase = state.phase
	if phase == "Ending" or phase == "Results" or phase == "Closed" then
		return Result.err(ErrorCodes.NOT_ALLOWED, "BATTLE_OVER")
	end
	local slot = state.humans[userId]
	if slot == nil then
		return Result.err(ErrorCodes.NOT_ALLOWED, "NOT_IN_ROSTER")
	end
	if not fromHub then
		return Result.err(ErrorCodes.NOT_ALLOWED, "FOREIGN_SOURCE")
	end
	if not slot.arrived then
		if slot.expired or now > state.createdAt + state.settings.arrivalWindowS + EPS then
			if not slot.expired then
				slot.expired = true
				slot.resolvedAt = state.createdAt + state.settings.arrivalWindowS
			end
			return Result.err(ErrorCodes.NOT_ALLOWED, "ARRIVAL_WINDOW_CLOSED")
		end
		slot.arrived = true
		slot.arrivedAt = now
	end
	if not slot.present then
		slot.present = true
		slot.loaded = false
		slot.resolvedAt = nil
	end
	return Result.ok(slot.participantId)
end

--- The client of `userId` finished loading (MapReady acknowledged). Returns false for unknown/absent users.
function Phases.markLoaded(state: PhaseState, userId: number, now: number): boolean
	local slot = state.humans[userId]
	if slot == nil or not slot.present then
		return false
	end
	if not slot.loaded then
		slot.loaded = true
		slot.resolvedAt = now
	end
	return true
end

--- `userId` left the server (disconnect or leave). A gone human no longer blocks the early start.
function Phases.markGone(state: PhaseState, userId: number, now: number): boolean
	local slot = state.humans[userId]
	if slot == nil or not slot.present then
		return false
	end
	slot.present = false
	if slot.resolvedAt == nil then
		slot.resolvedAt = now
	end
	return true
end

--------------------------------------------------------------------------------
-- Driving the machine
--------------------------------------------------------------------------------

--- Manifest validated and map built (MapReady): Preparing → Loading. Returns false in any other phase.
function Phases.markReady(state: PhaseState, now: number, out: PhaseOutput?): boolean
	if state.phase ~= "Preparing" then
		return false
	end
	state.readyAt = now
	transition(state, "Loading", now, "Ready", out)
	return true
end

--- Advances every due timer up to `now` (several transitions may happen in one call). Returns the phase.
--- The Active → Ending transition is never automatic: evaluate Outcome (with isTimeUp) and call finish().
function Phases.step(state: PhaseState, now: number, out: PhaseOutput?): Phase
	if not isFinite(now) then
		return state.phase
	end
	if now < state.lastNow then
		now = state.lastNow
	end
	state.lastNow = now
	local phase = state.phase
	if phase ~= "Ending" and phase ~= "Results" and phase ~= "Closed" then
		expireLate(state, now, out)
	end
	for _ = 1, MAX_TRANSITIONS_PER_STEP do
		if not advance(state, now, out) then
			break
		end
	end
	return state.phase
end

--- Ends an Active battle with `outcome` at `now` (clamped to the timer's end). Returns false when the battle is
--- not Active (already finished, not started); the first outcome always wins.
function Phases.finish(state: PhaseState, outcome: BattleOutcome, now: number, out: PhaseOutput?): boolean
	if state.phase ~= "Active" then
		return false
	end
	local at = math.max(state.goAt :: number, math.min(now, state.endsAt :: number))
	enterEnding(state, outcome, at, "Finished", out)
	return true
end

--- Aborts the battle (no win/loss recorded): any phase before Ending → Ending with the "Aborted" outcome.
function Phases.abort(state: PhaseState, reason: AbortReason, now: number, out: PhaseOutput?): boolean
	local at = if isFinite(now) then math.max(now, state.phaseAt) else state.phaseAt
	return abortAt(state, reason, at, out)
end

--- Reward inbox written and players teleported: Results → Closed on the next step (immediately when already in
--- Results). Returns false once Closed or before the battle ended.
function Phases.markResultsDelivered(state: PhaseState, now: number, out: PhaseOutput?): boolean
	local phase = state.phase
	if phase ~= "Ending" and phase ~= "Results" then
		return false
	end
	if state.deliveredAt == nil then
		state.deliveredAt = now
	end
	if phase == "Results" then
		advance(state, now, out)
	end
	return true
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

--- Battle seconds since GO (0 before; frozen at the end). The `t` of every BattleEvent.
function Phases.battleTime(state: PhaseState, now: number): number
	local stop = state.endedAt
	return battleTimeAt(state, if stop ~= nil then math.min(now, stop) else now)
end

--- Seconds left on the battle timer: the full duration before GO, frozen at the end (0 when aborted before GO).
function Phases.timeLeft(state: PhaseState, now: number): number
	local endsAt = state.endsAt
	local stop = state.endedAt
	if endsAt == nil then
		return if stop ~= nil then 0 else state.settings.durationS
	end
	local at = if stop ~= nil then math.min(now, stop) else now
	return math.max(0, endsAt - at)
end

--- True when the battle is Active and its timer ran out (evaluate Outcome with timeUp = true this tick).
function Phases.isTimeUp(state: PhaseState, now: number): boolean
	local endsAt = state.endsAt
	return state.phase == "Active" and endsAt ~= nil and now >= endsAt - EPS
end

--- True once the battle ended (Ending, Results, Closed): no input is accepted any more.
function Phases.isOver(state: PhaseState): boolean
	local phase = state.phase
	return phase == "Ending" or phase == "Results" or phase == "Closed"
end

--- Whether a player action is accepted in the current phase (REG-BTL-06): the countdown allows turret rotation
--- and chat only; Active allows everything; nothing but chat before the countdown or after the end.
function Phases.allows(state: PhaseState, action: Action): boolean
	local phase = state.phase
	if action == "Chat" then
		return phase ~= "Closed"
	elseif phase == "Active" then
		return true
	elseif phase == "Countdown" then
		return action == "Turret"
	end
	return false
end

--- Number of roster humans that arrived at least once.
function Phases.arrivedCount(state: PhaseState): number
	return arrivedHumans(state)
end

--- The human slot of `userId` (read-only view), or nil.
function Phases.human(state: PhaseState, userId: number): HumanSlot?
	return state.humans[userId]
end

return Phases
