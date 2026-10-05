--!strict
--[[
	Content/Engines/IronUnion — Iron Union engines (exemplar line, tiers I–III).

	Purpose:          Engine modules: power (hp), fuel (fire chance default), sound family, exhaust visuals.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: power/fire sanity ranges, audio family enum.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Engine power is a GAMEPLAY value tuned to the class power-to-weight target (00-DECISIONS §6), not a
	real-world rating. Diesels: 12 % fire chance per engine hit.
]]

local Content = require("../../../Types/Content")

local engines: { Content.EngineDefinition } = {
	{
		id = "iu_engine_d120",
		kind = "Engine",
		name = "IU-D120 diesel",
		tier = 1,
		massKg = 600,
		priceCredits = 0,
		researchXp = 0,
		powerHp = 120,
		fuel = "Diesel",
		audio = "small_engine",
		visual = { exhausts = 2, exhaustPlacement = "Rear" },
	},
	{
		id = "iu_engine_d165",
		kind = "Engine",
		name = "IU-D165 diesel",
		tier = 2,
		massKg = 750,
		priceCredits = 0,
		researchXp = 0,
		powerHp = 165,
		fuel = "Diesel",
		audio = "medium_diesel",
		visual = { exhausts = 2, exhaustPlacement = "Rear" },
	},
	{
		id = "iu_engine_d230",
		kind = "Engine",
		name = "IU-D230 diesel",
		tier = 3,
		massKg = 950,
		priceCredits = 0,
		researchXp = 0,
		powerHp = 230,
		fuel = "Diesel",
		audio = "heavy_diesel",
		visual = { exhausts = 2, exhaustPlacement = "Sides" },
	},
	{
		id = "iu_engine_d290",
		kind = "Engine",
		name = "IU-D290 supercharged diesel",
		tier = 3,
		massKg = 1050,
		priceCredits = 6000,
		researchXp = 80,
		powerHp = 290,
		fuel = "Diesel",
		audio = "heavy_diesel",
		visual = { exhausts = 2, exhaustPlacement = "Sides" },
	},
}

return engines
