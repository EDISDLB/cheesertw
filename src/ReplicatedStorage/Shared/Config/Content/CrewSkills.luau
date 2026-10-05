--!strict
--[[
	Content/CrewSkills — Crew skills/perks (00-DECISIONS §12): 6 individual + 3 group perks per role, effects at 100 % training (linear from 1 %).

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: roles are CrewRoles, effects use StatKeys, kind Individual/Group.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  Snap Shot: { id = "snap_shot", name = "Snap Shot", description = "Turret-traverse bloom −7.5 %.",
	  icon = "crew/skill_snap_shot", roles = { "Gunner" }, kind = "Individual",
	  effects = { { stat = "bloomTurretTraverse", op = "mul", value = 0.925 } } }
]]

local Content = require("../../Types/Content")

local crewSkills: { Content.CrewSkillDefinition } = {}

return crewSkills
