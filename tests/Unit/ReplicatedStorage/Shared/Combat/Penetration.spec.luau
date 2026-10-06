local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Penetration = require("@game/ReplicatedStorage/Shared/Combat/Penetration")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Fixtures = require("./CombatFixtures")

local function round(x: number): number
	return math.floor(x + 0.5)
end

describe("Penetration", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	describe("rolls (00-DECISIONS §1 RNG, REG-ARM-07)", function()
		it("100,000 rolls stay within ±25 % and average to the mean within 0.5 %", function()
			local rng = RNG.new(42)
			local sum, sq = 0, 0
			local n = 100000
			local lo, hi = math.huge, -math.huge
			for _ = 1, n do
				local v = Penetration.roll(200, rng)
				sum += v
				sq += (v - 200) ^ 2
				lo = math.min(lo, v)
				hi = math.max(hi, v)
			end
			expect(lo >= 150 - 1e-9).toBe(true)
			expect(hi <= 250 + 1e-9).toBe(true)
			local mean = sum / n
			expect(math.abs(mean - 200) / 200 < 0.005).toBe(true)
			-- normal truncated at ±2σ: sd = σ·0.8796 = 25 × 0.8796 = 21.99
			local sd = math.sqrt(sq / n)
			expect(sd).toBeCloseTo(21.99, 0.3)
		end)

		it("competitive spread keeps rolls within ±10 %", function()
			local rng = RNG.new(43)
			local spread = Penetration.spreadFor(true)
			expect(spread).toBe(0.10)
			expect(Penetration.spreadFor(false)).toBe(0.25)
			for _ = 1, 20000 do
				local v = Penetration.roll(100, rng, spread)
				expect(v >= 90 - 1e-9 and v <= 110 + 1e-9).toBe(true)
			end
		end)

		it("re-rolls out-of-range draws and clamps after ROLL_RESAMPLE_TRIES", function()
			-- first draw z = 3 (out), second z = 1 (in): 100 × (1 + 0.25 × 1/2)
			expect(Penetration.roll(100, Fixtures.scriptedRng({ 3, 1 }))).toBeCloseTo(112.5, 1e-12)
			-- always out of range: clamped to the rim
			expect(Penetration.roll(100, Fixtures.scriptedRng({ 5 }))).toBeCloseTo(125, 1e-12)
			expect(Penetration.roll(100, Fixtures.scriptedRng({ -9 }))).toBeCloseTo(75, 1e-12)
		end)

		it("damage rolls are whole HP inside [round(0.75α), round(1.25α)] and deterministic per seed", function()
			for _, alpha in { 1, 40, 45, 115, 390, 515 } do
				local rng = RNG.new(alpha)
				for _ = 1, 5000 do
					local d = Penetration.rollDamage(alpha, rng)
					expect(d % 1).toBe(0)
					expect(d >= round(0.75 * alpha) and d <= round(1.25 * alpha)).toBe(true)
				end
			end
			local a, b = RNG.new(5), RNG.new(5)
			for _ = 1, 100 do
				expect(Penetration.rollDamage(220, a)).toBe(Penetration.rollDamage(220, b))
			end
		end)

		it("degenerate means roll safely", function()
			local rng = RNG.new(1)
			expect(Penetration.roll(0, rng)).toBe(0)
			expect(Penetration.roll(0 / 0, rng)).toBe(0)
			expect(Penetration.roll(math.huge, rng)).toBe(0)
			expect(Penetration.roll(100, rng, 0)).toBe(100)
			expect(Penetration.rollDamage(-5, rng)).toBe(0)
		end)

		it("rollPenetration applies falloff before the roll", function()
			local ap = Fixtures.shell("AP")
			-- z = 0 -> exactly the mean at that distance
			expect(Penetration.rollPenetration(ap, 300, Fixtures.scriptedRng({ 0 }))).toBeCloseTo(95, 1e-12)
		end)
	end)

	describe("2- and 3-calibre rules (REG-ARM-03)", function()
		it("boundaries are exclusive: boost only when cal > 2T, overmatch only when cal > 3T", function()
			local cases = {
				{ ratio = 1.99, two = false, three = false },
				{ ratio = 2.00, two = false, three = false },
				{ ratio = 2.01, two = true, three = false },
				{ ratio = 2.99, two = true, three = false },
				{ ratio = 3.00, two = true, three = false },
				{ ratio = 3.01, two = true, three = true },
			}
			for _, case in cases do
				local t = 120 / case.ratio
				expect(Penetration.isTwoCaliber("AP", 120, t)).toBe(case.two)
				expect(Penetration.isOvermatch("AP", 120, t)).toBe(case.three)
				expect(Penetration.isOvermatch("APCR", 120, t)).toBe(case.three)
				-- never for HEAT / HE
				expect(Penetration.isTwoCaliber("HEAT", 120, t)).toBe(false)
				expect(Penetration.isOvermatch("HEAT", 120, t)).toBe(false)
				expect(Penetration.isOvermatch("HE", 120, t)).toBe(false)
			end
		end)

		it("normalization: AP 5°, APCR 2°, boosted n·1.4·cal/(2T), HEAT/HE 0", function()
			local ap = Fixtures.shell("AP", { caliberMm = 100 })
			expect(Penetration.normalizationDeg(ap, 60)).toBe(5)
			local n, two = Penetration.normalizationDeg(ap, 40) -- cal/T = 2.5
			expect(two).toBe(true)
			expect(n).toBeCloseTo(5 * 1.4 * 100 / 80, 1e-12) -- 8.75°
			local apcr = Fixtures.shell("APCR", { caliberMm = 100 })
			expect((Penetration.normalizationDeg(apcr, 40))).toBeCloseTo(3.5, 1e-12)
			expect((Penetration.normalizationDeg(Fixtures.shell("HEAT"), 10))).toBe(0)
			expect((Penetration.normalizationDeg(Fixtures.shell("HE"), 10))).toBe(0)
			expect((Penetration.normalizationDeg(Fixtures.shell("AP", { normalizationDeg = 0 / 0 }), 100))).toBe(0)
		end)
	end)

	describe("ricochet", function()
		it("thresholds are strict: AP/APCR > 70°, HEAT > 85°, HE/HESH never", function()
			local ap = Fixtures.shell("AP")
			expect(Penetration.ricochets(ap, 100, 70)).toBe(false)
			expect(Penetration.ricochets(ap, 100, 70.01)).toBe(true)
			local heat = Fixtures.shell("HEAT")
			expect(Penetration.ricochets(heat, 100, 85)).toBe(false)
			expect(Penetration.ricochets(heat, 100, 85.01)).toBe(true)
			expect(Penetration.ricochets(Fixtures.shell("HE"), 100, 89.9)).toBe(false)
			expect(Penetration.ricochets(Fixtures.shell("HESH"), 100, 89.9)).toBe(false)
		end)

		it("overmatch prevents kinetic ricochets but not HEAT ones", function()
			local ap = Fixtures.shell("AP") -- 75 mm
			expect(Penetration.ricochets(ap, 25, 85)).toBe(true) -- exactly 3T (75 = 3 × 25): not overmatched
			expect(Penetration.ricochets(ap, 24.9, 85)).toBe(false) -- overmatched
			expect(Penetration.ricochets(Fixtures.shell("HEAT"), 10, 86)).toBe(true)
		end)

		it("ricochet keeps 75 % pen for kinetic, 100 % for HEAT", function()
			local r = Penetration.resolvePlate(Fixtures.shell("AP"), "Main", 100, 75, 120)
			expect(r.outcome).toBe("Ricochet")
			expect(r.penAfter).toBeCloseTo(90, 1e-12)
			local h = Penetration.resolvePlate(Fixtures.shell("HEAT"), "Main", 100, 87, 120)
			expect(h.outcome).toBe("Ricochet")
			expect(h.penAfter).toBe(120)
			expect(Penetration.ricochetPenMul("HE")).toBe(1)
		end)
	end)

	describe("resolvePlate", function()
		it("main plate: pen >= T_eff penetrates (hand-computed, n = 5°)", function()
			local ap = Fixtures.shell("AP") -- 75 mm vs 50 mm: no 2-cal boost (75 < 100)
			local tEff = 50 / math.cos(math.rad(55))
			local r = Penetration.resolvePlate(ap, "Main", 50, 60, 100)
			expect(r.outcome).toBe("Penetrated")
			expect(r.effectiveMm).toBeCloseTo(tEff, 1e-9)
			expect(r.penAfter).toBeCloseTo(100 - tEff, 1e-9)
			expect(r.normalizationDeg).toBe(5)
			expect(r.twoCaliber).toBe(false)
			local s = Penetration.resolvePlate(ap, "Main", 50, 60, 80)
			expect(s.outcome).toBe("Stopped")
			-- equality penetrates
			expect(Penetration.resolvePlate(ap, "Main", 50, 0, 50).outcome).toBe("Penetrated")
		end)

		it("2-calibre boost lowers T_eff on thin sloped plates", function()
			local ap = Fixtures.shell("AP") -- 75 mm vs 30 mm (2.5×): n' = 5·1.4·75/60 = 8.75
			local r = Penetration.resolvePlate(ap, "Main", 30, 65, 100)
			expect(r.twoCaliber).toBe(true)
			expect(r.normalizationDeg).toBeCloseTo(8.75, 1e-12)
			expect(r.effectiveMm).toBeCloseTo(30 / math.cos(math.rad(65 - 8.75)), 1e-9)
		end)

		it("spaced / layered plates subtract T_eff and continue", function()
			local ap = Fixtures.shell("AP")
			local r = Penetration.resolvePlate(ap, "Spaced", 10, 0, 100)
			expect(r.outcome).toBe("Penetrated")
			expect(r.penAfter).toBeCloseTo(90, 1e-12)
			local l = Penetration.resolvePlate(ap, "Layered", 80, 0, 70)
			expect(l.outcome).toBe("Stopped")
			expect(l.penAfter).toBeCloseTo(-10, 1e-12)
		end)

		it("HE / HESH pay 3 T on spaced plates (1.13 example: 100 mm through 20 mm leaves 40, REG-ARM-05)", function()
			local he = Fixtures.shell("HE")
			local r = Penetration.resolvePlate(he, "Spaced", 20, 30, 100)
			expect(r.outcome).toBe("Penetrated")
			expect(r.penAfter).toBe(40)
			expect(r.effectiveMm).toBe(60)
			expect(Penetration.resolvePlate(he, "Spaced", 13, 0, 38).outcome).toBe("Stopped") -- 38 − 39 <= 0
			expect(Penetration.resolvePlate(he, "Spaced", 38 / 3, 0, 38).outcome).toBe("Stopped") -- exactly 0
			-- main plate: no normalization, no ricochet even at 89°
			local m = Penetration.resolvePlate(he, "Main", 20, 60, 41)
			expect(m.outcome).toBe("Penetrated")
			expect(m.effectiveMm).toBeCloseTo(40, 1e-9)
			expect(Penetration.resolvePlate(he, "Main", 20, 89, 38).outcome).toBe("Stopped")
		end)

		it("garbage input never penetrates and reuses the result table", function()
			local ap = Fixtures.shell("AP")
			local out = Penetration.newPlateResult()
			expect(Penetration.resolvePlate(ap, "Main", 0 / 0, 0, 100, out)).toBe(out)
			expect(out.outcome).toBe("Stopped")
			expect(Penetration.resolvePlate(ap, "Main", 50, 0, 0 / 0, out).outcome).toBe("Stopped")
		end)

		it("effectiveThickness uses the shell's normalization", function()
			expect(Penetration.effectiveThickness(Fixtures.shell("AP"), 100, 45)).toBeCloseTo(
				100 / math.cos(math.rad(40)),
				1e-9
			)
			expect(Penetration.effectiveThickness(Fixtures.shell("HEAT"), 100, 45)).toBeCloseTo(
				100 / math.cos(math.rad(45)),
				1e-9
			)
		end)
	end)

	describe("HEAT air gap (REG-ARM-05)", function()
		it("loses 5 % per 10 cm (linear 50 %/m), never below 0", function()
			expect(Penetration.heatGapFactor(0.1)).toBeCloseTo(0.95, 1e-12)
			expect(Penetration.heatGapFactor(1)).toBeCloseTo(0.5, 1e-12)
			expect(Penetration.heatGapFactor(2)).toBe(0)
			expect(Penetration.heatGapFactor(3)).toBe(0)
			expect(Penetration.heatGapFactor(0)).toBe(1)
			expect(Penetration.heatGapFactor(-1)).toBe(1)
			expect(Penetration.heatGapFactor(0 / 0)).toBe(1)
		end)

		it("follows live overrides of HEAT_GAP_LOSS_PER_M", function()
			expect(Config.applyOverrides({ Combat = { HEAT_GAP_LOSS_PER_M = 0.25 } })).toBeOk()
			expect(Penetration.heatGapFactor(1)).toBeCloseTo(0.75, 1e-12)
		end)
	end)

	it("classifies families", function()
		expect(Penetration.isKinetic("AP")).toBe(true)
		expect(Penetration.isKinetic("APCR")).toBe(true)
		expect(Penetration.isKinetic("HEAT")).toBe(false)
		expect(Penetration.isExplosive("HE")).toBe(true)
		expect(Penetration.isExplosive("HESH")).toBe(true)
		expect(Penetration.isExplosive("AP")).toBe(false)
		expect(Penetration.isKinetic("Nope")).toBe(false)
	end)
end)
