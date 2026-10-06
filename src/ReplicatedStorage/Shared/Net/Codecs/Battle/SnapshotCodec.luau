--!strict
--[[
	Codecs/Battle/SnapshotCodec — the per-observer BattleSnapshot (S2C, UnreliableRemoteEvent, 20 Hz): server tick,
	the owner's last processed input, the owner's full state (prediction/reconciliation + HUD), compact records of
	the other replicated vehicles and coarse minimap records, chunked under 900 bytes (ARCHITECTURE §5.2, §6.1 step
	9, §6.2; layout and precision: docs/systems/battle-protocol.md §5).

	Purpose:          Server: newEntityCache / cacheEntity (quantize each vehicle ONCE per snapshot tick) and
	                  encodeIds (per observer: header + owner + the visible ids, copied from the cache) or encode
	                  (one frame). Client: newReceiver():push(chunk) -> Result<SnapshotFrame?> (reassembly via
	                  Chunker + decode into one reused frame), or decodePayload directly.
	Dependencies:     Codecs/Battle/{Quantize, Enums, Chunker}, Core/Result, Net/ErrorCodes, Types/BattleNet.
	State:            A module-level scratch payload buffer and entity cache used by encode() (single-threaded per
	                  Luau VM). Caches and receivers are caller-owned objects.
	Validation:       Encoders raise on programming mistakes (entity id outside 1..255, non-finite numbers, too many
	                  records, unknown enum values, an id that was not cached). Lossy fields saturate (see Quantize).
	                  Decoders check every length, count, enum code and reserved bit, reject NaN/±inf (except the two
	                  fields that legitimately carry math.huge) and trailing bytes.
	Error handling:   Decoding never throws: errors become Err(INVALID_ARGS, reason) (pcall around a bounds-checked
	                  cursor). On Err the output frame's content is unspecified.
	Performance notes: cacheEntity writes 24 bytes into a 6 KB cache buffer; encodeIds copies records with
	                  buffer.copy (no per-entity quantization per observer). Decode reuses the frame, its entity,
	                  minimap, module and consumable records (one Vector3 per entity).

	Payload layout (after the Chunker header; little endian):
	  u8  flags         bit0 owner present, bit1 minimap present (other bits 0)
	  u16 lastInputSeq  owner's last processed input seq, wrapped (0 without owner)
	  [owner section]   see writeOwner (≈ 200–240 bytes)
	  u8  entityCount   then entityCount × 24-byte records:
	        u8 id, i24 x y z (1/256 stud), u16 yaw pitch roll, u16 turret bearing, u16 gun pitch (deg grid),
	        i8 speed (1.28 km/h), u16 hp fraction, u8 flags (1 moving, 2 firing, 4 burning, 8 tracksBroken,
	        16 destroyed, 32 stunned, 64 mechanicActive)
	  [u8 minimapCount, then × 6 bytes: u8 id, i16 x, i16 z (studs), u8 yaw]
]]

local Quantize = require("./Quantize")
local Enums = require("./Enums")
local Chunker = require("./Chunker")
local Result = require("../../../Core/Result")
local ErrorCodes = require("../../ErrorCodes")
local BattleNet = require("../../../Types/BattleNet")

type Result<T> = Result.Result<T>
type SnapshotFrame = BattleNet.SnapshotFrame
type EntityState = BattleNet.EntityState
type MinimapRecord = BattleNet.MinimapRecord
type OwnerState = BattleNet.OwnerState
type OwnerSim = BattleNet.OwnerSim
type OwnerTurret = BattleNet.OwnerTurret
type OwnerCombat = BattleNet.OwnerCombat
type GunView = BattleNet.GunView
type ModuleView = BattleNet.ModuleView
type ConsumableView = BattleNet.ConsumableView
type Delivery = Chunker.Delivery

local SNAPSHOT_KIND = 0x53
local ENTITY_BYTES = 24
local MINIMAP_BYTES = 6
local MAX_ENTITIES = 64
local MAX_MINIMAP = 64
local MAX_MODULES = 8
local MAX_CREW = 8
local MAX_CONSUMABLES = 8
local MAX_AMMO_SLOTS = 8
local MAX_BARRELS = 2
local F32_MAX = 3.4028234663852886e38
local CAPACITY = Chunker.MAX_PAYLOAD_BYTES

local FLAG_OWNER = 1
local FLAG_MINIMAP = 2

local SnapshotCodec = {}

SnapshotCodec.KIND = SNAPSHOT_KIND
SnapshotCodec.ENTITY_BYTES = ENTITY_BYTES
SnapshotCodec.MINIMAP_BYTES = MINIMAP_BYTES
SnapshotCodec.HEADER_BYTES = 3
SnapshotCodec.MAX_ENTITIES = MAX_ENTITIES
SnapshotCodec.MAX_MINIMAP = MAX_MINIMAP
SnapshotCodec.MAX_PAYLOAD_BYTES = CAPACITY

--------------------------------------------------------------------------------
-- Writer (module scratch; encoders are synchronous)
--------------------------------------------------------------------------------

local W = buffer.create(CAPACITY)
local wp = 0

local function room(n: number)
	if wp + n > CAPACITY then
		error(`SnapshotCodec: payload exceeds {CAPACITY} bytes`, 3)
	end
end

local function w8(v: number)
	room(1)
	buffer.writeu8(W, wp, v)
	wp += 1
end

local function w16(v: number)
	room(2)
	buffer.writeu16(W, wp, v)
	wp += 2
end

local function isFinite(v: number): boolean
	return v == v and v ~= math.huge and v ~= -math.huge
end

local function wf32(v: number, what: string)
	if type(v) ~= "number" or not isFinite(v) or math.abs(v) > F32_MAX then
		error(`SnapshotCodec: {what} must be a finite number, got {tostring(v)}`, 3)
	end
	room(4)
	buffer.writef32(W, wp, v)
	wp += 4
end

-- f32 that may be +inf (speed caps, unlimited charges); NaN / -inf are still mistakes.
local function wf32Inf(v: number, what: string)
	if type(v) ~= "number" or v ~= v or v == -math.huge or (v ~= math.huge and math.abs(v) > F32_MAX) then
		error(`SnapshotCodec: {what} must be finite or +inf, got {tostring(v)}`, 3)
	end
	room(4)
	buffer.writef32(W, wp, v)
	wp += 4
end

local function bit(flag: boolean, value: number): number
	return if flag then value else 0
end

local function byteSat(n: number): number
	if not (n > 0) then
		return 0
	end
	return math.min(math.floor(n), 255)
end

local function u16Sat(n: number): number
	if not (n > 0) then
		return 0
	end
	return math.min(math.floor(n), 65535)
end

local function checkId(id: number, what: string)
	if type(id) ~= "number" or id ~= math.floor(id) or id < 1 or id > 255 then
		error(`SnapshotCodec: {what} must be an entity id in 1..255, got {tostring(id)}`, 3)
	end
end

local function moduleStateBits(state: string): number
	return Enums.encode(Enums.ModuleState, state) - 1
end

local function writeOwner(owner: OwnerState, gun: GunView?)
	checkId(owner.entityId, "owner.entityId")
	w8(owner.entityId)
	local s: OwnerSim = owner.sim
	local p = s.position
	wf32(p.X, "sim.position.X")
	wf32(p.Y, "sim.position.Y")
	wf32(p.Z, "sim.position.Z")
	wf32(s.yaw, "sim.yaw")
	wf32(s.pitch, "sim.pitch")
	wf32(s.roll, "sim.roll")
	wf32(s.speed, "sim.speed")
	wf32(s.lateralSpeed, "sim.lateralSpeed")
	wf32(s.yawRate, "sim.yawRate")
	wf32(s.verticalVelocity, "sim.verticalVelocity")
	wf32(s.groundPitch, "sim.groundPitch")
	wf32(s.groundRoll, "sim.groundRoll")
	wf32(s.waterDepthM, "sim.waterDepthM")
	wf32(s.airborneTime, "sim.airborneTime")
	wf32(s.submergedTime, "sim.submergedTime")
	wf32(s.tiltTime, "sim.tiltTime")
	wf32(s.overturnedTime, "sim.overturnedTime")
	wf32(s.stillTime, "sim.stillTime")
	wf32(s.gunDepressionBonusDeg, "sim.gunDepressionBonusDeg")
	wf32(s.gunElevationBonusDeg, "sim.gunElevationBonusDeg")
	local m = s.modifiers
	local mech = s.mechanic
	w16(
		bit(s.grounded, 1)
			+ bit(s.submerged, 2)
			+ bit(s.overturned, 4)
			+ bit(s.drowned, 8)
			+ bit(s.wrecked, 16)
			+ bit(s.immobilized, 32)
			+ bit(s.mechanicActive, 64)
			+ bit(m.immobilized, 128)
			+ bit(mech.lastInput, 256)
			+ bit(mech.external, 512)
			+ bit(mech.hydroActive, 1024)
	)
	w8(Enums.encodeOptional(Enums.ImmobileReason, s.immobileReason))
	w8(moduleStateBits(m.engine) + moduleStateBits(m.trackLeft) * 4 + moduleStateBits(m.trackRight) * 16)
	w8(byteSat(m.lostWheelPairs))
	wf32(m.powerMul, "modifiers.powerMul")
	wf32(m.topSpeedMul, "modifiers.topSpeedMul")
	wf32(m.topSpeedBonusKmh, "modifiers.topSpeedBonusKmh")
	wf32(m.reverseSpeedMul, "modifiers.reverseSpeedMul")
	wf32Inf(m.speedCapKmh, "modifiers.speedCapKmh")
	wf32(m.hullTraverseMul, "modifiers.hullTraverseMul")
	w8(Enums.encodeOptional(Enums.MechanicKind, mech.kind))
	w8(Enums.encode(Enums.MechanicPhase, mech.phase))
	wf32(mech.timer, "mechanic.timer")
	wf32Inf(mech.charges, "mechanic.charges")
	local t: OwnerTurret = owner.turret
	wf32(t.turretYawDeg, "turret.turretYawDeg")
	wf32(t.gunYawDeg, "turret.gunYawDeg")
	wf32(t.gunPitchDeg, "turret.gunPitchDeg")
	wf32(t.bearingSpeedDegS, "turret.bearingSpeedDegS")
	wf32(t.pitchSpeedDegS, "turret.pitchSpeedDegS")
	wf32(t.traverseMul, "turret.traverseMul")
	wf32(t.elevationSpeedMul, "turret.elevationSpeedMul")
	wf32(t.depressionBonusDeg, "turret.depressionBonusDeg")
	wf32(t.elevationBonusDeg, "turret.elevationBonusDeg")
	w8(bit(t.enabled, 1) + bit(gun ~= nil, 2))
	local c: OwnerCombat = owner.combat
	local hp = c.hp
	if type(hp) ~= "number" or hp ~= hp then
		error("SnapshotCodec: combat.hp must be a number", 2)
	end
	w16(math.clamp(math.ceil(hp), 0, 65535))
	w8(bit(c.burning, 1))
	w16(Quantize.toCentis(c.stunRemainingS))
	w16(Quantize.toMilli(c.aimMultiplier))
	local modules = c.modules
	if #modules > MAX_MODULES then
		error(`SnapshotCodec: at most {MAX_MODULES} modules`, 2)
	end
	w8(#modules)
	for _, mod in modules do
		local repairing = mod.repairRemainingS > 0
		w8(Enums.encode(Enums.ModuleKind, mod.kind) + moduleStateBits(mod.state) * 16 + bit(repairing, 64))
		if repairing then
			w16(Quantize.toCentis(mod.repairRemainingS))
			w16(Quantize.toCentis(mod.repairS))
		end
	end
	local crew = c.crewInjured
	if #crew > MAX_CREW then
		error(`SnapshotCodec: at most {MAX_CREW} crew slots`, 2)
	end
	local mask = 0
	for i, injured in crew do
		if injured then
			mask += 2 ^ (i - 1)
		end
	end
	w8(#crew)
	w8(mask)
	local consumables = c.consumables
	if #consumables > MAX_CONSUMABLES then
		error(`SnapshotCodec: at most {MAX_CONSUMABLES} consumable slots`, 2)
	end
	w8(#consumables)
	for _, item in consumables do
		local unlimited = item.charges == math.huge
		w8(bit(item.active, 1) + bit(unlimited, 2))
		w8(if unlimited then 0 else math.min(byteSat(item.charges), 254))
		w16(Quantize.toCentis(item.cooldownRemainingS))
		w16(Quantize.toCentis(item.cooldownS))
		w16(Quantize.toCentis(item.activeRemainingS))
	end
	if gun ~= nil then
		w8(Enums.encode(Enums.ReloadKind, gun.kind))
		w8(Enums.encode(Enums.GunPhase, gun.phase))
		w8(bit(gun.alive, 1) + bit(gun.enabled, 2) + bit(gun.canFire, 4) + bit(gun.toppingOff, 8))
		w8(byteSat(gun.selectedSlot))
		w8(byteSat(gun.loadedSlot))
		w16(Quantize.toCentis(gun.reloadRemainingS))
		w16(Quantize.toCentis(gun.reloadDurationS))
		w16(Quantize.toCentis(gun.nextShotS))
		w16(Quantize.toCentis(gun.intraClipRemainingS))
		w8(byteSat(gun.roundsLoaded))
		w8(byteSat(gun.magazineSize))
		w8(byteSat(gun.refillSlotIndex))
		w8(Quantize.toByteFraction(gun.chargeProgress))
		w16(Quantize.toMilli(gun.reloadMul))
		local ammo = gun.ammo
		if #ammo > MAX_AMMO_SLOTS then
			error(`SnapshotCodec: at most {MAX_AMMO_SLOTS} ammo slots`, 2)
		end
		w8(#ammo)
		for _, count in ammo do
			w16(u16Sat(count))
		end
		local barrels = gun.barrelProgress
		if #barrels > MAX_BARRELS then
			error(`SnapshotCodec: at most {MAX_BARRELS} barrels`, 2)
		end
		w8(#barrels)
		for _, progress in barrels do
			w8(Quantize.toByteFraction(progress))
		end
	end
end

--------------------------------------------------------------------------------
-- Entity cache (server: quantize each vehicle once per snapshot tick)
--------------------------------------------------------------------------------

export type EntityCache = {
	records: buffer, -- 255 × ENTITY_BYTES, record of id at (id - 1) × ENTITY_BYTES
	present: { boolean }, -- by id
}

function SnapshotCodec.newEntityCache(): EntityCache
	return { records = buffer.create(255 * ENTITY_BYTES), present = table.create(255, false) }
end

--- Forgets every cached record (call once per snapshot tick before caching the new states).
function SnapshotCodec.clearCache(cache: EntityCache)
	table.clear(cache.present)
end

--- Quantizes `e` into the cache (replacing any record with the same id).
function SnapshotCodec.cacheEntity(cache: EntityCache, e: EntityState)
	checkId(e.id, "entity.id")
	local p = e.position
	if typeof(p) ~= "Vector3" or not (isFinite(p.X) and isFinite(p.Y) and isFinite(p.Z)) then
		error(`SnapshotCodec: entity {e.id} position must be a finite Vector3`, 2)
	end
	if not (isFinite(e.yaw) and isFinite(e.pitch) and isFinite(e.roll)) then
		error(`SnapshotCodec: entity {e.id} attitude must be finite`, 2)
	end
	if not (isFinite(e.turretYawDeg) and isFinite(e.gunPitchDeg) and isFinite(e.speedKmh)) then
		error(`SnapshotCodec: entity {e.id} turret/gun/speed must be finite`, 2)
	end
	local b = cache.records
	local o = (e.id - 1) * ENTITY_BYTES
	buffer.writeu8(b, o, e.id)
	Quantize.writePos3(b, o + 1, p)
	buffer.writeu16(b, o + 10, Quantize.toAngle(e.yaw))
	buffer.writeu16(b, o + 12, Quantize.toAngle(e.pitch))
	buffer.writeu16(b, o + 14, Quantize.toAngle(e.roll))
	buffer.writeu16(b, o + 16, Quantize.toAngleDeg(e.turretYawDeg))
	buffer.writeu16(b, o + 18, Quantize.toAngleDeg(e.gunPitchDeg))
	buffer.writei8(b, o + 20, Quantize.toSpeed(e.speedKmh))
	local hp = Quantize.toFraction(e.hpFraction)
	if hp < 1 and e.hpFraction > 0 then
		hp = 1
	end
	buffer.writeu16(b, o + 21, hp)
	buffer.writeu8(
		b,
		o + 23,
		bit(e.moving, 1)
			+ bit(e.firing, 2)
			+ bit(e.burning, 4)
			+ bit(e.tracksBroken, 8)
			+ bit(e.destroyed, 16)
			+ bit(e.stunned, 32)
			+ bit(e.mechanicActive, 64)
	)
	cache.present[e.id] = true
end

--------------------------------------------------------------------------------
-- Encoding
--------------------------------------------------------------------------------

--- Per-observer snapshot from a filled cache: `ids[1..idCount]` (default #ids) are copied from the cache in that
--- order. Returns the chunks (`out` cleared and reused when given).
function SnapshotCodec.encodeIds(
	tick: number,
	lastInputSeq: number,
	owner: OwnerState?,
	cache: EntityCache,
	ids: { number },
	idCount: number?,
	minimap: { MinimapRecord }?,
	out: { buffer }?
): { buffer }
	local n = idCount or #ids
	if n > MAX_ENTITIES then
		error(`SnapshotCodec: at most {MAX_ENTITIES} entities per snapshot, got {n}`, 2)
	end
	if minimap ~= nil and #minimap > MAX_MINIMAP then
		error(`SnapshotCodec: at most {MAX_MINIMAP} minimap records, got {#minimap}`, 2)
	end
	if type(lastInputSeq) ~= "number" or lastInputSeq ~= math.floor(lastInputSeq) then
		error("SnapshotCodec: lastInputSeq must be an integer", 2)
	end
	wp = 0
	w8(bit(owner ~= nil, FLAG_OWNER) + bit(minimap ~= nil, FLAG_MINIMAP))
	w16(lastInputSeq % 65536)
	if owner ~= nil then
		writeOwner(owner, owner.gun)
	end
	w8(n)
	room(n * ENTITY_BYTES)
	local records = cache.records
	local present = cache.present
	for i = 1, n do
		local id = ids[i]
		checkId(id, "ids[i]")
		if not present[id] then
			error(`SnapshotCodec: entity {id} was not cached this tick`, 2)
		end
		buffer.copy(W, wp, records, (id - 1) * ENTITY_BYTES, ENTITY_BYTES)
		wp += ENTITY_BYTES
	end
	if minimap ~= nil then
		w8(#minimap)
		room(#minimap * MINIMAP_BYTES)
		for _, r in minimap do
			checkId(r.id, "minimap.id")
			buffer.writeu8(W, wp, r.id)
			buffer.writei16(W, wp + 1, Quantize.toMapCoord(r.x))
			buffer.writei16(W, wp + 3, Quantize.toMapCoord(r.z))
			buffer.writeu8(W, wp + 5, Quantize.toAngle8(r.yaw))
			wp += MINIMAP_BYTES
		end
	end
	return Chunker.split(SNAPSHOT_KIND, tick, W, wp, out)
end

local scratchCache = SnapshotCodec.newEntityCache()
local scratchIds: { number } = {}

--- Encodes one frame (convenience path: quantizes the frame's entities itself).
function SnapshotCodec.encode(frame: SnapshotFrame, out: { buffer }?): { buffer }
	SnapshotCodec.clearCache(scratchCache)
	table.clear(scratchIds)
	for i, e in frame.entities do
		SnapshotCodec.cacheEntity(scratchCache, e)
		scratchIds[i] = e.id
	end
	local minimap = if #frame.minimap > 0 then frame.minimap else nil
	return SnapshotCodec.encodeIds(
		frame.tick,
		frame.lastInputSeq,
		frame.owner,
		scratchCache,
		scratchIds,
		#scratchIds,
		minimap,
		out
	)
end

--- Exact payload size (bytes, without chunk headers) encodeIds would produce for these sections.
function SnapshotCodec.payloadBytes(owner: OwnerState?, entityCount: number, minimapCount: number?): number
	local size = SnapshotCodec.HEADER_BYTES + 1 + entityCount * ENTITY_BYTES
	if minimapCount ~= nil then
		size += 1 + minimapCount * MINIMAP_BYTES
	end
	if owner ~= nil then
		-- 1 id + 20 f32 + 2 flags + 3 bytes + 6 f32 + 2 bytes + 2 f32 + 9 f32 + 1 (turret) + 8 combat header
		size += 1 + 80 + 2 + 3 + 24 + 2 + 8 + 36 + 1 + 7
		size += 1 -- module count
		for _, mod in owner.combat.modules do
			size += if mod.repairRemainingS > 0 then 5 else 1
		end
		size += 2 + 1 + 8 * #owner.combat.consumables
		local gun = owner.gun
		if gun ~= nil then
			size += 19 + 1 + 2 * #gun.ammo + 1 + #gun.barrelProgress
		end
	end
	return size
end

--------------------------------------------------------------------------------
-- Decoding (bounds-checked cursor; errors are caught by decodePayload)
--------------------------------------------------------------------------------

local EMPTY = buffer.create(0)
local R = EMPTY
local rp = 0
local re = 0

local function fail(message: string): never
	error({ snapshotError = message }, 0)
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

local function rf32(what: string): number
	need(4)
	local v = buffer.readf32(R, rp)
	if not isFinite(v) then
		fail(`{what}: non-finite value`)
	end
	rp += 4
	return v
end

local function rf32Inf(what: string): number
	need(4)
	local v = buffer.readf32(R, rp)
	if v ~= v or v == -math.huge then
		fail(`{what}: invalid value`)
	end
	rp += 4
	return v
end

local function rEnum(enum: Enums.Enum, code: number, what: string): string
	local value = Enums.decode(enum, code)
	if value == nil then
		fail(`{what}: unknown code {code}`)
	end
	return value :: string
end

local function reserved(value: number, mask: number, what: string)
	if bit32.band(value, bit32.bnot(mask)) ~= 0 then
		fail(`{what}: reserved bits set`)
	end
end

local function rId(what: string): number
	local id = r8()
	if id == 0 then
		fail(`{what}: entity id 0`)
	end
	return id
end

local function newGun(): GunView
	return {
		kind = "Single",
		phase = "Ready",
		alive = true,
		enabled = true,
		canFire = false,
		selectedSlot = 0,
		loadedSlot = 0,
		reloadProgress = 1,
		reloadRemainingS = 0,
		reloadDurationS = 0,
		nextShotS = 0,
		intraClipRemainingS = 0,
		roundsLoaded = 0,
		magazineSize = 0,
		toppingOff = false,
		refillSlotIndex = 0,
		chargeProgress = 0,
		reloadMul = 1,
		ammo = {},
		totalAmmo = 0,
		barrelProgress = {},
	}
end

--- A blank owner record (decoder output; also a template for servers building OwnerState by hand).
function SnapshotCodec.newOwner(): OwnerState
	return {
		entityId = 0,
		sim = {
			position = Vector3.zero,
			yaw = 0,
			pitch = 0,
			roll = 0,
			speed = 0,
			lateralSpeed = 0,
			yawRate = 0,
			verticalVelocity = 0,
			grounded = true,
			groundPitch = 0,
			groundRoll = 0,
			waterDepthM = 0,
			submerged = false,
			airborneTime = 0,
			submergedTime = 0,
			tiltTime = 0,
			overturnedTime = 0,
			stillTime = 0,
			overturned = false,
			drowned = false,
			wrecked = false,
			immobilized = false,
			immobileReason = nil,
			mechanicActive = false,
			gunDepressionBonusDeg = 0,
			gunElevationBonusDeg = 0,
			modifiers = {
				engine = "Ok",
				trackLeft = "Ok",
				trackRight = "Ok",
				lostWheelPairs = 0,
				powerMul = 1,
				topSpeedMul = 1,
				topSpeedBonusKmh = 0,
				reverseSpeedMul = 1,
				speedCapKmh = math.huge,
				hullTraverseMul = 1,
				immobilized = false,
			},
			mechanic = {
				kind = "",
				phase = "Off",
				timer = 0,
				charges = math.huge,
				lastInput = false,
				external = false,
				hydroActive = false,
			},
		},
		turret = {
			turretYawDeg = 0,
			gunYawDeg = 0,
			gunPitchDeg = 0,
			bearingSpeedDegS = 0,
			pitchSpeedDegS = 0,
			traverseMul = 1,
			elevationSpeedMul = 1,
			depressionBonusDeg = 0,
			elevationBonusDeg = 0,
			enabled = true,
		},
		gun = nil,
		combat = {
			hp = 0,
			burning = false,
			stunRemainingS = 0,
			modules = {},
			crewInjured = {},
			aimMultiplier = 1,
			consumables = {},
		},
	}
end

local function moduleStateOf(bits: number, what: string): any
	return rEnum(Enums.ModuleState, bits + 1, what)
end

local function readOwner(owner: OwnerState)
	owner.entityId = rId("owner.entityId")
	local s = owner.sim
	s.position = Vector3.new(rf32("position"), rf32("position"), rf32("position"))
	s.yaw = rf32("yaw")
	s.pitch = rf32("pitch")
	s.roll = rf32("roll")
	s.speed = rf32("speed")
	s.lateralSpeed = rf32("lateralSpeed")
	s.yawRate = rf32("yawRate")
	s.verticalVelocity = rf32("verticalVelocity")
	s.groundPitch = rf32("groundPitch")
	s.groundRoll = rf32("groundRoll")
	s.waterDepthM = rf32("waterDepthM")
	s.airborneTime = rf32("airborneTime")
	s.submergedTime = rf32("submergedTime")
	s.tiltTime = rf32("tiltTime")
	s.overturnedTime = rf32("overturnedTime")
	s.stillTime = rf32("stillTime")
	s.gunDepressionBonusDeg = rf32("gunDepressionBonusDeg")
	s.gunElevationBonusDeg = rf32("gunElevationBonusDeg")
	local flags = r16()
	reserved(flags, 2047, "sim flags")
	local m = s.modifiers
	local mech = s.mechanic
	s.grounded = bit32.btest(flags, 1)
	s.submerged = bit32.btest(flags, 2)
	s.overturned = bit32.btest(flags, 4)
	s.drowned = bit32.btest(flags, 8)
	s.wrecked = bit32.btest(flags, 16)
	s.immobilized = bit32.btest(flags, 32)
	s.mechanicActive = bit32.btest(flags, 64)
	m.immobilized = bit32.btest(flags, 128)
	mech.lastInput = bit32.btest(flags, 256)
	mech.external = bit32.btest(flags, 512)
	mech.hydroActive = bit32.btest(flags, 1024)
	local reason = r8()
	s.immobileReason = if reason == 0 then nil else rEnum(Enums.ImmobileReason, reason, "immobileReason") :: any
	local states = r8()
	reserved(states, 63, "module states")
	m.engine = moduleStateOf(states % 4, "engine")
	m.trackLeft = moduleStateOf((states // 4) % 4, "trackLeft")
	m.trackRight = moduleStateOf((states // 16) % 4, "trackRight")
	m.lostWheelPairs = r8()
	m.powerMul = rf32("powerMul")
	m.topSpeedMul = rf32("topSpeedMul")
	m.topSpeedBonusKmh = rf32("topSpeedBonusKmh")
	m.reverseSpeedMul = rf32("reverseSpeedMul")
	m.speedCapKmh = rf32Inf("speedCapKmh")
	m.hullTraverseMul = rf32("hullTraverseMul")
	local kind = r8()
	mech.kind = if kind == 0 then "" else rEnum(Enums.MechanicKind, kind, "mechanic.kind")
	mech.phase = rEnum(Enums.MechanicPhase, r8(), "mechanic.phase") :: any
	mech.timer = rf32("mechanic.timer")
	mech.charges = rf32Inf("mechanic.charges")
	local t = owner.turret
	t.turretYawDeg = rf32("turretYawDeg")
	t.gunYawDeg = rf32("gunYawDeg")
	t.gunPitchDeg = rf32("gunPitchDeg")
	t.bearingSpeedDegS = rf32("bearingSpeedDegS")
	t.pitchSpeedDegS = rf32("pitchSpeedDegS")
	t.traverseMul = rf32("traverseMul")
	t.elevationSpeedMul = rf32("elevationSpeedMul")
	t.depressionBonusDeg = rf32("depressionBonusDeg")
	t.elevationBonusDeg = rf32("elevationBonusDeg")
	local turretFlags = r8()
	reserved(turretFlags, 3, "turret flags")
	t.enabled = bit32.btest(turretFlags, 1)
	local hasGun = bit32.btest(turretFlags, 2)
	local c = owner.combat
	c.hp = r16()
	local combatFlags = r8()
	reserved(combatFlags, 1, "combat flags")
	c.burning = combatFlags == 1
	c.stunRemainingS = Quantize.fromCentis(r16())
	c.aimMultiplier = Quantize.fromMilli(r16())
	local moduleCount = r8()
	if moduleCount > MAX_MODULES then
		fail(`module count {moduleCount}`)
	end
	local modules = c.modules
	for i = 1, moduleCount do
		local packed = r8()
		reserved(packed, 127, "module")
		local mod: ModuleView = modules[i] or { kind = "Engine", state = "Ok", repairRemainingS = 0, repairS = 0 }
		modules[i] = mod
		mod.kind = rEnum(Enums.ModuleKind, packed % 16, "module.kind") :: any
		mod.state = moduleStateOf((packed // 16) % 4, "module.state")
		if bit32.btest(packed, 64) then
			mod.repairRemainingS = Quantize.fromCentis(r16())
			mod.repairS = Quantize.fromCentis(r16())
		else
			mod.repairRemainingS = 0
			mod.repairS = 0
		end
	end
	for i = #modules, moduleCount + 1, -1 do
		modules[i] = nil
	end
	local crewCount = r8()
	if crewCount > MAX_CREW then
		fail(`crew count {crewCount}`)
	end
	local mask = r8()
	if mask >= 2 ^ crewCount then
		fail("crew mask beyond crew count")
	end
	local crew = c.crewInjured
	for i = 1, crewCount do
		crew[i] = bit32.btest(mask, 2 ^ (i - 1))
	end
	for i = #crew, crewCount + 1, -1 do
		crew[i] = nil
	end
	local consumableCount = r8()
	if consumableCount > MAX_CONSUMABLES then
		fail(`consumable count {consumableCount}`)
	end
	local consumables = c.consumables
	for i = 1, consumableCount do
		local item: ConsumableView = consumables[i]
			or { active = false, charges = 0, cooldownRemainingS = 0, cooldownS = 0, activeRemainingS = 0 }
		consumables[i] = item
		local itemFlags = r8()
		reserved(itemFlags, 3, "consumable flags")
		local charges = r8()
		item.active = bit32.btest(itemFlags, 1)
		if bit32.btest(itemFlags, 2) then
			if charges ~= 0 then
				fail("unlimited consumable with a charge count")
			end
			item.charges = math.huge
		else
			if charges > 254 then
				fail("consumable charges out of range")
			end
			item.charges = charges
		end
		item.cooldownRemainingS = Quantize.fromCentis(r16())
		item.cooldownS = Quantize.fromCentis(r16())
		item.activeRemainingS = Quantize.fromCentis(r16())
	end
	for i = #consumables, consumableCount + 1, -1 do
		consumables[i] = nil
	end
	if not hasGun then
		owner.gun = nil
		return
	end
	local gun = owner.gun or newGun()
	owner.gun = gun
	gun.kind = rEnum(Enums.ReloadKind, r8(), "gun.kind") :: any
	gun.phase = rEnum(Enums.GunPhase, r8(), "gun.phase") :: any
	local gunFlags = r8()
	reserved(gunFlags, 15, "gun flags")
	gun.alive = bit32.btest(gunFlags, 1)
	gun.enabled = bit32.btest(gunFlags, 2)
	gun.canFire = bit32.btest(gunFlags, 4)
	gun.toppingOff = bit32.btest(gunFlags, 8)
	gun.selectedSlot = r8()
	gun.loadedSlot = r8()
	gun.reloadRemainingS = Quantize.fromCentis(r16())
	gun.reloadDurationS = Quantize.fromCentis(r16())
	gun.nextShotS = Quantize.fromCentis(r16())
	gun.intraClipRemainingS = Quantize.fromCentis(r16())
	gun.roundsLoaded = r8()
	gun.magazineSize = r8()
	gun.refillSlotIndex = r8()
	gun.chargeProgress = Quantize.fromByteFraction(r8())
	gun.reloadMul = Quantize.fromMilli(r16())
	local ammoCount = r8()
	if ammoCount > MAX_AMMO_SLOTS then
		fail(`ammo slot count {ammoCount}`)
	end
	local ammo = gun.ammo
	local total = 0
	for i = 1, ammoCount do
		local count = r16()
		ammo[i] = count
		total += count
	end
	for i = #ammo, ammoCount + 1, -1 do
		ammo[i] = nil
	end
	gun.totalAmmo = total
	local barrelCount = r8()
	if barrelCount > MAX_BARRELS then
		fail(`barrel count {barrelCount}`)
	end
	local barrels = gun.barrelProgress
	for i = 1, barrelCount do
		barrels[i] = Quantize.fromByteFraction(r8())
	end
	for i = #barrels, barrelCount + 1, -1 do
		barrels[i] = nil
	end
	-- Derived exactly as GunState.snapshot does: remaining / duration share one multiplier.
	local duration = gun.reloadDurationS
	if duration > 0 and duration ~= math.huge then
		gun.reloadProgress = math.clamp(1 - gun.reloadRemainingS / duration, 0, 1)
	else
		gun.reloadProgress = if gun.roundsLoaded > 0 then 1 else 0
	end
end

local function newEntity(): EntityState
	return {
		id = 0,
		position = Vector3.zero,
		yaw = 0,
		pitch = 0,
		roll = 0,
		turretYawDeg = 0,
		gunPitchDeg = 0,
		speedKmh = 0,
		hpFraction = 0,
		moving = false,
		firing = false,
		burning = false,
		tracksBroken = false,
		destroyed = false,
		stunned = false,
		mechanicActive = false,
	}
end

--- A blank, reusable frame.
function SnapshotCodec.newFrame(): SnapshotFrame
	return { tick = 0, lastInputSeq = 0, owner = nil, entities = {}, minimap = {} }
end

local spareOwners: { [SnapshotFrame]: OwnerState } = setmetatable({}, { __mode = "k" }) :: any

-- Returns nil; typed `any` so pcall(readPayload, frame) yields (ok, err).
local function readPayload(frame: SnapshotFrame): any
	local flags = r8()
	reserved(flags, FLAG_OWNER + FLAG_MINIMAP, "payload flags")
	frame.lastInputSeq = r16()
	if bit32.btest(flags, FLAG_OWNER) then
		local owner = frame.owner or spareOwners[frame] or SnapshotCodec.newOwner()
		spareOwners[frame] = owner
		frame.owner = owner
		readOwner(owner)
	else
		frame.owner = nil
	end
	local count = r8()
	if count > MAX_ENTITIES then
		fail(`entity count {count}`)
	end
	need(count * ENTITY_BYTES)
	local entities = frame.entities
	local seen = 0
	for i = 1, count do
		local o = rp
		local id = buffer.readu8(R, o)
		if id == 0 then
			fail("entity id 0")
		end
		local e = entities[i]
		if e == nil then
			e = newEntity()
			entities[i] = e
		end
		local entityFlags = buffer.readu8(R, o + 23)
		reserved(entityFlags, 127, "entity flags")
		e.id = id
		e.position = Quantize.readPos3(R, o + 1)
		e.yaw = Quantize.fromAngle(buffer.readu16(R, o + 10))
		e.pitch = Quantize.fromAngle(buffer.readu16(R, o + 12))
		e.roll = Quantize.fromAngle(buffer.readu16(R, o + 14))
		e.turretYawDeg = Quantize.fromAngleDeg(buffer.readu16(R, o + 16))
		e.gunPitchDeg = Quantize.fromAngleDeg(buffer.readu16(R, o + 18))
		local speed = buffer.readi8(R, o + 20)
		if speed == -128 then
			fail("entity speed out of range")
		end
		e.speedKmh = Quantize.fromSpeed(speed)
		e.hpFraction = Quantize.fromFraction(buffer.readu16(R, o + 21))
		e.moving = bit32.btest(entityFlags, 1)
		e.firing = bit32.btest(entityFlags, 2)
		e.burning = bit32.btest(entityFlags, 4)
		e.tracksBroken = bit32.btest(entityFlags, 8)
		e.destroyed = bit32.btest(entityFlags, 16)
		e.stunned = bit32.btest(entityFlags, 32)
		e.mechanicActive = bit32.btest(entityFlags, 64)
		rp += ENTITY_BYTES
		seen += 1
	end
	for i = #entities, seen + 1, -1 do
		entities[i] = nil
	end
	local minimap = frame.minimap
	local minimapCount = 0
	if bit32.btest(flags, FLAG_MINIMAP) then
		minimapCount = r8()
		if minimapCount > MAX_MINIMAP then
			fail(`minimap count {minimapCount}`)
		end
		need(minimapCount * MINIMAP_BYTES)
		for i = 1, minimapCount do
			local o = rp
			local id = buffer.readu8(R, o)
			if id == 0 then
				fail("minimap id 0")
			end
			local r = minimap[i]
			if r == nil then
				r = { id = 0, x = 0, z = 0, yaw = 0 }
				minimap[i] = r
			end
			r.id = id
			r.x = buffer.readi16(R, o + 1)
			r.z = buffer.readi16(R, o + 3)
			r.yaw = Quantize.fromAngle8(buffer.readu8(R, o + 5))
			rp += MINIMAP_BYTES
		end
	end
	for i = #minimap, minimapCount + 1, -1 do
		minimap[i] = nil
	end
	if rp ~= re then
		fail(`{re - rp} trailing bytes`)
	end
	return nil
end

--- Decodes `length` payload bytes of `b` starting at `offset` (as delivered by Chunker) into `out` (or a new
--- frame) stamped with `tick`. Never throws.
function SnapshotCodec.decodePayload(
	tick: number,
	b: buffer,
	offset: number,
	length: number,
	out: SnapshotFrame?
): Result<SnapshotFrame>
	if type(b) ~= "buffer" or offset < 0 or length < 0 or offset + length > buffer.len(b) then
		return Result.err(ErrorCodes.INVALID_ARGS, "snapshot: invalid payload range")
	end
	local frame = out or SnapshotCodec.newFrame()
	R, rp, re = b, offset, offset + length
	local ok, err = pcall(readPayload, frame)
	R = EMPTY
	if not ok then
		local message = if type(err) == "table" and err.snapshotError ~= nil
			then err.snapshotError
			else `decoder error: {tostring(err)}`
		return Result.err(ErrorCodes.INVALID_ARGS, `snapshot: {message}`)
	end
	frame.tick = tick
	return Result.ok(frame)
end

--------------------------------------------------------------------------------
-- Receiver (client): reassembly + decode into one reused frame
--------------------------------------------------------------------------------

local ReceiverClass = {}
ReceiverClass.__index = ReceiverClass

export type SnapshotReceiver = typeof(setmetatable(
	{} :: { assembler: Chunker.Assembler, frame: SnapshotFrame, decodeErrors: number },
	ReceiverClass
))

--- Feeds one BattleSnapshot packet. Ok(frame) when a snapshot newer than every delivered one completed (the frame
--- is reused: read it before the next push), Ok(nil) while waiting / for stale or duplicate chunks, Err for
--- malformed chunks or payloads.
function ReceiverClass.push(self: SnapshotReceiver, chunk: unknown): Result<SnapshotFrame?>
	local assembled = self.assembler:push(chunk)
	if not assembled.ok then
		return assembled
	end
	local delivery: Delivery? = assembled.value
	if delivery == nil then
		return Result.ok(nil)
	end
	local decoded = SnapshotCodec.decodePayload(delivery.seq, delivery.buffer, delivery.offset, delivery.length, self.frame)
	if not decoded.ok then
		self.decodeErrors += 1
		return decoded
	end
	return Result.ok(decoded.value)
end

--- Forgets the stream (new battle).
function ReceiverClass.reset(self: SnapshotReceiver)
	self.assembler:reset()
end

function SnapshotCodec.newReceiver(options: Chunker.AssemblerOptions?): SnapshotReceiver
	return setmetatable({
		assembler = Chunker.newAssembler(SNAPSHOT_KIND, options),
		frame = SnapshotCodec.newFrame(),
		decodeErrors = 0,
	}, ReceiverClass)
end

return table.freeze(SnapshotCodec)
