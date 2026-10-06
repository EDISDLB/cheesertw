-- Blueprint/Decompose: convex armor body -> Roblox parts. Exactness is proven by volume: every part lies inside the
-- body and the part volumes sum to the body volume, so the parts tile it with no gap and no overlap (REG-ARM-01
-- parity by construction; docs/design/vehicle-visuals.md §4).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Decompose = require("@game/ReplicatedStorage/Shared/Vehicle/Blueprint/Decompose")
local Geometry = require("@game/ReplicatedStorage/Shared/Vehicle/Blueprint/Geometry")
local Shapes = require("@game/ReplicatedStorage/Shared/Vehicle/Blueprint/Shapes")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local rad, tan = math.rad, math.tan

local function P(nx, ny, nz, px, py, pz)
	return Geometry.plane(nx, ny, nz, px, py, pz, "HullSide", 10)
end

-- Box [x0,x1] x [y0,y1] x [z0,z1] as planes.
local function boxPlanes(x0, x1, y0, y1, z0, z1)
	return {
		P(1, 0, 0, x1, 0, 0),
		P(-1, 0, 0, x0, 0, 0),
		P(0, 1, 0, 0, y1, 0),
		P(0, -1, 0, 0, y0, 0),
		P(0, 0, 1, 0, 0, z1),
		P(0, 0, -1, 0, 0, z0),
	}
end

-- Hull-like stack: lower plate, glacis, sloped sides above `ys`, sloped rear.
local function hullPlanes(L, W, H, gc, yN, aLow, aUp, aRear, sideDeg, ys)
	local planes = {
		P(0, -1, 0, 0, gc, 0),
		P(0, 1, 0, 0, H, 0),
		P(0, -math.sin(rad(aLow)), -math.cos(rad(aLow)), 0, yN, -L / 2),
		P(0, math.sin(rad(aUp)), -math.cos(rad(aUp)), 0, yN, -L / 2),
		P(0, math.sin(rad(aRear)), math.cos(rad(aRear)), 0, gc, L / 2),
		P(1, 0, 0, W / 2, 0, 0),
		P(-1, 0, 0, -W / 2, 0, 0),
	}
	if sideDeg > 0 then
		table.insert(planes, P(math.cos(rad(sideDeg)), math.sin(rad(sideDeg)), 0, W / 2, ys, 0))
		table.insert(planes, P(-math.cos(rad(sideDeg)), math.sin(rad(sideDeg)), 0, -W / 2, ys, 0))
	end
	return planes
end

local function tile(planes)
	local pruned, verts = Geometry.prune(planes)
	local pieces = Decompose.body(pruned, verts)
	local sum = 0
	for _, piece in pieces do
		sum += Shapes.volume(piece.spec)
	end
	return pruned, verts, pieces, sum, Geometry.volume(pruned, verts)
end

local function allInside(planes, pieces)
	for _, piece in pieces do
		for _, v in Shapes.vertices(piece.spec) do
			if Geometry.signedDistance(planes, v.X, v.Y, v.Z) > 1e-3 then
				return false
			end
		end
	end
	return true
end

local function covered(pieces, point)
	for _, piece in pieces do
		if Shapes.contains(piece.spec, point, 1e-3) then
			return true
		end
	end
	return false
end

describe("Decompose.prism", function()
	it("a rectangle is one block", function()
		local poly = Geometry.section(boxPlanes(-2, 2, 0, 1, -3, 3), { 0.5 })
		local parts = Decompose.prism(poly, 0, 1)
		expect(#parts).toBe(1)
		expect(parts[1].shape).toBe("Block")
		expect(parts[1].size).toBeCloseTo(Vector3.new(4, 1, 6), 1e-5)
	end)

	it("an octagon is 3 blocks + 4 corner wedges whose volume equals area × height", function()
		local c = 1
		local planes = boxPlanes(-3, 3, 0, 2, -4, 4)
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				-- corner cut through (sx·(3 − c), sz·4) and (sx·3, sz·(4 − c))
				table.insert(planes, P(sx, 0, sz, sx * (3 - c), 0, sz * 4))
			end
		end
		local poly = Geometry.section(planes, { 1 })
		expect(#poly).toBe(8)
		local parts = Decompose.prism(poly, 0, 2)
		expect(#parts).toBe(7)
		local vol = 0
		for _, s in parts do
			vol += Shapes.volume(s)
		end
		expect(vol).toBeCloseTo(math.abs(Geometry.polyArea(poly)) * 2, 1e-4)
	end)

	it("random convex polygons are tiled exactly (seeded property test)", function()
		local rng = RNG.new(7101)
		for _ = 1, 60 do
			local planes = { P(0, 1, 0, 0, 1, 0), P(0, -1, 0, 0, 0, 0) }
			local n = rng:int(3, 9)
			for k = 1, n do
				local a = (k / n) * 2 * math.pi + rng:range(-0.2, 0.2)
				local r = rng:range(1, 4)
				table.insert(planes, P(math.cos(a), 0, math.sin(a), math.cos(a) * r, 0, math.sin(a) * r))
			end
			local poly = Geometry.section(planes, { 0.5 })
			local parts = Decompose.prism(poly, 0, 1)
			local vol = 0
			for _, s in parts do
				vol += Shapes.volume(s)
				for _, v in Shapes.vertices(s) do
					expect(Geometry.signedDistance(planes, v.X, v.Y, v.Z) <= 1e-4).toBe(true)
				end
			end
			expect(vol).toBeCloseTo(math.abs(Geometry.polyArea(poly)), 1e-4)
		end
	end)
end)

describe("Decompose.body", function()
	it("a box body is a single block", function()
		local _, _, pieces, sum, vol = tile(boxPlanes(-1, 1, 0, 2, -3, 3))
		expect(#pieces).toBe(1)
		expect(sum).toBeCloseTo(vol, 1e-6)
	end)

	it("a hull profile (lower plate, glacis, rear plate) is tiled exactly with wedges on the plates", function()
		local planes, _, pieces, sum, vol = tile(hullPlanes(18, 6, 4.5, 1.2, 2.6, 30, 55, 12, 0, 0))
		expect(allInside(planes, pieces)).toBe(true)
		expect(sum).toBeCloseTo(vol, vol * 1e-6)
		local wedges = 0
		for _, piece in pieces do
			if piece.kind == "wedge" then
				wedges += 1
			end
		end
		expect(wedges).toBeGreaterThanOrEqual(3) -- lower plate, glacis, rear plate (rear spans two slabs)
	end)

	it("sloped sides above the nose add side wedges and corner wedges, still exact", function()
		local planes, _, pieces, sum, vol = tile(hullPlanes(18, 6, 4.5, 1.2, 2.6, 30, 55, 12, 20, 2.6))
		expect(allInside(planes, pieces)).toBe(true)
		expect(sum).toBeCloseTo(vol, vol * 1e-6)
		local corners = 0
		for _, piece in pieces do
			if piece.kind == "corner" then
				corners += 1
				expect(piece.spec.shape).toBe("CornerWedge")
			end
		end
		expect(corners).toBeGreaterThanOrEqual(4) -- glacis × 2 sides, rear × 2 sides
	end)

	it("random axis-aligned stacks are tiled exactly (seeded property test, 80 bodies)", function()
		local rng = RNG.new(424242)
		for _ = 1, 80 do
			local L, W = rng:range(10, 25), rng:range(4, 9)
			local gc = rng:range(0.5, 1.5)
			local H = gc + rng:range(2, 5)
			local yN = gc + (H - gc) * rng:range(0.15, 0.85)
			local aLow = rng:range(0, 60)
			local aUp = rng:range(0, 70)
			local aRear = rng:range(0, 40)
			-- keep the plates from crossing: total runs below the length
			while (yN - gc) * tan(rad(aLow)) + (H - yN) * tan(rad(aUp)) + (H - gc) * tan(rad(aRear)) > 0.8 * L do
				aUp *= 0.8
				aRear *= 0.8
				aLow *= 0.8
			end
			local side = if rng:chance(0.5) then rng:range(5, 30) else 0
			local planes, verts, pieces, sum, vol = tile(hullPlanes(L, W, H, gc, yN, aLow, aUp, aRear, side, yN))
			expect(#verts >= 8).toBe(true)
			expect(allInside(planes, pieces)).toBe(true)
			expect(sum).toBeCloseTo(vol, vol * 1e-5)
		end
	end)

	it("oblique faces (pike nose) are approximated from inside with a small volume deficit", function()
		local planes = hullPlanes(18, 6, 4.5, 1.2, 2.6, 30, 0, 12, 0, 0)
		-- replace the vertical upper front by two yawed glacis plates meeting on the centre ridge
		table.remove(planes, 4)
		local a, psi = rad(55), rad(25)
		for _, s in { -1, 1 } do
			local nx, ny, nz = -math.cos(a) * math.sin(s * psi), math.sin(a), -math.cos(a) * math.cos(psi)
			table.insert(planes, P(nx, ny, nz, 0, 2.6, -9))
		end
		local pruned, _, pieces, sum, vol = tile(planes)
		expect(allInside(pruned, pieces)).toBe(true)
		expect(sum).toBeLessThanOrEqual(vol * (1 + 1e-6))
		expect(sum).toBeGreaterThan(vol * 0.97)
		-- interior points away from the nose are covered
		local rng = RNG.new(5)
		for _ = 1, 300 do
			local p = Vector3.new(rng:range(-2.9, 2.9), rng:range(1.3, 4.4), rng:range(-3, 8.5))
			if Geometry.contains(pruned, p, 0.05) then
				expect(covered(pieces, p)).toBe(true)
			end
		end
	end)

	it("returns nothing for an empty body", function()
		local planes = { P(1, 0, 0, -1, 0, 0), P(-1, 0, 0, -1, 0, 0), P(0, 1, 0, 0, 1, 0), P(0, -1, 0, 0, 0, 0) }
		local pruned, verts = Geometry.prune(planes)
		expect(#Decompose.body(pruned, verts)).toBe(0)
	end)
end)
