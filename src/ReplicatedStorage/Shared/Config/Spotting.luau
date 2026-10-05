--!strict
--[[
	Config/Spotting — tunables owned by the spotting team (view range, camouflage, proximity, check intervals, foliage, linger, sixth sense).

	Purpose:          Section placeholder registered in Config/init so owning teams fill it without touching the aggregator.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	Error handling:   N/A.
	Performance notes: Read via Config.Spotting at use time (live overrides replace the section table).
]]

local Spotting = {
	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {},
}

return Spotting
