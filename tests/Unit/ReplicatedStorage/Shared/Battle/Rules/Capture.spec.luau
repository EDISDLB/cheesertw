local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Units = require("@game/ReplicatedStorage/Shared/Core/Units")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local ModeRules = require("@game/ReplicatedStorage/Shared/Battle/Rules/ModeRules")
local Capture = require("@game/ReplicatedStorage/Shared/Battle/Rules/Capture")
local Fixtures = require("../Ledger/BattleFixtures")

local DT = 1 / 30

-- Bases (metres). Standard: team 1 owns "base1" at (0,0), team 2 owns "base2" at (500, 0). Encounter: neutral at
-- (250, 250). Assault: team 2 defends "def" at (0, 0).
local BASES = {
	{ id = "base1", battleType = "Standard", team = 1, center = { x = 0, z = 0 } },
	{ id = "base2", battleType = "Standard", team = 2, center = { x = 500, z = 0 } },
	{ id = "mid", battleType = "Encounter", center = { x = 250, z = 250 }, radiusM = 50 },
	{ id = "def", battleType = "Assault", team = 2, center = { x = 0, z = 0 }, radiusM = 40 },
}

local ROSTER = {
	{ participantId = 1, team = 1 },
	{ participantId = 2, team = 1 },
	{ participantId = 3, team = 1 },
	{ participantId = 4, team = 1 },
	{ participantId = 5, team = 1 },
	{ participantId = 11, team = 2 },
	{ participantId = 12, team = 2 },
	{ participantId = 13, team = 2 },
}

local function at(xm: number, zm: number, ym: number?): Vector3
	return Vector3.new(Units.mToStuds(xm), Units.mToStuds(ym or 0), Units.mToStuds(zm))
end

local function vehicle(id: number, team: number, xm: number, zm: number, extra: { [string]: any }?)
	local v = { id = id, team = team, position = at(xm, zm), alive = true, canCapture = true, rateMul = nil }
	if extra then
		for k, val in extra do
			v[k] = val
		end
	end
	return v
end

local function new(battleType: string, settings: any?)
	return Capture.new(settings or ModeRules.defaults("Random", battleType), BASES, ROSTER)
end

-- Steps until a capture completes (or `maxS`), returns (battle time of completion or nil, teams).
local function runUntilCaptured(state, vehicles, maxS: number, events)
	local t = 0
	local steps = math.floor(maxS / DT + 0.5)
	for _ = 1, steps do
		t += DT
		local done = Capture.step(state, vehicles, DT, t, events)
		if #done > 0 then
			return t, table.clone(done)
		end
	end
	return nil, {}
end

describe("Capture zones (00-DECISIONS §9, report 04 R7)", function()
	it("REG-MAP-04: r − 0.1 m counts, r + 0.1 m does not (planar distance, height ignored)", function()
		local state = new("Standard")
		local base = state.bases[1]
		expect(base.id).toBe("base1")
		expect(base.radiusStuds).toBe(150)
		expect(Capture.isInside(base, at(49.9, 0, 30))).toBe(true)
		expect(Capture.isInside(base, at(50.1, 0))).toBe(false)
		expect(Capture.isInside(base, at(35.3, 35.3))).toBe(true)
		expect(Capture.isInside(base, at(35.4, 35.4))).toBe(false)
		local assault = new("Assault")
		expect(assault.bases[1].radiusStuds).toBe(120)
	end)

	it("Standard: 100 s alone, 50 s with two, 33.3 s with three, still 33.3 s with five (max counted 3)", function()
		local cases = { { n = 1, s = 100 }, { n = 2, s = 50 }, { n = 3, s = 100 / 3 }, { n = 5, s = 100 / 3 } }
		for _, case in cases do
			local state = new("Standard")
			local vehicles = {}
			for i = 1, case.n do
				table.insert(vehicles, vehicle(i, 1, 500 + i, 0))
			end
			local t, teams = runUntilCaptured(state, vehicles, 200)
			expect(teams).toEqual({ 1 })
			expect(math.abs((t :: number) - case.s)).toBeLessThan(DT + 1e-9)
			-- Every capper earned an equal share; the total is exactly 100.
			local points = Capture.participantPoints(state)
			local sum = 0
			for i = 1, case.n do
				expect(points[i]).toBeCloseTo(100 / case.n, 1e-6)
				sum += points[i]
			end
			expect(sum).toBeCloseTo(100, 1e-9)
			expect(Capture.progress(state, "base2", 1)).toBe(100)
		end
	end)

	it("Encounter: half rate (200 s alone, 66.7 s with three) and frozen while contested", function()
		local state = new("Encounter")
		expect(#state.bases).toBe(1)
		local t = runUntilCaptured(state, { vehicle(1, 1, 250, 250) }, 300)
		expect(math.abs((t :: number) - 200)).toBeLessThan(DT + 1e-9)

		local three = new("Encounter")
		local t3 =
			runUntilCaptured(three, { vehicle(1, 1, 250, 250), vehicle(2, 1, 251, 250), vehicle(3, 1, 249, 250) }, 300)
		expect(math.abs((t3 :: number) - 200 / 3)).toBeLessThan(DT + 1e-9)

		local contested = new("Encounter")
		local cappers = { vehicle(1, 1, 250, 250) }
		for i = 1, 300 do
			Capture.step(contested, cappers, DT, i * DT)
		end
		expect(Capture.progress(contested, "mid", 1)).toBeCloseTo(5, 1e-6)
		local withEnemy = { cappers[1], vehicle(11, 2, 260, 250) }
		for i = 1, 300 do
			Capture.step(contested, withEnemy, DT, 10 + i * DT)
		end
		expect(Capture.progress(contested, "mid", 1)).toBeCloseTo(5, 1e-6)
		expect(Capture.progress(contested, "mid", 2)).toBe(0)
		expect(Capture.isFrozen(contested, "mid", 1)).toBe(true)
		expect(Capture.isFrozen(contested, "mid", 2)).toBe(true)
		-- A dead enemy does not contest.
		withEnemy[2] = vehicle(11, 2, 260, 250, { alive = false })
		Capture.step(contested, withEnemy, DT, 30)
		expect(Capture.isFrozen(contested, "mid", 1)).toBe(false)
		expect(Capture.progress(contested, "mid", 1)).toBeCloseTo(5 + 0.5 * DT, 1e-6)
	end)

	it("Standard: defenders inside do not stop the capture", function()
		local state = new("Standard")
		local vehicles = { vehicle(1, 1, 500, 0), vehicle(11, 2, 505, 0), vehicle(12, 2, 495, 5) }
		for i = 1, 300 do
			Capture.step(state, vehicles, DT, i * DT)
		end
		expect(Capture.progress(state, "base2", 1)).toBeCloseTo(10, 1e-6)
		expect(Capture.isFrozen(state, "base2", 1)).toBe(false)
	end)

	it("Assault: only attackers capture the defender's base", function()
		local state = new("Assault")
		expect(Capture.defenderTeam(state)).toBe(2)
		expect(#state.bases[1].tracks).toBe(1)
		expect(state.bases[1].tracks[1].team).toBe(1)
		local vehicles = { vehicle(11, 2, 0, 0), vehicle(12, 2, 1, 1) }
		for i = 1, 300 do
			Capture.step(state, vehicles, DT, i * DT)
		end
		expect(Capture.progress(state, "def", 2)).toBe(0)
		expect(Capture.defenderTeam(new("Standard"))).toBeNil()
	end)

	it("REG-BTL-01: enemy HP damage resets that capper; the attacker earns defense points", function()
		local state = new("Standard")
		local events = {}
		local vehicles = { vehicle(1, 1, 500, 0), vehicle(2, 1, 501, 0) }
		for i = 1, 1200 do -- 40 s: 2 cappers × 20 points each
			Capture.step(state, vehicles, DT, i * DT, events)
		end
		expect(Capture.progress(state, "base2", 1)).toBeCloseTo(80, 1e-6)
		table.clear(events)
		local removed = Capture.onDamage(state, 1, 11, "Hp", 40, events)
		expect(removed).toBeCloseTo(40, 1e-6)
		expect(Capture.progress(state, "base2", 1)).toBeCloseTo(40, 1e-6)
		expect(Capture.capperPoints(state, "base2", 1)).toBe(0)
		expect(Capture.defensePoints(state)).toEqual({ [11] = removed })
		local resets = Fixtures.ofType(events, "CaptureReset")
		expect(#resets).toBe(1)
		expect(resets[1]).toEqual({ type = "CaptureReset", t = 40, base = "base2", by = 11, capper = 1, points = 40 })
		local progress = Fixtures.ofType(events, "CaptureProgress")
		expect(progress[#progress].points).toBe(40)
		-- The reset capper keeps capping from 0.
		Capture.step(state, vehicles, DT, 40 + DT, events)
		expect(Capture.capperPoints(state, "base2", 1)).toBeCloseTo(DT, 1e-9)
	end)

	it("allies, self, environment and stun never reset; crits reset unless configured off", function()
		local state = new("Standard")
		local vehicles = { vehicle(1, 1, 500, 0) }
		for i = 1, 300 do
			Capture.step(state, vehicles, DT, i * DT)
		end
		local before = Capture.progress(state, "base2", 1)
		expect(Capture.onDamage(state, 1, 2, "Hp", 10)).toBe(0)
		expect(Capture.onDamage(state, 1, 1, "Hp", 10)).toBe(0)
		expect(Capture.onDamage(state, 1, nil, "Hp", 10)).toBe(0)
		expect(Capture.onDamage(state, 1, 11, "Stun", 10)).toBe(0)
		expect(Capture.onDamage(state, 1, 999, "Hp", 10)).toBe(0)
		expect(Capture.progress(state, "base2", 1)).toBe(before)
		expect(Capture.onDamage(state, 1, 11, "Crit", 10)).toBeCloseTo(before, 1e-9)

		local noCrit =
			ModeRules.with(ModeRules.defaults("Random", "Standard"), { capture = { resetOnModuleCrit = false } })
		local other = Capture.new(noCrit, BASES, ROSTER)
		for i = 1, 300 do
			Capture.step(other, vehicles, DT, i * DT)
		end
		expect(Capture.onDamage(other, 1, 11, "Crit", 10)).toBe(0)
		local stunResets = ModeRules.with(noCrit, { capture = { resetOnStun = true } })
		local third = Capture.new(stunResets, BASES, ROSTER)
		for i = 1, 300 do
			Capture.step(third, vehicles, DT, i * DT)
		end
		expect(Capture.onDamage(third, 1, 11, "Stun", 10)).toBeGreaterThan(0)
	end)

	it("applyDamageEvent classifies HP damage, module/crew crits and harmless hits", function()
		local function capped()
			local state = new("Standard")
			for i = 1, 300 do
				Capture.step(state, { vehicle(1, 1, 500, 0) }, DT, i * DT)
			end
			return state
		end
		expect(Capture.applyDamageEvent(capped(), Fixtures.damage({ attacker = 11, target = 1, damage = 120 }))).toBeGreaterThan(
			0
		)
		local nonPen =
			Fixtures.damage({ attacker = 11, target = 1, damage = 0, result = "NonPenetration", potentialDamage = 200 })
		expect(Capture.applyDamageEvent(capped(), nonPen)).toBe(0)
		local trackHit = Fixtures.damage({
			attacker = 11,
			target = 1,
			damage = 0,
			result = "Absorbed",
			modulesHit = { { module = "TrackLeft", damage = 90, state = "Destroyed" } },
		})
		expect(Capture.applyDamageEvent(capped(), trackHit)).toBeGreaterThan(0)
		local crew =
			Fixtures.damage({ attacker = 11, target = 1, damage = 0, crewInjured = { { slot = 1, role = "Driver" } } })
		expect(Capture.applyDamageEvent(capped(), crew)).toBeGreaterThan(0)
	end)

	it("leaving keeps points for the 1 s grace, then forfeits them (no defense credit)", function()
		local state = new("Standard")
		local events = {}
		local inside = { vehicle(1, 1, 500, 0) }
		local outside = { vehicle(1, 1, 600, 0) }
		local t = 0
		for _ = 1, 300 do
			t += DT
			Capture.step(state, inside, DT, t, events)
		end
		for _ = 1, 27 do -- 0.9 s outside
			t += DT
			Capture.step(state, outside, DT, t, events)
		end
		expect(Capture.progress(state, "base2", 1)).toBeCloseTo(10, 1e-6)
		t += DT
		Capture.step(state, inside, DT, t, events)
		expect(Capture.progress(state, "base2", 1)).toBeCloseTo(10 + DT, 1e-6)
		for _ = 1, 31 do -- 1.03 s outside
			t += DT
			Capture.step(state, outside, DT, t, events)
		end
		expect(Capture.progress(state, "base2", 1)).toBe(0)
		expect(Capture.defensePoints(state)).toEqual({})
		local progress = Fixtures.ofType(events, "CaptureProgress")
		expect(progress[#progress].points).toBe(0)
	end)

	it("overturned (canCapture = false) and dead cappers stop accruing; resetVehicle clears without credit", function()
		local state = new("Standard")
		for i = 1, 300 do
			Capture.step(state, { vehicle(1, 1, 500, 0), vehicle(2, 1, 500, 5) }, DT, i * DT)
		end
		expect(Capture.progress(state, "base2", 1)).toBeCloseTo(20, 1e-6)
		local removed = Capture.resetVehicle(state, 1, 10)
		expect(removed).toBeCloseTo(10, 1e-6)
		expect(Capture.defensePoints(state)).toEqual({})
		local p = Capture.progress(state, "base2", 1)
		Capture.step(
			state,
			{ vehicle(1, 1, 500, 0, { canCapture = false }), vehicle(2, 1, 500, 5, { alive = false }) },
			DT,
			11
		)
		expect(Capture.progress(state, "base2", 1)).toBe(p)
	end)

	it("progress events every 5 points, on every drop and at completion; BaseCaptured once", function()
		local state = new("Standard")
		local events = {}
		local t = runUntilCaptured(state, { vehicle(1, 1, 500, 0) }, 200, events)
		expect(t).never.toBeNil()
		local points = {}
		for _, e in Fixtures.ofType(events, "CaptureProgress") do
			table.insert(points, e.points)
		end
		expect(#points).toBe(20)
		expect(points[1]).toBe(5)
		expect(points[#points]).toBe(100)
		local captured = Fixtures.ofType(events, "BaseCaptured")
		expect(#captured).toBe(1)
		expect(captured[1].base).toBe("base2")
		expect(captured[1].team).toBe(1)
		-- A captured base no longer changes.
		expect(Capture.step(state, { vehicle(1, 1, 500, 0) }, DT, 200)).toEqual({})
		expect(Capture.onDamage(state, 1, 11, "Hp", 200)).toBe(0)
	end)

	it("double capture on the same step reports both teams (Outcome makes it a draw)", function()
		local state = new("Standard")
		local vehicles = { vehicle(1, 1, 500, 0), vehicle(11, 2, 0, 0) }
		local _, teams = runUntilCaptured(state, vehicles, 200)
		expect(teams).toEqual({ 1, 2 })
	end)

	it("two teams finishing one neutral base on the same step both claim it (freeze disabled)", function()
		local settings =
			ModeRules.with(ModeRules.defaults("Random", "Encounter"), { capture = { contestedFreezes = false } })
		local state = Capture.new(settings, BASES, ROSTER)
		local events = {}
		local _, teams = runUntilCaptured(state, { vehicle(1, 1, 250, 250), vehicle(11, 2, 250, 251) }, 300, events)
		expect(teams).toEqual({ 1, 2 })
		expect(#Fixtures.ofType(events, "BaseCaptured")).toBe(2)
		expect(state.bases[1].capturedBy).toBe(1)
	end)

	it("per-vehicle rate multiplier; invalid multipliers count as 0", function()
		local state = new("Standard")
		local t = runUntilCaptured(state, { vehicle(1, 1, 500, 0, { rateMul = 2 }) }, 200)
		expect(math.abs((t :: number) - 50)).toBeLessThan(DT + 1e-9)
		local broken = new("Standard")
		for i = 1, 30 do
			Capture.step(broken, { vehicle(1, 1, 500, 0, { rateMul = 0 / 0 }) }, DT, i * DT)
		end
		expect(Capture.progress(broken, "base2", 1)).toBe(0)
	end)

	it("disabled capture (Practice) and foreign battle types are inert", function()
		local practice = Capture.new(ModeRules.defaults("Practice"), BASES, ROSTER)
		expect(practice.enabled).toBe(false)
		expect(#practice.bases).toBe(0)
		expect(Capture.step(practice, { vehicle(1, 1, 500, 0) }, DT, 1)).toEqual({})
		local standard = new("Standard")
		for _, base in standard.bases do
			expect(base.id == "mid" or base.id == "def").toBe(false)
		end
		expect(Capture.step(standard, {}, 0, 1)).toEqual({})
		expect(Capture.step(standard, {}, 0 / 0, 1)).toEqual({})
	end)

	it("participantPoints = banked capture points + points still held", function()
		local state = new("Standard")
		runUntilCaptured(state, { vehicle(1, 1, 500, 0), vehicle(11, 2, 1, 0), vehicle(12, 2, 0, 1) }, 60)
		-- Team 2 (two cappers) captures base1 at 50 s; team 1 holds 50 points on base2.
		local points = Capture.participantPoints(state)
		expect(points[11]).toBeCloseTo(50, 1e-6)
		expect(points[12]).toBeCloseTo(50, 1e-6)
		expect(points[1]).toBeCloseTo(50, 1e-6)
		local rows = Capture.snapshot(state)
		expect(#rows).toBe(2)
		expect(rows[1].base).toBe("base1")
		expect(rows[1].capturedBy).toBe(2)
	end)

	it("vehicle order never changes the result (deterministic sums)", function()
		local function run(order: { number })
			local state = new("Standard")
			local vehicles = {}
			for _, i in order do
				table.insert(vehicles, vehicle(i, 1, 500 + i * 0.37, 0, { rateMul = 1 + i * 0.013 }))
			end
			local events = {}
			local t = runUntilCaptured(state, vehicles, 200, events)
			return { t = t, points = Capture.participantPoints(state), events = events }
		end
		expect(run({ 5, 3, 1, 4, 2 })).toEqual(run({ 1, 2, 3, 4, 5 }))
	end)

	it("property: random movement and damage keep progress in [0, 100] and equal to Σ capper points", function()
		local rng = RNG.new(20261006)
		for _ = 1, 20 do
			local bt = rng:pick({ "Standard", "Encounter", "Assault" })
			local state = new(bt)
			local ids = { 1, 2, 3, 4, 5, 11, 12, 13 }
			local vehicles = {}
			for _, id in ids do
				table.insert(vehicles, vehicle(id, if id < 10 then 1 else 2, 0, 0))
			end
			local t = 0
			for _ = 1, 900 do
				t += DT
				for _, v in vehicles do
					if rng:chance(0.05) then
						local base = rng:pick(state.bases)
						local ang = rng:range(0, 2 * math.pi)
						local r = rng:range(0, Units.studsToM(base.radiusStuds) * 1.3)
						v.position = Vector3.new(
							base.cx + Units.mToStuds(r * math.cos(ang)),
							0,
							base.cz + Units.mToStuds(r * math.sin(ang))
						)
					end
					if rng:chance(0.002) then
						v.alive = not v.alive
					end
				end
				if rng:chance(0.02) then
					Capture.onDamage(state, rng:pick(ids), rng:pick(ids), rng:pick({ "Hp", "Crit", "Stun" }), t)
				end
				Capture.step(state, vehicles, DT, t)
				for _, base in state.bases do
					for _, track in base.tracks do
						expect(track.progress == track.progress).toBe(true)
						expect(track.progress >= 0 and track.progress <= 100).toBe(true)
						local sum = 0
						for _, id in track.capperIds do
							sum += track.cappers[id].points
						end
						expect(math.abs(sum - track.progress)).toBeLessThan(1e-6)
					end
				end
			end
		end
	end)
end)
