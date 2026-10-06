-- ContentRegistry: getters and derived views on the shipped content, and proof that EVERY validator class fires
-- (each case mutates a copy of the shipped bundle + valid fixtures and expects a specific issue code/path).
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ContentRegistry = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

type Issue = ContentRegistry.ContentIssue

local function report(bundle: any, options: any?): ({ Issue }, { Issue })
	local result = ContentRegistry.fromBundle(bundle):validate(options)
	local value = if result.ok then result.value else result.detail
	return value.errors, value.warnings
end

local function hasIssue(list: { Issue }, code: string, pathPart: string?, messagePart: string?): boolean
	for _, issue in list do
		if
			issue.code == code
			and (pathPart == nil or string.find(issue.path, pathPart, 1, true) ~= nil)
			and (messagePart == nil or string.find(issue.message, messagePart, 1, true) ~= nil)
		then
			return true
		end
	end
	return false
end

local function find(list: { any }, id: any): any
	for _, def in list do
		if def.id == id or def.tier == id then
			return def
		end
	end
	error(`fixture: no definition {tostring(id)}`, 2)
end

-- Valid definitions for every registry that ships empty, so their validators can be proven too.
local function addFixtures(b: any)
	table.insert(b.equipment, {
		id = "rammer_assist_c",
		name = "Rammer Assist",
		description = "Reload time -10 %.",
		icon = "equipment/rammer",
		categories = { "Firepower" },
		grade = "Standard",
		tiers = { min = 2, max = 4 },
		exclusiveGroup = "rammer",
		effects = { { stat = "reloadTime", op = "mul", value = 0.90 } },
		categorySlotEffects = { { stat = "reloadTime", op = "mul", value = 0.885 } },
		compatibility = { excludeReload = { "Magazine" } },
		price = { credits = 25000 },
	})
	table.insert(b.equipment, {
		id = "cam_netting_c",
		name = "Cam Netting",
		description = "Camouflage bonus after 3 s stationary.",
		icon = "equipment/camo_net",
		categories = { "Scouting" },
		grade = "Standard",
		tiers = { min = 2, max = 4 },
		exclusiveGroup = "cam_net",
		effects = { { stat = "camoNet", op = "add", value = 0.10, condition = "StationaryArmed" } },
		effectsByClass = { td = { { stat = "camoNet", op = "add", value = 0.15, condition = "StationaryArmed" } } },
		price = { credits = 25000 },
	})
	table.insert(b.consumables, {
		id = "repair_kit",
		name = "Repair Kit",
		description = "Repairs all modules.",
		icon = "consumables/repair_kit",
		kind = "RepairKit",
		activation = "Manual",
		cooldownS = 90,
		repairs = { modules = true },
		exclusiveGroup = "repair",
		price = { credits = 3000 },
	})
	table.insert(b.consumables, {
		id = "auto_extinguisher",
		name = "Automatic Extinguisher",
		description = "Puts out fires 0.5 s after they start.",
		icon = "consumables/extinguisher_auto",
		kind = "Extinguisher",
		activation = "Automatic",
		cooldownS = 60,
		triggerDelayS = 0.5,
		repairs = { fire = true },
		passiveEffects = { { stat = "fireChance", op = "mul", value = 0.9 } },
		exclusiveGroup = "fire",
		price = { credits = 20000, bullion = 100 },
	})
	table.insert(b.consumables, {
		id = "smoke_screen",
		name = "Smoke Screen",
		description = "Event mode: blocks sight lines for 20 s.",
		icon = "consumables/smoke",
		kind = "Smoke",
		activation = "Manual",
		cooldownS = 60,
		charges = 2,
		durationS = 20,
		effects = { { stat = "viewRange", op = "mul", value = 0.7 } },
		exclusiveGroup = "smoke",
		eventOnly = true,
		price = { credits = 5000 },
	})
	table.insert(b.crewSkills, {
		id = "snap_shot",
		name = "Snap Shot",
		description = "Turret-traverse bloom -7.5 %.",
		icon = "crew/gunner",
		roles = { "Gunner" },
		kind = "Individual",
		effects = { { stat = "bloomTurretTraverse", op = "mul", value = 0.925 } },
	})
	table.insert(b.crewBooks, {
		id = "crew_booklet",
		name = "Crew Booklet",
		description = "+5,000 crew XP to every member.",
		icon = "crew/commander",
		xpPerMember = 5000,
		price = { credits = 60000 },
	})
	table.insert(b.boosters, {
		id = "xp_booster",
		name = "XP Booster",
		description = "+50 % vehicle XP for 2 hours.",
		icon = "currency/vehicle_xp",
		target = "VehicleXP",
		multiplier = 1.5,
		durationS = 7200,
	})
	table.insert(b.customization, {
		id = "paint_foundry_red",
		name = "Foundry Red",
		icon = "factions/iron_union",
		kind = "Paint",
		rarity = "uncommon",
		colors = { Color3.fromHex("#8A3B26") },
		camoBonus = true,
		scope = { factions = { "iron_union" }, vehicles = { "iu_kolmal" } },
		source = "Store",
		price = { credits = 50000 },
	})
	table.insert(b.missions, {
		id = "daily_hold_the_line",
		name = "Hold the line",
		description = "Deal and block 1,500 HP in one battle.",
		cadence = "Daily",
		difficulty = "Medium",
		match = "All",
		conditions = { { stat = "damageDealtPlusBlocked", atLeast = 1500, aggregate = "SingleBattle" } },
		scope = { classes = { "heavy", "medium" }, minTier = 1, maxTier = 11, maps = { "proving_grounds" } },
		rewards = {
			{ kind = "Credits", amount = 3000 },
			{ kind = "FreeXP", amount = 300 },
			{ kind = "Equipment", id = "rammer_assist_c", amount = 1 },
		},
		honors = {
			match = "All",
			conditions = { { stat = "kills", atLeast = 2, aggregate = "SingleBattle" } },
			rewards = { { kind = "CampaignTokens", amount = 10 } },
		},
		scaleRewardsByTier = true,
	})
	table.insert(b.missions, {
		id = "forge_week_daily",
		name = "Forge week",
		description = "Win a battle in an Iron Union vehicle.",
		cadence = "Event",
		match = "All",
		conditions = { { stat = "wins", atLeast = 1, aggregate = "Cumulative" } },
		scope = { factions = { "iron_union" } },
		rewards = { { kind = "EventTokens", id = "forge_week", amount = 50 } },
		eventId = "forge_week",
	})
	table.insert(b.achievements, {
		id = "top_gun",
		name = "Top Gun",
		description = "Destroy the most enemies on your team, at least 6.",
		icon = "classes/heavy",
		category = "BattleHero",
		kind = "BattleMedal",
		rule = "mostOnTeam",
		stat = "kills",
		params = { min = 6 },
		repeatable = true,
		rarity = "rare",
		rewards = { { kind = "CampaignTokens", amount = 10 } },
	})
	table.insert(b.achievements, {
		id = "veteran",
		name = "Veteran",
		description = "Fight many battles.",
		icon = "ranks/rank_05",
		category = "Milestone",
		kind = "Milestone",
		rule = "threshold",
		stat = "battles",
		thresholds = { 100, 1000, 10000 },
		rarity = "common",
		rewards = {},
	})
	table.insert(b.store, {
		id = "bullion_pack_s",
		name = "Bullion, small pack",
		description = "250 Bullion.",
		kind = "BullionPack",
		robux = { kind = "DeveloperProduct", productId = 1 },
		grants = { { kind = "Bullion", amount = 250 } },
	})
	table.insert(b.store, {
		id = "forge_week_paint",
		name = "Foundry Red",
		description = "Event paint.",
		kind = "Customization",
		price = { eventTokens = { eventId = "forge_week", amount = 500 } },
		grants = { { kind = "Customization", id = "paint_foundry_red", amount = 1 } },
	})
	table.insert(b.store, {
		id = "season_pass_1",
		name = "Season Pass",
		description = "Unlocks the paid track.",
		kind = "SeasonPass",
		price = { bullion = 1000 },
		grants = {},
	})
	table.insert(b.events, {
		id = "forge_week",
		name = "Forge Week",
		description = "Triple first-win XP.",
		kind = "XpFever",
		startsAt = 1790000000,
		endsAt = 1790604800,
		missions = { "forge_week_daily" },
		modifiers = { firstWinMul = 3 },
		shop = { "forge_week_paint" },
		modes = {
			{
				id = "forge_brawl",
				name = "Forge Brawl",
				baseMode = "Event",
				teamSize = 7,
				maps = { "proving_grounds" },
				abilities = {
					{
						id = "smoke_screen",
						name = "Smoke screen",
						kind = "Smoke",
						cooldownS = 60,
						radiusM = 20,
						durationS = 20,
					},
				},
			},
		},
	})
	table.insert(b.events, {
		id = "ranked_s1",
		name = "Ridge League, season 1",
		description = "7 v 7 competitive season.",
		kind = "Ranked",
		startsAt = 1790000000,
		endsAt = 1794838400,
		missions = {},
		modes = {
			{
				id = "ridge_league",
				name = "Ridge League",
				baseMode = "Event",
				teamSize = 7,
				maps = { "proving_grounds" },
				tierRange = { min = 1, max = 3 },
				battleTypes = { "Standard" },
				competitive = true,
				classCaps = { artillery = 0, light = 2 },
				ladder = {
					ranks = {
						{ id = "recruit", name = "Recruit", pointsToAdvance = 100 },
						{ id = "veteran", name = "Veteran", pointsToAdvance = 200, protected = true },
						{
							id = "marshal",
							name = "Marshal",
							pointsToAdvance = 0,
							rewards = { { kind = "CampaignTokens", amount = 100 } },
						},
					},
					points = {
						{ maxTeamRank = 3, win = 12, loss = 0 },
						{ maxTeamRank = 7, win = 8, loss = -4 },
					},
					finalRewards = { { kind = "Bullion", amount = 500 } },
				},
			},
		},
	})
	table.insert(b.seasons, {
		id = "season_1",
		name = "Season 1: Ridge Line",
		startsAt = 1790000000,
		endsAt = 1794838400,
		chapters = {
			{
				id = "s1c1",
				name = "Chapter 1",
				stages = 30,
				pointsPerStage = 30,
				rewards = {
					{ stage = 1, track = "Free", rewards = { { kind = "Credits", amount = 5000 } } },
					{ stage = 30, track = "Paid", rewards = { { kind = "Booster", id = "xp_booster", amount = 2 } } },
				},
				finalReward = { { kind = "CrewBook", id = "crew_booklet", amount = 1 } },
			},
		},
		pointsByRank = {
			{ maxTeamRank = 3, win = 8, loss = 6 },
			{ maxTeamRank = 10, win = 6, loss = 4 },
			{ maxTeamRank = 15, win = 3, loss = 2 },
		},
		pointsPerDailyMission = 15,
		paidUnlock = "season_pass_1",
	})
end

local function fixtureBundle(): any
	local b = ContentRegistry.shippedBundle() :: any
	addFixtures(b)
	return b
end

-- A second, premium Iron Union vehicle copied from the Kolmal (used by acquisition cases).
local function addPremium(b: any): any
	local premium = table.clone(find(b.vehicles, "iu_kolmal"))
	premium.id = "iu_premium_two"
	premium.name = "Kolmal Premium"
	premium.shortName = "Kolmal P"
	premium.tier = 2
	premium.acquisition = "Premium"
	premium.moduleTree = {}
	premium.unlocks = {}
	premium.modules = {
		guns = { "iu_gun_45mm" },
		turrets = { "iu_turret_kolmal" },
		engines = { "iu_engine_d120" },
		tracks = { "iu_tracks_kolmal" },
	}
	premium.stock = premium.top
	premium.price = { bullion = 250 }
	premium.researchXp = nil
	premium.tree = { row = 6 }
	table.insert(b.vehicles, premium)
	return premium
end

-- A Tier XI Apex built as an Event vehicle (no research path needed): one configuration, one signature, the
-- 6 small / 3 large / 1 final node track. Its Tier I modules raise TIER_RANGE warnings, never errors.
local function addApex(b: any): any
	local apex = table.clone(find(b.vehicles, "iu_kolmal"))
	apex.id = "iu_apex"
	apex.tier = 11
	apex.acquisition = "Event"
	apex.modules = {
		guns = { "iu_gun_45mm" },
		turrets = { "iu_turret_kolmal" },
		engines = { "iu_engine_d120" },
		tracks = { "iu_tracks_kolmal" },
	}
	apex.stock = apex.top
	apex.moduleTree = {}
	apex.unlocks = {}
	apex.price = {}
	apex.researchXp = nil
	apex.tree = { row = 7 }
	apex.mechanics = { { kind = "ChargedShot", chargeTimeS = 1.5, effect = "Accuracy", dispersionMul = 0.6 } }
	local nodes = {}
	for i = 1, 6 do
		table.insert(nodes, { id = `small_{i}`, name = "Small", kind = "Small", xp = 4000, effects = {} })
	end
	for i = 1, 3 do
		table.insert(nodes, { id = `large_{i}`, name = "Large", kind = "Large", xp = 8000, effects = {} })
	end
	table.insert(nodes, {
		id = "final",
		name = "Final",
		kind = "Final",
		xp = 12000,
		effects = { { stat = "mechanicChargeTime", op = "mul", value = 0.8 } },
	})
	apex.apex = { nodes = nodes }
	table.insert(b.vehicles, apex)
	-- An Event vehicle must be handed out by something: the fixture event mode rents it.
	find(b.events, "forge_week").modes[1].vehicles = { "iu_apex" }
	return apex
end

-- `count` single-configuration Reward copies of the Kolmal at Tier II; the first `hydro` get Hydropneumatic.
local function addRewardCopies(b: any, count: number, hydro: number)
	for i = 1, count do
		local copy = table.clone(find(b.vehicles, "iu_kolmal"))
		copy.id = `iu_reward_{i}`
		copy.tier = 2
		copy.acquisition = "Reward"
		copy.modules = {
			guns = { "iu_gun_45mm" },
			turrets = { "iu_turret_kolmal" },
			engines = { "iu_engine_d120" },
			tracks = { "iu_tracks_kolmal" },
		}
		copy.stock = copy.top
		copy.moduleTree = {}
		copy.unlocks = {}
		copy.price = {}
		copy.tree = { row = 10 }
		if i <= hydro then
			copy.mechanics =
				{ { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 } }
		end
		table.insert(b.vehicles, copy)
	end
end

describe("ContentRegistry: shipped content", function()
	it("validates with no errors and no warnings", function()
		local errors, warnings = report(ContentRegistry.shippedBundle())
		expect(ContentRegistry.formatIssues(errors)).toBe("")
		expect(ContentRegistry.formatIssues(warnings)).toBe("")
		expect(ContentRegistry.get():validate()).toBeOk()
	end)

	it("validates together with a fixture for every empty registry", function()
		local errors, warnings = report(fixtureBundle())
		expect(ContentRegistry.formatIssues(errors)).toBe("")
		expect(ContentRegistry.formatIssues(warnings)).toBe("")
	end)

	it("accepts a complete Tier XI Apex (signature, 6/3/1 node track, single configuration)", function()
		local b = fixtureBundle()
		addApex(b)
		local errors, warnings = report(b)
		expect(ContentRegistry.formatIssues(errors)).toBe("")
		for _, warning in warnings do
			expect(warning.code).toBe("TIER_RANGE") -- the copied Tier I modules are far from Tier XI
		end
	end)

	it("ships the six locked factions, five classes, 17 roles and tiers I-XI", function()
		local content = ContentRegistry.get()
		expect(#content:list("Faction")).toBe(6)
		expect(#content:list("Class")).toBe(5)
		expect(#content:list("Role")).toBe(17)
		expect(#content:list("Tier")).toBe(11)
		expect((content:getTier(11) :: any).numeral).toBe("XI")
		expect((content:getFaction("desert_corps") :: any).name).toBe("Desert Armor Corps")
		for _, class in content:list("Class") do
			for _, role in content:rolesByClass(class.id) do
				expect(role.class).toBe(class.id)
			end
		end
		expect(#content:rolesByClass("medium")).toBe(4)
		expect(#content:rolesByClass("artillery")).toBe(2)
	end)

	it("is deep-frozen; shippedBundle() returns an independent mutable copy", function()
		local content = ContentRegistry.get()
		local kolmal = content:getVehicle("iu_kolmal") :: any
		expect(function()
			kolmal.tier = 2
		end).toThrow("readonly")
		expect(function()
			(kolmal.crew :: any)[1].role = "Gunner"
		end).toThrow("readonly")
		local copy = ContentRegistry.shippedBundle() :: any
		find(copy.vehicles, "iu_kolmal").tier = 5
		expect(kolmal.tier).toBe(1)
		expect(ContentRegistry.get()).toBe(content)
	end)
end)

describe("ContentRegistry: getters and derived views", function()
	local content = ContentRegistry.get()

	it("gets every kind by id and returns nil for unknown or wrong-kind ids", function()
		expect((content:getVehicle("iu_bulmal") :: any).tier).toBe(3)
		expect((content:getGun("iu_gun_76mm") :: any).caliberMm).toBe(76)
		expect((content:getTurret("iu_turret_bulmal_m2") :: any).hpBonus).toBe(20)
		expect((content:getEngine("iu_engine_d250") :: any).powerHp).toBe(250)
		expect((content:getTracks("iu_tracks_ostmal_m2") :: any).loadLimitKg).toBe(13200)
		expect((content:getShell("iu_63mm_apcr") :: any).special).toBe(true)
		expect((content:getClass("td") :: any).camoCasemate).never.toBeNil()
		expect((content:getRole("heavy_assault") :: any).categorySlot).toBe("Survivability")
		expect((content:getMap("proving_grounds") :: any).sizeM).toBe(800)
		expect(content:getModule("Gun", "iu_gun_45mm")).never.toBeNil()
		expect(content:getModule("Engine", "iu_gun_45mm")).toBeNil()
		expect((content:getAnyModule("iu_tracks_kolmal") :: any).kind).toBe("Tracks")
		expect(content:getVehicle("nope")).toBeNil()
		expect(content:getTier(12)).toBeNil()
		expect(content:getEquipment("nope")).toBeNil()
		expect(content:getConsumable("nope")).toBeNil()
		expect(content:getSkill("nope")).toBeNil()
		expect(content:getMission("nope")).toBeNil()
		expect(content:getAchievement("nope")).toBeNil()
		expect(content:getStoreItem("nope")).toBeNil()
		expect(content:getEvent("nope")).toBeNil()
		expect(content:getSeason("nope")).toBeNil()
		expect(content:getCustomization("nope")).toBeNil()
		expect(content:getCrewBook("nope")).toBeNil()
		expect(content:getBooster("nope")).toBeNil()
		expect(content:list("Nope" :: any)).toEqual({})
	end)

	it("orders vehicles by faction, tier and tree row", function()
		local function ids(list: { any }): { string }
			local out = {}
			for _, v in list do
				table.insert(out, v.id)
			end
			return out
		end
		expect(ids(content:vehiclesByFaction("iron_union"))).toEqual({ "iu_kolmal", "iu_ostmal", "iu_bulmal" })
		expect(ids(content:vehiclesByFaction("crown_industries"))).toEqual({})
		expect(ids(content:vehiclesByTier(2))).toEqual({ "iu_ostmal" })
		expect(ids(content:vehiclesByClass("medium"))).toEqual({ "iu_kolmal", "iu_ostmal", "iu_bulmal" })
		expect(ids(content:vehiclesByClass("heavy"))).toEqual({})
		expect(ids(content:branchesByFaction("iron_union"))).toEqual({
			"iu_foundry",
			"iu_bulwark",
			"iu_hammer",
			"iu_ram",
		})
		expect((content:getBranch("iu_foundry") :: any).faction).toBe("iron_union")
		expect(content:getBranch("nope")).toBeNil()
		expect(#content:allVehicles()).toBe(3)
		expect(#content:allMaps()).toBe(1)
	end)

	it("derives tech-tree edges with the target's research XP", function()
		expect(content:techTreeEdges()).toEqual({
			{ from = "iu_kolmal", to = "iu_ostmal", requires = "iu_gun_45mm", xp = 350 },
			{ from = "iu_ostmal", to = "iu_bulmal", requires = "iu_gun_63mm", xp = 750 },
		})
		expect(#content:techTreeEdges("iron_union")).toBe(2)
		expect(content:techTreeEdges("desert_corps")).toEqual({})
		expect(#content:parentsOf("iu_ostmal")).toBe(1)
		expect(content:parentsOf("iu_kolmal")).toEqual({})
		expect(content:childrenOf("iu_bulmal")).toEqual({})
	end)

	it("returns frozen views, so a caller's in-place sort cannot reorder the shared registry", function()
		local content = ContentRegistry.get()
		local views: { { any } } = {
			content:list("Vehicle"),
			content:list("Gun"),
			content:allVehicles(),
			content:allMaps(),
			content:vehiclesByFaction("iron_union"),
			content:vehiclesByTier(1),
			content:vehiclesByClass("medium"),
			content:rolesByClass("medium"),
			content:branchesByFaction("iron_union"),
			content:techTreeEdges(),
			content:techTreeEdges("iron_union"),
			content:parentsOf("iu_ostmal"),
			content:childrenOf("iu_kolmal"),
			content:parentsOf("iu_kolmal"), -- empty
		}
		for i, view in views do
			if not table.isfrozen(view) then
				error(`view {i} is not frozen`)
			end
		end
		expect(function()
			table.sort(content:allVehicles() :: any, function(a: any, b: any)
				return a.tier > b.tier
			end)
		end).toThrow("readonly")
		expect(content:allVehicles()[1].id).toBe("iu_kolmal")
	end)

	it("accepts a Tier VI vehicle once its role defines enough Field Kit levels", function()
		local b = fixtureBundle()
		addRewardCopies(b, 1, 0)
		local copy = find(b.vehicles, "iu_reward_1")
		copy.tier = 6
		table.insert(
			find(b.missions, "daily_hold_the_line").rewards,
			{ kind = "Vehicle", id = "iu_reward_1", amount = 1 }
		)
		local levels = {}
		for level = 1, 3 do
			table.insert(levels, {
				options = {
					{ id = `fk_{level}_a`, name = "Option A", description = "A.", effects = {} },
					{ id = `fk_{level}_b`, name = "Option B", description = "B.", effects = {} },
				},
			})
		end
		find(b.roles, "medium_versatile").fieldKit = levels
		local errors = report(b)
		expect(ContentRegistry.formatIssues(errors)).toBe("")
	end)

	it("computes configuration mass and enforces the mount rules", function()
		local kolmal = content:getVehicle("iu_kolmal") :: any
		expect(content:configurationMassKg("iu_kolmal", kolmal.stock)).toBe(9850)
		expect(content:configurationMassKg("iu_kolmal", kolmal.top)).toBe(10020)
		expect(content:configurationMassKg("nope", kolmal.stock)).toBeNil()
		local bulmal = content:getVehicle("iu_bulmal") :: any
		local ok = content:checkConfiguration("iu_bulmal", bulmal.top)
		expect(ok).toBeOk()
		expect(ok.value).toBe(18230)
		-- Tracks -> Turret -> Gun is physical: the stock tracks cannot carry the top turret + gun.
		local heavy = {
			gun = "iu_gun_76mm",
			turret = "iu_turret_bulmal_m2",
			engine = "iu_engine_d210",
			tracks = "iu_tracks_bulmal_m1",
		}
		local over = content:checkConfiguration("iu_bulmal", heavy :: any)
		expect(over).toBeErr("INVALID_ARGS")
		expect(over.detail).toContain("exceeds")
		local wrongGun = table.clone(bulmal.stock)
		wrongGun.gun = "iu_gun_76mm"
		expect(content:checkConfiguration("iu_bulmal", wrongGun)).toBeErr("INVALID_ARGS")
		local foreign = table.clone(bulmal.stock)
		foreign.engine = "iu_engine_d120"
		expect(content:checkConfiguration("iu_bulmal", foreign)).toBeErr("INVALID_ARGS")
		local unknown = table.clone(bulmal.stock)
		unknown.engine = "nope"
		expect(content:checkConfiguration("iu_bulmal", unknown)).toBeErr("NOT_FOUND")
		expect(content:checkConfiguration("nope", bulmal.stock)).toBeErr("NOT_FOUND")
		expect(content:checkConfiguration("iu_bulmal", 5 :: any)).toBeErr("INVALID_ARGS")
	end)

	it("authors stock tracks with 1-3 % spare load on the exemplar line", function()
		for _, vehicle in content:allVehicles() do
			local tracks = content:getTracks(vehicle.stock.tracks) :: any
			local mass = content:configurationMassKg(vehicle.id, vehicle.stock) :: number
			local spare = (tracks.loadLimitKg - mass) / tracks.loadLimitKg
			expect(spare).toBeGreaterThanOrEqual(0.0)
			expect(spare).toBeLessThanOrEqual(0.035)
		end
	end)

	it("maps ids to stable ordinals and back", function()
		for _, kind in { "Vehicle", "Gun", "Shell", "Tier", "Map" } do
			for _, def in content:list(kind :: any) do
				local id = if kind == "Tier" then def.tier else def.id
				local ordinal = content:ordinal(kind :: any, id) :: number
				expect(ordinal).never.toBeNil()
				expect(content:idAt(kind :: any, ordinal)).toBe(id)
			end
		end
		expect(content:ordinal("Vehicle", "iu_bulmal")).toBe(1)
		expect(content:ordinal("Vehicle", "nope")).toBeNil()
		expect(content:idAt("Vehicle", 99)).toBeNil()
	end)

	it("hashes content deterministically and detects any change", function()
		local hash = content:contentHash()
		expect(hash).toMatch("^%x+$")
		expect(#hash).toBe(16)
		expect(content:contentHash()).toBe(hash)
		expect(ContentRegistry.fromBundle(ContentRegistry.shippedBundle()):contentHash()).toBe(hash)
		local changed = ContentRegistry.shippedBundle() :: any
		find(changed.shells, "iu_45mm_ap").damage = 48
		expect(ContentRegistry.fromBundle(changed):contentHash()).never.toBe(hash)
		local colour = ContentRegistry.shippedBundle() :: any
		find(colour.factions, "iron_union").palette.primary = Color3.fromHex("#B8492B")
		expect(ContentRegistry.fromBundle(colour):contentHash()).never.toBe(hash)
	end)

	it("flattens per-file source lists", function()
		local registry = ContentRegistry.fromSources({
			factions = {},
			classes = {},
			roles = {},
			tiers = {},
			shells = { { { id = "a_shell" } }, { { id = "b_shell" }, { id = "c_shell" } } },
			guns = {},
			turrets = {},
			engines = {},
			tracks = {},
			vehicles = {},
			equipment = {},
			consumables = {},
			crewSkills = {},
			crewBooks = {},
			boosters = {},
			customization = {},
			missions = {},
			achievements = {},
			maps = {},
			store = {},
			events = {},
			seasons = {},
		} :: any)
		expect(#registry:list("Shell")).toBe(3)
		expect(registry:getShell("c_shell")).never.toBeNil()
	end)

	it("reports issues deterministically and formats them one per line", function()
		local b = fixtureBundle()
		find(b.vehicles, "iu_kolmal").crew = {}
		find(b.guns, "iu_gun_45mm").shells = {}
		local first = report(b)
		local second = report(b)
		expect(first).toEqual(second)
		local text = ContentRegistry.formatIssues({
			{ code = "BAD_VALUE", path = "a.b", message = "nope", severity = "error" },
			{ code = "X", path = "c", message = "m", severity = "warning" },
		})
		expect(text).toBe("BAD_VALUE a.b: nope\nX c: m")
	end)
end)

describe("ContentRegistry: loadout legality (checkLoadout)", function()
	local function registry(): any
		local b = fixtureBundle()
		table.insert(b.customization, {
			id = "attachment_spare_links",
			name = "Spare links",
			icon = "factions/iron_union",
			kind = "Attachment",
			rarity = "common",
			pattern = "spare_links",
			source = "Store",
			price = { credits = 10000 },
		})
		table.insert(b.customization, {
			id = "paint_proving_grey",
			name = "Proving Grey",
			icon = "factions/iron_union",
			kind = "Paint",
			rarity = "common",
			colors = { Color3.fromHex("#6B6E70") },
			source = "Store",
			price = { credits = 20000 },
		})
		return ContentRegistry.fromBundle(b)
	end
	-- The Ostmal (Tier II): Tier I has equipment slots but no equipment band reaches it (see the review notes).
	local function ostmalLoadout(): any
		return {
			vehicleId = "iu_ostmal",
			configuration = {
				gun = "iu_gun_45mm",
				turret = "iu_turret_ostmal",
				engine = "iu_engine_d165",
				tracks = "iu_tracks_ostmal_m1",
			},
			equipment = { { slot = 1, id = "rammer_assist_c" } },
			ammo = { { shell = "iu_45mm_ap", count = 60 }, { shell = "iu_45mm_he", count = 40 } },
			consumables = { { slot = 1, id = "repair_kit" }, { slot = 2, id = "auto_extinguisher" } },
			crew = {
				{ slot = 1, role = "Commander", also = { "Loader" }, level = 100, skills = {} },
				{ slot = 2, role = "Gunner", level = 100, skills = { { id = "snap_shot", training = 0.5 } } },
				{ slot = 3, role = "Driver", level = 100, skills = {} },
			},
			customization = { paint = "paint_proving_grey", attachments = { "attachment_spare_links" } },
		}
	end

	it("accepts a complete legal loadout", function()
		local content = registry()
		expect(content:validate()).toBeOk()
		expect(content:checkLoadout(ostmalLoadout())).toBeOk()
	end)

	local bad: { { name: string, code: string, detail: string, mutate: (any) -> () } } = {
		{
			name = "unknown vehicle",
			code = "NOT_FOUND",
			detail = "vehicleId",
			mutate = function(l)
				l.vehicleId = "iu_nope"
			end,
		},
		{
			name = "unknown loadout field",
			code = "INVALID_ARGS",
			detail = "ammunition",
			mutate = function(l)
				l.ammunition = {}
			end,
		},
		{
			name = "unmountable configuration",
			code = "INVALID_ARGS",
			detail = "configuration",
			mutate = function(l)
				l.configuration.gun = "iu_gun_76mm"
			end,
		},
		{
			name = "shell of another gun",
			code = "INVALID_ARGS",
			detail = "ammo[1].shell",
			mutate = function(l)
				l.ammo[1].shell = "iu_37mm_ap"
			end,
		},
		{
			name = "more shells than the rack holds",
			code = "INVALID_ARGS",
			detail = "ammo capacity",
			mutate = function(l)
				l.ammo[1].count = 61 + 40
			end,
		},
		{
			name = "fractional shell count",
			code = "INVALID_ARGS",
			detail = "ammo[2].count",
			mutate = function(l)
				l.ammo[2].count = 2.5
			end,
		},
		{
			name = "equipment slot beyond the tier's slots",
			code = "INVALID_ARGS",
			detail = "equipment[1].slot",
			mutate = function(l)
				l.equipment[1].slot = 3
			end,
		},
		{
			name = "equipment outside its tier band",
			code = "INVALID_ARGS",
			detail = "fits Tiers",
			mutate = function(l)
				-- the Kolmal is Tier I; Rammer Assist C is II–IV
				l.vehicleId = "iu_kolmal"
				l.configuration = {
					gun = "iu_gun_45mm",
					turret = "iu_turret_kolmal",
					engine = "iu_engine_d120",
					tracks = "iu_tracks_kolmal",
				}
				l.crew = {
					{ slot = 1, role = "Commander", also = { "Gunner", "Loader" }, level = 100, skills = {} },
					{ slot = 2, role = "Driver", level = 100, skills = {} },
				}
			end,
		},
		{
			name = "two items of one exclusive group",
			code = "INVALID_ARGS",
			detail = "already",
			mutate = function(l)
				l.consumables = { { slot = 1, id = "repair_kit" }, { slot = 2, id = "repair_kit" } }
			end,
		},
		{
			name = "event-only consumable in a regular battle",
			code = "INVALID_ARGS",
			detail = "event modes",
			mutate = function(l)
				l.consumables = { { slot = 1, id = "smoke_screen" } }
			end,
		},
		{
			name = "crew member in the wrong seat",
			code = "INVALID_ARGS",
			detail = "crew[3]",
			mutate = function(l)
				l.crew[3].role = "Gunner"
			end,
		},
		{
			name = "skill of another duty",
			code = "INVALID_ARGS",
			detail = "crew[3].skills[1].id",
			mutate = function(l)
				l.crew[3].skills = { { id = "snap_shot", training = 1 } }
			end,
		},
		{
			name = "cosmetic scoped to another vehicle",
			code = "INVALID_ARGS",
			detail = "cannot be applied to iu_ostmal",
			mutate = function(l)
				l.customization.paint = "paint_foundry_red" -- scoped to the Kolmal
			end,
		},
		{
			name = "cosmetic of the wrong kind",
			code = "INVALID_ARGS",
			detail = "customization.camouflage",
			mutate = function(l)
				l.customization.camouflage = "paint_proving_grey"
			end,
		},
		{
			name = "Field Kit below Tier VI",
			code = "INVALID_ARGS",
			detail = "fieldKit",
			mutate = function(l)
				l.fieldKit = { "fk_a" }
			end,
		},
		{
			name = "Apex nodes on a vehicle without an Apex track",
			code = "INVALID_ARGS",
			detail = "apexNodes",
			mutate = function(l)
				l.apexNodes = { "small_1" }
			end,
		},
	}
	for _, case in bad do
		it(`rejects: {case.name}`, function()
			local loadout = ostmalLoadout()
			case.mutate(loadout)
			local result = registry():checkLoadout(loadout)
			expect(result).toBeErr(case.code)
			expect(result.detail).toContain(case.detail)
		end)
	end

	it("never throws on hostile input (it runs on manifest data in the battle server)", function()
		local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
		local rng = RNG.new(20261006)
		local content = registry()
		local function junk(depth: number): any
			local roll = rng:int(1, 8)
			if roll == 1 then
				return nil
			elseif roll == 2 then
				return rng:range(-1e9, 1e9)
			elseif roll == 3 then
				return 0 / 0
			elseif roll == 4 then
				return "iu_kolmal"
			elseif roll == 5 then
				return true
			elseif roll == 6 and depth < 3 then
				return { junk(depth + 1), junk(depth + 1) }
			elseif roll == 7 and depth < 3 then
				return { slot = junk(depth + 1), id = junk(depth + 1), shell = junk(depth + 1), count = junk(depth + 1) }
			end
			return {}
		end
		local fieldsToBreak = {
			"vehicleId",
			"configuration",
			"equipment",
			"ammo",
			"consumables",
			"crew",
			"crewPerkEfficiency",
			"customization",
			"fieldKit",
			"apexNodes",
		}
		for _ = 1, 400 do
			local loadout = ostmalLoadout()
			for _ = 1, rng:int(1, 3) do
				loadout[rng:pick(fieldsToBreak)] = junk(0)
			end
			if rng:chance(0.3) then
				loadout.crew = { { slot = 1, role = "Commander", also = junk(1), level = junk(1), skills = junk(1) } }
			end
			local ok, result = pcall(function()
				return content:checkLoadout(loadout)
			end)
			if not ok then
				error(`checkLoadout threw: {tostring(result)}`)
			end
			expect(type(result.ok)).toBe("boolean")
		end
	end)

	it("allows event-only consumables when the mode says so", function()
		local loadout = ostmalLoadout()
		loadout.consumables = { { slot = 1, id = "smoke_screen" } }
		expect(registry():checkLoadout(loadout, { eventItems = true })).toBeOk()
	end)
end)

describe("ContentRegistry: asset keys", function()
	local function iconCatalogue(): { [string]: boolean }
		local keys = {}
		local root = "assets/icons"
		for _, folder in fs.readDir(root) do
			if fs.isDir(`{root}/{folder}`) then
				for _, file in fs.readDir(`{root}/{folder}`) do
					local name = string.match(file, "^(.+)%.svg$")
					if name then
						keys[`{folder}/{name}`] = true
					end
				end
			end
		end
		return keys
	end
	local function soundCatalogue(): { [string]: boolean }
		local catalogue = serde.decode("json", fs.readFile("assets/audio/catalog.json"))
		local keys = {}
		for key in catalogue.sounds do
			keys[key] = true
		end
		return keys
	end

	it("checks icon and sound keys only when a catalogue is given", function()
		local errors = report(ContentRegistry.shippedBundle(), { iconKeys = {}, soundKeys = {} })
		expect(hasIssue(errors, "ASSET_KEY", "factions[1](iron_union).emblem")).toBe(true)
		expect(hasIssue(errors, "ASSET_KEY", "guns[1](iu_gun_37mm).audio")).toBe(true)
		expect(hasIssue(errors, "ASSET_KEY", "maps[1](proving_grounds).audio.ambience")).toBe(true)
	end)

	it("resolves every faction, class, tier, sound family and ambience key against the real catalogues", function()
		local errors = report(ContentRegistry.shippedBundle(), {
			iconKeys = iconCatalogue(),
			soundKeys = soundCatalogue(),
		})
		local remaining = {}
		for _, issue in errors do
			expect(issue.code).toBe("ASSET_KEY")
			-- Role badges and map thumbnails are not drawn yet (glyph fallback); everything else must resolve.
			if not (string.find(issue.path, ".badge", 1, true) or string.find(issue.path, ".thumbnail", 1, true)) then
				table.insert(remaining, issue)
			end
		end
		expect(ContentRegistry.formatIssues(remaining)).toBe("")
	end)
end)

--------------------------------------------------------------------------------
-- Every validator fires
--------------------------------------------------------------------------------

type Case = {
	name: string,
	code: string,
	path: string?,
	message: string?, -- substring of the issue message (when the code and path alone are ambiguous)
	warning: boolean?,
	options: any?, -- ValidateOptions passed to validate()
	mutate: (b: any) -> (),
}

local cases: { Case } = {
	-- Indexing ---------------------------------------------------------------------------------------------------
	{
		name = "invalid id",
		code = "INVALID_ID",
		path = "vehicles[1]",
		mutate = function(b)
			b.vehicles[1].id = "Bad-Id"
		end,
	},
	{
		name = "duplicate id within a kind",
		code = "DUPLICATE_ID",
		path = "vehicles[4]",
		mutate = function(b)
			table.insert(b.vehicles, table.clone(b.vehicles[1]))
		end,
	},
	{
		name = "duplicate id across module kinds",
		code = "DUPLICATE_ID",
		path = "engines[5]",
		mutate = function(b)
			local engine = table.clone(b.engines[1])
			engine.id = "iu_gun_37mm"
			table.insert(b.engines, engine)
		end,
	},
	{
		name = "missing list in the bundle",
		code = "MISSING_FIELD",
		path = "maps",
		mutate = function(b)
			b.maps = nil
		end,
	},
	{
		name = "unknown (typo) field",
		code = "UNKNOWN_FIELD",
		path = "vehicles[1](iu_kolmal).camoflage",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").camoflage = { stationary = 0.1, moving = 0.1 }
		end,
	},
	{
		name = "missing required field",
		code = "MISSING_FIELD",
		path = "vehicles[1](iu_kolmal).lore",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").lore = nil
		end,
	},
	{
		name = "non-finite number",
		code = "BAD_VALUE",
		path = "shells[1](iu_37mm_ap).damage",
		mutate = function(b)
			find(b.shells, "iu_37mm_ap").damage = 0 / 0
		end,
	},
	-- Locked sets and registries -------------------------------------------------------------------------------------
	{
		name = "missing locked faction",
		code = "LOCKED_SET",
		path = "factions",
		mutate = function(b)
			table.remove(b.factions, 6)
		end,
	},
	{
		name = "extra faction",
		code = "LOCKED_SET",
		path = "factions",
		mutate = function(b)
			local extra = table.clone(b.factions[1])
			extra.id = "pirate_league"
			table.insert(b.factions, extra)
		end,
	},
	{
		name = "missing tier",
		code = "LOCKED_SET",
		path = "tiers",
		mutate = function(b)
			table.remove(b.tiers, 11)
		end,
	},
	{
		name = "faction palette is not a Color3",
		code = "BAD_VALUE",
		path = "factions[1](iron_union).palette.primary",
		mutate = function(b)
			find(b.factions, "iron_union").palette.primary = "#B8492A"
		end,
	},
	{
		name = "faction kit with an unknown balance stat",
		code = "BAD_VALUE",
		path = "factions[1](iron_union).kit.mul.alfa",
		mutate = function(b)
			find(b.factions, "iron_union").kit.mul.alfa = 1.1
		end,
	},
	{
		name = "class lists a role of another class",
		code = "ROLE_CLASS",
		path = "classes[1](light).roles[4]",
		mutate = function(b)
			table.insert(find(b.classes, "light").roles, "heavy_assault")
		end,
	},
	{
		name = "td class without casemate camo",
		code = "MISSING_FIELD",
		path = "classes[4](td).camoCasemate",
		mutate = function(b)
			find(b.classes, "td").camoCasemate = nil
		end,
	},
	{
		name = "role score weights do not sum to 1",
		code = "ROLE_SCORE",
		path = "roles[1](light_scout).roleScore",
		mutate = function(b)
			find(b.roles, "light_scout").roleScore.capture = 0.2
		end,
	},
	{
		name = "role with an unknown Role Score component",
		code = "ROLE_SCORE",
		path = "roleScore.style",
		mutate = function(b)
			find(b.roles, "light_scout").roleScore.style = 0
		end,
	},
	{
		name = "role not listed by its class",
		code = "ROLE_CLASS",
		path = "roles[4](medium_assault).class",
		mutate = function(b)
			table.remove(find(b.classes, "medium").roles, 1)
		end,
	},
	{
		name = "role needs exactly three tips",
		code = "BAD_VALUE",
		path = "roles[1](light_scout).tips",
		mutate = function(b)
			table.remove(find(b.roles, "light_scout").tips, 1)
		end,
	},
	{
		name = "tier numeral mismatch",
		code = "BAD_VALUE",
		path = "tiers[4](4).numeral",
		mutate = function(b)
			find(b.tiers, 4).numeral = "III"
		end,
	},
	{
		name = "tier matchmaking range excludes the tier",
		code = "TIER_RANGE",
		path = "tiers[5](5).matchmaking",
		mutate = function(b)
			find(b.tiers, 5).matchmaking = { min = 6, max = 8 }
		end,
	},
	-- Shells -------------------------------------------------------------------------------------------------------------
	{
		name = "kinetic shell with a blast radius",
		code = "SHELL_KIND",
		path = "shells[1](iu_37mm_ap).explosionRadiusM",
		mutate = function(b)
			find(b.shells, "iu_37mm_ap").explosionRadiusM = 1
		end,
	},
	{
		name = "stun on a non-HE shell",
		code = "SHELL_KIND",
		path = "iu_37mm_apcr).stun",
		mutate = function(b)
			find(b.shells, "iu_37mm_apcr").stun = { maxS = 6, minS = 3 }
		end,
	},
	{
		name = "falloff on a HE shell",
		code = "SHELL_KIND",
		path = "iu_37mm_he).penetrationAt500Mm",
		mutate = function(b)
			find(b.shells, "iu_37mm_he").penetrationAt500Mm = 10
		end,
	},
	{
		name = "falloff endpoint above point-blank pen",
		code = "BAD_VALUE",
		path = "iu_45mm_ap).penetrationAt500Mm",
		mutate = function(b)
			find(b.shells, "iu_45mm_ap").penetrationAt500Mm = 60
		end,
	},
	{
		name = "stun minimum above maximum",
		code = "BAD_VALUE",
		path = "iu_37mm_he).stun",
		mutate = function(b)
			find(b.shells, "iu_37mm_he").stun = { maxS = 3, minS = 6 }
		end,
	},
	{
		name = "orphan shell",
		code = "ORPHAN",
		path = "iu_99mm_ap",
		warning = true,
		mutate = function(b)
			local shell = table.clone(b.shells[1])
			shell.id = "iu_99mm_ap"
			table.insert(b.shells, shell)
		end,
	},
	-- Guns ---------------------------------------------------------------------------------------------------------------
	{
		name = "gun without shells",
		code = "BAD_VALUE",
		path = "guns[1](iu_gun_37mm).shells",
		mutate = function(b)
			find(b.guns, "iu_gun_37mm").shells = {}
		end,
	},
	{
		name = "gun with four shells",
		code = "SHELL_COUNT",
		path = "guns[1](iu_gun_37mm).shells",
		mutate = function(b)
			table.insert(find(b.guns, "iu_gun_37mm").shells, "iu_45mm_ap")
		end,
	},
	{
		name = "gun lists a shell twice",
		code = "SHELL_COUNT",
		path = "guns[1](iu_gun_37mm).shells[2]",
		mutate = function(b)
			find(b.guns, "iu_gun_37mm").shells = { "iu_37mm_ap", "iu_37mm_ap" }
		end,
	},
	{
		name = "gun references an unknown shell",
		code = "DANGLING_REF",
		path = "guns[1](iu_gun_37mm).shells[3]",
		mutate = function(b)
			find(b.guns, "iu_gun_37mm").shells[3] = "iu_37mm_hesh"
		end,
	},
	{
		name = "shell calibre differs from the gun",
		code = "SHELL_CALIBER",
		path = "guns[1](iu_gun_37mm).shells[1]",
		mutate = function(b)
			find(b.guns, "iu_gun_37mm").shells[1] = "iu_45mm_ap"
		end,
	},
	{
		name = "special shell listed first",
		code = "SHELL_ORDER",
		path = "guns[1](iu_gun_37mm).shells[1]",
		mutate = function(b)
			find(b.guns, "iu_gun_37mm").shells = { "iu_37mm_apcr", "iu_37mm_ap", "iu_37mm_he" }
		end,
	},
	{
		name = "autoreloader timers do not match its size",
		code = "BAD_VALUE",
		path = "guns[2](iu_gun_45mm).reload.perShellReloadS",
		mutate = function(b)
			find(b.guns, "iu_gun_45mm").reload =
				{ kind = "Autoreloader", size = 3, perShellReloadS = { 3, 2 }, intraClipS = 1.5 }
		end,
	},
	{
		name = "unknown reload kind",
		code = "BAD_VALUE",
		path = "guns[2](iu_gun_45mm).reload.kind",
		mutate = function(b)
			find(b.guns, "iu_gun_45mm").reload = { kind = "Gatling", reloadS = 2 }
		end,
	},
	{
		name = "unknown gun sound family",
		code = "BAD_VALUE",
		path = "guns[2](iu_gun_45mm).audio",
		mutate = function(b)
			find(b.guns, "iu_gun_45mm").audio = "laser"
		end,
	},
	{
		name = "orphan gun",
		code = "ORPHAN",
		path = "iu_gun_spare",
		warning = true,
		mutate = function(b)
			local gun = table.clone(b.guns[1])
			gun.id = "iu_gun_spare"
			table.insert(b.guns, gun)
		end,
	},
	-- Turrets, engines, tracks ------------------------------------------------------------------------------------------
	{
		name = "turret lists a module that is not a gun",
		code = "WRONG_KIND",
		path = "turrets[1](iu_turret_kolmal).guns[1]",
		mutate = function(b)
			find(b.turrets, "iu_turret_kolmal").guns[1] = "iu_engine_d120"
		end,
	},
	{
		name = "turret lists an unknown gun",
		code = "DANGLING_REF",
		path = "turrets[1](iu_turret_kolmal).guns[2]",
		mutate = function(b)
			find(b.turrets, "iu_turret_kolmal").guns[2] = "iu_gun_nope"
		end,
	},
	{
		name = "casemate mount without yaw limits",
		code = "MOUNT",
		path = "turrets[1](iu_turret_kolmal).yawLimitsDeg",
		mutate = function(b)
			local turret = find(b.turrets, "iu_turret_kolmal")
			turret.mount = "Casemate"
			turret.visual.style = "Casemate"
		end,
	},
	{
		name = "casemate mount with a turret visual",
		code = "MOUNT",
		path = "turrets[1](iu_turret_kolmal).visual.style",
		mutate = function(b)
			local turret = find(b.turrets, "iu_turret_kolmal")
			turret.mount = "Casemate"
			turret.yawLimitsDeg = { left = 11, right = 11 }
		end,
	},
	{
		name = "module declares the wrong kind",
		code = "WRONG_KIND",
		path = "engines[1](iu_engine_d120).kind",
		mutate = function(b)
			find(b.engines, "iu_engine_d120").kind = "Gun"
		end,
	},
	{
		name = "fire chance above 1",
		code = "BAD_VALUE",
		path = "engines[1](iu_engine_d120).fireChance",
		mutate = function(b)
			find(b.engines, "iu_engine_d120").fireChance = 1.5
		end,
	},
	{
		name = "terrain resistance out of order",
		code = "BAD_VALUE",
		path = "tracks[1](iu_tracks_kolmal).terrainResistance",
		mutate = function(b)
			find(b.tracks, "iu_tracks_kolmal").terrainResistance = { hard = 2, medium = 1, soft = 3 }
		end,
	},
	-- Vehicles: references and identity ---------------------------------------------------------------------------------
	{
		name = "vehicle references an unknown faction",
		code = "DANGLING_REF",
		path = "vehicles[1](iu_kolmal).faction",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").faction = "pirate_league"
		end,
	},
	{
		name = "vehicle role of another class",
		code = "ROLE_CLASS",
		path = "vehicles[1](iu_kolmal).role",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").role = "heavy_assault"
		end,
	},
	{
		name = "class outside its tier range",
		code = "TIER_RANGE",
		path = "vehicles[1](iu_kolmal).tier",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			kolmal.class = "artillery"
			kolmal.role = "artillery_support"
		end,
	},
	{
		name = "tier outside 1..11",
		code = "BAD_VALUE",
		path = "vehicles[3](iu_bulmal).tier",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").tier = 12
		end,
	},
	{
		name = "short name longer than 12 characters",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_kolmal).shortName",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").shortName = "Kolmal Mark One"
		end,
	},
	{
		name = "module list references an unknown module",
		code = "DANGLING_REF",
		path = "vehicles[1](iu_kolmal).modules.engines[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_kolmal").modules.engines, "iu_engine_nope")
		end,
	},
	{
		name = "module list holds a module of another kind",
		code = "WRONG_KIND",
		path = "vehicles[1](iu_kolmal).modules.engines[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_kolmal").modules.engines, "iu_tracks_kolmal")
		end,
	},
	-- Vehicles: configurations and load limits ----------------------------------------------------------------------------
	{
		name = "stock configuration uses a module the vehicle does not list",
		code = "CONFIG_INVALID",
		path = "vehicles[1](iu_kolmal).stock.engine",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").stock.engine = "iu_engine_d165"
		end,
	},
	{
		name = "stock configuration mounts a gun the turret cannot carry",
		code = "CONFIG_INVALID",
		path = "vehicles[3](iu_bulmal).stock.gun",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").stock.gun = "iu_gun_76mm"
		end,
	},
	{
		name = "configuration slot holds a module of another kind",
		code = "WRONG_KIND",
		path = "vehicles[1](iu_kolmal).top.engine",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").top.engine = "iu_tracks_kolmal"
		end,
	},
	{
		name = "configuration slot missing",
		code = "MISSING_FIELD",
		path = "vehicles[1](iu_kolmal).top.tracks",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").top.tracks = nil
		end,
	},
	{
		name = "stock configuration over the load limit",
		code = "OVER_LOAD_LIMIT",
		path = "vehicles[1](iu_kolmal).stock",
		mutate = function(b)
			find(b.tracks, "iu_tracks_kolmal").loadLimitKg = 9800
		end,
	},
	{
		name = "top configuration over the load limit",
		code = "OVER_LOAD_LIMIT",
		path = "vehicles[3](iu_bulmal).top",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").hull.massKg = 18000
		end,
	},
	{
		name = "stock tracks can carry the top modules (weak research order)",
		code = "LOAD_ORDER",
		path = "vehicles[2](iu_ostmal).stock.tracks",
		warning = true,
		mutate = function(b)
			find(b.tracks, "iu_tracks_ostmal_m1").loadLimitKg = 12800
		end,
	},
	-- Vehicles: module tree ------------------------------------------------------------------------------------------
	{
		name = "module tree node is not a module of the vehicle",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_kolmal).moduleTree[2].module",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_kolmal").moduleTree, { module = "iu_gun_76mm" })
		end,
	},
	{
		name = "stock module listed in the module tree",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_kolmal).moduleTree[2].module",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_kolmal").moduleTree, { module = "iu_gun_37mm" })
		end,
	},
	{
		name = "module listed twice in the tree",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_kolmal).moduleTree[2].module",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_kolmal").moduleTree, { module = "iu_gun_45mm" })
		end,
	},
	{
		name = "module requires itself",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_kolmal).moduleTree[1].requires[1]",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").moduleTree[1].requires = { "iu_gun_45mm" }
		end,
	},
	{
		name = "module requires a module of another vehicle",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_kolmal).moduleTree[1].requires[1]",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").moduleTree[1].requires = { "iu_tracks_bulmal_m2" }
		end,
	},
	{
		name = "non-stock module missing from the tree",
		code = "MODULE_UNREACHABLE",
		path = "vehicles[3](iu_bulmal).modules.engines(iu_engine_d250)",
		mutate = function(b)
			table.remove(find(b.vehicles, "iu_bulmal").moduleTree, 4)
		end,
	},
	{
		name = "module requirements form a cycle",
		code = "MODULE_CYCLE",
		path = "vehicles[3](iu_bulmal).moduleTree",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").moduleTree[1].requires = { "iu_gun_76mm" }
		end,
	},
	{
		name = "a gun that no turret of the vehicle can mount",
		code = "TURRET_GUNS",
		path = "vehicles[1](iu_kolmal).modules.guns(iu_gun_63mm)",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			table.insert(kolmal.modules.guns, "iu_gun_63mm")
			table.insert(kolmal.moduleTree, { module = "iu_gun_63mm" })
		end,
	},
	-- Vehicles: tech tree -------------------------------------------------------------------------------------------
	{
		name = "unlock of an unknown vehicle",
		code = "DANGLING_REF",
		path = "vehicles[3](iu_bulmal).unlocks[1].vehicle",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").unlocks = { { vehicle = "iu_nope" } }
		end,
	},
	{
		name = "unlock skips a tier",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_kolmal).unlocks[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_kolmal").unlocks, { vehicle = "iu_bulmal" })
		end,
	},
	{
		name = "unlock requires a module the vehicle does not have",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_kolmal).unlocks[1].requires",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").unlocks[1].requires = "iu_gun_63mm"
		end,
	},
	{
		name = "duplicate unlock",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_kolmal).unlocks[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_kolmal").unlocks, { vehicle = "iu_ostmal" })
		end,
	},
	{
		name = "unlock across factions",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_kolmal).unlocks[1]",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").faction = "crown_industries"
		end,
	},
	{
		name = "unlock of a premium vehicle",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_kolmal).unlocks[2]",
		mutate = function(b)
			addPremium(b)
			table.insert(find(b.vehicles, "iu_kolmal").unlocks, { vehicle = "iu_premium_two" })
		end,
	},
	{
		name = "premium vehicle unlocking another vehicle",
		code = "UNLOCK_EDGE",
		path = "vehicles[4](iu_premium_two).unlocks[1]",
		mutate = function(b)
			local premium = addPremium(b)
			premium.unlocks = { { vehicle = "iu_bulmal" } }
		end,
	},
	{
		name = "tech tree cycle",
		code = "TECH_TREE_CYCLE",
		path = "vehicles",
		mutate = function(b)
			local twin = table.clone(find(b.vehicles, "iu_ostmal"))
			twin.id = "iu_ostmal_twin"
			twin.tree = { row = 4 }
			twin.unlocks = { { vehicle = "iu_ostmal" } }
			table.insert(b.vehicles, twin)
			table.insert(find(b.vehicles, "iu_ostmal").unlocks, { vehicle = "iu_ostmal_twin" })
		end,
	},
	{
		name = "vehicle unreachable from a Tier I root",
		code = "UNREACHABLE_VEHICLE",
		path = "vehicles(iu_bulmal)",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").unlocks = {}
		end,
	},
	{
		name = "faction without a Tier I root",
		code = "NO_ROOT",
		path = "factions(iron_union)",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			kolmal.acquisition = "Reward"
			kolmal.unlocks = {}
		end,
	},
	{
		name = "Tier I starter unlocked by another vehicle",
		code = "UNLOCK_EDGE",
		path = "vehicles(iu_kolmal_b)",
		mutate = function(b)
			local twin = table.clone(find(b.vehicles, "iu_kolmal"))
			twin.id = "iu_kolmal_b"
			twin.tree = { row = 5 }
			twin.unlocks = {}
			table.insert(b.vehicles, twin)
			table.insert(find(b.vehicles, "iu_kolmal").unlocks, { vehicle = "iu_kolmal_b" })
		end,
	},
	{
		name = "two tech-tree vehicles in the same tree slot",
		code = "TREE_POSITION",
		path = "vehicles[4](iu_ostmal_b).tree.row",
		mutate = function(b)
			local twin = table.clone(find(b.vehicles, "iu_ostmal"))
			twin.id = "iu_ostmal_b"
			twin.unlocks = {}
			table.insert(b.vehicles, twin)
			table.insert(find(b.vehicles, "iu_kolmal").unlocks, { vehicle = "iu_ostmal_b" })
		end,
	},
	-- Vehicles: crew ---------------------------------------------------------------------------------------------------
	{
		name = "two commanders",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_ostmal).crew",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").crew[4] = { role = "Commander", also = { "Loader" } }
		end,
	},
	{
		name = "no commander",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_ostmal).crew",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").crew[1] = { role = "Loader" }
		end,
	},
	{
		name = "no seat covers the loader duty",
		code = "CREW_COMPOSITION",
		path = "vehicles[1](iu_kolmal).crew",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").crew[1] = { role = "Commander" }
		end,
	},
	{
		name = "driver with extra duties",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_ostmal).crew[3].also",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").crew[3].also = { "Loader" }
		end,
	},
	{
		name = "commander as a secondary duty",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_ostmal).crew[2].also[1]",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").crew[2].also = { "Commander" }
		end,
	},
	{
		name = "crew too large",
		code = "CREW_COMPOSITION",
		path = "vehicles[3](iu_bulmal).crew",
		mutate = function(b)
			local crew = find(b.vehicles, "iu_bulmal").crew
			table.insert(crew, { role = "Loader" })
			table.insert(crew, { role = "Gunner" })
		end,
	},
	-- Vehicles: acquisition --------------------------------------------------------------------------------------------
	{
		name = "tech-tree vehicle without research XP",
		code = "ACQUISITION",
		path = "vehicles[2](iu_ostmal).researchXp",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").researchXp = nil
		end,
	},
	{
		name = "tier I vehicle that costs credits",
		code = "ACQUISITION",
		path = "vehicles[1](iu_kolmal).price.credits",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").price = { credits = 1000 }
		end,
	},
	{
		name = "tech-tree vehicle sold for Bullion",
		code = "ACQUISITION",
		path = "vehicles[2](iu_ostmal).price.bullion",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").price.bullion = 250
		end,
	},
	{
		name = "premium vehicle without a Bullion price",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_two).price.bullion",
		mutate = function(b)
			addPremium(b).price = { credits = 35000 }
		end,
	},
	{
		name = "premium vehicle with research XP",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_two).researchXp",
		mutate = function(b)
			addPremium(b).researchXp = 350
		end,
	},
	{
		name = "premium vehicle at Tier X",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_two).tier",
		mutate = function(b)
			addPremium(b).tier = 10
		end,
	},
	{
		name = "premium vehicle with a module tree",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_two).moduleTree",
		mutate = function(b)
			local premium = addPremium(b)
			premium.modules.guns = { "iu_gun_37mm", "iu_gun_45mm" }
			premium.stock = table.clone(premium.stock)
			premium.stock.gun = "iu_gun_37mm"
			premium.moduleTree = { { module = "iu_gun_45mm" } }
		end,
	},
	-- Vehicles: mechanics, apex, visuals --------------------------------------------------------------------------------
	{
		name = "siege mode on a heavy tank",
		code = "MECHANIC",
		path = "vehicles[3](iu_bulmal).mechanics[1]",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").mechanics = {
				{ kind = "SiegeMode", engageS = 2, disengageS = 1.25, maxSpeedKmh = 10, modifiers = {} },
			}
		end,
	},
	{
		name = "Tier XI signature on a Tier III vehicle",
		code = "MECHANIC",
		path = "vehicles[3](iu_bulmal).mechanics[1]",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").mechanics = {
				{ kind = "RocketBoost", charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 },
			}
		end,
	},
	{
		name = "mechanic listed twice",
		code = "MECHANIC",
		path = "vehicles[2](iu_ostmal).mechanics[2]",
		mutate = function(b)
			local hydro = { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 }
			find(b.vehicles, "iu_ostmal").mechanics = { hydro, table.clone(hydro) }
		end,
	},
	{
		name = "wheeled tracks without the Wheeled mechanic",
		code = "MECHANIC",
		path = "vehicles[1](iu_kolmal).mechanics",
		mutate = function(b)
			find(b.tracks, "iu_tracks_kolmal").wheeled = true
		end,
	},
	{
		name = "dual gun on a Tier III heavy",
		code = "MECHANIC",
		path = "vehicles[3](iu_bulmal).modules.guns(iu_gun_76mm)",
		mutate = function(b)
			find(b.guns, "iu_gun_76mm").reload =
				{ kind = "DualGun", reloadEachS = 8, salvoDelayS = 1.5, chargeTimeS = 1, volleyDispersionMul = 1.5 }
		end,
	},
	{
		name = "magazine gun on a Heavy Assault",
		code = "MECHANIC",
		path = "vehicles[3](iu_bulmal).modules.guns(iu_gun_76mm)",
		mutate = function(b)
			local bulmal = find(b.vehicles, "iu_bulmal")
			bulmal.class = "heavy"
			bulmal.role = "heavy_assault"
			find(b.guns, "iu_gun_76mm").reload = { kind = "Magazine", size = 3, intraClipS = 2, reloadS = 10 }
		end,
	},
	{
		name = "indirect gun on a tank",
		code = "MECHANIC",
		path = "vehicles[3](iu_bulmal).modules.guns(iu_gun_76mm)",
		mutate = function(b)
			find(b.guns, "iu_gun_76mm").indirect = true
		end,
	},
	{
		name = "apex track below Tier XI",
		code = "APEX",
		path = "vehicles[3](iu_bulmal).apex",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").apex =
				{ nodes = { { id = "n1", name = "Node", kind = "Small", xp = 4000, effects = {} } } }
		end,
	},
	{
		name = "Tier XI vehicle without an apex track or signature",
		code = "APEX",
		path = "vehicles[4](iu_apex).apex",
		mutate = function(b)
			local apex = table.clone(find(b.vehicles, "iu_kolmal"))
			apex.id = "iu_apex"
			apex.tier = 11
			apex.acquisition = "Event"
			apex.moduleTree = {}
			apex.unlocks = {}
			apex.price = {}
			table.insert(b.vehicles, apex)
		end,
	},
	{
		name = "turret ring wider than the hull",
		code = "VISUAL",
		path = "vehicles[1](iu_kolmal).visual.hull.turretRing.diameterM",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.hull.turretRing.diameterM = 3
		end,
	},
	{
		name = "ground clearance above the hull roof",
		code = "VISUAL",
		path = "vehicles[1](iu_kolmal).visual.hull.groundClearanceM",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.hull.groundClearanceM = 0.9
			find(b.vehicles, "iu_kolmal").visual.hull.heightM = 0.8
		end,
	},
	{
		name = "skirts without spaced-armor thickness",
		code = "ARMOR",
		path = "vehicles[1](iu_kolmal).visual.hull.skirts",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.hull.skirts = "Plates"
		end,
	},
	{
		name = "superstructure without armor values",
		code = "ARMOR",
		path = "vehicles[2](iu_ostmal).visual.hull.superstructure",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").visual.hull.superstructure =
				{ lengthM = 3, heightM = 0.6, positionFraction = 0.4, frontAngleDeg = 30 }
		end,
	},
	{
		name = "bustle ammo rack in a turret without a bustle",
		code = "LAYOUT",
		path = "vehicles[3](iu_bulmal).visual.layout.ammoRacks[1]",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").visual.layout.ammoRacks = { "Bustle" }
		end,
	},
	{
		name = "visual hook that is not snake_case",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_kolmal).visual.hooks[1]",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.hooks = { "Tractor Chassis" }
		end,
	},
	{
		name = "builder preset that is not snake_case",
		code = "BAD_VALUE",
		path = "vehicles[2](iu_ostmal).visual.preset",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").visual.preset = "IU-Foundry"
		end,
	},
	-- Branches and id prefixes ------------------------------------------------------------------------------------------
	{
		name = "vehicle id without its faction prefix",
		code = "BAD_VALUE",
		path = "vehicles[1](kolmal).id",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			kolmal.id = "kolmal"
			kolmal.unlocks = {}
		end,
	},
	{
		name = "branch id without its faction prefix",
		code = "BAD_VALUE",
		path = "branches[1](foundry).id",
		mutate = function(b)
			b.branches[1].id = "foundry"
		end,
	},
	{
		name = "vehicle in an unknown branch",
		code = "DANGLING_REF",
		path = "vehicles[1](iu_kolmal).tree.branch",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").tree.branch = "iu_nope"
		end,
	},
	{
		name = "vehicle in another faction's branch",
		code = "BRANCH",
		path = "vehicles[1](iu_kolmal).tree.branch",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").tree.branch = "dc_caravan"
		end,
	},
	{
		name = "vehicle class not carried by its branch",
		code = "BRANCH",
		path = "vehicles[1](iu_kolmal).tree.branch",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").tree.branch = "iu_ram"
		end,
	},
	{
		name = "vehicle tier outside its branch",
		code = "BRANCH",
		path = "vehicles[1](iu_kolmal).tree.branch",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").tree.branch = "iu_hammer"
		end,
	},
	{
		name = "branch with an unknown class",
		code = "BAD_VALUE",
		path = "branches[1](iu_foundry).classes[1]",
		mutate = function(b)
			b.branches[1].classes = { "tankette" }
		end,
	},
	{
		name = "internal volume override with a non-positive size",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_kolmal).visual.layout.overrides[1].sizeM",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.layout.overrides = {
				{ kind = "AmmoRack", group = "Hull", centerM = Vector3.new(0, 0.8, 0), sizeM = Vector3.new(1, 0, 1) },
			}
		end,
	},
	-- Equipment, consumables, crew, cosmetics ----------------------------------------------------------------------------
	{
		name = "modifier with an unknown stat",
		code = "BAD_VALUE",
		path = "equipment[1](rammer_assist_c).effects[1].stat",
		mutate = function(b)
			find(b.equipment, "rammer_assist_c").effects[1].stat = "reloadSpeed"
		end,
	},
	{
		name = "timed modifier without a duration",
		code = "BAD_VALUE",
		path = "equipment[1](rammer_assist_c).effects[1].durationS",
		mutate = function(b)
			find(b.equipment, "rammer_assist_c").effects[1].condition = "AfterShot"
		end,
	},
	{
		name = "Bullion-only equipment",
		code = "PRICE",
		path = "equipment[1](rammer_assist_c).price",
		mutate = function(b)
			find(b.equipment, "rammer_assist_c").price = { bullion = 100 }
		end,
	},
	{
		name = "class-scaled effects for an unknown class",
		code = "BAD_VALUE",
		path = "equipment[2](cam_netting_c).effectsByClass.tank",
		mutate = function(b)
			find(b.equipment, "cam_netting_c").effectsByClass.tank = {}
		end,
	},
	{
		name = "manual consumable without a cooldown",
		code = "MISSING_FIELD",
		path = "consumables[1](repair_kit).cooldownS",
		mutate = function(b)
			find(b.consumables, "repair_kit").cooldownS = nil
		end,
	},
	{
		name = "trigger delay on a manual consumable",
		code = "BAD_VALUE",
		path = "consumables[1](repair_kit).triggerDelayS",
		mutate = function(b)
			find(b.consumables, "repair_kit").triggerDelayS = 0.5
		end,
	},
	{
		name = "Bullion price undercutting credits",
		code = "PRICE",
		path = "consumables[2](auto_extinguisher).price",
		mutate = function(b)
			find(b.consumables, "auto_extinguisher").price.bullion = 25
		end,
	},
	{
		name = "crew skill for an unknown role",
		code = "BAD_VALUE",
		path = "crewSkills[1](snap_shot).roles[1]",
		mutate = function(b)
			find(b.crewSkills, "snap_shot").roles = { "RadioOperator" }
		end,
	},
	{
		name = "booster without a duration or battle count",
		code = "BAD_VALUE",
		path = "boosters[1](xp_booster)",
		mutate = function(b)
			find(b.boosters, "xp_booster").durationS = nil
		end,
	},
	{
		name = "paint without colours",
		code = "MISSING_FIELD",
		path = "customization[1](paint_foundry_red).colors",
		mutate = function(b)
			find(b.customization, "paint_foundry_red").colors = nil
		end,
	},
	{
		name = "customization scoped to an unknown vehicle",
		code = "DANGLING_REF",
		path = "customization[1](paint_foundry_red).scope.vehicles[1]",
		mutate = function(b)
			find(b.customization, "paint_foundry_red").scope.vehicles = { "iu_nope" }
		end,
	},
	-- Missions and achievements ------------------------------------------------------------------------------------------
	{
		name = "mission condition on an unknown stat",
		code = "BAD_VALUE",
		path = "missions[1](daily_hold_the_line).conditions[1].stat",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1].stat = "frags"
		end,
	},
	{
		name = "mission condition without a target",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).conditions[1]",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1].atLeast = nil
		end,
	},
	{
		name = "mission reward referencing unknown equipment",
		code = "DANGLING_REF",
		path = "missions[1](daily_hold_the_line).rewards[3].id",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").rewards[3].id = "rammer_nope"
		end,
	},
	{
		name = "currency reward with an id",
		code = "REWARD",
		path = "missions[1](daily_hold_the_line).rewards[1].id",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").rewards[1].id = "credits"
		end,
	},
	{
		name = "mission scope with minTier above maxTier",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).scope",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").scope.minTier = 8
			find(b.missions, "daily_hold_the_line").scope.maxTier = 4
		end,
	},
	{
		name = "event mission without its event",
		code = "MISSION",
		path = "missions[2](forge_week_daily).eventId",
		mutate = function(b)
			find(b.missions, "forge_week_daily").eventId = nil
		end,
	},
	{
		name = "mission names an event that does not list it",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).eventId",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").eventId = "forge_week"
		end,
	},
	{
		name = "campaign mission without its campaign block",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).campaign",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").cadence = "Campaign"
		end,
	},
	{
		name = "achievement thresholds not increasing",
		code = "BAD_VALUE",
		path = "achievements[2](veteran).thresholds[3]",
		mutate = function(b)
			find(b.achievements, "veteran").thresholds = { 100, 1000, 1000 }
		end,
	},
	{
		name = "achievement reading an unknown stat",
		code = "BAD_VALUE",
		path = "achievements[1](top_gun).stat",
		mutate = function(b)
			find(b.achievements, "top_gun").stat = "frags"
		end,
	},
	-- Maps -------------------------------------------------------------------------------------------------------------
	{
		name = "fewer than 15 spawns",
		code = "MAP_SPAWNS",
		path = "maps[1](proving_grounds).spawns.team1",
		mutate = function(b)
			table.remove(b.maps[1].spawns.team1, 1)
		end,
	},
	{
		name = "fewer than 3 rear spawns",
		code = "MAP_SPAWNS",
		path = "maps[1](proving_grounds).spawns.team2",
		mutate = function(b)
			for _, spawn in b.maps[1].spawns.team2 do
				spawn.rear = nil
			end
		end,
	},
	{
		name = "spawn slots on top of each other",
		code = "MAP_SPAWNS",
		path = "maps[1](proving_grounds).spawns.team1[2].at",
		mutate = function(b)
			b.maps[1].spawns.team1[2].at = { x = -115, z = -280 }
		end,
	},
	{
		name = "spawn outside the playable square",
		code = "MAP_BOUNDS",
		path = "maps[1](proving_grounds).spawns.team1[1].at",
		mutate = function(b)
			b.maps[1].spawns.team1[1].at = { x = -450, z = -280 }
		end,
	},
	{
		name = "spawn centroids too close",
		code = "MAP_SEPARATION",
		path = "maps[1](proving_grounds).spawns",
		mutate = function(b)
			for _, spawn in b.maps[1].spawns.team2 do
				spawn.at = { x = spawn.at.x, z = spawn.at.z - 200 }
			end
		end,
	},
	{
		name = "Standard battle type without one base per team",
		code = "MAP_BASES",
		path = "maps[1](proving_grounds).bases",
		mutate = function(b)
			table.remove(b.maps[1].bases, 2)
		end,
	},
	{
		name = "Encounter listed without a neutral base",
		code = "MAP_BASES",
		path = "maps[1](proving_grounds).bases",
		mutate = function(b)
			table.insert(b.maps[1].battleTypes, "Encounter")
		end,
	},
	{
		name = "capture circle too close to the edge",
		code = "MAP_BASES",
		path = "maps[1](proving_grounds).bases[1]",
		mutate = function(b)
			b.maps[1].bases[1].center = { x = 0, z = -320 }
		end,
	},
	{
		name = "no Open lane",
		code = "MAP_LANES",
		path = "maps[1](proving_grounds).lanes",
		mutate = function(b)
			b.maps[1].lanes[3].kind = "Heavy"
		end,
	},
	{
		name = "too few lanes",
		code = "MAP_LANES",
		path = "maps[1](proving_grounds).lanes",
		mutate = function(b)
			table.remove(b.maps[1].lanes, 3)
		end,
	},
	{
		name = "terrain without exactly one default material",
		code = "MAP_TERRAIN",
		path = "maps[1](proving_grounds).terrain.materials",
		mutate = function(b)
			table.insert(b.maps[1].terrain.materials, { material = "Sand", rule = "Default" })
		end,
	},
	{
		name = "foliage concealment above the stack cap",
		code = "BAD_VALUE",
		path = "maps[1](proving_grounds).foliage[1].concealment",
		mutate = function(b)
			b.maps[1].foliage[1].concealment = 0.95
		end,
	},
	-- Store, events, seasons ---------------------------------------------------------------------------------------------
	{
		name = "store item with both an in-game price and a Robux product",
		code = "STORE",
		path = "store[1](bullion_pack_s)",
		mutate = function(b)
			find(b.store, "bullion_pack_s").price = { credits = 10 }
		end,
	},
	{
		name = "Bullion pack that is not a Robux product",
		code = "STORE",
		path = "store[1](bullion_pack_s).robux",
		mutate = function(b)
			local pack = find(b.store, "bullion_pack_s")
			pack.robux = nil
			pack.price = { credits = 10 }
		end,
	},
	{
		name = "store grant referencing unknown cosmetics",
		code = "DANGLING_REF",
		path = "store[2](forge_week_paint).grants[1].id",
		mutate = function(b)
			find(b.store, "forge_week_paint").grants[1].id = "paint_nope"
		end,
	},
	{
		name = "event ending before it starts",
		code = "SCHEDULE",
		path = "events[1](forge_week)",
		mutate = function(b)
			find(b.events, "forge_week").endsAt = 1780000000
		end,
	},
	{
		name = "event shop closing before the event ends",
		code = "SCHEDULE",
		path = "events[1](forge_week).shopClosesAt",
		mutate = function(b)
			find(b.events, "forge_week").shopClosesAt = 1790000001
		end,
	},
	{
		name = "event listing an unknown mission",
		code = "DANGLING_REF",
		path = "events[1](forge_week).missions[2]",
		mutate = function(b)
			table.insert(find(b.events, "forge_week").missions, "mission_nope")
		end,
	},
	{
		name = "event mode on an unknown map",
		code = "DANGLING_REF",
		path = "events[1](forge_week).modes[1].maps[1]",
		mutate = function(b)
			find(b.events, "forge_week").modes[1].maps = { "map_nope" }
		end,
	},
	{
		name = "event ability of an unknown kind",
		code = "BAD_VALUE",
		path = "events[1](forge_week).modes[1].abilities[1].kind",
		mutate = function(b)
			find(b.events, "forge_week").modes[1].abilities[1].kind = "Nuke"
		end,
	},
	{
		name = "season points by rank not ascending",
		code = "SEASON",
		path = "seasons[1](season_1).pointsByRank[2].maxTeamRank",
		mutate = function(b)
			find(b.seasons, "season_1").pointsByRank[2].maxTeamRank = 2
		end,
	},
	{
		name = "season reward beyond the chapter's stages",
		code = "SEASON",
		path = "seasons[1](season_1).chapters[1].rewards[2].stage",
		mutate = function(b)
			find(b.seasons, "season_1").chapters[1].rewards[2].stage = 31
		end,
	},
	{
		name = "season paid unlock that is not a season pass",
		code = "SEASON",
		path = "seasons[1](season_1).paidUnlock",
		mutate = function(b)
			find(b.seasons, "season_1").paidUnlock = "bullion_pack_s"
		end,
	}, -- Review hardening (adversarial pass): every case below passed validate() before the fix --------------------
	-- Nested typos (the old solver ignores unknown keys in nested literals, so the registry must catch them)
	{
		name = "misspelt optional gun bloom field",
		code = "UNKNOWN_FIELD",
		path = "guns[2](iu_gun_45mm).bloom.movmentPerKmh",
		mutate = function(b)
			find(b.guns, "iu_gun_45mm").bloom = { movmentPerKmh = 0.05 }
		end,
	},
	{
		name = "misspelt optional mechanic field",
		code = "UNKNOWN_FIELD",
		path = "vehicles[3](iu_bulmal).mechanics[1].settle",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").mechanics = {
				{ kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75, settle = 1 },
			}
		end,
	},
	{
		name = "misspelt optional turret visual field",
		code = "UNKNOWN_FIELD",
		path = "turrets[4](iu_turret_bulmal_m2).visual.bustleLength",
		mutate = function(b)
			find(b.turrets, "iu_turret_bulmal_m2").visual.bustleLength = 0.6
		end,
	},
	{
		name = "misspelt optional spawn field",
		code = "UNKNOWN_FIELD",
		path = "maps[1](proving_grounds).spawns.team1[1].reer",
		mutate = function(b)
			b.maps[1].spawns.team1[1].reer = true
		end,
	},
	{
		name = "misspelt range bound",
		code = "UNKNOWN_FIELD",
		path = "branches[1](iu_foundry).tiers.maxx",
		mutate = function(b)
			b.branches[1].tiers.maxx = 4
		end,
	},
	{
		name = "misspelt running-gear field",
		code = "UNKNOWN_FIELD",
		path = "vehicles[1](iu_kolmal).visual.running.returnRoller",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.running.returnRoller = 2
		end,
	},
	{
		name = "map random-event props were never validated",
		code = "MAP_BOUNDS",
		path = "maps[1](proving_grounds).randomEvents[1].props[1].at",
		mutate = function(b)
			b.maps[1].randomEvents =
				{ { id = "rockfall", chance = 0.1, props = { { prop = "rock_large", at = { x = 5000, z = 0 } } } } }
		end,
	},
	-- Shells and guns
	{
		name = "stunning shell on a direct-fire gun",
		code = "SHELL_KIND",
		path = "guns[1](iu_gun_37mm).shells[3]",
		message = "only artillery",
		mutate = function(b)
			find(b.shells, "iu_37mm_he").stun = { maxS = 3, minS = 1 }
		end,
	},
	{
		name = "artillery shell with the direct-fire range",
		code = "SHELL_KIND",
		path = "guns[4](iu_gun_76mm).shells[1]",
		message = "maxRangeM",
		mutate = function(b)
			local gun = find(b.guns, "iu_gun_76mm")
			gun.indirect = true
			gun.arcs.elevationDeg = 50
		end,
	},
	{
		name = "howitzer that cannot elevate to 45°",
		code = "BAD_VALUE",
		path = "guns[4](iu_gun_76mm).arcs.elevationDeg",
		mutate = function(b)
			find(b.guns, "iu_gun_76mm").indirect = true
		end,
	},
	{
		name = "magazine larger than the ammo capacity",
		code = "BAD_VALUE",
		path = "guns[2](iu_gun_45mm).reload.size",
		mutate = function(b)
			local gun = find(b.guns, "iu_gun_45mm")
			gun.reload = { kind = "Magazine", size = 6, intraClipS = 2, reloadS = 12 }
			gun.ammoCapacity = 5
		end,
	},
	-- Mounts and mechanics
	{
		name = "casemate superstructure on a medium tank",
		code = "MOUNT",
		path = "vehicles[1](iu_kolmal).modules.turrets[1]",
		mutate = function(b)
			local turret = find(b.turrets, "iu_turret_kolmal")
			turret.mount = "Casemate"
			turret.yawLimitsDeg = { left = 11, right = 11 }
			turret.visual.style = "Casemate"
		end,
	},
	{
		name = "siege mode on an assault tank destroyer",
		code = "MECHANIC",
		path = "vehicles[3](iu_bulmal).mechanics[1]",
		message = "Sniper and Support",
		mutate = function(b)
			local bulmal = find(b.vehicles, "iu_bulmal")
			bulmal.class = "td"
			bulmal.role = "td_assault"
			bulmal.mechanics = {
				{ kind = "SiegeMode", engageS = 2, disengageS = 1.25, maxSpeedKmh = 10, modifiers = {} },
			}
		end,
	},
	{
		name = "charged shot with the other effect's field",
		code = "MECHANIC",
		path = "vehicles[4](iu_apex).mechanics[1].damageMul",
		mutate = function(b)
			addApex(b).mechanics[1].damageMul = 1.1
		end,
	},
	{
		name = "Apex with a Tier I-X mechanic",
		code = "MECHANIC",
		path = "vehicles[4](iu_apex).mechanics[2]",
		message = "no Tier I–X mechanic",
		mutate = function(b)
			table.insert(
				addApex(b).mechanics,
				{ kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 }
			)
		end,
	},
	{
		name = "Apex with an autoreloader",
		code = "MECHANIC",
		path = "vehicles[4](iu_apex).modules.guns(iu_gun_45mm)",
		message = "Tier I–X",
		mutate = function(b)
			addApex(b)
			find(b.guns, "iu_gun_45mm").reload =
				{ kind = "Autoreloader", size = 3, perShellReloadS = { 4, 3, 3 }, intraClipS = 1.5 }
		end,
	},
	{
		name = "adaptive magazine on a single-shot gun",
		code = "MECHANIC",
		path = "vehicles[4](iu_apex).modules.guns(iu_gun_45mm)",
		message = "AdaptiveMagazine needs a Magazine gun",
		mutate = function(b)
			addApex(b).mechanics = { { kind = "AdaptiveMagazine", partialReloadFactor = 0.35 } }
		end,
	},
	{
		name = "Apex node track of the wrong shape",
		code = "APEX",
		path = "vehicles[4](iu_apex).apex.nodes",
		mutate = function(b)
			table.remove(addApex(b).apex.nodes, 1)
		end,
	},
	{
		name = "special mechanics above 20 % of the Tier I-X roster",
		code = "MECHANIC",
		path = "vehicles",
		warning = true,
		mutate = function(b)
			addRewardCopies(b, 20, 5)
		end,
	},
	-- Crew and armor consistency
	{
		name = "driving as a secondary duty",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_ostmal).crew[2].also[1]",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").crew[2].also = { "Driver" }
		end,
	},
	{
		name = "two driver seats",
		code = "CREW_COMPOSITION",
		path = "vehicles[3](iu_bulmal).crew",
		message = "Driver seat",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").crew[5] = { role = "Driver" }
		end,
	},
	{
		name = "skirt armor on a hull without skirts",
		code = "ARMOR",
		path = "vehicles[1](iu_kolmal).visual.hull.skirts",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").hull.armor.skirts = 6
		end,
	},
	{
		name = "superstructure armor on a hull without a superstructure",
		code = "ARMOR",
		path = "vehicles[1](iu_kolmal).visual.hull.superstructure",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").hull.armor.superstructureFront = 30
		end,
	},
	{
		name = "crew seat placed twice",
		code = "LAYOUT",
		path = "vehicles[1](iu_kolmal).visual.layout.crewSeats[2].slot",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.layout.crewSeats = {
				{ slot = 1, centerM = Vector3.new(0, 1, 0) },
				{ slot = 1, centerM = Vector3.new(0, 1, -1) },
			}
		end,
	},
	-- Research and acquisition
	{
		name = "gun researchable before the only turret that mounts it",
		code = "MODULE_TREE",
		path = "vehicles[3](iu_bulmal).moduleTree[3](iu_gun_76mm).requires",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").moduleTree[3].requires = nil
		end,
	},
	{
		name = "turret researchable before the tracks that can carry it",
		code = "MODULE_TREE",
		path = "vehicles[3](iu_bulmal).moduleTree[2](iu_turret_bulmal_m2).requires",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").moduleTree[2].requires = nil
		end,
	},
	{
		name = "tech-tree vehicle outside every branch",
		code = "BRANCH",
		path = "vehicles[2](iu_ostmal).tree.branch",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").tree.branch = nil
		end,
	},
	{
		name = "premium vehicle with a credit price",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_two).price",
		message = "Bullion only",
		mutate = function(b)
			addPremium(b).price = { bullion = 250, credits = 1000 }
		end,
	},
	{
		name = "reward vehicle with a price",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_two).price",
		message = "not sold",
		mutate = function(b)
			local reward = addPremium(b)
			reward.acquisition = "Reward"
			reward.price = { credits = 5000 }
		end,
	},
	{
		name = "tech-tree vehicle priced in Campaign Tokens",
		code = "ACQUISITION",
		path = "vehicles[2](iu_ostmal).price",
		message = "credits only",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").price.campaignTokens = 100
		end,
	},
	-- Tiers
	{
		name = "one-sided tier matchmaking range",
		code = "TIER_RANGE",
		path = "tiers[5](5).matchmaking",
		mutate = function(b)
			find(b.tiers, 5).matchmaking = { min = 3, max = 7 }
		end,
	},
	{
		name = "field kit below Tier VI",
		code = "BAD_VALUE",
		path = "tiers[5](5).fieldKit",
		mutate = function(b)
			find(b.tiers, 5).fieldKit = { levels = 3, xpPerLevel = 1000 }
		end,
	},
	{
		name = "category slot below Tier VI",
		code = "BAD_VALUE",
		path = "tiers[5](5).categorySlot",
		mutate = function(b)
			find(b.tiers, 5).categorySlot = true
		end,
	},
	-- Loadout items
	{
		name = "Standard equipment without a credit price",
		code = "PRICE",
		path = "equipment[1](rammer_assist_c).price.credits",
		mutate = function(b)
			find(b.equipment, "rammer_assist_c").price = { campaignTokens = 3000 }
		end,
	},
	{
		name = "Refined equipment without a Campaign Token price",
		code = "PRICE",
		path = "equipment[1](rammer_assist_c).price.campaignTokens",
		mutate = function(b)
			find(b.equipment, "rammer_assist_c").grade = "Refined"
		end,
	},
	{
		name = "charges on a passive consumable",
		code = "BAD_VALUE",
		path = "consumables[3](smoke_screen).charges",
		mutate = function(b)
			local smoke = find(b.consumables, "smoke_screen")
			smoke.activation = "Passive"
			smoke.cooldownS = nil
		end,
	},
	{
		name = "timed consumable effects without a duration",
		code = "MISSING_FIELD",
		path = "consumables[3](smoke_screen).durationS",
		mutate = function(b)
			find(b.consumables, "smoke_screen").durationS = nil
		end,
	},
	-- Missions, achievements, rewards
	{
		name = "daily mission without a difficulty slot",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).difficulty",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").difficulty = nil
		end,
	},
	{
		name = "difficulty on a non-daily mission",
		code = "MISSION",
		path = "missions[2](forge_week_daily).difficulty",
		mutate = function(b)
			find(b.missions, "forge_week_daily").difficulty = "Hard"
		end,
	},
	{
		name = "team XP rank counted cumulatively",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).conditions[1]",
		message = "teamXpRank",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1] =
				{ stat = "teamXpRank", atMost = 3, aggregate = "Cumulative" }
		end,
	},
	{
		name = "against-class filter on a stat that cannot be split",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).conditions[1].against",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1].against = { classes = { "heavy" } }
		end,
	},
	{
		name = "event listing a mission that names no event",
		code = "MISSION",
		path = "events[1](forge_week).missions[2]",
		mutate = function(b)
			table.insert(find(b.events, "forge_week").missions, "daily_hold_the_line")
		end,
	},
	{
		name = "milestone without thresholds",
		code = "MISSING_FIELD",
		path = "achievements[2](veteran).thresholds",
		mutate = function(b)
			find(b.achievements, "veteran").thresholds = nil
		end,
	},
	{
		name = "mastery badge that is not per vehicle",
		code = "BAD_VALUE",
		path = "achievements[2](veteran).perVehicle",
		mutate = function(b)
			local a = find(b.achievements, "veteran")
			a.kind = "Mastery"
			a.category = "Mastery"
		end,
	},
	{
		name = "achievement scope with minTier above maxTier",
		code = "BAD_VALUE",
		path = "achievements[1](top_gun).scope",
		mutate = function(b)
			find(b.achievements, "top_gun").scope = { minTier = 9, maxTier = 5 }
		end,
	},
	{
		name = "vehicle granted twice by one reward",
		code = "REWARD",
		path = "missions[1](daily_hold_the_line).rewards[4].amount",
		mutate = function(b)
			table.insert(
				find(b.missions, "daily_hold_the_line").rewards,
				{ kind = "Vehicle", id = "iu_ostmal", amount = 2 }
			)
		end,
	},
	-- Store, events, ranked seasons
	{
		name = "Bullion pack sold as a game pass",
		code = "STORE",
		path = "store[1](bullion_pack_s).robux.kind",
		mutate = function(b)
			find(b.store, "bullion_pack_s").robux.kind = "GamePass"
		end,
	},
	{
		name = "premium-vehicle store item granting a tech-tree vehicle",
		code = "STORE",
		path = "store[4](premium_ostmal).grants",
		mutate = function(b)
			table.insert(b.store, {
				id = "premium_ostmal",
				name = "Ostmal",
				description = "Not a premium.",
				kind = "PremiumVehicle",
				price = { bullion = 250 },
				grants = { { kind = "Vehicle", id = "iu_ostmal", amount = 1 } },
			})
		end,
	},
	{
		name = "event-token item outside its event's shop",
		code = "STORE",
		path = "store[2](forge_week_paint).price.eventTokens",
		mutate = function(b)
			find(b.events, "forge_week").shop = {}
		end,
	},
	{
		name = "event shop item not priced in the event's tokens",
		code = "STORE",
		path = "events[1](forge_week).shop[2]",
		mutate = function(b)
			table.insert(find(b.events, "forge_week").shop, "season_pass_1")
		end,
	},
	{
		name = "event mode on a map without the mode's battle type",
		code = "SCHEDULE",
		path = "events[1](forge_week).modes[1].maps[1]",
		mutate = function(b)
			find(b.events, "forge_week").modes[1].battleTypes = { "Encounter" }
		end,
	},
	{
		name = "ranked event without a ladder",
		code = "SEASON",
		path = "events[2](ranked_s1).modes",
		mutate = function(b)
			find(b.events, "ranked_s1").modes[1].ladder = nil
		end,
	},
	{
		name = "ladder on an event that is not Ranked",
		code = "SEASON",
		path = "events[1](forge_week).modes[1].ladder",
		mutate = function(b)
			find(b.events, "forge_week").modes[1].ladder = table.clone(find(b.events, "ranked_s1").modes[1].ladder)
		end,
	},
	{
		name = "ladder whose top rank still needs points",
		code = "SEASON",
		path = "events[2](ranked_s1).modes[1].ladder.ranks[3].pointsToAdvance",
		mutate = function(b)
			find(b.events, "ranked_s1").modes[1].ladder.ranks[3].pointsToAdvance = 100
		end,
	},
	{
		name = "pass stage rewarded twice on the same track",
		code = "SEASON",
		path = "seasons[1](season_1).chapters[1].rewards[3]",
		mutate = function(b)
			table.insert(
				find(b.seasons, "season_1").chapters[1].rewards,
				{ stage = 1, track = "Free", rewards = { { kind = "Credits", amount = 1 } } }
			)
		end,
	},
	-- Maps
	{
		name = "too few hull-down positions for a team",
		code = "MAP_POSITIONS",
		path = "maps[1](proving_grounds).positions",
		message = "team 1 needs 3 HullDown",
		mutate = function(b)
			table.remove(b.maps[1].positions, 1)
		end,
	},
	{
		name = "no artillery pit on a map artillery can play",
		code = "MAP_POSITIONS",
		path = "maps[1](proving_grounds).positions",
		message = "Artillery",
		mutate = function(b)
			b.maps[1].tierRange = { min = 3, max = 5 }
		end,
	},
	{
		name = "position on an unknown lane",
		code = "DANGLING_REF",
		path = "maps[1](proving_grounds).positions[1].lane",
		mutate = function(b)
			b.maps[1].positions[1].lane = "north_ridge"
		end,
	},
	{
		name = "reverse faster than forward",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_kolmal).mobility.reverseKmh",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").mobility.reverseKmh = 40
		end,
	},
	{
		name = "arc sector that widens the gun's arc",
		code = "BAD_VALUE",
		path = "vehicles[3](iu_bulmal).arcSectors[1].depressionDeg",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").arcSectors[1].depressionDeg = 9
		end,
	},
	{
		name = "researchable module that costs no XP",
		code = "MODULE_TREE",
		path = "vehicles[3](iu_bulmal).moduleTree[4].module",
		message = "researchXp",
		mutate = function(b)
			find(b.engines, "iu_engine_d250").researchXp = 0
		end,
	},
	{
		name = "module qualifier on a stat that has no module",
		code = "BAD_VALUE",
		path = "equipment[1](rammer_assist_c).effects[1].module",
		mutate = function(b)
			find(b.equipment, "rammer_assist_c").effects[1].module = "Engine"
		end,
	},
	{
		name = "two factions sharing an id prefix",
		code = "BAD_VALUE",
		path = "factions[2](crown_industries).idPrefix",
		mutate = function(b)
			find(b.factions, "crown_industries").idPrefix = "iu"
		end,
	},
	{
		name = "turret listing a gun twice",
		code = "BAD_VALUE",
		path = "turrets[1](iu_turret_kolmal).guns[2]",
		mutate = function(b)
			find(b.turrets, "iu_turret_kolmal").guns = { "iu_gun_37mm", "iu_gun_37mm", "iu_gun_45mm" }
		end,
	},
	{
		name = "equipment without any effect",
		code = "BAD_VALUE",
		path = "equipment[1](rammer_assist_c).effects",
		mutate = function(b)
			local rammer = find(b.equipment, "rammer_assist_c")
			rammer.effects = {}
			rammer.categorySlotEffects = nil
		end,
	},
	{
		name = "repair kit that repairs nothing",
		code = "MISSING_FIELD",
		path = "consumables[1](repair_kit).repairs.modules",
		mutate = function(b)
			find(b.consumables, "repair_kit").repairs = { crew = true }
		end,
	},
	{
		name = "camo bonus on an emblem",
		code = "BAD_VALUE",
		path = "customization[1](paint_foundry_red).camoBonus",
		mutate = function(b)
			local paint = find(b.customization, "paint_foundry_red")
			paint.kind = "Emblem"
		end,
	},
	{
		name = "two missions in one campaign slot",
		code = "MISSION",
		path = "missions[3](campaign_b).campaign",
		mutate = function(b)
			local campaign = { campaignId = "assault_line", operation = 1, series = "Assault", index = 1 }
			for _, id in { "campaign_a", "campaign_b" } do
				local m = table.clone(find(b.missions, "daily_hold_the_line"))
				m.id = id
				m.cadence = "Campaign"
				m.difficulty = nil
				m.campaign = table.clone(campaign)
				table.insert(b.missions, m)
			end
			table.remove(b.missions, 2) -- keep the indices simple: daily, campaign_a, campaign_b
			find(b.events, "forge_week").missions = {}
		end,
	},
	{
		name = "achievement rule with no evaluator (catalogue given)",
		code = "DANGLING_REF",
		path = "achievements[2](veteran).rule",
		options = { achievementRules = { mostOnTeam = true } },
		mutate = function(_b) end,
	},
	{
		name = "standard base on the enemy's side",
		code = "MAP_BASES",
		path = "maps[1](proving_grounds).bases[1].team",
		mutate = function(b)
			b.maps[1].bases[1].team = 2
			b.maps[1].bases[2].team = 1
		end,
	},
	{
		name = "spawn slot in a pond",
		code = "MAP_SPAWNS",
		path = "maps[1](proving_grounds).spawns.team1[1].at",
		mutate = function(b)
			table.insert(b.maps[1].water, {
				id = "spawn_pond",
				points = {
					{ x = -130, z = -290 },
					{ x = -110, z = -290 },
					{ x = -110, z = -270 },
					{ x = -130, z = -270 },
				},
				surfaceHeightM = 17,
				depthM = 2,
			})
		end,
	},
	{
		name = "single-point road",
		code = "MAP_TERRAIN",
		path = "maps[1](proving_grounds).terrain.features[7].points",
		mutate = function(b)
			b.maps[1].terrain.features[7].points = { { x = 0, z = 0 } }
		end,
	},
	{
		name = "tech-tree vehicle sold in the store",
		code = "STORE",
		path = "store[2](forge_week_paint).grants[2]",
		mutate = function(b)
			table.insert(find(b.store, "forge_week_paint").grants, { kind = "Vehicle", id = "iu_ostmal", amount = 1 })
		end,
	},
	{
		name = "store item that does not grant what its kind sells",
		code = "STORE",
		path = "store[1](bullion_pack_s).grants",
		mutate = function(b)
			find(b.store, "bullion_pack_s").grants = { { kind = "Credits", amount = 50000 } }
		end,
	},
	{
		name = "paid pass reward without a paid unlock",
		code = "SEASON",
		path = "seasons[1](season_1).chapters[1].rewards[2].track",
		mutate = function(b)
			find(b.seasons, "season_1").paidUnlock = nil
		end,
	},
	{
		name = "field kit option id reused within a role",
		code = "BAD_VALUE",
		path = "roles[1](light_scout).fieldKit[2].options[1].id",
		mutate = function(b)
			local option = { id = "fk_scout", name = "Option", description = "Text.", effects = {} }
			find(b.roles, "light_scout").fieldKit = {
				{ options = { table.clone(option), { id = "fk_b", name = "B", description = "Text.", effects = {} } } },
				{ options = { table.clone(option), { id = "fk_c", name = "C", description = "Text.", effects = {} } } },
			}
		end,
	},
	{
		name = "capture base id that is not snake_case",
		code = "BAD_VALUE",
		path = "maps[1](proving_grounds).bases[1].id",
		mutate = function(b)
			b.maps[1].bases[1].id = "Base North"
		end,
	},
	{
		name = "reserve tracks on a Tier III vehicle",
		code = "MECHANIC",
		path = "vehicles[3](iu_bulmal).mechanics[1]",
		message = "Tier XI signature",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").mechanics =
				{ { kind = "ReserveTracks", charges = 1, repairS = 2, cooldownS = 60 } }
		end,
	},
	{
		name = "two mechanics on the one mechanic key",
		code = "MECHANIC",
		path = "vehicles[4](iu_apex).mechanics",
		message = "share the one mechanic key",
		mutate = function(b)
			local apex = addApex(b)
			apex.acquisition = "Event"
			apex.mechanics = {
				{ kind = "Turbo", powerMul = 1.25, durationS = 6, cooldownS = 40 },
				{ kind = "RocketBoost", charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 },
			}
		end,
	},
	{
		name = "slope material rule without bounds",
		code = "MAP_TERRAIN",
		path = "maps[1](proving_grounds).terrain.materials[1]",
		mutate = function(b)
			b.maps[1].terrain.materials[1].min = nil
		end,
	},
	-- Adversarial review (2026-10-06): each case below passed validate() before the rule existed ---------------
	{
		name = "unlock gated on a stock module",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_kolmal).unlocks[1].requires",
		warning = true,
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").unlocks[1].requires = "iu_gun_37mm"
		end,
	},
	{
		name = "tech-tree vehicle off its branch's row",
		code = "BRANCH",
		path = "vehicles[2](iu_ostmal).tree.row",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").tree.row = 3
		end,
	},
	{
		name = "casemate gun mount on a hull with no fighting compartment",
		code = "MOUNT",
		path = "vehicles[1](iu_kolmal).visual.hull",
		message = "fighting compartment",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			kolmal.class = "td"
			kolmal.role = "td_support"
			local turret = find(b.turrets, "iu_turret_kolmal")
			turret.mount = "Casemate"
			turret.visual.style = "Casemate"
			turret.yawLimitsDeg = { left = 11, right = 11 }
		end,
	},
	{
		name = "rotating turret on a Casemate hull",
		code = "MOUNT",
		path = "vehicles[1](iu_kolmal).visual.hull.style",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.hull.style = "Casemate"
		end,
	},
	{
		name = "vehicle mixing a rotating turret and a casemate mount",
		code = "MOUNT",
		path = "vehicles[3](iu_bulmal).modules.turrets",
		mutate = function(b)
			local bulmal = find(b.vehicles, "iu_bulmal")
			bulmal.class = "td"
			bulmal.role = "td_support"
			local dome = find(b.turrets, "iu_turret_bulmal_m2")
			dome.mount = "Casemate"
			dome.visual.style = "Casemate"
			dome.yawLimitsDeg = { left = 10, right = 10 }
		end,
	},
	{
		name = "Casemate visual style on a rotating turret",
		code = "MOUNT",
		path = "turrets[1](iu_turret_kolmal).visual.style",
		message = "for casemate gun mounts",
		mutate = function(b)
			find(b.turrets, "iu_turret_kolmal").visual.style = "Casemate"
		end,
	},
	{
		name = "rotating turret smaller than its ring",
		code = "VISUAL",
		path = "vehicles[1](iu_kolmal).visual.hull.turretRing.diameterM",
		message = "does not cover",
		mutate = function(b)
			find(b.turrets, "iu_turret_kolmal").visual.widthM = 0.8
		end,
	},
	{
		name = "ChargedShot on a magazine gun",
		code = "MECHANIC",
		path = "vehicles[4](iu_apex).modules.guns(iu_gun_45mm)",
		message = "ChargedShot rides the fire trigger",
		mutate = function(b)
			addApex(b)
			find(b.guns, "iu_gun_45mm").reload = { kind = "Magazine", size = 3, intraClipS = 2, reloadS = 12 }
		end,
	},
	{
		name = "Wheeled vehicle drawn on tracked suspension",
		code = "MECHANIC",
		path = "vehicles[1](iu_kolmal).visual.running.suspension",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			kolmal.class = "light"
			kolmal.role = "light_versatile"
			kolmal.mechanics = {
				{
					kind = "Wheeled",
					wheelPairs = 4,
					speedModeTopSpeedMul = 1.3,
					speedModeSteeringMul = 0.6,
					speedModeReverseMul = 0.7,
					toggleS = 1,
					lostPairSpeedMul = 0.75,
					movingDispersionMul = 1.15,
					turnRadiusM = 8,
				},
			}
			find(b.tracks, "iu_tracks_kolmal").wheeled = true
		end,
	},
	{
		name = "Wheeled mechanic with a wheel-pair count the model does not draw",
		code = "MECHANIC",
		path = "vehicles[1](iu_kolmal).mechanics[1].wheelPairs",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			kolmal.class = "light"
			kolmal.role = "light_versatile"
			kolmal.visual.running.suspension = "Wheeled"
			kolmal.mechanics = {
				{
					kind = "Wheeled",
					wheelPairs = 3,
					speedModeTopSpeedMul = 1.3,
					speedModeSteeringMul = 0.6,
					speedModeReverseMul = 0.7,
					toggleS = 1,
					lostPairSpeedMul = 0.75,
					movingDispersionMul = 1.15,
					turnRadiusM = 8,
				},
			}
			find(b.tracks, "iu_tracks_kolmal").wheeled = true
		end,
	},
	{
		name = "wheeled vehicle with neutral steer",
		code = "MECHANIC",
		path = "vehicles[1](iu_kolmal).mobility.pivot",
		mutate = function(b)
			local kolmal = find(b.vehicles, "iu_kolmal")
			kolmal.class = "light"
			kolmal.role = "light_versatile"
			kolmal.visual.running.suspension = "Wheeled"
			kolmal.mobility.pivot = true
			kolmal.mechanics = {
				{
					kind = "Wheeled",
					wheelPairs = 4,
					speedModeTopSpeedMul = 1.3,
					speedModeSteeringMul = 0.6,
					speedModeReverseMul = 0.7,
					toggleS = 1,
					lostPairSpeedMul = 0.75,
					movingDispersionMul = 1.15,
					turnRadiusM = 8,
				},
			}
			find(b.tracks, "iu_tracks_kolmal").wheeled = true
		end,
	},
	{
		name = "Wheeled suspension without the Wheeled mechanic",
		code = "MECHANIC",
		path = "vehicles[1](iu_kolmal).visual.running.suspension",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.running.suspension = "Wheeled"
		end,
	},
	{
		name = "mission granting a tech-tree vehicle (research bypass)",
		code = "REWARD",
		path = "missions[1](daily_hold_the_line).rewards[4].id",
		mutate = function(b)
			table.insert(
				find(b.missions, "daily_hold_the_line").rewards,
				{ kind = "Vehicle", id = "iu_ostmal", amount = 1 }
			)
		end,
	},
	{
		name = "consumable with no credit price",
		code = "PRICE",
		path = "consumables[1](repair_kit).price",
		mutate = function(b)
			find(b.consumables, "repair_kit").price = { campaignTokens = 100 }
		end,
	},
	{
		name = "smoke consumable usable in Random battles",
		code = "BAD_VALUE",
		path = "consumables[3](smoke_screen).eventOnly",
		mutate = function(b)
			find(b.consumables, "smoke_screen").eventOnly = nil
		end,
	},
	{
		name = "arc sector whose ends are the same bearing",
		code = "BAD_VALUE",
		path = "vehicles[3](iu_bulmal).arcSectors[1]",
		message = "same bearing",
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").arcSectors[1].toDeg = 150
		end,
	},
	{
		name = "Tier VI vehicle whose role defines no Field Kit",
		code = "FIELD_KIT",
		path = "vehicles[4](iu_reward_1).role",
		mutate = function(b)
			addRewardCopies(b, 1, 0)
			find(b.vehicles, "iu_reward_1").tier = 6
		end,
	},
	{
		name = "duplicate map variant id",
		code = "BAD_VALUE",
		path = "maps[1](proving_grounds).variants[2].id",
		message = "duplicate",
		mutate = function(b)
			b.maps[1].variants[2].id = "midday"
		end,
	},
	{
		name = "duplicate water body id",
		code = "BAD_VALUE",
		path = "maps[1](proving_grounds).water[2].id",
		message = "duplicate",
		mutate = function(b)
			b.maps[1].water[2].id = "mill_pond_east"
		end,
	},
	{
		name = "duplicate random-event id",
		code = "BAD_VALUE",
		path = "maps[1](proving_grounds).randomEvents[2].id",
		message = "duplicate",
		mutate = function(b)
			b.maps[1].randomEvents = {
				{ id = "bridge_out", chance = 0.1, props = {} },
				{ id = "bridge_out", chance = 0.1, props = {} },
			}
		end,
	},
	{
		name = "duplicate event-mode ability id",
		code = "BAD_VALUE",
		path = "events[1](forge_week).modes[1].abilities[2].id",
		mutate = function(b)
			local abilities = find(b.events, "forge_week").modes[1].abilities
			table.insert(abilities, table.clone(abilities[1]))
		end,
	},
	{
		name = "class lists a role twice",
		code = "BAD_VALUE",
		path = "classes[1](light).roles[4]",
		mutate = function(b)
			table.insert(find(b.classes, "light").roles, "light_scout")
		end,
	},
	{
		name = "two classes share a UI order",
		code = "BAD_VALUE",
		path = "classes[2](medium).order",
		mutate = function(b)
			find(b.classes, "medium").order = 1
		end,
	},
	{
		name = "equipment spanning two price bands",
		code = "BAD_VALUE",
		path = "equipment[1](rammer_assist_c).tiers",
		message = "spans equipment bands",
		mutate = function(b)
			find(b.equipment, "rammer_assist_c").tiers = { min = 2, max = 6 }
		end,
	},
	{
		name = "equipment compatibility with inverted mass bounds",
		code = "BAD_VALUE",
		path = "equipment[1](rammer_assist_c).compatibility",
		mutate = function(b)
			local c = find(b.equipment, "rammer_assist_c").compatibility
			c.minMassKg = 50000
			c.maxMassKg = 10000
		end,
	},
	{
		name = "category slot override below Tier VI",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_kolmal).slots.categorySlot",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").slots = { categorySlot = "Firepower" }
		end,
	},
	{
		name = "artillery gun with a kinetic round",
		code = "SHELL_KIND",
		path = "guns[4](iu_gun_76mm).shells[1]",
		message = "HE/HESH only",
		mutate = function(b)
			local gun = find(b.guns, "iu_gun_76mm")
			gun.indirect = true
			gun.arcs.elevationDeg = 60
			for _, shellId in gun.shells do
				find(b.shells, shellId).maxRangeM = 1200
			end
		end,
	},
	{
		name = "ricochet angle on an HE shell",
		code = "SHELL_KIND",
		path = "shells[3](iu_37mm_he).ricochetAngleDeg",
		mutate = function(b)
			find(b.shells, "iu_37mm_he").ricochetAngleDeg = 70
		end,
	},
	{
		name = "dual gun with a single round of ammunition",
		code = "BAD_VALUE",
		path = "guns[4](iu_gun_76mm).ammoCapacity",
		mutate = function(b)
			local gun = find(b.guns, "iu_gun_76mm")
			gun.reload =
				{ kind = "DualGun", reloadEachS = 8, salvoDelayS = 1.5, chargeTimeS = 1, volleyDispersionMul = 1.5 }
			gun.ammoCapacity = 1
		end,
	},
	{
		name = "autoreloader whose first refill is not the longest",
		code = "BAD_VALUE",
		path = "guns[4](iu_gun_76mm).reload.perShellReloadS",
		warning = true,
		mutate = function(b)
			find(b.guns, "iu_gun_76mm").reload =
				{ kind = "Autoreloader", size = 3, perShellReloadS = { 6, 7, 9 }, intraClipS = 2 }
		end,
	},
	{
		name = "two overlapping pass seasons",
		code = "SEASON",
		path = "seasons[2](season_2)",
		message = "overlaps season season_1",
		mutate = function(b)
			local second = table.clone(b.seasons[1])
			second.id = "season_2"
			second.startsAt = b.seasons[1].endsAt - 86400
			second.endsAt = b.seasons[1].endsAt + 30 * 86400
			table.insert(b.seasons, second)
		end,
	},
	{
		name = "game pass sold more than once per account",
		code = "STORE",
		path = "store[4](foundry_red_pass).purchaseLimit",
		mutate = function(b)
			table.insert(b.store, {
				id = "foundry_red_pass",
				name = "Foundry Red",
				description = "Permanent paint.",
				kind = "Customization",
				robux = { kind = "GamePass", productId = 7 },
				grants = { { kind = "Customization", id = "paint_foundry_red", amount = 1 } },
			})
		end,
	},
	{
		name = "competitive mode that allows artillery",
		code = "BAD_VALUE",
		path = "events[2](ranked_s1).modes[1].classCaps.artillery",
		mutate = function(b)
			find(b.events, "ranked_s1").modes[1].classCaps.artillery = 1
		end,
	},
	{
		name = "Mastery achievement filed under another category",
		code = "BAD_VALUE",
		path = "achievements[2](veteran).category",
		mutate = function(b)
			local veteran = find(b.achievements, "veteran")
			veteran.kind = "Mastery"
			veteran.perVehicle = true
		end,
	},
	{
		name = "top configuration keeps a stock module although an upgrade exists",
		code = "CONFIG_INVALID",
		path = "vehicles[3](iu_bulmal).top.engine",
		warning = true,
		mutate = function(b)
			find(b.vehicles, "iu_bulmal").top.engine = "iu_engine_d210"
		end,
	},
	{
		name = "vehicle id equal to a branch id",
		code = "BAD_VALUE",
		path = "vehicles[2](iu_foundry).id",
		message = "branch id",
		mutate = function(b)
			find(b.vehicles, "iu_ostmal").id = "iu_foundry"
		end,
	},
	{
		name = "Encounter listed on a Tier I-III map",
		code = "MAP_BASES",
		path = "maps[1](proving_grounds).battleTypes",
		message = "starts at Tier IV",
		warning = true,
		mutate = function(b)
			local map = b.maps[1]
			table.insert(map.battleTypes, "Encounter")
			table.insert(map.bases, { id = "base_centre", battleType = "Encounter", center = { x = 0, z = 0 } })
		end,
	},
	{
		name = "medal filter on a stat other than medals",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).conditions[1].medal",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1].medal = "top_gun"
		end,
	},
	{
		name = "medal filter naming a milestone",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).conditions[1].medal",
		message = "not a battle medal",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1] =
				{ stat = "medals", atLeast = 1, aggregate = "Cumulative", medal = "veteran" }
		end,
	},
	{
		name = "medal filter naming an unknown achievement",
		code = "DANGLING_REF",
		path = "missions[1](daily_hold_the_line).conditions[1].medal",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1] =
				{ stat = "medals", atLeast = 1, aggregate = "Cumulative", medal = "steel_wall" }
		end,
	},
	{
		name = "Role Score summed across battles",
		code = "MISSION",
		path = "missions[1](daily_hold_the_line).conditions[1].aggregate",
		mutate = function(b)
			find(b.missions, "daily_hold_the_line").conditions[1] =
				{ stat = "roleScore", atLeast = 1.2, aggregate = "Cumulative" }
		end,
	},
	{
		name = "Reward vehicle that nothing hands out",
		code = "ORPHAN",
		path = "vehicles[4](iu_reward_1)",
		warning = true,
		mutate = function(b)
			addRewardCopies(b, 1, 0)
		end,
	},
	{
		name = "unknown crew seat group",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_kolmal).visual.layout.crewSeats[1].group",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.layout.crewSeats =
				{ { slot = 1, centerM = Vector3.new(0, 1.2, 0), group = "Roof" } }
		end,
	},
	{
		name = "driver seated in the turret",
		code = "LAYOUT",
		path = "vehicles[1](iu_kolmal).visual.layout.crewSeats[1].group",
		message = "driver",
		mutate = function(b)
			find(b.vehicles, "iu_kolmal").visual.layout.crewSeats =
				{ { slot = 2, centerM = Vector3.new(0, 0.4, 0), group = "Turret" } }
		end,
	},
}

describe("ContentRegistry: every validator fires on a bad fixture", function()
	for _, case in cases do
		it(`{case.code}: {case.name}`, function()
			local b = fixtureBundle()
			case.mutate(b)
			local errors, warnings = report(b, case.options)
			local list = if case.warning then warnings else errors
			if not hasIssue(list, case.code, case.path, case.message) then
				error(
					`expected {case.code} at {tostring(case.path)} ({tostring(case.message)}); errors:\n{ContentRegistry.formatIssues(
						errors
					)}\nwarnings:\n{ContentRegistry.formatIssues(warnings)}`,
					0
				)
			end
			if case.warning then
				-- Warnings never fail validation on their own.
				expect(ContentRegistry.formatIssues(errors)).toBe("")
			end
		end)
	end

	it("never throws: random junk anywhere in the bundle becomes issues, not errors", function()
		local RNG = require("@game/ReplicatedStorage/Shared/Core/RNG")
		local rng = RNG.new(7) -- 10 seeds × 4,000 bundles were run once by hand
		local junkValues: { any } = { "x", -1, 0 / 0, math.huge, true, {}, { 1, 2 }, { a = 1 }, Vector3.new(1, 2, 3) }
		for _ = 1, 200 do
			local b = fixtureBundle()
			addApex(b)
			-- collect every (table, key) slot of the bundle, then corrupt a few of them
			local slots: { { any } } = {}
			local function walk(t: any, depth: number)
				if depth > 12 then
					return
				end
				for key, value in t do
					table.insert(slots, { t, key })
					if type(value) == "table" then
						walk(value, depth + 1)
					end
				end
			end
			walk(b, 0)
			for _ = 1, rng:int(1, 4) do
				local slot = rng:pick(slots)
				local roll = rng:int(1, #junkValues + 1)
				slot[1][slot[2]] = if roll > #junkValues then nil else junkValues[roll]
			end
			local ok, err = pcall(function()
				return ContentRegistry.fromBundle(b):validate()
			end)
			if not ok then
				error(`validate() threw: {tostring(err)}`)
			end
		end
	end)

	it("covers every issue code the registry can emit", function()
		local covered = {}
		for _, case in cases do
			covered[case.code] = true
		end
		covered.ASSET_KEY = true -- asset-key specs above
		local source = fs.readFile("src/ReplicatedStorage/Shared/Config/ContentRegistry.luau")
		local missing = {}
		for code in string.gmatch(source, 'add%a+%(%s*ctx,%s*"([A-Z_]+)"') do
			if not covered[code] then
				missing[code] = true
			end
		end
		for code in string.gmatch(source, 'code = "([A-Z_]+)"') do
			if not covered[code] then
				missing[code] = true
			end
		end
		local list = {}
		for code in missing do
			table.insert(list, code)
		end
		table.sort(list)
		expect(list).toEqual({})
	end)
end)
