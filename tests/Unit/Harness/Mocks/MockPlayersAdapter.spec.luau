local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local MockPlayersAdapter = require("@tests/Harness/Mocks/MockPlayersAdapter")
local MockAdapters = require("@tests/Harness/Mocks/MockAdapters")

describe("MockPlayersAdapter", function()
	it("mirrors the Players service and its signals", function()
		local adapter = MockPlayersAdapter.new()
		local added, removing = {}, {}
		adapter.PlayerAdded:Connect(function(p)
			table.insert(added, p.UserId)
		end)
		adapter.PlayerRemoving:Connect(function(p)
			table.insert(removing, p.UserId)
		end)
		local p = adapter:addPlayer({ UserId = 42 })
		expect(adapter:getPlayerByUserId(42)).toBe(p)
		expect(#adapter:getPlayers()).toBe(1)
		adapter:kick(p, "rule violation")
		expect(adapter.kicked[1].message).toBe("rule violation")
		expect(added).toEqual({ 42 })
		expect(removing).toEqual({ 42 })
		expect(adapter:getPlayerByUserId(42)).toBeNil()
	end)

	it("group ranks with failure injection", function()
		local adapter = MockPlayersAdapter.new()
		expect(select(2, adapter:getGroupRankAsync(1, 77))).toBe(0)
		adapter:setGroupRank(1, 77, 255)
		expect(select(2, adapter:getGroupRankAsync(1, 77))).toBe(255)
		adapter:failNext("getGroupRankAsync")
		expect((adapter:getGroupRankAsync(1, 77))).toBe(false)
	end)

	it("MockAdapters builds a complete bundle", function()
		local adapters = MockAdapters.new()
		for _, key in { "players", "dataStore", "memoryStore", "messaging", "teleport", "marketplace" } do
			expect(adapters[key]).never.toBeNil()
		end
		expect(adapters.world).toBeNil()
	end)
end)
