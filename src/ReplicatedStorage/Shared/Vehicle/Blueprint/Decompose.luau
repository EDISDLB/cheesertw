--!strict
--[[
	Vehicle/Blueprint/Decompose — turns one convex armor body (half-space planes) into Roblox parts that tile it.

	Purpose:          The visual half of armor/visual parity. A body is cut into horizontal slabs at its vertex
	                  heights. In each slab:
	                    1. core   = plan section at the slab bottom ∩ section at the top, extruded over the slab and
	                                split into x-strips (Block + up to two Wedges each): exact for any convex
	                                polygon (boxes, octagons, hexagons, tapers);
	                    2. wedges = one WedgePart per sloped face, its slope lying ON the face plane, spanning the
	                                part of the face edge present at both slab levels;
	                    3. corners = one CornerWedgePart where two sloped faces meet at a right angle in plan and
	                                narrow the same way.
	                  The result is exact for stacks of axis-aligned slopes (hulls, box/cast/dome turrets,
	                  superstructures) and an inner approximation with small corner notches where sloped faces meet
	                  at other angles (pike noses, octagonal and hexagonal turrets). Every emitted part is checked to
	                  lie inside the body, so a visual never shows armor that is not there.
	Dependencies:     Blueprint/Geometry, Blueprint/Shapes.
	State:            None.
	Validation:       Pieces whose vertices leave the body (> 1e-3 studs) are discarded; degenerate slabs skipped.
	Error handling:   Never throws; an empty body yields no pieces.
	Performance notes: Build-time only: O(slabs × faces²) with tiny constants.
]]

local Geometry = require("./Geometry")
local Shapes = require("./Shapes")

type Plane = Geometry.Plane
type Poly = Geometry.Poly
type ShapeSpec = Shapes.ShapeSpec

export type PieceKind = "core" | "wedge" | "corner"
export type Piece = {
	spec: ShapeSpec,
	kind: PieceKind,
	face: number?, -- plane index whose surface the piece's slope lies on (wedges, corners)
}

local Decompose = {}

local LEVEL_EPS = 1e-4
local MIN_THICK = 1e-3
local INSIDE_EPS = 1e-3

local function insideBody(planes: { Plane }, spec: ShapeSpec): boolean
	for _, v in Shapes.vertices(spec) do
		if Geometry.signedDistance(planes, v.X, v.Y, v.Z) > INSIDE_EPS then
			return false
		end
	end
	return true
end

local function push(out: { Piece }, planes: { Plane }, spec: ShapeSpec?, kind: PieceKind, face: number?)
	if spec ~= nil and insideBody(planes, spec) then
		table.insert(out, { spec = spec, kind = kind, face = face })
	end
end

-- Plan triangle (x, z) extruded over [y0, y1] as two right-triangle wedges split by the altitude onto the longest
-- edge (its foot always lies inside that edge).
local function triangleWedges(
	out: { ShapeSpec },
	ax: number,
	az: number,
	bx: number,
	bz: number,
	cx: number,
	cz: number,
	ym: number,
	h: number
)
	local pts = { { ax, az }, { bx, bz }, { cx, cz } }
	local best, bestLen = 1, -1
	for i = 1, 3 do
		local p, q = pts[i], pts[i % 3 + 1]
		local len = (q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2
		if len > bestLen then
			best, bestLen = i, len
		end
	end
	if bestLen < 1e-12 then
		return
	end
	local e1, e2, v = pts[best], pts[best % 3 + 1], pts[(best + 1) % 3 + 1]
	local ex, ez = e2[1] - e1[1], e2[2] - e1[2]
	local t = ((v[1] - e1[1]) * ex + (v[2] - e1[2]) * ez) / bestLen
	local fx, fz = e1[1] + ex * t, e1[2] + ez * t
	local foot = Vector3.new(fx, ym, fz)
	local apex = Vector3.new(v[1] - fx, 0, v[2] - fz)
	for _, e in { e1, e2 } do
		local spec = Shapes.wedge(foot, Vector3.new(e[1] - fx, 0, e[2] - fz), apex, h)
		if spec ~= nil then
			table.insert(out, spec)
		end
	end
end

--- Exact tiling of the vertical prism `poly` × [y0, y1] with blocks and x-strip wedges.
function Decompose.prism(poly: Poly, y0: number, y1: number): { ShapeSpec }
	local out: { ShapeSpec } = {}
	if #poly < 3 or y1 - y0 < MIN_THICK then
		return out
	end
	local xs: { number } = {}
	for _, p in poly do
		table.insert(xs, p.x)
	end
	table.sort(xs)
	local uniq: { number } = {}
	for _, x in xs do
		if #uniq == 0 or x - uniq[#uniq] > 1e-6 then
			table.insert(uniq, x)
		end
	end
	local ym = (y0 + y1) / 2
	local h = y1 - y0
	for i = 1, #uniq - 1 do
		local xa, xb = uniq[i], uniq[i + 1]
		if xb - xa < 1e-4 then
			continue
		end
		local la, ha = Geometry.spanAtX(poly, xa)
		local lb, hb = Geometry.spanAtX(poly, xb)
		if la == nil or ha == nil or lb == nil or hb == nil then
			continue
		end
		local z0, z1 = math.max(la, lb), math.min(ha, hb)
		if z0 > z1 + 1e-9 then
			-- slanted strip whose end spans do not overlap: two triangles, each split into right triangles
			if ha - la > 1e-6 then
				triangleWedges(out, xa, la, xb, lb, xa, ha, ym, h)
			end
			if hb - lb > 1e-6 then
				triangleWedges(out, xa, ha, xb, lb, xb, hb, ym, h)
			end
			continue
		end
		if z1 - z0 > 1e-4 then
			local block = Shapes.box(Vector3.new(xa, y0, z0), Vector3.new(xb, y1, z1))
			if block ~= nil then
				table.insert(out, block)
			end
		end
		-- lower chain triangle (between the low chain and z0)
		if math.abs(la - lb) > 1e-4 then
			local spec
			if la < lb then
				spec = Shapes.wedge(Vector3.new(xa, ym, lb), Vector3.new(0, 0, la - lb), Vector3.new(xb - xa, 0, 0), h)
			else
				spec = Shapes.wedge(Vector3.new(xb, ym, la), Vector3.new(0, 0, lb - la), Vector3.new(xa - xb, 0, 0), h)
			end
			if spec ~= nil then
				table.insert(out, spec)
			end
		end
		-- upper chain triangle (between z1 and the high chain)
		if math.abs(ha - hb) > 1e-4 then
			local spec
			if ha > hb then
				spec = Shapes.wedge(Vector3.new(xa, ym, hb), Vector3.new(0, 0, ha - hb), Vector3.new(xb - xa, 0, 0), h)
			else
				spec = Shapes.wedge(Vector3.new(xb, ym, ha), Vector3.new(0, 0, hb - ha), Vector3.new(xa - xb, 0, 0), h)
			end
			if spec ~= nil then
				table.insert(out, spec)
			end
		end
	end
	return out
end

-- Interval [lo, hi] along the edge direction (tx, tz) of the polygon's boundary on the line hx·x + hz·z = s.
local function chord(poly: Poly, hx: number, hz: number, s: number, tx: number, tz: number): (number?, number?)
	local lo, hi = math.huge, -math.huge
	local count = 0
	for _, p in poly do
		if math.abs(hx * p.x + hz * p.z - s) < 1e-5 then
			local t = tx * p.x + tz * p.z
			lo, hi = math.min(lo, t), math.max(hi, t)
			count += 1
		end
	end
	if count < 2 then
		return nil, nil
	end
	return lo, hi
end

type FaceSlab = {
	face: number,
	up: boolean, -- narrowing upward (the slope's full width is at the slab bottom)
	run: number,
	sIn: number, -- offset of the inner line along the outward horizontal
	hx: number,
	hz: number,
}

--- Parts tiling the convex body (planes + its vertices). See the module header for the method.
function Decompose.body(planes: { Plane }, vertices: { Vector3 }): { Piece }
	local out: { Piece } = {}
	if #vertices < 4 then
		return out
	end
	local ys: { number } = {}
	for _, v in vertices do
		table.insert(ys, v.Y)
	end
	table.sort(ys)
	local levels: { number } = {}
	for _, y in ys do
		if #levels == 0 or y - levels[#levels] > LEVEL_EPS then
			table.insert(levels, y)
		end
	end
	for s = 1, #levels - 1 do
		local y0, y1 = levels[s], levels[s + 1]
		local h = y1 - y0
		if h < MIN_THICK then
			continue
		end
		-- 1. core prism
		local core = Geometry.section(planes, { y0, y1 })
		if #core >= 3 and math.abs(Geometry.polyArea(core)) > 1e-6 then
			for _, spec in Decompose.prism(core, y0, y1) do
				push(out, planes, spec, "core", nil)
			end
		end
		-- 2. one wedge per sloped face
		local bottom = Geometry.section(planes, { y0 })
		local top = Geometry.section(planes, { y1 })
		local slabs: { FaceSlab } = {}
		for k, p in planes do
			local n = p.normal
			local hn = math.sqrt(n.X * n.X + n.Z * n.Z)
			if hn < 1e-6 or math.abs(n.Y) < 1e-6 then
				continue
			end
			local hx, hz = n.X / hn, n.Z / hn
			local tx, tz = -hz, hx
			local s0 = (p.distance - n.Y * y0) / hn
			local s1 = (p.distance - n.Y * y1) / hn
			local a0, b0 = chord(bottom, hx, hz, s0, tx, tz)
			local a1, b1 = chord(top, hx, hz, s1, tx, tz)
			if a0 == nil or b0 == nil or a1 == nil or b1 == nil then
				continue
			end
			local lo, hi = math.max(a0, a1), math.min(b0, b1)
			local run = math.abs(s0 - s1)
			if hi - lo < 1e-3 or run < 1e-4 then
				continue
			end
			local up = s1 < s0
			local sIn = math.min(s0, s1)
			local tm = (lo + hi) / 2
			local yRA = if up then y0 else y1
			local pRA = Vector3.new(hx * sIn + tx * tm, yRA, hz * sIn + tz * tm)
			local outward = Vector3.new(hx, 0, hz) * run
			local vertical = Vector3.new(0, if up then h else -h, 0)
			push(out, planes, Shapes.wedge(pRA, outward, vertical, hi - lo), "wedge", k)
			table.insert(slabs, { face = k, up = up, run = run, sIn = sIn, hx = hx, hz = hz })
		end
		-- 3. corner pyramids between perpendicular sloped faces narrowing the same way
		for i = 1, #slabs - 1 do
			local f1 = slabs[i]
			for j = i + 1, #slabs do
				local f2 = slabs[j]
				if f1.up ~= f2.up or math.abs(f1.hx * f2.hx + f1.hz * f2.hz) > 1e-6 then
					continue
				end
				local det = f1.hx * f2.hz - f1.hz * f2.hx
				if math.abs(det) < 1e-9 then
					continue
				end
				local qx = (f1.sIn * f2.hz - f2.sIn * f1.hz) / det
				local qz = (f1.hx * f2.sIn - f2.hx * f1.sIn) / det
				local yBase = if f1.up then y0 else y1
				local spec = Shapes.cornerWedge(
					Vector3.new(qx, yBase, qz),
					Vector3.new(f1.hx, 0, f1.hz) * f1.run,
					Vector3.new(f2.hx, 0, f2.hz) * f2.run,
					Vector3.new(0, if f1.up then h else -h, 0)
				)
				push(out, planes, spec, "corner", f1.face)
			end
		end
	end
	return out
end

return Decompose
