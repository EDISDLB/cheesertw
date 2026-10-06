-- Mechanics/Hydropneumatic: +4° depression / +3° elevation after 0.75 s still and grounded (00-DECISIONS §4), with
-- the settle point exact (stop time + settleS), moving / airborne / dead → off, nothing to activate.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Hydropneumatic = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Hydropneumatic")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local SPEC: any = { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 }

describe("Mechanics/Hydropneumatic", function()
	it("settles exactly settleS after the hull stopped, whatever the update times", function()
		local s = Hydropneumatic.new(SPEC, 0)
		local ctx = Common.newContext()
		ctx.stationaryForS = 0
		Hydropneumatic.update(s, 10, ctx)
		expect(s.phase).toBe("Off")
		ctx.stationaryForS = 0.5 -- stopped at 10.0
		Hydropneumatic.update(s, 10.5, ctx)
		expect(s.phase).toBe("Engaging")
		expect(s.phaseEnd).toBeCloseTo(10.75, 1e-12)
		expect(Hydropneumatic.bonusDeg(s)).toBe(0)
		ctx.stationaryForS = 2.0
		expect(Hydropneumatic.update(s, 12, ctx)).toBe(true)
		expect(s.phase).toBe("On")
		expect(s.phaseStart).toBeCloseTo(10.75, 1e-12) -- the exact settle instant, not the update time
		local dep, elev = Hydropneumatic.bonusDeg(s)
		expect(dep).toBe(4)
		expect(elev).toBe(3)
		local mods = Hydropneumatic.modifiers(s) :: any
		expect(mods[1]).toEqual({ stat = "gunDepression", op = "add", value = 4 })
		expect(mods[2]).toEqual({ stat = "gunElevation", op = "add", value = 3 })
	end)

	it("moving, airborne or dead drops the bonus at once", function()
		for _, patch in { { stationaryForS = 0 }, { grounded = false }, { alive = false } } do
			local s = Hydropneumatic.new(SPEC, 0)
			local ctx: any = Common.newContext()
			ctx.stationaryForS = 5
			Hydropneumatic.update(s, 5, ctx)
			expect(Hydropneumatic.isActive(s)).toBe(true)
			for k, v in patch do
				ctx[k] = v
			end
			Hydropneumatic.update(s, 5.1, ctx)
			expect(s.phase).toBe("Off")
			expect(Hydropneumatic.modifiers(s)).toBeNil()
		end
	end)

	it("without a context a pending settle still completes; it is passive", function()
		local s = Hydropneumatic.new(SPEC, 0)
		local ctx = Common.newContext()
		ctx.stationaryForS = 0.25
		Hydropneumatic.update(s, 1, ctx)
		expect(Hydropneumatic.nextChange(s)).toBeCloseTo(1.5, 1e-12)
		Hydropneumatic.update(s, 1.5)
		expect(s.phase).toBe("On")
		expect(select(2, Hydropneumatic.activate(s, 2))).toBe("PASSIVE")
		expect(select(2, Hydropneumatic.deactivate(s, 2))).toBe("PASSIVE")
		local snap = Hydropneumatic.snapshot(s, 2)
		expect(snap.active).toBe(true)
		expect(snap.kind).toBe("Hydropneumatic")
	end)

	it("bad numbers: negative bonuses count as 0, settleS defaults to 0.75", function()
		local s = Hydropneumatic.new(
			{ kind = "Hydropneumatic", depressionBonusDeg = -4, elevationBonusDeg = 0 / 0, settleS = -1 } :: any,
			0
		)
		expect(s.depressionBonusDeg).toBe(0)
		expect(s.elevationBonusDeg).toBe(0)
		expect(s.settleS).toBe(0.75)
	end)
end)
