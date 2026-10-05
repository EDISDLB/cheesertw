local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local BufferWriter = require("@game/ReplicatedStorage/Shared/Net/Codecs/BufferWriter")
local BufferReader = require("@game/ReplicatedStorage/Shared/Net/Codecs/BufferReader")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local function roundTrip(write: (any) -> (), read: (any) -> any): any
	local w = BufferWriter.new(1)
	write(w)
	local r = BufferReader.new(w:toBuffer())
	local value = read(r)
	expect(r:isAtEnd()).toBe(true)
	return value
end

describe("BufferWriter/BufferReader round trips", function()
	it("fixed-width integers at their limits", function()
		local cases = {
			{ "U8", { 0, 1, 127, 255 } },
			{ "U16", { 0, 256, 65535 } },
			{ "U32", { 0, 65536, 4294967295 } },
			{ "I8", { -128, -1, 0, 127 } },
			{ "I16", { -32768, -1, 32767 } },
			{ "I32", { -2147483648, -1, 0, 2147483647 } },
		}
		for _, case in cases do
			local kind, values = case[1], case[2]
			for _, v in values do
				local got = roundTrip(function(w)
					w["write" .. kind](w, v)
				end, function(r)
					return r["read" .. kind](r)
				end)
				expect(got).toBe(v)
			end
		end
	end)

	it("floats: f64 exact, f32 rounded to single precision", function()
		for _, v in { 0, -0.5, 1e300, -123.456, math.huge } do
			expect(roundTrip(function(w)
				w:writeF64(v)
			end, function(r)
				return r:readF64()
			end)).toBe(v)
		end
		for _, v in { 0, 0.5, -2, 1024.25 } do
			expect(roundTrip(function(w)
				w:writeF32(v)
			end, function(r)
				return r:readF32()
			end)).toBe(v)
		end
		local approx = roundTrip(function(w)
			w:writeF32(0.1)
		end, function(r)
			return r:readF32()
		end)
		expect(approx).toBeCloseTo(0.1, 1e-7)
		expect(approx).never.toBe(0.1)
	end)

	it("booleans and Vector3", function()
		expect(roundTrip(function(w)
			w:writeBool(true)
		end, function(r)
			return r:readBool()
		end)).toBe(true)
		local v = roundTrip(function(w)
			w:writeVector3(Vector3.new(1.5, -2.25, 1000))
		end, function(r)
			return r:readVector3()
		end)
		expect(v).toEqual(Vector3.new(1.5, -2.25, 1000))
	end)

	it("quantized angles stay within half a step (wrapping to [-pi, pi))", function()
		local step = 2 * math.pi / 65536
		local worst = 0
		for i = -1000, 1000 do
			local angle = i * 0.0137
			local got = roundTrip(function(w)
				w:writeAngle16(angle)
			end, function(r)
				return r:readAngle16()
			end)
			expect(got >= -math.pi and got < math.pi).toBe(true)
			local diff = math.abs((got - angle + math.pi) % (2 * math.pi) - math.pi)
			worst = math.max(worst, diff)
		end
		expect(worst).toBeLessThanOrEqual(step / 2 + 1e-12)
		expect(roundTrip(function(w)
			w:writeAngle16(math.pi)
		end, function(r)
			return r:readAngle16()
		end)).toBeCloseTo(-math.pi, 1e-12)
	end)

	it("octahedral unit vectors are accurate to < 0.01 degrees", function()
		local rng = RNG.new(31)
		local worstDeg = 0
		local directions = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
			Vector3.new(1, 1, -1).Unit,
		}
		for _ = 1, 2000 do
			table.insert(directions, Vector3.new(rng:normal(0, 1), rng:normal(0, 1), rng:normal(0, 1)).Unit)
		end
		for _, d in directions do
			local got = roundTrip(function(w)
				w:writeUnitVector(d)
			end, function(r)
				return r:readUnitVector()
			end)
			expect(got.Magnitude).toBeCloseTo(1, 1e-5)
			-- atan2(|a x b|, a . b) in double precision: acos(dot) cannot resolve tiny angles.
			local ax, ay, az = got.X, got.Y, got.Z
			local bx, by, bz = d.X, d.Y, d.Z
			local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
			local angle = math.deg(math.atan2(math.sqrt(cx * cx + cy * cy + cz * cz), ax * bx + ay * by + az * bz))
			worstDeg = math.max(worstDeg, angle)
		end
		expect(worstDeg).toBeLessThan(0.01)
	end)

	it("varints at the edges", function()
		for _, v in { 0, 1, 127, 128, 16383, 16384, 2 ^ 32, 2 ^ 53 - 1 } do
			expect(roundTrip(function(w)
				w:writeVarUInt(v)
			end, function(r)
				return r:readVarUInt()
			end)).toBe(v)
		end
		for _, v in { 0, -1, 1, -64, 64, -(2 ^ 52), 2 ^ 52 - 1 } do
			expect(roundTrip(function(w)
				w:writeVarInt(v)
			end, function(r)
				return r:readVarInt()
			end)).toBe(v)
		end
		local w = BufferWriter.new()
		w:writeVarUInt(127)
		expect(w:length()).toBe(1)
		w:writeVarUInt(128)
		expect(w:length()).toBe(3)
	end)

	it("strings (empty, unicode, long)", function()
		for _, s in { "", "HULLDOWN", "Tiger " .. utf8.char(0x1F405, 0xE9), string.rep("x", 5000) } do
			expect(roundTrip(function(w)
				w:writeString(s)
			end, function(r)
				return r:readString()
			end)).toBe(s)
		end
	end)

	it("mixed sequences, growth, toBuffer size and reset", function()
		local w = BufferWriter.new(2)
		for i = 1, 3000 do
			w:writeU16(i)
		end
		w:writeString("end")
		local b = w:toBuffer()
		expect(buffer.len(b)).toBe(6000 + 1 + 3)
		local r = BufferReader.new(b)
		for i = 1, 3000 do
			if r:readU16() ~= i then
				error("mismatch at " .. i)
			end
		end
		expect(r:readString()).toBe("end")
		expect(r:remaining()).toBe(0)
		w:reset()
		expect(w:length()).toBe(0)
		w:writeU8(7)
		expect(buffer.len(w:toBuffer())).toBe(1)
	end)
end)

describe("BufferWriter validation", function()
	it("rejects out-of-range and non-integer values", function()
		local w = BufferWriter.new()
		expect(function()
			w:writeU8(256)
		end).toThrow("writeU8 expects an integer in [0, 255]")
		expect(function()
			w:writeU8(1.5)
		end).toThrow("writeU8")
		expect(function()
			w:writeI8(-129)
		end).toThrow("writeI8")
		expect(function()
			w:writeU32(-1)
		end).toThrow("writeU32")
		expect(function()
			w:writeVarUInt(-1)
		end).toThrow("writeVarUInt")
		expect(function()
			w:writeVarUInt(2 ^ 53)
		end).toThrow("writeVarUInt")
		expect(function()
			w:writeVarInt(2 ^ 52)
		end).toThrow("writeVarInt")
		expect(function()
			w:writeAngle16(0 / 0)
		end).toThrow("finite")
		expect(function()
			w:writeUnitVector(Vector3.new(0 / 0, 0, 0))
		end).toThrow("finite")
		expect(function()
			w:writeString(5 :: any)
		end).toThrow("expects a string")
		expect(w:length()).toBe(0)
	end)

	it("zero vectors encode to +Z", function()
		local w = BufferWriter.new()
		w:writeUnitVector(Vector3.zero)
		expect(BufferReader.new(w:toBuffer()):readUnitVector()).toBeCloseTo(Vector3.new(0, 0, 1), 1e-4)
	end)
end)
