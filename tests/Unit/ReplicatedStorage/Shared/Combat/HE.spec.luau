local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local HE = require("@game/ReplicatedStorage/Shared/Combat/HE")
local Fixtures = require("./CombatFixtures")

describe("HE", function()
	it("non-penetration damage at the impact point uses nominal T (REG-ARM-13 goldens)", function()
		-- 0.5 × 150 − 1.1 × 50 × 1 = 20
		expect(HE.nonPenDamage(150, 150, 50, 1, "HE")).toBe(20)
		-- HESH × 1.15 = 23
		expect(HE.nonPenDamage(150, 150, 50, 1, "HESH")).toBe(23)
		-- rolled alpha drives the blast: 0.5 × 180 − 55 = 35
		expect(HE.nonPenDamage(150, 180, 50, 1, "HE")).toBe(35)
		-- floor 0.05 α (of the mean): 7.5 -> 8 (halves up)
		expect(HE.nonPenDamage(150, 150, 100, 1, "HE")).toBe(8)
		expect(HE.nonPenDamage(150, 150, 100, 1, "HESH")).toBe(9) -- 8.625
		-- spall lining K 1.5: 75 − 1.1 × 40 × 1.5 = 9
		expect(HE.nonPenDamage(150, 150, 40, 1.5, "HE")).toBe(9)
	end)

	it("splash damage: max(0, 0.5 α (1 − d/R) − 1.1 T_min K)", function()
		expect(HE.splashDamage(150, 0.25, 0.75, 20, 1)).toBe(28) -- 50 − 22
		expect(HE.splashDamage(150, 0, 0.75, 20, 1)).toBe(53) -- 75 − 22
		expect(HE.splashDamage(150, 0.75, 0.75, 0, 1)).toBe(0) -- edge
		expect(HE.splashDamage(150, 1, 0.75, 0, 1)).toBe(0)
		expect(HE.splashDamage(150, 0.25, 0.75, 60, 1)).toBe(0) -- armor absorbs it all
		expect(HE.splashDamage(150, 0 / 0, 0.75, 0, 1)).toBe(0)
		expect(HE.splashDamage(150, 0.1, 0, 0, 1)).toBe(0)
	end)

	it("screen and destructible pen costs (1.13: 3 T and 1 T)", function()
		expect(HE.screenCost(20)).toBe(60)
		expect(100 - HE.screenCost(20)).toBe(40) -- official 1.13 example
		expect(HE.destructibleCost(20)).toBe(20)
	end)

	it("burst radius: explosionRadiusM, else caliber / 100; artillery 3 + 0.03 cal", function()
		expect(HE.radiusM(Fixtures.shell("HE"))).toBe(0.75)
		expect(HE.radiusM(Fixtures.shell("HE", { explosionRadiusM = 0, caliberMm = 105 }))).toBeCloseTo(1.05, 1e-12)
		expect(HE.radiusM(Fixtures.shell("HE", { explosionRadiusM = 0 / 0, caliberMm = 120 }))).toBeCloseTo(1.2, 1e-12)
		expect(HE.defaultRadiusM(152, true)).toBeCloseTo(7.56, 1e-12)
		expect(HE.defaultRadiusM(75)).toBeCloseTo(0.75, 1e-12)
	end)

	it("splash module damage falls off linearly", function()
		expect(HE.splashModuleDamage(112.5, 0, 0.75)).toBe(113)
		expect(HE.splashModuleDamage(112.5, 0.375, 0.75)).toBe(56)
		expect(HE.splashModuleDamage(112.5, 0.8, 0.75)).toBe(0)
	end)

	it("artillery stun lerps from maxS at the centre to minS at the edge", function()
		local spg = Fixtures.shell("HE", { stun = { maxS = 10, minS = 5 } })
		expect(HE.stunDuration(spg, 0, 3)).toBe(10)
		expect(HE.stunDuration(spg, 1.5, 3)).toBeCloseTo(7.5, 1e-12)
		expect(HE.stunDuration(spg, 3, 3)).toBeCloseTo(5, 1e-12)
		expect(HE.stunDuration(spg, 3.1, 3)).toBe(0)
		expect(HE.stunDuration(spg, 0, 3, 0.7)).toBeCloseTo(7, 1e-12) -- Spall Lining −30 %
		expect(HE.stunDuration(Fixtures.shell("HE"), 0, 3)).toBe(0)
	end)
end)
