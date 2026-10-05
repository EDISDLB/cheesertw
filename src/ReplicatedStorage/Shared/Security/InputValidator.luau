--!strict
--[[
	InputValidator — sanitizers for untrusted client input that passed schema validation.

	Purpose:          Clamp/normalize values (axes, aim directions, aim points, strings) so simulation never sees
	                  NaN, infinities or out-of-range inputs. The combat team extends this for InputPacket fields.
	Dependencies:     None (Roblox datatypes only).
	State:            None.
	Validation:       Every helper accepts any value and returns a safe value of the expected type.
	Error handling:   Never throws; invalid input maps to the provided default (or a neutral value).
	Performance notes: Allocation-free except Vector3 construction; safe for 30 Hz input processing.
]]

local InputValidator = {}

function InputValidator.isFiniteNumber(value: unknown): boolean
	if type(value) ~= "number" then
		return false
	end
	local n = value :: number
	return n == n and n ~= math.huge and n ~= -math.huge
end

--- Finite number or `default`.
function InputValidator.finiteOr(value: unknown, default: number): number
	if InputValidator.isFiniteNumber(value) then
		return value :: number
	end
	return default
end

--- Finite number clamped to [min, max]; non-numbers / NaN map to `default` (defaults to min).
function InputValidator.clampNumber(value: unknown, min: number, max: number, default: number?): number
	if not InputValidator.isFiniteNumber(value) then
		return default or min
	end
	return math.clamp(value :: number, min, max)
end

--- Control axis (throttle, steer) in [-1, 1]; invalid -> 0.
function InputValidator.clampAxis(value: unknown): number
	return InputValidator.clampNumber(value, -1, 1, 0)
end

local function finiteVector(v: Vector3): boolean
	return InputValidator.isFiniteNumber(v.X)
		and InputValidator.isFiniteNumber(v.Y)
		and InputValidator.isFiniteNumber(v.Z)
end

--- Unit vector from an untrusted direction; zero/invalid vectors map to `fallback` (default +Z look vector).
function InputValidator.unitVector(value: unknown, fallback: Vector3?): Vector3
	local default = fallback or Vector3.new(0, 0, -1)
	if typeof(value) ~= "Vector3" then
		return default
	end
	local v = value :: Vector3
	if not finiteVector(v) then
		return default
	end
	local magnitude = v.Magnitude
	if magnitude < 1e-6 then
		return default
	end
	return v / magnitude
end

--- Aim point limited to `maxDistance` studs from `origin`; invalid -> origin + fallbackDirection * maxDistance.
function InputValidator.clampAimPoint(
	value: unknown,
	origin: Vector3,
	maxDistance: number,
	fallbackDirection: Vector3?
): Vector3
	local fallback = origin + (fallbackDirection or Vector3.new(0, 0, -1)) * maxDistance
	if typeof(value) ~= "Vector3" then
		return fallback
	end
	local p = value :: Vector3
	if not finiteVector(p) then
		return fallback
	end
	local offset = p - origin
	local distance = offset.Magnitude
	if distance > maxDistance then
		return origin + offset / distance * maxDistance
	end
	return p
end

--- String truncated to `maxBytes` on a UTF-8 boundary with control characters removed; non-strings -> "".
function InputValidator.sanitizeString(value: unknown, maxBytes: number): string
	if type(value) ~= "string" then
		return ""
	end
	local s = string.gsub(value :: string, "%c", "")
	if utf8.len(s) == nil then
		return ""
	end
	if #s <= maxBytes then
		return s
	end
	local lastEnd = 0
	for position, codepoint in utf8.codes(s) do
		local finish = position + #utf8.char(codepoint) - 1
		if finish > maxBytes then
			break
		end
		lastEnd = finish
	end
	return string.sub(s, 1, lastEnd)
end

--- Integer in [min, max] or nil (for ids/indices that must be exact).
function InputValidator.integerInRange(value: unknown, min: number, max: number): number?
	if not InputValidator.isFiniteNumber(value) then
		return nil
	end
	local n = value :: number
	if n ~= math.floor(n) or n < min or n > max then
		return nil
	end
	return n
end

return InputValidator
