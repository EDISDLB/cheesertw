--!strict
--[[
	Config/Audio — tunables owned by the client audio team (buses, voice budgets, distance bands, ducking) — client tunables.

	Purpose:          Section placeholder registered in Config/init so owning teams fill it without touching the aggregator.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	Error handling:   N/A.
	Performance notes: Read via Config.Audio at use time (live overrides replace the section table).
]]

local Audio = {
	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {},
}

return Audio
