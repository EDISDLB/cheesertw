-- Mechanics/ActiveCooling: 5 s window, 45 s cooldown, reload/aim ×0.85 (00-DECISIONS §4; roster §2.7), the reload
-- factor GunState integrates and the runtime list without reloadTime (no double counting).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ActiveCooling = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/ActiveCooling")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local SPEC: any = {
	kind = "ActiveCooling",
	durationS = 5,
	cooldownS = 45,
	modifiers = {
		{ stat = "reloadTime", op = "mul", value = 0.85 },
		{ stat = "aimTime", op = "mul", value = 0.85 },
	},
}

describe("Mechanics/ActiveCooling", function()
	it("factors and the runtime list are resolved once", function()
		local s = ActiveCooling.new(SPEC, 0)
		expect(s.reloadFactor).toBeCloseTo(0.85, 1e-12)
		expect(s.aimFactor).toBeCloseTo(0.85, 1e-12)
		expect(#s.runtime).toBe(1)
		expect(s.runtime[1].stat).toBe("aimTime")
		local floor = ActiveCooling.new(
			{
				kind = "ActiveCooling",
				durationS = 5,
				cooldownS = 45,
				modifiers = { { stat = "reloadTime", op = "mul", value = 0 } },
			} :: any,
			0
		)
		expect(floor.reloadFactor).toBe(0.05) -- a reload can never freeze
		local added = ActiveCooling.new(
			{
				kind = "ActiveCooling",
				durationS = 5,
				cooldownS = 45,
				modifiers = { { stat = "reloadTime", op = "add", value = -0.1 } },
			} :: any,
			0
		)
		expect(added.reloadFactor).toBeCloseTo(0.9, 1e-12)
	end)

	it("lifecycle: window, cooldown, rejection reasons, death", function()
		local s = ActiveCooling.new(SPEC, 0)
		local ctx = Common.newContext()
		expect(ActiveCooling.currentReloadFactor(s)).toBe(1)
		expect(ActiveCooling.runtimeModifiers(s)).toBeNil()
		expect((ActiveCooling.activate(s, 10, ctx))).toBe(true)
		expect(ActiveCooling.currentReloadFactor(s)).toBeCloseTo(0.85, 1e-12)
		expect(ActiveCooling.modifiers(s)).toBe(SPEC.modifiers)
		expect(ActiveCooling.runtimeModifiers(s)).toBe(s.runtime)
		expect(select(2, ActiveCooling.activate(s, 12, ctx))).toBe("ACTIVE")
		ActiveCooling.update(s, 15, ctx)
		expect(s.phase).toBe("Cooldown")
		expect(select(2, ActiveCooling.activate(s, 59.99, ctx))).toBe("COOLDOWN")
		ActiveCooling.update(s, 60, ctx)
		expect(s.phase).toBe("Off")
		ActiveCooling.activate(s, 60, ctx)
		ctx.alive = false
		ActiveCooling.update(s, 61, ctx)
		expect(s.phase).toBe("Cooldown")
		expect(select(2, ActiveCooling.activate(s, 200, ctx))).toBe("DEAD")
		local early = ActiveCooling.new(SPEC, 0)
		ActiveCooling.activate(early, 0)
		expect((ActiveCooling.deactivate(early, 2))).toBe(true)
		expect(ActiveCooling.nextChange(early)).toBe(47)
		expect(select(2, ActiveCooling.deactivate(early, 3))).toBe("NOT_ACTIVE")
	end)

	it("snapshot: duration ring then cooldown sweep", function()
		local s = ActiveCooling.new(SPEC, 0)
		ActiveCooling.activate(s, 0)
		local snap = ActiveCooling.snapshot(s, 1)
		expect(snap.progress).toBeCloseTo(0.2, 1e-12)
		expect(snap.cooldownRemainingS).toBe(49)
		expect(snap.active).toBe(true)
		ActiveCooling.update(s, 20)
		ActiveCooling.snapshot(s, 20, snap)
		expect(snap.cooldownRemainingS).toBe(30)
		expect(snap.active).toBe(false)
	end)
end)
