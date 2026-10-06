--!strict
--[[
	Content/Engines/IronUnion — Iron Union engines (exemplar line: roster.md §2.1 Foundry trunk, I–III).

	Purpose:          Engine modules: power (hp), fuel (fire chance default), sound family, exhaust visuals.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: power/fire sanity ranges, audio family enum.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Engine power is a GAMEPLAY value tuned to the class power-to-weight target (00-DECISIONS §6), not a real-world
	rating. Iron Union runs diesels (12 % fire chance per engine hit) with rear exhaust stacks (roster.md §1.1).
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
		id = "iu_engine_d210",
		kind = "Engine",
		name = "IU-D210 diesel",
		tier = 3,
		massKg = 800,
		priceCredits = 0,
		researchXp = 0,
		powerHp = 210,
		fuel = "Diesel",
		audio = "medium_diesel",
		visual = { exhausts = 2, exhaustPlacement = "Rear" },
	},
	{
		id = "iu_engine_d250",
		kind = "Engine",
		name = "IU-D250 supercharged diesel",
		tier = 3,
		massKg = 880,
		priceCredits = 6000,
		researchXp = 80,
		powerHp = 250,
		fuel = "Diesel",
		audio = "medium_diesel",
		visual = { exhausts = 2, exhaustPlacement = "Rear" },
	},
}

return engines
