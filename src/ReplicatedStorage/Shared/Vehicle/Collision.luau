--!strict
--[[
	Collision — vehicle-vs-vehicle contact geometry and impulses for the server CollisionSystem (ramming,
	pushing, landing on a tank) and client prediction (ARCHITECTURE §6.1 step 2, 00-DECISIONS §2/§6).

	Purpose:          Yaw-oriented box overlap in XZ (separating-axis test on the 4 box axes) plus a vertical
	                  interval test, giving the minimum separation vector (normal from A to B × depth), the relative
	                  closing speed along the normal (m/s, for the ram threshold and damage), an approximate contact
	                  point and the face of each box that is hit (rammer front arc, armor lookup). Also the
	                  momentum-conserving impulse along the normal (restitution <= 1, so kinetic energy never
	                  increases: REG-VEH-04) and the mass-weighted split of the separation.
	Dependencies:     Config (Movement section), Core/Units, Types/VehicleSim, Types/Vehicle, Vehicle/VehicleSim
	                  (body helpers).
	State:            None (pure functions over caller-owned bodies/contacts).
	Validation:       Non-finite inputs never overlap; masses <= 0 or non-finite are treated as immovable (infinite).
	Error handling:   Never throws on finite input.
	Performance notes: test() is allocation-free when given an `out` contact (Vector3 are value types in Roblox);
	                  bodies are reused per vehicle (bodyFromSim(state, stats, out)). Broadphase is the caller's
	                  (bounding circles or the spatial grid of the CollisionSystem).

	Body convention: `position` = hull origin (footprint centre at track-bottom level), `yaw` as VehicleSimState
	(0 = -Z, + clockwise), `size` = (width, height, length) in studs, the box spans [position.Y, position.Y +
	size.Y]. Pitch and roll are ignored (contacts are resolved in the ground plane).
]]

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Units = require("../Core/Units")
local VehicleTypes = require("../Types/Vehicle")
local SimTypes = require("../Types/VehicleSim")
local VehicleSim = require("./VehicleSim")

type VehicleStats = VehicleTypes.VehicleStats
type CollisionBody = SimTypes.CollisionBody
type CollisionContact = SimTypes.CollisionContact
type BoxFace = SimTypes.BoxFace
type VehicleSimState = SimTypes.VehicleSimState

local Collision = {}

local SPM = Units.STUDS_PER_METER
local abs, cos, sin, min, max = math.abs, math.cos, math.sin, math.min, math.max

local function finite(x: number): boolean
	return x == x and x - x == 0
end

local function finiteVector(v: Vector3): boolean
	return finite(v.X) and finite(v.Y) and finite(v.Z)
end

--- A body at the origin with a unit box (fill it per vehicle and reuse it).
function Collision.newBody(): CollisionBody
	return { position = Vector3.zero, yaw = 0, size = Vector3.one, velocity = Vector3.zero }
end

--- An empty contact record (reuse it across tests).
function Collision.newContact(): CollisionContact
	return {
		overlapping = false,
		normal = Vector3.xAxis,
		depth = 0,
		closingSpeedMps = 0,
		contactPoint = Vector3.zero,
		faceA = "Front",
		faceB = "Front",
	}
end

--- Fills `out` (or a new body) from a VehicleSim state: hull origin, heading, collision box, world velocity.
function Collision.bodyFromSim(state: VehicleSimState, stats: VehicleStats, out: CollisionBody?): CollisionBody
	local body = out or Collision.newBody()
	body.position = state.position
	body.yaw = state.yaw
	body.size = VehicleSim.hullSize(state, stats)
	body.velocity = VehicleSim.velocity(state)
	return body
end

-- Face of a box (heading `yaw`) whose outward normal is closest to world direction `n`.
local function faceOf(yaw: number, n: Vector3): BoxFace
	local cy, sy = cos(yaw), sin(yaw)
	local right = n.X * cy + n.Z * sy
	local fwd = n.X * sy - n.Z * cy
	local up = n.Y
	local ar, af, au = abs(right), abs(fwd), abs(up)
	if au >= ar and au >= af then
		return if up >= 0 then "Top" else "Bottom"
	elseif ar > af then
		return if right >= 0 then "Right" else "Left"
	end
	return if fwd >= 0 then "Front" else "Rear"
end

--- Face of a box with heading `yaw` hit from world direction `towardOther` (unit, from the box toward the contact).
Collision.faceOf = faceOf

-- Scratch polygons for footprint clipping (allocation-free; ≤ 8 vertices for two rectangles).
local polyX: { number } = table.create(16, 0)
local polyZ: { number } = table.create(16, 0)
local nextX: { number } = table.create(16, 0)
local nextZ: { number } = table.create(16, 0)

-- Clips the polygon (polyX/polyZ, n vertices) to the half-plane lx·x + lz·z <= d. Returns the new vertex count.
local function clipHalfPlane(n: number, lx: number, lz: number, d: number): number
	local m = 0
	if n == 0 then
		return 0
	end
	local px, pz = polyX[n], polyZ[n]
	local pIn = lx * px + lz * pz <= d
	for i = 1, n do
		local qx, qz = polyX[i], polyZ[i]
		local qIn = lx * qx + lz * qz <= d
		if qIn ~= pIn then
			local dp = lx * px + lz * pz - d
			local dq = lx * qx + lz * qz - d
			local t = dp / (dp - dq)
			m += 1
			nextX[m] = px + (qx - px) * t
			nextZ[m] = pz + (qz - pz) * t
		end
		if qIn then
			m += 1
			nextX[m] = qx
			nextZ[m] = qz
		end
		px, pz, pIn = qx, qz, qIn
	end
	for i = 1, m do
		polyX[i] = nextX[i]
		polyZ[i] = nextZ[i]
	end
	return m
end

-- Vertex average of the intersection of the two footprints (falls back to the midpoint of the centres).
local function footprintIntersectionCentre(
	a: CollisionBody,
	b: CollisionBody,
	arx: number,
	arz: number,
	afx: number,
	afz: number,
	haw: number,
	hal: number,
	brx: number,
	brz: number,
	bfx: number,
	bfz: number,
	hbw: number,
	hbl: number
): (number, number)
	local ax, az = a.position.X, a.position.Z
	local k = 0
	for sx = -1, 1, 2 do
		for sf = -1, 1, 2 do
			k += 1
			local f = if sx > 0 then sf else -sf -- consistent winding
			polyX[k] = ax + arx * haw * sx + afx * hal * f
			polyZ[k] = az + arz * haw * sx + afz * hal * f
		end
	end
	local bx, bz = b.position.X, b.position.Z
	local bR = bx * brx + bz * brz
	local bF = bx * bfx + bz * bfz
	local n = clipHalfPlane(4, brx, brz, bR + hbw)
	n = clipHalfPlane(n, -brx, -brz, -bR + hbw)
	n = clipHalfPlane(n, bfx, bfz, bF + hbl)
	n = clipHalfPlane(n, -bfx, -bfz, -bF + hbl)
	if n == 0 then
		return (ax + bx) / 2, (az + bz) / 2
	end
	local sx, sz = 0, 0
	for i = 1, n do
		sx += polyX[i]
		sz += polyZ[i]
	end
	return sx / n, sz / n
end

local function validBody(b: CollisionBody): boolean
	local s = b.size
	return finiteVector(b.position) and finite(b.yaw) and finiteVector(s) and s.X > 0 and s.Y > 0 and s.Z > 0
end

--- Overlap test between bodies A and B. Fills `out` (or a new contact) and returns (overlapping, contact).
--- The minimum translation that separates them is `normal * depth` applied to B (or its opposite to A).
function Collision.test(a: CollisionBody, b: CollisionBody, out: CollisionContact?): (boolean, CollisionContact)
	local c = out or Collision.newContact()
	c.overlapping = false
	c.depth = 0
	c.closingSpeedMps = 0
	if not (validBody(a) and validBody(b)) then
		return false, c
	end
	-- Vertical intervals.
	local aBottom, bBottom = a.position.Y, b.position.Y
	local aTop, bTop = aBottom + a.size.Y, bBottom + b.size.Y
	local vOverlap = min(aTop, bTop) - max(aBottom, bBottom)
	if vOverlap <= 0 then
		return false, c
	end
	-- Box axes in XZ.
	local ca, sa = cos(a.yaw), sin(a.yaw)
	local cb, sb = cos(b.yaw), sin(b.yaw)
	local arx, arz = ca, sa -- A right
	local afx, afz = sa, -ca -- A forward
	local brx, brz = cb, sb
	local bfx, bfz = sb, -cb
	local haw, hal = a.size.X / 2, a.size.Z / 2
	local hbw, hbl = b.size.X / 2, b.size.Z / 2
	local dx, dz = b.position.X - a.position.X, b.position.Z - a.position.Z
	local best = math.huge
	local nx, nz = 1, 0
	for i = 1, 4 do
		local lx, lz
		if i == 1 then
			lx, lz = arx, arz
		elseif i == 2 then
			lx, lz = afx, afz
		elseif i == 3 then
			lx, lz = brx, brz
		else
			lx, lz = bfx, bfz
		end
		local ra = haw * abs(arx * lx + arz * lz) + hal * abs(afx * lx + afz * lz)
		local rb = hbw * abs(brx * lx + brz * lz) + hbl * abs(bfx * lx + bfz * lz)
		local dist = dx * lx + dz * lz
		local overlap = ra + rb - abs(dist)
		if overlap <= 0 then
			return false, c
		end
		if overlap < best then
			best = overlap
			if dist >= 0 then
				nx, nz = lx, lz
			else
				nx, nz = -lx, -lz
			end
		end
	end
	c.overlapping = true
	local midY = (max(aBottom, bBottom) + min(aTop, bTop)) / 2
	-- Stacked (landing on a tank): one box's bottom above the other's mid-height and the vertical overlap the
	-- shallower one. Boxes side by side always separate horizontally, however deep the overlap.
	local stacked = bBottom >= aBottom + a.size.Y / 2 or aBottom >= bBottom + b.size.Y / 2
	if stacked and vOverlap < best then
		-- Vertical normal from A toward B.
		local up = if (bBottom + bTop) >= (aBottom + aTop) then 1 else -1
		c.normal = Vector3.new(0, up, 0)
		c.depth = vOverlap
		local surface = if up > 0 then aTop else aBottom
		c.contactPoint = Vector3.new((a.position.X + b.position.X) / 2, surface, (a.position.Z + b.position.Z) / 2)
	else
		c.normal = Vector3.new(nx, 0, nz)
		c.depth = best
		-- Contact point: vertex average of the footprints' intersection polygon (inside both), mid overlap height.
		local cx, cz = footprintIntersectionCentre(a, b, arx, arz, afx, afz, haw, hal, brx, brz, bfx, bfz, hbw, hbl)
		c.contactPoint = Vector3.new(cx, midY, cz)
	end
	local n = c.normal
	local rel = a.velocity - b.velocity
	c.closingSpeedMps = if finiteVector(rel) then rel:Dot(n) / SPM else 0
	c.faceA = faceOf(a.yaw, n)
	c.faceB = faceOf(b.yaw, -n)
	return true, c
end

local function inverseMass(m: number): number
	if type(m) ~= "number" or not (m > 0) or not finite(m) then
		return 0
	end
	return 1 / m
end

--- Velocity changes (studs/s) of A and B from an impulse along the unit `normal` (A -> B) when they approach.
--- Masses in any common unit; a mass <= 0 or infinite is immovable. Restitution defaults to
--- Config.Movement.COLLISION_RESTITUTION and is clamped to [0, 1], so momentum is conserved and kinetic energy
--- never increases.
function Collision.resolveVelocities(
	massA: number,
	massB: number,
	velocityA: Vector3,
	velocityB: Vector3,
	normal: Vector3,
	restitution: number?
): (Vector3, Vector3)
	if not (finiteVector(velocityA) and finiteVector(velocityB) and finiteVector(normal)) then
		return Vector3.zero, Vector3.zero
	end
	local vn = (velocityA - velocityB):Dot(normal)
	if vn <= 0 then
		return Vector3.zero, Vector3.zero
	end
	local e: number = Config.Movement.COLLISION_RESTITUTION
	if type(restitution) == "number" and finite(restitution) then
		e = restitution
	end
	e = math.clamp(e, 0, 1)
	local invA, invB = inverseMass(massA), inverseMass(massB)
	local sum = invA + invB
	if sum <= 0 then
		return Vector3.zero, Vector3.zero
	end
	local j = (1 + e) * vn / sum
	return -normal * (j * invA), normal * (j * invB)
end

--- Splits the separation `contact.normal * (contact.depth + skin)` between A and B by inverse mass. Returns the
--- offsets (studs) to apply with VehicleSim.displace.
function Collision.separation(
	massA: number,
	massB: number,
	contact: CollisionContact,
	skin: number?
): (Vector3, Vector3)
	if not contact.overlapping then
		return Vector3.zero, Vector3.zero
	end
	local invA, invB = inverseMass(massA), inverseMass(massB)
	local sum = invA + invB
	if sum <= 0 then
		return Vector3.zero, Vector3.zero
	end
	local total = contact.depth + max(0, skin or 0)
	return -contact.normal * (total * invA / sum), contact.normal * (total * invB / sum)
end

--- Kinetic energy in joules of `massKg` moving at `velocity` studs/s.
function Collision.kineticEnergy(massKg: number, velocity: Vector3): number
	local v = velocity.Magnitude / SPM
	return 0.5 * massKg * v * v
end

return Collision
