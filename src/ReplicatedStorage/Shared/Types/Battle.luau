--!strict
--[[
	Types/Battle — the BATTLE LEDGER contract: participants, per-participant stats, damage and event streams,
	the battle result and the reward breakdown.

	Purpose:          One shape shared by BattleInstance (producer), Spotting (assists), Battle/Scoring + Economy
	                  (rewards), Missions and Achievements/Medals (consumers of stats and events), the reward inbox
	                  (battle server -> Hub) and the Results UI (lines rendered verbatim, never re-derived).
	Dependencies:     Types/Content.
	State:            None (type-only).
	Validation:       Producers keep the invariants below; Scoring goldens (REG-RES-02) and Invariants.check (ledger
	                  sum = HP lost) test them.
	Error handling:   N/A.
	Performance notes: Erased at runtime. DamageEvent/BattleEvent are appended during the battle (pooled by the
	                  producer if needed); BattleResult is built once at the end.

	Invariants:
	  * Σ DamageEvent.damage over events with target T = T's HP lost; damage to allies is always 0 (friendly fire
	    off, 00-DECISIONS §2) and allies only "consume" shells (result "AllyBlocked").
	  * BattleStats are derived from the event stream; Scoring never reads anything that is not in the ledger.
	  * RewardBreakdown.lines sum per currency to the totals in `credits`/`xp`/`other`, and those totals are exactly
	    what RewardService applies to the profile (the Results screen renders the lines, never recomputes them).
	  * Times `t` are battle seconds since the countdown ended (0 = GO); timestamps (`startedAt`, `issuedAt`) are
	    unix seconds (Clock.wall on the server).
]]

local Content = require("./Content")

type VehicleId = Content.VehicleId
type MapId = Content.MapId
type ShellId = Content.ShellId
type ShellKind = Content.ShellKind
type FactionId = Content.FactionId
type VehicleClass = Content.VehicleClass
type RoleId = Content.RoleId
type CrewRole = Content.CrewRole
type InternalModuleKind = Content.InternalModuleKind
type ConsumableId = Content.ConsumableId
type AchievementId = Content.AchievementId

export type BattleId = string
--- Vehicle entity id inside one battle (also the participant id). Stable for the whole battle.
export type EntityId = number
--- 1 or 2.
export type TeamId = number
export type BattleMode = Content.BattleMode
export type BattleType = Content.BattleType

--------------------------------------------------------------------------------
-- Outcome
--------------------------------------------------------------------------------

export type BattleOutcomeKind = "Victory" | "Defeat" | "Draw"
--- Why the battle ended (00-DECISIONS §9). "DefenderHeld" = Assault timeout (defender wins); "Simultaneous" =
--- double capture / double wipe on the same tick (draw); "Aborted" = server failure (no win/loss recorded).
export type BattleEndReason = "Destruction" | "Capture" | "Timeout" | "DefenderHeld" | "Simultaneous" | "Aborted"
export type TeamOutcome = { team: TeamId, outcome: BattleOutcomeKind }
export type BattleOutcome = {
	winner: TeamId?, -- nil on a draw/abort
	reason: BattleEndReason,
	teams: { TeamOutcome }, -- one entry per team, ascending team id
}

--------------------------------------------------------------------------------
-- Participants and stats
--------------------------------------------------------------------------------

export type BotSkill = "Recruit" | "Regular" | "Veteran"
export type BattleParticipant = {
	participantId: EntityId,
	userId: number?, -- nil for bots
	botId: string?, -- nil for humans (stable per battle, e.g. "bot_07")
	isBot: boolean, -- labelled in every roster (00-DECISIONS §8)
	botSkill: BotSkill?,
	name: string, -- display name at battle start
	team: TeamId,
	platoonId: string?,
	vehicleId: VehicleId,
	tier: number,
	class: VehicleClass,
	role: RoleId,
	faction: FactionId,
	premiumVehicle: boolean,
	--- Share of the battle the human controlled the vehicle (disconnect/AFK hand-over to a bot); rewards scale by it.
	controlShare: number,
}

--- Per-participant counters, all derived from the event stream. Damage values are HP.
export type BattleStats = {
	damageDealt: number,
	damageReceived: number,
	damageBlocked: number, -- potential damage of non-penetrating/ricochet/absorbed hits received
	potentialDamageReceived: number, -- rolled damage of every enemy hit received
	assistSpotting: number, -- damage allies dealt to targets this vehicle spotted (≤ 10 s ago)
	assistTracking: number, -- damage dealt to targets while immobilised by this vehicle
	assistStun: number, -- damage dealt to targets while stunned by this vehicle
	stuns: number, -- enemies stunned
	kills: number,
	spotted: number, -- enemies this vehicle detected FIRST for its team
	shotsFired: number,
	hits: number, -- shells that hit an enemy vehicle
	penetrations: number,
	criticalHits: number, -- hits that damaged/destroyed a module or injured crew
	hitsReceived: number,
	penetrationsReceived: number,
	ricochetsReceived: number,
	nonPensReceived: number, -- non-penetrations + absorbed hits received
	capturePoints: number, -- points contributed to an enemy-base capture
	defensePoints: number, -- enemy capture points reset by hitting cappers
	ramDamageDealt: number,
	firesStarted: number,
	distanceM: number,
	timeAliveS: number,
	survived: boolean,
	firstBlood: boolean, -- this vehicle dealt the battle's first kill
	firstContactDamage: number, -- damage dealt in the first 180 s (Role Score)
	soleSpotterDamaged: number, -- enemies damaged by allies that only this vehicle spotted (Patrol Duty)
	hitsOnLaterKilled: number, -- enemies hit by this vehicle and later destroyed by others (Confederate)
	killedBy: EntityId?,
	deathCause: DamageKind?,
	roleScore: number?, -- filled by Scoring (normalised; 1.0 = class×tier median)
	teamXpRank: number?, -- filled by Scoring (1 = top of the team)
}

--------------------------------------------------------------------------------
-- Damage and the event stream
--------------------------------------------------------------------------------

export type DamageKind = "Shell" | "Splash" | "Fire" | "Ram" | "Fall" | "AmmoRack" | "Drown"
--- Shot outcome against one vehicle (brand-art §10.2). Criticals are flagged by `modulesHit`/`crewInjured`.
export type ShotResultKind =
	"Penetration"
	| "NonPenetration"
	| "Ricochet"
	| "Absorbed" -- stopped by spaced armor / tracks
	| "Splash" -- HE splash without a direct hit
	| "AllyBlocked" -- shell consumed by an ally (0 damage)
export type ModuleHit = { module: InternalModuleKind, damage: number, state: "Ok" | "Damaged" | "Destroyed" }
export type CrewHit = { slot: number, role: CrewRole }

--- One damage application (HP and/or modules) to one target. Fire/ram/fall/drown carry no shell fields.
export type DamageEvent = {
	t: number,
	attacker: EntityId?, -- nil for falls/drowning/self-inflicted
	target: EntityId,
	kind: DamageKind,
	shellId: ShellId?,
	shellKind: ShellKind?,
	result: ShotResultKind?, -- Shell/Splash only
	damage: number, -- HP removed (0 for blocked shots)
	potentialDamage: number, -- rolled damage before armor (feeds damageBlocked)
	distanceM: number?,
	modulesHit: { ModuleHit },
	crewInjured: { CrewHit },
	fireStarted: boolean,
	killed: boolean,
	--- Assist attribution at the moment of damage (00-DECISIONS §5): allies who saw the target <= 10 s ago, whose
	--- track hit immobilised it, or whose shell stunned it. The attacker is never listed.
	assistSpotters: { EntityId },
	assistTrackers: { EntityId },
	assistStunners: { EntityId },
}

export type CaptureBaseId = string
--- Battle event stream (kill feed, damage log, results timeline, missions, medals). Ordered by `t`, then by
--- emission order; deterministic for a given (seed, inputs, content hash).
export type BattleEvent =
	{ type: "Started", t: number }
	| { type: "Spotted", t: number, spotter: EntityId, target: EntityId, first: boolean }
	| { type: "Shot", t: number, shooter: EntityId, shellId: ShellId }
	| { type: "Damage", t: number, damage: DamageEvent }
	| {
		type: "ModuleState",
		t: number,
		target: EntityId,
		module: InternalModuleKind,
		state: "Ok" | "Damaged" | "Destroyed",
		attacker: EntityId?,
	}
	| { type: "CrewInjured", t: number, target: EntityId, slot: number, role: CrewRole, attacker: EntityId? }
	| { type: "Fire", t: number, target: EntityId, burning: boolean, attacker: EntityId? }
	| { type: "Stunned", t: number, target: EntityId, attacker: EntityId, durationS: number }
	| { type: "Destroyed", t: number, target: EntityId, attacker: EntityId?, cause: DamageKind, assisters: { EntityId } }
	| { type: "ConsumableUsed", t: number, participant: EntityId, consumable: ConsumableId }
	| { type: "CaptureProgress", t: number, base: CaptureBaseId, team: TeamId, points: number }
	| { type: "CaptureReset", t: number, base: CaptureBaseId, by: EntityId, capper: EntityId, points: number }
	| { type: "BaseCaptured", t: number, base: CaptureBaseId, team: TeamId }
	| {
		type: "ControlChanged",
		t: number,
		participant: EntityId,
		controller: "Player" | "Bot",
		reason: "Disconnect" | "Reconnect" | "Afk" | "Left" | "Arrived",
	}
	| { type: "Ended", t: number, outcome: BattleOutcome }
export type BattleEventType =
	"Started"
	| "Spotted"
	| "Shot"
	| "Damage"
	| "ModuleState"
	| "CrewInjured"
	| "Fire"
	| "Stunned"
	| "Destroyed"
	| "ConsumableUsed"
	| "CaptureProgress"
	| "CaptureReset"
	| "BaseCaptured"
	| "ControlChanged"
	| "Ended"

--------------------------------------------------------------------------------
-- Rewards (filled by Shared/Battle/Scoring on the battle server)
--------------------------------------------------------------------------------

--- Ledger line keys, in Results "Report" order (00-DECISIONS §14, 05-R12).
export type LedgerLineKey =
	-- credits
	"BattleIncome"
	| "VictoryBonus"
	| "PremiumTimeBonus"
	| "PremiumVehicleBonus"
	| "RobloxPremiumBonus"
	| "PlusBonus"
	| "EventBonus"
	| "AwardRewards"
	| "MissionRewards"
	| "RepairCost"
	| "AmmoCost"
	| "ConsumableCost"
	| "DebtWaived"
	-- xp
	| "BaseXP"
	| "WinBonus"
	| "SurvivalBonus"
	| "BlockedBonus"
	| "DefeatProtection"
	| "FirstWinBonus"
	| "PremiumTimeXP"
	| "PlusXP"
	| "BoosterXP"
	| "EventXP"
	| "FreeXP"
	| "CrewXP"
	-- other
	| "CampaignTokens"
	| "PassPoints"
export type LedgerLine = {
	key: LedgerLineKey,
	currency: Content.Currency | "PassPoints",
	amount: number, -- signed: costs are negative
	multiplier: number?, -- shown as "×2" (first win) when the line is a multiplier step
	detail: string?, -- e.g. mission or medal id
}
--- Performance breakdown of BattleIncome / BaseXP by action (00-DECISIONS §11 XP mix).
export type PerformanceLine = {
	action: "Damage" | "Assist" | "Kills" | "Capture" | "Defense" | "Crits" | "Spotting" | "Blocked",
	credits: number,
	xp: number,
}
export type CreditReport = {
	battleIncome: number, -- Σ performance credits × tier scale × vehicle coefficient
	performance: { PerformanceLine },
	victoryBonus: number,
	premiumTimeBonus: number,
	premiumVehicleBonus: number,
	robloxPremiumBonus: number,
	plusBonus: number,
	eventBonus: number,
	awardRewards: number, -- medal credit rewards
	missionRewards: number, -- 0 from the battle server; the Hub's RewardService evaluates missions against the
	-- inbox entry and fills this (plus "MissionRewards" lines) before showing the report
	repairCost: number, -- positive amounts; subtracted in `net`
	ammoCost: number,
	consumableCost: number,
	debtWaived: number, -- auto-repair floor: part of the costs waived so the balance never goes negative
	gross: number,
	net: number, -- gross − costs + debtWaived (may be negative before the floor; never applied below 0 balance)
}
export type XpReport = {
	base: number, -- Σ action XP × tier scale (win bonus excluded)
	winBonus: number,
	survivalBonus: number,
	blockedBonus: number,
	defeatProtection: number, -- top-5 losing Role Score bonus
	firstWinMultiplier: number, -- 1 or 2 (per vehicle per day)
	firstWinBonus: number,
	premiumTimeBonus: number,
	plusBonus: number,
	boosterBonus: number,
	eventBonus: number,
	total: number, -- vehicle XP credited to the vehicle
	freeXp: number,
	crewXp: number,
}
export type RewardBreakdown = {
	credits: CreditReport,
	xp: XpReport,
	campaignTokens: number,
	passPoints: number,
	lines: { LedgerLine }, -- UI-ready report, generated from the same numbers
}

--- A medal/achievement awarded in this battle.
export type MedalAward = { id: AchievementId, count: number }

--------------------------------------------------------------------------------
-- Results
--------------------------------------------------------------------------------

export type ParticipantResult = {
	participant: BattleParticipant,
	stats: BattleStats,
	medals: { MedalAward },
	rewards: RewardBreakdown?, -- humans only (nil for bots)
}
export type BattleResult = {
	battleId: BattleId,
	mode: BattleMode,
	battleType: BattleType?, -- Random battles
	mapId: MapId,
	startedAt: number, -- unix seconds at GO
	durationS: number,
	outcome: BattleOutcome,
	participants: { ParticipantResult }, -- ascending participantId
	contentHash: string, -- ContentRegistry:contentHash() of the battle server
	buildVersion: string,
	botShare: number, -- 0..1 share of bot slots (leaderboards / pvpOnly achievements exclude > 0.5)
}

--- Trimmed per-player record kept in profile.battleHistory (last 20) and shown on the Results screen.
export type BattleSummary = {
	battleId: BattleId,
	mode: BattleMode,
	battleType: BattleType?,
	mapId: MapId,
	startedAt: number,
	durationS: number,
	vehicleId: VehicleId,
	team: TeamId,
	outcome: BattleOutcomeKind,
	reason: BattleEndReason,
	stats: BattleStats,
	medals: { MedalAward },
	xp: number,
	freeXp: number,
	creditsNet: number,
}

--- One reward-inbox entry (DataStore RewardInbox_v1, key u_<UserId>, <= 20 entries; ARCHITECTURE §7). Written by
--- the battle server before teleporting players back; applied once by the Hub under the session lock.
export type RewardInboxEntry = {
	battleId: BattleId,
	issuedAt: number,
	userId: number,
	summary: BattleSummary,
	rewards: RewardBreakdown,
	consumedAmmo: { { shell: ShellId, count: number } }, -- for auto-resupply
	consumedConsumables: { ConsumableId },
	afkStrike: boolean,
}

return {}
