-- covers: research 02-R11 formula / interval / after-shot tables, 00-DECISIONS §5, REG-SPT-04, REG-SPT-09 (model side)
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local VisibilityModel = require("@game/ReplicatedStorage/Shared/Spotting/VisibilityModel")

local function camo(stationary, moving, afterShotMul, net, paint)
	return { stationary = stationary, moving = moving, afterShotMul = afterShotMul, net = net, paint = paint }
end

describe("VisibilityModel", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	describe("Config.Spotting", function()
		it("every live-overridable default lies inside its bounds", function()
			local problems = {}
			for _, p in Config.validateBounds() do
				if string.find(p, "^Spotting%.") then
					table.insert(problems, p)
				end
			end
			expect(problems).toEqual({})
		end)

		it("carries the decided values (00-DECISIONS §5)", function()
			local C = Config.Spotting
			expect(C.MAX_SPOT_RANGE_M).toBe(445)
			expect(C.PROXIMITY_RADIUS_M).toBe(50)
			expect(C.FORMULA_FLOOR_M).toBe(50)
			expect(C.ENEMY_DRAW_RANGE_M).toBe(564)
			expect(C.CAMO_TOTAL_CAP).toBe(0.90)
			expect(C.FOLIAGE_STACK_CAP).toBe(0.80)
			expect(C.FOLIAGE_OBSERVER_CLEAR_M).toBe(15)
			expect(C.FOLIAGE_SHOOTER_CLEAR_M).toBe(15)
			expect(C.SHOT_FOLIAGE_PENALTY_S).toBe(3)
			expect(C.SHOT_CAMO_PENALTY_S).toBe(3)
			expect(C.STATIONARY_ARM_S).toBe(3)
			expect(C.STOP_SPEED_KMH).toBe(0.5)
			expect(C.MOVING_YAW_RATE_DEG_S).toBe(2)
			expect(C.CHECK_INTERVAL_MAX_S).toBe(1.0)
			expect(C.MAX_RAYS_PER_TICK).toBe(400)
			expect(C.SPOT_LINGER_S).toBe(10)
			expect(C.LAST_KNOWN_MARKER_S).toBe(30)
			expect(C.SIXTH_SENSE_DELAY_S).toBe(3)
			expect(C.SIGNAL_RELAY_ENABLED).toBe(false)
			expect(C.SMOKE_INSIDE_VR_MULT).toBe(0.70)
			expect(C.PAINT_CAMO_BONUS).toBe(0.04)
			expect(C.PAINT_CAMO_BONUS_COMPETITIVE).toBe(0)
			expect(C.FOLIAGE_CONCEALMENT).toEqual({
				LightBush = 0.25,
				Hedgerow = 0.40,
				DenseBush = 0.50,
				TreeCrown = 0.30,
				FelledTree = 0.30,
				Thicket = 0.60,
			})
			-- Worst-case pair (2 ports × MAX_CHECKPOINTS × 3 queries) fits the smallest allowed budget.
			expect(C.BOUNDS.MAX_RAYS_PER_TICK.min >= 2 * C.BOUNDS.MAX_CHECKPOINTS.max * 3).toBe(true)
		end)
	end)

	describe("spotDistance (research 02 §3 worked examples)", function()
		it("reproduces every row of the table", function()
			expect(VisibilityModel.spotDistance(445, 0)).toBeCloseTo(445, 1e-9)
			expect(VisibilityModel.spotDistance(445, 0.12)).toBeCloseTo(397.6, 1e-9)
			expect(VisibilityModel.spotDistance(445, 1)).toBeCloseTo(50, 1e-9)
			expect(VisibilityModel.spotDistance(500, 0.43)).toBeCloseTo(306.5, 1e-9)
			-- 0.93 raw (WoT) vs our 0.90 total cap
			expect(VisibilityModel.spotDistance(500, 0.93)).toBeCloseTo(81.5, 1e-9)
			expect(VisibilityModel.spotDistance(500, VisibilityModel.totalCamo(0.43, 0.50))).toBeCloseTo(95.0, 1e-9)
			expect(VisibilityModel.spotDistance(520, 0.10)).toBe(445) -- 473 capped
			expect(VisibilityModel.spotDistance(300, 0.18)).toBeCloseTo(255.0, 1e-9)
		end)

		it("a 445 m observer always spots a capped target at 89.5 m", function()
			expect(VisibilityModel.spotDistance(445, VisibilityModel.totalCamo(0.95, 0.8))).toBeCloseTo(89.5, 1e-9)
		end)

		it("cap vs cheap reject (02-R11): camoB 0.95 at 85 m with clear LOS is spotted", function()
			local camo = VisibilityModel.totalCamo(0.95, 0)
			expect(camo).toBe(0.90)
			expect(VisibilityModel.isSpotted(85, 445, camo)).toBe(true)
			expect(VisibilityModel.isSpotted(90, 445, camo)).toBe(false)
		end)

		it("VR is not capped before the formula (VR 550 spots camo 0.21 at 445 m)", function()
			expect(VisibilityModel.spotDistance(550, 0.21)).toBeCloseTo(445, 1e-9)
			expect(VisibilityModel.spotDistance(550, 0.22) < 445).toBe(true)
		end)

		it("degrades safely on bad input", function()
			expect(VisibilityModel.spotDistance(0 / 0, 0)).toBe(0)
			expect(VisibilityModel.spotDistance(-100, 0)).toBe(0)
			expect(VisibilityModel.spotDistance(math.huge, 0)).toBe(0)
			expect(VisibilityModel.spotDistance(400, 0 / 0)).toBe(50) -- NaN camo = fully concealed
			expect(VisibilityModel.spotDistance(400, 2)).toBe(50)
			expect(VisibilityModel.spotDistance(400, -1)).toBe(400)
			-- VR at or below the floor never reaches beyond itself
			expect(VisibilityModel.spotDistance(40, 1)).toBe(40)
			expect(VisibilityModel.spotDistance(50, 0.5)).toBe(50)
		end)

		it("property: monotone in camo and VR, bounded by [floor + 0.1 (VR − floor), 445] under the cap", function()
			local rng = RNG.new(7)
			for _ = 1, 2000 do
				local vr = rng:range(60, 700)
				local c1 = rng:range(0, 0.9)
				local c2 = rng:range(c1, 0.9)
				local d1 = VisibilityModel.spotDistance(vr, c1)
				local d2 = VisibilityModel.spotDistance(vr, c2)
				expect(d2 <= d1 + 1e-9).toBe(true)
				expect(VisibilityModel.spotDistance(vr + 10, c1) >= d1 - 1e-9).toBe(true)
				expect(d1 <= 445).toBe(true)
				expect(d2 >= math.min(445, 50 + 0.1 * (vr - 50)) - 1e-9).toBe(true)
			end
		end)
	end)

	describe("camouflage stacking and caps", function()
		it("caps total camo at 0.90 and foliage at 0.80", function()
			expect(VisibilityModel.totalCamo(0.43, 0.50)).toBe(0.90)
			expect(VisibilityModel.totalCamo(0, 0.5 + 0.5)).toBeCloseTo(0.80, 1e-12) -- two dense bushes
			expect(VisibilityModel.totalCamo(0.05, 1.0)).toBeCloseTo(0.85, 1e-12)
			expect(VisibilityModel.totalCamo(0.12, 0.25)).toBeCloseTo(0.37, 1e-12)
			expect(VisibilityModel.totalCamo(-1, -1)).toBe(0)
			expect(VisibilityModel.totalCamo(0 / 0, 0.3)).toBeCloseTo(0.3, 1e-12)
		end)

		it("isMoving uses the 0.5 km/h and 2 °/s thresholds; turret traverse never counts", function()
			expect(VisibilityModel.isMoving(0.5, 0)).toBe(false)
			expect(VisibilityModel.isMoving(0.51, 0)).toBe(true)
			expect(VisibilityModel.isMoving(-3, 0)).toBe(true)
			expect(VisibilityModel.isMoving(0, 2)).toBe(false)
			expect(VisibilityModel.isMoving(0, -2.1)).toBe(true)
			expect(VisibilityModel.isMoving(0 / 0, nil)).toBe(false)
		end)

		it("bodyCamo = base × shotMult + paint + armed net (hand-computed, MT 0.12/0.07, 75 mm gun)", function()
			local mt = camo(0.12, 0.07, 0.2625, 0.10, 0.04)
			expect(VisibilityModel.bodyCamo(mt, false, 0, nil)).toBeCloseTo(0.16, 1e-12)
			expect(VisibilityModel.bodyCamo(mt, false, 2.99, nil)).toBeCloseTo(0.16, 1e-12) -- net not armed yet
			expect(VisibilityModel.bodyCamo(mt, false, 3.0, nil)).toBeCloseTo(0.26, 1e-12) -- net armed at 3 s
			expect(VisibilityModel.bodyCamo(mt, true, 60, nil)).toBeCloseTo(0.11, 1e-12) -- moving: net off
			-- just fired, armed: 0.12 × 0.2625 + 0.04 + 0.10
			expect(VisibilityModel.bodyCamo(mt, false, 10, 0)).toBeCloseTo(0.1715, 1e-12)
			expect(VisibilityModel.bodyCamo(mt, false, 10, 2.999)).toBeCloseTo(0.1715, 1e-12)
			expect(VisibilityModel.bodyCamo(mt, false, 10, 3.0)).toBeCloseTo(0.26, 1e-12) -- penalty over at 3 s
			expect(VisibilityModel.bodyCamo(mt, true, 0, 1)).toBeCloseTo(0.07 * 0.2625 + 0.04, 1e-12)
		end)

		it("light tanks keep camo when moving; turretless TD drops (00-DECISIONS §5 class table)", function()
			local lt = camo(0.18, 0.18, 0.4, 0.10, 0)
			local td = camo(0.28, 0.16, 0.4, 0.15, 0)
			expect(VisibilityModel.bodyCamo(lt, true, 0, nil)).toBeCloseTo(
				VisibilityModel.bodyCamo(lt, false, 0, nil),
				1e-12
			)
			expect(VisibilityModel.bodyCamo(td, false, 5, nil)).toBeCloseTo(0.43, 1e-12)
			expect(VisibilityModel.bodyCamo(td, true, 5, nil)).toBeCloseTo(0.16, 1e-12)
		end)

		it("after-shot multiplier by calibre: clamp(.40 − .0025(cal − 20), .05, .40)", function()
			expect(VisibilityModel.defaultShotCamoMul(75)).toBeCloseTo(0.2625, 1e-12)
			expect(VisibilityModel.defaultShotCamoMul(105)).toBeCloseTo(0.1875, 1e-12)
			expect(VisibilityModel.defaultShotCamoMul(120)).toBeCloseTo(0.15, 1e-12)
			expect(VisibilityModel.defaultShotCamoMul(160)).toBeCloseTo(0.05, 1e-12)
			expect(VisibilityModel.defaultShotCamoMul(200)).toBeCloseTo(0.05, 1e-12)
			expect(VisibilityModel.defaultShotCamoMul(20)).toBeCloseTo(0.40, 1e-12)
			expect(VisibilityModel.defaultShotCamoMul(10)).toBeCloseTo(0.40, 1e-12)
			expect(VisibilityModel.defaultShotCamoMul(0 / 0)).toBeCloseTo(0.40, 1e-12)
		end)

		it("shot penalty windows are [0, 3) s", function()
			expect(VisibilityModel.isShotCamoPenaltyActive(nil)).toBe(false)
			expect(VisibilityModel.isShotCamoPenaltyActive(0)).toBe(true)
			expect(VisibilityModel.isShotCamoPenaltyActive(2.999)).toBe(true)
			expect(VisibilityModel.isShotCamoPenaltyActive(3)).toBe(false)
			expect(VisibilityModel.isShotCamoPenaltyActive(-0.1)).toBe(false)
			expect(VisibilityModel.isShotFoliagePenaltyActive(2.9)).toBe(true)
			expect(VisibilityModel.isShotFoliagePenaltyActive(3.0)).toBe(false)
		end)

		it("stationary arming (REG-SPT-09): inactive < 3 s, active >= 3 s, never while moving", function()
			expect(VisibilityModel.isStationaryArmed(false, 2.999)).toBe(false)
			expect(VisibilityModel.isStationaryArmed(false, 3)).toBe(true)
			expect(VisibilityModel.isStationaryArmed(true, 100)).toBe(false)
			expect(VisibilityModel.isStationaryArmed(false, 0 / 0)).toBe(false)
		end)

		it("follows live overrides of the caps", function()
			expect(Config.applyOverrides({ Spotting = { CAMO_TOTAL_CAP = 0.95, FOLIAGE_STACK_CAP = 0.6 } })).toBeOk()
			expect(VisibilityModel.totalCamo(0.43, 0.50)).toBeCloseTo(0.93, 1e-12)
			expect(VisibilityModel.totalCamo(0.1, 1)).toBeCloseTo(0.7, 1e-12)
		end)
	end)

	describe("foliage", function()
		it("resolves kind defaults, explicit values and the 0.64 single-volume cap", function()
			expect(VisibilityModel.foliageConcealment("LightBush")).toBe(0.25)
			expect(VisibilityModel.foliageConcealment("Hedgerow")).toBe(0.40)
			expect(VisibilityModel.foliageConcealment("DenseBush")).toBe(0.50)
			expect(VisibilityModel.foliageConcealment("TreeCrown")).toBe(0.30)
			expect(VisibilityModel.foliageConcealment("FelledTree")).toBe(0.30)
			expect(VisibilityModel.foliageConcealment("Thicket")).toBe(0.60)
			expect(VisibilityModel.foliageConcealment("DenseBush", 0.35)).toBe(0.35)
			expect(VisibilityModel.foliageConcealment("Thicket", 0.9)).toBe(0.64)
			expect(VisibilityModel.foliageConcealment("Grass")).toBe(0)
		end)

		it("effectiveFoliage subtracts the 15 m clear zones, then caps the stack", function()
			expect(VisibilityModel.effectiveFoliage(0.5, 0.5, 0)).toBe(0)
			expect(VisibilityModel.effectiveFoliage(0.75, 0.25, 0)).toBeCloseTo(0.5, 1e-12)
			expect(VisibilityModel.effectiveFoliage(0.75, 0, 0.5)).toBeCloseTo(0.25, 1e-12)
			expect(VisibilityModel.effectiveFoliage(1.2, 0, 0)).toBeCloseTo(0.8, 1e-12)
			expect(VisibilityModel.effectiveFoliage(0.5, 0.5, 0.5)).toBe(0) -- double subtraction clamps at 0
			expect(VisibilityModel.effectiveFoliage(-1, 0, 0)).toBe(0)
		end)
	end)

	describe("view range", function()
		it("composes runtime multiplier, smoke and weather (VR never capped)", function()
			expect(VisibilityModel.effectiveViewRange(400, 0.8, true, 1)).toBeCloseTo(224, 1e-9)
			expect(VisibilityModel.effectiveViewRange(400, nil, nil, nil)).toBe(400)
			expect(VisibilityModel.effectiveViewRange(600, 1, false, 1)).toBe(600)
			expect(VisibilityModel.effectiveViewRange(400, 0 / 0, nil, 0.5)).toBe(200)
			expect(VisibilityModel.effectiveViewRange(-5, 1, nil, 1)).toBe(0)
			expect(VisibilityModel.effectiveViewRange(400, 0.5, nil, 0 / 0)).toBe(200) -- default weather 1
		end)

		it("applies the conditional modifiers Spotting owns ((base + Σadd) × Πmul)", function()
			local mods = {
				{ stat = "viewRange", op = "mul", value = 1.25, condition = "StationaryArmed" }, -- periscope mast
				{ stat = "viewRange", op = "add", value = 10, condition = "Stationary" },
				{ stat = "viewRange", op = "mul", value = 1.02, condition = "Spotted" },
				{ stat = "viewRange", op = "mul", value = 2, condition = "AfterShot" }, -- not Spotting's: ignored
				{ stat = "viewRange", op = "mul", value = 3 }, -- Always: pre-folded, ignored
				{ stat = "camoMoving", op = "add", value = 0.05, condition = "Moving" },
			}
			expect(VisibilityModel.applyConditional(400, "viewRange", mods, true, false, false)).toBe(400)
			expect(VisibilityModel.applyConditional(400, "viewRange", mods, false, false, false)).toBe(410)
			expect(VisibilityModel.applyConditional(400, "viewRange", mods, false, true, false)).toBeCloseTo(
				512.5,
				1e-9
			)
			expect(VisibilityModel.applyConditional(400, "viewRange", mods, false, true, true)).toBeCloseTo(
				522.75,
				1e-9
			)
			expect(VisibilityModel.applyConditional(0.16, "camoMoving", mods, true, false, false)).toBeCloseTo(
				0.21,
				1e-12
			)
			expect(VisibilityModel.applyConditional(400, "viewRange", nil, false, true, true)).toBe(400)
		end)
	end)

	describe("check interval curve (02-R11)", function()
		it("matches the anchor table raw and clamped", function()
			expect(VisibilityModel.rawCheckInterval(30)).toBeCloseTo(0.10, 1e-12)
			expect(VisibilityModel.rawCheckInterval(50)).toBeCloseTo(0.10, 1e-12)
			expect(VisibilityModel.rawCheckInterval(100)).toBeCloseTo(0.30, 1e-12)
			expect(VisibilityModel.rawCheckInterval(150)).toBeCloseTo(0.50, 1e-12)
			expect(VisibilityModel.rawCheckInterval(200)).toBeCloseTo(0.708, 1e-3)
			expect(VisibilityModel.rawCheckInterval(270)).toBeCloseTo(1.0, 1e-12)
			expect(VisibilityModel.rawCheckInterval(350)).toBeCloseTo(1.457, 1e-3)
			expect(VisibilityModel.rawCheckInterval(445)).toBeCloseTo(2.0, 1e-12)
			expect(VisibilityModel.rawCheckInterval(900)).toBeCloseTo(2.0, 1e-12)
			expect(VisibilityModel.checkInterval(200)).toBeCloseTo(0.708, 1e-3)
			expect(VisibilityModel.checkInterval(350)).toBe(1.0)
			expect(VisibilityModel.checkInterval(445)).toBe(1.0)
			expect(VisibilityModel.checkInterval(0 / 0)).toBeCloseTo(0.10, 1e-12)
		end)

		it(
			"property: monotone non-decreasing, jittered interval in [(1 − J)·i, i], never above the clamp",
			function()
				local rng = RNG.new(11)
				local J = Config.Spotting.CHECK_JITTER_FRACTION
				for _ = 1, 2000 do
					local a = rng:range(0, 1000)
					local b = rng:range(a, 1000)
					expect(VisibilityModel.checkInterval(b) >= VisibilityModel.checkInterval(a) - 1e-12).toBe(true)
					local phase = rng:next()
					local i = VisibilityModel.checkInterval(a)
					local s = VisibilityModel.scheduledInterval(a, phase)
					expect(s <= i + 1e-12 and s >= i * (1 - J) - 1e-12).toBe(true)
					expect(s <= Config.Spotting.CHECK_INTERVAL_MAX_S + 1e-12).toBe(true)
				end
			end
		)
	end)

	describe("proximity and replication tiers", function()
		it("proximity ignores VR and camo", function()
			expect(VisibilityModel.isWithinProximity(50)).toBe(true)
			expect(VisibilityModel.isWithinProximity(50.01)).toBe(false)
			expect(VisibilityModel.isSpotted(49, 0, 1)).toBe(true)
			expect(VisibilityModel.isSpotted(51, 0, 0)).toBe(false)
			expect(VisibilityModel.isSpotted(0 / 0, 1000, 0)).toBe(false)
		end)

		it("full state within 564 m, minimap beyond, nothing when not team-visible (REG-SPT-08)", function()
			expect(VisibilityModel.replicationTier(false, 10)).toBe("None")
			expect(VisibilityModel.replicationTier(true, 500)).toBe("Full")
			expect(VisibilityModel.replicationTier(true, 564)).toBe("Full")
			expect(VisibilityModel.replicationTier(true, 564.5)).toBe("Minimap")
			expect(VisibilityModel.replicationTier(true, 0 / 0)).toBe("Minimap")
		end)
	end)
end)
