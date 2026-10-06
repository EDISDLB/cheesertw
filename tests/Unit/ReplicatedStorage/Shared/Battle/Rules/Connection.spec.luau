local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ModeRules = require("@game/ReplicatedStorage/Shared/Battle/Rules/ModeRules")
local Connection = require("@game/ReplicatedStorage/Shared/Battle/Rules/Connection")

local GO = 100

-- 1, 2 humans (team 1); 3 human; 4 bot.
local ROSTER = {
	{ participantId = 1, userId = 1001 },
	{ participantId = 2, userId = 1002 },
	{ participantId = 3, userId = 1003 },
	{ participantId = 4 },
}

local function started(mode: string?, arrivals: { number }?)
	local state = Connection.new(ModeRules.defaults(mode or "Random", "Standard"), ROSTER, 0)
	for _, id in arrivals or { 1, 2, 3 } do
		Connection.arrive(state, id, 10)
	end
	local events = {}
	Connection.start(state, GO, events)
	return state, events
end

local function changes(events): { string }
	local out = {}
	for _, e in events do
		if e.type == "ControlChanged" then
			table.insert(out, `{e.t}:{e.participant}>{e.controller}:{e.reason}`)
		end
	end
	return out
end

-- Steps from `from` to `to` (inclusive) at 30 Hz, calling `each(now)` first when given.
local function run(state, from: number, to: number, events, notices, each: ((number) -> ())?)
	local n = math.floor((to - from) * 30 + 0.5)
	for i = 0, n do
		local now = from + i / 30
		if each then
			each(now)
		end
		Connection.step(state, now, events, notices)
	end
end

describe("Connection (00-DECISIONS §9 Disconnect / AFK / leave)", function()
	it("GO: absent humans are bot-driven from t = 0; bots and present humans emit nothing", function()
		local state, events = started(nil, { 1, 3 })
		expect(changes(events)).toEqual({ "0:2>Bot:Disconnect" })
		expect(Connection.isBotControlled(state, 2)).toBe(true)
		expect(Connection.isBotControlled(state, 1)).toBe(false)
		expect(Connection.isBotControlled(state, 4)).toBe(true)
		expect(Connection.get(state, 2).botReason).toBe("Absent")
		Connection.start(state, GO + 5, events) -- idempotent
		expect(#events).toBe(1)
	end)

	it("a late arrival takes over its vehicle ('Arrived'); an expired slot stays a bot", function()
		local state, events = started(nil, { 1 })
		local notices = {}
		expect(Connection.arrive(state, 2, GO + 12, events, notices)).toBe(true)
		expect(Connection.expire(state, 3)).toBe(true)
		expect(Connection.arrive(state, 3, GO + 50, events)).toBe(false)
		expect(changes(events)).toEqual({ "0:2>Bot:Disconnect", "0:3>Bot:Disconnect", "12:2>Player:Arrived" })
		expect(notices).toEqual({ { participantId = 2, kind = "ControlRestored", reason = "Arrived" } })
		expect(Connection.get(state, 3).status).toBe("Expired")
	end)

	it("disconnect → bot after 5 s; reconnect gives control back at once (REG-BTL-04)", function()
		local state = started()
		local events, notices = {}, {}
		local function busy(now)
			Connection.activity(state, 2, now)
			Connection.activity(state, 3, now)
		end
		expect(Connection.disconnect(state, 1, GO + 100)).toBe(true)
		run(state, GO + 100, GO + 104.9, events, notices, busy)
		expect(#events).toBe(0)
		run(state, GO + 105, GO + 106, events, notices, busy)
		-- t is the battle time of the takeover step
		expect(changes(events)).toEqual({ "105:1>Bot:Disconnect" })
		events = {}
		expect(Connection.arrive(state, 1, GO + 300, events, notices)).toBe(true)
		expect(changes(events)).toEqual({ "300:1>Player:Reconnect" })
		expect(Connection.get(state, 1).reconnects).toBe(1)
		expect(Connection.get(state, 1).disconnects).toBe(1)
		expect(notices[1].kind).toBe("BotTakeover")
	end)

	it("a reconnect inside the 5 s delay changes nothing", function()
		local state = started()
		local events = {}
		Connection.disconnect(state, 1, GO + 50)
		run(state, GO + 50, GO + 53, events)
		Connection.arrive(state, 1, GO + 54, events)
		run(state, GO + 54, GO + 70, events, nil, function(now)
			Connection.activity(state, 2, now)
			Connection.activity(state, 3, now)
		end)
		expect(events).toEqual({})
		expect(Connection.controller(state, 1)).toBe("Player")
	end)

	it("disconnected during the countdown: long ago → bot at GO, recently → bot when the delay expires", function()
		local state = Connection.new(ModeRules.defaults("Random", "Standard"), ROSTER, 0)
		for _, id in { 1, 2, 3 } do
			Connection.arrive(state, id, 10)
		end
		Connection.disconnect(state, 1, GO - 10)
		Connection.disconnect(state, 2, GO - 2)
		local events = {}
		Connection.start(state, GO, events)
		run(state, GO, GO + 4, events)
		expect(changes(events)).toEqual({ "0:1>Bot:Disconnect", "3:2>Bot:Disconnect" })
	end)

	it("AFK: warning at 60 s, takeover + strike at 90 s, input gives control back, strike stays", function()
		local state = started()
		local events, notices = {}, {}
		local function busy(now)
			Connection.activity(state, 2, now)
			Connection.activity(state, 3, now)
		end
		run(state, GO, GO + 59.9, events, notices, busy)
		expect(notices).toEqual({})
		run(state, GO + 60, GO + 89.9, events, notices, busy)
		expect(notices).toEqual({ { participantId = 1, kind = "AfkWarning", reason = "Afk" } })
		expect(#events).toBe(0)
		run(state, GO + 90, GO + 91, events, notices, busy)
		expect(changes(events)).toEqual({ "90:1>Bot:Afk" })
		expect(Connection.get(state, 1).afkStrike).toBe(true)
		expect(Connection.activity(state, 1, GO + 120, events, notices)).toBe(true)
		expect(changes(events)).toEqual({ "90:1>Bot:Afk", "120:1>Player:Reconnect" })
		expect(Connection.get(state, 1).afkStrike).toBe(true)
		expect(Connection.controller(state, 1)).toBe("Player")
	end)

	it("REG-BTL-05: a stuck/overturned player who keeps sending input is never flagged", function()
		local state = started()
		local events, notices = {}, {}
		local nextInput = GO
		run(state, GO, GO + 600, events, notices, function(now)
			if now >= nextInput then
				Connection.activity(state, 1, now)
				Connection.activity(state, 2, now)
				Connection.activity(state, 3, now)
				nextInput = now + 55
			end
		end)
		expect(events).toEqual({})
		expect(notices).toEqual({})
	end)

	it("modes without AFK (Practice/Training/Bootcamp) never warn or strike", function()
		for _, mode in { "Practice", "Training", "Bootcamp" } do
			local state = started(mode)
			local events, notices = {}, {}
			run(state, GO, GO + 200, events, notices)
			expect(events).toEqual({})
			expect(notices).toEqual({})
		end
	end)

	it("leaving alive: bot at once, leftAlive (strike, no win bonus); leaving dead changes nothing", function()
		local state = started()
		local events = {}
		expect(Connection.leave(state, 1, GO + 30, events)).toBe(true)
		expect(changes(events)).toEqual({ "30:1>Bot:Left" })
		expect(Connection.get(state, 1).leftAlive).toBe(true)
		-- The PlayerRemoving that follows the teleport is not a second change.
		expect(Connection.disconnect(state, 1, GO + 31)).toBe(false)
		run(state, GO + 31, GO + 40, events)
		expect(#events).toBe(1)

		Connection.destroyed(state, 2)
		expect(Connection.leave(state, 2, GO + 50, events)).toBe(true)
		expect(Connection.get(state, 2).leftAlive).toBe(false)
		expect(#events).toBe(1)
	end)

	it("leaving during the countdown is a leave at GO", function()
		local state = Connection.new(ModeRules.defaults("Random", "Standard"), ROSTER, 0)
		for _, id in { 1, 2, 3 } do
			Connection.arrive(state, id, 10)
		end
		Connection.leave(state, 3, GO - 5)
		local events = {}
		Connection.start(state, GO, events)
		expect(changes(events)).toEqual({ "0:3>Bot:Left" })
		expect(Connection.get(state, 3).leftAlive).toBe(true)
	end)

	it("destroyed vehicles and ended battles never change controller", function()
		local state = started()
		local events = {}
		Connection.destroyed(state, 1)
		Connection.disconnect(state, 1, GO + 10)
		run(state, GO + 10, GO + 200, events)
		expect(changes(events)).toEqual({ "90:2>Bot:Afk", "90:3>Bot:Afk" })
		Connection.finish(state)
		local after = {}
		Connection.disconnect(state, 2, GO + 300)
		Connection.step(state, GO + 400, after)
		expect(Connection.arrive(state, 2, GO + 500, after)).toBe(false)
		expect(after).toEqual({})
	end)

	it("BOT_TAKEOVER = false leaves absent and disconnected vehicles idle (WoT behaviour)", function()
		local settings = ModeRules.with(ModeRules.defaults("Random", "Standard"), { botTakeover = false })
		local state = Connection.new(settings, ROSTER, 0)
		Connection.arrive(state, 1, 10)
		local events = {}
		Connection.start(state, GO, events)
		Connection.disconnect(state, 1, GO + 1)
		run(state, GO, GO + 120, events)
		expect(events).toEqual({})
		expect(Connection.controller(state, 2)).toBe("Player")
	end)

	it("unknown ids and bots are ignored", function()
		local state = started()
		expect(Connection.arrive(state, 99, GO)).toBe(false)
		expect(Connection.disconnect(state, 4, GO)).toBe(false)
		expect(Connection.activity(state, 4, GO)).toBe(false)
		expect(Connection.leave(state, 99, GO)).toBe(false)
		expect(Connection.destroyed(state, 99)).toBe(false)
		expect(Connection.controller(state, 99)).toBe("Bot")
	end)

	it("strike ladder: 1 → no rewards, 2 → 10 min lock, 3+ → 60 min", function()
		expect(Connection.strikePenalty(0)).toEqual({ noRewards = false, queueLockS = 0 })
		expect(Connection.strikePenalty(0 / 0)).toEqual({ noRewards = false, queueLockS = 0 })
		expect(Connection.strikePenalty(1)).toEqual({ noRewards = true, queueLockS = 0 })
		expect(Connection.strikePenalty(2)).toEqual({ noRewards = true, queueLockS = 600 })
		expect(Connection.strikePenalty(3)).toEqual({ noRewards = true, queueLockS = 3600 })
		expect(Connection.strikePenalty(12)).toEqual({ noRewards = true, queueLockS = 3600 })
	end)
end)
