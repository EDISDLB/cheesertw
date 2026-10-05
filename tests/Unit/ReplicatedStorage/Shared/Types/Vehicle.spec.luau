-- Types/Vehicle smoke tests: executable statements of the contract's conventions (armor half-spaces, hull/turret/
-- gun frames, input flags) and complete example values (Loadout, VehicleStats) checked against the declarations
-- and the shipped content.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ContentRegistry = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")
local Types = require("@game/ReplicatedStorage/Shared/Types")
local TypeSource = require("./TypeSource")

local SOURCE = TypeSource.read("Vehicle")

type ArmorFace = Types.ArmorFace
type ArmorVolume = Types.ArmorVolume
type Loadout = Types.Loadout
type VehicleStats = Types.VehicleStats
type InputCommand = Types.InputCommand

-- Reference reading of the half-space convention: p is inside when normal:Dot(p) <= distance for every face.
local function contains(volume: ArmorVolume, p: Vector3): boolean
	for _, face in volume.faces do
		if face.normal:Dot(p) > face.distance + 1e-9 then
			return false
		end
	end
	return true
end

-- Axis-aligned box volume in group space (studs), the simplest Blueprint output.
local function box(id: number, center: Vector3, size: Vector3, thickness: number): ArmorVolume
	local half = size / 2
	local faces: { ArmorFace } = {}
	local axes = {
		{ Vector3.new(0, 0, -1), "HullUpperFront" },
		{ Vector3.new(0, 0, 1), "HullRear" },
		{ Vector3.new(1, 0, 0), "HullSide" },
		{ Vector3.new(-1, 0, 0), "HullSide" },
		{ Vector3.new(0, 1, 0), "HullRoof" },
		{ Vector3.new(0, -1, 0), "HullFloor" },
	}
	for _, axis in axes do
		local normal = axis[1] :: Vector3
		local extent = math.abs(normal.X) * half.X + math.abs(normal.Y) * half.Y + math.abs(normal.Z) * half.Z
		table.insert(faces, {
			normal = normal,
			distance = normal:Dot(center) + extent,
			thicknessMm = thickness,
			zone = axis[2] :: any,
			spaced = false,
		})
	end
	return {
		id = id,
		group = "Hull",
		kind = "Armor",
		faces = faces,
		center = center,
		radius = half.Magnitude,
		label = "Hull box",
	}
end

describe("Types/Vehicle: armor model contract", function()
	it("defines volumes as intersections of outward half-spaces", function()
		-- A 7 m x 2 m x 3 m hull (21 x 6 x 9 studs) standing on the ground: origin at footprint centre, +Y up.
		local hull = box(1, Vector3.new(0, 3, 0), Vector3.new(9, 6, 21), 50)
		expect(contains(hull, Vector3.new(0, 3, 0))).toBe(true)
		expect(contains(hull, Vector3.new(0, 0.5, -10))).toBe(true)
		expect(contains(hull, Vector3.new(0, -0.1, 0))).toBe(false) -- below ground contact
		expect(contains(hull, Vector3.new(0, 3, -10.6))).toBe(false) -- ahead of the front plate
		for _, face in hull.faces do
			expect(face.normal.Magnitude).toBeCloseTo(1, 1e-9)
		end
		-- every face point is inside the bounding sphere
		expect((Vector3.new(4.5, 6, -10.5) - hull.center).Magnitude).toBeLessThanOrEqual(hull.radius + 1e-9)
	end)

	it("uses -Z forward, +Y up; turret yaw is clockwise and gun elevation is up", function()
		expect(CFrame.new().LookVector).toBeCloseTo(Vector3.new(0, 0, -1), 1e-9)
		local yaw = math.rad(90) -- turret turned 90° to the right
		local turret = CFrame.Angles(0, -yaw, 0)
		expect(turret.LookVector).toBeCloseTo(Vector3.new(1, 0, 0), 1e-6)
		local elevated = CFrame.Angles(math.rad(10), 0, 0)
		expect(elevated.LookVector.Y).toBeGreaterThan(0)
		-- world = hull * turretRing * yaw * trunnion * elevation * point
		local hullCFrame = CFrame.new(100, 0, 50)
		local turretRing = CFrame.new(0, 6, -1.5)
		local trunnion = CFrame.new(0, 1, -2)
		local muzzle = hullCFrame * turretRing * turret * trunnion * CFrame.new(0, 0, -9)
		expect(muzzle.Position).toBeCloseTo(Vector3.new(100 + 2 + 9, 7, 50 - 1.5), 1e-6)
	end)

	it("lists every armor-model field the producer must fill", function()
		expect(TypeSource.fieldNames(SOURCE, "ArmorFace")).toEqual({
			"distance",
			"normal",
			"spaced",
			"thicknessMm",
			"zone",
		})
		expect(TypeSource.fieldNames(SOURCE, "ArmorModel")).toEqual({
			"boundsCenter",
			"boundsRadius",
			"pivots",
			"volumes",
		})
		expect(TypeSource.fieldNames(SOURCE, "VehiclePivots")).toEqual({
			"camoPoints",
			"exhausts",
			"gunTrunnion",
			"hullSize",
			"muzzle",
			"trackContacts",
			"turretRing",
			"viewPoint",
		})
		expect(TypeSource.unionMembers(SOURCE, "ArmorGroup")).toEqual({ "Gun", "Hull", "Turret" })
		expect(TypeSource.unionMembers(SOURCE, "ArmorVolumeKind")).toEqual({ "Armor", "Crew", "Module", "Spaced" })
	end)
end)

describe("Types/Vehicle: input, loadout, stats", function()
	it("InputFlag names exactly the boolean fields of InputCommand", function()
		local booleans = {}
		for line in string.gmatch(SOURCE, "\n\t(%a+): boolean,") do
			booleans[line] = true
		end
		local flags = TypeSource.unionMembers(SOURCE, "InputFlag")
		for _, flag in flags do
			expect(booleans[flag]).toBe(true)
		end
		local example: InputCommand = {
			seq = 1,
			throttle = 1,
			steer = -0.5,
			aimPoint = Vector3.new(0, 0, -300),
			fire = false,
			holdTurret = false,
			brake = false,
			mechanic = false,
		}
		local names = TypeSource.fieldNames(SOURCE, "InputCommand")
		expect(TypeSource.sortedKeys(example :: any)).toEqual(names)
	end)

	it("a Loadout for the IU-1 Forge passes the content mount rules", function()
		local content = ContentRegistry.get()
		local forge = content:getVehicle("iu_forge") :: any
		local loadout: Loadout = {
			vehicleId = "iu_forge",
			configuration = forge.top,
			equipment = {},
			ammo = {
				{ shell = "iu_45mm_ap", count = 70 },
				{ shell = "iu_45mm_apcr", count = 20 },
				{ shell = "iu_45mm_he", count = 20 },
			},
			consumables = {},
			crew = {
				{ slot = 1, role = "Commander", also = { "Loader" }, level = 100, skills = {} },
				{ slot = 2, role = "Gunner", level = 100, skills = { { id = "snap_shot", training = 0.4 } } },
				{ slot = 3, role = "Driver", level = 100, skills = {} },
			},
			customization = {},
		}
		expect(content:checkConfiguration(loadout.vehicleId, loadout.configuration)).toBeOk()
		local gun = content:getGun(loadout.configuration.gun) :: any
		local total = 0
		for i, load in loadout.ammo do
			expect(load.shell).toBe(gun.shells[i])
			total += load.count
		end
		expect(total).toBeLessThanOrEqual(gun.ammoCapacity)
		expect(#loadout.crew).toBe(#forge.crew)
		for i, member in loadout.crew do
			expect(member.role).toBe(forge.crew[i].role)
		end
		expect(TypeSource.shapeProblems(loadout :: any, SOURCE, "Loadout")).toEqual({})
		expect(TypeSource.shapeProblems(loadout.crew[1] :: any, SOURCE, "CrewMemberSnapshot")).toEqual({})
	end)

	it("a complete VehicleStats example covers every required field", function()
		local stats: VehicleStats = {
			vehicleId = "iu_forge",
			faction = "iron_union",
			tier = 1,
			class = "medium",
			role = "medium_versatile",
			configuration = (ContentRegistry.get():getVehicle("iu_forge") :: any).top,
			premium = false,
			hp = 280,
			massKg = 10070,
			dimensionsM = Vector3.new(2.3, 1.55, 4.6),
			modules = {
				Engine = { maxHp = 40, repairS = 14 },
				AmmoRack = { maxHp = 36, repairS = 10 },
				FuelTank = { maxHp = 40, repairS = 10 },
				Gun = { maxHp = 40, repairS = 12 },
				TurretRing = { maxHp = 40, repairS = 12 },
				Optics = { maxHp = 32, repairS = 8 },
				TrackLeft = { maxHp = 56, repairS = 10 },
				TrackRight = { maxHp = 56, repairS = 10 },
			},
			fireChance = 0.12,
			fireDurationS = 8,
			crewInjuryChanceMul = 1,
			spallFactor = 1,
			stunDurationMul = 1,
			ramDamageDealtMul = 1,
			ramDamageTakenMul = 1,
			fallDamageMul = 1,
			repairTimeMul = 1,
			enginePowerHp = 120,
			specificPowerHpT = 120 / 10.07,
			topSpeedKmh = 40,
			reverseSpeedKmh = 14,
			hullTraverseDegS = 38,
			terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
			loadLimitKg = 10100,
			pivot = true,
			turretMount = "Turret",
			turretTraverseDegS = 40,
			gun = {
				id = "iu_gun_45mm",
				caliberMm = 45,
				reload = { kind = "Single", reloadS = 2.3 },
				dispersionM100 = 0.51,
				aimTimeS = 2.0,
				bloom = {
					movementPerKmh = 0.07,
					hullTraversePerDegS = 0.075,
					turretTraversePerDegS = 0.03,
					afterShot = 3,
					damagedMul = 1.5,
				},
				depressionDeg = 5,
				elevationDeg = 22,
				arcSectors = {},
				shells = {},
				ammoCapacity = 110,
				camoAfterShotMul = 0.34,
				shellSwapS = 2.3,
				indirect = false,
			},
			viewRangeM = 300,
			signalRangeM = 600,
			camo = { stationary = 0.12, moving = 0.07, afterShotMul = 0.34, net = 0, paint = 0 },
			crew = {
				{ slot = 1, role = "Commander", also = { "Loader" }, level = 100 },
				{ slot = 2, role = "Gunner", also = {}, level = 100 },
				{ slot = 3, role = "Driver", also = {}, level = 100 },
			},
			crewLevels = { Commander = 100, Gunner = 100, Driver = 100, Loader = 100 },
			consumableSlots = 3,
			consumableCooldownMul = 1,
			mechanics = {},
			conditionalModifiers = {},
		}
		expect(TypeSource.shapeProblems(stats :: any, SOURCE, "VehicleStats")).toEqual({})
		expect(TypeSource.shapeProblems(stats.gun :: any, SOURCE, "GunStats")).toEqual({})
		expect(TypeSource.shapeProblems(stats.gun.bloom :: any, SOURCE, "BloomStats")).toEqual({})
		expect(TypeSource.shapeProblems(stats.camo :: any, SOURCE, "CamoStats")).toEqual({})
		expect(TypeSource.shapeProblems(stats.crew[1] :: any, SOURCE, "CrewSlotStats")).toEqual({})
		-- module stats are keyed by every internal module kind
		expect(TypeSource.sortedKeys(stats.modules :: any)).toEqual(
			TypeSource.unionMembers(TypeSource.read("Content"), "InternalModuleKind")
		)
	end)

	it("ModuleState matches the battle event module states", function()
		expect(TypeSource.unionMembers(SOURCE, "ModuleState")).toEqual({ "Damaged", "Destroyed", "Ok" })
	end)
end)
