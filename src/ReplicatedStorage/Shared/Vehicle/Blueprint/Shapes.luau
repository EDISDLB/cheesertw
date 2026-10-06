--!strict
--[[
	Vehicle/Blueprint/Shapes — Roblox part shapes as exact convex geometry: frames from geometric intent (a wedge
	from its right-angle vertex and legs, a corner wedge from its apex corner), point containment, vertices, volume
	and uniform interior / surface sampling.

	Purpose:          The single place that encodes how Block, WedgePart, CornerWedgePart, Cylinder and Ball parts
	                  occupy space (Blueprint/Types header). Builders describe what they want ("a wedge whose slope
	                  lies on this armor plane"), Shapes returns (shape, size, cframe); tests use the same functions
	                  to prove that visuals and armor coincide.
	Dependencies:     Core/RNG (type only).
	State:            None.
	Validation:       Degenerate requests (zero-length legs) return nil from the constructors.
	Error handling:   Never throws.
	Performance notes: Build- and test-time only. Containment is a few dot products in the part's local frame.

	Local geometry (half sizes hx, hy, hz):
	  Wedge:       box ∩ { hz·y − hy·z <= 0 }: right angle along (y = −hy, z = +hz), slope normal (0, hz, −hy).
	  CornerWedge: box ∩ { −hy·(x + hx) + hx·(y + hy) <= 0 } ∩ { hz·(y + hy) + hy·(z − hz) <= 0 }:
	               apex (hx, hy, −hz) over the base corner (hx, −hy, −hz).
	  Cylinder:    |x| <= hx, y² + z² <= r², r = min(hy, hz).   Ball: |p| <= min(hx, hy, hz).
]]

local RNGModule = require("../../Core/RNG")
type RNG = RNGModule.RNG

export type Shape = "Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"
export type ShapeSpec = { shape: Shape, size: Vector3, cframe: CFrame }

local Shapes = {}

local EPS_LEN = 1e-5

--- Axis-aligned block between two corners (any order).
function Shapes.box(a: Vector3, b: Vector3): ShapeSpec?
	local mn = a:Min(b)
	local mx = a:Max(b)
	local size = mx - mn
	if size.X < EPS_LEN or size.Y < EPS_LEN or size.Z < EPS_LEN then
		return nil
	end
	return { shape = "Block", size = size, cframe = CFrame.new((mn + mx) / 2) }
end

--- Oriented block.
function Shapes.block(cframe: CFrame, size: Vector3): ShapeSpec?
	if size.X < EPS_LEN or size.Y < EPS_LEN or size.Z < EPS_LEN then
		return nil
	end
	return { shape = "Block", size = size, cframe = cframe }
end

--- WedgePart with its right-angle edge through `p` (p = the right-angle vertex at the middle of the extrusion),
--- leg `a` along the bottom (local −Z), leg `b` up the back (local +Y), extruded `length` along local X = b̂ × −â.
--- The slope runs from p + a to p + b.
function Shapes.wedge(p: Vector3, a: Vector3, b: Vector3, length: number): ShapeSpec?
	local la, lb = a.Magnitude, b.Magnitude
	if la < EPS_LEN or lb < EPS_LEN or length < EPS_LEN then
		return nil
	end
	local zAxis = -a / la
	local yAxis = b / lb
	local xAxis = yAxis:Cross(zAxis)
	if xAxis.Magnitude < 0.5 then
		return nil -- legs not perpendicular
	end
	xAxis = xAxis.Unit
	local centre = p + a / 2 + b / 2
	return {
		shape = "Wedge",
		size = Vector3.new(length, lb, la),
		cframe = CFrame.fromMatrix(centre, xAxis, yAxis, zAxis),
	}
end

--- CornerWedgePart (square pyramid) whose apex sits at q + h above the base corner `q`; `u` and `w` run from q
--- along the two base edges (the vertical faces contain q, q + h and q + u or q + w).
function Shapes.cornerWedge(q: Vector3, u: Vector3, w: Vector3, h: Vector3): ShapeSpec?
	local lu, lw, lh = u.Magnitude, w.Magnitude, h.Magnitude
	if lu < EPS_LEN or lw < EPS_LEN or lh < EPS_LEN then
		return nil
	end
	local uh, wh, hh = u / lu, w / lw, h / lh
	local xAxis, zAxis, sx, sz
	-- local −X runs along one base edge, +Z along the other; pick the assignment that is right-handed.
	if (-uh):Cross(hh):Dot(wh) > 0 then
		xAxis, zAxis, sx, sz = -uh, wh, lu, lw
	else
		xAxis, zAxis, sx, sz = -wh, uh, lw, lu
	end
	local centre = q + u / 2 + w / 2 + h / 2
	return {
		shape = "CornerWedge",
		size = Vector3.new(sx, lh, sz),
		cframe = CFrame.fromMatrix(centre, xAxis, hh, zAxis),
	}
end

--- Cylinder part centred at `centre` with its axis along `axis` (any length; normalized).
function Shapes.cylinder(centre: Vector3, axis: Vector3, length: number, diameter: number): ShapeSpec?
	if length < EPS_LEN or diameter < EPS_LEN or axis.Magnitude < EPS_LEN then
		return nil
	end
	local x = axis.Unit
	local ref = if math.abs(x.Y) < 0.9 then Vector3.yAxis else Vector3.zAxis
	local z = x:Cross(ref).Unit
	local y = z:Cross(x)
	return {
		shape = "Cylinder",
		size = Vector3.new(length, diameter, diameter),
		cframe = CFrame.fromMatrix(centre, x, y, z),
	}
end

--- Ball part.
function Shapes.ball(centre: Vector3, diameter: number): ShapeSpec?
	if diameter < EPS_LEN then
		return nil
	end
	return { shape = "Ball", size = Vector3.new(diameter, diameter, diameter), cframe = CFrame.new(centre) }
end

--------------------------------------------------------------------------------
-- Queries (points are in the space the spec's cframe maps into)
--------------------------------------------------------------------------------

local function localContains(shape: Shape, size: Vector3, x: number, y: number, z: number, eps: number): boolean
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	if shape == "Ball" then
		local r = math.min(hx, hy, hz)
		return x * x + y * y + z * z <= (r + eps) * (r + eps)
	end
	if math.abs(x) > hx + eps or math.abs(y) > hy + eps or math.abs(z) > hz + eps then
		return false
	end
	if shape == "Block" then
		return true
	elseif shape == "Wedge" then
		return (hz * y - hy * z) / math.sqrt(hz * hz + hy * hy) <= eps
	elseif shape == "CornerWedge" then
		local f1 = (-hy * (x + hx) + hx * (y + hy)) / math.sqrt(hx * hx + hy * hy)
		local f2 = (hz * (y + hy) + hy * (z - hz)) / math.sqrt(hz * hz + hy * hy)
		return f1 <= eps and f2 <= eps
	else -- Cylinder
		local r = math.min(hy, hz)
		return y * y + z * z <= (r + eps) * (r + eps)
	end
end

--- True when `point` lies inside the part (within `eps` studs, default 1e-4).
function Shapes.contains(spec: ShapeSpec, point: Vector3, eps: number?): boolean
	local l = spec.cframe:PointToObjectSpace(point)
	return localContains(spec.shape, spec.size, l.X, l.Y, l.Z, eps or 1e-4)
end

local function localVertices(shape: Shape, size: Vector3): { Vector3 }
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	if shape == "Block" then
		local out = {}
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					table.insert(out, Vector3.new(sx * hx, sy * hy, sz * hz))
				end
			end
		end
		return out
	elseif shape == "Wedge" then
		return {
			Vector3.new(-hx, -hy, -hz),
			Vector3.new(hx, -hy, -hz),
			Vector3.new(-hx, -hy, hz),
			Vector3.new(hx, -hy, hz),
			Vector3.new(-hx, hy, hz),
			Vector3.new(hx, hy, hz),
		}
	elseif shape == "CornerWedge" then
		return {
			Vector3.new(-hx, -hy, -hz),
			Vector3.new(hx, -hy, -hz),
			Vector3.new(-hx, -hy, hz),
			Vector3.new(hx, -hy, hz),
			Vector3.new(hx, hy, -hz),
		}
	elseif shape == "Cylinder" then
		local r = math.min(hy, hz)
		local out = {}
		for k = 0, 15 do
			local a = k * math.pi / 8
			local c, s = math.cos(a) * r, math.sin(a) * r
			table.insert(out, Vector3.new(-hx, c, s))
			table.insert(out, Vector3.new(hx, c, s))
		end
		return out
	else -- Ball: the six poles (callers treat balls as small decorations)
		local r = math.min(hx, hy, hz)
		return {
			Vector3.new(r, 0, 0),
			Vector3.new(-r, 0, 0),
			Vector3.new(0, r, 0),
			Vector3.new(0, -r, 0),
			Vector3.new(0, 0, r),
			Vector3.new(0, 0, -r),
		}
	end
end

--- Corner points of the part in its parent space (cylinders: two 16-point rims; balls: six poles).
function Shapes.vertices(spec: ShapeSpec): { Vector3 }
	local out = localVertices(spec.shape, spec.size)
	for i, v in out do
		out[i] = spec.cframe:PointToWorldSpace(v)
	end
	return out
end

--- Volume in cubic studs.
function Shapes.volume(spec: ShapeSpec): number
	local s = spec.size
	if spec.shape == "Block" then
		return s.X * s.Y * s.Z
	elseif spec.shape == "Wedge" then
		return s.X * s.Y * s.Z / 2
	elseif spec.shape == "CornerWedge" then
		return s.X * s.Y * s.Z / 3
	elseif spec.shape == "Cylinder" then
		local r = math.min(s.Y, s.Z) / 2
		return math.pi * r * r * s.X
	else
		local r = math.min(s.X, s.Y, s.Z) / 2
		return 4 / 3 * math.pi * r * r * r
	end
end

--- Uniform random point inside the part (rejection sampling in its box).
function Shapes.samplePoint(spec: ShapeSpec, rng: RNG): Vector3
	local s = spec.size
	for _ = 1, 64 do
		local x, y, z = rng:range(-s.X / 2, s.X / 2), rng:range(-s.Y / 2, s.Y / 2), rng:range(-s.Z / 2, s.Z / 2)
		if localContains(spec.shape, s, x, y, z, 0) then
			return spec.cframe:PointToWorldSpace(Vector3.new(x, y, z))
		end
	end
	return spec.cframe.Position
end

local function localFaces(shape: Shape, size: Vector3): { { Vector3 } }
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z)
	end
	if shape == "Block" then
		return {
			{ v(hx, -hy, -hz), v(hx, hy, -hz), v(hx, hy, hz), v(hx, -hy, hz) },
			{ v(-hx, -hy, -hz), v(-hx, -hy, hz), v(-hx, hy, hz), v(-hx, hy, -hz) },
			{ v(-hx, hy, -hz), v(-hx, hy, hz), v(hx, hy, hz), v(hx, hy, -hz) },
			{ v(-hx, -hy, -hz), v(hx, -hy, -hz), v(hx, -hy, hz), v(-hx, -hy, hz) },
			{ v(-hx, -hy, hz), v(hx, -hy, hz), v(hx, hy, hz), v(-hx, hy, hz) },
			{ v(-hx, -hy, -hz), v(-hx, hy, -hz), v(hx, hy, -hz), v(hx, -hy, -hz) },
		}
	elseif shape == "Wedge" then
		return {
			{ v(-hx, -hy, -hz), v(hx, -hy, -hz), v(hx, -hy, hz), v(-hx, -hy, hz) },
			{ v(-hx, -hy, hz), v(hx, -hy, hz), v(hx, hy, hz), v(-hx, hy, hz) },
			{ v(-hx, -hy, -hz), v(-hx, hy, hz), v(hx, hy, hz), v(hx, -hy, -hz) },
			{ v(hx, -hy, -hz), v(hx, hy, hz), v(hx, -hy, hz) },
			{ v(-hx, -hy, -hz), v(-hx, -hy, hz), v(-hx, hy, hz) },
		}
	else -- CornerWedge
		local apex = v(hx, hy, -hz)
		return {
			{ v(-hx, -hy, -hz), v(hx, -hy, -hz), v(hx, -hy, hz), v(-hx, -hy, hz) },
			{ v(hx, -hy, -hz), apex, v(hx, -hy, hz) },
			{ v(hx, -hy, -hz), v(-hx, -hy, -hz), apex },
			{ v(-hx, -hy, -hz), v(-hx, -hy, hz), apex },
			{ v(-hx, -hy, hz), v(hx, -hy, hz), apex },
		}
	end
end

local function triArea(a: Vector3, b: Vector3, c: Vector3): number
	return (b - a):Cross(c - a).Magnitude / 2
end

--- Uniform random point on the part's surface (parent space). Cylinders: rim + caps; balls: the sphere.
function Shapes.sampleSurface(spec: ShapeSpec, rng: RNG): Vector3
	local s = spec.size
	local cf = spec.cframe
	if spec.shape == "Ball" then
		local d = Vector3.new(rng:normal(0, 1), rng:normal(0, 1), rng:normal(0, 1))
		if d.Magnitude < 1e-9 then
			d = Vector3.yAxis
		end
		return cf:PointToWorldSpace(d.Unit * (math.min(s.X, s.Y, s.Z) / 2))
	elseif spec.shape == "Cylinder" then
		local r = math.min(s.Y, s.Z) / 2
		local side = 2 * math.pi * r * s.X
		local cap = math.pi * r * r
		local pick = rng:next() * (side + 2 * cap)
		local a = rng:range(0, 2 * math.pi)
		if pick < side then
			return cf:PointToWorldSpace(Vector3.new(rng:range(-s.X / 2, s.X / 2), math.cos(a) * r, math.sin(a) * r))
		end
		local rr = r * math.sqrt(rng:next())
		local x = if pick < side + cap then -s.X / 2 else s.X / 2
		return cf:PointToWorldSpace(Vector3.new(x, math.cos(a) * rr, math.sin(a) * rr))
	end
	local faces = localFaces(spec.shape, s)
	local tris: { { Vector3 } } = {}
	local areas: { number } = {}
	local total = 0
	for _, f in faces do
		for k = 2, #f - 1 do
			local area = triArea(f[1], f[k], f[k + 1])
			table.insert(tris, { f[1], f[k], f[k + 1] })
			table.insert(areas, area)
			total += area
		end
	end
	local pick = rng:next() * total
	local chosen = tris[#tris]
	for i, area in areas do
		if pick <= area then
			chosen = tris[i]
			break
		end
		pick -= area
	end
	local r1, r2 = rng:next(), rng:next()
	if r1 + r2 > 1 then
		r1, r2 = 1 - r1, 1 - r2
	end
	local a, b, c = chosen[1], chosen[2], chosen[3]
	return cf:PointToWorldSpace(a + (b - a) * r1 + (c - a) * r2)
end

return Shapes
