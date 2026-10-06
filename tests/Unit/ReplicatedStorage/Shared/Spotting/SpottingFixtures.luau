--!strict
--[[
	SpottingFixtures — vehicle records, worlds and a counting World wrapper shared by the Spotting specs (not a spec).

	Purpose:          Build SpottingVehicle records and HeightmapWorld scenes in METRES (converted to studs here), so
	                  specs read like the decisions doc (a 300 m pair, a bush 10 m in front of the observer).
	Dependencies:     tests/Harness/HeightmapWorld, Core/Units.
	State:            None (every call builds fresh tables).
	Validation:       N/A (test-only).
	Error handling:   N/A.
	Performance notes: Flat worlds march terrain in one 4,000-stud step (exact on flat ground: rays never dip below 0).

	Vehicle geometry (studs, hull space; −Z forward): hull box 9.6 × 6 × 19.8 (3.2 × 2 × 6.6 m), centre y = 3.
	Turret ring at (0, 6, 0); view point (gun axis) turret (0, 2.4, −1.5) → hull y 8.4. Checkpoints: turret roof
	(0, 8.7, 0), mantlet (0, 7.5, −4.2), front (0, 4.8, −9.6), rear (0, 4.8, 9.6), left (−4.5, 4.8, 0), right
	(4.5, 4.8, 0). Roof port = (0, 8.7, 0).
]]

local HeightmapWorld = require("@tests/Harness/HeightmapWorld")
local Units = require("@game/ReplicatedStorage/Shared/Core/Units")

local Fixtures = {}

local S = Units.STUDS_PER_METER
Fixtures.S = S
Fixtures.DT = 1 / 30

Fixtures.PIVOTS = table.freeze({
	turretRing = CFrame.new(0, 6, 0),
	gunTrunnion = CFrame.new(0, 1.5, -3.5),
	muzzle = CFrame.new(0, 0, -9),
	viewPoint = Vector3.new(0, 2.4, -1.5),
	camoPoints = table.freeze({
		Vector3.new(0, 8.7, 0),
		Vector3.new(0, 7.5, -4.2),
		Vector3.new(0, 4.8, -9.6),
		Vector3.new(0, 4.8, 9.6),
		Vector3.new(-4.5, 4.8, 0),
		Vector3.new(4.5, 4.8, 0),
	}),
	trackContacts = { left = {}, right = {} },
	exhausts = {},
	hullSize = Vector3.new(9.6, 6, 19.8),
})

export type CamoOpts = { stationary: number?, moving: number?, afterShotMul: number?, net: number?, paint: number? }

function Fixtures.camo(o: CamoOpts?): any
	local opts: CamoOpts = o or {}
	return {
		stationary = opts.stationary or 0.12,
		moving = opts.moving or opts.stationary or 0.12,
		afterShotMul = opts.afterShotMul or 1,
		net = opts.net or 0,
		paint = opts.paint or 0,
	}
end

--- A vehicle record at (xM, zM) metres on flat ground, facing −Z unless `headingDeg` (clockwise from −Z) is given.
function Fixtures.vehicle(id: number, team: number, xM: number, zM: number, opts: { [string]: any }?): any
	local o = opts or {}
	local heading = math.rad(o.headingDeg or 0)
	local v = {
		id = id,
		team = team,
		alive = if o.alive == nil then true else o.alive,
		cframe = CFrame.new(xM * S, (o.yM or 0) * S, zM * S) * CFrame.Angles(0, -heading, 0),
		turretYawRad = o.turretYawRad or 0,
		pivots = o.pivots or Fixtures.PIVOTS,
		viewRangeM = o.viewRangeM or 400,
		viewRangeMul = o.viewRangeMul,
		camo = o.camo or Fixtures.camo(),
		moving = o.moving == true,
		lastShotAt = o.lastShotAt,
		inSmoke = o.inSmoke,
		sixthSense = o.sixthSense,
		conditionalModifiers = o.conditionalModifiers,
	}
	return v
end

--- Moves a record to (xM, zM) keeping its heading.
function Fixtures.place(v: any, xM: number, zM: number, yM: number?)
	local rot = v.cframe - v.cframe.Position
	v.cframe = CFrame.new(xM * S, (yM or 0) * S, zM * S) * rot
end

--- A flat HeightmapWorld. Boxes/foliage/smoke in METRES: { x, y, z, sx, sy, sz } boxes (centre + size),
--- { x, y, z, r, c } foliage spheres, { x, y, z, r } smoke spheres.
function Fixtures.flatWorld(scene: { boxes: { any }?, foliage: { any }?, smoke: { any }? }?): any
	local sc = scene or {}
	local world = HeightmapWorld.new({ step = 4000 })
	for i, b in sc.boxes or {} do
		Fixtures.addWall(world, b, `box{i}`)
	end
	for i, f in sc.foliage or {} do
		world:addFoliage({
			id = `bush{i}`,
			center = Vector3.new(f.x * S, f.y * S, f.z * S),
			radius = f.r * S,
			concealment = f.c,
		})
	end
	for _, s in sc.smoke or {} do
		world:addSmoke({ center = Vector3.new(s.x * S, s.y * S, s.z * S), radius = s.r * S })
	end
	return world
end

function Fixtures.addWall(world: any, b: any, id: string?)
	world:addBox({
		id = id,
		cframe = CFrame.new(b.x * S, b.y * S, b.z * S) * CFrame.Angles(0, math.rad(b.yawDeg or 0), 0),
		size = Vector3.new(b.sx * S, b.sy * S, b.sz * S),
	})
end

--- Wraps a World: counts sightLine calls (total and since `reset()`), optionally exposes an analytic foliageAlong.
function Fixtures.counting(inner: any, withProbe: boolean?): any
	local wrapper = { inner = inner, calls = 0, total = 0, probes = 0 }
	function wrapper.sightLine(self: any, from: Vector3, to: Vector3)
		self.calls += 1
		self.total += 1
		return inner:sightLine(from, to)
	end
	function wrapper.raycast(_self: any, origin: Vector3, direction: Vector3, mode: string)
		return inner:raycast(origin, direction, mode)
	end
	function wrapper.groundAt(_self: any, x: number, z: number, fromY: number)
		return inner:groundAt(x, z, fromY)
	end
	function wrapper.sweepBox(_self: any, cf: CFrame, size: Vector3, disp: Vector3)
		return inner:sweepBox(cf, size, disp)
	end
	function wrapper.waterDepthAt(_self: any, p: Vector3)
		return inner:waterDepthAt(p)
	end
	function wrapper.destroyObject(_self: any, id: string)
		inner:destroyObject(id)
	end
	function wrapper.reset(self: any)
		self.calls = 0
	end
	if withProbe then
		-- Analytic foliage only: same spheres as HeightmapWorld (it ignores blocking, like a pure volume walk).
		function wrapper.foliageAlong(self: any, from: Vector3, to: Vector3): number
			self.probes += 1
			local offset = to - from
			local length = offset.Magnitude
			if length < 1e-6 then
				return 0
			end
			local dir = offset / length
			local sum = 0
			for _, f in inner._foliage do
				local m = from - f.center
				local b = m:Dot(dir)
				local c = m:Dot(m) - f.radius * f.radius
				local disc = b * b - c
				if disc > 0 then
					local root = math.sqrt(disc)
					local t1 = math.max(0, -b - root)
					local t2 = math.min(length, -b + root)
					if t2 - t1 > 0 then
						sum += f.concealment
					end
				end
			end
			return sum
		end
	end
	return wrapper
end

--- Runs `system:update` at 30 Hz from tick `fromTick` (inclusive) to `toTick`, calling `each(tick, now, events)`.
function Fixtures.run(
	system: any,
	vehicles: { any },
	world: any,
	fromTick: number,
	toTick: number,
	each: ((number, number, { any }) -> ())?
)
	for tick = fromTick, toTick do
		local now = tick / 30
		local events = system:update(now, vehicles, world)
		if each ~= nil then
			each(tick, now, events)
		end
	end
end

--- Events of one kind (copied).
function Fixtures.filter(events: { any }, kind: string): { any }
	local out = {}
	for _, e in events do
		if e.kind == kind then
			table.insert(out, {
				kind = e.kind,
				t = e.t,
				team = e.team,
				target = e.target,
				spotter = e.spotter,
				first = e.first,
				position = e.position,
			})
		end
	end
	return out
end

return Fixtures
