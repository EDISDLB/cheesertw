--!strict
--[[
	Combat/ArmorGeometry — analytic ray / sphere queries against a vehicle's ArmorModel (convex volumes of half-space
	faces grouped Hull / Turret / Gun) at a given pose. No Instances, no engine raycasts.

	Purpose:          raycast(): every surface crossing of a world ray with every volume, sorted by distance — the
	                  input of ShotResolver (server shells), the Armor Inspector (client) and bots. Also: the pose
	                  transform (groupFrames), point-in-volume, volumes near a point (HE spall / splash), nearest
	                  main armor (splash T_min), impact angle / effective thickness helpers, model validation and
	                  a reusable watertightness probe (REG-ARM-01).
	Dependencies:     Types/Vehicle, Types/Combat (types), Core/RNG (probe only, type), Config (Combat.EFFECTIVE_COS_FLOOR).
	State:            Weak-keyed cache: ArmorModel -> compiled flat number arrays (face planes, bounding spheres).
	                  Models are treated as immutable; call ArmorGeometry.invalidate(model) after mutating one.
	Validation:       Non-finite or zero-length rays return no crossings; validate(model) lists contract violations
	                  (unit normals, finite planes, >= 4 faces, unique ids, kinds/groups, module/crew tags).
	Error handling:   Never throws on bad numeric input (NaN in -> no hits). validate() returns problems as strings.
	Performance notes: The inner loop (bounding sphere + face clipping) runs on cached plain numbers: no table or
	                  userdata allocation per face or per volume. Per query: 1–3 CFrame compositions (turret / gun
	                  only when the whole-model sphere is hit) and one pooled Crossing record per crossing
	                  (CrossingBuffer grows once, then reuses its records). Results are insertion-sorted (n is small).

	Conventions: rays and points are WORLD studs; volumes live in their group's local space (Types/Vehicle):
	  Hull   = pose.hullCFrame
	  Turret = Hull * pivots.turretRing * Ry(−turretYaw)
	  Gun    = Turret * pivots.gunTrunnion * Ry(−gunYaw) * Rx(gunElevation)
	A face with outward normal n and offset d bounds the half-space n·p <= d. A ray enters a volume through the face
	that maximises the entering parameter and leaves through the one that minimises the exit parameter.
	Ties at (nearly) equal distance are ordered by rank so walkers see outer layers first and never "leave" the body
	at a face shared by two adjoining Armor volumes:
	  0 Spaced/Layered exit · 1 Spaced/Layered entry · 2 Armor entry · 3 Armor exit · 4 Module/Crew entry · 5 exit
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local VehicleTypes = require("@game/ReplicatedStorage/Shared/Types/Vehicle")
local CombatTypes = require("@game/ReplicatedStorage/Shared/Types/Combat")
local RNGModule = require("@game/ReplicatedStorage/Shared/Core/RNG")

type ArmorModel = VehicleTypes.ArmorModel
type ArmorVolume = VehicleTypes.ArmorVolume
type ArmorFace = VehicleTypes.ArmorFace
type ArmorVolumeKind = VehicleTypes.ArmorVolumeKind
type VehiclePose = CombatTypes.VehiclePose
type GroupFrames = CombatTypes.GroupFrames
type Crossing = CombatTypes.Crossing
type CrossingBuffer = CombatTypes.CrossingBuffer
type NearVolume = CombatTypes.NearVolume
type NearBuffer = CombatTypes.NearBuffer
type RNG = RNGModule.RNG

local ArmorGeometry = {}

local GROUP_INDEX: { [string]: number } = { Hull = 1, Turret = 2, Gun = 3 }
local VALID_KINDS: { [string]: boolean } = { Armor = true, Layered = true, Spaced = true, Module = true, Crew = true }
local ENTER_RANK: { [string]: number } = { Spaced = 1, Layered = 1, Armor = 2, Module = 4, Crew = 4 }
local EXIT_RANK: { [string]: number } = { Spaced = 0, Layered = 0, Armor = 3, Module = 5, Crew = 5 }

--- Distances closer than this (studs) are "equal" for ordering purposes.
local TIE_EPS = 1e-4
--- Denominators smaller than this mean the ray is parallel to the face plane.
local PARALLEL_EPS = 1e-12
--- Slack added to bounding-sphere radii (studs) so floating error never culls a grazing hit.
local SPHERE_SLACK = 1e-6

-- Compiled, allocation-free view of one ArmorModel.
type Compiled = {
	n: number,
	volumes: { ArmorVolume },
	vGroup: { number },
	vStart: { number },
	vCount: { number },
	vcx: { number },
	vcy: { number },
	vcz: { number },
	vr: { number },
	vEnterRank: { number },
	vExitRank: { number },
	fnx: { number },
	fny: { number },
	fnz: { number },
	fd: { number },
	hasTurret: boolean,
	hasGun: boolean,
	bcx: number,
	bcy: number,
	bcz: number,
	br: number,
}

local cache: { [ArmorModel]: Compiled } = setmetatable({}, { __mode = "k" }) :: any

local function compile(model: ArmorModel): Compiled
	local c: Compiled = {
		n = 0,
		volumes = {},
		vGroup = {},
		vStart = {},
		vCount = {},
		vcx = {},
		vcy = {},
		vcz = {},
		vr = {},
		vEnterRank = {},
		vExitRank = {},
		fnx = {},
		fny = {},
		fnz = {},
		fd = {},
		hasTurret = false,
		hasGun = false,
		bcx = model.boundsCenter.X,
		bcy = model.boundsCenter.Y,
		bcz = model.boundsCenter.Z,
		br = model.boundsRadius,
	}
	local faceCursor = 0
	for i, volume in model.volumes do
		local g = GROUP_INDEX[volume.group] or 1
		c.n = i
		c.volumes[i] = volume
		c.vGroup[i] = g
		if g == 2 then
			c.hasTurret = true
		elseif g == 3 then
			c.hasGun = true
		end
		c.vcx[i] = volume.center.X
		c.vcy[i] = volume.center.Y
		c.vcz[i] = volume.center.Z
		c.vr[i] = volume.radius
		c.vEnterRank[i] = ENTER_RANK[volume.kind] or 2
		c.vExitRank[i] = EXIT_RANK[volume.kind] or 3
		c.vStart[i] = faceCursor + 1
		c.vCount[i] = #volume.faces
		for _, face in volume.faces do
			faceCursor += 1
			c.fnx[faceCursor] = face.normal.X
			c.fny[faceCursor] = face.normal.Y
			c.fnz[faceCursor] = face.normal.Z
			c.fd[faceCursor] = face.distance
		end
	end
	if c.hasGun then
		-- The gun hangs off the turret frame even when no Turret volume exists.
		c.hasTurret = true
	end
	return c
end

local function compiled(model: ArmorModel): Compiled
	local c = cache[model]
	if c == nil then
		c = compile(model)
		cache[model] = c
	end
	return c
end

local function isFiniteNumber(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function isFiniteVector(v: Vector3): boolean
	return isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)
end

--- Drops the cached compiled form of `model` (only needed if a model table is mutated after first use).
function ArmorGeometry.invalidate(model: ArmorModel)
	cache[model] = nil
end

--------------------------------------------------------------------------------
-- Pose transforms
--------------------------------------------------------------------------------

local function turretFrame(model: ArmorModel, pose: VehiclePose): CFrame
	return pose.hullCFrame * model.pivots.turretRing * CFrame.Angles(0, -math.rad(pose.turretYawDeg or 0), 0)
end

local function gunFrame(model: ArmorModel, pose: VehiclePose, turret: CFrame): CFrame
	return turret
		* model.pivots.gunTrunnion
		* CFrame.Angles(0, -math.rad(pose.gunYawDeg or 0), 0)
		* CFrame.Angles(math.rad(pose.gunElevationDeg or 0), 0, 0)
end

--- World frames of the Hull, Turret and Gun groups for `pose` (shared with the Armor Inspector and renderer).
function ArmorGeometry.groupFrames(model: ArmorModel, pose: VehiclePose, out: GroupFrames?): GroupFrames
	local turret = turretFrame(model, pose)
	local gun = gunFrame(model, pose, turret)
	if out ~= nil then
		out.Hull = pose.hullCFrame
		out.Turret = turret
		out.Gun = gun
		return out
	end
	return { Hull = pose.hullCFrame, Turret = turret, Gun = gun }
end

--- World frame of one group (by name).
function ArmorGeometry.groupFrame(model: ArmorModel, pose: VehiclePose, group: VehicleTypes.ArmorGroup): CFrame
	if group == "Hull" then
		return pose.hullCFrame
	end
	local turret = turretFrame(model, pose)
	if group == "Turret" then
		return turret
	end
	return gunFrame(model, pose, turret)
end

--- World muzzle frame (−Z = shot direction) for `pose` (pivots.muzzle lives in gun space).
function ArmorGeometry.muzzleFrame(model: ArmorModel, pose: VehiclePose): CFrame
	return gunFrame(model, pose, turretFrame(model, pose)) * model.pivots.muzzle
end

-- Per-query scratch: rotation matrix + position of the three group frames, as plain numbers.
-- Index layout per group g: base = (g − 1) * 12; [base+1..3] = position, [base+4..12] = R00..R22.
local frameScratch: { number } = table.create(36, 0)

local function loadFrame(g: number, cf: CFrame)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local b = (g - 1) * 12
	local f = frameScratch
	f[b + 1], f[b + 2], f[b + 3] = x, y, z
	f[b + 4], f[b + 5], f[b + 6] = r00, r01, r02
	f[b + 7], f[b + 8], f[b + 9] = r10, r11, r12
	f[b + 10], f[b + 11], f[b + 12] = r20, r21, r22
end

-- Local ray per group (origin xyz, direction xyz), plain numbers.
local rayScratch: { number } = table.create(18, 0)

local function localizeRay(g: number, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number)
	local f = frameScratch
	local b = (g - 1) * 12
	local px, py, pz = ox - f[b + 1], oy - f[b + 2], oz - f[b + 3]
	local r00, r01, r02 = f[b + 4], f[b + 5], f[b + 6]
	local r10, r11, r12 = f[b + 7], f[b + 8], f[b + 9]
	local r20, r21, r22 = f[b + 10], f[b + 11], f[b + 12]
	local r = rayScratch
	local k = (g - 1) * 6
	-- local = Rᵀ · v
	r[k + 1] = r00 * px + r10 * py + r20 * pz
	r[k + 2] = r01 * px + r11 * py + r21 * pz
	r[k + 3] = r02 * px + r12 * py + r22 * pz
	r[k + 4] = r00 * dx + r10 * dy + r20 * dz
	r[k + 5] = r01 * dx + r11 * dy + r21 * dz
	r[k + 6] = r02 * dx + r12 * dy + r22 * dz
end

--------------------------------------------------------------------------------
-- Ray queries
--------------------------------------------------------------------------------

--- An empty, reusable crossing buffer.
function ArmorGeometry.newBuffer(): CrossingBuffer
	return { count = 0, items = {} }
end

local function writeCrossing(
	buf: CrossingBuffer,
	c: Compiled,
	v: number,
	faceGlobal: number,
	t: number,
	entering: boolean,
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number
)
	local volume = c.volumes[v]
	local localIndex = faceGlobal - c.vStart[v] + 1
	local face = volume.faces[localIndex]
	local f = frameScratch
	local b = (c.vGroup[v] - 1) * 12
	local nx, ny, nz = c.fnx[faceGlobal], c.fny[faceGlobal], c.fnz[faceGlobal]
	-- world normal = R · n
	local wx = f[b + 4] * nx + f[b + 5] * ny + f[b + 6] * nz
	local wy = f[b + 7] * nx + f[b + 8] * ny + f[b + 9] * nz
	local wz = f[b + 10] * nx + f[b + 11] * ny + f[b + 12] * nz
	local point = Vector3.new(ox + dx * t, oy + dy * t, oz + dz * t)
	local normal = Vector3.new(wx, wy, wz)
	local rank = if entering then c.vEnterRank[v] else c.vExitRank[v]
	local n = buf.count + 1
	local rec = buf.items[n]
	if rec == nil then
		rec = {
			distance = t,
			point = point,
			normal = normal,
			entering = entering,
			thicknessMm = face.thicknessMm,
			zone = face.zone,
			spaced = face.spaced,
			volumeId = volume.id,
			volumeKind = volume.kind,
			group = volume.group,
			module = volume.module,
			crewSlot = volume.crewSlot,
			volume = volume,
			face = face,
			faceIndex = localIndex,
			rank = rank,
		}
		buf.items[n] = rec
	else
		rec.distance = t
		rec.point = point
		rec.normal = normal
		rec.entering = entering
		rec.thicknessMm = face.thicknessMm
		rec.zone = face.zone
		rec.spaced = face.spaced
		rec.volumeId = volume.id
		rec.volumeKind = volume.kind
		rec.group = volume.group
		rec.module = volume.module
		rec.crewSlot = volume.crewSlot
		rec.volume = volume
		rec.face = face
		rec.faceIndex = localIndex
		rec.rank = rank
	end
	buf.count = n
end

local function before(a: Crossing, b: Crossing): boolean
	local da, db = a.distance, b.distance
	if da < db - TIE_EPS then
		return true
	elseif da > db + TIE_EPS then
		return false
	elseif a.rank ~= b.rank then
		return a.rank < b.rank
	elseif a.volumeId ~= b.volumeId then
		return a.volumeId < b.volumeId
	end
	return da < db
end

local function sortBuffer(buf: CrossingBuffer)
	local items = buf.items
	for i = 2, buf.count do
		local rec = items[i]
		local j = i - 1
		while j >= 1 and before(rec, items[j]) do
			items[j + 1] = items[j]
			j -= 1
		end
		items[j + 1] = rec
	end
end

--- All crossings of the ray (world studs) with the model at `pose`, sorted (see header for tie ranks).
--- `direction` may have any non-zero length (it is normalized; distances are studs along the unit ray).
--- Crossings behind the origin or beyond `maxDistance` (default unbounded) are dropped, so a ray starting inside a
--- volume reports only its exit. Returns the buffer (reused when `out` is given) and the crossing count.
function ArmorGeometry.raycast(
	model: ArmorModel,
	pose: VehiclePose,
	origin: Vector3,
	direction: Vector3,
	maxDistance: number?,
	out: CrossingBuffer?
): (CrossingBuffer, number)
	local buf = out or ArmorGeometry.newBuffer()
	buf.count = 0
	local maxT = maxDistance or math.huge
	if not (maxT >= 0) then
		return buf, 0
	end
	local ox, oy, oz = origin.X, origin.Y, origin.Z
	local dx, dy, dz = direction.X, direction.Y, direction.Z
	local mag = math.sqrt(dx * dx + dy * dy + dz * dz)
	if not (mag > 0 and mag < math.huge) or not (isFiniteNumber(ox) and isFiniteNumber(oy) and isFiniteNumber(oz)) then
		return buf, 0
	end
	dx, dy, dz = dx / mag, dy / mag, dz / mag

	local c = compiled(model)
	-- Whole-model broadphase in hull space.
	loadFrame(1, pose.hullCFrame)
	localizeRay(1, ox, oy, oz, dx, dy, dz)
	do
		local r = rayScratch
		local cx, cy, cz = c.bcx - r[1], c.bcy - r[2], c.bcz - r[3]
		local tca = cx * r[4] + cy * r[5] + cz * r[6]
		local d2 = cx * cx + cy * cy + cz * cz - tca * tca
		local rad = c.br + SPHERE_SLACK
		if not (d2 <= rad * rad) or tca + rad < 0 or tca - rad > maxT then
			return buf, 0
		end
	end
	if c.hasTurret then
		local turret = turretFrame(model, pose)
		loadFrame(2, turret)
		localizeRay(2, ox, oy, oz, dx, dy, dz)
		if c.hasGun then
			loadFrame(3, gunFrame(model, pose, turret))
			localizeRay(3, ox, oy, oz, dx, dy, dz)
		end
	end

	local r = rayScratch
	local vGroup, vStart, vCount = c.vGroup, c.vStart, c.vCount
	local vcx, vcy, vcz, vr = c.vcx, c.vcy, c.vcz, c.vr
	local fnx, fny, fnz, fd = c.fnx, c.fny, c.fnz, c.fd
	for v = 1, c.n do
		local k = (vGroup[v] - 1) * 6
		local lox, loy, loz = r[k + 1], r[k + 2], r[k + 3]
		local ldx, ldy, ldz = r[k + 4], r[k + 5], r[k + 6]
		-- Bounding sphere.
		local cx, cy, cz = vcx[v] - lox, vcy[v] - loy, vcz[v] - loz
		local tca = cx * ldx + cy * ldy + cz * ldz
		local d2 = cx * cx + cy * cy + cz * cz - tca * tca
		local rad = vr[v] + SPHERE_SLACK
		if not (d2 <= rad * rad) or tca + rad < 0 or tca - rad > maxT then
			continue
		end
		-- Clip against every face.
		local tEnter, tExit = -math.huge, math.huge
		local enterF, exitF = 0, 0
		local hit = true
		local first = vStart[v]
		for f = first, first + vCount[v] - 1 do
			local nx, ny, nz = fnx[f], fny[f], fnz[f]
			local denom = nx * ldx + ny * ldy + nz * ldz
			local s = fd[f] - (nx * lox + ny * loy + nz * loz)
			if denom < -PARALLEL_EPS then
				local t = s / denom
				if t > tEnter then
					tEnter = t
					enterF = f
				end
			elseif denom > PARALLEL_EPS then
				local t = s / denom
				if t < tExit then
					tExit = t
					exitF = f
				end
			elseif not (s >= 0) then
				hit = false
				break
			end
			if tEnter > tExit then
				hit = false
				break
			end
		end
		if not hit then
			continue
		end
		if enterF ~= 0 and tEnter >= 0 and tEnter <= maxT then
			writeCrossing(buf, c, v, enterF, tEnter, true, ox, oy, oz, dx, dy, dz)
		end
		if exitF ~= 0 and tExit >= 0 and tExit <= maxT then
			writeCrossing(buf, c, v, exitF, tExit, false, ox, oy, oz, dx, dy, dz)
		end
	end
	sortBuffer(buf)
	return buf, buf.count
end

--- First entering crossing of an Armor / Layered / Spaced volume (what a shell strikes first), or nil.
function ArmorGeometry.firstHit(buf: CrossingBuffer): Crossing?
	for i = 1, buf.count do
		local rec = buf.items[i]
		if
			rec.entering and (rec.volumeKind == "Armor" or rec.volumeKind == "Layered" or rec.volumeKind == "Spaced")
		then
			return rec
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Point / sphere queries
--------------------------------------------------------------------------------

--- True when `localPoint` (the volume's group space) satisfies every face (n·p <= d + eps).
function ArmorGeometry.containsPoint(volume: ArmorVolume, localPoint: Vector3, eps: number?): boolean
	local tolerance = eps or 0
	local px, py, pz = localPoint.X, localPoint.Y, localPoint.Z
	for _, face in volume.faces do
		local n = face.normal
		if not (n.X * px + n.Y * py + n.Z * pz <= face.distance + tolerance) then
			return false
		end
	end
	return true
end

local function localPointInGroup(g: number, wx: number, wy: number, wz: number): (number, number, number)
	local f = frameScratch
	local b = (g - 1) * 12
	local px, py, pz = wx - f[b + 1], wy - f[b + 2], wz - f[b + 3]
	return f[b + 4] * px + f[b + 7] * py + f[b + 10] * pz,
		f[b + 5] * px + f[b + 8] * py + f[b + 11] * pz,
		f[b + 6] * px + f[b + 9] * py + f[b + 12] * pz
end

local function loadAllFrames(model: ArmorModel, pose: VehiclePose, c: Compiled)
	loadFrame(1, pose.hullCFrame)
	if c.hasTurret then
		local turret = turretFrame(model, pose)
		loadFrame(2, turret)
		if c.hasGun then
			loadFrame(3, gunFrame(model, pose, turret))
		end
	end
end

-- Largest signed plane distance of a local point over a volume's faces (<= 0 inside; > 0 is a lower bound of the
-- Euclidean distance to the convex volume).
local function maxPlaneDistance(c: Compiled, v: number, px: number, py: number, pz: number): number
	local best = -math.huge
	local first = c.vStart[v]
	local fnx, fny, fnz, fd = c.fnx, c.fny, c.fnz, c.fd
	for f = first, first + c.vCount[v] - 1 do
		local s = fnx[f] * px + fny[f] * py + fnz[f] * pz - fd[f]
		if s > best then
			best = s
		end
	end
	return best
end

-- First volume (model order) of an allowed kind containing the world point; frames must already be loaded.
local function volumeAtLoaded(
	c: Compiled,
	wx: number,
	wy: number,
	wz: number,
	kinds: { [ArmorVolumeKind]: boolean }?
): ArmorVolume?
	for v = 1, c.n do
		local volume = c.volumes[v]
		if kinds == nil or kinds[volume.kind] then
			local px, py, pz = localPointInGroup(c.vGroup[v], wx, wy, wz)
			if maxPlaneDistance(c, v, px, py, pz) <= 0 then
				return volume
			end
		end
	end
	return nil
end

--- The first volume (model order) of an allowed kind containing the world point, or nil.
function ArmorGeometry.volumeAt(
	model: ArmorModel,
	pose: VehiclePose,
	worldPoint: Vector3,
	kinds: { [ArmorVolumeKind]: boolean }?
): ArmorVolume?
	if not isFiniteVector(worldPoint) then
		return nil
	end
	local c = compiled(model)
	loadAllFrames(model, pose, c)
	return volumeAtLoaded(c, worldPoint.X, worldPoint.Y, worldPoint.Z, kinds)
end

--- An empty, reusable near-volume buffer.
function ArmorGeometry.newNearBuffer(): NearBuffer
	return { count = 0, items = {} }
end

--- Volumes of the allowed kinds (default Module + Crew) within `radius` studs of the world point, sorted by distance
--- then id. Distance is the largest face-plane distance (exact for faces, a slight under-estimate near edges and
--- corners: the sphere test is generous by design). Volumes containing the point have distance 0.
function ArmorGeometry.volumesNear(
	model: ArmorModel,
	pose: VehiclePose,
	worldPoint: Vector3,
	radius: number,
	kinds: { [ArmorVolumeKind]: boolean }?,
	out: NearBuffer?
): NearBuffer
	local buf = out or ArmorGeometry.newNearBuffer()
	buf.count = 0
	if not (radius >= 0) or not isFiniteVector(worldPoint) then
		return buf
	end
	local c = compiled(model)
	loadAllFrames(model, pose, c)
	local wx, wy, wz = worldPoint.X, worldPoint.Y, worldPoint.Z
	for v = 1, c.n do
		local volume = c.volumes[v]
		local allowed = if kinds == nil then (volume.kind == "Module" or volume.kind == "Crew") else kinds[volume.kind]
		if not allowed then
			continue
		end
		local px, py, pz = localPointInGroup(c.vGroup[v], wx, wy, wz)
		local cx, cy, cz = px - c.vcx[v], py - c.vcy[v], pz - c.vcz[v]
		local centreDistance = math.sqrt(cx * cx + cy * cy + cz * cz)
		if centreDistance - c.vr[v] > radius + SPHERE_SLACK then
			continue
		end
		local d = math.max(0, maxPlaneDistance(c, v, px, py, pz))
		if d <= radius then
			local n = buf.count + 1
			local rec = buf.items[n]
			if rec == nil then
				buf.items[n] = { volume = volume, distance = d }
			else
				rec.volume = volume
				rec.distance = d
			end
			buf.count = n
		end
	end
	-- insertion sort by (distance, id)
	local items = buf.items
	for i = 2, buf.count do
		local rec = items[i]
		local j = i - 1
		while
			j >= 1
			and (
				rec.distance < items[j].distance
				or (rec.distance == items[j].distance and rec.volume.id < items[j].volume.id)
			)
		do
			items[j + 1] = items[j]
			j -= 1
		end
		items[j + 1] = rec
	end
	return buf
end

--- Nearest main armor (Armor + Layered volumes) to a world point within `radius` studs, for HE splash.
--- Returns (found, distanceStuds, thinnestMm): distance is the smallest volume distance (0 when touching/inside);
--- thinnestMm is the thinnest face that faces the point (point on its outer side) with its plane within `radius`
--- (for a point inside a volume, the closest face). This approximates "T_min of the plates whose surface lies
--- inside R" with plane distances (generous near edges, exact on faces).
function ArmorGeometry.nearestArmor(
	model: ArmorModel,
	pose: VehiclePose,
	worldPoint: Vector3,
	radius: number
): (boolean, number, number)
	if not (radius >= 0) or not isFiniteVector(worldPoint) then
		return false, math.huge, 0
	end
	local c = compiled(model)
	loadAllFrames(model, pose, c)
	local wx, wy, wz = worldPoint.X, worldPoint.Y, worldPoint.Z
	local found = false
	local bestDistance = math.huge
	local thinnest = math.huge
	local fnx, fny, fnz, fd = c.fnx, c.fny, c.fnz, c.fd
	for v = 1, c.n do
		local volume = c.volumes[v]
		if volume.kind ~= "Armor" and volume.kind ~= "Layered" then
			continue
		end
		local px, py, pz = localPointInGroup(c.vGroup[v], wx, wy, wz)
		local cx, cy, cz = px - c.vcx[v], py - c.vcy[v], pz - c.vcz[v]
		if math.sqrt(cx * cx + cy * cy + cz * cz) - c.vr[v] > radius + SPHERE_SLACK then
			continue
		end
		local lowerBound = maxPlaneDistance(c, v, px, py, pz)
		if lowerBound > radius then
			continue
		end
		found = true
		local d = math.max(0, lowerBound)
		if d < bestDistance then
			bestDistance = d
		end
		local first = c.vStart[v]
		local facing = false
		local closestFace, closestS = 0, -math.huge
		for f = first, first + c.vCount[v] - 1 do
			local s = fnx[f] * px + fny[f] * py + fnz[f] * pz - fd[f]
			if s > closestS then
				closestS = s
				closestFace = f
			end
			if s >= -TIE_EPS and s <= radius then
				facing = true
				local t = volume.faces[f - first + 1].thicknessMm
				if t < thinnest then
					thinnest = t
				end
			end
		end
		if not facing and closestFace ~= 0 then
			local t = volume.faces[closestFace - first + 1].thicknessMm
			if t < thinnest then
				thinnest = t
			end
		end
	end
	if not found then
		return false, math.huge, 0
	end
	return true, bestDistance, thinnest
end

--------------------------------------------------------------------------------
-- Angles and thickness
--------------------------------------------------------------------------------

--- Impact angle θ (deg) between the reversed travel direction and the plate's outward normal: 0 = head-on,
--- 90 = grazing. Inputs need not be unit length; degenerate input returns 90.
function ArmorGeometry.impactAngleDeg(direction: Vector3, normal: Vector3): number
	local dm = direction.Magnitude
	local nm = normal.Magnitude
	if not (dm > 0 and nm > 0) or dm == math.huge or nm == math.huge then
		return 90
	end
	local cosine = -(direction:Dot(normal)) / (dm * nm)
	if cosine ~= cosine then
		return 90
	end
	return math.deg(math.acos(math.clamp(cosine, -1, 1)))
end

--- T_eff = T / max(EFFECTIVE_COS_FLOOR, cos(max(0, θ − n))) in mm (n = applied normalization, default 0).
function ArmorGeometry.effectiveThickness(thicknessMm: number, angleDeg: number, normalizationDeg: number?): number
	local floor = Config.Combat.EFFECTIVE_COS_FLOOR
	local theta = math.max(0, angleDeg - (normalizationDeg or 0))
	local cosine = math.cos(math.rad(theta))
	if not (cosine >= floor) then
		cosine = floor
	end
	return thicknessMm / cosine
end

--- Mirror reflection of a direction about a unit normal: d − 2 (d·n) n.
function ArmorGeometry.reflect(direction: Vector3, normal: Vector3): Vector3
	return direction - normal * (2 * direction:Dot(normal))
end

--------------------------------------------------------------------------------
-- Model validation and the watertightness probe
--------------------------------------------------------------------------------

--- Contract problems of a model (empty list = valid). Checks: unique ids, known groups/kinds, >= 4 faces, unit and
--- finite normals, finite offsets and thickness >= 0, positive finite bounding spheres, Module volumes tagged with
--- a module, Crew volumes with a crew slot, face.spaced mirroring kind == "Spaced", finite pivots.
function ArmorGeometry.validate(model: ArmorModel): { string }
	local problems: { string } = {}
	local seen: { [number]: boolean } = {}
	if
		not (model.boundsRadius > 0 and isFiniteNumber(model.boundsRadius)) or not isFiniteVector(model.boundsCenter)
	then
		table.insert(problems, "model: bounds sphere must be finite with a positive radius")
	end
	for i, volume in model.volumes do
		local label = `volume[{i}] id={tostring(volume.id)}`
		if seen[volume.id] then
			table.insert(problems, `{label}: duplicate id`)
		end
		seen[volume.id] = true
		if GROUP_INDEX[volume.group] == nil then
			table.insert(problems, `{label}: unknown group {tostring(volume.group)}`)
		end
		if not VALID_KINDS[volume.kind] then
			table.insert(problems, `{label}: unknown kind {tostring(volume.kind)}`)
		end
		if #volume.faces < 4 then
			table.insert(problems, `{label}: needs >= 4 faces, has {#volume.faces}`)
		end
		if not (volume.radius > 0 and isFiniteNumber(volume.radius)) or not isFiniteVector(volume.center) then
			table.insert(problems, `{label}: bounding sphere must be finite with a positive radius`)
		end
		if volume.kind == "Module" and volume.module == nil then
			table.insert(problems, `{label}: Module volume without a module kind`)
		end
		if volume.kind == "Crew" and volume.crewSlot == nil then
			table.insert(problems, `{label}: Crew volume without a crew slot`)
		end
		for j, face in volume.faces do
			local n = face.normal
			if not isFiniteVector(n) or math.abs(n.Magnitude - 1) > 1e-3 then
				table.insert(problems, `{label} face[{j}]: normal must be finite and unit length`)
			end
			if not isFiniteNumber(face.distance) then
				table.insert(problems, `{label} face[{j}]: plane offset must be finite`)
			end
			if not (face.thicknessMm >= 0 and isFiniteNumber(face.thicknessMm)) then
				table.insert(problems, `{label} face[{j}]: thickness must be finite and >= 0`)
			end
			if face.spaced ~= (volume.kind == "Spaced") then
				table.insert(problems, `{label} face[{j}]: spaced flag must mirror kind == "Spaced"`)
			end
		end
	end
	return problems
end

export type LeakReport = {
	rays: number,
	leaks: number,
	firstLeaks: { { origin: Vector3, target: Vector3 } }, -- up to 10 examples
}

local DEFAULT_ARMOR_KINDS: { [ArmorVolumeKind]: boolean } = { Armor = true }

--- Uniform random point inside the union of Armor volumes (rejection sampling in the bounds sphere), or nil.
function ArmorGeometry.sampleInteriorPoint(model: ArmorModel, pose: VehiclePose, rng: RNG, maxTries: number?): Vector3?
	local c = compiled(model)
	loadAllFrames(model, pose, c)
	local centre = pose.hullCFrame:PointToWorldSpace(model.boundsCenter)
	local cx, cy, cz = centre.X, centre.Y, centre.Z
	local radius = model.boundsRadius
	for _ = 1, maxTries or 4000 do
		local x, y, z = rng:range(-1, 1), rng:range(-1, 1), rng:range(-1, 1)
		if x * x + y * y + z * z <= 1 then
			local wx, wy, wz = cx + x * radius, cy + y * radius, cz + z * radius
			if volumeAtLoaded(c, wx, wy, wz, DEFAULT_ARMOR_KINDS) ~= nil then
				return Vector3.new(wx, wy, wz)
			end
		end
	end
	return nil
end

--- REG-ARM-01 probe: fires `rays` seeded rays from random points outside the bounds sphere at random target points
--- (default: uniform inside the Armor union; or `sampler(rng)` returning world points on the visual surface) and
--- counts leaks = rays that reach their target without entering an Armor volume first.
function ArmorGeometry.probeLeaks(
	model: ArmorModel,
	pose: VehiclePose,
	rng: RNG,
	rays: number,
	sampler: ((RNG) -> Vector3?)?
): LeakReport
	local report: LeakReport = { rays = 0, leaks = 0, firstLeaks = {} }
	local centre = pose.hullCFrame:PointToWorldSpace(model.boundsCenter)
	local shell = model.boundsRadius * 2 + 10
	local buf = ArmorGeometry.newBuffer()
	for _ = 1, rays do
		local target = if sampler ~= nil then sampler(rng) else ArmorGeometry.sampleInteriorPoint(model, pose, rng)
		if target == nil then
			continue
		end
		-- Uniform direction on the sphere (normal deviates, normalized).
		local dir = Vector3.new(rng:normal(0, 1), rng:normal(0, 1), rng:normal(0, 1))
		if dir.Magnitude < 1e-9 then
			dir = Vector3.new(0, 1, 0)
		end
		local origin = centre + dir.Unit * shell
		local toTarget = target - origin
		local length = toTarget.Magnitude
		report.rays += 1
		local _, count = ArmorGeometry.raycast(model, pose, origin, toTarget, length + 1e-6, buf)
		local entered = false
		for i = 1, count do
			local rec = buf.items[i]
			if rec.entering and rec.volumeKind == "Armor" then
				entered = true
				break
			end
		end
		if not entered then
			report.leaks += 1
			if #report.firstLeaks < 10 then
				table.insert(report.firstLeaks, { origin = origin, target = target })
			end
		end
	end
	return report
end

return ArmorGeometry
