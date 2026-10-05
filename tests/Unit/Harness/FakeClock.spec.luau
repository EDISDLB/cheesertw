local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local FakeClock = require("@tests/Harness/FakeClock")

describe("FakeClock", function()
	it("advances and fires timers in due order at their due time", function()
		local clock = FakeClock.new(100)
		local fired = {}
		clock:schedule(2, function()
			table.insert(fired, { "b", clock:now() })
		end)
		clock:schedule(1, function()
			table.insert(fired, { "a", clock:now() })
		end)
		clock:schedule(1, function()
			table.insert(fired, { "a2", clock:now() })
		end)
		clock:advance(1.5)
		expect(fired).toEqual({ { "a", 101 }, { "a2", 101 } })
		expect(clock:now()).toBe(101.5)
		clock:advance(10)
		expect(fired[3]).toEqual({ "b", 102 })
		expect(clock:pending()).toBe(0)
	end)

	it("timers scheduled by timers run when due", function()
		local clock = FakeClock.new(0)
		local count = 0
		local function tick()
			count += 1
			clock:schedule(1, tick)
		end
		clock:schedule(1, tick)
		clock:advance(5)
		expect(count).toBe(5)
	end)

	it("cancels timers and set() moves time", function()
		local clock = FakeClock.new(0)
		local fired = false
		local id = clock:schedule(1, function()
			fired = true
		end)
		expect(clock:cancel(id)).toBe(true)
		expect(clock:cancel(id)).toBe(false)
		clock:set(10)
		expect(fired).toBe(false)
		clock:set(5)
		expect(clock:now()).toBe(5)
		expect(function()
			clock:advance(-1)
		end).toThrow("dt must be >= 0")
	end)
end)
