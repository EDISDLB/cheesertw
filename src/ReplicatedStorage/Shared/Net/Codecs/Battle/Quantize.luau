--!strict
--[[
	Codecs/Battle/Quantize — fixed-point, angle and fraction quantizers shared by the battle codecs, plus raw
	buffer helpers for the 24-bit and octahedral encodings (precision analysis: docs/systems/battle-protocol.md §5).

	Purpose:          One definition of every lossy wire encoding so encoders, decoders, tests and the precision
	                  table agree. Every `toX` maps a real value to an integer code that fits its field; every
	                  `fromX` maps a code back. Codes are always in range: out-of-range values SATURATE (documented
	                  per encoding) and NaN maps to the neutral code, so a quantizer never produces an unwritable code.
	Dependencies:     None (Roblox datatypes: Vector3).
	State:            None.
	Validation:       Inputs are clamped/saturated; NaN -> neutral code (0, or the midpoint where noted). Encoders
	                  that must reject non-finite values check them before quantizing.
	Error handling:   Never throws (callers pass numbers; type errors are programming mistakes).
	Performance notes: Pure arithmetic, no allocation except Vector3 results. Used on the server hot path (snapshot
	                  entity records) and in client decoders.

	Encodings (max absolute error inside the range):
	  position   i24, 1/256 stud           range ±32767.996 studs (±10.9 km)     error 1/512 stud (0.65 mm)
	  angle      u16, 2π/65536             any angle (wrapped), decodes [-π, π)  error π/65536 rad (0.0027°)
	  angle8     u8,  2π/256               minimap headings                      error π/256 rad (0.7°)
	  axis       i8,  1/127                [-1, 1] (-128 is never produced)      error 1/254 (exact -1, 0, 1)
	  fraction   u16, 1/65535              [0, 1]                                error 1/131070 (exact 0, 1)
	  speed      i8,  1.28 km/h            ±162.56 km/h                          error 0.64 km/h
	  centis     u16, 0.01 s               [0, 655.34] s, 65535 = math.huge      error 0.005 s
	  milli      u16, 0.001                [0, 65.535]                           error 0.0005
	  mapCoord   i16, 1 stud               ±32767 studs                          error 0.5 stud
	  unit       2 × u16 octahedral        unit vectors                          error < 0.01°
]]

local TWO_PI = 2 * math.pi

local Quantize = {}

Quantize.POS_SCALE = 256
Quantize.POS_MIN_Q = -8388608
Quantize.POS_MAX_Q = 8388607
--- Largest encodable coordinate (studs); larger values saturate.
Quantize.POS_LIMIT = 8388607 / 256
--- Worst-case per-axis error for coordinates inside ±POS_LIMIT.
Quantize.POS_ERROR = 0.5 / 256
Quantize.ANGLE_ERROR = math.pi / 65536
Quantize.ANGLE8_ERROR = math.pi / 256
Quantize.AXIS_ERROR = 0.5 / 127
Quantize.FRACTION_ERROR = 0.5 / 65535
Quantize.SPEED_STEP_KMH = 1.28
Quantize.SPEED_LIMIT_KMH = 127 * 1.28
Quantize.CENTIS_INFINITE = 65535
--- Largest finite duration (s); longer durations (and math.huge) decode as math.huge.
Quantize.CENTIS_LIMIT_S = 655.34
Quantize.MILLI_LIMIT = 65.535
Quantize.MAP_COORD_LIMIT = 32767

local function roundHalfUp(x: number): number
	return math.floor(x + 0.5)
end

--------------------------------------------------------------------------------
-- Positions (i24 fixed point)
--------------------------------------------------------------------------------

--- Studs -> signed 24-bit code (saturates at ±POS_LIMIT; NaN -> 0).
function Quantize.toPos(studs: number): number
	if studs ~= studs then
		return 0
	end
	local q = roundHalfUp(studs * 256)
	if q < -8388608 then
		return -8388608
	elseif q > 8388607 then
		return 8388607
	end
	return q
end

function Quantize.fromPos(q: number): number
	return q / 256
end

--- Writes a signed 24-bit code (little endian) at `offset`.
function Quantize.writeI24(b: buffer, offset: number, q: number)
	local u = q % 16777216
	buffer.writeu16(b, offset, u % 65536)
	buffer.writeu8(b, offset + 2, u // 65536)
end

--- Reads a signed 24-bit code at `offset` (caller checks bounds).
function Quantize.readI24(b: buffer, offset: number): number
	local u = buffer.readu16(b, offset) + buffer.readu8(b, offset + 2) * 65536
	if u >= 8388608 then
		return u - 16777216
	end
	return u
end

--- Writes a Vector3 as three i24 position codes (9 bytes).
function Quantize.writePos3(b: buffer, offset: number, v: Vector3)
	Quantize.writeI24(b, offset, Quantize.toPos(v.X))
	Quantize.writeI24(b, offset + 3, Quantize.toPos(v.Y))
	Quantize.writeI24(b, offset + 6, Quantize.toPos(v.Z))
end

function Quantize.readPos3(b: buffer, offset: number): Vector3
	return Vector3.new(
		Quantize.readI24(b, offset) / 256,
		Quantize.readI24(b, offset + 3) / 256,
		Quantize.readI24(b, offset + 6) / 256
	)
end

--------------------------------------------------------------------------------
-- Angles
--------------------------------------------------------------------------------

--- Radians (any value) -> u16 code; NaN / ±inf -> 0.
function Quantize.toAngle(radians: number): number
	if radians ~= radians or radians == math.huge or radians == -math.huge then
		return 0
	end
	return roundHalfUp((radians % TWO_PI) / TWO_PI * 65536) % 65536
end

--- u16 code -> radians in [-π, π).
function Quantize.fromAngle(q: number): number
	local r = q / 65536 * TWO_PI
	if r >= math.pi then
		r -= TWO_PI
	end
	return r
end

--- Degrees (any value) -> u16 code (same grid as toAngle).
function Quantize.toAngleDeg(degrees: number): number
	if degrees ~= degrees or degrees == math.huge or degrees == -math.huge then
		return 0
	end
	return roundHalfUp((degrees % 360) / 360 * 65536) % 65536
end

--- u16 code -> degrees in [-180, 180).
function Quantize.fromAngleDeg(q: number): number
	local d = q / 65536 * 360
	if d >= 180 then
		d -= 360
	end
	return d
end

--- Radians -> u8 code (minimap headings).
function Quantize.toAngle8(radians: number): number
	if radians ~= radians or radians == math.huge or radians == -math.huge then
		return 0
	end
	return roundHalfUp((radians % TWO_PI) / TWO_PI * 256) % 256
end

function Quantize.fromAngle8(q: number): number
	local r = q / 256 * TWO_PI
	if r >= math.pi then
		r -= TWO_PI
	end
	return r
end

--------------------------------------------------------------------------------
-- Scalars
--------------------------------------------------------------------------------

--- Control axis [-1, 1] -> i8 code in [-127, 127] (clamped; NaN -> 0).
function Quantize.toAxis(v: number): number
	if v ~= v then
		return 0
	end
	return roundHalfUp(math.clamp(v, -1, 1) * 127)
end

function Quantize.fromAxis(q: number): number
	return q / 127
end

--- [0, 1] -> u16 code (clamped; NaN -> 0).
function Quantize.toFraction(f: number): number
	if f ~= f then
		return 0
	end
	return roundHalfUp(math.clamp(f, 0, 1) * 65535)
end

function Quantize.fromFraction(q: number): number
	return q / 65535
end

--- hp / maxHp as a u16 fraction that is never 0 while hp > 0 (a living vehicle never shows an empty bar).
function Quantize.toHpFraction(hp: number, maxHp: number): number
	if not (hp > 0) or not (maxHp > 0) then
		return 0
	end
	local q = Quantize.toFraction(hp / maxHp)
	if q < 1 then
		return 1
	end
	return q
end

--- Signed speed (km/h) -> i8 code (saturates at ±SPEED_LIMIT_KMH; NaN -> 0).
function Quantize.toSpeed(kmh: number): number
	if kmh ~= kmh then
		return 0
	end
	return math.clamp(roundHalfUp(kmh / 1.28), -127, 127)
end

function Quantize.fromSpeed(q: number): number
	return q * 1.28
end

--- Seconds -> u16 centiseconds; <= 0 / NaN -> 0; > CENTIS_LIMIT_S or math.huge -> 65535 (decodes as math.huge).
function Quantize.toCentis(seconds: number): number
	if seconds ~= seconds or seconds <= 0 then
		return 0
	end
	local q = roundHalfUp(seconds * 100)
	if q >= 65535 then
		return 65535
	end
	return q
end

function Quantize.fromCentis(q: number): number
	if q >= 65535 then
		return math.huge
	end
	return q / 100
end

--- Non-negative multiplier -> u16 thousandths (saturates at MILLI_LIMIT; negative / NaN -> 0).
function Quantize.toMilli(m: number): number
	if m ~= m or m <= 0 then
		return 0
	end
	return math.min(roundHalfUp(m * 1000), 65535)
end

function Quantize.fromMilli(q: number): number
	return q / 1000
end

--- [0, 1] -> u8 code (progress bars).
function Quantize.toByteFraction(f: number): number
	if f ~= f then
		return 0
	end
	return roundHalfUp(math.clamp(f, 0, 1) * 255)
end

function Quantize.fromByteFraction(q: number): number
	return q / 255
end

--- Map coordinate (studs) -> i16 code (1-stud grid, saturates at ±MAP_COORD_LIMIT; NaN -> 0).
function Quantize.toMapCoord(studs: number): number
	if studs ~= studs then
		return 0
	end
	return math.clamp(roundHalfUp(studs), -32767, 32767)
end

--------------------------------------------------------------------------------
-- Unit vectors (octahedral, same layout as BufferWriter:writeUnitVector)
--------------------------------------------------------------------------------

local function signNotZero(n: number): number
	return if n < 0 then -1 else 1
end

local function quantizeUnit(u: number): number
	return roundHalfUp((math.clamp(u, -1, 1) + 1) * 0.5 * 65535)
end

--- Writes a direction (normalized implicitly; zero / non-finite -> +Z) as 4 bytes.
function Quantize.writeUnit(b: buffer, offset: number, v: Vector3)
	local x, y, z = v.X, v.Y, v.Z
	local l1 = math.abs(x) + math.abs(y) + math.abs(z)
	local px, py = 0, 0
	if l1 == l1 and l1 ~= math.huge and l1 > 1e-12 then
		px, py = x / l1, y / l1
		if z < 0 then
			px, py = (1 - math.abs(py)) * signNotZero(px), (1 - math.abs(px)) * signNotZero(py)
		end
	end
	buffer.writeu16(b, offset, quantizeUnit(px))
	buffer.writeu16(b, offset + 2, quantizeUnit(py))
end

--- Reads a unit Vector3 written by writeUnit (always finite and unit length).
function Quantize.readUnit(b: buffer, offset: number): Vector3
	local u = buffer.readu16(b, offset) / 65535 * 2 - 1
	local v = buffer.readu16(b, offset + 2) / 65535 * 2 - 1
	local z = 1 - math.abs(u) - math.abs(v)
	local x, y = u, v
	if z < 0 then
		x, y = (1 - math.abs(v)) * signNotZero(u), (1 - math.abs(u)) * signNotZero(v)
	end
	local length = math.sqrt(x * x + y * y + z * z)
	return Vector3.new(x / length, y / length, z / length)
end

return table.freeze(Quantize)
