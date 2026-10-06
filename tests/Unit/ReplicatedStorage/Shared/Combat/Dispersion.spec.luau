local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Dispersion = require("@game/ReplicatedStorage/Shared/Combat/Dispersion")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Fixtures = require("./CombatFixtures")

local function gun(overrides: { [string]: any }?): any
	local g: { [string]: any } = { dispersionM100 = 0.4, aimTimeS = 2, bloom = Dispersion.defaultBloom("medium") }
	if overrides then
		for k, v in overrides do
			g[k] = v
		end
	end
	return g
end

local STILL = { hullSpeedKmh = 0, hullTraverseDegS = 0, turretTraverseDegS = 0 }

describe("Dispersion", function()
	describe("bloom target (00-DECISIONS §3)", function()
		it("combines factors as a root sum of squares", function()
			local bloom = Dispersion.defaultBloom("medium")
			expect(Dispersion.targetMultiplier(bloom, STILL)).toBe(1)
			-- √(1 + (0.07 × 50)²) = 3.640
			expect(
				Dispersion.targetMultiplier(bloom, { hullSpeedKmh = 50, hullTraverseDegS = 0, turretTraverseDegS = 0 })
			).toBeCloseTo(math.sqrt(1 + 3.5 ^ 2), 1e-12)
			-- + hull 20°/s (1.5) + turret 30°/s (0.9)
			local m = Dispersion.targetMultiplier(
				bloom,
				{ hullSpeedKmh = 50, hullTraverseDegS = 20, turretTraverseDegS = 30 }
			)
			expect(m).toBeCloseTo(math.sqrt(1 + 3.5 ^ 2 + 1.5 ^ 2 + 0.9 ^ 2), 1e-12)
			-- negative speeds / rates count by magnitude
			expect(
				Dispersion.targetMultiplier(
					bloom,
					{ hullSpeedKmh = -50, hullTraverseDegS = -20, turretTraverseDegS = -30 }
				)
			).toBe(m)
		end)

		it("multiplies by the damaged-gun, wheeled-moving and stun factors", function()
			local bloom = Dispersion.defaultBloom("medium")
			local base = { hullSpeedKmh = 10, hullTraverseDegS = 0, turretTraverseDegS = 0 }
			local m0 = Dispersion.targetMultiplier(bloom, base)
			expect(Dispersion.targetMultiplier(bloom, {
				hullSpeedKmh = 10,
				hullTraverseDegS = 0,
				turretTraverseDegS = 0,
				gunDamaged = true,
			})).toBeCloseTo(m0 * 1.5, 1e-12)
			expect(Dispersion.targetMultiplier(bloom, {
				hullSpeedKmh = 10,
				hullTraverseDegS = 0,
				turretTraverseDegS = 0,
				wheeledMoving = true,
				stunned = true,
			})).toBeCloseTo(m0 * 1.15 * 1.2, 1e-12)
		end)

		it("ignores non-finite factors and clamps runaway values", function()
			local bloom = Dispersion.defaultBloom("heavy")
			expect(bloom.afterShot).toBe(3.5)
			expect(Dispersion.defaultBloom("artillery").afterShot).toBe(4)
			expect(Dispersion.defaultBloom(nil).afterShot).toBe(3)
			expect(
				Dispersion.targetMultiplier(
					bloom,
					{ hullSpeedKmh = 0 / 0, hullTraverseDegS = math.huge, turretTraverseDegS = 0 }
				)
			).toBe(1)
			expect(
				Dispersion.targetMultiplier(bloom, { hullSpeedKmh = 1e9, hullTraverseDegS = 0, turretTraverseDegS = 0 })
			).toBe(40)
		end)
	end)

	describe("convergence", function()
		it("decays by e every τ seconds and never below the target", function()
			local s = Dispersion.new(gun())
			Dispersion.update(s, 0, STILL)
			Dispersion.onShot(s) -- 1 × 3
			expect(s.multiplier).toBe(3)
			for _ = 1, 60 do
				Dispersion.update(s, 2 / 60, STILL)
			end
			expect(s.multiplier).toBeCloseTo(3 / math.exp(1), 1e-9)
			expect(Dispersion.timeToAim(s)).toBeCloseTo(2 * math.log(3 / math.exp(1)), 1e-9)
			for _ = 1, 600 do
				Dispersion.update(s, 1 / 30, STILL)
			end
			expect(s.multiplier).toBe(1)
			expect(Dispersion.timeToAim(s)).toBe(0)
		end)

		it("jumps up immediately to a higher target (bloom is instant)", function()
			local s = Dispersion.new(gun())
			Dispersion.update(s, 1 / 30, { hullSpeedKmh = 50, hullTraverseDegS = 0, turretTraverseDegS = 0 })
			expect(s.multiplier).toBeCloseTo(math.sqrt(1 + 3.5 ^ 2), 1e-12)
		end)

		it("after-shot bloom: M = max(M, M_target) × afterShot", function()
			local s = Dispersion.new(gun())
			Dispersion.update(s, 1 / 30, { hullSpeedKmh = 20, hullTraverseDegS = 0, turretTraverseDegS = 0 })
			local target = s.target
			s.multiplier = 1 -- below target (e.g. a stale value)
			Dispersion.onShot(s)
			expect(s.multiplier).toBeCloseTo(target * 3, 1e-12)
			Dispersion.onShot(s, 1.5) -- dual-gun volley override
			expect(s.multiplier).toBeCloseTo(target * 4.5, 1e-12)
			Dispersion.reset(s)
			expect(s.multiplier).toBe(1)
		end)

		it("aimTimeMul scales τ; zero aim time snaps; bad dt does not decay", function()
			local a = Dispersion.new(gun())
			local b = Dispersion.new(gun())
			a.multiplier, b.multiplier = 3, 3
			Dispersion.update(a, 1, { hullSpeedKmh = 0, hullTraverseDegS = 0, turretTraverseDegS = 0, aimTimeMul = 2 })
			Dispersion.update(b, 2, STILL)
			expect(a.multiplier).toBeCloseTo(3 * math.exp(-0.25), 1e-12) -- τ = 4 s for 1 s
			expect(b.multiplier).toBeCloseTo(3 * math.exp(-1), 1e-12) -- τ = 2 s for 2 s
			local snap = Dispersion.new(gun({ aimTimeS = 0 }))
			snap.multiplier = 5
			Dispersion.update(snap, 1 / 30, STILL)
			expect(snap.multiplier).toBe(1)
			local c = Dispersion.new(gun())
			c.multiplier = 3
			Dispersion.update(c, 0 / 0, STILL)
			Dispersion.update(c, -1, STILL)
			expect(c.multiplier).toBe(3)
		end)

		it("radius at 100 m and at distance (linear), with the extra multiplier", function()
			local s = Dispersion.new(gun())
			Dispersion.update(
				s,
				0,
				{ hullSpeedKmh = 0, hullTraverseDegS = 0, turretTraverseDegS = 0, dispersionMul = 1.1 }
			)
			expect(Dispersion.radiusM100(s)).toBeCloseTo(0.44, 1e-12)
			expect(Dispersion.radiusAt(s, 300)).toBeCloseTo(1.32, 1e-12)
			expect(Dispersion.radiusAt(s, -5)).toBe(0)
		end)
	end)

	describe("sampling", function()
		it("radial model: never outside the circle; P(r <= σ) ≈ 0.715 (|N| truncated at 2σ)", function()
			local rng = RNG.new(8)
			local n, inside = 100000, 0
			for _ = 1, n do
				local x, y = Dispersion.sampleOffset(2, rng, "radial")
				local r = math.sqrt(x * x + y * y)
				expect(r <= 2 + 1e-9).toBe(true)
				if r <= 1 then
					inside += 1
				end
			end
			expect(inside / n).toBeCloseTo(0.6827 / 0.9545, 0.01)
		end)

		it("gauss2d model: never outside the circle; P(r <= σ) ≈ 0.455", function()
			local rng = RNG.new(9)
			local n, inside = 50000, 0
			for _ = 1, n do
				local x, y = Dispersion.sampleOffset(2, rng, "gauss2d")
				local r = math.sqrt(x * x + y * y)
				expect(r <= 2 + 1e-9).toBe(true)
				if r <= 1 then
					inside += 1
				end
			end
			expect(inside / n).toBeCloseTo((1 - math.exp(-0.5)) / (1 - math.exp(-2)), 0.012)
		end)

		it("clamps to the rim after DISPERSION_RESAMPLE_TRIES out-of-circle draws", function()
			local x, y = Dispersion.sampleOffset(2, Fixtures.scriptedRng({ 5 }, { 0 }), "radial")
			expect(math.sqrt(x * x + y * y)).toBeCloseTo(2, 1e-12)
			local gx, gy = Dispersion.sampleOffset(2, Fixtures.scriptedRng({ 5, 5 }), "gauss2d")
			expect(math.sqrt(gx * gx + gy * gy)).toBeCloseTo(2, 1e-12)
			expect(Dispersion.sampleOffset(0, RNG.new(1))).toBe(0)
		end)

		it("sampleDirection deviates the aim by at most atan(R / 100)", function()
			local rng = RNG.new(10)
			local aims = { Vector3.new(0, 0, -1), Vector3.new(1, 2, 3), Vector3.new(0, 1, 0), Vector3.new(0, -5, 0.01) }
			for _, aim in aims do
				for _ = 1, 2000 do
					local dir = Dispersion.sampleDirection(aim, 0.5, rng)
					expect(math.abs(dir.Magnitude - 1) < 1e-5).toBe(true)
					local angle = math.acos(math.clamp(dir:Dot(aim.Unit), -1, 1))
					expect(angle <= math.atan(0.5 / 100) + 1e-5).toBe(true)
				end
			end
			expect(Dispersion.sampleDirection(Vector3.new(0, 0, -2), 0, rng)).toBeCloseTo(Vector3.new(0, 0, -1), 1e-6)
			expect(Dispersion.sampleDirection(Vector3.zero, 0.5, rng)).toBe(Vector3.new(0, 0, -1))
		end)

		it("is deterministic per seed", function()
			local a, b = RNG.new(77), RNG.new(77)
			for _ = 1, 100 do
				expect(Dispersion.sampleDirection(Vector3.new(1, 0, 0), 0.4, a)).toBe(
					Dispersion.sampleDirection(Vector3.new(1, 0, 0), 0.4, b)
				)
			end
		end)
	end)
end)
