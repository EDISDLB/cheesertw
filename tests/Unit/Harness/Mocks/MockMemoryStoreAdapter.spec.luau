local Test = require("@tests/Harness/Test")
local FakeClock = require("@tests/Harness/FakeClock")
local describe, it, expect = Test.describe, Test.it, Test.expect

local MockMemoryStoreAdapter = require("@tests/Harness/Mocks/MockMemoryStoreAdapter")

local clock, adapter

Test.beforeEach(function()
	clock = FakeClock.new(0)
	adapter = MockMemoryStoreAdapter.new({ clock = clock })
end)

local function keysOf(items: { any }): { string }
	local out = {}
	for _, item in items do
		table.insert(out, item.key)
	end
	return out
end

describe("MockMemoryStoreAdapter sorted maps", function()
	it("set/get with sort keys and TTL expiry", function()
		local map = adapter:getSortedMap("Queue")
		expect(adapter:getSortedMap("Queue")).toBe(map)
		local ok, overwrote = map:setAsync("t1", { size = 1 }, 10, 5)
		expect(ok).toBe(true)
		expect(overwrote).toBe(false)
		local _, overwroteAgain = map:setAsync("t1", { size = 2 }, 10, 6)
		expect(overwroteAgain).toBe(true)
		local okGet, value, sortKey = map:getAsync("t1")
		expect(okGet).toBe(true)
		expect(value).toEqual({ size = 2 })
		expect(sortKey).toBe(6)
		clock:advance(9.9)
		expect(select(2, map:getAsync("t1"))).never.toBeNil()
		clock:advance(0.1)
		expect(select(2, map:getAsync("t1"))).toBeNil()
	end)

	it("orders numeric, then string, then missing sort keys; ties by key", function()
		local map = adapter:getSortedMap("Board")
		map:setAsync("e", 1, 100)
		map:setAsync("d", 1, 100, "beta")
		map:setAsync("c", 1, 100, "alpha")
		map:setAsync("b", 1, 100, 10)
		map:setAsync("a", 1, 100, 10)
		map:setAsync("z", 1, 100, 2)
		local _, items = map:getRangeAsync("Ascending", 10)
		expect(keysOf(items)).toEqual({ "z", "a", "b", "c", "d", "e" })
		local _, desc = map:getRangeAsync("Descending", 2)
		expect(keysOf(desc)).toEqual({ "e", "d" })
	end)

	it("honours exclusive bounds", function()
		local map = adapter:getSortedMap("Board")
		for i = 1, 5 do
			map:setAsync("k" .. i, i, 100, i * 10)
		end
		local _, items = map:getRangeAsync("Ascending", 10, { sortKey = 20 }, { sortKey = 50 })
		expect(keysOf(items)).toEqual({ "k3", "k4" })
		local _, withKey = map:getRangeAsync("Ascending", 10, { sortKey = 20, key = "k1" })
		expect(keysOf(withKey)).toEqual({ "k2", "k3", "k4", "k5" })
		local okSize, size = map:getSizeAsync()
		expect(okSize).toBe(true)
		expect(size).toBe(5)
	end)

	it("UpdateAsync transforms value and sort key; nil cancels", function()
		local map = adapter:getSortedMap("Locks")
		local ok, value, sortKey = map:updateAsync("leader", function(old, oldSort)
			expect(old).toBeNil()
			expect(oldSort).toBeNil()
			return { owner = "job-1" }, 1
		end, 30)
		expect(ok).toBe(true)
		expect(value).toEqual({ owner = "job-1" })
		expect(sortKey).toBe(1)
		local okCancel, cancelled = map:updateAsync("leader", function()
			return nil
		end, 30)
		expect(okCancel).toBe(true)
		expect(cancelled).toBeNil()
		expect(adapter:peek("sorted", "Locks", "leader").value).toEqual({ owner = "job-1" })
	end)

	it("simulated conflicts re-run the transform with the competing value", function()
		local map = adapter:getSortedMap("Locks")
		adapter:simulateConflict("sorted", "Locks", "leader", { owner = "job-2" }, 2)
		local seen = {}
		local ok, value = map:updateAsync("leader", function(old)
			table.insert(seen, if old then old.owner else "none")
			if old ~= nil then
				return nil
			end
			return { owner = "job-1" }, 1
		end, 30)
		expect(ok).toBe(true)
		expect(value).toBeNil()
		expect(seen).toEqual({ "none", "job-2" })
		expect(adapter:peek("sorted", "Locks", "leader").value.owner).toBe("job-2")
	end)

	it("validates keys, TTLs, values and sort keys", function()
		local map = adapter:getSortedMap("V")
		expect((map:setAsync("", 1, 10))).toBe(false)
		expect((map:setAsync(string.rep("k", 129), 1, 10))).toBe(false)
		expect((map:setAsync("k", 1, 0))).toBe(false)
		expect((map:setAsync("k", 1, 3888001))).toBe(false)
		expect((map:setAsync("k", string.rep("x", 33 * 1024), 10))).toBe(false)
		expect((map:setAsync("k", 1, 10, {} :: any))).toBe(false)
		expect((map:getRangeAsync("Ascending", 201))).toBe(false)
		expect((map:setAsync("k", 1, 3888000, "ok"))).toBe(true)
	end)

	it("injected failures", function()
		local map = adapter:getSortedMap("F")
		adapter:failNext("setAsync")
		local ok, err = map:setAsync("k", 1, 10)
		expect(ok).toBe(false)
		expect(err).toContain("injected")
		expect((map:setAsync("k", 1, 10))).toBe(true)
	end)
end)

describe("MockMemoryStoreAdapter hash maps", function()
	it("set/get/update/remove/list with TTL", function()
		local map = adapter:getHashMap("Manifests")
		expect((map:setAsync("match:1", { players = { 1, 2 } }, 60))).toBe(true)
		map:setAsync("match:2", { players = {} }, 5)
		local _, value = map:getAsync("match:1")
		expect(value.players).toEqual({ 1, 2 })
		local okUpdate, updated = map:updateAsync("match:1", function(old)
			table.insert(old.players, 3)
			return old
		end, 60)
		expect(okUpdate).toBe(true)
		expect(updated.players).toEqual({ 1, 2, 3 })
		local _, items = map:listItemsAsync(10)
		expect(#items).toBe(2)
		clock:advance(6)
		local _, after = map:listItemsAsync(10)
		expect(#after).toBe(1)
		expect((map:removeAsync("match:1"))).toBe(true)
		expect(select(2, map:getAsync("match:1"))).toBeNil()
	end)

	it("hash and sorted namespaces are separate", function()
		adapter:getHashMap("Same"):setAsync("k", "hash", 10)
		adapter:getSortedMap("Same"):setAsync("k", "sorted", 10)
		expect(select(2, adapter:getHashMap("Same"):getAsync("k"))).toBe("hash")
		expect(select(2, adapter:getSortedMap("Same"):getAsync("k"))).toBe("sorted")
	end)
end)
