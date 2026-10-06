--!strict
--[[
	Content/Maps/ProvingGrounds — "Proving Grounds", a small 800 m training-pool map (exemplar map definition).

	Purpose:          Smallest complete MapDefinition: terrain recipe, 15 + 15 spawns, Standard bases, the three lane
	                  kinds, tactical positions, analytic foliage volumes, props, water, cosmetic variants, audio
	                  and tips.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: spawn counts/rear slots/bounds/spacing/centroid separation, bases per battle
	                  type and >= 60 m inside the edge, one lane of each kind, per-team positions, foliage ranges,
	                  references.
	Error handling:   N/A.
	Performance notes: Loaded once; the Battle server builds the map from this data before players arrive.

	Map space: metres, origin at the centre, +x east, +z south. Team 1 spawns in the north facing south (180°), team
	2 in the south facing north (0°). The layout is mirrored through the centre so every lane is symmetric.
]]

local Content = require("../../../Types/Content")

local map: Content.MapDefinition = {
	id = "proving_grounds",
	name = "Proving Grounds",
	description = "A foundry test range of rolling fields split by a central ridge. Heavies grind through the western farm, mediums duel over the ridge and scouts race the open eastern meadow.",
	biome = "temperate",
	sizeM = 800,
	skirtM = 150,
	tierRange = { min = 1, max = 3 },
	battleTypes = { "Standard" },
	modes = { "Random", "Training", "Practice", "Bootcamp" },
	terrain = {
		seed = 1103,
		baseHeightM = 20,
		noise = {
			{ scaleM = 220, amplitudeM = 6 },
			{ scaleM = 60, amplitudeM = 1.5 },
		},
		features = {
			{
				kind = "Ridge",
				points = { { x = -40, z = -120 }, { x = 0, z = 0 }, { x = 40, z = 120 } },
				radiusM = 70,
				heightM = 14,
			},
			{ kind = "Hill", points = { { x = -230, z = -40 } }, radiusM = 80, heightM = 9 },
			{ kind = "Hill", points = { { x = 230, z = 40 } }, radiusM = 80, heightM = 9 },
			{ kind = "Valley", points = { { x = 240, z = -160 }, { x = 240, z = 160 } }, radiusM = 90, heightM = -4 },
			{ kind = "Flatten", points = { { x = 0, z = -310 } }, radiusM = 140, heightM = 0, falloff = 0.8 },
			{ kind = "Flatten", points = { { x = 0, z = 310 } }, radiusM = 140, heightM = 0, falloff = 0.8 },
			{
				kind = "Road",
				points = { { x = -300, z = -390 }, { x = -260, z = 0 }, { x = -300, z = 390 } },
				radiusM = 5,
				heightM = 0,
			},
		},
		materials = {
			{ material = "Rock", rule = "Slope", min = 30 },
			{ material = "Ground", rule = "Feature", feature = "Road" },
			{ material = "LeafyGrass", rule = "Height", min = 12 },
			{ material = "Grass", rule = "Default" },
		},
		waterLevelM = 17,
	},
	spawns = {
		team1 = {
			{ at = { x = -120, z = -280 }, facingDeg = 180 },
			{ at = { x = -60, z = -280 }, facingDeg = 180 },
			{ at = { x = 0, z = -280 }, facingDeg = 180 },
			{ at = { x = 60, z = -280 }, facingDeg = 180 },
			{ at = { x = 120, z = -280 }, facingDeg = 180 },
			{ at = { x = -120, z = -310 }, facingDeg = 180 },
			{ at = { x = -60, z = -310 }, facingDeg = 180 },
			{ at = { x = 0, z = -310 }, facingDeg = 180 },
			{ at = { x = 60, z = -310 }, facingDeg = 180 },
			{ at = { x = 120, z = -310 }, facingDeg = 180 },
			{ at = { x = -120, z = -340 }, facingDeg = 180, rear = true },
			{ at = { x = -60, z = -340 }, facingDeg = 180, rear = true },
			{ at = { x = 0, z = -340 }, facingDeg = 180, rear = true },
			{ at = { x = 60, z = -340 }, facingDeg = 180, rear = true },
			{ at = { x = 120, z = -340 }, facingDeg = 180, rear = true },
		},
		team2 = {
			{ at = { x = 120, z = 280 }, facingDeg = 0 },
			{ at = { x = 60, z = 280 }, facingDeg = 0 },
			{ at = { x = 0, z = 280 }, facingDeg = 0 },
			{ at = { x = -60, z = 280 }, facingDeg = 0 },
			{ at = { x = -120, z = 280 }, facingDeg = 0 },
			{ at = { x = 120, z = 310 }, facingDeg = 0 },
			{ at = { x = 60, z = 310 }, facingDeg = 0 },
			{ at = { x = 0, z = 310 }, facingDeg = 0 },
			{ at = { x = -60, z = 310 }, facingDeg = 0 },
			{ at = { x = -120, z = 310 }, facingDeg = 0 },
			{ at = { x = 120, z = 340 }, facingDeg = 0, rear = true },
			{ at = { x = 60, z = 340 }, facingDeg = 0, rear = true },
			{ at = { x = 0, z = 340 }, facingDeg = 0, rear = true },
			{ at = { x = -60, z = 340 }, facingDeg = 0, rear = true },
			{ at = { x = -120, z = 340 }, facingDeg = 0, rear = true },
		},
	},
	bases = {
		{ id = "base_north", battleType = "Standard", team = 1, center = { x = 0, z = -200 }, radiusM = 50 },
		{ id = "base_south", battleType = "Standard", team = 2, center = { x = 0, z = 200 }, radiusM = 50 },
	},
	lanes = {
		{
			id = "west_farm",
			kind = "Heavy",
			points = { { x = -260, z = -250 }, { x = -280, z = 0 }, { x = -260, z = 250 } },
			widthM = 140,
		},
		{
			id = "central_ridge",
			kind = "Flex",
			points = { { x = 0, z = -220 }, { x = 0, z = 0 }, { x = 0, z = 220 } },
			widthM = 160,
		},
		{
			id = "east_meadow",
			kind = "Open",
			points = { { x = 260, z = -250 }, { x = 240, z = 0 }, { x = 260, z = 250 } },
			widthM = 180,
		},
	},
	-- Tactical points for bots and map QA: three hull-down spots per side on the ridge, a sniper overwatch and a
	-- scout bush per team, and a brawl corner at the western farm. No artillery pits: SPGs start at Tier IV.
	positions = {
		{
			id = "t1_ridge_north",
			kind = "HullDown",
			at = { x = -45, z = -140 },
			facingDeg = 180,
			team = 1,
			lane = "central_ridge",
		},
		{
			id = "t1_ridge_mid",
			kind = "HullDown",
			at = { x = -30, z = -100 },
			facingDeg = 180,
			team = 1,
			lane = "central_ridge",
		},
		{
			id = "t1_ridge_crest",
			kind = "HullDown",
			at = { x = -10, z = -60 },
			facingDeg = 180,
			team = 1,
			lane = "central_ridge",
		},
		{ id = "t1_hill_overwatch", kind = "Sniper", at = { x = -230, z = -150 }, facingDeg = 150, team = 1 },
		{
			id = "t1_hedgerow",
			kind = "Scout",
			at = { x = 190, z = -70 },
			facingDeg = 180,
			team = 1,
			lane = "east_meadow",
		},
		{
			id = "t1_farm_corner",
			kind = "Brawl",
			at = { x = -285, z = -85 },
			facingDeg = 180,
			team = 1,
			lane = "west_farm",
		},
		{
			id = "t2_ridge_south",
			kind = "HullDown",
			at = { x = 45, z = 140 },
			facingDeg = 0,
			team = 2,
			lane = "central_ridge",
		},
		{
			id = "t2_ridge_mid",
			kind = "HullDown",
			at = { x = 30, z = 100 },
			facingDeg = 0,
			team = 2,
			lane = "central_ridge",
		},
		{
			id = "t2_ridge_crest",
			kind = "HullDown",
			at = { x = 10, z = 60 },
			facingDeg = 0,
			team = 2,
			lane = "central_ridge",
		},
		{ id = "t2_hill_overwatch", kind = "Sniper", at = { x = 230, z = 150 }, facingDeg = 330, team = 2 },
		{
			id = "t2_dense_bush",
			kind = "Scout",
			at = { x = 205, z = 125 },
			facingDeg = 0,
			team = 2,
			lane = "east_meadow",
		},
		{
			id = "t2_farm_corner",
			kind = "Brawl",
			at = { x = -270, z = 60 },
			facingDeg = 0,
			team = 2,
			lane = "west_farm",
		},
	},
	foliage = {
		{ kind = "DenseBush", at = { x = -200, z = -120 }, heightM = 1.2, radiusM = 3 },
		{ kind = "DenseBush", at = { x = 200, z = 120 }, heightM = 1.2, radiusM = 3 },
		{ kind = "Hedgerow", at = { x = 150, z = -60 }, to = { x = 230, z = -40 }, heightM = 1.0, radiusM = 1.5 },
		{ kind = "Hedgerow", at = { x = -150, z = 60 }, to = { x = -230, z = 40 }, heightM = 1.0, radiusM = 1.5 },
		{ kind = "TreeCrown", at = { x = 60, z = -150 }, heightM = 6, radiusM = 4 },
		{ kind = "TreeCrown", at = { x = -60, z = 150 }, heightM = 6, radiusM = 4 },
		{ kind = "LightBush", at = { x = 300, z = -20 }, heightM = 0.8, radiusM = 2 },
		{ kind = "LightBush", at = { x = -300, z = 20 }, heightM = 0.8, radiusM = 2 },
		{ kind = "Thicket", at = { x = 120, z = -200 }, heightM = 1.5, radiusM = 4 },
		{ kind = "Thicket", at = { x = -120, z = 200 }, heightM = 1.5, radiusM = 4 },
	},
	props = {
		{ prop = "house_small", at = { x = -300, z = -60 }, rotationDeg = 90, destructible = "Heavy" },
		{ prop = "house_small", at = { x = 300, z = 60 }, rotationDeg = 270, destructible = "Heavy" },
		{ prop = "barn", at = { x = -250, z = -10 }, rotationDeg = 0, destructible = "Permanent" },
		{ prop = "barn", at = { x = 250, z = 10 }, rotationDeg = 180, destructible = "Permanent" },
		{ prop = "rock_large", at = { x = -20, z = -40 }, scale = 1.2 },
		{ prop = "rock_large", at = { x = 20, z = 40 }, scale = 1.2 },
		{ prop = "fence_wood", at = { x = -220, z = -90 }, rotationDeg = 45, destructible = "Light" },
		{ prop = "fence_wood", at = { x = 220, z = 90 }, rotationDeg = 225, destructible = "Light" },
	},
	water = {
		{
			id = "mill_pond_east",
			points = { { x = 150, z = -20 }, { x = 185, z = -5 }, { x = 170, z = 25 }, { x = 140, z = 15 } },
			surfaceHeightM = 17,
			depthM = 0.8,
		},
		{
			id = "mill_pond_west",
			points = { { x = -150, z = 20 }, { x = -185, z = 5 }, { x = -170, z = -25 }, { x = -140, z = -15 } },
			surfaceHeightM = 17,
			depthM = 0.8,
		},
	},
	variants = {
		{ id = "midday", lighting = "midday", weather = "clear", weight = 1 },
		{ id = "overcast", lighting = "overcast", weather = "overcast", weight = 0.5 },
	},
	audio = { ambience = "amb_plains_bed" },
	thumbnail = "maps/proving_grounds",
	tips = {
		"The central ridge gives hull-down cover to both teams. Peek, fire, reverse.",
		"Scouts can light the whole eastern meadow from the hedgerows.",
		"The western farm houses can be rammed down by heavy vehicles.",
	},
	revision = 1,
}

return map
