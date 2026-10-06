--!strict
--[[
	Vehicle/Blueprint/Geometry — convex-polyhedron kernel of the Blueprint: half-space planes with armor zones,
	vertex enumeration, pruning, containment, horizontal cross-sections, ray entry and surface sampling.

	Purpose:          Every armor body the Blueprint builds is the intersection of half-spaces n·p <= d (the exact
	                  ArmorFace contract of Types/Vehicle). This module turns plane lists into vertices, bounding
	                  spheres and plan-view sections (for the visual decomposition), answers point/ray queries used
	                  to place parts on surfaces, and samples face points for the parity tests.
	Dependencies:     Types/Content (ArmorZone), Core/RNG (type only, sampling).
	State:            None.
	Validation:       Callers pass finite numbers; degenerate inputs (parallel planes, empty bodies) yield empty
	                  results rather than errors.
	Error handling:   Never throws; empty vertex lists / nil hits signal degenerate geometry.
	Performance notes: Build-time only. Vertex enumeration is O(F^3 · F) with F <= ~16 faces per body. Arithmetic
	                  runs on float64 numbers; Vector3 (float32) is produced only at the end, and plane offsets
	                  are computed from the float32-rounded normal so ArmorGeometry sees the same plane.
]]

local Content = require("../../Types/Content")
local RNGModule = require("../../Core/RNG")

type ArmorZone = Content.ArmorZone
type RNG = RNGModule.RNG

export type Plane = {
	normal: Vector3, -- outward unit normal
	distance: number, -- n·p = distance on the plane; inside n·p <= distance
	zone: ArmorZone,
	thicknessMm: number,
	open: boolean?, -- open-top face: no plate (0 mm) and no visual
}

--- Plan-view (x, z) polygon vertex; `edge` = index of the plane that bounds the edge from this vertex to the next
--- one (0 = the initial bounding square). Polygons are convex and wound consistently.
export type PlanPoint = { x: number, z: number, edge: number }
export type Poly = { PlanPoint }

local Geometry = {}

local BIG = 1e4

--- Plane with outward normal (nx, ny, nz) (any length) through the point (px, py, pz).
function Geometry.plane(
	nx: number,
	ny: number,
	nz: number,
	px: number,
	py: number,
	pz: number,
	zone: ArmorZone,
	thicknessMm: number,
	open: boolean?
): Plane
	local m = math.sqrt(nx * nx + ny * ny + nz * nz)
	local n = Vector3.new(nx / m, ny / m, nz / m)
	return {
		normal = n,
		distance = n.X * px + n.Y * py + n.Z * pz,
		zone = zone,
		thicknessMm = thicknessMm,
		open = open,
	}
end

--- Copy of `p` with another zone / thickness (same plane).
function Geometry.retag(p: Plane, zone: ArmorZone, thicknessMm: number, open: boolean?): Plane
	return { normal = p.normal, distance = p.distance, zone = zone, thicknessMm = thicknessMm, open = open }
end

--- The same plane facing the other way (the far side of a split), with its own zone / thickness.
function Geometry.flip(p: Plane, zone: ArmorZone, thicknessMm: number): Plane
	return { normal = -p.normal, distance = -p.distance, zone = zone, thicknessMm = thicknessMm }
end

--- Max over planes of n·p − d (<= 0 inside; > 0 outside by at most that much along the worst face).
function Geometry.signedDistance(planes: { Plane }, x: number, y: number, z: number): number
	local worst = -math.huge
	for _, p in planes do
		local n = p.normal
		local s = n.X * x + n.Y * y + n.Z * z - p.distance
		if s > worst then
			worst = s
		end
	end
	return worst
end

--- True when (x, y, z) is inside every plane by at least `margin` (negative margin = tolerance outside).
function Geometry.contains(planes: { Plane }, point: Vector3, margin: number?): boolean
	return Geometry.signedDistance(planes, point.X, point.Y, point.Z) <= -(margin or 0)
end

--- Vertices of the convex polyhedron (triple-plane intersections inside every plane), deduplicated.
function Geometry.vertices(planes: { Plane }, eps: number?): { Vector3 }
	local e = eps or 1e-5
	local n = #planes
	local px: { number }, py: { number }, pz: { number } = {}, {}, {}
	for i = 1, n - 2 do
		local a = planes[i]
		local ax, ay, az, ad = a.normal.X, a.normal.Y, a.normal.Z, a.distance
		for j = i + 1, n - 1 do
			local b = planes[j]
			local bx, by, bz, bd = b.normal.X, b.normal.Y, b.normal.Z, b.distance
			local abx, aby, abz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
			for k = j + 1, n do
				local c = planes[k]
				local cx, cy, cz, cd = c.normal.X, c.normal.Y, c.normal.Z, c.distance
				local det = cx * abx + cy * aby + cz * abz -- = a·(b×c)
				if math.abs(det) < 1e-9 then
					continue
				end
				local bcx, bcy, bcz = by * cz - bz * cy, bz * cx - bx * cz, bx * cy - by * cx
				local cax, cay, caz = cy * az - cz * ay, cz * ax - cx * az, cx * ay - cy * ax
				local x = (ad * bcx + bd * cax + cd * abx) / det
				local y = (ad * bcy + bd * cay + cd * aby) / det
				local z = (ad * bcz + bd * caz + cd * abz) / det
				if Geometry.signedDistance(planes, x, y, z) > e then
					continue
				end
				local dup = false
				for v = 1, #px do
					if math.abs(px[v] - x) < e and math.abs(py[v] - y) < e and math.abs(pz[v] - z) < e then
						dup = true
						break
					end
				end
				if not dup then
					table.insert(px, x)
					table.insert(py, y)
					table.insert(pz, z)
				end
			end
		end
	end
	local out = table.create(#px)
	for v = 1, #px do
		out[v] = Vector3.new(px[v], py[v], pz[v])
	end
	return out
end

--- Drops duplicate planes (keeping the first) and planes that touch fewer than 3 vertices (redundant half-spaces).
--- Returns the pruned planes and the vertices.
function Geometry.prune(planes: { Plane }, eps: number?): ({ Plane }, { Vector3 })
	local e = eps or 1e-4
	local unique: { Plane } = {}
	for _, p in planes do
		local dup = false
		for _, q in unique do
			if p.normal:Dot(q.normal) > 1 - 1e-7 and math.abs(p.distance - q.distance) < e then
				dup = true
				break
			end
		end
		if not dup then
			table.insert(unique, p)
		end
	end
	local verts = Geometry.vertices(unique)
	local kept: { Plane } = {}
	for _, p in unique do
		local count = 0
		for _, v in verts do
			if math.abs(p.normal:Dot(v) - p.distance) <= e then
				count += 1
			end
		end
		if count >= 3 then
			table.insert(kept, p)
		end
	end
	return kept, verts
end

--- Axis-aligned bounds of a point list.
function Geometry.bounds(points: { Vector3 }): (Vector3, Vector3)
	local x0, y0, z0 = math.huge, math.huge, math.huge
	local x1, y1, z1 = -math.huge, -math.huge, -math.huge
	for _, p in points do
		x0, y0, z0 = math.min(x0, p.X), math.min(y0, p.Y), math.min(z0, p.Z)
		x1, y1, z1 = math.max(x1, p.X), math.max(y1, p.Y), math.max(z1, p.Z)
	end
	return Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
end

--- Bounding sphere (AABB centre, farthest point) with a small slack.
function Geometry.sphere(points: { Vector3 }): (Vector3, number)
	local mn, mx = Geometry.bounds(points)
	local c = (mn + mx) / 2
	local r = 0
	for _, p in points do
		r = math.max(r, (p - c).Magnitude)
	end
	return c, r + 1e-3
end

--- Centroid of a point list (average).
function Geometry.centroid(points: { Vector3 }): Vector3
	local s = Vector3.zero
	for _, p in points do
		s += p
	end
	return if #points > 0 then s / #points else s
end

--- Planes moved by a rigid frame (local -> parent): n' = R n, d' = d + n'·t.
function Geometry.transform(planes: { Plane }, cf: CFrame): { Plane }
	local out = table.create(#planes)
	local t = cf.Position
	for i, p in planes do
		local n = cf:VectorToWorldSpace(p.normal)
		n = n.Unit
		out[i] = {
			normal = n,
			distance = p.distance + n.X * t.X + n.Y * t.Y + n.Z * t.Z,
			zone = p.zone,
			thicknessMm = p.thicknessMm,
			open = p.open,
		}
	end
	return out
end

--------------------------------------------------------------------------------
-- Plan-view sections
--------------------------------------------------------------------------------

local function clip(poly: Poly, a: number, b: number, c: number, tag: number): Poly
	-- keeps a·x + b·z <= c
	local out: Poly = {}
	local n = #poly
	if n == 0 then
		return out
	end
	local eps = 1e-9
	for i = 1, n do
		local cur = poly[i]
		local nxt = poly[i % n + 1]
		local fc = a * cur.x + b * cur.z - c
		local fn = a * nxt.x + b * nxt.z - c
		if fc <= eps then
			table.insert(out, { x = cur.x, z = cur.z, edge = cur.edge })
			if fn > eps then
				local t = fc / (fc - fn)
				table.insert(out, { x = cur.x + (nxt.x - cur.x) * t, z = cur.z + (nxt.z - cur.z) * t, edge = tag })
			end
		elseif fn <= eps then
			local t = fc / (fc - fn)
			table.insert(out, { x = cur.x + (nxt.x - cur.x) * t, z = cur.z + (nxt.z - cur.z) * t, edge = cur.edge })
		end
	end
	-- merge coincident neighbours (keep the later outgoing edge: the zero-length edge carries no boundary)
	local merged: Poly = {}
	for _, p in out do
		local last = merged[#merged]
		if last ~= nil and math.abs(last.x - p.x) < 1e-7 and math.abs(last.z - p.z) < 1e-7 then
			last.edge = p.edge
		else
			table.insert(merged, p)
		end
	end
	if #merged >= 2 then
		local first, last = merged[1], merged[#merged]
		if math.abs(first.x - last.x) < 1e-7 and math.abs(first.z - last.z) < 1e-7 then
			table.remove(merged)
		end
	end
	if #merged < 3 then
		return {}
	end
	return merged
end

--- Horizontal cross-section(s): the plan polygon of points (x, z) inside every plane at EVERY height in `heights`
--- (one height = the section at that level; two = the intersection of both sections, the "core" of a slab).
function Geometry.section(planes: { Plane }, heights: { number }): Poly
	local poly: Poly = {
		{ x = -BIG, z = -BIG, edge = 0 },
		{ x = BIG, z = -BIG, edge = 0 },
		{ x = BIG, z = BIG, edge = 0 },
		{ x = -BIG, z = BIG, edge = 0 },
	}
	for i, p in planes do
		local n = p.normal
		local h = math.abs(n.X) + math.abs(n.Z)
		for _, y in heights do
			if h < 1e-9 then
				if n.Y * y > p.distance + 1e-6 then
					return {}
				end
			else
				poly = clip(poly, n.X, n.Z, p.distance - n.Y * y, i)
				if #poly == 0 then
					return poly
				end
			end
		end
	end
	return poly
end

--- Signed area of a plan polygon (x, z).
function Geometry.polyArea(poly: Poly): number
	local a = 0
	local n = #poly
	for i = 1, n do
		local p, q = poly[i], poly[i % n + 1]
		a += p.x * q.z - q.x * p.z
	end
	return a / 2
end

--- z-interval [lo, hi] of a convex plan polygon along the line x = c (nil when the line misses it).
function Geometry.spanAtX(poly: Poly, c: number): (number?, number?)
	local lo, hi = math.huge, -math.huge
	local n = #poly
	for i = 1, n do
		local p, q = poly[i], poly[i % n + 1]
		local x0, x1 = math.min(p.x, q.x), math.max(p.x, q.x)
		if c >= x0 - 1e-9 and c <= x1 + 1e-9 then
			if math.abs(q.x - p.x) < 1e-12 then
				lo, hi = math.min(lo, p.z, q.z), math.max(hi, p.z, q.z)
			else
				local t = math.clamp((c - p.x) / (q.x - p.x), 0, 1)
				local z = p.z + (q.z - p.z) * t
				lo, hi = math.min(lo, z), math.max(hi, z)
			end
		end
	end
	if lo > hi then
		return nil, nil
	end
	return lo, hi
end

--------------------------------------------------------------------------------
-- Rays and surfaces
--------------------------------------------------------------------------------

--- Slab clip of the ray o + t·d against the body: entering / exiting parameters and the entering plane index.
--- Returns nil when the ray misses (or the body is empty along it).
function Geometry.rayClip(planes: { Plane }, origin: Vector3, direction: Vector3): (number?, number?, number?)
	local tIn, tOut, enter = -math.huge, math.huge, 0
	local ox, oy, oz = origin.X, origin.Y, origin.Z
	local dx, dy, dz = direction.X, direction.Y, direction.Z
	for i, p in planes do
		local n = p.normal
		local denom = n.X * dx + n.Y * dy + n.Z * dz
		local num = p.distance - (n.X * ox + n.Y * oy + n.Z * oz)
		if math.abs(denom) < 1e-12 then
			if num < 0 then
				return nil, nil, nil
			end
		else
			local t = num / denom
			if denom < 0 then
				if t > tIn then
					tIn, enter = t, i
				end
			elseif t < tOut then
				tOut = t
			end
		end
	end
	if tIn > tOut then
		return nil, nil, nil
	end
	return tIn, tOut, enter
end

--- Highest point of the body on the vertical line (x, z) (nil if the line misses).
function Geometry.topAt(planes: { Plane }, x: number, z: number): number?
	local tIn = Geometry.rayClip(planes, Vector3.new(x, BIG, z), Vector3.new(0, -1, 0))
	if tIn == nil then
		return nil
	end
	return BIG - tIn
end

--- Vertices lying on plane `i`, ordered around the face.
function Geometry.facePolygon(planes: { Plane }, i: number, vertices: { Vector3 }, eps: number?): { Vector3 }
	local e = eps or 1e-4
	local p = planes[i]
	local on: { Vector3 } = {}
	for _, v in vertices do
		if math.abs(p.normal:Dot(v) - p.distance) <= e then
			table.insert(on, v)
		end
	end
	if #on < 3 then
		return on
	end
	local c = Geometry.centroid(on)
	local n = p.normal
	local ref = if math.abs(n.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	local u = n:Cross(ref).Unit
	local w = n:Cross(u)
	local keyed: { { v: Vector3, a: number } } = table.create(#on)
	for k, v in on do
		local d = v - c
		keyed[k] = { v = v, a = math.atan2(d:Dot(w), d:Dot(u)) }
	end
	table.sort(keyed, function(a, b): boolean
		return a.a < b.a
	end)
	for k, rec in keyed do
		on[k] = rec.v
	end
	return on
end

--- Area of a planar convex polygon given as ordered 3-D points.
function Geometry.polygonArea3(points: { Vector3 }): number
	local a = 0
	for k = 2, #points - 1 do
		a += (points[k] - points[1]):Cross(points[k + 1] - points[1]).Magnitude / 2
	end
	return a
end

--- Exact volume of the convex polyhedron: V = 1/3 Σ area_f · d_f (divergence theorem with outward unit normals).
function Geometry.volume(planes: { Plane }, vertices: { Vector3 }): number
	local v = 0
	for i, p in planes do
		local poly = Geometry.facePolygon(planes, i, vertices)
		if #poly >= 3 then
			v += Geometry.polygonArea3(poly) * p.distance / 3
		end
	end
	return v
end

--- Uniform random point on a planar convex polygon (ordered 3-D points); nil for degenerate polygons.
function Geometry.samplePolygon(points: { Vector3 }, rng: RNG): Vector3?
	local total = Geometry.polygonArea3(points)
	if total <= 1e-12 then
		return nil
	end
	local pick = rng:next() * total
	for k = 2, #points - 1 do
		local a, b, c = points[1], points[k], points[k + 1]
		local area = (b - a):Cross(c - a).Magnitude / 2
		if pick <= area or k == #points - 1 then
			local r1, r2 = rng:next(), rng:next()
			if r1 + r2 > 1 then
				r1, r2 = 1 - r1, 1 - r2
			end
			return a + (b - a) * r1 + (c - a) * r2
		end
		pick -= area
	end
	return nil
end

return Geometry
