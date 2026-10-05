-- Types/Battle smoke tests: the ledger contract's internal consistency (event tags, ledger keys covering every
-- report field) and an executable example of the invariants Scoring and the Results UI rely on.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Types = require("@game/ReplicatedStorage/Shared/Types")
local TypeSource = require("./TypeSource")

local SOURCE = TypeSource.read("Battle")

type RewardBreakdown = Types.RewardBreakdown
type DamageEvent = Types.DamageEvent
type BattleEvent = Types.BattleEvent
type BattleStats = Types.BattleStats

-- CreditReport / XpReport field -> ledger line key.
local CREDIT_LINES = {
	battleIncome = "BattleIncome",
	victoryBonus = "VictoryBonus",
	premiumTimeBonus = "PremiumTimeBonus",
	premiumVehicleBonus = "PremiumVehicleBonus",
	robloxPremiumBonus = "RobloxPremiumBonus",
	plusBonus = "PlusBonus",
	eventBonus = "EventBonus",
	awardRewards = "AwardRewards",
	missionRewards = "MissionRewards",
	repairCost = "RepairCost",
	ammoCost = "AmmoCost",
	consumableCost = "ConsumableCost",
	debtWaived = "DebtWaived",
}
local XP_LINES = {
	base = "BaseXP",
	winBonus = "WinBonus",
	survivalBonus = "SurvivalBonus",
	blockedBonus = "BlockedBonus",
	defeatProtection = "DefeatProtection",
	firstWinBonus = "FirstWinBonus",
	premiumTimeBonus = "PremiumTimeXP",
	plusBonus = "PlusXP",
	boosterBonus = "BoosterXP",
	eventBonus = "EventXP",
	freeXp = "FreeXP",
	crewXp = "CrewXP",
}
local CREDIT_TOTALS = { performance = true, gross = true, net = true }
local XP_TOTALS = { firstWinMultiplier = true, total = true }

local function zeroStats(): BattleStats
	return {
		damageDealt = 0,
		damageReceived = 0,
		damageBlocked = 0,
		potentialDamageReceived = 0,
		assistSpotting = 0,
		assistTracking = 0,
		assistStun = 0,
		stuns = 0,
		kills = 0,
		spotted = 0,
		shotsFired = 0,
		hits = 0,
		penetrations = 0,
		criticalHits = 0,
		hitsReceived = 0,
		penetrationsReceived = 0,
		ricochetsReceived = 0,
		nonPensReceived = 0,
		capturePoints = 0,
		defensePoints = 0,
		ramDamageDealt = 0,
		firesStarted = 0,
		distanceM = 0,
		timeAliveS = 0,
		survived = true,
		firstBlood = false,
		firstContactDamage = 0,
		soleSpotterDamaged = 0,
		hitsOnLaterKilled = 0,
	}
end

describe("Types/Battle", function()
	it("BattleEventType lists exactly the BattleEvent tags", function()
		expect(TypeSource.tagsOf(SOURCE, "BattleEvent", "type")).toEqual(
			TypeSource.unionMembers(SOURCE, "BattleEventType")
		)
	end)

	it("every credit and XP report field has a ledger line key", function()
		local keys = {}
		for _, key in TypeSource.unionMembers(SOURCE, "LedgerLineKey") do
			keys[key] = true
		end
		for _, field in TypeSource.fieldNames(SOURCE, "CreditReport") do
			if not CREDIT_TOTALS[field] then
				local key = (CREDIT_LINES :: any)[field]
				expect(key).never.toBeNil()
				expect(keys[key]).toBe(true)
			end
		end
		for _, field in TypeSource.fieldNames(SOURCE, "XpReport") do
			if not XP_TOTALS[field] then
				local key = (XP_LINES :: any)[field]
				expect(key).never.toBeNil()
				expect(keys[key]).toBe(true)
			end
		end
	end)

	it("the zero BattleStats example covers every required field", function()
		expect(TypeSource.sortedKeys(zeroStats() :: any)).toEqual(TypeSource.fieldNames(SOURCE, "BattleStats"))
	end)

	it("example ledger: damage events sum to HP lost and report lines sum to the totals", function()
		-- Two shots on target 7: a penetration and a bounce; the spotter (3) is credited on the damaging hit.
		local events: { DamageEvent } = {
			{
				t = 41.5,
				attacker = 1,
				target = 7,
				kind = "Shell",
				shellId = "iu_45mm_ap",
				shellKind = "AP",
				result = "Penetration",
				damage = 46,
				potentialDamage = 46,
				distanceM = 180,
				modulesHit = { { module = "Engine", damage = 23, state = "Damaged" } },
				crewInjured = {},
				fireStarted = false,
				killed = false,
				assistSpotters = { 3 },
				assistTrackers = {},
				assistStunners = {},
			},
			{
				t = 44.1,
				attacker = 1,
				target = 7,
				kind = "Shell",
				shellId = "iu_45mm_ap",
				shellKind = "AP",
				result = "Ricochet",
				damage = 0,
				potentialDamage = 49,
				modulesHit = {},
				crewInjured = {},
				fireStarted = false,
				killed = false,
				assistSpotters = { 3 },
				assistTrackers = {},
				assistStunners = {},
			},
		}
		local stream: { BattleEvent } = { { type = "Started", t = 0 } }
		local hpLost = 0
		local blocked = 0
		for _, event in events do
			table.insert(stream, { type = "Damage", t = event.t, damage = event })
			hpLost += event.damage
			if event.result ~= "Penetration" then
				blocked += event.potentialDamage
			end
		end
		expect(hpLost).toBe(46)
		expect(blocked).toBe(49)
		expect(#stream).toBe(3)

		local rewards: RewardBreakdown = {
			credits = {
				battleIncome = 12000,
				performance = {
					{ action = "Damage", credits = 9000, xp = 110 },
					{ action = "Assist", credits = 3000, xp = 40 },
				},
				victoryBonus = 6000,
				premiumTimeBonus = 0,
				premiumVehicleBonus = 0,
				robloxPremiumBonus = 0,
				plusBonus = 0,
				eventBonus = 0,
				awardRewards = 0,
				missionRewards = 0,
				repairCost = 1500,
				ammoCost = 100,
				consumableCost = 0,
				debtWaived = 0,
				gross = 18000,
				net = 16400,
			},
			xp = {
				base = 150,
				winBonus = 75,
				survivalBonus = 0,
				blockedBonus = 0,
				defeatProtection = 0,
				firstWinMultiplier = 2,
				firstWinBonus = 225,
				premiumTimeBonus = 0,
				plusBonus = 0,
				boosterBonus = 0,
				eventBonus = 0,
				total = 450,
				freeXp = 8,
				crewXp = 450,
			},
			campaignTokens = 0,
			passPoints = 8,
			lines = {
				{ key = "BattleIncome", currency = "Credits", amount = 12000 },
				{ key = "VictoryBonus", currency = "Credits", amount = 6000 },
				{ key = "RepairCost", currency = "Credits", amount = -1500 },
				{ key = "AmmoCost", currency = "Credits", amount = -100 },
				{ key = "BaseXP", currency = "VehicleXP", amount = 150 },
				{ key = "WinBonus", currency = "VehicleXP", amount = 75 },
				{ key = "FirstWinBonus", currency = "VehicleXP", amount = 225, multiplier = 2 },
				{ key = "FreeXP", currency = "FreeXP", amount = 8 },
				{ key = "CrewXP", currency = "CrewXP", amount = 450 },
				{ key = "PassPoints", currency = "PassPoints", amount = 8 },
			},
		}
		local sums: { [string]: number } = {}
		for _, line in rewards.lines do
			sums[line.currency] = (sums[line.currency] or 0) + line.amount
		end
		expect(sums.Credits).toBe(rewards.credits.net)
		expect(sums.VehicleXP).toBe(rewards.xp.total)
		expect(sums.FreeXP).toBe(rewards.xp.freeXp)
		expect(sums.CrewXP).toBe(rewards.xp.crewXp)
		expect(sums.PassPoints).toBe(rewards.passPoints)
		local performance = 0
		for _, line in rewards.credits.performance do
			performance += line.credits
		end
		expect(performance).toBe(rewards.credits.battleIncome)
	end)

	it("keeps the outcome vocabulary of 00-DECISIONS §9", function()
		expect(TypeSource.unionMembers(SOURCE, "BattleOutcomeKind")).toEqual({ "Defeat", "Draw", "Victory" })
		expect(TypeSource.unionMembers(SOURCE, "BattleEndReason")).toEqual({
			"Aborted",
			"Capture",
			"DefenderHeld",
			"Destruction",
			"Simultaneous",
			"Timeout",
		})
		expect(TypeSource.unionMembers(SOURCE, "DamageKind")).toEqual({
			"AmmoRack",
			"Drown",
			"Fall",
			"Fire",
			"Ram",
			"Shell",
			"Splash",
		})
	end)
end)
