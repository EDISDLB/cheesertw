--!strict
--[[
	Spotting/SpottingSystem — server-authoritative visibility for one battle (00-DECISIONS §5, ARCHITECTURE §6.1 tick
	step 7): staggered directed pair checks, proximity, LOS from 2 observer ports to the target's checkpoints through
	World:sightLine (hard cover, foliage with the 15 m rules, smoke), linger, per-team visible sets, last-known markers,
	Sixth Sense, spotter attribution and the replication filter (isVisibleTo / visibleSet / replicationTier).

	Purpose:          THE anti-wallhack source: replication sends an enemy's state to a client only if
	                  isVisibleTo(clientTeam, enemyId) (full state only within ENEMY_DRAW_RANGE_M, see replicationTier).
	                  Scoring reads Spotted events (first detection) and spottersOf (assist credit).
	Dependencies:     Config (Spotting), Core/RNG (pair hash), Core/Units, Types/World, Types/Spotting,
	                  Spotting/VisibilityModel.
	State:            Per battle: vehicle records (sorted by id), directed enemy pairs (schedule, last success),
	                  per-team visible sets / first-detection flags / last-known markers, a reused event buffer.
	Validation:       update() raises on structural mistakes (non-table record, non-number id/team, duplicate id, team
	                  change, missing CFrame/pivots/camo, non-finite or decreasing `now`). Non-finite poses skip the
	                  vehicle's pairs that tick; non-finite VR/camo degrade per VisibilityModel.
	Error handling:   Errors only for programming mistakes (above); world results with NaN foliage count as blocked.
	Performance notes: O(pairs) numeric work per update (450 pairs for 15 v 15) with no per-pair allocation; World
	                  queries are capped at MAX_RAYS_PER_TICK (forced pairs first, then long-deferred pairs, then nearest
	                  first; the rest wait). Ports/checkpoints are built lazily, once per vehicle per update. Events,
	                  visible sets and the stats record are reused: copy what you keep.

	Rules (all values Config.Spotting):
	  * A directed pair (observer o, target t) exists for every two vehicles of different teams. Distances are hull
	    centre to hull centre (3-D, metres).
	  * Every update: d <= PROXIMITY_RADIUS_M spots (no ray). Otherwise a pair is checked when due (scheduledInterval)
	    or forced (t fired; o or t stopped / spawned / revived; forceCheck). Due pairs beyond MAX_SPOT_RANGE_M or
	    beyond spotDistance(VR_o, min(CAMO_TOTAL_CAP, body_t)) are rejected without rays. The rest are served within
	    MAX_RAYS_PER_TICK: forced pairs nearest first, then pairs overdue by DEFER_PRIORITY_S oldest first, then
	    nearest first; a pair the budget cannot finish stays due (its partial rays are discarded).
	  * LOS: for port in (gun-axis view point, roof port over the hull centre), for checkpoint in t's camoPoints:
	    World:sightLine(port, checkpoint); blocked or smoke (SMOKE_BLOCKS_LOS) fails the ray; otherwise
	    camo = totalCamo(body_t, effectiveFoliage) and the ray succeeds if d <= spotDistance(VR_o, camo). Foliage within
	    FOLIAGE_OBSERVER_CLEAR_M of the port never conceals; foliage within FOLIAGE_SHOOTER_CLEAR_M of the checkpoint
	    stops concealing for SHOT_FOLIAGE_PENALTY_S after t fires (sub-segment queries only when foliage decides).
	    The first successful ray wins.
	  * A team sees t while some observer of the team succeeded within SPOT_LINGER_S (dead observers keep their past
	    sightings if DEAD_SPOTTER_KEEPS_LINGER but never start new ones). Transitions emit Spotted / Lost; Lost leaves a
	    last-known marker for LAST_KNOWN_MARKER_S.
	  * Wrecks (alive = false) are visible to every team, never observe, and leave the visible sets silently.
	  * Sixth Sense: one SixthSense event SIXTH_SENSE_DELAY_S after a vehicle first becomes visible to any enemy team,
	    while still visible and sixthSense ~= false; re-armed only after a fully unspotted period.
	  * Determinism: everything iterates in id order; ties are broken by id; no wall clock, no unseeded randomness.
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Units = require("@game/ReplicatedStorage/Shared/Core/Units")
local WorldTypes = require("@game/ReplicatedStorage/Shared/Types/World")
local SpottingTypes = require("@game/ReplicatedStorage/Shared/Types/Spotting")
local VisibilityModel = require("./VisibilityModel")

type World = WorldTypes.World
type SpottingVehicle = SpottingTypes.SpottingVehicle
type SpottingPivots = SpottingTypes.SpottingPivots
type SpottingEvent = SpottingTypes.SpottingEvent
type SpottingEventKind = SpottingTypes.SpottingEventKind
type SpottingStats = SpottingTypes.SpottingStats
type SpottingOptions = SpottingTypes.SpottingOptions
type ReplicationTier = SpottingTypes.ReplicationTier
type PairInfo = SpottingTypes.PairInfo

type FoliageFn = (any, Vector3, Vector3) -> number

local NEVER = -math.huge
local TIME_EPS = 1e-6
local STUDS_PER_M = Units.STUDS_PER_METER
local GOLDEN = 0.6180339887498949
local TWO32 = 4294967296
local EMPTY_IDS: { number } = table.freeze({})

type VehicleRec = {
	id: number,
	team: number,
	src: SpottingVehicle,
	epoch: number,
	spawned: boolean,
	alive: boolean,
	valid: boolean,
	moving: boolean,
	stationarySince: number?,
	lastShotSeen: number,
	firedRecently: boolean,
	forcePending: boolean,
	cx: number,
	cy: number,
	cz: number,
	vr: number,
	body: number,
	pivotsRef: SpottingPivots?,
	halfHeight: number,
	roofLocal: Vector3,
	geomTick: number,
	ports: { Vector3 },
	nPorts: number,
	cps: { Vector3 },
	nCps: number,
	exposed: boolean,
	exposedSince: number?,
	sixthDone: boolean,
	asObserver: { PairRec },
	asTarget: { PairRec },
}

type PairRec = {
	observer: VehicleRec,
	target: VehicleRec,
	order: number,
	phase: number,
	checks: number,
	nextCheck: number,
	lastCheck: number,
	lastSeen: number,
	forced: boolean,
	distM: number,
	prioClass: number,
	sortKey: number,
}

type Marker = { position: Vector3, at: number }

type TeamRec = {
	id: number,
	visible: { [number]: boolean },
	ever: { [number]: boolean },
	markers: { [number]: Marker },
	list: { number },
	bestSeen: { [number]: number },
	bestSpotter: { [number]: number },
}

local SpottingSystemClass = {}
SpottingSystemClass.__index = SpottingSystemClass

type SystemData = {
	_byId: { [number]: VehicleRec },
	_order: { VehicleRec },
	_pairs: { PairRec },
	_pairMap: { [number]: { [number]: PairRec } },
	_teams: { [number]: TeamRec },
	_teamOrder: { TeamRec },
	_due: { PairRec },
	_events: { SpottingEvent },
	_pool: { SpottingEvent },
	_eventCount: number,
	_epoch: number,
	_tick: number,
	_now: number,
	_rays: number,
	_probes: number,
	_stats: SpottingStats,
	_visibilityMult: number,
}

export type SpottingSystem = typeof(setmetatable({} :: SystemData, SpottingSystemClass))

local SpottingSystem = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function byRecId(a: VehicleRec, b: VehicleRec): boolean
	return a.id < b.id
end

local function byTeamId(a: TeamRec, b: TeamRec): boolean
	return a.id < b.id
end

-- Due-pair order: forced (nearest first), then pairs deferred >= DEFER_PRIORITY_S (longest-waiting first, so no pair
-- can starve under sustained overload), then the rest (nearest first); pair order breaks ties.
local function dueLess(a: PairRec, b: PairRec): boolean
	if a.prioClass ~= b.prioClass then
		return a.prioClass < b.prioClass
	end
	if a.sortKey ~= b.sortKey then
		return a.sortKey < b.sortKey
	end
	return a.order < b.order
end

local function shotTime(v: SpottingVehicle): number
	local s = v.lastShotAt
	if type(s) == "number" and isFinite(s) then
		return s
	end
	return NEVER
end

local function validateRecord(v: any, index: number)
	if type(v) ~= "table" then
		error(`SpottingSystem.update: vehicles[{index}] is not a table`, 4)
	end
	if type(v.id) ~= "number" or not isFinite(v.id) then
		error(`SpottingSystem.update: vehicles[{index}].id must be a finite number`, 4)
	end
	if type(v.team) ~= "number" or not isFinite(v.team) then
		error(`SpottingSystem.update: vehicle {v.id} team must be a finite number`, 4)
	end
	if typeof(v.cframe) ~= "CFrame" then
		error(`SpottingSystem.update: vehicle {v.id} cframe must be a CFrame`, 4)
	end
	local piv = v.pivots
	if
		type(piv) ~= "table"
		or typeof(piv.turretRing) ~= "CFrame"
		or typeof(piv.viewPoint) ~= "Vector3"
		or type(piv.camoPoints) ~= "table"
		or typeof(piv.hullSize) ~= "Vector3"
	then
		error(`SpottingSystem.update: vehicle {v.id} pivots need turretRing, viewPoint, camoPoints, hullSize`, 4)
	end
	if type(v.camo) ~= "table" then
		error(`SpottingSystem.update: vehicle {v.id} camo must be a CamoStats table`, 4)
	end
end

local function newVehicleRec(v: SpottingVehicle, epoch: number): VehicleRec
	return {
		id = v.id,
		team = v.team,
		src = v,
		epoch = epoch,
		spawned = false,
		alive = false,
		valid = false,
		moving = false,
		stationarySince = nil,
		lastShotSeen = NEVER,
		firedRecently = false,
		forcePending = false,
		cx = 0,
		cy = 0,
		cz = 0,
		vr = 0,
		body = 0,
		pivotsRef = nil,
		halfHeight = 0,
		roofLocal = Vector3.zero,
		geomTick = 0,
		ports = {},
		nPorts = 0,
		cps = {},
		nCps = 0,
		exposed = false,
		exposedSince = nil,
		sixthDone = false,
		asObserver = {},
		asTarget = {},
	}
end

local function newTeamRec(id: number): TeamRec
	return { id = id, visible = {}, ever = {}, markers = {}, list = {}, bestSeen = {}, bestSpotter = {} }
end

local function newPair(o: VehicleRec, t: VehicleRec, now: number): PairRec
	return {
		observer = o,
		target = t,
		order = 0,
		phase = RNG.hash(o.id, t.id) / TWO32,
		checks = 0,
		nextCheck = now,
		lastCheck = NEVER,
		lastSeen = NEVER,
		forced = false,
		distM = 0,
		prioClass = 2,
		sortKey = 0,
	}
end

local function emit(
	self: SpottingSystem,
	kind: SpottingEventKind,
	now: number,
	team: number,
	target: number,
	spotter: number?,
	first: boolean,
	position: Vector3?
)
	local n = self._eventCount + 1
	self._eventCount = n
	local ev = self._pool[n]
	if ev == nil then
		ev = {
			kind = kind,
			t = now,
			team = team,
			target = target,
			spotter = spotter,
			first = first,
			position = position,
		}
		self._pool[n] = ev
	else
		ev.kind = kind
		ev.t = now
		ev.team = team
		ev.target = target
		ev.spotter = spotter
		ev.first = first
		ev.position = position
	end
	self._events[n] = ev
end

local function forcePairs(rec: VehicleRec, asObserverToo: boolean)
	for _, pair in rec.asTarget do
		pair.forced = true
	end
	if asObserverToo then
		for _, pair in rec.asObserver do
			pair.forced = true
		end
	end
end

local function schedule(pair: PairRec, now: number, distM: number)
	pair.checks += 1
	local phase = (pair.phase + pair.checks * GOLDEN) % 1
	pair.nextCheck = now + VisibilityModel.scheduledInterval(distM, phase)
end

local function ensurePivotConsts(rec: VehicleRec, piv: SpottingPivots)
	if rec.pivotsRef == piv then
		return
	end
	rec.pivotsRef = piv
	local hullY = piv.hullSize.Y
	rec.halfHeight = hullY / 2
	-- Roof port: over the hull centre at the top of the hull + turret box (approximated by the highest known point).
	local top = hullY
	local viewY = piv.turretRing:PointToWorldSpace(piv.viewPoint).Y
	if viewY > top then
		top = viewY
	end
	for _, p in piv.camoPoints do
		if p.Y > top then
			top = p.Y
		end
	end
	rec.roofLocal = Vector3.new(0, top, 0)
end

-- World positions of the observer ports and target checkpoints, built at most once per vehicle per update.
local function ensureGeometry(self: SpottingSystem, rec: VehicleRec, maxCheckpoints: number)
	if rec.geomTick == self._tick then
		return
	end
	rec.geomTick = self._tick
	local v = rec.src
	local piv = v.pivots
	local cf = v.cframe
	local yaw = v.turretYawRad
	local turretCf = cf * piv.turretRing
	if type(yaw) == "number" and isFinite(yaw) and yaw ~= 0 then
		turretCf *= CFrame.Angles(0, -yaw, 0)
	end
	-- Port 1 (turret first): the gun-axis view point; port 2: the static roof port.
	rec.ports[1] = turretCf:PointToWorldSpace(piv.viewPoint)
	rec.ports[2] = cf:PointToWorldSpace(rec.roofLocal)
	rec.nPorts = 2
	local points = piv.camoPoints
	local n = math.min(#points, maxCheckpoints)
	if n <= 0 then
		rec.cps[1] = Vector3.new(rec.cx, rec.cy, rec.cz)
		n = 1
	else
		for i = 1, n do
			rec.cps[i] = cf:PointToWorldSpace(points[i])
		end
	end
	rec.nCps = n
end

--------------------------------------------------------------------------------
-- Membership
--------------------------------------------------------------------------------

local function removeVehicle(self: SpottingSystem, rec: VehicleRec, now: number)
	for _, team in self._teamOrder do
		if team.visible[rec.id] then
			team.visible[rec.id] = nil
			if rec.alive then
				emit(self, "Lost", now, team.id, rec.id, nil, false, rec.src.cframe.Position)
			end
		end
		team.markers[rec.id] = nil
	end
	self._byId[rec.id] = nil
end

local function rebuild(self: SpottingSystem, now: number)
	local order = self._order
	table.clear(order)
	for _, rec in self._byId do
		table.insert(order, rec)
	end
	table.sort(order, byRecId)
	local teamsAdded = false
	for _, rec in order do
		if self._teams[rec.team] == nil then
			local team = newTeamRec(rec.team)
			self._teams[rec.team] = team
			table.insert(self._teamOrder, team)
			teamsAdded = true
		end
		table.clear(rec.asObserver)
		table.clear(rec.asTarget)
	end
	if teamsAdded then
		table.sort(self._teamOrder, byTeamId)
	end
	local oldMap = self._pairMap
	local newMap: { [number]: { [number]: PairRec } } = {}
	local pairs = self._pairs
	table.clear(pairs)
	for _, o in order do
		local oldRow = oldMap[o.id]
		local row: { [number]: PairRec } = {}
		for _, t in order do
			if o.team ~= t.team then
				local pair = if oldRow ~= nil then oldRow[t.id] else nil
				if pair == nil or pair.observer ~= o or pair.target ~= t then
					pair = newPair(o, t, now)
				end
				local p = pair :: PairRec
				row[t.id] = p
				table.insert(pairs, p)
				p.order = #pairs
				table.insert(o.asObserver, p)
				table.insert(t.asTarget, p)
			end
		end
		newMap[o.id] = row
	end
	self._pairMap = newMap
end

local function syncMembership(self: SpottingSystem, vehicles: { SpottingVehicle }, now: number)
	self._epoch += 1
	local epoch = self._epoch
	local changed = false
	for i = 1, #vehicles do
		local v = vehicles[i]
		validateRecord(v, i)
		local rec = self._byId[v.id]
		if rec == nil then
			rec = newVehicleRec(v, epoch)
			self._byId[v.id] = rec
			changed = true
		elseif rec.epoch == epoch then
			error(`SpottingSystem.update: duplicate vehicle id {v.id}`, 3)
		elseif rec.team ~= v.team then
			error(`SpottingSystem.update: vehicle {v.id} changed team ({rec.team} -> {v.team})`, 3)
		end
		local r = rec :: VehicleRec
		r.src = v
		r.epoch = epoch
	end
	for _, rec in self._order do
		if rec.epoch ~= epoch then
			removeVehicle(self, rec, now)
			changed = true
		end
	end
	if changed then
		rebuild(self, now)
	end
end

--------------------------------------------------------------------------------
-- Per-vehicle state
--------------------------------------------------------------------------------

local function onDeath(self: SpottingSystem, rec: VehicleRec)
	-- The wreck leaves every visible set silently (VehicleDestroyed tells clients) and is visible to all from now on.
	for _, team in self._teamOrder do
		team.visible[rec.id] = nil
		team.markers[rec.id] = nil
	end
	rec.exposed = false
	rec.exposedSince = nil
	rec.sixthDone = false
	for _, pair in rec.asObserver do
		pair.forced = false
	end
	for _, pair in rec.asTarget do
		pair.forced = false
	end
end

local function refreshVehicles(self: SpottingSystem, C: any, now: number)
	local visibilityMult = self._visibilityMult
	for _, rec in self._order do
		local v = rec.src
		local alive = v.alive == true
		local moving = v.moving == true
		if alive and not rec.alive then
			-- Spawn (first appearance) or revive: earlier sightings of it no longer count.
			if rec.spawned then
				for _, pair in rec.asTarget do
					pair.lastSeen = NEVER
				end
			end
			rec.moving = moving
			rec.stationarySince = nil
			rec.lastShotSeen = shotTime(v)
			rec.exposed = false
			rec.exposedSince = nil
			rec.sixthDone = false
			if C.EVENT_CHECK_ON_SPAWN then
				forcePairs(rec, true)
			end
		elseif not alive and rec.alive then
			onDeath(self, rec)
		end
		rec.spawned = true
		rec.alive = alive

		-- Motion: stationary timer (nets/masts) and the forced check on stop.
		if moving then
			rec.stationarySince = nil
		else
			if rec.stationarySince == nil then
				rec.stationarySince = now
			end
			if rec.moving and alive and C.EVENT_CHECK_ON_STOP then
				forcePairs(rec, true)
			end
		end
		rec.moving = moving

		-- Shots: forced check of every pair where the shooter is the target, after-shot penalties.
		local shot = shotTime(v)
		if shot > rec.lastShotSeen then
			rec.lastShotSeen = shot
			if alive and C.EVENT_CHECK_ON_SHOT then
				forcePairs(rec, false)
			end
		end
		local sinceShot: number? = if rec.lastShotSeen == NEVER then nil else now - rec.lastShotSeen
		rec.firedRecently = VisibilityModel.isShotFoliagePenaltyActive(sinceShot)

		if rec.forcePending then
			rec.forcePending = false
			if alive then
				forcePairs(rec, true)
			end
		end

		-- Hull centre (studs) without allocation: position + UpVector × half the hull height.
		local piv = v.pivots
		ensurePivotConsts(rec, piv)
		local px, py, pz, _, r01, _, _, r11, _, _, r21, _ = v.cframe:GetComponents()
		local h = rec.halfHeight
		local cx, cy, cz = px + r01 * h, py + r11 * h, pz + r21 * h
		rec.cx, rec.cy, rec.cz = cx, cy, cz
		rec.valid = isFinite(cx) and isFinite(cy) and isFinite(cz)
		rec.geomTick = 0

		-- View range and body camo with the conditional modifiers Spotting owns ("Spotted" uses last update).
		local stationaryFor = if rec.stationarySince ~= nil then now - rec.stationarySince else -1
		local armed = VisibilityModel.isStationaryArmed(moving, stationaryFor)
		local mods = v.conditionalModifiers
		local exposed = rec.exposed
		local baseVr = v.viewRangeM
		if mods ~= nil then
			baseVr = VisibilityModel.applyConditional(baseVr, "viewRange", mods, moving, armed, exposed)
		end
		rec.vr = VisibilityModel.effectiveViewRange(baseVr, v.viewRangeMul, v.inSmoke, visibilityMult)
		local camo = v.camo
		local base = if moving then camo.moving else camo.stationary
		if mods ~= nil then
			base = VisibilityModel.applyConditional(
				base,
				if moving then "camoMoving" else "camoStationary",
				mods,
				moving,
				armed,
				exposed
			)
		end
		rec.body = VisibilityModel.composeBodyCamo(
			base,
			camo.afterShotMul,
			camo.paint,
			camo.net,
			armed,
			VisibilityModel.isShotCamoPenaltyActive(sinceShot)
		)
	end
end

--------------------------------------------------------------------------------
-- Pair scheduling and LOS
--------------------------------------------------------------------------------

local function schedulePairs(self: SpottingSystem, C: any, now: number): number
	local prox = C.PROXIMITY_RADIUS_M
	local maxSpot = C.MAX_SPOT_RANGE_M
	local cap = C.CAMO_TOTAL_CAP
	local deferPriority = C.DEFER_PRIORITY_S
	local stats = self._stats
	local due = self._due
	local nDue = 0
	for _, pair in self._pairs do
		local o, t = pair.observer, pair.target
		if not (o.alive and t.alive and o.valid and t.valid) then
			pair.forced = false
			continue
		end
		local dx, dy, dz = t.cx - o.cx, t.cy - o.cy, t.cz - o.cz
		local distM = math.sqrt(dx * dx + dy * dy + dz * dz) / STUDS_PER_M
		pair.distM = distM
		if distM <= prox then
			-- Proximity: spotted through anything, evaluated every update (no ray).
			pair.lastSeen = now
			pair.lastCheck = now
			pair.nextCheck = now
			pair.forced = false
			stats.proximitySpots += 1
			continue
		end
		if not pair.forced and pair.nextCheck > now + TIME_EPS then
			continue
		end
		if distM > maxSpot or distM > VisibilityModel.spotDistance(o.vr, math.min(cap, t.body)) then
			-- Out of reach even with zero foliage (capped camo, research 02-R2 fact-check): no rays.
			pair.lastCheck = now
			pair.forced = false
			schedule(pair, now, distM)
			stats.cheapRejects += 1
			continue
		end
		if pair.forced then
			pair.prioClass = 0
			pair.sortKey = distM
		elseif now - pair.nextCheck >= deferPriority then
			pair.prioClass = 1
			pair.sortKey = pair.nextCheck
		else
			pair.prioClass = 2
			pair.sortKey = distM
		end
		nDue += 1
		due[nDue] = pair
	end
	for i = nDue + 1, #due do
		due[i] = nil
	end
	if nDue > 1 then
		table.sort(due, dueLess)
	end
	return nDue
end

-- Foliage summed along [from, to]: the analytic probe when the World has one, else a counted sightLine.
-- Returns (false, 0) when the ray budget is exhausted.
local function foliageAlong(
	self: SpottingSystem,
	world: World,
	probe: FoliageFn?,
	budget: number,
	from: Vector3,
	to: Vector3
): (boolean, number)
	if probe ~= nil then
		self._probes += 1
		local f = probe(world, from, to)
		-- A broken probe discounts nothing (conservative: the target stays concealed).
		return true, if type(f) == "number" and isFinite(f) then f else 0
	end
	if self._rays >= budget then
		return false, 0
	end
	self._rays += 1
	local f = world:sightLine(from, to).foliage
	return true, if type(f) == "number" and isFinite(f) then f else 0
end

-- 1 = spotted, 0 = not spotted, -1 = aborted (ray budget exhausted; the pair stays due).
local function losCheck(
	self: SpottingSystem,
	C: any,
	world: World,
	probe: FoliageFn?,
	pair: PairRec,
	budget: number
): number
	local o, t = pair.observer, pair.target
	local maxCheckpoints = C.MAX_CHECKPOINTS
	ensureGeometry(self, o, maxCheckpoints)
	ensureGeometry(self, t, maxCheckpoints)
	local vr, body, distM = o.vr, t.body, pair.distM
	local smokeBlocks = C.SMOKE_BLOCKS_LOS == true
	local observerClear = math.max(0, C.FOLIAGE_OBSERVER_CLEAR_M) * STUDS_PER_M
	local shooterClear = if t.firedRecently then math.max(0, C.FOLIAGE_SHOOTER_CLEAR_M) * STUDS_PER_M else 0
	local ports, cps = o.ports, t.cps
	for pi = 1, o.nPorts do
		local port = ports[pi]
		for ci = 1, t.nCps do
			if self._rays >= budget then
				return -1
			end
			local cp = cps[ci]
			self._rays += 1
			local res = world:sightLine(port, cp)
			local foliage = res.foliage
			if res.blocked or (smokeBlocks and res.smoke) or type(foliage) ~= "number" or not isFinite(foliage) then
				continue -- blocked, smoked, or a corrupt result (treated as blocked)
			end
			if distM <= VisibilityModel.spotDistance(vr, VisibilityModel.totalCamo(body, foliage)) then
				return 1
			end
			-- Foliage decides: discount what lies in the 15 m clear zones (they can only lower it).
			local offset = cp - port
			local length = offset.Magnitude
			local nearObserver, nearShooter = 0, 0
			if length <= observerClear + shooterClear then
				-- Every point of the ray lies in a clear zone: no foliage conceals.
				nearObserver = foliage
			else
				local dir = offset / length
				if observerClear > 0 then
					local ok, f = foliageAlong(self, world, probe, budget, port, port + dir * observerClear)
					if not ok then
						return -1
					end
					nearObserver = f
				end
				if shooterClear > 0 then
					local ok, f = foliageAlong(self, world, probe, budget, cp - dir * shooterClear, cp)
					if not ok then
						return -1
					end
					nearShooter = f
				end
			end
			local effective = VisibilityModel.effectiveFoliage(foliage, nearObserver, nearShooter)
			if distM <= VisibilityModel.spotDistance(vr, VisibilityModel.totalCamo(body, effective)) then
				return 1
			end
		end
	end
	return 0
end

local function runChecks(self: SpottingSystem, C: any, world: World, nDue: number, now: number)
	local budget = C.MAX_RAYS_PER_TICK
	local probe: FoliageFn? = nil
	local candidate = (world :: any).foliageAlong
	if type(candidate) == "function" then
		probe = candidate
	end
	local stats = self._stats
	local due = self._due
	for i = 1, nDue do
		local pair = due[i]
		if self._rays >= budget then
			stats.pairsDeferred += 1
			continue
		end
		local result = losCheck(self, C, world, probe, pair, budget)
		if result < 0 then
			stats.pairsDeferred += 1
			continue
		end
		stats.pairsChecked += 1
		pair.lastCheck = now
		pair.forced = false
		if result > 0 then
			pair.lastSeen = now
		end
		schedule(pair, now, pair.distM)
	end
end

--------------------------------------------------------------------------------
-- Team visibility, markers, Sixth Sense
--------------------------------------------------------------------------------

local function updateTeams(self: SpottingSystem, C: any, now: number)
	local linger = C.SPOT_LINGER_S
	local keepDead = C.DEAD_SPOTTER_KEEPS_LINGER == true
	local markerLife = C.LAST_KNOWN_MARKER_S
	local teams = self._teams
	for _, team in self._teamOrder do
		table.clear(team.bestSeen)
		table.clear(team.bestSpotter)
	end
	-- Best (latest) sighting per (team, target); pairs iterate by observer id, so the lowest id wins ties.
	for _, pair in self._pairs do
		local seen = pair.lastSeen
		if seen == NEVER then
			continue
		end
		local o, t = pair.observer, pair.target
		if not t.alive or (not o.alive and not keepDead) then
			continue
		end
		local team = teams[o.team]
		local current = team.bestSeen[t.id]
		if current == nil or seen > current then
			team.bestSeen[t.id] = seen
			team.bestSpotter[t.id] = o.id
		end
	end
	for _, team in self._teamOrder do
		local list = team.list
		local n = 0
		for _, t in self._order do
			if t.team == team.id or not t.alive then
				continue
			end
			local best = team.bestSeen[t.id]
			local visible = best ~= nil and now - best <= linger + TIME_EPS
			local was = team.visible[t.id] == true
			if visible then
				n += 1
				list[n] = t.id
				if not was then
					team.visible[t.id] = true
					local first = team.ever[t.id] ~= true
					team.ever[t.id] = true
					team.markers[t.id] = nil
					emit(self, "Spotted", now, team.id, t.id, team.bestSpotter[t.id], first, nil)
				end
			elseif was then
				team.visible[t.id] = nil
				local position = t.src.cframe.Position
				local marker = team.markers[t.id]
				if marker == nil then
					team.markers[t.id] = { position = position, at = now }
				else
					marker.position = position
					marker.at = now
				end
				emit(self, "Lost", now, team.id, t.id, nil, false, position)
			end
		end
		for i = n + 1, #list do
			list[i] = nil
		end
		for id, marker in team.markers do
			if now - marker.at > markerLife + TIME_EPS then
				team.markers[id] = nil
			end
		end
	end
end

local function updateSixthSense(self: SpottingSystem, C: any, now: number)
	local delay = C.SIXTH_SENSE_DELAY_S
	for _, t in self._order do
		if not t.alive then
			continue
		end
		local exposed = false
		for _, team in self._teamOrder do
			if team.id ~= t.team and team.visible[t.id] then
				exposed = true
				break
			end
		end
		t.exposed = exposed
		if exposed then
			local since = t.exposedSince
			if since == nil then
				since = now
				t.exposedSince = now
				t.sixthDone = false
			end
			if not t.sixthDone and now - (since :: number) >= delay - TIME_EPS and t.src.sixthSense ~= false then
				t.sixthDone = true
				emit(self, "SixthSense", now, t.team, t.id, nil, false, nil)
			end
		else
			t.exposedSince = nil
			t.sixthDone = false
		end
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- A spotting state for one battle. Raises if Config.Spotting.SIGNAL_RELAY_ENABLED (relay is not implemented).
function SpottingSystem.new(options: SpottingOptions?): SpottingSystem
	local C = Config.Spotting
	if C.SIGNAL_RELAY_ENABLED then
		error("SpottingSystem.new: SIGNAL_RELAY_ENABLED (relay chains) is not implemented in v1", 2)
	end
	local mult = C.VISIBILITY_MULT_DEFAULT
	if options ~= nil and options.visibilityMult ~= nil then
		local m = options.visibilityMult
		if type(m) ~= "number" or not isFinite(m) or m < 0 then
			error("SpottingSystem.new: visibilityMult must be a finite number >= 0", 2)
		end
		mult = m
	end
	local data: SystemData = {
		_byId = {},
		_order = {},
		_pairs = {},
		_pairMap = {},
		_teams = {},
		_teamOrder = {},
		_due = {},
		_events = {},
		_pool = {},
		_eventCount = 0,
		_epoch = 0,
		_tick = 0,
		_now = NEVER,
		_rays = 0,
		_probes = 0,
		_stats = {
			tick = 0,
			now = 0,
			rays = 0,
			foliageProbes = 0,
			peakRays = 0,
			pairs = 0,
			pairsDue = 0,
			pairsChecked = 0,
			pairsDeferred = 0,
			proximitySpots = 0,
			cheapRejects = 0,
		},
		_visibilityMult = mult,
	}
	return setmetatable(data, SpottingSystemClass)
end

--- Advances spotting to battle time `now` (s) for the given vehicles (every vehicle of the battle, alive or wreck;
--- a vehicle missing from the list is removed and lost by every team). Returns the reused event buffer: Spotted /
--- Lost per (team, target) in id order, then SixthSense in target id order. Records are recycled next update.
function SpottingSystemClass.update(
	self: SpottingSystem,
	now: number,
	vehicles: { SpottingVehicle },
	world: World
): { SpottingEvent }
	if type(now) ~= "number" or not isFinite(now) then
		error("SpottingSystem:update: now must be a finite number", 2)
	end
	if now < self._now - TIME_EPS then
		error(`SpottingSystem:update: time went backwards ({self._now} -> {now})`, 2)
	end
	if type(vehicles) ~= "table" then
		error("SpottingSystem:update: vehicles must be an array", 2)
	end
	local C = Config.Spotting
	self._tick += 1
	self._now = now
	self._rays = 0
	self._probes = 0
	self._eventCount = 0
	local stats = self._stats
	stats.proximitySpots = 0
	stats.cheapRejects = 0
	stats.pairsChecked = 0
	stats.pairsDeferred = 0

	syncMembership(self, vehicles, now)
	refreshVehicles(self, C, now)
	local nDue = schedulePairs(self, C, now)
	runChecks(self, C, world, nDue, now)
	updateTeams(self, C, now)
	updateSixthSense(self, C, now)

	local events = self._events
	for i = self._eventCount + 1, #events do
		events[i] = nil
	end
	stats.tick = self._tick
	stats.now = now
	stats.rays = self._rays
	stats.foliageProbes = self._probes
	stats.peakRays = math.max(stats.peakRays, self._rays)
	stats.pairs = #self._pairs
	stats.pairsDue = nDue
	return events
end

--- THE replication filter: may `team` receive this vehicle's state? Allies and wrecks: always. Live enemies: only
--- while team-visible (with linger). Unknown ids: never.
function SpottingSystemClass.isVisibleTo(self: SpottingSystem, team: number, vehicleId: number): boolean
	local rec = self._byId[vehicleId]
	if rec == nil then
		return false
	end
	if rec.team == team or not rec.alive then
		return true
	end
	local teamRec = self._teams[team]
	return teamRec ~= nil and teamRec.visible[vehicleId] == true
end

--- Live enemies currently visible to `team`, ascending ids. Read-only, reused: valid until the next update.
--- (Allies and wrecks are not listed; isVisibleTo reports them visible.)
function SpottingSystemClass.visibleSet(self: SpottingSystem, team: number): { number }
	local teamRec = self._teams[team]
	if teamRec == nil then
		return EMPTY_IDS
	end
	return teamRec.list
end

--- What replication may send about `targetId` to the vehicle `observerId`: allies "Full"; enemies and wrecks
--- "Full" within ENEMY_DRAW_RANGE_M when visible to the observer's team, "Minimap" beyond, else "None".
function SpottingSystemClass.replicationTier(
	self: SpottingSystem,
	observerId: number,
	targetId: number
): ReplicationTier
	local o = self._byId[observerId]
	local t = self._byId[targetId]
	if o == nil or t == nil then
		return "None"
	end
	if o.team == t.team then
		return "Full"
	end
	if not self:isVisibleTo(o.team, targetId) then
		return "None"
	end
	local dx, dy, dz = t.cx - o.cx, t.cy - o.cy, t.cz - o.cz
	local distM = math.sqrt(dx * dx + dy * dy + dz * dz) / STUDS_PER_M
	return VisibilityModel.replicationTier(true, distM)
end

--- True while the vehicle is visible to at least one enemy team (as of the last update).
function SpottingSystemClass.isExposed(self: SpottingSystem, vehicleId: number): boolean
	local rec = self._byId[vehicleId]
	return rec ~= nil and rec.exposed
end

--- Observers (ascending ids, optionally only of `team`) whose last successful check of the target is within
--- ASSIST_WINDOW_S of `now` — the spotting-assist split. Destroyed spotters count if DEAD_SPOTTER_ASSIST_CREDIT.
--- Fills and returns `out` (cleared) or a new array.
function SpottingSystemClass.spottersOf(
	self: SpottingSystem,
	targetId: number,
	now: number,
	team: number?,
	out: { number }?
): { number }
	local result = out or {}
	table.clear(result)
	local rec = self._byId[targetId]
	if rec == nil then
		return result
	end
	local C = Config.Spotting
	local window = C.ASSIST_WINDOW_S
	local creditDead = C.DEAD_SPOTTER_ASSIST_CREDIT == true
	for _, pair in rec.asTarget do
		local o = pair.observer
		local seen = pair.lastSeen
		if
			seen ~= NEVER
			and now - seen <= window + TIME_EPS
			and (team == nil or o.team == team)
			and (o.alive or creditDead)
		then
			table.insert(result, o.id)
		end
	end
	return result
end

--- Battle time of the observer's last successful check of the target (nil = never).
function SpottingSystemClass.lastSeenBy(self: SpottingSystem, observerId: number, targetId: number): number?
	local row = self._pairMap[observerId]
	local pair = if row ~= nil then row[targetId] else nil
	if pair == nil or pair.lastSeen == NEVER then
		return nil
	end
	return pair.lastSeen
end

--- Last-known marker of a lost enemy for `team`: (position in studs, battle time lost) or nil once expired,
--- re-spotted or destroyed.
function SpottingSystemClass.lastKnown(self: SpottingSystem, team: number, vehicleId: number): (Vector3?, number?)
	local teamRec = self._teams[team]
	local marker = if teamRec ~= nil then teamRec.markers[vehicleId] else nil
	if marker == nil then
		return nil, nil
	end
	return marker.position, marker.at
end

--- Ids with an active last-known marker for `team`, ascending. Fills and returns `out` (cleared) or a new array.
function SpottingSystemClass.lastKnownIds(self: SpottingSystem, team: number, out: { number }?): { number }
	local result = out or {}
	table.clear(result)
	local teamRec = self._teams[team]
	if teamRec ~= nil then
		for id in teamRec.markers do
			table.insert(result, id)
		end
		table.sort(result)
	end
	return result
end

--- Effective view range (m) used for the vehicle at the last update (HUD VR circle, REG-MINI-03).
function SpottingSystemClass.viewRangeOf(self: SpottingSystem, vehicleId: number): number?
	local rec = self._byId[vehicleId]
	return if rec ~= nil then rec.vr else nil
end

--- Body camo (0..) used for the vehicle at the last update, before foliage and the total cap.
function SpottingSystemClass.bodyCamoOf(self: SpottingSystem, vehicleId: number): number?
	local rec = self._byId[vehicleId]
	return if rec ~= nil then rec.body else nil
end

--- Forces a check of every pair involving the vehicle at the next update (e.g. a consumable or mode event).
function SpottingSystemClass.forceCheck(self: SpottingSystem, vehicleId: number)
	local rec = self._byId[vehicleId]
	if rec ~= nil then
		rec.forcePending = true
	end
end

--- Sets the per-map-variant view range multiplier (weather/night hook), applied from the next update.
function SpottingSystemClass.setVisibilityMult(self: SpottingSystem, mult: number)
	if type(mult) ~= "number" or not isFinite(mult) or mult < 0 then
		error("SpottingSystem:setVisibilityMult: expected a finite number >= 0", 2)
	end
	self._visibilityMult = mult
end

--- Telemetry of the last update (reused record).
function SpottingSystemClass.stats(self: SpottingSystem): SpottingStats
	return self._stats
end

--- Debug / test view of one directed pair (allocates), or nil if the pair does not exist.
function SpottingSystemClass.pairInfo(self: SpottingSystem, observerId: number, targetId: number): PairInfo?
	local row = self._pairMap[observerId]
	local pair = if row ~= nil then row[targetId] else nil
	if pair == nil then
		return nil
	end
	return {
		nextCheck = pair.nextCheck,
		lastCheck = if pair.lastCheck == NEVER then nil else pair.lastCheck,
		lastSeen = if pair.lastSeen == NEVER then nil else pair.lastSeen,
		forced = pair.forced,
		checks = pair.checks,
		distanceM = pair.distM,
	}
end

return SpottingSystem
