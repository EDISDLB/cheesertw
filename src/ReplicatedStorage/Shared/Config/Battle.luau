--!strict
--[[
	Config/Battle — battle timing, lifecycle, objective, connection/AFK and ledger rules (real-world units: seconds,
	metres, points, players). Values follow docs/research/00-DECISIONS.md §9 (battle rules and lifecycle), §5
	(spotting assist window), §2 (drowning/no credit), §7.2 (first-contact window) and §21 #22; design notes in
	docs/design/battle-rules.md.

	Purpose:          Tick/snapshot rates used by BattleInstance and replication; every timer, rate and limit read by
	                  Shared/Battle/Rules (ModeRules, Phases, Capture, Outcome, Connection) and Shared/Battle/Ledger.
	Dependencies:     None.
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares which keys may be live-overridden and their numeric limits (Config.applyOverrides).
	                  Cross-key consistency (AFK warn < takeover, …) is enforced by Rules/ModeRules.resolve.
	Error handling:   N/A.
	Performance notes: Read via Config.Battle at use time (live overrides replace the section table); ModeRules
	                  snapshots the values once per battle so a battle never changes rules mid-way.

	Resolution order for one battle (Rules/ModeRules): an event mode's own `durationS` > MODES[mode].<KEY> >
	TIMER_S[battleType] (duration only) > the top-level <KEY>. Random battles use the top-level keys.
]]

local Battle = {
	--- Fixed simulation step rate (Hz). ARCHITECTURE §6.1.
	TICK_RATE = 30,
	--- Per-observer snapshot rate (Hz). ARCHITECTURE §5.2.
	SNAPSHOT_RATE = 20,
	--- Players per team in random battles.
	TEAM_SIZE = 15,
	--- Fallback battle length (s) when no battle type / mode / event sets one. 00-DECISIONS §9 (12:00).
	DURATION_S = 720,
	--- Pre-battle countdown (s): vehicles cannot move or fire, turrets may rotate. 00-DECISIONS §9 / §21 #22 (20 s).
	COUNTDOWN_S = 20,
	--- Remote vehicle interpolation delay on clients (s).
	INTERPOLATION_DELAY_S = 0.1,

	--- Battle length by Random-battle type (s). 00-DECISIONS §9: Standard/Encounter 12:00, Assault 8:00
	--- (O: WoT 15/15/10 min × 0.8). If > 5 % of battles time out, raise to 900 or capture RATE × 1.25.
	TIMER_S = { Standard = 720, Encounter = 720, Assault = 480 },

	--- Lifecycle (00-DECISIONS §9 "Load", §19 "Stale codes"; ARCHITECTURE §2.1).
	--- Preparing (manifest read + map build) longer than this aborts the battle with reason PrepareTimeout (O).
	PREPARE_TIMEOUT_S = 90,
	--- Humans may first arrive at most this long after the battle server was created (the Hub's teleport deadline
	--- is 40 s, so the Hub always gives up first). Later first arrivals are rejected; the slot stays a bot.
	ARRIVAL_WINDOW_S = 45,
	--- The countdown starts when every roster human has arrived and loaded, or this long after MapReady.
	LOAD_TIMEOUT_S = 30,
	--- Ending phase: result banner shown in the battle place before the Results phase (inbox + teleport).
	END_BANNER_S = 6,
	--- Results phase: closes when delivery is confirmed or after this long (O).
	RESULTS_TIMEOUT_S = 60,
	--- Humans that must have arrived when the countdown would start; fewer aborts the battle (TooFewHumans).
	MIN_HUMANS = 1,

	--- Per-mode overrides of the keys above plus flags (booleans default to true when absent):
	---   EARLY_START   countdown may start before LOAD_TIMEOUT_S once everyone loaded
	---   WIPE_VICTORY  destroying every enemy wins
	---   CAPTURE       capture bases are active (needs the battle type's bases on the map)
	---   BOT_TAKEOVER  absent / disconnected / leaving humans are driven by a bot
	---   AFK           AFK warning + takeover + strike
	MODES = {
		--- Random battles: the top-level values.
		Random = {},
		--- Private training rooms (O): friends need longer to load; no AFK strikes in private rooms.
		Training = { LOAD_TIMEOUT_S = 45, AFK = false },
		--- Scripted tutorial vs bots (O): short countdown, 10 min cap, newcomers are never struck.
		Bootcamp = { COUNTDOWN_S = 10, DURATION_S = 600, AFK = false },
		--- Solo map explorer / shooting range (O): no objectives, ends on timeout or when the player leaves.
		Practice = { COUNTDOWN_S = 3, DURATION_S = 1800, WIPE_VICTORY = false, CAPTURE = false, AFK = false },
		--- Event modes: EventModeDefinition.durationS (when set) replaces the battle-type timer.
		Event = {},
	},

	--- Base capture (00-DECISIONS §9 "Capture"; report 04 R7). Per vehicle each tick:
	--- points += RATE[type] · rateMul · dt · min(1, MAX_COUNTED / n), team progress = Σ points (≤ POINTS).
	CAPTURE = {
		POINTS = 100,
		--- Default radius when CaptureBase.radiusM is absent (planar distance, metres).
		RADIUS_M = 50,
		--- Vehicles that add speed; more cappers still earn points but the team rate stays capped.
		MAX_COUNTED = 3,
		--- Points per second per vehicle: 100 s alone / 50 s with two / 33.3 s with three (Encounter ×2).
		RATE = { Standard = 1.0, Encounter = 0.5, Assault = 1.0 },
		--- A base freezes while vehicles of another team are inside (Encounter only, parity).
		CONTESTED_FREEZES = { Standard = false, Encounter = true, Assault = false },
		--- HP damage from an enemy resets that capper's points (parity).
		RESET_ON_HP_DAMAGE = true,
		--- A module crit / crew injury without HP damage also resets (O; tracking a capper resets it).
		RESET_ON_MODULE_CRIT = true,
		--- Stun does not reset (O).
		RESET_ON_STUN = false,
		--- A capper outside the circle keeps its points this long (boundary jitter), then loses them (O).
		LEAVE_GRACE_S = 1.0,
		--- CaptureProgress events are emitted when progress crosses a multiple of this step (and on every drop).
		PROGRESS_EVENT_STEP = 5,
	},

	--- Timer expiry per battle type (00-DECISIONS §9): Standard/Encounter draw, Assault defender win.
	TIMEOUT_RESULT = { Standard = "Draw", Encounter = "Draw", Assault = "DefenderWin" },
	--- Reason reported when the same team wipes the enemy AND completes a capture on one tick (O: "Capture", so the
	--- cappers' Invader/capture credit is kept). Opposite results on one tick are always a "Simultaneous" draw.
	SAME_TICK_WIPE_AND_CAPTURE_REASON = "Capture",

	--- Disconnect / AFK / leaving (00-DECISIONS §9 "Disconnect", "AFK/leave").
	--- Seconds without a connection before a bot takes the vehicle (reconnect allowed until the end).
	DISCONNECT_BOT_DELAY_S = 5,
	--- Seconds without meaningful input (throttle/steer/turret/fire) before the on-screen warning.
	AFK_WARN_S = 60,
	--- Seconds without meaningful input before bot takeover + AFK strike (XP 0 for the battle).
	AFK_TAKEOVER_S = 90,
	--- Strike ladder window (s) and queue lock per strike count within it: 1 → no rewards, 2 → 10 min, 3+ → 60 min.
	AFK_STRIKE_WINDOW_S = 86400,
	AFK_STRIKE_LOCK_S = { 0, 600, 3600 },

	--- Ledger attribution (00-DECISIONS §5 Rewards, §2 Drowning, §7.2 Role Score).
	LEDGER = {
		--- Allies who saw the target at most this long ago share spotting assist (= spotting linger, 10 s).
		ASSIST_SPOT_WINDOW_S = 10,
		--- BattleStats.firstContactDamage window (Role Score "first-3-min dmg").
		FIRST_CONTACT_WINDOW_S = 180,
		--- A fall death without an attacker is credited to the last enemy that damaged the vehicle within this
		--- window (O: ramming someone off a cliff is a kill). Drowning never credits anyone (00-DECISIONS §2).
		FALL_CREDIT_WINDOW_S = 5,
		--- Wheeled vehicles are slowed, not immobilised, by a destroyed side: no tracking assist (O).
		WHEELED_TRACK_ASSIST = false,
	},

	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {
		TICK_RATE = { min = 10, max = 60, integer = true },
		SNAPSHOT_RATE = { min = 5, max = 30, integer = true },
		TEAM_SIZE = { min = 1, max = 15, integer = true },
		DURATION_S = { min = 60, max = 1800, integer = true },
		COUNTDOWN_S = { min = 0, max = 120, integer = true },
		INTERPOLATION_DELAY_S = { min = 0.03, max = 0.5 },
		["TIMER_S.Standard"] = { min = 60, max = 1800, integer = true },
		["TIMER_S.Encounter"] = { min = 60, max = 1800, integer = true },
		["TIMER_S.Assault"] = { min = 60, max = 1800, integer = true },
		PREPARE_TIMEOUT_S = { min = 10, max = 300 },
		ARRIVAL_WINDOW_S = { min = 10, max = 300 },
		LOAD_TIMEOUT_S = { min = 0, max = 300 },
		END_BANNER_S = { min = 0, max = 30 },
		RESULTS_TIMEOUT_S = { min = 5, max = 300 },
		MIN_HUMANS = { min = 0, max = 30, integer = true },
		["MODES.Training.LOAD_TIMEOUT_S"] = { min = 0, max = 300 },
		["MODES.Bootcamp.COUNTDOWN_S"] = { min = 0, max = 120, integer = true },
		["MODES.Bootcamp.DURATION_S"] = { min = 60, max = 3600, integer = true },
		["MODES.Practice.COUNTDOWN_S"] = { min = 0, max = 120, integer = true },
		["MODES.Practice.DURATION_S"] = { min = 60, max = 3600, integer = true },
		["CAPTURE.POINTS"] = { min = 1, max = 1000 },
		["CAPTURE.RADIUS_M"] = { min = 5, max = 200 },
		["CAPTURE.MAX_COUNTED"] = { min = 1, max = 15, integer = true },
		["CAPTURE.RATE.Standard"] = { min = 0, max = 10 },
		["CAPTURE.RATE.Encounter"] = { min = 0, max = 10 },
		["CAPTURE.RATE.Assault"] = { min = 0, max = 10 },
		["CAPTURE.LEAVE_GRACE_S"] = { min = 0, max = 10 },
		["CAPTURE.PROGRESS_EVENT_STEP"] = { min = 1, max = 100, integer = true },
		DISCONNECT_BOT_DELAY_S = { min = 0, max = 60 },
		AFK_WARN_S = { min = 10, max = 600 },
		AFK_TAKEOVER_S = { min = 10, max = 900 },
		AFK_STRIKE_WINDOW_S = { min = 3600, max = 604800, integer = true },
		["LEDGER.ASSIST_SPOT_WINDOW_S"] = { min = 0, max = 60 },
		["LEDGER.FIRST_CONTACT_WINDOW_S"] = { min = 0, max = 900 },
		["LEDGER.FALL_CREDIT_WINDOW_S"] = { min = 0, max = 60 },
	},
}

return Battle
