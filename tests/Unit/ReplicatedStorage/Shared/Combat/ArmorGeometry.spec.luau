local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ArmorGeometry = require("@game/ReplicatedStorage/Shared/Combat/ArmorGeometry")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Fixtures = require("./CombatFixtures")

-- Vector3 / CFrame components are float32 (Roblox and Lune): positions carry ~1e-7 relative error.
local EPS = 1e-4

local function kinds(buf, count)
	local out = {}
	for i = 1, count do
		local c = buf.items[i]
		table.insert(out, `{c.volumeId}{if c.entering then "+" else "-"}`)
	end
	return out
end

describe("ArmorGeometry", function()
	describe("raycast", function()
		it("returns every crossing sorted by distance with face data (head-on, lower front plate)", function()
			local model = Fixtures.model()
			local buf, count = ArmorGeometry.raycast(
				model,
				Fixtures.pose(),
				Vector3.new(0, 2.5, -30),
				Vector3.new(0, 0, 1)
			)
			-- hull in (z −9), ammo rack (z −2..2), engine (z 4..8), hull out (z 9)
			expect(kinds(buf, count)).toEqual({ "1+", "11+", "11-", "9+", "9-", "1-" })
			local first = buf.items[1]
			expect(first.distance).toBeCloseTo(21, EPS)
			expect(first.point).toBeCloseTo(Vector3.new(0, 2.5, -9), EPS)
			expect(first.normal).toBeCloseTo(Vector3.new(0, 0, -1), EPS)
			expect(first.entering).toBe(true)
			expect(first.thicknessMm).toBe(60)
			expect(first.zone).toBe("HullLowerFront")
			expect(first.volumeKind).toBe("Armor")
			expect(first.group).toBe("Hull")
			expect(first.spaced).toBe(false)
			local rack = buf.items[2]
			expect(rack.module).toBe("AmmoRack")
			expect(rack.distance).toBeCloseTo(28, EPS)
			local exit = buf.items[count]
			expect(exit.entering).toBe(false)
			expect(exit.normal).toBeCloseTo(Vector3.new(0, 0, 1), EPS)
			expect(exit.distance).toBeCloseTo(39, EPS)
		end)

		it("hits the sloped glacis at the hand-computed point and normal", function()
			local model = Fixtures.model()
			local buf = ArmorGeometry.raycast(model, Fixtures.pose(), Vector3.new(2.5, 5, -30), Vector3.new(0, 0, 1))
			local first = ArmorGeometry.firstHit(buf) :: any
			expect(first.zone).toBe("HullUpperFront")
			expect(first.point).toBeCloseTo(Vector3.new(2.5, 5, -6), EPS)
			expect(first.normal).toBeCloseTo(Fixtures.GLACIS_NORMAL, EPS)
			expect(ArmorGeometry.impactAngleDeg(Vector3.new(0, 0, 1), first.normal)).toBeCloseTo(
				math.deg(math.acos(2 / math.sqrt(40))),
				EPS
			)
		end)

		it("normalizes the direction (distances are studs) and honours maxDistance", function()
			local model = Fixtures.model()
			local _, count = ArmorGeometry.raycast(
				model,
				Fixtures.pose(),
				Vector3.new(0, 2.5, -30),
				Vector3.new(0, 0, 7),
				20.9
			)
			expect(count).toBe(0)
			local buf2, count2 =
				ArmorGeometry.raycast(model, Fixtures.pose(), Vector3.new(0, 2.5, -30), Vector3.new(0, 0, 7), 21)
			expect(count2).toBe(1)
			expect(buf2.items[1].distance).toBeCloseTo(21, EPS)
		end)

		it("applies turret yaw (+ = clockwise): at 90° the gun points right (+X)", function()
			local model = Fixtures.model()
			local buf, count =
				ArmorGeometry.raycast(model, Fixtures.pose(nil, 90), Vector3.new(30, 7.5, 0), Vector3.new(-1, 0, 0))
			expect(count).toBeGreaterThan(3)
			-- barrel tip (Spaced) at x = 3.5 + 9.6, mantlet (Layered) at x = 4.1, turret front at x = 3.5
			expect(buf.items[1].volumeId).toBe(4)
			expect(buf.items[1].distance).toBeCloseTo(30 - 13.1, EPS)
			expect(buf.items[1].zone).toBe("GunBarrel")
			local mantlet, front
			for i = 1, count do
				local c = buf.items[i]
				if c.entering and c.volumeId == 3 then
					mantlet = c
				elseif c.entering and c.volumeId == 2 then
					front = c
				end
			end
			expect(mantlet.distance).toBeCloseTo(30 - 4.1, EPS)
			expect(front.distance).toBeCloseTo(26.5, EPS)
			expect(front.zone).toBe("TurretFront")
			expect(front.normal).toBeCloseTo(Vector3.new(1, 0, 0), EPS)
		end)

		it("applies gun elevation about the trunnion (+ = up)", function()
			local model = Fixtures.model()
			local e = math.rad(10)
			-- barrel axis point at horizontal distance 7.5 studs from the trunnion (hull z = −11)
			local s = 7.5 / math.cos(e)
			local topY = 7.5 + s * math.sin(e) + 0.25 / math.cos(e)
			local buf =
				ArmorGeometry.raycast(model, Fixtures.pose(nil, 0, 10), Vector3.new(0, 30, -11), Vector3.new(0, -1, 0))
			expect(buf.items[1].volumeId).toBe(4)
			expect(buf.items[1].distance).toBeCloseTo(30 - topY, EPS)
		end)

		it("applies casemate gun yaw and the hull CFrame, consistent with groupFrames", function()
			local model = Fixtures.model()
			local hull = CFrame.new(100, 2, 50) * CFrame.Angles(0, math.rad(-30), 0)
			local pose = Fixtures.pose(hull, 0, 0, 12)
			local frames = ArmorGeometry.groupFrames(model, pose)
			local tip = frames.Gun:PointToWorldSpace(Vector3.new(0, 0.25, -9))
			local buf = ArmorGeometry.raycast(model, pose, tip + Vector3.new(0, 20, 0), Vector3.new(0, -1, 0))
			local first = ArmorGeometry.firstHit(buf) :: any
			expect(first.volumeId).toBe(4)
			expect(first.distance).toBeCloseTo(20, EPS)
			expect(ArmorGeometry.groupFrame(model, pose, "Gun")).toBeCloseTo(frames.Gun, EPS)
			expect(ArmorGeometry.groupFrame(model, pose, "Turret")).toBeCloseTo(frames.Turret, EPS)
			expect(ArmorGeometry.groupFrame(model, pose, "Hull")).toBeCloseTo(hull, EPS)
			expect(ArmorGeometry.muzzleFrame(model, pose).Position).toBeCloseTo(
				frames.Gun:PointToWorldSpace(Vector3.new(0, 0, -9.6)),
				EPS
			)
			-- groupFrames reuses `out`
			local out = { Hull = CFrame.new(), Turret = CFrame.new(), Gun = CFrame.new() }
			expect(ArmorGeometry.groupFrames(model, pose, out)).toBe(out)
		end)

		it("orders ties by rank: spaced exit before the armor entry behind it, armor entry before armor exit", function()
			local model = Fixtures.model()
			-- track outer x = 6, inner x = 4.5 == hull side
			local buf, count =
				ArmorGeometry.raycast(model, Fixtures.pose(), Vector3.new(30, 2, 0), Vector3.new(-1, 0, 0))
			local seq = kinds(buf, count)
			expect(seq[1]).toBe("5+")
			expect(seq[2]).toBe("5-")
			expect(seq[3]).toBe("1+")

			-- two Armor boxes sharing the face z = 0
			local shared = {
				volumes = {
					Fixtures.box({
						id = 1,
						group = "Hull",
						kind = "Armor",
						min = Vector3.new(-1, 0, -2),
						max = Vector3.new(1, 2, 0),
						thickness = 10,
						zone = "HullSide",
					}),
					Fixtures.box({
						id = 2,
						group = "Hull",
						kind = "Armor",
						min = Vector3.new(-1, 0, 0),
						max = Vector3.new(1, 2, 2),
						thickness = 10,
						zone = "HullSide",
					}),
				},
				boundsCenter = Vector3.new(0, 1, 0),
				boundsRadius = 4,
				pivots = Fixtures.model().pivots,
			}
			local b2, c2 = ArmorGeometry.raycast(shared, Fixtures.pose(), Vector3.new(0, 1, -10), Vector3.new(0, 0, 1))
			expect(kinds(b2, c2)).toEqual({ "1+", "2+", "1-", "2-" })
		end)

		it("reports only exits for a ray starting inside a volume, and nothing behind the origin", function()
			local model = Fixtures.model()
			local buf, count = ArmorGeometry.raycast(model, Fixtures.pose(), Vector3.new(0, 4, 0), Vector3.new(0, 0, 1))
			for i = 1, count do
				local c = buf.items[i]
				if c.volumeId == 1 then
					expect(c.entering).toBe(false)
				end
				expect(c.distance >= 0).toBe(true)
			end
		end)

		it("returns no crossings for misses and for degenerate or non-finite rays", function()
			local model = Fixtures.model()
			local pose = Fixtures.pose()
			local nan = 0 / 0
			local cases = {
				{ Vector3.new(0, 50, -30), Vector3.new(0, 0, 1) },
				{ Vector3.new(0, 2.5, -30), Vector3.new(0, 0, -1) },
				{ Vector3.new(0, 2.5, -30), Vector3.zero },
				{ Vector3.new(nan, 2.5, -30), Vector3.new(0, 0, 1) },
				{ Vector3.new(0, 2.5, -30), Vector3.new(0, nan, 1) },
				{ Vector3.new(0, 2.5, -30), Vector3.new(math.huge, 0, 1) },
				{ Vector3.new(math.huge, 2.5, -30), Vector3.new(0, 0, 1) },
			}
			for _, case in cases do
				local _, count = ArmorGeometry.raycast(model, pose, case[1], case[2])
				expect(count).toBe(0)
			end
			local _, nanMax = ArmorGeometry.raycast(model, pose, Vector3.new(0, 2.5, -30), Vector3.new(0, 0, 1), nan)
			expect(nanMax).toBe(0)
		end)

		it("reuses the buffer and its records between calls", function()
			local model = Fixtures.model()
			local buf = ArmorGeometry.newBuffer()
			local _, c1 = ArmorGeometry.raycast(model, Fixtures.pose(), Vector3.new(0, 2.5, -30), Vector3.new(0, 0, 1), nil, buf)
			local firstRecord = buf.items[1]
			local _, c2 = ArmorGeometry.raycast(model, Fixtures.pose(), Vector3.new(30, 7.5, 0), Vector3.new(-1, 0, 0), nil, buf)
			expect(c1).toBe(6)
			expect(buf.count).toBe(c2)
			local found = false
			for i = 1, c2 do
				if buf.items[i] == firstRecord then
					found = true
				end
			end
			expect(found).toBe(true)
		end)

		it("is deterministic and every crossing lies on its face plane (property, 2,000 seeded rays)", function()
			local model = Fixtures.model()
			local rng = RNG.new(1234)
			local buf = ArmorGeometry.newBuffer()
			local buf2 = ArmorGeometry.newBuffer()
			for _ = 1, 2000 do
				local pose = Fixtures.pose(
					CFrame.new(rng:range(-50, 50), rng:range(-5, 5), rng:range(-50, 50))
						* CFrame.Angles(rng:range(-0.3, 0.3), rng:range(-math.pi, math.pi), rng:range(-0.3, 0.3)),
					rng:range(-180, 180),
					rng:range(-8, 20)
				)
				local frames = ArmorGeometry.groupFrames(model, pose)
				local centre = pose.hullCFrame:PointToWorldSpace(Vector3.new(0, 4, 0))
				local origin = centre
					+ Vector3.new(rng:normal(0, 1), rng:normal(0, 1), rng:normal(0, 1)).Unit * 40
				local target = centre + Vector3.new(rng:range(-8, 8), rng:range(-5, 5), rng:range(-12, 12))
				local _, count = ArmorGeometry.raycast(model, pose, origin, target - origin, nil, buf)
				local _, again = ArmorGeometry.raycast(model, pose, origin, target - origin, nil, buf2)
				expect(again).toBe(count)
				local perVolume = {}
				for i = 1, count do
					local c = buf.items[i]
					expect(buf2.items[i].volumeId).toBe(c.volumeId)
					expect(buf2.items[i].distance).toBe(c.distance)
					if i > 1 then
						expect(c.distance >= buf.items[i - 1].distance - 1e-4).toBe(true)
					end
					-- point is on the face plane (in the group's local space)
					local frame = (frames :: any)[c.group]
					local lp = frame:PointToObjectSpace(c.point)
					expect(math.abs(c.face.normal:Dot(lp) - c.face.distance) < 2e-3).toBe(true)
					expect(math.abs(c.normal.Magnitude - 1) < EPS).toBe(true)
					local list = perVolume[c.volumeId] or {}
					perVolume[c.volumeId] = list
					table.insert(list, c)
				end
				-- from outside, each convex volume is crossed exactly twice: entry then exit
				for _, list in perVolume do
					expect(#list).toBe(2)
					expect(list[1].entering).toBe(true)
					expect(list[2].entering).toBe(false)
				end
			end
		end)
	end)

	describe("watertightness (REG-ARM-01)", function()
		it("10,000 seeded rays from outside aimed at the closed hull + turret all enter an Armor volume", function()
			local model = Fixtures.model()
			expect(ArmorGeometry.validate(model)).toEqual({})
			local rng = RNG.new(20261006)
			local total, leaks = 0, 0
			local examples = {}
			for p = 1, 20 do
				local pose = Fixtures.pose(
					CFrame.new(rng:range(-300, 300), rng:range(-10, 30), rng:range(-300, 300))
						* CFrame.Angles(rng:range(-0.4, 0.4), rng:range(-math.pi, math.pi), rng:range(-0.4, 0.4)),
					rng:range(-180, 180),
					if p % 2 == 0 then -8 else 20
				)
				local report = ArmorGeometry.probeLeaks(model, pose, rng:fork(p), 500)
				total += report.rays
				leaks += report.leaks
				for _, leak in report.firstLeaks do
					table.insert(examples, leak)
				end
			end
			expect(total).toBe(10000)
			if leaks > 0 then
				error(`{leaks} leaks, e.g. origin {examples[1].origin} -> target {examples[1].target}`)
			end
			expect(leaks).toBe(0)
		end)

		it("probeLeaks detects a real gap (a hull with a missing slab between two boxes)", function()
			local gapped = {
				volumes = {
					Fixtures.box({
						id = 1,
						group = "Hull",
						kind = "Armor",
						min = Vector3.new(-2, 0, -4),
						max = Vector3.new(2, 2, -0.5),
						thickness = 10,
						zone = "HullSide",
					}),
					Fixtures.box({
						id = 2,
						group = "Hull",
						kind = "Armor",
						min = Vector3.new(-2, 0, 0.5),
						max = Vector3.new(2, 2, 4),
						thickness = 10,
						zone = "HullSide",
					}),
				},
				boundsCenter = Vector3.new(0, 1, 0),
				boundsRadius = 5,
				pivots = Fixtures.model().pivots,
			}
			-- visual surface includes the slab z ∈ (−0.5, 0.5): sample targets there
			local report = ArmorGeometry.probeLeaks(gapped, Fixtures.pose(), RNG.new(5), 200, function(r)
				return Vector3.new(r:range(-1.9, 1.9), r:range(0.1, 1.9), r:range(-0.4, 0.4))
			end)
			expect(report.leaks).toBeGreaterThan(0)
			expect(#report.firstLeaks).toBeGreaterThan(0)
		end)
	end)

	describe("point and sphere queries", function()
		it("containsPoint / volumeAt find the right volume at a pose", function()
			local model = Fixtures.model()
			local pose = Fixtures.pose(CFrame.new(10, 0, 0), 90)
			expect(ArmorGeometry.volumeAt(model, pose, Vector3.new(10, 3, 6), { Module = true }).module).toBe("Engine")
			-- turret bustle rack after 90° yaw: turret z+ (rear) maps to world −X
			expect(ArmorGeometry.volumeAt(model, pose, Vector3.new(10 - 2.6, 7, 0), { Module = true }).id).toBe(14)
			expect(ArmorGeometry.volumeAt(model, pose, Vector3.new(10, 100, 0))).toBeNil()
			expect(ArmorGeometry.volumeAt(model, pose, Vector3.new(0 / 0, 0, 0))).toBeNil()
			local hull = model.volumes[1]
			expect(ArmorGeometry.containsPoint(hull, Vector3.new(0, 3, 0))).toBe(true)
			expect(ArmorGeometry.containsPoint(hull, Vector3.new(0, 6.0001, 0))).toBe(false)
			expect(ArmorGeometry.containsPoint(hull, Vector3.new(0, 6.0001, 0), 1e-3)).toBe(true)
		end)

		it("volumesNear returns module/crew volumes within the radius sorted by distance", function()
			local model = Fixtures.model()
			local near = ArmorGeometry.volumesNear(model, Fixtures.pose(), Vector3.new(4, 6, -5), 2.25)
			local ids = {}
			for i = 1, near.count do
				table.insert(ids, near.items[i].volume.id)
			end
			-- turret ring (plane distances 1, 0.1, 2 -> 2) and driver (0.5, 2, 1 -> 2): tie broken by id
			expect(ids).toEqual({ 12, 13 })
			expect(near.items[1].distance).toBeCloseTo(2, EPS)
			expect(near.items[2].distance).toBeCloseTo(2, EPS)
			-- inside a volume = 0; explicit kinds filter
			local inside = ArmorGeometry.volumesNear(model, Fixtures.pose(), Vector3.new(0, 3, 6), 0.1)
			expect(inside.count).toBe(1)
			expect(inside.items[1].distance).toBe(0)
			local spaced = ArmorGeometry.volumesNear(model, Fixtures.pose(), Vector3.new(6.5, 1, 0), 1, { Spaced = true })
			expect(spaced.count).toBe(1)
			expect(spaced.items[1].volume.module).toBe("TrackRight")
			expect(ArmorGeometry.volumesNear(model, Fixtures.pose(), Vector3.new(0, 3, 6), -1).count).toBe(0)
		end)

		it("nearestArmor reports distance and the thinnest facing plate", function()
			local model = Fixtures.model()
			local found, d, t = ArmorGeometry.nearestArmor(model, Fixtures.pose(), Vector3.new(0, 2.5, -10), 3)
			expect(found).toBe(true)
			expect(d).toBeCloseTo(1, EPS)
			expect(t).toBe(60)
			-- behind the rear plate, 0.75 studs away
			local f2, d2, t2 = ArmorGeometry.nearestArmor(model, Fixtures.pose(), Vector3.new(0, 3, 9.75), 2.25)
			expect(f2).toBe(true)
			expect(d2).toBeCloseTo(0.75, EPS)
			expect(t2).toBe(30)
			-- on the surface: distance 0
			local _, d3, t3 = ArmorGeometry.nearestArmor(model, Fixtures.pose(), Vector3.new(0, 7.5, -3.5), 1)
			expect(d3).toBe(0)
			expect(t3).toBe(80) -- mantlet (Layered) face at z −3.5 is the thinnest facing plate within 1 stud
			local f4 = ArmorGeometry.nearestArmor(model, Fixtures.pose(), Vector3.new(0, 40, 0), 2)
			expect(f4).toBe(false)
		end)
	end)

	describe("angles and thickness", function()
		it("impactAngleDeg: head-on 0, grazing 90, degenerate 90", function()
			expect(ArmorGeometry.impactAngleDeg(Vector3.new(0, 0, 1), Vector3.new(0, 0, -1))).toBeCloseTo(0, EPS)
			expect(ArmorGeometry.impactAngleDeg(Vector3.new(0, 0, 5), Vector3.new(0, 0, -2))).toBeCloseTo(0, EPS)
			expect(ArmorGeometry.impactAngleDeg(Vector3.new(1, 0, 0), Vector3.new(0, 0, -1))).toBeCloseTo(90, EPS)
			expect(ArmorGeometry.impactAngleDeg(Vector3.new(0, 0, 1), Vector3.new(0, 0, 1))).toBeCloseTo(180, EPS)
			expect(ArmorGeometry.impactAngleDeg(Vector3.zero, Vector3.new(0, 0, 1))).toBe(90)
			expect(ArmorGeometry.impactAngleDeg(Vector3.new(0 / 0, 0, 1), Vector3.new(0, 0, 1))).toBe(90)
		end)

		it("effectiveThickness = T / max(0.05, cos(max(0, θ − n)))", function()
			expect(ArmorGeometry.effectiveThickness(100, 0)).toBeCloseTo(100, EPS)
			expect(ArmorGeometry.effectiveThickness(100, 60)).toBeCloseTo(200, EPS)
			expect(ArmorGeometry.effectiveThickness(100, 60, 5)).toBeCloseTo(100 / math.cos(math.rad(55)), EPS)
			expect(ArmorGeometry.effectiveThickness(100, 4, 5)).toBeCloseTo(100, EPS)
			expect(ArmorGeometry.effectiveThickness(100, 89.9)).toBeCloseTo(2000, EPS)
			expect(ArmorGeometry.effectiveThickness(100, 120)).toBeCloseTo(2000, EPS)
		end)

		it("reflect mirrors about the normal", function()
			local r = ArmorGeometry.reflect(Vector3.new(0, 0, 1), Fixtures.GLACIS_NORMAL)
			expect(r).toBeCloseTo(Vector3.new(0, 0.6, 0.8), EPS)
		end)
	end)

	describe("validate", function()
		it("accepts the fixture and reports contract violations", function()
			expect(ArmorGeometry.validate(Fixtures.model())).toEqual({})
			local bad = Fixtures.model()
			bad.volumes[2].id = 1
			bad.volumes[3].faces[1].normal = Vector3.new(2, 0, 0)
			bad.volumes[4].faces[1].spaced = false
			bad.volumes[9].module = nil
			bad.volumes[13].crewSlot = nil
			bad.volumes[5].faces = { bad.volumes[5].faces[1] }
			bad.volumes[6].group = "Wing"
			bad.volumes[7].kind = "Foam"
			bad.volumes[8].radius = 0 / 0
			bad.volumes[10].faces[1].thicknessMm = -1
			bad.boundsRadius = 0
			local problems = ArmorGeometry.validate(bad)
			local text = table.concat(problems, "\n")
			for _, needle in
				{
					"duplicate id",
					"unit length",
					"spaced flag",
					"without a module",
					"without a crew slot",
					">= 4 faces",
					"unknown group",
					"unknown kind",
					"bounding sphere",
					"thickness",
					"model: bounds",
				}
			do
				expect(text).toContain(needle)
			end
		end)

		it("invalidate() drops the compiled cache so mutations are seen", function()
			local model = Fixtures.model()
			local pose = Fixtures.pose()
			local _, before = ArmorGeometry.raycast(model, pose, Vector3.new(0, 2.5, -30), Vector3.new(0, 0, 1))
			table.remove(model.volumes, 11) -- hull ammo rack
			ArmorGeometry.invalidate(model)
			local _, after = ArmorGeometry.raycast(model, pose, Vector3.new(0, 2.5, -30), Vector3.new(0, 0, 1))
			expect(after).toBe(before - 2)
		end)
	end)
end)
