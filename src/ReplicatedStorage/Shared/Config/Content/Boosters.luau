--!strict
--[[
	Content/Boosters — Personal boosters (XP, Free XP, crew XP, credits) granted by missions, the pass and events.

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: multiplier > 1, a duration or a battle count, valid target.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  { id = "xp_booster_50", name = "XP Booster", description = "+50 % vehicle XP for 2 hours.",
	  icon = "boosters/xp", target = "VehicleXP", multiplier = 1.5, durationS = 7200 }
]]

local Content = require("../../Types/Content")

local boosters: { Content.BoosterDefinition } = {}

return boosters
