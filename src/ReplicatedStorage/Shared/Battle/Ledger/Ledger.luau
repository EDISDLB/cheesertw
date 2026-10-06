--!strict
--[[
	Battle/Ledger/Ledger — accumulates the battle event stream into per-participant BattleStats, the kill feed and
	per-pair interactions, and produces the BattleResult (Types/Battle) WITHOUT rewards or medals (Battle/Scoring and
	Medals fill those). 00-DECISIONS §2 (friendly fire off, fire credited to the igniter, drowning no credit), §5
	(spotting assist), §9 (disconnect → controlShare, AFK, leaving), §14 (Results); REG-RES-06, REG-RES-08,
	REG-BTL-02, REG-BTL-07, REG-SPT-07.

	Purpose:          The only place BattleStats are derived ("Scoring never reads anything that is not in the
	                  ledger"). Feed every BattleEvent in stream order with apply(); call finalize() once at the end.
	Dependencies:     Ledger/KillCredit, Rules/ModeRules (settings type), Rules/Outcome (abort fallback), Config
	                  (Battle.LEDGER defaults), Core/TableUtil, Types/Battle + Types/Content (types only).
	State:            LedgerState records owned by the caller (one per battle).
	Validation:       Defensive: events that are malformed, reference unknown participants, carry damage between
	                  allies (friendly fire is off — "AllyBlocked" 0-damage events are accepted silently), hit a
	                  destroyed vehicle, or arrive after "Ended" are ignored and counted in anomalies(). Assist lists
	                  are re-validated (allies of the attacker only, never the attacker or the target, no duplicates).
	Error handling:   No throws; apply() returns false for ignored events.
	Performance notes: apply() is O(1) except assist lists (≤ 15 entries). Per-pair interaction rows are created
	                  lazily once per pair. finalize() allocates the result once and never mutates the ledger (it
	                  may be called again and returns an equal result).

	Counting rules (enemy = participant of the other team):
	    damageDealt / damageReceived      HP removed (all kinds; received also counts environment)
	    damageBlocked                     Σ max(0, potential − damage) of enemy Shell hits whose result
	                                      is NonPenetration / Ricochet / Absorbed (kinetic non-pens deal
	                                      0 → their full potential; partial HE/HESH non-pens: the part
	                                      the armor stopped)
	    potentialDamageReceived           Σ potential of enemy Shell + Splash events
	    hits / penetrations               enemy Shell events (any result) / Penetration
	    criticalHits                      enemy Shell/Splash events that damaged a module or crew
	    assistSpotting/Tracking/Stun      +damage for every (validated) ally listed in the event's assist
	                                      lists (Ledger/Attribution fills them); full amount each
	    kills / killedBy / deathCause     Ledger/KillCredit on the first death signal (Damage.killed or
	                                      Destroyed); dead attackers keep credit (mutual kills)
	    spotted                           Spotted events with first = true, once per (team, target)
	    shotsFired, stuns, firesStarted   Shot / Stunned / Fire(burning) events
	    defensePoints                     CaptureReset events (`by`); capturePoints come from
	                                      Capture.participantPoints at finalize (no per-vehicle event)
	    distanceM                         addDistance() (sim-side, not in the stream)
	    timeAliveS / survived             death t, else the end t
	    firstBlood                        killer of the first credited kill
	    firstContactDamage                damage dealt with t ≤ FIRST_CONTACT_WINDOW_S
	    soleSpotterDamaged                distinct targets damaged while this vehicle was the ONLY listed
	                                      spotter (Patrol Duty)
	    hitsOnLaterKilled                 distinct targets this vehicle damaged that someone else got
	                                      credit for destroying (Confederate)
	    byTargetClass                     damageDealt / kills / spotted / assist split by enemy class
	controlShare = human-controlled seconds / seconds alive (ControlChanged events; humans start as "Player" at
	t = 0); afkStrike / leftAlive flags come from "Afk" / "Left" changes.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local TableUtil = require("@game/ReplicatedStorage/Shared/Core/TableUtil")
local KillCredit = require("./KillCredit")
local ModeRules = require("../Rules/ModeRules")
local Outcome = require("../Rules/Outcome")
local BattleTypes = require("@game/ReplicatedStorage/Shared/Types/Battle")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")

type ModeSettings = ModeRules.ModeSettings
type EntityId = BattleTypes.EntityId
type TeamId = BattleTypes.TeamId
type BattleId = BattleTypes.BattleId
type BattleMode = BattleTypes.BattleMode
type BattleType = BattleTypes.BattleType
type BattleEvent = BattleTypes.BattleEvent
type DamageEvent = BattleTypes.DamageEvent
type DamageKind = BattleTypes.DamageKind
type ShotResultKind = BattleTypes.ShotResultKind
type BattleStats = BattleTypes.BattleStats
type TargetClassStats = BattleTypes.TargetClassStats
type BattleParticipant = BattleTypes.BattleParticipant
type ParticipantResult = BattleTypes.ParticipantResult
type BattleResult = BattleTypes.BattleResult
type BattleOutcome = BattleTypes.BattleOutcome
type Interaction = BattleTypes.Interaction
type VehicleClass = ContentTypes.VehicleClass
type MapId = ContentTypes.MapId
type EventId = ContentTypes.EventId
type ShellId = ContentTypes.ShellId
type ConsumableId = ContentTypes.ConsumableId

export type LedgerSpec = {
	battleId: BattleId,
	mode: BattleMode,
	battleType: BattleType?,
	eventId: EventId?,
	eventModeId: string?,
	mapId: MapId,
	startedAt: number, -- unix seconds at GO
	contentHash: string,
	buildVersion: string,
	participants: { BattleParticipant }, -- controlShare is recomputed
	settings: ModeSettings?, -- windows (FIRST_CONTACT, FALL_CREDIT); Config.Battle.LEDGER when nil
}
export type KillFeedEntry = {
	t: number,
	victim: EntityId,
	killer: EntityId?,
	cause: DamageKind,
	assisters: { EntityId },
}
export type ParticipantFlags = {
	afkStrike: boolean, -- an AFK takeover happened (XP 0 + strike)
	leftAlive: boolean, -- left the battle while alive (no win bonus + strike)
	botTakeovers: number,
	returns: number, -- control given back to the player
}
export type FinalizeOptions = {
	endT: number?, -- battle seconds at the end (default: the Ended event, else the last event t)
	outcome: BattleOutcome?, -- default: the Ended event, else "Aborted"
	capturePoints: { [EntityId]: number }?, -- Capture.participantPoints
}
export type AmmoUse = { shell: ShellId, count: number }

type Entry = {
	id: EntityId,
	participant: BattleParticipant,
	team: TeamId,
	class: VehicleClass,
	isBot: boolean,
	stats: BattleStats,
	alive: boolean,
	deathT: number?,
	controller: "Player" | "Bot",
	controlSince: number,
	humanTime: number,
	flags: ParticipantFlags,
	damagedTargets: { [EntityId]: boolean },
	soleSpotted: { [EntityId]: boolean },
	ammo: { [string]: number },
	consumables: { ConsumableId },
	pairs: { [EntityId]: Interaction },
	contributors: { [EntityId]: boolean }, -- enemies that damaged or assisted against this vehicle
	lastEnemyDamager: EntityId?,
	lastEnemyDamageT: number?,
}

export type LedgerState = {
	spec: LedgerSpec,
	entries: { [EntityId]: Entry },
	order: { EntityId }, -- ascending participant ids
	teamOf: { [EntityId]: TeamId },
	teams: { TeamId },
	firstSpots: { [TeamId]: { [EntityId]: boolean } },
	killFeed: { KillFeedEntry },
	deaths: { [EntityId]: KillFeedEntry },
	firstBloodTaken: boolean,
	ended: boolean,
	endT: number?,
	outcome: BattleOutcome?,
	lastT: number,
	anomalies: { [string]: number },
	firstContactWindowS: number,
	fallCreditWindowS: number,
	_assist: { EntityId }, -- scratch
}

local Ledger = {}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function newStats(): BattleStats
	return {
		damageDealt = 0,
		damageReceived = 0,
		damageBlocked = 0,
		potentialDamageReceived = 0,
		assistSpotting = 0,
		assistTracking = 0,
		assistStun = 0,
		stuns = 0,
		kills = 0,
		spotted = 0,
		shotsFired = 0,
		hits = 0,
		penetrations = 0,
		criticalHits = 0,
		hitsReceived = 0,
		penetrationsReceived = 0,
		ricochetsReceived = 0,
		nonPensReceived = 0,
		capturePoints = 0,
		defensePoints = 0,
		ramDamageDealt = 0,
		firesStarted = 0,
		distanceM = 0,
		timeAliveS = 0,
		survived = true,
		firstBlood = false,
		firstContactDamage = 0,
		soleSpotterDamaged = 0,
		hitsOnLaterKilled = 0,
		byTargetClass = {},
		killedBy = nil,
		deathCause = nil,
		roleScore = nil,
		teamXpRank = nil,
	}
end

local function newInteraction(other: EntityId): Interaction
	return {
		other = other,
		shotsAt = 0,
		hitsOn = 0,
		pensOn = 0,
		critsOn = 0,
		damageDealt = 0,
		spottedIt = false,
		killedIt = false,
		hitsFrom = 0,
		damageReceived = 0,
		killedBy = false,
	}
end

--- A ledger for one battle. Duplicate participant ids keep the first entry.
function Ledger.new(spec: LedgerSpec): LedgerState
	local ledgerConfig = (Config.Battle :: any).LEDGER or {}
	local settings = spec.settings
	local state: LedgerState = {
		spec = spec,
		entries = {},
		order = {},
		teamOf = {},
		teams = {},
		firstSpots = {},
		killFeed = {},
		deaths = {},
		firstBloodTaken = false,
		ended = false,
		endT = nil,
		outcome = nil,
		lastT = 0,
		anomalies = {},
		firstContactWindowS = if settings
			then settings.firstContactWindowS
			else (ledgerConfig.FIRST_CONTACT_WINDOW_S or 180),
		fallCreditWindowS = if settings then settings.fallCreditWindowS else (ledgerConfig.FALL_CREDIT_WINDOW_S or 5),
		_assist = {},
	}
	for _, p in spec.participants do
		local id = p.participantId
		if state.entries[id] ~= nil then
			continue
		end
		state.entries[id] = {
			id = id,
			participant = p,
			team = p.team,
			class = p.class,
			isBot = p.isBot,
			stats = newStats(),
			alive = true,
			deathT = nil,
			controller = if p.isBot then "Bot" else "Player",
			controlSince = 0,
			humanTime = 0,
			flags = { afkStrike = false, leftAlive = false, botTakeovers = 0, returns = 0 },
			damagedTargets = {},
			soleSpotted = {},
			ammo = {},
			consumables = {},
			pairs = {},
			contributors = {},
			lastEnemyDamager = nil,
			lastEnemyDamageT = nil,
		}
		state.teamOf[id] = p.team
		table.insert(state.order, id)
		if table.find(state.teams, p.team) == nil then
			table.insert(state.teams, p.team)
			state.firstSpots[p.team] = {}
		end
	end
	table.sort(state.order)
	table.sort(state.teams)
	return state
end

--------------------------------------------------------------------------------
-- Internals
--------------------------------------------------------------------------------

local function isFinite(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function anomaly(state: LedgerState, kind: string): boolean
	state.anomalies[kind] = (state.anomalies[kind] or 0) + 1
	return false
end

local function byClass(entry: Entry, class: VehicleClass): TargetClassStats
	local row = entry.stats.byTargetClass[class]
	if row == nil then
		row = { damageDealt = 0, kills = 0, spotted = 0, assist = 0 }
		entry.stats.byTargetClass[class] = row
	end
	return row :: TargetClassStats
end

local function pairOf(entry: Entry, other: EntityId): Interaction
	local row = entry.pairs[other]
	if row == nil then
		row = newInteraction(other)
		entry.pairs[other] = row
	end
	return row :: Interaction
end

local function isCritical(d: DamageEvent): boolean
	if #d.crewInjured > 0 then
		return true
	end
	for _, hit in d.modulesHit do
		if hit.damage > 0 then
			return true
		end
	end
	return false
end

-- Validated, deduplicated allies of `attacker` from `list` (into the scratch array).
local function validAssists(state: LedgerState, list: { EntityId }?, attacker: Entry, target: Entry): { EntityId }
	local out = state._assist
	table.clear(out)
	if list == nil then
		return out
	end
	for _, id in list do
		local e = state.entries[id]
		if
			e ~= nil
			and id ~= attacker.id
			and id ~= target.id
			and e.team == attacker.team
			and table.find(out, id) == nil
		then
			table.insert(out, id)
		end
	end
	return out
end

local function closeControl(entry: Entry, t: number)
	if entry.controller == "Player" then
		entry.humanTime += math.max(0, t - entry.controlSince)
	end
	entry.controlSince = math.max(entry.controlSince, t)
end

local function registerDeath(
	state: LedgerState,
	victimId: EntityId,
	t: number,
	cause: DamageKind,
	attackerId: EntityId?
): boolean
	local victim = state.entries[victimId]
	if victim == nil then
		return anomaly(state, "UnknownParticipant")
	end
	if not victim.alive then
		return true -- second death signal (Damage.killed then Destroyed): already recorded
	end
	victim.alive = false
	victim.deathT = t
	closeControl(victim, t)

	local killer = KillCredit.resolve(
		cause,
		attackerId,
		victimId,
		t,
		state.teamOf,
		victim.lastEnemyDamager,
		victim.lastEnemyDamageT,
		state.fallCreditWindowS
	)
	local stats = victim.stats
	stats.survived = false
	stats.timeAliveS = math.max(0, t)
	stats.deathCause = cause
	stats.killedBy = killer

	local assisters: { EntityId } = {}
	for _, id in state.order do
		if id ~= killer and victim.contributors[id] and state.teamOf[id] ~= victim.team then
			table.insert(assisters, id)
		end
	end

	if killer ~= nil then
		local k = state.entries[killer]
		k.stats.kills += 1
		byClass(k, victim.class).kills += 1
		pairOf(k, victimId).killedIt = true
		pairOf(victim, killer).killedBy = true
		if not state.firstBloodTaken then
			state.firstBloodTaken = true
			k.stats.firstBlood = true
		end
	end
	local record: KillFeedEntry = { t = t, victim = victimId, killer = killer, cause = cause, assisters = assisters }
	table.insert(state.killFeed, record)
	state.deaths[victimId] = record
	return true
end

local function applyDamage(state: LedgerState, d: DamageEvent): boolean
	if type(d) ~= "table" or not isFinite(d.t) or not isFinite(d.damage) or d.damage < 0 then
		return anomaly(state, "Invalid")
	end
	local target = state.entries[d.target]
	if target == nil then
		return anomaly(state, "UnknownParticipant")
	end
	local attackerId = d.attacker
	local attacker: Entry? = nil
	if attackerId ~= nil and attackerId ~= d.target then
		attacker = state.entries[attackerId]
		if attacker == nil then
			return anomaly(state, "UnknownParticipant")
		end
	end
	if attacker ~= nil and attacker.team == target.team then
		-- Friendly fire is off: an ally consumes the shell for 0 damage. Anything else is a producer bug.
		if d.result == "AllyBlocked" and d.damage == 0 then
			return true
		end
		return anomaly(state, "AllyDamage")
	end
	if not target.alive then
		return anomaly(state, "DeadTarget")
	end

	local dmg = d.damage
	local t = d.t
	local potential = if isFinite(d.potentialDamage) and d.potentialDamage > 0 then d.potentialDamage else 0
	local ts = target.stats
	ts.damageReceived += dmg

	if attacker ~= nil then
		local isShell = d.kind == "Shell"
		local isSplash = d.kind == "Splash"
		local result: ShotResultKind? = d.result
		if isShell and result == nil then
			result = if dmg > 0 then "Penetration" else "NonPenetration"
		end
		local critical = (isShell or isSplash) and isCritical(d)

		-- Receiver.
		if isShell or isSplash then
			ts.potentialDamageReceived += potential
		end
		if isShell then
			ts.hitsReceived += 1
			if result == "Penetration" then
				ts.penetrationsReceived += 1
			elseif result == "Ricochet" then
				ts.ricochetsReceived += 1
				ts.damageBlocked += math.max(0, potential - dmg)
			elseif result == "NonPenetration" or result == "Absorbed" then
				ts.nonPensReceived += 1
				ts.damageBlocked += math.max(0, potential - dmg)
			end
		end
		if dmg > 0 then
			target.lastEnemyDamager = attacker.id
			target.lastEnemyDamageT = t
		end

		-- Attacker.
		local as = attacker.stats
		as.damageDealt += dmg
		if d.kind == "Ram" then
			as.ramDamageDealt += dmg
		end
		if t <= state.firstContactWindowS then
			as.firstContactDamage += dmg
		end
		if isShell then
			as.hits += 1
			if result == "Penetration" then
				as.penetrations += 1
			end
		end
		if critical then
			as.criticalHits += 1
		end
		if dmg > 0 then
			byClass(attacker, target.class).damageDealt += dmg
		end

		local out = pairOf(attacker, target.id)
		local back = pairOf(target, attacker.id)
		out.damageDealt += dmg
		back.damageReceived += dmg
		if isShell then
			out.hitsOn += 1
			out.shotsAt += 1
			back.hitsFrom += 1
			if result == "Penetration" then
				out.pensOn += 1
			end
		end
		if critical then
			out.critsOn += 1
		end

		-- Assists (00-DECISIONS §5: every listed ally gets the full amount for display; Scoring splits rewards).
		if dmg > 0 then
			attacker.damagedTargets[target.id] = true
			target.contributors[attacker.id] = true
			local spotters = validAssists(state, d.assistSpotters, attacker, target)
			for _, id in spotters do
				local e = state.entries[id]
				e.stats.assistSpotting += dmg
				byClass(e, target.class).assist += dmg
				target.contributors[id] = true
			end
			if #spotters == 1 then
				state.entries[spotters[1]].soleSpotted[target.id] = true
			end
			for _, id in validAssists(state, d.assistTrackers, attacker, target) do
				local e = state.entries[id]
				e.stats.assistTracking += dmg
				byClass(e, target.class).assist += dmg
				target.contributors[id] = true
			end
			for _, id in validAssists(state, d.assistStunners, attacker, target) do
				local e = state.entries[id]
				e.stats.assistStun += dmg
				byClass(e, target.class).assist += dmg
				target.contributors[id] = true
			end
		end
	end

	if d.killed then
		registerDeath(state, target.id, t, d.kind, if attacker then attacker.id else nil)
	end
	return true
end

local function enemyPair(state: LedgerState, a: EntityId?, b: EntityId?): (Entry?, Entry?)
	if a == nil or b == nil then
		return nil, nil
	end
	local ea, eb = state.entries[a], state.entries[b]
	if ea == nil or eb == nil or ea.team == eb.team then
		return nil, nil
	end
	return ea, eb
end

--------------------------------------------------------------------------------
-- Feeding
--------------------------------------------------------------------------------

--- Applies one stream event (in stream order). Returns false when the event was ignored (see anomalies()).
function Ledger.apply(state: LedgerState, event: BattleEvent): boolean
	if type(event) ~= "table" or type((event :: any).type) ~= "string" or not isFinite((event :: any).t) then
		return anomaly(state, "Invalid")
	end
	if state.ended then
		return anomaly(state, "AfterEnd")
	end
	if event.t > state.lastT then
		state.lastT = event.t
	end

	if event.type == "Damage" then
		return applyDamage(state, event.damage)
	elseif event.type == "Destroyed" then
		return registerDeath(state, event.target, event.t, event.cause, event.attacker)
	elseif event.type == "Spotted" then
		local spotter, target = enemyPair(state, event.spotter, event.target)
		if spotter == nil or target == nil then
			return anomaly(state, "Invalid")
		end
		pairOf(spotter, target.id).spottedIt = true
		if event.first then
			local seen = state.firstSpots[spotter.team]
			if seen[target.id] then
				return anomaly(state, "Duplicate")
			end
			seen[target.id] = true
			spotter.stats.spotted += 1
			byClass(spotter, target.class).spotted += 1
		end
		return true
	elseif event.type == "Shot" then
		local shooter = state.entries[event.shooter]
		if shooter == nil then
			return anomaly(state, "UnknownParticipant")
		end
		shooter.stats.shotsFired += 1
		shooter.ammo[event.shellId] = (shooter.ammo[event.shellId] or 0) + 1
		return true
	elseif event.type == "Fire" then
		if event.burning then
			local igniter = enemyPair(state, event.attacker, event.target)
			if igniter ~= nil then
				igniter.stats.firesStarted += 1
			end
		end
		return true
	elseif event.type == "Stunned" then
		local stunner = enemyPair(state, event.attacker, event.target)
		if stunner == nil then
			return anomaly(state, "Invalid")
		end
		stunner.stats.stuns += 1
		return true
	elseif event.type == "ConsumableUsed" then
		local user = state.entries[event.participant]
		if user == nil then
			return anomaly(state, "UnknownParticipant")
		end
		table.insert(user.consumables, event.consumable)
		return true
	elseif event.type == "CaptureReset" then
		local defender = enemyPair(state, event.by, event.capper)
		if defender == nil or not isFinite(event.points) or event.points < 0 then
			return anomaly(state, "Invalid")
		end
		defender.stats.defensePoints += event.points
		return true
	elseif event.type == "ControlChanged" then
		local entry = state.entries[event.participant]
		if entry == nil then
			return anomaly(state, "UnknownParticipant")
		end
		if entry.isBot or not entry.alive or entry.controller == event.controller then
			return true
		end
		closeControl(entry, event.t)
		entry.controller = event.controller
		if event.controller == "Bot" then
			entry.flags.botTakeovers += 1
			if event.reason == "Afk" then
				entry.flags.afkStrike = true
			elseif event.reason == "Left" then
				entry.flags.leftAlive = true
			end
		else
			entry.flags.returns += 1
		end
		return true
	elseif event.type == "Ended" then
		state.ended = true
		state.endT = event.t
		state.outcome = event.outcome
		return true
	elseif
		event.type == "Started"
		or event.type == "ModuleState"
		or event.type == "CrewInjured"
		or event.type == "CaptureProgress"
		or event.type == "BaseCaptured"
	then
		return true
	end
	return anomaly(state, "UnknownEvent")
end

--- Applies a list of events in order; returns how many were accepted.
function Ledger.applyAll(state: LedgerState, events: { BattleEvent }): number
	local accepted = 0
	for _, event in events do
		if Ledger.apply(state, event) then
			accepted += 1
		end
	end
	return accepted
end

--- Adds driven distance (metres; sim-side, not in the event stream). Ignored for unknown ids / bad values.
function Ledger.addDistance(state: LedgerState, participantId: EntityId, meters: number): boolean
	local entry = state.entries[participantId]
	if entry == nil or not isFinite(meters) or meters <= 0 or state.ended then
		return false
	end
	entry.stats.distanceM += meters
	return true
end

--------------------------------------------------------------------------------
-- Queries
--------------------------------------------------------------------------------

--- Who would be credited if `victim` died now by `cause` from `attacker`, and the assisters so far (read-only).
--- After the death is applied use deathRecord() instead (it includes the killing shot's assists).
function Ledger.resolveKill(
	state: LedgerState,
	victim: EntityId,
	cause: DamageKind,
	attacker: EntityId?,
	t: number
): (EntityId?, { EntityId })
	local entry = state.entries[victim]
	if entry == nil then
		return nil, {}
	end
	local killer = KillCredit.resolve(
		cause,
		attacker,
		victim,
		t,
		state.teamOf,
		entry.lastEnemyDamager,
		entry.lastEnemyDamageT,
		state.fallCreditWindowS
	)
	local assisters: { EntityId } = {}
	for _, id in state.order do
		if id ~= killer and entry.contributors[id] and state.teamOf[id] ~= entry.team then
			table.insert(assisters, id)
		end
	end
	return killer, assisters
end

--- The recorded death of `victim` (kill-feed row: killer, cause, assisters), or nil while alive. Use it to fill
--- the Destroyed event after applying the killing Damage event.
function Ledger.deathRecord(state: LedgerState, victim: EntityId): KillFeedEntry?
	return state.deaths[victim]
end

--- Kill feed rows in death order (read-only view).
function Ledger.killFeed(state: LedgerState): { KillFeedEntry }
	return state.killFeed
end

--- Live stats of one participant (read-only view; finalize-only fields — survived/timeAliveS for the living,
--- capturePoints, soleSpotterDamaged, hitsOnLaterKilled — are filled by finalize()).
function Ledger.stats(state: LedgerState, participantId: EntityId): BattleStats?
	local entry = state.entries[participantId]
	return if entry then entry.stats else nil
end

function Ledger.isAlive(state: LedgerState, participantId: EntityId): boolean
	local entry = state.entries[participantId]
	return entry ~= nil and entry.alive
end

--- Alive vehicles per team (Outcome input).
function Ledger.aliveByTeam(state: LedgerState): { [TeamId]: number }
	local out: { [TeamId]: number } = {}
	for _, team in state.teams do
		out[team] = 0
	end
	for _, id in state.order do
		local entry = state.entries[id]
		if entry.alive then
			out[entry.team] += 1
		end
	end
	return out
end

--- Vehicles per team at the start (Outcome input).
function Ledger.rosterByTeam(state: LedgerState): { [TeamId]: number }
	local out: { [TeamId]: number } = {}
	for _, team in state.teams do
		out[team] = 0
	end
	for _, id in state.order do
		local entry = state.entries[id]
		out[entry.team] += 1
	end
	return out
end

--- Teams of the battle, ascending.
function Ledger.teams(state: LedgerState): { TeamId }
	return table.clone(state.teams)
end

--- Connection flags of one participant (copy), or nil. Feeds RewardInboxEntry.afkStrike / no win bonus.
function Ledger.flags(state: LedgerState, participantId: EntityId): ParticipantFlags?
	local entry = state.entries[participantId]
	return if entry then table.clone(entry.flags) else nil
end

--- The player's exchanges with every other vehicle (Results "Team" row → per-enemy hits), ascending `other`.
--- `shotsAt` counts shells that reached the vehicle (Shot events carry no target).
function Ledger.interactions(state: LedgerState, participantId: EntityId): { Interaction }
	local entry = state.entries[participantId]
	local out: { Interaction } = {}
	if entry == nil then
		return out
	end
	for _, other in TableUtil.sortedKeys(entry.pairs) do
		table.insert(out, table.clone(entry.pairs[other]))
	end
	return out
end

--- Shells fired by `participantId` per shell id (auto-resupply input), ascending shell id.
function Ledger.consumedAmmo(state: LedgerState, participantId: EntityId): { AmmoUse }
	local entry = state.entries[participantId]
	local out: { AmmoUse } = {}
	if entry == nil then
		return out
	end
	for _, shell in TableUtil.sortedKeys(entry.ammo) do
		table.insert(out, { shell = shell, count = entry.ammo[shell] })
	end
	return out
end

--- Consumables used by `participantId`, in use order.
function Ledger.consumedConsumables(state: LedgerState, participantId: EntityId): { ConsumableId }
	local entry = state.entries[participantId]
	return if entry then table.clone(entry.consumables) else {}
end

--- Counts of ignored events by kind (Invalid, UnknownParticipant, AllyDamage, DeadTarget, AfterEnd, Duplicate,
--- UnknownEvent). Copy.
function Ledger.anomalies(state: LedgerState): { [string]: number }
	return table.clone(state.anomalies)
end

--------------------------------------------------------------------------------
-- Result
--------------------------------------------------------------------------------

local function copyStats(stats: BattleStats): BattleStats
	local copy = table.clone(stats)
	local classes = table.clone(stats.byTargetClass)
	for class, row in stats.byTargetClass :: any do
		(classes :: any)[class] = table.clone(row)
	end
	copy.byTargetClass = classes
	return copy
end

--- Share of an entry's life the human controlled the vehicle, at battle end `endT`.
local function controlShareOf(entry: Entry, endT: number): number
	if entry.isBot then
		return 0
	end
	local lifetime = math.max(0, entry.deathT or endT)
	local human = entry.humanTime
	if entry.alive and entry.controller == "Player" then
		human += math.max(0, endT - entry.controlSince)
	end
	if lifetime <= 0 then
		return if entry.controller == "Player" then 1 else 0
	end
	return math.clamp(human / lifetime, 0, 1)
end

--- Builds the BattleResult (participants ascending; medals empty; rewards nil). Does not mutate the ledger.
function Ledger.finalize(state: LedgerState, options: FinalizeOptions?): BattleResult
	local opts: FinalizeOptions = options or {}
	local endT = state.endT or opts.endT or state.lastT
	if not isFinite(endT) or endT < 0 then
		endT = 0
	end
	local outcome = state.outcome or opts.outcome or Outcome.aborted(state.teams)
	local capturePoints = opts.capturePoints or {}

	local participants: { ParticipantResult } = {}
	local botWeight = 0
	for _, id in state.order do
		local entry = state.entries[id]
		local share = controlShareOf(entry, endT)
		botWeight += if entry.isBot then 1 else 1 - share

		local stats = copyStats(entry.stats)
		if entry.alive then
			stats.survived = true
			stats.timeAliveS = endT
		end
		local cap = capturePoints[id]
		if isFinite(cap) and cap > 0 then
			stats.capturePoints = cap
		end
		local sole = 0
		for _ in entry.soleSpotted do
			sole += 1
		end
		stats.soleSpotterDamaged = sole
		local later = 0
		for target in entry.damagedTargets do
			local record = state.deaths[target]
			if record ~= nil and record.killer ~= nil and record.killer ~= id then
				later += 1
			end
		end
		stats.hitsOnLaterKilled = later

		local participant = TableUtil.deepCopy(entry.participant)
		participant.controlShare = share
		table.insert(participants, { participant = participant, stats = stats, medals = {}, rewards = nil })
	end

	local spec = state.spec
	return {
		battleId = spec.battleId,
		mode = spec.mode,
		battleType = spec.battleType,
		eventId = spec.eventId,
		eventModeId = spec.eventModeId,
		mapId = spec.mapId,
		startedAt = spec.startedAt,
		durationS = endT,
		outcome = TableUtil.deepCopy(outcome),
		participants = participants,
		contentHash = spec.contentHash,
		buildVersion = spec.buildVersion,
		botShare = if #state.order > 0 then botWeight / #state.order else 0,
	}
end

return Ledger
