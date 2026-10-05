--!strict
--[[
	Config/Battle — battle timing and team rules (real-world units: seconds, players).

	Purpose:          Tick/snapshot rates used by BattleInstance and replication; placeholders the combat team fills.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	Error handling:   N/A.
	Performance notes: Read via Config.Battle at use time (live overrides replace the section table).
]]

local Battle = {
	--- Fixed simulation step rate (Hz). ARCHITECTURE §6.1.
	TICK_RATE = 30,
	--- Per-observer snapshot rate (Hz). ARCHITECTURE §5.2.
	SNAPSHOT_RATE = 20,
	--- Players per team in random battles.
	TEAM_SIZE = 15,
	--- Battle length and pre-battle countdown (s). TODO(combat-team): tune.
	DURATION_S = 900,
	COUNTDOWN_S = 30,
	--- Remote vehicle interpolation delay on clients (s).
	INTERPOLATION_DELAY_S = 0.1,

	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {
		TICK_RATE = { min = 10, max = 60, integer = true },
		SNAPSHOT_RATE = { min = 5, max = 30, integer = true },
		TEAM_SIZE = { min = 1, max = 15, integer = true },
		DURATION_S = { min = 60, max = 1800, integer = true },
		COUNTDOWN_S = { min = 0, max = 120, integer = true },
		INTERPOLATION_DELAY_S = { min = 0.03, max = 0.5 },
	},
}

return Battle
