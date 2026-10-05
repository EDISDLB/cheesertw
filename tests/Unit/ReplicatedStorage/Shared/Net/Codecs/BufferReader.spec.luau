local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local BufferReader = require("@game/ReplicatedStorage/Shared/Net/Codecs/BufferReader")
local BufferWriter = require("@game/ReplicatedStorage/Shared/Net/Codecs/BufferWriter")

local function bytes(...: number): buffer
	local list = { ... }
	local b = buffer.create(#list)
	for i, v in list do
		buffer.writeu8(b, i - 1, v)
	end
	return b
end

describe("BufferReader bounds and malformed input", function()
	it("errors when reading past the end", function()
		local r = BufferReader.new(bytes(1, 2, 3))
		expect(r:readU16()).toBe(0x0201)
		expect(function()
			r:readU16()
		end).toThrow("needs 2 bytes at offset 2 but only 1 remain")
		expect(r:readU8()).toBe(3)
		expect(function()
			r:readU8()
		end).toThrow("readU8 needs 1 bytes")
	end)

	it("rejects over-long and oversized varints", function()
		expect(function()
			BufferReader.new(bytes(0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01)):readVarUInt()
		end).toThrow("longer than 8 bytes")
		expect(function()
			BufferReader.new(bytes(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F)):readVarUInt()
		end).toThrow("exceeds 2^53")
		expect(function()
			BufferReader.new(bytes(0x80)):readVarUInt()
		end).toThrow("needs 1 bytes")
	end)

	it("guards string lengths", function()
		local w = BufferWriter.new()
		w:writeString("hello")
		expect(function()
			BufferReader.new(w:toBuffer()):readString(4)
		end).toThrow("exceeds max 4")
		expect(function()
			BufferReader.new(bytes(10, 65, 66)):readString()
		end).toThrow("readString needs 10 bytes")
	end)

	it("rejects invalid booleans", function()
		expect(function()
			BufferReader.new(bytes(2)):readBool()
		end).toThrow("invalid boolean byte 2")
	end)

	it("reads windows of a buffer", function()
		local b = bytes(9, 9, 1, 2, 9)
		local r = BufferReader.new(b, 2, 2)
		expect(r:offset()).toBe(2)
		expect(r:readU8()).toBe(1)
		expect(r:readU8()).toBe(2)
		expect(r:isAtEnd()).toBe(true)
		expect(function()
			r:readU8()
		end).toThrow("readU8")
		expect(function()
			BufferReader.new(b, 4, 5)
		end).toThrow("invalid range")
		expect(function()
			BufferReader.new("x" :: any)
		end).toThrow("expects a buffer")
	end)
end)

describe("BufferReader (adversarial packets)", function()
	local READERS = {
		{ "readU8", 1 },
		{ "readI8", 1 },
		{ "readBool", 1 },
		{ "readU16", 2 },
		{ "readI16", 2 },
		{ "readAngle16", 2 },
		{ "readU32", 4 },
		{ "readI32", 4 },
		{ "readF32", 4 },
		{ "readUnitVector", 4 },
		{ "readF64", 8 },
		{ "readVector3", 12 },
	}

	it("every fixed-width read errors cleanly (no partial read) when one byte is missing", function()
		for _, entry in READERS do
			local method, width = entry[1], entry[2]
			local reader = BufferReader.new(buffer.create(width - 1))
			local ok, err = pcall(function()
				return (reader :: any)[method](reader)
			end)
			expect(ok).toBe(false)
			expect(tostring(err)).toContain(`BufferReader:{method} needs {width} bytes`)
			expect(reader:offset()).toBe(0)
		end
	end)

	it("reads on an empty buffer and past a window's end fail even if the backing buffer is longer", function()
		local empty = BufferReader.new(buffer.create(0))
		expect(empty:isAtEnd()).toBe(true)
		expect(function()
			empty:readU8()
		end).toThrow("needs 1 bytes")
		local window = BufferReader.new(bytes(1, 2, 3, 4), 1, 2)
		expect(window:readU8()).toBe(2)
		expect(window:readU8()).toBe(3)
		expect(function()
			window:readU8()
		end).toThrow("needs 1 bytes")
	end)

	it("varints truncated mid-way, all-continuation bytes and hostile string lengths error cleanly", function()
		expect(function()
			BufferReader.new(bytes(0x80, 0x80)):readVarUInt()
		end).toThrow("readVarUInt needs 1 bytes")
		expect(function()
			BufferReader.new(bytes(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF)):readVarUInt()
		end).toThrow("longer than 8 bytes")
		-- Length prefix claims 2^40 bytes: refused by maxLen, and by the remaining-bytes check without maxLen.
		local w = BufferWriter.new()
		w:writeVarUInt(2 ^ 40)
		w:writeU8(65)
		expect(function()
			BufferReader.new(w:toBuffer()):readString(64)
		end).toThrow("exceeds max 64")
		expect(function()
			BufferReader.new(w:toBuffer()):readString()
		end).toThrow("readString needs")
	end)

	it("random garbage never crashes a decode loop outside pcall (errors only)", function()
		local seed = 12345
		local function nextByte(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % 256
		end
		for _ = 1, 300 do
			local len = nextByte() % 24
			local b = buffer.create(len)
			for i = 0, len - 1 do
				buffer.writeu8(b, i, nextByte())
			end
			local reader = BufferReader.new(b)
			local ok, err = pcall(function()
				while not reader:isAtEnd() do
					reader:readVarInt()
					reader:readString(16)
					reader:readUnitVector()
				end
			end)
			if not ok then
				expect(tostring(err)).toContain("BufferReader:")
			end
		end
	end)

	it("float reads pass NaN/inf through (decoders must use the readFinite* variants)", function()
		local w = BufferWriter.new()
		w:writeF32(0 / 0)
		w:writeF64(math.huge)
		local r = BufferReader.new(w:toBuffer())
		local nan = r:readF32()
		expect(nan ~= nan).toBe(true)
		expect(r:readF64()).toBe(math.huge)
	end)
end)
