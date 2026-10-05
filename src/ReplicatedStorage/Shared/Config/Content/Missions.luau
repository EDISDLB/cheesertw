--!strict
--[[
	Content/Missions — Missions: dailies, weeklies, campaigns, event and tutorial missions (00-DECISIONS §14).

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: conditions use BattleStatKeys with atLeast/atMost, scopes and rewards reference existing content, event missions name their event.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  A daily: { id = "daily_block_and_deal", name = "Hold the line", description = "Deal and block 1,500 HP in one battle.",
	  cadence = "Daily", difficulty = "Medium", match = "All",
	  conditions = { { stat = "damageDealtPlusBlocked", atLeast = 1500, aggregate = "SingleBattle" } },
	  rewards = { { kind = "Credits", amount = 3000 }, { kind = "FreeXP", amount = 300 } }, scaleRewardsByTier = true }
]]

local Content = require("../../Types/Content")

local missions: { Content.MissionDefinition } = {}

return missions
