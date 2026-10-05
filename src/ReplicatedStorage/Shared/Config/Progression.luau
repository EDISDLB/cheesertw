--!strict
--[[
	Config/Progression — tunables owned by the progression team (account levels, crew XP curves, skill costs, research rules).

	Purpose:          Section placeholder registered in Config/init so owning teams fill it without touching the aggregator.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	Error handling:   N/A.
	Performance notes: Read via Config.Progression at use time (live overrides replace the section table).
]]

local Progression = {
	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {},
}

return Progression
