--!strict
--[[
	Content/Vehicles/IronUnion/IuKolmal — Kolmal, Tier I medium tank, Versatile (roster.md §2.1; exemplar line 1/3).

	Purpose:          Complete vehicle definition proving the schema end to end (modules, module tree, unlocks,
	                  crew, visual spec + hooks, internal layout, lore).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry:validate() (references, configurations within load limits, crew, tree).
	Error handling:   N/A.
	Performance notes: Loaded once.

	Roster identity: "forgiving starter: sloped riveted front that rewards angling, slow, choice of a quick or a
	hard-hitting gun" — the 37 mm (fast reload) arrives stock, the 45 mm (more alpha and pen) is the one upgrade and
	unlocks the Ostmal. Balance targets: Tier I Medium baseline (280 HP, α 40, pen 45, 40 km/h, 12 hp/t) × Iron
	Union kit (α ×1.10, reload ×1.10, dispersion ×1.06, aim ×1.05, depression 5°); slow by design (36 km/h).
	Two seats: the commander also aims and loads (the smallest legal crew).
	Masses: stock 6,900 + 1,100 + 350 + 600 + 900 = 9,850 kg (2.5 % spare on 10,100); top 10,020 kg.
]]

local Content = require("../../../../Types/Content")

local vehicle: Content.VehicleDefinition = {
	id = "iu_kolmal",
	name = "Kolmal",
	shortName = "Kolmal",
	faction = "iron_union",
	tier = 1,
	class = "medium",
	role = "medium_versatile",
	acquisition = "TechTree",
	description = "A forgiving starter built on a tractor chassis. Angle its riveted front and it shrugs off its peers.",
	lore = "The first Cinderbelt foundries bolted armor plate onto plough tractors to clear the proving fields. The Kolmal kept the tractor's patience and its stubbornness, and every Iron Union crew still learns to angle in one.",
	strengths = { "Sloped front that rewards angling", "Choice of a quick or a hard-hitting gun" },
	weaknesses = { "Slow", "Only 5° of gun depression" },
	hull = {
		hp = 280,
		massKg = 6900,
		armor = { upperFront = 20, lowerFront = 16, side = 15, rear = 15, roof = 10, floor = 8, engineDeck = 8 },
	},
	mobility = { forwardKmh = 36, reverseKmh = 13 },
	crew = {
		{ role = "Commander", also = { "Gunner", "Loader" } :: Content.CrewRoles },
		{ role = "Driver" },
	},
	modules = {
		guns = { "iu_gun_37mm", "iu_gun_45mm" },
		turrets = { "iu_turret_kolmal" },
		engines = { "iu_engine_d120" },
		tracks = { "iu_tracks_kolmal" },
	},
	stock = {
		gun = "iu_gun_37mm",
		turret = "iu_turret_kolmal",
		engine = "iu_engine_d120",
		tracks = "iu_tracks_kolmal",
	},
	top = {
		gun = "iu_gun_45mm",
		turret = "iu_turret_kolmal",
		engine = "iu_engine_d120",
		tracks = "iu_tracks_kolmal",
	},
	moduleTree = {
		{ module = "iu_gun_45mm" },
	},
	unlocks = {
		{ vehicle = "iu_ostmal", requires = "iu_gun_45mm" },
	},
	price = { credits = 0 },
	visual = {
		hull = {
			lengthM = 4.4,
			widthM = 2.3,
			heightM = 1.4,
			groundClearanceM = 0.35,
			style = "Boxy",
			upperFrontAngleDeg = 50,
			lowerFrontAngleDeg = 30,
			upperFrontFraction = 0.5,
			rearAngleDeg = 10,
			turretRing = { positionFraction = 0.42, diameterM = 1.0 },
			engineDeck = "Louvered",
			fenders = true,
			skirts = "None",
		},
		running = {
			roadWheels = 4,
			wheelDiameterM = 0.7,
			returnRollers = 0,
			sprocket = "Rear",
			trackWidthM = 0.35,
			suspension = "Leaf",
		},
		details = { exhausts = 2, toolboxes = 1, headlights = 1, towCables = true },
		layout = {
			engine = "Rear",
			transmission = "Rear",
			ammoRacks = { "HullMiddle" },
			fuel = "Rear",
		},
		hooks = { "tractor_chassis", "sagging_track", "riveted_plates" }, -- roster.md §2.9: IU-wide + own
	},
	tree = { row = 2, branch = "iu_foundry" },
	tags = { "starter" },
}

return vehicle
