-- Mechanics/Common: eligibility (00-DECISIONS §4: Tier XI signatures only on Apex/Event vehicles, Tier I–X
-- mechanics never on an Apex), keyed set, numeric guards, exact-time helpers and the timed machine shared by Turbo
-- and ActiveCooling.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local function timed(durationS: number, cooldownS: number): any
	return {
		phase = "Off",
		phaseStart = 0,
		phaseEnd = math.huge,
		time = 0,
		durationS = durationS,
		cooldownS = cooldownS,
	}
end

describe("Mechanics/Common", function()
	it("table: which mechanics may sit on which vehicles", function()
		local rows = {
			{ "SiegeMode", 9, "TechTree", true },
			{ "SiegeMode", 11, "TechTree", false },
			{ "Hydropneumatic", 10, "Premium", true },
			{ "Wheeled", 11, "Event", false },
			{ "Turbo", 11, "TechTree", true },
			{ "Turbo", 10, "TechTree", false },
			{ "RocketBoost", 5, "Event", true },
			{ "ChargedShot", 11, "TechTree", true },
			{ "ActiveCooling", 8, "Premium", false },
			{ "AdaptiveMagazine", 11, "TechTree", true },
			{ "ReserveTracks", 3, "Reward", false },
		}
		for _, row in rows do
			if Common.allowedOn(row[1], row[2], row[3]) ~= row[4] then
				error(`{row[1]} tier {row[2]} {row[3]}: expected {tostring(row[4])}`)
			end
		end
		expect(Common.isExotic("Turbo")).toBe(true)
		expect(Common.isExotic("SiegeMode")).toBe(false)
		expect(Common.KEYED.SiegeMode).toBe(true)
		expect(Common.KEYED.Hydropneumatic).toBeNil()
		expect(Common.KEYED.ChargedShot).toBeNil() -- rides the fire trigger
	end)

	it("numeric guards never let NaN / inf / negatives into a machine", function()
		expect(Common.nonNegative(2, 9)).toBe(2)
		expect(Common.nonNegative(0, 9)).toBe(0)
		expect(Common.nonNegative(-1, 9)).toBe(9)
		expect(Common.nonNegative(0 / 0, 9)).toBe(9)
		expect(Common.nonNegative(math.huge, 9)).toBe(9)
		expect(Common.nonNegative("3", 9)).toBe(9)
		expect(Common.positive(0, 4)).toBe(4)
		expect(Common.positive(0.5, 4)).toBe(0.5)
		expect(Common.time(3, 1)).toBe(3)
		expect(Common.time(-math.huge, 1)).toBe(1)
		expect(Common.time(nil, 1)).toBe(1)
	end)

	it("progress and reached work on exact absolute times", function()
		expect(Common.progress(2, 4, 3)).toBe(0.5)
		expect(Common.progress(2, 4, 10)).toBe(1)
		expect(Common.progress(2, 4, 0)).toBe(0)
		expect(Common.progress(2, 2, 0)).toBe(1) -- zero-length phase
		expect(Common.reached(4, 4)).toBe(true)
		expect(Common.reached(4 - 1e-8, 4)).toBe(true) -- within EPS
		expect(Common.reached(3.999, 4)).toBe(false)
	end)

	it("timed machine: passes several phase ends in one update at their exact times", function()
		local s = timed(6, 40)
		Common.timedUpdate(s, 10)
		Common.timedStart(s)
		expect(s.phase).toBe("On")
		expect(s.phaseEnd).toBe(16)
		expect(Common.timedUpdate(s, 15.9)).toBe(false)
		expect(Common.timedUpdate(s, 100)).toBe(true) -- On → Cooldown (16) → Off (56)
		expect(s.phase).toBe("Off")
		expect(s.phaseStart).toBe(56)
		expect(s.phaseEnd).toBe(math.huge)
		expect(Common.timedUpdate(s, 50)).toBe(false) -- never backwards
		expect(s.time).toBe(100)
		Common.timedStart(s)
		Common.timedUpdate(s, 102)
		Common.timedCancel(s) -- cooldown from the cancel instant
		expect(s.phase).toBe("Cooldown")
		expect(s.phaseEnd).toBe(142)
		Common.timedCancel(s) -- no-op outside On
		expect(s.phaseEnd).toBe(142)
	end)

	it("fill writes a snapshot in place", function()
		local out = Common.newSnapshot()
		local same = Common.fill(out, "Turbo", "On", true, 10, 16, true, 13, math.huge, math.huge, 43)
		expect(same).toBe(out)
		expect(out.progress).toBe(0.5)
		expect(out.remainingS).toBe(3)
		expect(out.cooldownRemainingS).toBe(43)
		Common.fill(out, "SiegeMode", "On", true, 10, math.huge, false, 13, 2, 2, -5)
		expect(out.progress).toBe(1)
		expect(out.remainingS).toBe(0)
		expect(out.cooldownRemainingS).toBe(0)
		expect(out.charges).toBe(2)
	end)
end)
