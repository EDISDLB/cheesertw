--!strict
--[[
	RateLimiter — token buckets keyed by (owner, bucket name), e.g. (player, remote name).

	Purpose:          NetServer throttles every C2S remote per player; services can throttle anything else.
	Dependencies:     Types/Core (Clock), Types/Net (RateSpec).
	State:            owner -> bucketName -> { tokens, last }. Owners are weak keys so departed Players can be
	                  collected even if forget() was missed.
	Validation:       Rate specs must have perSecond >= 0 and burst >= 1 (checked on first use of a bucket).
	Error handling:   A clock that goes backwards is treated as zero elapsed time (never mints tokens).
	Performance notes: O(1) per consume; buckets are created lazily; prune() drops idle full buckets.

	Semantics: a bucket starts full (`burst` tokens), refills continuously at `perSecond`, and each call consumes
	`cost` tokens (default 1) when available.
]]

local CoreTypes = require("../Types/Core")
local NetTypes = require("../Types/Net")

type Clock = CoreTypes.Clock
export type RateSpec = NetTypes.RateSpec

type Bucket = { tokens: number, last: number }

local RateLimiterClass = {}
RateLimiterClass.__index = RateLimiterClass

export type RateLimiter = typeof(setmetatable(
	{} :: { _clock: Clock, _owners: { [any]: { [string]: Bucket } } },
	RateLimiterClass
))

local function validateRate(rate: RateSpec)
	if type(rate) ~= "table" or type(rate.perSecond) ~= "number" or type(rate.burst) ~= "number" then
		error("RateLimiter: rate must be { perSecond: number, burst: number }", 3)
	end
	if rate.perSecond < 0 or rate.burst < 1 or rate.perSecond ~= rate.perSecond then
		error(`RateLimiter: invalid rate (perSecond={rate.perSecond}, burst={rate.burst})`, 3)
	end
end

local function refill(bucket: Bucket, rate: RateSpec, now: number)
	local elapsed = now - bucket.last
	if elapsed > 0 then
		bucket.tokens = math.min(rate.burst, bucket.tokens + elapsed * rate.perSecond)
	end
	bucket.last = math.max(bucket.last, now)
end

local function getBucket(self: RateLimiter, owner: any, name: string, rate: RateSpec, now: number): Bucket
	local buckets = self._owners[owner]
	if buckets == nil then
		buckets = {}
		self._owners[owner] = buckets
	end
	local bucket = buckets[name]
	if bucket == nil then
		validateRate(rate)
		bucket = { tokens = rate.burst, last = now }
		buckets[name] = bucket
	end
	return bucket
end

--- Consumes `cost` tokens (default 1). Returns true if allowed.
function RateLimiterClass.consume(self: RateLimiter, owner: any, name: string, rate: RateSpec, cost: number?): boolean
	local now = self._clock:now()
	local bucket = getBucket(self, owner, name, rate, now)
	refill(bucket, rate, now)
	local c = cost or 1
	if bucket.tokens >= c then
		bucket.tokens -= c
		return true
	end
	return false
end

--- Tokens currently available (after refill) without consuming.
function RateLimiterClass.remaining(self: RateLimiter, owner: any, name: string, rate: RateSpec): number
	local now = self._clock:now()
	local bucket = getBucket(self, owner, name, rate, now)
	refill(bucket, rate, now)
	return bucket.tokens
end

--- Drops every bucket of `owner` (call on PlayerRemoving).
function RateLimiterClass.forget(self: RateLimiter, owner: any)
	self._owners[owner] = nil
end

--- Drops buckets idle for at least `idleSeconds` (they would be full again anyway). Returns how many were dropped.
function RateLimiterClass.prune(self: RateLimiter, idleSeconds: number): number
	local now = self._clock:now()
	local dropped = 0
	for owner, buckets in self._owners do
		for name, bucket in buckets do
			if now - bucket.last >= idleSeconds then
				buckets[name] = nil
				dropped += 1
			end
		end
		if next(buckets) == nil then
			self._owners[owner] = nil
		end
	end
	return dropped
end

local RateLimiter = {}

function RateLimiter.new(clock: Clock): RateLimiter
	assert(type(clock) == "table" and type(clock.now) == "function", "RateLimiter.new: a Clock is required")
	return setmetatable({
		_clock = clock,
		_owners = setmetatable({}, { __mode = "k" }) :: any,
	}, RateLimiterClass)
end

return RateLimiter
