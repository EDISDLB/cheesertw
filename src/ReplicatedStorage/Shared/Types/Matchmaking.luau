--!strict
--[[
	Types/Matchmaking — the MATCHMAKING contract: queue tickets (Hub QueueService -> Matchmaker), the matchmaker's
	configuration, its output (matches with bot slots, metrics, rejections) and the match manifest (MemoryStore,
	matchmaker -> battle server).

	Purpose:          Shared by Shared/Matchmaking/* (producer), the Hub QueueService / MatchmakerService and the
	                  battle server's manifest reader (consumers). See docs/design/matchmaking.md.
	Dependencies:     Types/Content, Types/Battle (type-only).
	State:            None (type-only).
	Validation:       Tickets.prepare validates every ticket (untrusted MemoryStore data); Manifest.validate checks
	                  manifests on the battle server; Pools.build validates the bot/map pools.
	Error handling:   N/A.
	Performance notes: Erased at runtime.

	Shape notes:
	  * One Ticket = one queue entry = a solo player OR a whole platoon (members 1..PLATOON.MAX_SIZE), so a platoon is
	    claimed atomically (one MemoryStore item, state Q -> M) and can never be split. Each member carries its own
	    vehicle (platoon members drive different vehicles).
	  * Times are unix seconds (Clock.wall on the Hub); `now` is passed into Matchmaker.run, never read.
	  * `mmType` is game.MatchmakingType.Name ("Default", "XboxOnly", "PlayStationOnly"); it is part of the pool key
	    and never relaxed (00-DECISIONS §8).
]]

local Content = require("./Content")
local Battle = require("./Battle")

type VehicleId = Content.VehicleId
type VehicleClass = Content.VehicleClass
type RoleId = Content.RoleId
type FactionId = Content.FactionId
type MapId = Content.MapId
type BattleMode = Content.BattleMode
type BattleType = Content.BattleType
type TeamId = Battle.TeamId
type BotSkill = Battle.BotSkill

--- Region buckets (00-DECISIONS §8 "Pool key"; GetCountryRegionForPlayerAsync mapped by the Hub).
export type RegionBucket = "NA" | "SA" | "EU" | "APAC" | "OCE"
--- game.MatchmakingType.Name of the Hub server that queued the ticket.
export type MatchmakingType = string

--------------------------------------------------------------------------------
-- Tickets (Hub QueueService -> Matchmaker)
--------------------------------------------------------------------------------

--- The queued vehicle, snapshotted (and locked) by the Hub at enqueue.
export type TicketVehicle = {
	defId: VehicleId,
	tier: number, -- 1..11
	class: VehicleClass,
	role: RoleId, -- must belong to `class` ("<class>_<role>")
	faction: FactionId,
	wheeled: boolean?, -- Wheeled mechanic (light only; WHEELED_CAP per team)
}

export type TicketMember = {
	userId: number,
	vehicle: TicketVehicle,
	--- Account Random battles played; the match's average below BOT_SKILL.RECRUIT_MAX_AVG_BATTLES gives Recruit bots.
	--- nil = experienced.
	battles: number?,
	--- Consecutive battles at the bottom row of a multi-tier template (BOTTOM_TIER_STREAK_PROTECTION).
	bottomTierStreak: number?,
	--- Maps of the member's last battles, newest LAST (MAP_SELECTION.RECENT_HISTORY used).
	recentMaps: { MapId }?,
	--- Profile.matchmaking.mapBlacklist; only the first BLACKLIST_SLOTS (BLACKLIST_SLOTS_PREMIUM with Premium Time)
	--- entries count.
	mapBlacklist: { MapId }?,
	premiumTime: boolean?,
	battleTypeOptOuts: { BattleType }?, -- Encounter / Assault opt-outs (lower weight, never a split queue)
	--- Opaque compact loadout snapshot (Hub codec, ContentRegistry ordinals), copied verbatim into the manifest.
	loadout: string?,
}

export type TicketFlags = {
	--- "Start now with bots" (00-DECISIONS §8): honoured from START_WITH_BOTS_AFTER_S of waiting.
	startWithBots: boolean?,
}

export type Ticket = {
	ticketId: string, -- unique; <= TICKET_ID_MAX_LEN chars
	members: { TicketMember }, -- 1 = solo; 2..PLATOON.MAX_SIZE = platoon (same tier, <= 1 SPG)
	platoonId: string?, -- platoon badge id (BattleParticipant.platoonId); <= TICKET_ID_MAX_LEN chars
	mode: BattleMode,
	region: RegionBucket,
	mmType: MatchmakingType,
	hubJobId: string?, -- the Hub server that owns the players (teleport / notify)
	enqueuedAt: number, -- unix s; kept across teleport-failure re-queues (priority)
	refreshedAt: number?, -- last heartbeat (unix s); older than STALE_TICKET_S = stale. nil = not checked
	flags: TicketFlags?,
}

--- Why a ticket was dropped from the pool (the caller removes it from MemoryStore and notifies the Hub).
export type RejectReason =
	"INVALID" -- malformed, unknown class/region, platoon rules broken, class banned in the mode
	| "UNSUPPORTED_MODE" -- no MODES entry for ticket.mode
	| "DUPLICATE_TICKET" -- several different tickets share one ticketId (identical copies are merged silently)
	| "DUPLICATE_MEMBER" -- a member is also in a newer ticket (the newest ticket wins)
	| "STALE" -- no heartbeat for STALE_TICKET_S
	| "TIMEOUT" -- waited longer than QUEUE_TIMEOUT_S
export type RejectedTicket = {
	ticketId: string, -- tostring of whatever was there when the id itself is invalid
	reason: RejectReason,
	detail: string,
	ticket: any, -- the input value
}

--------------------------------------------------------------------------------
-- Configuration (built once by Matchmaking/Pools from Config.Matchmaking + content)
--------------------------------------------------------------------------------

export type TemplateSpec = { id: string, counts: { number }, weight: number }
export type RelaxStageSpec = { fromS: number, relax: number, maxBots: number, regionReach: number }
export type ClassMixSpec = { minTier: number, mix: { [string]: number } }
export type ModeSpec = {
	TEAM_SIZE: number,
	BOT_FILL: boolean, -- labelled bots may fill (false: humans only)
	COMPETITIVE: boolean, -- artillery banned, class mirror exact
	RANDOM_BATTLE_TYPES: boolean, -- Standard / Encounter / Assault by BATTLE_TYPE_WEIGHTS (false: Standard only)
}

--- The Config.Matchmaking section (see Config/Matchmaking.luau for every key's meaning and source).
export type MatchmakingSettings = {
	TEAM_SIZE: number,
	TIER_MIN: number,
	TIER_MAX: number,
	TIER_SPREAD: { number },
	TEMPLATES: { TemplateSpec },
	CLASS_CAPS: { [string]: number },
	WHEELED_CAP: number,
	SMALL_TEAM_SIZE: number,
	SMALL_TEAM_ARTILLERY_CAP: number,
	CLASS_MIRROR_RELAX_AT: number,
	CLASS_MIRROR_TOLERANCE: number,
	ROLE_MATCH: { EXACT: number, GROUP: number, OTHER: number },
	PLATOON: { MAX_SIZE: number, MAX_ARTILLERY: number, MAX_COUNT_DIFF: number },
	SCORE: {
		HUMAN: number,
		BOT: number,
		TEMPLATE: number,
		CLASS_ERR: number,
		ROLE_ERR: number,
		PLATOON: number,
		POSITION: number,
		BOTTOM_STREAK: number,
		HUMAN_IMBALANCE: number,
	},
	BOTTOM_TIER_STREAK_PROTECTION: number,
	TEAM_WEIGHT_TIER_STEP: number,
	RELAX_STAGES: { RelaxStageSpec },
	RELAX_TIME_SCALE: number,
	START_WITH_BOTS_AFTER_S: number,
	MIN_HUMANS: number,
	QUEUE_TIMEOUT_S: number,
	STALE_TICKET_S: number,
	FUTURE_SKEW_S: number,
	TICKET_ID_MAX_LEN: number,
	LOADOUT_MAX_BYTES: number,
	REGIONS: { string },
	REGION_ADJACENT: { [string]: { string } },
	MODES: { [string]: ModeSpec },
	BOT_SKILL: { RECRUIT_MAX_AVG_BATTLES: number, VETERAN_MIN_TIER: number },
	BOT_CLASS_MIX: { ClassMixSpec },
	BOT_FILLER_ORDER: { string },
	BOT_VARIETY: { SOFT_COPIES: number, SOFT_PENALTY: number, HARD_COPIES_MIN: number },
	BOT_ACQUISITIONS: { string },
	BATTLE_TYPE_WEIGHTS: { [string]: number },
	BATTLE_TYPE_MIN_TIER: { [string]: number },
	MAP_SELECTION: {
		RECENT_HISTORY: number,
		RECENT_PENALTY: number,
		REPEAT_LIMIT: number,
		BLACKLIST_SLOTS: number,
		BLACKLIST_SLOTS_PREMIUM: number,
		BLACKLIST_MIN_POOL: number,
		BLACKLIST_HARD_MIN_CANDIDATES: number,
	},
	MANIFEST: { VERSION: number, MAX_BYTES: number },
	BOUNDS: { [string]: { min: number?, max: number?, integer: boolean? } },
}

--- A vehicle bots may drive (Pools.fromContent: not hidden, acquisition in BOT_ACQUISITIONS).
export type BotVehicle = {
	defId: VehicleId,
	tier: number,
	class: VehicleClass,
	role: RoleId,
	faction: FactionId,
	wheeled: boolean,
	premium: boolean,
}
--- A map as the matchmaker sees it (Pools.fromContent from MapDefinition).
export type MapEntry = {
	id: MapId,
	tierMin: number,
	tierMax: number,
	battleTypes: { BattleType },
	modes: { BattleMode },
	weight: number, -- relative pick weight (default 1)
}
--- Per-mode rules, resolved from Config.Matchmaking.MODES plus caller overrides (event modes).
export type ModeRules = {
	teamSize: number,
	botFill: boolean,
	competitive: boolean,
	randomBattleTypes: boolean,
	classCaps: { [string]: number }?, -- per-team caps overriding the scaled defaults (0 = banned)
	tierMin: number?,
	tierMax: number?,
}
--- Pool index: [tier][class index] -> vehicles sorted by defId (class order = Rules.CLASSES).
export type VehicleIndex = { [number]: { { BotVehicle } } }

export type MatchmakerConfig = {
	settings: MatchmakingSettings,
	vehicles: { BotVehicle }, -- sorted by defId
	maps: { MapEntry }, -- sorted by id
	roleGroups: { [string]: string }, -- RoleId -> RoleDefinition.group (soft role mirror)
	modes: { [string]: ModeRules },
	index: VehicleIndex,
}

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

export type BotSlot = {
	botId: string, -- "bot_01".. unique per match (BattleParticipant.botId)
	team: TeamId,
	defId: VehicleId,
	tier: number,
	class: VehicleClass,
	role: RoleId,
	faction: FactionId,
	wheeled: boolean,
	skill: BotSkill,
	mirror: boolean, -- added to complete the class mirror (else filler from BOT_CLASS_MIX)
}

export type MatchTeam = {
	team: TeamId,
	tickets: { Ticket }, -- the validated input tickets, oldest first
	bots: { BotSlot },
	humans: number,
	platoons: number,
}

export type Match = {
	matchId: string, -- 16 hex chars
	mode: BattleMode,
	battleType: BattleType,
	mapId: MapId,
	mmType: MatchmakingType,
	region: RegionBucket, -- the oldest ticket's region (server placement hint)
	templateId: string,
	teamSize: number,
	tiers: { number }, -- per template row, top first
	tierBand: { min: number, max: number },
	teams: { MatchTeam }, -- exactly 2, teams[i].team == i
	botSkill: BotSkill,
	createdAt: number, -- = now
	seed: number, -- u32 battle seed (bot AI, cosmetic variant)
	anchorTicketId: string, -- the oldest ticket (relaxation is measured on it)
	waitS: number, -- the anchor's wait
	stage: number, -- RELAX_STAGES index applied
	relax: number,
	startNow: boolean, -- formed by a "Start now with bots" ticket
	classTolerance: number, -- class mirror tolerance applied (0 or CLASS_MIRROR_TOLERANCE)
	humans: number,
	bots: number,
	classErr: number, -- Σ_class |A − B| over the final rosters
	roleErr: number, -- soft role mirror error over the final rosters
	score: number,
}

export type MatchmakerMetrics = {
	ticketsIn: number,
	validTickets: number,
	rejected: number,
	rejectedByReason: { [string]: number },
	partitions: number,
	matches: number,
	matchedTickets: number,
	matchedPlayers: number,
	botsAdded: number,
	remainingTickets: number,
	remainingPlayers: number,
	oldestRemainingWaitS: number,
	anchorsTried: number,
	candidatesEvaluated: number,
	candidatesPruned: number,
	varietyOverflows: number, -- bot picks that had to exceed the per-vehicle copy cap
}

export type MatchmakerResult = {
	matches: { Match },
	remaining: { Ticket }, -- valid, unmatched, oldest first (stay queued)
	rejected: { RejectedTicket },
	metrics: MatchmakerMetrics,
}

--------------------------------------------------------------------------------
-- Manifest (MemoryStore HashMap `match`/<privateServerId>, <= MANIFEST.MAX_BYTES serialized)
--------------------------------------------------------------------------------

--- Wire format: readable header, compact repeated entries (30 humans + 30 bots must fit 8 KB with loadouts).
--- Consumers use Manifest.findMember / members / bots instead of reading entries directly.
export type ManifestMember = {
	u: number, -- userId
	v: VehicleId, -- vehicle
	t: number, -- tier
	l: string?, -- loadout (absent when externalised: extLoadouts)
}
export type ManifestTicket = {
	id: string, -- ticketId
	p: string?, -- platoonId
	m: { ManifestMember },
}
export type ManifestBot = {
	id: string, -- botId
	v: VehicleId,
	t: number,
}
export type ManifestTeam = { tickets: { ManifestTicket }, bots: { ManifestBot } }
export type Manifest = {
	version: number,
	matchId: string,
	mode: BattleMode,
	battleType: BattleType,
	mapId: MapId,
	mmType: MatchmakingType,
	region: string,
	template: string,
	teamSize: number,
	tierBand: { min: number, max: number },
	createdAt: number, -- unix s (integer)
	botSeed: number,
	botSkill: BotSkill,
	extLoadouts: boolean?, -- loadouts moved to per-user keys (overflow strategy, docs/design/matchmaking.md §8)
	placeId: number?,
	term: number?, -- leader lease term that wrote it
	teams: { ManifestTeam }, -- exactly 2
}
export type ManifestBuild = {
	manifest: Manifest,
	json: string, -- deterministic encoding used for the size measurement
	bytes: number,
	--- userId (decimal string) -> loadout, present when loadouts were externalised to fit MAX_BYTES.
	externalLoadouts: { [string]: string }?,
}
--- One human of a manifest (battle-server member lookup).
export type ManifestMemberInfo = {
	userId: number,
	team: TeamId,
	ticketId: string,
	platoonId: string?,
	vehicleId: VehicleId,
	tier: number,
	loadout: string?,
	loadoutExternal: boolean, -- read the loadout from the per-user key instead
}
export type ManifestBotInfo = { botId: string, team: TeamId, vehicleId: VehicleId, tier: number, skill: BotSkill }
export type ManifestExpect = { matchId: string?, mmType: MatchmakingType? }

return {}
