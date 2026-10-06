--!strict
--[[
	Matchmaking/Tickets — validates raw queue tickets (untrusted MemoryStore data), rejects duplicates, stale and
	timed-out tickets, and turns the survivors into matchmaking units sorted oldest first.

	Purpose:          Tickets.prepare(raw, now, config) -> { units, rejected } for Matchmaker.run; Tickets.validate for
	                  the Hub's enqueue path (same rules, one ticket).
	Dependencies:     Types/Matchmaking, Core/TableUtil (deepEqual), Matchmaking/Rules.
	State:            None.
	Validation:       Structure and ranges (ids, members, vehicle tier/class/role/faction, region, mode, mmType,
	                  times), platoon rules (size, same tier, <= MAX_ARTILLERY SPG, per-team class caps and the wheeled
	                  cap of the mode), then duplicates: identical copies of one ticket merge silently, different tickets
	                  sharing a ticketId are all rejected (DUPLICATE_TICKET), a userId found in several tickets keeps
	                  only the newest ticket (DUPLICATE_MEMBER). TIMEOUT / STALE are applied before duplicates so a
	                  dead ticket never displaces a live one.
	Error handling:   Never throws on ticket content; every problem becomes a RejectedTicket with a detail string.
	Performance notes: O(n log n) (one sort); one Unit record per ticket. 1,000 tickets ≈ 2-3 ms in Lune.
]]

local MatchmakingTypes = require("@game/ReplicatedStorage/Shared/Types/Matchmaking")
local TableUtil = require("@game/ReplicatedStorage/Shared/Core/TableUtil")
local Rules = require("./Rules")

type Ticket = MatchmakingTypes.Ticket
type TicketMember = MatchmakingTypes.TicketMember
type RejectedTicket = MatchmakingTypes.RejectedTicket
type RejectReason = MatchmakingTypes.RejectReason
type MatchmakerConfig = MatchmakingTypes.MatchmakerConfig
type ModeRules = MatchmakingTypes.ModeRules

local Tickets = {}

--- A validated ticket as the matcher sees it. Counts are arrays in Rules.CLASSES order.
export type Unit = {
	ticket: Ticket,
	id: string,
	order: number, -- age rank among all valid units (1 = oldest)
	partition: string, -- mode .. "|" .. mmType
	mode: string,
	size: number,
	tier: number,
	region: string,
	waitS: number,
	stage: Rules.Stage, -- by the unit's own wait
	classVec: { number },
	wheeled: number,
	roles: { string },
	sig: string, -- tier + sorted classes (pairing signature for the zero-bot fill)
	streak: number, -- members whose bottomTierStreak >= BOTTOM_TIER_STREAK_PROTECTION
	battlesSum: number, -- members with a known battle count
	battlesKnown: number,
	used: boolean,
}

export type Prepared = { units: { Unit }, rejected: { RejectedTicket } }

local MAX_USER_ID = 2 ^ 53

local function isFiniteNumber(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function isInteger(v: any): boolean
	return isFiniteNumber(v) and v == math.floor(v)
end

local function isString(v: any, maxLen: number): boolean
	return type(v) == "string" and #v >= 1 and #v <= maxLen
end

local function isStringArray(v: any, maxLen: number): boolean
	if v == nil then
		return true
	end
	if type(v) ~= "table" or #v > maxLen then
		return false
	end
	local n = 0
	for k, item in v do
		n += 1
		if type(k) ~= "number" or type(item) ~= "string" then
			return false
		end
	end
	return n == #v
end

local function isArray(v: any): boolean
	if type(v) ~= "table" then
		return false
	end
	local n = 0
	for k in v do
		if type(k) ~= "number" then
			return false
		end
		n += 1
	end
	return n == #v
end

--- Resolves the mode rules of a ticket mode (nil = not matchmade).
local function modeRulesOf(config: MatchmakerConfig, mode: any): ModeRules?
	if type(mode) ~= "string" then
		return nil
	end
	return config.modes[mode]
end

local function checkMember(config: MatchmakerConfig, m: any, index: number): string?
	local settings = config.settings
	if type(m) ~= "table" then
		return `members[{index}]: expected a table`
	end
	if not isInteger(m.userId) or m.userId < 1 or m.userId > MAX_USER_ID then
		return `members[{index}].userId: expected a positive integer`
	end
	local v = m.vehicle
	if type(v) ~= "table" then
		return `members[{index}].vehicle: expected a table`
	end
	if not isString(v.defId, 64) then
		return `members[{index}].vehicle.defId: expected a string (1..64)`
	end
	if not isInteger(v.tier) or v.tier < settings.TIER_MIN or v.tier > settings.TIER_MAX then
		return `members[{index}].vehicle.tier: expected an integer {settings.TIER_MIN}..{settings.TIER_MAX}`
	end
	if type(v.class) ~= "string" or Rules.CLASS_INDEX[v.class] == nil then
		return `members[{index}].vehicle.class: unknown class`
	end
	if not isString(v.role, 64) or string.sub(v.role, 1, #v.class + 1) ~= v.class .. "_" then
		return `members[{index}].vehicle.role: expected a {v.class}_* role`
	end
	if not isString(v.faction, 64) then
		return `members[{index}].vehicle.faction: expected a string (1..64)`
	end
	if v.wheeled ~= nil and type(v.wheeled) ~= "boolean" then
		return `members[{index}].vehicle.wheeled: expected a boolean`
	end
	if v.wheeled == true and v.class ~= "light" then
		return `members[{index}].vehicle.wheeled: only light vehicles are wheeled`
	end
	if m.battles ~= nil and (not isFiniteNumber(m.battles) or m.battles < 0) then
		return `members[{index}].battles: expected a number >= 0`
	end
	if m.bottomTierStreak ~= nil and (not isFiniteNumber(m.bottomTierStreak) or m.bottomTierStreak < 0) then
		return `members[{index}].bottomTierStreak: expected a number >= 0`
	end
	if not isStringArray(m.recentMaps, 64) then
		return `members[{index}].recentMaps: expected an array of map ids (<= 64)`
	end
	if not isStringArray(m.mapBlacklist, 16) then
		return `members[{index}].mapBlacklist: expected an array of map ids (<= 16)`
	end
	if not isStringArray(m.battleTypeOptOuts, 8) then
		return `members[{index}].battleTypeOptOuts: expected an array of battle types (<= 8)`
	end
	if m.premiumTime ~= nil and type(m.premiumTime) ~= "boolean" then
		return `members[{index}].premiumTime: expected a boolean`
	end
	if m.loadout ~= nil and (type(m.loadout) ~= "string" or #m.loadout > settings.LOADOUT_MAX_BYTES) then
		return `members[{index}].loadout: expected a string (<= {settings.LOADOUT_MAX_BYTES} bytes)`
	end
	return nil
end

--- Structural and rule validation of one ticket against `now`. Returns (reason, detail) or nil when valid.
--- TIMEOUT / STALE are reported here as well (they depend on `now`).
function Tickets.check(config: MatchmakerConfig, t: any, now: number): (RejectReason?, string?)
	local settings = config.settings
	if type(t) ~= "table" then
		return "INVALID", "ticket: expected a table"
	end
	if not isString(t.ticketId, settings.TICKET_ID_MAX_LEN) then
		return "INVALID", `ticketId: expected a string (1..{settings.TICKET_ID_MAX_LEN})`
	end
	local mode = modeRulesOf(config, t.mode)
	if mode == nil then
		if type(t.mode) == "string" then
			return "UNSUPPORTED_MODE", `mode {t.mode} is not matchmade`
		end
		return "INVALID", "mode: expected a string"
	end
	if type(t.region) ~= "string" or table.find(settings.REGIONS, t.region) == nil then
		return "INVALID", "region: unknown region bucket"
	end
	if not isString(t.mmType, 32) then
		return "INVALID", "mmType: expected a string (1..32)"
	end
	if not isFiniteNumber(t.enqueuedAt) then
		return "INVALID", "enqueuedAt: expected a finite number"
	end
	if t.enqueuedAt > now + settings.FUTURE_SKEW_S then
		return "INVALID", "enqueuedAt: in the future"
	end
	if t.refreshedAt ~= nil and not isFiniteNumber(t.refreshedAt) then
		return "INVALID", "refreshedAt: expected a finite number"
	end
	if t.platoonId ~= nil and not isString(t.platoonId, settings.TICKET_ID_MAX_LEN) then
		return "INVALID", `platoonId: expected a string (1..{settings.TICKET_ID_MAX_LEN})`
	end
	if t.hubJobId ~= nil and not isString(t.hubJobId, 64) then
		return "INVALID", "hubJobId: expected a string (1..64)"
	end
	if t.flags ~= nil then
		if type(t.flags) ~= "table" then
			return "INVALID", "flags: expected a table"
		end
		if t.flags.startWithBots ~= nil and type(t.flags.startWithBots) ~= "boolean" then
			return "INVALID", "flags.startWithBots: expected a boolean"
		end
	end
	local members = t.members
	if not isArray(members) or #members < 1 or #members > settings.PLATOON.MAX_SIZE then
		return "INVALID", `members: expected 1..{settings.PLATOON.MAX_SIZE} members`
	end
	local seen: { [number]: boolean } = {}
	for i, m in members do
		local problem = checkMember(config, m, i)
		if problem then
			return "INVALID", problem
		end
		if seen[m.userId] then
			return "INVALID", `members[{i}].userId: listed twice`
		end
		seen[m.userId] = true
	end
	-- Class rules: one ticket is one team's worth of vehicles (platoons are never split).
	local teamSize = mode.teamSize
	local vec = table.create(Rules.CLASS_COUNT, 0)
	local wheeled = 0
	local tier = members[1].vehicle.tier
	for _, m in members do
		local v = m.vehicle
		if v.tier ~= tier then
			return "INVALID", "platoon: members must share one tier"
		end
		local ci = Rules.CLASS_INDEX[v.class]
		vec[ci] += 1
		if v.wheeled == true then
			wheeled += 1
		end
	end
	if vec[Rules.ARTILLERY] > settings.PLATOON.MAX_ARTILLERY and #members > 1 then
		return "INVALID", `platoon: more than {settings.PLATOON.MAX_ARTILLERY} artillery`
	end
	for ci = 1, Rules.CLASS_COUNT do
		if vec[ci] > Rules.classCap(settings, ci, teamSize, mode) then
			return "INVALID", `class {Rules.CLASSES[ci]}: exceeds the per-team cap of mode {t.mode}`
		end
	end
	if wheeled > Rules.wheeledCap(settings, teamSize) then
		return "INVALID", "wheeled: exceeds the per-team cap"
	end
	if (mode.tierMin and tier < mode.tierMin) or (mode.tierMax and tier > mode.tierMax) then
		return "INVALID", `tier {tier}: outside mode {t.mode}'s tier range`
	end
	-- Age
	if now - t.enqueuedAt > settings.QUEUE_TIMEOUT_S then
		return "TIMEOUT", `waited {math.floor(now - t.enqueuedAt)} s`
	end
	if t.refreshedAt ~= nil and now - t.refreshedAt > settings.STALE_TICKET_S then
		return "STALE", `no heartbeat for {math.floor(now - t.refreshedAt)} s`
	end
	return nil, nil
end

local function describeId(t: any): string
	if type(t) == "table" and type(t.ticketId) == "string" then
		return string.sub(t.ticketId, 1, 64)
	end
	return if type(t) == "table" then tostring(t.ticketId) else "?"
end

local function makeUnit(config: MatchmakerConfig, t: Ticket, now: number): Unit
	local settings = config.settings
	local vec = table.create(Rules.CLASS_COUNT, 0)
	local wheeled = 0
	local roles: { string } = {}
	local classes: { string } = {}
	local streak, battlesSum, battlesKnown = 0, 0, 0
	for _, m in t.members do
		local v = m.vehicle
		vec[Rules.CLASS_INDEX[v.class]] += 1
		if v.wheeled == true then
			wheeled += 1
			table.insert(classes, "light_w")
		else
			table.insert(classes, v.class)
		end
		table.insert(roles, v.role)
		if (m.bottomTierStreak or 0) >= settings.BOTTOM_TIER_STREAK_PROTECTION then
			streak += 1
		end
		if m.battles ~= nil then
			battlesSum += m.battles
			battlesKnown += 1
		end
	end
	table.sort(classes)
	local tier = t.members[1].vehicle.tier
	local waitS = math.max(0, now - t.enqueuedAt)
	local startWithBots = t.flags ~= nil and t.flags.startWithBots == true
	return {
		ticket = t,
		id = t.ticketId,
		order = 0,
		partition = t.mode .. "|" .. t.mmType,
		mode = t.mode,
		size = #t.members,
		tier = tier,
		region = t.region,
		waitS = waitS,
		stage = Rules.stage(settings, waitS, startWithBots),
		classVec = vec,
		wheeled = wheeled,
		roles = roles,
		sig = `{tier}|{table.concat(classes, ",")}`,
		streak = streak,
		battlesSum = battlesSum,
		battlesKnown = battlesKnown,
		used = false,
	}
end

--- Validates one ticket for the Hub's enqueue path: nil when acceptable, else (reason, detail).
function Tickets.validate(config: MatchmakerConfig, ticket: any, now: number): (RejectReason?, string?)
	return Tickets.check(config, ticket, now)
end

--- Validates, de-duplicates and sorts a batch of raw tickets. Units come back oldest first (enqueuedAt, then
--- ticketId), independent of the input order.
function Tickets.prepare(raw: { any }, now: number, config: MatchmakerConfig): Prepared
	local rejected: { RejectedTicket } = {}
	local function reject(t: any, reason: RejectReason, detail: string)
		table.insert(rejected, { ticketId = describeId(t), reason = reason, detail = detail, ticket = t })
	end

	-- 1. Per-ticket validation (incl. TIMEOUT / STALE).
	local valid: { Ticket } = {}
	for _, t in raw do
		local reason, detail = Tickets.check(config, t, now)
		if reason then
			reject(t, reason, detail or "")
		else
			table.insert(valid, t)
		end
	end

	-- 2. ticketId duplicates: identical copies merge, conflicting copies are all rejected.
	local byId: { [string]: { Ticket } } = {}
	local ids: { string } = {}
	for _, t in valid do
		local list = byId[t.ticketId]
		if list == nil then
			list = {}
			byId[t.ticketId] = list
			table.insert(ids, t.ticketId)
		end
		table.insert(list, t)
	end
	table.sort(ids)
	local unique: { Ticket } = {}
	for _, id in ids do
		local list = byId[id]
		local first = list[1]
		local identical = true
		for i = 2, #list do
			if list[i] ~= first and not TableUtil.deepEqual(list[i], first) then
				identical = false
				break
			end
		end
		if identical then
			table.insert(unique, first)
		else
			for _, t in list do
				reject(t, "DUPLICATE_TICKET", `{#list} different tickets share this ticketId`)
			end
		end
	end

	-- 3. Members in several tickets: the newest ticket wins (enqueuedAt desc, then ticketId desc).
	table.sort(unique, function(a: Ticket, b: Ticket): boolean
		if a.enqueuedAt ~= b.enqueuedAt then
			return a.enqueuedAt > b.enqueuedAt
		end
		return a.ticketId > b.ticketId
	end)
	local owner: { [number]: string } = {}
	local kept: { Ticket } = {}
	for _, t in unique do
		local clash: string? = nil
		for _, m in t.members do
			local o = owner[m.userId]
			if o ~= nil then
				clash = `user {m.userId} is in newer ticket {o}`
				break
			end
		end
		if clash then
			reject(t, "DUPLICATE_MEMBER", clash)
		else
			for _, m in t.members do
				owner[m.userId] = t.ticketId
			end
			table.insert(kept, t)
		end
	end

	-- 4. Units, oldest first.
	table.sort(kept, function(a: Ticket, b: Ticket): boolean
		if a.enqueuedAt ~= b.enqueuedAt then
			return a.enqueuedAt < b.enqueuedAt
		end
		return a.ticketId < b.ticketId
	end)
	local units: { Unit } = table.create(#kept)
	for i, t in kept do
		local u = makeUnit(config, t, now)
		u.order = i
		units[i] = u
	end
	table.sort(rejected, function(a: RejectedTicket, b: RejectedTicket): boolean
		if a.ticketId ~= b.ticketId then
			return a.ticketId < b.ticketId
		end
		return a.reason < b.reason
	end)
	return { units = units, rejected = rejected }
end

return Tickets
