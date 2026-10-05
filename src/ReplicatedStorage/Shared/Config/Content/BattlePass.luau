--!strict
--[[
	Content/BattlePass — Season Pass seasons: chapters, stages, free/paid fixed rewards, points per battle by team rank (00-DECISIONS §14).

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: windows ordered, stages/points positive, rewards reference content, rank rules ascending.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  { id = "season_1", name = "Season 1: Ridge Line", startsAt = 1790000000, endsAt = 1794838400,
	  chapters = { { id = "s1c1", name = "Chapter 1", stages = 30, pointsPerStage = 30, rewards = {} } },
	  pointsByRank = { { maxTeamRank = 3, win = 8, loss = 6 }, { maxTeamRank = 10, win = 6, loss = 4 },
	    { maxTeamRank = 15, win = 3, loss = 2 } }, pointsPerDailyMission = 15 }
]]

local Content = require("../../Types/Content")

local seasons: { Content.SeasonDefinition } = {}

return seasons
