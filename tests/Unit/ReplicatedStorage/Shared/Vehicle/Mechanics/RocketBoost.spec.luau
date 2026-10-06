-- Mechanics/RocketBoost: 2 charges × 2.5 s burns, +20 km/h, each charge back 30 s after ITS burn ended (roster §2.7
-- "30 s cooldown per charge", two pips), immobile/dead ends a burn (00-DECISIONS §4 Tier XI signatures).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local RocketBoost = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/RocketBoost")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local SPEC: any = { kind = "RocketBoost", charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 }

describe("Mechanics/RocketBoost", function()
	it("table-driven charge timeline with independent recharges", function()
		local s = RocketBoost.new(SPEC, 0)
		local ctx = Common.newContext()
		-- { t, action, ok/phase, charges after, reason? }
		local steps = {
			{ 0, "activate", true, 1 },
			{ 1, "activate", false, 1, "ACTIVE" },
			{ 2.5, "phase", "Off", 1 }, -- burn 1 ends: charge 1 back at 32.5
			{ 3, "activate", true, 0 },
			{ 5.5, "phase", "Cooldown", 0 }, -- no charge left: charge 2 back at 35.5
			{ 10, "activate", false, 0, "NO_CHARGES" },
			{ 32.499, "phase", "Cooldown", 0 },
			{ 32.5, "phase", "Off", 1 },
			{ 35.5, "phase", "Off", 2 },
			{ 40, "activate", true, 1 },
		}
		for i, step in steps do
			local t, action = step[1], step[2]
			if action == "phase" then
				RocketBoost.update(s, t, ctx)
				if s.phase ~= step[3] then
					error(`step {i} @ {t}: phase {s.phase}, expected {step[3]}`)
				end
			else
				local ok, reason = RocketBoost.activate(s, t, ctx)
				if ok ~= step[3] or reason ~= step[5] then
					error(`step {i} @ {t}: {tostring(ok)} {tostring(reason)}`)
				end
			end
			if s.charges ~= step[4] then
				error(`step {i} @ {t}: {s.charges} charges, expected {step[4]}`)
			end
		end
	end)

	it("topSpeed + speedBonusKmh only while burning", function()
		local s = RocketBoost.new(SPEC, 0)
		expect(RocketBoost.modifiers(s)).toBeNil()
		RocketBoost.activate(s, 0)
		expect((RocketBoost.modifiers(s) :: any)[1]).toEqual({ stat = "topSpeed", op = "add", value = 20 })
		expect(RocketBoost.isActive(s)).toBe(true)
		RocketBoost.update(s, 2.5)
		expect(RocketBoost.modifiers(s)).toBeNil()
	end)

	it(
		"a destroyed engine/track ends the burn at once and blocks presses; early release recharges from then",
		function()
			local s = RocketBoost.new(SPEC, 0)
			local ctx = Common.newContext()
			RocketBoost.activate(s, 0, ctx)
			ctx.mobile = false
			RocketBoost.update(s, 1, ctx)
			expect(s.phase).toBe("Off")
			expect(RocketBoost.nextChange(s)).toBe(31)
			expect(select(2, RocketBoost.activate(s, 2, ctx))).toBe("IMMOBILE")
			ctx.mobile = true
			RocketBoost.activate(s, 3, ctx)
			expect((RocketBoost.deactivate(s, 4, ctx))).toBe(true)
			expect(s.rechargeAt).toEqual({ 31, 34 })
			expect(select(2, RocketBoost.deactivate(s, 5))).toBe("NOT_ACTIVE")
			ctx.alive = false
			expect(select(2, RocketBoost.activate(s, 40, ctx))).toBe("DEAD")
		end
	)

	it("charges floor to a whole number >= 1; snapshot shows pips and the next recharge", function()
		local s = RocketBoost.new(
			{ kind = "RocketBoost", charges = 0, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 } :: any,
			0
		)
		expect(s.maxCharges).toBe(1)
		local t = RocketBoost.new(SPEC, 0)
		RocketBoost.activate(t, 0)
		local snap = RocketBoost.snapshot(t, 1)
		expect(snap.charges).toBe(1)
		expect(snap.maxCharges).toBe(2)
		expect(snap.active).toBe(true)
		expect(snap.remainingS).toBeCloseTo(1.5, 1e-12)
		RocketBoost.update(t, 2.5)
		RocketBoost.snapshot(t, 10, snap)
		expect(snap.cooldownRemainingS).toBeCloseTo(22.5, 1e-12)
		expect(snap.remainingS).toBe(0)
	end)
end)
