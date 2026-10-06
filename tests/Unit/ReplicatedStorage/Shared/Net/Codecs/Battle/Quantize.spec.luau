-- Quantization error bounds of every battle wire encoding (docs/systems/battle-protocol.md §5).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Quantize = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Quantize")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local TWO_PI = 2 * math.pi

local function angleDiff(a: number, b: number): number
	local d = (a - b) % TWO_PI
	if d > math.pi then
		d -= TWO_PI
	end
	return math.abs(d)
end

local function degDiff(a: number, b: number): number
	local d = (a - b) % 360
	if d > 180 then
		d -= 360
	end
	return math.abs(d)
end

describe("Quantize positions (i24, 1/256 stud)", function()
	it("round-trips random coordinates within POS_ERROR (10k samples)", function()
		local rng = RNG.new(101)
		local worst = 0
		for _ = 1, 10000 do
			local x = rng:range(-Quantize.POS_LIMIT, Quantize.POS_LIMIT)
			local back = Quantize.fromPos(Quantize.toPos(x))
			worst = math.max(worst, math.abs(back - x))
		end
		expect(worst <= Quantize.POS_ERROR + 1e-12).toBe(true)
		expect(Quantize.POS_ERROR).toBeCloseTo(0.001953125, 1e-12)
	end)

	it("is exact on the 1/256 grid and saturates outside the range", function()
		expect(Quantize.fromPos(Quantize.toPos(12.5))).toBe(12.5)
		expect(Quantize.fromPos(Quantize.toPos(-0.00390625))).toBe(-0.00390625)
		expect(Quantize.toPos(1e9)).toBe(Quantize.POS_MAX_Q)
		expect(Quantize.toPos(-1e9)).toBe(Quantize.POS_MIN_Q)
		expect(Quantize.toPos(math.huge)).toBe(Quantize.POS_MAX_Q)
		expect(Quantize.toPos(-math.huge)).toBe(Quantize.POS_MIN_Q)
		expect(Quantize.toPos(0 / 0)).toBe(0)
	end)

	it("writes and reads signed 24-bit codes at the extremes", function()
		local b = buffer.create(3)
		for _, q in { -8388608, -1, 0, 1, 255, 256, 65535, 65536, 8388607 } do
			Quantize.writeI24(b, 0, q)
			expect(Quantize.readI24(b, 0)).toBe(q)
		end
	end)

	it("packs Vector3 positions into 9 bytes", function()
		local b = buffer.create(9)
		local v = Vector3.new(-4500.123, 87.5, 4499.999)
		Quantize.writePos3(b, 0, v)
		local back = Quantize.readPos3(b, 0)
		-- Vector3 components are float32: allow the float32 rounding of the input on top of the grid error.
		expect(math.abs(back.X - v.X) <= Quantize.POS_ERROR + 1e-3).toBe(true)
		expect(math.abs(back.Y - v.Y) <= Quantize.POS_ERROR + 1e-5).toBe(true)
		expect(math.abs(back.Z - v.Z) <= Quantize.POS_ERROR + 1e-3).toBe(true)
	end)
end)

describe("Quantize angles", function()
	it("u16 radians: error <= pi/65536 for any finite angle and decodes into [-pi, pi)", function()
		local rng = RNG.new(7)
		local worst = 0
		for _ = 1, 10000 do
			local a = rng:range(-50, 50)
			local q = Quantize.toAngle(a)
			expect(q >= 0 and q <= 65535 and q == math.floor(q)).toBe(true)
			local back = Quantize.fromAngle(q)
			if back < -math.pi or back >= math.pi then
				error(`decoded angle {back} outside [-pi, pi)`)
			end
			worst = math.max(worst, angleDiff(back, a))
		end
		expect(worst <= Quantize.ANGLE_ERROR + 1e-12).toBe(true)
	end)

	it("handles the wrap point and non-finite input", function()
		expect(Quantize.toAngle(TWO_PI - 1e-12)).toBe(0)
		expect(Quantize.toAngle(-1e-17)).toBe(0)
		expect(Quantize.fromAngle(Quantize.toAngle(math.pi))).toBe(-math.pi)
		expect(Quantize.toAngle(0 / 0)).toBe(0)
		expect(Quantize.toAngle(math.huge)).toBe(0)
	end)

	it("u16 degrees: error <= 360/131072 deg and decodes into [-180, 180)", function()
		local rng = RNG.new(8)
		local worst = 0
		for _ = 1, 5000 do
			local d = rng:range(-720, 720)
			local back = Quantize.fromAngleDeg(Quantize.toAngleDeg(d))
			expect(back >= -180 and back < 180).toBe(true)
			worst = math.max(worst, degDiff(back, d))
		end
		expect(worst <= 360 / 131072 + 1e-9).toBe(true)
		expect(Quantize.fromAngleDeg(Quantize.toAngleDeg(-8))).toBeCloseTo(-8, 360 / 131072)
	end)

	it("u8 minimap headings: error <= pi/256", function()
		local rng = RNG.new(9)
		for _ = 1, 2000 do
			local a = rng:range(-10, 10)
			local q = Quantize.toAngle8(a)
			expect(q >= 0 and q <= 255).toBe(true)
			expect(angleDiff(Quantize.fromAngle8(q), a) <= Quantize.ANGLE8_ERROR + 1e-12).toBe(true)
		end
	end)
end)

describe("Quantize scalars", function()
	it("axes are exact at -1, 0, 1, bounded elsewhere and never produce -128", function()
		expect(Quantize.toAxis(-1)).toBe(-127)
		expect(Quantize.toAxis(0)).toBe(0)
		expect(Quantize.toAxis(1)).toBe(127)
		expect(Quantize.fromAxis(127)).toBe(1)
		expect(Quantize.fromAxis(-127)).toBe(-1)
		expect(Quantize.toAxis(-5)).toBe(-127)
		expect(Quantize.toAxis(0 / 0)).toBe(0)
		local rng = RNG.new(10)
		for _ = 1, 5000 do
			local v = rng:range(-1, 1)
			local q = Quantize.toAxis(v)
			expect(q >= -127 and q <= 127).toBe(true)
			expect(math.abs(Quantize.fromAxis(q) - v) <= Quantize.AXIS_ERROR + 1e-12).toBe(true)
		end
	end)

	it("fractions are exact at 0 and 1 and HP fractions stay positive while alive", function()
		expect(Quantize.toFraction(0)).toBe(0)
		expect(Quantize.toFraction(1)).toBe(65535)
		expect(Quantize.fromFraction(65535)).toBe(1)
		expect(Quantize.toHpFraction(0.001, 1000000)).toBe(1)
		expect(Quantize.toHpFraction(0, 1000)).toBe(0)
		expect(Quantize.toHpFraction(-5, 1000)).toBe(0)
		expect(Quantize.toHpFraction(1000, 1000)).toBe(65535)
		expect(Quantize.toHpFraction(1500, 0)).toBe(0)
		expect(Quantize.toHpFraction(0 / 0, 100)).toBe(0)
		-- maxHp <= 32767: hp = round(fraction * maxHp) is exact.
		local rng = RNG.new(11)
		for _ = 1, 2000 do
			local maxHp = rng:int(100, 32767)
			local hp = rng:int(1, maxHp)
			local back = math.floor(Quantize.fromFraction(Quantize.toHpFraction(hp, maxHp)) * maxHp + 0.5)
			expect(back).toBe(hp)
		end
	end)

	it("speeds: 1.28 km/h steps, error <= 0.64 km/h, saturating", function()
		local rng = RNG.new(12)
		for _ = 1, 5000 do
			local v = rng:range(-Quantize.SPEED_LIMIT_KMH, Quantize.SPEED_LIMIT_KMH)
			expect(math.abs(Quantize.fromSpeed(Quantize.toSpeed(v)) - v) <= 0.64 + 1e-9).toBe(true)
		end
		expect(Quantize.toSpeed(1000)).toBe(127)
		expect(Quantize.toSpeed(-1000)).toBe(-127)
		expect(Quantize.toSpeed(-math.huge)).toBe(-127)
		expect(Quantize.toSpeed(0 / 0)).toBe(0)
	end)

	it("centiseconds: 0.005 s error, 65535 = math.huge", function()
		expect(Quantize.toCentis(0)).toBe(0)
		expect(Quantize.toCentis(-3)).toBe(0)
		expect(Quantize.toCentis(0 / 0)).toBe(0)
		expect(Quantize.toCentis(math.huge)).toBe(65535)
		expect(Quantize.fromCentis(65535)).toBe(math.huge)
		expect(Quantize.toCentis(Quantize.CENTIS_LIMIT_S)).toBe(65534)
		expect(Quantize.toCentis(700)).toBe(65535)
		local rng = RNG.new(13)
		for _ = 1, 5000 do
			local s = rng:range(0, Quantize.CENTIS_LIMIT_S)
			expect(math.abs(Quantize.fromCentis(Quantize.toCentis(s)) - s) <= 0.005 + 1e-9).toBe(true)
		end
	end)

	it("milli multipliers and byte fractions", function()
		expect(Quantize.fromMilli(Quantize.toMilli(1.234))).toBeCloseTo(1.234, 1e-9)
		expect(Quantize.toMilli(-1)).toBe(0)
		expect(Quantize.toMilli(1e6)).toBe(65535)
		expect(Quantize.toMilli(math.huge)).toBe(65535)
		expect(Quantize.toByteFraction(1)).toBe(255)
		expect(Quantize.toByteFraction(2)).toBe(255)
		expect(Quantize.toByteFraction(-1)).toBe(0)
		expect(math.abs(Quantize.fromByteFraction(Quantize.toByteFraction(0.4)) - 0.4) <= 0.5 / 255).toBe(true)
	end)

	it("map coordinates: 1-stud grid, ±32767 saturation", function()
		expect(Quantize.toMapCoord(1234.4)).toBe(1234)
		expect(Quantize.toMapCoord(-1234.6)).toBe(-1235)
		expect(Quantize.toMapCoord(1e9)).toBe(32767)
		expect(Quantize.toMapCoord(-1e9)).toBe(-32767)
		expect(Quantize.toMapCoord(0 / 0)).toBe(0)
	end)
end)

describe("Quantize unit vectors (octahedral)", function()
	it("round-trips random directions within 0.01 degrees", function()
		local rng = RNG.new(14)
		local b = buffer.create(4)
		local worst = 0
		for _ = 1, 5000 do
			local v = Vector3.new(rng:range(-1, 1), rng:range(-1, 1), rng:range(-1, 1))
			if v.Magnitude > 1e-3 then
				local u = v.Unit
				Quantize.writeUnit(b, 0, v)
				local back = Quantize.readUnit(b, 0)
				expect(math.abs(back.Magnitude - 1) < 1e-5).toBe(true)
				-- chord formula: stable for tiny angles (acos of a float32 dot product is not)
				local dx, dy, dz = back.X - u.X, back.Y - u.Y, back.Z - u.Z
				local chord = math.sqrt(dx * dx + dy * dy + dz * dz)
				worst = math.max(worst, math.deg(2 * math.asin(math.min(1, chord / 2))))
			end
		end
		expect(worst).toBeLessThan(0.01)
	end)

	it("maps zero and non-finite vectors to +Z instead of garbage", function()
		local b = buffer.create(4)
		Quantize.writeUnit(b, 0, Vector3.zero)
		expect(Quantize.readUnit(b, 0)).toBeCloseTo(Vector3.new(0, 0, 1), 1e-4)
		Quantize.writeUnit(b, 0, Vector3.new(0 / 0, 1, 0))
		expect(Quantize.readUnit(b, 0)).toBeCloseTo(Vector3.new(0, 0, 1), 1e-4)
		-- every 4-byte pattern decodes to a finite unit vector (hostile bytes are harmless)
		local rng = RNG.new(15)
		for _ = 1, 2000 do
			buffer.writeu32(b, 0, rng:nextU32())
			local v = Quantize.readUnit(b, 0)
			expect(math.abs(v.Magnitude - 1) < 1e-4).toBe(true)
		end
	end)
end)
