-- Mechanics/Turbo: the active Turbo signature (00-DECISIONS §4: power ×1.25 for 6 s, 40 s cooldown; roster §2.7:
-- a destroyed engine or track cancels the boost and blocks activations).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Turbo = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Turbo")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local SPEC: any = { kind = "Turbo", powerMul = 1.25, durationS = 6, cooldownS = 40 }

describe("Mechanics/Turbo", function()
	it("Off → On (6 s, power ×1.25) → Cooldown (40 s) → Off with rejection reasons", function()
		local s = Turbo.new(SPEC, 0)
		local ctx = Common.newContext()
		expect(Turbo.modifiers(s)).toBeNil()
		expect(select(2, Turbo.deactivate(s, 0))).toBe("NOT_ACTIVE")
		expect((Turbo.activate(s, 10, ctx))).toBe(true)
		expect(Turbo.isActive(s)).toBe(true)
		local mods = Turbo.modifiers(s) :: any
		expect(mods[1]).toEqual({ stat = "enginePower", op = "mul", value = 1.25 })
		expect(select(2, Turbo.activate(s, 12, ctx))).toBe("ACTIVE")
		Turbo.update(s, 15.999, ctx)
		expect(s.phase).toBe("On")
		Turbo.update(s, 16, ctx)
		expect(s.phase).toBe("Cooldown")
		expect(Turbo.modifiers(s)).toBeNil()
		expect(select(2, Turbo.activate(s, 55.9, ctx))).toBe("COOLDOWN")
		expect((Turbo.activate(s, 56, ctx))).toBe(true)
	end)

	it(
		"an immobilised or destroyed vehicle cancels the boost (cooldown from that instant) and cannot start one",
		function()
			local s = Turbo.new(SPEC, 0)
			local ctx = Common.newContext()
			Turbo.activate(s, 0, ctx)
			ctx.mobile = false
			expect(Turbo.update(s, 2, ctx)).toBe(true)
			expect(s.phase).toBe("Cooldown")
			expect(s.phaseEnd).toBe(42)
			Turbo.update(s, 50, ctx)
			expect(select(2, Turbo.activate(s, 50, ctx))).toBe("IMMOBILE")
			ctx.mobile = true
			ctx.alive = false
			expect(select(2, Turbo.activate(s, 50, ctx))).toBe("DEAD")
		end
	)

	it("an early deactivate starts the cooldown; bad numbers mean no boost", function()
		local s = Turbo.new(SPEC, 0)
		Turbo.activate(s, 0)
		expect((Turbo.deactivate(s, 1))).toBe(true)
		expect(s.phaseEnd).toBe(41)
		local bad = Turbo.new({ kind = "Turbo", powerMul = 0 / 0, durationS = -3, cooldownS = math.huge } :: any, 0)
		expect(bad.powerMul).toBe(1)
		expect(bad.durationS).toBe(0)
		expect(bad.cooldownS).toBe(0)
	end)

	it("snapshot: duration ring then cooldown sweep", function()
		local s = Turbo.new(SPEC, 0)
		Turbo.activate(s, 0)
		local snap = Turbo.snapshot(s, 3)
		expect(snap.progress).toBe(0.5)
		expect(snap.remainingS).toBe(3)
		expect(snap.cooldownRemainingS).toBe(43)
		Turbo.update(s, 26)
		Turbo.snapshot(s, 26, snap)
		expect(snap.phase).toBe("Cooldown")
		expect(snap.cooldownRemainingS).toBe(20)
		expect(Turbo.nextChange(s)).toBe(46)
	end)
end)
