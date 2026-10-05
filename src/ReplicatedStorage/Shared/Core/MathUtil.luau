--!strict
--[[
	MathUtil — small scalar helpers used across simulation, UI and tooling.

	Purpose:          clamp, lerp, inverseLerp, remap, approach, angle helpers (degrees), smoothDamp, round, expDecay.
	Dependencies:     None.
	State:            None.
	Validation:       Degenerate ranges are handled (inverseLerp(a, a, v) = 0); smoothDamp guards dt <= 0.
	Error handling:   None (pure arithmetic).
	Performance notes: Allocation-free; safe in per-frame loops.
]]

local MathUtil = {}

function MathUtil.clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Returns t such that lerp(a, b, t) == v (0 when a == b). Not clamped.
function MathUtil.inverseLerp(a: number, b: number, v: number): number
	if a == b then
		return 0
	end
	return (v - a) / (b - a)
end

--- Maps v from [inMin, inMax] to [outMin, outMax]; clamps to the output range when `clampOutput` is true.
function MathUtil.remap(
	v: number,
	inMin: number,
	inMax: number,
	outMin: number,
	outMax: number,
	clampOutput: boolean?
): number
	local t = MathUtil.inverseLerp(inMin, inMax, v)
	if clampOutput then
		t = MathUtil.clamp(t, 0, 1)
	end
	return outMin + (outMax - outMin) * t
end

--- Moves `current` toward `target` by at most `maxDelta` (maxDelta >= 0).
function MathUtil.approach(current: number, target: number, maxDelta: number): number
	local delta = target - current
	if math.abs(delta) <= maxDelta then
		return target
	end
	return current + (if delta > 0 then maxDelta else -maxDelta)
end

--- Wraps an angle in degrees to (-180, 180].
function MathUtil.wrapDeg(deg: number): number
	local wrapped = (deg + 180) % 360 - 180
	if wrapped == -180 then
		return 180
	end
	return wrapped
end

--- Shortest signed difference `to - from` in degrees, in (-180, 180].
function MathUtil.angleDiffDeg(from: number, to: number): number
	return MathUtil.wrapDeg(to - from)
end

--- Rotates `current` toward `target` (degrees) along the shortest arc by at most `maxDelta`.
function MathUtil.approachAngleDeg(current: number, target: number, maxDelta: number): number
	local diff = MathUtil.angleDiffDeg(current, target)
	if math.abs(diff) <= maxDelta then
		return MathUtil.wrapDeg(current + diff)
	end
	return MathUtil.wrapDeg(current + (if diff > 0 then maxDelta else -maxDelta))
end

--- Critically damped smoothing (Unity's SmoothDamp). Returns (newValue, newVelocity).
function MathUtil.smoothDamp(
	current: number,
	target: number,
	velocity: number,
	smoothTime: number,
	dt: number,
	maxSpeed: number?
): (number, number)
	if dt <= 0 then
		return current, velocity
	end
	local st = math.max(0.0001, smoothTime)
	local omega = 2 / st
	local x = omega * dt
	local decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
	local change = current - target
	local originalTarget = target
	local maxChange = (maxSpeed or math.huge) * st
	change = MathUtil.clamp(change, -maxChange, maxChange)
	local adjustedTarget = current - change
	local temp = (velocity + omega * change) * dt
	local newVelocity = (velocity - omega * temp) * decay
	local output = adjustedTarget + (change + temp) * decay
	if (originalTarget - current > 0) == (output > originalTarget) then
		output = originalTarget
		newVelocity = (output - originalTarget) / dt
	end
	return output, newVelocity
end

--- Rounds to the nearest multiple of `step` (default 1); halves round away from zero.
function MathUtil.round(n: number, step: number?): number
	local s = step or 1
	if s == 0 then
		return n
	end
	local q = n / s
	local r = if q >= 0 then math.floor(q + 0.5) else -math.floor(-q + 0.5)
	return r * s
end

--- Frame-rate independent exponential approach: moves `current` toward `target` with `rate` (1/s) over dt.
function MathUtil.expDecay(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

function MathUtil.sign(n: number): number
	if n > 0 then
		return 1
	elseif n < 0 then
		return -1
	end
	return 0
end

function MathUtil.isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

return MathUtil
