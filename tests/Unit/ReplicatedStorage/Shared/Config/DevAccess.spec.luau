local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local DevAccess = require("@game/ReplicatedStorage/Shared/Config/DevAccess")
local Config = require("@game/ReplicatedStorage/Shared/Config")

describe("Config/DevAccess", function()
	it("is the same frozen table Config exposes (the allow-list cannot be mutated at runtime)", function()
		expect(Config.DevAccess).toBe(DevAccess)
		expect(table.isfrozen(DevAccess.USER_IDS)).toBe(true)
		expect(function()
			table.insert(DevAccess.USER_IDS, 1)
		end).toThrow()
	end)

	it("always allows Studio sessions", function()
		expect(DevAccess.isAllowed(1, nil, true)).toBe(true)
		expect(DevAccess.isAllowed(-5, 0, true)).toBe(true)
	end)

	it("denies unknown users on live servers whatever rank they claim while GROUP_ID is 0", function()
		expect(DevAccess.isAllowed(1, nil, false)).toBe(false)
		expect(DevAccess.isAllowed(1, 0, false)).toBe(false)
		-- GROUP_ID is 0 (disabled) until the studio group exists, so rank never grants access.
		expect(DevAccess.isAllowed(1, 255, false)).toBe(DevAccess.GROUP_ID ~= 0)
	end)

	it("allow-listed users pass on live servers; ranks below the threshold never do", function()
		for _, userId in DevAccess.USER_IDS do
			expect(DevAccess.isAllowed(userId, nil, false)).toBe(true)
		end
		expect(DevAccess.isAllowed(987654321, DevAccess.MIN_GROUP_RANK - 1, false)).toBe(false)
	end)

	it("the threshold is a sane Roblox rank", function()
		expect(DevAccess.MIN_GROUP_RANK >= 1 and DevAccess.MIN_GROUP_RANK <= 255).toBe(true)
	end)
end)
