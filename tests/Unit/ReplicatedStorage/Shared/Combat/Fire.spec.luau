local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Fire = require("@game/ReplicatedStorage/Shared/Combat/Fire")

describe("Fire", function()
	it("ignites once (the first igniter keeps the credit) and extinguishes", function()
		local f = Fire.newState()
		expect(Fire.ignite(f, 8, 3)).toBe(true)
		expect(Fire.ignite(f, 8, 4)).toBe(false)
		expect(f.igniter).toBe(3)
		expect(f.remainingS).toBe(8)
		expect(Fire.extinguish(f)).toBe(true)
		expect(Fire.extinguish(f)).toBe(false)
		expect(f.burning).toBe(false)
		expect(Fire.ignite(f, 0 / 0, 5)).toBe(true)
		expect(f.remainingS).toBe(8) -- config default
	end)

	it("ticks whole HP every FIRE_TICK_S with a fractional carry; a full burn = 20 % of max HP", function()
		local f = Fire.newState()
		Fire.ignite(f, 8, 1)
		local total, ticks = 0, 0
		local out = false
		for _ = 1, 30 * 9 do
			local hp, n, burnedOut = Fire.tick(f, 1 / 30, 1000)
			total += hp
			ticks += n
			out = out or burnedOut
		end
		expect(total).toBe(200)
		expect(ticks).toBe(8)
		expect(out).toBe(true)
		-- 2.5 % of 999 = 24.975 per tick: carried, floor of the running total
		local g = Fire.newState()
		Fire.ignite(g, 8, 1)
		local sum = 0
		for _ = 1, 8 do
			sum += Fire.tick(g, 1, 999)
		end
		expect(sum).toBe(199)
		-- partial last tick (6.5 s): 6 × 25 + 0.5 × 25
		local h = Fire.newState()
		Fire.ignite(h, 6.5, 1)
		local partial = 0
		for _ = 1, 10 do
			partial += Fire.tick(h, 1, 1000)
		end
		expect(partial).toBe(162)
	end)

	it("ignores bad dt and non-burning states", function()
		local f = Fire.newState()
		expect(Fire.tick(f, 1, 1000)).toBe(0)
		Fire.ignite(f, 8, 1)
		expect(Fire.tick(f, 0 / 0, 1000)).toBe(0)
		expect(Fire.tick(f, -1, 1000)).toBe(0)
		expect(Fire.tick(f, math.huge, 1000)).toBe(0)
		expect(f.burning).toBe(true)
	end)

	it("engine-hit chance × 1.5 with a damaged or destroyed fuel tank, clamped to [0, 1]", function()
		expect(Fire.engineHitChance(0.2, "Ok")).toBeCloseTo(0.2, 1e-12)
		expect(Fire.engineHitChance(0.2, "Damaged")).toBeCloseTo(0.3, 1e-12)
		expect(Fire.engineHitChance(0.2, "Destroyed")).toBeCloseTo(0.3, 1e-12)
		expect(Fire.engineHitChance(0.9, "Damaged")).toBe(1)
		expect(Fire.engineHitChance(0 / 0, nil)).toBe(0)
		expect(Fire.engineHitChance(-1, nil)).toBe(0)
	end)
end)
