--!strict
--[[
	Types/Profile — the persistent player profile, schema v1 (DataStore Profiles_v1, key Player_<UserId>).

	Purpose:          Contract between Progression/ProfileSchema (defaults, validateAndRepair, Migrations),
	                  Transactions (pure economic actions), DataService (persistence), RewardService (inbox),
	                  DataSync (client patches), Missions/Achievements and every garage screen.
	Dependencies:     Types/Content, Types/Vehicle, Types/Battle.
	State:            None at runtime except the frozen LIMITS table returned by this module.
	Validation:       ProfileSchema validates/repairs loaded data against this shape and LIMITS.
	Error handling:   N/A.
	Performance notes: Types are erased. Size budget: a maxed-out profile must JSON-encode under 512 KB (target
	                  200 KB, hard fail 2 MB; 00-DECISIONS §19, REG-DATA-08), hence the ring and list caps below.

	Persistence rules (DataStore JSON):
	  * Only strings, finite numbers, booleans and tables. Maps use string keys (content ids, stringified ids);
	    arrays are dense (no holes). No Color3/Vector3/CFrame/Instances.
	  * Timestamps are unix seconds (Clock.wall on the server); 0 = never.
	  * Rings are arrays ordered oldest -> newest; appending past the cap drops from the front.
	  * Every field exists after ProfileSchema.default(); optional (`?`) fields are only those that are genuinely
	    absent in normal play (activeBattle, retrain penalties…).
]]

local Content = require("./Content")
local VehicleTypes = require("./Vehicle")
local BattleTypes = require("./Battle")

type VehicleId = Content.VehicleId
type ModuleId = Content.ModuleId
type ShellId = Content.ShellId
type EquipmentId = Content.EquipmentId
type ConsumableId = Content.ConsumableId
type CrewSkillId = Content.CrewSkillId
type CrewBookId = Content.CrewBookId
type BoosterId = Content.BoosterId
type CustomizationId = Content.CustomizationId
type MissionId = Content.MissionId
type CampaignId = Content.CampaignId
type AchievementId = Content.AchievementId
type EventId = Content.EventId
type SeasonId = Content.SeasonId
type StoreItemId = Content.StoreItemId
type FactionId = Content.FactionId
type MapId = Content.MapId
type BattleType = Content.BattleType
type VehicleClass = Content.VehicleClass
type CrewRole = Content.CrewRole
type Configuration = Content.Configuration

export type UserId = number
export type ProfileVersion = number
export type CrewId = string -- "c<n>" allocated from Profile.nextCrewSerial
export type ProfileCurrency = "credits" | "bullion" | "freeXp" | "campaignTokens"

--------------------------------------------------------------------------------
-- Account and currencies
--------------------------------------------------------------------------------

--- Tutorial / first-launch flags (all false/0 on a new profile).
export type AccountFlags = {
	tutorialStep: number, -- 0 = not started; Tutorial owns the step numbers
	tutorialCompleted: boolean,
	bootcampCompleted: boolean,
	colorSchemePrompted: boolean, -- first-launch colour-blind scheme chooser shown (00-DECISIONS §16)
	captionsPrompted: boolean,
	firstPurchaseOffered: boolean,
}
export type Account = {
	level: number, -- account level (Config.Progression curve)
	rank: number, -- 1..15 (brand-art §7 rank_01..rank_15)
	xp: number, -- account XP toward the next level
	premiumUntil: number, -- Premium Time end (unix s; 0 = none). HULLDOWN Plus is read live, never stored.
	flags: AccountFlags,
	firstWinResetAt: number, -- next UTC reset of first-win-of-the-day
	lastPlusGrantDay: number, -- day index of the last Plus +25 Bullion grant
	plusCrewXpDay: number, -- day index of plusCrewXpToday (Plus: 100 crew XP per 5 min online, <= 3,000 a day)
	plusCrewXpToday: number,
	plusVehicleId: VehicleId?, -- the tech-tree vehicle that gets the Plus +20 % (subscribers only)
}
export type Currencies = {
	credits: number,
	bullion: number,
	freeXp: number,
	campaignTokens: number,
	eventTokens: { [EventId]: number },
}

--------------------------------------------------------------------------------
-- Vehicles (garage)
--------------------------------------------------------------------------------

--- Per-vehicle career stats (Profile/Compare/mastery). Mastery: 0 none, 1 III class, 2 II, 3 I, 4 Ace.
export type VehicleCareerStats = {
	battles: number,
	wins: number,
	survived: number,
	damageDealt: number,
	assist: number,
	damageBlocked: number,
	kills: number,
	spotted: number,
	xp: number,
	maxDamage: number,
	maxKills: number,
	maxXp: number,
	mastery: number,
	marks: number, -- gun marks earned 0..3 (V–XI)
	marksProgress: number, -- EMA of combined damage (00-DECISIONS §14)
	firstWinDay: number, -- day index of the last first-win bonus on this vehicle
}
--- Vehicle record. Exists once the vehicle is researched or owned; kept after selling (XP stays with it).
export type VehicleRecord = {
	owned: boolean,
	xp: number, -- vehicle XP banked on this vehicle
	elite: boolean, -- all modules + child vehicles researched (enables XP conversion, Field Kits)
	acquiredAt: number,
	soldAt: number, -- 0 = never; buyback allowed for 72 h at +10 % (00-DECISIONS §11)
	configuration: Configuration, -- mounted modules (must pass ContentRegistry:checkConfiguration)
	--- Non-stock modules already bought for THIS vehicle (module priceCredits is paid once per vehicle). Mounting a
	--- stock module or one of these is free; mounting another researched module charges its price and adds it here.
	--- Swapping never loses a purchase; selling the vehicle refunds per Config.Economy.
	ownedModules: { [ModuleId]: boolean },
	equipment: { VehicleTypes.EquipmentSlot },
	ammo: { VehicleTypes.AmmoLoad }, -- desired load; resupplied after each battle when autoResupply.ammo
	consumables: { VehicleTypes.ConsumableSlot },
	autoResupply: { ammo: boolean, consumables: boolean, repair: boolean },
	crewId: CrewId?, -- assigned crew (nil = no crew; cannot battle)
	customization: VehicleTypes.CustomizationLoadout,
	favorite: boolean,
	fieldKit: { string }, -- chosen Field Kit option ids (index = level)
	apexNodes: { string }, -- researched Tier XI node ids
	lockedUntil: number, -- in a battle (pendingBattles) until this time (30 min safety, ARCHITECTURE §7)
	stats: VehicleCareerStats,
}

--------------------------------------------------------------------------------
-- Crews
--------------------------------------------------------------------------------

--- Original generated name (never a real person); `portrait` indexes the generated portrait set.
export type CrewName = { first: string, last: string, portrait: number }
--- Crew XP model (00-DECISIONS §12): skills are learned in slot order; slot k costs Config.Progression's k-th perk
--- cost (12k, 24k, 48k, 96k, 192k). `xp` is the member's total crew XP put into skills, so slot k's training is
--- clamp((xp − Σ cost[1..k−1]) / cost[k], 0, 1) — skills work from 1 %, linear. XP beyond the last slot overflows to
--- Free XP 10:1 when it is earned (never stored here).
export type CrewMember = {
	slot: number, -- seat index in the vehicle's crew list
	role: CrewRole,
	also: { CrewRole },
	name: CrewName,
	level: number, -- L, always 100 in v1 (no qualification levels)
	xp: number,
	skills: { CrewSkillId }, -- chosen skills in slot order (<= LIMITS.CREW_SKILLS)
}
export type Crew = {
	id: CrewId,
	faction: FactionId,
	class: VehicleClass,
	trainedFor: VehicleId, -- full efficiency in this vehicle; same faction+class = retrain penalty
	vehicleId: VehicleId?, -- current assignment (nil = barracks)
	members: { CrewMember },
	retrain: { efficiency: number, xpToRecover: number }?, -- credit retrain penalty (0.75 recovering over 20,000 XP)
	freeResetUsed: boolean,
	createdAt: number,
}

--------------------------------------------------------------------------------
-- Inventory
--------------------------------------------------------------------------------

export type ActiveBooster = { id: BoosterId, vehicleId: VehicleId?, expiresAt: number, battlesLeft: number }
export type Inventory = {
	equipment: { [EquipmentId]: number }, -- unmounted counts
	consumables: { [ConsumableId]: number },
	shells: { [ShellId]: number }, -- depot stock beyond vehicle loads
	customization: { [CustomizationId]: number }, -- owned counts (permanent items = 1)
	boosters: { [BoosterId]: number },
	crewBooks: { [CrewBookId]: number },
	activeBoosters: { ActiveBooster }, -- <= LIMITS.ACTIVE_BOOSTERS
}

--------------------------------------------------------------------------------
-- Missions, pass, events, achievements
--------------------------------------------------------------------------------

export type MissionProgress = {
	id: MissionId,
	progress: { number }, -- per MissionDefinition.conditions entry (cumulative counters / best single battle)
	honorsProgress: { number }?,
	completed: boolean,
	completedAt: number,
	claimed: boolean,
	assignedAt: number,
}
export type DailyMissions = {
	slots: { MissionProgress }, -- Easy, Medium, Hard (+ Bonus once all three are complete)
	resetAt: number,
	rerollsUsed: number,
	bonusUnlocked: boolean,
}
export type WeeklyMissions = { slots: { MissionProgress }, resetAt: number }
export type CampaignState = { operation: number, missions: { [MissionId]: MissionProgress } }
export type MissionsState = {
	daily: DailyMissions,
	weekly: WeeklyMissions,
	campaigns: { [CampaignId]: CampaignState },
	event: { [MissionId]: MissionProgress },
	claimed: { MissionId }, -- ring of non-repeatable missions already claimed (LIMITS.CLAIMED_MISSIONS)
}
export type PassState = {
	seasonId: SeasonId?, -- nil when no season is running
	points: number,
	paid: boolean,
	claimed: { string }, -- "<chapterId>:<stage>:<Free|Paid>" keys already claimed
	tokens: number, -- season tokens carried across seasons
}
--- Ranked ladder standing in one Ranked event (index into the mode's RankLadder.ranks, 1 = lowest).
export type RankedProgress = { rank: number, points: number, bestRank: number, battles: number, wins: number }
export type EventState = {
	joinedAt: number,
	progress: { [string]: number }, -- event-owned counters (stage reached, tokens earned…)
	ranked: RankedProgress?, -- Ranked events only
	--- When the end-of-event settlement ran (Ranked finalRewards by bestRank, leftover-token conversion after the
	--- shop closes): unix s, 0 = not yet. The Hub settles once, under the session lock, and never again.
	settledAt: number,
}
export type AchievementProgress = {
	count: number, -- times earned (medals) or tier reached (milestones)
	progress: number, -- current value toward the next threshold
	first: number, -- unix s first earned (0 = never)
	last: number,
}

--------------------------------------------------------------------------------
-- Career stats, history, idempotency
--------------------------------------------------------------------------------

export type CareerStats = {
	battles: number,
	wins: number,
	losses: number,
	draws: number,
	survived: number,
	damageDealt: number,
	damageReceived: number,
	damageBlocked: number,
	assistSpotting: number,
	assistTracking: number,
	assistStun: number,
	kills: number,
	spotted: number,
	shotsFired: number,
	hits: number,
	penetrations: number,
	capturePoints: number,
	defensePoints: number,
	xpEarned: number,
	creditsEarned: number,
	maxDamage: number,
	maxKills: number,
	maxXp: number,
	distanceM: number,
	timeInBattleS: number,
}
--- Idempotency rings (ARCHITECTURE §7, 00-DECISIONS §19).
export type ProcessedRings = {
	battles: { string }, -- battle ids applied from the reward inbox (LIMITS.PROCESSED_BATTLES)
	receipts: { string }, -- Marketplace PurchaseIds granted (LIMITS.PROCESSED_RECEIPTS)
	requestIds: { string }, -- client mutation requestIds (LIMITS.PROCESSED_REQUEST_IDS)
}
--- Vehicle locked for a battle that has not reported yet (unlocked after 30 min).
export type PendingBattle = { battleId: string, vehicleId: VehicleId, lockedAt: number }
--- "Return to battle" target (ARCHITECTURE §2.1).
export type ActiveBattle = {
	battleId: string,
	placeId: number,
	privateServerId: string,
	vehicleId: VehicleId,
	startedAt: number,
}
export type RewardInboxState = {
	cursor: number, -- issuedAt of the newest applied entry
	lastDrainAt: number,
}
export type SettingValue = number | boolean | string
export type Social = {
	favoriteFriends: { UserId }, -- LIMITS.FAVORITE_FRIENDS
	blocked: { UserId }, -- LIMITS.BLOCKED
	recentPlatoonmates: { UserId }, -- ring (LIMITS.RECENT_PLATOONMATES)
}
export type PurchaseRecord = { purchaseId: string, item: StoreItemId, at: number }
export type StoreState = {
	purchases: { [StoreItemId]: number }, -- counts (purchaseLimit enforcement)
	history: { PurchaseRecord }, -- ring (LIMITS.PURCHASE_HISTORY)
}
--- Matchmaking preferences (00-DECISIONS §8): map blacklist (1 slot, 2 with Premium Time, once >= 8 maps exist)
--- and battle-type opt-outs (lower weight, never a split queue).
export type MatchmakingPrefs = {
	mapBlacklist: { MapId }, -- <= LIMITS.MAP_BLACKLIST
	battleTypeOptOuts: { BattleType }, -- Encounter / Assault only
}
export type Moderation = {
	afkStrikes: { number }, -- timestamps of AFK/leave strikes in the last 24 h (00-DECISIONS §9)
	queueLockedUntil: number,
}

--------------------------------------------------------------------------------
-- Profile v1
--------------------------------------------------------------------------------

export type Profile = {
	schemaVersion: ProfileVersion, -- 1
	userId: UserId,
	createdAt: number,
	updatedAt: number,
	lastLoginAt: number,
	loginCount: number,
	account: Account,
	currencies: Currencies,
	vehicles: { [VehicleId]: VehicleRecord },
	researchedVehicles: { [VehicleId]: boolean },
	researchedModules: { [ModuleId]: boolean }, -- global: a module researched once is researched everywhere
	crews: { [CrewId]: Crew },
	nextCrewSerial: number,
	inventory: Inventory,
	missions: MissionsState,
	pass: PassState,
	events: { [EventId]: EventState },
	achievements: { [AchievementId]: AchievementProgress },
	stats: CareerStats,
	battleHistory: { BattleTypes.BattleSummary }, -- ring, newest last (LIMITS.BATTLE_HISTORY)
	processed: ProcessedRings,
	pendingBattles: { PendingBattle }, -- LIMITS.PENDING_BATTLES
	activeBattle: ActiveBattle?,
	rewardInbox: RewardInboxState,
	settings: { [string]: SettingValue }, -- Settings controller owns the keys (LIMITS.SETTINGS)
	social: Social,
	store: StoreState,
	matchmaking: MatchmakingPrefs,
	moderation: Moderation,
}

--- Hard caps (ProfileSchema clamps; Transactions refuse to exceed). Rings drop the oldest entry.
export type ProfileLimits = {
	BATTLE_HISTORY: number,
	PROCESSED_BATTLES: number,
	PROCESSED_RECEIPTS: number,
	PROCESSED_REQUEST_IDS: number,
	PENDING_BATTLES: number,
	CLAIMED_MISSIONS: number,
	PURCHASE_HISTORY: number,
	FAVORITE_FRIENDS: number,
	BLOCKED: number,
	RECENT_PLATOONMATES: number,
	ACTIVE_BOOSTERS: number,
	CREWS: number,
	CREW_SKILLS: number,
	SETTINGS: number,
	AFK_STRIKES: number,
	MAP_BLACKLIST: number,
	REQUEST_ID_LENGTH: number,
	CREW_NAME_LENGTH: number,
	SIZE_TARGET_BYTES: number,
	SIZE_WARN_BYTES: number,
	SIZE_FAIL_BYTES: number,
}

local LIMITS: ProfileLimits = table.freeze({
	BATTLE_HISTORY = 20, -- 00-DECISIONS §14 "last 20 kept"
	PROCESSED_BATTLES = 200, -- ARCHITECTURE §7
	PROCESSED_RECEIPTS = 200,
	PROCESSED_REQUEST_IDS = 50, -- last 50 per session
	PENDING_BATTLES = 10,
	CLAIMED_MISSIONS = 500,
	PURCHASE_HISTORY = 50,
	FAVORITE_FRIENDS = 50,
	BLOCKED = 200,
	RECENT_PLATOONMATES = 20,
	ACTIVE_BOOSTERS = 10,
	CREWS = 400, -- unlimited garage slots; crews are ~0.5 KB each
	CREW_SKILLS = 5, -- perk slots per member (00-DECISIONS §12)
	SETTINGS = 128,
	AFK_STRIKES = 10,
	MAP_BLACKLIST = 2, -- with Premium Time (1 without)
	REQUEST_ID_LENGTH = 40,
	CREW_NAME_LENGTH = 24,
	SIZE_TARGET_BYTES = 200 * 1024,
	SIZE_WARN_BYTES = 512 * 1024,
	SIZE_FAIL_BYTES = 2 * 1024 * 1024,
})

return table.freeze({
	--- Profile schema version written by ProfileSchema.default() for this shape.
	SCHEMA_VERSION = 1,
	LIMITS = LIMITS,
})
