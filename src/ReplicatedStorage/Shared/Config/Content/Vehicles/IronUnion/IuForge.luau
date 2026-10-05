--!strict
--[[
	Content/Vehicles/IronUnion/IuForge — IU-1 Forge, Tier I medium tank (Iron Union starter; exemplar line 1/3).

	Purpose:          Complete vehicle definition proving the schema end to end (modules, module tree, unlocks,
	                  crew, visual spec, internal layout, lore).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry:validate() (references, configurations within load limits, crew, tree).
	Error handling:   N/A.
	Performance notes: Loaded once.

	Balance targets: Tier I Medium baseline (280 HP, α 40, pen 45, 40 km/h, 12 hp/t) × Iron Union kit
	(α ×1.10, reload ×1.10, dispersion ×1.06, aim ×1.05, depression 5°). One upgrade (the 45 mm), which also
	unlocks the IU-2 Anvil.
	Masses: stock 6,750 + 1,300 + 350 + 600 + 900 = 9,900 kg (2.0 % spare on 10,100); top 10,070 kg.
]]

local Content = require("../../../../Types/Content")

local vehicle: Content.VehicleDefinition = {
	id = "iu_forge",
	name = "IU-1 Forge",
	shortName = "Forge",
	faction = "iron_union",
	tier = 1,
	class = "medium",
	role = "medium_versatile",
	acquisition = "TechTree",
	description = "The Iron Union's training tank: simple, sturdy and forgiving, with a turret that can take a hit.",
	lore = "Assembled from tractor parts in the first foundry towns, the Forge taught a generation of crews that a plain, honest machine wins more battles than a clever one.",
	strengths = { "Sturdy turret for its tier", "Good hit points", "Easy to drive" },
	weaknesses = { "Modest gun depression", "Slow reload" },
	hull = {
		hp = 280,
		massKg = 6750,
		armor = { upperFront = 20, lowerFront = 16, side = 15, rear = 15, roof = 10, floor = 8, engineDeck = 8 },
	},
	mobility = { forwardKmh = 40, reverseKmh = 14 },
	crew = {
		{ role = "Commander", also = { "Loader" } :: Content.CrewRoles },
		{ role = "Gunner" },
		{ role = "Driver" },
	},
	modules = {
		guns = { "iu_gun_37mm", "iu_gun_45mm" },
		turrets = { "iu_turret_forge" },
		engines = { "iu_engine_d120" },
		tracks = { "iu_tracks_forge" },
	},
	stock = { gun = "iu_gun_37mm", turret = "iu_turret_forge", engine = "iu_engine_d120", tracks = "iu_tracks_forge" },
	top = { gun = "iu_gun_45mm", turret = "iu_turret_forge", engine = "iu_engine_d120", tracks = "iu_tracks_forge" },
	moduleTree = {
		{ module = "iu_gun_45mm" },
	},
	unlocks = {
		{ vehicle = "iu_anvil", requires = "iu_gun_45mm" },
	},
	price = { credits = 0 },
	visual = {
		hull = {
			lengthM = 4.6,
			widthM = 2.3,
			heightM = 1.55,
			groundClearanceM = 0.38,
			style = "Boxy",
			upperFrontAngleDeg = 55,
			lowerFrontAngleDeg = 30,
			upperFrontFraction = 0.5,
			rearAngleDeg = 10,
			turretRing = { positionFraction = 0.38, diameterM = 1.3 },
			engineDeck = "Louvered",
			fenders = true,
			skirts = "None",
		},
		running = {
			roadWheels = 4,
			wheelDiameterM = 0.55,
			returnRollers = 2,
			sprocket = "Rear",
			trackWidthM = 0.35,
			suspension = "Bogie",
		},
		details = { exhausts = 2, antennas = 1, toolboxes = 1, headlights = 1, towCables = true },
		layout = {
			engine = "Rear",
			transmission = "Rear",
			ammoRacks = { "HullMiddle" },
			fuel = "Rear",
		},
	},
	tree = { row = 3, branch = "Main line" },
	tags = { "starter" },
}

return vehicle
