--!strict
--[[
	Content/Vehicles/IronUnion/IuOstmal — Ostmal, Tier II medium tank, Assault (roster.md §2.1; exemplar line 2/3).

	Purpose:          Shows module sharing (the Kolmal's 45 mm arrives researched as the stock gun) and the
	                  weight-gated upgrade order (the 63 mm only fits after the reinforced suspension).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry:validate().
	Error handling:   N/A.
	Performance notes: Loaded once.

	Roster identity: "short high-alpha gun with a slow reload; thickest Tier II front, soft sides". Balance targets:
	Tier II Medium baseline (360 HP, α 50, pen 55, 42 km/h, 13 hp/t) × medium_assault trims (armor ×1.15, HP ×1.05,
	speed ×0.92) × Iron Union kit. Stepped riveted front: 30 mm at 45° ≈ 0.75 × P(II) effective; 15 mm sides.
	Masses: stock 8,200 + 1,600 + 520 + 750 + 1,100 = 12,170 kg (1.1 % spare on 12,300); top 12,480 kg on 13,200;
	stock tracks + 63 mm = 12,430 kg > 12,300, so Tracks -> Gun.
]]

local Content = require("../../../../Types/Content")

local vehicle: Content.VehicleDefinition = {
	id = "iu_ostmal",
	name = "Ostmal",
	shortName = "Ostmal",
	faction = "iron_union",
	tier = 2,
	class = "medium",
	role = "medium_assault",
	acquisition = "TechTree",
	description = "A stubby, hard-hitting medium with the thickest front of its tier. Lead the push and make every shot count.",
	lore = "Foundry crews wanted a tank that could knock down a gate in one blow. The Ostmal's short gun and stepped glacis were cast in the same shop that made the furnace doors of the Cinderbelt.",
	strengths = { "Thickest front at Tier II", "High alpha damage from the 63 mm" },
	weaknesses = { "Thin sides", "Slow reload", "Limited gun depression" },
	hull = {
		hp = 380,
		massKg = 8200,
		armor = { upperFront = 30, lowerFront = 25, side = 15, rear = 15, roof = 10, floor = 8, engineDeck = 10 },
	},
	mobility = { forwardKmh = 38, reverseKmh = 13 },
	crew = {
		{ role = "Commander", also = { "Loader" } :: Content.CrewRoles },
		{ role = "Gunner" },
		{ role = "Driver" },
	},
	modules = {
		guns = { "iu_gun_45mm", "iu_gun_63mm" },
		turrets = { "iu_turret_ostmal" },
		engines = { "iu_engine_d165" },
		tracks = { "iu_tracks_ostmal_m1", "iu_tracks_ostmal_m2" },
	},
	stock = {
		gun = "iu_gun_45mm",
		turret = "iu_turret_ostmal",
		engine = "iu_engine_d165",
		tracks = "iu_tracks_ostmal_m1",
	},
	top = {
		gun = "iu_gun_63mm",
		turret = "iu_turret_ostmal",
		engine = "iu_engine_d165",
		tracks = "iu_tracks_ostmal_m2",
	},
	moduleTree = {
		{ module = "iu_tracks_ostmal_m2" },
		{ module = "iu_gun_63mm", requires = { "iu_tracks_ostmal_m2" } },
	},
	unlocks = {
		{ vehicle = "iu_bulmal", requires = "iu_gun_63mm" },
	},
	researchXp = 350,
	price = { credits = 35000 },
	visual = {
		hull = {
			lengthM = 5.0,
			widthM = 2.5,
			heightM = 1.5,
			groundClearanceM = 0.4,
			style = "Stepped",
			upperFrontAngleDeg = 45,
			lowerFrontAngleDeg = 35,
			upperFrontFraction = 0.55,
			rearAngleDeg = 12,
			turretRing = { positionFraction = 0.32, diameterM = 1.3 },
			engineDeck = "Flat",
			fenders = true,
			skirts = "None",
		},
		running = {
			roadWheels = 5,
			wheelDiameterM = 0.7,
			returnRollers = 0,
			sprocket = "Front",
			trackWidthM = 0.4,
			suspension = "Torsion",
		},
		details = { exhausts = 2, toolboxes = 2, spareTracks = true, towCables = true, headlights = 2 },
		layout = {
			engine = "Rear",
			transmission = "Front",
			ammoRacks = { "Sponsons" },
			fuel = "Sides",
		},
		hooks = { "stepped_front", "spare_track_glacis" },
	},
	tree = { row = 2, branch = "iu_foundry" },
}

return vehicle
