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

describe("Trove (adversarial)", function()
	it("Clean twice and Destroy twice are idempotent", function()
		local trove = Trove.new()
		local n = 0
		trove:Add(function()
			n += 1
		end)
		trove:Clean()
		trove:Clean()
		trove:Destroy()
		trove:Destroy()
		expect(n).toBe(1)
	end)

	it("a cleanup that re-enters Clean/Destroy does not double-clean or skip entries", function()
		local trove = Trove.new()
		local order = {}
		trove:Add(function()
			table.insert(order, "first-added")
		end)
		trove:Add(function()
			table.insert(order, "reenter")
			trove:Clean()
		end)
		trove:Add(function()
			table.insert(order, "last-added")
		end)
		trove:Clean()
		expect(order).toEqual({ "last-added", "reenter", "first-added" })
	end)

	it("entries added by a cleanup during Clean are cleaned in the same pass", function()
		local trove = Trove.new()
		local cleaned = {}
		trove:Add(function()
			table.insert(cleaned, "outer")
			trove:Add(function()
				table.insert(cleaned, "added-during-clean")
			end)
		end)
		trove:Clean()
		expect(cleaned).toEqual({ "outer", "added-during-clean" })
	end)

	it("Remove of an entry from inside another cleanup", function()
		local trove = Trove.new()
		local cleaned = {}
		local target = function()
			table.insert(cleaned, "target")
		end
		trove:Add(target)
		trove:Add(function()
			table.insert(cleaned, "remover")
			expect(trove:Remove(target)).toBe(true)
		end)
		trove:Clean()
		expect(cleaned).toEqual({ "remover", "target" })
		expect(trove:Remove(target)).toBe(false)
	end)

	it("Extend on a destroyed trove yields an already-destroyed child", function()
		local trove = Trove.new()
		trove:Destroy()
		local child = trove:Extend()
		local ran = false
		child:Add(function()
			ran = true
		end)
		expect(ran).toBe(true)
	end)

	it("Clean cancels a thread that is waiting and leaves dead threads alone", function()
		local trove = Trove.new()
		local waiting = task.spawn(function()
			task.wait(10)
		end)
		local dead = coroutine.create(function() end)
		coroutine.resume(dead)
		trove:Add(waiting)
		trove:Add(dead)
		trove:Clean()
		expect(coroutine.status(waiting)).toBe("dead")
	end)

	it("rejects explicit methods on values that cannot have methods", function()
		local trove = Trove.new()
		expect(function()
			trove:Add(42 :: any, "Destroy")
		end).toThrow("given for a number")
		expect(function()
			trove:Add({}, "Nope")
		end).toThrow('has no method "Nope"')
		expect(function()
			trove:Add(nil :: any)
		end).toThrow("nil")
	end)
end)
