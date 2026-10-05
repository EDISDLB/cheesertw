--[[
	HeightmapWorld — analytic implementation of Types.World for headless battles (ARCHITECTURE §6.4).

	Purpose:          Terrain from a height function, static oriented boxes (props, rocks, houses, destructibles),
	                  foliage spheres (concealment), smoke spheres and a global water level — enough to run whole
	                  battles in Lune with the same World interface RobloxWorld implements.
	Dependencies:     Roblox datatypes (Vector3, CFrame) injected by the Loader.
	State:            Box/foliage/smoke lists and the destroyed-object set.
	Validation:       Options are type-checked in new(); box sizes must be positive.
	Error handling:   Queries never throw on valid Vector3/CFrame input.
	Performance notes: Terrain raycasts march in `step` studs then bisect (20 iterations); box tests are O(boxes).
	                  Fine for tests; not meant for production.

	Mode rules (shared with RobloxWorld): "Shell" hits terrain + every box (destructibles included);
	"Sight" hits terrain + boxes with blocksSight ~= false; "Ground" hits terrain + non-destructible boxes with
	ground ~= false. Foliage and smoke never block rays; sightLine reports them. Geometry containing a ray's origin
	is not hit (Roblox raycast semantics); sweepBox reports an initial overlap at distance 0.
]]

export type Box = {
	id: string?,
	cframe: CFrame,
	size: Vector3,
	material: string?,
	destructible: boolean?,
	blocksSight: boolean?,
	ground: boolean?,
}
export type FoliageSphere = { id: string?, center: Vector3, radius: number, concealment: number }
export type SmokeSphere = { center: Vector3, radius: number }
export type Options = {
	height: ((x: number, z: number) -> number)?,
	groundMaterial: (string | (x: number, z: number) -> string)?,
	waterLevel: number?,
	boxes: { Box }?,
	foliage: { FoliageSphere }?,
	smoke: { SmokeSphere }?,
	step: number?,
	maxRayLength: number?,
}

local HeightmapWorld = {}
HeightmapWorld.__index = HeightmapWorld

local EPS = 1e-6

function HeightmapWorld.new(options: Options?)
	local opts = options or {}
	local self = setmetatable({
		_height = opts.height or function(_x: number, _z: number): number
			return 0
		end,
		_material = opts.groundMaterial or "Grass",
		_waterLevel = opts.waterLevel,
		_boxes = {},
		_foliage = {},
		_smoke = {},
		_destroyed = {},
		_step = opts.step or 1,
		_maxRay = opts.maxRayLength or 10000,
	}, HeightmapWorld)
	for _, box in opts.boxes or {} do
		self:addBox(box)
	end
	for _, f in opts.foliage or {} do
		self:addFoliage(f)
	end
	for _, s in opts.smoke or {} do
		self:addSmoke(s)
	end
	return self
end

function HeightmapWorld.addBox(self: any, box: Box)
	assert(typeof(box.cframe) == "CFrame" and typeof(box.size) == "Vector3", "box needs cframe and size")
	assert(box.size.X > 0 and box.size.Y > 0 and box.size.Z > 0, "box size must be positive")
	table.insert(self._boxes, box)
end

function HeightmapWorld.addFoliage(self: any, foliage: FoliageSphere)
	table.insert(self._foliage, foliage)
end

function HeightmapWorld.addSmoke(self: any, smoke: SmokeSphere)
	table.insert(self._smoke, smoke)
end

function HeightmapWorld.heightAt(self: any, x: number, z: number): number
	return self._height(x, z)
end

function HeightmapWorld.isDestroyed(self: any, objectId: string): boolean
	return self._destroyed[objectId] == true
end

local function materialAt(self: any, x: number, z: number): string
	local m = self._material
	if type(m) == "function" then
		return m(x, z)
	end
	return m
end

local function terrainNormal(self: any, x: number, z: number): Vector3
	local e = 0.05
	local h = self._height
	local dx = (h(x + e, z) - h(x - e, z)) / (2 * e)
	local dz = (h(x, z + e) - h(x, z - e)) / (2 * e)
	return Vector3.new(-dx, 1, -dz).Unit
end

-- Distance along the unit ray to the terrain surface within [0, length], or nil.
local function terrainHit(self: any, origin: Vector3, dir: Vector3, length: number): number?
	local function f(t: number): number
		local p = origin + dir * t
		return p.Y - self._height(p.X, p.Z)
	end
	-- Rays starting below the surface ignore terrain until they emerge (Roblox: the origin's geometry is not hit).
	local prevT, prevF = 0, f(0)
	local t = 0
	while prevF <= 0 do
		if t >= length then
			return nil
		end
		t = math.min(length, t + self._step)
		prevT, prevF = t, f(t)
	end
	while t < length do
		t = math.min(length, t + self._step)
		local ft = f(t)
		if ft <= 0 then
			local lo, hi = prevT, t
			for _ = 1, 24 do
				local mid = (lo + hi) / 2
				if f(mid) > 0 then
					lo = mid
				else
					hi = mid
				end
			end
			return hi
		end
		prevT, prevF = t, ft
	end
	return nil
end

-- Ray vs oriented box (slab test in box space). Returns (distance, worldNormal) or nil.
local function boxHit(box: Box, origin: Vector3, dir: Vector3, length: number): (number?, Vector3?)
	local localOrigin = box.cframe:PointToObjectSpace(origin)
	local localDir = box.cframe:VectorToObjectSpace(dir)
	local half = box.size / 2
	local tMin, tMax = -math.huge, math.huge
	local enterAxis, enterSign = 0, 0
	local o = { localOrigin.X, localOrigin.Y, localOrigin.Z }
	local d = { localDir.X, localDir.Y, localDir.Z }
	local h = { half.X, half.Y, half.Z }
	for axis = 1, 3 do
		if math.abs(d[axis]) < EPS then
			if o[axis] < -h[axis] or o[axis] > h[axis] then
				return nil, nil
			end
		else
			local t1 = (-h[axis] - o[axis]) / d[axis]
			local t2 = (h[axis] - o[axis]) / d[axis]
			local sign = -1
			if t1 > t2 then
				t1, t2 = t2, t1
				sign = 1
			end
			if t1 > tMin then
				tMin = t1
				enterAxis = axis
				enterSign = sign
			end
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil, nil
			end
		end
	end
	-- Behind the origin, beyond the ray, or starting inside the box (ignored, like Roblox raycasts).
	if tMax < 0 or tMin > length or tMin < 0 then
		return nil, nil
	end
	local localNormal = Vector3.new(
		if enterAxis == 1 then enterSign else 0,
		if enterAxis == 2 then enterSign else 0,
		if enterAxis == 3 then enterSign else 0
	)
	return tMin, box.cframe:VectorToWorldSpace(localNormal)
end

local function boxApplies(self: any, box: Box, mode: string): boolean
	if box.id ~= nil and self._destroyed[box.id] then
		return false
	end
	if mode == "Sight" then
		return box.blocksSight ~= false
	elseif mode == "Ground" then
		return box.ground ~= false and box.destructible ~= true
	end
	return true
end

function HeightmapWorld.raycast(self: any, origin: Vector3, direction: Vector3, mode: string): any
	local length = direction.Magnitude
	if length < EPS then
		return nil
	end
	local dir = direction / length
	local bestT, bestNormal, bestBox = nil, nil, nil
	local tTerrain = terrainHit(self, origin, dir, length)
	if tTerrain ~= nil then
		bestT = tTerrain
	end
	for _, box in self._boxes do
		if boxApplies(self, box, mode) then
			local t, normal = boxHit(box, origin, dir, length)
			if t ~= nil and (bestT == nil or t < bestT) then
				bestT, bestNormal, bestBox = t, normal, box
			end
		end
	end
	if bestT == nil then
		return nil
	end
	local position = origin + dir * bestT
	if bestBox == nil then
		return {
			position = position,
			normal = terrainNormal(self, position.X, position.Z),
			distance = bestT,
			material = materialAt(self, position.X, position.Z),
			objectId = nil,
			destructible = false,
		}
	end
	return {
		position = position,
		normal = bestNormal,
		distance = bestT,
		material = bestBox.material or "Concrete",
		objectId = bestBox.id,
		destructible = bestBox.destructible == true,
	}
end

function HeightmapWorld.groundAt(self: any, x: number, z: number, fromY: number): any
	return self:raycast(Vector3.new(x, fromY, z), Vector3.new(0, -self._maxRay, 0), "Ground")
end

-- Separating-axis test between two oriented boxes. Returns (overlapping, minPenetration, axis toward B).
local function obbOverlap(cfA: CFrame, sizeA: Vector3, cfB: CFrame, sizeB: Vector3): (boolean, number, Vector3)
	local axesA = { cfA.XVector, cfA.YVector, cfA.ZVector }
	local axesB = { cfB.XVector, cfB.YVector, cfB.ZVector }
	local ha = { sizeA.X / 2, sizeA.Y / 2, sizeA.Z / 2 }
	local hb = { sizeB.X / 2, sizeB.Y / 2, sizeB.Z / 2 }
	local delta = cfB.Position - cfA.Position
	local candidates = {}
	for i = 1, 3 do
		table.insert(candidates, axesA[i])
		table.insert(candidates, axesB[i])
	end
	for i = 1, 3 do
		for j = 1, 3 do
			local c = axesA[i]:Cross(axesB[j])
			if c.Magnitude > 1e-4 then
				table.insert(candidates, c.Unit)
			end
		end
	end
	local minOverlap, minAxis = math.huge, Vector3.new(0, 1, 0)
	for _, axis in candidates do
		local ra = 0
		local rb = 0
		for i = 1, 3 do
			ra += ha[i] * math.abs(axesA[i]:Dot(axis))
			rb += hb[i] * math.abs(axesB[i]:Dot(axis))
		end
		local dist = delta:Dot(axis)
		local overlap = ra + rb - math.abs(dist)
		if overlap <= 0 then
			return false, 0, axis
		end
		if overlap < minOverlap then
			minOverlap = overlap
			minAxis = if dist >= 0 then axis else -axis
		end
	end
	return true, minOverlap, minAxis
end

local function anyOverlap(self: any, cframe: CFrame, size: Vector3): (Box?, Vector3?)
	for _, box in self._boxes do
		if box.id == nil or not self._destroyed[box.id] then
			local overlapping, _, axis = obbOverlap(box.cframe, box.size, cframe, size)
			if overlapping then
				return box, axis
			end
		end
	end
	return nil, nil
end

function HeightmapWorld.sweepBox(self: any, cframe: CFrame, size: Vector3, displacement: Vector3): any
	local distance = displacement.Magnitude
	local minHalf = math.min(size.X, size.Y, size.Z) / 2
	local steps = math.max(1, math.ceil(distance / math.max(0.05, minHalf * 0.5)))
	local hitBox, hitAxis = anyOverlap(self, cframe, size)
	local tHit = 0
	if hitBox == nil then
		local prev = 0
		for i = 1, steps do
			local t = i / steps
			local box, axis = anyOverlap(self, cframe + displacement * t, size)
			if box ~= nil then
				-- Refine the first contact between prev and t.
				local lo, hi = prev, t
				for _ = 1, 16 do
					local mid = (lo + hi) / 2
					if anyOverlap(self, cframe + displacement * mid, size) ~= nil then
						hi = mid
					else
						lo = mid
					end
				end
				hitBox, hitAxis, tHit = box, axis, hi
				break
			end
			prev = t
		end
	end
	if hitBox == nil then
		return nil
	end
	local moverCenter = (cframe + displacement * tHit).Position
	local localCenter = hitBox.cframe:PointToObjectSpace(moverCenter)
	local half = hitBox.size / 2
	local clamped = Vector3.new(
		math.clamp(localCenter.X, -half.X, half.X),
		math.clamp(localCenter.Y, -half.Y, half.Y),
		math.clamp(localCenter.Z, -half.Z, half.Z)
	)
	return {
		position = hitBox.cframe:PointToWorldSpace(clamped),
		normal = hitAxis or Vector3.new(0, 1, 0),
		distance = distance * tHit,
		material = hitBox.material or "Concrete",
		objectId = hitBox.id,
		destructible = hitBox.destructible == true,
	}
end

-- Length of the segment [0, limit] (unit dir from origin) inside the sphere; 0 when not crossing.
local function segmentInSphere(origin: Vector3, dir: Vector3, limit: number, center: Vector3, radius: number): number
	local m = origin - center
	local b = m:Dot(dir)
	local c = m:Dot(m) - radius * radius
	local disc = b * b - c
	if disc <= 0 then
		return 0
	end
	local root = math.sqrt(disc)
	local t1 = math.max(0, -b - root)
	local t2 = math.min(limit, -b + root)
	return math.max(0, t2 - t1)
end

function HeightmapWorld.sightLine(self: any, from: Vector3, to: Vector3): any
	local offset = to - from
	local distance = offset.Magnitude
	if distance < EPS then
		return { blocked = false, foliage = 0, smoke = false }
	end
	local dir = offset / distance
	local limit = distance
	local blocked = false
	local hit = self:raycast(from, offset, "Sight")
	if hit ~= nil and hit.distance < distance - 1e-3 then
		blocked = true
		limit = hit.distance
	end
	local foliage = 0
	for _, f in self._foliage do
		if (f.id == nil or not self._destroyed[f.id]) and segmentInSphere(from, dir, limit, f.center, f.radius) > 0 then
			foliage += f.concealment
		end
	end
	local smoke = false
	for _, s in self._smoke do
		if segmentInSphere(from, dir, limit, s.center, s.radius) > 0 then
			smoke = true
			break
		end
	end
	return { blocked = blocked, foliage = foliage, smoke = smoke }
end

function HeightmapWorld.waterDepthAt(self: any, position: Vector3): number
	local level = self._waterLevel
	if level == nil then
		return 0
	end
	if self._height(position.X, position.Z) >= level then
		return 0
	end
	return math.max(0, level - position.Y)
end

function HeightmapWorld.destroyObject(self: any, objectId: string)
	for _, box in self._boxes do
		if box.id == objectId and box.destructible == true then
			self._destroyed[objectId] = true
			return
		end
	end
	for _, f in self._foliage do
		if f.id == objectId then
			self._destroyed[objectId] = true
			return
		end
	end
end

return HeightmapWorld
