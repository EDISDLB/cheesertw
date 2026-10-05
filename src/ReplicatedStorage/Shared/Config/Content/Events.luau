--!strict
--[[
	Content/Events — Live events: windows, missions, modifiers, event modes with mode-only abilities, token shops. Data-driven; services implement.

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: startsAt < endsAt, missions/shop/maps exist, abilities only here (never in vehicles).
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  { id = "forge_week", name = "Forge Week", description = "Double first-win XP on Iron Union vehicles.",
	  kind = "XpFever", startsAt = 1790000000, endsAt = 1790604800, missions = {},
	  modifiers = { firstWinMul = 3 } }
]]

local Content = require("../../Types/Content")

local events: { Content.EventDefinition } = {}

return events
