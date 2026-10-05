--!strict
--[[
	RNG — deterministic PCG32 random number generator (bit-identical in Roblox and Lune).

	Purpose:          Seeded randomness for simulation (shell dispersion, damage rolls, bots, matchmaking ties).
	Dependencies:     None (bit32 + float arithmetic only).
	State:            64-bit state and 64-bit odd increment, each stored as two 32-bit halves (hi, lo).
	Validation:       Seeds must be finite numbers; int() bounds must be integers with max - min + 1 <= 2^32;
	                  pick() rejects empty lists.
	Error handling:   Invalid arguments raise errors (programming mistakes).
	Performance notes: nextU32 costs ~20 arithmetic/bit32 ops and never allocates.

	Algorithm (O'Neill, PCG-XSH-RR 64/32 — reference pcg32_random_r / pcg32_srandom_r):
	  step:   state = state * 6364136223846793005 + inc   (mod 2^64)
	  output: xorshifted = ((old >> 18) ^ old) >> 27 (low 32 bits); rot = old >> 59; return rotr32(xorshifted, rot)
	  seed:   state = 0; inc = (stream << 1) | 1; step(); state += seed; step()
	Exactness: Luau numbers are IEEE doubles (53-bit mantissa). 64-bit values are kept as two 32-bit halves and
	the 64x64 multiply is decomposed into 16-bit limb products (each < 2^32, partial sums < 2^50), so every
	intermediate is an exactly representable integer. Results therefore match the C reference bit-for-bit
	(RNG.new(42) with the default stream 54 yields 0xa15c02b7, 0x7b47f409, 0xba1d3330, ... as in pcg32-demo).
	Integer-derived APIs (nextU32, int, chance, pick, shuffle, fork, hash) are bit-exact everywhere; float transforms
	(normal, truncatedNormal) use math.log/cos/sqrt and are deterministic per platform libm.
]]

local TWO16 = 65536
local TWO32 = 4294967296
local INV_TWO32 = 1 / 4294967296
local DEFAULT_STREAM = 54

local MUL_HI = 0x5851F42D
local MUL_LO = 0x4C957F2D

-- (a * b) mod 2^32 for a, b in [0, 2^32).
local function mul32(a: number, b: number): number
	local aHi = a // TWO16
	local aLo = a % TWO16
	local hiPart = (aHi * b) % TWO16
	return (hiPart * TWO16 + aLo * b) % TWO32
end

-- Full 64-bit product of two 32-bit values as (hi, lo).
local function mul32x32(a: number, b: number): (number, number)
	local a1, a0 = a // TWO16, a % TWO16
	local b1, b0 = b // TWO16, b % TWO16
	local p00 = a0 * b0
	local mid = a0 * b1 + a1 * b0 + p00 // TWO16
	local lo = p00 % TWO16 + (mid % TWO16) * TWO16
	local hi = a1 * b1 + mid // TWO16
	return hi, lo
end

-- Splits a finite number into a 64-bit two's complement (hi, lo) pair after flooring.
local function split64(n: number): (number, number)
	local f = math.floor(n)
	return (f // TWO32) % TWO32, f % TWO32
end

type RNGState = {
	_hi: number,
	_lo: number,
	_incHi: number,
	_incLo: number,
}

local RNGClass = {}
RNGClass.__index = RNGClass

export type RNG = typeof(setmetatable({} :: RNGState, RNGClass))

local function step(self: RNG)
	local sh, sl = self._hi, self._lo
	local ph, pl = mul32x32(sl, MUL_LO)
	ph = (ph + mul32(sh, MUL_LO) + mul32(sl, MUL_HI)) % TWO32
	local lo = pl + self._incLo
	local carry = lo // TWO32
	self._lo = lo % TWO32
	self._hi = (ph + self._incHi + carry) % TWO32
end

local function output(oldHi: number, oldLo: number): number
	local xHi = bit32.rshift(oldHi, 18)
	local xLo = bit32.bor(bit32.rshift(oldLo, 18), bit32.lshift(oldHi, 14))
	local yHi = bit32.bxor(xHi, oldHi)
	local yLo = bit32.bxor(xLo, oldLo)
	local xorshifted = bit32.bor(bit32.rshift(yLo, 27), bit32.lshift(yHi, 5))
	local rot = bit32.rshift(oldHi, 27)
	return bit32.rrotate(xorshifted, rot)
end

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

local function fnvByte(h: number, byte: number): number
	return mul32(bit32.bxor(h, byte), FNV_PRIME)
end

local function fnvString(h: number, s: string): number
	for i = 1, #s do
		h = fnvByte(h, string.byte(s, i))
	end
	return h
end

local function fmix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

-- Stable 32-bit hash of numbers/strings (FNV-1a over a typed canonical encoding + murmur3 finalizer).
local function hashValues(...: number | string): number
	local h = FNV_OFFSET
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "number" then
			local n = v
			if n ~= n then
				-- NaN bit patterns differ by CPU (x86 0/0 is negative, ARM's is positive): hash a fixed tag instead.
				h = fnvByte(h, 3)
				continue
			elseif n == 0 then
				n = 0 -- -0 and 0 hash alike
			end
			h = fnvByte(h, 1)
			h = fnvString(h, string.pack("<d", n))
		elseif type(v) == "string" then
			h = fnvByte(h, 2)
			h = fnvString(h, string.pack("<I4", #v))
			h = fnvString(h, v)
		else
			error(`RNG.hash: arguments must be numbers or strings, got {typeof(v)}`, 3)
		end
	end
	return fmix32(h)
end

local function assertFinite(n: number, what: string)
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		error(`RNG: {what} must be a finite number, got {tostring(n)}`, 3)
	end
end

local function create(seedHi: number, seedLo: number, streamHi: number, streamLo: number): RNG
	local self: RNG = setmetatable(
		{
			_hi = 0,
			_lo = 0,
			_incHi = bit32.bor(bit32.lshift(streamHi, 1), bit32.rshift(streamLo, 31)),
			_incLo = bit32.bor(bit32.lshift(streamLo, 1), 1),
		} :: RNGState,
		RNGClass
	)
	step(self)
	local lo = self._lo + seedLo
	local carry = lo // TWO32
	self._lo = lo % TWO32
	self._hi = (self._hi + seedHi + carry) % TWO32
	step(self)
	return self
end

--- Next uniformly distributed integer in [0, 2^32).
function RNGClass.nextU32(self: RNG): number
	local oldHi, oldLo = self._hi, self._lo
	step(self)
	return output(oldHi, oldLo)
end

--- Uniform float in [0, 1) with 32 bits of resolution.
function RNGClass.next(self: RNG): number
	return RNGClass.nextU32(self) * INV_TWO32
end

--- Uniform float in [min, max).
function RNGClass.range(self: RNG, min: number, max: number): number
	return min + (max - min) * RNGClass.next(self)
end

--- Uniform integer in [min, max] (inclusive) without modulo bias (rejection sampling).
function RNGClass.int(self: RNG, min: number, max: number): number
	if min ~= math.floor(min) or max ~= math.floor(max) then
		error(`RNG:int bounds must be integers, got {min}, {max}`, 2)
	end
	if max < min then
		error(`RNG:int max ({max}) < min ({min})`, 2)
	end
	local span = max - min + 1
	if span > TWO32 then
		error("RNG:int range exceeds 2^32", 2)
	end
	local threshold = (TWO32 - span) % span
	while true do
		local r = RNGClass.nextU32(self)
		if r >= threshold then
			return min + r % span
		end
	end
end

--- Normally distributed float (Box-Muller, one draw per call; consumes two u32).
function RNGClass.normal(self: RNG, mean: number, stddev: number): number
	local u1 = (RNGClass.nextU32(self) + 1) * INV_TWO32 -- (0, 1]
	local u2 = RNGClass.next(self)
	local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	return mean + stddev * z
end

--- Normal sample restricted to mean +/- limitSigma * stddev (rejection; uniform fallback for tiny limits).
function RNGClass.truncatedNormal(self: RNG, mean: number, stddev: number, limitSigma: number): number
	if limitSigma <= 0 or stddev == 0 then
		return mean
	end
	for _ = 1, 32 do
		local u1 = (RNGClass.nextU32(self) + 1) * INV_TWO32
		local u2 = RNGClass.next(self)
		local z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
		if math.abs(z) <= limitSigma then
			return mean + stddev * z
		end
	end
	-- Only reachable for very small limitSigma, where the truncated normal is ~uniform.
	return mean + stddev * (RNGClass.next(self) * 2 - 1) * limitSigma
end

--- True with probability p (always consumes exactly one draw).
function RNGClass.chance(self: RNG, p: number): boolean
	return RNGClass.next(self) < p
end

--- Uniformly chosen element of a non-empty array.
function RNGClass.pick<T>(self: RNG, list: { T }): T
	local n = #list
	if n == 0 then
		error("RNG:pick on an empty list", 2)
	end
	return list[RNGClass.int(self, 1, n)]
end

--- In-place Fisher-Yates shuffle.
function RNGClass.shuffle<T>(self: RNG, list: { T })
	for i = #list, 2, -1 do
		local j = RNGClass.int(self, 1, i)
		list[i], list[j] = list[j], list[i]
	end
end

--- Independent child generator derived from the current state and `salt` (does NOT advance this RNG).
function RNGClass.fork(self: RNG, salt: number): RNG
	assertFinite(salt, "fork salt")
	local seedHi = hashValues(self._hi, self._lo, salt, 1)
	local seedLo = hashValues(self._lo, self._incLo, salt, 2)
	local streamHi = hashValues(self._incHi, salt, 3)
	local streamLo = hashValues(self._incLo, salt, 4)
	return create(seedHi, seedLo, streamHi, streamLo)
end

--- Snapshot of the generator state (four u32) for replays/debugging.
function RNGClass.getState(self: RNG): { number }
	return { self._hi, self._lo, self._incHi, self._incLo }
end

local RNG = {}

--- Stable 32-bit hash of numbers/strings for seeding (e.g. RNG.new(RNG.hash(matchId, "spotting"))).
function RNG.hash(...: number | string): number
	return hashValues(...)
end

--- Creates a generator. `seed` is any finite number (floored, 64-bit two's complement); `stream` selects one of
--- 2^63 independent sequences (default 54, matching the PCG reference demo).
function RNG.new(seed: number, stream: number?): RNG
	assertFinite(seed, "seed")
	local streamValue = stream or DEFAULT_STREAM
	assertFinite(streamValue, "stream")
	local seedHi, seedLo = split64(seed)
	local streamHi, streamLo = split64(streamValue)
	return create(seedHi, seedLo, streamHi, streamLo)
end

--- Restores a generator from getState() output.
function RNG.fromState(state: { number }): RNG
	assert(#state == 4, "RNG.fromState: expected 4 numbers")
	local restored: RNG = setmetatable(
		{
			_hi = state[1] % TWO32,
			_lo = state[2] % TWO32,
			_incHi = state[3] % TWO32,
			_incLo = bit32.bor(state[4] % TWO32, 1),
		} :: RNGState,
		RNGClass
	)
	return restored
end

return RNG
