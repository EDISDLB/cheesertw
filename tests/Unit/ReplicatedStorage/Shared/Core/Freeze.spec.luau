local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Freeze = require("@game/ReplicatedStorage/Shared/Core/Freeze")

describe("Freeze", function()
	it("freezes nested tables and returns the same reference", function()
		local data = { a = { b = { c = 1 } }, list = { 1, 2, 3 } }
		local frozen = Freeze.deep(data)
		expect(frozen).toBe(data)
		expect(table.isfrozen(data)).toBe(true)
		expect(table.isfrozen(data.a.b)).toBe(true)
		expect(Freeze.isDeepFrozen(data)).toBe(true)
	end)

	it("mutations raise errors at every level", function()
		local data = Freeze.deep({ a = { b = 1 }, list = { 1 } })
		expect(function()
			data.x = 1
		end).toThrow("readonly")
		expect(function()
			data.a.b = 2
		end).toThrow("readonly")
		expect(function()
			table.insert(data.list, 2)
		end).toThrow("readonly")
	end)

	it("is idempotent and freezes children of an already frozen parent", function()
		local child = { v = 1 }
		local parent = table.freeze({ child = child })
		expect(table.isfrozen(child)).toBe(false)
		Freeze.deep(parent)
		expect(table.isfrozen(child)).toBe(true)
		expect(Freeze.deep(parent)).toBe(parent)
	end)

	it("handles cycles and shared subtables", function()
		local shared = { 1 }
		local t: any = { a = shared, b = shared }
		t.self = t
		Freeze.deep(t)
		expect(Freeze.isDeepFrozen(t)).toBe(true)
	end)

	it("passes non-tables through", function()
		expect(Freeze.deep(5)).toBe(5)
		expect(Freeze.deep("x")).toBe("x")
		expect(Freeze.isDeepFrozen({ { 1 } })).toBe(false)
	end)
end)
