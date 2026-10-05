local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local HeightmapWorld = require("@tests/Harness/HeightmapWorld")

describe("HeightmapWorld terrain", function()
	it("raycasts onto flat ground with an up normal", function()
		local world = HeightmapWorld.new()
		local hit = world:raycast(Vector3.new(5, 10, 5), Vector3.new(0, -100, 0), "Shell")
		expect(hit).never.toBeNil()
		expect(hit.position).toBeCloseTo(Vector3.new(5, 0, 5), 1e-3)
		expect(hit.normal).toBeCloseTo(Vector3.new(0, 1, 0), 1e-3)
		expect(hit.distance).toBeCloseTo(10, 1e-3)
		expect(hit.material).toBe("Grass")
		expect(hit.destructible).toBe(false)
		expect(hit.objectId).toBeNil()
	end)

	it("respects the ray length and zero-length rays", function()
		local world = HeightmapWorld.new()
		expect(world:raycast(Vector3.new(0, 10, 0), Vector3.new(0, -5, 0), "Shell")).toBeNil()
		expect(world:raycast(Vector3.new(0, 10, 0), Vector3.zero, "Shell")).toBeNil()
	end)

	it("hits slopes with the analytic normal", function()
		-- Plane y = 0.5 x: normal is (-0.5, 1, 0) normalized.
		local world = HeightmapWorld.new({
			height = function(x, _z)
				return 0.5 * x
			end,
			step = 0.5,
		})
		local hit = world:raycast(Vector3.new(4, 50, 0), Vector3.new(0, -100, 0), "Ground")
		expect(hit.position.Y).toBeCloseTo(2, 1e-3)
		expect(hit.normal).toBeCloseTo(Vector3.new(-0.5, 1, 0).Unit, 1e-3)
		local horizontal = world:raycast(Vector3.new(-10, 1, 0), Vector3.new(100, 0, 0), "Shell")
		expect(horizontal.position.X).toBeCloseTo(2, 1e-3)
	end)

	it("groundAt casts down from a height and materials can vary", function()
		local world = HeightmapWorld.new({
			height = function(x, z)
				return math.sin(x * 0.1) * 3 + z * 0.01
			end,
			groundMaterial = function(x, _z)
				return if x > 0 then "Mud" else "Grass"
			end,
		})
		local hit = world:groundAt(10, 20, 100)
		expect(hit.position.Y).toBeCloseTo(math.sin(1) * 3 + 0.2, 1e-3)
		expect(hit.material).toBe("Mud")
		expect(world:groundAt(-10, 0, 100).material).toBe("Grass")
		expect(world:groundAt(0, 0, -50)).toBeNil()
	end)

	it("reports water depth only where the ground is under water", function()
		local world = HeightmapWorld.new({
			waterLevel = 0,
			height = function(x, _z)
				return if x < 0 then -5 else 2
			end,
		})
		expect(world:waterDepthAt(Vector3.new(-10, -3, 0))).toBe(3)
		expect(world:waterDepthAt(Vector3.new(-10, 1, 0))).toBe(0)
		expect(world:waterDepthAt(Vector3.new(10, -1, 0))).toBe(0)
		expect(HeightmapWorld.new():waterDepthAt(Vector3.new(0, -100, 0))).toBe(0)
	end)
end)

describe("HeightmapWorld boxes", function()
	local function world(): any
		return HeightmapWorld.new({
			boxes = {
				{ id = "rock", cframe = CFrame.new(0, 5, 20), size = Vector3.new(10, 10, 10), material = "Rock" },
				{
					id = "fence",
					cframe = CFrame.new(0, 2, 40),
					size = Vector3.new(10, 4, 1),
					destructible = true,
					material = "Wood",
				},
				{
					id = "glass",
					cframe = CFrame.new(0, 2, 60),
					size = Vector3.new(10, 4, 1),
					blocksSight = false,
				},
			},
		})
	end

	it("raycasts hit the nearest face with the face normal", function()
		local hit = world():raycast(Vector3.new(0, 5, 0), Vector3.new(0, 0, 100), "Shell")
		expect(hit.objectId).toBe("rock")
		expect(hit.distance).toBeCloseTo(15, 1e-6)
		expect(hit.normal).toBeCloseTo(Vector3.new(0, 0, -1), 1e-6)
		expect(hit.material).toBe("Rock")
	end)

	it("handles rotated boxes", function()
		local w = HeightmapWorld.new({
			boxes = {
				{
					id = "wedge",
					cframe = CFrame.new(0, 5, 20) * CFrame.Angles(0, math.rad(45), 0),
					size = Vector3.new(10, 10, 10),
				},
			},
		})
		local hit = w:raycast(Vector3.new(0, 5, 0), Vector3.new(0, 0, 100), "Shell")
		-- The rotated cube's corner points at the ray: distance = 20 - 5 * sqrt(2).
		expect(hit.distance).toBeCloseTo(20 - 5 * math.sqrt(2), 1e-4)
		expect(math.abs(hit.normal.Z)).toBeCloseTo(math.sqrt(0.5), 1e-4)
	end)

	it("applies mode filters for destructibles and sight blockers", function()
		local w = world()
		local shell = w:raycast(Vector3.new(0, 2, 30), Vector3.new(0, 0, 100), "Shell")
		expect(shell.objectId).toBe("fence")
		expect(shell.destructible).toBe(true)
		local sight = w:raycast(Vector3.new(0, 2, 50), Vector3.new(0, 0, 100), "Sight")
		expect(sight).toBeNil()
		local ground = w:raycast(Vector3.new(0, 10, 40), Vector3.new(0, -20, 0), "Ground")
		expect(ground.objectId).toBeNil()
		expect(ground.position.Y).toBeCloseTo(0, 1e-3)
		local onRock = w:groundAt(0, 20, 50)
		expect(onRock.objectId).toBe("rock")
		expect(onRock.position.Y).toBeCloseTo(10, 1e-6)
	end)

	it("destroyObject removes destructibles only", function()
		local w = world()
		w:destroyObject("fence")
		w:destroyObject("rock")
		expect(w:isDestroyed("fence")).toBe(true)
		expect(w:isDestroyed("rock")).toBe(false)
		local hit = w:raycast(Vector3.new(0, 2, 30), Vector3.new(0, 0, 100), "Shell")
		expect(hit.objectId).toBe("glass")
	end)

	it("rays starting inside geometry ignore it (Roblox semantics)", function()
		local w = world()
		expect(w:raycast(Vector3.new(0, 5, 20), Vector3.new(0, 0, 10), "Shell")).toBeNil()
		local exits = w:raycast(Vector3.new(0, 2, 20), Vector3.new(0, 0, 30), "Shell")
		expect(exits.objectId).toBe("fence")
		local underground = HeightmapWorld.new():raycast(Vector3.new(0, -5, 0), Vector3.new(0, 20, 0), "Shell")
		expect(underground).toBeNil()
	end)

	it("sweepBox finds the first contact along the displacement", function()
		local w = world()
		local hit = w:sweepBox(CFrame.new(0, 5, 0), Vector3.new(4, 4, 4), Vector3.new(0, 0, 30))
		expect(hit).never.toBeNil()
		expect(hit.objectId).toBe("rock")
		-- Front face of the mover (z + 2) touches the rock face at z = 15 after 13 studs.
		expect(hit.distance).toBeCloseTo(13, 0.01)
		expect(hit.normal).toBeCloseTo(Vector3.new(0, 0, -1), 1e-6)
		expect(w:sweepBox(CFrame.new(50, 5, 0), Vector3.new(4, 4, 4), Vector3.new(0, 0, 30))).toBeNil()
		local stuck = w:sweepBox(CFrame.new(0, 5, 20), Vector3.new(2, 2, 2), Vector3.new(1, 0, 0))
		expect(stuck.distance).toBe(0)
	end)
end)

describe("HeightmapWorld sight lines", function()
	it("sums foliage concealment, detects smoke and terrain blocking", function()
		local w = HeightmapWorld.new({
			height = function(x, _z)
				return if x > 40 and x < 60 then 20 else 0
			end,
			foliage = {
				{ id = "bush1", center = Vector3.new(10, 2, 0), radius = 3, concealment = 0.25 },
				{ id = "bush2", center = Vector3.new(20, 2, 0), radius = 3, concealment = 0.5 },
				{ id = "far", center = Vector3.new(20, 50, 0), radius = 3, concealment = 1 },
			},
			smoke = { { center = Vector3.new(30, 2, 0), radius = 4 } },
		})
		local clear = w:sightLine(Vector3.new(0, 2, 0), Vector3.new(25, 2, 0))
		expect(clear.blocked).toBe(false)
		expect(clear.foliage).toBeCloseTo(0.75, 1e-9)
		expect(clear.smoke).toBe(false)
		local smoky = w:sightLine(Vector3.new(0, 2, 0), Vector3.new(35, 2, 0))
		expect(smoky.smoke).toBe(true)
		local blocked = w:sightLine(Vector3.new(0, 2, 0), Vector3.new(100, 2, 0))
		expect(blocked.blocked).toBe(true)
		w:destroyObject("bush1")
		expect(w:sightLine(Vector3.new(0, 2, 0), Vector3.new(25, 2, 0)).foliage).toBeCloseTo(0.5, 1e-9)
		local same = w:sightLine(Vector3.new(1, 1, 1), Vector3.new(1, 1, 1))
		expect(same.blocked).toBe(false)
	end)

	it("foliage behind a blocker does not count", function()
		local w = HeightmapWorld.new({
			boxes = { { cframe = CFrame.new(15, 2, 0), size = Vector3.new(2, 10, 10) } },
			foliage = { { center = Vector3.new(25, 2, 0), radius = 3, concealment = 0.5 } },
		})
		local result = w:sightLine(Vector3.new(0, 2, 0), Vector3.new(30, 2, 0))
		expect(result.blocked).toBe(true)
		expect(result.foliage).toBe(0)
	end)
end)
