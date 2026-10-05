local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local TableUtil = require("@game/ReplicatedStorage/Shared/Core/TableUtil")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

-- Random JSON-like tree: dictionaries with string keys, arrays, numbers, strings, booleans.
local function randomValue(rng: any, depth: number): any
	local roll = rng:int(1, if depth >= 4 then 4 else 7)
	if roll == 1 then
		return rng:int(-100, 100)
	elseif roll == 2 then
		return rng:pick({ "a", "b", "tank", "" })
	elseif roll == 3 then
		return rng:chance(0.5)
	elseif roll == 4 then
		return rng:range(-1, 1)
	elseif roll <= 6 then
		local t = {}
		for _ = 1, rng:int(0, 5) do
			t[rng:pick({ "x", "y", "z", "w", "hp", "ammo" })] = randomValue(rng, depth + 1)
		end
		return t
	end
	local list = {}
	for i = 1, rng:int(0, 5) do
		list[i] = randomValue(rng, depth + 1)
	end
	return list
end

local function randomTable(rng: any): { [any]: any }
	local value = randomValue(rng, 0)
	while type(value) ~= "table" do
		value = randomValue(rng, 0)
	end
	return value
end

-- Mutates a deep copy a little so old/new share structure (more interesting diffs).
local function mutate(rng: any, t: { [any]: any }, depth: number)
	for k, v in table.clone(t) do
		local roll = rng:int(1, 6)
		if roll == 1 then
			t[k] = nil
		elseif roll == 2 then
			t[k] = randomValue(rng, depth + 1)
		elseif roll == 3 and type(v) == "table" then
			mutate(rng, v, depth + 1)
		end
	end
	if rng:chance(0.3) then
		t[rng:pick({ "new", "added" })] = randomValue(rng, depth + 1)
	end
end

describe("TableUtil basics", function()
	it("copy is shallow, deepCopy is deep and cycle-safe", function()
		local inner = { 1 }
		local t: any = { inner = inner }
		local shallow = TableUtil.copy(t)
		expect(shallow.inner).toBe(inner)
		t.self = t
		local deep = TableUtil.deepCopy(t)
		expect(deep.inner).never.toBe(inner)
		expect(deep.inner).toEqual({ 1 })
		expect(deep.self).toBe(deep)
		local frozen = table.freeze({ a = table.freeze({ 1 }) })
		local thawed = TableUtil.deepCopy(frozen)
		expect(table.isfrozen(thawed)).toBe(false)
		expect(table.isfrozen(thawed.a)).toBe(false)
	end)

	it("deepEqual handles nesting, NaN and key mismatches", function()
		expect(TableUtil.deepEqual({ a = { 1, 2 } }, { a = { 1, 2 } })).toBe(true)
		expect(TableUtil.deepEqual({ a = 0 / 0 }, { a = 0 / 0 })).toBe(true)
		expect(TableUtil.deepEqual({ a = 1 }, { a = 1, b = 2 })).toBe(false)
		expect(TableUtil.deepEqual({ 1 }, { "1" })).toBe(false)
		expect(TableUtil.deepEqual(1, 1)).toBe(true)
	end)

	it("merge / keys / sortedKeys / values / count", function()
		expect(TableUtil.merge({ a = 1, b = 1 }, nil, { b = 2 })).toEqual({ a = 1, b = 2 })
		expect(TableUtil.sortedKeys({ b = 1, [2] = 1, a = 1, [1] = 1 })).toEqual({ 1, 2, "a", "b" })
		local keys = TableUtil.keys({ x = 1, y = 2 })
		table.sort(keys)
		expect(keys).toEqual({ "x", "y" })
		local values = TableUtil.values({ x = 1, y = 2 })
		table.sort(values)
		expect(values).toEqual({ 1, 2 })
		expect(TableUtil.count({ a = 1, b = 2, 3 })).toBe(3)
	end)

	it("filter / map / find on arrays", function()
		local list = { 1, 2, 3, 4 }
		expect(TableUtil.filter(list, function(v)
			return v % 2 == 0
		end)).toEqual({ 2, 4 })
		expect(TableUtil.map(list, function(v, i)
			return v * i
		end)).toEqual({ 1, 4, 9, 16 })
		local value, index = TableUtil.find(list, function(v)
			return v > 2
		end)
		expect(value).toBe(3)
		expect(index).toBe(3)
		expect((TableUtil.find(list, function()
			return false
		end))).toBeNil()
	end)
end)

describe("TableUtil.diff / applyPatches", function()
	it("emits sets for added/changed keys and deletes for removed keys", function()
		local patches = TableUtil.diff(
			{ credits = 100, vehicles = { t1 = true }, gone = 1 },
			{ credits = 150, vehicles = { t1 = true, t2 = true } }
		)
		expect(patches).toEqual({
			{ op = "set", path = { "credits" }, value = 150 },
			{ op = "set", path = { "vehicles", "t2" }, value = true },
			{ op = "delete", path = { "gone" } },
		})
	end)

	it("diff of identical tables is empty", function()
		local t = { a = { b = { 1, 2, 3 } }, c = "x", n = 0 / 0 }
		expect(TableUtil.diff(t, TableUtil.deepCopy(t))).toEqual({})
	end)

	it("shrinks arrays from the end and grows them in order", function()
		local shrink = TableUtil.diff({ list = { 1, 2, 3, 4 } }, { list = { 1, 2 } })
		expect(shrink).toEqual({
			{ op = "delete", path = { "list", 4 } },
			{ op = "delete", path = { "list", 3 } },
		})
		local grow = TableUtil.diff({ list = { 1 } }, { list = { 1, 2, 3 } })
		expect(grow).toEqual({
			{ op = "set", path = { "list", 2 }, value = 2 },
			{ op = "set", path = { "list", 3 }, value = 3 },
		})
	end)

	it("replaces values whose type changes", function()
		expect(TableUtil.diff({ a = 1 }, { a = { b = 2 } })).toEqual({
			{ op = "set", path = { "a" }, value = { b = 2 } },
		})
		expect(TableUtil.diff({ a = { b = 2 } }, { a = 1 })).toEqual({ { op = "set", path = { "a" }, value = 1 } })
	end)

	it("patch values are copies (no aliasing with the new table)", function()
		local new = { nested = { v = 1 } }
		local patches = TableUtil.diff({}, new)
		new.nested.v = 99
		local target = TableUtil.applyPatches({}, patches)
		expect(target.nested.v).toBe(1)
	end)

	it("applyPatches creates intermediates, ignores deletes of missing paths and handles the root", function()
		local target = {}
		TableUtil.applyPatches(target, {
			{ op = "set", path = { "a", "b", "c" }, value = 1 },
			{ op = "delete", path = { "x", "y" } },
		})
		expect(target).toEqual({ a = { b = { c = 1 } } })
		local returned = TableUtil.applyPatches(target, { { op = "set", path = {}, value = { fresh = true } } })
		expect(returned).toBe(target)
		expect(target).toEqual({ fresh = true })
		TableUtil.applyPatches(target, { { op = "delete", path = {} } })
		expect(target).toEqual({})
	end)

	it("applyPatches rejects malformed patches", function()
		expect(function()
			TableUtil.applyPatches({ a = 1 }, { { op = "set", path = { "a", "b" }, value = 1 } })
		end).toThrow("traverses a non-table")
		expect(function()
			TableUtil.applyPatches({}, { { op = "merge" :: any, path = { "a" } } })
		end).toThrow("unknown op")
		expect(function()
			TableUtil.applyPatches({}, { { op = "set", path = { true :: any }, value = 1 } })
		end).toThrow("must be a string or number")
		expect(function()
			TableUtil.applyPatches({}, { { op = "set", path = {}, value = 5 } })
		end).toThrow("non-table")
	end)

	it("property: applyPatches(copy(old), diff(old, new)) == new for random tables", function()
		local rng = RNG.new(2024)
		for _ = 1, 400 do
			local old = randomTable(rng)
			local new = TableUtil.deepCopy(old)
			mutate(rng, new, 0)
			if rng:chance(0.2) then
				new = randomTable(rng)
			end
			local patches = TableUtil.diff(old, new)
			local target = TableUtil.deepCopy(old)
			TableUtil.applyPatches(target, patches)
			if not TableUtil.deepEqual(target, new) then
				expect(target).toEqual(new)
			end
			expect(TableUtil.diff(new, TableUtil.deepCopy(new))).toEqual({})
		end
	end)

	it("property: patches are deterministic", function()
		local rng = RNG.new(77)
		for _ = 1, 50 do
			local old = randomTable(rng)
			local new = randomTable(rng)
			expect(TableUtil.diff(old, new)).toEqual(TableUtil.diff(TableUtil.deepCopy(old), TableUtil.deepCopy(new)))
		end
	end)
end)

describe("TableUtil.diff (adversarial shapes)", function()
	local function roundTrip(old: any, new: any): any
		local target = TableUtil.deepCopy(old)
		TableUtil.applyPatches(target, TableUtil.diff(old, new))
		return target
	end

	it("arrays: shrink to empty, grow from empty, remove from the middle, insert at the front", function()
		local cases = {
			{ { 1, 2, 3 }, {} },
			{ {}, { 1, 2, 3 } },
			{ { "a", "b", "c", "d" }, { "a", "c", "d" } },
			{ { "b", "c" }, { "a", "b", "c" } },
			{ { { id = 1 }, { id = 2 }, { id = 3 } }, { { id = 3 } } },
			{ { { id = 1 } }, { { id = 1, hp = 5 }, { id = 2 } } },
		}
		for _, case in cases do
			expect(roundTrip(case[1], case[2])).toEqual(case[2])
		end
	end)

	it("array shrink deletes run from the highest index down (no holes mid-way)", function()
		local patches = TableUtil.diff({ 1, 2, 3, 4, 5 }, { 1, 2 })
		local deleted = {}
		for _, p in patches do
			if p.op == "delete" then
				table.insert(deleted, p.path[1])
			end
		end
		expect(deleted).toEqual({ 5, 4, 3 })
	end)

	it("type changes: array <-> dictionary, value <-> table, nested deletes", function()
		local cases = {
			{ { list = { 1, 2 } }, { list = { a = 1 } } },
			{ { list = { a = 1 } }, { list = { 1, 2 } } },
			{ { v = 5 }, { v = { 5 } } },
			{ { v = { deep = { deeper = { x = 1 } } } }, { v = 5 } },
			{ { a = { b = { c = { d = 1 } } } }, { a = { b = {} } } },
			{ { a = { b = { c = { d = 1 } } }, keep = true }, { keep = true } },
			{ { x = false }, { x = true } },
			{ { x = 0 / 0 }, { x = 0 / 0 } },
		}
		for _, case in cases do
			expect(roundTrip(case[1], case[2])).toEqual(case[2])
		end
		expect(TableUtil.diff({ x = 0 / 0 }, { x = 0 / 0 })).toEqual({})
	end)

	it("never aliases patch values with the new tree, even for shared subtables", function()
		local shared = { hp = 1 }
		local new = { a = shared, b = shared }
		local patches = TableUtil.diff({}, new)
		for _, p in patches do
			expect(p.value).never.toBe(shared)
		end
		shared.hp = 99
		local target = TableUtil.applyPatches({}, patches)
		expect(target).toEqual({ a = { hp = 1 }, b = { hp = 1 } })
	end)

	it("rejects keys applyPatches could never accept (boolean/table keys)", function()
		expect(function()
			TableUtil.diff({}, { [true] = 1 } :: any)
		end).toThrow("unsupported key type boolean")
		expect(function()
			TableUtil.diff({ [{}] = 1 } :: any, {})
		end).toThrow("unsupported key type table")
	end)

	it("applyPatches refuses to traverse through a non-table and leaves earlier patches applied", function()
		local target = { a = 1 }
		expect(function()
			TableUtil.applyPatches(target, {
				{ op = "set", path = { "b" }, value = 2 },
				{ op = "set", path = { "a", "x" }, value = 3 },
			})
		end).toThrow("traverses a non-table")
		expect(target.b).toBe(2)
	end)
end)
