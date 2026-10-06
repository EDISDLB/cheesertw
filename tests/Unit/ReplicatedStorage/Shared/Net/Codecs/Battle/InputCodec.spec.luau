-- BattleInput codec: round trips, quantization bounds, canonical-layout validation, hostile fuzz and exactly-once
-- sequencing. QA ids: REG-NET-02 (size, stale packets ignored, redundant inputs applied once), REG-NET-05 (fuzz:
-- clean Err, never a throw, never a non-finite value), REG-NET-06 (axes bounded to [-1, 1]).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local InputCodec = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/InputCodec")
local Quantize = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Quantize")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

type InputCommand = {
	seq: number,
	throttle: number,
	steer: number,
	aimPoint: Vector3,
	fire: boolean,
	holdTurret: boolean,
	brake: boolean,
	mechanic: boolean,
}

local function command(seq: number, overrides: { [string]: any }?): InputCommand
	local c: InputCommand = {
		seq = seq,
		throttle = 0.5,
		steer = -0.25,
		aimPoint = Vector3.new(120.5, 10.25, -300.75),
		fire = false,
		holdTurret = false,
		brake = false,
		mechanic = false,
	}
	if overrides then
		for k, v in overrides do
			(c :: any)[k] = v
		end
	end
	return c
end

local function randomCommand(rng: any, seq: number): InputCommand
	return {
		seq = seq,
		throttle = rng:range(-1, 1),
		steer = rng:range(-1, 1),
		aimPoint = Vector3.new(rng:range(-7500, 7500), rng:range(-600, 6000), rng:range(-7500, 7500)),
		fire = rng:chance(0.5),
		holdTurret = rng:chance(0.5),
		brake = rng:chance(0.5),
		mechanic = rng:chance(0.5),
	}
end

local function history(newest: number, n: number, rng: any): { InputCommand }
	local list = {}
	for i = 1, n do
		list[i] = randomCommand(rng, newest - (i - 1))
	end
	return list
end

local function decodeOk(b: buffer): any
	local r = InputCodec.decode(b)
	if not r.ok then
		error(`decode failed: {tostring((r :: any).detail)}`)
	end
	return r.value
end

describe("InputCodec layout", function()
	it("is 16/28/40 bytes for 1/2/3 commands (<= 64 B, REG-NET-02)", function()
		local rng = RNG.new(1)
		for n = 1, 3 do
			local b = InputCodec.encode(history(100, n, rng))
			expect(buffer.len(b)).toBe(4 + 12 * n)
		end
		expect(InputCodec.MAX_BYTES).toBe(40)
		expect(InputCodec.MAX_BYTES <= 64).toBe(true)
		-- extra history is ignored
		expect(buffer.len(InputCodec.encode(history(100, 6, rng)))).toBe(40)
		expect(buffer.len(InputCodec.encode(history(100, 3, rng), 2))).toBe(28)
	end)

	it("writes the documented header", function()
		local b = InputCodec.encode({ command(70000), command(69999) })
		expect(buffer.readu8(b, 0)).toBe(InputCodec.PACKET_KIND)
		expect(buffer.readu16(b, 1)).toBe(70000 % 65536)
		expect(buffer.readu8(b, 3)).toBe(2)
	end)

	it("drops history after the first sequence gap and wraps sequences at 2^16", function()
		local b = InputCodec.encode({ command(10), command(9), command(7) })
		expect(buffer.readu8(b, 3)).toBe(2)
		local wrapped = InputCodec.encode({ command(65536), command(65535), command(65534) })
		local batch = decodeOk(wrapped)
		expect(batch.count).toBe(3)
		expect(batch.seq).toBe(0)
		expect(batch.commands[2].seq).toBe(65535)
		expect(batch.commands[3].seq).toBe(65534)
	end)

	it("raises on programming mistakes only", function()
		expect(function()
			InputCodec.encode({})
		end).toThrow("at least one command")
		expect(function()
			InputCodec.encode({ command(1.5) })
		end).toThrow("seq must be an integer")
		expect(function()
			InputCodec.encode({ command(0 / 0) })
		end).toThrow("seq must be an integer")
	end)
end)

describe("InputCodec round trip", function()
	it("restores random commands within the quantization bounds (5k packets)", function()
		local rng = RNG.new(42)
		local out = InputCodec.newBatch()
		for _ = 1, 5000 do
			local newest = rng:int(0, 200000)
			local n = rng:int(1, 3)
			local cmds = history(newest, n, rng)
			local r = InputCodec.decode(InputCodec.encode(cmds), out)
			expect(r.ok).toBe(true)
			local batch = (r :: any).value
			expect(batch).toBe(out)
			expect(batch.count).toBe(n)
			expect(batch.seq).toBe(newest % 65536)
			for i = 1, n do
				local a, b = cmds[i], batch.commands[i]
				if b.seq ~= (newest - i + 1) % 65536 then
					error("seq mismatch")
				end
				if math.abs(a.throttle - b.throttle) > Quantize.AXIS_ERROR + 1e-12 then
					error("throttle error too large")
				end
				if math.abs(a.steer - b.steer) > Quantize.AXIS_ERROR + 1e-12 then
					error("steer error too large")
				end
				local d = a.aimPoint - b.aimPoint
				-- grid error + float32 rounding of the source Vector3
				if math.abs(d.X) > 0.003 or math.abs(d.Y) > 0.003 or math.abs(d.Z) > 0.003 then
					error(`aim error {d}`)
				end
				if a.fire ~= b.fire or a.holdTurret ~= b.holdTurret or a.brake ~= b.brake or a.mechanic ~= b.mechanic then
					error("flag mismatch")
				end
			end
		end
	end)

	it("clamps out-of-range axes and saturates far aim points (REG-NET-06)", function()
		local batch = decodeOk(InputCodec.encode({
			command(5, { throttle = 7, steer = -0 / 1 - 3, aimPoint = Vector3.new(1e7, -1e7, 5) }),
		}))
		local c = batch.commands[1]
		expect(c.throttle).toBe(1)
		expect(c.steer).toBe(-1)
		expect(c.aimPoint.X).toBeCloseTo(Quantize.POS_LIMIT, 1e-2)
		expect(c.aimPoint.Y).toBeCloseTo(-8388608 / 256, 1e-2)
		local nanBatch = decodeOk(InputCodec.encode({ command(6, { throttle = 0 / 0 }) }))
		expect(nanBatch.commands[1].throttle).toBe(0)
	end)

	it("decode -> encode is the identity on every accepted packet (canonical layout)", function()
		local rng = RNG.new(3)
		for _ = 1, 500 do
			local b = InputCodec.encode(history(rng:int(0, 65535), rng:int(1, 3), rng))
			local batch = decodeOk(b)
			local again = InputCodec.encode(batch.commands, batch.count)
			expect(buffer.tostring(again)).toBe(buffer.tostring(b))
		end
	end)
end)

describe("InputCodec hostile input (REG-NET-05)", function()
	local function bytes(list: { number }): buffer
		local b = buffer.create(#list)
		for i, v in list do
			buffer.writeu8(b, i - 1, v)
		end
		return b
	end

	it("rejects non-buffers and malformed layouts with Err(INVALID_ARGS)", function()
		local valid = InputCodec.encode({ command(9), command(8) })
		local cases: { any } = {
			nil,
			true,
			42,
			0 / 0,
			"I\0\0\1",
			{ 73, 0, 0, 1 },
			Vector3.zero,
			buffer.create(0),
			buffer.create(15),
			buffer.create(41),
			buffer.create(1000),
		}
		for _, v in cases do
			expect(InputCodec.decode(v)).toBeErr("INVALID_ARGS")
			local ok = InputCodec.validate(v)
			expect(ok).toBe(false)
		end
		local function mutate(offset: number, value: number): buffer
			local b = buffer.create(buffer.len(valid))
			buffer.copy(b, 0, valid)
			buffer.writeu8(b, offset, value)
			return b
		end
		expect(InputCodec.decode(mutate(0, 0x48))).toBeErr("INVALID_ARGS") -- packet kind
		expect(InputCodec.decode(mutate(3, 0))).toBeErr("INVALID_ARGS") -- count 0
		expect(InputCodec.decode(mutate(3, 3))).toBeErr("INVALID_ARGS") -- count vs length
		expect(InputCodec.decode(mutate(3, 4))).toBeErr("INVALID_ARGS") -- count > 3
		expect(InputCodec.decode(mutate(4, 0x80))).toBeErr("INVALID_ARGS") -- throttle -128
		expect(InputCodec.decode(mutate(17, 0x80))).toBeErr("INVALID_ARGS") -- second steer -128
		expect(InputCodec.decode(mutate(15, 0x10))).toBeErr("INVALID_ARGS") -- reserved flag bit
		local truncated = buffer.create(buffer.len(valid) - 1)
		buffer.copy(truncated, 0, valid, 0, buffer.len(truncated))
		expect(InputCodec.decode(truncated)).toBeErr("INVALID_ARGS")
		expect(InputCodec.decode(bytes({ 0x49, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }))).toBeOk()
	end)

	it("10k random and mutated packets: never throws, validate == decode, accepted values are bounded", function()
		local rng = RNG.new(2024)
		local out = InputCodec.newBatch()
		local accepted = 0
		for i = 1, 10000 do
			local b: buffer
			if i % 2 == 0 then
				local len = rng:int(0, 48)
				b = buffer.create(len)
				for j = 0, len - 1 do
					buffer.writeu8(b, j, rng:int(0, 255))
				end
				-- bias toward the right kind/count so deep paths are exercised
				if len >= 4 and rng:chance(0.7) then
					buffer.writeu8(b, 0, InputCodec.PACKET_KIND)
					buffer.writeu8(b, 3, rng:int(0, 4))
				end
			else
				local src = InputCodec.encode(history(rng:int(0, 65535), rng:int(1, 3), rng))
				b = buffer.create(buffer.len(src))
				buffer.copy(b, 0, src)
				for _ = 1, rng:int(1, 3) do
					local at = rng:int(0, buffer.len(b) - 1)
					buffer.writeu8(b, at, bit32.bxor(buffer.readu8(b, at), 2 ^ rng:int(0, 7)))
				end
			end
			local called, r = pcall(InputCodec.decode, b, out)
			if not called then
				error(`decode threw: {tostring(r)}`)
			end
			local valid = InputCodec.validate(b)
			if valid ~= r.ok then
				error("validate disagrees with decode")
			end
			if r.ok then
				accepted += 1
				local batch = r.value
				for k = 1, batch.count do
					local c = batch.commands[k]
					if not (c.throttle >= -1 and c.throttle <= 1 and c.steer >= -1 and c.steer <= 1) then
						error("axis out of range")
					end
					local a = c.aimPoint
					for _, v in { a.X, a.Y, a.Z } do
						if v ~= v or math.abs(v) > 32768 then
							error("aim not finite/bounded")
						end
					end
				end
			elseif r.err ~= "INVALID_ARGS" then
				error(`unexpected error code {r.err}`)
			end
		end
		expect(accepted > 100).toBe(true)
	end)
end)

describe("InputCodec sequencing (REG-NET-02)", function()
	it("unwraps 16-bit sequences around a reference", function()
		expect(InputCodec.unwrapSeq(5, 65530)).toBe(65541)
		expect(InputCodec.unwrapSeq(65530, 65541)).toBe(65530)
		expect(InputCodec.unwrapSeq(100, 100)).toBe(100)
		expect(InputCodec.unwrapSeq(0, 0)).toBe(0)
		expect(InputCodec.unwrapSeq(32768, 0)).toBe(32768) -- ties go forward
		expect(InputCodec.unwrapSeq(32769, 0)).toBe(-32767)
		expect(InputCodec.unwrapSeq(7, 3 * 65536 + 10)).toBe(3 * 65536 + 7)
	end)

	it("yields only unseen commands, oldest first, with full sequence numbers", function()
		local out = {}
		local batch = decodeOk(InputCodec.encode({ command(102), command(101), command(100) }))
		expect(InputCodec.newCommands(batch, 100, out)).toBe(2)
		expect(out[1].seq).toBe(101)
		expect(out[2].seq).toBe(102)
		expect(InputCodec.newCommands(batch, 102, out)).toBe(0) -- duplicate packet
		expect(InputCodec.newCommands(batch, 150, out)).toBe(0) -- stale packet
		expect(InputCodec.newCommands(batch, 90, out)).toBe(3) -- gap: everything still available
		expect(out[1].seq).toBe(100)
		expect(InputCodec.newCommands(batch, nil, out)).toBe(3)
		local first = decodeOk(InputCodec.encode({ command(1), command(0) }))
		expect(InputCodec.newCommands(first, nil, out)).toBe(2)
		local zero = decodeOk(InputCodec.encode({ command(0) }))
		expect(InputCodec.newCommands(zero, nil, out)).toBe(1)
		expect(out[1].seq).toBe(0)
		local wrapped = decodeOk(InputCodec.encode({ command(65537), command(65536), command(65535) }))
		expect(InputCodec.newCommands(wrapped, 65535, out)).toBe(2)
		expect(out[1].seq).toBe(65536)
		expect(out[2].seq).toBe(65537)
	end)

	it("applies every input exactly once under loss, duplication and reordering (seeded stream)", function()
		local rng = RNG.new(77)
		local sent: { buffer } = {}
		local cmds: { InputCommand } = {}
		local total = 3000
		for seq = 0, total - 1 do
			table.insert(cmds, 1, randomCommand(rng, seq))
			if #cmds > 3 then
				cmds[4] = nil
			end
			table.insert(sent, InputCodec.encode(cmds))
		end
		-- network: 15 % loss, 10 % duplicates, local reordering within 2 packets
		local wire: { buffer } = {}
		for _, b in sent do
			if not rng:chance(0.15) then
				table.insert(wire, b)
				if rng:chance(0.10) then
					table.insert(wire, b)
				end
			end
		end
		for i = 1, #wire - 1 do
			if rng:chance(0.2) then
				wire[i], wire[i + 1] = wire[i + 1], wire[i]
			end
		end
		local lastSeq: number? = nil
		local applied: { [number]: number } = {}
		local out = {}
		local batch = InputCodec.newBatch()
		local previous = -1
		for _, b in wire do
			local r = InputCodec.decode(b, batch)
			assert(r.ok, "decode")
			local n = InputCodec.newCommands(batch, lastSeq, out)
			for k = 1, n do
				local s = out[k].seq
				applied[s] = (applied[s] or 0) + 1
				if s <= previous then
					error(`out-of-order apply {s} after {previous}`)
				end
				previous = s
			end
			if n > 0 then
				lastSeq = out[n].seq
			end
		end
		local missing = 0
		for seq = 0, total - 1 do
			local count = applied[seq] or 0
			if count > 1 then
				error(`seq {seq} applied {count} times`)
			end
			if count == 0 then
				missing += 1
			end
		end
		-- with 3x redundancy only bursts of >= 3 consecutive losses lose inputs
		expect(missing < total * 0.02).toBe(true)
	end)
end)
