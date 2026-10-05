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

describe("Signal (adversarial reentrancy)", function()
	it("a handler disconnecting a later handler and connecting a new one in the same Fire", function()
		local s = Signal.new()
		local calls = {}
		local cB
		s:Connect(function()
			table.insert(calls, "A")
			cB:Disconnect()
			s:Connect(function()
				table.insert(calls, "C")
			end)
		end)
		cB = s:Connect(function()
			table.insert(calls, "B")
		end)
		s:Fire()
		expect(calls).toEqual({ "A" })
		s:Fire()
		-- B stays disconnected; A runs again (connecting another C), the first C runs.
		expect(calls).toEqual({ "A", "A", "C" })
	end)

	it("nested Fire from a handler sees connections made by the outer Fire only from its own start", function()
		local s = Signal.new()
		local log = {}
		local depth = 0
		s:Connect(function(n)
			depth += 1
			table.insert(log, "h1:" .. n)
			if n == 1 then
				s:Connect(function(m)
					table.insert(log, "late:" .. m)
				end)
				s:Fire(2) -- nested: the late handler exists when this Fire starts
			end
			depth -= 1
		end)
		s:Fire(1)
		expect(log).toEqual({ "h1:1", "h1:2", "late:2" })
		expect(depth).toBe(0)
	end)

	it("Once handlers fire once even when the signal is fired again from inside them", function()
		local s = Signal.new()
		local count = 0
		s:Once(function()
			count += 1
			s:Fire()
		end)
		s:Fire()
		s:Fire()
		expect(count).toBe(1)
	end)

	it("DisconnectAll inside a nested Fire stops the outer iteration too", function()
		local s = Signal.new()
		local calls = {}
		s:Connect(function(n)
			table.insert(calls, "a" .. n)
			if n == 1 then
				s:Fire(2)
			else
				s:DisconnectAll()
			end
		end)
		s:Connect(function(n)
			table.insert(calls, "b" .. n)
		end)
		s:Fire(1)
		expect(calls).toEqual({ "a1", "a2" })
		s:Fire(3)
		expect(calls).toEqual({ "a1", "a2" })
	end)

	it("Disconnect after DisconnectAll and Destroy are harmless; Connected reflects state", function()
		local s = Signal.new()
		local c = s:Connect(function() end)
		s:DisconnectAll()
		expect(c.Connected).toBe(false)
		c:Disconnect()
		s:Destroy()
		local c2 = s:Connect(function() end)
		expect(c2.Connected).toBe(true)
	end)

	it("Wait returns every fired value including nils and holes", function()
		local s = Signal.new()
		local packed
		local co = coroutine.create(function()
			packed = table.pack(s:Wait())
		end)
		coroutine.resume(co)
		s:Fire(nil, 2, nil)
		expect(packed.n).toBe(3)
		expect(packed[1]).toBeNil()
		expect(packed[2]).toBe(2)
		expect(packed[3]).toBeNil()
	end)

	it("several waiters resume in order on one Fire and never on the following ones", function()
		local s = Signal.new()
		local resumed = {}
		for i = 1, 3 do
			coroutine.resume(coroutine.create(function()
				local v = s:Wait()
				table.insert(resumed, i .. ":" .. v)
			end))
		end
		s:Fire("x")
		s:Fire("y")
		expect(resumed).toEqual({ "1:x", "2:x", "3:x" })
	end)

	it("a waiter that errors after resuming is logged and does not break other handlers", function()
		local capture = LogCapture.start()
		local s = Signal.new()
		local after = false
		coroutine.resume(coroutine.create(function()
			s:Wait()
			error("waiter blew up")
		end))
		s:Connect(function()
			after = true
		end)
		s:Fire()
		capture:stop()
		expect(after).toBe(true)
		expect(capture:find("error", "waiter blew up")).never.toBeNil()
	end)

	it("Fire with no connections and many connect/disconnect cycles keeps the list compact", function()
		local s = Signal.new()
		s:Fire(1, 2, 3)
		for _ = 1, 1000 do
			local c = s:Connect(function() end)
			c:Disconnect()
		end
		expect(#(s :: any)._connections).toBe(0)
	end)
end)
