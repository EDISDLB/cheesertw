local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local MathUtil = require("@game/ReplicatedStorage/Shared/Core/MathUtil")

describe("MathUtil", function()
	it("clamp / lerp / inverseLerp / remap", function()
		expect(MathUtil.clamp(5, 0, 3)).toBe(3)
		expect(MathUtil.clamp(-1, 0, 3)).toBe(0)
		expect(MathUtil.clamp(2, 0, 3)).toBe(2)
		expect(MathUtil.lerp(10, 20, 0.25)).toBe(12.5)
		expect(MathUtil.inverseLerp(10, 20, 12.5)).toBe(0.25)
		expect(MathUtil.inverseLerp(5, 5, 7)).toBe(0)
		expect(MathUtil.remap(5, 0, 10, 100, 200)).toBe(150)
		expect(MathUtil.remap(15, 0, 10, 100, 200)).toBe(250)
		expect(MathUtil.remap(15, 0, 10, 100, 200, true)).toBe(200)
	end)

	it("approach never overshoots", function()
		expect(MathUtil.approach(0, 10, 3)).toBe(3)
		expect(MathUtil.approach(9, 10, 3)).toBe(10)
		expect(MathUtil.approach(10, 0, 4)).toBe(6)
	end)

	it("wraps and diffs angles in degrees", function()
		expect(MathUtil.wrapDeg(190)).toBe(-170)
		expect(MathUtil.wrapDeg(-190)).toBe(170)
		expect(MathUtil.wrapDeg(180)).toBe(180)
		expect(MathUtil.wrapDeg(-180)).toBe(180)
		expect(MathUtil.wrapDeg(720)).toBe(0)
		expect(MathUtil.angleDiffDeg(350, 10)).toBe(20)
		expect(MathUtil.angleDiffDeg(10, 350)).toBe(-20)
		expect(MathUtil.angleDiffDeg(0, 180)).toBe(180)
	end)

	it("approachAngleDeg takes the short way round", function()
		expect(MathUtil.approachAngleDeg(170, -170, 5)).toBe(175)
		expect(MathUtil.approachAngleDeg(170, -170, 50)).toBe(-170)
		expect(MathUtil.approachAngleDeg(0, 90, 30)).toBe(30)
	end)

	it("smoothDamp converges without overshoot", function()
		local value, velocity = 0, 0
		for _ = 1, 600 do
			value, velocity = MathUtil.smoothDamp(value, 10, velocity, 0.3, 1 / 60)
			expect(value <= 10 + 1e-9).toBe(true)
		end
		expect(value).toBeCloseTo(10, 1e-3)
		local same, v = MathUtil.smoothDamp(3, 10, 1, 0.3, 0)
		expect(same).toBe(3)
		expect(v).toBe(1)
		local limited = MathUtil.smoothDamp(0, 100, 0, 1, 0.1, 5)
		expect(limited).toBeLessThan(1)
	end)

	it("rounds to steps (halves away from zero)", function()
		expect(MathUtil.round(2.5)).toBe(3)
		expect(MathUtil.round(-2.5)).toBe(-3)
		expect(MathUtil.round(7.3, 0.5)).toBe(7.5)
		expect(MathUtil.round(14, 5)).toBe(15)
		expect(MathUtil.round(3.3, 0)).toBe(3.3)
	end)

	it("expDecay is frame-rate independent", function()
		local a = 0
		for _ = 1, 10 do
			a = MathUtil.expDecay(a, 1, 2, 0.1)
		end
		local b = MathUtil.expDecay(0, 1, 2, 1)
		expect(a).toBeCloseTo(b, 1e-9)
	end)

	it("sign / isFinite", function()
		expect(MathUtil.sign(-3)).toBe(-1)
		expect(MathUtil.sign(0)).toBe(0)
		expect(MathUtil.sign(2)).toBe(1)
		expect(MathUtil.isFinite(1)).toBe(true)
		expect(MathUtil.isFinite(0 / 0)).toBe(false)
		expect(MathUtil.isFinite(math.huge)).toBe(false)
	end)
end)
