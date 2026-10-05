--!strict
--[[
	Content/Achievements — Achievements: Battle Heroes, epic medals, mastery badges, gun marks, milestones and event awards (00-DECISIONS §14).

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: category/kind/rarity enums, strictly increasing thresholds, rule key set, reward references.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  Top Gun: { id = "top_gun", name = "Top Gun", description = "Destroy the most enemies on your team, at least 6.",
	  icon = "achievements/top_gun", category = "BattleHero", kind = "BattleMedal", rule = "mostOnTeam",
	  stat = "kills", params = { min = 6 }, repeatable = true, rarity = "rare",
	  rewards = { { kind = "CampaignTokens", amount = 10 } } }
]]

local Content = require("../../Types/Content")

local achievements: { Content.AchievementDefinition } = {}

return achievements
