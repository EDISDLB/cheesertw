local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ModeRules = require("@game/ReplicatedStorage/Shared/Battle/Rules/ModeRules")
local Phases = require("@game/ReplicatedStorage/Shared/Battle/Rules/Phases")
local Outcome = require("@game/ReplicatedStorage/Shared/Battle/Rules/Outcome")

-- Roster: participants 1–2 team 1 (humans 1001, 1002), 3–4 team 2 (3 human 1003, 4 bot).
local function roster()
	return {
		{ participantId = 1, team = 1, userId = 1001 },
		{ participantId = 2, team = 1, userId = 1002 },
		{ participantId = 3, team = 2, userId = 1003 },
		{ participantId = 4, team = 2 },
	}
end

local function transitionsOf(out): { string }
	local list = {}
	for _, tr in out.transitions do
		table.insert(list, `{tr.from}>{tr.to}@{tr.at}:{tr.reason}`)
	end
	return list
end

local function arriveAll(state, at: number)
	for _, userId in { 1001, 1002, 1003 } do
		expect(Phases.admit(state, userId, at, true)).toBeOk()
	end
end

describe("Phases timeline", function()
	it("Random Standard: early start once everyone loaded, 20 s countdown, 12 min timer", function()
		local s = ModeRules.defaults("Random", "Standard")
		local state = Phases.new(s, roster(), 0)
		local out = Phases.newOutput()
		expect(state.phase).toBe("Preparing")
		arriveAll(state, 2)
		expect(Phases.markReady(state, 10, out)).toBe(true)
		Phases.markLoaded(state, 1001, 11)
		Phases.markLoaded(state, 1002, 12)
		expect(Phases.step(state, 13, out)).toBe("Loading")
		Phases.markLoaded(state, 1003, 14)
		expect(Phases.step(state, 14.02, out)).toBe("Countdown")
		expect(state.countdownAt).toBe(14)
		expect(Phases.step(state, 33.99, out)).toBe("Countdown")
		expect(Phases.step(state, 34.01, out)).toBe("Active")
		expect(state.goAt).toBe(34)
		expect(state.endsAt).toBe(34 + 720)
		expect(transitionsOf(out)).toEqual({
			"Preparing>Loading@10:Ready",
			"Loading>Countdown@14:AllLoaded",
			"Countdown>Active@34:CountdownDone",
		})
		expect(out.events).toEqual({ { type = "Started", t = 0 } })
		expect(Phases.battleTime(state, 100)).toBe(66)
		expect(Phases.timeLeft(state, 100)).toBe(654)
	end)

	it("per-mode timelines (ready at 10 with everyone loaded → GO = 10 + countdown, end = GO + duration)", function()
		local cases = {
			{ mode = "Random", bt = "Standard", go = 30, ends = 750 },
			{ mode = "Random", bt = "Encounter", go = 30, ends = 750 },
			{ mode = "Random", bt = "Assault", go = 30, ends = 510 },
			{ mode = "Training", bt = "Standard", go = 30, ends = 750 },
			{ mode = "Bootcamp", bt = nil, go = 20, ends = 620 },
			{ mode = "Practice", bt = nil, go = 13, ends = 1813 },
			{ mode = "Event", bt = "Standard", go = 30, ends = 330, durationS = 300 },
		}
		for _, case in cases do
			local s = ModeRules.defaults(case.mode, case.bt, { durationS = case.durationS })
			local state = Phases.new(s, { { participantId = 1, team = 1, userId = 7 } }, 0)
			expect(Phases.admit(state, 7, 1, true)).toBeOk()
			Phases.markLoaded(state, 7, 2)
			Phases.markReady(state, 10)
			Phases.step(state, 10)
			expect(state.phase).toBe("Countdown")
			Phases.step(state, case.go)
			expect(state.phase).toBe("Active")
			expect(state.goAt).toBe(case.go)
			expect(state.endsAt).toBe(case.ends)
			expect(Phases.isTimeUp(state, case.ends - 0.01)).toBe(false)
			expect(Phases.isTimeUp(state, case.ends)).toBe(true)
		end
	end)

	it("load timeout: the countdown starts 30 s after ready without the missing human", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		local out = Phases.newOutput()
		expect(Phases.admit(state, 1001, 1, true)).toBeOk()
		expect(Phases.admit(state, 1002, 1, true)).toBeOk()
		Phases.markReady(state, 5)
		Phases.markLoaded(state, 1001, 6)
		Phases.markLoaded(state, 1002, 6)
		expect(Phases.step(state, 34.9, out)).toBe("Loading")
		expect(Phases.step(state, 35, out)).toBe("Countdown")
		expect(state.countdownAt).toBe(35)
		-- 1003 may still arrive within 45 s of creation (bot-driven until then)...
		expect(Phases.admit(state, 1003, 44.5, true)).toBeOk()
		-- ...but the window is per first arrival only.
		expect(transitionsOf(out)).toEqual({ "Loading>Countdown@35:LoadTimeout" })
	end)

	it("expires humans that never arrive within the arrival window (REG-TP-03, REG-MMK-06)", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 100)
		local out = Phases.newOutput()
		expect(Phases.admit(state, 1001, 101, true)).toBeOk()
		Phases.markReady(state, 105, out)
		Phases.step(state, 145, out)
		expect(out.expired).toEqual({})
		Phases.step(state, 145.1, out)
		expect(out.expired).toEqual({ 1002, 1003 })
		expect(Phases.human(state, 1002).expired).toBe(true)
		local late = Phases.admit(state, 1002, 146, true)
		expect(late).toBeErr("NOT_ALLOWED")
		expect(late.detail).toBe("ARRIVAL_WINDOW_CLOSED")
		-- A late admit attempt before any step also expires the slot.
		local other = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		expect(Phases.admit(other, 1003, 45, true)).toBeOk()
		expect(Phases.admit(other, 1002, 45.01, true).detail).toBe("ARRIVAL_WINDOW_CLOSED")
	end)

	it("a returning player is admitted after the window until the battle ends (REG-BTL-04)", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		arriveAll(state, 1)
		Phases.markReady(state, 2)
		for _, u in { 1001, 1002, 1003 } do
			Phases.markLoaded(state, u, 3)
		end
		Phases.step(state, 30)
		expect(state.phase).toBe("Active")
		expect(Phases.markGone(state, 1002, 100)).toBe(true)
		expect(Phases.admit(state, 1002, 400, true)).toBeOk()
		expect(Phases.finish(state, Outcome.draw("Timeout", { 1, 2 }), 500)).toBe(true)
		expect(Phases.admit(state, 1002, 501, true).detail).toBe("BATTLE_OVER")
	end)

	it("admit rejects users outside the roster and foreign sources", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		expect(Phases.admit(state, 9999, 1, true).detail).toBe("NOT_IN_ROSTER")
		expect(Phases.admit(state, 1001, 1, false).detail).toBe("FOREIGN_SOURCE")
		expect(Phases.admit(state, 1001, 1, true)).toBeOk()
		expect(Phases.admit(state, 1001, 2, true).value).toBe(1)
		expect(Phases.arrivedCount(state)).toBe(1)
	end)

	it("a human who leaves during loading no longer blocks the early start", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		arriveAll(state, 1)
		Phases.markReady(state, 5)
		Phases.markLoaded(state, 1001, 6)
		Phases.markLoaded(state, 1003, 7)
		Phases.markGone(state, 1002, 8)
		Phases.step(state, 9)
		expect(state.phase).toBe("Countdown")
		expect(state.countdownAt).toBe(8)
	end)

	it("early start disabled waits for the load timeout", function()
		local s = ModeRules.with(ModeRules.defaults("Random", "Standard"), { earlyStart = false })
		local state = Phases.new(s, { { participantId = 1, team = 1, userId = 7 } }, 0)
		Phases.admit(state, 7, 1, true)
		Phases.markLoaded(state, 7, 2)
		Phases.markReady(state, 3)
		expect(Phases.step(state, 20)).toBe("Loading")
		expect(Phases.step(state, 33)).toBe("Countdown")
	end)

	it("aborts with too few humans at the gate (no human arrived)", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		local out = Phases.newOutput()
		Phases.markReady(state, 5, out)
		Phases.step(state, 35, out)
		expect(state.phase).toBe("Ending")
		expect(state.abortReason).toBe("TooFewHumans")
		expect(state.outcome).toEqual(Outcome.aborted({ 1, 2 }))
		expect(out.events).toEqual({ { type = "Ended", t = 0, outcome = Outcome.aborted({ 1, 2 }) } })
		expect(Phases.allows(state, "Move")).toBe(false)
	end)

	it("a bot-only battle (MIN_HUMANS 0) starts at ready", function()
		local s = ModeRules.with(ModeRules.defaults("Random", "Standard"), { minHumans = 0 })
		local state = Phases.new(s, { { participantId = 1, team = 1 }, { participantId = 2, team = 2 } }, 0)
		Phases.markReady(state, 4)
		expect(Phases.step(state, 4)).toBe("Countdown")
		expect(Phases.step(state, 24)).toBe("Active")
	end)

	it("aborts when preparing takes longer than PREPARE_TIMEOUT_S", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		expect(Phases.step(state, 89.9)).toBe("Preparing")
		expect(Phases.step(state, 90)).toBe("Ending")
		expect(state.abortReason).toBe("PrepareTimeout")
		expect(state.endedAt).toBe(90)
		expect(Phases.markReady(state, 91)).toBe(false)
	end)

	it("ending: 6 s banner → Results → Closed on delivery or after RESULTS_TIMEOUT_S", function()
		local function activeBattle()
			local s = ModeRules.with(ModeRules.defaults("Random", "Standard"), { minHumans = 0 })
			local state = Phases.new(s, { { participantId = 1, team = 1 }, { participantId = 2, team = 2 } }, 0)
			Phases.markReady(state, 0)
			Phases.step(state, 20)
			return state
		end
		local state = activeBattle()
		local out = Phases.newOutput()
		local outcome = Outcome.make(1, "Destruction", { 1, 2 })
		expect(Phases.finish(state, outcome, 120, out)).toBe(true)
		expect(Phases.finish(state, Outcome.make(2, "Destruction", { 1, 2 }), 120, out)).toBe(false)
		expect(state.outcome).toEqual(outcome)
		expect(out.events).toEqual({ { type = "Ended", t = 100, outcome = outcome } })
		expect(Phases.step(state, 125.9, out)).toBe("Ending")
		expect(Phases.step(state, 126, out)).toBe("Results")
		expect(Phases.step(state, 185.9, out)).toBe("Results")
		expect(Phases.step(state, 186, out)).toBe("Closed")
		expect(state.closedAt).toBe(186)

		local delivered = activeBattle()
		Phases.finish(delivered, outcome, 50)
		expect(Phases.markResultsDelivered(delivered, 53)).toBe(true) -- during the banner
		expect(Phases.step(delivered, 56)).toBe("Closed")
		expect(delivered.closedAt).toBe(56)
		expect(Phases.markResultsDelivered(delivered, 57)).toBe(false)
	end)

	it("finish only works in Active and clamps the end to the timer", function()
		local s = ModeRules.with(ModeRules.defaults("Random", "Assault"), { minHumans = 0 })
		local state = Phases.new(s, { { participantId = 1, team = 1 }, { participantId = 2, team = 2 } }, 0)
		expect(Phases.finish(state, Outcome.draw("Timeout", { 1, 2 }), 1)).toBe(false)
		Phases.markReady(state, 0)
		Phases.step(state, 20)
		local out = Phases.newOutput()
		expect(Phases.finish(state, Outcome.make(2, "DefenderHeld", { 1, 2 }), 500.03, out)).toBe(true)
		expect(state.endedAt).toBe(500)
		expect(out.events[1].t).toBe(480)
		expect(Phases.battleTime(state, 9999)).toBe(480)
		expect(Phases.timeLeft(state, 9999)).toBe(0)
	end)

	it("REG-BTL-03: endsAt is fixed; timeLeft + battleTime = duration at every step, any cadence", function()
		local s = ModeRules.with(ModeRules.defaults("Random", "Standard"), { minHumans = 0 })
		local state = Phases.new(s, { { participantId = 1, team = 1 } }, 1000)
		Phases.markReady(state, 1000)
		Phases.step(state, 1020)
		local endsAt = state.endsAt
		local now = 1020
		local worst = 0
		local i = 0
		while now < 1020 + 720 do
			i += 1
			now += if i % 3 == 0 then 0.031 else 0.0347
			Phases.step(state, now)
			expect(state.endsAt).toBe(endsAt)
			if now <= endsAt then
				local drift = math.abs(Phases.timeLeft(state, now) + Phases.battleTime(state, now) - 720)
				worst = math.max(worst, drift)
			else
				expect(Phases.timeLeft(state, now)).toBe(0)
			end
		end
		expect(worst).toBeLessThan(1e-6)
	end)

	it("the timeline is identical whatever the step cadence (deterministic transitions)", function()
		local function run(dt: number): { string }
			local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
			local out = Phases.newOutput()
			local now = 0
			local loaded = false
			while now < 200 do
				now += dt
				if now >= 3 and state.phase == "Preparing" then
					Phases.markReady(state, 3, out)
				end
				if not loaded and now >= 4 then
					loaded = true
					arriveAll(state, 4)
					for _, u in { 1001, 1002, 1003 } do
						Phases.markLoaded(state, u, 4)
					end
				end
				Phases.step(state, now, out)
			end
			return transitionsOf(out)
		end
		expect(run(1 / 30)).toEqual(run(0.37))
		expect(run(1 / 30)).toEqual(run(5))
	end)

	it("one late step can cross several phases; NaN and backwards time are ignored", function()
		local s = ModeRules.with(ModeRules.defaults("Random", "Standard"), { minHumans = 0 })
		local state = Phases.new(s, { { participantId = 1, team = 1 } }, 0)
		local out = Phases.newOutput()
		Phases.markReady(state, 1, out)
		expect(Phases.step(state, 0 / 0, out)).toBe("Loading")
		expect(Phases.step(state, 5000, out)).toBe("Active")
		expect(#out.transitions).toBe(3)
		expect(Phases.isTimeUp(state, 5000)).toBe(true)
		expect(Phases.step(state, 10, out)).toBe("Active")
		expect(state.lastNow).toBe(5000)
	end)

	it("abort is possible in any phase before Ending and records the reason", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		arriveAll(state, 1)
		Phases.markReady(state, 2)
		for _, u in { 1001, 1002, 1003 } do
			Phases.markLoaded(state, u, 3)
		end
		Phases.step(state, 100)
		local out = Phases.newOutput()
		expect(Phases.abort(state, "ServerClosing", 150, out)).toBe(true)
		expect(state.abortReason).toBe("ServerClosing")
		expect(out.events[1]).toEqual({ type = "Ended", t = 127, outcome = Outcome.aborted({ 1, 2 }) })
		expect(Phases.abort(state, "Internal", 151)).toBe(false)
		expect(Phases.isOver(state)).toBe(true)
	end)
end)

describe("Phases.allows (REG-BTL-06)", function()
	it("countdown rejects movement, fire and consumables but allows turret rotation", function()
		local s = ModeRules.with(ModeRules.defaults("Random", "Standard"), { minHumans = 0 })
		local state = Phases.new(s, { { participantId = 1, team = 1 } }, 0)
		local matrix = {}
		local function snapshot()
			local row = {}
			for _, action in { "Move", "Fire", "Turret", "Consumable", "Chat" } do
				row[action] = Phases.allows(state, action)
			end
			matrix[state.phase] = row
		end
		snapshot()
		Phases.markReady(state, 0)
		snapshot()
		Phases.step(state, 0)
		snapshot()
		Phases.step(state, 20)
		snapshot()
		Phases.finish(state, Outcome.draw("Timeout", { 1 }), 30)
		snapshot()
		Phases.step(state, 36)
		snapshot()
		Phases.step(state, 1000)
		snapshot()
		local none = { Move = false, Fire = false, Turret = false, Consumable = false, Chat = true }
		expect(matrix).toEqual({
			Preparing = none,
			Loading = none,
			Countdown = { Move = false, Fire = false, Turret = true, Consumable = false, Chat = true },
			Active = { Move = true, Fire = true, Turret = true, Consumable = true, Chat = true },
			Ending = none,
			Results = none,
			Closed = { Move = false, Fire = false, Turret = false, Consumable = false, Chat = false },
		})
	end)
end)

describe("Phases.checkAccess (stale access codes, ARCHITECTURE §2.1)", function()
	local function info(overrides)
		local base = {
			privateServerId = "ps-123",
			privateServerOwnerId = 0,
			matchmakingType = 0,
			manifest = { mmType = 0, ended = false },
		}
		for key, value in overrides do
			base[key] = value
		end
		return base
	end

	it("accepts a reserved server with a live manifest of the same matchmaking type", function()
		expect(Phases.checkAccess(info({}))).toBeOk()
	end)

	it("rejects every stale or foreign case with a reason", function()
		local cases = {
			{ patch = { privateServerId = "" }, code = "NOT_ALLOWED", detail = "NO_PRIVATE_SERVER" },
			{ patch = { privateServerOwnerId = 42 }, code = "NOT_ALLOWED", detail = "PLAYER_OWNED_SERVER" },
			{ patch = { manifest = false }, code = "NOT_FOUND", detail = "MANIFEST_MISSING" },
			{ patch = { manifest = { mmType = 0, ended = true } }, code = "NOT_ALLOWED", detail = "MANIFEST_ENDED" },
			{ patch = { matchmakingType = 1 }, code = "NOT_ALLOWED", detail = "MATCHMAKING_TYPE_MISMATCH" },
			{ patch = { manifest = { ended = false } }, code = "NOT_ALLOWED", detail = "MATCHMAKING_TYPE_MISMATCH" },
		}
		for _, case in cases do
			local i = info(case.patch)
			if i.manifest == false then
				i.manifest = nil
			end
			local r = Phases.checkAccess(i)
			expect(r).toBeErr(case.code)
			expect(r.detail).toBe(case.detail)
		end
	end)

	it("a rejected server aborts with StaleAccessCode before anyone plays", function()
		local state = Phases.new(ModeRules.defaults("Random", "Standard"), roster(), 0)
		local r = Phases.checkAccess(info({ manifest = { mmType = 0, ended = true } }))
		expect(r.ok).toBe(false)
		expect(Phases.abort(state, "StaleAccessCode", 0.5)).toBe(true)
		expect(state.abortReason).toBe("StaleAccessCode")
		expect(Phases.admit(state, 1001, 1, true).detail).toBe("BATTLE_OVER")
	end)
end)
