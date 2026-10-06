-- Mechanics/SiegeMode: Off → Engaging (2.0 s) → On → Disengaging (1.25 s) → Off with exact transition times, the
-- speed cap, travel reverse ratio, siege modifiers, auto-engage and rejection reasons (00-DECISIONS §4).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local SiegeMode = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/SiegeMode")
local Common = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Common")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local MODS = {
	{ stat = "aimTime", op = "mul", value = 0.4 },
	{ stat = "dispersion", op = "mul", value = 0.85 },
	{ stat = "gunDepression", op = "add", value = 8 },
	{ stat = "gunElevation", op = "add", value = 6 },
	{ stat = "hullTraverse", op = "mul", value = 0.5 },
}

local function spec(extra: any?): any
	local s: any = {
		kind = "SiegeMode",
		engageS = 2.0,
		disengageS = 1.25,
		maxSpeedKmh = 10,
		travelReverseRatio = 0.9,
		modifiers = MODS,
	}
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end

describe("Mechanics/SiegeMode", function()
	it("table-driven lifecycle with exact transition times and rejection reasons", function()
		local s = SiegeMode.new(spec(), 0)
		-- { t, action, expected ok/phase, reason? }
		local steps = {
			{ 0.5, "deactivate", false, "NOT_ACTIVE" },
			{ 1.0, "activate", true },
			{ 1.0, "phase", "Engaging" },
			{ 2.0, "activate", false, "ALREADY_ACTIVE" },
			{ 2.0, "deactivate", false, "IN_TRANSITION" },
			{ 2.999, "phase", "Engaging" },
			{ 3.0, "phase", "On" },
			{ 4.0, "activate", false, "ALREADY_ACTIVE" },
			{ 5.0, "deactivate", true },
			{ 5.5, "activate", false, "IN_TRANSITION" },
			{ 6.249, "phase", "Disengaging" },
			{ 6.25, "phase", "Off" },
			{ 7.0, "toggle", true },
			{ 9.0, "phase", "On" },
			{ 9.5, "toggle", true },
			{ 9.5, "phase", "Disengaging" },
		}
		for i, step in steps do
			local t, action = step[1], step[2]
			if action == "phase" then
				SiegeMode.update(s, t)
				if s.phase ~= step[3] then
					error(`step {i} @ {t}: phase {s.phase}, expected {step[3]}`)
				end
			else
				local fn = (SiegeMode :: any)[action]
				local ok, reason = fn(s, t, Common.newContext())
				if ok ~= step[3] or reason ~= step[4] then
					error(`step {i} @ {t} {action}: {tostring(ok)} {tostring(reason)}`)
				end
			end
		end
		expect(s.phaseStart).toBe(9.5)
		expect(s.phaseEnd).toBe(10.75)
	end)

	it("speed cap from the first engaging instant until fully off; travel reverse only while off", function()
		local s = SiegeMode.new(spec(), 0)
		expect(SiegeMode.speedCapKmh(s)).toBe(math.huge)
		expect(SiegeMode.travelReverseRatio(s)).toBe(0.9)
		SiegeMode.activate(s, 0)
		expect(SiegeMode.speedCapKmh(s)).toBe(10)
		expect(SiegeMode.travelReverseRatio(s)).toBeNil()
		expect(SiegeMode.modifiers(s)).toBeNil() -- not sieged yet
		expect(SiegeMode.isActive(s)).toBe(false)
		SiegeMode.update(s, 2)
		expect(SiegeMode.modifiers(s)).toBe(MODS)
		expect(SiegeMode.isActive(s)).toBe(true)
		SiegeMode.deactivate(s, 3)
		expect(SiegeMode.speedCapKmh(s)).toBe(10)
		expect(SiegeMode.modifiers(s)).toBeNil()
		SiegeMode.update(s, 4.25)
		expect(SiegeMode.speedCapKmh(s)).toBe(math.huge)
	end)

	it("auto-engage after autoEngageS still; a manual disengage suppresses it until the hull moves", function()
		local s = SiegeMode.new(spec({ autoEngageS = 0.5 }), 0)
		local ctx = Common.newContext()
		ctx.stationaryForS = 0.4
		SiegeMode.update(s, 1, ctx)
		expect(s.phase).toBe("Off")
		ctx.stationaryForS = 0.5
		expect(SiegeMode.update(s, 1.1, ctx)).toBe(true)
		expect(s.phase).toBe("Engaging")
		ctx.stationaryForS = 3
		SiegeMode.update(s, 3.1, ctx)
		expect(s.phase).toBe("On")
		SiegeMode.deactivate(s, 4, ctx)
		SiegeMode.update(s, 6, ctx)
		expect(s.phase).toBe("Off") -- still stationary, but suppressed
		ctx.stationaryForS = 0 -- moved
		SiegeMode.update(s, 7, ctx)
		ctx.stationaryForS = 0.6
		SiegeMode.update(s, 7.6, ctx)
		expect(s.phase).toBe("Engaging") -- re-armed
		local off = SiegeMode.new(spec({ autoEngageS = 0.5 }), 0, { autoEngage = false })
		ctx.stationaryForS = 9
		SiegeMode.update(off, 9, ctx)
		expect(off.phase).toBe("Off")
		local none = SiegeMode.new(spec(), 0, { autoEngage = true }) -- no autoEngageS in the spec
		expect(none.autoEngage).toBe(false)
		ctx.alive = false
		local dead = SiegeMode.new(spec({ autoEngageS = 0.5 }), 0)
		SiegeMode.update(dead, 9, ctx)
		expect(dead.phase).toBe("Off")
		expect(select(2, SiegeMode.activate(dead, 9, ctx))).toBe("DEAD")
	end)

	it("falls back to the decided timings on bad data", function()
		local s = SiegeMode.new(spec({ engageS = 0 / 0, disengageS = -1 }), 0)
		expect(s.engageS).toBe(2.0)
		expect(s.disengageS).toBe(1.25)
		local capless = SiegeMode.new(spec({ maxSpeedKmh = -5 }), 0)
		SiegeMode.activate(capless, 0)
		expect(SiegeMode.speedCapKmh(capless)).toBe(10)
	end)

	it("transitions land on the same instant whatever the tick rate (seeded)", function()
		local rng = RNG.new(9)
		for _ = 1, 50 do
			local s = SiegeMode.new(spec(), 0)
			SiegeMode.activate(s, 0.25)
			local t = 0.25
			while s.phase ~= "On" do
				t += rng:range(0.001, 0.2)
				SiegeMode.update(s, t)
			end
			expect(s.phaseStart).toBe(2.25)
		end
	end)

	it("snapshot reports transition progress", function()
		local s = SiegeMode.new(spec(), 0)
		SiegeMode.activate(s, 0)
		local snap = SiegeMode.snapshot(s, 0.5)
		expect(snap.kind).toBe("SiegeMode")
		expect(snap.phase).toBe("Engaging")
		expect(snap.progress).toBeCloseTo(0.25, 1e-12)
		expect(snap.remainingS).toBeCloseTo(1.5, 1e-12)
		expect(snap.active).toBe(false)
		expect(SiegeMode.nextChange(s)).toBe(2)
		SiegeMode.update(s, 2)
		local on = SiegeMode.snapshot(s, 3, snap)
		expect(on.active).toBe(true)
		expect(on.progress).toBe(1)
		expect(SiegeMode.nextChange(s)).toBe(math.huge)
	end)
end)
