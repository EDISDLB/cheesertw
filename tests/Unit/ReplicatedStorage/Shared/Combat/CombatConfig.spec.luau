-- Config/Combat is data-only (no spec required by rule 10); these checks pin its values to 00-DECISIONS.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Config = require("@game/ReplicatedStorage/Shared/Config")

local KINDS = { "AP", "APCR", "HEAT", "HE", "HESH" }

describe("Config.Combat", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	it("every default lies inside its declared bounds and every bound names a number", function()
		local problems = {}
		for _, p in Config.validateBounds() do
			if string.sub(p, 1, 7) == "Combat." then
				table.insert(problems, p)
			end
		end
		expect(problems).toEqual({})
	end)

	it("covers every shell family", function()
		local C = Config.Combat
		for _, kind in KINDS do
			expect(type(C.NORMALIZATION_DEG[kind])).toBe("number")
			expect(type(C.RICOCHET_ANGLE_DEG[kind])).toBe("number")
			expect(type(C.KINETIC[kind])).toBe("boolean")
			expect(type(C.EXPLOSIVE[kind])).toBe("boolean")
			expect(type(C.MODULE_DAMAGE_FACTOR[kind])).toBe("number")
			expect(type(C.VELOCITY_RATIO[kind])).toBe("number")
		end
	end)

	it("matches the decided values (00-DECISIONS §1–§3)", function()
		local C = Config.Combat
		expect(C.NORMALIZATION_DEG.AP).toBe(5)
		expect(C.NORMALIZATION_DEG.APCR).toBe(2)
		expect(C.RICOCHET_ANGLE_DEG.AP).toBe(70)
		expect(C.RICOCHET_ANGLE_DEG.HEAT).toBe(85)
		expect(C.RICOCHET_PEN_MUL.AP).toBe(0.75)
		expect(C.RICOCHET_MAX).toBe(1)
		expect(C.MAX_PLATES).toBe(8)
		expect(C.ROLL_SPREAD).toBe(0.25)
		expect(C.ROLL_SPREAD / C.ROLL_SPREAD_SIGMAS).toBe(0.125)
		expect(C.ROLL_RESAMPLE_TRIES).toBe(8)
		expect(C.SHELL_GRAVITY_MPS2).toBe(19.62)
		expect(C.MAX_RANGE_M).toBe(600)
		expect(C.VELOCITY_SCALE).toBe(0.6)
		expect(C.HEAT_GAP_LOSS_PER_M).toBe(0.5)
		expect(C.HE_SCREEN_PEN_MUL).toBe(3)
		expect(C.HESH_NONPEN_MUL).toBe(1.15)
		expect(C.FIRE_DURATION_S * C.FIRE_DAMAGE_PER_S).toBeCloseTo(0.2, 1e-12)
		expect(C.RAM_MIN_SPEED_MPS).toBe(3)
		expect(C.FALL_MIN_SPEED_MPS).toBe(7)
		expect(C.DROWN_TIME_S).toBe(10)
		expect(C.DISPERSION_MODEL).toBe("radial")
		expect(C.AFTER_SHOT_BLOOM.heavy).toBe(3.5)
	end)

	it("accepts in-bounds live overrides and rejects out-of-bounds ones", function()
		expect(Config.applyOverrides({ Combat = { ROLL_SPREAD = 0.2, ["RICOCHET_ANGLE_DEG.AP"] = 72 } })).toBeOk()
		expect(Config.Combat.ROLL_SPREAD).toBe(0.2)
		expect(Config.Combat.RICOCHET_ANGLE_DEG.AP).toBe(72)
		expect(Config.applyOverrides({ Combat = { ROLL_SPREAD = 0.9 } })).toBeErr("INVALID_ARGS")
		expect(Config.applyOverrides({ Combat = { MAX_PLATES = 2.5 } })).toBeErr("INVALID_ARGS")
	end)
end)
