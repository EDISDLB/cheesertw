--!strict
--[[
	Config/Movement — tunables owned by the vehicle-simulation team (terrain resistance, slopes, water, overturn, collisions).

	Purpose:          Section placeholder registered in Config/init so owning teams fill it without touching the aggregator.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	Error handling:   N/A.
	Performance notes: Read via Config.Movement at use time (live overrides replace the section table).
]]

local Movement = {
	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {},
}

return Movement
