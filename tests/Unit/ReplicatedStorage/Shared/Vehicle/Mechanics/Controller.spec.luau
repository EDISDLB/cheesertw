-- Mechanics/Controller: owns the VehicleSim-side mechanics and drives VehicleSim's external mode
-- (docs/design/movement.md §4.10). Integration with the real VehicleSim: siege / boost / turbo / hydro phases
-- written by the controller produce the same mobility effects as the built-in machine; StatsCalculator's runtime
-- takes the non-mobility siege modifiers.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Controller = require("@game/ReplicatedStorage/Shared/Vehicle/Mechanics/Controller")
local VehicleSim = require("@game/ReplicatedStorage/Shared/Vehicle/VehicleSim")
local StatsCalculator = require("@game/ReplicatedStorage/Shared/Vehicle/StatsCalculator")
local Units = require("@game/ReplicatedStorage/Shared/Core/Units")

local DT = 1 / 30

local SIEGE: any = {
	kind = "SiegeMode",
	engageS = 2,
	disengageS = 1.25,
	maxSpeedKmh = 10,
	modifiers = {
		{ stat = "aimTime", op = "mul", value = 0.4 },
		{ stat = "dispersion", op = "mul", value = 0.85 },
		{ stat = "gunDepression", op = "add", value = 8 },
	},
}
local HYDRO: any = { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 }
local TURBO: any = { kind = "Turbo", powerMul = 1.25, durationS = 6, cooldownS = 40 }
local ROCKET: any = { kind = "RocketBoost", charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 }
local RESERVE: any = { kind = "ReserveTracks", charges = 1, repairS = 6, cooldownS = 30 }
local WHEELED: any = {
	kind = "Wheeled",
	wheelPairs = 4,
	speedModeTopSpeedMul = 1.3,
	speedModeSteeringMul = 0.6,
	speedModeReverseMul = 0.7,
	toggleS = 1,
	lostPairSpeedMul = 0.75,
	movingDispersionMul = 1.15,
	turnRadiusM = 8,
}

-- A Tier V-ish medium (VehicleSim spec fixture shape).
local function stats(mechanics: { any }): any
	return {
		vehicleId = "test_medium",
		class = "medium",
		massKg = 30000,
		enginePowerHp = 900,
		specificPowerHpT = 30,
		topSpeedKmh = 50,
		reverseSpeedKmh = 20,
		hullTraverseDegS = 36,
		terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
		dimensionsM = Vector3.new(3.2, 2.4, 6.6),
		pivot = true,
		turretMount = "Turret",
		turretTraverseDegS = 40,
		mechanics = mechanics,
		conditionalModifiers = {},
		gun = {
			aimTimeS = 2,
			dispersionM100 = 0.4,
			reload = { kind = "Single", reloadS = 5 },
			bloom = {
				movementPerKmh = 0.07,
				hullTraversePerDegS = 0.075,
				turretTraversePerDegS = 0.03,
				afterShot = 3,
				damagedMul = 1.5,
			},
			depressionDeg = 5,
			elevationDeg = 20,
			shells = {},
		},
		modules = {},
		camo = { stationary = 0.12, moving = 0.07, afterShotMul = 0.3, net = 0, paint = 0 },
		viewRangeM = 350,
		fireChance = 0.12,
	}
end

local function flatWorld(): any
	return {
		groundAt = function(_, x, z, fromY)
			if fromY < 0 then
				return nil
			end
			return {
				position = Vector3.new(x, 0, z),
				normal = Vector3.yAxis,
				distance = fromY,
				material = "Concrete",
				objectId = nil,
				destructible = false,
			}
		end,
		sweepBox = function()
			return nil
		end,
		waterDepthAt = function()
			return 0
		end,
		raycast = function()
			return nil
		end,
		sightLine = function()
			return { blocked = false, foliage = 0, smoke = false }
		end,
		destroyObject = function() end,
	}
end

local function input(throttle: number?, mechanic: boolean?): any
	return {
		seq = 0,
		throttle = throttle or 0,
		steer = 0,
		aimPoint = Vector3.zero,
		fire = false,
		holdTurret = false,
		brake = false,
		mechanic = mechanic == true,
	}
end

-- Runs `seconds` of battle ticks with the controller in charge (tick order of the module header).
local function run(
	ctrl: any,
	sim: any,
	st: any,
	world: any,
	t0: number,
	seconds: number,
	throttle: number?,
	key: boolean?
): number
	local t = t0
	for _ = 1, math.floor(seconds / DT + 0.5) do
		t += DT
		Controller.input(ctrl, key == true, t)
		Controller.readSim(ctrl, sim)
		Controller.update(ctrl, t)
		Controller.writeSim(ctrl, sim)
		VehicleSim.step(sim, input(throttle, key), st, world, DT)
	end
	return t
end

local function kmh(sim: any): number
	return Units.studsPerSecToKmh(sim.speed)
end

describe("Mechanics/Controller", function()
	it("owns the keyed and hydro machines, never Wheeled vehicles or GunState mechanics", function()
		local rows = {
			{ { SIEGE }, true, "SiegeMode" },
			{ { HYDRO }, true, "" },
			{ { TURBO, RESERVE }, true, "Turbo" },
			{ { WHEELED }, false, "" },
			{ { { kind = "ChargedShot", chargeTimeS = 1.5, effect = "Damage", damageMul = 1.1 } }, false, "" },
			{ { RESERVE }, false, "" },
			{ {}, false, "" },
		}
		for i, row in rows do
			local ctrl = Controller.new(row[1], 0)
			if ctrl.owns ~= row[2] or ctrl.keyedKind ~= row[3] then
				error(`row {i}: owns {tostring(ctrl.owns)} keyed {ctrl.keyedKind}`)
			end
			local sim = VehicleSim.newState(CFrame.new())
			Controller.attach(ctrl, sim)
			expect(sim.mechanic.external).toBe(row[2])
		end
		expect(Controller.new(nil, 0).owns).toBe(false)
		expect(Controller.new({ TURBO, RESERVE }, 0).reserve).never.toBeNil()
	end)

	it("SiegeMode through VehicleSim's external mode: exact engage, speed cap, arc bonus, disengage", function()
		local st = stats({ SIEGE })
		local world = flatWorld()
		local sim = VehicleSim.newState(CFrame.new())
		local ctrl = Controller.new(st.mechanics, 0)
		Controller.attach(ctrl, sim)
		local t = run(ctrl, sim, st, world, 0, DT, 0, true) -- press on the first tick
		expect(ctrl.siege.phase).toBe("Engaging")
		expect(ctrl.siege.phaseStart).toBeCloseTo(DT, 1e-12)
		t = run(ctrl, sim, st, world, t, 1.9, 0, true) -- held: no re-toggle
		expect(sim.mechanic.phase).toBe("Engaging")
		expect(sim.mechanic.timer).toBeCloseTo(0.1, 1e-6)
		t = run(ctrl, sim, st, world, t, 0.2, 0, false)
		expect(sim.mechanic.phase).toBe("On")
		expect(sim.mechanicActive).toBe(true)
		expect(sim.gunDepressionBonusDeg).toBe(8)
		expect(Controller.isActive(ctrl)).toBe(true)
		t = run(ctrl, sim, st, world, t, 8, 1)
		expect(kmh(sim)).toBeCloseTo(10, 1e-6)
		t = run(ctrl, sim, st, world, t, DT, 1, true)
		expect(sim.mechanic.phase).toBe("Disengaging")
		expect(sim.mechanicActive).toBe(false)
		t = run(ctrl, sim, st, world, t, 1.0, 1, false)
		expect(kmh(sim)).toBeLessThanOrEqual(10 + 1e-6) -- the cap holds until fully off
		run(ctrl, sim, st, world, t, 0.3, 1)
		expect(sim.mechanic.phase).toBe("Off")
	end)

	it("matches the built-in machine's phase timeline tick for tick", function()
		local st = stats({ SIEGE })
		local world = flatWorld()
		local builtin = VehicleSim.newState(CFrame.new())
		local owned = VehicleSim.newState(CFrame.new())
		local ctrl = Controller.new(st.mechanics, 0)
		Controller.attach(ctrl, owned)
		local t = 0
		for i = 1, 150 do
			local key = i == 1 or i == 100
			t += DT
			VehicleSim.step(builtin, input(0, key), st, world, DT)
			Controller.input(ctrl, key, t)
			Controller.readSim(ctrl, owned)
			Controller.update(ctrl, t)
			Controller.writeSim(ctrl, owned)
			VehicleSim.step(owned, input(0, key), st, world, DT)
			if builtin.mechanic.phase ~= owned.mechanic.phase then
				error(`tick {i}: built-in {builtin.mechanic.phase}, controller {owned.mechanic.phase}`)
			end
			expect(builtin.gunDepressionBonusDeg).toBe(owned.gunDepressionBonusDeg)
		end
	end)

	it("RocketBoost: charges and the +20 km/h burn reach VehicleSim", function()
		local st = stats({ ROCKET })
		local world = flatWorld()
		local sim = VehicleSim.newState(CFrame.new())
		local ctrl = Controller.new(st.mechanics, 0)
		Controller.attach(ctrl, sim)
		expect(sim.mechanic.charges).toBe(2)
		local t = run(ctrl, sim, st, world, 0, 20, 1) -- top speed 50
		expect(kmh(sim)).toBeCloseTo(50, 1e-6)
		t = run(ctrl, sim, st, world, t, DT, 1, true)
		expect(sim.mechanic.phase).toBe("On")
		expect(sim.mechanic.charges).toBe(1)
		t = run(ctrl, sim, st, world, t, 2.4, 1, false)
		expect(kmh(sim) > 50).toBe(true)
		t = run(ctrl, sim, st, world, t, 0.2, 1)
		expect(sim.mechanic.phase).toBe("Off")
		local snap = Controller.snapshot(ctrl, t) :: any
		expect(snap.charges).toBe(1)
		expect(snap.maxCharges).toBe(2)
		expect(Controller.nextChange(ctrl)).toBeCloseTo(20 + DT + 2.5 + 30, 1e-6)
	end)

	it("Turbo: a destroyed engine (immobilised hull) cancels the boost through readSim", function()
		local st = stats({ TURBO })
		local world = flatWorld()
		local sim = VehicleSim.newState(CFrame.new())
		local ctrl = Controller.new(st.mechanics, 0)
		Controller.attach(ctrl, sim)
		local t = run(ctrl, sim, st, world, 0, DT, 0, true)
		expect(sim.mechanic.phase).toBe("On")
		local mods = Controller.modifiers(ctrl) :: any
		expect(mods[1].stat).toBe("enginePower")
		sim.modifiers.engine = "Destroyed"
		t = run(ctrl, sim, st, world, t, 3 * DT, 0, false)
		expect(sim.immobilized).toBe(true)
		expect(ctrl.turbo.phase).toBe("Cooldown")
		expect(sim.mechanic.phase).toBe("Cooldown")
		local ok, reason = Controller.press(ctrl, t)
		expect(ok).toBe(false)
		expect(reason).toBe("IMMOBILE") -- still immobile: that reason wins over the cooldown
	end)

	it("Hydropneumatic: hydroActive follows the exact settle of the sim's still time", function()
		local st = stats({ HYDRO })
		local world = flatWorld()
		local sim = VehicleSim.newState(CFrame.new())
		local ctrl = Controller.new(st.mechanics, 0)
		Controller.attach(ctrl, sim)
		local t = run(ctrl, sim, st, world, 0, 2, 1) -- moving
		expect(sim.mechanic.hydroActive).toBe(false)
		expect(sim.gunDepressionBonusDeg).toBe(0)
		t = run(ctrl, sim, st, world, t, 6, 0) -- coast to a stop, then settle
		expect(sim.mechanic.hydroActive).toBe(true)
		expect(sim.gunDepressionBonusDeg).toBe(4)
		expect(sim.gunElevationBonusDeg).toBe(3)
		expect((Controller.snapshot(ctrl, t) :: any).kind).toBe("Hydropneumatic")
		expect(select(2, Controller.press(ctrl, t))).toBe("NO_MECHANIC")
	end)

	it("siege modifiers feed StatsCalculator's runtime (aim/dispersion here, mobility in VehicleSim)", function()
		local st = stats({ SIEGE })
		local ctrl = Controller.new(st.mechanics, 0)
		local rt = StatsCalculator.newRuntime(st)
		Controller.press(ctrl, 0)
		Controller.update(ctrl, 2)
		StatsCalculator.setActive(rt, StatsCalculator.SOURCE.Mechanic, Controller.modifiers(ctrl))
		rt.conditions.mechanicActive = Controller.isActive(ctrl)
		local out = StatsCalculator.update(rt)
		expect(out.aimTimeMul).toBeCloseTo(0.4, 1e-12)
		expect(out.dispersionMul).toBeCloseTo(0.85, 1e-12)
		expect(out.depressionBonusDeg).toBe(0)
	end)

	it("ReserveTracks hooks and the update report", function()
		local ctrl = Controller.new({ RESERVE }, 0)
		expect(Controller.onTrackDestroyed(ctrl, "TrackLeft", 1)).toBe(true)
		local changed, left, right = Controller.update(ctrl, 6.9)
		expect(left).toBe(false)
		changed, left, right = Controller.update(ctrl, 7)
		expect(left).toBe(true)
		expect(right).toBe(false)
		expect(changed).toBe(false)
		expect(Controller.onTrackDestroyed(ctrl, "TrackRight", 8)).toBe(false) -- cooling down
		Controller.onTrackRepaired(ctrl, "TrackRight", 9)
		local none = Controller.new({ SIEGE }, 0)
		expect(Controller.onTrackDestroyed(none, "TrackLeft", 0)).toBe(false)
		Controller.onTrackRepaired(none, "TrackLeft", 0)
		expect(Controller.snapshot(Controller.new({}, 0), 0)).toBeNil()
		local ctx = Controller.context(none)
		expect(ctx.alive).toBe(true)
	end)
end)
