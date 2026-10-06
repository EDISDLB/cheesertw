-- StatsCalculator: hand-computed resolution of the exemplar Iron Union vehicles (Kolmal, Ostmal, Bulmal), crew levels
-- and duties, equipment / skill / consumable / Field Kit / Apex stacking, shell defaults, conditional copies, the
-- runtime cache (effects, damaged-module penalties, conditions, active sources, sim/turret/aim writers) and
-- determinism. Regression ids: REG-CRW-01 (table-driven crew contributions; group perks scale by crew share per
-- 00-DECISIONS §12, which supersedes the catalogue's "iff every member" rule), REG-EQP-01 (stacking table-driven,
-- garage == server for random loadouts), REG-EQP-02 (category bonus only for the matching category in slot 1),
-- REG-EQP-05 (Field Kit effects appear in StatsCalculator), REG-CRW-04 (injury effects removed in the heal tick),
-- REG-RET-05 (reload multiplier follows loader injury/heal through the runtime).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local StatsCalculator = require("@game/ReplicatedStorage/Shared/Vehicle/StatsCalculator")
local ContentRegistry = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")
local DamageModel = require("@game/ReplicatedStorage/Shared/Combat/DamageModel")
local CrewEffects = require("@game/ReplicatedStorage/Shared/Combat/CrewEffects")
local Dispersion = require("@game/ReplicatedStorage/Shared/Combat/Dispersion")
local VehicleSim = require("@game/ReplicatedStorage/Shared/Vehicle/VehicleSim")
local TurretSim = require("@game/ReplicatedStorage/Shared/Vehicle/TurretSim")
local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")

local EPS = 1e-9

-- Crew curves (00-DECISIONS §4), written out so every expectation below is a hand computation.
local function reloadF(L: number): number
	return 0.875 / (0.00375 * L + 0.5)
end
local function statF(L: number): number
	return 0.57 + 0.0043 * L
end

local function mod(stat: string, op: string, value: number, extra: any?): any
	local m: any = { stat = stat, op = op, value = value }
	if extra then
		for k, v in extra do
			m[k] = v
		end
	end
	return m
end

local function equipment(id: string, categories: { string }, group: string, effects: { any }, extra: any?): any
	local def: any = {
		id = id,
		name = id,
		description = id,
		icon = "equipment/test",
		categories = categories,
		grade = "Standard",
		tiers = { min = 1, max = 11 },
		exclusiveGroup = group,
		effects = effects,
		price = { credits = 1000 },
	}
	if extra then
		for k, v in extra do
			def[k] = v
		end
	end
	return def
end

local function skill(id: string, roles: { string }, kind: string, effects: { any }): any
	return { id = id, name = id, description = id, icon = "crew/test", roles = roles, kind = kind, effects = effects }
end

local function consumable(id: string, activation: string, group: string, extra: any?): any
	local def: any = {
		id = id,
		name = id,
		description = id,
		icon = "consumables/test",
		kind = "Utility",
		activation = activation,
		exclusiveGroup = group,
		price = { credits = 3000 },
	}
	if extra then
		for k, v in extra do
			def[k] = v
		end
	end
	return def
end

local function find(list: { any }, id: any): any
	for _, def in list do
		if def.id == id then
			return def
		end
	end
	error("fixture: missing " .. tostring(id))
end

local ALL_ROLES = { "Commander", "Gunner", "Driver", "Loader" }
local ALL_CATEGORIES = { "Firepower", "Survivability", "Mobility", "Scouting" }

-- Shipped content + loadout items + three test vehicles (Tier VI category-slot copy, two Apex copies) built from
-- the Bulmal so checkConfiguration passes with the real modules.
local function fixtureBundle(): any
	local bundle: any = ContentRegistry.shippedBundle()
	bundle.equipment = {
		equipment("rammer", { "Firepower" }, "rammer", { mod("reloadTime", "mul", 0.90) }, {
			categorySlotEffects = { mod("reloadTime", "mul", 0.885) },
			compatibility = { excludeReload = { "Magazine" } },
		}),
		equipment("rammer_b", { "Firepower" }, "rammer", { mod("reloadTime", "mul", 0.50) }),
		equipment("vents", ALL_CATEGORIES, "vents", { mod("crewLevel", "add", 5) }, {
			categorySlotEffects = { mod("crewLevel", "add", 6) },
		}),
		equipment("lenses", { "Scouting" }, "optics", { mod("viewRange", "mul", 1.10) }),
		equipment("netting", { "Scouting" }, "net", {}, {
			effectsByClass = {
				light = { mod("camoNet", "add", 0.10) },
				medium = { mod("camoNet", "add", 0.10) },
				heavy = { mod("camoNet", "add", 0.05) },
				td = { mod("camoNet", "add", 0.15) },
			},
		}),
		equipment("gyro", { "Firepower" }, "gyro", {
			mod("bloomMovement", "mul", 0.80),
			mod("bloomHullTraverse", "mul", 0.80),
		}),
		equipment("torsion", { "Survivability" }, "torsion", {
			mod("hp", "mul", 1.08),
			mod("moduleHp", "mul", 1.5, { module = "TrackLeft" }),
			mod("moduleHp", "mul", 1.5, { module = "TrackRight" }),
		}),
		equipment("spall", { "Survivability" }, "spall", {
			mod("spallFactor", "add", 0.50),
			mod("stunDuration", "mul", 0.70),
		}),
		equipment("dcs", { "Survivability" }, "dcs", {
			mod("repairTime", "mul", 1 / 1.45),
			mod("moduleHp", "mul", 2.5, { module = "AmmoRack" }),
			mod("moduleHp", "mul", 2.5, { module = "Engine" }),
			mod("fireChance", "mul", 0.35),
		}),
		equipment("turbo_kit", { "Mobility" }, "turbo", {
			mod("enginePower", "mul", 1.075),
			mod("topSpeed", "add", 4),
		}),
		equipment("mast", { "Scouting" }, "optics", {
			mod("viewRange", "mul", 1.25, { condition = "StationaryArmed" }),
		}),
	}
	bundle.crewSkills = {
		skill("snap_shot", { "Gunner" }, "Individual", { mod("bloomTurretTraverse", "mul", 0.925) }),
		skill("brothers", ALL_ROLES, "Group", { mod("crewLevel", "add", 5) }),
		skill("intuition", { "Loader" }, "Individual", { mod("shellSwapTime", "mul", 0.6) }),
		skill("deadeye", { "Gunner" }, "Individual", {
			mod("dispersion", "mul", 0.96, { condition = "StationaryArmed" }),
		}),
		skill("close_combat", { "Loader" }, "Individual", {
			mod("reloadTime", "mul", 0.90, { condition = "NearEnemy", rangeM = 50 }),
		}),
		skill("recon", { "Commander" }, "Individual", {
			mod("viewRange", "mul", 1.02),
			mod("damagedModulePenalty", "mul", 0.5, { module = "Optics" }),
		}),
		skill("concealment", ALL_ROLES, "Group", {
			mod("camoStationary", "mul", 1.8),
			mod("camoMoving", "mul", 1.8),
		}),
	}
	bundle.consumables = {
		consumable("rations", "Passive", "ration", { effects = { mod("crewLevel", "add", 10) } }),
		consumable("quality_fuel", "Passive", "fuel", { effects = { mod("enginePower", "mul", 1.05) } }),
		consumable("large_repair", "Manual", "repair", {
			cooldownS = 60,
			passiveEffects = { mod("repairTime", "mul", 0.90) },
			repairs = { modules = true },
		}),
		consumable("adrenaline", "Manual", "adrenaline", {
			cooldownS = 90,
			durationS = 10,
			effects = { mod("reloadTime", "mul", 0.5) },
		}),
	}
	bundle.customization = {
		{
			id = "paint_test",
			name = "Test paint",
			icon = "customization/test",
			kind = "Paint",
			rarity = "common",
			colors = { Color3.new(0.5, 0.5, 0.5) },
			camoBonus = true,
			source = "Store",
		},
		{
			id = "paint_plain",
			name = "Plain paint",
			icon = "customization/test",
			kind = "Paint",
			rarity = "common",
			colors = { Color3.new(0.5, 0.5, 0.5) },
			source = "Store",
		},
	}
	local bulmal = find(bundle.vehicles, "iu_bulmal")
	local six = table.clone(bulmal)
	six.id = "iu_testsix"
	six.tier = 6
	table.insert(bundle.vehicles, six)
	local apex = table.clone(bulmal)
	apex.id = "iu_testapex"
	apex.tier = 11
	apex.mechanics = {
		{ kind = "ChargedShot", chargeTimeS = 1.5, effect = "Damage", damageMul = 1.10 },
		{ kind = "ReserveTracks", charges = 1, repairS = 6, cooldownS = 30 },
	}
	apex.apex = {
		nodes = {
			{
				id = "n_final",
				name = "Final",
				kind = "Final",
				xp = 12000,
				effects = { mod("mechanicChargeTime", "mul", 0.8) },
			},
			{ id = "n_hp", name = "Hull", kind = "Small", xp = 4000, effects = { mod("hp", "mul", 1.02) } },
			{
				id = "n_more",
				name = "Spares",
				kind = "Large",
				xp = 8000,
				effects = { mod("mechanicCharges", "add", 1) },
			},
		},
	}
	table.insert(bundle.vehicles, apex)
	local boost = table.clone(bulmal)
	boost.id = "iu_testboost"
	boost.tier = 11
	boost.mechanics = {
		{ kind = "RocketBoost", charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 },
	}
	boost.apex = {
		nodes = {
			{
				id = "n_cd",
				name = "Cooldown",
				kind = "Final",
				xp = 1,
				effects = { mod("mechanicCooldown", "mul", 25 / 30) },
			},
			{
				id = "n_dur",
				name = "Duration",
				kind = "Large",
				xp = 1,
				effects = { mod("mechanicDuration", "add", 0.5) },
			},
		},
	}
	table.insert(bundle.vehicles, boost)
	local siege = table.clone(bulmal)
	siege.id = "iu_testsiege"
	siege.mechanics = {
		{
			kind = "SiegeMode",
			engageS = 2,
			disengageS = 1.25,
			maxSpeedKmh = 10,
			modifiers = {
				mod("aimTime", "mul", 0.4),
				mod("dispersion", "mul", 0.85),
				mod("gunDepression", "add", 8),
				mod("hullTraverse", "mul", 0.5),
			},
		},
	}
	table.insert(bundle.vehicles, siege)
	return bundle
end

local REGISTRY = ContentRegistry.fromBundle(fixtureBundle())

local function vehicle(id: string): any
	return REGISTRY:getVehicle(id) :: any
end

local function loadoutFor(id: string, configuration: any?): any
	local def = vehicle(id)
	local l: any = StatsCalculator.defaultLoadout(def, REGISTRY, configuration)
	return l
end

local function computeOk(id: string, configuration: any?, loadout: any?, opts: any?): any
	local def = vehicle(id)
	local result = StatsCalculator.compute(def, configuration or def.top, loadout, REGISTRY, opts)
	if not result.ok then
		error(`compute {id} failed: {tostring((result :: any).err)} {tostring((result :: any).detail)}`)
	end
	return (result :: any).value
end

describe("StatsCalculator.compute: exemplar Iron Union vehicles (hand-computed, trained crew L 100)", function()
	it("Kolmal top: base stats straight from modules, class and tier", function()
		local s = computeOk("iu_kolmal")
		expect(s.vehicleId).toBe("iu_kolmal")
		expect(s.class).toBe("medium")
		expect(s.premium).toBe(false)
		expect(s.hp).toBe(280) -- hull 280 + turret hpBonus 0
		expect(s.massKg).toBe(6900 + 520 + 1100 + 600 + 900) -- 10,020 kg
		expect(s.enginePowerHp).toBe(120)
		expect(s.specificPowerHpT).toBeCloseTo(120 / 10.02, EPS)
		expect(s.topSpeedKmh).toBe(36)
		expect(s.reverseSpeedKmh).toBe(13)
		expect(s.hullTraverseDegS).toBeCloseTo(36, EPS)
		expect(s.turretTraverseDegS).toBeCloseTo(38, EPS)
		expect(s.loadLimitKg).toBe(10100)
		expect(s.pivot).toBe(true)
		expect(s.wheeled).toBeNil()
		expect(s.turretMount).toBe("Turret")
		expect(s.yawLimitsDeg).toBeNil()
		expect(s.terrainResistance).toEqual({ hard = 0.9, medium = 1.1, soft = 1.9 })
		expect(s.dimensionsM).toEqual(Vector3.new(2.3, 1.4, 4.4))
		expect(s.viewRangeM).toBeCloseTo(300, EPS) -- 300 × medium 1.0 × f(100)
		expect(s.signalRangeM).toBe(600)
		expect(s.fireChance).toBeCloseTo(0.12, EPS) -- diesel
		expect(s.fireDurationS).toBe(8)
		expect(s.spallFactor).toBe(1)
		expect(s.consumableSlots).toBe(3)
		expect(s.crewXpMul).toBe(1)
		expect(s.conditionalModifiers).toEqual({})
		expect(s.mechanics).toEqual({})
	end)

	it("Kolmal top gun: reload, aim, dispersion, bloom, arcs, swap and after-shot camo", function()
		local g = computeOk("iu_kolmal").gun
		expect(g.id).toBe("iu_gun_45mm")
		expect(g.reload).toEqual({ kind = "Single", reloadS = 2.4 })
		expect(g.aimTimeS).toBeCloseTo(2.1, EPS)
		expect(g.dispersionM100).toBeCloseTo(0.52, EPS)
		expect(g.bloom).toEqual({
			movementPerKmh = 0.07,
			hullTraversePerDegS = 0.075,
			turretTraversePerDegS = 0.03,
			afterShot = 3.0, -- medium class
			damagedMul = 1.5,
		})
		expect(g.depressionDeg).toBe(5)
		expect(g.elevationDeg).toBe(20)
		expect(g.arcSectors).toEqual({})
		expect(g.ammoCapacity).toBe(100)
		expect(g.shellSwapS).toBeCloseTo(2.4, EPS) -- default = one reload
		expect(g.camoAfterShotMul).toBeCloseTo(0.40 - 0.0025 * (45 - 20), EPS) -- 0.3375
		expect(g.indirect).toBe(false)
		expect(g.damageRollMinAdd).toBe(0)
		expect(g.penetrationRollMinAdd).toBe(0)
		expect(#g.shells).toBe(3)
	end)

	it("Kolmal shells: every content default resolved (00-DECISIONS §1)", function()
		local shells = computeOk("iu_kolmal").gun.shells
		local ap, apcr, he = shells[1], shells[2], shells[3]
		expect(ap).toEqual({
			id = "iu_45mm_ap",
			kind = "AP",
			special = false,
			caliberMm = 45,
			damage = 50,
			moduleDamage = 25, -- 0.5 α
			penetrationMm = 45,
			penetrationAt500Mm = 45 * 0.90,
			velocityMps = 456,
			gravityMps2 = 19.62,
			maxRangeM = 600,
			explosionRadiusM = 0,
			normalizationDeg = 5,
			ricochetAngleDeg = 70,
			priceCredits = 50,
			tracer = "AP",
		})
		expect(apcr.penetrationAt500Mm).toBeCloseTo(58 * 0.75, EPS)
		expect(apcr.normalizationDeg).toBe(2)
		expect(apcr.tracer).toBe("APCR")
		expect(apcr.special).toBe(true)
		expect(he.moduleDamage).toBeCloseTo(0.75 * 65, EPS)
		expect(he.penetrationAt500Mm).toBe(22) -- no falloff for HE
		expect(he.explosionRadiusM).toBe(0.45) -- authored
		expect(he.ricochetAngleDeg).toBe(90) -- HE never ricochets
		expect(he.normalizationDeg).toBe(0)
		expect(he.tracer).toBe("HE")
	end)

	it("Kolmal stock: the 37 mm and the same chassis", function()
		local def = vehicle("iu_kolmal")
		local s = computeOk("iu_kolmal", def.stock)
		expect(s.massKg).toBe(9850)
		expect(s.gun.reload).toEqual({ kind = "Single", reloadS = 1.9 })
		expect(s.gun.ammoCapacity).toBe(120)
		expect(s.gun.camoAfterShotMul).toBeCloseTo(0.40 - 0.0025 * 17, EPS)
	end)

	it("Kolmal modules and crew: HP = k × tier reference α 40, crew HP 0.8 × 40, base repair times", function()
		local s = computeOk("iu_kolmal")
		local expected = {
			Engine = { 40, 14 },
			AmmoRack = { 36, 10 },
			FuelTank = { 40, 10 },
			Gun = { 40, 12 },
			TurretRing = { 40, 12 },
			Optics = { 32, 8 },
			TrackLeft = { 56, 10 },
			TrackRight = { 56, 10 },
		}
		for kind, v in expected do
			expect(s.modules[kind].maxHp).toBe(v[1])
			expect(s.modules[kind].repairS).toBeCloseTo(v[2], EPS)
			expect(s.modules[kind].damagedPenaltyMul).toBe(1)
			expect(s.modules[kind].maxHp).toBe(DamageModel.moduleHpFor(kind :: any, 40))
		end
		expect(#s.crew).toBe(2)
		expect(s.crew[1]).toEqual({
			slot = 1,
			role = "Commander",
			also = { "Gunner", "Loader" },
			level = 100,
			maxHp = 32,
		})
		expect(s.crew[2]).toEqual({ slot = 2, role = "Driver", also = {}, level = 100, maxHp = 32 })
		expect(s.crewLevels).toEqual({ Commander = 100, Gunner = 100, Driver = 100, Loader = 100 })
		expect(s.repairTimeMul).toBeCloseTo(1, EPS)
	end)

	it("Ostmal top: tier II modules, refAlpha 50, three seats", function()
		local s = computeOk("iu_ostmal")
		expect(s.hp).toBe(380)
		expect(s.massKg).toBe(8200 + 780 + 1600 + 750 + 1150) -- 12,480
		expect(s.specificPowerHpT).toBeCloseTo(165 / 12.48, EPS)
		expect(s.hullTraverseDegS).toBeCloseTo(38, EPS) -- m2 tracks
		expect(s.turretTraverseDegS).toBeCloseTo(40, EPS)
		expect(s.viewRangeM).toBeCloseTo(310, EPS)
		expect(s.gun.reload).toEqual({ kind = "Single", reloadS = 2.9 })
		expect(s.gun.depressionDeg).toBe(5)
		expect(s.gun.elevationDeg).toBe(18)
		expect(s.modules.Engine.maxHp).toBe(50)
		expect(s.modules.AmmoRack.maxHp).toBe(45)
		expect(s.modules.Optics.maxHp).toBe(40)
		expect(s.modules.TrackLeft.maxHp).toBe(70)
		expect(s.crew[1].maxHp).toBe(40)
		expect(s.terrainResistance).toEqual({ hard = 0.9, medium = 1.1, soft = 1.9 })
	end)

	it("Bulmal top: turret HP bonus, rear arc sector, refAlpha 60, two loaders", function()
		local s = computeOk("iu_bulmal")
		expect(s.hp).toBe(440 + 20)
		expect(s.massKg).toBe(11800 + 1150 + 2700 + 880 + 1700) -- 18,230 ≤ 18,800
		expect(s.enginePowerHp).toBe(250)
		expect(s.specificPowerHpT).toBeCloseTo(250 / 18.23, EPS)
		expect(s.topSpeedKmh).toBe(43)
		expect(s.reverseSpeedKmh).toBe(15)
		expect(s.hullTraverseDegS).toBeCloseTo(37, EPS)
		expect(s.turretTraverseDegS).toBeCloseTo(40, EPS)
		expect(s.viewRangeM).toBeCloseTo(320, EPS)
		expect(s.gun.reload).toEqual({ kind = "Single", reloadS = 3.0 })
		expect(s.gun.arcSectors).toEqual({ { fromDeg = 150, toDeg = -150, depressionDeg = 2 } })
		expect(s.gun.shells[3].explosionRadiusM).toBe(0.76)
		expect(s.modules.Engine.maxHp).toBe(60)
		expect(s.modules.AmmoRack.maxHp).toBe(54)
		expect(s.modules.TrackRight.maxHp).toBe(84)
		expect(#s.crew).toBe(5)
		expect(s.crew[5].role).toBe("Loader")
		expect(s.crew[1].maxHp).toBe(48)
	end)

	it("Bulmal stock fits its stock tracks; the top turret on stock tracks is rejected (load limit)", function()
		local def = vehicle("iu_bulmal")
		local s = computeOk("iu_bulmal", def.stock)
		expect(s.massKg).toBe(11800 + 780 + 2100 + 800 + 1600) -- 17,080 ≤ 17,400
		expect(s.gun.id).toBe("iu_gun_63mm")
		local heavy = {
			gun = "iu_gun_76mm",
			turret = "iu_turret_bulmal_m2",
			engine = "iu_engine_d250",
			tracks = "iu_tracks_bulmal_m1",
		}
		local result = StatsCalculator.compute(def, heavy, nil, REGISTRY)
		expect(result).toBeErr("INVALID_ARGS")
	end)

	it("validates the configuration and the loadout's vehicle", function()
		local def = vehicle("iu_kolmal")
		local foreign = table.clone(def.top)
		foreign.gun = "iu_gun_76mm"
		expect(StatsCalculator.compute(def, foreign, nil, REGISTRY)).toBeErr("INVALID_ARGS")
		local unknown = table.clone(def.top)
		unknown.engine = "no_such_engine"
		expect(StatsCalculator.compute(def, unknown, nil, REGISTRY)).toBeErr("NOT_FOUND")
		local ghost = table.clone(def)
		ghost.id = "iu_ghost"
		expect(StatsCalculator.compute(ghost, def.top, nil, REGISTRY)).toBeErr("NOT_FOUND")
		local l = loadoutFor("iu_ostmal")
		expect(StatsCalculator.compute(def, def.top, l, REGISTRY)).toBeErr("INVALID_ARGS")
		expect(StatsCalculator.compute(nil :: any, def.top, nil, REGISTRY)).toBeErr("INVALID_ARGS")
		expect(StatsCalculator.fromLoadout(nil :: any, REGISTRY)).toBeErr("INVALID_ARGS")
		local stray = loadoutFor("iu_kolmal")
		stray.vehicleId = "iu_ghost"
		expect(StatsCalculator.fromLoadout(stray, REGISTRY)).toBeErr("NOT_FOUND")
	end)

	it("unknown loadout items are NOT_FOUND (equipment, skill, consumable, Field Kit, Apex node)", function()
		local cases = {
			function(l)
				l.equipment = { { slot = 1, id = "no_such_item" } }
			end,
			function(l)
				l.crew[1].skills = { { id = "no_such_skill", training = 1 } }
			end,
			function(l)
				l.consumables = { { slot = 1, id = "no_such_kit" } }
			end,
			function(l)
				l.fieldKit = { "no_such_option" }
			end,
			function(l)
				l.apexNodes = { "no_such_node" }
			end,
		}
		for i, mutate in cases do
			local l = loadoutFor("iu_bulmal")
			mutate(l)
			local result = StatsCalculator.compute(vehicle("iu_bulmal"), l.configuration, l, REGISTRY)
			if result.ok then
				error(`case {i}: expected NOT_FOUND`)
			end
			expect(result).toBeErr("NOT_FOUND")
		end
	end)

	it("results are deep-frozen unless mutable; compute is deterministic", function()
		local a = computeOk("iu_bulmal")
		expect(table.isfrozen(a)).toBe(true)
		expect(table.isfrozen(a.gun.shells[1])).toBe(true)
		expect(table.isfrozen(a.modules.Engine)).toBe(true)
		local b = computeOk("iu_bulmal", nil, nil, { mutable = true })
		expect(table.isfrozen(b)).toBe(false)
		expect(b).toEqual(a)
	end)
end)

describe("StatsCalculator.compute: crew (00-DECISIONS §4 'L', §12; REG-CRW-01)", function()
	it("L 120 (ventilation + rations + Brothers in Arms) scales every duty's stats", function()
		local l = loadoutFor("iu_bulmal")
		l.equipment = { { slot = 1, id = "vents" } }
		l.consumables = { { slot = 1, id = "rations" } }
		for _, m in l.crew do
			m.skills = { { id = "brothers", training = 1 } }
		end
		local s = computeOk("iu_bulmal", nil, l)
		for _, m in s.crew do
			expect(m.level).toBe(120)
		end
		expect(s.crewLevels).toEqual({ Commander = 120, Gunner = 120, Driver = 120, Loader = 120 })
		local f = statF(120) -- 1.086
		expect(s.gun.reload.reloadS).toBeCloseTo(3.0 * reloadF(120), EPS) -- 2.7632
		expect(s.gun.reload.reloadS).toBeCloseTo(2.763157894736842, 1e-12)
		expect(s.viewRangeM).toBeCloseTo(320 * f, EPS) -- 347.52
		expect(s.turretTraverseDegS).toBeCloseTo(40 * f, EPS)
		expect(s.hullTraverseDegS).toBeCloseTo(37 * f, EPS)
		expect(s.gun.aimTimeS).toBeCloseTo(2.2 / f, EPS)
		expect(s.gun.dispersionM100).toBeCloseTo(0.50 / f, EPS)
		expect(s.modules.Engine.repairS).toBeCloseTo(14 / f, EPS)
		expect(s.modules.Optics.repairS).toBeCloseTo(8 / f, EPS)
		expect(s.repairTimeMul).toBeCloseTo(1 / f, EPS)
		expect(s.gun.shellSwapS).toBeCloseTo(3.0 * reloadF(120), EPS)
	end)

	it("loaders are averaged; each other stat follows the member holding its duty", function()
		local l = loadoutFor("iu_bulmal")
		l.crew[1].level = 110 -- commander
		l.crew[2].level = 90 -- gunner
		l.crew[3].level = 130 -- driver
		l.crew[4].level = 100 -- loader
		l.crew[5].level = 60 -- loader: average 80
		local s = computeOk("iu_bulmal", nil, l)
		expect(s.crewLevels).toEqual({ Commander = 110, Gunner = 90, Driver = 130, Loader = 80 })
		expect(s.gun.reload.reloadS).toBeCloseTo(3.0 * 0.875 / 0.8, EPS) -- reloadF(80) = 1.09375
		expect(s.viewRangeM).toBeCloseTo(320 * statF(110), EPS)
		expect(s.gun.aimTimeS).toBeCloseTo(2.2 / statF(90), EPS)
		expect(s.turretTraverseDegS).toBeCloseTo(40 * statF(90), EPS)
		expect(s.hullTraverseDegS).toBeCloseTo(37 * statF(130), EPS)
		expect(s.modules.Gun.repairS).toBeCloseTo(12 / statF(130), EPS)
		-- the same duty averaging as Combat's CrewEffects (runtime injury ratios start from these levels)
		local combatCrew = {}
		for _, m in s.crew do
			table.insert(
				combatCrew,
				{ slot = m.slot, role = m.role, also = m.also, level = m.level, hp = 1, maxHp = 1, injured = false }
			)
		end
		for _, duty in ALL_ROLES do
			expect(CrewEffects.dutyLevel(combatCrew :: any, duty :: any, true)).toBe(s.crewLevels[duty])
		end
	end)

	it("a commander doubling as gunner and loader drives all three duties (Kolmal)", function()
		local l = loadoutFor("iu_kolmal")
		l.crew[1].level = 120
		local s = computeOk("iu_kolmal", nil, l)
		expect(s.crewLevels).toEqual({ Commander = 120, Gunner = 120, Driver = 100, Loader = 120 })
		expect(s.gun.reload.reloadS).toBeCloseTo(2.4 * reloadF(120), EPS)
		expect(s.hullTraverseDegS).toBeCloseTo(36, EPS)
	end)

	it("table: Individual skills scale by the average training of the duty's holders, Group by crew share", function()
		-- { description, mutate(loadout), stat getter, expected }
		local rows: { { any } } = {
			{
				"Snap Shot on the Kolmal commander-gunner at 40 %",
				"iu_kolmal",
				function(l)
					l.crew[1].skills = { { id = "snap_shot", training = 0.4 } }
				end,
				function(s)
					return s.gun.bloom.turretTraversePerDegS
				end,
				0.03 * (1 - 0.075 * 0.4),
			},
			{
				"Intuition on one of two loaders: half the effect",
				"iu_bulmal",
				function(l)
					l.crew[4].skills = { { id = "intuition", training = 1 } }
				end,
				function(s)
					return s.gun.shellSwapS
				end,
				3.0 * (1 - 0.4 * 0.5),
			},
			{
				"Intuition on both loaders",
				"iu_bulmal",
				function(l)
					l.crew[4].skills = { { id = "intuition", training = 1 } }
					l.crew[5].skills = { { id = "intuition", training = 1 } }
				end,
				function(s)
					return s.gun.shellSwapS
				end,
				3.0 * 0.6,
			},
			{
				"Brothers in Arms on 3 of 5 members (1, 1, 0.5): +5 × 2.5/5 L",
				"iu_bulmal",
				function(l)
					l.crew[1].skills = { { id = "brothers", training = 1 } }
					l.crew[2].skills = { { id = "brothers", training = 1 } }
					l.crew[3].skills = { { id = "brothers", training = 0.5 } }
				end,
				function(s)
					return s.crew[4].level
				end,
				102.5,
			},
			{
				"retrain penalty: crewPerkEfficiency 0.75 scales every skill",
				"iu_bulmal",
				function(l)
					for _, m in l.crew do
						m.skills = { { id = "brothers", training = 1 } }
					end
					l.crewPerkEfficiency = 0.75
				end,
				function(s)
					return s.crew[1].level
				end,
				103.75,
			},
			{
				"Concealment on every member: body camo × 1.8",
				"iu_bulmal",
				function(l)
					for _, m in l.crew do
						m.skills = { { id = "concealment", training = 1 } }
					end
				end,
				function(s)
					return s.camo.stationary
				end,
				0.12 * 1.8,
			},
			{
				"Recon: view range +2 % and the optics damaged-state penalty halved",
				"iu_bulmal",
				function(l)
					l.crew[1].skills = { { id = "recon", training = 1 } }
				end,
				function(s)
					return s.viewRangeM * 1000 + s.modules.Optics.damagedPenaltyMul
				end,
				320 * 1.02 * 1000 + 0.5,
			},
			{
				"an untrained (0 %) skill does nothing",
				"iu_bulmal",
				function(l)
					l.crew[2].skills = { { id = "snap_shot", training = 0 } }
				end,
				function(s)
					return s.gun.bloom.turretTraversePerDegS
				end,
				0.03,
			},
		}
		for _, row in rows do
			local name, id, mutate, get, want = row[1], row[2], row[3], row[4], row[5]
			local l = loadoutFor(id)
			mutate(l)
			local got = get(computeOk(id, nil, l))
			if math.abs(got - want) > 1e-9 then
				error(`{name}: got {got}, expected {want}`)
			end
		end
	end)
end)

describe("StatsCalculator.compute: equipment, consumables, Field Kit, Apex (REG-EQP-01/02/05)", function()
	it("rammer + ventilation stack multiplicatively through the crew curve", function()
		local l = loadoutFor("iu_bulmal")
		l.equipment = { { slot = 1, id = "rammer" }, { slot = 2, id = "vents" } }
		local s = computeOk("iu_bulmal", nil, l)
		expect(s.crew[1].level).toBe(105)
		expect(s.gun.reload.reloadS).toBeCloseTo(3.0 * reloadF(105) * 0.90, EPS) -- 2.6434
		expect(s.gun.reload.reloadS).toBeCloseTo(2.6433566433566433, 1e-12)
	end)

	it("a second item of the same exclusive group never stacks", function()
		local l = loadoutFor("iu_bulmal")
		l.equipment = { { slot = 2, id = "rammer_b" }, { slot = 1, id = "rammer" } }
		local s = computeOk("iu_bulmal", nil, l)
		expect(s.gun.reload.reloadS).toBeCloseTo(3.0 * 0.90, EPS) -- slot 1 wins, slot 2 skipped
	end)

	it("survivability and scouting items land in their homes", function()
		local l = loadoutFor("iu_bulmal")
		l.equipment = { { slot = 1, id = "torsion" }, { slot = 2, id = "spall" } }
		local s = computeOk("iu_bulmal", nil, l)
		expect(s.hp).toBe(math.floor(460 * 1.08 + 0.5)) -- 497
		expect(s.modules.TrackLeft.maxHp).toBe(126) -- 84 × 1.5
		expect(s.modules.TrackRight.maxHp).toBe(126)
		expect(s.modules.Engine.maxHp).toBe(60)
		expect(s.spallFactor).toBeCloseTo(1.5, EPS)
		expect(s.stunDurationMul).toBeCloseTo(0.7, EPS)
		local d = loadoutFor("iu_bulmal")
		d.equipment = { { slot = 1, id = "dcs" }, { slot = 2, id = "lenses" } }
		local t = computeOk("iu_bulmal", nil, d)
		expect(t.modules.AmmoRack.maxHp).toBe(135) -- 54 × 2.5
		expect(t.modules.Engine.maxHp).toBe(150)
		expect(t.modules.Optics.maxHp).toBe(48)
		expect(t.modules.Engine.repairS).toBeCloseTo(14 / 1.45, EPS)
		expect(t.repairTimeMul).toBeCloseTo(1 / 1.45, EPS)
		expect(t.fireChance).toBeCloseTo(0.12 * 0.35, EPS)
		expect(t.viewRangeM).toBeCloseTo(320 * 1.10, EPS)
	end)

	it("class-scaled items use effectsByClass (camo net +0.10 on a medium)", function()
		local l = loadoutFor("iu_bulmal")
		l.equipment = { { slot = 1, id = "netting" }, { slot = 2, id = "gyro" } }
		local s = computeOk("iu_bulmal", nil, l)
		expect(s.camo.net).toBeCloseTo(0.10, EPS)
		expect(s.gun.bloom.movementPerKmh).toBeCloseTo(0.07 * 0.8, EPS)
		expect(s.gun.bloom.hullTraversePerDegS).toBeCloseTo(0.075 * 0.8, EPS)
		expect(s.gun.bloom.turretTraversePerDegS).toBeCloseTo(0.03, EPS)
	end)

	it("category slot (Tier VI+): only slot 1 and only the role's category get +15 % (REG-EQP-02)", function()
		-- iu_testsix is a medium_versatile at Tier VI: category Mobility
		local rows = {
			-- equipment list, expected power, expected top speed, expected reload
			{ { { slot = 1, id = "turbo_kit" } }, 250 * (1 + 0.075 * 1.15), 43 + 4 * 1.15, 3.0 },
			{ { { slot = 2, id = "turbo_kit" } }, 250 * 1.075, 47, 3.0 },
			{ { { slot = 1, id = "rammer" } }, 250, 43, 3.0 * 0.90 }, -- Firepower ≠ Mobility: no bonus
		}
		for i, row in rows do
			local l = loadoutFor("iu_testsix")
			l.equipment = row[1]
			local s = computeOk("iu_testsix", nil, l)
			if math.abs(s.enginePowerHp - row[2]) > 1e-9 or math.abs(s.topSpeedKmh - row[3]) > 1e-9 then
				error(`row {i}: power {s.enginePowerHp}, speed {s.topSpeedKmh}`)
			end
			expect(s.gun.reload.reloadS).toBeCloseTo(row[4], EPS)
		end
		-- explicit categorySlotEffects win over the ×1.15 rule (vents: +6 L instead of +5.75)
		local l = loadoutFor("iu_testsix")
		l.equipment = { { slot = 1, id = "vents" } }
		expect(computeOk("iu_testsix", nil, l).crew[1].level).toBe(106)
		-- below Tier VI there is no category slot
		local low = loadoutFor("iu_bulmal")
		low.equipment = { { slot = 1, id = "turbo_kit" } }
		expect(computeOk("iu_bulmal", nil, low).enginePowerHp).toBeCloseTo(250 * 1.075, EPS)
		-- Tier VI reference alpha: module HP 160 k
		expect(computeOk("iu_testsix").modules.Engine.maxHp).toBe(160)
	end)

	it("consumables: passive effects and passiveEffects apply; timed effects wait for the runtime", function()
		local l = loadoutFor("iu_bulmal")
		l.consumables = {
			{ slot = 1, id = "quality_fuel" },
			{ slot = 2, id = "large_repair" },
			{ slot = 3, id = "adrenaline" },
		}
		local s = computeOk("iu_bulmal", nil, l)
		expect(s.enginePowerHp).toBeCloseTo(250 * 1.05, EPS)
		expect(s.specificPowerHpT).toBeCloseTo(262.5 / 18.23, EPS)
		expect(s.modules.Engine.repairS).toBeCloseTo(14 * 0.90, EPS)
		expect(s.gun.reload.reloadS).toBeCloseTo(3.0, EPS) -- adrenaline is Manual: runtime only
	end)

	it("conditional modifiers are copied with their share already applied", function()
		local l = loadoutFor("iu_bulmal")
		l.crew[2].skills = { { id = "deadeye", training = 0.5 } }
		l.crew[4].skills = { { id = "close_combat", training = 1 } }
		l.equipment = { { slot = 1, id = "mast" } }
		local s = computeOk("iu_bulmal", nil, l)
		expect(#s.conditionalModifiers).toBe(3)
		local byStat = {}
		for _, m in s.conditionalModifiers do
			byStat[m.stat] = m
		end
		expect(byStat.viewRange.value).toBeCloseTo(1.25, EPS)
		expect(byStat.viewRange.condition).toBe("StationaryArmed")
		expect(byStat.dispersion.value).toBeCloseTo(1 - 0.04 * 0.5, EPS) -- deadeye at 50 %
		expect(byStat.reloadTime.value).toBeCloseTo(1 - 0.10 * 0.5, EPS) -- one of two loaders
		expect(byStat.reloadTime.rangeM).toBe(50)
		-- none of them touched the battle-start stats
		expect(s.viewRangeM).toBeCloseTo(320, EPS)
		expect(s.gun.dispersionM100).toBeCloseTo(0.50, EPS)
		expect(s.gun.reload.reloadS).toBeCloseTo(3.0, EPS)
	end)

	it("Apex nodes upgrade the resolved mechanic copies (mechanic* StatKeys) and stats", function()
		local l = loadoutFor("iu_testapex")
		l.apexNodes = { "n_final", "n_hp", "n_more" }
		local s = computeOk("iu_testapex", nil, l)
		expect(s.hp).toBe(math.floor(460 * 1.02 + 0.5))
		expect(s.mechanics[1].kind).toBe("ChargedShot")
		expect((s.mechanics[1] :: any).chargeTimeS).toBeCloseTo(1.2, EPS)
		expect((s.mechanics[1] :: any).damageMul).toBeCloseTo(1.10, EPS)
		expect((s.mechanics[2] :: any).charges).toBe(2)
		expect((s.mechanics[2] :: any).repairS).toBe(6)
		-- the definition itself is untouched
		expect((vehicle("iu_testapex").mechanics[1] :: any).chargeTimeS).toBe(1.5)
		local b = loadoutFor("iu_testboost")
		b.apexNodes = { "n_cd", "n_dur" }
		local rb = computeOk("iu_testboost", nil, b).mechanics[1] :: any
		expect(rb.cooldownS).toBeCloseTo(25, EPS)
		expect(rb.durationS).toBeCloseTo(3.0, EPS)
		expect(rb.charges).toBe(2)
		expect(rb.speedBonusKmh).toBe(20)
		-- without nodes the copy equals the authored spec
		expect(computeOk("iu_testboost").mechanics[1]).toEqual(vehicle("iu_testboost").mechanics[1])
	end)

	it("paint camo bonus: once, 0 in competitive queues, none without camoBonus", function()
		local l = loadoutFor("iu_bulmal")
		l.customization = { paint = "paint_test" }
		expect(computeOk("iu_bulmal", nil, l).camo.paint).toBeCloseTo(0.04, EPS)
		expect(computeOk("iu_bulmal", nil, l, { competitive = true }).camo.paint).toBe(0)
		l.customization = { paint = "paint_plain" }
		expect(computeOk("iu_bulmal", nil, l).camo.paint).toBe(0)
		l.customization = { paint = "unknown_cosmetic" }
		expect(computeOk("iu_bulmal", nil, l).camo.paint).toBe(0) -- cosmetics never block a battle
	end)

	it("casemate mounts default to ±CASEMATE_DEFAULT_YAW_DEG and indirect guns resolve artillery shells", function()
		local bundle = fixtureBundle()
		local turret = find(bundle.turrets, "iu_turret_kolmal")
		turret.mount = "Casemate"
		local gun = find(bundle.guns, "iu_gun_45mm")
		gun.indirect = true
		local he = find(bundle.shells, "iu_45mm_he")
		he.explosionRadiusM = nil
		local registry = ContentRegistry.fromBundle(bundle)
		local def = registry:getVehicle("iu_kolmal") :: any
		local result = StatsCalculator.compute(def, def.top, nil, registry)
		expect(result).toBeOk()
		local s = (result :: any).value
		expect(s.yawLimitsDeg).toEqual({ left = 11, right = 11 })
		expect(s.gun.indirect).toBe(true)
		expect(s.gun.shells[3].explosionRadiusM).toBeCloseTo(3 + 0.03 * 45, EPS)
		expect(s.gun.shells[3].tracer).toBe("Artillery")
		expect(s.camo.stationary).toBe(0.12) -- medium has no casemate camo: the class camo
	end)
end)

describe("StatsCalculator: loadout helpers and integration", function()
	it("defaultLoadout is a legal loadout for every shipped vehicle and fromLoadout == compute", function()
		local shipped = ContentRegistry.get()
		for _, def in shipped:allVehicles() do
			for _, cfg in { def.stock, def.top } do
				local l = StatsCalculator.defaultLoadout(def, shipped, cfg)
				expect(shipped:checkLoadout(l)).toBeOk()
				local a = StatsCalculator.fromLoadout(l, shipped)
				local b = StatsCalculator.compute(def, cfg, nil, shipped)
				expect(a).toBeOk()
				expect((a :: any).value).toEqual((b :: any).value)
			end
		end
	end)

	it("VehicleStats feed DamageModel.new, Dispersion.new, VehicleSim and TurretSim unchanged", function()
		local s = computeOk("iu_bulmal")
		local combat = DamageModel.new(s :: any)
		expect(combat.maxHp).toBe(460)
		expect(combat.modules.AmmoRack.maxHp).toBe(54)
		expect(combat.crewLevels.Loader).toBe(100)
		expect(combat.fireChance).toBeCloseTo(0.12, EPS)
		local aim = Dispersion.new(s.gun)
		expect(Dispersion.radiusM100(aim)).toBeCloseTo(0.50, EPS)
		local sim = VehicleSim.newState(CFrame.new())
		expect(sim.position).toEqual(Vector3.zero)
		expect(TurretSim.yawRange(s)).toBe(false)
	end)

	it("garage and server resolve random loadouts identically; outputs stay finite (seeded, REG-EQP-01)", function()
		local a = ContentRegistry.fromBundle(fixtureBundle())
		local b = ContentRegistry.fromBundle(fixtureBundle())
		local rng = RNG.new(77)
		local items = {
			"rammer",
			"rammer_b",
			"vents",
			"lenses",
			"netting",
			"gyro",
			"torsion",
			"spall",
			"dcs",
			"turbo_kit",
			"mast",
		}
		local kits = { "rations", "quality_fuel", "large_repair", "adrenaline" }
		local skills = { "snap_shot", "brothers", "intuition", "deadeye", "close_combat", "recon", "concealment" }
		local function finiteDeep(v: any, path: string)
			if type(v) == "number" then
				if v ~= v or v == math.huge or v == -math.huge then
					error("non-finite at " .. path)
				end
			elseif type(v) == "table" then
				for k, x in v do
					finiteDeep(x, path .. "." .. tostring(k))
				end
			end
		end
		for _, id in { "iu_kolmal", "iu_ostmal", "iu_bulmal", "iu_testsix" } do
			local def = a:getVehicle(id) :: any
			for _ = 1, 50 do
				local l: any = StatsCalculator.defaultLoadout(def, a)
				l.equipment = {}
				for slot = 1, 3 do
					if rng:chance(0.7) then
						table.insert(l.equipment, { slot = slot, id = rng:pick(items) })
					end
				end
				l.consumables = {}
				for slot = 1, 3 do
					if rng:chance(0.5) then
						table.insert(l.consumables, { slot = slot, id = rng:pick(kits) })
					end
				end
				for _, m in l.crew do
					m.level = rng:int(50, 200)
					m.skills = {}
					for _ = 1, rng:int(0, 3) do
						table.insert(m.skills, { id = rng:pick(skills), training = rng:next() })
					end
				end
				l.crewPerkEfficiency = rng:range(0.75, 1)
				local ra = StatsCalculator.compute(def, def.top, l, a)
				local rb = StatsCalculator.compute(b:getVehicle(id) :: any, def.top, l, b)
				expect(ra).toBeOk()
				expect((ra :: any).value).toEqual((rb :: any).value)
				local s = (ra :: any).value
				finiteDeep(s, id)
				expect(s.gun.reload.reloadS > 0).toBe(true)
				expect(s.hp >= 1).toBe(true)
				for _, m in s.crew do
					expect(m.level >= 1 and m.level <= 300).toBe(true)
				end
			end
		end
	end)

	it("resolveShell without modifiers is the authoring-default view of a shell", function()
		local shell = REGISTRY:getShell("iu_76mm_apcr") :: any
		local s = StatsCalculator.resolveShell(shell, false)
		expect(s.penetrationMm).toBe(86)
		expect(s.penetrationAt500Mm).toBeCloseTo(86 * 0.75, EPS)
		expect(s.velocityMps).toBe(510)
		local auto: any = { kind = "Autoreloader", size = 3, perShellReloadS = { 9, 7, 6 }, intraClipS = 2 }
		local dual: any =
			{ kind = "DualGun", reloadEachS = 12, salvoDelayS = 1.5, chargeTimeS = 1, volleyDispersionMul = 1.5 }
		expect(StatsCalculator.oneReload(auto)).toBe(9)
		expect(StatsCalculator.oneReload(dual)).toBe(12)
	end)
end)

describe("StatsCalculator runtime (30 Hz cache)", function()
	local function runtimeFor(id: string, loadout: any?): (any, any)
		local s = computeOk(id, nil, loadout)
		local rt = StatsCalculator.newRuntime(s)
		StatsCalculator.update(rt)
		return rt, s
	end

	it("starts at identity ratios and the battle-start values", function()
		local rt, s = runtimeFor("iu_bulmal")
		local out = rt.out
		expect(out.version).toBe(1)
		expect(out.reloadMul).toBe(1)
		expect(out.aimTimeMul).toBe(1)
		expect(out.dispersionMul).toBe(1)
		expect(out.enginePowerMul).toBe(1)
		expect(out.topSpeedMul).toBe(1)
		expect(out.topSpeedBonusKmh).toBe(0)
		expect(out.reverseSpeedMul).toBe(1)
		expect(out.turretTraverseMul).toBe(1)
		expect(out.viewRangeM).toBe(s.viewRangeM)
		expect(out.viewRangeMul).toBe(1)
		expect(out.camo).toEqual(s.camo)
		expect(out.bloom).toEqual(s.gun.bloom)
		expect(out.canFire).toBe(true)
		expect(out.canMove).toBe(true)
		expect(out.damageMul).toBe(1)
		expect(out.depressionBonusDeg).toBe(0)
		local _, changed = StatsCalculator.update(rt)
		expect(changed).toBe(false)
		expect(out.version).toBe(1)
	end)

	it("follows DamageModel effects; loader injury and heal (REG-RET-05, REG-CRW-04)", function()
		local rt, s = runtimeFor("iu_bulmal")
		local combat = DamageModel.new(s :: any)
		local eff = DamageModel.newEffects()
		combat.crew[4].injured = true -- one of two loaders: average L 75
		DamageModel.effects(combat, eff)
		StatsCalculator.setEffects(rt, eff, combat.modules)
		local out, changed = StatsCalculator.update(rt)
		expect(changed).toBe(true)
		expect(out.reloadMul).toBeCloseTo(reloadF(75) / reloadF(100), EPS)
		combat.crew[4].injured = false
		DamageModel.effects(combat, eff)
		StatsCalculator.setEffects(rt, eff, combat.modules)
		out = StatsCalculator.update(rt)
		expect(out.reloadMul).toBe(1) -- removed in the heal tick
	end)

	it(
		"damaged modules: Recon halves the optics penalty; ammo rack / engine / ring use DamageModel's numbers",
		function()
			local l = loadoutFor("iu_bulmal")
			l.crew[1].skills = { { id = "recon", training = 1 } }
			local rt, s = runtimeFor("iu_bulmal", l)
			local combat = DamageModel.new(s :: any)
			for _, kind in { "Optics", "AmmoRack", "Engine", "TurretRing" } do
				local m = (combat.modules :: any)[kind]
				m.hp = m.maxHp * 0.4
				m.state = "Damaged"
			end
			local eff = DamageModel.effects(combat)
			StatsCalculator.setEffects(rt, eff, combat.modules)
			local out = StatsCalculator.update(rt)
			expect(out.viewRangeMul).toBeCloseTo(0.90, EPS) -- 1 − (1 − 0.80) × 0.5
			expect(out.reloadMul).toBeCloseTo(1.25, EPS)
			expect(out.enginePowerMul).toBeCloseTo(0.5, EPS)
			expect(out.turretTraverseMul).toBeCloseTo(0.5, EPS)
			expect(out.enginePowerHp).toBeCloseTo(125, EPS)
			-- destroyed optics are not "damaged": DamageModel's ×0.5 stands
			combat.modules.Optics.state = "Destroyed"
			DamageModel.effects(combat, eff)
			StatsCalculator.setEffects(rt, eff, combat.modules)
			expect(StatsCalculator.update(rt).viewRangeMul).toBeCloseTo(0.5, EPS)
			-- a destroyed gun blocks firing
			combat.modules.Gun.state = "Destroyed"
			DamageModel.effects(combat, eff)
			StatsCalculator.setEffects(rt, eff, combat.modules)
			expect(StatsCalculator.update(rt).canFire).toBe(false)
		end
	)

	it("conditional modifiers switch with their condition; the cache recomputes only on a flip", function()
		local l = loadoutFor("iu_bulmal")
		l.crew[4].skills = { { id = "close_combat", training = 1 } }
		l.crew[5].skills = { { id = "close_combat", training = 1 } }
		l.crew[2].skills = { { id = "deadeye", training = 1 } }
		l.equipment = { { slot = 1, id = "mast" } }
		local rt = runtimeFor("iu_bulmal", l)
		local c = StatsCalculator.conditions(rt)
		local v0 = rt.out.version
		c.nearestEnemyM = 80
		local out, changed = StatsCalculator.update(rt)
		expect(changed).toBe(false)
		c.nearestEnemyM = 50 -- inclusive
		out, changed = StatsCalculator.update(rt)
		expect(changed).toBe(true)
		expect(out.reloadMul).toBeCloseTo(0.9, EPS)
		expect(out.version).toBe(v0 + 1)
		-- stationary for 3 s arms the mast and Deadeye (StationaryArmed)
		c.moving = false
		c.stationaryForS = 2.9
		out = StatsCalculator.update(rt)
		expect(out.viewRangeM).toBeCloseTo(320, EPS)
		c.stationaryForS = 3
		out = StatsCalculator.update(rt)
		expect(out.viewRangeM).toBeCloseTo(400, EPS)
		expect(out.dispersionMul).toBeCloseTo(0.96, EPS)
		c.moving = true
		c.stationaryForS = 0
		out = StatsCalculator.update(rt)
		expect(out.viewRangeM).toBeCloseTo(320, EPS)
		expect(out.dispersionMul).toBe(1)
	end)

	it("mechanic sources: siege aim/dispersion apply here, mobility and arc parts stay with VehicleSim", function()
		local rt, s = runtimeFor("iu_testsiege")
		StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Mechanic, (s.mechanics[1] :: any).modifiers)
		rt.conditions.mechanicActive = true
		local out = StatsCalculator.update(rt)
		expect(out.aimTimeMul).toBeCloseTo(0.4, EPS)
		expect(out.dispersionMul).toBeCloseTo(0.85, EPS)
		expect(out.hullTraverseMul).toBe(1) -- VehicleSim applies the siege hull traverse
		expect(out.depressionBonusDeg).toBe(0) -- and the +8° arc
		expect(out.mechanicActive).toBe(true)
		StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Mechanic, nil)
		rt.conditions.mechanicActive = false
		out = StatsCalculator.update(rt)
		expect(out.aimTimeMul).toBe(1)
		-- the same list again is free; a bad slot is ignored
		StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Mechanic, nil)
		StatsCalculator.setActive(rt, 99, { mod("aimTime", "mul", 2) })
		local _, changed = StatsCalculator.update(rt)
		expect(changed).toBe(false)
	end)

	it(
		"an active consumable applies for as long as its list is set; conditional MechanicActive mobility is skipped",
		function()
			local rt = runtimeFor("iu_bulmal")
			local adrenaline = (REGISTRY:getConsumable("adrenaline") :: any).effects
			StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Consumable1, adrenaline)
			expect(StatsCalculator.update(rt).reloadMul).toBeCloseTo(0.5, EPS)
			StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Event, {
				mod("topSpeed", "add", 5, { condition = "MechanicActive" }),
				mod("viewRange", "mul", 1.1, { condition = "MechanicActive" }),
				mod("topSpeed", "mul", 1.2),
				mod("enginePower", "add", 50),
				mod("reverseSpeed", "add", 3),
			})
			rt.conditions.mechanicActive = true
			local out = StatsCalculator.update(rt)
			expect(out.topSpeedBonusKmh).toBe(0) -- MechanicActive topSpeed: VehicleSim's
			expect(out.topSpeedMul).toBeCloseTo(1.2, EPS)
			expect(out.viewRangeM).toBeCloseTo(320 * 1.1, EPS)
			expect(out.enginePowerMul).toBeCloseTo(300 / 250, EPS)
			expect(out.reverseSpeedMul).toBeCloseTo(18 / 15, EPS)
			StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Consumable1, nil)
			expect(StatsCalculator.update(rt).reloadMul).toBe(1)
		end
	)

	it("writers fill VehicleSim / TurretSim modifiers and Dispersion aim factors", function()
		local rt, s = runtimeFor("iu_bulmal")
		local combat = DamageModel.new(s :: any)
		combat.stunRemainingS = 3
		local eff = DamageModel.effects(combat)
		StatsCalculator.setEffects(rt, eff, combat.modules)
		StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Event, { mod("gunDepression", "add", 2) })
		StatsCalculator.update(rt)
		local sim = VehicleSim.newState(CFrame.new())
		sim.modifiers.engine = "Damaged"
		StatsCalculator.writeSimModifiers(rt, sim.modifiers)
		expect(sim.modifiers.engine).toBe("Ok")
		expect(sim.modifiers.topSpeedMul).toBeCloseTo(0.85, EPS) -- stun
		expect(sim.modifiers.reverseSpeedMul).toBeCloseTo(0.85, EPS)
		expect(sim.modifiers.hullTraverseMul).toBeCloseTo(0.80, EPS)
		expect(sim.modifiers.immobilized).toBe(false)
		local turret = TurretSim.newState()
		StatsCalculator.writeTurretModifiers(rt, turret.modifiers)
		expect(turret.modifiers.traverseMul).toBeCloseTo(0.80, EPS)
		expect(turret.modifiers.depressionBonusDeg).toBe(2)
		local factors: any = { hullSpeedKmh = 0, hullTraverseDegS = 0, turretTraverseDegS = 0 }
		StatsCalculator.writeAimFactors(rt, factors)
		expect(factors.dispersionMul).toBeCloseTo(1.20, EPS)
		expect(factors.aimTimeMul).toBeCloseTo(1.25, EPS)
		expect(factors.stunned).toBe(false) -- already inside dispersionMul
		expect(rt.out.stunned).toBe(true)
	end)

	it("the per-tick path allocates nothing", function()
		local l = loadoutFor("iu_bulmal")
		l.crew[4].skills = { { id = "close_combat", training = 1 } }
		l.equipment = { { slot = 1, id = "mast" } }
		local rt, s = runtimeFor("iu_bulmal", l)
		local combat = DamageModel.new(s :: any)
		local eff = DamageModel.newEffects()
		local sim = VehicleSim.newState(CFrame.new())
		local turret = TurretSim.newState()
		local factors: any = { hullSpeedKmh = 0, hullTraverseDegS = 0, turretTraverseDegS = 0 }
		local siege = { mod("aimTime", "mul", 0.4) }
		local c = rt.conditions
		local function tick(i: number)
			c.nearestEnemyM = if i % 40 < 20 then 30 else 90
			c.moving = i % 90 < 45
			c.stationaryForS = if c.moving then 0 else (i % 90 - 45) / 30
			combat.crew[4].injured = i % 70 < 10
			DamageModel.effects(combat, eff)
			StatsCalculator.setEffects(rt, eff, combat.modules)
			StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Mechanic, if i % 50 < 25 then siege else nil)
			StatsCalculator.update(rt)
			StatsCalculator.writeSimModifiers(rt, sim.modifiers)
			StatsCalculator.writeTurretModifiers(rt, turret.modifiers)
			StatsCalculator.writeAimFactors(rt, factors)
		end
		for i = 1, 200 do
			tick(i)
		end
		-- Luau exposes only collectgarbage("count"): with no allocation the heap size stays exactly constant, so
		-- most short windows must show zero growth (a window that allocates almost never nets exactly 0).
		local zero, windows = 0, 20
		local i = 200
		for _ = 1, windows do
			local before = collectgarbage("count")
			for _ = 1, 150 do
				i += 1
				tick(i)
			end
			if collectgarbage("count") == before then
				zero += 1
			end
		end
		expect(zero >= windows - 2).toBe(true)
	end)
end)
