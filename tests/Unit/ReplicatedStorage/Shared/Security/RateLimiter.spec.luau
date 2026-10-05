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

describe("RateLimiter (adversarial)", function()
	it("a burst exactly drains the bucket; refill is continuous and fractional", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		local rate = { perSecond = 4, burst = 2 }
		expect(limiter:consume("p", "r", rate)).toBe(true)
		expect(limiter:consume("p", "r", rate)).toBe(true)
		expect(limiter:consume("p", "r", rate)).toBe(false)
		clock:advance(0.2) -- 0.8 tokens: not enough
		expect(limiter:consume("p", "r", rate)).toBe(false)
		clock:advance(0.05) -- 1.0 token
		expect(limiter:consume("p", "r", rate)).toBe(true)
		expect(limiter:consume("p", "r", rate)).toBe(false)
	end)

	it("a spammer gains nothing by being throttled: rejected calls do not consume or delay refill", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		local rate = { perSecond = 10, burst = 10 }
		local allowed = 0
		for _ = 1, 1000 do -- 1000 calls over 10 s (100/s against a 10/s limit)
			if limiter:consume("p", "r", rate) then
				allowed += 1
			end
			clock:advance(0.01)
		end
		-- burst (10) + 10 s * 10/s refill (100), give or take one boundary token.
		expect(allowed >= 109 and allowed <= 111).toBe(true)
	end)

	it("a cost above burst can never pass; zero perSecond never refills", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		expect(limiter:consume("p", "big", { perSecond = 100, burst = 5 }, 6)).toBe(false)
		clock:advance(1000)
		expect(limiter:consume("p", "big", { perSecond = 100, burst = 5 }, 6)).toBe(false)
		local once = { perSecond = 0, burst = 1 }
		expect(limiter:consume("p", "once", once)).toBe(true)
		clock:advance(1e6)
		expect(limiter:consume("p", "once", once)).toBe(false)
	end)

	it("buckets never exceed burst after long idle periods or huge clock jumps", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		local rate = { perSecond = 1000, burst = 3 }
		limiter:consume("p", "r", rate)
		clock:advance(1e9)
		expect(limiter:remaining("p", "r", rate)).toBe(3)
	end)

	it("rejects NaN/negative rates on first use (fails closed)", function()
		local limiter = RateLimiter.new(FakeClock.new(0))
		expect(function()
			limiter:consume("p", "nan", { perSecond = 0 / 0, burst = 1 })
		end).toThrow("invalid rate")
		expect(function()
			limiter:consume("p", "neg", { perSecond = -1, burst = 1 })
		end).toThrow("invalid rate")
		expect(function()
			limiter:consume("p", "zero", { perSecond = 1, burst = 0 })
		end).toThrow("invalid rate")
	end)

	it("forgotten owners start again with a full bucket; prune keeps active buckets", function()
		local clock = FakeClock.new(0)
		local limiter = RateLimiter.new(clock)
		local rate = { perSecond = 1, burst = 1 }
		limiter:consume("a", "r", rate)
		limiter:consume("b", "r", rate)
		expect(limiter:consume("a", "r", rate)).toBe(false)
		limiter:forget("a")
		expect(limiter:consume("a", "r", rate)).toBe(true)
		clock:advance(5)
		limiter:consume("b", "r", rate)
		expect(limiter:prune(5)).toBe(1) -- "a" idle for 5 s; "b" just used
		expect(limiter:remaining("b", "r", rate)).toBe(0)
	end)
end)
