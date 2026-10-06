--!strict
--[[
	Config/Matchmaking — tunables owned by the matchmaking team: templates, tier spread, class caps and mirror,
	platoons, candidate score, relaxation schedule, bot fill, map/battle-type selection, queue hygiene, manifest.

	Purpose:          The single source of matchmaking numbers (00-DECISIONS §8, §19 "Manifest"; research 04-R1…R6;
	                  roster.md §3.4). Read by Shared/Matchmaking (passed in through MatchmakerConfig.settings).
	Dependencies:     Types/Matchmaking (type only).
	State:            Constant table (deep-frozen by Config/init).
	Validation:       BOUNDS declares the live-overridable scalars (Config.applyOverrides); Matchmaking specs assert
	                  every default lies inside its bounds, that TIER_SPREAD reproduces Content/Tiers' ranges and that
	                  TEAM_SIZE equals Config.Battle.TEAM_SIZE. Arrays (TEMPLATES, RELAX_STAGES, TIER_SPREAD) are not
	                  overridable (applyOverrides cannot address array slots): RELAX_TIME_SCALE tunes the schedule.
	Error handling:   N/A.
	Performance notes: Read at use time (live overrides replace the section table); the matchmaker receives the
	                  table per run, so an override applies from the next run.

	B/C legend as in 00-DECISIONS: W = WoT parity, O = OUR DESIGN CHOICE, P = platform fact.
]]

local MatchmakingTypes = require("../Types/Matchmaking")

local Matchmaking: MatchmakingTypes.MatchmakingSettings = {
	--- Vehicles per team in Random battles: 15 v 15 (00-DECISIONS §0, W). Must equal Config.Battle.TEAM_SIZE.
	TEAM_SIZE = 15,
	TIER_MIN = 1,
	TIER_MAX = 11,
	--- Max tier difference a vehicle of tier t meets (index = tier). Two tiers meet iff |a − b| <= min(spread[a],
	--- spread[b]), which yields 00-DECISIONS §8 "Spread" exactly (O·H, §21 #6): I–II own tier only; III–IV ±1;
	--- V–X ±2 and never above X (XI's spread 1 excludes IX); XI only in X–XI. Must agree with the Content/Tiers
	--- `matchmaking` ranges shown in the garage (tested).
	TIER_SPREAD = { 0, 0, 1, 1, 2, 2, 2, 2, 2, 2, 1 },
	--- Per-team templates, top row first, identical for both teams (00-DECISIONS §8 "Templates": 15 · 5/10 · 3/5/7,
	--- weights 1/1/.6 so ±1 battles are preferred; W shapes, O weights). Counts are for TEAM_SIZE; other team sizes
	--- scale proportionally (the bottom row takes the rounding remainder; a template with an empty row is dropped).
	TEMPLATES = {
		{ id = "T1", counts = { 15 }, weight = 1.0 },
		{ id = "T2", counts = { 5, 10 }, weight = 1.0 },
		{ id = "T3", counts = { 3, 5, 7 }, weight = 0.6 },
	},
	--- Per-team class caps for a 15-vehicle team (00-DECISIONS §8 "Caps/team", §21 #5; O·M): LT <= 3, TD <= 4,
	--- SPG <= 2; heavy/medium uncapped. Smaller teams: ceil(cap × size / 15); SPG <= SMALL_TEAM_ARTILLERY_CAP when the
	--- team has <= SMALL_TEAM_SIZE vehicles; SPG 0 in competitive modes. Event modes may override per class.
	CLASS_CAPS = { light = 3, td = 4, artillery = 2 },
	--- Wheeled light tanks per team (counted inside the light cap).
	WHEELED_CAP = 1,
	SMALL_TEAM_SIZE = 10,
	SMALL_TEAM_ARTILLERY_CAP = 1,
	--- Class mirror (00-DECISIONS §8 "Mirror", W 2.0·M): per class |teamA − teamB| <= 0 while the candidate's relax <
	--- CLASS_MIRROR_RELAX_AT, then <= CLASS_MIRROR_TOLERANCE. Bots pick classes that close the mirror.
	CLASS_MIRROR_RELAX_AT = 0.5,
	CLASS_MIRROR_TOLERANCE = 1,
	--- Soft role mirror (00-DECISIONS §8; roster.md §3.2): per class, roles are paired across teams; a pair with the
	--- same role costs EXACT, the same RoleGroup GROUP, otherwise OTHER (summed into roleErr). Never blocks a match.
	ROLE_MATCH = { EXACT = 0, GROUP = 0.5, OTHER = 1 },
	--- Platoons (00-DECISIONS §8 "Platoons", O·M): <= MAX_SIZE players, same tier, <= MAX_ARTILLERY SPG, platoon count
	--- difference between the teams <= MAX_COUNT_DIFF; members always on one team; bots never platooned.
	PLATOON = { MAX_SIZE = 3, MAX_ARTILLERY = 1, MAX_COUNT_DIFF = 1 },
	--- Candidate score (00-DECISIONS §8 "Score", O·M): HUMAN·humans − BOT·bots·(1 − relax) − TEMPLATE·(1 − weight)
	--- − CLASS_ERR·classErr − ROLE_ERR·roleErr − PLATOON·|platoonsA − platoonsB|, refined (O) with
	--- − POSITION·Σ_humans bottomness (0 top row … 1 bottom row: "humans to upper slots")
	--- − BOTTOM_STREAK·(humans with a bottom-tier streak placed on the bottom row)
	--- − HUMAN_IMBALANCE·max(0, |humansA − humansB| − 1).
	SCORE = {
		HUMAN = 10,
		BOT = 6,
		TEMPLATE = 7.5,
		CLASS_ERR = 2,
		ROLE_ERR = 1,
		PLATOON = 1,
		POSITION = 0.5,
		BOTTOM_STREAK = 4,
		HUMAN_IMBALANCE = 2,
	},
	--- After this many bottom-tier battles in a row a player is kept off the bottom row when possible (00-DECISIONS §8).
	BOTTOM_TIER_STREAK_PROTECTION = 2,
	--- Team balance by weights (O): a human weighs 1 + TEAM_WEIGHT_TIER_STEP × (rows below theirs); the greedy fill
	--- puts each ticket on the team with fewer humans, then the lighter team.
	TEAM_WEIGHT_TIER_STEP = 0.25,
	--- Relaxation schedule (00-DECISIONS §8 "Relaxation", O·M), measured on a candidate's OLDEST ticket (the anchor):
	--- 0–10 s strict (no bots, own region) · 10–25 s <= 10 bots, adjacent regions · 25–45 s <= 20 bots, global,
	--- class mirror ±1 (relax >= CLASS_MIRROR_RELAX_AT) · >= 45 s fill everything (>= MIN_HUMANS human).
	--- maxBots is per battle for TEAM_SIZE; other team sizes scale it by size / TEAM_SIZE. regionReach: 0 own
	--- bucket, 1 + REGION_ADJACENT, 2 global; a ticket joins another region's battle only when BOTH its own stage and
	--- the anchor's stage reach that far.
	RELAX_STAGES = {
		{ fromS = 0, relax = 0, maxBots = 0, regionReach = 0 },
		{ fromS = 10, relax = 0.33, maxBots = 10, regionReach = 1 },
		{ fromS = 25, relax = 0.66, maxBots = 20, regionReach = 2 },
		{ fromS = 45, relax = 1, maxBots = 29, regionReach = 2 },
	},
	--- Multiplies every RELAX_STAGES fromS (live tuning knob for the whole schedule).
	RELAX_TIME_SCALE = 1,
	--- "Start now with bots" (00-DECISIONS §8): a ticket flagged startWithBots that has waited this long anchors a
	--- battle with full bot fill (relax 1) immediately; region reach still follows its wait.
	START_WITH_BOTS_AFTER_S = 15,
	--- Every battle has at least this many humans.
	MIN_HUMANS = 1,
	--- Queue hygiene (O): tickets waiting longer are rejected TIMEOUT (the Hub shows "no battle found" and unlocks
	--- the vehicle). Bot fill guarantees a battle at 45 s, so a timeout means no map or bot vehicle fits the tier.
	QUEUE_TIMEOUT_S = 180,
	--- A ticket whose refreshedAt heartbeat (every 30 s, 00-DECISIONS §8) is older than this is STALE (dead Hub).
	STALE_TICKET_S = 75,
	--- enqueuedAt may lie this far in the future (Hub clock skew); further is INVALID.
	FUTURE_SKEW_S = 10,
	--- Max length of ticketId / platoonId (keeps the manifest under MANIFEST.MAX_BYTES; MemoryStore key <= 128).
	TICKET_ID_MAX_LEN = 40,
	--- Max length of a member's opaque loadout snapshot (externalised beyond the manifest budget, never truncated).
	LOADOUT_MAX_BYTES = 2048,
	--- Region buckets and adjacency for the 10–25 s stage (00-DECISIONS §8 "Pool key"; O, tune with ping data).
	REGIONS = { "NA", "SA", "EU", "APAC", "OCE" },
	REGION_ADJACENT = {
		NA = { "SA", "EU" },
		SA = { "NA" },
		EU = { "NA" },
		APAC = { "OCE" },
		OCE = { "APAC" },
	},
	--- Matchmade modes. Tickets of other modes are rejected UNSUPPORTED_MODE. Event modes are added per event by the
	--- caller (Pools.build `modes` from EventModeDefinition: teamSize, competitive, classCaps, tier range).
	MODES = {
		Random = { TEAM_SIZE = 15, BOT_FILL = true, COMPETITIVE = false, RANDOM_BATTLE_TYPES = true },
	},
	--- Bot skill (00-DECISIONS §8 "Bots", O·M): Recruit when the humans' average battles < RECRUIT_MAX_AVG_BATTLES,
	--- else Veteran when the top tier >= VETERAN_MIN_TIER, else Regular. One skill per battle.
	BOT_SKILL = { RECRUIT_MAX_AVG_BATTLES = 20, VETERAN_MIN_TIER = 8 },
	--- Default per-team class mix once the mirror is satisfied (roster.md §3.4 rule 3, sized to supply): selected
	--- by the battle's top tier (first entry with top >= minTier). Bots never add artillery except to mirror a human
	--- SPG (rule 2); classes missing from the pool at a row's tier are never placed there.
	BOT_CLASS_MIX = {
		{ minTier = 8, mix = { medium = 5, heavy = 4, td = 3, light = 3 } },
		{ minTier = 6, mix = { medium = 6, heavy = 3, td = 3, light = 3 } },
		{ minTier = 4, mix = { medium = 7, heavy = 2, td = 3, light = 3 } },
		{ minTier = 2, mix = { medium = 10, light = 3, td = 2 } },
		{ minTier = 1, mix = { medium = 12, light = 3 } },
	},
	--- Tie order when two filler classes are equally short of the mix (artillery is never a filler).
	BOT_FILLER_ORDER = { "medium", "heavy", "td", "light" },
	--- Bot vehicle variety per team (roster.md §3.4 rule 4): beyond SOFT_COPIES copies of one vehicle a pick costs
	--- SOFT_PENALTY (between the GROUP and OTHER role costs, so a same-group alternative wins but a third copy beats a
	--- role from another group); the hard cap is max(HARD_COPIES_MIN, ceil(class bot slots ÷ class vehicles in the
	--- template)), exceeded only when nothing else fits (metrics.varietyOverflows).
	BOT_VARIETY = { SOFT_COPIES = 2, SOFT_PENALTY = 0.75, HARD_COPIES_MIN = 3 },
	--- Vehicles bots may drive (roster.md §3.4: premiums allowed; reward/event vehicles stay rare).
	BOT_ACQUISITIONS = { "TechTree", "Premium" },
	--- Random battle types (00-DECISIONS §8 "Maps/modes", O): Standard .70 / Encounter .20 / Assault .10; Encounter
	--- and Assault only when every vehicle is >= BATTLE_TYPE_MIN_TIER. Opt-outs scale a type's weight by the share of
	--- humans who did not opt out (never a split queue).
	BATTLE_TYPE_WEIGHTS = { Standard = 0.70, Encounter = 0.20, Assault = 0.10 },
	BATTLE_TYPE_MIN_TIER = { Encounter = 4, Assault = 4 },
	--- Map choice after teams (00-DECISIONS §8 "Maps/modes"; 04-R5; REG-MMK-02):
	---   RECENT_PENALTY per occurrence in a human's last RECENT_HISTORY maps (multiplicative weight);
	---   REPEAT_LIMIT: a map a human just played REPEAT_LIMIT times in a row is excluded (pool >= 2 maps);
	---   blacklists count only once the battle-level pool has >= BLACKLIST_MIN_POOL maps, BLACKLIST_SLOTS entries per
	---   human (BLACKLIST_SLOTS_PREMIUM with Premium Time); they are hard exclusions while >= BLACKLIST_HARD_MIN_CANDIDATES
	---   maps remain, else the least-blacklisted maps are used.
	MAP_SELECTION = {
		RECENT_HISTORY = 5,
		RECENT_PENALTY = 0.25,
		REPEAT_LIMIT = 2,
		BLACKLIST_SLOTS = 1,
		BLACKLIST_SLOTS_PREMIUM = 2,
		BLACKLIST_MIN_POOL = 8,
		BLACKLIST_HARD_MIN_CANDIDATES = 3,
	},
	--- Match manifest (00-DECISIONS §19 "Manifest", P·H): serialized size budget (MemoryStore value <= 32 KB; our cap
	--- keeps RU and memory quota low at small CCU). Over budget, loadouts move to per-user keys (extLoadouts).
	MANIFEST = { VERSION = 1, MAX_BYTES = 8192 },

	--- Live-override limits: key path (relative to this section) -> numeric bounds.
	BOUNDS = {
		["CLASS_CAPS.light"] = { min = 0, max = 15, integer = true },
		["CLASS_CAPS.td"] = { min = 0, max = 15, integer = true },
		["CLASS_CAPS.artillery"] = { min = 0, max = 15, integer = true },
		WHEELED_CAP = { min = 0, max = 15, integer = true },
		CLASS_MIRROR_RELAX_AT = { min = 0, max = 1 },
		CLASS_MIRROR_TOLERANCE = { min = 0, max = 3, integer = true },
		["SCORE.HUMAN"] = { min = 0, max = 100 },
		["SCORE.BOT"] = { min = 0, max = 100 },
		["SCORE.TEMPLATE"] = { min = 0, max = 100 },
		["SCORE.CLASS_ERR"] = { min = 0, max = 100 },
		["SCORE.ROLE_ERR"] = { min = 0, max = 100 },
		["SCORE.PLATOON"] = { min = 0, max = 100 },
		["SCORE.POSITION"] = { min = 0, max = 100 },
		["SCORE.BOTTOM_STREAK"] = { min = 0, max = 100 },
		["SCORE.HUMAN_IMBALANCE"] = { min = 0, max = 100 },
		BOTTOM_TIER_STREAK_PROTECTION = { min = 1, max = 20, integer = true },
		RELAX_TIME_SCALE = { min = 0.25, max = 4 },
		START_WITH_BOTS_AFTER_S = { min = 0, max = 120 },
		QUEUE_TIMEOUT_S = { min = 60, max = 600 },
		STALE_TICKET_S = { min = 30, max = 300 },
		["BOT_SKILL.RECRUIT_MAX_AVG_BATTLES"] = { min = 0, max = 1000, integer = true },
		["BOT_SKILL.VETERAN_MIN_TIER"] = { min = 1, max = 12, integer = true },
		["BOT_VARIETY.SOFT_COPIES"] = { min = 1, max = 15, integer = true },
		["BOT_VARIETY.HARD_COPIES_MIN"] = { min = 1, max = 15, integer = true },
		["BATTLE_TYPE_WEIGHTS.Standard"] = { min = 0, max = 1 },
		["BATTLE_TYPE_WEIGHTS.Encounter"] = { min = 0, max = 1 },
		["BATTLE_TYPE_WEIGHTS.Assault"] = { min = 0, max = 1 },
		["MAP_SELECTION.RECENT_PENALTY"] = { min = 0, max = 1 },
		["MAP_SELECTION.BLACKLIST_MIN_POOL"] = { min = 1, max = 100, integer = true },
	},
}

return Matchmaking
