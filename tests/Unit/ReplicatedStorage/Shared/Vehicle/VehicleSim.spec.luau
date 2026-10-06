-- VehicleSim: kinematic vehicle model (00-DECISIONS §2, §4, §6; ARCHITECTURE §6.1-6.2; docs/design/movement.md).
-- Regression ids: REG-VEH-01 (stuck/depenetration), REG-VEH-02 (never below ground, bounds), REG-VEH-03 (climb
-- limit), REG-VEH-05 (overturn), REG-VEH-07 (prediction replay determinism), REG-VEH-08 (destroyed objects),
-- REG-VEH-10 (drowning table), REG-VEH-11 (landing speed feeding fall damage), REG-NET-05 (input fuzz).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local HeightmapWorld = require("@tests/Harness/HeightmapWorld")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local VehicleSim = require("@game/ReplicatedStorage/Shared/Vehicle/VehicleSim")

local DT = 1 / 30
local SPM = 3
local G = 9.81
local WATTS_PER_HP = 745.7

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

local function withOverrides(base, overrides)
	for k, v in overrides or {} do
		base[k] = v
	end
	return base
end

-- Tier V-ish medium tank: 30 t, 480 hp (16 hp/t), 50/20 km/h, 36 °/s.
local function mediumStats(overrides)
	return withOverrides({
		vehicleId = "test_medium",
		class = "medium",
		massKg = 30000,
		enginePowerHp = 480,
		specificPowerHpT = 16,
		topSpeedKmh = 50,
		reverseSpeedKmh = 20,
		hullTraverseDegS = 36,
		terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
		dimensionsM = Vector3.new(3.2, 2.4, 6.6),
		pivot = true,
		turretMount = "Turret",
		turretTraverseDegS = 40,
		mechanics = {},
		conditionalModifiers = {},
	}, overrides)
end

-- Light tank: 18 t, 600 hp (33 hp/t), 60/22 km/h, 45 °/s.
local function lightStats(overrides)
	return withOverrides({
		vehicleId = "test_light",
		class = "light",
		massKg = 18000,
		enginePowerHp = 600,
		specificPowerHpT = 33.3,
		topSpeedKmh = 60,
		reverseSpeedKmh = 22,
		hullTraverseDegS = 45,
		terrainResistance = { hard = 0.8, medium = 1.0, soft = 1.7 },
		dimensionsM = Vector3.new(2.9, 2.1, 5.6),
		pivot = true,
		turretMount = "Turret",
		turretTraverseDegS = 46,
		mechanics = {},
		conditionalModifiers = {},
	}, overrides)
end

local function wheeledSpec()
	return {
		wheelPairs = 4,
		speedModeTopSpeedKmh = 91,
		speedModeSteeringMul = 0.6,
		speedModeReverseKmh = 30,
		toggleS = 1,
		lostPairSpeedMul = 0.75,
		movingDispersionMul = 1.15,
		turnRadiusM = 8,
	}
end

local function input(throttle, steer, flags)
	local cmd = {
		seq = 0,
		throttle = throttle or 0,
		steer = steer or 0,
		aimPoint = Vector3.zero,
		fire = false,
		holdTurret = false,
		brake = false,
		mechanic = false,
	}
	return withOverrides(cmd, flags)
end

-- Analytic World (same contract as tests/Harness/HeightmapWorld for groundAt: a probe that starts inside the terrain
-- finds nothing) without boxes: fast enough for long kinematic runs. `height` and `material` may be functions.
local function analyticWorld(opts)
	local o = opts or {}
	local heightFn = o.height or function()
		return 0
	end
	local material = o.material or "Concrete"
	local level = o.waterLevel
	return {
		calls = 0,
		groundAt = function(self, x, z, fromY)
			self.calls += 1
			local h = heightFn(x, z)
			if fromY < h then
				return nil
			end
			return {
				position = Vector3.new(x, h, z),
				normal = Vector3.yAxis,
				distance = fromY - h,
				material = if type(material) == "function" then material(x, z) else material,
				objectId = nil,
				destructible = false,
			}
		end,
		sweepBox = function()
			return nil
		end,
		waterDepthAt = function(_, p)
			if level == nil or heightFn(p.X, p.Z) >= level then
				return 0
			end
			return math.max(0, level - p.Y)
		end,
		raycast = function()
			return nil
		end,
		sightLine = function()
			return { blocked = false, foliage = 0, smoke = false }
		end,
		destroyObject = function() end,
	}
end

-- Flat ground of `material` on the harness HeightmapWorld (boxes, water, destroyObject). Terrain is a plane, so a
-- 2-stud march step (refined by bisection) is exact and keeps the specs fast.
local function flatWorld(material, options)
	local opts = options or {}
	opts.groundMaterial = material or "Concrete"
	opts.step = opts.step or 2
	return HeightmapWorld.new(opts)
end

-- Constant slope rising toward the north (-Z, the default heading) by `deg` (HeightmapWorld).
local function slopeWorld(deg, material)
	local k = math.tan(math.rad(deg))
	return HeightmapWorld.new({
		groundMaterial = material or "Concrete",
		step = 2,
		height = function(_x, z)
			return -z * k
		end,
	})
end

-- Allocation-light World for long runs: flat Grass ground (medium), no obstacles, no water.
local function fastFlatWorld(material)
	return analyticWorld({ material = material or "Grass" })
end

-- State with bounds far away (long straight runs must not reach the map edge).
local FAR = { minX = -1e6, maxX = 1e6, minZ = -1e6, maxZ = 1e6 }
local function newState(cf, options)
	local opts = options or {}
	opts.bounds = opts.bounds or FAR
	return VehicleSim.newState(cf or CFrame.new(), opts)
end

-- Heading CFrame (0 = north/-Z, + clockwise) at `position`.
local function facing(headingDeg, position)
	return CFrame.new(position or Vector3.zero) * CFrame.Angles(0, -math.rad(headingDeg), 0)
end

-- Steps `seconds` of simulation; returns the events (copied) with their tick numbers.
local function run(state, stats, world, cmd, seconds, onStep)
	local out = {}
	local ticks = math.floor(seconds * 30 + 0.5)
	for i = 1, ticks do
		local events = VehicleSim.step(state, cmd, stats, world, DT)
		for _, e in events do
			table.insert(out, {
				tick = i,
				kind = e.kind,
				t = e.t,
				speedMps = e.speedMps,
				normal = e.normal,
				objectId = e.objectId,
				destructible = e.destructible,
				inverted = e.inverted,
			})
		end
		if onStep then
			onStep(i, events)
		end
	end
	return out
end

local function eventsOf(list, kind)
	local out = {}
	for _, e in list do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

local function kmh(state)
	return VehicleSim.speedKmh(state)
end

local function deg(rad)
	return math.deg(rad)
end

local function isFinite(x)
	return x == x and x - x == 0
end

-- Bit-exact fingerprint of every simulated field.
local function fingerprint(s)
	local function f(x)
		return string.format("%.17g", x)
	end
	return table.concat({
		f(s.position.X),
		f(s.position.Y),
		f(s.position.Z),
		f(s.yaw),
		f(s.pitch),
		f(s.roll),
		f(s.speed),
		f(s.lateralSpeed),
		f(s.yawRate),
		f(s.verticalVelocity),
		f(s.groundPitch),
		f(s.groundRoll),
		f(s.terrainResistance),
		f(s.traction),
		f(s.waterDepthM),
		f(s.airborneTime),
		f(s.submergedTime),
		f(s.tiltTime),
		f(s.overturnedTime),
		f(s.stillTime),
		tostring(s.grounded),
		tostring(s.overturned),
		tostring(s.wrecked),
		tostring(s.immobileReason),
		s.mechanic.phase,
		f(s.mechanic.timer),
	}, "|")
end

-- Rough terrain with boxes and water for robustness tests.
local function roughWorld(seed, boxCount)
	local rng = RNG.new(seed)
	local boxes = {}
	for i = 1, boxCount do
		local h = rng:range(0.5, 12)
		table.insert(boxes, {
			id = "b" .. i,
			cframe = CFrame.new(rng:range(-120, 120), h / 2 + 2 * math.sin(i), rng:range(-120, 120))
				* CFrame.Angles(0, rng:range(0, 6.28), 0),
			size = Vector3.new(rng:range(2, 25), h, rng:range(2, 25)),
			destructible = rng:chance(0.2),
		})
	end
	local a1, a2, a3 = rng:range(5, 30), rng:range(15, 60), rng:range(0.5, 3)
	return HeightmapWorld.new({
		groundMaterial = function(x, _z)
			return if x > 0 then "Mud" else "Concrete"
		end,
		waterLevel = -10,
		height = function(x, z)
			return a1 * math.sin(x / a2) * math.cos(z / (a2 * 0.7)) + a3 * math.sin(x * 0.3 + z * 0.2)
		end,
		boxes = boxes,
	}),
		rng
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

describe("VehicleSim construction", function()
	it("takes the heading from the spawn LookVector and clamps the position into the bounds", function()
		local east = VehicleSim.newState(CFrame.lookAt(Vector3.new(1, 2, 3), Vector3.new(11, 2, 3)))
		expect(deg(east.yaw)).toBeCloseTo(90, 1e-4)
		expect(east.position).toBeCloseTo(Vector3.new(1, 2, 3), 1e-6)
		local south = VehicleSim.newState(facing(180))
		expect(math.abs(deg(south.yaw))).toBeCloseTo(180, 1e-4)
		local bounds = VehicleSim.boundsFromSize(100)
		expect(bounds).toEqual({ minX = -150, maxX = 150, minZ = -150, maxZ = 150 })
		local clamped = VehicleSim.newState(CFrame.new(1000, 5, -1000), { bounds = bounds })
		expect(clamped.position).toEqual(Vector3.new(150, 5, -150))
		local default = VehicleSim.newState(CFrame.new())
		expect(default.bounds.maxX).toBe(Config.Movement.DEFAULT_MAP_SIZE_M * SPM / 2)
	end)

	it("starts neutral: at rest, grounded, modules OK, no events", function()
		local s = VehicleSim.newState(CFrame.new())
		expect(s.speed).toBe(0)
		expect(s.lateralSpeed).toBe(0)
		expect(s.yawRate).toBe(0)
		expect(s.grounded).toBe(true)
		expect(s.wrecked).toBe(false)
		expect(s.immobilized).toBe(false)
		expect(s.events).toHaveLength(0)
		expect(s.modifiers).toEqual(VehicleSim.newModifiers())
		expect(s.modifiers.engine).toBe("Ok")
		expect(s.modifiers.speedCapKmh).toBe(math.huge)
		expect(s.mechanic.phase).toBe("Off")
	end)

	it("replaces a non-finite spawn with the origin", function()
		local s = VehicleSim.newState(CFrame.new(0 / 0, 1, 2))
		expect(s.position).toEqual(Vector3.zero)
		expect(s.yaw).toBe(0)
	end)

	it("settles onto the ground: snaps height and attitude at spawn", function()
		local world = slopeWorld(20)
		local stats = mediumStats()
		local s = VehicleSim.newState(CFrame.new(0, 200, 0))
		VehicleSim.settle(s, stats, world)
		expect(deg(s.pitch)).toBeCloseTo(20, 1e-3)
		expect(deg(s.roll)).toBeCloseTo(0, 1e-3)
		expect(s.position.Y).toBeCloseTo(0, 1e-3)
		expect(s.grounded).toBe(true)
		-- step() settles automatically when settle() was not called.
		local auto = VehicleSim.newState(CFrame.new(0, -50, 0))
		VehicleSim.step(auto, input(), stats, world, DT)
		expect(auto.position.Y).toBeCloseTo(0, 1e-3)
		expect(deg(auto.groundPitch)).toBeCloseTo(20, 1e-3)
	end)

	it("maps ground materials to resistance classes (00-DECISIONS §6)", function()
		for _, m in { "Concrete", "Asphalt", "Pavement", "Cobblestone", "Brick", "Slate", "Rock", "Basalt" } do
			expect(VehicleSim.terrainClassOf(m)).toBe("hard")
		end
		for _, m in { "Grass", "LeafyGrass", "Ground", "Sandstone" } do
			expect(VehicleSim.terrainClassOf(m)).toBe("medium")
		end
		for _, m in { "Sand", "Mud", "Snow", "Glacier" } do
			expect(VehicleSim.terrainClassOf(m)).toBe("soft")
		end
		expect(VehicleSim.terrainClassOf("Unobtainium")).toBe("medium")
		expect(VehicleSim.terrainClassOf(nil)).toBe("medium")
	end)

	it("uses the Blueprint pivots: contact samples, hull box and turret-roof drown depth", function()
		local pivots = {
			turretRing = CFrame.new(0, 6, 1),
			gunTrunnion = CFrame.new(0, 1.5, -2),
			muzzle = CFrame.new(0, 0, -12),
			viewPoint = Vector3.new(0, 3, 0),
			camoPoints = {},
			trackContacts = {
				left = { Vector3.new(-4, 0, -9), Vector3.new(-4, 0, 9) },
				right = { Vector3.new(4, 0, -9), Vector3.new(4, 0, 9) },
			},
			exhausts = {},
			hullSize = Vector3.new(10, 7, 22),
		}
		local s = VehicleSim.newState(CFrame.new(), { pivots = pivots })
		local stats = mediumStats()
		expect(VehicleSim.hullSize(s, stats)).toEqual(Vector3.new(10, 7, 22))
		expect(VehicleSim.drownDepthM(s, stats)).toBeCloseTo((6 + 3) / SPM, 1e-9)
		-- 4 contacts + the hull centre support.
		expect(s._contactX).toEqual({ -4, -4, 4, 4, 0 })
		expect(s._contactZ).toEqual({ -9, 9, -9, 9, 0 })
		local explicit = VehicleSim.newState(CFrame.new(), { pivots = pivots, drownDepthM = 2.5 })
		expect(VehicleSim.drownDepthM(explicit, stats)).toBe(2.5)
	end)

	it("falls back to default contacts when the pivots carry too few or malformed samples", function()
		local stats = mediumStats()
		for _, contacts in
			{
				{ left = {}, right = {} },
				{ left = { Vector3.new(0 / 0, 0, 1) }, right = { Vector3.new(1, 0, 1) } },
				{ left = nil, right = nil },
			}
		do
			local pivots = { trackContacts = contacts, hullSize = Vector3.new(0 / 0, 1, 1) }
			local s = VehicleSim.newState(CFrame.new(), { pivots = pivots })
			VehicleSim.step(s, input(), stats, flatWorld("Concrete"), DT)
			expect(#s._contactX).toBe(9)
			expect(VehicleSim.hullSize(s, stats)).toBeCloseTo(Vector3.new(3.2 * SPM, 2.4 * SPM, 6.6 * SPM), 1e-4)
		end
	end)

	it("derives defaults from VehicleStats.dimensionsM without pivots", function()
		local s = VehicleSim.newState(CFrame.new())
		local stats = mediumStats()
		local size = VehicleSim.hullSize(s, stats)
		expect(size).toBeCloseTo(Vector3.new(3.2 * SPM, 2.4 * SPM, 6.6 * SPM), 1e-4)
		expect(VehicleSim.drownDepthM(s, stats)).toBeCloseTo(2.4 + Config.Movement.DEFAULT_TURRET_HEIGHT_M, 1e-6)
		expect(#s._contactX).toBe(9) -- 4 per side + centre
	end)
end)

--------------------------------------------------------------------------------
-- Acceleration (00-DECISIONS §6)
--------------------------------------------------------------------------------

describe("VehicleSim acceleration (00-DECISIONS §6)", function()
	it("is traction-limited from a standstill: first tick = (μg − 0.1·R·g)·dt", function()
		local stats = lightStats()
		local s = newState(CFrame.new())
		run(s, stats, flatWorld("Concrete"), input(1), DT)
		local expected = (0.75 * G - G * 0.1 * 0.8) * DT
		expect(s.speed / SPM).toBeCloseTo(expected, 1e-9)
	end)

	it("reaches 95 % of top speed in the analytic time and then holds the cap exactly", function()
		local stats = lightStats()
		local k = 600 * WATTS_PER_HP / 18000 -- P/m (W/kg)
		local r = G * 0.1 * 0.8 -- rolling resistance on hard
		local mu = 0.75 * G
		local v1 = k / mu -- end of the traction-limited phase
		local top = 60 / 3.6
		local target = 0.95 * top
		local function F(v)
			return -v / r - (k / (r * r)) * math.log(k - r * v)
		end
		local analytic = v1 / (mu - r) + F(target) - F(v1)
		local s = newState(CFrame.new())
		local world = flatWorld("Concrete")
		local reached = nil
		run(s, stats, world, input(1), 30, function(i)
			if reached == nil and s.speed / SPM >= target then
				reached = i * DT
			end
		end)
		expect(reached).never.toBeNil()
		expect(math.abs(reached - analytic) / analytic).toBeLessThan(0.03)
		expect(kmh(s)).toBeCloseTo(60, 1e-9)
	end)

	it("settles at the power-limited terminal speed P/(m·g·0.1·R) when it is below the cap", function()
		local stats = mediumStats()
		local s = newState(CFrame.new())
		run(s, stats, fastFlatWorld(), input(1), 120) -- Grass = medium, R = 1.1
		local terminal = (480 * WATTS_PER_HP / 30000) / (G * 0.1 * 1.1)
		expect(terminal * 3.6).toBeLessThan(50)
		expect(math.abs(s.speed / SPM - terminal) / terminal).toBeLessThan(0.005)
		expect(s.terrainClass).toBe("medium")
		expect(s.terrainResistance).toBeCloseTo(1.1, 1e-12)
		expect(s.traction).toBeCloseTo(0.70, 1e-12)
	end)

	it("is slower on worse ground: hard > medium > soft", function()
		local speeds = {}
		for _, material in { "Concrete", "Grass", "Mud" } do
			local s = newState(CFrame.new())
			run(s, mediumStats(), flatWorld(material), input(1), 10)
			speeds[material] = s.speed
		end
		expect(speeds.Concrete).toBeGreaterThan(speeds.Grass)
		expect(speeds.Grass).toBeGreaterThan(speeds.Mud)
	end)

	it("scales the speed cap with partial throttle", function()
		local s = newState(CFrame.new())
		run(s, lightStats(), flatWorld("Concrete"), input(0.5), 30)
		expect(kmh(s)).toBeCloseTo(30, 1e-9)
	end)

	it("climbs a 15° slope at the power/gravity equilibrium speed", function()
		local s = newState(CFrame.new(0, 10, 0))
		run(s, mediumStats(), slopeWorld(15), input(1), 12)
		local theta = math.rad(15)
		local k = 480 * WATTS_PER_HP / 30000
		local expected = k / (G * 0.1 * 0.9 * math.cos(theta) + G * math.sin(theta))
		expect(math.abs(s.speed / SPM - expected) / expected).toBeLessThan(0.01)
		expect(deg(s.pitch)).toBeCloseTo(15, 1e-3)
	end)
end)

--------------------------------------------------------------------------------
-- Caps and braking
--------------------------------------------------------------------------------

describe("VehicleSim speed caps and braking", function()
	it("caps reverse speed at reverseSpeedKmh", function()
		local s = newState(CFrame.new())
		run(s, mediumStats(), flatWorld("Concrete"), input(-1), 15)
		expect(kmh(s)).toBeCloseTo(-20, 1e-9)
	end)

	it("defaults the reverse speed to clamp(0.35 × forward, 12, 25) km/h", function()
		for _, case in { { top = 50, expected = 17.5 }, { top = 80, expected = 25 }, { top = 20, expected = 12 } } do
			local s = newState(CFrame.new())
			run(
				s,
				lightStats({ topSpeedKmh = case.top, reverseSpeedKmh = 0 }),
				fastFlatWorld("Concrete"),
				input(-1),
				15
			)
			expect(kmh(s)).toBeCloseTo(-case.expected, 1e-9)
		end
	end)

	it("coasts to a stop with engine braking plus rolling resistance", function()
		local stats = lightStats()
		local world = flatWorld("Concrete")
		local s = newState(CFrame.new())
		run(s, stats, world, input(1), 20)
		local v0 = s.speed / SPM
		local stopped = nil
		run(s, stats, world, input(0), 10, function(i)
			if stopped == nil and s.speed == 0 then
				stopped = i * DT
			end
		end)
		local expected = v0 / (Config.Movement.ENGINE_BRAKE_DECEL_MPS2 + G * 0.1 * 0.8)
		expect(stopped).never.toBeNil()
		expect(math.abs(stopped - expected)).toBeLessThanOrEqual(2 * DT)
		expect(s.speed).toBe(0)
	end)

	it("the brake input stops faster (traction-limited) and holds", function()
		local stats = lightStats()
		local world = flatWorld("Concrete")
		local s = newState(CFrame.new())
		run(s, stats, world, input(1), 20)
		local v0 = s.speed / SPM
		local stopped = nil
		run(s, stats, world, input(1, 0, { brake = true }), 5, function(i)
			if stopped == nil and s.speed == 0 then
				stopped = i * DT
			end
		end)
		local decel = math.min(Config.Movement.BRAKE_DECEL_MPS2, 0.75 * G) + G * 0.1 * 0.8
		expect(math.abs(stopped - v0 / decel)).toBeLessThanOrEqual(2 * DT)
		expect(s.speed).toBe(0)
	end)

	it("reverse throttle brakes first, then reverses (speed is continuous)", function()
		local stats = mediumStats()
		local world = flatWorld("Concrete")
		local s = newState(CFrame.new())
		run(s, stats, world, input(1), 10)
		local previous = s.speed
		local sawZero = false
		run(s, stats, world, input(-1), 10, function()
			expect(s.speed).toBeLessThanOrEqual(previous + 1e-9)
			expect(previous - s.speed).toBeLessThan(10 * DT * SPM) -- never more than 10 m/s² of change
			if s.speed == 0 then
				sawZero = true
			end
			previous = s.speed
		end)
		expect(sawZero).toBe(true)
		expect(kmh(s)).toBeCloseTo(-20, 1e-9)
	end)

	it("never exceeds the top speed downhill, coasting or driving", function()
		local stats = mediumStats()
		local s = newState(CFrame.new(0, 0, 0), {})
		s.yaw = math.pi -- face south = downhill on slopeWorld
		local world = slopeWorld(25)
		local maxSeen = 0
		run(s, stats, world, input(1), 15, function()
			maxSeen = math.max(maxSeen, kmh(s))
		end)
		run(s, stats, world, input(0), 10, function()
			maxSeen = math.max(maxSeen, kmh(s))
		end)
		expect(maxSeen).toBeLessThanOrEqual(50 + 1e-9)
		expect(maxSeen).toBeGreaterThan(49.9)
	end)
end)

--------------------------------------------------------------------------------
-- Slopes (REG-VEH-03)
--------------------------------------------------------------------------------

local function climbGain(angle, stats, seconds)
	local s = newState(CFrame.new(0, 300, 0))
	local world = slopeWorld(angle)
	VehicleSim.settle(s, stats, world)
	local y0 = s.position.Y
	run(s, stats, world, input(1), seconds or 6)
	return s.position.Y - y0, s
end

describe("VehicleSim slopes (REG-VEH-03)", function()
	it("gains no altitude above MAX_CLIMB_DEG", function()
		local limit = Config.Movement.MAX_CLIMB_DEG
		local stats = lightStats()
		for _, angle in { 0, 10, 20, 25, 30, 32, 34, 36, 38, 40, 45, 50, 55, 60 } do
			local gain = climbGain(angle, stats)
			if angle > limit then
				expect(gain).toBeLessThanOrEqual(1e-3)
			elseif angle >= 10 and angle <= 30 then
				expect(gain).toBeGreaterThan(1)
			end
		end
	end)

	it("the climb limit binds even when traction would allow steeper climbs", function()
		local ok = Config.applyOverrides({ Movement = { TRACTION = { hard = 1.2 } } })
		expect(ok).toBeOk()
		local stats = lightStats()
		expect(climbGain(34, stats)).toBeGreaterThan(1)
		for _, angle in { 36, 40, 45 } do
			expect(climbGain(angle, stats)).toBeLessThanOrEqual(1e-3)
		end
		expect(Config.applyOverrides({ Movement = { MAX_CLIMB_DEG = 25 } })).toBeOk()
		expect(climbGain(30, stats)).toBeLessThanOrEqual(1e-3)
		expect(climbGain(20, stats)).toBeGreaterThan(1)
		Config.resetOverrides()
	end)

	it("holds still within the traction limit and slides down beyond it", function()
		local stats = mediumStats()
		local held = newState(CFrame.new(0, 100, 0))
		local world30 = slopeWorld(30)
		VehicleSim.settle(held, stats, world30)
		local p0 = held.position
		run(held, stats, world30, input(0), 5)
		expect(held.position).toBeCloseTo(p0, 1e-6)
		local slid = newState(CFrame.new(0, 100, 0))
		local world50 = slopeWorld(50)
		VehicleSim.settle(slid, stats, world50)
		local y0 = slid.position.Y
		run(slid, stats, world50, input(0), 3)
		expect(slid.position.Y).toBeLessThan(y0 - 5)
		expect(slid.speed).toBeLessThan(0)
	end)

	it("side-slips off slopes steeper than atan(μ) but not off gentler ones", function()
		local stats = mediumStats()
		local function sideWorld(angle)
			local k = math.tan(math.rad(angle))
			return analyticWorld({
				height = function(x)
					return x * k
				end,
			})
		end
		local calm = newState(CFrame.new(0, 50, 0))
		run(calm, stats, sideWorld(30), input(0), 3)
		expect(deg(calm.roll)).toBeCloseTo(30, 1e-3)
		expect(calm.lateralSpeed).toBe(0)
		expect(calm.position.X).toBeCloseTo(0, 1e-6)
		local slipping = newState(CFrame.new(0, 50, 0))
		run(slipping, stats, sideWorld(45), input(0), 3)
		expect(slipping.lateralSpeed).toBeLessThan(0)
		expect(slipping.position.X).toBeLessThan(-3)
		expect(slipping.grounded).toBe(true)
	end)
end)

--------------------------------------------------------------------------------
-- Hull traverse
--------------------------------------------------------------------------------

describe("VehicleSim hull traverse", function()
	it("pivots in place at hullTraverseDegS on hard ground after the response time", function()
		local s = newState(CFrame.new())
		local stats = mediumStats()
		run(s, stats, flatWorld("Concrete"), input(0, 1), DT)
		local response = Config.Movement.HULL_TRAVERSE_RESPONSE_S
		expect(deg(s.yawRate)).toBeCloseTo(36 / response * DT, 1e-9)
		run(s, stats, flatWorld("Concrete"), input(0, 1), 1)
		expect(deg(s.yawRate)).toBeCloseTo(36, 1e-9)
		expect(s.position).toBeCloseTo(Vector3.zero, 1e-6)
		local turned = 0
		local s2 = newState(CFrame.new())
		local before = s2.yaw
		run(s2, stats, flatWorld("Concrete"), input(0, -1), 5, function()
			turned += math.deg(math.atan2(math.sin(s2.yaw - before), math.cos(s2.yaw - before)))
			before = s2.yaw
		end)
		-- 5 s at 36 °/s minus the ramp (≈ rate × response / 2, discretised per tick).
		expect(turned).toBeCloseTo(-(36 * 5 - 36 * response / 2), 1)
	end)

	it("scales the rate by R_hard / R (soft ground turns slower)", function()
		local s = newState(CFrame.new())
		run(s, mediumStats(), flatWorld("Mud"), input(0, 1), 1)
		expect(deg(s.yawRate)).toBeCloseTo(36 * 0.9 / 1.9, 1e-9)
	end)

	it("slows to ×0.6 at top speed", function()
		local s = newState(CFrame.new())
		local stats = lightStats()
		local world = flatWorld("Concrete")
		run(s, stats, world, input(1), 25)
		expect(kmh(s)).toBeCloseTo(60, 1e-9)
		run(s, stats, world, input(1, 1), 0.5)
		expect(kmh(s)).toBeCloseTo(60, 1e-9)
		expect(deg(s.yawRate)).toBeCloseTo(45 * Config.Movement.HULL_TRAVERSE_TOP_SPEED_MUL, 1e-9)
	end)

	it("turns about the inner track without neutral steer (pivot = false)", function()
		local stats = mediumStats({ pivot = false })
		local s = newState(CFrame.new())
		local offset = 3.2 * SPM * Config.Movement.TRACK_CENTRELINE_FRACTION
		-- Clockwise: the right track is the inner one.
		local centre = Vector3.new(offset, 0, 0)
		run(s, stats, flatWorld("Concrete"), input(0, 1), 2)
		expect(deg(s.yaw)).toBeGreaterThan(50)
		local d = s.position - centre
		expect(Vector3.new(d.X, 0, d.Z).Magnitude).toBeCloseTo(offset, 1e-3)
		expect(s.position.Magnitude).toBeGreaterThan(1)
	end)

	it("wheels need speed to turn and follow the turn radius", function()
		local stats = lightStats({ wheeled = wheeledSpec(), pivot = false })
		local world = flatWorld("Concrete")
		local s = newState(CFrame.new())
		run(s, stats, world, input(0, 1), 1)
		expect(s.yawRate).toBe(0)
		expect(s.position).toBeCloseTo(Vector3.zero, 1e-9)
		run(s, stats, world, input(0.2, 0), 10) -- 12 km/h
		local v = s.speed / SPM
		run(s, stats, world, input(0.2, 1), 1)
		local base = math.rad(45) * (1 + (0.6 - 1) * (v / (60 / 3.6)))
		local expected = math.min(base, v / 8)
		expect(s.yawRate).toBeCloseTo(expected, 1e-6)
	end)

	it("does not rotate with the brake held or while immobilised", function()
		local stats = mediumStats()
		local braked = newState(CFrame.new())
		run(braked, stats, flatWorld("Concrete"), input(0, 1, { brake = true }), 1)
		expect(braked.yaw).toBe(0)
		local stuck = newState(CFrame.new())
		stuck.modifiers.immobilized = true
		run(stuck, stats, flatWorld("Concrete"), input(1, 1), 1)
		expect(stuck.yaw).toBe(0)
		expect(stuck.speed).toBe(0)
		expect(stuck.immobileReason).toBe("External")
	end)
end)

--------------------------------------------------------------------------------
-- Modules and immobilisation
--------------------------------------------------------------------------------

describe("VehicleSim module effects and immobilisation", function()
	it("a destroyed track stops translation and rotation until repaired", function()
		local stats = mediumStats()
		local world = flatWorld("Concrete")
		local s = newState(CFrame.new())
		run(s, stats, world, input(1), 5)
		s.modifiers.trackLeft = "Destroyed"
		run(s, stats, world, input(1, 1), 3)
		expect(s.speed).toBe(0)
		expect(s.yawRate).toBe(0)
		expect(s.immobilized).toBe(true)
		expect(s.immobileReason).toBe("Tracks")
		local p = s.position
		run(s, stats, world, input(1, 1), 1)
		expect(s.position).toEqual(p)
		s.modifiers.trackLeft = "Damaged" -- field repair (00-DECISIONS §2: Destroyed -> 50 %)
		run(s, stats, world, input(1), 1)
		expect(s.speed).toBeGreaterThan(0)
		expect(s.immobileReason).toBeNil()
	end)

	it("a damaged engine halves the power, a destroyed one immobilises", function()
		local stats = mediumStats()
		local damaged = newState(CFrame.new())
		damaged.modifiers.engine = "Damaged"
		run(damaged, stats, fastFlatWorld(), input(1), 90)
		local k = 480 * WATTS_PER_HP / 30000 * Config.Movement.ENGINE_DAMAGED_POWER_MUL
		local terminal = k / (G * 0.1 * 1.1)
		expect(math.abs(damaged.speed / SPM - terminal) / terminal).toBeLessThan(0.005)
		local dead = newState(CFrame.new())
		dead.modifiers.engine = "Destroyed"
		run(dead, stats, fastFlatWorld(), input(1, 1), 2)
		expect(dead.speed).toBe(0)
		expect(dead.yaw).toBe(0)
		expect(dead.immobileReason).toBe("Engine")
	end)

	it("wheeled vehicles lose speed per destroyed wheel pair and only stop when all are lost", function()
		local stats = lightStats({ wheeled = wheeledSpec(), pivot = false, enginePowerHp = 900 })
		local world = flatWorld("Concrete")
		local s = newState(CFrame.new())
		s.modifiers.trackLeft = "Destroyed" -- wheels ignore track states
		s.modifiers.lostWheelPairs = 2
		run(s, stats, world, input(1), 20)
		expect(kmh(s)).toBeCloseTo(60 * 0.75 ^ 2, 1e-9)
		s.modifiers.lostWheelPairs = 4
		run(s, stats, world, input(1), 5)
		expect(s.speed).toBe(0)
		expect(s.immobileReason).toBe("Tracks")
	end)

	it("maps DamageModel effects onto the modifiers without counting module damage twice", function()
		local stats = mediumStats()
		local s = newState(CFrame.new())
		s.modifiers.engine = "Damaged"
		s.modifiers.trackLeft = "Destroyed"
		VehicleSim.applyEffects(s, { enginePowerMul = 0.5, topSpeedMul = 1, canMove = true, hullTraverseMul = 0.8 })
		expect(s.modifiers.engine).toBe("Ok")
		expect(s.modifiers.trackLeft).toBe("Ok")
		expect(s.modifiers.powerMul).toBe(0.5)
		expect(s.modifiers.hullTraverseMul).toBe(0.8)
		run(s, stats, fastFlatWorld(), input(1), 90)
		local terminal = 480 * WATTS_PER_HP / 30000 * 0.5 / (G * 0.1 * 1.1) -- half power, not a quarter
		expect(math.abs(s.speed / SPM - terminal) / terminal).toBeLessThan(0.005)
		VehicleSim.applyEffects(s, { enginePowerMul = 1, topSpeedMul = 1, canMove = false, hullTraverseMul = 1 })
		run(s, stats, fastFlatWorld(), input(1), 5)
		expect(s.speed).toBe(0)
		expect(s.immobileReason).toBe("External")
		VehicleSim.applyEffects(s, { enginePowerMul = 0 / 0, topSpeedMul = -1, canMove = true, hullTraverseMul = 1 })
		expect(s.modifiers.powerMul).toBe(1)
		expect(s.modifiers.topSpeedMul).toBe(1)
	end)

	it("applies the runtime speed and traverse multipliers", function()
		local stats = lightStats()
		local world = fastFlatWorld("Concrete")
		local s = newState(CFrame.new())
		s.modifiers.topSpeedMul = 0.5
		run(s, stats, world, input(1), 20)
		expect(kmh(s)).toBeCloseTo(30, 1e-9)
		s.modifiers.speedCapKmh = 10
		run(s, stats, world, input(1), 10)
		expect(kmh(s)).toBeCloseTo(10, 1e-9)
		local t = newState(CFrame.new())
		t.modifiers.hullTraverseMul = 0.5
		run(t, stats, world, input(0, 1), 1)
		expect(deg(t.yawRate)).toBeCloseTo(22.5, 1e-9)
		local p = newState(CFrame.new())
		p.modifiers.powerMul = 0.5
		run(p, mediumStats(), fastFlatWorld(), input(1), 90)
		local terminal = 480 * WATTS_PER_HP / 30000 * 0.5 / (G * 0.1 * 1.1)
		expect(math.abs(p.speed / SPM - terminal) / terminal).toBeLessThan(0.005)
	end)
end)

--------------------------------------------------------------------------------
-- Ground fit
--------------------------------------------------------------------------------

describe("VehicleSim ground fit", function()
	it("pitches on a slope ahead and rolls on a slope across", function()
		local world = slopeWorld(20)
		local stats = mediumStats()
		local north = newState(CFrame.new(0, 50, 0))
		VehicleSim.settle(north, stats, world)
		expect(deg(north.pitch)).toBeCloseTo(20, 1e-3)
		expect(deg(north.roll)).toBeCloseTo(0, 1e-3)
		-- Facing east, the ground rises to the left (north): right side down = negative roll.
		local east = newState(facing(90, Vector3.new(0, 50, 0)))
		VehicleSim.settle(east, stats, world)
		expect(deg(east.pitch)).toBeCloseTo(0, 1e-3)
		expect(deg(east.roll)).toBeCloseTo(-20, 1e-3)
		local cf = VehicleSim.hullCFrame(east)
		expect(cf.RightVector.Y).toBeLessThan(0)
	end)

	it("smooths attitude changes exponentially at GROUND_FIT_RATE", function()
		local slope = 0
		local world = analyticWorld({
			height = function(_x, z)
				return -z * slope
			end,
		})
		local stats = mediumStats()
		local s = newState(CFrame.new())
		run(s, stats, world, input(), 1)
		expect(s.pitch).toBe(0)
		slope = math.tan(math.rad(10))
		VehicleSim.displace(s, Vector3.zero) -- wake the resting vehicle
		local k = 1 - math.exp(-Config.Movement.GROUND_FIT_RATE * DT)
		run(s, stats, world, input(), 3 * DT)
		expect(deg(s.groundPitch)).toBeCloseTo(10, 1e-3)
		expect(deg(s.pitch)).toBeCloseTo(10 * (1 - (1 - k) ^ 3), 0.05)
		run(s, stats, world, input(), 2)
		expect(deg(s.pitch)).toBeCloseTo(10, 1e-3)
	end)

	it("keeps the hull origin above a crest narrower than the contact spacing (REG-VEH-02)", function()
		local world = analyticWorld({
			height = function(_x, z)
				return math.max(0, 4 - 2 * math.abs(z + 40))
			end,
		})
		local stats = mediumStats()
		local s = newState(CFrame.new())
		local maxY = 0
		run(s, stats, world, input(0.3), 12, function()
			local g = world:groundAt(s.position.X, s.position.Z, s.position.Y + 20)
			expect(s.position.Y).toBeGreaterThanOrEqual(g.position.Y - 0.05 * SPM)
			maxY = math.max(maxY, s.position.Y)
		end)
		expect(s.position.Z).toBeLessThan(-60) -- crossed it
		expect(maxY).toBeGreaterThanOrEqual(3.5) -- the centre support rides the peak (sampled once per tick)
	end)

	it("drives over boxes lower than the step height and is blocked by taller ones", function()
		local stats = mediumStats()
		-- A 0.4 m platform 40 studs deep: climbed, driven along level, left again (then the hull settles back).
		local low = flatWorld("Concrete", {
			boxes = { { id = "platform", cframe = CFrame.new(0, 0.6, -60), size = Vector3.new(40, 1.2, 40) } },
		})
		local s = newState(CFrame.new())
		local events = run(s, stats, low, input(0.6), 12, function()
			local z = s.position.Z
			if z < -55 and z > -65 then
				expect(s.position.Y).toBeCloseTo(1.2, 0.05)
				expect(deg(s.pitch)).toBeCloseTo(0, 0.2)
			end
			expect(s.position.Y).toBeLessThan(1.2 + 1.5)
		end)
		expect(s.position.Z).toBeLessThan(-110)
		expect(s.position.Y).toBeCloseTo(0, 1e-3)
		expect(deg(s.pitch)).toBeCloseTo(0, 0.01)
		expect(#eventsOf(events, "Obstacle")).toBe(0)
		local tall = flatWorld("Concrete", {
			boxes = { { id = "wall", cframe = CFrame.new(0, 1.5, -40), size = Vector3.new(40, 3, 6) } },
		})
		local t = newState(CFrame.new())
		local blocked = run(t, stats, tall, input(0.6), 8)
		expect(#eventsOf(blocked, "Obstacle")).toBeGreaterThan(0)
		expect(t.position.Z).toBeGreaterThan(-37 + 3.3 * SPM - 0.1)
		expect(t.position.Y).toBeCloseTo(0, 1e-6)
	end)

	it("is stopped by terrain rises taller than a step, and never climbs them", function()
		local world = analyticWorld({
			height = function(_x, z)
				return if z < -30 then 6 else 0
			end,
		})
		local s = newState(CFrame.new())
		local events = run(s, mediumStats(), world, input(1), 8)
		local obstacles = eventsOf(events, "Obstacle")
		expect(#obstacles).toBeGreaterThan(0)
		expect(obstacles[1].objectId).toBeNil()
		expect(obstacles[1].normal).toBeCloseTo(Vector3.new(0, 0, 1), 1e-6)
		expect(s.position.Y).toBeCloseTo(0, 1e-6)
		expect(s.position.Z).toBeGreaterThan(-30)
		expect(s.speed).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Falling (REG-VEH-11 input)
--------------------------------------------------------------------------------

describe("VehicleSim falling and landing", function()
	it("lands from a 10 m drop at sqrt(2·g·h) (fall-damage input, REG-VEH-11)", function()
		local world = flatWorld("Concrete")
		local stats = mediumStats()
		for _, h in { 2.5, 10, 25 } do
			local s = newState(CFrame.new())
			VehicleSim.settle(s, stats, world)
			s.position = Vector3.new(0, h * SPM, 0)
			s.grounded = false
			local events = run(s, stats, world, input(), 4)
			local landed = eventsOf(events, "Landed")
			expect(#landed).toBe(1)
			expect(landed[1].speedMps).toBeCloseTo(math.sqrt(2 * G * h), 1e-3)
			expect(landed[1].inverted).toBe(false)
			expect(s.position.Y).toBeCloseTo(0, 1e-4)
		end
	end)

	it("drives off a 10 m cliff, tips toward the void, lands and keeps driving", function()
		local world = analyticWorld({
			height = function(_x, z)
				return if z < -30 then -30 else 0
			end,
		})
		local s = newState(CFrame.new())
		local airborneTicks = 0
		local takeoffY, takeoffVy, touchdownY = nil, nil, nil
		local events = run(s, mediumStats(), world, input(1), 6, function(_, evs)
			for _, e in evs do
				if e.kind == "Landed" then
					touchdownY = s.position.Y -- the lowest contact touches first (the hull may still be tilted)
				end
			end
			if not s.grounded then
				airborneTicks += 1
				if takeoffY == nil then
					takeoffY, takeoffVy = s.position.Y, s.verticalVelocity
				end
				expect(math.abs(deg(s.pitch))).toBeLessThanOrEqual(Config.Movement.OVERHANG_MAX_TILT_DEG + 1e-6)
			end
		end)
		local landed = eventsOf(events, "Landed")
		expect(#landed).toBe(1)
		-- Energy between takeoff and touchdown (the hull pivots over the edge before leaving it).
		local g = G * SPM
		local expected = math.sqrt(takeoffVy * takeoffVy + 2 * g * (takeoffY - touchdownY)) / SPM
		expect(landed[1].speedMps).toBeCloseTo(expected, 0.02 * expected)
		expect(landed[1].speedMps).toBeGreaterThan(10)
		expect(landed[1].speedMps).toBeLessThan(15)
		expect(airborneTicks).toBeGreaterThan(15) -- ≈ 0.75 s of flight from the edge
		expect(s.grounded).toBe(true)
		expect(s.position.Y).toBeCloseTo(-30, 1e-3)
		expect(deg(s.pitch)).toBeCloseTo(0, 0.1)
		expect(s.airborneTime).toBe(0)
		expect(s.speed).toBeGreaterThan(0)
	end)

	it("keeps contact over drops shorter than the snap distance", function()
		local world = analyticWorld({
			height = function(_x, z)
				return if z < -30 then -0.5 else 0 -- 0.17 m
			end,
		})
		local s = newState(CFrame.new())
		local events = run(s, mediumStats(), world, input(0.5), 8, function()
			expect(s.grounded).toBe(true)
		end)
		expect(#eventsOf(events, "Landed")).toBe(0)
		expect(s.position.Y).toBeCloseTo(-0.5, 1e-4)
	end)

	it("flies ballistically: horizontal speed is kept while airborne", function()
		local world = analyticWorld({
			height = function(_x, z)
				return if z < -30 then -150 else 0
			end,
		})
		local s = newState(CFrame.new())
		local stats = lightStats()
		local speedAtTakeoff = nil
		run(s, stats, world, input(1), 6, function()
			if not s.grounded then
				speedAtTakeoff = speedAtTakeoff or s.speed
				expect(s.speed).toBe(speedAtTakeoff)
			end
		end)
		expect(speedAtTakeoff).never.toBeNil()
	end)

	it("is lost below the kill plane when there is no ground at all", function()
		local world = {
			groundAt = function()
				return nil
			end,
			sweepBox = function()
				return nil
			end,
			waterDepthAt = function()
				return 0
			end,
		}
		local s = newState(CFrame.new())
		local events = run(s, mediumStats(), world, input(1), 12)
		local fell = eventsOf(events, "FellOut")
		expect(#fell).toBe(1)
		expect(s.wrecked).toBe(true)
		expect(s.immobileReason).toBe("FellOut")
		expect(s.position.Y).toBeCloseTo(Config.Movement.KILL_PLANE_Y_M * SPM, 1e-6)
		local p = s.position
		expect(#VehicleSim.step(s, input(1), mediumStats(), world, DT)).toBe(0)
		expect(s.position).toEqual(p)
	end)
end)

--------------------------------------------------------------------------------
-- Static obstacles
--------------------------------------------------------------------------------

local function overlapsAny(world, s, stats)
	-- Zero-length sweep with the sim's own obstacle box: an initial overlap reports a hit at distance 0.
	local size = VehicleSim.hullSize(s, stats)
	local stepUp = Config.Movement.STEP_HEIGHT_M * SPM
	local height = size.Y - stepUp
	local cf = VehicleSim.hullCFrame(s) * CFrame.new(0, stepUp + height / 2, 0)
	local hit = world:sweepBox(cf, Vector3.new(size.X, height, size.Z), Vector3.zero)
	return hit ~= nil
end

describe("VehicleSim static obstacles", function()
	it("stops at a wall hit head-on and reports the impact", function()
		local world = flatWorld("Concrete", {
			boxes = { { id = "wall", cframe = CFrame.new(0, 5, -60), size = Vector3.new(400, 10, 2) } },
		})
		local stats = mediumStats()
		local s = newState(CFrame.new())
		local events = run(s, stats, world, input(1), 8, function()
			expect(overlapsAny(world, s, stats)).toBe(false)
		end)
		local hits = eventsOf(events, "Obstacle")
		expect(#hits).toBeGreaterThan(0)
		expect(hits[1].objectId).toBe("wall")
		expect(hits[1].normal).toBeCloseTo(Vector3.new(0, 0, 1), 1e-5)
		expect(hits[1].speedMps).toBeGreaterThan(5)
		local front = s.position.Z - 3.3 * SPM
		expect(front).toBeGreaterThanOrEqual(-59 - 1e-3)
		expect(front).toBeLessThan(-58.9)
		expect(s.speed).toBeLessThan(0.5)
	end)

	it("slides along a wall met at a shallow angle", function()
		local world = flatWorld("Concrete", {
			boxes = {
				{
					id = "wall",
					cframe = CFrame.new(12, 5, -60) * CFrame.Angles(0, math.rad(-15), 0),
					size = Vector3.new(2, 10, 400),
				},
			},
		})
		local stats = mediumStats()
		local s = newState(CFrame.new(0, 0, 40))
		local events = run(s, stats, world, input(1), 10, function()
			expect(overlapsAny(world, s, stats)).toBe(false)
		end)
		expect(#eventsOf(events, "Obstacle")).toBeGreaterThan(0)
		-- Progress along the wall direction (sin 15°, -cos 15°) well beyond the contact point.
		local along = s.position.X * math.sin(math.rad(15)) - s.position.Z * math.cos(math.rad(15))
		expect(along).toBeGreaterThan(80)
		expect(kmh(s)).toBeGreaterThan(10)
	end)

	it("reports destructibles with their id, keeps most speed and passes once destroyed (REG-VEH-08)", function()
		local world = flatWorld("Concrete", {
			boxes = {
				{ id = "fence", destructible = true, cframe = CFrame.new(0, 3, -40), size = Vector3.new(40, 6, 1) },
			},
		})
		local stats = mediumStats()
		local s = newState(CFrame.new())
		local hitSpeed, after = nil, nil
		local events = run(s, stats, world, input(1), 5, function(_, evs)
			for _, e in evs do
				if e.kind == "Obstacle" and e.destructible and hitSpeed == nil then
					hitSpeed = e.speedMps
					after = s.speed / SPM
					world:destroyObject(e.objectId)
				end
			end
		end)
		local first = eventsOf(events, "Obstacle")[1]
		expect(first.objectId).toBe("fence")
		expect(first.destructible).toBe(true)
		-- Closing speed kept at DESTRUCTIBLE_SPEED_KEEP (head-on: forward speed = closing speed).
		expect(after).toBeCloseTo(hitSpeed * Config.Movement.DESTRUCTIBLE_SPEED_KEEP, 0.05)
		expect(s.position.Z).toBeLessThan(-60)
		expect(#eventsOf(events, "Obstacle")).toBe(1)
	end)

	it("cannot rotate into a wall alongside", function()
		local stats = mediumStats()
		local half = 1.6 * SPM
		local world = flatWorld("Concrete", {
			boxes = { { id = "wall", cframe = CFrame.new(half + 0.5 + 1, 5, 0), size = Vector3.new(2, 10, 200) } },
		})
		local s = newState(CFrame.new())
		run(s, stats, world, input(0, 1), 2, function()
			expect(overlapsAny(world, s, stats)).toBe(false)
		end)
		-- The front-right corner (r ≈ 11 studs) may swing at most ~0.5 stud into the gap: < 4°.
		expect(math.abs(deg(s.yaw))).toBeLessThan(4)
		run(s, stats, world, input(0, -1), 2, function()
			expect(overlapsAny(world, s, stats)).toBe(false)
		end)
		expect(math.abs(deg(s.yaw))).toBeLessThan(4)
	end)

	it("pushes itself out of an obstacle it was spawned or pushed into (REG-VEH-01)", function()
		local stats = mediumStats()
		local world = flatWorld("Concrete", {
			boxes = { { id = "rock", ground = false, cframe = CFrame.new(6, 5, 0), size = Vector3.new(6, 10, 6) } },
		})
		local s = newState(CFrame.new())
		expect(overlapsAny(world, s, stats)).toBe(true)
		run(s, stats, world, input(0, 0), 3)
		expect(overlapsAny(world, s, stats)).toBe(false)
		expect(s.position.X).toBeLessThan(-1)
		-- Then a push by another vehicle (CollisionSystem) is resolved the same way.
		VehicleSim.displace(s, Vector3.new(3, 0, 0))
		expect(overlapsAny(world, s, stats)).toBe(true)
		run(s, stats, world, input(0, 0), 3)
		expect(overlapsAny(world, s, stats)).toBe(false)
	end)

	it("never leaves the map bounds (REG-VEH-02)", function()
		local bounds = { minX = -60, maxX = 60, minZ = -60, maxZ = 60 }
		local s = newState(CFrame.new(), { bounds = bounds })
		local stats = lightStats()
		run(s, stats, flatWorld("Concrete"), input(1), 8)
		expect(s.position.Z).toBe(-60)
		expect(s.speed).toBe(0)
		run(s, stats, flatWorld("Concrete"), input(1, 0.4), 20, function()
			local p = s.position
			expect(p.X >= -60 and p.X <= 60 and p.Z >= -60 and p.Z <= 60).toBe(true)
		end)
	end)
end)

--------------------------------------------------------------------------------
-- Water (REG-VEH-10)
--------------------------------------------------------------------------------

describe("VehicleSim water and drowning (REG-VEH-10)", function()
	it("fording water slows the vehicle: soft × WATER_RESISTANCE_MUL, speed × WATER_SPEED_MUL", function()
		local world = flatWorld("Grass", { waterLevel = 1.5 }) -- 0.5 m
		local s = newState(CFrame.new())
		run(s, lightStats(), world, input(1), 30)
		expect(s.waterDepthM).toBeCloseTo(0.5, 1e-6)
		expect(s.terrainResistance).toBeCloseTo(1.7 * Config.Movement.WATER_RESISTANCE_MUL, 1e-12)
		expect(kmh(s)).toBeCloseTo(60 * Config.Movement.WATER_SPEED_MUL, 1e-9)
		local m = newState(CFrame.new())
		run(m, mediumStats(), world, input(1), 20)
		local terminal = (480 * WATTS_PER_HP / 30000) / (G * 0.1 * 1.9 * Config.Movement.WATER_RESISTANCE_MUL)
		expect(math.abs(m.speed / SPM - terminal) / terminal).toBeLessThan(0.01)
	end)

	it("starts the drowning timer only at the drown depth (−0.01 / ±0 / +0.01 m)", function()
		local stats = mediumStats()
		for _, case in
			{ { delta = -0.01, drowning = false }, { delta = 0, drowning = true }, { delta = 0.01, drowning = true } }
		do
			local depth = 2 + case.delta
			local world = flatWorld("Concrete", { waterLevel = depth * SPM })
			local s = newState(CFrame.new(), { drownDepthM = 2 })
			local events = run(s, stats, world, input(), 1)
			expect(#eventsOf(events, "Drowning") == 1).toBe(case.drowning)
			expect(s.submerged).toBe(case.drowning) -- DamageModel.updateDrowning input
			if case.drowning then
				expect(s.submergedTime).toBeCloseTo(1, 1e-9)
			else
				expect(s.submergedTime).toBe(0)
			end
		end
	end)

	it("drowns after DROWN_TIME_S with a warning, then is inert", function()
		local world = flatWorld("Concrete", { waterLevel = 12 })
		local s = newState(CFrame.new(), { drownDepthM = 3 })
		local stats = mediumStats()
		local events = run(s, stats, world, input(1), 11)
		local warn = eventsOf(events, "Drowning")
		expect(#warn).toBe(1)
		expect(warn[1].tick).toBe(1)
		expect(warn[1].t).toBe(Config.Movement.DROWN_TIME_S)
		local drowned = eventsOf(events, "Drowned")
		expect(#drowned).toBe(1)
		expect(drowned[1].tick).toBe(math.floor(Config.Movement.DROWN_TIME_S * 30 + 0.5))
		expect(s.drowned).toBe(true)
		expect(s.wrecked).toBe(true)
		expect(s.immobileReason).toBe("Drowned")
		local p = s.position
		expect(#VehicleSim.step(s, input(1), stats, world, DT)).toBe(0)
		expect(s.position).toEqual(p)
	end)

	it("resets the timer when the vehicle leaves deep water", function()
		-- Ground rises 14° toward the north out of a basin with the water 5 m deep at the start.
		local world = analyticWorld({
			waterLevel = -5,
			height = function(_x, z)
				return -0.25 * z - 20
			end,
		})
		local s = newState(CFrame.new(0, -20, 0), { drownDepthM = 3 })
		local events = run(s, mediumStats(), world, input(1), 8)
		expect(#eventsOf(events, "Drowning")).toBe(1)
		expect(#eventsOf(events, "DrowningEnded")).toBe(1)
		expect(#eventsOf(events, "Drowned")).toBe(0)
		expect(s.submergedTime).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Overturn (REG-VEH-05)
--------------------------------------------------------------------------------

local function overturnWorld()
	local k = math.tan(math.rad(75))
	return HeightmapWorld.new({
		groundMaterial = "Concrete",
		height = function(x)
			return x * k
		end,
		boxes = { { id = "stop", ground = false, cframe = CFrame.new(-26, -60, 0), size = Vector3.new(4, 300, 100) } },
	})
end

describe("VehicleSim overturn (REG-VEH-05)", function()
	it("never overturns on flat ground under random inputs (10 simulated minutes)", function()
		local rng = RNG.new(505)
		local world = fastFlatWorld()
		local stats = lightStats()
		local s = newState(CFrame.new())
		local cmd = input()
		for i = 1, 30 * 600 do
			if i % 20 == 1 then
				cmd.throttle = rng:range(-1, 1)
				cmd.steer = rng:range(-1, 1)
				cmd.brake = rng:chance(0.05)
			end
			VehicleSim.step(s, cmd, stats, world, DT)
			expect(s.tiltTime).toBe(0)
		end
		expect(s.overturned).toBe(false)
		expect(s.nanResets).toBe(0)
	end)

	it("overturns after OVERTURN_TIME_S beyond OVERTURN_DEG and self-rights after SELF_RIGHT_S", function()
		local M = Config.Movement
		local stats = mediumStats()
		local timeline = {}
		for runIndex = 1, 2 do
			local s = newState(CFrame.new())
			local world = overturnWorld()
			local events = run(s, stats, world, input(), 3.5)
			expect(s.overturned).toBe(true)
			-- Overturned: immobile, inputs ignored.
			local more = run(s, stats, world, input(1, 1), 13.5, function()
				if s.overturned then
					expect(s.immobilized).toBe(true)
					expect(s.immobileReason).toBe("Overturned")
					expect(s.yawRate).toBe(0)
				end
			end)
			for _, e in more do
				e.tick += 105
				table.insert(events, e)
			end
			local ticks = {}
			for _, e in events do
				if e.kind == "Overturned" or e.kind == "Righted" then
					table.insert(ticks, e.kind .. "@" .. e.tick)
				end
			end
			timeline[runIndex] = table.concat(ticks, ",")
			local over = eventsOf(events, "Overturned")
			expect(over[1].tick).toBe(math.floor(M.OVERTURN_TIME_S * 30 + 0.5))
			expect(over[1].t).toBe(M.SELF_RIGHT_S)
			local righted = eventsOf(events, "Righted")
			expect(righted[1].tick).toBe(over[1].tick + math.floor(M.SELF_RIGHT_S * 30 + 0.5))
			-- Still on a 75° face: it tips again after another OVERTURN_TIME_S.
			expect(over[2].tick).toBe(righted[1].tick + math.floor(M.OVERTURN_TIME_S * 30 + 0.5))
			expect(s.wrecked).toBe(false)
		end
		expect(timeline[1]).toBe(timeline[2])
	end)

	it("the Destroy rule wrecks the vehicle after OVERTURN_DESTROY_S", function()
		local original = Config.Movement
		Config.Movement = setmetatable({ OVERTURN_RULE = "Destroy" }, { __index = original })
		local s = newState(CFrame.new())
		local events = run(s, mediumStats(), overturnWorld(), input(), 14)
		Config.resetOverrides()
		local over = eventsOf(events, "Overturned")
		expect(over[1].t).toBe(original.OVERTURN_DESTROY_S)
		local destroyed = eventsOf(events, "OverturnDestroyed")
		expect(#destroyed).toBe(1)
		expect(destroyed[1].tick).toBe(over[1].tick + math.floor(original.OVERTURN_DESTROY_S * 30 + 0.5))
		expect(s.wrecked).toBe(true)
		expect(#eventsOf(events, "Righted")).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Mechanics (00-DECISIONS §4 placement: VehicleSim)
--------------------------------------------------------------------------------

local function pressMechanic(s, stats, world)
	VehicleSim.step(s, input(0, 0, { mechanic = true }), stats, world, DT)
	VehicleSim.step(s, input(0, 0, { mechanic = false }), stats, world, DT)
end

describe("VehicleSim mechanics", function()
	it("SiegeMode engages over engageS, caps speed, applies its modifiers and disengages", function()
		local siege = {
			kind = "SiegeMode",
			engageS = 2,
			disengageS = 1.25,
			maxSpeedKmh = 10,
			travelReverseRatio = 0.9,
			modifiers = {
				{ stat = "aimTime", op = "mul", value = 0.4 },
				{ stat = "gunDepression", op = "add", value = 8 },
				{ stat = "gunElevation", op = "add", value = 6 },
				{ stat = "hullTraverse", op = "mul", value = 0.5 },
			},
		}
		local stats = mediumStats({ mechanics = { siege }, enginePowerHp = 900 })
		local world = fastFlatWorld("Concrete")
		-- Travel mode: reverse = forward × 0.9 = 45 km/h.
		local travel = newState(CFrame.new())
		run(travel, stats, world, input(-1), 20)
		expect(kmh(travel)).toBeCloseTo(-45, 1e-9)

		local s = newState(CFrame.new())
		local events = run(s, stats, world, input(0, 0, { mechanic = true }), DT)
		expect(s.mechanic.phase).toBe("Engaging")
		expect(eventsOf(events, "MechanicChanged")[1].t).toBe(2)
		run(s, stats, world, input(0, 0, { mechanic = true }), 2) -- held: no re-toggle
		expect(s.mechanic.phase).toBe("On")
		expect(s.mechanicActive).toBe(true)
		expect(s.gunDepressionBonusDeg).toBe(8)
		expect(s.gunElevationBonusDeg).toBe(6)
		run(s, stats, world, input(1, 0), 10)
		expect(kmh(s)).toBeCloseTo(10, 1e-9)
		run(s, stats, world, input(-1, 0), 10)
		expect(kmh(s)).toBeCloseTo(-10, 1e-9)
		run(s, stats, world, input(0, 1), 1)
		expect(deg(s.yawRate)).toBeCloseTo(36 * 0.5, 1e-9)
		pressMechanic(s, stats, world)
		expect(s.mechanic.phase).toBe("Disengaging")
		expect(s.mechanicActive).toBe(false)
		expect(s.gunDepressionBonusDeg).toBe(0)
		run(s, stats, world, input(), 1.25)
		expect(s.mechanic.phase).toBe("Off")
	end)

	it("can be driven by an external mechanic state machine (Vehicle/Mechanics)", function()
		local siege = {
			kind = "SiegeMode",
			engageS = 2,
			disengageS = 1.25,
			maxSpeedKmh = 10,
			modifiers = { { stat = "gunDepression", op = "add", value = 8 } },
		}
		local hydro = { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 }
		local stats = mediumStats({ mechanics = { siege, hydro } })
		local world = fastFlatWorld("Concrete")
		local s = newState(CFrame.new())
		s.mechanic.external = true
		local events = run(s, stats, world, input(0, 0, { mechanic = true }), 3)
		expect(s.mechanic.phase).toBe("Off") -- the key does nothing: the owner drives the phase
		expect(#eventsOf(events, "MechanicChanged")).toBe(0)
		expect(s.gunDepressionBonusDeg).toBe(0) -- still, but hydroActive not set by the owner
		s.mechanic.phase = "On"
		s.mechanic.hydroActive = true
		run(s, stats, world, input(1), 8)
		expect(kmh(s)).toBeCloseTo(10, 1e-9)
		expect(s.mechanicActive).toBe(true)
		expect(s.gunDepressionBonusDeg).toBe(8 + 4) -- siege + hydro (while moving: the owner decides)
		s.mechanic.phase = "Disengaging"
		run(s, stats, world, input(1), 1)
		expect(s.mechanicActive).toBe(false)
		expect(kmh(s)).toBeCloseTo(10, 1e-9) -- the cap holds until Off
		expect(s.mechanic.phase).toBe("Disengaging") -- never advanced by the sim
		local copy = VehicleSim.copyState(s)
		expect(copy.mechanic.external).toBe(true)
		expect(copy.mechanic.hydroActive).toBe(true)
	end)

	it("Hydropneumatic adds its gun bonuses only after settling still", function()
		local hydro = { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 }
		local stats = mediumStats({ mechanics = { hydro } })
		local world = fastFlatWorld("Concrete")
		local s = newState(CFrame.new())
		run(s, stats, world, input(), 0.5)
		expect(s.gunDepressionBonusDeg).toBe(0)
		run(s, stats, world, input(), 0.5)
		expect(s.gunDepressionBonusDeg).toBe(4)
		expect(s.gunElevationBonusDeg).toBe(3)
		expect(s.mechanicActive).toBe(false) -- passive: not a "MechanicActive" mechanic
		run(s, stats, world, input(1), 0.2)
		expect(s.gunDepressionBonusDeg).toBe(0)
	end)

	it("Wheeled speed mode raises the top speed and softens steering after toggleS", function()
		local wheeled = wheeledSpec()
		local spec = {
			kind = "Wheeled",
			wheelPairs = 4,
			speedModeTopSpeedMul = 1.3,
			speedModeSteeringMul = 0.6,
			speedModeReverseMul = 0.7,
			toggleS = 1,
			lostPairSpeedMul = 0.75,
			movingDispersionMul = 1.15,
			turnRadiusM = 8,
		}
		local stats = lightStats({ wheeled = wheeled, pivot = false, mechanics = { spec }, enginePowerHp = 1200 })
		local world = fastFlatWorld("Concrete")
		local s = newState(CFrame.new())
		pressMechanic(s, stats, world)
		expect(s.mechanic.phase).toBe("Engaging")
		run(s, stats, world, input(), 1)
		expect(s.mechanic.phase).toBe("On")
		expect(s.mechanicActive).toBe(true)
		run(s, stats, world, input(1), 40)
		expect(kmh(s)).toBeCloseTo(91, 1e-9)
		run(s, stats, world, input(1, 1), 0.5)
		local v = s.speed / SPM
		local base = math.rad(45) * 0.6 * (1 + (0.6 - 1) * math.min(1, v / (91 / 3.6)))
		expect(s.yawRate).toBeCloseTo(math.min(base, v / 8), 1e-9)
	end)

	it("Turbo multiplies power for its duration, then cools down before it can fire again", function()
		local turbo = { kind = "Turbo", powerMul = 1.25, durationS = 6, cooldownS = 40 }
		local stats = mediumStats({ mechanics = { turbo } })
		local world = fastFlatWorld()
		local s = newState(CFrame.new())
		run(s, stats, world, input(1), 90)
		local base = s.speed
		VehicleSim.step(s, input(1, 0, { mechanic = true }), stats, world, DT)
		expect(s.mechanic.phase).toBe("On")
		run(s, stats, world, input(1), 5.5)
		expect(s.speed).toBeGreaterThan(base * 1.05)
		run(s, stats, world, input(1), 1)
		expect(s.mechanic.phase).toBe("Cooldown")
		pressMechanic(s, stats, world)
		expect(s.mechanic.phase).toBe("Cooldown")
		run(s, stats, world, input(), 40)
		expect(s.mechanic.phase).toBe("Off")
	end)

	it("RocketBoost spends its charges and adds speed while active", function()
		local boost = { kind = "RocketBoost", charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 1 }
		local stats = lightStats({ mechanics = { boost } })
		local world = fastFlatWorld("Concrete")
		local s = newState(CFrame.new())
		run(s, stats, world, input(1), 25)
		expect(kmh(s)).toBeCloseTo(60, 1e-9)
		VehicleSim.step(s, input(1, 0, { mechanic = true }), stats, world, DT)
		expect(s.mechanic.charges).toBe(1)
		run(s, stats, world, input(1), 2)
		expect(kmh(s)).toBeGreaterThan(65)
		expect(kmh(s)).toBeLessThanOrEqual(80 + 1e-9)
		run(s, stats, world, input(1), 2)
		expect(s.mechanic.phase).toBe("Off")
		expect(kmh(s)).toBeCloseTo(60, 1e-6)
		pressMechanic(s, stats, world)
		expect(s.mechanic.charges).toBe(0)
		run(s, stats, world, input(), 4)
		pressMechanic(s, stats, world)
		expect(s.mechanic.phase).toBe("Off") -- no charges left
	end)
end)

--------------------------------------------------------------------------------
-- Determinism and robustness
--------------------------------------------------------------------------------

describe("VehicleSim determinism and robustness", function()
	it("identical inputs give bit-identical states every tick (ARCHITECTURE §13 determinism)", function()
		local worldA = roughWorld(7, 6)
		local worldB = roughWorld(7, 6)
		local stats = mediumStats()
		local a = newState(CFrame.new(10, 0, 10))
		local b = newState(CFrame.new(10, 0, 10))
		local rngA, rngB = RNG.new(99), RNG.new(99)
		local ca, cb = input(), input()
		for i = 1, 450 do
			if i % 30 == 1 then
				ca.throttle, ca.steer = rngA:range(-1, 1), rngA:range(-1, 1)
				cb.throttle, cb.steer = rngB:range(-1, 1), rngB:range(-1, 1)
			end
			VehicleSim.step(a, ca, stats, worldA, DT)
			VehicleSim.step(b, cb, stats, worldB, DT)
			expect(fingerprint(a)).toBe(fingerprint(b))
		end
	end)

	it("copyState replays identically (prediction reconciliation, REG-VEH-07)", function()
		local world = roughWorld(11, 4)
		local stats = mediumStats()
		local server = newState(CFrame.new(-20, 0, 15))
		local rng = RNG.new(3)
		local inputs = {}
		for i = 1, 300 do
			inputs[i] = input(rng:range(-1, 1), rng:range(-1, 1))
		end
		for i = 1, 100 do
			VehicleSim.step(server, inputs[i], stats, world, DT)
		end
		local predicted = VehicleSim.copyState(server)
		expect(fingerprint(predicted)).toBe(fingerprint(server))
		for i = 101, 300 do
			VehicleSim.step(server, inputs[i], stats, world, DT)
			VehicleSim.step(predicted, inputs[i], stats, world, DT)
		end
		expect(fingerprint(predicted)).toBe(fingerprint(server))
		-- Copy into an existing state (no allocation path).
		local reused = newState(CFrame.new())
		expect(VehicleSim.copyState(server, reused)).toBe(reused)
		expect(fingerprint(reused)).toBe(fingerprint(server))
		reused.modifiers.engine = "Destroyed"
		expect(server.modifiers.engine).toBe("Ok") -- modifiers are not shared
	end)

	it("randomized drives never produce NaN, never sink below the ground and never leave the bounds", function()
		local stats = mediumStats()
		local bounds = { minX = -150, maxX = 150, minZ = -150, maxZ = 150 }
		for seed = 1, 3 do
			local world, rng = roughWorld(seed, 8)
			local s = newState(CFrame.new(rng:range(-60, 60), 0, rng:range(-60, 60)), { bounds = bounds })
			local cmd = input()
			for i = 1, 450 do
				if i % 25 == 1 then
					cmd.throttle, cmd.steer = rng:range(-1, 1), rng:range(-1, 1)
					cmd.brake = rng:chance(0.05)
				end
				VehicleSim.step(s, cmd, stats, world, DT)
				local p = s.position
				expect(isFinite(p.X) and isFinite(p.Y) and isFinite(p.Z)).toBe(true)
				expect(isFinite(s.speed) and isFinite(s.yaw) and isFinite(s.pitch) and isFinite(s.roll)).toBe(true)
				expect(p.X >= -150 and p.X <= 150 and p.Z >= -150 and p.Z <= 150).toBe(true)
				if s.grounded then
					local g = world:groundAt(p.X, p.Z, p.Y + 0.15 * SPM)
					if g ~= nil then
						expect(p.Y).toBeGreaterThanOrEqual(g.position.Y - 0.05 * SPM)
					end
				end
				if s.wrecked then
					break
				end
			end
			expect(s.nanResets).toBe(0)
		end
	end)

	it("garbage inputs, stats and time steps never break the state (REG-NET-05)", function()
		local rng = RNG.new(42)
		local world = fastFlatWorld()
		local garbage = { 0 / 0, math.huge, -math.huge, 1e300, -1e300, "1", true, {}, nil, 0.5, -0.5 }
		local s = newState(CFrame.new())
		local stats = mediumStats()
		for i = 1, 600 do
			local cmd = {
				seq = garbage[rng:int(1, #garbage)],
				throttle = garbage[rng:int(1, #garbage)],
				steer = garbage[rng:int(1, #garbage)],
				aimPoint = Vector3.new(0 / 0, 0, 0),
				brake = garbage[rng:int(1, #garbage)],
				mechanic = garbage[rng:int(1, #garbage)],
			}
			local dt = if i % 50 == 0 then garbage[rng:int(1, 5)] else DT
			if type(dt) ~= "number" then
				dt = DT
			end
			VehicleSim.step(s, cmd, stats, world, dt)
			expect(isFinite(s.position.X) and isFinite(s.position.Y) and isFinite(s.position.Z)).toBe(true)
			expect(isFinite(s.speed) and isFinite(s.yaw)).toBe(true)
			expect(math.abs(kmh(s))).toBeLessThanOrEqual(Config.Movement.ABSOLUTE_MAX_SPEED_KMH)
		end
		expect(s.nanResets).toBe(0)
		-- Broken stats fall back to safe values.
		local broken =
			mediumStats({ massKg = 0 / 0, enginePowerHp = math.huge, topSpeedKmh = -5, hullTraverseDegS = 0 / 0 })
		local b = newState(CFrame.new())
		run(b, broken, world, input(1, 1), 2)
		expect(isFinite(b.speed) and isFinite(b.yaw)).toBe(true)
		expect(b.speed).toBe(0) -- negative top speed -> cap 0
	end)

	it("treats dt <= 0 and NaN as no-ops and clamps huge steps to MAX_DT_S", function()
		local world = flatWorld("Concrete")
		local stats = mediumStats()
		local s = newState(CFrame.new())
		run(s, stats, world, input(1), 2)
		local before = fingerprint(s)
		for _, dt in { 0, -1, 0 / 0 } do
			expect(#VehicleSim.step(s, input(1), stats, world, dt)).toBe(0)
			expect(fingerprint(s)).toBe(before)
		end
		local a = VehicleSim.copyState(s)
		local b = VehicleSim.copyState(s)
		VehicleSim.step(a, input(1), stats, world, 1000)
		VehicleSim.step(b, input(1), stats, world, Config.Movement.MAX_DT_S)
		expect(fingerprint(a)).toBe(fingerprint(b))
	end)
end)

--------------------------------------------------------------------------------
-- Input sanitising
--------------------------------------------------------------------------------

describe("VehicleSim.sanitizeInput", function()
	local bounds = { minX = -300, maxX = 300, minZ = -300, maxZ = 300 }

	it("passes valid commands through unchanged", function()
		local raw = input(0.5, -0.25, { seq = 12, aimPoint = Vector3.new(10, 5, -20), fire = true, brake = true })
		local cmd, valid = VehicleSim.sanitizeInput(raw, nil, bounds)
		expect(valid).toBe(true)
		expect(cmd).toEqual(raw)
		expect(cmd).never.toBe(raw)
	end)

	it("clamps axes and flags out-of-range or non-finite values", function()
		local cmd, valid = VehicleSim.sanitizeInput(input(1.5, -7, { seq = 1 }), nil, bounds)
		expect(valid).toBe(false)
		expect(cmd.throttle).toBe(1)
		expect(cmd.steer).toBe(-1)
		local nan, ok = VehicleSim.sanitizeInput(input(0 / 0, math.huge, { seq = -1 }), nil, bounds)
		expect(ok).toBe(false)
		expect(nan.throttle).toBe(0)
		expect(nan.steer).toBe(0)
		expect(nan.seq).toBe(0)
		local _, fractional = VehicleSim.sanitizeInput(input(0, 0, { seq = 1.5 }), nil, bounds)
		expect(fractional).toBe(false)
	end)

	it("replaces non-finite aim points and clamps far ones", function()
		local fallback = Vector3.new(1, 2, 3)
		local cmd, valid =
			VehicleSim.sanitizeInput(input(0, 0, { aimPoint = Vector3.new(0 / 0, 0, 0) }), nil, bounds, fallback)
		expect(valid).toBe(false)
		expect(cmd.aimPoint).toEqual(fallback)
		local far, ok = VehicleSim.sanitizeInput(input(0, 0, { aimPoint = Vector3.new(1e9, -1e9, 0) }), nil, bounds)
		expect(ok).toBe(false)
		local margin = Config.Movement.AIM_POINT_MARGIN_M * SPM
		expect(far.aimPoint.X).toBe(300 + margin)
		expect(far.aimPoint.Y).toBe(-Config.Movement.MAX_AIM_HEIGHT_M * SPM)
		local missing, ok2 = VehicleSim.sanitizeInput({ seq = 1, throttle = 0, steer = 0 }, nil, bounds, fallback)
		expect(ok2).toBe(false)
		expect(missing.aimPoint).toEqual(fallback)
	end)

	it("rejects non-tables and wrongly typed flags", function()
		for _, raw in { nil, 5, "input", true } do
			local cmd, valid = VehicleSim.sanitizeInput(raw, nil, bounds)
			expect(valid).toBe(false)
			expect(cmd.throttle).toBe(0)
			expect(cmd.fire).toBe(false)
		end
		local cmd, valid = VehicleSim.sanitizeInput(input(0, 0, { fire = 1, brake = "yes" }), nil, bounds)
		expect(valid).toBe(false)
		expect(cmd.fire).toBe(false)
		expect(cmd.brake).toBe(false)
	end)

	it("reuses the output table", function()
		local out = VehicleSim.neutralInput()
		local cmd = VehicleSim.sanitizeInput(input(0.3, 0.2), out, bounds)
		expect(cmd).toBe(out)
		expect(out.throttle).toBe(0.3)
		VehicleSim.sanitizeInput("garbage", out, bounds)
		expect(out.throttle).toBe(0)
	end)
end)

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

describe("VehicleSim helpers", function()
	it("hullCFrame follows the yaw/pitch/roll conventions", function()
		local s = newState(CFrame.new(1, 2, 3))
		s.yaw = math.rad(90)
		expect(VehicleSim.hullCFrame(s).LookVector).toBeCloseTo(Vector3.new(1, 0, 0), 1e-6)
		s.yaw, s.pitch = 0, math.rad(10)
		expect(VehicleSim.hullCFrame(s).LookVector.Y).toBeCloseTo(math.sin(math.rad(10)), 1e-6)
		s.pitch, s.roll = 0, math.rad(15)
		expect(VehicleSim.hullCFrame(s).RightVector.Y).toBeCloseTo(math.sin(math.rad(15)), 1e-6)
		expect(VehicleSim.hullCFrame(s).Position).toBeCloseTo(Vector3.new(1, 2, 3), 1e-6)
	end)

	it("velocity() matches the displacement per tick", function()
		local s = newState(CFrame.new())
		local stats = mediumStats()
		local world = flatWorld("Concrete")
		run(s, stats, world, input(1, 0.5), 3)
		local p0 = s.position
		VehicleSim.step(s, input(1, 0.5), stats, world, DT)
		local v = VehicleSim.velocity(s)
		local moved = (s.position - p0) / DT
		expect((v - moved).Magnitude).toBeLessThan(0.05 * v.Magnitude)
	end)

	it("applyVelocityChange splits a world impulse into forward and side speed", function()
		local s = newState(CFrame.new())
		VehicleSim.applyVelocityChange(s, Vector3.new(0, 0, -6))
		expect(s.speed).toBeCloseTo(6, 1e-9)
		VehicleSim.applyVelocityChange(s, Vector3.new(3, 0, 0))
		expect(s.lateralSpeed).toBeCloseTo(3, 1e-9)
		expect(VehicleSim.velocity(s)).toBeCloseTo(Vector3.new(3, 0, -6), 1e-6)
		VehicleSim.applyVelocityChange(s, Vector3.new(0 / 0, 0, 0))
		expect(s.speed).toBeCloseTo(6, 1e-9)
		s.grounded = false
		VehicleSim.applyVelocityChange(s, Vector3.new(0, 5, 0))
		expect(s.verticalVelocity).toBe(5)
	end)

	it("displace and teleport move the hull inside the bounds and re-settle it", function()
		local bounds = { minX = -30, maxX = 30, minZ = -30, maxZ = 30 }
		local s = newState(CFrame.new(), { bounds = bounds })
		VehicleSim.displace(s, Vector3.new(100, 50, 0))
		expect(s.position).toEqual(Vector3.new(30, 0, 0)) -- grounded: vertical ignored
		local world = slopeWorld(10)
		VehicleSim.teleport(s, Vector3.new(-10, 99, 5), math.rad(45))
		expect(deg(s.yaw)).toBeCloseTo(45, 1e-9)
		VehicleSim.step(s, input(), mediumStats(), world, DT)
		expect(s.position.Y).toBeCloseTo(-5 * math.tan(math.rad(10)), 1e-3)
	end)

	it("a resting vehicle stops probing the world and re-probes every REST_REPROBE_S", function()
		local world = fastFlatWorld()
		local stats = mediumStats()
		local s = newState(CFrame.new())
		run(s, stats, world, input(), 1)
		local calls = world.calls
		run(s, stats, world, input(), 1)
		local perSecond = world.calls - calls
		local probesPerSecond = math.ceil(1 / Config.Movement.REST_REPROBE_S)
		expect(perSecond).toBeLessThanOrEqual(probesPerSecond * #s._contactX)
		-- Any input wakes it immediately.
		calls = world.calls
		VehicleSim.step(s, input(0, 1), stats, world, DT)
		expect(world.calls).toBeGreaterThan(calls)
	end)

	it("notices ground destroyed under a resting vehicle within REST_REPROBE_S (REG-VEH-08)", function()
		local world = flatWorld("Concrete", {
			boxes = {
				{ id = "deck", destructible = false, cframe = CFrame.new(0, -1, 0), size = Vector3.new(60, 2, 60) },
			},
		})
		world._height = function()
			return -30
		end
		local s = newState(CFrame.new(0, 5, 0))
		run(s, mediumStats(), world, input(), 1)
		expect(s.position.Y).toBeCloseTo(0, 1e-4)
		world._boxes[1].destructible = true
		world:destroyObject("deck")
		local fellAt = nil
		run(s, mediumStats(), world, input(), 1, function(i)
			if fellAt == nil and not s.grounded then
				fellAt = i * DT
			end
		end)
		expect(fellAt).never.toBeNil()
		expect(fellAt).toBeLessThanOrEqual(Config.Movement.REST_REPROBE_S + DT)
	end)
end)
