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

-- Independent PCG32 reference using four 16-bit limbs (little-endian) and schoolbook multiplication, so every
-- intermediate stays far below 2^53. Seeds follow the module contract: floor(seed) mod 2^64.
local Reference = {}

local MUL_LIMBS = { 0x7F2D, 0x4C95, 0xF42D, 0x5851 } -- 6364136223846793005

local function toLimbs(n: number): { number }
	local v = math.floor(n)
	return { v % 65536, (v // 65536) % 65536, (v // 4294967296) % 65536, (v // 281474976710656) % 65536 }
end

local function mulLimbs(a: { number }, b: { number }): { number }
	local out = { 0, 0, 0, 0 }
	for i = 1, 4 do
		local carry = 0
		for j = 1, 5 - i do
			local k = i + j - 1
			local cur = out[k] + a[i] * b[j] + carry
			out[k] = cur % 65536
			carry = cur // 65536
		end
	end
	return out
end

local function addLimbs(a: { number }, b: { number }): { number }
	local out, carry = {}, 0
	for i = 1, 4 do
		local cur = a[i] + b[i] + carry
		out[i] = cur % 65536
		carry = cur // 65536
	end
	return out
end

local function shr(a: { number }, bits: number): { number }
	-- Shift right by `bits` (< 64): whole limbs first, then the remaining 0..15 bits across limb boundaries.
	local q, r = bits // 16, bits % 16
	local out = {}
	for i = 1, 4 do
		local lo = a[i + q] or 0
		local hi = a[i + q + 1] or 0
		out[i] = bit32.band(bit32.bor(bit32.rshift(lo, r), bit32.lshift(hi, 16 - r)), 0xFFFF)
	end
	return out
end

function Reference.new(seed: number, stream: number?)
	local inc = addLimbs(mulLimbs(toLimbs(stream or 54), { 2, 0, 0, 0 }), { 1, 0, 0, 0 })
	local self = { state = { 0, 0, 0, 0 }, inc = inc }
	local function step()
		self.state = addLimbs(mulLimbs(self.state, MUL_LIMBS), self.inc)
	end
	step()
	self.state = addLimbs(self.state, toLimbs(seed))
	step()
	function self.nextU32(): number
		local old = self.state
		step()
		local x = shr(old, 18)
		local mixed = {}
		for i = 1, 4 do
			mixed[i] = bit32.bxor(x[i], old[i])
		end
		local shifted = shr(mixed, 27)
		local xorshifted = shifted[1] + shifted[2] * 65536
		local rot = shr(old, 59)[1]
		return bit32.rrotate(xorshifted, rot)
	end
	return self
end

describe("RNG (adversarial determinism)", function()
	it("matches an independent limb-arithmetic PCG32 for edge, negative, fractional and huge seeds", function()
		local seeds = {
			0,
			1,
			-1,
			42,
			-7,
			0.999,
			-0.5,
			2 ^ 31,
			2 ^ 32 - 1,
			2 ^ 32,
			2 ^ 53 - 1,
			-(2 ^ 53),
			2 ^ 63,
			-(2 ^ 63),
			2 ^ 64 + 2 ^ 12,
			1e300,
			-1e300,
			123456789.75,
		}
		local seedRng = RNG.new(2024)
		for _ = 1, 30 do
			table.insert(seeds, seedRng:int(-2 ^ 31, 2 ^ 31 - 1) * 2 ^ seedRng:int(0, 30))
		end
		for _, seed in seeds do
			for _, stream in { 54, 0, 7, -3 } do
				local rng, ref = RNG.new(seed, stream), Reference.new(seed, stream)
				for i = 1, 12 do
					local got, want = rng:nextU32(), ref.nextU32()
					if got ~= want then
						error(`seed {seed} stream {stream} draw {i}: got {got}, reference {want}`, 0)
					end
				end
			end
		end
	end)

	it("seeds are floored: 1.9 and 1 give the same sequence, -0.5 and -1 too", function()
		local a, b = RNG.new(1.9), RNG.new(1)
		local c, d = RNG.new(-0.5), RNG.new(-1)
		for _ = 1, 10 do
			expect(a:nextU32()).toBe(b:nextU32())
			expect(c:nextU32()).toBe(d:nextU32())
		end
	end)

	it(
		"truncatedNormal never exceeds mean +/- limitSigma * |stddev| (incl. tiny limits and negative stddev)",
		function()
			local rng = RNG.new(77)
			for _, case in
				{
					{ mean = 0, sd = 1, limit = 0.001 },
					{ mean = 0, sd = 1, limit = 0.5 },
					{ mean = 10, sd = 3, limit = 1 },
					{ mean = -5, sd = 2, limit = 3 },
					{ mean = 0, sd = -2, limit = 2 },
					{ mean = 100, sd = 0.01, limit = 4 },
				}
			do
				local bound = case.limit * math.abs(case.sd) + 1e-9
				-- Tiny limits reject almost every Box-Muller draw (32 tries each), so they get fewer samples.
				local samples = if case.limit < 0.01 then 500 else 5000
				for _ = 1, samples do
					local v = rng:truncatedNormal(case.mean, case.sd, case.limit)
					if math.abs(v - case.mean) > bound or v ~= v then
						error(`truncatedNormal({case.mean}, {case.sd}, {case.limit}) produced {v}`, 0)
					end
				end
			end
		end
	)

	it("int() handles the full 2^32 span and single-value ranges", function()
		local rng = RNG.new(5)
		for _ = 1, 1000 do
			local v = rng:int(-2 ^ 31, 2 ^ 31 - 1)
			expect(v >= -2 ^ 31 and v <= 2 ^ 31 - 1 and v == math.floor(v)).toBe(true)
			expect(rng:int(9, 9)).toBe(9)
		end
		expect(function()
			rng:int(0, 2 ^ 32)
		end).toThrow("exceeds 2^32")
	end)

	it("fork children are independent of each other and reproducible from restored state", function()
		local parent = RNG.new(99)
		parent:nextU32()
		local state = parent:getState()
		local childA = parent:fork(1)
		local restored = RNG.fromState(state)
		local childB = restored:fork(1)
		for _ = 1, 20 do
			expect(childA:nextU32()).toBe(childB:nextU32())
		end
		expect(parent:nextU32()).toBe(restored:nextU32())
	end)

	it("rejects non-finite fork salts and stream values", function()
		local rng = RNG.new(1)
		expect(function()
			rng:fork(0 / 0)
		end).toThrow("finite")
		expect(function()
			RNG.new(1, math.huge)
		end).toThrow("finite")
	end)
end)
