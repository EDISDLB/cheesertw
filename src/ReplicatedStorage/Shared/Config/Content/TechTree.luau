--!strict
--[[
	Content/TechTree — named branches of each faction's tech tree (roster.md §1 branch tables).

	Purpose:          Branch identity for the tech-tree screen (headers, filters, "branch" chips) and for the
	                  authoring checks that keep a vehicle inside its branch's classes and tiers. Research EDGES are
	                  not here: they live on the vehicles (`unlocks`) and ContentRegistry:techTreeEdges() derives the
	                  graph, so one fact is never written twice.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: faction exists, id starts with the faction idPrefix, classes and tier range
	                  valid; vehicles naming a branch match its faction, classes and tiers.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Ids follow the roster's `<prefix>.<branch>` names in snake_case (`iu.bulwark` -> `iu_bulwark`). Tier ranges are
	the full design ranges, including the Tier XI Apex where a branch leads to one.
]]

local Content = require("../../Types/Content")

local branches: { Content.BranchDefinition } = {
	-- Iron Union
	{
		id = "iu_foundry",
		faction = "iron_union",
		name = "Foundry trunk",
		description = "Slow, sturdy starter mediums that teach angling and trading.",
		classes = { "medium" },
		tiers = { min = 1, max = 3 },
	},
	{
		id = "iu_bulwark",
		faction = "iron_union",
		name = "Bulwark heavy line",
		description = "The spine: from riveted box to pike nose to twin-gun wall.",
		classes = { "heavy" },
		tiers = { min = 4, max = 11 },
	},
	{
		id = "iu_hammer",
		faction = "iron_union",
		name = "Hammer brawler mediums",
		description = "Turret-strong, high-alpha mediums that fight like light heavies.",
		classes = { "medium" },
		tiers = { min = 4, max = 10 },
	},
	{
		id = "iu_ram",
		faction = "iron_union",
		name = "Ram destroyer line",
		description = "Rear-casemate destroyers with very high alpha and poor arcs.",
		classes = { "td" },
		tiers = { min = 4, max = 10 },
	},
	-- Crown Industries
	{
		id = "ci_guild",
		faction = "crown_industries",
		name = "Guild trunk",
		description = "Precision from the first battle.",
		classes = { "light", "medium" },
		tiers = { min = 1, max = 4 },
	},
	{
		id = "ci_warden",
		faction = "crown_industries",
		name = "Warden heavy line",
		description = "Hull-down heavies; HESH from Tier VIII.",
		classes = { "heavy" },
		tiers = { min = 5, max = 10 },
	},
	{
		id = "ci_vernier",
		faction = "crown_industries",
		name = "Vernier destroyer line",
		description = "Low precision casemates with HESH.",
		classes = { "td" },
		tiers = { min = 4, max = 11 },
	},
	{
		id = "ci_herald",
		faction = "crown_industries",
		name = "Herald light line",
		description = "Fast, accurate scouts with poor alpha.",
		classes = { "light" },
		tiers = { min = 5, max = 10 },
	},
	-- Eastern Armor Group
	{
		id = "ea_skirmish",
		faction = "eastern_armor",
		name = "Skirmish light line",
		description = "The spine: scouts and flankers, with magazines at Tiers IX–X.",
		classes = { "light" },
		tiers = { min = 1, max = 11 },
	},
	{
		id = "ea_outrider",
		faction = "eastern_armor",
		name = "Outrider wheeled line",
		description = "The fastest vehicles in the game: information, not trades.",
		classes = { "light" },
		tiers = { min = 7, max = 10 },
	},
	{
		id = "ea_gale",
		faction = "eastern_armor",
		name = "Gale medium line",
		description = "Fast, thin, high-alpha single-shot mediums.",
		classes = { "medium" },
		tiers = { min = 5, max = 10 },
	},
	-- Desert Armor Corps
	{
		id = "dc_caravan",
		faction = "desert_corps",
		name = "Caravan trunk",
		description = "Quick-aiming starter mediums.",
		classes = { "medium" },
		tiers = { min = 1, max = 3 },
	},
	{
		id = "dc_longshot",
		faction = "desert_corps",
		name = "Longshot medium line",
		description = "The spine: hull-down long-range mediums with autoreloaders at Tiers VIII–X.",
		classes = { "medium" },
		tiers = { min = 4, max = 11 },
	},
	{
		id = "dc_sunfall",
		faction = "desert_corps",
		name = "Sunfall artillery line",
		description = "The launch artillery, alternating stun Support and Area control roles.",
		classes = { "artillery" },
		tiers = { min = 4, max = 10 },
	},
	{
		id = "dc_glint",
		faction = "desert_corps",
		name = "Glint destroyer line",
		description = "Autoreloader casemates.",
		classes = { "td" },
		tiers = { min = 5, max = 10 },
	},
	-- Mountain Republic
	{
		id = "mr_pathfinder",
		faction = "mountain_republic",
		name = "Pathfinder trunk",
		description = "Nimble climbing scouts.",
		classes = { "light" },
		tiers = { min = 1, max = 3 },
	},
	{
		id = "mr_ridgeline",
		faction = "mountain_republic",
		name = "Ridgeline medium line",
		description = "The spine: reverse-slope mediums with hydropneumatic suspension at Tiers VIII–X.",
		classes = { "medium" },
		tiers = { min = 4, max = 11 },
	},
	{
		id = "mr_bastion",
		faction = "mountain_republic",
		name = "Bastion siege line",
		description = "Turretless siege casemates.",
		classes = { "td" },
		tiers = { min = 4, max = 10 },
	},
	{
		id = "mr_scree",
		faction = "mountain_republic",
		name = "Scree light line",
		description = "Climbing scouts that spot from the peaks.",
		classes = { "light" },
		tiers = { min = 4, max = 10 },
	},
	-- Northern Federation
	{
		id = "nf_frontier",
		faction = "northern_federation",
		name = "Frontier trunk",
		description = "One rugged starter.",
		classes = { "medium" },
		tiers = { min = 1, max = 1 },
	},
	{
		id = "nf_glacis",
		faction = "northern_federation",
		name = "Glacis destroyer line",
		description = "The spine: from ambush carriages to assault casemates.",
		classes = { "td" },
		tiers = { min = 2, max = 10 },
	},
	{
		id = "nf_rimeguard",
		faction = "northern_federation",
		name = "Rimeguard heavy line",
		description = "Survival heavies that become breakthrough machines.",
		classes = { "heavy" },
		tiers = { min = 4, max = 11 },
	},
	{
		id = "nf_aurora",
		faction = "northern_federation",
		name = "Aurora artillery line",
		description = "The second artillery line, stun Support only.",
		classes = { "artillery" },
		tiers = { min = 4, max = 10 },
	},
}

return branches
