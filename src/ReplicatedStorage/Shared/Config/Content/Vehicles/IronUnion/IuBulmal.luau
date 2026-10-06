--!strict
--[[
	Content/Vehicles/IronUnion/IuBulmal — Bulmal, Tier III medium tank, Versatile (roster.md §2.1; exemplar 3/3).

	Purpose:          Shows the full WoT-style module tree (Tracks -> Turret -> Gun, Engine independent), a turret
	                  upgrade that changes the model and the armor (faceted dome, HP bonus, weak cupola), a hull-
	                  relative arc sector (raised rear deck) and a five-seat crew with two loaders.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry:validate().
	Error handling:   N/A.
	Performance notes: Loaded once.

	Roster identity: "first dome turret that bounces Tier III standard rounds; −5°; best medium alpha at III".
	Balance targets: Tier III Medium baseline (440 HP, α 60, pen 65, 45 km/h, 14 hp/t) × Iron Union kit.
	Armor vs P(III) = 65 mm (03-R3 rule): dome face 62 mm at 25° ≈ 1.05 P with a 70 mm mantlet and a 16 mm cupola;
	hull 30 mm at 50° ≈ 0.65 P; lower plate 25 mm at 30° ≈ 0.45 P (the weak spot behind the front transmission).
	Masses: stock 11,800 + 2,100 + 780 + 800 + 1,600 = 17,080 kg (1.8 % spare on 17,400); top 18,230 kg on 18,800;
	stock tracks + dome + 76 mm = 18,050 kg > 17,400. The next vehicle (Osthald, Tier IV heavy) will hang off the
	76 mm once it is authored; until then the exemplar line ends here.
]]

local Content = require("../../../../Types/Content")

local vehicle: Content.VehicleDefinition = {
	id = "iu_bulmal",
	name = "Bulmal",
	shortName = "Bulmal",
	faction = "iron_union",
	tier = 3,
	class = "medium",
	role = "medium_versatile",
	acquisition = "TechTree",
	description = "The first Iron Union turret that bounces shells. A preview of the heavy line, with the best medium alpha at its tier.",
	lore = "Bulmal crews were the first to trust a cast dome. The foundry poured it in one piece, and the Marshals of the Trials logged it turning away shot after shot on the open flats.",
	strengths = { "Dome turret bounces same-tier standard rounds", "Best medium alpha at Tier III" },
	weaknesses = { "Weak lower plate", "Only 5° of gun depression", "Thin cupola" },
	hull = {
		hp = 440,
		massKg = 11800,
		armor = { upperFront = 30, lowerFront = 25, side = 25, rear = 20, roof = 12, floor = 10, engineDeck = 12 },
	},
	mobility = { forwardKmh = 43, reverseKmh = 15 },
	crew = {
		{ role = "Commander" },
		{ role = "Gunner" },
		{ role = "Driver" },
		{ role = "Loader" },
		{ role = "Loader" },
	},
	modules = {
		guns = { "iu_gun_63mm", "iu_gun_76mm" },
		turrets = { "iu_turret_bulmal_m1", "iu_turret_bulmal_m2" },
		engines = { "iu_engine_d210", "iu_engine_d250" },
		tracks = { "iu_tracks_bulmal_m1", "iu_tracks_bulmal_m2" },
	},
	stock = {
		gun = "iu_gun_63mm",
		turret = "iu_turret_bulmal_m1",
		engine = "iu_engine_d210",
		tracks = "iu_tracks_bulmal_m1",
	},
	top = {
		gun = "iu_gun_76mm",
		turret = "iu_turret_bulmal_m2",
		engine = "iu_engine_d250",
		tracks = "iu_tracks_bulmal_m2",
	},
	moduleTree = {
		{ module = "iu_tracks_bulmal_m2" },
		{ module = "iu_turret_bulmal_m2", requires = { "iu_tracks_bulmal_m2" } },
		{ module = "iu_gun_76mm", requires = { "iu_turret_bulmal_m2" } },
		{ module = "iu_engine_d250" },
	},
	unlocks = {},
	researchXp = 750,
	price = { credits = 100000 },
	arcSectors = {
		-- The raised engine deck limits depression over the back of the hull.
		{ fromDeg = 150, toDeg = -150, depressionDeg = 2 },
	},
	visual = {
		hull = {
			lengthM = 5.8,
			widthM = 2.8,
			heightM = 1.7,
			groundClearanceM = 0.42,
			style = "Sloped",
			upperFrontAngleDeg = 50,
			lowerFrontAngleDeg = 30,
			upperFrontFraction = 0.55,
			rearAngleDeg = 12,
			turretRing = { positionFraction = 0.45, diameterM = 1.6 },
			engineDeck = "Raised",
			fenders = true,
			skirts = "None",
		},
		running = {
			roadWheels = 5,
			wheelDiameterM = 0.75,
			returnRollers = 0,
			sprocket = "Front",
			trackWidthM = 0.45,
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
			ammoRacks = { "Sponsons", "Floor" },
			fuel = "Rear",
		},
		hooks = { "sagging_track", "riveted_plates" },
	},
	tree = { row = 2, branch = "iu_foundry" },
}

return vehicle
