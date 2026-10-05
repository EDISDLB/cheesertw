local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

describe("Trove", function()
	it("calls functions on Clean in LIFO order", function()
		local trove = Trove.new()
		local order = {}
		trove:Add(function()
			table.insert(order, 1)
		end)
		trove:Add(function()
			table.insert(order, 2)
		end)
		trove:Clean()
		expect(order).toEqual({ 2, 1 })
		trove:Clean()
		expect(order).toEqual({ 2, 1 })
	end)

	it("destroys Instances and returns the added object", function()
		local trove = Trove.new()
		local folder = Instance.new("Folder")
		folder.Parent = workspace
		expect(trove:Add(folder)).toBe(folder)
		trove:Clean()
		expect(folder.Parent).toBeNil()
		expect(function()
			folder.Parent = workspace
		end).toThrow("locked")
	end)

	it("disconnects Signal connections and Connect() works with signals", function()
		local trove = Trove.new()
		local s = Signal.new()
		local count = 0
		local connection = trove:Connect(s, function()
			count += 1
		end)
		s:Fire()
		trove:Clean()
		s:Fire()
		expect(count).toBe(1)
		expect(connection.Connected).toBe(false)
	end)

	it("handles tables with Destroy, Disconnect or a custom method", function()
		local trove = Trove.new()
		local log = {}
		trove:Add({
			Destroy = function()
				table.insert(log, "destroy")
			end,
		})
		trove:Add({
			Disconnect = function()
				table.insert(log, "disconnect")
			end,
		})
		trove:Add({
			Close = function()
				table.insert(log, "close")
			end,
		}, "Close")
		trove:Clean()
		expect(log).toEqual({ "close", "disconnect", "destroy" })
	end)

	it("cancels threads", function()
		local trove = Trove.new()
		local ran = false
		local thread = task.delay(0.05, function()
			ran = true
		end)
		trove:Add(thread)
		trove:Clean()
		task.wait(0.1)
		expect(ran).toBe(false)
		expect(coroutine.status(thread)).toBe("dead")
	end)

	it("Extend creates a child cleaned with the parent", function()
		local parent = Trove.new()
		local child = parent:Extend()
		local cleaned = false
		child:Add(function()
			cleaned = true
		end)
		parent:Clean()
		expect(cleaned).toBe(true)
	end)

	it("Remove cleans one object and reports whether it was tracked", function()
		local trove = Trove.new()
		local count = 0
		local fn = function()
			count += 1
		end
		trove:Add(fn)
		expect(trove:Remove(fn)).toBe(true)
		expect(count).toBe(1)
		expect(trove:Remove(fn)).toBe(false)
		trove:Clean()
		expect(count).toBe(1)
	end)

	it("cleans objects added after Destroy immediately", function()
		local trove = Trove.new()
		trove:Destroy()
		local cleaned = false
		trove:Add(function()
			cleaned = true
		end)
		expect(cleaned).toBe(true)
	end)

	it("rejects values it cannot clean", function()
		local trove = Trove.new()
		expect(function()
			trove:Add({})
		end).toThrow("cannot clean")
		expect(function()
			trove:Add(5 :: any)
		end).toThrow("cannot clean")
		expect(function()
			trove:Add({}, "Missing")
		end).toThrow("no method")
	end)

	it("keeps cleaning when one cleanup fails", function()
		local capture = LogCapture.start()
		local trove = Trove.new()
		local cleaned = false
		trove:Add(function()
			cleaned = true
		end)
		trove:Add(function()
			error("cleanup failed on purpose")
		end)
		trove:Clean()
		capture:stop()
		expect(cleaned).toBe(true)
		expect(capture:find("error", "cleanup failed on purpose")).never.toBeNil()
	end)
end)
