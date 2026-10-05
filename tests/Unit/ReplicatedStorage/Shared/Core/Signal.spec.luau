local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

describe("Signal", function()
	it("calls handlers synchronously in connection order with arguments", function()
		local s = Signal.new()
		local order = {}
		s:Connect(function(a, b)
			table.insert(order, "first:" .. a .. b)
		end)
		s:Connect(function(a, b)
			table.insert(order, "second:" .. a .. b)
		end)
		s:Fire("x", "y")
		expect(order).toEqual({ "first:xy", "second:xy" })
	end)

	it("passes nil and multiple values through", function()
		local s = Signal.new()
		local got
		s:Connect(function(...)
			got = table.pack(...)
		end)
		s:Fire(1, nil, 3)
		expect(got.n).toBe(3)
		expect(got[3]).toBe(3)
	end)

	it("Once fires exactly once", function()
		local s = Signal.new()
		local count = 0
		local connection = s:Once(function()
			count += 1
		end)
		s:Fire()
		s:Fire()
		expect(count).toBe(1)
		expect(connection.Connected).toBe(false)
	end)

	it("Disconnect stops delivery and is idempotent", function()
		local s = Signal.new()
		local count = 0
		local c = s:Connect(function()
			count += 1
		end)
		s:Fire()
		c:Disconnect()
		c:Disconnect()
		s:Fire()
		expect(count).toBe(1)
		expect(c.Connected).toBe(false)
	end)

	it("a handler disconnected during Fire by an earlier handler is not called", function()
		local s = Signal.new()
		local calls = {}
		local second
		s:Connect(function()
			table.insert(calls, "first")
			second:Disconnect()
		end)
		second = s:Connect(function()
			table.insert(calls, "second")
		end)
		s:Connect(function()
			table.insert(calls, "third")
		end)
		s:Fire()
		expect(calls).toEqual({ "first", "third" })
		s:Fire()
		expect(calls).toEqual({ "first", "third", "first", "third" })
	end)

	it("a handler disconnecting itself does not skip the next handler", function()
		local s = Signal.new()
		local calls = {}
		local selfConn
		selfConn = s:Connect(function()
			table.insert(calls, "self")
			selfConn:Disconnect()
		end)
		s:Connect(function()
			table.insert(calls, "next")
		end)
		s:Fire()
		s:Fire()
		expect(calls).toEqual({ "self", "next", "next" })
	end)

	it("handlers connected during Fire run from the next Fire", function()
		local s = Signal.new()
		local calls = {}
		local added = false
		s:Connect(function()
			table.insert(calls, "outer")
			if not added then
				added = true
				s:Connect(function()
					table.insert(calls, "late")
				end)
			end
		end)
		s:Fire()
		expect(calls).toEqual({ "outer" })
		s:Fire()
		expect(calls).toEqual({ "outer", "outer", "late" })
	end)

	it("supports nested Fire", function()
		local s = Signal.new()
		local depth = {}
		s:Connect(function(n)
			table.insert(depth, n)
			if n < 3 then
				s:Fire(n + 1)
			end
		end)
		s:Fire(1)
		expect(depth).toEqual({ 1, 2, 3 })
	end)

	it("DisconnectAll disconnects every connection, even during Fire", function()
		local s = Signal.new()
		local calls = 0
		local c1 = s:Connect(function()
			calls += 1
			s:DisconnectAll()
		end)
		local c2 = s:Connect(function()
			calls += 1
		end)
		s:Fire()
		expect(calls).toBe(1)
		expect(c1.Connected).toBe(false)
		expect(c2.Connected).toBe(false)
		s:Fire()
		expect(calls).toBe(1)
	end)

	it("a failing handler is logged and does not stop the others", function()
		local capture = LogCapture.start()
		local s = Signal.new()
		local reached = false
		s:Connect(function()
			error("handler boom")
		end)
		s:Connect(function()
			reached = true
		end)
		s:Fire()
		capture:stop()
		expect(reached).toBe(true)
		expect(capture:find("error", "handler boom")).never.toBeNil()
	end)

	it("Wait suspends the coroutine until the next Fire", function()
		local s = Signal.new()
		local result
		local co = coroutine.create(function()
			result = table.pack(s:Wait())
		end)
		coroutine.resume(co)
		expect(coroutine.status(co)).toBe("suspended")
		s:Fire("a", 2)
		expect(coroutine.status(co)).toBe("dead")
		expect(result[1]).toBe("a")
		expect(result[2]).toBe(2)
	end)

	it("rejects non-function handlers and identifies signals", function()
		local s = Signal.new()
		expect(function()
			s:Connect(nil :: any)
		end).toThrow("expects a function")
		expect(Signal.is(s)).toBe(true)
		expect(Signal.is({})).toBe(false)
	end)
end)
