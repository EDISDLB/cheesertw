--!strict
--[[
	Config/Combat — tunables owned by the combat/ballistics team (penetration, normalization, ricochet, RNG, HE/HEAT, damage, modules, fire, ramming, falls, dispersion, reload rules).

	Purpose:          Section placeholder registered in Config/init so owning teams fill it without touching the aggregator.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	Error handling:   N/A.
	Performance notes: Read via Config.Combat at use time (live overrides replace the section table).
]]

local Combat = {
	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {},
}

return Combat
