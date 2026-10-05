local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local SAMPLES = 100000

local function meanAndVariance(samples: { number }): (number, number)
	local sum = 0
	for _, v in samples do
		sum += v
	end
	local mean = sum / #samples
	local sq = 0
	for _, v in samples do
		sq += (v - mean) ^ 2
	end
	return mean, sq / (#samples - 1)
end

describe("RNG (PCG32)", function()
	it("matches the PCG reference implementation bit-for-bit", function()
		-- pcg32-demo: pcg32_srandom_r(&rng, 42, 54)
		local rng = RNG.new(42)
		local expected = { 0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e }
		for _, value in expected do
			expect(rng:nextU32()).toBe(value)
		end
	end)

	it("matches reference vectors for edge seeds (computed with exact 64-bit integers)", function()
		local cases = {
			{ seed = 0, values = { 1203932051, 3113183783, 2101201694 } },
			{ seed = 2 ^ 53 - 1, values = { 2285046032, 1746973319, 2855516544 } },
			{ seed = -7, values = { 2824053522, 1685972468, 2122275554 } },
		}
		for _, case in cases do
			local rng = RNG.new(case.seed)
			for _, value in case.values do
				expect(rng:nextU32()).toBe(value)
			end
		end
	end)

	it("is deterministic per seed and differs across seeds and streams", function()
		local a, b, c = RNG.new(123), RNG.new(123), RNG.new(124)
		local d = RNG.new(123, 99)
		local sameAB, sameAC, sameAD = true, true, true
		for _ = 1, 100 do
			local va = a:nextU32()
			sameAB = sameAB and va == b:nextU32()
			sameAC = sameAC and va == c:nextU32()
			sameAD = sameAD and va == d:nextU32()
		end
		expect(sameAB).toBe(true)
		expect(sameAC).toBe(false)
		expect(sameAD).toBe(false)
	end)

	it("next() is uniform on [0, 1)", function()
		local rng = RNG.new(7)
		local samples = table.create(SAMPLES)
		local lo, hi = 1, 0
		for i = 1, SAMPLES do
			local v = rng:next()
			samples[i] = v
			lo = math.min(lo, v)
			hi = math.max(hi, v)
		end
		local mean, variance = meanAndVariance(samples)
		expect(lo).toBeGreaterThanOrEqual(0)
		expect(hi).toBeLessThan(1)
		expect(mean).toBeCloseTo(0.5, 0.005)
		expect(variance).toBeCloseTo(1 / 12, 0.002)
	end)

	it("range() maps to [min, max)", function()
		local rng = RNG.new(8)
		local lo, hi = math.huge, -math.huge
		for _ = 1, 1000 do
			local v = rng:range(-5, 5)
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		expect(lo).toBeGreaterThanOrEqual(-5)
		expect(hi).toBeLessThan(5)
	end)

	it("int() is inclusive and unbiased", function()
		local rng = RNG.new(9)
		local counts = { 0, 0, 0, 0, 0, 0 }
		for _ = 1, 60000 do
			local v = rng:int(1, 6)
			counts[v] += 1
		end
		for face = 1, 6 do
			expect(counts[face]).toBeGreaterThan(9500)
			expect(counts[face]).toBeLessThan(10500)
		end
		expect(rng:int(5, 5)).toBe(5)
		local big = rng:int(0, 2 ^ 32 - 1)
		expect(big >= 0 and big < 2 ^ 32).toBe(true)
		expect(rng:int(-10, -10)).toBe(-10)
	end)

	it("int() rejects invalid bounds", function()
		local rng = RNG.new(1)
		expect(function()
			rng:int(1.5, 3)
		end).toThrow("integers")
		expect(function()
			rng:int(3, 1)
		end).toThrow("max")
		expect(function()
			rng:int(0, 2 ^ 32)
		end).toThrow("2^32")
	end)

	it("normal() has the requested mean and standard deviation", function()
		local rng = RNG.new(10)
		local samples = table.create(SAMPLES)
		for i = 1, SAMPLES do
			samples[i] = rng:normal(5, 2)
		end
		local mean, variance = meanAndVariance(samples)
		expect(mean).toBeCloseTo(5, 0.03)
		expect(math.sqrt(variance)).toBeCloseTo(2, 0.03)
	end)

	it("truncatedNormal() stays within limitSigma and narrows the spread", function()
		local rng = RNG.new(11)
		local samples = table.create(SAMPLES)
		local worst = 0
		for i = 1, SAMPLES do
			local v = rng:truncatedNormal(0, 1, 2)
			worst = math.max(worst, math.abs(v))
			samples[i] = v
		end
		expect(worst).toBeLessThanOrEqual(2)
		local mean, variance = meanAndVariance(samples)
		expect(mean).toBeCloseTo(0, 0.02)
		-- Variance of a standard normal truncated at +/-2 sigma is ~0.774.
		expect(variance).toBeCloseTo(0.774, 0.02)
	end)

	it("truncatedNormal() handles degenerate limits", function()
		local rng = RNG.new(12)
		expect(rng:truncatedNormal(3, 1, 0)).toBe(3)
		expect(rng:truncatedNormal(3, 0, 2)).toBe(3)
		for _ = 1, 200 do
			local v = rng:truncatedNormal(0, 1, 0.001)
			expect(math.abs(v) <= 0.001).toBe(true)
		end
	end)

	it("chance() matches the probability and always consumes one draw", function()
		local rng = RNG.new(13)
		local hits = 0
		for _ = 1, SAMPLES do
			if rng:chance(0.25) then
				hits += 1
			end
		end
		expect(hits / SAMPLES).toBeCloseTo(0.25, 0.01)
		local a, b = RNG.new(5), RNG.new(5)
		a:chance(0)
		b:chance(1)
		expect(a:nextU32()).toBe(b:nextU32())
	end)

	it("pick() covers every element and rejects empty lists", function()
		local rng = RNG.new(14)
		local seen = {}
		for _ = 1, 200 do
			seen[rng:pick({ "a", "b", "c" })] = true
		end
		expect(seen).toEqual({ a = true, b = true, c = true })
		expect(function()
			rng:pick({})
		end).toThrow("empty")
	end)

	it("shuffle() is a deterministic permutation", function()
		local list1 = { 1, 2, 3, 4, 5, 6, 7, 8 }
		local list2 = table.clone(list1)
		RNG.new(15):shuffle(list1)
		RNG.new(15):shuffle(list2)
		expect(list1).toEqual(list2)
		local sorted = table.clone(list1)
		table.sort(sorted)
		expect(sorted).toEqual({ 1, 2, 3, 4, 5, 6, 7, 8 })
	end)

	it("fork() is deterministic, salt-dependent and does not advance the parent", function()
		local parent = RNG.new(16)
		local reference = RNG.new(16)
		local f1 = parent:fork(1)
		local f1again = parent:fork(1)
		local f2 = parent:fork(2)
		expect(parent:nextU32()).toBe(reference:nextU32())
		local v1 = f1:nextU32()
		expect(f1again:nextU32()).toBe(v1)
		expect(f2:nextU32()).never.toBe(v1)
	end)

	it("hash() is stable, ordered and type-aware", function()
		expect(RNG.hash(1, "a")).toBe(2670412485)
		expect(RNG.hash("a", 1)).toBe(2262527150)
		expect(RNG.hash(0)).toBe(RNG.hash(-0))
		expect(RNG.hash("1")).never.toBe(RNG.hash(1))
		expect(RNG.hash("ab", "c")).never.toBe(RNG.hash("a", "bc"))
		local h = RNG.hash("match-123")
		expect(h >= 0 and h < 2 ^ 32 and h == math.floor(h)).toBe(true)
	end)

	it("getState/fromState round-trips", function()
		local a = RNG.new(17)
		a:nextU32()
		local b = RNG.fromState(a:getState())
		for _ = 1, 10 do
			expect(b:nextU32()).toBe(a:nextU32())
		end
	end)

	it("rejects non-finite seeds", function()
		expect(function()
			RNG.new(0 / 0)
		end).toThrow("finite")
		expect(function()
			RNG.new(math.huge)
		end).toThrow("finite")
	end)
end)
