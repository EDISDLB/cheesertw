-- Mechanics/ChargedShot: hold-to-charge (1.5 s → dispersion ×0.6 or damage ×1.10, roster §2.7): bonus only at a full
-- charge (boundary inclusive), early release = normal shot, cancel, death, and the optional reset-on-move rule
-- (the charge holds at 0 while moving and restarts at the stop instant).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ChargedShot = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/ChargedShot")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")

local ACCURACY: any = { kind = "ChargedShot", chargeTimeS = 1.5, effect = "Accuracy", dispersionMul = 0.6 }
local DAMAGE: any = { kind = "ChargedShot", chargeTimeS = 1.5, effect = "Damage", damageMul = 1.10 }

describe("Mechanics/ChargedShot", function()
	it("a full charge (inclusive) carries the effect's factor; an early release does not", function()
		local s = ChargedShot.new(ACCURACY, 0)
		expect((ChargedShot.begin(s, 1))).toBe(true)
		expect(select(2, ChargedShot.begin(s, 1.2))).toBe("ACTIVE")
		expect(ChargedShot.progress(s, 1.75)).toBeCloseTo(0.5, 1e-12)
		expect(ChargedShot.release(s, 2.4999)).toBe(false)
		expect(s.phase).toBe("Off")
		ChargedShot.begin(s, 3)
		expect(ChargedShot.release(s, 4.5)).toBe(true)
		local disp, dmg = ChargedShot.shotMultipliers(s, true)
		expect(disp).toBe(0.6)
		expect(dmg).toBe(1)
		expect(select(1, ChargedShot.shotMultipliers(s, false))).toBe(1)
		local d = ChargedShot.new(DAMAGE, 0)
		local dDisp, dDmg = ChargedShot.shotMultipliers(d, true)
		expect(dDisp).toBe(1)
		expect(dDmg).toBe(1.10)
		expect(ChargedShot.modifiers(d)).toBeNil() -- the bonus rides the shot, never a standing modifier
	end)

	it("cancel, death and the generic activate/deactivate contract", function()
		local s = ChargedShot.new(DAMAGE, 0)
		ChargedShot.activate(s, 0)
		expect(ChargedShot.isActive(s)).toBe(true)
		expect((ChargedShot.deactivate(s, 0.5))).toBe(true)
		expect(select(2, ChargedShot.deactivate(s, 0.6))).toBe("NOT_ACTIVE")
		ChargedShot.begin(s, 1)
		ChargedShot.cancel(s)
		expect(ChargedShot.release(s, 5)).toBe(false)
		local ctx = Common.newContext()
		ChargedShot.begin(s, 6, ctx)
		ctx.alive = false
		ChargedShot.update(s, 6.5, ctx)
		expect(s.phase).toBe("Off")
		expect(select(2, ChargedShot.begin(s, 7, ctx))).toBe("DEAD")
	end)

	it("resetOnMove: holds at 0 while moving and restarts when the hull stops", function()
		local s = ChargedShot.new(ACCURACY, 0, { resetOnMove = true })
		local ctx = Common.newContext()
		ctx.stationaryForS = math.huge
		ChargedShot.begin(s, 0, ctx)
		ctx.stationaryForS = 0 -- moving from 1 s
		ChargedShot.update(s, 1, ctx)
		ChargedShot.update(s, 1.9, ctx)
		expect(ChargedShot.progress(s, 1.9)).toBe(0)
		expect(ChargedShot.progress(s, 2.5)).toBe(0) -- held between updates too
		expect(ChargedShot.nextChange(s)).toBe(math.huge)
		expect(ChargedShot.snapshot(s, 1.9).progress).toBe(0)
		ctx.stationaryForS = math.huge -- stopped at 2 s
		ChargedShot.update(s, 2, ctx)
		expect(ChargedShot.progress(s, 2.75)).toBeCloseTo(0.5, 1e-12)
		ChargedShot.update(s, 3.5, ctx)
		expect(s.phase).toBe("On")
		-- without the option (the machine's own default) the charge runs while moving
		local free = ChargedShot.new(ACCURACY, 0)
		ChargedShot.begin(free, 0, ctx)
		ctx.stationaryForS = 0
		ChargedShot.update(free, 1.5, ctx)
		expect(free.phase).toBe("On")
	end)

	it("snapshot and defaults", function()
		local s = ChargedShot.new({ kind = "ChargedShot", chargeTimeS = 0, effect = "Accuracy" } :: any, 0)
		expect(s.chargeTimeS).toBe(1.5)
		expect(s.dispersionMul).toBe(1) -- no factor authored
		local snap = ChargedShot.snapshot(s, 0)
		expect(snap.progress).toBe(0)
		ChargedShot.begin(s, 0)
		expect(ChargedShot.nextChange(s)).toBe(1.5)
		ChargedShot.snapshot(s, 0.75, snap)
		expect(snap.phase).toBe("Engaging")
		expect(snap.progress).toBeCloseTo(0.5, 1e-12)
		ChargedShot.update(s, 2)
		expect(ChargedShot.progress(s, 2)).toBe(1)
		expect(ChargedShot.nextChange(s)).toBe(math.huge)
	end)
end)
