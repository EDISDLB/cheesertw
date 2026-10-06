-- Types/Profile smoke tests: ring caps, and a maxed-out profile built to the v1 shape stays inside the DataStore
-- size budget and survives a JSON round trip (REG-DATA-08 shape check; ProfileSchema owns the runtime validation).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local serde = require("@lune/serde")
local ProfileTypes = require("@game/ReplicatedStorage/Shared/Types/Profile")
local Types = require("@game/ReplicatedStorage/Shared/Types")
local TypeSource = require("./TypeSource")

local SOURCE = TypeSource.read("Profile")
local LIMITS = ProfileTypes.LIMITS

type Profile = Types.Profile
type BattleSummary = Types.BattleSummary
type VehicleRecord = Types.VehicleRecord
type Crew = Types.Crew

local function stats(): Types.BattleStats
	return {
		damageDealt = 2450,
		damageReceived = 1320,
		damageBlocked = 980,
		potentialDamageReceived = 2300,
		assistSpotting = 1200,
		assistTracking = 400,
		assistStun = 0,
		stuns = 0,
		kills = 3,
		spotted = 4,
		shotsFired = 14,
		hits = 11,
		penetrations = 9,
		criticalHits = 3,
		hitsReceived = 8,
		penetrationsReceived = 5,
		ricochetsReceived = 2,
		nonPensReceived = 1,
		capturePoints = 40,
		defensePoints = 25,
		ramDamageDealt = 0,
		firesStarted = 1,
		distanceM = 2140,
		timeAliveS = 412,
		survived = true,
		firstBlood = false,
		firstContactDamage = 600,
		soleSpotterDamaged = 1,
		hitsOnLaterKilled = 2,
		byTargetClass = {
			heavy = { damageDealt = 1600, kills = 2, spotted = 1, assist = 900 },
			medium = { damageDealt = 850, kills = 1, spotted = 3, assist = 700 },
		},
		killedBy = 17,
		deathCause = "Shell",
		roleScore = 1.12,
		teamXpRank = 3,
	}
end

local function summary(i: number): BattleSummary
	return {
		battleId = string.format("b_%032x", i),
		mode = "Random",
		battleType = "Standard",
		mapId = "proving_grounds",
		startedAt = 1790000000 + i * 400,
		durationS = 412,
		vehicleId = "iu_vehicle_" .. i,
		team = 1,
		outcome = "Victory",
		reason = "Destruction",
		botShare = 0.2,
		stats = stats(),
		medals = { { id = "top_gun", count = 1 }, { id = "scout", count = 1 } },
		xp = 1240,
		freeXp = 62,
		creditsNet = 41200,
	}
end

local function vehicleRecord(i: number): VehicleRecord
	return {
		owned = true,
		xp = 123456,
		elite = true,
		acquiredAt = 1790000000,
		soldAt = 0,
		configuration = {
			gun = "iu_gun_" .. i,
			turret = "iu_turret_" .. i,
			engine = "iu_engine_" .. i,
			tracks = "iu_tracks_" .. i,
		},
		ownedModules = { [`iu_gun_{i}_alt`] = true, [`iu_tracks_{i}_alt`] = true },
		equipment = {
			{ slot = 1, id = "rammer_assist_a" },
			{ slot = 2, id = "gyro_stabiliser_a" },
			{ slot = 3, id = "crew_ventilation_a" },
		},
		ammo = { { shell = "iu_shell_ap_" .. i, count = 40 }, { shell = "iu_shell_apcr_" .. i, count = 10 } },
		consumables = {
			{ slot = 1, id = "repair_kit_large" },
			{ slot = 2, id = "med_kit_large" },
			{ slot = 3, id = "auto_extinguisher" },
		},
		autoResupply = { ammo = true, consumables = true, repair = true },
		crewId = "c" .. i,
		customization = {
			paint = "paint_foundry_red",
			camouflage = "camo_ridge",
			emblem = "emblem_anvil",
			attachments = { "attachment_spare_links", "attachment_logs" },
		},
		favorite = false,
		fieldKit = { "fk_a", "fk_b", "fk_a", "fk_b", "fk_a" },
		apexNodes = {},
		lockedUntil = 0,
		stats = {
			battles = 812,
			wins = 431,
			survived = 377,
			damageDealt = 1450000,
			assist = 640000,
			damageBlocked = 380000,
			kills = 905,
			spotted = 1200,
			xp = 980000,
			maxDamage = 6200,
			maxKills = 9,
			maxXp = 3100,
			mastery = 4,
			marks = 3,
			marksProgress = 3120.5,
			firstWinDay = 20500,
		},
	}
end

local function crew(i: number): Crew
	local members = {}
	for slot, role in { "Commander", "Gunner", "Driver", "Loader", "Loader" } do
		local skills = {}
		for s = 1, LIMITS.CREW_SKILLS do
			table.insert(skills, "crew_skill_" .. s)
		end
		table.insert(members, {
			slot = slot,
			role = role :: any,
			also = {},
			name = { first = "Alexandria", last = "Montgomery-Hale", portrait = i * 10 + slot },
			level = 100,
			xp = 372000,
			skills = skills,
		})
	end
	return {
		id = "c" .. i,
		faction = "iron_union",
		class = "heavy",
		trainedFor = "iu_vehicle_" .. i,
		vehicleId = "iu_vehicle_" .. i,
		members = members,
		freeResetUsed = true,
		createdAt = 1790000000,
	}
end

local function maxedProfile(vehicleCount: number): Profile
	local vehicles = {}
	local researchedVehicles = {}
	local researchedModules = {}
	local crews = {}
	for i = 1, vehicleCount do
		local id = "iu_vehicle_" .. i
		vehicles[id] = vehicleRecord(i)
		researchedVehicles[id] = true
		for _, kind in { "gun", "turret", "engine", "tracks" } do
			researchedModules[`iu_{kind}_{i}`] = true
			researchedModules[`iu_{kind}_{i}_alt`] = true
		end
		crews["c" .. i] = crew(i)
	end
	local history = {}
	for i = 1, LIMITS.BATTLE_HISTORY do
		table.insert(history, summary(i))
	end
	local function ring(n: number, prefix: string, width: number): { string }
		local out = {}
		for i = 1, n do
			table.insert(out, prefix .. string.rep("0", width - #tostring(i)) .. i)
		end
		return out
	end
	local achievements = {}
	for i = 1, 250 do
		achievements["achievement_" .. i] = { count = 120, progress = 4500, first = 1790000000, last = 1795000000 }
	end
	local settings = {}
	for i = 1, LIMITS.SETTINGS do
		settings["setting_key_" .. i] = if i % 3 == 0 then true elseif i % 3 == 1 then 0.75 else "value_" .. i
	end
	local profile: Profile = {
		schemaVersion = ProfileTypes.SCHEMA_VERSION,
		userId = 1234567890,
		createdAt = 1790000000,
		updatedAt = 1795000000,
		lastLoginAt = 1795000000,
		loginCount = 4000,
		account = {
			level = 60,
			rank = 15,
			xp = 120000,
			premiumUntil = 1796000000,
			flags = {
				tutorialStep = 12,
				tutorialCompleted = true,
				bootcampCompleted = true,
				colorSchemePrompted = true,
				captionsPrompted = true,
				firstPurchaseOffered = true,
			},
			firstWinResetAt = 1795046400,
			lastPlusGrantDay = 20500,
			plusCrewXpDay = 20500,
			plusCrewXpToday = 1200,
			plusVehicleId = "iu_vehicle_1",
		},
		currencies = {
			credits = 98000000,
			bullion = 25000,
			freeXp = 1500000,
			campaignTokens = 12000,
			eventTokens = { forge_week = 300, ridge_rally = 1200 },
		},
		vehicles = vehicles,
		researchedVehicles = researchedVehicles,
		researchedModules = researchedModules,
		crews = crews,
		nextCrewSerial = vehicleCount + 1,
		inventory = {
			equipment = { rammer_assist_a = 3, gyro_stabiliser_a = 2 },
			consumables = { repair_kit_large = 12 },
			shells = {},
			customization = { paint_foundry_red = 1, camo_ridge = 1 },
			boosters = { xp_booster = 4 },
			crewBooks = { crew_booklet = 9 },
			activeBoosters = {},
		},
		missions = {
			daily = { slots = {}, resetAt = 1795046400, rerollsUsed = 1, bonusUnlocked = false },
			weekly = { slots = {}, resetAt = 1795400000 },
			campaigns = {},
			event = {},
			claimed = ring(LIMITS.CLAIMED_MISSIONS, "mission_", 12),
		},
		pass = { seasonId = "season_1", points = 1800, paid = true, claimed = ring(180, "s1c1:", 4), tokens = 40 },
		events = {
			forge_week = { joinedAt = 1790000000, progress = { stage = 4 }, settledAt = 1790700000 },
			ranked_s1 = {
				joinedAt = 1790000000,
				progress = {},
				ranked = { rank = 7, points = 140, bestRank = 8, battles = 212, wins = 118 },
				settledAt = 0,
			},
		},
		achievements = achievements,
		stats = {
			battles = 25000,
			wins = 13200,
			losses = 11000,
			draws = 800,
			survived = 9800,
			damageDealt = 40000000,
			damageReceived = 30000000,
			damageBlocked = 9000000,
			assistSpotting = 12000000,
			assistTracking = 3000000,
			assistStun = 0,
			kills = 30000,
			spotted = 40000,
			shotsFired = 300000,
			hits = 250000,
			penetrations = 200000,
			capturePoints = 120000,
			defensePoints = 90000,
			xpEarned = 28000000,
			creditsEarned = 900000000,
			maxDamage = 9800,
			maxKills = 12,
			maxXp = 4200,
			distanceM = 9000000,
			timeInBattleS = 9000000,
		},
		battleHistory = history,
		processed = {
			battles = ring(LIMITS.PROCESSED_BATTLES, "battle_", 36),
			receipts = ring(LIMITS.PROCESSED_RECEIPTS, "receipt_", 32),
			requestIds = ring(LIMITS.PROCESSED_REQUEST_IDS, "req_", LIMITS.REQUEST_ID_LENGTH - 4),
		},
		pendingBattles = {},
		rewardInbox = { cursor = 1795000000, lastDrainAt = 1795000000 },
		settings = settings,
		social = {
			favoriteFriends = table.create(LIMITS.FAVORITE_FRIENDS, 9876543210),
			blocked = table.create(LIMITS.BLOCKED, 9876543210),
			recentPlatoonmates = table.create(LIMITS.RECENT_PLATOONMATES, 9876543210),
		},
		store = { purchases = { bullion_pack_s = 4 }, history = {} },
		matchmaking = { mapBlacklist = { "proving_grounds", "ridge_line" }, battleTypeOptOuts = { "Assault" } },
		moderation = { afkStrikes = {}, queueLockedUntil = 0 },
	}
	return profile
end

describe("Types/Profile", function()
	it("exports frozen ring caps that match ARCHITECTURE §7 and 00-DECISIONS §14/§19", function()
		expect(table.isfrozen(ProfileTypes)).toBe(true)
		expect(table.isfrozen(LIMITS)).toBe(true)
		expect(ProfileTypes.SCHEMA_VERSION).toBe(1)
		expect(LIMITS.BATTLE_HISTORY).toBe(20)
		expect(LIMITS.PROCESSED_BATTLES).toBe(200)
		expect(LIMITS.PROCESSED_RECEIPTS).toBe(200)
		expect(LIMITS.PROCESSED_REQUEST_IDS).toBe(50)
		expect(LIMITS.CREW_SKILLS).toBe(5)
		expect(LIMITS.SIZE_TARGET_BYTES < LIMITS.SIZE_WARN_BYTES).toBe(true)
		expect(LIMITS.SIZE_WARN_BYTES < LIMITS.SIZE_FAIL_BYTES).toBe(true)
		-- every cap declared in the type has a value, and vice versa
		expect(TypeSource.sortedKeys(LIMITS :: any)).toEqual(TypeSource.fieldNames(SOURCE, "ProfileLimits"))
	end)

	it("the maxed fixture has exactly the declared shape", function()
		local profile = maxedProfile(1)
		local function check(value: any, typeName: string)
			expect(TypeSource.shapeProblems(value, SOURCE, typeName)).toEqual({})
		end
		check(profile, "Profile")
		check(profile.account, "Account")
		check(profile.account.flags, "AccountFlags")
		check(profile.currencies, "Currencies")
		check(profile.vehicles.iu_vehicle_1, "VehicleRecord")
		check(profile.vehicles.iu_vehicle_1.stats, "VehicleCareerStats")
		check(profile.crews.c1, "Crew")
		check(profile.crews.c1.members[1], "CrewMember")
		check(profile.inventory, "Inventory")
		check(profile.missions, "MissionsState")
		check(profile.pass, "PassState")
		check(profile.stats, "CareerStats")
		check(profile.processed, "ProcessedRings")
		check(profile.rewardInbox, "RewardInboxState")
		check(profile.social, "Social")
		check(profile.store, "StoreState")
		check(profile.moderation, "Moderation")
		check(profile.matchmaking, "MatchmakingPrefs")
		check(profile.events.ranked_s1, "EventState")
		check(profile.events.ranked_s1.ranked :: any, "RankedProgress")
		expect(
			TypeSource.shapeProblems(
				profile.vehicles.iu_vehicle_1.customization :: any,
				TypeSource.read("Vehicle"),
				"CustomizationLoadout"
			)
		).toEqual({})
		expect(TypeSource.shapeProblems(profile.battleHistory[1] :: any, TypeSource.read("Battle"), "BattleSummary")).toEqual({})
		expect(
			TypeSource.shapeProblems(profile.battleHistory[1].stats :: any, TypeSource.read("Battle"), "BattleStats")
		).toEqual({})
	end)

	it(
		"a profile with 150 maxed vehicles and full rings stays under the 512 KB warning and round-trips JSON",
		function()
			local profile = maxedProfile(150)
			local json = serde.encode("json", profile)
			expect(#json).toBeLessThan(LIMITS.SIZE_WARN_BYTES)
			local decoded = serde.decode("json", json)
			expect(decoded).toEqual(profile)
		end
	)

	it("full rings alone stay well inside the 200 KB target", function()
		local profile = maxedProfile(0)
		local json = serde.encode("json", profile)
		expect(#json).toBeLessThan(LIMITS.SIZE_TARGET_BYTES)
	end)
end)
