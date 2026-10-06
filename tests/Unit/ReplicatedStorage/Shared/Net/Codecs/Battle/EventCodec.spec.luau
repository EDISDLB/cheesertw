-- EventCodec: every event type round-trips, batches split on size / tick span / count while preserving order,
-- encoders reject programming mistakes, decoders reject hostile batches cleanly. QA ids: REG-NET-05 (fuzz never
-- throws), REG-SPT-08 (an unseen attacker is encoded as entity 0 and cannot be recovered from the bytes).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local EventCodec = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/EventCodec")
local Enums = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Enums")
local Quantize = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Quantize")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local function pick(rng: any, list: { string }): any
	return list[rng:int(1, #list)]
end

local function unit(rng: any): Vector3
	local v = Vector3.new(rng:range(-1, 1), rng:range(-1, 1), rng:range(-1, 1))
	if v.Magnitude < 0.01 then
		return Vector3.new(0, 0, 1)
	end
	return v.Unit
end

local function point(rng: any): Vector3
	return Vector3.new(rng:range(-4500, 4500), rng:range(-100, 400), rng:range(-4500, 4500))
end

local function randomEvent(rng: any, kind: string, tick: number): any
	local id = function()
		return rng:int(0, 30)
	end
	if kind == "ShotFired" then
		return {
			type = kind,
			tick = tick,
			shooter = id(),
			shotId = rng:int(0, 70000),
			shellIndex = rng:int(0, 3),
			shellKind = pick(rng, Enums.ShellKind.values),
			caliberMm = rng:int(20, 240) + rng:int(0, 9) / 10,
			origin = point(rng),
			direction = unit(rng),
			speedMps = rng:int(100, 1700),
			gravityMps2 = rng:int(500, 3000) / 100,
			volley = rng:chance(0.2),
			charged = rng:chance(0.2),
			tracerOnly = rng:chance(0.2),
		}
	elseif kind == "ShotHeard" then
		return {
			type = kind,
			tick = tick,
			caliberClass = pick(rng, Enums.CaliberClass.values),
			x = rng:int(-4500, 4500),
			z = rng:int(-4500, 4500),
		}
	elseif kind == "ShotResult" then
		return {
			type = kind,
			tick = tick,
			shotId = rng:int(0, 65535),
			target = id(),
			attacker = id(),
			result = pick(rng, Enums.ShotResult.values),
			damage = rng:int(0, 1500),
			critical = rng:chance(0.3),
			fireStarted = rng:chance(0.1),
			killed = rng:chance(0.1),
			point = point(rng),
			direction = unit(rng),
		}
	elseif kind == "ModuleState" then
		return {
			type = kind,
			tick = tick,
			target = id(),
			module = pick(rng, Enums.ModuleKind.values),
			state = pick(rng, Enums.ModuleState.values),
			attacker = id(),
		}
	elseif kind == "CrewInjured" then
		return {
			type = kind,
			tick = tick,
			target = id(),
			slot = rng:int(1, 6),
			role = pick(rng, Enums.CrewRole.values),
			healed = rng:chance(0.5),
		}
	elseif kind == "Damage" then
		return {
			type = kind,
			tick = tick,
			target = id(),
			attacker = id(),
			kind = pick(rng, Enums.DamageKind.values),
			damage = rng:int(0, 900),
		}
	elseif kind == "Destroyed" then
		return { type = kind, tick = tick, target = id(), attacker = id(), cause = pick(rng, Enums.DamageKind.values) }
	elseif kind == "Spotted" then
		return { type = kind, tick = tick, target = id(), spotter = id(), first = rng:chance(0.5) }
	elseif kind == "Lost" then
		return { type = kind, tick = tick, target = id(), x = rng:int(-4500, 4500), z = rng:int(-4500, 4500) }
	elseif kind == "SixthSense" then
		return { type = kind, tick = tick }
	elseif kind == "Fire" then
		return { type = kind, tick = tick, target = id(), burning = rng:chance(0.5) }
	elseif kind == "Stunned" then
		return { type = kind, tick = tick, target = id(), durationS = rng:int(0, 2000) / 100 }
	elseif kind == "ConsumableUsed" then
		local ids = { "repair_kit_small", "medkit_large", "extinguisher_auto", "x" }
		return { type = kind, tick = tick, participant = id(), consumable = pick(rng, ids) }
	elseif kind == "Command" then
		return {
			type = kind,
			tick = tick,
			sender = id(),
			command = pick(rng, Enums.QuickCommand.values),
			targetId = id(),
			hasPoint = rng:chance(0.5),
			x = rng:int(-4500, 4500),
			z = rng:int(-4500, 4500),
		}
	elseif kind == "Ping" then
		return {
			type = kind,
			tick = tick,
			sender = id(),
			ping = pick(rng, Enums.PingKind.values),
			x = rng:int(-4500, 4500),
			z = rng:int(-4500, 4500),
		}
	elseif kind == "Ribbon" then
		return {
			type = kind,
			tick = tick,
			ribbon = pick(rng, Enums.RibbonKind.values),
			value = rng:int(0, 5000),
			target = id(),
		}
	elseif kind == "Notice" then
		return { type = kind, tick = tick, notice = pick(rng, Enums.NoticeKind.values) }
	end
	error("unknown kind " .. kind)
end

local function check(cond: boolean, message: string)
	if not cond then
		error(message, 2)
	end
end

local function compareEvent(a: any, b: any)
	check(a.type == b.type and a.tick == b.tick, `type/tick mismatch {a.type}`)
	for key, value in a do
		local got = b[key]
		if key == "shotId" then
			check(got == value % 65536, "shotId")
		elseif key == "origin" or key == "point" then
			local d = got - value
			check(
				math.abs(d.X) <= Quantize.POS_ERROR + 1e-3
					and math.abs(d.Y) <= Quantize.POS_ERROR + 1e-4
					and math.abs(d.Z) <= Quantize.POS_ERROR + 1e-3,
				`{key} error {d}`
			)
		elseif key == "direction" then
			check((got - value).Magnitude < 2e-4, "direction")
		elseif key == "caliberMm" then
			check(math.abs(got - value) <= 0.05 + 1e-9, "caliber")
		elseif key == "gravityMps2" or key == "durationS" then
			check(math.abs(got - value) <= 0.005 + 1e-9, key)
		else
			check(got == value, `{a.type}.{key}: {tostring(got)} vs {tostring(value)}`)
		end
	end
	for key in b do
		check(a[key] ~= nil, `{a.type}: unexpected decoded key {key}`)
	end
end

local function roundTrip(events: { any }): { any }
	local decoded = {}
	for _, batch in EventCodec.encode(events) do
		check(buffer.len(batch) <= EventCodec.MAX_BATCH_BYTES, "batch too large")
		local r = EventCodec.decode(batch)
		if not r.ok then
			error(`decode failed: {tostring((r :: any).detail)}`)
		end
		for _, e in (r :: any).value do
			table.insert(decoded, e)
		end
	end
	return decoded
end

describe("EventCodec round trip", function()
	it("restores one event of every type exactly (or within its quantization)", function()
		local rng = RNG.new(1)
		local events = {}
		for i, kind in Enums.EventType.values do
			events[i] = randomEvent(rng, kind, 1000 + i)
		end
		local back = roundTrip(events)
		expect(#back).toBe(#events)
		for i, e in events do
			compareEvent(e, back[i])
		end
	end)

	it("restores 5k random events in order across batches", function()
		local rng = RNG.new(2)
		local events = {}
		local tick = 500
		for i = 1, 5000 do
			if rng:chance(0.3) then
				tick += rng:int(0, 40)
			end
			events[i] = randomEvent(rng, pick(rng, Enums.EventType.values), tick)
		end
		local back = roundTrip(events)
		expect(#back).toBe(#events)
		for i, e in events do
			compareEvent(e, back[i])
		end
	end)

	it("starts new batches on tick span, backwards ticks, count and size", function()
		local rng = RNG.new(3)
		local function batchesFor(events: { any }): number
			return #EventCodec.encode(events)
		end
		expect(batchesFor({})).toBe(0)
		expect(batchesFor({ randomEvent(rng, "SixthSense", 10), randomEvent(rng, "SixthSense", 265) })).toBe(1)
		expect(batchesFor({ randomEvent(rng, "SixthSense", 10), randomEvent(rng, "SixthSense", 266) })).toBe(2)
		expect(batchesFor({ randomEvent(rng, "SixthSense", 10), randomEvent(rng, "SixthSense", 9) })).toBe(2)
		local many = {}
		for i = 1, 600 do
			many[i] = randomEvent(rng, "Notice", 7)
		end
		expect(batchesFor(many)).toBe(3) -- 255 per batch
		local shots = {}
		for i = 1, 200 do
			shots[i] = randomEvent(rng, "ShotFired", 7)
		end
		local batches = EventCodec.encode(shots)
		expect(#batches).toBe(math.ceil(200 * 27 / (EventCodec.MAX_BATCH_BYTES - EventCodec.HEADER_BYTES)))
		for _, b in batches do
			expect(buffer.len(b) <= EventCodec.MAX_BATCH_BYTES).toBe(true)
		end
		local back = roundTrip(shots)
		expect(#back).toBe(200)
	end)

	it("saturates magnitudes instead of corrupting the batch", function()
		local rng = RNG.new(4)
		local e = randomEvent(rng, "ShotResult", 1)
		e.damage = 1e9
		local d = randomEvent(rng, "Damage", 1)
		d.damage = -5
		local s = randomEvent(rng, "Stunned", 1)
		s.durationS = math.huge
		local p = randomEvent(rng, "Ping", 1)
		p.x = 1e9
		local back = roundTrip({ e, d, s, p })
		expect(back[1].damage).toBe(65535)
		expect(back[2].damage).toBe(0)
		expect(back[3].durationS).toBe(math.huge)
		expect(back[4].x).toBe(32767)
	end)

	it("an unrevealed attacker (0) stays anonymous on the wire (REG-SPT-08)", function()
		local rng = RNG.new(5)
		local hit = randomEvent(rng, "ShotResult", 3)
		hit.attacker = 0
		local tracer = randomEvent(rng, "ShotFired", 3)
		tracer.shooter = 0
		tracer.tracerOnly = true
		local batch = EventCodec.encode({ hit, tracer })[1]
		-- ShotResult: kind(1) tick(4) count(1) | type(1) delta(1) shotId(2) target(1) attacker(1)
		expect(buffer.readu8(batch, 6 + 2 + 3)).toBe(0)
		local back = roundTrip({ hit, tracer })
		expect(back[1].attacker).toBe(0)
		expect(back[2].shooter).toBe(0)
		expect(back[2].tracerOnly).toBe(true)
	end)
end)

describe("EventCodec encoder guards", function()
	it("raises on programming mistakes", function()
		local rng = RNG.new(6)
		local function throws(e: any, message: string)
			expect(function()
				EventCodec.encode({ e })
			end).toThrow(message)
		end
		throws({ type = "Teleport", tick = 1 }, "unknown event type")
		local e = randomEvent(rng, "Destroyed", 1)
		e.target = 256
		throws(e, "entity id in 0..255")
		e.target = -1
		throws(e, "entity id in 0..255")
		e.target = 1.5
		throws(e, "entity id in 0..255")
		local m = randomEvent(rng, "ModuleState", 1)
		m.module = "Radio"
		throws(m, "unknown value Radio")
		local s = randomEvent(rng, "ShotFired", 1)
		s.origin = Vector3.new(0 / 0, 0, 0)
		throws(s, "finite Vector3")
		local s2 = randomEvent(rng, "ShotFired", 1)
		s2.shotId = 0.5
		throws(s2, "must be an integer")
		local c = randomEvent(rng, "ConsumableUsed", 1)
		c.consumable = string.rep("a", 65)
		throws(c, "at most 64 bytes")
		local t = randomEvent(rng, "SixthSense", -1)
		throws(t, "tick must be a u32")
		local t2 = randomEvent(rng, "SixthSense", 2 ^ 32)
		throws(t2, "tick must be a u32")
	end)
end)

describe("EventCodec hostile batches (REG-NET-05)", function()
	local function copyOf(b: buffer): buffer
		local c = buffer.create(buffer.len(b))
		buffer.copy(c, 0, b)
		return c
	end

	it("rejects malformed batches with Err(INVALID_ARGS)", function()
		local rng = RNG.new(7)
		local good = EventCodec.encode({ randomEvent(rng, "Spotted", 5), randomEvent(rng, "Fire", 6) })[1]
		expect(EventCodec.decode(good)).toBeOk()
		expect(EventCodec.decode(nil)).toBeErr("INVALID_ARGS")
		expect(EventCodec.decode("events")).toBeErr("INVALID_ARGS")
		expect(EventCodec.decode(buffer.create(0))).toBeErr("INVALID_ARGS")
		expect(EventCodec.decode(buffer.create(EventCodec.MAX_BATCH_BYTES + 1))).toBeErr("INVALID_ARGS")
		local bad = copyOf(good)
		buffer.writeu8(bad, 0, 0x53)
		expect(EventCodec.decode(bad)).toBeErr("INVALID_ARGS") -- kind
		bad = copyOf(good)
		buffer.writeu8(bad, 5, 0)
		expect(EventCodec.decode(bad)).toBeErr("INVALID_ARGS") -- empty batch
		bad = copyOf(good)
		buffer.writeu8(bad, 5, 3)
		expect(EventCodec.decode(bad)).toBeErr("INVALID_ARGS") -- count beyond data
		bad = copyOf(good)
		buffer.writeu8(bad, 6, 99)
		expect(EventCodec.decode(bad)).toBeErr("INVALID_ARGS") -- unknown type code
		bad = copyOf(good)
		buffer.writeu8(bad, 6 + 2 + 2, 2)
		expect(EventCodec.decode(bad)).toBeErr("INVALID_ARGS") -- boolean byte 2 (Spotted.first)
		local longer = buffer.create(buffer.len(good) + 1)
		buffer.copy(longer, 0, good)
		expect(EventCodec.decode(longer)).toBeErr("INVALID_ARGS") -- trailing byte
		for cut = 0, buffer.len(good) - 1 do
			local t = buffer.create(cut)
			buffer.copy(t, 0, good, 0, cut)
			expect(EventCodec.decode(t)).toBeErr("INVALID_ARGS")
		end
	end)

	it("10k mutated and random batches never throw and only yield known types", function()
		local rng = RNG.new(8)
		local seeds = {}
		for i = 1, 6 do
			local events = {}
			for j = 1, rng:int(1, 20) do
				events[j] = randomEvent(rng, pick(rng, Enums.EventType.values), 100 + j)
			end
			seeds[i] = EventCodec.encode(events)[1]
		end
		local accepted = 0
		local out = {}
		for i = 1, 10000 do
			local b: buffer
			if i % 3 == 0 then
				local len = rng:int(0, 120)
				b = buffer.create(len)
				for j = 0, len - 1 do
					buffer.writeu8(b, j, rng:int(0, 255))
				end
				if len > 0 then
					buffer.writeu8(b, 0, EventCodec.KIND)
				end
			else
				b = copyOf(seeds[rng:int(1, #seeds)])
				for _ = 1, rng:int(1, 3) do
					local at = rng:int(0, buffer.len(b) - 1)
					buffer.writeu8(b, at, bit32.bxor(buffer.readu8(b, at), 2 ^ rng:int(0, 7)))
				end
			end
			local called, r = pcall(EventCodec.decode, b, out)
			check(called, `decode threw: {tostring(r)}`)
			if r.ok then
				accepted += 1
				for _, e in r.value do
					check(Enums.EventType.codes[e.type] ~= nil, "unknown decoded type")
				end
			else
				check(r.err == "INVALID_ARGS", "unexpected error code")
				check(#out == 0, "output not cleared on error")
			end
		end
		expect(accepted > 500).toBe(true)
	end)
end)
