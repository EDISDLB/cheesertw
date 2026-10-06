-- Chunker: <= 900-byte packets, near-equal split, loss/reorder/duplicate-tolerant reassembly that never rolls back,
-- and malformed chunks rejected cleanly. QA ids: REG-NET-02 (packet size limit), REG-NET-05 (fuzz never throws).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Chunker = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Chunker")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local KIND = 0x53

local function payload(rng: any, len: number): buffer
	local b = buffer.create(len)
	local i = 0
	while i + 4 <= len do
		buffer.writeu32(b, i, rng:nextU32())
		i += 4
	end
	while i < len do
		buffer.writeu8(b, i, rng:int(0, 255))
		i += 1
	end
	return b
end

local function deliveredBytes(d: any): string
	return buffer.readstring(d.buffer, d.offset, d.length)
end

describe("Chunker.split", function()
	it("keeps every packet <= 900 bytes and splits into near-equal chunks", function()
		local rng = RNG.new(5)
		expect(Chunker.MAX_PACKET_BYTES).toBe(900)
		for _, len in { 1, 2, 892, 893, 894, 1500, 1786, 1787, 2679, 3000, Chunker.MAX_PAYLOAD_BYTES } do
			local chunks = Chunker.split(KIND, 7, payload(rng, len), len)
			expect(#chunks).toBe(math.ceil(len / Chunker.MAX_CHUNK_PAYLOAD))
			local minSize, maxSize, total = math.huge, 0, 0
			for i, c in chunks do
				local size = buffer.len(c)
				expect(size <= 900).toBe(true)
				expect(buffer.readu8(c, 0)).toBe(KIND)
				expect(buffer.readu32(c, 1)).toBe(7)
				expect(buffer.readu8(c, 5)).toBe(i - 1)
				expect(buffer.readu8(c, 6)).toBe(#chunks)
				minSize = math.min(minSize, size)
				maxSize = math.max(maxSize, size)
				total += size - Chunker.HEADER_BYTES
			end
			expect(total).toBe(len)
			expect(maxSize - minSize <= 1).toBe(true)
		end
	end)

	it("splits only the first `length` bytes and reuses the output list", function()
		local b = buffer.create(100)
		buffer.writeu8(b, 0, 9)
		local out = { buffer.create(1), buffer.create(1), buffer.create(1) }
		local chunks = Chunker.split(KIND, 1, b, 1, out)
		expect(chunks).toBe(out)
		expect(#chunks).toBe(1)
		expect(buffer.len(chunks[1])).toBe(Chunker.HEADER_BYTES + 1)
	end)

	it("raises on programming mistakes", function()
		local b = buffer.create(Chunker.MAX_PAYLOAD_BYTES + 1)
		expect(function()
			Chunker.split(KIND, 1, b, buffer.len(b))
		end).toThrow("exceeds")
		expect(function()
			Chunker.split(KIND, -1, b, 10)
		end).toThrow("seq must be a u32")
		expect(function()
			Chunker.split(KIND, 2 ^ 32, b, 10)
		end).toThrow("seq must be a u32")
		expect(function()
			Chunker.split(256, 1, b, 10)
		end).toThrow("kind must be a byte")
		expect(function()
			Chunker.split(KIND, 1, b, 0)
		end).toThrow("invalid payload length")
	end)
end)

describe("Chunker assembler", function()
	it("delivers single-chunk payloads without copying", function()
		local a = Chunker.newAssembler(KIND)
		local src = payload(RNG.new(1), 50)
		local chunks = Chunker.split(KIND, 10, src, 50)
		local r = a:push(chunks[1])
		expect(r).toBeOk()
		local d = (r :: any).value
		expect(d.seq).toBe(10)
		expect(d.buffer).toBe(chunks[1])
		expect(d.offset).toBe(Chunker.HEADER_BYTES)
		expect(deliveredBytes(d)).toBe(buffer.tostring(src))
	end)

	it("reassembles out-of-order chunks and ignores duplicates", function()
		local rng = RNG.new(2)
		local a = Chunker.newAssembler(KIND)
		local src = payload(rng, 2000)
		local c = Chunker.split(KIND, 11, src, 2000)
		expect(#c).toBe(3)
		expect((a:push(c[3]) :: any).value).toBeNil()
		expect((a:push(c[1]) :: any).value).toBeNil()
		expect((a:push(c[3]) :: any).value).toBeNil()
		expect(a.stats.duplicates).toBe(1)
		local d = (a:push(c[2]) :: any).value
		expect(d).never.toBeNil()
		expect(deliveredBytes(d)).toBe(buffer.tostring(src))
		expect(a:pendingCount()).toBe(0)
		-- a late duplicate of a delivered payload is stale
		expect((a:push(c[1]) :: any).value).toBeNil()
		expect(a.stats.stale).toBe(1)
	end)

	it("never rolls back: an older payload completing after a newer one is dropped", function()
		local rng = RNG.new(3)
		local a = Chunker.newAssembler(KIND)
		local old = Chunker.split(KIND, 20, payload(rng, 1000), 1000)
		local new = Chunker.split(KIND, 21, payload(rng, 1000), 1000)
		expect((a:push(old[1]) :: any).value).toBeNil()
		expect((a:push(new[1]) :: any).value).toBeNil()
		expect((a:push(new[2]) :: any).value.seq).toBe(21)
		expect(a.stats.evicted).toBe(1) -- the partial seq 20 can never be delivered any more
		expect((a:push(old[2]) :: any).value).toBeNil()
		expect(a.lastSeq).toBe(21)
	end)

	it("bounds memory: at most maxPending partial payloads", function()
		local rng = RNG.new(4)
		local a = Chunker.newAssembler(KIND, { maxPending = 2 })
		for seq = 1, 10 do
			a:push(Chunker.split(KIND, seq, payload(rng, 1000), 1000)[1])
			expect(a:pendingCount() <= 2).toBe(true)
		end
		expect(a.stats.evicted).toBe(8)
		a:reset()
		expect(a:pendingCount()).toBe(0)
		expect(a.lastSeq).toBeNil()
	end)

	it("rejects malformed chunks with Err(INVALID_ARGS) and counts them", function()
		local a = Chunker.newAssembler(KIND)
		local function chunk(kind: number, seq: number, index: number, count: number, len: number): buffer
			local b = buffer.create(len)
			if len >= 7 then
				buffer.writeu8(b, 0, kind)
				buffer.writeu32(b, 1, seq)
				buffer.writeu8(b, 5, index)
				buffer.writeu8(b, 6, count)
			end
			return b
		end
		expect(a:push(nil)).toBeErr("INVALID_ARGS")
		local cases: { any } = {
			"chunk",
			{},
			buffer.create(0),
			chunk(KIND, 1, 0, 1, 7), -- header only
			chunk(KIND, 1, 0, 1, 901), -- too long
			chunk(0x45, 1, 0, 1, 20), -- wrong kind
			chunk(KIND, 1, 0, 0, 20), -- count 0
			chunk(KIND, 1, 2, 2, 20), -- index >= count
			chunk(KIND, 1, 0, 5, 20), -- count > MAX_CHUNKS
		}
		for _, v in cases do
			expect(a:push(v)).toBeErr("INVALID_ARGS")
		end
		expect(a.stats.malformed).toBe(#cases + 1)
		-- inconsistent counts for one seq
		expect(a:push(chunk(KIND, 5, 0, 2, 20))).toBeOk()
		expect(a:push(chunk(KIND, 5, 1, 3, 20))).toBeErr("INVALID_ARGS")
	end)

	it("property: random loss, duplication and reordering deliver strictly newer, byte-exact payloads", function()
		local rng = RNG.new(99)
		local a = Chunker.newAssembler(KIND)
		local originals: { [number]: string } = {}
		local wire: { buffer } = {}
		for seq = 1, 600 do
			local len = rng:int(1, Chunker.MAX_PAYLOAD_BYTES)
			local src = payload(rng, len)
			originals[seq] = buffer.tostring(src)
			for _, c in Chunker.split(KIND, seq, src, len) do
				if not rng:chance(0.1) then
					table.insert(wire, c)
					if rng:chance(0.05) then
						table.insert(wire, c)
					end
				end
			end
		end
		for i = 1, #wire - 1 do
			if rng:chance(0.3) then
				local j = math.min(#wire, i + rng:int(1, 4))
				wire[i], wire[j] = wire[j], wire[i]
			end
		end
		local last = 0
		local delivered = 0
		for _, c in wire do
			local r = a:push(c)
			expect(r.ok).toBe(true)
			local d = (r :: any).value
			if d ~= nil then
				if d.seq <= last then
					error(`delivered {d.seq} after {last}`)
				end
				last = d.seq
				delivered += 1
				if deliveredBytes(d) ~= originals[d.seq] then
					error(`payload {d.seq} corrupted`)
				end
			end
			if a:pendingCount() > 4 then
				error("pending not bounded")
			end
		end
		expect(delivered > 200).toBe(true)
	end)

	it("10k hostile buffers never throw", function()
		local rng = RNG.new(31337)
		local a = Chunker.newAssembler(KIND)
		for _ = 1, 10000 do
			local len = rng:int(0, 950)
			local b = buffer.create(len)
			for j = 0, math.min(len, 16) - 1 do
				buffer.writeu8(b, j, rng:int(0, 255))
			end
			if len > 0 and rng:chance(0.6) then
				buffer.writeu8(b, 0, KIND)
			end
			if len > 6 and rng:chance(0.6) then
				buffer.writeu8(b, 6, rng:int(1, 4))
				buffer.writeu8(b, 5, rng:int(0, 3))
			end
			local called, r = pcall(a.push, a, b)
			if not called then
				error(`push threw: {tostring(r)}`)
			end
			if not r.ok and r.err ~= "INVALID_ARGS" then
				error("unexpected error code")
			end
		end
		expect(a:pendingCount() <= 4).toBe(true)
	end)
end)
