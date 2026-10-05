--!strict
--[[
	Content/Vehicles/IronUnion/IuAnvil — IU-2 Anvil, Tier II medium tank, Assault role (exemplar line 2/3).

	Purpose:          Shows module sharing (the Forge's 45 mm arrives researched as the stock gun) and the
	                  weight-gated upgrade order (the 57 mm only fits after the reinforced suspension).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry:validate().
	Error handling:   N/A.
	Performance notes: Loaded once.

	Balance targets: Tier II Medium baseline (360 HP, α 50, pen 55, 42 km/h, 13 hp/t) × medium_assault trims
	(armor ×1.15, HP ×1.05, speed ×0.92) × Iron Union kit.
	Masses: stock 8,300 + 1,700 + 520 + 750 + 1,100 = 12,370 kg (1.0 % spare on 12,500);
	top 12,800 kg on 13,400; stock tracks + 57 mm = 12,750 kg > 12,500, so Tracks -> Gun.
]]

local Content = require("../../../../Types/Content")

local vehicle: Content.VehicleDefinition = {
	id = "iu_anvil",
	name = "IU-2 Anvil",
	shortName = "Anvil",
	faction = "iron_union",
	tier = 2,
	class = "medium",
	role = "medium_assault",
	acquisition = "TechTree",
	description = "A thick-skinned medium built to lead the push. Angle it well and it shrugs off its peers.",
	lore = "The Anvil took its name from the foundry floors that built it. Crews swore it rang like one when shells bounced off its glacis.",
	strengths = { "Thick, sloped front for its tier", "Strong 57 mm gun", "Good hit points" },
	weaknesses = { "Slower than other mediums", "Limited gun depression" },
	hull = {
		hp = 380,
		massKg = 8300,
		armor = { upperFront = 30, lowerFront = 24, side = 23, rear = 17, roof = 12, floor = 10, engineDeck = 10 },
	},
	mobility = { forwardKmh = 39, reverseKmh = 14 },
	crew = {
		{ role = "Commander" },
		{ role = "Gunner" },
		{ role = "Driver" },
		{ role = "Loader" },
	},
	modules = {
		guns = { "iu_gun_45mm", "iu_gun_57mm" },
		turrets = { "iu_turret_anvil" },
		engines = { "iu_engine_d165" },
		tracks = { "iu_tracks_anvil_m1", "iu_tracks_anvil_m2" },
	},
	stock = {
		gun = "iu_gun_45mm",
		turret = "iu_turret_anvil",
		engine = "iu_engine_d165",
		tracks = "iu_tracks_anvil_m1",
	},
	top = {
		gun = "iu_gun_57mm",
		turret = "iu_turret_anvil",
		engine = "iu_engine_d165",
		tracks = "iu_tracks_anvil_m2",
	},
	moduleTree = {
		{ module = "iu_tracks_anvil_m2" },
		{ module = "iu_gun_57mm", requires = { "iu_tracks_anvil_m2" } },
	},
	unlocks = {
		{ vehicle = "iu_bastion", requires = "iu_gun_57mm" },
	},
	researchXp = 350,
	price = { credits = 35000 },
	visual = {
		hull = {
			lengthM = 5.4,
			widthM = 2.6,
			heightM = 1.7,
			groundClearanceM = 0.4,
			style = "Sloped",
			upperFrontAngleDeg = 50,
			lowerFrontAngleDeg = 45,
			upperFrontFraction = 0.55,
			rearAngleDeg = 15,
			sideSlopeDeg = 10,
			turretRing = { positionFraction = 0.36, diameterM = 1.5 },
			engineDeck = "Flat",
			fenders = true,
			skirts = "None",
		},
		running = {
			roadWheels = 5,
			wheelDiameterM = 0.6,
			returnRollers = 3,
			sprocket = "Rear",
			trackWidthM = 0.4,
			suspension = "Torsion",
		},
		details = { exhausts = 2, antennas = 1, toolboxes = 2, spareTracks = true, jerrycans = 2, headlights = 2 },
		layout = {
			engine = "Rear",
			transmission = "Front",
			ammoRacks = { "Sponsons", "Floor" },
			fuel = "Sides",
		},
	},
	tree = { row = 3, branch = "Main line" },
}

return vehicle
