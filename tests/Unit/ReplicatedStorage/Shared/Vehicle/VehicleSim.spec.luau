local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect
local HeightmapWorld = require("@tests/Harness/HeightmapWorld")
local VehicleSim = require("@game/ReplicatedStorage/Shared/Vehicle/VehicleSim")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local DT = 1 / 30
local function makeStats(o)
	local s = {
		vehicleId = "t", massKg = 30000, enginePowerHp = 480, topSpeedKmh = 50, reverseSpeedKmh = 20,
		hullTraverseDegS = 36, terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
		dimensionsM = Vector3.new(3.2, 2.4, 6.6), pivot = true, mechanics = {}, conditionalModifiers = {},
	}
	for k, v in o or {} do s[k] = v end
	return s
end
local function cmd(t, s) return { seq = 0, throttle = t, steer = s, aimPoint = Vector3.zero, fire = false, holdTurret = false, brake = false, mechanic = false } end

describe("explore", function()
	it("fuzz", function()
		for seed = 1, 6 do
			local rng = RNG.new(seed)
			local boxes = {}
			for i = 1, 40 do
				local h = rng:range(0.5, 12)
				table.insert(boxes, { id = "b" .. i, cframe = CFrame.new(rng:range(-250, 250), h / 2 + 3 * math.sin(i), rng:range(-250, 250)) * CFrame.Angles(0, rng:range(0, 6.28), 0), size = Vector3.new(rng:range(2, 30), h, rng:range(2, 30)), destructible = rng:chance(0.2) })
			end
			local a1, a2, a3 = rng:range(5, 40), rng:range(10, 60), rng:range(0.5, 4)
			local world = HeightmapWorld.new({
				groundMaterial = function(x, z) return if x > 0 then "Mud" else "Concrete" end,
				waterLevel = -8,
				height = function(x, z) return a1 * math.sin(x / a2) * math.cos(z / (a2 * 0.7)) + a3 * math.sin(x * 0.3 + z * 0.2) end,
				boxes = boxes,
			})
			local stats = makeStats()
			local st = VehicleSim.newState(CFrame.new(rng:range(-100, 100), 0, rng:range(-100, 100)), { bounds = { minX = -300, maxX = 300, minZ = -300, maxZ = 300 } })
			local inp = cmd(0, 0)
			local worst = 0
			local counts = {}
			for i = 1, 30 * 60 do
				if i % 45 == 1 then inp.throttle = rng:range(-1, 1); inp.steer = rng:range(-1, 1); inp.brake = rng:chance(0.05) end
				local ev = VehicleSim.step(st, inp, stats, world, DT)
				for _, e in ev do counts[e.kind] = (counts[e.kind] or 0) + 1 end
				if st.wrecked then break end
				local g = world:groundAt(st.position.X, st.position.Z, st.position.Y + 0.15)
				if st.grounded and g then
					local below = g.position.Y - st.position.Y
					if below > worst then worst = below end
				end
			end
			local parts = {}
			for k, v in counts do table.insert(parts, k .. "=" .. v) end
			print(seed, "worst below", worst, st.position, st.nanResets, st.wrecked, table.concat(parts, " "))
		end
	end)
end)
