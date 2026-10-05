local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Freeze = require("@game/ReplicatedStorage/Shared/Core/Freeze")

Test.afterEach(function()
	Config.resetOverrides()
end)

describe("Config", function()
	it("aggregates deep-frozen sections", function()
		expect(Config.Battle.TICK_RATE).toBe(30)
		expect(Config.Battle.SNAPSHOT_RATE).toBe(20)
		for _, name in Config.sections() do
			expect(Freeze.isDeepFrozen((Config :: any)[name])).toBe(true)
		end
		expect(function()
			(Config.Battle :: any).TICK_RATE = 60
		end).toThrow("readonly")
	end)

	it("declared bounds contain the shipped defaults", function()
		expect(Config.validateBounds()).toEqual({})
	end)

	it("applies valid overrides atomically into a new frozen section", function()
		local before = Config.Battle
		local result = Config.applyOverrides({ Battle = { SNAPSHOT_RATE = 15, INTERPOLATION_DELAY_S = 0.12 } })
		expect(result).toBeOk()
		expect(result.value).toEqual({ "Battle.INTERPOLATION_DELAY_S", "Battle.SNAPSHOT_RATE" })
		expect(Config.Battle.SNAPSHOT_RATE).toBe(15)
		expect(Config.Battle.TICK_RATE).toBe(30)
		expect(Config.Battle).never.toBe(before)
		expect(before.SNAPSHOT_RATE).toBe(20)
		expect(Freeze.isDeepFrozen(Config.Battle)).toBe(true)
	end)

	it("rejects out-of-bounds, non-integer, non-numeric and undeclared keys with paths", function()
		local cases = {
			{ patch = { Battle = { TICK_RATE = 90 } }, msg = "Battle.TICK_RATE: expected <= 60, got 90" },
			{ patch = { Battle = { TICK_RATE = 5 } }, msg = "Battle.TICK_RATE: expected >= 10, got 5" },
			{ patch = { Battle = { TEAM_SIZE = 7.5 } }, msg = "Battle.TEAM_SIZE: expected an integer" },
			{ patch = { Battle = { TICK_RATE = "30" } }, msg = "expected a finite number" },
			{ patch = { Battle = { TICK_RATE = 0 / 0 } }, msg = "expected a finite number" },
			{ patch = { Battle = { BOUNDS = 1 } }, msg = "Battle.BOUNDS: not overridable" },
			{ patch = { Battle = { NEW_KEY = 1 } }, msg = "Battle.NEW_KEY: not overridable" },
			{ patch = { Places = { HUB_PLACE_ID = 5 } }, msg = "Places: section has no overridable keys" },
			{ patch = { Nope = { X = 1 } }, msg = "Nope: section has no overridable keys" },
			{ patch = { Battle = 5 }, msg = "Battle: expected a table of overrides" },
		}
		for _, case in cases do
			local result = Config.applyOverrides(case.patch :: any)
			expect(result).toBeErr("INVALID_ARGS")
			expect(result.detail).toContain(case.msg)
		end
		expect(Config.applyOverrides(5 :: any)).toBeErr("INVALID_ARGS")
	end)

	it("is all-or-nothing", function()
		local result = Config.applyOverrides({ Battle = { SNAPSHOT_RATE = 10, TICK_RATE = 1000 } })
		expect(result).toBeErr("INVALID_ARGS")
		expect(Config.Battle.SNAPSHOT_RATE).toBe(20)
	end)

	it("resetOverrides restores shipped values", function()
		Config.applyOverrides({ Battle = { SNAPSHOT_RATE = 10 } })
		expect(Config.Battle.SNAPSHOT_RATE).toBe(10)
		Config.resetOverrides()
		expect(Config.Battle.SNAPSHOT_RATE).toBe(20)
	end)
end)

describe("Config.Places", function()
	it("resolves roles: Studio and unmapped places are Dev", function()
		expect(Config.Places.resolveRole(0, true)).toBe("Dev")
		expect(Config.Places.resolveRole(0, false)).toBe("Dev")
		expect(Config.Places.resolveRole(123456, false)).toBe("Dev")
		expect(Config.Places.resolveRole(123456, true)).toBe("Dev")
		expect(Config.Places.placeIdFor("Hub")).toBe(Config.Places.HUB_PLACE_ID)
		expect(Config.Places.ROLES).toEqual({ "Hub", "Battle", "Dev" })
	end)
end)

describe("Config.DevAccess", function()
	it("always allows Studio and denies unknown users on live servers", function()
		expect(Config.DevAccess.isAllowed(1, nil, true)).toBe(true)
		expect(Config.DevAccess.isAllowed(1, nil, false)).toBe(false)
		-- GROUP_ID is 0 (disabled) until the studio group exists, so rank never grants access.
		expect(Config.DevAccess.isAllowed(1, 255, false)).toBe(Config.DevAccess.GROUP_ID ~= 0)
	end)
end)
