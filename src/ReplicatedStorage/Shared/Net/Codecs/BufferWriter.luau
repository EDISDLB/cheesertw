--!strict
--[[
	BufferWriter — growable binary writer over Luau `buffer` for high-frequency packets (Input/Snapshot codecs).

	Purpose:          Little-endian fixed-width ints/floats, LEB128 varints (+zigzag), length-prefixed strings,
	                  quantized angles (u16) and octahedral unit vectors (2 x u16).
	Dependencies:     None (Roblox datatypes: Vector3).
	State:            Backing buffer, capacity and write cursor.
	Validation:       Every write checks range/integrality (e.g. writeU8 rejects 256 or 1.5) and errors loudly:
	                  encoding bugs must never silently corrupt packets.
	Error handling:   Errors are raised with the method name and offending value.
	Performance notes: Capacity doubles on demand (amortized O(1)); reuse one writer per stream via reset() to
	                  avoid per-tick allocation; toBuffer() copies exactly `length()` bytes.

	Encodings (BufferReader mirrors each):
	  angle16:     radians wrapped to [0, 2pi) -> round(x / 2pi * 65536) mod 65536   (step 9.6e-5 rad)
	  unitVector:  octahedral projection, each axis round((u + 1) / 2 * 65535)       (error < 0.01 deg)
	  varUInt:     unsigned LEB128, integers in [0, 2^53)
	  varInt:      zigzag (n >= 0 -> 2n, n < 0 -> -2n - 1) then varUInt; |n| <= 2^52
	  string:      varUInt byte length, then raw bytes
]]

local TWO_PI = 2 * math.pi
local MAX_SAFE = 9007199254740992 -- 2^53

local WriterClass = {}
WriterClass.__index = WriterClass

export type BufferWriter = typeof(setmetatable({} :: { _buf: buffer, _cap: number, _len: number }, WriterClass))

local function ensure(self: BufferWriter, extra: number)
	local needed = self._len + extra
	if needed <= self._cap then
		return
	end
	local cap = self._cap
	while cap < needed do
		cap *= 2
	end
	local grown = buffer.create(cap)
	buffer.copy(grown, 0, self._buf, 0, self._len)
	self._buf = grown
	self._cap = cap
end

local function checkInt(method: string, n: number, lo: number, hi: number)
	if type(n) ~= "number" or n ~= n or n ~= math.floor(n) or n < lo or n > hi then
		error(`BufferWriter:{method} expects an integer in [{lo}, {hi}], got {tostring(n)}`, 3)
	end
end

function WriterClass.writeU8(self: BufferWriter, n: number)
	checkInt("writeU8", n, 0, 255)
	ensure(self, 1)
	buffer.writeu8(self._buf, self._len, n)
	self._len += 1
end

function WriterClass.writeU16(self: BufferWriter, n: number)
	checkInt("writeU16", n, 0, 65535)
	ensure(self, 2)
	buffer.writeu16(self._buf, self._len, n)
	self._len += 2
end

function WriterClass.writeU32(self: BufferWriter, n: number)
	checkInt("writeU32", n, 0, 4294967295)
	ensure(self, 4)
	buffer.writeu32(self._buf, self._len, n)
	self._len += 4
end

function WriterClass.writeI8(self: BufferWriter, n: number)
	checkInt("writeI8", n, -128, 127)
	ensure(self, 1)
	buffer.writei8(self._buf, self._len, n)
	self._len += 1
end

function WriterClass.writeI16(self: BufferWriter, n: number)
	checkInt("writeI16", n, -32768, 32767)
	ensure(self, 2)
	buffer.writei16(self._buf, self._len, n)
	self._len += 2
end

function WriterClass.writeI32(self: BufferWriter, n: number)
	checkInt("writeI32", n, -2147483648, 2147483647)
	ensure(self, 4)
	buffer.writei32(self._buf, self._len, n)
	self._len += 4
end

function WriterClass.writeF32(self: BufferWriter, n: number)
	if type(n) ~= "number" then
		error(`BufferWriter:writeF32 expects a number, got {typeof(n)}`, 2)
	end
	ensure(self, 4)
	buffer.writef32(self._buf, self._len, n)
	self._len += 4
end

function WriterClass.writeF64(self: BufferWriter, n: number)
	if type(n) ~= "number" then
		error(`BufferWriter:writeF64 expects a number, got {typeof(n)}`, 2)
	end
	ensure(self, 8)
	buffer.writef64(self._buf, self._len, n)
	self._len += 8
end

function WriterClass.writeBool(self: BufferWriter, b: boolean)
	if type(b) ~= "boolean" then
		error(`BufferWriter:writeBool expects a boolean, got {typeof(b)}`, 2)
	end
	ensure(self, 1)
	buffer.writeu8(self._buf, self._len, if b then 1 else 0)
	self._len += 1
end

--- Angle in radians (any finite value; wrapped) quantized to 16 bits.
function WriterClass.writeAngle16(self: BufferWriter, radians: number)
	if type(radians) ~= "number" or radians ~= radians or math.abs(radians) == math.huge then
		error(`BufferWriter:writeAngle16 expects a finite number, got {tostring(radians)}`, 2)
	end
	local unit = (radians % TWO_PI) / TWO_PI
	local q = math.floor(unit * 65536 + 0.5) % 65536
	ensure(self, 2)
	buffer.writeu16(self._buf, self._len, q)
	self._len += 2
end

local function signNotZero(n: number): number
	return if n < 0 then -1 else 1
end

local function quantizeUnit(u: number): number
	local q = math.floor((math.clamp(u, -1, 1) + 1) * 0.5 * 65535 + 0.5)
	return q
end

--- Unit direction (any non-zero finite Vector3; normalized implicitly) as 4 bytes (octahedral encoding).
function WriterClass.writeUnitVector(self: BufferWriter, v: Vector3)
	if typeof(v) ~= "Vector3" then
		error(`BufferWriter:writeUnitVector expects a Vector3, got {typeof(v)}`, 2)
	end
	local x, y, z = v.X, v.Y, v.Z
	local l1 = math.abs(x) + math.abs(y) + math.abs(z)
	if l1 ~= l1 or l1 == math.huge then
		error("BufferWriter:writeUnitVector expects finite components", 2)
	end
	local px, py
	if l1 < 1e-12 then
		px, py = 0, 0
	else
		px, py = x / l1, y / l1
		if z < 0 then
			px, py = (1 - math.abs(py)) * signNotZero(px), (1 - math.abs(px)) * signNotZero(py)
		end
	end
	ensure(self, 4)
	buffer.writeu16(self._buf, self._len, quantizeUnit(px))
	buffer.writeu16(self._buf, self._len + 2, quantizeUnit(py))
	self._len += 4
end

--- Vector3 as three float32 (12 bytes).
function WriterClass.writeVector3(self: BufferWriter, v: Vector3)
	if typeof(v) ~= "Vector3" then
		error(`BufferWriter:writeVector3 expects a Vector3, got {typeof(v)}`, 2)
	end
	ensure(self, 12)
	buffer.writef32(self._buf, self._len, v.X)
	buffer.writef32(self._buf, self._len + 4, v.Y)
	buffer.writef32(self._buf, self._len + 8, v.Z)
	self._len += 12
end

--- Unsigned LEB128 for integers in [0, 2^53).
function WriterClass.writeVarUInt(self: BufferWriter, n: number)
	checkInt("writeVarUInt", n, 0, MAX_SAFE - 1)
	ensure(self, 8)
	local value = n
	while value >= 128 do
		buffer.writeu8(self._buf, self._len, value % 128 + 128)
		self._len += 1
		value = value // 128
	end
	buffer.writeu8(self._buf, self._len, value)
	self._len += 1
end

--- Signed integer (zigzag + LEB128), |n| <= 2^52.
function WriterClass.writeVarInt(self: BufferWriter, n: number)
	checkInt("writeVarInt", n, -MAX_SAFE / 2, MAX_SAFE / 2 - 1)
	local zigzag = if n >= 0 then n * 2 else -n * 2 - 1
	WriterClass.writeVarUInt(self, zigzag)
end

--- Length-prefixed (varUInt) byte string.
function WriterClass.writeString(self: BufferWriter, s: string)
	if type(s) ~= "string" then
		error(`BufferWriter:writeString expects a string, got {typeof(s)}`, 2)
	end
	local len = #s
	WriterClass.writeVarUInt(self, len)
	ensure(self, len)
	buffer.writestring(self._buf, self._len, s)
	self._len += len
end

--- Bytes written so far.
function WriterClass.length(self: BufferWriter): number
	return self._len
end

--- Copy of the written bytes as an exactly-sized buffer.
function WriterClass.toBuffer(self: BufferWriter): buffer
	local out = buffer.create(self._len)
	buffer.copy(out, 0, self._buf, 0, self._len)
	return out
end

--- Rewinds to empty, keeping capacity (reuse per tick).
function WriterClass.reset(self: BufferWriter)
	self._len = 0
end

local BufferWriter = {}

function BufferWriter.new(initialCapacity: number?): BufferWriter
	local cap = math.max(8, initialCapacity or 64)
	return setmetatable({ _buf = buffer.create(cap), _cap = cap, _len = 0 }, WriterClass)
end

return BufferWriter
