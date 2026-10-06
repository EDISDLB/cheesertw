-- Collision: vehicle-vs-vehicle contacts (00-DECISIONS §2 ramming "rammer's front arc ×.5", falls "on a tank = ram at
-- v_y"; §6 "vehicle–vehicle OBB, energy never increases"). Regression ids: REG-VEH-04 (no energy creation, no
-- vertical velocity on flat ground), REG-VEH-06 (wreck box = live hull box: bodyFromSim uses the sim's hull box).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local HeightmapWorld = require("@tests/Harness/HeightmapWorld")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Collision = require("@game/ReplicatedStorage/Shared/Vehicle/Collision")
local VehicleSim = require("@game/ReplicatedStorage/Shared/Vehicle/VehicleSim")

local SPM = 3
local SIZE = Vector3.new(9, 7, 20) -- (width, height, length) studs

local function body(x, z, yawDeg, velocity, y, size)
	local b = Collision.newBody()
	b.position = Vector3.new(x, y or 0, z)
	b.yaw = math.rad(yawDeg or 0)
	b.size = size or SIZE
	b.velocity = velocity or Vector3.zero
	return b
end

local function boxCFrame(b)
	return CFrame.new(b.position + Vector3.new(0, b.size.Y / 2, 0)) * CFrame.Angles(0, -b.yaw, 0)
end

-- Independent overlap oracle: the harness' 3-D SAT (HeightmapWorld.sweepBox reports an initial overlap at 0).
local function oracleOverlap(a, b)
	local world = HeightmapWorld.new({ boxes = { { id = "a", cframe = boxCFrame(a), size = a.size } } })
	local hit = world:sweepBox(boxCFrame(b), b.size, Vector3.zero)
	return hit ~= nil
end

describe("Collision.test", function()
	it("reports no contact for separated or merely touching boxes", function()
		local a = body(0, 0)
		expect((Collision.test(a, body(30, 0)))).toBe(false)
		expect((Collision.test(a, body(9, 0)))).toBe(false) -- touching side faces
		expect((Collision.test(a, body(0, 0, 0, nil, 7)))).toBe(false) -- resting exactly on top
		local overlapping, contact = Collision.test(a, body(0, 0, 0, nil, 10))
		expect(overlapping).toBe(false)
		expect(contact.overlapping).toBe(false)
		expect(contact.depth).toBe(0)
	end)

	it("resolves a head-on overlap along the length with front faces and closing speed", function()
		local a = body(0, 0, 0, Vector3.new(0, 0, -30)) -- north at 10 m/s
		local b = body(0, -19, 180, Vector3.new(0, 0, 15)) -- south at 5 m/s, front to front
		local overlapping, c = Collision.test(a, b)
		expect(overlapping).toBe(true)
		expect(c.normal).toBeCloseTo(Vector3.new(0, 0, -1), 1e-9)
		expect(c.depth).toBeCloseTo(1, 1e-9)
		expect(c.faceA).toBe("Front")
		expect(c.faceB).toBe("Front")
		expect(c.closingSpeedMps).toBeCloseTo(15, 1e-9)
		expect(c.contactPoint).toBeCloseTo(Vector3.new(0, 3.5, -9.5), 1e-6)
	end)

	it("resolves a T-bone along the width with side faces", function()
		local a = body(0, 0, 0)
		local b = body(8.5, 0, 0, Vector3.new(-6, 0, 0))
		local overlapping, c = Collision.test(a, b)
		expect(overlapping).toBe(true)
		expect(c.normal).toBeCloseTo(Vector3.new(1, 0, 0), 1e-9)
		expect(c.depth).toBeCloseTo(0.5, 1e-9)
		expect(c.faceA).toBe("Right")
		expect(c.faceB).toBe("Left")
		expect(c.closingSpeedMps).toBeCloseTo(2, 1e-9) -- B drives into A at 2 m/s
		-- Rear-ending: B behind A, both facing north.
		local _, r = Collision.test(a, body(0, 19.5, 0))
		expect(r.faceA).toBe("Rear")
		expect(r.faceB).toBe("Front")
	end)

	it("detects stacking (landing on a tank) with a vertical normal", function()
		local a = body(0, 0)
		local b = body(1, 2, 30, Vector3.new(0, -30, 0), 6.8)
		local overlapping, c = Collision.test(a, b)
		expect(overlapping).toBe(true)
		expect(c.normal).toEqual(Vector3.new(0, 1, 0))
		expect(c.depth).toBeCloseTo(0.2, 1e-6)
		expect(c.faceA).toBe("Top")
		expect(c.faceB).toBe("Bottom")
		expect(c.closingSpeedMps).toBeCloseTo(10, 1e-9)
		expect(c.contactPoint.Y).toBeCloseTo(7, 1e-9)
	end)

	it("separates side-by-side boxes horizontally however deep they overlap", function()
		local _, c = Collision.test(body(0, 0), body(1, 3, 10))
		expect(c.normal.Y).toBe(0)
		expect(c.depth).toBeGreaterThan(7) -- deeper than the boxes are tall, still horizontal
	end)

	it("reports a negative closing speed for separating bodies", function()
		local a = body(0, 0, 0, Vector3.new(0, 0, 3))
		local b = body(0, -19, 0, Vector3.new(0, 0, -30))
		local _, c = Collision.test(a, b)
		expect(c.closingSpeedMps).toBeLessThan(0)
	end)

	it("rejects invalid bodies", function()
		expect((Collision.test(body(0 / 0, 0), body(0, 0)))).toBe(false)
		expect((Collision.test(body(0, 0, 0, nil, 0, Vector3.new(0, 7, 20)), body(0, 0)))).toBe(false)
	end)

	it("agrees with an independent SAT and gives a minimal separation (property, 400 cases)", function()
		local rng = RNG.new(77)
		local contact = Collision.newContact()
		local overlaps = 0
		for _ = 1, 400 do
			local a = body(
				rng:range(-5, 5),
				rng:range(-5, 5),
				rng:range(-180, 180),
				nil,
				0,
				Vector3.new(rng:range(6, 12), 7, rng:range(12, 24))
			)
			local b = body(
				rng:range(-20, 20),
				rng:range(-20, 20),
				rng:range(-180, 180),
				nil,
				0,
				Vector3.new(rng:range(6, 12), 7, rng:range(12, 24))
			)
			local overlapping = Collision.test(a, b, contact)
			expect(overlapping).toBe(oracleOverlap(a, b))
			if overlapping then
				overlaps += 1
				expect(contact.depth).toBeGreaterThan(0)
				expect(math.abs(contact.normal.Magnitude - 1)).toBeLessThan(1e-6) -- Vector3 is float32
				expect(contact.normal.Y).toBe(0)
				-- Moving B by the separation clears the overlap; a little less does not (minimality on that axis).
				local moved = body(0, 0, math.deg(b.yaw), nil, 0, b.size)
				moved.position = b.position + contact.normal * (contact.depth + 1e-3)
				expect((Collision.test(a, moved))).toBe(false)
				moved.position = b.position + contact.normal * (contact.depth - 1e-3)
				expect((Collision.test(a, moved))).toBe(true)
				-- The contact point lies inside both footprints (grown slightly for rounding).
				for _, box in { a, b } do
					local cf = CFrame.new(box.position) * CFrame.Angles(0, -box.yaw, 0)
					local p = cf:PointToObjectSpace(contact.contactPoint)
					expect(math.abs(p.X)).toBeLessThanOrEqual(box.size.X / 2 + 1e-3)
					expect(math.abs(p.Z)).toBeLessThanOrEqual(box.size.Z / 2 + 1e-3)
				end
			end
		end
		expect(overlaps).toBeGreaterThan(50)
	end)
end)

describe("Collision faces", function()
	it("maps world directions to box faces for any heading", function()
		expect(Collision.faceOf(0, Vector3.new(0, 0, -1))).toBe("Front")
		expect(Collision.faceOf(0, Vector3.new(0, 0, 1))).toBe("Rear")
		expect(Collision.faceOf(0, Vector3.new(1, 0, 0))).toBe("Right")
		expect(Collision.faceOf(0, Vector3.new(-1, 0, 0))).toBe("Left")
		expect(Collision.faceOf(math.rad(90), Vector3.new(1, 0, 0))).toBe("Front") -- facing east
		expect(Collision.faceOf(math.rad(90), Vector3.new(0, 0, 1))).toBe("Right")
		expect(Collision.faceOf(1.3, Vector3.new(0, 1, 0))).toBe("Top")
		expect(Collision.faceOf(1.3, Vector3.new(0, -1, 0))).toBe("Bottom")
	end)
end)

describe("Collision impulses (REG-VEH-04)", function()
	local function ke(m, v)
		return Collision.kineticEnergy(m, v)
	end

	it("perfectly inelastic: equal masses end with equal normal velocity, momentum kept", function()
		local n = Vector3.new(0, 0, -1)
		local vA, vB = Vector3.new(0, 0, -30), Vector3.zero
		local dA, dB = Collision.resolveVelocities(40000, 40000, vA, vB, n, 0)
		expect(vA + dA).toBeCloseTo(Vector3.new(0, 0, -15), 1e-9)
		expect(vB + dB).toBeCloseTo(Vector3.new(0, 0, -15), 1e-9)
		expect(ke(40000, vA + dA) + ke(40000, vB + dB)).toBeLessThan(ke(40000, vA))
	end)

	it("elastic: equal masses swap normal velocities; an immovable body reflects", function()
		local n = Vector3.new(1, 0, 0)
		local vA, vB = Vector3.new(12, 0, 3), Vector3.new(-6, 0, 0)
		local dA, dB = Collision.resolveVelocities(20000, 20000, vA, vB, n, 1)
		expect(vA + dA).toBeCloseTo(Vector3.new(-6, 0, 3), 1e-9) -- tangential part untouched
		expect(vB + dB).toBeCloseTo(Vector3.new(12, 0, 0), 1e-9)
		local wA, wall = Collision.resolveVelocities(20000, math.huge, Vector3.new(9, 0, 0), Vector3.zero, n, 0.5)
		expect(Vector3.new(9, 0, 0) + wA).toBeCloseTo(Vector3.new(-4.5, 0, 0), 1e-9)
		expect(wall).toEqual(Vector3.zero)
	end)

	it("does nothing for separating bodies, immovable pairs or invalid input", function()
		local n = Vector3.new(1, 0, 0)
		local a, b = Collision.resolveVelocities(1, 1, Vector3.new(-1, 0, 0), Vector3.zero, n)
		expect(a).toEqual(Vector3.zero)
		expect(b).toEqual(Vector3.zero)
		a, b = Collision.resolveVelocities(0, -5, Vector3.new(5, 0, 0), Vector3.zero, n)
		expect(a).toEqual(Vector3.zero)
		expect(b).toEqual(Vector3.zero)
		a = Collision.resolveVelocities(1, 1, Vector3.new(0 / 0, 0, 0), Vector3.zero, n)
		expect(a).toEqual(Vector3.zero)
	end)

	it("never creates energy or vertical velocity (10,000 random pairs, 10–80 t, 0–70 km/h)", function()
		local rng = RNG.new(404)
		for _ = 1, 10000 do
			local mA, mB = rng:range(10000, 80000), rng:range(10000, 80000)
			local function randomVelocity()
				local speed = rng:range(0, 70) / 3.6 * SPM
				local heading = rng:range(-math.pi, math.pi)
				return Vector3.new(math.sin(heading) * speed, 0, -math.cos(heading) * speed)
			end
			local vA, vB = randomVelocity(), randomVelocity()
			local angle = rng:range(-math.pi, math.pi)
			local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local e = rng:range(0, 1)
			local dA, dB = Collision.resolveVelocities(mA, mB, vA, vB, n, e)
			local before = ke(mA, vA) + ke(mB, vB)
			local after = ke(mA, vA + dA) + ke(mB, vB + dB)
			-- Tolerances are relative float32 rounding (Vector3 components are float32 in Roblox and Lune).
			expect(after).toBeLessThanOrEqual(before * (1 + 1e-6) + 1e-6)
			expect(dA.Y).toBe(0)
			expect(dB.Y).toBe(0)
			local function momentum(va, vb)
				return Vector3.new(mA * va.X + mB * vb.X, mA * va.Y + mB * vb.Y, mA * va.Z + mB * vb.Z)
			end
			local drift = (momentum(vA, vB) - momentum(vA + dA, vB + dB)).Magnitude
			local scale = mA * vA.Magnitude + mB * vB.Magnitude
			expect(drift).toBeLessThanOrEqual(1e-6 * scale + 1e-3)
		end
	end)

	it("keeps the energy bound once applied to flat-ground VehicleSim states (1,000 random pairs)", function()
		local rng = RNG.new(405)
		for _ = 1, 1000 do
			local a = VehicleSim.newState(CFrame.Angles(0, rng:range(-math.pi, math.pi), 0))
			local b = VehicleSim.newState(CFrame.Angles(0, rng:range(-math.pi, math.pi), 0))
			a.speed = rng:range(-20, 70) / 3.6 * SPM
			b.speed = rng:range(-20, 70) / 3.6 * SPM
			local mA, mB = rng:range(10000, 80000), rng:range(10000, 80000)
			local vA, vB = VehicleSim.velocity(a), VehicleSim.velocity(b)
			local angle = rng:range(-math.pi, math.pi)
			local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local dA, dB = Collision.resolveVelocities(mA, mB, vA, vB, n)
			VehicleSim.applyVelocityChange(a, dA)
			VehicleSim.applyVelocityChange(b, dB)
			local before = ke(mA, vA) + ke(mB, vB)
			local after = ke(mA, VehicleSim.velocity(a)) + ke(mB, VehicleSim.velocity(b))
			expect(after).toBeLessThanOrEqual(before * (1 + 1e-9) + 1e-6)
			expect(VehicleSim.velocity(a).Y).toBe(0)
		end
	end)
end)

describe("Collision separation and bodies", function()
	it("splits the separation by inverse mass; immovable bodies do not move", function()
		local a, b = body(0, 0), body(8.5, 0)
		local _, c = Collision.test(a, b)
		local pushA, pushB = Collision.separation(30000, 10000, c, 0.1)
		expect(pushA).toBeCloseTo(Vector3.new(-0.15, 0, 0), 1e-9)
		expect(pushB).toBeCloseTo(Vector3.new(0.45, 0, 0), 1e-9)
		local still, all = Collision.separation(math.huge, 10000, c)
		expect(still).toEqual(-Vector3.new(1, 0, 0) * 0)
		expect(all).toBeCloseTo(Vector3.new(0.5, 0, 0), 1e-9)
		local _, none = Collision.test(a, body(50, 0))
		local x, y = Collision.separation(1, 1, none)
		expect(x).toEqual(Vector3.zero)
		expect(y).toEqual(Vector3.zero)
	end)

	it("separating via VehicleSim.displace clears the overlap", function()
		local stats = { dimensionsM = Vector3.new(3, 2.4, 6.6), terrainResistance = { hard = 1, medium = 1, soft = 1 } }
		local a = VehicleSim.newState(CFrame.new(0, 0, 0))
		local b = VehicleSim.newState(CFrame.new(8, 0, 2) * CFrame.Angles(0, 0.4, 0))
		local ba = Collision.bodyFromSim(a, stats)
		local bb = Collision.bodyFromSim(b, stats)
		local overlapping, c = Collision.test(ba, bb)
		expect(overlapping).toBe(true)
		local pushA, pushB = Collision.separation(30000, 30000, c, 0.01)
		VehicleSim.displace(a, pushA)
		VehicleSim.displace(b, pushB)
		expect((Collision.test(Collision.bodyFromSim(a, stats, ba), Collision.bodyFromSim(b, stats, bb)))).toBe(false)
	end)

	it("bodyFromSim uses the sim's own hull box, heading and velocity (REG-VEH-06 parity)", function()
		local stats = { dimensionsM = Vector3.new(3, 2.4, 6.6), terrainResistance = { hard = 1, medium = 1, soft = 1 } }
		local s = VehicleSim.newState(CFrame.new(4, 1, -2) * CFrame.Angles(0, -math.rad(30), 0))
		s.speed = 15
		local reused = Collision.newBody()
		local b = Collision.bodyFromSim(s, stats, reused)
		expect(b).toBe(reused)
		expect(b.position).toEqual(s.position)
		expect(b.yaw).toBe(s.yaw)
		expect(b.size).toEqual(VehicleSim.hullSize(s, stats))
		expect(b.velocity).toBeCloseTo(VehicleSim.velocity(s), 1e-9)
		expect(Collision.kineticEnergy(1000, Vector3.new(30, 0, 0))).toBeCloseTo(0.5 * 1000 * 100, 1e-9)
	end)
end)
