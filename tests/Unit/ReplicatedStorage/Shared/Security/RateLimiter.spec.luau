local Test = require("@tests/Harness/Test")
local FakeClock = require("@tests/Harness/FakeClock")
local describe, it, expect = Test.describe, Test.it, Test.expect

local RateLimiter = require("@game/ReplicatedStorage/Shared/Security/RateLimiter")

local RATE = { perSecond = 2, burst = 3 }

describe("RateLimiter", function()
	it("allows a burst then throttles", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		local owner = {}
		for _ = 1, 3 do
			expect(limiter:consume(owner, "Fire", RATE)).toBe(true)
		end
		expect(limiter:consume(owner, "Fire", RATE)).toBe(false)
	end)

	it("refills continuously and caps at burst", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		local owner = {}
		for _ = 1, 3 do
			limiter:consume(owner, "Fire", RATE)
		end
		clock:advance(0.5)
		expect(limiter:consume(owner, "Fire", RATE)).toBe(true)
		expect(limiter:consume(owner, "Fire", RATE)).toBe(false)
		clock:advance(100)
		expect(limiter:remaining(owner, "Fire", RATE)).toBe(3)
	end)

	it("isolates owners and bucket names", function()
		local limiter = RateLimiter.new(FakeClock.new(0))
		local a, b = {}, {}
		for _ = 1, 3 do
			limiter:consume(a, "Fire", RATE)
		end
		expect(limiter:consume(a, "Fire", RATE)).toBe(false)
		expect(limiter:consume(b, "Fire", RATE)).toBe(true)
		expect(limiter:consume(a, "Chat", RATE)).toBe(true)
	end)

	it("supports costs", function()
		local limiter = RateLimiter.new(FakeClock.new(0))
		local owner = {}
		expect(limiter:consume(owner, "Buy", RATE, 3)).toBe(true)
		expect(limiter:consume(owner, "Buy", RATE, 1)).toBe(false)
	end)

	it("never mints tokens when the clock goes backwards", function()
		local clock = FakeClock.new(10)
		local limiter = RateLimiter.new(clock)
		local owner = {}
		for _ = 1, 3 do
			limiter:consume(owner, "Fire", RATE)
		end
		clock:set(0)
		expect(limiter:consume(owner, "Fire", RATE)).toBe(false)
		clock:set(10.5)
		expect(limiter:consume(owner, "Fire", RATE)).toBe(true)
	end)

	it("forget and prune drop state", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		local owner = {}
		for _ = 1, 3 do
			limiter:consume(owner, "Fire", RATE)
		end
		limiter:forget(owner)
		expect(limiter:consume(owner, "Fire", RATE)).toBe(true)
		limiter:consume({}, "Other", RATE)
		clock:advance(60)
		expect(limiter:prune(30)).toBe(2)
		expect(limiter:prune(30)).toBe(0)
	end)

	it("validates rates and clocks", function()
		local limiter = RateLimiter.new(FakeClock.new(0))
		expect(function()
			limiter:consume({}, "X", { perSecond = 1, burst = 0 })
		end).toThrow("invalid rate")
		expect(function()
			limiter:consume({}, "X", {} :: any)
		end).toThrow("rate must be")
		expect(function()
			RateLimiter.new(nil :: any)
		end).toThrow("Clock is required")
	end)
end)
