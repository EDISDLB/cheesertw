--!strict
--[[
	Content/Tracks/IronUnion — Iron Union tracks/suspensions (exemplar line: roster.md §2.1 Foundry trunk, I–III).

	Purpose:          Tracks modules: load limit (gates heavier turrets/guns), hull traverse, terrain resistance,
	                  track armor (spaced) and track visuals.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: hard <= medium <= soft, load limits vs every configuration, sanity ranges.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Stock tracks carry the stock configuration with 1–3 % spare capacity, so the upgraded turret + gun only fit
	after the tracks upgrade (WoT's Tracks -> Turret -> Gun order enforced physically, 03-R4).
]]

local Content = require("../../../Types/Content")

local tracks: { Content.TracksDefinition } = {
	{
		id = "iu_tracks_kolmal",
		kind = "Tracks",
		name = "Kolmal tractor suspension",
		tier = 1,
		massKg = 900,
		priceCredits = 0,
		researchXp = 0,
		loadLimitKg = 10100,
		traverseDegS = 36,
		terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
		armorMm = 15,
		visual = { trackWidthM = 0.35, linkStyle = "Plain" },
	},
	{
		id = "iu_tracks_ostmal_m1",
		kind = "Tracks",
		name = "Ostmal torsion suspension",
		tier = 2,
		massKg = 1100,
		priceCredits = 0,
		researchXp = 0,
		loadLimitKg = 12300,
		traverseDegS = 35,
		terrainResistance = { hard = 0.95, medium = 1.15, soft = 2.0 },
		armorMm = 16,
		visual = { trackWidthM = 0.4, linkStyle = "Plain" },
	},
	{
		id = "iu_tracks_ostmal_m2",
		kind = "Tracks",
		name = "Ostmal reinforced suspension",
		tier = 2,
		massKg = 1150,
		priceCredits = 2100,
		researchXp = 90,
		loadLimitKg = 13200,
		traverseDegS = 38,
		terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
		armorMm = 18,
		visual = { trackWidthM = 0.4, linkStyle = "Grousered" },
	},
	{
		id = "iu_tracks_bulmal_m1",
		kind = "Tracks",
		name = "Bulmal torsion suspension",
		tier = 3,
		massKg = 1600,
		priceCredits = 0,
		researchXp = 0,
		loadLimitKg = 17400,
		traverseDegS = 34,
		terrainResistance = { hard = 0.95, medium = 1.15, soft = 2.0 },
		armorMm = 18,
		visual = { trackWidthM = 0.45, linkStyle = "Plain" },
	},
	{
		id = "iu_tracks_bulmal_m2",
		kind = "Tracks",
		name = "Bulmal heavy suspension",
		tier = 3,
		massKg = 1700,
		priceCredits = 6000,
		researchXp = 120,
		loadLimitKg = 18800,
		traverseDegS = 37,
		terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
		armorMm = 20,
		visual = { trackWidthM = 0.45, linkStyle = "Grousered" },
	},
}

return tracks
