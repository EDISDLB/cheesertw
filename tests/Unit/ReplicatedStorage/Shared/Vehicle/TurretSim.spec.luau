-- TurretSim: turret/gun drives, limits, ballistic laying and the aim ray (ARCHITECTURE §6.1 step 3; 00-DECISIONS §2
-- "Ring traverse ×.5 / none", §3 "Arcs: default −8°/+20°, casemate yaw ±11°", §4 Hydropneumatic/SiegeMode bonuses).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local TurretSim = require("@game/ReplicatedStorage/Shared/Vehicle/TurretSim")
local VehicleSim = require("@game/ReplicatedStorage/Shared/Vehicle/VehicleSim")

local DT = 1 / 30
local SPM = 3

local PIVOTS = {
	turretRing = CFrame.new(0, 6, 0),
	gunTrunnion = CFrame.new(0, 1.5, -2),
	muzzle = CFrame.new(0, 0, -12),
	viewPoint = Vector3.new(0, 2.5, 0),
	camoPoints = {},
	trackContacts = { left = {}, right = {} },
	exhausts = {},
	hullSize = Vector3.new(9, 7, 20),
}

local function gunStats(overrides)
	local gun = {
		id = "test_gun",
		caliberMm = 85,
		depressionDeg = 8,
		elevationDeg = 20,
		arcSectors = {},
		indirect = false,
		shells = {},
	}
	for k, v in overrides or {} do
		gun[k] = v
	end
	return gun
end

local function turretStats(overrides, gunOverrides)
	local stats = {
		vehicleId = "test",
		turretMount = "Turret",
		turretTraverseDegS = 40,
		yawLimitsDeg = nil,
		gun = gunStats(gunOverrides),
	}
	for k, v in overrides or {} do
		stats[k] = v
	end
	return stats
end

local function casemateStats(gunOverrides)
	return turretStats(
		{ turretMount = "Casemate", turretTraverseDegS = 30, yawLimitsDeg = { left = 11, right = 11 } },
		gunOverrides
	)
end

-- World point at hull-relative bearing/elevation (deg) and distance (studs) from the trunnion at that bearing.
local function aimAt(hullCFrame, bearingDeg, elevationDeg, distance)
	local ring = hullCFrame * PIVOTS.turretRing
	local trunnion = ring * CFrame.Angles(0, -math.rad(bearingDeg), 0) * PIVOTS.gunTrunnion
	local e = math.rad(elevationDeg)
	local local_ = Vector3.new(0, math.sin(e), -math.cos(e)) * distance
	return trunnion:PointToWorldSpace(local_)
end

-- World point `distance` studs from the trunnion along WORLD elevation `elevationDeg` on the hull's heading plane.
local function aimWorldElevation(hullCFrame, bearingDeg, elevationDeg, distance)
	local ring = hullCFrame * PIVOTS.turretRing
	local trunnion = (ring * CFrame.Angles(0, -math.rad(bearingDeg), 0) * PIVOTS.gunTrunnion).Position
	local look = (hullCFrame * CFrame.Angles(0, -math.rad(bearingDeg), 0)).LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local e = math.rad(elevationDeg)
	return trunnion + (flat * math.cos(e) + Vector3.yAxis * math.sin(e)) * distance
end

local function steps(turret, aim, hull, stats, seconds, hold, vehicle, onStep)
	local n = math.floor(seconds * 30 + 0.5)
	local last = 0
	for i = 1, n do
		last = TurretSim.step(turret, aim, hold == true, hull, stats, PIVOTS, DT, vehicle)
		if onStep then
			onStep(i, last)
		end
	end
	return last
end

-- Signed angular distance a - b in degrees, wrapped to (-180, 180].
local function angleDiff(a, b)
	local d = (a - b + 180) % 360 - 180
	return if d == -180 then 180 else d
end

local function worldElevationOfBarrel(turret, hull, stats)
	local _, dir = TurretSim.aimRay(turret, hull, stats, PIVOTS)
	return math.deg(math.asin(dir.Y))
end

describe("TurretSim construction", function()
	it("starts centred, enabled, with neutral modifiers", function()
		local t = TurretSim.newState()
		expect(t.turretYawDeg).toBe(0)
		expect(t.gunYawDeg).toBe(0)
		expect(t.gunPitchDeg).toBe(0)
		expect(t.modifiers).toEqual(TurretSim.newModifiers())
		expect(t.modifiers.enabled).toBe(true)
		expect(t.modifiers.ring).toBe("Ok")
		expect(t.modifiers.shellVelocityMps).toBe(0)
		TurretSim.setShell(t, 480, 19.62)
		expect(t.modifiers.shellVelocityMps).toBe(480)
		expect(t.modifiers.shellGravityMps2).toBe(19.62)
		TurretSim.setShell(t, 0 / 0, -1)
		expect(t.modifiers.shellVelocityMps).toBe(0)
		expect(t.modifiers.shellGravityMps2).toBe(0)
	end)
end)

describe("TurretSim traverse", function()
	it("turns at turretTraverseDegS and reports the bearing speed", function()
		local t = TurretSim.newState()
		local stats = turretStats()
		local aim = aimAt(CFrame.new(), 90, 0, 300)
		local speed = steps(t, aim, CFrame.new(), stats, 1)
		expect(t.turretYawDeg).toBeCloseTo(40, 1e-6)
		expect(speed).toBeCloseTo(40, 1e-6)
		expect(t.bearingSpeedDegS).toBeCloseTo(40, 1e-6)
		steps(t, aim, CFrame.new(), stats, 1.5)
		expect(t.turretYawDeg).toBeCloseTo(90, 1e-3)
		expect(TurretSim.step(t, aim, false, CFrame.new(), stats, PIVOTS, DT)).toBeCloseTo(0, 1e-3)
		expect(t.desiredBearingDeg).toBeCloseTo(90, 1e-3)
	end)

	it("takes the short way through 180°", function()
		local t = TurretSim.newState()
		t.turretYawDeg = 170
		local stats = turretStats()
		local aim = aimAt(CFrame.new(), -170, 0, 300)
		steps(t, aim, CFrame.new(), stats, 0.6, false, nil, function()
			expect(math.abs(t.turretYawDeg)).toBeGreaterThanOrEqual(169.999)
		end)
		expect(angleDiff(t.turretYawDeg, -170)).toBeCloseTo(0, 0.05)
	end)

	it("is halved by a damaged ring, stopped by a destroyed one, and scaled by traverseMul", function()
		local stats = turretStats()
		local aim = aimAt(CFrame.new(), 90, 0, 300)
		local damaged = TurretSim.newState()
		damaged.modifiers.ring = "Damaged"
		steps(damaged, aim, CFrame.new(), stats, 1)
		expect(damaged.turretYawDeg).toBeCloseTo(40 * Config.Movement.TURRET_RING_DAMAGED_MUL, 1e-6)
		local jammed = TurretSim.newState()
		jammed.modifiers.ring = "Destroyed"
		steps(jammed, aim, CFrame.new(), stats, 1)
		expect(jammed.turretYawDeg).toBe(0)
		expect(jammed.bearingSpeedDegS).toBe(0)
		local crew = TurretSim.newState()
		crew.modifiers.traverseMul = 0.75
		steps(crew, aim, CFrame.new(), stats, 1)
		expect(crew.turretYawDeg).toBeCloseTo(30, 1e-6)
	end)

	it("maps DamageModel effects (turretTraverseMul) without counting ring damage twice", function()
		local stats = turretStats()
		local t = TurretSim.newState()
		t.modifiers.ring = "Damaged"
		TurretSim.applyEffects(t, { turretTraverseMul = 0.5 })
		expect(t.modifiers.ring).toBe("Ok")
		steps(t, aimAt(CFrame.new(), 90, 0, 300), CFrame.new(), stats, 1)
		expect(t.turretYawDeg).toBeCloseTo(20, 1e-6)
		TurretSim.applyEffects(t, { turretTraverseMul = 0 })
		local yaw = t.turretYawDeg
		steps(t, aimAt(CFrame.new(), 90, 0, 300), CFrame.new(), stats, 1)
		expect(t.turretYawDeg).toBe(yaw)
	end)

	it("holds its hull-relative angles in free look but keeps tracking the desired direction", function()
		local t = TurretSim.newState()
		local stats = turretStats()
		local aim = aimAt(CFrame.new(), 45, 5, 300)
		steps(t, aim, CFrame.new(), stats, 1, true)
		expect(t.turretYawDeg).toBe(0)
		expect(t.gunPitchDeg).toBe(0)
		-- Measured from the trunnion where it is now (2 studs ahead of the ring): small parallax at 300 studs.
		expect(t.desiredBearingDeg).toBeCloseTo(45, 0.5)
		expect(t.aimErrorDeg).toBeGreaterThan(40)
		expect(TurretSim.onTarget(t)).toBe(false)
	end)

	it("stops at the nearer limit of a limited turret without crossing the dead zone", function()
		local stats = turretStats({ yawLimitsDeg = { left = 120, right = 120 } })
		local t = TurretSim.newState()
		t.turretYawDeg = -110
		local aim = aimAt(CFrame.new(), 110, 0, 300)
		local previous = t.turretYawDeg
		steps(t, aim, CFrame.new(), stats, 7, false, nil, function()
			expect(t.turretYawDeg).toBeGreaterThanOrEqual(previous) -- monotonic through 0, never through 180
			previous = t.turretYawDeg
		end)
		expect(t.turretYawDeg).toBeCloseTo(110, 1e-3)
		local behind = aimAt(CFrame.new(), 170, 0, 300)
		steps(t, behind, CFrame.new(), stats, 2)
		expect(t.turretYawDeg).toBeCloseTo(120, 1e-6)
		expect(t.outOfArc).toBe(true)
		local behindLeft = aimAt(CFrame.new(), -175, 0, 300)
		steps(t, behindLeft, CFrame.new(), stats, 8)
		expect(t.turretYawDeg).toBeCloseTo(-120, 1e-6)
	end)
end)

describe("TurretSim casemate mounts (00-DECISIONS §3 ±11°)", function()
	it("keeps the superstructure fixed and yaws the gun inside its arc", function()
		local stats = casemateStats()
		local t = TurretSim.newState()
		local aim = aimAt(CFrame.new(), 30, 0, 600)
		steps(t, aim, CFrame.new(), stats, 2)
		expect(t.turretYawDeg).toBe(0)
		expect(t.gunYawDeg).toBeCloseTo(11, 1e-6)
		expect(t.outOfArc).toBe(true)
		expect(TurretSim.autoHullSteer(t, stats)).toBe(1)
		local inside = aimAt(CFrame.new(), 6, 0, 600)
		steps(t, inside, CFrame.new(), stats, 1)
		expect(t.outOfArc).toBe(false)
		expect(TurretSim.autoHullSteer(t, stats)).toBe(0)
		expect(t.aimErrorDeg).toBeLessThan(0.1)
		expect(TurretSim.onTarget(t)).toBe(true)
	end)

	it("suggests a proportional hull steer toward aims just outside the arc", function()
		local stats = casemateStats()
		local t = TurretSim.newState()
		steps(t, aimAt(CFrame.new(), 13, 0, 3000), CFrame.new(), stats, 1)
		local excess = t.desiredBearingDeg - 11
		expect(TurretSim.autoHullSteer(t, stats)).toBeCloseTo(excess / Config.Movement.AUTO_HULL_TURN_FULL_DEG, 1e-6)
		steps(t, aimAt(CFrame.new(), -170, 0, 600), CFrame.new(), stats, 2)
		expect(t.gunYawDeg).toBeCloseTo(-11, 1e-6)
		expect(TurretSim.autoHullSteer(t, stats)).toBe(-1)
	end)

	it("defaults missing casemate limits to CASEMATE_DEFAULT_YAW_DEG", function()
		local stats = casemateStats()
		stats.yawLimitsDeg = nil
		local limited, left, right = TurretSim.yawRange(stats)
		expect(limited).toBe(true)
		expect(left).toBe(Config.Movement.CASEMATE_DEFAULT_YAW_DEG)
		expect(right).toBe(Config.Movement.CASEMATE_DEFAULT_YAW_DEG)
		expect(TurretSim.yawRange(turretStats())).toBe(false)
		expect(TurretSim.yawRange(turretStats({ yawLimitsDeg = { left = 180, right = 180 } }))).toBe(false)
	end)
end)

describe("TurretSim elevation and limits", function()
	it("elevates at GUN_ELEVATION_SPEED_DEGS and stops at the depression/elevation limits", function()
		local stats = turretStats()
		local t = TurretSim.newState()
		steps(t, aimAt(CFrame.new(), 0, -30, 300), CFrame.new(), stats, 0.2)
		expect(t.gunPitchDeg).toBeCloseTo(-Config.Movement.GUN_ELEVATION_SPEED_DEGS * 0.2, 1e-6)
		steps(t, aimAt(CFrame.new(), 0, -30, 300), CFrame.new(), stats, 1)
		expect(t.gunPitchDeg).toBeCloseTo(-8, 1e-6)
		expect(t.outOfElevation).toBe(true)
		steps(t, aimAt(CFrame.new(), 0, 45, 300), CFrame.new(), stats, 3)
		expect(t.gunPitchDeg).toBeCloseTo(20, 1e-6)
		expect(t.outOfElevation).toBe(true)
		steps(t, aimAt(CFrame.new(), 0, 7, 300), CFrame.new(), stats, 1)
		expect(t.gunPitchDeg).toBeCloseTo(7, 1e-3)
		expect(t.outOfElevation).toBe(false)
	end)

	it(
		"evaluates limits in the hull frame: a nose-up hull cannot depress as far in world terms (reverse slope)",
		function()
			local stats = turretStats()
			-- Hull-down behind a crest, nose up 10°: a target 5° below the horizon needs −15° of hull-relative depression.
			local noseUp = CFrame.fromEulerAnglesYXZ(math.rad(10), 0, 0)
			local t = TurretSim.newState()
			steps(t, aimWorldElevation(noseUp, 0, -5, 600), noseUp, stats, 2)
			expect(t.gunPitchDeg).toBeCloseTo(-8, 1e-6)
			expect(t.outOfElevation).toBe(true)
			expect(worldElevationOfBarrel(t, noseUp, stats)).toBeCloseTo(2, 1e-3)
			-- Facing the rear on the same hull, the tail is low: −15° in the world is only −5° for the gun.
			local r = TurretSim.newState()
			steps(r, aimWorldElevation(noseUp, 180, -15, 600), noseUp, stats, 6)
			expect(angleDiff(r.turretYawDeg, 180)).toBeCloseTo(0, 1e-3)
			expect(r.outOfElevation).toBe(false)
			expect(r.gunPitchDeg).toBeCloseTo(-5, 0.05)
			expect(worldElevationOfBarrel(r, noseUp, stats)).toBeCloseTo(-15, 0.05)
			-- Nose down 10° (cresting forward): −15° in the world is −5° for the gun.
			local noseDown = CFrame.fromEulerAnglesYXZ(math.rad(-10), 0, 0)
			local d = TurretSim.newState()
			steps(d, aimWorldElevation(noseDown, 0, -15, 600), noseDown, stats, 2)
			expect(d.outOfElevation).toBe(false)
			expect(worldElevationOfBarrel(d, noseDown, stats)).toBeCloseTo(-15, 0.05)
		end
	)

	it("applies arc sectors (rear deck) with wrap-around and lifts the gun over the deck", function()
		local sector = { fromDeg = 150, toDeg = -150, depressionDeg = 2, elevationDeg = 15 }
		local stats = turretStats(nil, { arcSectors = { sector } })
		for _, case in
			{
				{ b = 0, dep = 8, elev = 20 },
				{ b = 149, dep = 8, elev = 20 },
				{ b = 150, dep = 2, elev = 15 },
				{ b = 179, dep = 2, elev = 15 },
				{ b = 180, dep = 2, elev = 15 },
				{ b = -179, dep = 2, elev = 15 },
				{ b = -150, dep = 2, elev = 15 },
				{ b = -149, dep = 8, elev = 20 },
			}
		do
			local dep, elev = TurretSim.limitsAt(stats, case.b)
			expect(dep).toBe(case.dep)
			expect(elev).toBe(case.elev)
		end
		local dep, elev = TurretSim.limitsAt(stats, 0, 4, 3)
		expect(dep).toBe(12)
		expect(elev).toBe(23)
		-- Rotating over the deck with the gun depressed: inside the sector the gun is never below −2°.
		local t = TurretSim.newState()
		t.turretYawDeg = 140
		t.gunPitchDeg = -8
		steps(t, aimAt(CFrame.new(), 180, -8, 300), CFrame.new(), stats, 2, false, nil, function()
			if math.abs(t.turretYawDeg) >= 150 then
				expect(t.gunPitchDeg).toBeGreaterThanOrEqual(-2)
			end
		end)
		expect(angleDiff(t.turretYawDeg, 180)).toBeCloseTo(0, 1e-3)
		expect(t.gunPitchDeg).toBeCloseTo(-2, 1e-6)
		expect(t.outOfElevation).toBe(true)
	end)

	it("adds the vehicle's mechanic bonuses and freezes while the vehicle is overturned or wrecked", function()
		local stats = turretStats()
		local vehicle = VehicleSim.newState(CFrame.new())
		vehicle.gunDepressionBonusDeg = 4 -- Hydropneumatic settled
		local t = TurretSim.newState()
		steps(t, aimAt(CFrame.new(), 0, -30, 300), CFrame.new(), stats, 2, false, vehicle)
		expect(t.gunPitchDeg).toBeCloseTo(-12, 1e-6)
		vehicle.gunDepressionBonusDeg = 0
		TurretSim.step(t, aimAt(CFrame.new(), 0, -30, 300), false, CFrame.new(), stats, PIVOTS, DT, vehicle)
		expect(t.gunPitchDeg).toBeCloseTo(-8, 1e-6) -- bonus gone: clamped back at once
		vehicle.overturned = true
		local before = t.turretYawDeg
		steps(t, aimAt(CFrame.new(), 90, 0, 300), CFrame.new(), stats, 1, false, vehicle)
		expect(t.turretYawDeg).toBe(before)
		expect(t.bearingSpeedDegS).toBe(0)
		vehicle.overturned = false
		t.modifiers.enabled = false
		steps(t, aimAt(CFrame.new(), 90, 0, 300), CFrame.new(), stats, 1, false, vehicle)
		expect(t.turretYawDeg).toBe(before)
	end)
end)

describe("TurretSim ballistic laying", function()
	it("solves the low arc so the shell reaches the aim point", function()
		local v, g = 300, 19.62
		local x = 300 -- m
		local expected = math.deg(0.5 * math.asin(g * x / (v * v)))
		local stats = turretStats()
		local t = TurretSim.newState()
		TurretSim.setShell(t, v, g)
		local aim = aimAt(CFrame.new(), 0, 0, x * SPM)
		steps(t, aim, CFrame.new(), stats, 1)
		-- ≈ the closed form from the trunnion (the muzzle is 4 m along the barrel, a small correction).
		expect(t.desiredPitchDeg).toBeCloseTo(expected, 0.1)
		expect(t.gunPitchDeg).toBeCloseTo(t.desiredPitchDeg, 1e-6)
		expect(t.reachable).toBe(true)
		-- Fly the shell from the muzzle along the barrel: it passes the aim point's range at the aim height.
		local origin, dir = TurretSim.aimRay(t, CFrame.new(), stats, PIVOTS)
		local horizontal = Vector3.new(dir.X, 0, dir.Z).Magnitude
		local range = (Vector3.new(aim.X, 0, aim.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude / SPM
		local time = range / (v * horizontal)
		local y = origin.Y / SPM + v * dir.Y * time - 0.5 * g * time * time
		expect(y).toBeCloseTo(aim.Y / SPM, 0.01)
	end)

	it("uses the high arc for indirect guns and flags unreachable aims", function()
		local v, g = 300, 19.62
		local x = 4000
		local stats = turretStats(nil, { indirect = true, elevationDeg = 85 })
		local t = TurretSim.newState()
		TurretSim.setShell(t, v, g)
		steps(t, aimAt(CFrame.new(), 0, 0, x * SPM), CFrame.new(), stats, 0.1)
		local high = 90 - math.deg(0.5 * math.asin(g * x / (v * v)))
		expect(t.desiredPitchDeg).toBeCloseTo(high, 0.1)
		t.modifiers.highArc = false
		steps(t, aimAt(CFrame.new(), 0, 0, x * SPM), CFrame.new(), stats, 0.1)
		expect(t.desiredPitchDeg).toBeCloseTo(90 - high, 0.1)
		steps(t, aimAt(CFrame.new(), 0, 0, 20000 * SPM), CFrame.new(), stats, 0.1)
		expect(t.reachable).toBe(false)
		expect(t.desiredPitchDeg).toBeCloseTo(45, 1e-3)
	end)

	it("the high-arc shell from the muzzle lands on the aim point", function()
		local v, g = 300, 19.62
		local stats = turretStats(nil, { indirect = true, elevationDeg = 85, depressionDeg = 3 })
		local t = TurretSim.newState()
		TurretSim.setShell(t, v, g)
		local aim = Vector3.new(2500 * SPM, -30, -2000 * SPM)
		steps(t, aim, CFrame.new(), stats, 8)
		expect(TurretSim.onTarget(t)).toBe(true)
		local origin, dir = TurretSim.aimRay(t, CFrame.new(), stats, PIVOTS)
		local horizontal = Vector3.new(dir.X, 0, dir.Z)
		local range = (Vector3.new(aim.X, 0, aim.Z) - Vector3.new(origin.X, 0, origin.Z)).Magnitude / SPM
		local time = range / (v * horizontal.Magnitude)
		local y = origin.Y / SPM + v * dir.Y * time - 0.5 * g * time * time
		expect(y).toBeCloseTo(aim.Y / SPM, 0.05)
		local landing = Vector3.new(origin.X, 0, origin.Z) / SPM + horizontal.Unit * range
		expect((landing - Vector3.new(aim.X, 0, aim.Z) / SPM).Magnitude).toBeLessThan(0.05)
		expect(math.deg(math.asin(dir.Y))).toBeGreaterThan(45)
	end)

	it("ballisticDirection degenerates gracefully", function()
		local d, ok = TurretSim.ballisticDirection(Vector3.zero, Vector3.zero, 300, 9.81)
		expect(ok).toBe(true)
		expect(d).toEqual(Vector3.new(0, 0, -1))
		local up, ok2 = TurretSim.ballisticDirection(Vector3.zero, Vector3.new(0, 30, 0), 300, 9.81)
		expect(ok2).toBe(true)
		expect(up).toBeCloseTo(Vector3.yAxis, 1e-9)
		local straight = TurretSim.ballisticDirection(Vector3.zero, Vector3.new(3, 4, 0), 0, 9.81)
		expect(straight).toBeCloseTo(Vector3.new(0.6, 0.8, 0), 1e-9)
	end)
end)

describe("TurretSim aim ray and frames", function()
	it("builds the muzzle ray from the pivots for turrets and casemates", function()
		local stats = turretStats()
		local t = TurretSim.newState()
		local origin, dir = TurretSim.aimRay(t, CFrame.new(), stats, PIVOTS)
		expect(origin).toBeCloseTo(Vector3.new(0, 7.5, -14), 1e-5)
		expect(dir).toBeCloseTo(Vector3.new(0, 0, -1), 1e-6)
		t.turretYawDeg = 90
		origin, dir = TurretSim.aimRay(t, CFrame.new(), stats, PIVOTS)
		expect(origin).toBeCloseTo(Vector3.new(14, 7.5, 0), 1e-5)
		expect(dir).toBeCloseTo(Vector3.new(1, 0, 0), 1e-6)
		local hull = CFrame.new(10, 2, 30) * CFrame.Angles(0, -math.rad(90), 0)
		t.turretYawDeg = 0
		origin = TurretSim.aimRay(t, hull, stats, PIVOTS)
		expect(origin).toBeCloseTo(Vector3.new(24, 9.5, 30), 1e-4)
		-- Casemate: the gun yaws inside the fixed superstructure about the trunnion.
		local cs = casemateStats()
		local c = TurretSim.newState()
		c.gunYawDeg = 90
		origin, dir = TurretSim.aimRay(c, CFrame.new(), cs, PIVOTS)
		expect(origin).toBeCloseTo(Vector3.new(12, 7.5, -2), 1e-5)
		expect(dir).toBeCloseTo(Vector3.new(1, 0, 0), 1e-6)
		expect(TurretSim.turretCFrame(c, CFrame.new(), cs, PIVOTS)).toBeCloseTo(PIVOTS.turretRing, 1e-6)
	end)

	it("puts the barrel line through the aim point once on target (straight-line laying)", function()
		local stats = turretStats()
		local hull = CFrame.new(5, 1, -3) * CFrame.fromEulerAnglesYXZ(math.rad(4), math.rad(30), math.rad(-3))
		local t = TurretSim.newState()
		local aim = Vector3.new(-200, 20, -400)
		steps(t, aim, hull, stats, 6)
		expect(TurretSim.onTarget(t)).toBe(true)
		local origin, dir = TurretSim.aimRay(t, hull, stats, PIVOTS)
		local toAim = aim - origin
		local miss = (toAim - dir * toAim:Dot(dir)).Magnitude
		expect(miss).toBeLessThan(0.05)
	end)
end)

describe("TurretSim robustness", function()
	it("treats dt <= 0 / NaN as no-ops and keeps the previous desired angles on a non-finite aim", function()
		local stats = turretStats()
		local t = TurretSim.newState()
		steps(t, aimAt(CFrame.new(), 30, 0, 300), CFrame.new(), stats, 0.5)
		local yaw = t.turretYawDeg
		for _, dt in { 0, -1, 0 / 0 } do
			expect(TurretSim.step(t, Vector3.zero, false, CFrame.new(), stats, PIVOTS, dt)).toBe(0)
			expect(t.turretYawDeg).toBe(yaw)
		end
		local desired = t.desiredBearingDeg
		TurretSim.step(t, Vector3.new(0 / 0, 0, 0), false, CFrame.new(), stats, PIVOTS, DT)
		expect(t.desiredBearingDeg).toBe(desired)
		expect(t.turretYawDeg).toBeGreaterThan(yaw)
	end)

	it("copyState copies angles and modifiers without sharing tables", function()
		local t = TurretSim.newState()
		t.turretYawDeg, t.gunPitchDeg = 12, -3
		t.modifiers.ring = "Damaged"
		local c = TurretSim.copyState(t)
		expect(c.turretYawDeg).toBe(12)
		expect(c.gunPitchDeg).toBe(-3)
		expect(c.modifiers.ring).toBe("Damaged")
		c.modifiers.ring = "Ok"
		expect(t.modifiers.ring).toBe("Damaged")
		local reused = TurretSim.newState()
		expect(TurretSim.copyState(t, reused)).toBe(reused)
	end)

	it("random hull attitudes and aims never violate the limits (property, 300 cases)", function()
		local rng = RNG.new(2024)
		local sector = { fromDeg = 160, toDeg = -160, depressionDeg = 1 }
		local turreted = turretStats(nil, { arcSectors = { sector } })
		local casemate = casemateStats()
		for _ = 1, 300 do
			local stats = if rng:chance(0.5) then turreted else casemate
			local hull = CFrame.new(rng:range(-100, 100), rng:range(-10, 10), rng:range(-100, 100))
				* CFrame.fromEulerAnglesYXZ(
					math.rad(rng:range(-25, 25)),
					rng:range(-math.pi, math.pi),
					math.rad(rng:range(-25, 25))
				)
			local t = TurretSim.newState()
			if rng:chance(0.3) then
				t.modifiers.ring = "Damaged"
			end
			local aim = Vector3.new(rng:range(-2000, 2000), rng:range(-200, 400), rng:range(-2000, 2000))
			steps(t, aim, hull, stats, 0.5, false, nil, function()
				local bearing = t.turretYawDeg + t.gunYawDeg
				local dep, elev = TurretSim.limitsAt(stats, bearing)
				expect(t.gunPitchDeg).toBeGreaterThanOrEqual(-dep - 1e-9)
				expect(t.gunPitchDeg).toBeLessThanOrEqual(elev + 1e-9)
				if stats.turretMount == "Casemate" then
					expect(t.turretYawDeg).toBe(0)
					expect(math.abs(t.gunYawDeg)).toBeLessThanOrEqual(11 + 1e-9)
				end
				expect(t.bearingSpeedDegS).toBeLessThanOrEqual(stats.turretTraverseDegS + 1e-6)
				expect(t.aimErrorDeg == t.aimErrorDeg).toBe(true)
			end)
		end
	end)
end)
