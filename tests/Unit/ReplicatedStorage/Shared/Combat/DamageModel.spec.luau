local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local DamageModel = require("@game/ReplicatedStorage/Shared/Combat/DamageModel")
local ShotResolver = require("@game/ReplicatedStorage/Shared/Combat/ShotResolver")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
local Fixtures = require("./CombatFixtures")

local function outcome(fields: { [string]: any }): any
	local o = ShotResolver.newOutcome()
	o.result = "Penetration"
	o.hit = true
	for k, v in fields do
		(o :: any)[k] = v
	end
	return o
end

local function eventsOf(events: { any }, kind: string): { any }
	local out = {}
	for _, e in events do
		if e.type == kind then
			table.insert(out, e)
		end
	end
	return out
end

local function sumDamage(events: { any }): number
	local total = 0
	for _, e in events do
		if e.type == "Damage" then
			total += e.damage
		end
	end
	return total
end

describe("DamageModel", function()
	Test.afterEach(function()
		Config.resetOverrides()
	end)

	describe("construction", function()
		it("builds the state from VehicleStats-like init", function()
			local s = DamageModel.new(Fixtures.init())
			expect(s.hp).toBe(1000)
			expect(s.maxHp).toBe(1000)
			expect(s.destroyed).toBe(false)
			expect(s.modules.Engine.maxHp).toBe(160)
			expect(s.modules.Engine.state).toBe("Ok")
			expect(s.moduleOrder).toEqual(DamageModel.MODULE_KINDS)
			expect(#s.crew).toBe(4)
			expect(s.crew[1].injured).toBe(false)
			expect(s.ammoStored).toBe(1)
			expect(s.wheeled).toBe(false)
			expect(s.fire.burning).toBe(false)
		end)

		it("module / crew HP helpers follow k × tier reference alpha", function()
			expect(DamageModel.moduleHpFor("Engine", 160)).toBe(160)
			expect(DamageModel.moduleHpFor("AmmoRack", 160)).toBe(144)
			expect(DamageModel.moduleHpFor("Optics", 160)).toBe(128)
			expect(DamageModel.moduleHpFor("TrackLeft", 160)).toBe(224)
			expect(DamageModel.crewHpFor(160)).toBe(128)
		end)

		it("sanitizes non-finite init values", function()
			local s =
				DamageModel.new(Fixtures.init({ hp = 0 / 0, fireChance = 0 / 0, fireDurationS = -1, spallFactor = 0 }))
			expect(s.hp).toBe(0)
			expect(s.fireChance).toBe(Config.Combat.FIRE_CHANCE_DEFAULT)
			expect(s.fireDurationS).toBe(8)
			expect(s.spallFactor).toBe(1)
		end)
	end)

	describe("modules", function()
		it("state thresholds: Ok > 50 %, Damaged <= 50 %, Destroyed at 0 (events once per change)", function()
			local s = DamageModel.new(Fixtures.init())
			local events = {}
			DamageModel.damageModule(s, "Engine", 79, 3, events) -- 81 / 160 > 50 %
			expect(s.modules.Engine.state).toBe("Ok")
			DamageModel.damageModule(s, "Engine", 1, 3, events) -- 80 = 50 %
			expect(s.modules.Engine.state).toBe("Damaged")
			DamageModel.damageModule(s, "Engine", 10, 3, events)
			DamageModel.damageModule(s, "Engine", 100, 3, events)
			expect(s.modules.Engine.hp).toBe(0)
			expect(s.modules.Engine.state).toBe("Destroyed")
			expect(s.modules.Engine.repairRemainingS).toBe(14)
			local states = {}
			for _, e in eventsOf(events, "ModuleState") do
				table.insert(states, e.state)
			end
			expect(states).toEqual({ "Damaged", "Destroyed" })
			-- unknown kind / destroyed vehicle: nil
			expect((DamageModel.damageModule(s, "Nope" :: any, 1))).toBeNil()
		end)

		it("one hit removes at most 1.2 × the module's max HP", function()
			local s = DamageModel.new(Fixtures.init({ modules = { Engine = { maxHp = 1000, repairS = 1 } } }))
			DamageModel.damageModule(s, "Engine", 5000)
			expect(s.modules.Engine.hp).toBe(0) -- 1200 > 1000
			local s2 = DamageModel.new(Fixtures.init({ modules = { Gun = { maxHp = 100, repairS = 1 } } }))
			s2.modules.Gun.hp = 100
			s2.modules.Gun.maxHp = 1000
			DamageModel.damageModule(s2, "Gun", 5000)
			expect(s2.modules.Gun.hp).toBe(0)
		end)

		it("field repair restores Destroyed -> Damaged at 50 % after repairS; a driver injury slows it", function()
			local s = DamageModel.new(Fixtures.init())
			local events = {}
			DamageModel.damageModule(s, "TrackLeft", 500, 1, events)
			local rng = RNG.new(1)
			for _ = 1, 299 do
				DamageModel.update(s, 1 / 30, rng, events)
			end
			expect(s.modules.TrackLeft.state).toBe("Destroyed")
			DamageModel.update(s, 1 / 30 + 1e-9, rng, events)
			expect(s.modules.TrackLeft.state).toBe("Damaged")
			expect(s.modules.TrackLeft.hp).toBe(112)
			-- injured driver: repair time × f(100)/f(50) = 1 / 0.785
			local slow = DamageModel.new(Fixtures.init())
			DamageModel.damageCrew(slow, 1, 1000)
			DamageModel.damageModule(slow, "TrackLeft", 500)
			DamageModel.update(slow, 12.7, rng)
			expect(slow.modules.TrackLeft.state).toBe("Destroyed")
			DamageModel.update(slow, 0.05, rng)
			expect(slow.modules.TrackLeft.state).toBe("Damaged")
		end)
	end)

	describe("apply (shot outcomes)", function()
		it("removes HP, applies modules and crew, emits events, caps at remaining HP", function()
			local s = DamageModel.new(Fixtures.init({ hp = 300 }))
			local events = {}
			local o = outcome({
				damage = 120,
				modulesHit = { { kind = "Gun", damage = 90, external = false, volumeId = 15 } },
				crewHit = { { slot = 2, damage = 200, volumeId = 17 } },
			})
			expect(DamageModel.apply(s, o, RNG.new(1), 9, events)).toBe(120)
			expect(s.hp).toBe(180)
			expect(s.modules.Gun.state).toBe("Damaged")
			expect(s.crew[2].injured).toBe(true)
			expect(o.damageApplied).toBe(120)
			expect(o.killed).toBe(false)
			expect(#eventsOf(events, "CrewInjured")).toBe(1)
			expect(eventsOf(events, "Damage")[1].attacker).toBe(9)
			local big = outcome({ damage = 999 })
			expect(DamageModel.apply(s, big, RNG.new(1), 4, events)).toBe(180)
			expect(big.killed).toBe(true)
			expect(s.destroyed).toBe(true)
			expect(s.cause).toBe("Shell")
			expect(s.killer).toBe(4)
			-- nothing changes a wreck (no overkill, REG-ARM-07 / DMG-12)
			local after = outcome({ damage = 50 })
			expect(DamageModel.apply(s, after, RNG.new(1), 5, events)).toBe(0)
			expect(after.damageApplied).toBe(0)
			expect(sumDamage(events)).toBe(300)
		end)

		it("ignores misses, no-ops and garbage damage", function()
			local s = DamageModel.new(Fixtures.init())
			local miss = ShotResolver.newOutcome()
			miss.damage = 100
			expect(DamageModel.apply(s, miss, RNG.new(1))).toBe(0)
			local noop = outcome({ damage = 100, noop = true })
			expect(DamageModel.apply(s, noop, RNG.new(1))).toBe(0)
			expect(DamageModel.apply(s, outcome({ damage = 0 / 0 }), RNG.new(1))).toBe(0)
			expect(DamageModel.apply(s, outcome({ damage = -40 }), RNG.new(1))).toBe(0)
			expect(DamageModel.apply(s, outcome({ damage = math.huge }), RNG.new(1))).toBe(0)
			expect(s.hp).toBe(1000)
		end)

		it("engine hits roll fire (×1.5 with a damaged fuel tank); a destroyed fuel tank always ignites", function()
			local engineHit = { { kind = "Engine", damage = 1, external = false, volumeId = 9 } }
			local sure = DamageModel.new(Fixtures.init({ fireChance = 1 }))
			local o = outcome({ damage = 0, modulesHit = engineHit })
			DamageModel.apply(sure, o, RNG.new(1), 3)
			expect(o.fireStarted).toBe(true)
			expect(sure.fire.burning).toBe(true)
			expect(sure.fire.igniter).toBe(3)
			local never = DamageModel.new(Fixtures.init({ fireChance = 0 }))
			local o2 = outcome({ damage = 0, modulesHit = engineHit })
			DamageModel.apply(never, o2, RNG.new(1), 3)
			expect(o2.fireStarted).toBe(false)
			-- statistical: 0.4 × 1.5 = 0.6 with the fuel tank damaged
			local rng = RNG.new(99)
			local fires = 0
			local n = 20000
			for _ = 1, n do
				local s = DamageModel.new(Fixtures.init({ fireChance = 0.4 }))
				s.modules.FuelTank.state = "Damaged"
				local o3 = outcome({ damage = 0, modulesHit = engineHit })
				DamageModel.apply(s, o3, rng, 1)
				if o3.fireStarted then
					fires += 1
				end
			end
			expect(fires / n).toBeCloseTo(0.6, 0.015)
			-- fuel tank destroyed
			local fuel = DamageModel.new(Fixtures.init({ fireChance = 0 }))
			local o4 = outcome({
				damage = 0,
				modulesHit = { { kind = "FuelTank", damage = 500, external = false, volumeId = 10 } },
			})
			DamageModel.apply(fuel, o4, RNG.new(1), 8)
			expect(o4.fireStarted).toBe(true)
			expect(fuel.fire.igniter).toBe(8)
		end)

		it("ammo rack detonation needs >= AMMO_RACK_DETONATION_MIN_SHELLS stored (REG-ARM-08)", function()
			local rack = { { kind = "AmmoRack", damage = 173, external = false, volumeId = 11 } }
			local loaded = DamageModel.new(Fixtures.init())
			local events = {}
			local o = outcome({ damage = 10, modulesHit = rack })
			expect(DamageModel.apply(loaded, o, RNG.new(1), 2, events)).toBe(1000)
			expect(o.ammoRackDetonation).toBe(true)
			expect(loaded.cause).toBe("AmmoRack")
			expect(eventsOf(events, "Damage")[1].kind).toBe("AmmoRack")
			expect(eventsOf(events, "Destroyed")[1].cause).toBe("AmmoRack")

			local empty = DamageModel.new(Fixtures.init())
			DamageModel.setAmmoStored(empty, 0)
			local o2 = outcome({ damage = 10, modulesHit = rack })
			expect(DamageModel.apply(empty, o2, RNG.new(1), 2)).toBe(10)
			expect(o2.ammoRackDetonation).toBe(false)
			expect(empty.modules.AmmoRack.state).toBe("Destroyed")
			-- a damaged (not destroyed) rack never detonates
			local damaged = DamageModel.new(Fixtures.init())
			local o3 = outcome({
				damage = 0,
				modulesHit = { { kind = "AmmoRack", damage = 80, external = false, volumeId = 11 } },
			})
			DamageModel.apply(damaged, o3, RNG.new(1))
			expect(o3.ammoRackDetonation).toBe(false)
			expect(damaged.modules.AmmoRack.state).toBe("Damaged")
			DamageModel.setAmmoStored(damaged, 0 / 0)
			expect(damaged.ammoStored).toBe(0)
		end)

		it("splash applies HP, external modules and stun", function()
			local s = DamageModel.new(Fixtures.init())
			local events = {}
			local removed = DamageModel.applySplash(s, {
				index = 1,
				damage = 40,
				distanceM = 0.2,
				thicknessMm = 20,
				stunS = 6,
				modulesHit = { { kind = "TrackRight", damage = 120, external = true, volumeId = 5 } },
			}, RNG.new(1), 6, events)
			expect(removed).toBe(40)
			expect(s.modules.TrackRight.state).toBe("Damaged")
			expect(s.stunRemainingS).toBe(6)
			expect(s.stunAttacker).toBe(6)
			expect(eventsOf(events, "Damage")[1].kind).toBe("Splash")
			expect(#eventsOf(events, "Stunned")).toBe(1)
			-- a shorter stun does not replace a longer one
			DamageModel.applyStun(s, 2, 1, events)
			expect(s.stunRemainingS).toBe(6)
			DamageModel.update(s, 6, RNG.new(1))
			expect(s.stunRemainingS).toBe(0)
		end)
	end)

	describe("fire (REG-ARM-09)", function()
		it("burns 8 s × 2.5 %/s = 20 % of max HP, credited to the igniter, then burns out", function()
			local s = DamageModel.new(Fixtures.init())
			local events = {}
			DamageModel.ignite(s, 42, events)
			local rng = RNG.new(5)
			Config.applyOverrides({ Combat = { FIRE_CREW_HIT_CHANCE = 0 } })
			for _ = 1, 30 * 10 do
				DamageModel.update(s, 1 / 30, rng, events)
			end
			expect(s.hp).toBe(800)
			local damage = eventsOf(events, "Damage")
			expect(#damage).toBe(8)
			for _, e in damage do
				expect(e.kind).toBe("Fire")
				expect(e.attacker).toBe(42)
				expect(e.damage).toBe(25)
			end
			expect(s.fire.burning).toBe(false)
			local fireEvents = eventsOf(events, "Fire")
			expect(fireEvents[1].burning).toBe(true)
			expect(fireEvents[#fireEvents].reason).toBe("BurnedOut")
			-- engine bay modules took 5 %/s × 8 s = 40 % (Ok -> still above 50 %)
			expect(s.modules.Engine.hp).toBe(160 - 8 * 8)
		end)

		it("Fire Fighting duration (6 s) burns 15 %", function()
			Config.applyOverrides({ Combat = { FIRE_CREW_HIT_CHANCE = 0 } })
			local s = DamageModel.new(Fixtures.init({ fireDurationS = 6 }))
			DamageModel.ignite(s, 1)
			for _ = 1, 300 do
				DamageModel.update(s, 1 / 30, RNG.new(1))
			end
			expect(s.hp).toBe(850)
		end)

		it("extinguishing stops the damage in the same tick; fire never ticks on a destroyed vehicle", function()
			local s = DamageModel.new(Fixtures.init())
			DamageModel.ignite(s, 1)
			for _ = 1, 29 do
				DamageModel.update(s, 1 / 30, RNG.new(1))
			end
			expect(DamageModel.extinguish(s)).toBe(true)
			DamageModel.update(s, 1 / 30, RNG.new(1))
			expect(s.hp).toBe(1000)
			expect(DamageModel.extinguish(s)).toBe(false)

			local dead = DamageModel.new(Fixtures.init({ hp = 10 }))
			DamageModel.ignite(dead, 1)
			DamageModel.applyDamage(dead, "Shell", 10, 2)
			expect(dead.fire.burning).toBe(false)
			expect(DamageModel.update(dead, 5, RNG.new(1))).toBe(0)
			expect(DamageModel.ignite(dead, 3)).toBe(false)
		end)

		it("a fire can destroy the vehicle and the kill goes to the igniter", function()
			local s = DamageModel.new(Fixtures.init({ hp = 60 }))
			s.hp = 10 -- 1.5 HP/s for 8 s = 12 > 10
			DamageModel.ignite(s, 77)
			for _ = 1, 30 * 8 do
				DamageModel.update(s, 1 / 30, RNG.new(1))
			end
			expect(s.destroyed).toBe(true)
			expect(s.cause).toBe("Fire")
			expect(s.killer).toBe(77)
		end)

		it("the Automatic Extinguisher puts the fire out after 0.5 s with no damage, then disarms", function()
			local s = DamageModel.new(Fixtures.init(), { autoExtinguisher = true })
			local events = {}
			DamageModel.ignite(s, 1, events)
			for _ = 1, 30 do
				DamageModel.update(s, 1 / 30, RNG.new(1), events)
			end
			expect(s.fire.burning).toBe(false)
			expect(s.hp).toBe(1000)
			expect(s.autoExtinguisher).toBe(false)
			local fireEvents = eventsOf(events, "Fire")
			expect(fireEvents[#fireEvents].reason).toBe("AutoExtinguisher")
			DamageModel.armAutoExtinguisher(s, true)
			expect(s.autoExtinguisher).toBe(true)
		end)

		it("fire ticks may injure crew (seeded)", function()
			Config.applyOverrides({ Combat = { FIRE_CREW_HIT_CHANCE = 1, FIRE_CREW_DAMAGE_FRACTION = 1 } })
			local s = DamageModel.new(Fixtures.init())
			DamageModel.ignite(s, 1)
			for _ = 1, 30 * 3 do
				DamageModel.update(s, 1 / 30, RNG.new(3))
			end
			local injured = 0
			for _, m in s.crew do
				if m.injured then
					injured += 1
				end
			end
			expect(injured).toBe(3)
		end)
	end)

	describe("consumables", function()
		it("repair kit restores every module; medkit heals crew and clears stun", function()
			local s = DamageModel.new(Fixtures.init())
			local events = {}
			DamageModel.damageModule(s, "Engine", 500)
			DamageModel.damageModule(s, "Optics", 70)
			DamageModel.damageCrew(s, 4, 500)
			DamageModel.applyStun(s, 5, 2)
			expect(DamageModel.useRepairKit(s, events)).toBe(true)
			for _, kind in DamageModel.MODULE_KINDS do
				expect(s.modules[kind].state).toBe("Ok")
				expect(s.modules[kind].hp).toBe(s.modules[kind].maxHp)
				expect(s.modules[kind].repairRemainingS).toBe(0)
			end
			expect(#eventsOf(events, "ModuleState")).toBe(2)
			expect(DamageModel.useRepairKit(s)).toBe(false)
			expect(DamageModel.useMedkit(s, events)).toBe(true)
			expect(s.crew[4].injured).toBe(false)
			expect(s.stunRemainingS).toBe(0)
			expect(#eventsOf(events, "CrewHealed")).toBe(1)
			expect(DamageModel.useMedkit(s)).toBe(false)
		end)
	end)

	describe("effects (00-DECISIONS §2 Effects, §4)", function()
		it("module states map to the decided multipliers", function()
			local s = DamageModel.new(Fixtures.init())
			local e = DamageModel.effects(s)
			expect(e.enginePowerMul).toBe(1)
			expect(e.canMove).toBe(true)
			expect(e.canFire).toBe(true)
			s.modules.Engine.state = "Damaged"
			s.modules.AmmoRack.state = "Damaged"
			s.modules.FuelTank.state = "Damaged"
			s.modules.Gun.state = "Damaged"
			s.modules.TurretRing.state = "Damaged"
			s.modules.Optics.state = "Damaged"
			DamageModel.effects(s, e)
			expect(e.enginePowerMul).toBe(0.5)
			expect(e.reloadTimeMul).toBe(1.25)
			expect(e.fireChanceMul).toBe(1.5)
			expect(e.aimTimeMul).toBe(1.25)
			expect(e.gunDamaged).toBe(true)
			expect(e.dispersionMul).toBe(1) -- damaged-gun bloom goes through Dispersion's gunDamaged
			expect(e.turretTraverseMul).toBe(0.5)
			expect(e.viewRangeMul).toBe(0.8)
			s.modules.Engine.state = "Destroyed"
			s.modules.Gun.state = "Destroyed"
			s.modules.TurretRing.state = "Destroyed"
			s.modules.Optics.state = "Destroyed"
			DamageModel.effects(s, e)
			expect(e.canMove).toBe(false)
			expect(e.canFire).toBe(false)
			expect(e.turretTraverseMul).toBe(0)
			expect(e.viewRangeMul).toBe(0.5)
		end)

		it("destroyed tracks immobilise tracked vehicles; wheeled lose 25 % top speed per side", function()
			local tracked = DamageModel.new(Fixtures.init())
			tracked.modules.TrackLeft.state = "Destroyed"
			expect(DamageModel.effects(tracked).canMove).toBe(false)
			local wheeled = DamageModel.new(Fixtures.init({ wheeled = {} }))
			wheeled.modules.TrackLeft.state = "Destroyed"
			local e = DamageModel.effects(wheeled)
			expect(e.canMove).toBe(true)
			expect(e.topSpeedMul).toBe(0.75)
			wheeled.modules.TrackRight.state = "Destroyed"
			expect(DamageModel.effects(wheeled).topSpeedMul).toBeCloseTo(0.5625, 1e-12)
		end)

		it("crew injuries rescale stats by the crew curves (loader 50 -> reload × 1.273)", function()
			local s = DamageModel.new(Fixtures.init())
			DamageModel.damageCrew(s, 4, 1000) -- loader
			local e = DamageModel.effects(s)
			expect(e.reloadTimeMul).toBeCloseTo(0.875 / (0.00375 * 50 + 0.5), 1e-9)
			DamageModel.damageCrew(s, 2, 1000) -- gunner
			DamageModel.effects(s, e)
			expect(e.aimTimeMul).toBeCloseTo(1 / 0.785, 1e-9)
			expect(e.dispersionMul).toBeCloseTo(1 / 0.785, 1e-9)
			expect(e.turretTraverseMul).toBeCloseTo(0.785, 1e-9)
			expect(e.sixthSense).toBe(true)
			DamageModel.damageCrew(s, 3, 1000) -- commander: VR × f(50), others −10, Sixth Sense off
			DamageModel.effects(s, e)
			expect(e.viewRangeMul).toBeCloseTo(0.785, 1e-9)
			expect(e.hullTraverseMul).toBeCloseTo((0.57 + 0.0043 * 90) / 1, 1e-9)
			expect(e.sixthSense).toBe(false)
		end)

		it("stun stacks its multipliers; a destroyed vehicle can neither move nor fire", function()
			local s = DamageModel.new(Fixtures.init())
			DamageModel.applyStun(s, 4, 1)
			local e = DamageModel.effects(s)
			expect(e.stunned).toBe(true)
			expect(e.reloadTimeMul).toBe(1.25)
			expect(e.aimTimeMul).toBe(1.25)
			expect(e.dispersionMul).toBe(1.2)
			expect(e.turretTraverseMul).toBe(0.8)
			expect(e.hullTraverseMul).toBe(0.8)
			expect(e.topSpeedMul).toBe(0.85)
			expect(e.viewRangeMul).toBe(0.9)
			DamageModel.applyDamage(s, "Shell", 5000, 1)
			local dead = DamageModel.effects(s)
			expect(dead.canMove).toBe(false)
			expect(dead.canFire).toBe(false)
			expect(dead.stunned).toBe(false)
		end)

		it("exports the crew-injury effects table", function()
			expect(DamageModel.INJURY_EFFECTS.reloadTime.duty).toBe("Loader")
			expect(DamageModel.INJURY_EFFECTS.viewRange.duty).toBe("Commander")
			expect(DamageModel.CrewEffects.reloadFactor(100)).toBeCloseTo(1, 1e-12)
		end)
	end)

	describe("ramming (00-DECISIONS §2)", function()
		it("golden: 50 t at 11.1 m/s into a 20 t light's 40 mm side = 264; its 150 mm front takes 0", function()
			local heavy = { massKg = 50000, contactThicknessMm = 150, frontArc = false }
			local light = { massKg = 20000, contactThicknessMm = 40, frontArc = false }
			local toHeavy, toLight, rawOnHeavy, rawOnLight = DamageModel.resolveRam(heavy, light, 11.1)
			expect(toLight).toBe(264) -- 0.05 × 50 × 11.1² − 1.1 × 40 = 264.03
			expect(toHeavy).toBe(0) -- 0.05 × 20 × 11.1² − 165 < 0
			expect(rawOnLight).toBeCloseTo(0.05 * 50 * 11.1 * 11.1, 1e-9)
			expect(rawOnHeavy).toBeCloseTo(0.05 * 20 * 11.1 * 11.1, 1e-9)
		end)

		it("needs >= 3 m/s closing speed; front arc halves damage taken; spall lining and multipliers apply", function()
			local a = { massKg = 40000, contactThicknessMm = 0, frontArc = false }
			local b = { massKg = 40000, contactThicknessMm = 0, frontArc = false }
			expect((DamageModel.ramDamage(a, b, 2.99))).toBe(0)
			expect((DamageModel.ramDamage(a, b, 3))).toBe(18) -- 0.05 × 40 × 9
			local front = { massKg = 40000, contactThicknessMm = 0, frontArc = true }
			expect((DamageModel.ramDamage(a, front, 10))).toBe(100) -- 200 × 0.5
			local lined = { massKg = 40000, contactThicknessMm = 40, spallFactor = 1.5, frontArc = false }
			expect((DamageModel.ramDamage(a, lined, 10))).toBe(134) -- 200 − 1.1 × 40 × 1.5
			local dealer = { massKg = 40000, contactThicknessMm = 0, frontArc = false, ramDamageDealtMul = 1.2 }
			local taker = { massKg = 40000, contactThicknessMm = 0, frontArc = false, ramDamageTakenMul = 0.5 }
			expect((DamageModel.ramDamage(dealer, taker, 10))).toBe(120)
			expect((DamageModel.ramDamage(a, b, 0 / 0))).toBe(0)
		end)

		it("applies each contact once (REG-ARM-10) and rolls the contact-side track", function()
			Config.applyOverrides({ Combat = { RAM_TRACK_HIT_CHANCE = 1 } })
			local s = DamageModel.new(Fixtures.init())
			local events = {}
			expect(DamageModel.applyRam(s, "c1", 100, 300, RNG.new(1), 5, events, "TrackLeft")).toBe(100)
			expect(DamageModel.applyRam(s, "c1", 100, 300, RNG.new(1), 5, events, "TrackLeft")).toBe(0)
			expect(s.hp).toBe(900)
			expect(s.modules.TrackLeft.hp).toBe(224 - 150)
			expect(s.modules.TrackRight.hp).toBe(224)
			expect(eventsOf(events, "Damage")[1].kind).toBe("Ram")
			-- the memory is a ring: old ids eventually expire, recent ones never re-apply
			for i = 1, Config.Combat.CONTACT_MEMORY do
				DamageModel.applyRam(s, i, 1, 0, RNG.new(1), 5)
			end
			expect(DamageModel.applyRam(s, Config.Combat.CONTACT_MEMORY, 1, 0, RNG.new(1), 5)).toBe(0)
			expect(DamageModel.applyRam(s, "c1", 1, 0, RNG.new(1), 5)).toBe(1)
		end)

		it("isFrontArc uses the hull's forward axis (±45°)", function()
			local hull = CFrame.new(10, 0, 10) * CFrame.Angles(0, math.rad(-90), 0) -- facing +X
			expect(DamageModel.isFrontArc(hull, Vector3.new(15, 0, 10))).toBe(true)
			expect(DamageModel.isFrontArc(hull, Vector3.new(15, 0, 14))).toBe(true)
			expect(DamageModel.isFrontArc(hull, Vector3.new(15, 0, 16))).toBe(false)
			expect(DamageModel.isFrontArc(hull, Vector3.new(5, 0, 10))).toBe(false)
			expect(DamageModel.isFrontArc(hull, Vector3.new(10, 3, 10))).toBe(false)
		end)
	end)

	describe("falls (REG-VEH-11) and drowning", function()
		it("goldens: 7.0 m/s -> 0; 10 m/s, 40 t -> 216; upside down 432", function()
			expect(DamageModel.fallDamage(40000, 7.0)).toBe(0)
			expect(DamageModel.fallDamage(40000, 10)).toBe(216)
			expect(DamageModel.fallDamage(40000, -10)).toBe(216)
			expect(DamageModel.fallDamage(40000, 10, true)).toBe(432)
			expect(DamageModel.fallDamage(40000, 10, false, 0.5)).toBe(108)
			expect(DamageModel.fallDamage(40000, 0 / 0)).toBe(0)
		end)

		it(
			"applies each landing once, without kill credit, and breaks a track with chance min(1, (v − 7)/5)",
			function()
				local s = DamageModel.new(Fixtures.init())
				local events = {}
				expect(DamageModel.applyFall(s, "land1", 12, false, RNG.new(4), events)).toBe(600) -- 0.6 × 40 × 25
				expect(DamageModel.applyFall(s, "land1", 12, false, RNG.new(4), events)).toBe(0)
				local destroyedTracks = 0
				for _, kind in { "TrackLeft", "TrackRight" } do
					if s.modules[kind].state == "Destroyed" then
						destroyedTracks += 1
					end
				end
				expect(destroyedTracks).toBe(1)
				expect(DamageModel.applyFall(s, "land2", 10, true, RNG.new(4), events)).toBe(400) -- capped at remaining
				expect(s.destroyed).toBe(true)
				expect(s.cause).toBe("Fall")
				expect(s.killer).toBeNil()
				expect(DamageModel.applyFall(s, "land3", 30, true, RNG.new(4))).toBe(0)
			end
		)

		it("drowning destroys after 10 s submerged (no credit) and resets on exit", function()
			local s = DamageModel.new(Fixtures.init())
			local events = {}
			for _ = 1, 30 * 9 do
				DamageModel.updateDrowning(s, true, 1 / 30, events)
			end
			expect(s.destroyed).toBe(false)
			DamageModel.updateDrowning(s, false, 1 / 30, events)
			expect(s.drownS).toBe(0)
			local warnings = eventsOf(events, "Drowning")
			expect(warnings[1].active).toBe(true)
			expect(warnings[2].active).toBe(false)
			local killed = false
			for _ = 1, 30 * 10 + 1 do
				killed = DamageModel.updateDrowning(s, true, 1 / 30, events) or killed
			end
			expect(killed).toBe(true)
			expect(s.cause).toBe("Drown")
			expect(s.killer).toBeNil()
			expect(sumDamage(events)).toBe(1000)
		end)
	end)

	describe("invariants (property, seeded)", function()
		it("random operation sequences keep hp/modules in range and the damage ledger equal to HP lost", function()
			local master = RNG.new(2026)
			for _ = 1, 150 do
				local rng = master:fork(master:nextU32())
				local s =
					DamageModel.new(Fixtures.init({ fireChance = rng:range(0, 1) }), { ammoStored = rng:int(0, 2) })
				local events = {}
				local kinds = DamageModel.MODULE_KINDS
				for step = 1, 120 do
					local op = rng:int(1, 9)
					if op == 1 then
						local o = outcome({
							damage = rng:range(-50, 400),
							modulesHit = {
								{
									kind = kinds[rng:int(1, #kinds)],
									damage = rng:range(0, 300),
									external = false,
									volumeId = 1,
								},
							},
							crewHit = { { slot = rng:int(1, 4), damage = rng:range(0, 200), volumeId = 1 } },
						})
						DamageModel.apply(s, o, rng, rng:int(1, 3), events)
					elseif op == 2 then
						DamageModel.update(s, rng:range(0, 2), rng, events)
					elseif op == 3 then
						DamageModel.applyRam(s, step, rng:range(0, 200), rng:range(0, 300), rng, 1, events)
					elseif op == 4 then
						DamageModel.applyFall(s, -step, rng:range(0, 14), rng:chance(0.2), rng, events)
					elseif op == 5 then
						DamageModel.useRepairKit(s, events)
					elseif op == 6 then
						DamageModel.useMedkit(s, events)
					elseif op == 7 then
						DamageModel.ignite(s, 2, events)
					elseif op == 8 then
						DamageModel.applySplash(s, {
							index = 1,
							damage = rng:range(0, 100),
							distanceM = 0,
							thicknessMm = 0,
							stunS = rng:range(0, 5),
							modulesHit = {},
						}, rng, 3, events)
					else
						DamageModel.updateDrowning(s, rng:chance(0.5), rng:range(0, 3), events)
					end
					expect(s.hp >= 0 and s.hp <= s.maxHp).toBe(true)
					expect(s.hp % 1).toBe(0)
					for _, kind in s.moduleOrder do
						local m = s.modules[kind]
						expect(m.hp >= 0 and m.hp <= m.maxHp).toBe(true)
						local expected = if m.hp <= 0
							then "Destroyed"
							elseif m.hp <= 0.5 * m.maxHp then "Damaged"
							else "Ok"
						expect(m.state).toBe(expected)
					end
					if s.destroyed then
						expect(s.hp).toBe(0)
						expect(s.fire.burning).toBe(false)
					end
				end
				expect(sumDamage(events)).toBe(s.maxHp - s.hp)
				-- nothing is emitted after the Destroyed event
				local destroyedAt = nil
				for i, e in events do
					if e.type == "Destroyed" then
						destroyedAt = i
					end
				end
				if destroyedAt ~= nil then
					expect(destroyedAt).toBe(#events)
				end
			end
		end)
	end)
end)
