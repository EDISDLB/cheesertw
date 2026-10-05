--!strict
--[[
	BufferReader — bounds-checked binary reader mirroring BufferWriter (see its header for encodings).

	Purpose:          Decode untrusted packets: every read checks remaining length; malformed input raises an error
	                  that codec decoders catch with pcall and report as INVALID_ARGS.
	Dependencies:     None (Roblox datatypes: Vector3).
	State:            Source buffer, cursor, end offset.
	Validation:       Reads past the end, over-long varints, varints above 2^53 and strings longer than `maxLen`
	                  or the remaining bytes all raise errors.
	Error handling:   Errors are prefixed "BufferReader:" with offsets for debugging.
	Performance notes: No allocation except strings and Vector3 results.
]]

local TWO_PI = 2 * math.pi
local MAX_SAFE = 9007199254740992 -- 2^53

local ReaderClass = {}
ReaderClass.__index = ReaderClass

export type BufferReader = typeof(setmetatable({} :: { _buf: buffer, _pos: number, _end: number }, ReaderClass))

local function need(self: BufferReader, n: number, what: string)
	if self._pos + n > self._end then
		error(`BufferReader:{what} needs {n} bytes at offset {self._pos} but only {self._end - self._pos} remain`, 3)
	end
end

function ReaderClass.readU8(self: BufferReader): number
	need(self, 1, "readU8")
	local v = buffer.readu8(self._buf, self._pos)
	self._pos += 1
	return v
end

function ReaderClass.readU16(self: BufferReader): number
	need(self, 2, "readU16")
	local v = buffer.readu16(self._buf, self._pos)
	self._pos += 2
	return v
end

function ReaderClass.readU32(self: BufferReader): number
	need(self, 4, "readU32")
	local v = buffer.readu32(self._buf, self._pos)
	self._pos += 4
	return v
end

function ReaderClass.readI8(self: BufferReader): number
	need(self, 1, "readI8")
	local v = buffer.readi8(self._buf, self._pos)
	self._pos += 1
	return v
end

function ReaderClass.readI16(self: BufferReader): number
	need(self, 2, "readI16")
	local v = buffer.readi16(self._buf, self._pos)
	self._pos += 2
	return v
end

function ReaderClass.readI32(self: BufferReader): number
	need(self, 4, "readI32")
	local v = buffer.readi32(self._buf, self._pos)
	self._pos += 4
	return v
end

function ReaderClass.readF32(self: BufferReader): number
	need(self, 4, "readF32")
	local v = buffer.readf32(self._buf, self._pos)
	self._pos += 4
	return v
end

function ReaderClass.readF64(self: BufferReader): number
	need(self, 8, "readF64")
	local v = buffer.readf64(self._buf, self._pos)
	self._pos += 8
	return v
end

function ReaderClass.readBool(self: BufferReader): boolean
	need(self, 1, "readBool")
	local v = buffer.readu8(self._buf, self._pos)
	self._pos += 1
	if v > 1 then
		error(`BufferReader:readBool invalid boolean byte {v} at offset {self._pos - 1}`, 2)
	end
	return v == 1
end

--- Angle in radians in [-pi, pi).
function ReaderClass.readAngle16(self: BufferReader): number
	need(self, 2, "readAngle16")
	local q = buffer.readu16(self._buf, self._pos)
	self._pos += 2
	local radians = q / 65536 * TWO_PI
	if radians >= math.pi then
		radians -= TWO_PI
	end
	return radians
end

local function signNotZero(n: number): number
	return if n < 0 then -1 else 1
end

--- Unit Vector3 decoded from the octahedral encoding.
function ReaderClass.readUnitVector(self: BufferReader): Vector3
	need(self, 4, "readUnitVector")
	local u = buffer.readu16(self._buf, self._pos) / 65535 * 2 - 1
	local v = buffer.readu16(self._buf, self._pos + 2) / 65535 * 2 - 1
	self._pos += 4
	local z = 1 - math.abs(u) - math.abs(v)
	local x, y = u, v
	if z < 0 then
		x, y = (1 - math.abs(v)) * signNotZero(u), (1 - math.abs(u)) * signNotZero(v)
	end
	local length = math.sqrt(x * x + y * y + z * z)
	return Vector3.new(x / length, y / length, z / length)
end

function ReaderClass.readVector3(self: BufferReader): Vector3
	need(self, 12, "readVector3")
	local b, p = self._buf, self._pos
	self._pos += 12
	return Vector3.new(buffer.readf32(b, p), buffer.readf32(b, p + 4), buffer.readf32(b, p + 8))
end

function ReaderClass.readVarUInt(self: BufferReader): number
	local result = 0
	local multiplier = 1
	for _ = 1, 8 do
		need(self, 1, "readVarUInt")
		local byte = buffer.readu8(self._buf, self._pos)
		self._pos += 1
		result += (byte % 128) * multiplier
		if byte < 128 then
			if result >= MAX_SAFE then
				error(`BufferReader:readVarUInt value exceeds 2^53 at offset {self._pos}`, 2)
			end
			return result
		end
		multiplier *= 128
	end
	error(`BufferReader:readVarUInt varint longer than 8 bytes at offset {self._pos}`, 2)
end

function ReaderClass.readVarInt(self: BufferReader): number
	local z = ReaderClass.readVarUInt(self)
	if z % 2 == 0 then
		return z / 2
	end
	return -(z + 1) / 2
end

--- Length-prefixed string; `maxLen` (bytes) guards against hostile lengths.
function ReaderClass.readString(self: BufferReader, maxLen: number?): string
	local len = ReaderClass.readVarUInt(self)
	if maxLen ~= nil and len > maxLen then
		error(`BufferReader:readString length {len} exceeds max {maxLen}`, 2)
	end
	need(self, len, "readString")
	local s = buffer.readstring(self._buf, self._pos, len)
	self._pos += len
	return s
end

function ReaderClass.remaining(self: BufferReader): number
	return self._end - self._pos
end

function ReaderClass.offset(self: BufferReader): number
	return self._pos
end

--- True when every byte has been consumed (decoders should reject trailing garbage).
function ReaderClass.isAtEnd(self: BufferReader): boolean
	return self._pos == self._end
end

local BufferReader = {}

--- Reads `buf` from `offset` (default 0) up to `offset + length` (default: end of buffer).
function BufferReader.new(buf: buffer, offset: number?, length: number?): BufferReader
	if type(buf) ~= "buffer" then
		error(`BufferReader.new expects a buffer, got {typeof(buf)}`, 2)
	end
	local start = offset or 0
	local size = buffer.len(buf)
	local finish = if length ~= nil then start + length else size
	if start < 0 or finish > size or start > finish then
		error(`BufferReader.new invalid range [{start}, {finish}) for buffer of {size} bytes`, 2)
	end
	return setmetatable({ _buf = buf, _pos = start, _end = finish }, ReaderClass)
end

return BufferReader
