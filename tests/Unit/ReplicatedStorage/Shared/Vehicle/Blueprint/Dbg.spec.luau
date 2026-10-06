local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect
local Decompose = require("@game/ReplicatedStorage/Shared/Vehicle/Blueprint/Decompose")
local Geometry = require("@game/ReplicatedStorage/Shared/Vehicle/Blueprint/Geometry")
local Shapes = require("@game/ReplicatedStorage/Shared/Vehicle/Blueprint/Shapes")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local function P(nx, ny, nz, px, py, pz)
	return Geometry.plane(nx, ny, nz, px, py, pz, "HullSide", 10)
end
describe("dbg", function()
	it("x", function()
		local rng = RNG.new(7101)
		for iter = 1, 60 do
			local planes = { P(0, 1, 0, 0, 1, 0), P(0, -1, 0, 0, 0, 0) }
			local n = rng:int(3, 9)
			for k = 1, n do
				local a = (k / n) * 2 * math.pi + rng:range(-0.2, 0.2)
				local r = rng:range(1, 4)
				table.insert(planes, P(math.cos(a), 0, math.sin(a), math.cos(a) * r, 0, math.sin(a) * r))
			end
			local poly = Geometry.section(planes, { 0.5 })
			local parts = Decompose.prism(poly, 0, 1)
			for pi, s in parts do
				for _, v in Shapes.vertices(s) do
					local d = Geometry.signedDistance(planes, v.X, v.Y, v.Z)
					if d > 1e-4 then
						print(iter, pi, s.shape, d, v, s.size)
						for _, p in poly do print("  poly", p.x, p.z, p.edge) end
						error("stop")
					end
				end
			end
		end
	end)
end)
