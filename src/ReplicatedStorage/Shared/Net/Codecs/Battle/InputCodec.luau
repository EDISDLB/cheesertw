--!strict
--[[
	Codecs/Battle/InputCodec — the BattleInput packet (C2S, UnreliableRemoteEvent, 30 Hz): the newest InputCommand
	plus up to two older ones for loss tolerance (ARCHITECTURE §5.2, 00-DECISIONS §19 "InputPacket <= 64 B").

	Purpose:          encode (client), validate (NetServer arg validator, before any handler runs), decode (server,
	                  into reused records) and the sequence helpers the server uses to apply each input exactly once
	                  (REG-NET-02): unwrapSeq and newCommands.
	Dependencies:     Codecs/Battle/Quantize, Core/Result, Net/ErrorCodes, Types/Vehicle, Types/BattleNet.
	State:            None.
	Validation:       decode/validate accept only the exact canonical layout: buffer type, PACKET_KIND, count 1..3,
	                  length == 4 + 12 × count, axes in [-127, 127] (-128 is never produced), no reserved flag bits.
	                  Aim points are i24 fixed point, so they are always finite and within ±32768 studs; the server
	                  still clamps them to the map with VehicleSim.sanitizeInput.
	Error handling:   decode returns Err(INVALID_ARGS, reason) and never throws on hostile bytes (the layout is
	                  fixed-size, so every read is bounds-checked up front). encode raises only on programming
	                  mistakes (no commands, non-integer seq); out-of-range axes and aim components saturate.
	Performance notes: validate allocates nothing; decode reuses `out` and its command tables (one Vector3 per
	                  command); encode allocates one buffer of 16/28/40 bytes.

	Layout (little endian):
	  u8  PACKET_KIND (0x49)
	  u16 seq        newest command's input sequence (client tick), wrapped to 16 bits
	  u8  count      1..3, newest first; command i has seq (seq - i + 1) mod 65536
	  count × 12 B:  i8 throttle, i8 steer (q / 127), i24 aim X, Y, Z (q / 256 studs),
	                 u8 flags (1 fire, 2 holdTurret, 4 brake, 8 mechanic; bits 4..7 must be 0)
]]

local Quantize = require("./Quantize")
local Result = require("../../../Core/Result")
local ErrorCodes = require("../../ErrorCodes")
local VehicleTypes = require("../../../Types/Vehicle")
local BattleNet = require("../../../Types/BattleNet")

type InputCommand = VehicleTypes.InputCommand
type InputBatch = BattleNet.InputBatch
type Result<T> = Result.Result<T>

local PACKET_KIND = 0x49
local HEADER_BYTES = 4
local COMMAND_BYTES = 12
local MAX_COMMANDS = 3
local SEQ_MODULO = 65536

local FLAG_FIRE = 1
local FLAG_HOLD_TURRET = 2
local FLAG_BRAKE = 4
local FLAG_MECHANIC = 8
local FLAG_MASK = 15

local InputCodec = {}

InputCodec.PACKET_KIND = PACKET_KIND
InputCodec.HEADER_BYTES = HEADER_BYTES
InputCodec.COMMAND_BYTES = COMMAND_BYTES
InputCodec.MAX_COMMANDS = MAX_COMMANDS
InputCodec.MIN_BYTES = HEADER_BYTES + COMMAND_BYTES
InputCodec.MAX_BYTES = HEADER_BYTES + COMMAND_BYTES * MAX_COMMANDS
InputCodec.SEQ_MODULO = SEQ_MODULO

local function wrapSeq(seq: number): number
	if type(seq) ~= "number" or seq ~= seq or seq ~= math.floor(seq) or math.abs(seq) == math.huge then
		error(`InputCodec: command seq must be an integer, got {tostring(seq)}`, 3)
	end
	return seq % SEQ_MODULO
end

--- Encodes `commands` (newest first; at most MAX_COMMANDS, or `count`) into a new packet. Commands after the
--- first sequence gap are dropped (the layout implies consecutive sequences).
function InputCodec.encode(commands: { InputCommand }, count: number?): buffer
	local n = math.min(count or #commands, #commands, MAX_COMMANDS)
	if n < 1 then
		error("InputCodec.encode: at least one command is required", 2)
	end
	local seq = wrapSeq(commands[1].seq)
	local used = 1
	for i = 2, n do
		if wrapSeq(commands[i].seq) ~= (seq - (i - 1)) % SEQ_MODULO then
			break
		end
		used = i
	end
	local b = buffer.create(HEADER_BYTES + COMMAND_BYTES * used)
	buffer.writeu8(b, 0, PACKET_KIND)
	buffer.writeu16(b, 1, seq)
	buffer.writeu8(b, 3, used)
	for i = 1, used do
		local cmd = commands[i]
		local o = HEADER_BYTES + (i - 1) * COMMAND_BYTES
		buffer.writei8(b, o, Quantize.toAxis(cmd.throttle))
		buffer.writei8(b, o + 1, Quantize.toAxis(cmd.steer))
		Quantize.writePos3(b, o + 2, cmd.aimPoint)
		local flags = 0
		if cmd.fire then
			flags += FLAG_FIRE
		end
		if cmd.holdTurret then
			flags += FLAG_HOLD_TURRET
		end
		if cmd.brake then
			flags += FLAG_BRAKE
		end
		if cmd.mechanic then
			flags += FLAG_MECHANIC
		end
		buffer.writeu8(b, o + 11, flags)
	end
	return b
end

-- Returns nil when `value` is a canonical packet, otherwise a reason. Never throws, allocates only on failure.
local function check(value: unknown): string?
	if type(value) ~= "buffer" then
		return `expected buffer, got {typeof(value)}`
	end
	local b = value :: buffer
	local len = buffer.len(b)
	if len < HEADER_BYTES + COMMAND_BYTES or len > HEADER_BYTES + COMMAND_BYTES * MAX_COMMANDS then
		return `bad packet length {len}`
	end
	if buffer.readu8(b, 0) ~= PACKET_KIND then
		return "bad packet kind"
	end
	local count = buffer.readu8(b, 3)
	if count < 1 or count > MAX_COMMANDS then
		return `bad command count {count}`
	end
	if len ~= HEADER_BYTES + COMMAND_BYTES * count then
		return `length {len} does not match {count} commands`
	end
	for i = 1, count do
		local o = HEADER_BYTES + (i - 1) * COMMAND_BYTES
		if buffer.readi8(b, o) == -128 or buffer.readi8(b, o + 1) == -128 then
			return `command {i}: axis out of range`
		end
		if bit32.band(buffer.readu8(b, o + 11), bit32.bnot(FLAG_MASK)) ~= 0 then
			return `command {i}: reserved flag bits set`
		end
	end
	return nil
end

--- Schema-compatible validator for the BattleInput remote (runs in NetServer before any handler).
function InputCodec.validate(value: unknown): (boolean, string?)
	local problem = check(value)
	if problem ~= nil then
		return false, problem
	end
	return true, nil
end

local function newCommand(): InputCommand
	return {
		seq = 0,
		throttle = 0,
		steer = 0,
		aimPoint = Vector3.zero,
		fire = false,
		holdTurret = false,
		brake = false,
		mechanic = false,
	}
end

--- A reusable batch record (pass it to decode every tick).
function InputCodec.newBatch(): InputBatch
	local commands = table.create(MAX_COMMANDS)
	for i = 1, MAX_COMMANDS do
		commands[i] = newCommand()
	end
	return { seq = 0, count = 0, commands = commands }
end

--- Decodes an untrusted packet into `out` (or a new batch). Commands keep their WRAPPED sequence numbers; use
--- newCommands to unwrap and drop already-applied ones.
function InputCodec.decode(value: unknown, out: InputBatch?): Result<InputBatch>
	local problem = check(value)
	if problem ~= nil then
		return Result.err(ErrorCodes.INVALID_ARGS, problem)
	end
	local b = value :: buffer
	local batch = out or InputCodec.newBatch()
	local seq = buffer.readu16(b, 1)
	local count = buffer.readu8(b, 3)
	batch.seq = seq
	batch.count = count
	local commands = batch.commands
	for i = 1, count do
		local cmd = commands[i]
		if cmd == nil then
			cmd = newCommand()
			commands[i] = cmd
		end
		local o = HEADER_BYTES + (i - 1) * COMMAND_BYTES
		local flags = buffer.readu8(b, o + 11)
		cmd.seq = (seq - (i - 1)) % SEQ_MODULO
		cmd.throttle = Quantize.fromAxis(buffer.readi8(b, o))
		cmd.steer = Quantize.fromAxis(buffer.readi8(b, o + 1))
		cmd.aimPoint = Quantize.readPos3(b, o + 2)
		cmd.fire = bit32.btest(flags, FLAG_FIRE)
		cmd.holdTurret = bit32.btest(flags, FLAG_HOLD_TURRET)
		cmd.brake = bit32.btest(flags, FLAG_BRAKE)
		cmd.mechanic = bit32.btest(flags, FLAG_MECHANIC)
	end
	return Result.ok(batch)
end

--- The full sequence number whose low 16 bits are `wrapped`, nearest to `reference` (ties go forward).
function InputCodec.unwrapSeq(wrapped: number, reference: number): number
	local diff = (wrapped - reference) % SEQ_MODULO
	if diff > SEQ_MODULO / 2 then
		diff -= SEQ_MODULO
	end
	return reference + diff
end

--- Copies the commands of `batch` that are newer than `lastSeq` (full, unwrapped; nil = nothing applied yet) into
--- `out`, OLDEST FIRST, with unwrapped `seq`, and returns how many there are. Stale and duplicate packets yield 0;
--- redundant copies of already-applied commands are skipped, so each input is applied once (REG-NET-02). With
--- lastSeq = nil the newest command's wrapped seq is taken as its full seq (sequences never go below 0).
function InputCodec.newCommands(batch: InputBatch, lastSeq: number?, out: { InputCommand }): number
	local count = batch.count
	if count < 1 then
		return 0
	end
	local newest: number
	local fresh: number
	if lastSeq == nil then
		newest = batch.seq
		fresh = math.min(count, newest + 1)
	else
		newest = InputCodec.unwrapSeq(batch.seq, lastSeq)
		fresh = math.min(count, newest - lastSeq)
	end
	if fresh <= 0 then
		return 0
	end
	for k = 1, fresh do
		local src = batch.commands[fresh - k + 1]
		local dst = out[k]
		if dst == nil then
			dst = newCommand()
			out[k] = dst
		end
		dst.seq = newest - (fresh - k)
		dst.throttle = src.throttle
		dst.steer = src.steer
		dst.aimPoint = src.aimPoint
		dst.fire = src.fire
		dst.holdTurret = src.holdTurret
		dst.brake = src.brake
		dst.mechanic = src.mechanic
	end
	return fresh
end

return table.freeze(InputCodec)
