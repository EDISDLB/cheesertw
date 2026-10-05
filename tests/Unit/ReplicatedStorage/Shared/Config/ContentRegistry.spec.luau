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

local function hasIssue(list: { Issue }, code: string, pathPart: string?): boolean
	for _, issue in list do
		if issue.code == code and (pathPart == nil or string.find(issue.path, pathPart, 1, true) ~= nil) then
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
		scope = { factions = { "iron_union" }, vehicles = { "iu_forge" } },
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

-- A second, premium Iron Union vehicle copied from the Forge (used by acquisition cases).
local function addPremium(b: any): any
	local premium = table.clone(find(b.vehicles, "iu_forge"))
	premium.id = "iu_premium_anvil"
	premium.name = "IU-2P Anvil Premium"
	premium.shortName = "Anvil P"
	premium.tier = 2
	premium.acquisition = "Premium"
	premium.moduleTree = {}
	premium.unlocks = {}
	premium.modules = {
		guns = { "iu_gun_45mm" },
		turrets = { "iu_turret_forge" },
		engines = { "iu_engine_d120" },
		tracks = { "iu_tracks_forge" },
	}
	premium.stock = premium.top
	premium.price = { bullion = 250 }
	premium.researchXp = nil
	premium.tree = { row = 6 }
	table.insert(b.vehicles, premium)
	return premium
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
		local forge = content:getVehicle("iu_forge") :: any
		expect(function()
			forge.tier = 2
		end).toThrow("readonly")
		expect(function()
			(forge.crew :: any)[1].role = "Gunner"
		end).toThrow("readonly")
		local copy = ContentRegistry.shippedBundle() :: any
		find(copy.vehicles, "iu_forge").tier = 5
		expect(forge.tier).toBe(1)
		expect(ContentRegistry.get()).toBe(content)
	end)
end)

describe("ContentRegistry: getters and derived views", function()
	local content = ContentRegistry.get()

	it("gets every kind by id and returns nil for unknown or wrong-kind ids", function()
		expect((content:getVehicle("iu_bastion") :: any).tier).toBe(3)
		expect((content:getGun("iu_gun_76mm") :: any).caliberMm).toBe(76)
		expect((content:getTurret("iu_turret_bastion_m2") :: any).hpBonus).toBe(30)
		expect((content:getEngine("iu_engine_d290") :: any).powerHp).toBe(290)
		expect((content:getTracks("iu_tracks_anvil_m2") :: any).loadLimitKg).toBe(13400)
		expect((content:getShell("iu_57mm_apcr") :: any).special).toBe(true)
		expect((content:getClass("td") :: any).camoCasemate).never.toBeNil()
		expect((content:getRole("heavy_assault") :: any).categorySlot).toBe("Survivability")
		expect((content:getMap("proving_grounds") :: any).sizeM).toBe(800)
		expect(content:getModule("Gun", "iu_gun_45mm")).never.toBeNil()
		expect(content:getModule("Engine", "iu_gun_45mm")).toBeNil()
		expect((content:getAnyModule("iu_tracks_forge") :: any).kind).toBe("Tracks")
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
		expect(ids(content:vehiclesByFaction("iron_union"))).toEqual({ "iu_forge", "iu_anvil", "iu_bastion" })
		expect(ids(content:vehiclesByFaction("crown_industries"))).toEqual({})
		expect(ids(content:vehiclesByTier(2))).toEqual({ "iu_anvil" })
		expect(ids(content:vehiclesByClass("heavy"))).toEqual({ "iu_bastion" })
		expect(#content:allVehicles()).toBe(3)
		expect(#content:allMaps()).toBe(1)
	end)

	it("derives tech-tree edges with the target's research XP", function()
		expect(content:techTreeEdges()).toEqual({
			{ from = "iu_anvil", to = "iu_bastion", requires = "iu_gun_57mm", xp = 750 },
			{ from = "iu_forge", to = "iu_anvil", requires = "iu_gun_45mm", xp = 350 },
		})
		expect(#content:techTreeEdges("iron_union")).toBe(2)
		expect(content:techTreeEdges("desert_corps")).toEqual({})
		expect(#content:parentsOf("iu_anvil")).toBe(1)
		expect(content:parentsOf("iu_forge")).toEqual({})
		expect(content:childrenOf("iu_bastion")).toEqual({})
	end)

	it("computes configuration mass and enforces the mount rules", function()
		local forge = content:getVehicle("iu_forge") :: any
		expect(content:configurationMassKg("iu_forge", forge.stock)).toBe(9900)
		expect(content:configurationMassKg("iu_forge", forge.top)).toBe(10070)
		expect(content:configurationMassKg("nope", forge.stock)).toBeNil()
		local bastion = content:getVehicle("iu_bastion") :: any
		local ok = content:checkConfiguration("iu_bastion", bastion.top)
		expect(ok).toBeOk()
		expect(ok.value).toBe(25200)
		-- Tracks -> Turret -> Gun is physical: the stock tracks cannot carry the top turret + gun.
		local heavy = {
			gun = "iu_gun_76mm",
			turret = "iu_turret_bastion_m2",
			engine = "iu_engine_d230",
			tracks = "iu_tracks_bastion_m1",
		}
		local over = content:checkConfiguration("iu_bastion", heavy :: any)
		expect(over).toBeErr("INVALID_ARGS")
		expect(over.detail).toContain("exceeds")
		local wrongGun = table.clone(bastion.stock)
		wrongGun.gun = "iu_gun_76mm"
		expect(content:checkConfiguration("iu_bastion", wrongGun)).toBeErr("INVALID_ARGS")
		local foreign = table.clone(bastion.stock)
		foreign.engine = "iu_engine_d120"
		expect(content:checkConfiguration("iu_bastion", foreign)).toBeErr("INVALID_ARGS")
		local unknown = table.clone(bastion.stock)
		unknown.engine = "nope"
		expect(content:checkConfiguration("iu_bastion", unknown)).toBeErr("NOT_FOUND")
		expect(content:checkConfiguration("nope", bastion.stock)).toBeErr("NOT_FOUND")
		expect(content:checkConfiguration("iu_bastion", 5 :: any)).toBeErr("INVALID_ARGS")
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
		expect(content:ordinal("Vehicle", "iu_anvil")).toBe(1)
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
		find(b.vehicles, "iu_forge").crew = {}
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

type Case = { name: string, code: string, path: string?, warning: boolean?, mutate: (b: any) -> () }

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
		path = "vehicles[1](iu_forge).camoflage",
		mutate = function(b)
			find(b.vehicles, "iu_forge").camoflage = { stationary = 0.1, moving = 0.1 }
		end,
	},
	{
		name = "missing required field",
		code = "MISSING_FIELD",
		path = "vehicles[1](iu_forge).lore",
		mutate = function(b)
			find(b.vehicles, "iu_forge").lore = nil
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
		path = "turrets[1](iu_turret_forge).guns[1]",
		mutate = function(b)
			find(b.turrets, "iu_turret_forge").guns[1] = "iu_engine_d120"
		end,
	},
	{
		name = "turret lists an unknown gun",
		code = "DANGLING_REF",
		path = "turrets[1](iu_turret_forge).guns[2]",
		mutate = function(b)
			find(b.turrets, "iu_turret_forge").guns[2] = "iu_gun_nope"
		end,
	},
	{
		name = "casemate mount without yaw limits",
		code = "MOUNT",
		path = "turrets[1](iu_turret_forge).yawLimitsDeg",
		mutate = function(b)
			local turret = find(b.turrets, "iu_turret_forge")
			turret.mount = "Casemate"
			turret.visual.style = "Casemate"
		end,
	},
	{
		name = "casemate mount with a turret visual",
		code = "MOUNT",
		path = "turrets[1](iu_turret_forge).visual.style",
		mutate = function(b)
			local turret = find(b.turrets, "iu_turret_forge")
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
		path = "tracks[1](iu_tracks_forge).terrainResistance",
		mutate = function(b)
			find(b.tracks, "iu_tracks_forge").terrainResistance = { hard = 2, medium = 1, soft = 3 }
		end,
	},
	-- Vehicles: references and identity ---------------------------------------------------------------------------------
	{
		name = "vehicle references an unknown faction",
		code = "DANGLING_REF",
		path = "vehicles[1](iu_forge).faction",
		mutate = function(b)
			find(b.vehicles, "iu_forge").faction = "pirate_league"
		end,
	},
	{
		name = "vehicle role of another class",
		code = "ROLE_CLASS",
		path = "vehicles[1](iu_forge).role",
		mutate = function(b)
			find(b.vehicles, "iu_forge").role = "heavy_assault"
		end,
	},
	{
		name = "class outside its tier range",
		code = "TIER_RANGE",
		path = "vehicles[1](iu_forge).tier",
		mutate = function(b)
			local forge = find(b.vehicles, "iu_forge")
			forge.class = "artillery"
			forge.role = "artillery_support"
		end,
	},
	{
		name = "tier outside 1..11",
		code = "BAD_VALUE",
		path = "vehicles[3](iu_bastion).tier",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").tier = 12
		end,
	},
	{
		name = "short name longer than 12 characters",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_forge).shortName",
		mutate = function(b)
			find(b.vehicles, "iu_forge").shortName = "Forge Mark One"
		end,
	},
	{
		name = "module list references an unknown module",
		code = "DANGLING_REF",
		path = "vehicles[1](iu_forge).modules.engines[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_forge").modules.engines, "iu_engine_nope")
		end,
	},
	{
		name = "module list holds a module of another kind",
		code = "WRONG_KIND",
		path = "vehicles[1](iu_forge).modules.engines[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_forge").modules.engines, "iu_tracks_forge")
		end,
	},
	-- Vehicles: configurations and load limits ----------------------------------------------------------------------------
	{
		name = "stock configuration uses a module the vehicle does not list",
		code = "CONFIG_INVALID",
		path = "vehicles[1](iu_forge).stock.engine",
		mutate = function(b)
			find(b.vehicles, "iu_forge").stock.engine = "iu_engine_d165"
		end,
	},
	{
		name = "stock configuration mounts a gun the turret cannot carry",
		code = "CONFIG_INVALID",
		path = "vehicles[3](iu_bastion).stock.gun",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").stock.gun = "iu_gun_76mm"
		end,
	},
	{
		name = "configuration slot holds a module of another kind",
		code = "WRONG_KIND",
		path = "vehicles[1](iu_forge).top.engine",
		mutate = function(b)
			find(b.vehicles, "iu_forge").top.engine = "iu_tracks_forge"
		end,
	},
	{
		name = "configuration slot missing",
		code = "MISSING_FIELD",
		path = "vehicles[1](iu_forge).top.tracks",
		mutate = function(b)
			find(b.vehicles, "iu_forge").top.tracks = nil
		end,
	},
	{
		name = "stock configuration over the load limit",
		code = "OVER_LOAD_LIMIT",
		path = "vehicles[1](iu_forge).stock",
		mutate = function(b)
			find(b.tracks, "iu_tracks_forge").loadLimitKg = 9800
		end,
	},
	{
		name = "top configuration over the load limit",
		code = "OVER_LOAD_LIMIT",
		path = "vehicles[3](iu_bastion).top",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").hull.massKg = 18000
		end,
	},
	{
		name = "stock tracks can carry the top modules (weak research order)",
		code = "LOAD_ORDER",
		path = "vehicles[2](iu_anvil).stock.tracks",
		warning = true,
		mutate = function(b)
			find(b.tracks, "iu_tracks_anvil_m1").loadLimitKg = 12800
		end,
	},
	-- Vehicles: module tree ------------------------------------------------------------------------------------------
	{
		name = "module tree node is not a module of the vehicle",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_forge).moduleTree[2].module",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_forge").moduleTree, { module = "iu_gun_76mm" })
		end,
	},
	{
		name = "stock module listed in the module tree",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_forge).moduleTree[2].module",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_forge").moduleTree, { module = "iu_gun_37mm" })
		end,
	},
	{
		name = "module listed twice in the tree",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_forge).moduleTree[2].module",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_forge").moduleTree, { module = "iu_gun_45mm" })
		end,
	},
	{
		name = "module requires itself",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_forge).moduleTree[1].requires[1]",
		mutate = function(b)
			find(b.vehicles, "iu_forge").moduleTree[1].requires = { "iu_gun_45mm" }
		end,
	},
	{
		name = "module requires a module of another vehicle",
		code = "MODULE_TREE",
		path = "vehicles[1](iu_forge).moduleTree[1].requires[1]",
		mutate = function(b)
			find(b.vehicles, "iu_forge").moduleTree[1].requires = { "iu_tracks_bastion_m2" }
		end,
	},
	{
		name = "non-stock module missing from the tree",
		code = "MODULE_UNREACHABLE",
		path = "vehicles[3](iu_bastion).modules.engines(iu_engine_d290)",
		mutate = function(b)
			table.remove(find(b.vehicles, "iu_bastion").moduleTree, 4)
		end,
	},
	{
		name = "module requirements form a cycle",
		code = "MODULE_CYCLE",
		path = "vehicles[3](iu_bastion).moduleTree",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").moduleTree[1].requires = { "iu_gun_76mm" }
		end,
	},
	{
		name = "a gun that no turret of the vehicle can mount",
		code = "TURRET_GUNS",
		path = "vehicles[1](iu_forge).modules.guns(iu_gun_57mm)",
		mutate = function(b)
			local forge = find(b.vehicles, "iu_forge")
			table.insert(forge.modules.guns, "iu_gun_57mm")
			table.insert(forge.moduleTree, { module = "iu_gun_57mm" })
		end,
	},
	-- Vehicles: tech tree -------------------------------------------------------------------------------------------
	{
		name = "unlock of an unknown vehicle",
		code = "DANGLING_REF",
		path = "vehicles[3](iu_bastion).unlocks[1].vehicle",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").unlocks = { { vehicle = "iu_nope" } }
		end,
	},
	{
		name = "unlock skips a tier",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_forge).unlocks[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_forge").unlocks, { vehicle = "iu_bastion" })
		end,
	},
	{
		name = "unlock requires a module the vehicle does not have",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_forge).unlocks[1].requires",
		mutate = function(b)
			find(b.vehicles, "iu_forge").unlocks[1].requires = "iu_gun_57mm"
		end,
	},
	{
		name = "duplicate unlock",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_forge).unlocks[2]",
		mutate = function(b)
			table.insert(find(b.vehicles, "iu_forge").unlocks, { vehicle = "iu_anvil" })
		end,
	},
	{
		name = "unlock across factions",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_forge).unlocks[1]",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").faction = "crown_industries"
		end,
	},
	{
		name = "unlock of a premium vehicle",
		code = "UNLOCK_EDGE",
		path = "vehicles[1](iu_forge).unlocks[2]",
		mutate = function(b)
			addPremium(b)
			table.insert(find(b.vehicles, "iu_forge").unlocks, { vehicle = "iu_premium_anvil" })
		end,
	},
	{
		name = "premium vehicle unlocking another vehicle",
		code = "UNLOCK_EDGE",
		path = "vehicles[4](iu_premium_anvil).unlocks[1]",
		mutate = function(b)
			local premium = addPremium(b)
			premium.unlocks = { { vehicle = "iu_bastion" } }
		end,
	},
	{
		name = "tech tree cycle",
		code = "TECH_TREE_CYCLE",
		path = "vehicles",
		mutate = function(b)
			local twin = table.clone(find(b.vehicles, "iu_anvil"))
			twin.id = "iu_anvil_twin"
			twin.tree = { row = 4 }
			twin.unlocks = { { vehicle = "iu_anvil" } }
			table.insert(b.vehicles, twin)
			table.insert(find(b.vehicles, "iu_anvil").unlocks, { vehicle = "iu_anvil_twin" })
		end,
	},
	{
		name = "vehicle unreachable from a Tier I root",
		code = "UNREACHABLE_VEHICLE",
		path = "vehicles(iu_bastion)",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").unlocks = {}
		end,
	},
	{
		name = "faction without a Tier I root",
		code = "NO_ROOT",
		path = "factions(iron_union)",
		mutate = function(b)
			local forge = find(b.vehicles, "iu_forge")
			forge.acquisition = "Reward"
			forge.unlocks = {}
		end,
	},
	{
		name = "Tier I starter unlocked by another vehicle",
		code = "UNLOCK_EDGE",
		path = "vehicles(iu_forge_b)",
		mutate = function(b)
			local twin = table.clone(find(b.vehicles, "iu_forge"))
			twin.id = "iu_forge_b"
			twin.tree = { row = 5 }
			twin.unlocks = {}
			table.insert(b.vehicles, twin)
			table.insert(find(b.vehicles, "iu_forge").unlocks, { vehicle = "iu_forge_b" })
		end,
	},
	{
		name = "two tech-tree vehicles in the same tree slot",
		code = "TREE_POSITION",
		path = "vehicles[4](iu_anvil_b).tree.row",
		mutate = function(b)
			local twin = table.clone(find(b.vehicles, "iu_anvil"))
			twin.id = "iu_anvil_b"
			twin.unlocks = {}
			table.insert(b.vehicles, twin)
			table.insert(find(b.vehicles, "iu_forge").unlocks, { vehicle = "iu_anvil_b" })
		end,
	},
	-- Vehicles: crew ---------------------------------------------------------------------------------------------------
	{
		name = "two commanders",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_anvil).crew",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").crew[4] = { role = "Commander", also = { "Loader" } }
		end,
	},
	{
		name = "no commander",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_anvil).crew",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").crew[1] = { role = "Loader" }
		end,
	},
	{
		name = "no seat covers the loader duty",
		code = "CREW_COMPOSITION",
		path = "vehicles[1](iu_forge).crew",
		mutate = function(b)
			find(b.vehicles, "iu_forge").crew[1] = { role = "Commander" }
		end,
	},
	{
		name = "driver with extra duties",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_anvil).crew[3].also",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").crew[3].also = { "Loader" }
		end,
	},
	{
		name = "commander as a secondary duty",
		code = "CREW_COMPOSITION",
		path = "vehicles[2](iu_anvil).crew[2].also[1]",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").crew[2].also = { "Commander" }
		end,
	},
	{
		name = "crew too large",
		code = "CREW_COMPOSITION",
		path = "vehicles[3](iu_bastion).crew",
		mutate = function(b)
			local crew = find(b.vehicles, "iu_bastion").crew
			table.insert(crew, { role = "Loader" })
			table.insert(crew, { role = "Gunner" })
		end,
	},
	-- Vehicles: acquisition --------------------------------------------------------------------------------------------
	{
		name = "tech-tree vehicle without research XP",
		code = "ACQUISITION",
		path = "vehicles[2](iu_anvil).researchXp",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").researchXp = nil
		end,
	},
	{
		name = "tier I vehicle that costs credits",
		code = "ACQUISITION",
		path = "vehicles[1](iu_forge).price.credits",
		mutate = function(b)
			find(b.vehicles, "iu_forge").price = { credits = 1000 }
		end,
	},
	{
		name = "tech-tree vehicle sold for Bullion",
		code = "ACQUISITION",
		path = "vehicles[2](iu_anvil).price.bullion",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").price.bullion = 250
		end,
	},
	{
		name = "premium vehicle without a Bullion price",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_anvil).price.bullion",
		mutate = function(b)
			addPremium(b).price = { credits = 35000 }
		end,
	},
	{
		name = "premium vehicle with research XP",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_anvil).researchXp",
		mutate = function(b)
			addPremium(b).researchXp = 350
		end,
	},
	{
		name = "premium vehicle at Tier X",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_anvil).tier",
		mutate = function(b)
			addPremium(b).tier = 10
		end,
	},
	{
		name = "premium vehicle with a module tree",
		code = "ACQUISITION",
		path = "vehicles[4](iu_premium_anvil).moduleTree",
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
		path = "vehicles[3](iu_bastion).mechanics[1]",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").mechanics = {
				{ kind = "SiegeMode", engageS = 2, disengageS = 1.25, maxSpeedKmh = 10, modifiers = {} },
			}
		end,
	},
	{
		name = "Tier XI signature on a Tier III vehicle",
		code = "MECHANIC",
		path = "vehicles[3](iu_bastion).mechanics[1]",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").mechanics = {
				{ kind = "RocketBoost", charges = 2, durationS = 2.5, speedBonusKmh = 20, cooldownS = 30 },
			}
		end,
	},
	{
		name = "mechanic listed twice",
		code = "MECHANIC",
		path = "vehicles[2](iu_anvil).mechanics[2]",
		mutate = function(b)
			local hydro = { kind = "Hydropneumatic", depressionBonusDeg = 4, elevationBonusDeg = 3, settleS = 0.75 }
			find(b.vehicles, "iu_anvil").mechanics = { hydro, table.clone(hydro) }
		end,
	},
	{
		name = "wheeled tracks without the Wheeled mechanic",
		code = "MECHANIC",
		path = "vehicles[1](iu_forge).mechanics",
		mutate = function(b)
			find(b.tracks, "iu_tracks_forge").wheeled = true
		end,
	},
	{
		name = "dual gun on a Tier III heavy",
		code = "MECHANIC",
		path = "vehicles[3](iu_bastion).modules.guns(iu_gun_76mm)",
		mutate = function(b)
			find(b.guns, "iu_gun_76mm").reload =
				{ kind = "DualGun", reloadEachS = 8, salvoDelayS = 1.5, chargeTimeS = 1, volleyDispersionMul = 1.5 }
		end,
	},
	{
		name = "magazine gun on a Heavy Assault",
		code = "MECHANIC",
		path = "vehicles[3](iu_bastion).modules.guns(iu_gun_76mm)",
		mutate = function(b)
			find(b.guns, "iu_gun_76mm").reload = { kind = "Magazine", size = 3, intraClipS = 2, reloadS = 10 }
		end,
	},
	{
		name = "indirect gun on a tank",
		code = "MECHANIC",
		path = "vehicles[3](iu_bastion).modules.guns(iu_gun_76mm)",
		mutate = function(b)
			find(b.guns, "iu_gun_76mm").indirect = true
		end,
	},
	{
		name = "apex track below Tier XI",
		code = "APEX",
		path = "vehicles[3](iu_bastion).apex",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").apex =
				{ nodes = { { id = "n1", name = "Node", kind = "Small", xp = 4000, effects = {} } } }
		end,
	},
	{
		name = "Tier XI vehicle without an apex track or signature",
		code = "APEX",
		path = "vehicles[4](iu_apex).apex",
		mutate = function(b)
			local apex = table.clone(find(b.vehicles, "iu_forge"))
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
		path = "vehicles[1](iu_forge).visual.hull.turretRing.diameterM",
		mutate = function(b)
			find(b.vehicles, "iu_forge").visual.hull.turretRing.diameterM = 3
		end,
	},
	{
		name = "ground clearance above the hull roof",
		code = "VISUAL",
		path = "vehicles[1](iu_forge).visual.hull.groundClearanceM",
		mutate = function(b)
			find(b.vehicles, "iu_forge").visual.hull.groundClearanceM = 0.9
			find(b.vehicles, "iu_forge").visual.hull.heightM = 0.8
		end,
	},
	{
		name = "skirts without spaced-armor thickness",
		code = "ARMOR",
		path = "vehicles[3](iu_bastion).visual.hull.skirts",
		mutate = function(b)
			find(b.vehicles, "iu_bastion").hull.armor.skirts = nil
		end,
	},
	{
		name = "superstructure without armor values",
		code = "ARMOR",
		path = "vehicles[2](iu_anvil).visual.hull.superstructure",
		mutate = function(b)
			find(b.vehicles, "iu_anvil").visual.hull.superstructure =
				{ lengthM = 3, heightM = 0.6, positionFraction = 0.4, frontAngleDeg = 30 }
		end,
	},
	{
		name = "bustle ammo rack in a turret without a bustle",
		code = "LAYOUT",
		path = "vehicles[3](iu_bastion).visual.layout.ammoRacks[1]",
		mutate = function(b)
			find(b.turrets, "iu_turret_bastion_m1").visual.bustleLengthM = 0
		end,
	},
	{
		name = "internal volume override with a non-positive size",
		code = "BAD_VALUE",
		path = "vehicles[1](iu_forge).visual.layout.overrides[1].sizeM",
		mutate = function(b)
			find(b.vehicles, "iu_forge").visual.layout.overrides = {
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
	},
}

describe("ContentRegistry: every validator fires on a bad fixture", function()
	for _, case in cases do
		it(`{case.code}: {case.name}`, function()
			local b = fixtureBundle()
			case.mutate(b)
			local errors, warnings = report(b)
			local list = if case.warning then warnings else errors
			if not hasIssue(list, case.code, case.path) then
				error(
					`expected {case.code} at {tostring(case.path)}; errors:\n{ContentRegistry.formatIssues(errors)}\nwarnings:\n{ContentRegistry.formatIssues(
						warnings
					)}`,
					0
				)
			end
			if case.warning then
				-- Warnings never fail validation on their own.
				expect(ContentRegistry.formatIssues(errors)).toBe("")
			end
		end)
	end

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
