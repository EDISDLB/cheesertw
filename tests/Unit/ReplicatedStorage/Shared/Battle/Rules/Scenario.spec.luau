-- End-to-end wiring of the battle rules in the BattleInstance tick order (ARCHITECTURE §6.1 step 8):
-- Phases → Connection → (damage: Attribution.fill → Capture.applyDamageEvent → Ledger) → Capture.step → Outcome →
-- Phases.finish → Ledger.finalize. Mirrors what Server/Battle/BattleInstance is expected to do.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Units = require("@game/ReplicatedStorage/Shared/Core/Units")
local ModeRules = require("@game/ReplicatedStorage/Shared/Battle/Rules/ModeRules")
local Phases = require("@game/ReplicatedStorage/Shared/Battle/Rules/Phases")
local Capture = require("@game/ReplicatedStorage/Shared/Battle/Rules/Capture")
local Outcome = require("@game/ReplicatedStorage/Shared/Battle/Rules/Outcome")
local Connection = require("@game/ReplicatedStorage/Shared/Battle/Rules/Connection")
local Attribution = require("@game/ReplicatedStorage/Shared/Battle/Ledger/Attribution")
local Ledger = require("@game/ReplicatedStorage/Shared/Battle/Ledger/Ledger")
local Fixtures = require("../Ledger/BattleFixtures")

local BASES = {
	{ id = "base1", battleType = "Standard", team = 1, center = { x = 0, z = 0 } },
	{ id = "base2", battleType = "Standard", team = 2, center = { x = 500, z = 0 } },
}

local function at(xm: number, zm: number): Vector3
	return Vector3.new(Units.mToStuds(xm), 0, Units.mToStuds(zm))
end

-- Team 1: 1 (human 1001), 2 (bot). Team 2: 11 (human 1011), 12 (bot).
local function simulate(dt: number, opts: { disconnect: boolean? }?)
	local o = opts or {}
	local settings = ModeRules.defaults("Random", "Standard")
	local participants = Fixtures.roster({
		{ id = 1, team = 1 },
		{ id = 2, team = 1, bot = true },
		{ id = 11, team = 2, class = "heavy" },
		{ id = 12, team = 2, bot = true },
	})
	local roster = {}
	for _, p in participants do
		table.insert(roster, { participantId = p.participantId, team = p.team, userId = p.userId })
	end

	local stream = {}
	local function emit(list)
		for _, e in list do
			table.insert(stream, e)
		end
		table.clear(list)
	end

	local phases = Phases.new(settings, roster, 0)
	local conn = Connection.new(settings, roster, 0)
	local capture = Capture.new(settings, BASES, roster)
	local attribution = Attribution.new(roster, settings)
	local ledger = Ledger.new(Fixtures.ledgerSpec(participants, { settings = settings }))
	local out = Phases.newOutput()
	local events = {}

	expect(Phases.admit(phases, 1001, 1, true)).toBeOk()
	Connection.arrive(conn, 1, 1)
	expect(Phases.admit(phases, 1011, 2, true)).toBeOk()
	Connection.arrive(conn, 11, 2)
	Phases.markReady(phases, 5, out)
	Phases.markLoaded(phases, 1001, 6)
	Phases.markLoaded(phases, 1011, 6)

	local vehicles = {
		{ id = 1, team = 1, position = at(500, 10), alive = true },
		{ id = 2, team = 1, position = at(510, -5), alive = true },
		{ id = 11, team = 2, position = at(300, 0), alive = true },
		{ id = 12, team = 2, position = at(250, 100), alive = true },
	}
	local shotDone = false
	local now = 0
	while not Phases.isOver(phases) and now < 1000 do
		now += dt
		local wasActive = phases.phase == "Active"
		Phases.step(phases, now, out)
		if not wasActive and phases.phase == "Active" then
			Connection.start(conn, phases.goAt :: number, events)
		end
		for _, e in out.events do
			table.insert(events, e)
		end
		Phases.clearOutput(out)
		if phases.phase ~= "Active" then
			emit(events)
			continue
		end
		local t = Phases.battleTime(phases, now)

		-- Inputs / connection.
		Connection.activity(conn, 11, now)
		if not (o.disconnect and t >= 10) then
			Connection.activity(conn, 1, now)
		end
		if o.disconnect and t >= 10 and t - dt < 10 then
			Connection.disconnect(conn, 1, now)
		end
		Connection.step(conn, now, events)

		-- Spotting: the bot 2 keeps 11 lit.
		Attribution.noteSeen(attribution, 2, 11, t)

		-- Combat: at t = 20, 11 hits capper 1 (resets its points); 1 answers 11 (spot-assisted by 2).
		if t >= 20 and not shotDone then
			shotDone = true
			local d1 = Fixtures.damage({ t = t, attacker = 11, target = 1, damage = 300 })
			Attribution.fill(attribution, d1)
			Capture.applyDamageEvent(capture, d1, events)
			table.insert(events, { type = "Damage", t = t, damage = d1 })
			local d2 = Fixtures.damage({ t = t, attacker = 1, target = 11, damage = 250 })
			Attribution.fill(attribution, d2)
			Capture.applyDamageEvent(capture, d2, events)
			table.insert(events, { type = "Damage", t = t, damage = d2 })
		end

		-- Objectives.
		local completed = Capture.step(capture, vehicles, dt, t, events)
		for _, e in events do
			Ledger.apply(ledger, e)
		end
		local outcome = Outcome.evaluate({
			settings = settings,
			teams = Ledger.teams(ledger),
			rosterByTeam = Ledger.rosterByTeam(ledger),
			aliveByTeam = Ledger.aliveByTeam(ledger),
			captured = completed,
			timeUp = Phases.isTimeUp(phases, now),
			defender = Capture.defenderTeam(capture),
		})
		emit(events)
		if outcome then
			Phases.finish(phases, outcome, now, out)
			Connection.finish(conn)
			for _, e in out.events do
				Ledger.apply(ledger, e)
				table.insert(stream, e)
			end
			Phases.clearOutput(out)
		end
	end
	Phases.markResultsDelivered(phases, now + 7)
	Phases.step(phases, now + 7)
	local result = Ledger.finalize(ledger, { capturePoints = Capture.participantPoints(capture) })
	return result, stream, phases
end

local function statsOf(result, id)
	for _, p in result.participants do
		if p.participant.participantId == id then
			return p.stats, p.participant
		end
	end
	error("missing " .. id)
end

describe("Battle rules end to end", function()
	it("two cappers, one reset by a defender: team 1 wins by capture at t = 60", function()
		local result, stream, phases = simulate(1 / 30)
		expect(phases.phase).toBe("Closed")
		expect(phases.goAt).toBe(26)
		expect(result.outcome.winner).toBe(1)
		expect(result.outcome.reason).toBe("Capture")
		-- 40 points at t = 20 (2 × 1 pt/s), capper 1 reset to 0 (progress 20), then 2 pt/s → 100 at t = 60.
		expect(math.abs(result.durationS - 60)).toBeLessThan(1 / 30 + 1e-9)
		expect(statsOf(result, 1).capturePoints).toBeCloseTo(40, 0.05)
		expect(statsOf(result, 2).capturePoints).toBeCloseTo(60, 0.05)
		expect(statsOf(result, 11).defensePoints).toBeCloseTo(20, 0.05)
		expect(statsOf(result, 1).damageDealt).toBe(250)
		expect(statsOf(result, 11).damageDealt).toBe(300)
		expect(statsOf(result, 2).assistSpotting).toBe(250)
		local _, p1 = statsOf(result, 1)
		expect(p1.controlShare).toBe(1)
		expect(result.botShare).toBeCloseTo(0.5, 1e-12)

		-- The stream starts with Started, ends with Ended, and is ordered by t.
		expect(stream[1].type).toBe("Started")
		expect(stream[#stream].type).toBe("Ended")
		for i = 2, #stream do
			expect(stream[i].t >= stream[i - 1].t).toBe(true)
		end
		expect(#Fixtures.ofType(stream, "BaseCaptured")).toBe(1)
		expect(#Fixtures.ofType(stream, "CaptureReset")).toBe(1)
	end)

	it("is deterministic: identical runs give identical results and streams", function()
		local a, sa = simulate(1 / 30)
		local b, sb = simulate(1 / 30)
		expect(a).toEqual(b)
		expect(sa).toEqual(sb)
	end)

	it("a disconnect hands the vehicle to a bot after 5 s and the ledger keeps the human share", function()
		local result, stream = simulate(1 / 30, { disconnect = true })
		local changes = Fixtures.ofType(stream, "ControlChanged")
		expect(#changes).toBe(1)
		expect(changes[1].participant).toBe(1)
		expect(changes[1].controller).toBe("Bot")
		expect(math.abs(changes[1].t - 15)).toBeLessThan(1 / 30 + 1e-9)
		local _, p1 = statsOf(result, 1)
		expect(p1.controlShare).toBeCloseTo(15 / result.durationS, 0.002)
		expect(statsOf(result, 1).damageDealt).toBe(250)
	end)
end)
