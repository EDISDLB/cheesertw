--!strict
--[[
	Config/Economy — tunables owned by the economy team (rewards, costs, premium multipliers, free XP share, repair/ammo pricing).

	Purpose:          Section placeholder registered in Config/init so owning teams fill it without touching the aggregator.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	Error handling:   N/A.
	Performance notes: Read via Config.Economy at use time (live overrides replace the section table).
]]

local Economy = {
	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {},
}

return Economy
