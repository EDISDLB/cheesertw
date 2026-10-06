--!strict
--[[
	Codecs/Battle/Chunker — splits a payload into unreliable packets of at most Protocol.MAX_UNRELIABLE_BYTES and
	reassembles them on the receiver, tolerating loss, reordering and duplication (ARCHITECTURE §5.2: "split if
	needed"). Used by SnapshotCodec; generic over the packet `kind` byte.

	Purpose:          split (sender) and Assembler:push (receiver). The stream's sequence number is the 32-bit
	                  `seq` (the server tick for snapshots), strictly increasing per stream: the assembler delivers a
	                  payload only when it is complete AND newer than the last delivered one, so a late or duplicate
	                  chunk can never roll the receiver back.
	Dependencies:     Net/Protocol, Core/Result, Net/ErrorCodes.
	State:            Assemblers hold at most `maxPending` partial payloads (oldest evicted) plus counters.
	Validation:       Every chunk is checked: buffer type, length > header and <= MAX_PACKET_BYTES, kind, count in
	                  1..MAX_CHUNKS, index < count, count consistent across chunks of one seq, non-empty payload.
	Error handling:   split raises on programming mistakes (oversized payload, bad seq/kind). Assembler:push never
	                  throws: malformed chunks return Err(INVALID_ARGS) and are counted.
	Performance notes: split allocates one buffer per chunk. A single-chunk payload is delivered without copying
	                  (the delivery points into the chunk); multi-chunk payloads are joined into one new buffer. The
	                  delivery record is reused by the assembler (valid until the next push).

	Chunk layout: u8 kind, u32 seq, u8 index (0-based), u8 count, then payload bytes (HEADER_BYTES = 7).
]]

local Protocol = require("../../Protocol")
local Result = require("../../../Core/Result")
local ErrorCodes = require("../../ErrorCodes")

type Result<T> = Result.Result<T>

local HEADER_BYTES = 7
local MAX_PACKET_BYTES = Protocol.MAX_UNRELIABLE_BYTES
local MAX_CHUNK_PAYLOAD = MAX_PACKET_BYTES - HEADER_BYTES
local MAX_CHUNKS = 4
local MAX_SEQ = 4294967295

export type Delivery = {
	seq: number,
	buffer: buffer,
	offset: number, -- payload start inside `buffer`
	length: number, -- payload bytes
}

export type AssemblerStats = {
	received: number, -- chunks pushed
	delivered: number, -- payloads delivered
	duplicates: number, -- chunks already held
	stale: number, -- chunks of a payload at or before the last delivered seq
	evicted: number, -- partial payloads dropped (superseded, or over maxPending)
	malformed: number,
}

type Pending = {
	seq: number,
	count: number,
	received: number,
	bytes: number,
	parts: { buffer? },
}

export type AssemblerOptions = {
	maxPending: number?, -- partial payloads kept (default 4)
}

local Chunker = {}

Chunker.HEADER_BYTES = HEADER_BYTES
Chunker.MAX_PACKET_BYTES = MAX_PACKET_BYTES
Chunker.MAX_CHUNK_PAYLOAD = MAX_CHUNK_PAYLOAD
Chunker.MAX_CHUNKS = MAX_CHUNKS
Chunker.MAX_PAYLOAD_BYTES = MAX_CHUNK_PAYLOAD * MAX_CHUNKS

--- Splits `length` bytes of `payload` (from offset 0) into chunks of near-equal size. Returns `out` (cleared) or a
--- new list.
function Chunker.split(kind: number, seq: number, payload: buffer, length: number, out: { buffer }?): { buffer }
	if type(kind) ~= "number" or kind ~= math.floor(kind) or kind < 0 or kind > 255 then
		error(`Chunker.split: kind must be a byte, got {tostring(kind)}`, 2)
	end
	if type(seq) ~= "number" or seq ~= math.floor(seq) or seq < 0 or seq > MAX_SEQ then
		error(`Chunker.split: seq must be a u32, got {tostring(seq)}`, 2)
	end
	if length < 1 or length > buffer.len(payload) then
		error(`Chunker.split: invalid payload length {length}`, 2)
	end
	local count = math.ceil(length / MAX_CHUNK_PAYLOAD)
	if count > MAX_CHUNKS then
		error(`Chunker.split: payload of {length} bytes exceeds {Chunker.MAX_PAYLOAD_BYTES}`, 2)
	end
	local list = out or {}
	table.clear(list)
	-- Near-equal chunks: a lost chunk costs the same whichever it is, and every packet stays small.
	local base = length // count
	local extra = length % count
	local offset = 0
	for index = 0, count - 1 do
		local size = base + (if index < extra then 1 else 0)
		local chunk = buffer.create(HEADER_BYTES + size)
		buffer.writeu8(chunk, 0, kind)
		buffer.writeu32(chunk, 1, seq)
		buffer.writeu8(chunk, 5, index)
		buffer.writeu8(chunk, 6, count)
		buffer.copy(chunk, HEADER_BYTES, payload, offset, size)
		offset += size
		table.insert(list, chunk)
	end
	return list
end

--- Parses a chunk header: (seq, index, count) or (nil, reason). Never throws.
function Chunker.parseHeader(kind: number, value: unknown): (number?, number | string, number?)
	if type(value) ~= "buffer" then
		return nil, `expected buffer, got {typeof(value)}`, nil
	end
	local b = value :: buffer
	local len = buffer.len(b)
	if len <= HEADER_BYTES or len > MAX_PACKET_BYTES then
		return nil, `bad chunk length {len}`, nil
	end
	if buffer.readu8(b, 0) ~= kind then
		return nil, "bad chunk kind", nil
	end
	local index = buffer.readu8(b, 5)
	local count = buffer.readu8(b, 6)
	if count < 1 or count > MAX_CHUNKS or index >= count then
		return nil, `bad chunk index {index}/{count}`, nil
	end
	return buffer.readu32(b, 1), index, count
end

local AssemblerClass = {}
AssemblerClass.__index = AssemblerClass

export type Assembler = typeof(setmetatable(
	{} :: {
		kind: number,
		maxPending: number,
		lastSeq: number?,
		pending: { Pending },
		stats: AssemblerStats,
		_delivery: Delivery,
	},
	AssemblerClass
))

local function malformed(self: Assembler, reason: string): Result<Delivery?>
	self.stats.malformed += 1
	return Result.err(ErrorCodes.INVALID_ARGS, reason)
end

local function removePending(self: Assembler, i: number)
	table.remove(self.pending, i)
end

--- Feeds one received chunk. Ok(delivery) when it completes a payload newer than the last delivered one; Ok(nil)
--- while incomplete, for duplicates and for stale chunks; Err(INVALID_ARGS) for malformed chunks.
function AssemblerClass.push(self: Assembler, value: unknown): Result<Delivery?>
	self.stats.received += 1
	local seq, indexOrReason, count = Chunker.parseHeader(self.kind, value)
	if seq == nil or count == nil then
		return malformed(self, tostring(indexOrReason))
	end
	local index = indexOrReason :: number
	local chunk = value :: buffer
	local last = self.lastSeq
	if last ~= nil and seq <= last then
		self.stats.stale += 1
		return Result.ok(nil)
	end
	local size = buffer.len(chunk) - HEADER_BYTES
	local delivery = self._delivery
	if count == 1 then
		-- Complete on its own: drop older partials (they can never be delivered any more).
		for i = #self.pending, 1, -1 do
			if self.pending[i].seq <= seq then
				removePending(self, i)
				self.stats.evicted += 1
			end
		end
		self.lastSeq = seq
		self.stats.delivered += 1
		delivery.seq, delivery.buffer, delivery.offset, delivery.length = seq, chunk, HEADER_BYTES, size
		return Result.ok(delivery)
	end
	local entry: Pending? = nil
	local entryIndex = 0
	for i, p in self.pending do
		if p.seq == seq then
			entry, entryIndex = p, i
			break
		end
	end
	if entry == nil then
		if #self.pending >= self.maxPending then
			-- Evict the oldest partial payload (lowest seq).
			local oldest = 1
			for i, p in self.pending do
				if p.seq < self.pending[oldest].seq then
					oldest = i
				end
			end
			removePending(self, oldest)
			self.stats.evicted += 1
		end
		local fresh: Pending = { seq = seq, count = count, received = 0, bytes = 0, parts = table.create(count) }
		table.insert(self.pending, fresh)
		entry, entryIndex = fresh, #self.pending
	end
	local p = entry :: Pending
	if p.count ~= count then
		return malformed(self, `chunk count {count} disagrees with {p.count} for seq {seq}`)
	end
	if p.parts[index + 1] ~= nil then
		self.stats.duplicates += 1
		return Result.ok(nil)
	end
	p.parts[index + 1] = chunk
	p.received += 1
	p.bytes += size
	if p.received < p.count then
		return Result.ok(nil)
	end
	-- Complete: join, deliver, and drop this and every older partial payload.
	local joined = buffer.create(p.bytes)
	local offset = 0
	for i = 1, p.count do
		local part = p.parts[i] :: buffer
		local partSize = buffer.len(part) - HEADER_BYTES
		buffer.copy(joined, offset, part, HEADER_BYTES, partSize)
		offset += partSize
	end
	removePending(self, entryIndex)
	for i = #self.pending, 1, -1 do
		if self.pending[i].seq < seq then
			removePending(self, i)
			self.stats.evicted += 1
		end
	end
	self.lastSeq = seq
	self.stats.delivered += 1
	delivery.seq, delivery.buffer, delivery.offset, delivery.length = seq, joined, 0, p.bytes
	return Result.ok(delivery)
end

--- Forgets everything (new stream, e.g. a new battle).
function AssemblerClass.reset(self: Assembler)
	self.lastSeq = nil
	table.clear(self.pending)
end

--- Partial payloads currently held.
function AssemblerClass.pendingCount(self: Assembler): number
	return #self.pending
end

--- A receiver for packets of `kind`.
function Chunker.newAssembler(kind: number, options: AssemblerOptions?): Assembler
	local maxPending = if options ~= nil and options.maxPending ~= nil then options.maxPending else 4
	assert(type(maxPending) == "number" and maxPending >= 1, "Chunker.newAssembler: maxPending must be >= 1")
	return setmetatable({
		kind = kind,
		maxPending = maxPending,
		lastSeq = nil :: number?,
		pending = {},
		stats = { received = 0, delivered = 0, duplicates = 0, stale = 0, evicted = 0, malformed = 0 },
		_delivery = { seq = 0, buffer = buffer.create(0), offset = 0, length = 0 },
	}, AssemblerClass)
end

return table.freeze(Chunker)
