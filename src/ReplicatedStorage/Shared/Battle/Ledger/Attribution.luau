--!strict
--[[
	Battle/Ledger/Attribution — live assist attribution: fills DamageEvent.assistSpotters / assistTrackers /
	assistStunners at the moment of damage (00-DECISIONS §5 "Rewards", report 02 R8; REG-SPT-07, REG-RES-08).

	Purpose:          The producer (BattleInstance) feeds it what the event stream cannot carry continuously and asks
	                  it for the assist lists of every DamageEvent before emitting it; the Ledger then credits those
	                  lists. Rules (the attacker is never listed; only allies of the attacker are):
	                    spotting — every ally of the attacker whose OWN spotting check saw the target at most
	                               ASSIST_SPOT_WINDOW_S (10 s) ago; still credited after that ally was destroyed
	                               (REG-SPT-07), so it simply lapses 10 s after its last successful check;
	                    tracking — the attacker whose hit destroyed a track side that is still destroyed (the
	                               target is immobilised); one entry per destroyed side, latest destroyer per side;
	                               wheeled targets only when WHEELED_TRACK_ASSIST (they are slowed, not stopped);
	                    stun     — every ally of the attacker whose stun on the target is still running.
	Dependencies:     Rules/ModeRules (settings), Config (Battle.LEDGER defaults), Types/Battle + Types/Content.
	State:            AttributionState records owned by the caller (one per battle).
	Validation:       Unknown participant ids are ignored; non-finite times / durations are ignored; lists are
	                  deduplicated and ascending (deterministic).
	Error handling:   No throws.
	Performance notes: noteSeen is O(1) (called on every successful spotting check); fill() is O(participants)
	                  and reuses the event's arrays (no allocation when they exist).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local ModeRules = require("../Rules/ModeRules")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type ModeSettings = ModeRules.ModeSettings
type EntityId = BattleTypes.EntityId
type TeamId = BattleTypes.TeamId
type DamageEvent = BattleTypes.DamageEvent
type BattleEvent = BattleTypes.BattleEvent
type InternalModuleKind = ContentTypes.InternalModuleKind

export type RosterEntry = { participantId: EntityId, team: TeamId, wheeled: boolean? }
export type TrackSides = { left: boolean, leftBy: EntityId?, right: boolean, rightBy: EntityId? }
export type AttributionState = {
	windowS: number,
	wheeledTrackAssist: boolean,
	teamOf: { [EntityId]: TeamId },
	wheeled: { [EntityId]: boolean },
	order: { EntityId }, -- ascending participant ids
	seen: { [EntityId]: { [EntityId]: number } }, -- seen[target][observer] = battle t of the last success
	tracks: { [EntityId]: TrackSides },
	stuns: { [EntityId]: { [EntityId]: number } }, -- stuns[target][stunner] = expires at (battle t)
}

local EPS = 1e-9

local Attribution = {}

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

--- A tracker for the roster. `settings` supplies ASSIST_SPOT_WINDOW_S / WHEELED_TRACK_ASSIST (Config defaults).
function Attribution.new(roster: { RosterEntry }, settings: ModeSettings?): AttributionState
	local ledgerConfig = (Config.Battle :: any).LEDGER or {}
	local state: AttributionState = {
		windowS = if settings then settings.assistSpotWindowS else (ledgerConfig.ASSIST_SPOT_WINDOW_S or 10),
		wheeledTrackAssist = if settings
			then settings.wheeledTrackAssist
			else (ledgerConfig.WHEELED_TRACK_ASSIST == true),
		teamOf = {},
		wheeled = {},
		order = {},
		seen = {},
		tracks = {},
		stuns = {},
	}
	for _, entry in roster do
		local id = entry.participantId
		if state.teamOf[id] == nil then
			state.teamOf[id] = entry.team
			state.wheeled[id] = entry.wheeled == true
			state.seen[id] = {}
			state.tracks[id] = { left = false, leftBy = nil, right = false, rightBy = nil }
			state.stuns[id] = {}
			table.insert(state.order, id)
		end
	end
	table.sort(state.order)
	return state
end

--- `observer`'s own spotting check saw `target` at battle time `t` (call on every successful check).
function Attribution.noteSeen(state: AttributionState, observer: EntityId, target: EntityId, t: number)
	local row = state.seen[target]
	if row == nil or state.teamOf[observer] == nil or observer == target or not isFinite(t) then
		return
	end
	local previous = row[observer]
	if previous == nil or t > previous then
		row[observer] = t
	end
end

--- A track side of `target` changed state; `attacker` = whose hit destroyed it (nil = environment).
function Attribution.noteModuleState(
	state: AttributionState,
	target: EntityId,
	module: InternalModuleKind,
	moduleState: "Ok" | "Damaged" | "Destroyed",
	attacker: EntityId?
)
	local sides = state.tracks[target]
	if sides == nil then
		return
	end
	local destroyed = moduleState == "Destroyed"
	if module == "TrackLeft" then
		sides.left = destroyed
		sides.leftBy = if destroyed then attacker else nil
	elseif module == "TrackRight" then
		sides.right = destroyed
		sides.rightBy = if destroyed then attacker else nil
	end
end

--- `stunner` stunned `target` at `t` for `durationS` (a later stun by the same stunner extends it).
function Attribution.noteStun(
	state: AttributionState,
	target: EntityId,
	stunner: EntityId,
	t: number,
	durationS: number
)
	local row = state.stuns[target]
	if row == nil or state.teamOf[stunner] == nil or not isFinite(t) or not isFinite(durationS) or durationS <= 0 then
		return
	end
	local expires = t + durationS
	local previous = row[stunner]
	if previous == nil or expires > previous then
		row[stunner] = expires
	end
end

--- Every stun on `target` ended early (Medkit, 00-DECISIONS §7.4).
function Attribution.clearStun(state: AttributionState, target: EntityId)
	local row = state.stuns[target]
	if row ~= nil then
		table.clear(row)
	end
end

--- `target` was destroyed: its track and stun records go (spotting records of others stay valid).
function Attribution.noteDestroyed(state: AttributionState, target: EntityId)
	local sides = state.tracks[target]
	if sides ~= nil then
		sides.left, sides.leftBy, sides.right, sides.rightBy = false, nil, false, nil
	end
	Attribution.clearStun(state, target)
end

--- Feeds the relevant stream events: Spotted (as a successful check), ModuleState (tracks), Stunned, Destroyed.
function Attribution.observe(state: AttributionState, event: BattleEvent)
	if event.type == "Spotted" then
		Attribution.noteSeen(state, event.spotter, event.target, event.t)
	elseif event.type == "ModuleState" then
		Attribution.noteModuleState(state, event.target, event.module, event.state, event.attacker)
	elseif event.type == "Stunned" then
		Attribution.noteStun(state, event.target, event.attacker, event.t, event.durationS)
	elseif event.type == "Destroyed" then
		Attribution.noteDestroyed(state, event.target)
	end
end

local function isAlly(state: AttributionState, id: EntityId?, attacker: EntityId, attackerTeam: TeamId): boolean
	return id ~= nil and id ~= attacker and state.teamOf[id] == attackerTeam
end

local function insertUnique(list: { EntityId }, id: EntityId)
	if table.find(list, id) == nil then
		table.insert(list, id)
	end
end

--- Writes the three assist lists of `damage` (in place; existing arrays are reused) for its attacker, target and
--- time. Damage without an enemy attacker gets empty lists. Returns `damage`.
function Attribution.fill(state: AttributionState, damage: DamageEvent): DamageEvent
	local spotters, trackers, stunners = damage.assistSpotters, damage.assistTrackers, damage.assistStunners
	if spotters == nil then
		spotters = {}
		damage.assistSpotters = spotters
	end
	if trackers == nil then
		trackers = {}
		damage.assistTrackers = trackers
	end
	if stunners == nil then
		stunners = {}
		damage.assistStunners = stunners
	end
	table.clear(spotters)
	table.clear(trackers)
	table.clear(stunners)

	local attacker = damage.attacker
	local target = damage.target
	local t = damage.t
	if attacker == nil or attacker == target or not isFinite(t) then
		return damage
	end
	local attackerTeam = state.teamOf[attacker]
	local targetTeam = state.teamOf[target]
	if attackerTeam == nil or targetTeam == nil or attackerTeam == targetTeam then
		return damage
	end

	local seen = state.seen[target]
	local stuns = state.stuns[target]
	for _, id in state.order do
		if id ~= target and isAlly(state, id, attacker, attackerTeam) then
			local seenAt = seen[id]
			if seenAt ~= nil and seenAt <= t + EPS and t - seenAt <= state.windowS + EPS then
				table.insert(spotters, id)
			end
			local expires = stuns[id]
			if expires ~= nil and t <= expires + EPS then
				table.insert(stunners, id)
			end
		end
	end

	if state.wheeledTrackAssist or not state.wheeled[target] then
		local sides = state.tracks[target]
		if sides.left and isAlly(state, sides.leftBy, attacker, attackerTeam) then
			insertUnique(trackers, sides.leftBy :: EntityId)
		end
		if sides.right and isAlly(state, sides.rightBy, attacker, attackerTeam) then
			insertUnique(trackers, sides.rightBy :: EntityId)
		end
		table.sort(trackers)
	end
	return damage
end

--- True while `target` has a destroyed track side (immobilised for tracking-assist purposes).
function Attribution.isTracked(state: AttributionState, target: EntityId): boolean
	local sides = state.tracks[target]
	return sides ~= nil and (sides.left or sides.right)
end

return Attribution
