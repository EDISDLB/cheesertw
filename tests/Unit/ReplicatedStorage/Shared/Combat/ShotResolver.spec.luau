local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ShotResolver = require("@game/ReplicatedStorage/Shared/Combat/ShotResolver")
local DamageModel = require("@game/ReplicatedStorage/Shared/Combat/DamageModel")
local ArmorGeometry = require("@game/ReplicatedStorage/Shared/Combat/ArmorGeometry")
local Ballistics = require("@game/ReplicatedStorage/Shared/Combat/Ballistics")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Fixtures = require("./CombatFixtures")

local EPS = 1e-3

local function target(pose: any?, state: any?): any
	return { armor = Fixtures.model(), pose = pose or Fixtures.pose(), state = state }
end

local function shoot(t: any, shell: any, origin: Vector3, dir: Vector3, extra: { [string]: any }?, rng: any?): any
	local input: { [string]: any } = { shell = shell, origin = origin, direction = dir }
	if extra then
		for k, v in extra do
			input[k] = v
		end
	end
	return ShotResolver.resolve(t, input :: any, rng or RNG.new(1))
end

local function override(patch: { [string]: any })
	local r = Config.applyOverrides({ Combat = patch })
	assert(r.ok, if r.ok then "" else r.detail)
end

describe("ShotResolver", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	describe("kinetic shells", function()
		it("penetrates the lower front head-on and rolls the driver on the internal path", function()
			override({ CREW_HIT_CHANCE = 1 })
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(2.5, 3, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 100, damage = 115 }
			)
			expect(o.result).toBe("Penetration")
			expect(o.hit).toBe(true)
			expect(o.damage).toBe(115)
			expect(o.potentialDamage).toBe(115)
			expect(o.penetrationMm).toBe(100)
			expect(o.penetrationRemainingMm).toBeCloseTo(40, 1e-6)
			expect(o.effectiveArmorMm).toBeCloseTo(60, 1e-6)
			expect(o.decidingZone).toBe("HullLowerFront")
			expect(o.plates).toBe(1)
			local impact = o.impact
			expect(impact.zone).toBe("HullLowerFront")
			expect(impact.thicknessMm).toBe(60)
			expect(impact.effectiveMm).toBeCloseTo(60, 1e-6)
			expect(impact.angleDeg).toBeCloseTo(0, 1e-3)
			expect(impact.point).toBeCloseTo(Vector3.new(2.5, 3, -9), EPS)
			expect(impact.distance).toBeCloseTo(21, EPS)
			expect(o.crewHit).toEqual({ { slot = 1, damage = 58, volumeId = 13 } })
			expect(o.modulesHit).toEqual({})
			expect(ShotResolver.toShotResultKind(o)).toBe("Penetration")
		end)

		it("does not penetrate when pen < T_eff (no damage, not absorbed)", function()
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(2.5, 3, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 40, damage = 115 }
			)
			expect(o.result).toBe("NonPenetration")
			expect(o.damage).toBe(0)
			expect(o.absorbed).toBe(false)
			expect(o.effectiveArmorMm).toBeCloseTo(60, 1e-6)
			expect(o.penetrationRemainingMm).toBe(0)
			expect(ShotResolver.toShotResultKind(o)).toBe("NonPenetration")
		end)

		it("walks skirt then hull side (multi-plate sequence)", function()
			local ap = Fixtures.shell("AP")
			local origin, dir = Vector3.new(30, 4, 0), Vector3.new(-1, 0, 0)
			-- skirt 10 mm (overmatched, T_eff 10) then hull side 40 mm: 45 − 10 = 35 < 40
			local stopped = shoot(target(), ap, origin, dir, { penetrationMm = 45, damage = 115 })
			expect(stopped.result).toBe("NonPenetration")
			expect(stopped.plates).toBe(2)
			expect(stopped.impact.zone).toBe("Skirt")
			expect(stopped.decidingZone).toBe("HullSide")
			expect(stopped.effectiveArmorMm).toBeCloseTo(40, 1e-6)
			local through = shoot(target(), ap, origin, dir, { penetrationMm = 60, damage = 115 })
			expect(through.result).toBe("Penetration")
			expect(through.penetrationRemainingMm).toBeCloseTo(10, 1e-6)
			expect(through.damage).toBe(115)
		end)

		it("respects MAX_PLATES", function()
			override({ MAX_PLATES = 1 })
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(30, 4, 0),
				Vector3.new(-1, 0, 0),
				{ penetrationMm = 500, damage = 115 }
			)
			expect(o.result).toBe("NonPenetration")
			expect(o.absorbed).toBe(true)
			expect(o.damage).toBe(0)
		end)

		it("is a Miss when nothing is struck within maxDistance", function()
			local t = target()
			local ap = Fixtures.shell("AP")
			local above = shoot(t, ap, Vector3.new(0, 40, -30), Vector3.new(0, 0, 1))
			expect(above.result).toBe("Miss")
			expect(above.hit).toBe(false)
			expect(above.impact).toBeNil()
			local short = shoot(t, ap, Vector3.new(2.5, 3, -30), Vector3.new(0, 0, 1), { maxDistance = 20 })
			expect(short.result).toBe("Miss")
			local exact = shoot(t, ap, Vector3.new(2.5, 3, -30), Vector3.new(0, 0, 1), { maxDistance = 21.001 })
			expect(exact.result).never.toBe("Miss")
			expect(ShotResolver.toShotResultKind(above)).toBeNil()
		end)
	end)

	describe("ricochets (REG-ARM-04)", function()
		it("a glacis ricochet continues into the turret front and penetrates with pen × 0.75", function()
			override({ CREW_HIT_CHANCE = 1 })
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(2.5, 5, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 250, damage = 115 }
			)
			-- turret front: θ = 36.87°, n = 5° -> T_eff = 100 / cos(31.87°)
			local tEff = 100 / math.cos(math.rad(math.deg(math.acos(0.8)) - 5))
			expect(o.result).toBe("Penetration")
			expect(o.ricochets).toBe(1)
			expect(o.plates).toBe(2)
			expect(o.impact.zone).toBe("HullUpperFront")
			expect(o.impact.angleDeg).toBeCloseTo(math.deg(math.acos(2 / math.sqrt(40))), 1e-3)
			expect(o.decidingZone).toBe("TurretFront")
			expect(o.effectiveArmorMm).toBeCloseTo(tEff, 1e-2)
			expect(o.penetrationRemainingMm).toBeCloseTo(187.5 - tEff, 1e-2)
			expect(o.damage).toBe(115)
			-- internal path in the turret crosses the gunner's seat
			expect(#o.crewHit).toBe(1)
			expect(o.crewHit[1].slot).toBe(2)
			expect(o.ricochetRay).toBeNil()
		end)

		it("the continued shell can fail on the turret (no HP damage)", function()
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(2.5, 5, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 100, damage = 115 }
			)
			expect(o.result).toBe("NonPenetration")
			expect(o.ricochets).toBe(1)
			expect(o.decidingZone).toBe("TurretFront")
			expect(o.damage).toBe(0)
		end)

		it("a ricochet that leaves the vehicle returns the continuation ray (pen × 0.75, same damage roll)", function()
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(4.2, 5, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 100, damage = 115 }
			)
			expect(o.result).toBe("Ricochet")
			expect(o.damage).toBe(0)
			expect(o.deleted).toBe(false)
			local ray = o.ricochetRay
			expect(ray.direction).toBeCloseTo(Vector3.new(0, 0.6, 0.8), 1e-5)
			expect(ray.origin).toBeCloseTo(Vector3.new(4.2, 5, -6) + Fixtures.GLACIS_NORMAL * 0.01, EPS)
			expect(ray.penetrationMm).toBeCloseTo(75, 1e-9)
			expect(ray.damage).toBe(115)
			expect(ray.ricochets).toBe(1)
			expect(ShotResolver.toShotResultKind(o)).toBe("Ricochet")
		end)

		it("a second ricochet deletes the shell", function()
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(4.2, 5, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 75, damage = 115, ricochets = 1 }
			)
			expect(o.result).toBe("Ricochet")
			expect(o.deleted).toBe(true)
			expect(o.ricochetRay).toBeNil()
			expect(o.ricochets).toBe(2)
		end)

		it("HEAT does not ricochet at 71.6° (threshold 85°)", function()
			local o = shoot(
				target(),
				Fixtures.shell("HEAT"),
				Vector3.new(4.2, 5, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 300, damage = 115 }
			)
			expect(o.result).toBe("Penetration")
			expect(o.ricochets).toBe(0)
		end)

		it("a grazing track hit ricochets and still damages the track (external module)", function()
			local small = Fixtures.shell("AP", { caliberMm = 45, damage = 50, moduleDamage = 25 })
			local dir = Vector3.new(-0.2, 0, 0.98)
			local origin = Vector3.new(6, 1, 0) - dir * 20
			local o = shoot(target(), small, origin, dir, { penetrationMm = 80, damage = 50 })
			expect(o.result).toBe("Ricochet")
			expect(o.damage).toBe(0)
			expect(o.modulesHit).toEqual({ { kind = "TrackRight", damage = 25, external = true, volumeId = 5 } })
			expect(o.ricochetRay).never.toBeNil()
		end)

		it("overmatch: a 75 mm shell never ricochets off 20 mm tracks; passing through is absorbed", function()
			local dir = Vector3.new(-0.2, 0, 0.98)
			local origin = Vector3.new(6, 1, 0) - dir * 20
			local o = shoot(target(), Fixtures.shell("AP"), origin, dir, { penetrationMm = 100, damage = 115 })
			expect(o.result).toBe("NonPenetration")
			expect(o.ricochets).toBe(0)
			expect(o.absorbed).toBe(true)
			expect(o.plates).toBe(1)
			expect(o.modulesHit[1].kind).toBe("TrackRight")
			expect(ShotResolver.toShotResultKind(o)).toBe("Absorbed")
		end)
	end)

	describe("HEAT", function()
		it("loses 50 %/m across the skirt-to-hull air gap (REG-ARM-05)", function()
			local o = shoot(
				target(),
				Fixtures.shell("HEAT"),
				Vector3.new(30, 4, 0),
				Vector3.new(-1, 0, 0),
				{ penetrationMm = 100, damage = 115 }
			)
			-- 100 − 10 = 90; gap 1.4 studs = 0.4667 m -> × 0.76667 = 69.0; − 40 = 29.0
			expect(o.result).toBe("Penetration")
			expect(o.penetrationRemainingMm).toBeCloseTo(90 * (1 - 0.5 * 1.4 / 3) - 40, 1e-3)
		end)

		it("is absorbed by the skirt when it cannot get through", function()
			local o = shoot(
				target(),
				Fixtures.shell("HEAT"),
				Vector3.new(30, 4, 0),
				Vector3.new(-1, 0, 0),
				{ penetrationMm = 9, damage = 115 }
			)
			expect(o.result).toBe("NonPenetration")
			expect(o.absorbed).toBe(true)
			expect(ShotResolver.toShotResultKind(o)).toBe("Absorbed")
		end)
	end)

	describe("HE / HESH (REG-ARM-13)", function()
		it("non-penetration on the hull side after the skirt: blast from nominal T + spall × 0.5", function()
			override({ ["MODULE_HIT_CHANCE.FuelTank"] = 1, ["MODULE_HIT_CHANCE.TurretRing"] = 1, CREW_HIT_CHANCE = 1 })
			local o = shoot(
				target(),
				Fixtures.shell("HE"),
				Vector3.new(-30, 4, 0),
				Vector3.new(1, 0, 0),
				{ penetrationMm = 38, damage = 150 }
			)
			-- skirt costs 3 × 10 = 30 -> 8 left < 40 -> blast: 0.5 × 150 − 1.1 × 40 = 31
			expect(o.result).toBe("HEBlast")
			expect(o.absorbed).toBe(false)
			expect(o.plates).toBe(2)
			expect(o.damage).toBe(31)
			expect(o.burstPoint).toBeCloseTo(Vector3.new(-4.5, 4, 0), EPS)
			-- spall sphere R = 0.75 m = 2.25 studs: fuel tank (0.3 studs) then turret ring (1.5 studs), × 0.5
			expect(o.modulesHit).toEqual({
				{ kind = "FuelTank", damage = 56, external = false, volumeId = 10 },
				{ kind = "TurretRing", damage = 56, external = false, volumeId = 12 },
			})
			expect(o.crewHit).toEqual({})
			expect(ShotResolver.toShotResultKind(o)).toBe("NonPenetration")
		end)

		it("HESH non-penetration deals × 1.15", function()
			local o = shoot(
				target(),
				Fixtures.shell("HESH"),
				Vector3.new(-30, 4, 0),
				Vector3.new(1, 0, 0),
				{ penetrationMm = 50, damage = 150 }
			)
			expect(o.result).toBe("HEBlast")
			expect(o.damage).toBe(36) -- 31 × 1.15 = 35.65
		end)

		it("a track absorbs HE (3 T): burst on the track, splash on the hull side, track damaged", function()
			local o = shoot(
				target(),
				Fixtures.shell("HE"),
				Vector3.new(30, 2, 0),
				Vector3.new(-1, 0, 0),
				{ penetrationMm = 38, damage = 150 }
			)
			-- d = 1.5 studs = 0.5 m: 0.5 × 150 × (1 − 0.5/0.75) − 1.1 × 40 < 0
			expect(o.result).toBe("HEBlast")
			expect(o.absorbed).toBe(true)
			expect(o.damage).toBe(0)
			expect(o.modulesHit).toEqual({ { kind = "TrackRight", damage = 113, external = true, volumeId = 5 } })
			expect(ShotResolver.toShotResultKind(o)).toBe("Absorbed")
			-- a thin-sided target takes splash damage through the gap
			local thin = Fixtures.model()
			thin.volumes[1].faces[1].thicknessMm = 5
			local o2 = ShotResolver.resolve({ armor = thin, pose = Fixtures.pose() }, {
				shell = Fixtures.shell("HE"),
				origin = Vector3.new(30, 2, 0),
				direction = Vector3.new(-1, 0, 0),
				penetrationMm = 38,
				damage = 150,
			}, RNG.new(1))
			expect(o2.damage).toBe(20) -- 25 − 5.5 = 19.5 -> 20
		end)

		it("penetration through the roof: full alpha + spall sphere at full module damage", function()
			override({ ["MODULE_HIT_CHANCE.TurretRing"] = 1, CREW_HIT_CHANCE = 1 })
			local o = shoot(
				target(),
				Fixtures.shell("HE"),
				Vector3.new(4, 30, -2),
				Vector3.new(0, -1, 0),
				{ penetrationMm = 38, damage = 150 }
			)
			-- roof 20 mm at 0°: 38 >= 20. Spall sphere 2.25 studs around (4, 6, −2): turret ring (1 stud),
			-- gunner (1.2), loader (2); the driver is 4 studs away.
			expect(o.result).toBe("Penetration")
			expect(o.impact.zone).toBe("HullRoof")
			expect(o.damage).toBe(150)
			expect(o.modulesHit).toEqual({ { kind = "TurretRing", damage = 113, external = false, volumeId = 12 } })
			expect(o.crewHit).toEqual({
				{ slot = 2, damage = 113, volumeId = 17 },
				{ slot = 4, damage = 113, volumeId = 19 },
			})
		end)

		it(
			"splashes nearby vehicles (skips destroyed and out-of-range ones) and stuns with artillery shells",
			function()
				local otherPose = Fixtures.pose(CFrame.new(-4.5, 1, -9.75)) -- its rear plate is 0.75 studs from the burst
				local destroyed = DamageModel.new(Fixtures.init())
				destroyed.destroyed = true
				local nearby = {
					{ armor = Fixtures.model(), pose = otherPose, id = "B" },
					{ armor = Fixtures.model(), pose = Fixtures.pose(CFrame.new(200, 0, 0)), id = "far" },
					{ armor = Fixtures.model(), pose = otherPose, state = destroyed, id = "wreck" },
				}
				local o = shoot(
					target(),
					Fixtures.shell("HE"),
					Vector3.new(-30, 4, 0),
					Vector3.new(1, 0, 0),
					{ penetrationMm = 38, damage = 150, nearby = nearby }
				)
				expect(#o.splash).toBe(1)
				local s = o.splash[1]
				expect(s.index).toBe(1)
				expect(s.id).toBe("B")
				expect(s.distanceM).toBeCloseTo(0.25, 1e-4)
				expect(s.thicknessMm).toBe(30)
				expect(s.damage).toBe(17) -- 0.5 × 150 × (1 − 1/3) − 1.1 × 30
				expect(s.stunS).toBe(0)
				expect(s.modulesHit).toEqual({})

				-- ground burst (terrain / max range) with an artillery shell: R = 3 m, stun 10 -> 5 s
				local spg = Fixtures.shell("HE", { explosionRadiusM = 3, stun = { maxS = 10, minS = 5 } })
				local hits = ShotResolver.burst(spg, Vector3.new(-4.5, 4, 0), { nearby[1] }, RNG.new(1), 150)
				expect(#hits).toBe(1)
				-- with R = 9 studs the thinnest facing plate within R is the 20 mm turret floor / hull roof:
				-- 0.5 × 150 × (1 − 0.25/3) − 1.1 × 20 = 46.75
				expect(hits[1].thicknessMm).toBe(20)
				expect(hits[1].damage).toBe(47)
				expect(hits[1].stunS).toBeCloseTo(10 - 5 * 0.25 / 3, 1e-4)
				for _, m in hits[1].modulesHit do
					expect(m.external).toBe(true)
				end
				-- kinetic shells never burst; non-finite points are ignored
				expect(ShotResolver.burst(Fixtures.shell("AP"), Vector3.zero, { nearby[1] }, RNG.new(1))).toEqual({})
				expect(ShotResolver.burst(spg, Vector3.new(0 / 0, 0, 0), { nearby[1] }, RNG.new(1))).toEqual({})
			end
		)
	end)

	describe("internal path and the ammo rack (REG-ARM-08)", function()
		it("a turret-rear penetration crossing the bustle rack detonates it when shells are stored", function()
			override({ ["MODULE_HIT_CHANCE.AmmoRack"] = 1 })
			local big = Fixtures.shell("AP", { damage = 400, moduleDamage = 200 })
			local state = DamageModel.new(Fixtures.init())
			local o = shoot(
				target(nil, state),
				big,
				Vector3.new(0, 7.5, 30),
				Vector3.new(0, 0, -1),
				{ penetrationMm = 250, damage = 400 }
			)
			expect(o.result).toBe("Penetration")
			expect(o.impact.zone).toBe("TurretRear")
			-- capped at 1.2 × 144 = 172.8 -> 173 >= 144
			expect(o.modulesHit).toEqual({ { kind = "AmmoRack", damage = 173, external = false, volumeId = 14 } })
			local events = {}
			local removed = DamageModel.apply(state, o, RNG.new(2), 7, events)
			expect(o.ammoRackDetonation).toBe(true)
			expect(o.killed).toBe(true)
			expect(removed).toBe(1000)
			expect(o.damageApplied).toBe(1000)
			expect(state.destroyed).toBe(true)
			expect(state.cause).toBe("AmmoRack")
			expect(state.killer).toBe(7)
		end)

		it("with an empty rack there is no detonation, only the shell's damage", function()
			override({ ["MODULE_HIT_CHANCE.AmmoRack"] = 1 })
			local big = Fixtures.shell("AP", { damage = 400, moduleDamage = 200 })
			local state = DamageModel.new(Fixtures.init(), { ammoStored = 0 })
			local o = shoot(
				target(nil, state),
				big,
				Vector3.new(0, 7.5, 30),
				Vector3.new(0, 0, -1),
				{ penetrationMm = 250, damage = 400 }
			)
			DamageModel.apply(state, o, RNG.new(2), 7)
			expect(o.ammoRackDetonation).toBe(false)
			expect(o.damageApplied).toBe(400)
			expect(state.hp).toBe(600)
			expect(state.modules.AmmoRack.state).toBe("Destroyed")
		end)

		it("the internal path stops after max(0.5 m, 10 cal) and never exits the body", function()
			override({ CREW_HIT_CHANCE = 1, ["MODULE_HIT_CHANCE.AmmoRack"] = 1, ["MODULE_HIT_CHANCE.Engine"] = 1 })
			-- head-on lower front at y 2.5: ammo rack starts 7 studs in, beyond 2.25 studs (75 mm)
			local o = shoot(
				target(),
				Fixtures.shell("AP"),
				Vector3.new(0, 2.5, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 200, damage = 115 }
			)
			expect(o.modulesHit).toEqual({})
			-- a 700 mm "calibre" path (7 m = 21 studs) reaches the rack and the engine but stops at the rear plate
			local huge = Fixtures.shell("AP", { caliberMm = 700 })
			local o2 = shoot(
				target(),
				huge,
				Vector3.new(0, 2.5, -30),
				Vector3.new(0, 0, 1),
				{ penetrationMm = 900, damage = 115 }
			)
			local kinds = {}
			for _, m in o2.modulesHit do
				table.insert(kinds, m.kind)
			end
			expect(kinds).toEqual({ "AmmoRack", "Engine" })
		end)
	end)

	describe("combat edge cases", function()
		it("a shell hitting an already-destroyed target is a no-op outcome", function()
			local state = DamageModel.new(Fixtures.init())
			state.destroyed = true
			local o = shoot(target(nil, state), Fixtures.shell("AP"), Vector3.new(2.5, 3, -30), Vector3.new(0, 0, 1))
			expect(o.noop).toBe(true)
			expect(o.hit).toBe(true)
			expect(o.damage).toBe(0)
			expect(o.impact).never.toBeNil()
			expect(DamageModel.apply(state, o, RNG.new(1))).toBe(0)
		end)

		it("two shells in the same tick apply in order; the ledger equals HP lost", function()
			local state = DamageModel.new(Fixtures.init({ hp = 100 }))
			local t = target(nil, state)
			local ap = Fixtures.shell("AP")
			local ledger = 0
			local rng = RNG.new(11)
			local first = shoot(t, ap, Vector3.new(2.5, 3, -30), Vector3.new(0, 0, 1), { penetrationMm = 100 }, rng)
			ledger += DamageModel.apply(state, first, rng, 1)
			local second = shoot(t, ap, Vector3.new(-2.5, 3, -30), Vector3.new(0, 0, 1), { penetrationMm = 100 }, rng)
			ledger += DamageModel.apply(state, second, rng, 2)
			expect(first.killed).toBe(true)
			expect(first.damageApplied).toBe(100)
			expect(second.noop).toBe(true)
			expect(second.damageApplied).toBe(0)
			expect(ledger).toBe(100)
			expect(state.killer).toBe(1)
		end)

		it("resolves against the pose it is given (the caller re-poses targets each tick)", function()
			local ap = Fixtures.shell("AP")
			local shell = Fixtures.shell("AP", { gravityMps2 = 0 })
			-- the target drives out of the shell's path between ticks: the stale pose would have been hit
			local p = Ballistics.launch(Vector3.new(0, 3, -150), Vector3.new(0, 0, 1), shell)
			local poses = {} :: { any }
			for tick = 1, 10 do
				poses[tick] = Fixtures.pose(CFrame.new(if tick <= 1 then 0 else 30, 0, 0))
			end
			local hitTick = nil
			for tick = 1, 10 do
				local from, to = Ballistics.step(p, 1 / 30)
				local segment = to - from
				local o = ShotResolver.resolve(
					{ armor = Fixtures.model(), pose = poses[tick] },
					{ shell = ap, origin = from, direction = segment, maxDistance = segment.Magnitude },
					RNG.new(tick)
				)
				if o.result ~= "Miss" then
					hitTick = tick
					break
				end
			end
			expect(hitTick).toBeNil()
			-- the same flight against a stationary target hits on the tick its segment reaches the plate
			local q = Ballistics.launch(Vector3.new(0, 3, -150), Vector3.new(0, 0, 1), shell)
			for tick = 1, 10 do
				local from, to = Ballistics.step(q, 1 / 30)
				local segment = to - from
				local o = ShotResolver.resolve(
					target(),
					{ shell = ap, origin = from, direction = segment, maxDistance = segment.Magnitude },
					RNG.new(tick)
				)
				if o.result ~= "Miss" then
					hitTick = tick
					break
				end
			end
			-- 1440 studs/s: 48 studs per tick; the plate is 141 studs away -> 3rd tick
			expect(hitTick).toBe(3)
			-- a turret yaw change between resolutions changes the struck zone
			local side = shoot(target(Fixtures.pose(nil, 0)), ap, Vector3.new(30, 7.5, 0), Vector3.new(-1, 0, 0))
			local front = shoot(target(Fixtures.pose(nil, 90)), ap, Vector3.new(30, 7.5, 0), Vector3.new(-1, 0, 0))
			expect(side.impact.zone).toBe("TurretSide")
			expect(front.impact.zone).toBe("GunBarrel")
		end)

		it("rolls pen with distance falloff from firedFrom", function()
			local ap = Fixtures.shell("AP")
			local scripted = Fixtures.scriptedRng({ 0 }, { 0.99 })
			-- 300 m from the muzzle: mean pen 95, z = 0
			local o = ShotResolver.resolve(target(), {
				shell = ap,
				origin = Vector3.new(2.5, 3, -30),
				direction = Vector3.new(0, 0, 1),
				firedFrom = Vector3.new(2.5, 3, -909),
			}, scripted)
			expect(o.penetrationMm).toBeCloseTo(95, 1e-3)
			expect(o.potentialDamage).toBe(115)
		end)

		it("is deterministic for a seed and stays within roll bounds (property)", function()
			local rng = RNG.new(77)
			local shells = { "AP", "APCR", "HEAT", "HE", "HESH" }
			for _ = 1, 400 do
				local kind = shells[rng:int(1, #shells)]
				local shell = Fixtures.shell(kind)
				local pose = Fixtures.pose(nil, rng:range(-180, 180), rng:range(-8, 20))
				local aim = Vector3.new(rng:range(-5, 5), rng:range(1, 9), rng:range(-10, 10))
				local origin = aim + Vector3.new(rng:normal(0, 1), rng:normal(0, 0.3), rng:normal(0, 1)).Unit * 40
				local seed = rng:int(1, 1000000)
				local a = ShotResolver.resolve(
					target(pose),
					{ shell = shell, origin = origin, direction = aim - origin },
					RNG.new(seed)
				)
				local b = ShotResolver.resolve(
					target(pose),
					{ shell = shell, origin = origin, direction = aim - origin },
					RNG.new(seed)
				)
				expect(a).toEqual(b)
				if a.hit then
					expect(a.potentialDamage >= math.floor(0.75 * shell.damage + 0.5)).toBe(true)
					expect(a.potentialDamage <= math.floor(1.25 * shell.damage + 0.5)).toBe(true)
					expect(a.penetrationMm >= 0.75 * shell.penetrationAt500Mm - 1e-9).toBe(true)
					expect(a.penetrationMm <= 1.25 * shell.penetrationMm + 1e-9).toBe(true)
				end
				if a.result == "Penetration" then
					expect(a.damage).toBe(a.potentialDamage)
				elseif a.result ~= "HEBlast" then
					expect(a.damage).toBe(0)
				end
				expect(a.ricochets <= 2).toBe(true)
				for _, m in a.modulesHit do
					expect(m.damage > 0 and m.damage % 1 == 0).toBe(true)
				end
			end
		end)

		it("every shot aimed at an interior point from outside strikes the vehicle", function()
			local rng = RNG.new(31337)
			local model = Fixtures.model()
			local out = ShotResolver.newOutcome()
			for i = 1, 1000 do
				local pose = Fixtures.pose(
					CFrame.new(rng:range(-50, 50), 0, rng:range(-50, 50)) * CFrame.Angles(0, rng:range(-3, 3), 0),
					rng:range(-180, 180),
					rng:range(-8, 20)
				)
				local aim = ArmorGeometry.sampleInteriorPoint(model, pose, rng) :: Vector3
				local origin = aim + Vector3.new(rng:normal(0, 1), rng:normal(0, 1), rng:normal(0, 1)).Unit * 60
				local o = ShotResolver.resolve(
					{ armor = model, pose = pose },
					{ shell = Fixtures.shell("AP"), origin = origin, direction = aim - origin },
					rng,
					out
				)
				if not o.hit then
					error(`shot {i} missed: origin {origin} aim {aim}`)
				end
			end
		end)

		it("survives NaN / inf fuzz without throwing or producing non-finite damage", function()
			local rng = RNG.new(404)
			local nan, inf = 0 / 0, math.huge
			local weird = { nan, inf, -inf, 0, 1e30, -1e30 }
			local function pick(normal: number): number
				if rng:chance(0.3) then
					return weird[rng:int(1, #weird)]
				end
				return normal
			end
			for _ = 1, 2000 do
				local kinds = { "AP", "APCR", "HEAT", "HE", "HESH" }
				local shell = Fixtures.shell(kinds[rng:int(1, 5)], {
					damage = pick(115),
					penetrationMm = pick(100),
					caliberMm = pick(75),
					explosionRadiusM = pick(0.75),
				})
				local pose = Fixtures.pose(nil, pick(0), pick(0), pick(0))
				local origin = Vector3.new(pick(2), pick(3), pick(-30))
				local dir = Vector3.new(pick(0), pick(0), pick(1))
				local ok, o = pcall(ShotResolver.resolve, target(pose), {
					shell = shell,
					origin = origin,
					direction = dir,
					penetrationMm = if rng:chance(0.5) then pick(100) else nil,
					damage = if rng:chance(0.5) then pick(115) else nil,
				}, rng)
				expect(ok).toBe(true)
				expect(o.damage == o.damage and o.damage >= 0 and o.damage < math.huge).toBe(true)
				expect(o.penetrationRemainingMm == o.penetrationRemainingMm).toBe(true)
				for _, m in o.modulesHit do
					expect(m.damage == m.damage and m.damage < math.huge).toBe(true)
				end
			end
		end)

		it("nearestTarget picks the first vehicle along the ray and honours skip / maxDistance", function()
			local near = target(Fixtures.pose(CFrame.new(0, 0, 0)))
			local far = target(Fixtures.pose(CFrame.new(0, 0, 60)))
			local list = { far, near }
			local index, distance = ShotResolver.nearestTarget(list, Vector3.new(0, 3, -40), Vector3.new(0, 0, 1))
			expect(index).toBe(2)
			expect(distance).toBeCloseTo(31, EPS)
			local skipped =
				ShotResolver.nearestTarget(list, Vector3.new(0, 3, -40), Vector3.new(0, 0, 1), nil, { [near] = true })
			expect(skipped).toBe(1)
			expect(ShotResolver.nearestTarget(list, Vector3.new(0, 3, -40), Vector3.new(0, 0, 1), 30)).toBeNil()
			expect(ShotResolver.nearestTarget({}, Vector3.zero, Vector3.new(0, 0, 1))).toBeNil()
			expect(ArmorGeometry.firstHitDistance(near.armor, near.pose, Vector3.new(0, 3, -40), Vector3.new(0, 0, 1))).toBeCloseTo(
				31,
				EPS
			)
		end)

		it("reuses the outcome table", function()
			local out = ShotResolver.newOutcome()
			override({ CREW_HIT_CHANCE = 1 })
			local t = target()
			local input = {
				shell = Fixtures.shell("AP"),
				origin = Vector3.new(2.5, 3, -30),
				direction = Vector3.new(0, 0, 1),
				penetrationMm = 100,
				damage = 115,
			}
			expect(ShotResolver.resolve(t, input, RNG.new(1), out)).toBe(out)
			expect(#out.crewHit).toBe(1)
			local miss = table.clone(input)
			miss.origin = Vector3.new(0, 50, -30)
			ShotResolver.resolve(t, miss, RNG.new(1), out)
			expect(out.result).toBe("Miss")
			expect(#out.crewHit).toBe(0)
		end)
	end)
end)
