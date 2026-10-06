local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local CrewEffects = require("@game/ReplicatedStorage/Shared/Combat/CrewEffects")

local function member(slot: number, role: string, also: { string }?, level: number?, injured: boolean?): any
	return {
		slot = slot,
		role = role,
		also = also or {},
		level = level or 100,
		hp = 100,
		maxHp = 100,
		injured = injured == true,
	}
end

describe("CrewEffects", function()
	it("reload curve: 0.875 / (0.00375 L + 0.5) (01-S17 goldens)", function()
		expect(CrewEffects.reloadFactor(100)).toBeCloseTo(1.000, 1e-12)
		expect(CrewEffects.reloadFactor(110)).toBeCloseTo(0.959, 1e-3)
		expect(CrewEffects.reloadFactor(50)).toBeCloseTo(1.273, 1e-3)
		expect(CrewEffects.reloadFactor(0)).toBeCloseTo(1.75, 1e-12)
		expect(CrewEffects.reloadFactor(-1000)).toBe(875) -- clamped denominator
		-- worked example: 30 s × curve(103.67) = 29.54 s
		expect(30 * CrewEffects.reloadFactor(103.67)).toBeCloseTo(29.54, 0.01)
	end)

	it("stat curve f(L) = 0.57 + 0.0043 L", function()
		expect(CrewEffects.statFactor(100)).toBeCloseTo(1, 1e-12)
		expect(CrewEffects.statFactor(50)).toBeCloseTo(0.785, 1e-12)
		expect(CrewEffects.statFactor(-1000)).toBe(1e-3)
	end)

	it("ratio applies the curve kind relative to the base level", function()
		expect(CrewEffects.ratio("reload", 100, 50)).toBeCloseTo(1.2727, 1e-4)
		expect(CrewEffects.ratio("mul", 100, 50)).toBeCloseTo(0.785, 1e-12)
		expect(CrewEffects.ratio("div", 100, 50)).toBeCloseTo(1 / 0.785, 1e-12)
		expect(CrewEffects.ratio("mul", 110, 110)).toBe(1)
	end)

	it("duty levels average every member holding the duty (loaders averaged, doubled duties)", function()
		local crew = {
			member(1, "Commander", { "Loader" }),
			member(2, "Gunner"),
			member(3, "Driver"),
			member(4, "Loader", nil, 100, true),
		}
		expect(CrewEffects.dutyLevel(crew, "Loader")).toBe(75) -- (100 + 50) / 2
		expect(CrewEffects.dutyLevel(crew, "Loader", true)).toBe(100)
		expect(CrewEffects.dutyLevel({ member(1, "Gunner") }, "Driver")).toBeNil()
	end)

	it("an injured commander costs the others 10 levels and turns Sixth Sense off", function()
		local crew = {
			member(1, "Commander", nil, 100, true),
			member(2, "Gunner"),
			member(3, "Driver"),
			member(4, "Loader"),
		}
		expect(CrewEffects.commanderInjured(crew)).toBe(true)
		expect(CrewEffects.memberLevel(crew[2], true)).toBe(90)
		expect(CrewEffects.memberLevel(crew[1], true)).toBe(50)
		local m = CrewEffects.multipliers(crew, { Commander = 100, Gunner = 100, Driver = 100, Loader = 100 })
		expect(m.sixthSense).toBe(false)
		expect(m.viewRange).toBeCloseTo(0.785, 1e-12)
		expect(m.reloadTime).toBeCloseTo(CrewEffects.reloadFactor(90), 1e-12)
		expect(m.turretTraverse).toBeCloseTo(CrewEffects.statFactor(90), 1e-12)
		expect(m.aimTime).toBeCloseTo(1 / CrewEffects.statFactor(90), 1e-12)
		expect(m.repairTime).toBeCloseTo(1 / CrewEffects.statFactor(90), 1e-12)
	end)

	it("uses the levels VehicleStats was resolved with (ventilation etc.) as the base", function()
		local crew = { member(1, "Loader", nil, 110, true) }
		local m = CrewEffects.multipliers(crew, { Loader = 110 })
		expect(m.reloadTime).toBeCloseTo(CrewEffects.reloadFactor(50) / CrewEffects.reloadFactor(110), 1e-12)
		-- healthy crew: all ones; out table reused
		local healthy = { member(1, "Commander"), member(2, "Gunner") }
		local out = CrewEffects.multipliers(healthy, nil)
		expect(CrewEffects.multipliers(healthy, nil, out)).toBe(out)
		for _, stat in CrewEffects.STATS do
			expect((out :: any)[stat]).toBe(1)
		end
		expect(out.sixthSense).toBe(true)
	end)

	it("exports a frozen injury-effects table covering every stat", function()
		expect(table.isfrozen(CrewEffects.INJURY_EFFECTS)).toBe(true)
		for _, stat in CrewEffects.STATS do
			local e = CrewEffects.INJURY_EFFECTS[stat]
			expect(e ~= nil).toBe(true)
			expect(table.find({ "Commander", "Gunner", "Driver", "Loader" }, e.duty) ~= nil).toBe(true)
		end
	end)
end)
