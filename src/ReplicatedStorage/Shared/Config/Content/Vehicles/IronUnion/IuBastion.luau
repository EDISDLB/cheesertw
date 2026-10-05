--!strict
--[[
	Content/Vehicles/IronUnion/IuBastion — IU-3 Bastion, Tier III heavy tank, Assault role (exemplar line 3/3).

	Purpose:          Shows the full WoT-style module tree (Tracks -> Turret -> Gun, Engine independent), a turret
	                  upgrade that changes the model (bustle, HP bonus, thinner cupola weak spot), spaced skirts,
	                  a five-seat crew with two loaders and a pike-nosed hull whose lower plate is the weak point.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry:validate().
	Error handling:   N/A.
	Performance notes: Loaded once.

	Balance targets: Tier III Medium baseline × heavy class (HP ×1.2, α ×1.25, pen ×1.03, reload ×1.27, aim ×1.2,
	speed ×0.72, hp/t ×0.77) × heavy_assault (armor ×1.15, speed ×0.85, hull traverse ×0.9) × Iron Union kit.
	Armor vs P(III) = 65 mm (03-R3 authoring rule, AP normalization 5° included): upper plate 55 mm at 45° ≈ 72 mm
	≈ 1.1 P; lower plate 40 mm at 25° ≈ 43 mm ≈ 0.66 P (the weak spot); turret face 72 mm at 15° ≈ 1.12 P with an
	80 mm mantlet; cupola 20 mm.
	Masses: stock 16,500 + 3,200 + 900 + 950 + 2,300 = 23,850 kg (1.4 % spare on 24,200); top 25,200 kg on 26,500;
	stock tracks + top turret + 76 mm = 24,950 kg > 24,200.
]]

local Content = require("../../../../Types/Content")

local vehicle: Content.VehicleDefinition = {
	id = "iu_bastion",
	name = "IU-3 Bastion",
	shortName = "Bastion",
	faction = "iron_union",
	tier = 3,
	class = "heavy",
	role = "heavy_assault",
	acquisition = "TechTree",
	description = "Iron Union's first true heavy: a pike-nosed fortress that leads the push and soaks up fire.",
	lore = "Built to break the river forts of the old border, the Bastion crawled forward under fire that stopped every lighter machine. Its crews still paint a tally of bounced shells on the turret.",
	strengths = { "Very strong upper glacis", "High alpha for its tier", "Five-seat crew with two loaders" },
	weaknesses = { "Thin lower plate", "Slow and sluggish", "Weak cupola on the heavy turret" },
	hull = {
		hp = 500,
		massKg = 16500,
		armor = {
			upperFront = 55,
			lowerFront = 40,
			side = 28,
			rear = 18,
			roof = 18,
			floor = 12,
			engineDeck = 15,
			skirts = 6,
		},
	},
	mobility = { forwardKmh = 28, reverseKmh = 12 },
	crew = {
		{ role = "Commander" },
		{ role = "Gunner" },
		{ role = "Driver" },
		{ role = "Loader" },
		{ role = "Loader" },
	},
	modules = {
		guns = { "iu_gun_57mm", "iu_gun_76mm" },
		turrets = { "iu_turret_bastion_m1", "iu_turret_bastion_m2" },
		engines = { "iu_engine_d230", "iu_engine_d290" },
		tracks = { "iu_tracks_bastion_m1", "iu_tracks_bastion_m2" },
	},
	stock = {
		gun = "iu_gun_57mm",
		turret = "iu_turret_bastion_m1",
		engine = "iu_engine_d230",
		tracks = "iu_tracks_bastion_m1",
	},
	top = {
		gun = "iu_gun_76mm",
		turret = "iu_turret_bastion_m2",
		engine = "iu_engine_d290",
		tracks = "iu_tracks_bastion_m2",
	},
	moduleTree = {
		{ module = "iu_tracks_bastion_m2" },
		{ module = "iu_turret_bastion_m2", requires = { "iu_tracks_bastion_m2" } },
		{ module = "iu_gun_76mm", requires = { "iu_turret_bastion_m2" } },
		{ module = "iu_engine_d290" },
	},
	unlocks = {},
	researchXp = 750,
	price = { credits = 100000 },
	arcSectors = {
		-- The raised rear deck limits depression over the back of the hull.
		{ fromDeg = 150, toDeg = -150, depressionDeg = 2 },
	},
	visual = {
		hull = {
			lengthM = 6.4,
			widthM = 3.1,
			heightM = 1.95,
			groundClearanceM = 0.45,
			style = "Pike",
			upperFrontAngleDeg = 45,
			lowerFrontAngleDeg = 25,
			upperFrontFraction = 0.6,
			rearAngleDeg = 12,
			sponsons = true,
			turretRing = { positionFraction = 0.42, diameterM = 1.8 },
			engineDeck = "Raised",
			fenders = true,
			skirts = "Plates",
		},
		running = {
			roadWheels = 6,
			wheelDiameterM = 0.7,
			returnRollers = 3,
			sprocket = "Front",
			trackWidthM = 0.5,
			suspension = "Torsion",
		},
		details = {
			exhausts = 2,
			antennas = 1,
			toolboxes = 2,
			spareTracks = true,
			towCables = true,
			stowage = true,
			machineGun = true,
			headlights = 2,
		},
		layout = {
			engine = "Rear",
			transmission = "Front",
			ammoRacks = { "Bustle", "HullMiddle" },
			fuel = "Rear",
		},
	},
	tree = { row = 3, branch = "Main line" },
}

return vehicle
