local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Ballistics = require("@game/ReplicatedStorage/Shared/Combat/Ballistics")
local ArmorGeometry = require("@game/ReplicatedStorage/Shared/Combat/ArmorGeometry")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Fixtures = require("./CombatFixtures")

-- Vector3 components are float32.
local EPS = 1e-3

describe("Ballistics", function()
	describe("penetration falloff (00-DECISIONS §1, REG-ARM-06)", function()
		it("AP: nominal to 100 m, linear to the 500 m value, flat beyond", function()
			local ap = Fixtures.shell("AP") -- 100 -> 90
			expect(Ballistics.penetrationAt(ap, 0)).toBe(100)
			expect(Ballistics.penetrationAt(ap, 100)).toBe(100)
			expect(Ballistics.penetrationAt(ap, 300)).toBeCloseTo(95, 1e-12)
			expect(Ballistics.penetrationAt(ap, 500)).toBe(90)
			expect(Ballistics.penetrationAt(ap, 900)).toBe(90)
		end)

		it("APCR loses more; HEAT / HE / HESH never lose penetration", function()
			local apcr = Fixtures.shell("APCR", { penetrationMm = 100, penetrationAt500Mm = 75 })
			expect(Ballistics.penetrationAt(apcr, 300)).toBeCloseTo(87.5, 1e-12)
			for _, kind in { "HEAT", "HE", "HESH" } do
				local s = Fixtures.shell(kind, { penetrationAt500Mm = 1 })
				expect(Ballistics.penetrationAt(s, 450)).toBe(s.penetrationMm)
				expect(Ballistics.penetrationAt(s, 5000)).toBe(s.penetrationMm)
			end
		end)

		it(
			"property: 10,000 random kinetic shells are non-increasing, nominal <= 100 m, linear, flat >= 500 m",
			function()
				local rng = RNG.new(7)
				for _ = 1, 10000 do
					local kind = if rng:chance(0.5) then "AP" else "APCR"
					local pen = rng:range(20, 400)
					local far = Ballistics.defaultPenetrationAt500(kind, pen)
					local s = Fixtures.shell(kind, { penetrationMm = pen, penetrationAt500Mm = far })
					local d1, d2 = rng:range(0, 800), rng:range(0, 800)
					if d1 > d2 then
						d1, d2 = d2, d1
					end
					expect(Ballistics.penetrationAt(s, d2) <= Ballistics.penetrationAt(s, d1) + 1e-9).toBe(true)
					expect(Ballistics.penetrationAt(s, rng:range(0, 100))).toBe(pen)
					expect(Ballistics.penetrationAt(s, rng:range(500, 2000))).toBe(far)
					local a, b = rng:range(100, 500), rng:range(100, 500)
					local mid = Ballistics.penetrationAt(s, (a + b) / 2)
					expect(mid).toBeCloseTo((Ballistics.penetrationAt(s, a) + Ballistics.penetrationAt(s, b)) / 2, 1e-9)
				end
			end
		)

		it("authoring defaults: falloff end, velocity scale and family ratios", function()
			expect(Ballistics.defaultPenetrationAt500("AP", 200)).toBeCloseTo(180, 1e-12)
			expect(Ballistics.defaultPenetrationAt500("APCR", 200)).toBeCloseTo(150, 1e-12)
			expect(Ballistics.defaultPenetrationAt500("HEAT", 200)).toBe(200)
			expect(Ballistics.authoredVelocityMps(800)).toBeCloseTo(480, 1e-12)
			expect(Ballistics.familyVelocityMps("APCR", 480)).toBeCloseTo(600, 1e-12)
			expect(Ballistics.familyVelocityMps("HEAT", 480)).toBeCloseTo(408, 1e-12)
			expect(Ballistics.familyVelocityMps("HE", 480)).toBe(480)
			expect(Ballistics.familyVelocityMps("Unknown", 480)).toBe(480)
		end)
	end)

	describe("flight", function()
		it("uses shell units converted to studs (480 m/s, 19.62 m/s² -> 1440 studs/s, 58.86 studs/s²)", function()
			local speed, gravity, range = Ballistics.flightParams(Fixtures.shell("AP"))
			expect(speed).toBeCloseTo(1440, 1e-9)
			expect(gravity).toBeCloseTo(58.86, 1e-9)
			expect(range).toBeCloseTo(1800, 1e-9)
			-- non-finite / missing gravity or range fall back to config
			local _, g2, r2 = Ballistics.flightParams(Fixtures.shell("AP", { gravityMps2 = 0 / 0, maxRangeM = -1 }))
			expect(g2).toBeCloseTo(58.86, 1e-9)
			expect(r2).toBeCloseTo(1800, 1e-9)
		end)

		it("position and velocity are analytic (hand-computed)", function()
			local p = Ballistics.launch(Vector3.new(0, 10, 0), Vector3.new(1, 0, 0), Fixtures.shell("AP"))
			expect(Ballistics.positionAt(p, 1)).toBeCloseTo(Vector3.new(1440, 10 - 29.43, 0), EPS)
			expect(Ballistics.velocityAt(p, 1)).toBeCloseTo(Vector3.new(1440, -58.86, 0), EPS)
			local up = Ballistics.launch(Vector3.zero, Vector3.new(0, 1, 0), Fixtures.shell("AP"))
			-- apex at t = v/g
			local tApex = 1440 / 58.86
			expect(Ballistics.velocityAt(up, tApex).Y).toBeCloseTo(0, EPS)
			expect(Ballistics.positionAt(up, tApex).Y).toBeCloseTo(1440 * 1440 / (2 * 58.86), 1)
		end)

		it("step() yields contiguous swept segments on the analytic arc at any tick rate", function()
			local shell = Fixtures.shell("AP")
			local a = Ballistics.launch(Vector3.new(0, 5, 0), Vector3.new(3, 1, 4), shell)
			local b = Ballistics.launch(Vector3.new(0, 5, 0), Vector3.new(3, 1, 4), shell)
			local last = a.position
			for tick = 1, 30 do
				local from, to, expired = Ballistics.step(a, 1 / 30)
				expect(expired).toBe(false)
				expect(from).toBe(last)
				last = to
				Ballistics.step(b, 1 / 60)
				Ballistics.step(b, 1 / 60)
				expect(a.position).toBeCloseTo(b.position, EPS)
				expect(to).toBeCloseTo(Ballistics.positionAt(a, tick / 30), EPS)
			end
		end)

		it("expires exactly at max range path length, cutting the last segment (REG-PRJ-04)", function()
			local shell = Fixtures.shell("AP", { maxRangeM = 100 }) -- 300 studs; 48 studs per 30 Hz tick
			local p = Ballistics.launch(
				Vector3.zero,
				Vector3.new(0, 0, -1),
				Fixtures.shell("AP", { maxRangeM = 100, gravityMps2 = 0 })
			)
			local ticks = 0
			local expired = false
			local lastFrom, lastTo
			while not expired and ticks < 100 do
				lastFrom, lastTo, expired = Ballistics.step(p, 1 / 30)
				ticks += 1
			end
			expect(ticks).toBe(7) -- 6 full ticks = 288 studs, the 7th is cut at 300
			expect(p.traveled).toBeCloseTo(300, 1e-9)
			expect((lastTo - lastFrom).Magnitude).toBeCloseTo(12, EPS)
			expect(p.position).toBeCloseTo(Vector3.new(0, 0, -300), EPS)
			-- an expired projectile no longer moves
			local from, to, still = Ballistics.step(p, 1 / 30)
			expect(still).toBe(true)
			expect(from).toBe(to)
			-- with gravity the path is longer than the chord, so it expires no later
			local g = Ballistics.launch(Vector3.zero, Vector3.new(0, 0, -1), shell)
			local n = 0
			repeat
				local _, _, e = Ballistics.step(g, 1 / 30)
				n += 1
			until e or n > 100
			expect(n <= 7).toBe(true)
			expect(g.traveled).toBeCloseTo(300, 1e-9)
		end)

		it("redirect() keeps speed and the range budget (ricochet continuation)", function()
			local p = Ballistics.launch(Vector3.zero, Vector3.new(0, 0, -1), Fixtures.shell("AP"))
			Ballistics.step(p, 0.1)
			local speed = Ballistics.velocityAt(p, p.t).Magnitude
			local traveled = p.traveled
			Ballistics.redirect(p, Vector3.new(1, 2, 3), Vector3.new(0, 0.6, 0.8))
			expect(p.origin).toBe(Vector3.new(1, 2, 3))
			expect(p.t).toBe(0)
			expect(p.traveled).toBe(traveled)
			expect(p.velocity0.Magnitude).toBeCloseTo(speed, EPS)
			expect(p.velocity0.Unit).toBeCloseTo(Vector3.new(0, 0.6, 0.8), 1e-5)
			Ballistics.redirect(p, Vector3.zero, Vector3.zero)
			expect(p.expired).toBe(true)
		end)

		it("bad launches expire immediately and never produce NaN segments", function()
			local nan = 0 / 0
			for _, dir in { Vector3.zero, Vector3.new(nan, 0, 1), Vector3.new(math.huge, 0, 0) } do
				local p = Ballistics.launch(Vector3.zero, dir, Fixtures.shell("AP"))
				expect(p.expired).toBe(true)
				local from, to, expired = Ballistics.step(p, 1 / 30)
				expect(expired).toBe(true)
				expect(from).toBe(to)
			end
			local p =
				Ballistics.launch(Vector3.zero, Vector3.new(0, 0, -1), Fixtures.shell("AP", { velocityMps = nan }))
			expect(p.expired).toBe(true)
			local q = Ballistics.launch(Vector3.zero, Vector3.new(0, 0, -1), Fixtures.shell("AP"))
			local from, to, expired = Ballistics.step(q, nan)
			expect(expired).toBe(false)
			expect(from).toBe(to)
			-- reusing a projectile record
			local reused = Ballistics.launch(Vector3.new(5, 5, 5), Vector3.new(1, 0, 0), Fixtures.shell("AP"), q)
			expect(reused).toBe(q)
			expect(q.origin).toBe(Vector3.new(5, 5, 5))
			expect(q.traveled).toBe(0)
		end)

		it("no tunneling: a 1,500 m/s shell at 30 Hz (50 m per tick) still hits a 0.2 m plate (REG-PRJ-06)", function()
			local plate = {
				volumes = {
					Fixtures.box({
						id = 1,
						group = "Hull",
						kind = "Armor",
						min = Vector3.new(-2.25, -2, -0.3),
						max = Vector3.new(2.25, 2, 0.3),
						thickness = 20,
						zone = "HullSide",
					}),
				},
				boundsCenter = Vector3.zero,
				boundsRadius = 4,
				pivots = Fixtures.model().pivots,
			}
			local shell = Fixtures.shell("AP", { velocityMps = 1500, maxRangeM = 2000, gravityMps2 = 0 })
			local rng = RNG.new(99)
			local buf = ArmorGeometry.newBuffer()
			for _ = 1, 300 do
				local distance = rng:range(10, 1500)
				local pose = Fixtures.pose(CFrame.new(0, 0, -distance))
				local p =
					Ballistics.launch(Vector3.new(rng:range(-2, 2), rng:range(-1, 1), 0), Vector3.new(0, 0, -1), shell)
				local hits = 0
				for _ = 1, 200 do
					local from, to, expired = Ballistics.step(p, 1 / 30)
					local segment = to - from
					local _, count = ArmorGeometry.raycast(plate, pose, from, segment, segment.Magnitude, buf)
					if count > 0 and buf.items[1].entering then
						hits += 1
						break
					end
					if expired then
						break
					end
				end
				expect(hits).toBe(1)
			end
		end)
	end)

	describe("aiming solver", function()
		it("low arc matches the closed form and the launched shell lands on the target", function()
			local shell = Fixtures.shell("AP")
			local speed, gravity = Ballistics.flightParams(shell)
			local x = 1200 -- 400 m
			local theta, tof = Ballistics.solveElevation(Vector3.zero, Vector3.new(x, 0, 0), speed, gravity)
			expect(theta).toBeCloseTo(0.5 * math.asin(gravity * x / (speed * speed)), 1e-12)
			expect(tof).toBeCloseTo(x / (speed * math.cos(theta :: number)), 1e-12)
			local dir, t2 = Ballistics.aimDirection(Vector3.zero, Vector3.new(x, 0, 0), shell)
			expect(t2).toBeCloseTo(tof :: number, 1e-12)
			local p = Ballistics.launch(Vector3.zero, dir :: Vector3, shell)
			expect(Ballistics.positionAt(p, tof :: number)).toBeCloseTo(Vector3.new(x, 0, 0), 0.05)
		end)

		it("hits elevated / depressed targets and orders low < high arc", function()
			local speed, gravity = 600, 58.86
			local rng = RNG.new(3)
			for _ = 1, 500 do
				local target = Vector3.new(rng:range(-1500, 1500), rng:range(-200, 200), rng:range(-1500, 1500))
				local low, tLow = Ballistics.solveElevation(Vector3.zero, target, speed, gravity)
				local high, tHigh = Ballistics.solveElevation(Vector3.zero, target, speed, gravity, true)
				if low ~= nil then
					expect(high ~= nil).toBe(true)
					expect((high :: number) >= (low :: number) - 1e-12).toBe(true)
					expect((tHigh :: number) >= (tLow :: number) - 1e-9).toBe(true)
					local flat = Vector3.new(target.X, 0, target.Z).Magnitude
					local yAt = flat * math.tan(low) - gravity * flat * flat / (2 * speed * speed * math.cos(low) ^ 2)
					expect(yAt).toBeCloseTo(target.Y, 1e-4)
				end
			end
		end)

		it("returns nil out of reach and handles vertical shots", function()
			local reach = Ballistics.maxReach(100, 10)
			expect(reach).toBe(1000)
			expect(Ballistics.solveElevation(Vector3.zero, Vector3.new(1001, 0, 0), 100, 10)).toBeNil()
			local up, tUp = Ballistics.solveElevation(Vector3.zero, Vector3.new(0, 100, 0), 100, 10)
			expect(up).toBeCloseTo(math.pi / 2, 1e-12)
			expect(tUp).toBeCloseTo((100 - math.sqrt(10000 - 2000)) / 10, 1e-12)
			expect(Ballistics.solveElevation(Vector3.zero, Vector3.new(0, 1000, 0), 100, 10)).toBeNil()
			local down = Ballistics.solveElevation(Vector3.zero, Vector3.new(0, -50, 0), 100, 10)
			expect(down).toBeCloseTo(-math.pi / 2, 1e-12)
			local flatTheta, flatT = Ballistics.solveElevation(Vector3.zero, Vector3.new(30, 40, 0), 100, 0)
			expect(flatTheta).toBeCloseTo(math.atan2(40, 30), 1e-12)
			expect(flatT).toBeCloseTo(0.5, 1e-12)
			expect(Ballistics.solveElevation(Vector3.new(0 / 0, 0, 0), Vector3.new(1, 0, 0), 100, 10)).toBeNil()
			expect(Ballistics.maxReach(100, 0)).toBe(math.huge)
		end)

		it("aimDirection refuses targets beyond the shell's max range", function()
			local shell = Fixtures.shell("AP", { maxRangeM = 100 }) -- 300 studs
			expect(Ballistics.aimDirection(Vector3.zero, Vector3.new(310, 0, 0), shell)).toBeNil()
			expect(Ballistics.aimDirection(Vector3.zero, Vector3.new(290, 0, 0), shell)).never.toBeNil()
		end)

		it("distanceM converts studs to metres", function()
			expect(Ballistics.distanceM(Vector3.zero, Vector3.new(0, 0, 300))).toBeCloseTo(100, 1e-9)
		end)
	end)
end)
