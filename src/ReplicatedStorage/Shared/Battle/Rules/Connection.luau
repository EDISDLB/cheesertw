--!strict
--[[
	Battle/Rules/Connection — participant connection states, bot takeover, reconnect and AFK (00-DECISIONS §9
	"Load", "Disconnect", "AFK/leave"; REG-BTL-04, REG-BTL-05, REG-RES-06).

	Purpose:          Decides who controls each vehicle (the player or a bot) and emits the ControlChanged events the
	                  Ledger turns into BattleParticipant.controlShare, afkStrike and leftAlive:
	                    * not arrived at GO → bot from t = 0 (reason "Disconnect"); a late arrival takes over
	                      ("Arrived"); a human that never arrives inside the arrival window stays a bot (expire);
	                    * disconnected for DISCONNECT_BOT_DELAY_S → bot ("Disconnect"); reconnecting before the end
	                      gives control back at once ("Reconnect"), or spectator mode when the vehicle is destroyed;
	                    * no meaningful input for AFK_WARN_S → warning notice; AFK_TAKEOVER_S → bot + AFK strike
	                      ("Afk"); any later input gives control back ("Reconnect"), the strike stays;
	                    * leaving while alive (confirmed in the UI) → bot at once ("Left"): no win bonus + strike.
	                  Only *input* counts as activity (call activity() for throttle/steer/turret/fire input), so a stuck
	                  or overturned player who keeps pressing keys is never flagged (REG-BTL-05).
	Dependencies:     Rules/ModeRules (settings), Config (Battle: AFK strike ladder), Types/Battle (types only).
	State:            ConnectionState records owned by the caller (one per battle).
	Validation:       Unknown participant ids return false; bots never change controller; nothing changes after
	                  finish() or for destroyed vehicles; modes with AFK = false never warn or strike, and modes with
	                  BOT_TAKEOVER = false leave absent/disconnected vehicles idle (WoT behaviour) and never take over
	                  for AFK.
	Error handling:   No throws.
	Performance notes: step() is O(participants) with no allocation unless an event/notice is produced.

	Times: `now` is the server clock (same as Phases); event `t` = now − goAt (battle seconds, 0 = GO).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local ModeRules = require("./ModeRules")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")

type ModeSettings = ModeRules.ModeSettings
type EntityId = BattleTypes.EntityId
type BattleEvent = BattleTypes.BattleEvent

export type ConnStatus = "Pending" | "Connected" | "Disconnected" | "Left" | "Expired"
export type Controller = "Player" | "Bot"
export type BotReason = "Bot" | "Absent" | "Disconnect" | "Afk" | "Left"
export type ParticipantConn = {
	participantId: EntityId,
	userId: number?,
	isBot: boolean,
	status: ConnStatus,
	controller: Controller,
	botReason: BotReason?, -- why a bot drives the vehicle (nil while the player does)
	alive: boolean,
	disconnectedAt: number?,
	lastActivityAt: number,
	afkWarned: boolean,
	afkStrike: boolean,
	leftAlive: boolean,
	disconnects: number,
	reconnects: number,
}
export type NoticeKind = "AfkWarning" | "BotTakeover" | "ControlRestored"
--- UI-facing notices (warning toast, "a bot is driving your vehicle", "welcome back").
export type ConnNotice = { participantId: EntityId, kind: NoticeKind, reason: string }
export type ConnectionState = {
	settings: ModeSettings,
	started: boolean,
	ended: boolean,
	goAt: number?,
	list: { ParticipantConn }, -- ascending participantId
	byId: { [EntityId]: ParticipantConn },
}
export type RosterEntry = { participantId: EntityId, userId: number? }
export type StrikePenalty = { noRewards: boolean, queueLockS: number }

local EPS = 1e-9

local Connection = {}

local function byParticipantId(a: ParticipantConn, b: ParticipantConn): boolean
	return a.participantId < b.participantId
end

--- A connection table for the roster at `now` (before GO). Humans start Pending; bots are always connected.
function Connection.new(settings: ModeSettings, roster: { RosterEntry }, now: number): ConnectionState
	local list: { ParticipantConn } = {}
	local byId: { [EntityId]: ParticipantConn } = {}
	for _, entry in roster do
		if byId[entry.participantId] ~= nil then
			continue
		end
		local isBot = entry.userId == nil
		local conn: ParticipantConn = {
			participantId = entry.participantId,
			userId = entry.userId,
			isBot = isBot,
			status = if isBot then "Connected" else "Pending",
			controller = if isBot then "Bot" else "Player",
			botReason = if isBot then "Bot" else nil,
			alive = true,
			disconnectedAt = nil,
			lastActivityAt = now,
			afkWarned = false,
			afkStrike = false,
			leftAlive = false,
			disconnects = 0,
			reconnects = 0,
		}
		byId[entry.participantId] = conn
		table.insert(list, conn)
	end
	table.sort(list, byParticipantId)
	return { settings = settings, started = false, ended = false, goAt = nil, list = list, byId = byId }
end

local function live(state: ConnectionState): boolean
	return state.started and not state.ended
end

local function battleT(state: ConnectionState, now: number): number
	local goAt = state.goAt
	return if goAt == nil then 0 else math.max(0, now - goAt)
end

local function emit(
	state: ConnectionState,
	conn: ParticipantConn,
	controller: Controller,
	reason: "Disconnect" | "Reconnect" | "Afk" | "Left" | "Arrived",
	now: number,
	events: { BattleEvent }?
)
	if events then
		table.insert(events, {
			type = "ControlChanged",
			t = battleT(state, now),
			participant = conn.participantId,
			controller = controller,
			reason = reason,
		})
	end
end

local function toBot(
	state: ConnectionState,
	conn: ParticipantConn,
	botReason: BotReason,
	eventReason: "Disconnect" | "Afk" | "Left",
	now: number,
	events: { BattleEvent }?,
	notices: { ConnNotice }?
)
	conn.controller = "Bot"
	conn.botReason = botReason
	emit(state, conn, "Bot", eventReason, now, events)
	if notices then
		table.insert(
			notices,
			{ participantId = conn.participantId, kind = "BotTakeover", reason = botReason :: string }
		)
	end
end

local function toPlayer(
	state: ConnectionState,
	conn: ParticipantConn,
	eventReason: "Reconnect" | "Arrived",
	now: number,
	events: { BattleEvent }?,
	notices: { ConnNotice }?
)
	conn.controller = "Player"
	conn.botReason = nil
	emit(state, conn, "Player", eventReason, now, events)
	if notices then
		table.insert(
			notices,
			{ participantId = conn.participantId, kind = "ControlRestored", reason = eventReason :: string }
		)
	end
end

--- GO: humans not connected become bot-driven at t = 0 (absent → "Disconnect", left → "Left"); a human
--- disconnected for less than the delay keeps the vehicle until step() hands it over. Idempotent.
function Connection.start(state: ConnectionState, goAt: number, events: { BattleEvent }?, notices: { ConnNotice }?)
	if state.started then
		return
	end
	state.started = true
	state.goAt = goAt
	local s = state.settings
	for _, conn in state.list do
		if conn.isBot then
			continue
		end
		conn.lastActivityAt = math.max(conn.lastActivityAt, goAt)
		if not s.botTakeover or not conn.alive then
			continue
		end
		local status = conn.status
		if status == "Pending" or status == "Expired" then
			toBot(state, conn, "Absent", "Disconnect", goAt, events, notices)
		elseif status == "Left" then
			conn.leftAlive = true
			toBot(state, conn, "Left", "Left", goAt, events, notices)
		elseif status == "Disconnected" then
			local since = conn.disconnectedAt or goAt
			if goAt - since >= s.disconnectBotDelayS - EPS then
				toBot(state, conn, "Disconnect", "Disconnect", goAt, events, notices)
			end
		end
	end
end

--- The player of `participantId` (re)joined at `now`. Takes the vehicle back from a bot when the battle is
--- running and the vehicle is alive ("Arrived" for a first arrival after GO, else "Reconnect"). Returns false for
--- unknown ids, bots and expired slots.
function Connection.arrive(
	state: ConnectionState,
	participantId: EntityId,
	now: number,
	events: { BattleEvent }?,
	notices: { ConnNotice }?
): boolean
	local conn = state.byId[participantId]
	if conn == nil or conn.isBot or conn.status == "Expired" or state.ended then
		return false
	end
	local previous = conn.status
	conn.status = "Connected"
	conn.disconnectedAt = nil
	conn.lastActivityAt = now
	conn.afkWarned = false
	if previous == "Disconnected" or previous == "Left" then
		conn.reconnects += 1
	end
	if live(state) and conn.alive and conn.controller == "Bot" then
		toPlayer(state, conn, if conn.botReason == "Absent" then "Arrived" else "Reconnect", now, events, notices)
	end
	return true
end

--- The player of `participantId` lost its connection at `now` (PlayerRemoving without a confirmed leave).
function Connection.disconnect(state: ConnectionState, participantId: EntityId, now: number): boolean
	local conn = state.byId[participantId]
	if conn == nil or conn.isBot or conn.status ~= "Connected" then
		return false
	end
	conn.status = "Disconnected"
	conn.disconnectedAt = now
	conn.disconnects += 1
	return true
end

--- The player confirmed "Leave battle" at `now`. While alive: bot at once, no win bonus, strike (leftAlive).
function Connection.leave(
	state: ConnectionState,
	participantId: EntityId,
	now: number,
	events: { BattleEvent }?,
	notices: { ConnNotice }?
): boolean
	local conn = state.byId[participantId]
	if conn == nil or conn.isBot or conn.status == "Expired" or state.ended then
		return false
	end
	conn.status = "Left"
	conn.disconnectedAt = now
	if conn.alive then
		conn.leftAlive = true
		if live(state) and conn.controller == "Player" and state.settings.botTakeover then
			toBot(state, conn, "Left", "Left", now, events, notices)
		end
	end
	return true
end

--- Meaningful input from the player at `now` (throttle/steer ≠ 0, turret/aim change, fire, consumable). Resets the
--- AFK clock; after an AFK takeover it gives the vehicle back ("Reconnect").
function Connection.activity(
	state: ConnectionState,
	participantId: EntityId,
	now: number,
	events: { BattleEvent }?,
	notices: { ConnNotice }?
): boolean
	local conn = state.byId[participantId]
	if conn == nil or conn.isBot or conn.status ~= "Connected" then
		return false
	end
	conn.lastActivityAt = math.max(conn.lastActivityAt, now)
	conn.afkWarned = false
	if live(state) and conn.alive and conn.controller == "Bot" and conn.botReason == "Afk" then
		toPlayer(state, conn, "Reconnect", now, events, notices)
	end
	return true
end

--- The vehicle was destroyed: no more control changes (the player spectates or returns to the Hub).
function Connection.destroyed(state: ConnectionState, participantId: EntityId): boolean
	local conn = state.byId[participantId]
	if conn == nil then
		return false
	end
	conn.alive = false
	return true
end

--- The arrival window closed without this human (Phases output.expired): the slot stays a bot for good.
function Connection.expire(state: ConnectionState, participantId: EntityId): boolean
	local conn = state.byId[participantId]
	if conn == nil or conn.isBot or conn.status ~= "Pending" then
		return false
	end
	conn.status = "Expired"
	return true
end

--- Per-tick timers: disconnect hand-over and AFK warning/takeover at `now`.
function Connection.step(state: ConnectionState, now: number, events: { BattleEvent }?, notices: { ConnNotice }?)
	if not live(state) or now ~= now then
		return
	end
	local s = state.settings
	for _, conn in state.list do
		if conn.isBot or not conn.alive or conn.controller ~= "Player" then
			continue
		end
		if conn.status == "Disconnected" or conn.status == "Left" then
			local since = conn.disconnectedAt or now
			if s.botTakeover and now - since >= s.disconnectBotDelayS - EPS then
				toBot(state, conn, "Disconnect", "Disconnect", now, events, notices)
			end
		elseif conn.status == "Connected" and s.afkEnabled and s.botTakeover then
			local idle = now - conn.lastActivityAt
			if idle >= s.afkTakeoverS - EPS then
				conn.afkStrike = true
				toBot(state, conn, "Afk", "Afk", now, events, notices)
			elseif idle >= s.afkWarnS - EPS and not conn.afkWarned then
				conn.afkWarned = true
				if notices then
					table.insert(notices, { participantId = conn.participantId, kind = "AfkWarning", reason = "Afk" })
				end
			end
		end
	end
end

--- The battle ended: nothing changes any more.
function Connection.finish(state: ConnectionState)
	state.ended = true
end

--- Who drives the vehicle now ("Bot" for unknown ids).
function Connection.controller(state: ConnectionState, participantId: EntityId): Controller
	local conn = state.byId[participantId]
	return if conn then conn.controller else "Bot"
end

--- True when a bot drives the vehicle (bots, absentees, disconnected/AFK/left players).
function Connection.isBotControlled(state: ConnectionState, participantId: EntityId): boolean
	return Connection.controller(state, participantId) == "Bot"
end

--- Read-only view of one participant, or nil.
function Connection.get(state: ConnectionState, participantId: EntityId): ParticipantConn?
	return state.byId[participantId]
end

--- Penalty for a player's AFK/leave strike count inside AFK_STRIKE_WINDOW_S (00-DECISIONS §9): 1 → no rewards for
--- the battle, 2 → + 10 min queue lock, 3+ → + 60 min. 0 strikes → no penalty. Applied by the Hub.
function Connection.strikePenalty(strikes: number): StrikePenalty
	if not (strikes >= 1) then
		return { noRewards = false, queueLockS = 0 }
	end
	local ladder: { number } = (Config.Battle :: any).AFK_STRIKE_LOCK_S or { 0, 600, 3600 }
	local index = math.clamp(math.floor(strikes), 1, math.max(1, #ladder))
	return { noRewards = true, queueLockS = ladder[index] or 0 }
end

return Connection
