-- SnapshotCodec: random round trips within the documented precision, chunking under 900 bytes, the 15 v 15 size
-- and bandwidth budget, loss/reorder/duplicate tolerance through the receiver, and hostile payloads -> clean Err.
-- QA ids: REG-NET-02 (packet size), REG-NET-05 (fuzz: never throws, never NaN), REG-SPT-08 (the codec carries only
-- what the server put in the frame: no hidden fields).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local SnapshotCodec = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/SnapshotCodec")
local Chunker = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Chunker")
local Quantize = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Quantize")
local Enums = require("@game/ReplicatedStorage/Shared/Net/Codecs/Battle/Enums")
local VehicleSim = require("@game/ReplicatedStorage/Shared/Vehicle/VehicleSim")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local TWO_PI = 2 * math.pi
local F32 = buffer.create(4)

local function f32(x: number): number
	buffer.writef32(F32, 0, x)
	return buffer.readf32(F32, 0)
end

local function angleDiff(a: number, b: number): number
	local d = (a - b) % TWO_PI
	if d > math.pi then
		d -= TWO_PI
	end
	return math.abs(d)
end

local function degDiff(a: number, b: number): number
	local d = (a - b) % 360
	if d > 180 then
		d -= 360
	end
	return math.abs(d)
end

local function pick(rng: any, list: { string }): any
	return list[rng:int(1, #list)]
end

local function randomEntity(rng: any, id: number): any
	return {
		id = id,
		position = Vector3.new(rng:range(-4500, 4500), rng:range(-450, 450), rng:range(-4500, 4500)),
		yaw = rng:range(-math.pi, math.pi),
		pitch = rng:range(-0.6, 0.6),
		roll = rng:range(-math.pi, math.pi),
		turretYawDeg = rng:range(-180, 180),
		gunPitchDeg = rng:range(-20, 65),
		speedKmh = rng:range(-30, 120),
		hpFraction = rng:next(),
		moving = rng:chance(0.5),
		firing = rng:chance(0.2),
		burning = rng:chance(0.1),
		tracksBroken = rng:chance(0.1),
		destroyed = rng:chance(0.1),
		stunned = rng:chance(0.1),
		mechanicActive = rng:chance(0.1),
	}
end

local function randomGun(rng: any): any
	local kind = pick(rng, Enums.ReloadKind.values)
	local slots = rng:int(1, 3)
	local ammo = {}
	for i = 1, slots do
		ammo[i] = rng:int(0, 120)
	end
	local barrels = {}
	if kind == "DualGun" then
		barrels = { rng:next(), rng:next() }
	end
	local duration = if rng:chance(0.7) then rng:range(1, 30) else 0
	return {
		kind = kind,
		phase = pick(rng, Enums.GunPhase.values),
		alive = rng:chance(0.9),
		enabled = rng:chance(0.9),
		canFire = rng:chance(0.5),
		selectedSlot = rng:int(1, slots),
		loadedSlot = rng:int(0, slots),
		reloadProgress = 0,
		reloadRemainingS = if duration > 0 then rng:range(0, duration) else 0,
		reloadDurationS = duration,
		nextShotS = if rng:chance(0.2) then math.huge else rng:range(0, 30),
		intraClipRemainingS = rng:range(0, 3),
		roundsLoaded = rng:int(0, 6),
		magazineSize = rng:int(1, 6),
		toppingOff = rng:chance(0.2),
		refillSlotIndex = rng:int(0, 6),
		chargeProgress = rng:next(),
		reloadMul = rng:range(0.5, 2),
		ammo = ammo,
		totalAmmo = 0,
		barrelProgress = barrels,
	}
end

local function randomOwner(rng: any, id: number, withGun: boolean?): any
	local modules = {}
	for i = 1, rng:int(0, 8) do
		local repairing = rng:chance(0.3)
		modules[i] = {
			kind = Enums.ModuleKind.values[i],
			state = pick(rng, Enums.ModuleState.values),
			repairRemainingS = if repairing then rng:range(0.5, 20) else 0,
			repairS = if repairing then rng:range(20, 40) else rng:range(5, 40),
		}
	end
	local crew = {}
	for i = 1, rng:int(0, 8) do
		crew[i] = rng:chance(0.3)
	end
	local consumables = {}
	for i = 1, rng:int(0, 3) do
		consumables[i] = {
			active = rng:chance(0.3),
			charges = if rng:chance(0.3) then math.huge else rng:int(0, 5),
			cooldownRemainingS = rng:range(0, 90),
			cooldownS = rng:range(30, 120),
			activeRemainingS = rng:range(0, 10),
		}
	end
	local mechanicKind = if rng:chance(0.5) then "" else pick(rng, Enums.MechanicKind.values)
	return {
		entityId = id,
		sim = {
			position = Vector3.new(rng:range(-4500, 4500), rng:range(-100, 300), rng:range(-4500, 4500)),
			yaw = rng:range(-10, 10),
			pitch = rng:range(-0.6, 0.6),
			roll = rng:range(-0.6, 0.6),
			speed = rng:range(-20, 60),
			lateralSpeed = rng:range(-3, 3),
			yawRate = rng:range(-1, 1),
			verticalVelocity = rng:range(-30, 5),
			grounded = rng:chance(0.8),
			groundPitch = rng:range(-0.5, 0.5),
			groundRoll = rng:range(-0.5, 0.5),
			waterDepthM = rng:range(0, 2),
			submerged = rng:chance(0.1),
			airborneTime = rng:range(0, 2),
			submergedTime = rng:range(0, 10),
			tiltTime = rng:range(0, 3),
			overturnedTime = rng:range(0, 10),
			stillTime = rng:range(0, 600),
			overturned = rng:chance(0.1),
			drowned = rng:chance(0.05),
			wrecked = rng:chance(0.05),
			immobilized = rng:chance(0.2),
			immobileReason = if rng:chance(0.5) then nil else pick(rng, Enums.ImmobileReason.values),
			mechanicActive = rng:chance(0.3),
			gunDepressionBonusDeg = rng:range(0, 8),
			gunElevationBonusDeg = rng:range(0, 6),
			modifiers = {
				engine = pick(rng, Enums.ModuleState.values),
				trackLeft = pick(rng, Enums.ModuleState.values),
				trackRight = pick(rng, Enums.ModuleState.values),
				lostWheelPairs = rng:int(0, 3),
				powerMul = rng:range(0.5, 1.5),
				topSpeedMul = rng:range(0.5, 1.5),
				topSpeedBonusKmh = rng:range(0, 20),
				reverseSpeedMul = rng:range(0.5, 1.5),
				speedCapKmh = if rng:chance(0.5) then math.huge else rng:range(5, 80),
				hullTraverseMul = rng:range(0.5, 1.5),
				immobilized = rng:chance(0.1),
			},
			mechanic = {
				kind = mechanicKind,
				phase = pick(rng, Enums.MechanicPhase.values),
				timer = rng:range(0, 30),
				charges = if rng:chance(0.5) then math.huge else rng:int(0, 3),
				lastInput = rng:chance(0.5),
				external = rng:chance(0.5),
				hydroActive = rng:chance(0.5),
			},
		},
		turret = {
			turretYawDeg = rng:range(-180, 180),
			gunYawDeg = rng:range(-11, 11),
			gunPitchDeg = rng:range(-10, 20),
			bearingSpeedDegS = rng:range(0, 60),
			pitchSpeedDegS = rng:range(0, 10),
			traverseMul = rng:range(0, 1.2),
			elevationSpeedMul = rng:range(0.5, 1.2),
			depressionBonusDeg = rng:range(0, 4),
			elevationBonusDeg = rng:range(0, 3),
			enabled = rng:chance(0.9),
		},
		gun = if withGun == false then nil else randomGun(rng),
		combat = {
			hp = rng:int(0, 3000),
			burning = rng:chance(0.2),
			stunRemainingS = rng:range(0, 15),
			modules = modules,
			crewInjured = crew,
			aimMultiplier = rng:range(1, 12),
			consumables = consumables,
		},
	}
end

local function randomFrame(rng: any, entityCount: number, minimapCount: number, withOwner: boolean): any
	local ids = {}
	for id = 1, 30 do
		ids[id] = id
	end
	rng:shuffle(ids)
	local entities, minimap = {}, {}
	for i = 1, entityCount do
		entities[i] = randomEntity(rng, ids[i])
	end
	for i = 1, minimapCount do
		local id = ids[entityCount + i]
		minimap[i] = { id = id, x = rng:range(-4500, 4500), z = rng:range(-4500, 4500), yaw = rng:range(-math.pi, math.pi) }
	end
	return {
		tick = rng:int(0, 1000000),
		lastInputSeq = rng:int(0, 200000),
		owner = if withOwner then randomOwner(rng, ids[30]) else nil,
		entities = entities,
		minimap = minimap,
	}
end

local function receive(chunks: { buffer }): any
	local receiver = SnapshotCodec.newReceiver()
	local frame = nil
	for _, c in chunks do
		local r = receiver:push(c)
		if not r.ok then
			error(`receiver rejected chunk: {tostring((r :: any).detail)}`)
		end
		frame = (r :: any).value or frame
	end
	return frame
end

local function check(cond: boolean, message: string)
	if not cond then
		error(message, 2)
	end
end

local function compareFrames(a: any, b: any)
	check(b.tick == a.tick, "tick")
	check(b.lastInputSeq == a.lastInputSeq % 65536, "lastInputSeq")
	check(#b.entities == #a.entities, "entity count")
	for i, e in a.entities do
		local d = b.entities[i]
		check(d.id == e.id, "entity id")
		local dp = d.position - e.position
		check(
			math.abs(dp.X) <= Quantize.POS_ERROR
				and math.abs(dp.Y) <= Quantize.POS_ERROR
				and math.abs(dp.Z) <= Quantize.POS_ERROR,
			`entity position error {dp}`
		)
		check(angleDiff(d.yaw, e.yaw) <= Quantize.ANGLE_ERROR + 1e-9, "yaw")
		check(angleDiff(d.pitch, e.pitch) <= Quantize.ANGLE_ERROR + 1e-9, "pitch")
		check(angleDiff(d.roll, e.roll) <= Quantize.ANGLE_ERROR + 1e-9, "roll")
		check(degDiff(d.turretYawDeg, e.turretYawDeg) <= 360 / 131072 + 1e-9, "turret")
		check(degDiff(d.gunPitchDeg, e.gunPitchDeg) <= 360 / 131072 + 1e-9, "gun pitch")
		check(math.abs(d.speedKmh - e.speedKmh) <= 0.64 + 1e-9, "speed")
		check(math.abs(d.hpFraction - e.hpFraction) <= Quantize.FRACTION_ERROR + 1e-12, "hp")
		check(e.hpFraction <= 0 or d.hpFraction > 0, "alive entity decoded with 0 hp")
		for _, key in { "moving", "firing", "burning", "tracksBroken", "destroyed", "stunned", "mechanicActive" } do
			check(d[key] == e[key], `flag {key}`)
		end
	end
	check(#b.minimap == #a.minimap, "minimap count")
	for i, r in a.minimap do
		local d = b.minimap[i]
		check(d.id == r.id, "minimap id")
		check(math.abs(d.x - r.x) <= 0.5 and math.abs(d.z - r.z) <= 0.5, "minimap position")
		check(angleDiff(d.yaw, r.yaw) <= Quantize.ANGLE8_ERROR + 1e-9, "minimap yaw")
	end
	if a.owner == nil then
		check(b.owner == nil, "owner should be absent")
		return
	end
	local o, p = a.owner, b.owner
	check(p ~= nil and p.entityId == o.entityId, "owner id")
	for key, value in o.sim do
		local got = p.sim[key]
		if key == "modifiers" or key == "mechanic" then
			for k2, v2 in value do
				local g2 = got[k2]
				if type(v2) == "number" then
					check(g2 == f32(v2), `sim.{key}.{k2}: {g2} vs {v2}`)
				else
					check(g2 == v2, `sim.{key}.{k2}`)
				end
			end
		elseif typeof(value) == "Vector3" then
			check(got == value, "sim.position")
		elseif type(value) == "number" then
			check(got == f32(value), `sim.{key}: {got} vs {value}`)
		else
			check(got == value, `sim.{key}`)
		end
	end
	check(p.sim.immobileReason == o.sim.immobileReason, "immobileReason")
	for key, value in o.turret do
		if type(value) == "number" then
			check(p.turret[key] == f32(value), `turret.{key}`)
		else
			check(p.turret[key] == value, `turret.{key}`)
		end
	end
	local c, q = o.combat, p.combat
	check(q.hp == c.hp, "hp")
	check(q.burning == c.burning, "burning")
	check(math.abs(q.stunRemainingS - c.stunRemainingS) <= 0.005 + 1e-9, "stun")
	check(math.abs(q.aimMultiplier - c.aimMultiplier) <= 0.0005 + 1e-9, "aim multiplier")
	check(#q.modules == #c.modules, "module count")
	for i, m in c.modules do
		local n = q.modules[i]
		check(n.kind == m.kind and n.state == m.state, "module kind/state")
		if m.repairRemainingS > 0 then
			check(math.abs(n.repairRemainingS - m.repairRemainingS) <= 0.005 + 1e-9, "module repair")
			check(math.abs(n.repairS - m.repairS) <= 0.005 + 1e-9, "module repairS")
		else
			check(n.repairRemainingS == 0 and n.repairS == 0, "module without repair")
		end
	end
	check(#q.crewInjured == #c.crewInjured, "crew count")
	for i, injured in c.crewInjured do
		check(q.crewInjured[i] == injured, "crew injured")
	end
	check(#q.consumables == #c.consumables, "consumable count")
	for i, item in c.consumables do
		local d = q.consumables[i]
		check(d.active == item.active and d.charges == item.charges, "consumable charges/active")
		check(math.abs(d.cooldownRemainingS - item.cooldownRemainingS) <= 0.005 + 1e-9, "cooldown left")
		check(math.abs(d.cooldownS - item.cooldownS) <= 0.005 + 1e-9, "cooldown")
		check(math.abs(d.activeRemainingS - item.activeRemainingS) <= 0.005 + 1e-9, "active left")
	end
	if o.gun == nil then
		check(p.gun == nil, "gun should be absent")
		return
	end
	local g, h = o.gun, p.gun
	check(h ~= nil, "gun missing")
	for _, key in { "kind", "phase", "alive", "enabled", "canFire", "toppingOff" } do
		check(h[key] == g[key], `gun.{key}`)
	end
	for _, key in { "selectedSlot", "loadedSlot", "roundsLoaded", "magazineSize", "refillSlotIndex" } do
		check(h[key] == g[key], `gun.{key}`)
	end
	for _, key in { "reloadRemainingS", "reloadDurationS", "intraClipRemainingS" } do
		check(math.abs(h[key] - g[key]) <= 0.005 + 1e-9, `gun.{key}`)
	end
	check(
		(g.nextShotS == math.huge and h.nextShotS == math.huge) or math.abs(h.nextShotS - g.nextShotS) <= 0.005 + 1e-9,
		"nextShotS"
	)
	check(math.abs(h.chargeProgress - g.chargeProgress) <= 0.5 / 255 + 1e-9, "charge")
	check(math.abs(h.reloadMul - g.reloadMul) <= 0.0005 + 1e-9, "reloadMul")
	local total = 0
	for i, n in g.ammo do
		check(h.ammo[i] == n, "ammo")
		total += n
	end
	check(#h.ammo == #g.ammo and h.totalAmmo == total, "ammo totals")
	check(#h.barrelProgress == #g.barrelProgress, "barrels")
	for i, v in g.barrelProgress do
		check(math.abs(h.barrelProgress[i] - v) <= 0.5 / 255 + 1e-9, "barrel progress")
	end
	check(h.reloadProgress >= 0 and h.reloadProgress <= 1, "reload progress range")
end

describe("SnapshotCodec round trip", function()
	it("restores 400 random frames within the documented precision", function()
		local rng = RNG.new(2026)
		for _ = 1, 400 do
			local entities = rng:int(0, 29)
			local minimap = rng:int(0, 30 - entities - 1)
			local frame = randomFrame(rng, entities, minimap, rng:chance(0.8))
			local chunks = SnapshotCodec.encode(frame)
			for _, c in chunks do
				check(buffer.len(c) <= 900, "chunk over 900 bytes")
			end
			compareFrames(frame, receive(chunks))
		end
	end)

	it("carries math.huge speed caps and unlimited charges, and derives reload progress like GunState", function()
		local rng = RNG.new(1)
		local frame = randomFrame(rng, 0, 0, true)
		frame.owner.sim.modifiers.speedCapKmh = math.huge
		frame.owner.sim.mechanic.charges = math.huge
		frame.owner.gun.reloadRemainingS = 2.5
		frame.owner.gun.reloadDurationS = 10
		local out = receive(SnapshotCodec.encode(frame))
		expect(out.owner.sim.modifiers.speedCapKmh).toBe(math.huge)
		expect(out.owner.sim.mechanic.charges).toBe(math.huge)
		expect(out.owner.gun.reloadProgress).toBeCloseTo(0.75, 1e-9)
		frame.owner.gun.reloadDurationS = 0
		frame.owner.gun.reloadRemainingS = 0
		frame.owner.gun.roundsLoaded = 1
		expect(receive(SnapshotCodec.encode(frame)).owner.gun.reloadProgress).toBe(1)
		frame.owner.gun.roundsLoaded = 0
		expect(receive(SnapshotCodec.encode(frame)).owner.gun.reloadProgress).toBe(0)
	end)

	it("encodes a real VehicleSimState as the owner's sim (contract with Types/VehicleSim)", function()
		local rng = RNG.new(3)
		local frame = randomFrame(rng, 2, 0, true)
		local state = VehicleSim.newState(CFrame.new(10, 2, -30) * CFrame.Angles(0, 0.5, 0))
		frame.owner.sim = state
		local out = receive(SnapshotCodec.encode(frame))
		expect(out.owner.sim.position).toEqual(state.position)
		expect(out.owner.sim.yaw).toBe(f32(state.yaw))
		expect(out.owner.sim.modifiers.speedCapKmh).toBe(state.modifiers.speedCapKmh)
		expect(out.owner.sim.mechanic.kind).toBe(state.mechanic.kind)
	end)

	it("supports spectators (no owner) and gunless owners", function()
		local rng = RNG.new(4)
		local spectator = randomFrame(rng, 10, 3, false)
		compareFrames(spectator, receive(SnapshotCodec.encode(spectator)))
		local gunless = randomFrame(rng, 5, 0, true)
		gunless.owner.gun = nil
		compareFrames(gunless, receive(SnapshotCodec.encode(gunless)))
	end)

	it("keeps every alive entity's HP above zero and full HP exact", function()
		local rng = RNG.new(5)
		local frame = randomFrame(rng, 3, 0, false)
		frame.entities[1].hpFraction = 1e-9
		frame.entities[2].hpFraction = 1
		frame.entities[3].hpFraction = 0
		local out = receive(SnapshotCodec.encode(frame))
		expect(out.entities[1].hpFraction > 0).toBe(true)
		expect(out.entities[2].hpFraction).toBe(1)
		expect(out.entities[3].hpFraction).toBe(0)
	end)

	it("reuses the receiver frame and trims shorter lists", function()
		local rng = RNG.new(6)
		local receiver = SnapshotCodec.newReceiver()
		local big = randomFrame(rng, 20, 5, true)
		big.tick = 10
		local small = randomFrame(rng, 2, 0, true)
		small.tick = 11
		local first = (receiver:push(SnapshotCodec.encode(big)[1]) :: any).value
		if first == nil then
			local chunks = SnapshotCodec.encode(big)
			for i = 2, #chunks do
				first = (receiver:push(chunks[i]) :: any).value or first
			end
		end
		expect(#first.entities).toBe(20)
		local ownerTable = first.owner
		local second = receive(SnapshotCodec.encode(small))
		local again = nil
		for _, c in SnapshotCodec.encode(small) do
			again = (receiver:push(c) :: any).value or again
		end
		expect(again).toBe(first)
		expect(#again.entities).toBe(2)
		expect(#again.minimap).toBe(0)
		expect(again.owner).toBe(ownerTable)
		compareFrames(small, second)
		compareFrames(small, again)
	end)
end)

describe("SnapshotCodec encodeIds and cache", function()
	it("produces the same bytes as encode for the same frame", function()
		local rng = RNG.new(7)
		local frame = randomFrame(rng, 12, 4, true)
		local cache = SnapshotCodec.newEntityCache()
		local ids = {}
		for i, e in frame.entities do
			SnapshotCodec.cacheEntity(cache, e)
			ids[i] = e.id
		end
		local a = SnapshotCodec.encode(frame)
		local b = SnapshotCodec.encodeIds(frame.tick, frame.lastInputSeq, frame.owner, cache, ids, nil, frame.minimap)
		expect(#a).toBe(#b)
		for i = 1, #a do
			expect(buffer.tostring(a[i])).toBe(buffer.tostring(b[i]))
		end
	end)

	it("lets each observer pick a subset of the cached vehicles (server fan-out)", function()
		local rng = RNG.new(8)
		local cache = SnapshotCodec.newEntityCache()
		local all = {}
		for id = 1, 29 do
			all[id] = randomEntity(rng, id)
			SnapshotCodec.cacheEntity(cache, all[id])
		end
		local visible = { 3, 17, 29, 1 }
		local out = receive(SnapshotCodec.encodeIds(55, 9, nil, cache, visible))
		expect(#out.entities).toBe(4)
		for i, id in visible do
			expect(out.entities[i].id).toBe(id)
		end
		SnapshotCodec.clearCache(cache)
		expect(function()
			SnapshotCodec.encodeIds(56, 9, nil, cache, visible)
		end).toThrow("was not cached")
	end)

	it("raises on programming mistakes", function()
		local rng = RNG.new(9)
		local cache = SnapshotCodec.newEntityCache()
		local e = randomEntity(rng, 0)
		expect(function()
			SnapshotCodec.cacheEntity(cache, e)
		end).toThrow("entity id in 1..255")
		e.id = 256
		expect(function()
			SnapshotCodec.cacheEntity(cache, e)
		end).toThrow("entity id in 1..255")
		e.id = 4
		e.position = Vector3.new(0 / 0, 0, 0)
		expect(function()
			SnapshotCodec.cacheEntity(cache, e)
		end).toThrow("finite Vector3")
		e.position = Vector3.zero
		e.yaw = math.huge
		expect(function()
			SnapshotCodec.cacheEntity(cache, e)
		end).toThrow("attitude must be finite")
		local frame = randomFrame(rng, 0, 0, true)
		frame.owner.sim.speed = 0 / 0
		expect(function()
			SnapshotCodec.encode(frame)
		end).toThrow("sim.speed must be a finite number")
		frame = randomFrame(rng, 0, 0, true)
		frame.owner.sim.modifiers.speedCapKmh = -math.huge
		expect(function()
			SnapshotCodec.encode(frame)
		end).toThrow("speedCapKmh must be finite or +inf")
		frame = randomFrame(rng, 0, 0, true)
		frame.owner.sim.mechanic.phase = "Sideways"
		expect(function()
			SnapshotCodec.encode(frame)
		end).toThrow("unknown value Sideways")
		frame = randomFrame(rng, 0, 0, true)
		frame.owner.sim.position = Vector3.new(1e30, 0, 0)
		expect(SnapshotCodec.encode(frame)).never.toBeNil() -- f32-representable: fine
		local many = {}
		for i = 1, 65 do
			many[i] = 1
		end
		SnapshotCodec.cacheEntity(cache, randomEntity(rng, 1))
		expect(function()
			SnapshotCodec.encodeIds(1, 0, nil, cache, many)
		end).toThrow("at most 64 entities")
	end)
end)

describe("SnapshotCodec size budget (15 v 15)", function()
	local function worstOwner(rng: any): any
		local owner = randomOwner(rng, 30)
		for i = 1, 8 do
			owner.combat.modules[i] = {
				kind = Enums.ModuleKind.values[i],
				state = "Destroyed",
				repairRemainingS = 10,
				repairS = 20,
			}
		end
		owner.combat.crewInjured = { true, false, true, false, true, false }
		owner.combat.consumables = {}
		for i = 1, 3 do
			owner.combat.consumables[i] =
				{ active = true, charges = 2, cooldownRemainingS = 5, cooldownS = 60, activeRemainingS = 3 }
		end
		owner.gun = randomGun(rng)
		owner.gun.kind = "DualGun"
		owner.gun.ammo = { 30, 20, 10 }
		owner.gun.barrelProgress = { 0.5, 1 }
		return owner
	end

	it("payloadBytes matches the encoded size exactly", function()
		local rng = RNG.new(10)
		for _ = 1, 200 do
			local frame = randomFrame(rng, rng:int(0, 29), 0, rng:chance(0.8))
			if rng:chance(0.5) and #frame.entities < 25 then
				frame.minimap = { { id = 200, x = 1, z = 2, yaw = 0 }, { id = 201, x = 3, z = 4, yaw = 1 } }
			end
			local chunks = SnapshotCodec.encode(frame)
			local bytes = 0
			for _, c in chunks do
				bytes += buffer.len(c) - Chunker.HEADER_BYTES
			end
			local minimapCount = if #frame.minimap > 0 then #frame.minimap else nil
			expect(SnapshotCodec.payloadBytes(frame.owner, #frame.entities, minimapCount)).toBe(bytes)
		end
	end)

	it("fits the worst case (owner + 29 vehicles) in 2 packets and <= 20 KB/s at 20 Hz", function()
		local rng = RNG.new(11)
		local frame = randomFrame(rng, 29, 0, false)
		frame.owner = worstOwner(rng)
		local chunks = SnapshotCodec.encode(frame)
		local wire = 0
		for _, c in chunks do
			expect(buffer.len(c) <= 900).toBe(true)
			wire += buffer.len(c)
		end
		expect(#chunks).toBe(2)
		expect(wire * 20 <= 20 * 1024).toBe(true) -- ARCHITECTURE §5.2 average budget, even at full visibility
		-- typical mid-battle view (owner + 14 allies + 6 spotted enemies) is a single packet
		local typical = randomFrame(rng, 20, 3, false)
		typical.owner = worstOwner(rng)
		expect(#SnapshotCodec.encode(typical)).toBe(1)
	end)
end)

describe("SnapshotCodec receiver under loss, reordering and duplication", function()
	it("delivers only complete, strictly newer snapshots", function()
		local rng = RNG.new(12)
		local frames = {}
		local wire = {}
		for tick = 1, 300 do
			local frame = randomFrame(rng, rng:int(10, 29), 0, true)
			frame.tick = tick * 3
			frames[frame.tick] = frame
			for _, c in SnapshotCodec.encode(frame) do
				if not rng:chance(0.1) then
					table.insert(wire, c)
					if rng:chance(0.05) then
						table.insert(wire, c)
					end
				end
			end
		end
		for i = 1, #wire - 1 do
			if rng:chance(0.25) then
				local j = math.min(#wire, i + rng:int(1, 3))
				wire[i], wire[j] = wire[j], wire[i]
			end
		end
		local receiver = SnapshotCodec.newReceiver()
		local last = -1
		local delivered = 0
		for _, c in wire do
			local r = receiver:push(c)
			expect(r.ok).toBe(true)
			local frame = (r :: any).value
			if frame ~= nil then
				check(frame.tick > last, "snapshot rolled back")
				last = frame.tick
				delivered += 1
				compareFrames(frames[frame.tick], frame)
			end
		end
		expect(delivered > 150).toBe(true)
		expect(receiver.assembler.stats.malformed).toBe(0)
	end)
end)

describe("SnapshotCodec hostile payloads (REG-NET-05)", function()
	local function scanNaN(value: any, path: string)
		if type(value) == "number" then
			check(value == value and value ~= -math.huge, `NaN or -inf at {path}`)
		elseif typeof(value) == "Vector3" then
			check(value.X == value.X and value.Y == value.Y and value.Z == value.Z, `NaN vector at {path}`)
		elseif type(value) == "table" then
			for k, v in value do
				scanNaN(v, path .. "." .. tostring(k))
			end
		end
	end

	local function payloadOf(frame: any): buffer
		local chunks = SnapshotCodec.encode(frame)
		local total = 0
		for _, c in chunks do
			total += buffer.len(c) - Chunker.HEADER_BYTES
		end
		local b = buffer.create(total)
		local at = 0
		for _, c in chunks do
			local n = buffer.len(c) - Chunker.HEADER_BYTES
			buffer.copy(b, at, c, Chunker.HEADER_BYTES, n)
			at += n
		end
		return b
	end

	it("rejects every truncation and trailing bytes", function()
		local rng = RNG.new(13)
		local b = payloadOf(randomFrame(rng, 3, 2, true))
		local len = buffer.len(b)
		for cut = 0, len - 1 do
			local r = SnapshotCodec.decodePayload(1, b, 0, cut)
			check(not r.ok and r.err == "INVALID_ARGS", `truncation at {cut} accepted`)
		end
		local longer = buffer.create(len + 1)
		buffer.copy(longer, 0, b)
		expect(SnapshotCodec.decodePayload(1, longer, 0, len + 1)).toBeErr("INVALID_ARGS")
		expect(SnapshotCodec.decodePayload(1, b, 0, len)).toBeOk()
		expect(SnapshotCodec.decodePayload(1, b, 5, len)).toBeErr("INVALID_ARGS")
		expect(SnapshotCodec.decodePayload(1, b, -1, 2)).toBeErr("INVALID_ARGS")
	end)

	it("rejects reserved bits, unknown enum codes and zero ids", function()
		local rng = RNG.new(14)
		local spectator = payloadOf(randomFrame(rng, 1, 0, false))
		local function mutated(src: buffer, offset: number, value: number): buffer
			local b = buffer.create(buffer.len(src))
			buffer.copy(b, 0, src)
			buffer.writeu8(b, offset, value)
			return b
		end
		local function decode(b: buffer): any
			return SnapshotCodec.decodePayload(1, b, 0, buffer.len(b))
		end
		expect(decode(mutated(spectator, 0, 4))).toBeErr("INVALID_ARGS") -- payload flags reserved bit
		expect(decode(mutated(spectator, 4, 0))).toBeErr("INVALID_ARGS") -- entity id 0
		expect(decode(mutated(spectator, 4 + 23, 128))).toBeErr("INVALID_ARGS") -- entity flags reserved bit
		expect(decode(mutated(spectator, 4 + 20, 0x80))).toBeErr("INVALID_ARGS") -- speed -128
		local withOwner = payloadOf(randomFrame(rng, 0, 0, true))
		expect(decode(mutated(withOwner, 3, 0))).toBeErr("INVALID_ARGS") -- owner id 0
		-- owner f32 position X = NaN
		local nan = buffer.create(buffer.len(withOwner))
		buffer.copy(nan, 0, withOwner)
		buffer.writef32(nan, 4, 0 / 0)
		expect(decode(nan)).toBeErr("INVALID_ARGS")
		buffer.writef32(nan, 4, math.huge)
		expect(decode(nan)).toBeErr("INVALID_ARGS")
		-- immobile reason code 200 (offset: 1 + 2 + 1 + 80 + 2)
		expect(decode(mutated(withOwner, 86, 200))).toBeErr("INVALID_ARGS")
		-- module-state byte with reserved bits (offset 87)
		expect(decode(mutated(withOwner, 87, 0xC0))).toBeErr("INVALID_ARGS")
		-- module-state code 3 does not exist (bits 0-1 = 3)
		expect(decode(mutated(withOwner, 87, 3))).toBeErr("INVALID_ARGS")
	end)

	it("10k random bit flips and random payloads never throw and never yield NaN", function()
		local rng = RNG.new(4242)
		local frames = {}
		for i = 1, 8 do
			frames[i] = payloadOf(randomFrame(rng, rng:int(0, 12), rng:int(0, 3), rng:chance(0.8)))
		end
		local out = SnapshotCodec.newFrame()
		local accepted = 0
		for i = 1, 10000 do
			local b: buffer
			if i % 4 == 0 then
				local len = rng:int(0, 400)
				b = buffer.create(len)
				for j = 0, len - 1 do
					buffer.writeu8(b, j, rng:int(0, 255))
				end
			else
				local src = frames[rng:int(1, #frames)]
				b = buffer.create(buffer.len(src))
				buffer.copy(b, 0, src)
				for _ = 1, rng:int(1, 4) do
					local at = rng:int(0, buffer.len(b) - 1)
					buffer.writeu8(b, at, bit32.bxor(buffer.readu8(b, at), 2 ^ rng:int(0, 7)))
				end
			end
			local called, r = pcall(SnapshotCodec.decodePayload, i, b, 0, buffer.len(b), out)
			check(called, `decodePayload threw: {tostring(r)}`)
			if r.ok then
				accepted += 1
				scanNaN(r.value, "frame")
			else
				check(r.err == "INVALID_ARGS", "unexpected error code")
			end
		end
		expect(accepted > 1000).toBe(true)
	end)

	it("the receiver rejects garbage chunks cleanly", function()
		local receiver = SnapshotCodec.newReceiver()
		expect(receiver:push(nil)).toBeErr("INVALID_ARGS")
		expect(receiver:push("snapshot")).toBeErr("INVALID_ARGS")
		local chunk = buffer.create(10)
		buffer.writeu8(chunk, 0, SnapshotCodec.KIND)
		buffer.writeu32(chunk, 1, 5)
		buffer.writeu8(chunk, 5, 0)
		buffer.writeu8(chunk, 6, 1)
		expect(receiver:push(chunk)).toBeErr("INVALID_ARGS") -- complete but undecodable payload
		expect(receiver.decodeErrors).toBe(1)
		receiver:reset()
		expect(receiver.assembler.lastSeq).toBeNil()
	end)
end)
