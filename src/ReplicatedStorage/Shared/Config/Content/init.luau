--!strict
--[[
	Content — the content manifest: explicit registration lists for every content kind (no instance scanning).

	Purpose:          The single list of shipped content files. ContentRegistry flattens these sources, indexes them
	                  by id and validates them. Gameplay code never requires content files directly.
	Dependencies:     Types/Content and every file under Config/Content.
	State:            Data only (the registry deep-freezes it).
	Validation:       ContentRegistry:validate().
	Error handling:   A missing file fails the require at load (and in tests).
	Performance notes: Loaded once per server/client.

	Adding content: create the file (see docs/design/content-schema.md) and add ONE line to the matching list.
	Multi-file kinds (shells, guns, turrets, engines, tracks) list one module per faction file; vehicles and maps
	list one module per definition.
]]

local Content = require("../Types/Content")

local sources: Content.ContentSources = {
	factions = require("@self/Factions"),
	classes = require("@self/Classes"),
	roles = require("@self/Roles"),
	tiers = require("@self/Tiers"),

	shells = {
		require("@self/Shells/IronUnion"),
	},
	guns = {
		require("@self/Guns/IronUnion"),
	},
	turrets = {
		require("@self/Turrets/IronUnion"),
	},
	engines = {
		require("@self/Engines/IronUnion"),
	},
	tracks = {
		require("@self/Tracks/IronUnion"),
	},

	vehicles = {
		-- Iron Union
		require("@self/Vehicles/IronUnion/IuForge"),
		require("@self/Vehicles/IronUnion/IuAnvil"),
		require("@self/Vehicles/IronUnion/IuBastion"),
	},

	equipment = require("@self/Equipment"),
	consumables = require("@self/Consumables"),
	crewSkills = require("@self/CrewSkills"),
	crewBooks = require("@self/CrewBooks"),
	boosters = require("@self/Boosters"),
	customization = require("@self/Customization"),
	missions = require("@self/Missions"),
	achievements = require("@self/Achievements"),

	maps = {
		require("@self/Maps/ProvingGrounds"),
	},

	store = require("@self/Store"),
	events = require("@self/Events"),
	seasons = require("@self/BattlePass"),
}

return sources
