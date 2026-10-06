--!strict
--[[
	Codecs/Battle/EventCodec — binary batches of reliable battle events for one observer (S2C BattleEvents
	RemoteEvent): shots, impacts, module/crew/fire/stun state, kills, spotting, comms, ribbons and notices
	(ARCHITECTURE §6.1 step 9; catalogue in docs/systems/battle-protocol.md §6).

	Purpose:          encode (server: a list of NetEvent -> one or more batches) and decode (client: batch -> list of
	                  NetEvent). Binary instead of tables because shot events are the highest-frequency reliable
	                  traffic (a table event costs its key strings on the wire every time).
	Dependencies:     Codecs/Battle/{Quantize, Enums}, Core/Result, Net/ErrorCodes, Types/BattleNet.
	State:            A module-level scratch batch buffer used by encode (synchronous, single-threaded per VM).
	Validation:       encode raises on programming mistakes (unknown type/enum, entity id outside 0..255,
	                  non-finite vectors, consumable id longer than MAX_STRING_BYTES); magnitudes saturate (damage,
	                  speeds, durations, map coordinates). decode checks the header, every type code, enum code,
	                  boolean byte, string length and the exact batch length.
	Error handling:   decode never throws: Err(INVALID_ARGS, reason).
	Performance notes: encode allocates one exact-size buffer per batch; decode allocates one table per event.

	Batch layout: u8 KIND (0x45), u32 baseTick, u8 count, then per event: u8 type code (Enums.EventType),
	u8 tick delta (event tick - baseTick, 0..255), type payload (see PAYLOAD_BYTES / writeEvent). A batch never
	exceeds MAX_BATCH_BYTES; encode starts a new batch when an event does not fit, when its tick is outside
	[baseTick, baseTick + 255] or after 255 events. Order is preserved within and across batches.
]]

local Quantize = require("./Quantize")
local Enums = require("./Enums")
local Result = require("../../../Core/Result")
local ErrorCodes = require("../../ErrorCodes")
local BattleNet = require("../../../Types/BattleNet")

type Result<T> = Result.Result<T>
type NetEvent = BattleNet.NetEvent

local KIND = 0x45
local HEADER_BYTES = 6
local MAX_BATCH_BYTES = 2048
local MAX_COUNT = 255
local MAX_STRING_BYTES = 64
local MAX_TICK = 4294967295

-- Payload bytes per event type (after the 2-byte type + delta prefix). ConsumableUsed adds its string length.
local PAYLOAD_BYTES: { [string]: number } = {
	ShotFired = 25,
	ShotHeard = 5,
	ShotResult = 21,
	ModuleState = 4,
	CrewInjured = 4,
	Damage = 5,
	Destroyed = 3,
	Spotted = 3,
	Lost = 5,
	SixthSense = 0,
	Fire = 2,
	Stunned = 3,
	ConsumableUsed = 2,
	Command = 8,
	Ping = 6,
	Ribbon = 4,
	Notice = 1,
}

local EventCodec = {}

EventCodec.KIND = KIND
EventCodec.HEADER_BYTES = HEADER_BYTES
EventCodec.MAX_BATCH_BYTES = MAX_BATCH_BYTES
EventCodec.MAX_STRING_BYTES = MAX_STRING_BYTES
EventCodec.PAYLOAD_BYTES = table.freeze(table.clone(PAYLOAD_BYTES))

--------------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------------

local W = buffer.create(MAX_BATCH_BYTES)
local wp = 0

local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function entity(id: number, what: string): number
	if type(id) ~= "number" or id ~= math.floor(id) or id < 0 or id > 255 then
		error(`EventCodec: {what} must be an entity id in 0..255, got {tostring(id)}`, 3)
	end
	return id
end

local function u16Round(n: number): number
	if not (n > 0) then
		return 0
	end
	return math.min(math.floor(n + 0.5), 65535)
end

-- Small counts / indices: NaN and negatives -> 0, saturate at 255.
local function byteSat(n: number): number
	if not (n > 0) then
		return 0
	end
	return math.min(math.floor(n), 255)
end

local function shotId(n: number, what: string): number
	if type(n) ~= "number" or n ~= math.floor(n) or not isFinite(n) then
		error(`EventCodec: {what} must be an integer, got {tostring(n)}`, 3)
	end
	return n % 65536
end

local function finiteVector(v: Vector3, what: string): Vector3
	if typeof(v) ~= "Vector3" or not (isFinite(v.X) and isFinite(v.Y) and isFinite(v.Z)) then
		error(`EventCodec: {what} must be a finite Vector3`, 3)
	end
	return v
end

local function w8(v: number)
	buffer.writeu8(W, wp, v)
	wp += 1
end

local function w16(v: number)
	buffer.writeu16(W, wp, v)
	wp += 2
end

local function wi16(v: number)
	buffer.writei16(W, wp, v)
	wp += 2
end

local function wBool(b: boolean)
	buffer.writeu8(W, wp, if b then 1 else 0)
	wp += 1
end

local function wPos(v: Vector3)
	Quantize.writePos3(W, wp, v)
	wp += 9
end

local function wUnit(v: Vector3)
	Quantize.writeUnit(W, wp, v)
	wp += 4
end

local function eventBytes(e: NetEvent): number
	local size = PAYLOAD_BYTES[e.type]
	if size == nil then
		error(`EventCodec: unknown event type {tostring(e.type)}`, 3)
	end
	if e.type == "ConsumableUsed" then
		local id = e.consumable
		if type(id) ~= "string" or #id > MAX_STRING_BYTES then
			error(`EventCodec: consumable id must be a string of at most {MAX_STRING_BYTES} bytes`, 3)
		end
		size += #id
	end
	return 2 + size
end

local function writeEvent(e: NetEvent)
	if e.type == "ShotFired" then
		w8(entity(e.shooter, "ShotFired.shooter"))
		w16(shotId(e.shotId, "ShotFired.shotId"))
		w8(byteSat(e.shellIndex))
		w8(Enums.encode(Enums.ShellKind, e.shellKind))
		w16(u16Round(e.caliberMm * 10))
		wPos(finiteVector(e.origin, "ShotFired.origin"))
		wUnit(finiteVector(e.direction, "ShotFired.direction"))
		w16(u16Round(e.speedMps))
		w16(u16Round(e.gravityMps2 * 100))
		w8((if e.volley then 1 else 0) + (if e.charged then 2 else 0) + (if e.tracerOnly then 4 else 0))
	elseif e.type == "ShotHeard" then
		w8(Enums.encode(Enums.CaliberClass, e.caliberClass))
		wi16(Quantize.toMapCoord(e.x))
		wi16(Quantize.toMapCoord(e.z))
	elseif e.type == "ShotResult" then
		w16(shotId(e.shotId, "ShotResult.shotId"))
		w8(entity(e.target, "ShotResult.target"))
		w8(entity(e.attacker, "ShotResult.attacker"))
		w8(Enums.encode(Enums.ShotResult, e.result))
		w16(u16Round(e.damage))
		w8((if e.critical then 1 else 0) + (if e.fireStarted then 2 else 0) + (if e.killed then 4 else 0))
		wPos(finiteVector(e.point, "ShotResult.point"))
		wUnit(finiteVector(e.direction, "ShotResult.direction"))
	elseif e.type == "ModuleState" then
		w8(entity(e.target, "ModuleState.target"))
		w8(Enums.encode(Enums.ModuleKind, e.module))
		w8(Enums.encode(Enums.ModuleState, e.state))
		w8(entity(e.attacker, "ModuleState.attacker"))
	elseif e.type == "CrewInjured" then
		w8(entity(e.target, "CrewInjured.target"))
		w8(byteSat(e.slot))
		w8(Enums.encode(Enums.CrewRole, e.role))
		wBool(e.healed)
	elseif e.type == "Damage" then
		w8(entity(e.target, "Damage.target"))
		w8(entity(e.attacker, "Damage.attacker"))
		w8(Enums.encode(Enums.DamageKind, e.kind))
		w16(u16Round(e.damage))
	elseif e.type == "Destroyed" then
		w8(entity(e.target, "Destroyed.target"))
		w8(entity(e.attacker, "Destroyed.attacker"))
		w8(Enums.encode(Enums.DamageKind, e.cause))
	elseif e.type == "Spotted" then
		w8(entity(e.target, "Spotted.target"))
		w8(entity(e.spotter, "Spotted.spotter"))
		wBool(e.first)
	elseif e.type == "Lost" then
		w8(entity(e.target, "Lost.target"))
		wi16(Quantize.toMapCoord(e.x))
		wi16(Quantize.toMapCoord(e.z))
	elseif e.type == "SixthSense" then
		-- no payload
	elseif e.type == "Fire" then
		w8(entity(e.target, "Fire.target"))
		wBool(e.burning)
	elseif e.type == "Stunned" then
		w8(entity(e.target, "Stunned.target"))
		w16(Quantize.toCentis(e.durationS))
	elseif e.type == "ConsumableUsed" then
		w8(entity(e.participant, "ConsumableUsed.participant"))
		w8(#e.consumable)
		buffer.writestring(W, wp, e.consumable)
		wp += #e.consumable
	elseif e.type == "Command" then
		w8(entity(e.sender, "Command.sender"))
		w8(Enums.encode(Enums.QuickCommand, e.command))
		w8(entity(e.targetId, "Command.targetId"))
		wBool(e.hasPoint)
		wi16(Quantize.toMapCoord(e.x))
		wi16(Quantize.toMapCoord(e.z))
	elseif e.type == "Ping" then
		w8(entity(e.sender, "Ping.sender"))
		w8(Enums.encode(Enums.PingKind, e.ping))
		wi16(Quantize.toMapCoord(e.x))
		wi16(Quantize.toMapCoord(e.z))
	elseif e.type == "Ribbon" then
		w8(Enums.encode(Enums.RibbonKind, e.ribbon))
		w16(u16Round(e.value))
		w8(entity(e.target, "Ribbon.target"))
	elseif e.type == "Notice" then
		w8(Enums.encode(Enums.NoticeKind, e.notice))
	end
end

local function checkTick(tick: number)
	if type(tick) ~= "number" or tick ~= math.floor(tick) or tick < 0 or tick > MAX_TICK then
		error(`EventCodec: event tick must be a u32, got {tostring(tick)}`, 3)
	end
end

--- Encodes `events` (in order) into batches. Returns `out` (cleared) or a new list; an empty list yields none.
function EventCodec.encode(events: { NetEvent }, out: { buffer }?): { buffer }
	local list = out or {}
	table.clear(list)
	local base = 0
	local count = 0
	local function flush()
		if count > 0 then
			buffer.writeu8(W, 5, count)
			local batch = buffer.create(wp)
			buffer.copy(batch, 0, W, 0, wp)
			table.insert(list, batch)
		end
		count = 0
		wp = 0
	end
	for _, e in events do
		local tick = e.tick
		checkTick(tick)
		local size = eventBytes(e)
		if count > 0 and (tick < base or tick - base > 255 or count >= MAX_COUNT or wp + size > MAX_BATCH_BYTES) then
			flush()
		end
		if count == 0 then
			base = tick
			wp = 0
			buffer.writeu8(W, 0, KIND)
			buffer.writeu32(W, 1, base)
			buffer.writeu8(W, 5, 0)
			wp = HEADER_BYTES
		end
		local start = wp
		w8(Enums.encode(Enums.EventType, e.type))
		w8(tick - base)
		writeEvent(e)
		if wp - start ~= size then
			error(`EventCodec: internal size mismatch for {e.type}`, 2)
		end
		count += 1
	end
	flush()
	return list
end

--------------------------------------------------------------------------------
-- Decoding
--------------------------------------------------------------------------------

local EMPTY = buffer.create(0)
local R = EMPTY
local rp = 0
local re = 0

local function fail(message: string): never
	error({ eventError = message }, 0)
end

local function need(n: number)
	if rp + n > re then
		fail(`truncated: {n} bytes needed at offset {rp}`)
	end
end

local function r8(): number
	need(1)
	local v = buffer.readu8(R, rp)
	rp += 1
	return v
end

local function r16(): number
	need(2)
	local v = buffer.readu16(R, rp)
	rp += 2
	return v
end

local function ri16(): number
	need(2)
	local v = buffer.readi16(R, rp)
	rp += 2
	if v == -32768 then
		fail("map coordinate out of range")
	end
	return v
end

local function rBool(): boolean
	local v = r8()
	if v > 1 then
		fail(`invalid boolean byte {v}`)
	end
	return v == 1
end

local function rPos(): Vector3
	need(9)
	local v = Quantize.readPos3(R, rp)
	rp += 9
	return v
end

local function rUnit(): Vector3
	need(4)
	local v = Quantize.readUnit(R, rp)
	rp += 4
	return v
end

local function rEnum(enum: Enums.Enum): any
	local code = r8()
	local value = Enums.decode(enum, code)
	if value == nil then
		fail(`{enum.name}: unknown code {code}`)
	end
	return value
end

local function rFlags(mask: number): number
	local v = r8()
	if bit32.band(v, bit32.bnot(mask)) ~= 0 then
		fail("reserved flag bits set")
	end
	return v
end

local function readEvent(kind: string, tick: number): NetEvent
	if kind == "ShotFired" then
		local shooter = r8()
		local shotId = r16()
		local shellIndex = r8()
		local shellKind = rEnum(Enums.ShellKind)
		local caliber = r16() / 10
		local origin = rPos()
		local direction = rUnit()
		local speed = r16()
		local gravity = r16() / 100
		local flags = rFlags(7)
		return {
			type = "ShotFired",
			tick = tick,
			shooter = shooter,
			shotId = shotId,
			shellIndex = shellIndex,
			shellKind = shellKind,
			caliberMm = caliber,
			origin = origin,
			direction = direction,
			speedMps = speed,
			gravityMps2 = gravity,
			volley = bit32.btest(flags, 1),
			charged = bit32.btest(flags, 2),
			tracerOnly = bit32.btest(flags, 4),
		}
	elseif kind == "ShotHeard" then
		local caliberClass = rEnum(Enums.CaliberClass)
		local x = ri16()
		local z = ri16()
		return { type = "ShotHeard", tick = tick, caliberClass = caliberClass, x = x, z = z }
	elseif kind == "ShotResult" then
		local shotId = r16()
		local target = r8()
		local attacker = r8()
		local result = rEnum(Enums.ShotResult)
		local damage = r16()
		local flags = rFlags(7)
		local point = rPos()
		local direction = rUnit()
		return {
			type = "ShotResult",
			tick = tick,
			shotId = shotId,
			target = target,
			attacker = attacker,
			result = result,
			damage = damage,
			critical = bit32.btest(flags, 1),
			fireStarted = bit32.btest(flags, 2),
			killed = bit32.btest(flags, 4),
			point = point,
			direction = direction,
		}
	elseif kind == "ModuleState" then
		local target = r8()
		local module = rEnum(Enums.ModuleKind)
		local state = rEnum(Enums.ModuleState)
		local attacker = r8()
		return { type = "ModuleState", tick = tick, target = target, module = module, state = state, attacker = attacker }
	elseif kind == "CrewInjured" then
		local target = r8()
		local slot = r8()
		local role = rEnum(Enums.CrewRole)
		local healed = rBool()
		return { type = "CrewInjured", tick = tick, target = target, slot = slot, role = role, healed = healed }
	elseif kind == "Damage" then
		local target = r8()
		local attacker = r8()
		local damageKind = rEnum(Enums.DamageKind)
		local damage = r16()
		return {
			type = "Damage",
			tick = tick,
			target = target,
			attacker = attacker,
			kind = damageKind,
			damage = damage,
		}
	elseif kind == "Destroyed" then
		local target = r8()
		local attacker = r8()
		local cause = rEnum(Enums.DamageKind)
		return { type = "Destroyed", tick = tick, target = target, attacker = attacker, cause = cause }
	elseif kind == "Spotted" then
		local target = r8()
		local spotter = r8()
		local first = rBool()
		return { type = "Spotted", tick = tick, target = target, spotter = spotter, first = first }
	elseif kind == "Lost" then
		local target = r8()
		local x = ri16()
		local z = ri16()
		return { type = "Lost", tick = tick, target = target, x = x, z = z }
	elseif kind == "SixthSense" then
		return { type = "SixthSense", tick = tick }
	elseif kind == "Fire" then
		local target = r8()
		local burning = rBool()
		return { type = "Fire", tick = tick, target = target, burning = burning }
	elseif kind == "Stunned" then
		local target = r8()
		local duration = Quantize.fromCentis(r16())
		return { type = "Stunned", tick = tick, target = target, durationS = duration }
	elseif kind == "ConsumableUsed" then
		local participant = r8()
		local len = r8()
		if len > MAX_STRING_BYTES then
			fail(`consumable id of {len} bytes`)
		end
		need(len)
		local id = buffer.readstring(R, rp, len)
		rp += len
		return { type = "ConsumableUsed", tick = tick, participant = participant, consumable = id }
	elseif kind == "Command" then
		local sender = r8()
		local command = rEnum(Enums.QuickCommand)
		local targetId = r8()
		local hasPoint = rBool()
		local x = ri16()
		local z = ri16()
		return {
			type = "Command",
			tick = tick,
			sender = sender,
			command = command,
			targetId = targetId,
			hasPoint = hasPoint,
			x = x,
			z = z,
		}
	elseif kind == "Ping" then
		local sender = r8()
		local ping = rEnum(Enums.PingKind)
		local x = ri16()
		local z = ri16()
		return { type = "Ping", tick = tick, sender = sender, ping = ping, x = x, z = z }
	elseif kind == "Ribbon" then
		local ribbon = rEnum(Enums.RibbonKind)
		local value = r16()
		local target = r8()
		return { type = "Ribbon", tick = tick, ribbon = ribbon, value = value, target = target }
	elseif kind == "Notice" then
		local notice = rEnum(Enums.NoticeKind)
		return { type = "Notice", tick = tick, notice = notice }
	end
	return fail(`unhandled event type {kind}`)
end

local function readBatch(out: { NetEvent }): any
	need(HEADER_BYTES)
	if buffer.readu8(R, 0) ~= KIND then
		fail("bad batch kind")
	end
	local base = buffer.readu32(R, 1)
	local count = buffer.readu8(R, 5)
	rp = HEADER_BYTES
	if count == 0 then
		fail("empty batch")
	end
	for _ = 1, count do
		local kind = rEnum(Enums.EventType)
		local delta = r8()
		local tick = base + delta
		if tick > MAX_TICK then
			fail("event tick overflows u32")
		end
		table.insert(out, readEvent(kind, tick))
	end
	if rp ~= re then
		fail(`{re - rp} trailing bytes`)
	end
	return nil
end

--- Decodes one batch into `out` (cleared) or a new list. Never throws.
function EventCodec.decode(value: unknown, out: { NetEvent }?): Result<{ NetEvent }>
	if type(value) ~= "buffer" then
		return Result.err(ErrorCodes.INVALID_ARGS, `events: expected buffer, got {typeof(value)}`)
	end
	local b = value :: buffer
	if buffer.len(b) > MAX_BATCH_BYTES then
		return Result.err(ErrorCodes.INVALID_ARGS, `events: batch of {buffer.len(b)} bytes`)
	end
	local list = out or {}
	table.clear(list)
	R, rp, re = b, 0, buffer.len(b)
	local ok, err = pcall(readBatch, list)
	R = EMPTY
	if not ok then
		table.clear(list)
		local message = if type(err) == "table" and err.eventError ~= nil
			then err.eventError
			else `decoder error: {tostring(err)}`
		return Result.err(ErrorCodes.INVALID_ARGS, `events: {message}`)
	end
	return Result.ok(list)
end

return table.freeze(EventCodec)
