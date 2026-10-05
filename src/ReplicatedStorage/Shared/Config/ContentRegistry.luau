--!strict
--[[
	ContentRegistry — indexes all authored content by id and cross-validates it (ARCHITECTURE §9).

	Purpose:          Typed read access to every content kind (getVehicle, getGun, getModule(kind, id), getMap…),
	                  derived views (vehiclesByFaction/Tier/Class, tech-tree edges, configuration mass and mount
	                  checks, stable ordinals for compact codecs, a content hash for determinism) and validate(),
	                  which reports EVERY problem in the data at once. Gameplay code reads content only through here.
	Dependencies:     Types/Content, Core/Freeze, Core/TableUtil, Core/Result, Core/RNG (hash), Net/ErrorCodes,
	                  Config/Content (the shipped manifest; only `ContentRegistry.get()` uses it).
	State:            A registry is immutable after construction: the bundle is deep-frozen, indexes are built once,
	                  the content hash is memoised. The shipped registry is built lazily on the first `get()`.
	Validation:       validate() returns Ok({ errors = {}, warnings }) or Err(INVALID_ARGS, { errors, warnings });
	                  issue codes, paths and the rules they enforce are listed in docs/design/content-schema.md §9.
	Error handling:   Construction never throws on bad data (bad ids and duplicates become issues; the first
	                  definition of an id wins). Getters return nil for unknown ids. checkConfiguration returns a
	                  Result (NOT_FOUND / INVALID_ARGS with a human-readable detail).
	Performance notes: Build is O(n); getters are O(1) table lookups; validate is O(content + edges) and meant for
	                  boot and tests (a few ms for hundreds of vehicles); contentHash serialises everything once.

	Usage:
	  local ContentRegistry = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")
	  local content = ContentRegistry.get()                 -- shipped content (Config/Content)
	  local forge = content:getVehicle("iu_forge")
	  local registry = ContentRegistry.fromBundle(bundle)   -- tools/tests (bundle = ContentRegistry.shippedBundle())
	  local report = registry:validate()
]]

local Content = require("../Types/Content")
local Freeze = require("../Core/Freeze")
local TableUtil = require("../Core/TableUtil")
local Result = require("../Core/Result")
local RNG = require("../Core/RNG")
local ErrorCodes = require("../Net/ErrorCodes")

type ContentBundle = Content.ContentBundle
type ContentSources = Content.ContentSources
type ContentKind = Content.ContentKind
type ModuleKind = Content.ModuleKind
type Configuration = Content.Configuration
type VehicleDefinition = Content.VehicleDefinition
type ModuleDefinition = Content.ModuleDefinition
type TechTreeEdge = Content.TechTreeEdge
type Result<T> = Result.Result<T>

export type IssueSeverity = "error" | "warning"
export type ContentIssue = { code: string, path: string, message: string, severity: IssueSeverity }
export type ValidationReport = { errors: { ContentIssue }, warnings: { ContentIssue } }
--- Optional asset catalogues: when given, every icon/sound key must exist (ARCHITECTURE §9).
export type ValidateOptions = { iconKeys: { [string]: boolean }?, soundKeys: { [string]: boolean }? }

--------------------------------------------------------------------------------
-- Kind table
--------------------------------------------------------------------------------

type KindSpec = { kind: ContentKind, field: string, idField: string, label: string }

local KINDS: { KindSpec } = {
	{ kind = "Faction", field = "factions", idField = "id", label = "faction" },
	{ kind = "Class", field = "classes", idField = "id", label = "class" },
	{ kind = "Role", field = "roles", idField = "id", label = "role" },
	{ kind = "Tier", field = "tiers", idField = "tier", label = "tier" },
	{ kind = "Shell", field = "shells", idField = "id", label = "shell" },
	{ kind = "Gun", field = "guns", idField = "id", label = "gun" },
	{ kind = "Turret", field = "turrets", idField = "id", label = "turret" },
	{ kind = "Engine", field = "engines", idField = "id", label = "engine" },
	{ kind = "Tracks", field = "tracks", idField = "id", label = "tracks" },
	{ kind = "Vehicle", field = "vehicles", idField = "id", label = "vehicle" },
	{ kind = "Equipment", field = "equipment", idField = "id", label = "equipment" },
	{ kind = "Consumable", field = "consumables", idField = "id", label = "consumable" },
	{ kind = "CrewSkill", field = "crewSkills", idField = "id", label = "crew skill" },
	{ kind = "CrewBook", field = "crewBooks", idField = "id", label = "crew book" },
	{ kind = "Booster", field = "boosters", idField = "id", label = "booster" },
	{ kind = "Customization", field = "customization", idField = "id", label = "customization" },
	{ kind = "Mission", field = "missions", idField = "id", label = "mission" },
	{ kind = "Achievement", field = "achievements", idField = "id", label = "achievement" },
	{ kind = "Map", field = "maps", idField = "id", label = "map" },
	{ kind = "StoreItem", field = "store", idField = "id", label = "store item" },
	{ kind = "Event", field = "events", idField = "id", label = "event" },
	{ kind = "Season", field = "seasons", idField = "id", label = "season" },
	{ kind = "Branch", field = "branches", idField = "id", label = "tech-tree branch" },
}

local KIND_BY_NAME: { [string]: KindSpec } = {}
for _, spec in KINDS do
	KIND_BY_NAME[spec.kind] = spec
end

local MODULE_FIELD: { [string]: string } = { Gun = "guns", Turret = "turrets", Engine = "engines", Tracks = "tracks" }
local CONFIG_SLOTS: { { key: string, kind: ModuleKind, list: string } } = {
	{ key = "gun", kind = "Gun", list = "guns" },
	{ key = "turret", kind = "Turret", list = "turrets" },
	{ key = "engine", kind = "Engine", list = "engines" },
	{ key = "tracks", kind = "Tracks", list = "tracks" },
}

--------------------------------------------------------------------------------
-- Enumerations (mirror Types/Content; the type checker cannot see inside data loaded at runtime)
--------------------------------------------------------------------------------

local function set(list: { string }): { [string]: boolean }
	local out = {}
	for _, v in list do
		out[v] = true
	end
	return out
end

local FACTION_IDS = {
	"iron_union",
	"crown_industries",
	"eastern_armor",
	"desert_corps",
	"mountain_republic",
	"northern_federation",
}
local CLASS_IDS = { "light", "medium", "heavy", "td", "artillery" }
local ROLE_IDS = {
	"light_scout",
	"light_support",
	"light_versatile",
	"medium_assault",
	"medium_sniper",
	"medium_support",
	"medium_versatile",
	"heavy_assault",
	"heavy_breakthrough",
	"heavy_support",
	"heavy_versatile",
	"td_assault",
	"td_sniper",
	"td_support",
	"td_versatile",
	"artillery_support",
	"artillery_area_control",
}
local NUMERALS = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI" }

local E = {
	faction = set(FACTION_IDS),
	class = set(CLASS_IDS),
	role = set(ROLE_IDS),
	crewRole = set({ "Commander", "Gunner", "Driver", "Loader" }),
	shellKind = set({ "AP", "APCR", "HEAT", "HE", "HESH" }),
	internalModule = set({ "Engine", "AmmoRack", "FuelTank", "Gun", "TurretRing", "Optics", "TrackLeft", "TrackRight" }),
	equipmentCategory = set({ "Firepower", "Survivability", "Mobility", "Scouting" }),
	acquisition = set({ "TechTree", "Premium", "Reward", "Event" }),
	battleMode = set({ "Random", "Training", "Bootcamp", "Practice", "Event" }),
	battleType = set({ "Standard", "Encounter", "Assault" }),
	rarity = set({ "common", "uncommon", "rare", "epic", "legendary", "prototype" }),
	biome = set({ "temperate", "desert", "winter", "urban", "alpine" }),
	statKey = set({
		"damage",
		"damageRollMin",
		"penetration",
		"reloadTime",
		"aimTime",
		"dispersion",
		"bloomMovement",
		"bloomHullTraverse",
		"bloomTurretTraverse",
		"bloomAfterShot",
		"shellVelocity",
		"shellSwapTime",
		"ammoCapacity",
		"turretTraverse",
		"gunDepression",
		"gunElevation",
		"enginePower",
		"topSpeed",
		"reverseSpeed",
		"hullTraverse",
		"terrainResistance",
		"loadLimit",
		"hp",
		"moduleHp",
		"repairTime",
		"fireChance",
		"fireDuration",
		"crewInjuryChance",
		"spallFactor",
		"stunDuration",
		"ramDamageDealt",
		"ramDamageTaken",
		"fallDamage",
		"viewRange",
		"camoStationary",
		"camoMoving",
		"camoAfterShot",
		"camoNet",
		"signalRange",
		"crewLevel",
		"consumableCooldown",
		"crewXp",
	}),
	statOp = set({ "mul", "add" }),
	statCondition = set({
		"Always",
		"Stationary",
		"StationaryArmed",
		"Moving",
		"TurretTraversing",
		"AfterShot",
		"AfterTakingDamage",
		"AfterSpotting",
		"NearEnemy",
		"Spotted",
		"LowHp",
		"MechanicActive",
	}),
	balanceStat = set({
		"hp",
		"alpha",
		"penetration",
		"reload",
		"dpm",
		"aimTime",
		"dispersion",
		"topSpeed",
		"specificPower",
		"hullTraverse",
		"turretTraverse",
		"viewRange",
		"hullArmor",
		"turretArmor",
		"lowerPlateArmor",
	}),
	factionSignature = set({
		"DualGun",
		"HESH",
		"Magazine",
		"Wheeled",
		"Autoreloader",
		"SiegeMode",
		"Hydropneumatic",
		"AssaultTD",
	}),
	roleScore = set({
		"damageDealt",
		"damageBlocked",
		"capture",
		"firstContactDamage",
		"assist",
		"assistSpotting",
		"assistTracking",
		"assistStun",
		"kills",
		"detections",
	}),
	roleGroup = set({ "Frontline", "Ranged", "Support", "Versatile", "Recon", "Indirect" }),
	equipmentBand = set({ "C", "B", "A" }),
	tracer = set({ "AP", "APCR", "HEAT", "HE", "Artillery" }),
	reloadKind = set({ "Single", "Magazine", "Autoreloader", "DualGun" }),
	muzzleBrake = set({ "None", "Single", "Double", "Slotted", "Pepperpot" }),
	mantlet = set({ "Box", "Rounded", "Pig", "Narrow", "Cast" }),
	gunAudio = set({
		"small_20_45mm",
		"medium_50_85mm",
		"large_88_122mm",
		"huge_130_183mm",
		"autocannon_burst",
		"artillery_howitzer",
	}),
	turretMount = set({ "Turret", "Casemate" }),
	turretStyle = set({
		"Box",
		"Cast",
		"Welded",
		"Wedge",
		"Hexagonal",
		"Dome",
		"FacetedDome",
		"Oscillating",
		"Casemate",
		"Open",
	}),
	engineFuel = set({ "Petrol", "Diesel", "Turbine" }),
	engineAudio = set({ "heavy_diesel", "medium_diesel", "light_highrpm", "large_v12", "small_engine", "turbine" }),
	exhaustPlacement = set({ "Rear", "Sides", "Deck" }),
	trackLink = set({ "Plain", "Grousered", "Rubber", "Chevron" }),
	hullStyle = set({
		"Boxy",
		"Stepped",
		"Sloped",
		"Pike",
		"Rounded",
		"Wedge",
		"Slab",
		"Casemate",
		"LowProfile",
	}),
	engineDeck = set({ "Flat", "Raised", "Louvered" }),
	skirts = set({ "None", "Plates", "Mesh", "Full" }),
	suspension = set({ "Torsion", "Christie", "Bogie", "Leaf", "Hydro", "Wheeled" }),
	sprocket = set({ "Front", "Rear" }),
	ammoRack = set({ "Turret", "Bustle", "HullFront", "HullMiddle", "Sponsons", "Floor" }),
	enginePlacement = set({ "Rear", "Front", "Middle" }),
	transmission = set({ "Front", "Rear" }),
	fuelPlacement = set({ "Rear", "Front", "Sides", "Middle" }),
	optics = set({ "Cupola", "TurretRoof", "HullRoof" }),
	volumeGroup = set({ "Hull", "Turret" }),
	mechanic = set({
		"SiegeMode",
		"Hydropneumatic",
		"Wheeled",
		"Turbo",
		"RocketBoost",
		"ChargedShot",
		"ActiveCooling",
		"AdaptiveMagazine",
	}),
	exotic = set({ "Turbo", "RocketBoost", "ChargedShot", "ActiveCooling", "AdaptiveMagazine" }),
	chargedEffect = set({ "Accuracy", "Damage" }),
	apexNode = set({ "Small", "Large", "Final" }),
	equipmentGrade = set({ "Standard", "Refined" }),
	consumableKind = set({ "RepairKit", "MedKit", "Extinguisher", "Ration", "Fuel", "Smoke", "Utility" }),
	activation = set({ "Manual", "Automatic", "Passive" }),
	boosterTarget = set({ "VehicleXP", "FreeXP", "CrewXP", "Credits" }),
	customizationKind = set({ "Paint", "Camouflage", "Emblem", "Inscription", "Style", "GunSleeve", "StatTracker" }),
	customizationSource = set({ "Store", "Mission", "Pass", "Event", "Achievement" }),
	battleStat = set({
		"battles",
		"wins",
		"survived",
		"xp",
		"teamXpRank",
		"damageDealt",
		"damageBlocked",
		"damageDealtPlusBlocked",
		"damageReceived",
		"assistSpotting",
		"assistTracking",
		"assistStun",
		"assistTotal",
		"damagePlusAssist",
		"kills",
		"spotted",
		"shotsFired",
		"hits",
		"penetrations",
		"criticalHits",
		"capturePoints",
		"defensePoints",
		"distanceM",
		"firstBlood",
		"medals",
	}),
	aggregate = set({ "SingleBattle", "Cumulative" }),
	cadence = set({ "Daily", "Weekly", "Campaign", "Event", "Tutorial", "Special" }),
	difficulty = set({ "Easy", "Medium", "Hard", "Bonus" }),
	match = set({ "All", "Any" }),
	campaignSeries = set({ "Assault", "Overwatch", "Support" }),
	rewardKind = set({
		"Credits",
		"Bullion",
		"FreeXP",
		"CrewXP",
		"CampaignTokens",
		"EventTokens",
		"PremiumDays",
		"PassPoints",
		"Equipment",
		"Consumable",
		"Vehicle",
		"Customization",
		"Booster",
		"CrewBook",
	}),
	achievementCategory = set({
		"BattleHero",
		"Epic",
		"Mastery",
		"Marks",
		"Milestone",
		"Series",
		"Event",
		"Commemorative",
	}),
	achievementKind = set({ "BattleMedal", "Milestone", "Streak", "Mastery", "Marks" }),
	terrainFeature = set({
		"Hill",
		"Ridge",
		"Valley",
		"Plateau",
		"Cliff",
		"Riverbed",
		"Crater",
		"Flatten",
		"Road",
		"Dune",
	}),
	terrainMaterial = set({
		"Grass",
		"LeafyGrass",
		"Ground",
		"Mud",
		"Sand",
		"Sandstone",
		"Rock",
		"Basalt",
		"Slate",
		"Snow",
		"Glacier",
		"Ice",
		"Concrete",
		"Asphalt",
		"Pavement",
		"Cobblestone",
		"Brick",
		"Pebble",
		"Limestone",
		"Salt",
	}),
	materialRule = set({ "Default", "Slope", "Height", "Feature" }),
	laneKind = set({ "Heavy", "Flex", "Open" }),
	foliage = set({ "LightBush", "DenseBush", "Hedgerow", "TreeCrown", "FelledTree", "Thicket" }),
	destructible = set({ "Light", "Medium", "Heavy", "Permanent" }),
	storeKind = set({
		"BullionPack",
		"PremiumTime",
		"PremiumVehicle",
		"Bundle",
		"Customization",
		"CrewBook",
		"Consumable",
		"Booster",
		"SeasonPass",
	}),
	robuxKind = set({ "DeveloperProduct", "GamePass" }),
	eventKind = set({ "Seasonal", "Weekend", "MedalHunt", "Mode", "Campaign", "XpFever" }),
	ability = set({ "Airstrike", "Smoke", "Minefield", "RepairZone", "ReconFlight" }),
	passTrack = set({ "Free", "Paid" }),
}

--- Reward kinds that name a content id, and the kind that id must resolve to.
local REWARD_REF: { [string]: ContentKind } = {
	Equipment = "Equipment",
	Consumable = "Consumable",
	Vehicle = "Vehicle",
	Customization = "Customization",
	Booster = "Booster",
	CrewBook = "CrewBook",
	EventTokens = "Event",
}

--------------------------------------------------------------------------------
-- Known fields (Luau's old solver accepts extra keys in table literals; typos in optional fields would be silently
-- ignored, so the top level of every definition is checked against these lists).
--------------------------------------------------------------------------------

local FIELDS: { [string]: { [string]: boolean } } = {
	Faction = set({
		"id",
		"name",
		"shortName",
		"motto",
		"description",
		"focus",
		"emblem",
		"order",
		"palette",
		"vehiclePaint",
		"kit",
		"signatures",
		"builderPreset",
	}),
	Branch = set({ "id", "faction", "name", "description", "classes", "tiers" }),
	Class = set({
		"id",
		"name",
		"shortName",
		"description",
		"icon",
		"minimapIcon",
		"order",
		"tiers",
		"roles",
		"baseline",
		"camo",
		"camoCasemate",
		"viewRangeMul",
		"afterShotBloom",
		"terrainResistance",
		"signalRangeM",
	}),
	Role = set({
		"id",
		"class",
		"name",
		"description",
		"playstyle",
		"tips",
		"statEmphasis",
		"trims",
		"categorySlot",
		"roleScore",
		"group",
		"badge",
		"fieldKit",
	}),
	Tier = set({
		"tier",
		"numeral",
		"name",
		"badge",
		"matchmaking",
		"baseline",
		"economy",
		"equipmentSlots",
		"consumableSlots",
		"categorySlot",
		"equipmentBand",
		"fieldKit",
		"stunMaxS",
		"moduleHpRefAlpha",
	}),
	Shell = set({
		"id",
		"name",
		"kind",
		"special",
		"caliberMm",
		"damage",
		"penetrationMm",
		"velocityMps",
		"priceCredits",
		"moduleDamage",
		"penetrationAt500Mm",
		"gravityMps2",
		"maxRangeM",
		"explosionRadiusM",
		"normalizationDeg",
		"ricochetAngleDeg",
		"stun",
		"tracer",
		"icon",
	}),
	Gun = set({
		"id",
		"kind",
		"name",
		"tier",
		"massKg",
		"priceCredits",
		"researchXp",
		"caliberMm",
		"shells",
		"reload",
		"dispersionM100",
		"aimTimeS",
		"arcs",
		"ammoCapacity",
		"bloom",
		"camoAfterShotMul",
		"shellSwapS",
		"indirect",
		"visual",
		"audio",
	}),
	Turret = set({
		"id",
		"kind",
		"name",
		"tier",
		"massKg",
		"priceCredits",
		"researchXp",
		"mount",
		"armor",
		"traverseDegS",
		"viewRangeM",
		"hpBonus",
		"guns",
		"yawLimitsDeg",
		"visual",
	}),
	Engine = set({
		"id",
		"kind",
		"name",
		"tier",
		"massKg",
		"priceCredits",
		"researchXp",
		"powerHp",
		"fuel",
		"fireChance",
		"audio",
		"visual",
	}),
	Tracks = set({
		"id",
		"kind",
		"name",
		"tier",
		"massKg",
		"priceCredits",
		"researchXp",
		"loadLimitKg",
		"traverseDegS",
		"terrainResistance",
		"armorMm",
		"bloomMul",
		"wheeled",
		"visual",
	}),
	Vehicle = set({
		"id",
		"name",
		"shortName",
		"faction",
		"tier",
		"class",
		"role",
		"acquisition",
		"description",
		"lore",
		"strengths",
		"weaknesses",
		"hull",
		"mobility",
		"camouflage",
		"crew",
		"modules",
		"stock",
		"top",
		"moduleTree",
		"unlocks",
		"researchXp",
		"price",
		"arcSectors",
		"slots",
		"mechanics",
		"apex",
		"visual",
		"audio",
		"economy",
		"tree",
		"icon",
		"balanceException",
		"hidden",
		"tags",
	}),
	Equipment = set({
		"id",
		"name",
		"description",
		"icon",
		"categories",
		"grade",
		"tiers",
		"exclusiveGroup",
		"effects",
		"categorySlotEffects",
		"effectsByClass",
		"compatibility",
		"price",
	}),
	Consumable = set({
		"id",
		"name",
		"description",
		"icon",
		"kind",
		"activation",
		"cooldownS",
		"durationS",
		"triggerDelayS",
		"repairs",
		"stunImmunityS",
		"effects",
		"passiveEffects",
		"exclusiveGroup",
		"tiers",
		"classes",
		"eventOnly",
		"price",
	}),
	CrewSkill = set({ "id", "name", "description", "icon", "roles", "kind", "effects" }),
	CrewBook = set({ "id", "name", "description", "icon", "xpPerMember", "price" }),
	Booster = set({ "id", "name", "description", "icon", "target", "multiplier", "durationS", "battles", "price" }),
	Customization = set({
		"id",
		"name",
		"description",
		"icon",
		"kind",
		"rarity",
		"colors",
		"pattern",
		"camoBonus",
		"scope",
		"source",
		"price",
	}),
	Mission = set({
		"id",
		"name",
		"description",
		"icon",
		"cadence",
		"difficulty",
		"match",
		"conditions",
		"requireWin",
		"requireSurvive",
		"scope",
		"rewards",
		"scaleRewardsByTier",
		"honors",
		"campaign",
		"eventId",
		"weight",
	}),
	Achievement = set({
		"id",
		"name",
		"description",
		"icon",
		"category",
		"kind",
		"rule",
		"stat",
		"params",
		"thresholds",
		"perVehicle",
		"repeatable",
		"scope",
		"rarity",
		"rewards",
		"hidden",
	}),
	Map = set({
		"id",
		"name",
		"description",
		"biome",
		"sizeM",
		"skirtM",
		"tierRange",
		"battleTypes",
		"modes",
		"terrain",
		"spawns",
		"bases",
		"lanes",
		"foliage",
		"props",
		"water",
		"variants",
		"randomEvents",
		"audio",
		"thumbnail",
		"tips",
		"revision",
	}),
	StoreItem = set({
		"id",
		"name",
		"description",
		"icon",
		"kind",
		"price",
		"robux",
		"grants",
		"startsAt",
		"endsAt",
		"purchaseLimit",
		"sortOrder",
		"featured",
	}),
	Event = set({
		"id",
		"name",
		"description",
		"icon",
		"kind",
		"startsAt",
		"endsAt",
		"shopClosesAt",
		"missions",
		"modifiers",
		"modes",
		"shop",
		"tokenConversionCredits",
	}),
	Season = set({
		"id",
		"name",
		"startsAt",
		"endsAt",
		"chapters",
		"pointsByRank",
		"pointsPerDailyMission",
		"paidUnlock",
	}),
	-- nested groups commonly written with optional fields
	Hull = set({ "hp", "massKg", "armor" }),
	HullArmor = set({
		"upperFront",
		"lowerFront",
		"side",
		"rear",
		"roof",
		"floor",
		"engineDeck",
		"superstructureFront",
		"superstructureSide",
		"skirts",
	}),
	Mobility = set({ "forwardKmh", "reverseKmh", "pivot" }),
	HullVisual = set({
		"lengthM",
		"widthM",
		"heightM",
		"groundClearanceM",
		"style",
		"upperFrontAngleDeg",
		"lowerFrontAngleDeg",
		"upperFrontFraction",
		"rearAngleDeg",
		"sideSlopeDeg",
		"turretRing",
		"superstructure",
		"engineDeck",
		"fenders",
		"skirts",
		"sponsons",
	}),
	Layout = set({ "engine", "transmission", "ammoRacks", "fuel", "optics", "overrides", "crewSeats" }),
	Slots = set({ "equipment", "consumables", "categorySlot" }),
	Economy = set({ "creditMul", "xpMul", "crewXpMul", "repairMul" }),
	Camo = set({ "stationary", "moving", "net" }),
}

--------------------------------------------------------------------------------
-- Validation context and primitive checks
--------------------------------------------------------------------------------

type Ctx = {
	errors: { ContentIssue },
	warnings: { ContentIssue },
	opts: ValidateOptions,
	reg: any,
}

local function addError(ctx: Ctx, code: string, path: string, message: string)
	table.insert(ctx.errors, { code = code, path = path, message = message, severity = "error" })
end

local function addWarning(ctx: Ctx, code: string, path: string, message: string)
	table.insert(ctx.warnings, { code = code, path = path, message = message, severity = "warning" })
end

local function isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function describe(v: any): string
	if type(v) == "string" then
		return `"{v}"`
	end
	return tostring(v)
end

--- Number in [min, max]; missing allowed only when optional. Returns true when present and valid.
local function num(
	ctx: Ctx,
	path: string,
	v: any,
	min: number,
	max: number,
	optional: boolean?,
	integer: boolean?
): boolean
	if v == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required number is missing")
		end
		return false
	end
	if not isFinite(v) then
		addError(ctx, "BAD_VALUE", path, `expected a finite number, got {describe(v)}`)
		return false
	end
	if integer and v ~= math.floor(v) then
		addError(ctx, "BAD_VALUE", path, `expected an integer, got {v}`)
		return false
	end
	if v < min or v > max then
		addError(ctx, "BAD_VALUE", path, `expected {min}..{max}, got {v}`)
		return false
	end
	return true
end

local function str(ctx: Ctx, path: string, v: any, maxLen: number, optional: boolean?): boolean
	if v == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required text is missing")
		end
		return false
	end
	if type(v) ~= "string" or v == "" then
		addError(ctx, "BAD_VALUE", path, `expected non-empty text, got {describe(v)}`)
		return false
	end
	if #v > maxLen then
		addError(ctx, "BAD_VALUE", path, `text longer than {maxLen} characters ({#v})`)
		return false
	end
	return true
end

local function bool(ctx: Ctx, path: string, v: any, optional: boolean?): boolean
	if v == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required boolean is missing")
		end
		return false
	end
	if type(v) ~= "boolean" then
		addError(ctx, "BAD_VALUE", path, `expected a boolean, got {describe(v)}`)
		return false
	end
	return true
end

local function enum(ctx: Ctx, path: string, v: any, allowed: { [string]: boolean }, optional: boolean?): boolean
	if v == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required value is missing")
		end
		return false
	end
	if type(v) ~= "string" or not allowed[v] then
		addError(ctx, "BAD_VALUE", path, `unknown value {describe(v)}`)
		return false
	end
	return true
end

--- Dense array with a length in [minLen, maxLen]. Returns true when it is a usable array.
local function list(ctx: Ctx, path: string, v: any, minLen: number, maxLen: number, optional: boolean?): boolean
	if v == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required list is missing")
		end
		return false
	end
	if type(v) ~= "table" then
		addError(ctx, "BAD_VALUE", path, `expected a list, got {typeof(v)}`)
		return false
	end
	local n = #v
	local count = 0
	for _ in v do
		count += 1
	end
	if count ~= n then
		addError(ctx, "BAD_VALUE", path, "expected a dense list (no holes or named keys)")
		return false
	end
	if n < minLen or n > maxLen then
		addError(ctx, "BAD_VALUE", path, `expected {minLen}..{maxLen} entries, got {n}`)
		return false
	end
	return true
end

local function tbl(ctx: Ctx, path: string, v: any, optional: boolean?): boolean
	if v == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required table is missing")
		end
		return false
	end
	if type(v) ~= "table" then
		addError(ctx, "BAD_VALUE", path, `expected a table, got {typeof(v)}`)
		return false
	end
	return true
end

local function fields(ctx: Ctx, path: string, v: any, allowed: { [string]: boolean })
	if type(v) ~= "table" then
		return
	end
	for _, key in TableUtil.sortedKeys(v) do
		if type(key) ~= "string" or not allowed[key] then
			addError(ctx, "UNKNOWN_FIELD", `{path}.{tostring(key)}`, "unknown field (typo?)")
		end
	end
end

local function enumList(
	ctx: Ctx,
	path: string,
	v: any,
	allowed: { [string]: boolean },
	minLen: number,
	maxLen: number,
	optional: boolean?
)
	if list(ctx, path, v, minLen, maxLen, optional) then
		local seen = {}
		for i, item in v do
			if enum(ctx, `{path}[{i}]`, item, allowed) then
				if seen[item] then
					addError(ctx, "BAD_VALUE", `{path}[{i}]`, `duplicate {describe(item)}`)
				end
				seen[item] = true
			end
		end
	end
end

local function color(ctx: Ctx, path: string, v: any, optional: boolean?)
	if v == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required Color3 is missing")
		end
		return
	end
	if typeof(v) ~= "Color3" then
		addError(ctx, "BAD_VALUE", path, `expected a Color3, got {typeof(v)}`)
	end
end

local function range(ctx: Ctx, path: string, v: any, min: number, max: number, optional: boolean?): boolean
	if not tbl(ctx, path, v, optional) then
		return false
	end
	local okMin = num(ctx, path .. ".min", v.min, min, max)
	local okMax = num(ctx, path .. ".max", v.max, min, max)
	if okMin and okMax and v.min > v.max then
		addError(ctx, "BAD_VALUE", path, `min {v.min} is greater than max {v.max}`)
		return false
	end
	return okMin and okMax
end

local ICON_PATTERN = "^[a-z0-9_]+/[a-z0-9_]+$"

local function icon(ctx: Ctx, path: string, key: any, optional: boolean?)
	if key == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, "required icon key is missing")
		end
		return
	end
	if type(key) ~= "string" or not string.match(key, ICON_PATTERN) then
		addError(ctx, "BAD_VALUE", path, `icon key must look like "folder/name", got {describe(key)}`)
		return
	end
	local catalogue = ctx.opts.iconKeys
	if catalogue ~= nil and not catalogue[key] then
		addError(ctx, "ASSET_KEY", path, `icon {describe(key)} is not in the asset manifest`)
	end
end

local function sound(ctx: Ctx, path: string, key: string)
	local catalogue = ctx.opts.soundKeys
	if catalogue ~= nil and not catalogue[key] then
		addError(ctx, "ASSET_KEY", path, `sound {describe(key)} is not in the audio catalogue`)
	end
end

local function vec2(ctx: Ctx, path: string, v: any, halfSize: number?): boolean
	if not tbl(ctx, path, v) then
		return false
	end
	local bound = halfSize or 1e6
	local okX = num(ctx, path .. ".x", v.x, -bound, bound)
	local okZ = num(ctx, path .. ".z", v.z, -bound, bound)
	if not (okX and okZ) and halfSize ~= nil and isFinite(v.x) and isFinite(v.z) then
		-- num() already reported the value; add a map-specific code so authors find bound problems quickly
		addError(ctx, "MAP_BOUNDS", path, `outside the playable square (±{halfSize} m)`)
	end
	return okX and okZ
end

local function ref(ctx: Ctx, path: string, id: any, kind: ContentKind, optional: boolean?): any
	if id == nil then
		if not optional then
			addError(ctx, "MISSING_FIELD", path, `required {KIND_BY_NAME[kind].label} id is missing`)
		end
		return nil
	end
	local found = ctx.reg:_get(kind, id)
	if found == nil then
		addError(ctx, "DANGLING_REF", path, `unknown {KIND_BY_NAME[kind].label} {describe(id)}`)
	end
	return found
end

local function refList(
	ctx: Ctx,
	path: string,
	v: any,
	kind: ContentKind,
	minLen: number,
	maxLen: number,
	optional: boolean?
)
	if list(ctx, path, v, minLen, maxLen, optional) then
		local seen = {}
		for i, id in v do
			ref(ctx, `{path}[{i}]`, id, kind)
			if seen[id] then
				addError(ctx, "BAD_VALUE", `{path}[{i}]`, `duplicate {describe(id)}`)
			end
			seen[id] = true
		end
	end
end

local function modifiers(ctx: Ctx, path: string, v: any, optional: boolean?)
	if not list(ctx, path, v, 0, 32, optional) then
		return
	end
	for i, m in v do
		local p = `{path}[{i}]`
		if not tbl(ctx, p, m) then
			continue
		end
		fields(ctx, p, m, set({ "stat", "op", "value", "condition", "durationS", "rangeM", "module" }))
		enum(ctx, p .. ".stat", m.stat, E.statKey)
		enum(ctx, p .. ".op", m.op, E.statOp)
		if m.op == "mul" then
			num(ctx, p .. ".value", m.value, 0.01, 10)
		else
			num(ctx, p .. ".value", m.value, -1000, 1000)
		end
		enum(ctx, p .. ".condition", m.condition, E.statCondition, true)
		num(ctx, p .. ".durationS", m.durationS, 0, 600, true)
		num(ctx, p .. ".rangeM", m.rangeM, 0, 600, true)
		enum(ctx, p .. ".module", m.module, E.internalModule, true)
		local timed = m.condition == "AfterShot" or m.condition == "AfterTakingDamage" or m.condition == "AfterSpotting"
		if timed and m.durationS == nil then
			addError(ctx, "BAD_VALUE", p .. ".durationS", `condition {m.condition} needs durationS`)
		end
		if m.condition == "NearEnemy" and m.rangeM == nil then
			addError(ctx, "BAD_VALUE", p .. ".rangeM", "condition NearEnemy needs rangeM")
		end
	end
end

local function price(ctx: Ctx, path: string, v: any, optional: boolean?)
	if not tbl(ctx, path, v, optional) then
		return
	end
	fields(ctx, path, v, set({ "credits", "bullion", "campaignTokens", "eventTokens" }))
	num(ctx, path .. ".credits", v.credits, 0, 1e9, true, true)
	num(ctx, path .. ".bullion", v.bullion, 0, 1e6, true, true)
	num(ctx, path .. ".campaignTokens", v.campaignTokens, 0, 1e6, true, true)
	if tbl(ctx, path .. ".eventTokens", v.eventTokens, true) then
		ref(ctx, path .. ".eventTokens.eventId", v.eventTokens.eventId, "Event")
		num(ctx, path .. ".eventTokens.amount", v.eventTokens.amount, 1, 1e6, false, true)
	end
end

local function rewards(ctx: Ctx, path: string, v: any, minLen: number, optional: boolean?)
	if not list(ctx, path, v, minLen, 32, optional) then
		return
	end
	for i, r in v do
		local p = `{path}[{i}]`
		if not tbl(ctx, p, r) then
			continue
		end
		fields(ctx, p, r, set({ "kind", "id", "amount" }))
		if enum(ctx, p .. ".kind", r.kind, E.rewardKind) then
			local refKind: ContentKind? = REWARD_REF[r.kind]
			if refKind ~= nil then
				ref(ctx, p .. ".id", r.id, refKind :: ContentKind)
			elseif r.id ~= nil then
				addError(ctx, "REWARD", p .. ".id", `reward kind {r.kind} does not take an id`)
			end
		end
		num(ctx, p .. ".amount", r.amount, 1, 1e9, false, true)
	end
end

local function balanceKit(ctx: Ctx, path: string, v: any, optional: boolean?)
	if not tbl(ctx, path, v, optional) then
		return
	end
	fields(ctx, path, v, set({ "mul", "camoAdd", "viewRangeAddM", "depressionDeg", "depressionAddDeg" }))
	if tbl(ctx, path .. ".mul", v.mul, true) then
		for _, key in TableUtil.sortedKeys(v.mul) do
			local p = `{path}.mul.{tostring(key)}`
			if type(key) ~= "string" or not E.balanceStat[key] then
				addError(ctx, "BAD_VALUE", p, "unknown balance stat")
			else
				num(ctx, p, v.mul[key], 0.05, 10)
			end
		end
	end
	num(ctx, path .. ".camoAdd", v.camoAdd, -0.5, 0.5, true)
	num(ctx, path .. ".viewRangeAddM", v.viewRangeAddM, -200, 200, true)
	num(ctx, path .. ".depressionDeg", v.depressionDeg, 0, 30, true)
	num(ctx, path .. ".depressionAddDeg", v.depressionAddDeg, -15, 15, true)
end

local function camoSpec(ctx: Ctx, path: string, v: any, optional: boolean?)
	if not tbl(ctx, path, v, optional) then
		return
	end
	fields(ctx, path, v, FIELDS.Camo)
	local okS = num(ctx, path .. ".stationary", v.stationary, 0, 0.6)
	local okM = num(ctx, path .. ".moving", v.moving, 0, 0.6)
	num(ctx, path .. ".net", v.net, 0, 0.5, true)
	if okS and okM and v.moving > v.stationary then
		addWarning(ctx, "BAD_VALUE", path, "moving camo is higher than stationary camo")
	end
end

local function terrainResistance(ctx: Ctx, path: string, v: any)
	if not tbl(ctx, path, v) then
		return
	end
	local okH = num(ctx, path .. ".hard", v.hard, 0.2, 5)
	local okM = num(ctx, path .. ".medium", v.medium, 0.2, 5)
	local okS = num(ctx, path .. ".soft", v.soft, 0.2, 5)
	if okH and okM and okS and not (v.hard <= v.medium and v.medium <= v.soft) then
		addError(ctx, "BAD_VALUE", path, "terrain resistance must satisfy hard <= medium <= soft")
	end
end

local function idOf(def: any, spec: KindSpec): any
	if type(def) ~= "table" then
		return nil
	end
	return def[spec.idField]
end

local ID_PATTERN = "^[a-z][a-z0-9_]*$"
local MAX_ID_LENGTH = 48

--------------------------------------------------------------------------------
-- Registry
--------------------------------------------------------------------------------

type KindIndex = {
	byId: { [any]: any },
	list: { any },
	sortedIds: { any },
	ordinals: { [any]: number },
}

type RegistryState = {
	_bundle: ContentBundle,
	_index: { [string]: KindIndex },
	_modules: { [string]: any },
	_buildIssues: { ContentIssue },
	_edges: { TechTreeEdge },
	_parents: { [string]: { TechTreeEdge } },
	_children: { [string]: { TechTreeEdge } },
	_hash: string?,
}

local Registry = {}
Registry.__index = Registry

export type ContentRegistry = typeof(setmetatable({} :: RegistryState, Registry))

local ContentRegistry = {}

--- Runtime mirror of every string-literal union in Types/Content, as sets ({ [value] = true }), keyed by a short
--- name (ENUMS.statKey, ENUMS.role, ENUMS.battleStat…). Tools and UI use it to list valid values; a spec checks it
--- against the type declarations so the validator and the static types cannot drift apart.
ContentRegistry.ENUMS = Freeze.deep(E)

local function emptyIndex(): KindIndex
	return { byId = {}, list = {}, sortedIds = {}, ordinals = {} }
end

local function edgeLess(a: TechTreeEdge, b: TechTreeEdge): boolean
	if a.from ~= b.from then
		return a.from < b.from
	end
	return a.to < b.to
end

--- Builds a registry from a flat bundle (deep-frozen in place). Never throws on bad data: problems are recorded and
--- reported by validate().
function ContentRegistry.fromBundle(bundle: ContentBundle): ContentRegistry
	local raw = bundle :: any
	local issues: { ContentIssue } = {}
	if type(raw) ~= "table" then
		raw = {}
		table.insert(issues, {
			code = "MISSING_FIELD",
			path = "bundle",
			message = "content bundle is not a table",
			severity = "error",
		})
	end
	Freeze.deep(raw)

	local index: { [string]: KindIndex } = {}
	local modules: { [string]: any } = {}
	for _, spec in KINDS do
		local entries = raw[spec.field]
		local idx = emptyIndex()
		index[spec.kind] = idx
		if entries == nil then
			table.insert(issues, {
				code = "MISSING_FIELD",
				path = spec.field,
				message = `bundle has no {spec.field} list`,
				severity = "error",
			})
			continue
		end
		if type(entries) ~= "table" then
			table.insert(issues, {
				code = "BAD_VALUE",
				path = spec.field,
				message = `expected a list of {spec.label} definitions`,
				severity = "error",
			})
			continue
		end
		for i, def in entries do
			local path = `{spec.field}[{i}]`
			local id = idOf(def, spec)
			local validId
			if spec.kind == "Tier" then
				validId = isFinite(id) and id == math.floor(id)
			else
				validId = type(id) == "string" and #id <= MAX_ID_LENGTH and string.match(id, ID_PATTERN) ~= nil
			end
			if not validId then
				table.insert(issues, {
					code = "INVALID_ID",
					path = path,
					message = `invalid {spec.label} id {describe(id)} (snake_case, <= {MAX_ID_LENGTH} chars)`,
					severity = "error",
				})
				continue
			end
			if idx.byId[id] ~= nil then
				table.insert(issues, {
					code = "DUPLICATE_ID",
					path = path,
					message = `duplicate {spec.label} id {describe(id)}`,
					severity = "error",
				})
				continue
			end
			if MODULE_FIELD[spec.kind] ~= nil then
				if modules[id] ~= nil then
					table.insert(issues, {
						code = "DUPLICATE_ID",
						path = path,
						message = `module id {describe(id)} is already used by another module kind`,
						severity = "error",
					})
					continue
				end
				modules[id] = def
			end
			idx.byId[id] = def
			table.insert(idx.list, def)
		end
		idx.sortedIds = TableUtil.sortedKeys(idx.byId)
		for ordinal, id in idx.sortedIds do
			idx.ordinals[id] = ordinal
		end
	end

	-- Tech-tree edges (only edges whose endpoints exist; validate() reports the rest).
	local edges: { TechTreeEdge } = {}
	local parents: { [string]: { TechTreeEdge } } = {}
	local children: { [string]: { TechTreeEdge } } = {}
	local vehicles = index.Vehicle.byId
	for _, vehicle in index.Vehicle.list do
		if type(vehicle.unlocks) ~= "table" then
			continue
		end
		for _, unlock in vehicle.unlocks do
			if type(unlock) ~= "table" then
				continue
			end
			local target = vehicles[unlock.vehicle]
			if target == nil then
				continue
			end
			local edge: TechTreeEdge = {
				from = vehicle.id,
				to = target.id,
				requires = unlock.requires,
				xp = if isFinite(target.researchXp) then target.researchXp else 0,
			}
			Freeze.deep(edge)
			table.insert(edges, edge)
		end
	end
	table.sort(edges, edgeLess)
	for _, edge in edges do
		local p = parents[edge.to] or {}
		parents[edge.to] = p
		table.insert(p, edge)
		local c = children[edge.from] or {}
		children[edge.from] = c
		table.insert(c, edge)
	end

	local state: RegistryState = {
		_bundle = raw :: ContentBundle,
		_index = index,
		_modules = modules,
		_buildIssues = issues,
		_edges = edges,
		_parents = parents,
		_children = children,
		_hash = nil,
	}
	return setmetatable(state, Registry)
end

--- Flattens a manifest (per-file lists for shells/guns/turrets/engines/tracks) into a bundle and builds it.
function ContentRegistry.fromSources(sources: ContentSources): ContentRegistry
	return ContentRegistry.fromBundle(ContentRegistry.flatten(sources))
end

--- Flattens a manifest into a new (unfrozen) bundle. The definitions are shared, not copied.
function ContentRegistry.flatten(sources: ContentSources): ContentBundle
	local src = sources :: any
	local bundle: any = {}
	for _, spec in KINDS do
		local value = src[spec.field]
		if MODULE_FIELD[spec.kind] ~= nil or spec.kind == "Shell" then
			local flat = {}
			if type(value) == "table" then
				for _, fileList in value do
					if type(fileList) == "table" then
						for _, def in fileList do
							table.insert(flat, def)
						end
					end
				end
			end
			bundle[spec.field] = flat
		else
			bundle[spec.field] = value
		end
	end
	return bundle :: ContentBundle
end

local shipped: ContentRegistry? = nil

--- The registry of the shipped content (Config/Content), built and frozen on first use.
function ContentRegistry.get(): ContentRegistry
	local current = shipped
	if current == nil then
		local sources = require("./Content") :: any
		current = ContentRegistry.fromSources(sources)
		shipped = current
	end
	return current :: ContentRegistry
end

--- A deep, mutable copy of the shipped bundle (for tests and tools that build variants).
function ContentRegistry.shippedBundle(): ContentBundle
	return TableUtil.deepCopy(ContentRegistry.get()._bundle)
end

--------------------------------------------------------------------------------
-- Getters
--------------------------------------------------------------------------------

function Registry._get(self: ContentRegistry, kind: ContentKind, id: any): any
	local idx = self._index[kind]
	if idx == nil or id == nil then
		return nil
	end
	return idx.byId[id]
end

function Registry.getFaction(self: ContentRegistry, id: string): Content.FactionDefinition?
	return self:_get("Faction", id)
end
function Registry.getClass(self: ContentRegistry, id: string): Content.ClassDefinition?
	return self:_get("Class", id)
end
function Registry.getRole(self: ContentRegistry, id: string): Content.RoleDefinition?
	return self:_get("Role", id)
end
function Registry.getTier(self: ContentRegistry, tier: number): Content.TierDefinition?
	return self:_get("Tier", tier)
end
function Registry.getShell(self: ContentRegistry, id: string): Content.ShellDefinition?
	return self:_get("Shell", id)
end
function Registry.getGun(self: ContentRegistry, id: string): Content.GunDefinition?
	return self:_get("Gun", id)
end
function Registry.getTurret(self: ContentRegistry, id: string): Content.TurretDefinition?
	return self:_get("Turret", id)
end
function Registry.getEngine(self: ContentRegistry, id: string): Content.EngineDefinition?
	return self:_get("Engine", id)
end
function Registry.getTracks(self: ContentRegistry, id: string): Content.TracksDefinition?
	return self:_get("Tracks", id)
end
--- Module of a given kind (nil when the id is unknown or belongs to another module kind).
function Registry.getModule(self: ContentRegistry, kind: ModuleKind, id: string): ModuleDefinition?
	return self:_get(kind, id)
end
--- Module of any kind (module ids are unique across kinds).
function Registry.getAnyModule(self: ContentRegistry, id: string): ModuleDefinition?
	return self._modules[id]
end
function Registry.getVehicle(self: ContentRegistry, id: string): VehicleDefinition?
	return self:_get("Vehicle", id)
end
function Registry.getEquipment(self: ContentRegistry, id: string): Content.EquipmentDefinition?
	return self:_get("Equipment", id)
end
function Registry.getConsumable(self: ContentRegistry, id: string): Content.ConsumableDefinition?
	return self:_get("Consumable", id)
end
function Registry.getSkill(self: ContentRegistry, id: string): Content.CrewSkillDefinition?
	return self:_get("CrewSkill", id)
end
function Registry.getCrewBook(self: ContentRegistry, id: string): Content.CrewBookDefinition?
	return self:_get("CrewBook", id)
end
function Registry.getBooster(self: ContentRegistry, id: string): Content.BoosterDefinition?
	return self:_get("Booster", id)
end
function Registry.getCustomization(self: ContentRegistry, id: string): Content.CustomizationDefinition?
	return self:_get("Customization", id)
end
function Registry.getMission(self: ContentRegistry, id: string): Content.MissionDefinition?
	return self:_get("Mission", id)
end
function Registry.getAchievement(self: ContentRegistry, id: string): Content.AchievementDefinition?
	return self:_get("Achievement", id)
end
function Registry.getMap(self: ContentRegistry, id: string): Content.MapDefinition?
	return self:_get("Map", id)
end
function Registry.getStoreItem(self: ContentRegistry, id: string): Content.StoreItem?
	return self:_get("StoreItem", id)
end
function Registry.getEvent(self: ContentRegistry, id: string): Content.EventDefinition?
	return self:_get("Event", id)
end
function Registry.getSeason(self: ContentRegistry, id: string): Content.SeasonDefinition?
	return self:_get("Season", id)
end
function Registry.getBranch(self: ContentRegistry, id: string): Content.BranchDefinition?
	return self:_get("Branch", id)
end
--- Branches of a faction, in manifest order.
function Registry.branchesByFaction(self: ContentRegistry, faction: string): { Content.BranchDefinition }
	local out = {}
	for _, branch in self:list("Branch") do
		if branch.faction == faction then
			table.insert(out, branch)
		end
	end
	return out
end

--- Every definition of a kind, in manifest order (frozen).
function Registry.list(self: ContentRegistry, kind: ContentKind): { any }
	local idx = self._index[kind]
	return if idx then idx.list else {}
end
function Registry.allVehicles(self: ContentRegistry): { VehicleDefinition }
	return self:list("Vehicle")
end
function Registry.allMaps(self: ContentRegistry): { Content.MapDefinition }
	return self:list("Map")
end

local function vehicleOrder(self: ContentRegistry): (any, any) -> boolean
	return function(a: any, b: any): boolean
		local fa = self:getFaction(a.faction)
		local fb = self:getFaction(b.faction)
		local oa = if fa then fa.order else 99
		local ob = if fb then fb.order else 99
		if oa ~= ob then
			return oa < ob
		end
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		local ra = if type(a.tree) == "table" and isFinite(a.tree.row) then a.tree.row else 0
		local rb = if type(b.tree) == "table" and isFinite(b.tree.row) then b.tree.row else 0
		if ra ~= rb then
			return ra < rb
		end
		return a.id < b.id
	end
end

local function filterVehicles(self: ContentRegistry, predicate: (VehicleDefinition) -> boolean): { VehicleDefinition }
	local out = {}
	for _, vehicle in self:allVehicles() do
		if predicate(vehicle) then
			table.insert(out, vehicle)
		end
	end
	table.sort(out, vehicleOrder(self))
	return out
end

--- Vehicles of a faction sorted by tier, tree row, id.
function Registry.vehiclesByFaction(self: ContentRegistry, faction: string): { VehicleDefinition }
	return filterVehicles(self, function(v)
		return v.faction == faction
	end)
end
--- Vehicles of a tier sorted by faction order, tree row, id.
function Registry.vehiclesByTier(self: ContentRegistry, tier: number): { VehicleDefinition }
	return filterVehicles(self, function(v)
		return v.tier == tier
	end)
end
function Registry.vehiclesByClass(self: ContentRegistry, class: string): { VehicleDefinition }
	return filterVehicles(self, function(v)
		return v.class == class
	end)
end
--- Roles of a class in the class's UI order.
function Registry.rolesByClass(self: ContentRegistry, class: string): { Content.RoleDefinition }
	local out = {}
	local def = self:getClass(class)
	if def ~= nil and type(def.roles) == "table" then
		for _, roleId in def.roles do
			local role = self:getRole(roleId)
			if role ~= nil then
				table.insert(out, role)
			end
		end
	end
	return out
end

--- Tech-tree edges (sorted by from, to), optionally restricted to one faction.
function Registry.techTreeEdges(self: ContentRegistry, faction: string?): { TechTreeEdge }
	if faction == nil then
		return self._edges
	end
	local out = {}
	for _, edge in self._edges do
		local from = self:getVehicle(edge.from)
		if from ~= nil and from.faction == faction then
			table.insert(out, edge)
		end
	end
	return out
end
function Registry.parentsOf(self: ContentRegistry, vehicleId: string): { TechTreeEdge }
	return self._parents[vehicleId] or {}
end
function Registry.childrenOf(self: ContentRegistry, vehicleId: string): { TechTreeEdge }
	return self._children[vehicleId] or {}
end

--- Total mass (kg) of a vehicle in a configuration, or nil when the vehicle or a module is unknown.
function Registry.configurationMassKg(self: ContentRegistry, vehicleId: string, config: Configuration): number?
	local vehicle = self:getVehicle(vehicleId) :: any
	if vehicle == nil or type(vehicle.hull) ~= "table" or not isFinite(vehicle.hull.massKg) then
		return nil
	end
	local total = vehicle.hull.massKg
	for _, slot in CONFIG_SLOTS do
		local module = self:_get(slot.kind, (config :: any)[slot.key]) :: any
		if module == nil or not isFinite(module.massKg) then
			return nil
		end
		total += module.massKg
	end
	return total
end

local function listContains(listValue: any, value: any): boolean
	if type(listValue) ~= "table" then
		return false
	end
	return table.find(listValue, value) ~= nil
end

--- Mount rules for a configuration (garage, transactions, battle loadout check): every module belongs to the
--- vehicle, the turret mounts the gun and the total mass fits the tracks' load limit. Ok(massKg) or Err.
function Registry.checkConfiguration(self: ContentRegistry, vehicleId: string, config: Configuration): Result<number>
	local vehicle = self:getVehicle(vehicleId) :: any
	if vehicle == nil then
		return Result.err(ErrorCodes.NOT_FOUND, `unknown vehicle {describe(vehicleId)}`)
	end
	if type(config) ~= "table" then
		return Result.err(ErrorCodes.INVALID_ARGS, "configuration must be a table")
	end
	local cfg = config :: any
	for _, slot in CONFIG_SLOTS do
		local id = cfg[slot.key]
		if self:_get(slot.kind, id) == nil then
			return Result.err(ErrorCodes.NOT_FOUND, `{slot.key}: unknown {string.lower(slot.kind)} {describe(id)}`)
		end
		if type(vehicle.modules) ~= "table" or not listContains(vehicle.modules[slot.list], id) then
			return Result.err(ErrorCodes.INVALID_ARGS, `{slot.key}: {describe(id)} does not fit {vehicleId}`)
		end
	end
	local turret = self:getTurret(cfg.turret) :: any
	if not listContains(turret.guns, cfg.gun) then
		return Result.err(ErrorCodes.INVALID_ARGS, `gun {describe(cfg.gun)} does not fit turret {describe(cfg.turret)}`)
	end
	local mass = self:configurationMassKg(vehicleId, config)
	local tracks = self:getTracks(cfg.tracks) :: any
	if mass == nil then
		return Result.err(ErrorCodes.INVALID_ARGS, "configuration mass is undefined")
	end
	if not isFinite(tracks.loadLimitKg) or mass > tracks.loadLimitKg then
		return Result.err(
			ErrorCodes.INVALID_ARGS,
			`mass {mass} kg exceeds the {describe(cfg.tracks)} load limit {tostring(tracks.loadLimitKg)} kg`
		)
	end
	return Result.ok(mass)
end

--- Stable 1-based ordinal of an id within its kind (sorted ids). Codecs pack ids as ordinals together with the
--- content hash (a hash mismatch means the ordinals cannot be trusted).
function Registry.ordinal(self: ContentRegistry, kind: ContentKind, id: any): number?
	local idx = self._index[kind]
	return if idx then idx.ordinals[id] else nil
end
function Registry.idAt(self: ContentRegistry, kind: ContentKind, ordinal: number): any
	local idx = self._index[kind]
	return if idx then idx.sortedIds[ordinal] else nil
end

--- Issues found while indexing (invalid/duplicate ids, missing lists). Also included in validate().
function Registry.buildIssues(self: ContentRegistry): { ContentIssue }
	return table.clone(self._buildIssues)
end

--------------------------------------------------------------------------------
-- Content hash (determinism, replays, map/manifest compatibility)
--------------------------------------------------------------------------------

local function encode(value: any, out: { string })
	local t = typeof(value)
	if t == "nil" then
		table.insert(out, "n")
	elseif t == "boolean" then
		table.insert(out, if value then "T" else "F")
	elseif t == "number" then
		table.insert(out, "d" .. string.pack("<d", if value == 0 then 0 else value))
	elseif t == "string" then
		table.insert(out, "s" .. string.pack("<s4", value))
	elseif t == "Color3" then
		table.insert(out, "c" .. string.pack("<ddd", value.R, value.G, value.B))
	elseif t == "Vector3" then
		table.insert(out, "v" .. string.pack("<ddd", value.X, value.Y, value.Z))
	elseif t == "table" then
		table.insert(out, "{")
		for _, key in TableUtil.sortedKeys(value) do
			encode(key, out)
			encode(value[key], out)
		end
		table.insert(out, "}")
	else
		table.insert(out, "?" .. t)
	end
end

--- Stable hex hash of all content (same data -> same hash on server, client and Lune).
function Registry.contentHash(self: ContentRegistry): string
	local cached = self._hash
	if cached ~= nil then
		return cached
	end
	local parts: { string } = {}
	for _, spec in KINDS do
		encode(spec.field, parts)
		encode(self._index[spec.kind].list, parts)
	end
	local blob = table.concat(parts)
	local hash = string.format("%08x%08x", RNG.hash(blob), RNG.hash("hulldown-content", blob))
	self._hash = hash
	return hash
end

--------------------------------------------------------------------------------
-- Validators: registries (factions, classes, roles, tiers)
--------------------------------------------------------------------------------

local function validateLockedSet(ctx: Ctx, field: string, idx: KindIndex, expected: { any }, label: string)
	for _, id in expected do
		if idx.byId[id] == nil then
			addError(ctx, "LOCKED_SET", field, `missing {label} {describe(id)}`)
		end
	end
	local allowed = {}
	for _, id in expected do
		allowed[id] = true
	end
	for _, id in idx.sortedIds do
		if not allowed[id] then
			addError(ctx, "LOCKED_SET", field, `unexpected {label} {describe(id)} (the set is locked)`)
		end
	end
end

local function validateFactions(ctx: Ctx, reg: ContentRegistry)
	local idx = reg._index.Faction
	validateLockedSet(ctx, "factions", idx, FACTION_IDS, "faction")
	local orders = {}
	for i, f in idx.list do
		local p = `factions[{i}]({f.id})`
		fields(ctx, p, f, FIELDS.Faction)
		str(ctx, p .. ".name", f.name, 32)
		str(ctx, p .. ".shortName", f.shortName, 4)
		str(ctx, p .. ".motto", f.motto, 80)
		str(ctx, p .. ".description", f.description, 400)
		enumList(ctx, p .. ".signatures", f.signatures, E.factionSignature, 0, 4)
		if list(ctx, p .. ".focus", f.focus, 1, 4) then
			for j, line in f.focus do
				str(ctx, `{p}.focus[{j}]`, line, 40)
			end
		end
		icon(ctx, p .. ".emblem", f.emblem)
		if num(ctx, p .. ".order", f.order, 1, 6, false, true) then
			if orders[f.order] then
				addError(ctx, "BAD_VALUE", p .. ".order", `order {f.order} is used twice`)
			end
			orders[f.order] = true
		end
		if tbl(ctx, p .. ".palette", f.palette) then
			color(ctx, p .. ".palette.primary", f.palette.primary)
			color(ctx, p .. ".palette.secondary", f.palette.secondary)
			color(ctx, p .. ".palette.textTint", f.palette.textTint)
		end
		if tbl(ctx, p .. ".vehiclePaint", f.vehiclePaint) then
			color(ctx, p .. ".vehiclePaint.base", f.vehiclePaint.base)
			color(ctx, p .. ".vehiclePaint.secondary", f.vehiclePaint.secondary)
			color(ctx, p .. ".vehiclePaint.accent", f.vehiclePaint.accent)
			if list(ctx, p .. ".vehiclePaint.camo", f.vehiclePaint.camo, 1, 6) then
				for j, c in f.vehiclePaint.camo do
					color(ctx, `{p}.vehiclePaint.camo[{j}]`, c)
				end
			end
		end
		balanceKit(ctx, p .. ".kit", f.kit)
		if str(ctx, p .. ".builderPreset", f.builderPreset, MAX_ID_LENGTH) then
			if not string.match(f.builderPreset, ID_PATTERN) then
				addError(ctx, "BAD_VALUE", p .. ".builderPreset", "preset keys are snake_case")
			end
		end
	end
end

local function validateBranches(ctx: Ctx, reg: ContentRegistry)
	for i, b in reg._index.Branch.list do
		local p = `branches[{i}]({b.id})`
		fields(ctx, p, b, FIELDS.Branch)
		local faction = ref(ctx, p .. ".faction", b.faction, "Faction")
		if faction ~= nil and type(b.id) == "string" then
			-- ids start with the faction's designation prefix (roster.md §0.2), e.g. iu_bulwark
			local prefix = string.lower(faction.shortName or "") .. "_"
			if prefix ~= "_" and string.sub(b.id, 1, #prefix) ~= prefix then
				addError(ctx, "BAD_VALUE", p .. ".id", `branch ids start with the faction prefix "{prefix}"`)
			end
		end
		str(ctx, p .. ".name", b.name, 40)
		str(ctx, p .. ".description", b.description, 200)
		enumList(ctx, p .. ".classes", b.classes, E.class, 1, 5)
		range(ctx, p .. ".tiers", b.tiers, 1, 11)
	end
end

local function validateClasses(ctx: Ctx, reg: ContentRegistry)
	local idx = reg._index.Class
	validateLockedSet(ctx, "classes", idx, CLASS_IDS, "class")
	for i, c in idx.list do
		local p = `classes[{i}]({c.id})`
		fields(ctx, p, c, FIELDS.Class)
		str(ctx, p .. ".name", c.name, 32)
		str(ctx, p .. ".shortName", c.shortName, 4)
		str(ctx, p .. ".description", c.description, 300)
		icon(ctx, p .. ".icon", c.icon)
		icon(ctx, p .. ".minimapIcon", c.minimapIcon)
		num(ctx, p .. ".order", c.order, 1, 5, false, true)
		range(ctx, p .. ".tiers", c.tiers, 1, 11)
		if list(ctx, p .. ".roles", c.roles, 1, 6) then
			for j, roleId in c.roles do
				local role = ref(ctx, `{p}.roles[{j}]`, roleId, "Role")
				if role ~= nil and role.class ~= c.id then
					addError(
						ctx,
						"ROLE_CLASS",
						`{p}.roles[{j}]`,
						`role {roleId} belongs to class {tostring(role.class)}`
					)
				end
			end
		end
		balanceKit(ctx, p .. ".baseline", c.baseline)
		camoSpec(ctx, p .. ".camo", c.camo)
		camoSpec(ctx, p .. ".camoCasemate", c.camoCasemate, true)
		if c.id == "td" and c.camoCasemate == nil then
			addError(ctx, "MISSING_FIELD", p .. ".camoCasemate", "the td class needs a casemate camo default")
		end
		num(ctx, p .. ".viewRangeMul", c.viewRangeMul, 0.5, 1.5)
		num(ctx, p .. ".afterShotBloom", c.afterShotBloom, 1, 8)
		terrainResistance(ctx, p .. ".terrainResistance", c.terrainResistance)
		num(ctx, p .. ".signalRangeM", c.signalRangeM, 0, 2000)
	end
end

local function validateRoles(ctx: Ctx, reg: ContentRegistry)
	local idx = reg._index.Role
	for i, r in idx.list do
		local p = `roles[{i}]({r.id})`
		fields(ctx, p, r, FIELDS.Role)
		if not E.role[r.id] then
			addError(ctx, "BAD_VALUE", p .. ".id", `unknown role id {describe(r.id)}`)
		end
		if enum(ctx, p .. ".class", r.class, E.class) then
			if type(r.id) == "string" and string.sub(r.id, 1, #r.class + 1) ~= r.class .. "_" then
				addError(ctx, "ROLE_CLASS", p .. ".class", `role id {r.id} does not belong to class {r.class}`)
			end
			local class = reg:getClass(r.class)
			if class ~= nil and not listContains(class.roles, r.id) then
				addError(ctx, "ROLE_CLASS", p .. ".class", `class {r.class} does not list role {r.id}`)
			end
		end
		str(ctx, p .. ".name", r.name, 24)
		str(ctx, p .. ".description", r.description, 160)
		str(ctx, p .. ".playstyle", r.playstyle, 400)
		if list(ctx, p .. ".tips", r.tips, 3, 3) then
			for j, tip in r.tips do
				str(ctx, `{p}.tips[{j}]`, tip, 80)
			end
		end
		enumList(ctx, p .. ".statEmphasis", r.statEmphasis, E.statKey, 1, 4)
		balanceKit(ctx, p .. ".trims", r.trims)
		enum(ctx, p .. ".categorySlot", r.categorySlot, E.equipmentCategory)
		enum(ctx, p .. ".group", r.group, E.roleGroup)
		icon(ctx, p .. ".badge", r.badge)
		if tbl(ctx, p .. ".roleScore", r.roleScore) then
			local sum = 0
			for _, key in TableUtil.sortedKeys(r.roleScore) do
				local kp = `{p}.roleScore.{tostring(key)}`
				if type(key) ~= "string" or not E.roleScore[key] then
					addError(ctx, "ROLE_SCORE", kp, "unknown Role Score component")
				elseif num(ctx, kp, r.roleScore[key], 0, 1) then
					sum += r.roleScore[key]
				end
			end
			if math.abs(sum - 1) > 1e-6 then
				addError(ctx, "ROLE_SCORE", p .. ".roleScore", `weights must sum to 1, got {sum}`)
			end
		end
		if list(ctx, p .. ".fieldKit", r.fieldKit, 1, 8, true) then
			for j, level in r.fieldKit do
				local lp = `{p}.fieldKit[{j}]`
				if tbl(ctx, lp, level) and list(ctx, lp .. ".options", level.options, 2, 2) then
					for k, option in level.options do
						local op = `{lp}.options[{k}]`
						if tbl(ctx, op, option) then
							str(ctx, op .. ".id", option.id, MAX_ID_LENGTH)
							str(ctx, op .. ".name", option.name, 40)
							str(ctx, op .. ".description", option.description, 160)
							modifiers(ctx, op .. ".effects", option.effects)
						end
					end
				end
			end
		end
	end
end

local function validateTiers(ctx: Ctx, reg: ContentRegistry)
	local idx = reg._index.Tier
	local expected = {}
	for t = 1, 11 do
		table.insert(expected, t)
	end
	validateLockedSet(ctx, "tiers", idx, expected, "tier")
	for i, t in idx.list do
		local p = `tiers[{i}]({tostring(t.tier)})`
		fields(ctx, p, t, FIELDS.Tier)
		if not num(ctx, p .. ".tier", t.tier, 1, 11, false, true) then
			continue
		end
		if t.numeral ~= NUMERALS[t.tier] then
			addError(ctx, "BAD_VALUE", p .. ".numeral", `tier {t.tier} numeral must be {NUMERALS[t.tier]}`)
		end
		str(ctx, p .. ".name", t.name, 24, true)
		icon(ctx, p .. ".badge", t.badge)
		if range(ctx, p .. ".matchmaking", t.matchmaking, 1, 11) then
			if t.tier < t.matchmaking.min or t.tier > t.matchmaking.max then
				addError(ctx, "TIER_RANGE", p .. ".matchmaking", "range must contain the tier itself")
			end
		end
		if tbl(ctx, p .. ".baseline", t.baseline) then
			local b = t.baseline
			local bp = p .. ".baseline"
			num(ctx, bp .. ".hp", b.hp, 50, 5000)
			num(ctx, bp .. ".alpha", b.alpha, 5, 2000)
			num(ctx, bp .. ".penetrationMm", b.penetrationMm, 5, 600)
			num(ctx, bp .. ".reloadS", b.reloadS, 0.3, 60)
			num(ctx, bp .. ".aimTimeS", b.aimTimeS, 0.3, 10)
			num(ctx, bp .. ".dispersionM100", b.dispersionM100, 0.05, 2)
			num(ctx, bp .. ".topSpeedKmh", b.topSpeedKmh, 5, 130)
			num(ctx, bp .. ".specificPowerHpT", b.specificPowerHpT, 1, 80)
			num(ctx, bp .. ".hullTraverseDegS", b.hullTraverseDegS, 1, 120)
			num(ctx, bp .. ".turretTraverseDegS", b.turretTraverseDegS, 1, 120)
			num(ctx, bp .. ".viewRangeM", b.viewRangeM, 100, 600)
			if tbl(ctx, bp .. ".hullArmorMm", b.hullArmorMm) then
				num(ctx, bp .. ".hullArmorMm.front", b.hullArmorMm.front, 0, 500)
				num(ctx, bp .. ".hullArmorMm.side", b.hullArmorMm.side, 0, 500)
				num(ctx, bp .. ".hullArmorMm.rear", b.hullArmorMm.rear, 0, 500)
			end
			num(ctx, bp .. ".turretFrontMm", b.turretFrontMm, 0, 500)
		end
		if tbl(ctx, p .. ".economy", t.economy) then
			local e = t.economy
			local ep = p .. ".economy"
			num(ctx, ep .. ".researchXp", e.researchXp, 0, 1e7, false, true)
			num(ctx, ep .. ".priceCredits", e.priceCredits, 0, 1e9, false, true)
			num(ctx, ep .. ".moduleXpTotal", e.moduleXpTotal, 0, 1e7, false, true)
			num(ctx, ep .. ".xpPerBattle", e.xpPerBattle, 0, 1e5)
			num(ctx, ep .. ".battlesAtTier", e.battlesAtTier, 0, 1000)
			num(ctx, ep .. ".fullRepairCredits", e.fullRepairCredits, 0, 1e7)
			num(ctx, ep .. ".shellCredits", e.shellCredits, 0, 1e5)
			num(ctx, ep .. ".netCreditsPerBattle", e.netCreditsPerBattle, -1e6, 1e6)
			num(ctx, ep .. ".xpScale", e.xpScale, 0.01, 100)
			num(ctx, ep .. ".creditScale", e.creditScale, 0.01, 100)
			num(ctx, ep .. ".premiumBullion", e.premiumBullion, 1, 1e5, true, true)
			num(ctx, ep .. ".premiumCreditMul", e.premiumCreditMul, 1, 5, true)
		end
		num(ctx, p .. ".equipmentSlots", t.equipmentSlots, 0, 3, false, true)
		num(ctx, p .. ".consumableSlots", t.consumableSlots, 0, 3, false, true)
		bool(ctx, p .. ".categorySlot", t.categorySlot)
		enum(ctx, p .. ".equipmentBand", t.equipmentBand, E.equipmentBand)
		if tbl(ctx, p .. ".fieldKit", t.fieldKit, true) then
			num(ctx, p .. ".fieldKit.levels", t.fieldKit.levels, 1, 10, false, true)
			num(ctx, p .. ".fieldKit.xpPerLevel", t.fieldKit.xpPerLevel, 1, 1e6, false, true)
		end
		num(ctx, p .. ".stunMaxS", t.stunMaxS, 0, 60)
		num(ctx, p .. ".moduleHpRefAlpha", t.moduleHpRefAlpha, 1, 3000)
	end
end

--------------------------------------------------------------------------------
-- Validators: ammunition and modules
--------------------------------------------------------------------------------

local function validateShells(ctx: Ctx, reg: ContentRegistry, used: { [string]: boolean })
	for i, s in reg._index.Shell.list do
		local p = `shells[{i}]({s.id})`
		fields(ctx, p, s, FIELDS.Shell)
		str(ctx, p .. ".name", s.name, 32)
		local kindOk = enum(ctx, p .. ".kind", s.kind, E.shellKind)
		bool(ctx, p .. ".special", s.special)
		num(ctx, p .. ".caliberMm", s.caliberMm, 5, 240)
		num(ctx, p .. ".damage", s.damage, 1, 3000)
		local penOk = num(ctx, p .. ".penetrationMm", s.penetrationMm, 1, 600)
		num(ctx, p .. ".velocityMps", s.velocityMps, 50, 2000)
		num(ctx, p .. ".priceCredits", s.priceCredits, 0, 1e5, false, true)
		num(ctx, p .. ".moduleDamage", s.moduleDamage, 0, 3000, true)
		num(ctx, p .. ".gravityMps2", s.gravityMps2, 1, 100, true)
		num(ctx, p .. ".maxRangeM", s.maxRangeM, 50, 2000, true)
		num(ctx, p .. ".normalizationDeg", s.normalizationDeg, 0, 20, true)
		num(ctx, p .. ".ricochetAngleDeg", s.ricochetAngleDeg, 45, 90, true)
		enum(ctx, p .. ".tracer", s.tracer, E.tracer, true)
		icon(ctx, p .. ".icon", s.icon, true)
		if kindOk then
			local explosive = s.kind == "HE" or s.kind == "HESH"
			local kinetic = s.kind == "AP" or s.kind == "APCR"
			if s.explosionRadiusM ~= nil then
				if explosive then
					num(ctx, p .. ".explosionRadiusM", s.explosionRadiusM, 0, 15)
				else
					addError(ctx, "SHELL_KIND", p .. ".explosionRadiusM", `{s.kind} shells do not explode`)
				end
			end
			if s.stun ~= nil then
				if not explosive then
					addError(ctx, "SHELL_KIND", p .. ".stun", "only HE/HESH shells can stun")
				elseif tbl(ctx, p .. ".stun", s.stun) then
					local okMax = num(ctx, p .. ".stun.maxS", s.stun.maxS, 0, 60)
					local okMin = num(ctx, p .. ".stun.minS", s.stun.minS, 0, 60)
					if okMax and okMin and s.stun.minS > s.stun.maxS then
						addError(ctx, "BAD_VALUE", p .. ".stun", "minS must not exceed maxS")
					end
				end
			end
			if s.penetrationAt500Mm ~= nil then
				if not kinetic then
					addError(ctx, "SHELL_KIND", p .. ".penetrationAt500Mm", "only AP/APCR lose penetration with range")
				elseif num(ctx, p .. ".penetrationAt500Mm", s.penetrationAt500Mm, 1, 600) and penOk then
					if s.penetrationAt500Mm > s.penetrationMm then
						addError(
							ctx,
							"BAD_VALUE",
							p .. ".penetrationAt500Mm",
							"falloff endpoint exceeds point-blank pen"
						)
					end
				end
			end
		end
		if not used[s.id] then
			addWarning(ctx, "ORPHAN", p, "no gun uses this shell")
		end
	end
end

local function moduleBase(ctx: Ctx, p: string, m: any, kind: string, allowed: { [string]: boolean })
	fields(ctx, p, m, allowed)
	if m.kind ~= kind then
		addError(ctx, "WRONG_KIND", p .. ".kind", `expected kind {kind}, got {describe(m.kind)}`)
	end
	str(ctx, p .. ".name", m.name, 40)
	num(ctx, p .. ".tier", m.tier, 1, 11, false, true)
	num(ctx, p .. ".massKg", m.massKg, 1, 100000)
	num(ctx, p .. ".priceCredits", m.priceCredits, 0, 1e8, false, true)
	num(ctx, p .. ".researchXp", m.researchXp, 0, 1e7, false, true)
end

local function validateReload(ctx: Ctx, p: string, r: any)
	if not tbl(ctx, p, r) then
		return
	end
	if not enum(ctx, p .. ".kind", r.kind, E.reloadKind) then
		return
	end
	if r.kind == "Single" then
		fields(ctx, p, r, set({ "kind", "reloadS" }))
		num(ctx, p .. ".reloadS", r.reloadS, 0.3, 90)
	elseif r.kind == "Magazine" then
		fields(ctx, p, r, set({ "kind", "size", "intraClipS", "reloadS" }))
		num(ctx, p .. ".size", r.size, 2, 12, false, true)
		num(ctx, p .. ".intraClipS", r.intraClipS, 0.1, 10)
		num(ctx, p .. ".reloadS", r.reloadS, 1, 120)
	elseif r.kind == "Autoreloader" then
		fields(ctx, p, r, set({ "kind", "size", "perShellReloadS", "intraClipS" }))
		local sizeOk = num(ctx, p .. ".size", r.size, 2, 8, false, true)
		num(ctx, p .. ".intraClipS", r.intraClipS, 0.1, 10)
		if list(ctx, p .. ".perShellReloadS", r.perShellReloadS, 2, 8) then
			for j, t in r.perShellReloadS do
				num(ctx, `{p}.perShellReloadS[{j}]`, t, 0.3, 60)
			end
			if sizeOk and #r.perShellReloadS ~= r.size then
				addError(ctx, "BAD_VALUE", p .. ".perShellReloadS", `needs exactly size ({r.size}) timers`)
			end
		end
	else
		fields(ctx, p, r, set({ "kind", "reloadEachS", "salvoDelayS", "chargeTimeS", "volleyDispersionMul" }))
		num(ctx, p .. ".reloadEachS", r.reloadEachS, 1, 90)
		num(ctx, p .. ".salvoDelayS", r.salvoDelayS, 0.1, 10)
		num(ctx, p .. ".chargeTimeS", r.chargeTimeS, 0.1, 10)
		num(ctx, p .. ".volleyDispersionMul", r.volleyDispersionMul, 1, 5)
	end
end

local function validateGuns(ctx: Ctx, reg: ContentRegistry, used: { [string]: boolean })
	for i, g in reg._index.Gun.list do
		local p = `guns[{i}]({g.id})`
		moduleBase(ctx, p, g, "Gun", FIELDS.Gun)
		local calOk = num(ctx, p .. ".caliberMm", g.caliberMm, 5, 240)
		if list(ctx, p .. ".shells", g.shells, 1, 3) then
			local seen = {}
			for j, shellId in g.shells do
				local sp = `{p}.shells[{j}]`
				if seen[shellId] then
					addError(ctx, "SHELL_COUNT", sp, `shell {describe(shellId)} listed twice`)
				end
				seen[shellId] = true
				local shell = ref(ctx, sp, shellId, "Shell")
				if shell ~= nil then
					if calOk and shell.caliberMm ~= g.caliberMm then
						addError(
							ctx,
							"SHELL_CALIBER",
							sp,
							`shell calibre {tostring(shell.caliberMm)} mm differs from the gun's {g.caliberMm} mm`
						)
					end
					if j == 1 and shell.special == true then
						addError(ctx, "SHELL_ORDER", sp, "the first shell must be the standard (non-special) round")
					end
				end
			end
		elseif type(g.shells) == "table" and #g.shells > 3 then
			addError(ctx, "SHELL_COUNT", p .. ".shells", "a gun carries 1..3 shell types")
		end
		validateReload(ctx, p .. ".reload", g.reload)
		num(ctx, p .. ".dispersionM100", g.dispersionM100, 0.05, 2)
		num(ctx, p .. ".aimTimeS", g.aimTimeS, 0.3, 12)
		if tbl(ctx, p .. ".arcs", g.arcs) then
			num(ctx, p .. ".arcs.depressionDeg", g.arcs.depressionDeg, 0, 30)
			num(ctx, p .. ".arcs.elevationDeg", g.arcs.elevationDeg, 0, 85)
		end
		num(ctx, p .. ".ammoCapacity", g.ammoCapacity, 1, 250, false, true)
		if tbl(ctx, p .. ".bloom", g.bloom, true) then
			local b = g.bloom
			num(ctx, p .. ".bloom.movementPerKmh", b.movementPerKmh, 0, 1, true)
			num(ctx, p .. ".bloom.hullTraversePerDegS", b.hullTraversePerDegS, 0, 1, true)
			num(ctx, p .. ".bloom.turretTraversePerDegS", b.turretTraversePerDegS, 0, 1, true)
			num(ctx, p .. ".bloom.afterShot", b.afterShot, 1, 10, true)
			num(ctx, p .. ".bloom.damagedMul", b.damagedMul, 1, 5, true)
		end
		num(ctx, p .. ".camoAfterShotMul", g.camoAfterShotMul, 0, 1, true)
		num(ctx, p .. ".shellSwapS", g.shellSwapS, 0, 60, true)
		bool(ctx, p .. ".indirect", g.indirect, true)
		if tbl(ctx, p .. ".visual", g.visual) then
			local v = g.visual
			num(ctx, p .. ".visual.barrelLengthM", v.barrelLengthM, 0.3, 10)
			num(ctx, p .. ".visual.barrelDiameterM", v.barrelDiameterM, 0.02, 1, true)
			enum(ctx, p .. ".visual.muzzleBrake", v.muzzleBrake, E.muzzleBrake)
			bool(ctx, p .. ".visual.fumeExtractor", v.fumeExtractor, true)
			bool(ctx, p .. ".visual.thermalSleeve", v.thermalSleeve, true)
			enum(ctx, p .. ".visual.mantlet", v.mantlet, E.mantlet)
			num(ctx, p .. ".visual.mantletWidthM", v.mantletWidthM, 0.1, 4, true)
		end
		if enum(ctx, p .. ".audio", g.audio, E.gunAudio) then
			sound(ctx, p .. ".audio", "gun_" .. g.audio .. "_close")
		end
		if not used[g.id] then
			addWarning(ctx, "ORPHAN", p, "no vehicle uses this gun")
		end
	end
end

local function validateTurrets(ctx: Ctx, reg: ContentRegistry, used: { [string]: boolean })
	for i, t in reg._index.Turret.list do
		local p = `turrets[{i}]({t.id})`
		moduleBase(ctx, p, t, "Turret", FIELDS.Turret)
		enum(ctx, p .. ".mount", t.mount, E.turretMount)
		if tbl(ctx, p .. ".armor", t.armor) then
			local a = t.armor
			for _, key in { "front", "side", "rear", "roof", "mantlet" } do
				num(ctx, `{p}.armor.{key}`, a[key], 0, 500)
			end
			num(ctx, p .. ".armor.cupola", a.cupola, 0, 500, true)
		end
		num(ctx, p .. ".traverseDegS", t.traverseDegS, 1, 120)
		num(ctx, p .. ".viewRangeM", t.viewRangeM, 100, 600)
		num(ctx, p .. ".hpBonus", t.hpBonus, 0, 1000)
		if list(ctx, p .. ".guns", t.guns, 1, 8) then
			for j, gunId in t.guns do
				local gp = `{p}.guns[{j}]`
				if reg:getGun(gunId) == nil then
					if reg._modules[gunId] ~= nil then
						addError(ctx, "WRONG_KIND", gp, `{describe(gunId)} is not a gun`)
					else
						addError(ctx, "DANGLING_REF", gp, `unknown gun {describe(gunId)}`)
					end
				end
			end
		end
		if t.yawLimitsDeg ~= nil then
			if tbl(ctx, p .. ".yawLimitsDeg", t.yawLimitsDeg) then
				num(ctx, p .. ".yawLimitsDeg.left", t.yawLimitsDeg.left, 0, 180)
				num(ctx, p .. ".yawLimitsDeg.right", t.yawLimitsDeg.right, 0, 180)
			end
		elseif t.mount == "Casemate" then
			addError(ctx, "MOUNT", p .. ".yawLimitsDeg", "a casemate mount needs gun yaw limits")
		end
		if tbl(ctx, p .. ".visual", t.visual) then
			local v = t.visual
			enum(ctx, p .. ".visual.style", v.style, E.turretStyle)
			num(ctx, p .. ".visual.lengthM", v.lengthM, 0.3, 8)
			num(ctx, p .. ".visual.widthM", v.widthM, 0.3, 5)
			num(ctx, p .. ".visual.heightM", v.heightM, 0.2, 3)
			num(ctx, p .. ".visual.bustleLengthM", v.bustleLengthM, 0, 3, true)
			num(ctx, p .. ".visual.frontAngleDeg", v.frontAngleDeg, 0, 80, true)
			num(ctx, p .. ".visual.sideAngleDeg", v.sideAngleDeg, 0, 80, true)
			num(ctx, p .. ".visual.rearAngleDeg", v.rearAngleDeg, 0, 80, true)
			bool(ctx, p .. ".visual.cupola", v.cupola, true)
			if t.mount == "Casemate" and v.style ~= "Casemate" then
				addError(ctx, "MOUNT", p .. ".visual.style", "a casemate mount uses the Casemate visual style")
			end
		end
		if not used[t.id] then
			addWarning(ctx, "ORPHAN", p, "no vehicle uses this turret")
		end
	end
end

local function validateEngines(ctx: Ctx, reg: ContentRegistry, used: { [string]: boolean })
	for i, e in reg._index.Engine.list do
		local p = `engines[{i}]({e.id})`
		moduleBase(ctx, p, e, "Engine", FIELDS.Engine)
		num(ctx, p .. ".powerHp", e.powerHp, 10, 3000)
		enum(ctx, p .. ".fuel", e.fuel, E.engineFuel)
		num(ctx, p .. ".fireChance", e.fireChance, 0, 1, true)
		if enum(ctx, p .. ".audio", e.audio, E.engineAudio) then
			sound(ctx, p .. ".audio", "engine_" .. e.audio .. "_idle")
		end
		if tbl(ctx, p .. ".visual", e.visual, true) then
			num(ctx, p .. ".visual.exhausts", e.visual.exhausts, 0, 8, true, true)
			enum(ctx, p .. ".visual.exhaustPlacement", e.visual.exhaustPlacement, E.exhaustPlacement, true)
		end
		if not used[e.id] then
			addWarning(ctx, "ORPHAN", p, "no vehicle uses this engine")
		end
	end
end

local function validateTracks(ctx: Ctx, reg: ContentRegistry, used: { [string]: boolean })
	for i, t in reg._index.Tracks.list do
		local p = `tracks[{i}]({t.id})`
		moduleBase(ctx, p, t, "Tracks", FIELDS.Tracks)
		num(ctx, p .. ".loadLimitKg", t.loadLimitKg, 1000, 250000)
		num(ctx, p .. ".traverseDegS", t.traverseDegS, 1, 120)
		terrainResistance(ctx, p .. ".terrainResistance", t.terrainResistance)
		num(ctx, p .. ".armorMm", t.armorMm, 0, 100)
		num(ctx, p .. ".bloomMul", t.bloomMul, 0.1, 5, true)
		bool(ctx, p .. ".wheeled", t.wheeled, true)
		if tbl(ctx, p .. ".visual", t.visual, true) then
			num(ctx, p .. ".visual.trackWidthM", t.visual.trackWidthM, 0.1, 1.5, true)
			enum(ctx, p .. ".visual.linkStyle", t.visual.linkStyle, E.trackLink, true)
		end
		if not used[t.id] then
			addWarning(ctx, "ORPHAN", p, "no vehicle uses these tracks")
		end
	end
end

--------------------------------------------------------------------------------
-- Validators: vehicles
--------------------------------------------------------------------------------

local function moduleListOf(v: any, kind: string): { any }
	if type(v.modules) ~= "table" or type(v.modules[MODULE_FIELD[kind]]) ~= "table" then
		return {}
	end
	return v.modules[MODULE_FIELD[kind]]
end

local function vehicleHasModule(v: any, id: any): boolean
	for _, slot in CONFIG_SLOTS do
		if listContains(moduleListOf(v, slot.kind), id) then
			return true
		end
	end
	return false
end

local function validateConfiguration(ctx: Ctx, reg: ContentRegistry, p: string, v: any, cfg: any): number?
	if not tbl(ctx, p, cfg) then
		return nil
	end
	fields(ctx, p, cfg, set({ "gun", "turret", "engine", "tracks" }))
	local ok = true
	for _, slot in CONFIG_SLOTS do
		local id = cfg[slot.key]
		local sp = `{p}.{slot.key}`
		if id == nil then
			addError(ctx, "MISSING_FIELD", sp, `configuration needs a {slot.key}`)
			ok = false
		elseif reg:_get(slot.kind, id) == nil then
			if reg._modules[id] ~= nil then
				addError(ctx, "WRONG_KIND", sp, `{describe(id)} is not a {string.lower(slot.kind)}`)
			else
				addError(ctx, "DANGLING_REF", sp, `unknown {string.lower(slot.kind)} {describe(id)}`)
			end
			ok = false
		elseif not listContains(moduleListOf(v, slot.kind), id) then
			addError(ctx, "CONFIG_INVALID", sp, `{describe(id)} is not in modules.{slot.list}`)
			ok = false
		end
	end
	if not ok then
		return nil
	end
	local turret = reg:getTurret(cfg.turret) :: any
	if not listContains(turret.guns, cfg.gun) then
		addError(ctx, "CONFIG_INVALID", p .. ".gun", `turret {cfg.turret} cannot mount gun {cfg.gun}`)
		return nil
	end
	local mass = reg:configurationMassKg(v.id, cfg)
	local tracks = reg:getTracks(cfg.tracks) :: any
	if mass ~= nil and isFinite(tracks.loadLimitKg) and mass > tracks.loadLimitKg then
		addError(
			ctx,
			"OVER_LOAD_LIMIT",
			p,
			`mass {mass} kg exceeds the {cfg.tracks} load limit of {tracks.loadLimitKg} kg`
		)
	end
	return mass
end

local function validateCrew(ctx: Ctx, p: string, crew: any)
	if not list(ctx, p, crew, 2, 6) then
		if type(crew) == "table" and #crew > 0 then
			addError(ctx, "CREW_COMPOSITION", p, "a crew has 2..6 seats")
		end
		return
	end
	local commanders = 0
	local covered: { [string]: boolean } = {}
	for i, seat in crew do
		local sp = `{p}[{i}]`
		if not tbl(ctx, sp, seat) then
			continue
		end
		fields(ctx, sp, seat, set({ "role", "also" }))
		if not enum(ctx, sp .. ".role", seat.role, E.crewRole) then
			continue
		end
		covered[seat.role] = true
		if seat.role == "Commander" then
			commanders += 1
		end
		if seat.also ~= nil and list(ctx, sp .. ".also", seat.also, 0, 3) then
			if seat.role == "Driver" and #seat.also > 0 then
				addError(ctx, "CREW_COMPOSITION", sp .. ".also", "the driver cannot take other duties")
			end
			local seen = { [seat.role] = true }
			for j, duty in seat.also do
				local dp = `{sp}.also[{j}]`
				if enum(ctx, dp, duty, E.crewRole) then
					if duty == "Commander" then
						addError(ctx, "CREW_COMPOSITION", dp, "Commander is always a primary role")
					elseif seen[duty] then
						addError(ctx, "CREW_COMPOSITION", dp, `duty {duty} listed twice for this seat`)
					end
					seen[duty] = true
					covered[duty] = true
				end
			end
		end
	end
	if commanders ~= 1 then
		addError(ctx, "CREW_COMPOSITION", p, `exactly one Commander seat is required, found {commanders}`)
	end
	for _, duty in { "Gunner", "Driver", "Loader" } do
		if not covered[duty] then
			addError(ctx, "CREW_COMPOSITION", p, `no seat covers the {duty} duty`)
		end
	end
end

local function validateVisual(ctx: Ctx, reg: ContentRegistry, p: string, v: any, vis: any)
	if not tbl(ctx, p, vis) then
		return
	end
	fields(ctx, p, vis, set({ "hull", "running", "details", "layout", "palette", "preset", "hooks" }))
	if str(ctx, p .. ".preset", vis.preset, MAX_ID_LENGTH, true) and not string.match(vis.preset, ID_PATTERN) then
		addError(ctx, "BAD_VALUE", p .. ".preset", "preset keys are snake_case")
	end
	if list(ctx, p .. ".hooks", vis.hooks, 0, 16, true) then
		for j, hook in vis.hooks do
			if str(ctx, `{p}.hooks[{j}]`, hook, MAX_ID_LENGTH) and not string.match(hook, ID_PATTERN) then
				addError(ctx, "BAD_VALUE", `{p}.hooks[{j}]`, "hook keys are snake_case")
			end
		end
	end
	local hull = vis.hull
	local hp = p .. ".hull"
	if tbl(ctx, hp, hull) then
		fields(ctx, hp, hull, FIELDS.HullVisual)
		local okL = num(ctx, hp .. ".lengthM", hull.lengthM, 2, 16)
		local okW = num(ctx, hp .. ".widthM", hull.widthM, 1.2, 5)
		local okH = num(ctx, hp .. ".heightM", hull.heightM, 0.6, 4)
		if num(ctx, hp .. ".groundClearanceM", hull.groundClearanceM, 0, 1) and okH then
			if hull.groundClearanceM >= hull.heightM then
				addError(ctx, "VISUAL", hp .. ".groundClearanceM", "clearance must be below the hull roof")
			end
		end
		enum(ctx, hp .. ".style", hull.style, E.hullStyle)
		num(ctx, hp .. ".upperFrontAngleDeg", hull.upperFrontAngleDeg, 0, 85)
		num(ctx, hp .. ".lowerFrontAngleDeg", hull.lowerFrontAngleDeg, 0, 85)
		num(ctx, hp .. ".upperFrontFraction", hull.upperFrontFraction, 0, 1)
		num(ctx, hp .. ".rearAngleDeg", hull.rearAngleDeg, 0, 85, true)
		num(ctx, hp .. ".sideSlopeDeg", hull.sideSlopeDeg, 0, 60, true)
		enum(ctx, hp .. ".engineDeck", hull.engineDeck, E.engineDeck)
		bool(ctx, hp .. ".fenders", hull.fenders)
		enum(ctx, hp .. ".skirts", hull.skirts, E.skirts)
		bool(ctx, hp .. ".sponsons", hull.sponsons, true)
		if tbl(ctx, hp .. ".turretRing", hull.turretRing) then
			local ring = hull.turretRing
			num(ctx, hp .. ".turretRing.positionFraction", ring.positionFraction, 0, 1)
			if num(ctx, hp .. ".turretRing.diameterM", ring.diameterM, 0.3, 4) and okW then
				if ring.diameterM > hull.widthM then
					addError(ctx, "VISUAL", hp .. ".turretRing.diameterM", "turret ring is wider than the hull")
				end
			end
			num(ctx, hp .. ".turretRing.heightOffsetM", ring.heightOffsetM, 0, 2, true)
		end
		if tbl(ctx, hp .. ".superstructure", hull.superstructure, true) then
			local s = hull.superstructure
			if num(ctx, hp .. ".superstructure.lengthM", s.lengthM, 0.3, 16) and okL and s.lengthM > hull.lengthM then
				addError(ctx, "VISUAL", hp .. ".superstructure.lengthM", "superstructure is longer than the hull")
			end
			num(ctx, hp .. ".superstructure.heightM", s.heightM, 0.1, 3)
			num(ctx, hp .. ".superstructure.positionFraction", s.positionFraction, 0, 1)
			num(ctx, hp .. ".superstructure.frontAngleDeg", s.frontAngleDeg, 0, 85)
			num(ctx, hp .. ".superstructure.sideAngleDeg", s.sideAngleDeg, 0, 85, true)
			local armor = if type(v.hull) == "table" and type(v.hull.armor) == "table" then v.hull.armor else {}
			if armor.superstructureFront == nil or armor.superstructureSide == nil then
				addError(
					ctx,
					"ARMOR",
					hp .. ".superstructure",
					"a superstructure needs hull.armor.superstructureFront and superstructureSide"
				)
			end
		end
		if hull.skirts ~= nil and hull.skirts ~= "None" then
			local armor = if type(v.hull) == "table" and type(v.hull.armor) == "table" then v.hull.armor else {}
			if armor.skirts == nil then
				addError(ctx, "ARMOR", hp .. ".skirts", "side skirts need hull.armor.skirts (spaced armor)")
			end
		end
		-- Turret visuals must sit on this hull.
		if okW then
			for _, turretId in moduleListOf(v, "Turret") do
				local turret = reg:getTurret(turretId) :: any
				if turret ~= nil and type(turret.visual) == "table" and isFinite(turret.visual.widthM) then
					if turret.visual.widthM > hull.widthM then
						addWarning(ctx, "VISUAL", hp .. ".widthM", `turret {turretId} is wider than the hull`)
					end
				end
			end
		end
	end
	local run = vis.running
	local rp = p .. ".running"
	if tbl(ctx, rp, run) then
		num(ctx, rp .. ".roadWheels", run.roadWheels, 2, 12, false, true)
		num(ctx, rp .. ".wheelDiameterM", run.wheelDiameterM, 0.2, 2)
		num(ctx, rp .. ".returnRollers", run.returnRollers, 0, 8, false, true)
		enum(ctx, rp .. ".sprocket", run.sprocket, E.sprocket)
		num(ctx, rp .. ".trackWidthM", run.trackWidthM, 0.1, 1.5)
		enum(ctx, rp .. ".suspension", run.suspension, E.suspension)
	end
	if tbl(ctx, p .. ".details", vis.details, true) then
		local d = vis.details
		for _, key in { "exhausts", "antennas", "toolboxes", "fuelDrums", "headlights", "jerrycans" } do
			num(ctx, `{p}.details.{key}`, d[key], 0, 12, true, true)
		end
		for _, key in { "spareTracks", "smokeDischargers", "towCables", "machineGun", "stowage", "logs", "camoNet" } do
			bool(ctx, `{p}.details.{key}`, d[key], true)
		end
	end
	local layout = vis.layout
	local lp = p .. ".layout"
	if tbl(ctx, lp, layout) then
		fields(ctx, lp, layout, FIELDS.Layout)
		enum(ctx, lp .. ".engine", layout.engine, E.enginePlacement)
		enum(ctx, lp .. ".transmission", layout.transmission, E.transmission)
		enum(ctx, lp .. ".fuel", layout.fuel, E.fuelPlacement)
		enum(ctx, lp .. ".optics", layout.optics, E.optics, true)
		enumList(ctx, lp .. ".ammoRacks", layout.ammoRacks, E.ammoRack, 1, 3)
		if type(layout.ammoRacks) == "table" then
			for j, placement in layout.ammoRacks do
				if placement == "Bustle" or placement == "Turret" then
					for _, turretId in moduleListOf(v, "Turret") do
						local turret = reg:getTurret(turretId) :: any
						if turret == nil then
							continue
						end
						if turret.mount == "Casemate" then
							addError(ctx, "LAYOUT", `{lp}.ammoRacks[{j}]`, `casemate {turretId} has no turret rack`)
						elseif
							placement == "Bustle"
							and (
								type(turret.visual) ~= "table"
								or not isFinite(turret.visual.bustleLengthM)
								or turret.visual.bustleLengthM <= 0
							)
						then
							addError(
								ctx,
								"LAYOUT",
								`{lp}.ammoRacks[{j}]`,
								`turret {turretId} has no bustle for a bustle rack`
							)
						end
					end
				end
			end
		end
		if list(ctx, lp .. ".overrides", layout.overrides, 0, 16, true) then
			for j, o in layout.overrides do
				local op = `{lp}.overrides[{j}]`
				if tbl(ctx, op, o) then
					enum(ctx, op .. ".kind", o.kind, E.internalModule)
					enum(ctx, op .. ".group", o.group, E.volumeGroup)
					if typeof(o.centerM) ~= "Vector3" then
						addError(ctx, "BAD_VALUE", op .. ".centerM", "expected a Vector3 (metres)")
					end
					if typeof(o.sizeM) ~= "Vector3" or o.sizeM.X <= 0 or o.sizeM.Y <= 0 or o.sizeM.Z <= 0 then
						addError(ctx, "BAD_VALUE", op .. ".sizeM", "expected a positive Vector3 (metres)")
					end
				end
			end
		end
		if list(ctx, lp .. ".crewSeats", layout.crewSeats, 0, 6, true) then
			local seats = if type(v.crew) == "table" then #v.crew else 0
			for j, seat in layout.crewSeats do
				local sp = `{lp}.crewSeats[{j}]`
				if tbl(ctx, sp, seat) then
					num(ctx, sp .. ".slot", seat.slot, 1, math.max(seats, 1), false, true)
					if typeof(seat.centerM) ~= "Vector3" then
						addError(ctx, "BAD_VALUE", sp .. ".centerM", "expected a Vector3 (metres)")
					end
				end
			end
		end
	end
	if tbl(ctx, p .. ".palette", vis.palette, true) then
		color(ctx, p .. ".palette.base", vis.palette.base, true)
		color(ctx, p .. ".palette.secondary", vis.palette.secondary, true)
		color(ctx, p .. ".palette.accent", vis.palette.accent, true)
	end
end

local function validateMechanics(ctx: Ctx, reg: ContentRegistry, vp: string, v: any)
	local p = vp .. ".mechanics"
	local mechanics = v.mechanics
	local exotic = 0
	local hasWheeled = false
	if list(ctx, p, mechanics, 0, 4, true) then
		local seen = {}
		for i, m in mechanics do
			local mp = `{p}[{i}]`
			if not tbl(ctx, mp, m) or not enum(ctx, mp .. ".kind", m.kind, E.mechanic) then
				continue
			end
			if seen[m.kind] then
				addError(ctx, "MECHANIC", mp, `mechanic {m.kind} listed twice`)
			end
			seen[m.kind] = true
			if E.exotic[m.kind] then
				exotic += 1
				if v.tier ~= 11 and v.acquisition ~= "Event" then
					addError(ctx, "MECHANIC", mp, `{m.kind} is a Tier XI signature (or Event vehicles only)`)
				end
			end
			local k = m.kind
			if k == "SiegeMode" then
				if v.class ~= "td" then
					addError(ctx, "MECHANIC", mp, "SiegeMode is for tank destroyers")
				end
				num(ctx, mp .. ".engageS", m.engageS, 0.1, 10)
				num(ctx, mp .. ".disengageS", m.disengageS, 0.1, 10)
				num(ctx, mp .. ".maxSpeedKmh", m.maxSpeedKmh, 0, 60)
				num(ctx, mp .. ".autoEngageS", m.autoEngageS, 0, 10, true)
				num(ctx, mp .. ".travelReverseRatio", m.travelReverseRatio, 0.1, 1.5, true)
				modifiers(ctx, mp .. ".modifiers", m.modifiers)
			elseif k == "Hydropneumatic" then
				if v.class ~= "medium" then
					addError(ctx, "MECHANIC", mp, "Hydropneumatic is for medium tanks")
				end
				num(ctx, mp .. ".depressionBonusDeg", m.depressionBonusDeg, 0, 15)
				num(ctx, mp .. ".elevationBonusDeg", m.elevationBonusDeg, 0, 15)
				num(ctx, mp .. ".settleS", m.settleS, 0, 5)
			elseif k == "Wheeled" then
				hasWheeled = true
				if v.class ~= "light" then
					addError(ctx, "MECHANIC", mp, "Wheeled is for light tanks")
				end
				num(ctx, mp .. ".wheelPairs", m.wheelPairs, 2, 6, false, true)
				num(ctx, mp .. ".speedModeTopSpeedMul", m.speedModeTopSpeedMul, 1, 2)
				num(ctx, mp .. ".speedModeSteeringMul", m.speedModeSteeringMul, 0.1, 1)
				num(ctx, mp .. ".speedModeReverseMul", m.speedModeReverseMul, 0.1, 1.5)
				num(ctx, mp .. ".toggleS", m.toggleS, 0, 5)
				num(ctx, mp .. ".lostPairSpeedMul", m.lostPairSpeedMul, 0.1, 1)
				num(ctx, mp .. ".movingDispersionMul", m.movingDispersionMul, 1, 3)
				num(ctx, mp .. ".turnRadiusM", m.turnRadiusM, 1, 30)
			elseif k == "Turbo" then
				num(ctx, mp .. ".powerMul", m.powerMul, 1, 3)
				num(ctx, mp .. ".durationS", m.durationS, 0.5, 60)
				num(ctx, mp .. ".cooldownS", m.cooldownS, 1, 600)
			elseif k == "RocketBoost" then
				num(ctx, mp .. ".charges", m.charges, 1, 10, false, true)
				num(ctx, mp .. ".durationS", m.durationS, 0.5, 30)
				num(ctx, mp .. ".speedBonusKmh", m.speedBonusKmh, 1, 80)
				num(ctx, mp .. ".cooldownS", m.cooldownS, 1, 600)
			elseif k == "ChargedShot" then
				num(ctx, mp .. ".chargeTimeS", m.chargeTimeS, 0.1, 10)
				if enum(ctx, mp .. ".effect", m.effect, E.chargedEffect) then
					if m.effect == "Accuracy" then
						num(ctx, mp .. ".dispersionMul", m.dispersionMul, 0.1, 1)
					else
						num(ctx, mp .. ".damageMul", m.damageMul, 1, 2)
					end
				end
			elseif k == "ActiveCooling" then
				num(ctx, mp .. ".durationS", m.durationS, 0.5, 60)
				num(ctx, mp .. ".cooldownS", m.cooldownS, 1, 600)
				modifiers(ctx, mp .. ".modifiers", m.modifiers)
			elseif k == "AdaptiveMagazine" then
				num(ctx, mp .. ".partialReloadFactor", m.partialReloadFactor, 0.05, 1)
			end
		end
	end
	if v.tier == 11 and exotic ~= 1 then
		addError(ctx, "MECHANIC", p, `a Tier XI vehicle needs exactly one signature mechanic, found {exotic}`)
	end
	-- Wheels and the Wheeled mechanic go together.
	for _, tracksId in moduleListOf(v, "Tracks") do
		local tracks = reg:getTracks(tracksId) :: any
		if tracks ~= nil and tracks.wheeled == true and not hasWheeled then
			addError(ctx, "MECHANIC", p, `tracks {tracksId} are wheeled but the vehicle has no Wheeled mechanic`)
		elseif tracks ~= nil and tracks.wheeled ~= true and hasWheeled then
			addError(ctx, "MECHANIC", p, `Wheeled vehicle uses non-wheeled tracks {tracksId}`)
		end
	end
	-- Gun reload kinds by class/role/tier (00-DECISIONS §4) and artillery howitzers.
	for _, gunId in moduleListOf(v, "Gun") do
		local gun = reg:getGun(gunId) :: any
		if gun == nil then
			continue
		end
		local reloadKind: string? = if type(gun.reload) == "table" then gun.reload.kind else nil
		local gunPath = `{vp}.modules.guns({gunId})`
		local allowedReload = true
		local reason = ""
		if reloadKind == "DualGun" then
			allowedReload = v.class == "heavy" and isFinite(v.tier) and v.tier >= 7
			reason = "dual guns are for Tier VII+ heavy tanks"
		elseif reloadKind == "Magazine" then
			allowedReload = v.role ~= "heavy_assault"
			reason = "magazine guns are not allowed on Heavy Assault"
		elseif reloadKind == "Autoreloader" then
			allowedReload = v.class == "medium" or v.class == "td"
			reason = "autoreloaders are for medium tanks and tank destroyers"
		end
		if not allowedReload then
			addError(ctx, "MECHANIC", gunPath, reason)
		end
		local indirect = gun.indirect == true
		if indirect ~= (v.class == "artillery") then
			addError(
				ctx,
				"MECHANIC",
				gunPath,
				if indirect then "indirect guns are for artillery" else "artillery needs indirect guns"
			)
		end
	end
end

local function validateApex(ctx: Ctx, p: string, v: any)
	if v.apex == nil then
		if v.tier == 11 then
			addError(ctx, "APEX", p, "Tier XI vehicles need an apex upgrade track")
		end
		return
	end
	if v.tier ~= 11 then
		addError(ctx, "APEX", p, "only Tier XI vehicles have an apex track")
	end
	if not tbl(ctx, p, v.apex) or not list(ctx, p .. ".nodes", v.apex.nodes, 1, 25) then
		return
	end
	local counts = { Small = 0, Large = 0, Final = 0 }
	local seen = {}
	for i, node in v.apex.nodes do
		local np = `{p}.nodes[{i}]`
		if not tbl(ctx, np, node) then
			continue
		end
		if str(ctx, np .. ".id", node.id, MAX_ID_LENGTH) then
			if seen[node.id] then
				addError(ctx, "APEX", np .. ".id", `duplicate node id {node.id}`)
			end
			seen[node.id] = true
		end
		str(ctx, np .. ".name", node.name, 40)
		if enum(ctx, np .. ".kind", node.kind, E.apexNode) then
			counts[node.kind] += 1
		end
		num(ctx, np .. ".xp", node.xp, 1, 1e6, false, true)
		modifiers(ctx, np .. ".effects", node.effects)
	end
	if counts.Small ~= 6 or counts.Large ~= 3 or counts.Final ~= 1 then
		addWarning(
			ctx,
			"APEX",
			p .. ".nodes",
			`expected 6 small, 3 large, 1 final node (00-DECISIONS §11), got {counts.Small}/{counts.Large}/{counts.Final}`
		)
	end
end

local function hasCycle(nodes: { string }, edgesOf: (string) -> { string }): string?
	local state: { [string]: number } = {}
	local found: string? = nil
	local function visit(n: string)
		if found ~= nil then
			return
		end
		state[n] = 1
		for _, m in edgesOf(n) do
			if state[m] == 1 then
				found = m
				return
			elseif state[m] == nil then
				visit(m)
			end
		end
		state[n] = 2
	end
	for _, n in nodes do
		if state[n] == nil then
			visit(n)
		end
	end
	return found
end

local function validateModuleTree(ctx: Ctx, reg: ContentRegistry, vp: string, v: any)
	local p = vp .. ".moduleTree"
	local stockSet: { [any]: boolean } = {}
	if type(v.stock) == "table" then
		for _, slot in CONFIG_SLOTS do
			if v.stock[slot.key] ~= nil then
				stockSet[v.stock[slot.key]] = true
			end
		end
	end
	local tree = v.moduleTree
	local inTree: { [string]: { string } } = {}
	local order: { string } = {}
	if list(ctx, p, tree, 0, 16) then
		for i, node in tree do
			local np = `{p}[{i}]`
			if not tbl(ctx, np, node) then
				continue
			end
			fields(ctx, np, node, set({ "module", "requires" }))
			local id = node.module
			if type(id) ~= "string" or not vehicleHasModule(v, id) then
				addError(ctx, "MODULE_TREE", np .. ".module", `{describe(id)} is not one of this vehicle's modules`)
				continue
			end
			if stockSet[id] then
				addError(
					ctx,
					"MODULE_TREE",
					np .. ".module",
					`{id} is a stock module (stock modules are not researched)`
				)
				continue
			end
			if inTree[id] ~= nil then
				addError(ctx, "MODULE_TREE", np .. ".module", `{id} appears twice`)
				continue
			end
			local requires: { string } = {}
			if list(ctx, np .. ".requires", node.requires, 0, 4, true) then
				for j, req in node.requires do
					if req == id then
						addError(ctx, "MODULE_TREE", `{np}.requires[{j}]`, "a module cannot require itself")
					elseif type(req) ~= "string" or not vehicleHasModule(v, req) then
						addError(
							ctx,
							"MODULE_TREE",
							`{np}.requires[{j}]`,
							`{describe(req)} is not one of this vehicle's modules`
						)
					else
						table.insert(requires, req)
					end
				end
			end
			inTree[id] = requires
			table.insert(order, id)
		end
	end
	-- Every non-stock module must be researchable here.
	for _, slot in CONFIG_SLOTS do
		for _, id in moduleListOf(v, slot.kind) do
			if not stockSet[id] and inTree[id] == nil then
				addError(
					ctx,
					"MODULE_UNREACHABLE",
					`{vp}.modules.{slot.list}({tostring(id)})`,
					"not stock and not in moduleTree"
				)
			end
		end
	end
	local cycleAt = hasCycle(order, function(n)
		return inTree[n] or {}
	end)
	if cycleAt ~= nil then
		addError(ctx, "MODULE_CYCLE", p, `module requirements form a cycle through {cycleAt}`)
	end
	-- Every gun fits at least one of the vehicle's turrets; every turret mounts at least one of its guns.
	local guns = moduleListOf(v, "Gun")
	local turrets = moduleListOf(v, "Turret")
	for _, gunId in guns do
		local fits = false
		for _, turretId in turrets do
			local turret = reg:getTurret(turretId) :: any
			if turret ~= nil and listContains(turret.guns, gunId) then
				fits = true
				break
			end
		end
		if not fits and reg:getGun(gunId) ~= nil then
			addError(ctx, "TURRET_GUNS", `{vp}.modules.guns({gunId})`, "no turret of this vehicle can mount this gun")
		end
	end
	for _, turretId in turrets do
		local turret = reg:getTurret(turretId) :: any
		if turret == nil then
			continue
		end
		local any = false
		for _, gunId in guns do
			if listContains(turret.guns, gunId) then
				any = true
				break
			end
		end
		if not any then
			addError(
				ctx,
				"TURRET_GUNS",
				`{vp}.modules.turrets({turretId})`,
				"this turret mounts none of the vehicle's guns"
			)
		end
	end
end

local function validateVehicle(ctx: Ctx, reg: ContentRegistry, i: number, v: any, rows: { [string]: string })
	local p = `vehicles[{i}]({v.id})`
	fields(ctx, p, v, FIELDS.Vehicle)
	str(ctx, p .. ".name", v.name, 32)
	str(ctx, p .. ".shortName", v.shortName, 12)
	local faction = ref(ctx, p .. ".faction", v.faction, "Faction")
	local tierOk = num(ctx, p .. ".tier", v.tier, 1, 11, false, true)
	local class = ref(ctx, p .. ".class", v.class, "Class")
	local role = ref(ctx, p .. ".role", v.role, "Role")
	if role ~= nil and class ~= nil and role.class ~= v.class then
		addError(
			ctx,
			"ROLE_CLASS",
			p .. ".role",
			`role {v.role} belongs to class {tostring(role.class)}, not {v.class}`
		)
	end
	if class ~= nil and tierOk and type(class.tiers) == "table" then
		if v.tier < class.tiers.min or v.tier > class.tiers.max then
			addError(
				ctx,
				"TIER_RANGE",
				p .. ".tier",
				`class {v.class} exists at tiers {class.tiers.min}..{class.tiers.max}`
			)
		end
	end
	local acquisitionOk = enum(ctx, p .. ".acquisition", v.acquisition, E.acquisition)
	str(ctx, p .. ".description", v.description, 300)
	str(ctx, p .. ".lore", v.lore, 600)
	for _, key in { "strengths", "weaknesses" } do
		if list(ctx, `{p}.{key}`, v[key], 1, 4) then
			for j, line in v[key] do
				str(ctx, `{p}.{key}[{j}]`, line, 60)
			end
		end
	end
	-- hull and mobility
	if tbl(ctx, p .. ".hull", v.hull) then
		fields(ctx, p .. ".hull", v.hull, FIELDS.Hull)
		num(ctx, p .. ".hull.hp", v.hull.hp, 50, 5000)
		num(ctx, p .. ".hull.massKg", v.hull.massKg, 500, 200000)
		if tbl(ctx, p .. ".hull.armor", v.hull.armor) then
			local a = v.hull.armor
			fields(ctx, p .. ".hull.armor", a, FIELDS.HullArmor)
			for _, key in { "upperFront", "lowerFront", "side", "rear", "roof", "floor" } do
				num(ctx, `{p}.hull.armor.{key}`, a[key], 0, 500)
			end
			for _, key in { "engineDeck", "superstructureFront", "superstructureSide", "skirts" } do
				num(ctx, `{p}.hull.armor.{key}`, a[key], 0, 500, true)
			end
		end
	end
	if tbl(ctx, p .. ".mobility", v.mobility) then
		fields(ctx, p .. ".mobility", v.mobility, FIELDS.Mobility)
		num(ctx, p .. ".mobility.forwardKmh", v.mobility.forwardKmh, 5, 130)
		num(ctx, p .. ".mobility.reverseKmh", v.mobility.reverseKmh, 2, 80, true)
		bool(ctx, p .. ".mobility.pivot", v.mobility.pivot, true)
	end
	camoSpec(ctx, p .. ".camouflage", v.camouflage, true)
	validateCrew(ctx, p .. ".crew", v.crew)
	-- modules
	if tbl(ctx, p .. ".modules", v.modules) then
		fields(ctx, p .. ".modules", v.modules, set({ "guns", "turrets", "engines", "tracks" }))
		for _, slot in CONFIG_SLOTS do
			local lp = `{p}.modules.{slot.list}`
			local maxLen = if tierOk and v.tier == 11 then 1 else 6
			if list(ctx, lp, v.modules[slot.list], 1, maxLen) then
				local seen = {}
				for j, id in v.modules[slot.list] do
					local ip = `{lp}[{j}]`
					if seen[id] then
						addError(ctx, "BAD_VALUE", ip, `duplicate {describe(id)}`)
					end
					seen[id] = true
					local module = reg:_get(slot.kind, id) :: any
					if module == nil then
						if reg._modules[id] ~= nil then
							addError(ctx, "WRONG_KIND", ip, `{describe(id)} is not a {string.lower(slot.kind)}`)
						else
							addError(ctx, "DANGLING_REF", ip, `unknown {string.lower(slot.kind)} {describe(id)}`)
						end
					elseif tierOk and isFinite(module.tier) and math.abs(module.tier - v.tier) > 1 then
						addWarning(ctx, "TIER_RANGE", ip, `module tier {module.tier} is far from vehicle tier {v.tier}`)
					end
				end
			elseif tierOk and v.tier == 11 and type(v.modules[slot.list]) == "table" and #v.modules[slot.list] > 1 then
				addError(ctx, "APEX", lp, "Tier XI vehicles have a single configuration")
			end
		end
	end
	local stockMass = validateConfiguration(ctx, reg, p .. ".stock", v, v.stock)
	validateConfiguration(ctx, reg, p .. ".top", v, v.top)
	validateModuleTree(ctx, reg, p, v)
	-- Physical research order (03-R4): stock tracks should not carry the top turret + gun.
	if stockMass ~= nil and type(v.top) == "table" and type(v.stock) == "table" then
		local stockTracks = reg:getTracks(v.stock.tracks) :: any
		if v.top.tracks ~= v.stock.tracks and (v.top.gun ~= v.stock.gun or v.top.turret ~= v.stock.turret) then
			local probe = {
				gun = v.top.gun,
				turret = v.top.turret,
				engine = v.stock.engine,
				tracks = v.stock.tracks,
			}
			local mass = reg:configurationMassKg(v.id, probe :: any)
			if mass ~= nil and stockTracks ~= nil and mass <= stockTracks.loadLimitKg then
				addWarning(
					ctx,
					"LOAD_ORDER",
					p .. ".stock.tracks",
					"stock tracks can carry the top turret and gun, so the tracks upgrade is optional"
				)
			end
		end
		if stockTracks ~= nil and isFinite(stockTracks.loadLimitKg) and v.top.tracks ~= v.stock.tracks then
			local spare = (stockTracks.loadLimitKg - stockMass) / stockTracks.loadLimitKg
			if spare > 0.05 then
				addWarning(
					ctx,
					"LOAD_ORDER",
					p .. ".stock",
					`stock tracks have {math.floor(spare * 100)} % spare load (aim for 1-3 %)`
				)
			end
		end
	end
	-- acquisition, research and price
	price(ctx, p .. ".price", v.price)
	num(ctx, p .. ".researchXp", v.researchXp, 0, 1e7, true, true)
	if list(ctx, p .. ".unlocks", v.unlocks, 0, 6) then
		local seen = {}
		for j, unlock in v.unlocks do
			local up = `{p}.unlocks[{j}]`
			if not tbl(ctx, up, unlock) then
				continue
			end
			fields(ctx, up, unlock, set({ "vehicle", "requires" }))
			local target = ref(ctx, up .. ".vehicle", unlock.vehicle, "Vehicle")
			if seen[unlock.vehicle] then
				addError(ctx, "UNLOCK_EDGE", up, `duplicate unlock of {describe(unlock.vehicle)}`)
			end
			seen[unlock.vehicle] = true
			if unlock.requires ~= nil and not vehicleHasModule(v, unlock.requires) then
				addError(
					ctx,
					"UNLOCK_EDGE",
					up .. ".requires",
					`{describe(unlock.requires)} is not one of this vehicle's modules`
				)
			end
			if v.acquisition ~= "TechTree" then
				addError(ctx, "UNLOCK_EDGE", up, "only tech-tree vehicles unlock other vehicles")
			end
			if target ~= nil then
				if target.faction ~= v.faction then
					addError(ctx, "UNLOCK_EDGE", up, `unlocks a {tostring(target.faction)} vehicle across factions`)
				end
				if tierOk and isFinite(target.tier) and (target.tier < v.tier or target.tier > v.tier + 1) then
					addError(ctx, "UNLOCK_EDGE", up, `tier {target.tier} is not the same or next tier`)
				end
				if target.acquisition ~= "TechTree" then
					addError(ctx, "UNLOCK_EDGE", up, `{target.id} is not a tech-tree vehicle`)
				end
			end
		end
	end
	if acquisitionOk and tierOk and type(v.price) == "table" then
		local a = v.acquisition
		local treeEmpty = type(v.moduleTree) ~= "table" or #v.moduleTree == 0
		if a == "TechTree" then
			if v.tier == 1 then
				if v.researchXp ~= nil and v.researchXp ~= 0 then
					addError(ctx, "ACQUISITION", p .. ".researchXp", "Tier I vehicles are starters (no research XP)")
				end
				if v.price.credits ~= 0 then
					addError(ctx, "ACQUISITION", p .. ".price.credits", "Tier I vehicles are free (credits = 0)")
				end
			else
				if not isFinite(v.researchXp) or v.researchXp <= 0 then
					addError(ctx, "ACQUISITION", p .. ".researchXp", "tech-tree vehicles above Tier I need research XP")
				end
				if not isFinite(v.price.credits) or v.price.credits <= 0 then
					addError(ctx, "ACQUISITION", p .. ".price.credits", "tech-tree vehicles above Tier I cost credits")
				end
			end
			if v.price.bullion ~= nil then
				addError(ctx, "ACQUISITION", p .. ".price.bullion", "tech-tree vehicles are never sold for Bullion")
			end
		else
			if v.researchXp ~= nil then
				addError(ctx, "ACQUISITION", p .. ".researchXp", `{a} vehicles are not researched`)
			end
			if not treeEmpty then
				addError(ctx, "ACQUISITION", p .. ".moduleTree", `{a} vehicles arrive fully upgraded (no module tree)`)
			end
			if a == "Premium" then
				if not isFinite(v.price.bullion) or v.price.bullion <= 0 then
					addError(ctx, "ACQUISITION", p .. ".price.bullion", "premium vehicles need a Bullion price")
				end
				if v.tier < 2 or v.tier > 9 then
					addError(ctx, "ACQUISITION", p .. ".tier", "premium vehicles exist at Tiers II–IX only")
				end
			elseif v.price.bullion ~= nil then
				addError(ctx, "ACQUISITION", p .. ".price.bullion", `{a} vehicles are not sold`)
			end
		end
		if v.tier == 10 and a == "TechTree" and not treeEmpty then
			addWarning(ctx, "ACQUISITION", p .. ".moduleTree", "Tier X vehicles normally arrive fully upgraded")
		end
		if v.tier == 11 and not treeEmpty then
			addError(ctx, "APEX", p .. ".moduleTree", "Tier XI vehicles use the apex track instead of modules")
		end
	end
	-- arcs, slots, mechanics, apex, economy
	if list(ctx, p .. ".arcSectors", v.arcSectors, 0, 8, true) then
		for j, s in v.arcSectors do
			local sp = `{p}.arcSectors[{j}]`
			if tbl(ctx, sp, s) then
				num(ctx, sp .. ".fromDeg", s.fromDeg, -180, 180)
				num(ctx, sp .. ".toDeg", s.toDeg, -180, 180)
				num(ctx, sp .. ".depressionDeg", s.depressionDeg, 0, 30, true)
				num(ctx, sp .. ".elevationDeg", s.elevationDeg, 0, 85, true)
			end
		end
	end
	if tbl(ctx, p .. ".slots", v.slots, true) then
		fields(ctx, p .. ".slots", v.slots, FIELDS.Slots)
		num(ctx, p .. ".slots.equipment", v.slots.equipment, 0, 3, true, true)
		num(ctx, p .. ".slots.consumables", v.slots.consumables, 0, 3, true, true)
		enum(ctx, p .. ".slots.categorySlot", v.slots.categorySlot, E.equipmentCategory, true)
	end
	validateMechanics(ctx, reg, p, v)
	validateApex(ctx, p .. ".apex", v)
	if tbl(ctx, p .. ".economy", v.economy, true) then
		fields(ctx, p .. ".economy", v.economy, FIELDS.Economy)
		for _, key in { "creditMul", "xpMul", "crewXpMul", "repairMul" } do
			num(ctx, `{p}.economy.{key}`, v.economy[key], 0.1, 5, true)
		end
	end
	if tbl(ctx, p .. ".audio", v.audio, true) and v.audio.engine ~= nil then
		if enum(ctx, p .. ".audio.engine", v.audio.engine, E.engineAudio) then
			sound(ctx, p .. ".audio.engine", "engine_" .. v.audio.engine .. "_idle")
		end
	end
	validateVisual(ctx, reg, p .. ".visual", v, v.visual)
	icon(ctx, p .. ".icon", v.icon, true)
	str(ctx, p .. ".balanceException", v.balanceException, 200, true)
	bool(ctx, p .. ".hidden", v.hidden, true)
	if list(ctx, p .. ".tags", v.tags, 0, 16, true) then
		for j, tag in v.tags do
			str(ctx, `{p}.tags[{j}]`, tag, 32)
		end
	end
	-- tech-tree position
	if tbl(ctx, p .. ".tree", v.tree) then
		fields(ctx, p .. ".tree", v.tree, set({ "row", "branch" }))
		local branch = ref(ctx, p .. ".tree.branch", v.tree.branch, "Branch", true)
		if branch ~= nil then
			if branch.faction ~= v.faction then
				addError(ctx, "BRANCH", p .. ".tree.branch", `branch {branch.id} belongs to {tostring(branch.faction)}`)
			end
			if v.acquisition == "TechTree" then
				if not listContains(branch.classes, v.class) then
					addError(ctx, "BRANCH", p .. ".tree.branch", `branch {branch.id} has no {tostring(v.class)} vehicles`)
				end
				if
					tierOk
					and type(branch.tiers) == "table"
					and isFinite(branch.tiers.min)
					and isFinite(branch.tiers.max)
					and (v.tier < branch.tiers.min or v.tier > branch.tiers.max)
				then
					addError(ctx, "BRANCH", p .. ".tree.branch", `tier {v.tier} is outside branch {branch.id}`)
				end
			end
		end
		if
			num(ctx, p .. ".tree.row", v.tree.row, 0, 20, false, true)
			and v.acquisition == "TechTree"
			and v.hidden ~= true
		then
			if faction ~= nil and tierOk then
				local key = `{v.faction}:{v.tier}:{v.tree.row}`
				if rows[key] ~= nil then
					addError(
						ctx,
						"TREE_POSITION",
						p .. ".tree.row",
						`row {v.tree.row} at tier {v.tier} is already used by {rows[key]}`
					)
				else
					rows[key] = v.id
				end
			end
		end
	end
end

local function validateTechTree(ctx: Ctx, reg: ContentRegistry)
	local vehicles = reg._index.Vehicle
	-- Cycles (possible only within a tier, since edges never go down a tier).
	local ids: { string } = {}
	for _, id in vehicles.sortedIds do
		table.insert(ids, id)
	end
	local cycleAt = hasCycle(ids, function(n)
		local out = {}
		for _, edge in reg:childrenOf(n) do
			table.insert(out, edge.to)
		end
		return out
	end)
	if cycleAt ~= nil then
		addError(ctx, "TECH_TREE_CYCLE", "vehicles", `the unlock graph has a cycle through {cycleAt}`)
	end
	-- Reachability from Tier I roots, per faction.
	for _, factionId in FACTION_IDS do
		local roots = {}
		local treeVehicles = {}
		for _, id in vehicles.sortedIds do
			local v = vehicles.byId[id]
			if v.faction == factionId and v.acquisition == "TechTree" then
				table.insert(treeVehicles, v)
				if v.tier == 1 then
					table.insert(roots, v.id)
				end
			end
		end
		if #treeVehicles == 0 then
			continue
		end
		if #roots == 0 then
			addError(ctx, "NO_ROOT", `factions({factionId})`, "the faction has tech-tree vehicles but no Tier I root")
			continue
		end
		local reached: { [string]: boolean } = {}
		local queue = table.clone(roots)
		while #queue > 0 do
			local id = table.remove(queue, 1) :: string
			if reached[id] then
				continue
			end
			reached[id] = true
			for _, edge in reg:childrenOf(id) do
				local target = vehicles.byId[edge.to]
				if target ~= nil and target.faction == factionId and not reached[edge.to] then
					table.insert(queue, edge.to)
				end
			end
		end
		for _, v in treeVehicles do
			if not reached[v.id] then
				addError(
					ctx,
					"UNREACHABLE_VEHICLE",
					`vehicles({v.id})`,
					"not reachable from a Tier I vehicle of its faction"
				)
			end
		end
		for _, id in roots do
			if #reg:parentsOf(id) > 0 then
				addError(ctx, "UNLOCK_EDGE", `vehicles({id})`, "Tier I starters cannot be unlocked by another vehicle")
			end
		end
	end
	-- Premium share at IX (00-DECISIONS §7.4: at most two).
	local premiumIX = 0
	for _, v in vehicles.list do
		if v.acquisition == "Premium" and v.tier == 9 then
			premiumIX += 1
		end
	end
	if premiumIX > 2 then
		addWarning(ctx, "ACQUISITION", "vehicles", `{premiumIX} Tier IX premiums (the plan allows at most 2)`)
	end
end

--------------------------------------------------------------------------------
-- Validators: loadout items, cosmetics, missions, achievements
--------------------------------------------------------------------------------

local function validateEquipment(ctx: Ctx, reg: ContentRegistry)
	for i, e in reg._index.Equipment.list do
		local p = `equipment[{i}]({e.id})`
		fields(ctx, p, e, FIELDS.Equipment)
		str(ctx, p .. ".name", e.name, 40)
		str(ctx, p .. ".description", e.description, 300)
		icon(ctx, p .. ".icon", e.icon)
		enumList(ctx, p .. ".categories", e.categories, E.equipmentCategory, 1, 4)
		enum(ctx, p .. ".grade", e.grade, E.equipmentGrade)
		range(ctx, p .. ".tiers", e.tiers, 1, 11)
		str(ctx, p .. ".exclusiveGroup", e.exclusiveGroup, MAX_ID_LENGTH)
		modifiers(ctx, p .. ".effects", e.effects)
		modifiers(ctx, p .. ".categorySlotEffects", e.categorySlotEffects, true)
		if tbl(ctx, p .. ".effectsByClass", e.effectsByClass, true) then
			for _, key in TableUtil.sortedKeys(e.effectsByClass) do
				local kp = `{p}.effectsByClass.{tostring(key)}`
				if type(key) ~= "string" or not E.class[key] then
					addError(ctx, "BAD_VALUE", kp, "unknown class")
				else
					modifiers(ctx, kp, e.effectsByClass[key])
				end
			end
		end
		if tbl(ctx, p .. ".compatibility", e.compatibility, true) then
			local c = e.compatibility
			local cp = p .. ".compatibility"
			fields(
				ctx,
				cp,
				c,
				set({
					"classes",
					"roles",
					"requiresTurret",
					"minMassKg",
					"maxMassKg",
					"excludeMechanics",
					"excludeReload",
				})
			)
			enumList(ctx, cp .. ".classes", c.classes, E.class, 1, 5, true)
			enumList(ctx, cp .. ".roles", c.roles, E.role, 1, 17, true)
			bool(ctx, cp .. ".requiresTurret", c.requiresTurret, true)
			num(ctx, cp .. ".minMassKg", c.minMassKg, 0, 250000, true)
			num(ctx, cp .. ".maxMassKg", c.maxMassKg, 0, 250000, true)
			enumList(ctx, cp .. ".excludeMechanics", c.excludeMechanics, E.mechanic, 1, 8, true)
			enumList(ctx, cp .. ".excludeReload", c.excludeReload, E.reloadKind, 1, 4, true)
		end
		price(ctx, p .. ".price", e.price)
		if type(e.price) == "table" and e.price.bullion ~= nil and e.price.credits == nil then
			addError(ctx, "PRICE", p .. ".price", "equipment is never Bullion-only (00-DECISIONS §13)")
		end
	end
end

local function validateConsumables(ctx: Ctx, reg: ContentRegistry)
	for i, c in reg._index.Consumable.list do
		local p = `consumables[{i}]({c.id})`
		fields(ctx, p, c, FIELDS.Consumable)
		str(ctx, p .. ".name", c.name, 40)
		str(ctx, p .. ".description", c.description, 300)
		icon(ctx, p .. ".icon", c.icon)
		enum(ctx, p .. ".kind", c.kind, E.consumableKind)
		if enum(ctx, p .. ".activation", c.activation, E.activation) then
			if c.activation ~= "Passive" then
				num(ctx, p .. ".cooldownS", c.cooldownS, 1, 600)
			else
				num(ctx, p .. ".cooldownS", c.cooldownS, 0, 600, true)
			end
			if c.activation == "Automatic" then
				num(ctx, p .. ".triggerDelayS", c.triggerDelayS, 0, 10)
			elseif c.triggerDelayS ~= nil then
				addError(ctx, "BAD_VALUE", p .. ".triggerDelayS", "only Automatic consumables have a trigger delay")
			end
		end
		num(ctx, p .. ".durationS", c.durationS, 0, 900, true)
		num(ctx, p .. ".stunImmunityS", c.stunImmunityS, 0, 60, true)
		if tbl(ctx, p .. ".repairs", c.repairs, true) then
			fields(ctx, p .. ".repairs", c.repairs, set({ "modules", "crew", "fire", "stun" }))
		end
		modifiers(ctx, p .. ".effects", c.effects, true)
		modifiers(ctx, p .. ".passiveEffects", c.passiveEffects, true)
		str(ctx, p .. ".exclusiveGroup", c.exclusiveGroup, MAX_ID_LENGTH)
		range(ctx, p .. ".tiers", c.tiers, 1, 11, true)
		enumList(ctx, p .. ".classes", c.classes, E.class, 1, 5, true)
		bool(ctx, p .. ".eventOnly", c.eventOnly, true)
		price(ctx, p .. ".price", c.price)
		if type(c.price) == "table" and c.price.bullion ~= nil and c.price.credits == nil then
			addError(ctx, "PRICE", p .. ".price", "consumables always have a credit price")
		end
		if
			type(c.price) == "table"
			and isFinite(c.price.bullion)
			and isFinite(c.price.credits)
			and c.price.bullion * 200 < c.price.credits
		then
			addError(
				ctx,
				"PRICE",
				p .. ".price",
				"the Bullion price undercuts the credit price (1 Bullion = 200 credits)"
			)
		end
	end
end

local function validateSmallKinds(ctx: Ctx, reg: ContentRegistry)
	for i, s in reg._index.CrewSkill.list do
		local p = `crewSkills[{i}]({s.id})`
		fields(ctx, p, s, FIELDS.CrewSkill)
		str(ctx, p .. ".name", s.name, 40)
		str(ctx, p .. ".description", s.description, 300)
		icon(ctx, p .. ".icon", s.icon)
		enumList(ctx, p .. ".roles", s.roles, E.crewRole, 1, 4)
		enum(ctx, p .. ".kind", s.kind, set({ "Individual", "Group" }))
		modifiers(ctx, p .. ".effects", s.effects)
	end
	for i, b in reg._index.CrewBook.list do
		local p = `crewBooks[{i}]({b.id})`
		fields(ctx, p, b, FIELDS.CrewBook)
		str(ctx, p .. ".name", b.name, 40)
		str(ctx, p .. ".description", b.description, 300)
		icon(ctx, p .. ".icon", b.icon)
		num(ctx, p .. ".xpPerMember", b.xpPerMember, 1, 1e7, false, true)
		price(ctx, p .. ".price", b.price, true)
	end
	for i, b in reg._index.Booster.list do
		local p = `boosters[{i}]({b.id})`
		fields(ctx, p, b, FIELDS.Booster)
		str(ctx, p .. ".name", b.name, 40)
		str(ctx, p .. ".description", b.description, 300)
		icon(ctx, p .. ".icon", b.icon)
		enum(ctx, p .. ".target", b.target, E.boosterTarget)
		num(ctx, p .. ".multiplier", b.multiplier, 1.01, 10)
		local hasDuration = num(ctx, p .. ".durationS", b.durationS, 1, 30 * 86400, true)
		local hasBattles = num(ctx, p .. ".battles", b.battles, 1, 1000, true, true)
		if not hasDuration and not hasBattles then
			addError(ctx, "BAD_VALUE", p, "a booster needs durationS or battles")
		end
		price(ctx, p .. ".price", b.price, true)
	end
	for i, c in reg._index.Customization.list do
		local p = `customization[{i}]({c.id})`
		fields(ctx, p, c, FIELDS.Customization)
		str(ctx, p .. ".name", c.name, 40)
		str(ctx, p .. ".description", c.description, 300, true)
		icon(ctx, p .. ".icon", c.icon)
		local kindOk = enum(ctx, p .. ".kind", c.kind, E.customizationKind)
		enum(ctx, p .. ".rarity", c.rarity, E.rarity)
		if list(ctx, p .. ".colors", c.colors, 1, 6, true) then
			for j, col in c.colors do
				color(ctx, `{p}.colors[{j}]`, col)
			end
		elseif kindOk and (c.kind == "Paint" or c.kind == "Camouflage") and c.colors == nil then
			addError(ctx, "MISSING_FIELD", p .. ".colors", `{c.kind} needs colours`)
		end
		str(ctx, p .. ".pattern", c.pattern, 48, true)
		bool(ctx, p .. ".camoBonus", c.camoBonus, true)
		if tbl(ctx, p .. ".scope", c.scope, true) then
			enumList(ctx, p .. ".scope.factions", c.scope.factions, E.faction, 1, 6, true)
			enumList(ctx, p .. ".scope.classes", c.scope.classes, E.class, 1, 5, true)
			refList(ctx, p .. ".scope.vehicles", c.scope.vehicles, "Vehicle", 1, 64, true)
		end
		enum(ctx, p .. ".source", c.source, E.customizationSource)
		price(ctx, p .. ".price", c.price, true)
	end
end

local function validateConditions(ctx: Ctx, p: string, conditions: any)
	if not list(ctx, p, conditions, 1, 8) then
		return
	end
	for i, c in conditions do
		local cp = `{p}[{i}]`
		if not tbl(ctx, cp, c) then
			continue
		end
		fields(ctx, cp, c, set({ "stat", "atLeast", "atMost", "aggregate", "against" }))
		enum(ctx, cp .. ".stat", c.stat, E.battleStat)
		enum(ctx, cp .. ".aggregate", c.aggregate, E.aggregate)
		local hasMin = num(ctx, cp .. ".atLeast", c.atLeast, 0, 1e9, true)
		local hasMax = num(ctx, cp .. ".atMost", c.atMost, 0, 1e9, true)
		if c.atLeast == nil and c.atMost == nil then
			addError(ctx, "MISSION", cp, "a condition needs atLeast or atMost")
		elseif hasMin and hasMax and c.atLeast > c.atMost then
			addError(ctx, "MISSION", cp, "atLeast exceeds atMost")
		end
		if tbl(ctx, cp .. ".against", c.against, true) then
			enumList(ctx, cp .. ".against.classes", c.against.classes, E.class, 1, 5, true)
		end
	end
end

local function validateMissions(ctx: Ctx, reg: ContentRegistry)
	for i, m in reg._index.Mission.list do
		local p = `missions[{i}]({m.id})`
		fields(ctx, p, m, FIELDS.Mission)
		str(ctx, p .. ".name", m.name, 48)
		str(ctx, p .. ".description", m.description, 300)
		icon(ctx, p .. ".icon", m.icon, true)
		local cadenceOk = enum(ctx, p .. ".cadence", m.cadence, E.cadence)
		enum(ctx, p .. ".difficulty", m.difficulty, E.difficulty, true)
		enum(ctx, p .. ".match", m.match, E.match)
		validateConditions(ctx, p .. ".conditions", m.conditions)
		bool(ctx, p .. ".requireWin", m.requireWin, true)
		bool(ctx, p .. ".requireSurvive", m.requireSurvive, true)
		bool(ctx, p .. ".scaleRewardsByTier", m.scaleRewardsByTier, true)
		num(ctx, p .. ".weight", m.weight, 0, 1000, true)
		rewards(ctx, p .. ".rewards", m.rewards, 1)
		if tbl(ctx, p .. ".scope", m.scope, true) then
			local s = m.scope
			local sp = p .. ".scope"
			fields(
				ctx,
				sp,
				s,
				set({
					"classes",
					"roles",
					"minTier",
					"maxTier",
					"factions",
					"vehicles",
					"modes",
					"battleTypes",
					"maps",
					"excludeBotHeavy",
				})
			)
			enumList(ctx, sp .. ".classes", s.classes, E.class, 1, 5, true)
			enumList(ctx, sp .. ".roles", s.roles, E.role, 1, 17, true)
			local okMin = num(ctx, sp .. ".minTier", s.minTier, 1, 11, true, true)
			local okMax = num(ctx, sp .. ".maxTier", s.maxTier, 1, 11, true, true)
			if okMin and okMax and s.minTier > s.maxTier then
				addError(ctx, "MISSION", sp, "minTier exceeds maxTier")
			end
			enumList(ctx, sp .. ".factions", s.factions, E.faction, 1, 6, true)
			refList(ctx, sp .. ".vehicles", s.vehicles, "Vehicle", 1, 64, true)
			enumList(ctx, sp .. ".modes", s.modes, E.battleMode, 1, 5, true)
			enumList(ctx, sp .. ".battleTypes", s.battleTypes, E.battleType, 1, 3, true)
			refList(ctx, sp .. ".maps", s.maps, "Map", 1, 64, true)
			bool(ctx, sp .. ".excludeBotHeavy", s.excludeBotHeavy, true)
		end
		if tbl(ctx, p .. ".honors", m.honors, true) then
			enum(ctx, p .. ".honors.match", m.honors.match, E.match)
			validateConditions(ctx, p .. ".honors.conditions", m.honors.conditions)
			rewards(ctx, p .. ".honors.rewards", m.honors.rewards, 1)
		end
		if tbl(ctx, p .. ".campaign", m.campaign, true) then
			local c = m.campaign
			str(ctx, p .. ".campaign.campaignId", c.campaignId, MAX_ID_LENGTH)
			num(ctx, p .. ".campaign.operation", c.operation, 1, 10, false, true)
			enum(ctx, p .. ".campaign.series", c.series, E.campaignSeries)
			num(ctx, p .. ".campaign.index", c.index, 1, 50, false, true)
		elseif cadenceOk and m.cadence == "Campaign" then
			addError(ctx, "MISSION", p .. ".campaign", "campaign missions need a campaign block")
		end
		if m.eventId ~= nil then
			local event = ref(ctx, p .. ".eventId", m.eventId, "Event")
			if event ~= nil and not listContains(event.missions, m.id) then
				addError(ctx, "MISSION", p .. ".eventId", `event {m.eventId} does not list this mission`)
			end
		elseif cadenceOk and m.cadence == "Event" then
			addError(ctx, "MISSION", p .. ".eventId", "event missions name their event")
		end
	end
end

local function validateAchievements(ctx: Ctx, reg: ContentRegistry)
	for i, a in reg._index.Achievement.list do
		local p = `achievements[{i}]({a.id})`
		fields(ctx, p, a, FIELDS.Achievement)
		str(ctx, p .. ".name", a.name, 48)
		str(ctx, p .. ".description", a.description, 300)
		icon(ctx, p .. ".icon", a.icon)
		enum(ctx, p .. ".category", a.category, E.achievementCategory)
		enum(ctx, p .. ".kind", a.kind, E.achievementKind)
		str(ctx, p .. ".rule", a.rule, 48)
		enum(ctx, p .. ".stat", a.stat, E.battleStat, true)
		if tbl(ctx, p .. ".params", a.params, true) then
			for _, key in TableUtil.sortedKeys(a.params) do
				local kp = `{p}.params.{tostring(key)}`
				if type(key) ~= "string" then
					addError(ctx, "BAD_VALUE", kp, "parameter names are strings")
				else
					num(ctx, kp, a.params[key], -1e9, 1e9)
				end
			end
		end
		if list(ctx, p .. ".thresholds", a.thresholds, 1, 16, true) then
			local previous = -math.huge
			for j, t in a.thresholds do
				if num(ctx, `{p}.thresholds[{j}]`, t, 0, 1e12) then
					if t <= previous then
						addError(ctx, "BAD_VALUE", `{p}.thresholds[{j}]`, "thresholds must strictly increase")
					end
					previous = t
				end
			end
		end
		bool(ctx, p .. ".perVehicle", a.perVehicle, true)
		bool(ctx, p .. ".repeatable", a.repeatable, true)
		bool(ctx, p .. ".hidden", a.hidden, true)
		if tbl(ctx, p .. ".scope", a.scope, true) then
			num(ctx, p .. ".scope.minTier", a.scope.minTier, 1, 11, true, true)
			num(ctx, p .. ".scope.maxTier", a.scope.maxTier, 1, 11, true, true)
			enumList(ctx, p .. ".scope.modes", a.scope.modes, E.battleMode, 1, 5, true)
			bool(ctx, p .. ".scope.pvpOnly", a.scope.pvpOnly, true)
		end
		enum(ctx, p .. ".rarity", a.rarity, E.rarity)
		rewards(ctx, p .. ".rewards", a.rewards, 0)
	end
end

--------------------------------------------------------------------------------
-- Validators: maps
--------------------------------------------------------------------------------

local MIN_SPAWNS_PER_TEAM = 15
local MIN_REAR_SPAWNS = 3
local MIN_SPAWN_SPACING_M = 10
local BASE_EDGE_MARGIN_M = 60
local SPAWN_SEPARATION_RATIO = 0.7

type Point = { x: number, z: number }

local function validateSpawns(ctx: Ctx, p: string, spawns: any, half: number): { Point }
	local centroids: { Point } = {}
	if not tbl(ctx, p, spawns) then
		return centroids
	end
	fields(ctx, p, spawns, set({ "team1", "team2" }))
	for _, team in { "team1", "team2" } do
		local tp = `{p}.{team}`
		local points = spawns[team]
		if not list(ctx, tp, points, 0, 30) then
			continue
		end
		if #points < MIN_SPAWNS_PER_TEAM then
			addError(ctx, "MAP_SPAWNS", tp, `needs at least {MIN_SPAWNS_PER_TEAM} spawn slots, has {#points}`)
		end
		local rear = 0
		local sumX, sumZ, count = 0, 0, 0
		local placed: { Point } = {}
		for i, sp in points do
			local ip = `{tp}[{i}]`
			if not tbl(ctx, ip, sp) then
				continue
			end
			num(ctx, ip .. ".facingDeg", sp.facingDeg, -360, 360)
			bool(ctx, ip .. ".rear", sp.rear, true)
			if sp.rear == true then
				rear += 1
			end
			if vec2(ctx, ip .. ".at", sp.at, half) then
				for _, other in placed do
					local dx, dz = other.x - sp.at.x, other.z - sp.at.z
					if math.sqrt(dx * dx + dz * dz) < MIN_SPAWN_SPACING_M then
						addError(ctx, "MAP_SPAWNS", ip .. ".at", `closer than {MIN_SPAWN_SPACING_M} m to another slot`)
						break
					end
				end
				table.insert(placed, sp.at)
				sumX += sp.at.x
				sumZ += sp.at.z
				count += 1
			end
		end
		if rear < MIN_REAR_SPAWNS then
			addError(ctx, "MAP_SPAWNS", tp, `needs at least {MIN_REAR_SPAWNS} rear slots, has {rear}`)
		end
		if count > 0 then
			table.insert(centroids, { x = sumX / count, z = sumZ / count })
		end
	end
	return centroids
end

local function validateMaps(ctx: Ctx, reg: ContentRegistry)
	for i, m in reg._index.Map.list do
		local p = `maps[{i}]({m.id})`
		fields(ctx, p, m, FIELDS.Map)
		str(ctx, p .. ".name", m.name, 32)
		str(ctx, p .. ".description", m.description, 400)
		enum(ctx, p .. ".biome", m.biome, E.biome)
		local sizeOk = num(ctx, p .. ".sizeM", m.sizeM, 300, 3000)
		local half = if sizeOk then m.sizeM / 2 else 1e6
		num(ctx, p .. ".skirtM", m.skirtM, 0, 1000, true)
		local outer = half + (if isFinite(m.skirtM) then m.skirtM else 150)
		range(ctx, p .. ".tierRange", m.tierRange, 1, 11)
		enumList(ctx, p .. ".battleTypes", m.battleTypes, E.battleType, 1, 3)
		enumList(ctx, p .. ".modes", m.modes, E.battleMode, 1, 5)
		num(ctx, p .. ".revision", m.revision, 1, 1e6, false, true)
		-- terrain
		local terrain = m.terrain
		local tp = p .. ".terrain"
		if tbl(ctx, tp, terrain) then
			num(ctx, tp .. ".seed", terrain.seed, 0, 2 ^ 31, false, true)
			num(ctx, tp .. ".baseHeightM", terrain.baseHeightM, -100, 500)
			num(ctx, tp .. ".waterLevelM", terrain.waterLevelM, -100, 500, true)
			if list(ctx, tp .. ".noise", terrain.noise, 0, 8) then
				for j, n in terrain.noise do
					if tbl(ctx, `{tp}.noise[{j}]`, n) then
						num(ctx, `{tp}.noise[{j}].scaleM`, n.scaleM, 1, 5000)
						num(ctx, `{tp}.noise[{j}].amplitudeM`, n.amplitudeM, 0, 80)
					end
				end
			end
			if list(ctx, tp .. ".features", terrain.features, 0, 256) then
				for j, f in terrain.features do
					local fp = `{tp}.features[{j}]`
					if tbl(ctx, fp, f) then
						enum(ctx, fp .. ".kind", f.kind, E.terrainFeature)
						if list(ctx, fp .. ".points", f.points, 1, 64) then
							for k, pt in f.points do
								vec2(ctx, `{fp}.points[{k}]`, pt, outer)
							end
						end
						num(ctx, fp .. ".radiusM", f.radiusM, 0.5, 2000)
						num(ctx, fp .. ".heightM", f.heightM, -80, 80)
						num(ctx, fp .. ".falloff", f.falloff, 0, 1, true)
					end
				end
			end
			if list(ctx, tp .. ".materials", terrain.materials, 1, 16) then
				local defaults = 0
				for j, rule in terrain.materials do
					local rp = `{tp}.materials[{j}]`
					if tbl(ctx, rp, rule) then
						enum(ctx, rp .. ".material", rule.material, E.terrainMaterial)
						if enum(ctx, rp .. ".rule", rule.rule, E.materialRule) then
							if rule.rule == "Default" then
								defaults += 1
							elseif rule.rule == "Feature" then
								enum(ctx, rp .. ".feature", rule.feature, E.terrainFeature)
							end
						end
						num(ctx, rp .. ".min", rule.min, -1000, 1000, true)
						num(ctx, rp .. ".max", rule.max, -1000, 1000, true)
					end
				end
				if defaults ~= 1 then
					addError(
						ctx,
						"MAP_TERRAIN",
						tp .. ".materials",
						`exactly one Default material rule, found {defaults}`
					)
				end
			end
		end
		-- spawns and separation
		local centroids = validateSpawns(ctx, p .. ".spawns", m.spawns, half)
		if #centroids == 2 and sizeOk then
			local dx, dz = centroids[1].x - centroids[2].x, centroids[1].z - centroids[2].z
			local separation = math.sqrt(dx * dx + dz * dz)
			if separation < SPAWN_SEPARATION_RATIO * m.sizeM then
				addError(
					ctx,
					"MAP_SEPARATION",
					p .. ".spawns",
					`spawn centroids are {math.floor(separation)} m apart (needs {SPAWN_SEPARATION_RATIO * m.sizeM} m)`
				)
			end
		end
		-- bases per battle type
		if list(ctx, p .. ".bases", m.bases, 1, 8) then
			local byType: { [string]: { any } } = {}
			local ids = {}
			for j, b in m.bases do
				local bp = `{p}.bases[{j}]`
				if not tbl(ctx, bp, b) then
					continue
				end
				if str(ctx, bp .. ".id", b.id, MAX_ID_LENGTH) then
					if ids[b.id] then
						addError(ctx, "MAP_BASES", bp .. ".id", `duplicate base id {b.id}`)
					end
					ids[b.id] = true
				end
				if enum(ctx, bp .. ".battleType", b.battleType, E.battleType) then
					local group = byType[b.battleType] or {}
					byType[b.battleType] = group
					table.insert(group, b)
				end
				if b.team ~= nil and b.team ~= 1 and b.team ~= 2 then
					addError(ctx, "MAP_BASES", bp .. ".team", "team must be 1, 2 or nil (neutral)")
				end
				local radius = if b.radiusM ~= nil then b.radiusM else 50
				num(ctx, bp .. ".radiusM", b.radiusM, 10, 200, true)
				if vec2(ctx, bp .. ".center", b.center, half) and sizeOk and isFinite(radius) then
					local reach = math.max(math.abs(b.center.x), math.abs(b.center.z)) + radius
					if reach > half - BASE_EDGE_MARGIN_M then
						addError(
							ctx,
							"MAP_BASES",
							bp,
							`capture circle must stay {BASE_EDGE_MARGIN_M} m inside the boundary`
						)
					end
				end
			end
			if type(m.battleTypes) == "table" then
				for _, battleType in m.battleTypes do
					local group: { any } = byType[battleType] or {}
					local teams: { [number]: number } = {}
					for _, b in group do
						local key = if b.team == nil then 0 else b.team
						teams[key] = (teams[key] or 0) + 1
					end
					local okShape, need
					if battleType == "Standard" then
						okShape = #group == 2 and teams[1] == 1 and teams[2] == 1
						need = "one base per team"
					elseif battleType == "Encounter" then
						okShape = #group == 1 and teams[0] == 1
						need = "one neutral base"
					else
						okShape = #group == 1 and (teams[1] == 1 or teams[2] == 1)
						need = "one defender base"
					end
					if not okShape then
						addError(ctx, "MAP_BASES", p .. ".bases", `{tostring(battleType)} needs {need}`)
					end
				end
				for _, battleType in TableUtil.sortedKeys(byType) do
					if not listContains(m.battleTypes, battleType) then
						addWarning(
							ctx,
							"MAP_BASES",
							p .. ".bases",
							`bases for {battleType}, which the map does not list`
						)
					end
				end
			end
		end
		-- lanes
		if list(ctx, p .. ".lanes", m.lanes, 3, 8) then
			local kinds = {}
			local ids = {}
			for j, lane in m.lanes do
				local lp = `{p}.lanes[{j}]`
				if not tbl(ctx, lp, lane) then
					continue
				end
				if str(ctx, lp .. ".id", lane.id, MAX_ID_LENGTH) then
					if ids[lane.id] then
						addError(ctx, "MAP_LANES", lp .. ".id", `duplicate lane id {lane.id}`)
					end
					ids[lane.id] = true
				end
				if enum(ctx, lp .. ".kind", lane.kind, E.laneKind) then
					kinds[lane.kind] = true
				end
				num(ctx, lp .. ".widthM", lane.widthM, 20, 600)
				if list(ctx, lp .. ".points", lane.points, 2, 32) then
					for k, pt in lane.points do
						vec2(ctx, `{lp}.points[{k}]`, pt, half)
					end
				end
			end
			for _, kind in { "Heavy", "Flex", "Open" } do
				if not kinds[kind] then
					addError(ctx, "MAP_LANES", p .. ".lanes", `needs a {kind} lane`)
				end
			end
		elseif type(m.lanes) == "table" and #m.lanes < 3 then
			addError(ctx, "MAP_LANES", p .. ".lanes", "needs one Heavy, one Flex and one Open lane")
		end
		-- foliage, props, water, variants, events
		if list(ctx, p .. ".foliage", m.foliage, 0, 20000) then
			for j, f in m.foliage do
				local fp = `{p}.foliage[{j}]`
				if tbl(ctx, fp, f) then
					enum(ctx, fp .. ".kind", f.kind, E.foliage)
					vec2(ctx, fp .. ".at", f.at, half)
					if f.to ~= nil then
						vec2(ctx, fp .. ".to", f.to, half)
					end
					num(ctx, fp .. ".heightM", f.heightM, 0, 40)
					num(ctx, fp .. ".radiusM", f.radiusM, 0.2, 30)
					num(ctx, fp .. ".concealment", f.concealment, 0, 0.8, true)
				end
			end
		end
		if list(ctx, p .. ".props", m.props, 0, 20000) then
			for j, prop in m.props do
				local pp = `{p}.props[{j}]`
				if tbl(ctx, pp, prop) then
					str(ctx, pp .. ".prop", prop.prop, 48)
					vec2(ctx, pp .. ".at", prop.at, outer)
					num(ctx, pp .. ".rotationDeg", prop.rotationDeg, -360, 360, true)
					num(ctx, pp .. ".scale", prop.scale, 0.1, 10, true)
					num(ctx, pp .. ".variant", prop.variant, 1, 64, true, true)
					enum(ctx, pp .. ".destructible", prop.destructible, E.destructible, true)
				end
			end
		end
		if list(ctx, p .. ".water", m.water, 0, 32, true) then
			for j, w in m.water do
				local wp = `{p}.water[{j}]`
				if tbl(ctx, wp, w) then
					str(ctx, wp .. ".id", w.id, MAX_ID_LENGTH)
					if list(ctx, wp .. ".points", w.points, 3, 64) then
						for k, pt in w.points do
							vec2(ctx, `{wp}.points[{k}]`, pt, outer)
						end
					end
					num(ctx, wp .. ".surfaceHeightM", w.surfaceHeightM, -100, 500)
					num(ctx, wp .. ".depthM", w.depthM, 0, 50)
				end
			end
		end
		if list(ctx, p .. ".variants", m.variants, 1, 8) then
			for j, variant in m.variants do
				local vp = `{p}.variants[{j}]`
				if tbl(ctx, vp, variant) then
					str(ctx, vp .. ".id", variant.id, MAX_ID_LENGTH)
					str(ctx, vp .. ".lighting", variant.lighting, 48)
					str(ctx, vp .. ".weather", variant.weather, 48)
					num(ctx, vp .. ".weight", variant.weight, 0.01, 100)
				end
			end
		end
		if list(ctx, p .. ".randomEvents", m.randomEvents, 0, 16, true) then
			for j, event in m.randomEvents do
				local ep = `{p}.randomEvents[{j}]`
				if tbl(ctx, ep, event) then
					str(ctx, ep .. ".id", event.id, MAX_ID_LENGTH)
					num(ctx, ep .. ".chance", event.chance, 0, 1)
					list(ctx, ep .. ".props", event.props, 0, 256)
				end
			end
		end
		if tbl(ctx, p .. ".audio", m.audio) then
			if str(ctx, p .. ".audio.ambience", m.audio.ambience, 64) then
				sound(ctx, p .. ".audio.ambience", m.audio.ambience)
			end
			if str(ctx, p .. ".audio.music", m.audio.music, 64, true) then
				sound(ctx, p .. ".audio.music", m.audio.music)
			end
		end
		icon(ctx, p .. ".thumbnail", m.thumbnail, true)
		if list(ctx, p .. ".tips", m.tips, 1, 8) then
			for j, tip in m.tips do
				str(ctx, `{p}.tips[{j}]`, tip, 120)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Validators: store, events, seasons
--------------------------------------------------------------------------------

local function validateWindow(ctx: Ctx, p: string, startsAt: any, endsAt: any, optional: boolean)
	local okStart = num(ctx, p .. ".startsAt", startsAt, 0, 1e11, optional, true)
	local okEnd = num(ctx, p .. ".endsAt", endsAt, 0, 1e11, optional, true)
	if okStart and okEnd and startsAt >= endsAt then
		addError(ctx, "SCHEDULE", p, "startsAt must be before endsAt")
	end
end

local function validateLiveOps(ctx: Ctx, reg: ContentRegistry)
	for i, s in reg._index.StoreItem.list do
		local p = `store[{i}]({s.id})`
		fields(ctx, p, s, FIELDS.StoreItem)
		str(ctx, p .. ".name", s.name, 48)
		str(ctx, p .. ".description", s.description, 300)
		icon(ctx, p .. ".icon", s.icon, true)
		local kindOk = enum(ctx, p .. ".kind", s.kind, E.storeKind)
		price(ctx, p .. ".price", s.price, true)
		if tbl(ctx, p .. ".robux", s.robux, true) then
			enum(ctx, p .. ".robux.kind", s.robux.kind, E.robuxKind)
			num(ctx, p .. ".robux.productId", s.robux.productId, 0, 2 ^ 53, false, true)
		end
		if (s.price == nil) == (s.robux == nil) then
			addError(ctx, "STORE", p, "exactly one of price (in-game currency) or robux (product) is required")
		end
		if kindOk and s.kind == "BullionPack" and s.robux == nil then
			addError(ctx, "STORE", p .. ".robux", "Bullion packs are Robux developer products")
		end
		rewards(ctx, p .. ".grants", s.grants, if s.kind == "SeasonPass" then 0 else 1)
		validateWindow(ctx, p, s.startsAt, s.endsAt, true)
		num(ctx, p .. ".purchaseLimit", s.purchaseLimit, 1, 1e6, true, true)
		num(ctx, p .. ".sortOrder", s.sortOrder, -1e6, 1e6, true)
		bool(ctx, p .. ".featured", s.featured, true)
	end
	for i, ev in reg._index.Event.list do
		local p = `events[{i}]({ev.id})`
		fields(ctx, p, ev, FIELDS.Event)
		str(ctx, p .. ".name", ev.name, 48)
		str(ctx, p .. ".description", ev.description, 400)
		icon(ctx, p .. ".icon", ev.icon, true)
		enum(ctx, p .. ".kind", ev.kind, E.eventKind)
		validateWindow(ctx, p, ev.startsAt, ev.endsAt, false)
		if num(ctx, p .. ".shopClosesAt", ev.shopClosesAt, 0, 1e11, true, true) and isFinite(ev.endsAt) then
			if ev.shopClosesAt < ev.endsAt then
				addError(ctx, "SCHEDULE", p .. ".shopClosesAt", "the token shop closes after the event ends")
			end
		end
		refList(ctx, p .. ".missions", ev.missions, "Mission", 0, 200)
		refList(ctx, p .. ".shop", ev.shop, "StoreItem", 0, 200, true)
		num(ctx, p .. ".tokenConversionCredits", ev.tokenConversionCredits, 0, 1e6, true)
		if tbl(ctx, p .. ".modifiers", ev.modifiers, true) then
			for _, key in { "xpMul", "creditMul", "freeXpMul", "crewXpMul", "firstWinMul" } do
				num(ctx, `{p}.modifiers.{key}`, ev.modifiers[key], 1, 10, true)
			end
		end
		if list(ctx, p .. ".modes", ev.modes, 0, 8, true) then
			for j, mode in ev.modes do
				local mp = `{p}.modes[{j}]`
				if not tbl(ctx, mp, mode) then
					continue
				end
				str(ctx, mp .. ".id", mode.id, MAX_ID_LENGTH)
				str(ctx, mp .. ".name", mode.name, 48)
				enum(ctx, mp .. ".baseMode", mode.baseMode, E.battleMode)
				num(ctx, mp .. ".teamSize", mode.teamSize, 1, 30, false, true)
				refList(ctx, mp .. ".maps", mode.maps, "Map", 1, 64)
				range(ctx, mp .. ".tierRange", mode.tierRange, 1, 11, true)
				refList(ctx, mp .. ".vehicles", mode.vehicles, "Vehicle", 1, 64, true)
				num(ctx, mp .. ".respawns", mode.respawns, 0, 100, true, true)
				num(ctx, mp .. ".durationS", mode.durationS, 30, 3600, true)
				if list(ctx, mp .. ".abilities", mode.abilities, 0, 8, true) then
					for k, ability in mode.abilities do
						local ap = `{mp}.abilities[{k}]`
						if tbl(ctx, ap, ability) then
							str(ctx, ap .. ".id", ability.id, MAX_ID_LENGTH)
							str(ctx, ap .. ".name", ability.name, 40)
							enum(ctx, ap .. ".kind", ability.kind, E.ability)
							num(ctx, ap .. ".cooldownS", ability.cooldownS, 1, 3600)
							num(ctx, ap .. ".charges", ability.charges, 1, 100, true, true)
							num(ctx, ap .. ".radiusM", ability.radiusM, 1, 500, true)
							num(ctx, ap .. ".durationS", ability.durationS, 0.1, 600, true)
							num(ctx, ap .. ".damage", ability.damage, 0, 5000, true)
							icon(ctx, ap .. ".icon", ability.icon, true)
						end
					end
				end
			end
		end
	end
	for i, s in reg._index.Season.list do
		local p = `seasons[{i}]({s.id})`
		fields(ctx, p, s, FIELDS.Season)
		str(ctx, p .. ".name", s.name, 48)
		validateWindow(ctx, p, s.startsAt, s.endsAt, false)
		num(ctx, p .. ".pointsPerDailyMission", s.pointsPerDailyMission, 0, 1000)
		if s.paidUnlock ~= nil then
			local item = ref(ctx, p .. ".paidUnlock", s.paidUnlock, "StoreItem")
			if item ~= nil and item.kind ~= "SeasonPass" then
				addError(ctx, "SEASON", p .. ".paidUnlock", "the paid unlock must be a SeasonPass store item")
			end
		end
		if list(ctx, p .. ".pointsByRank", s.pointsByRank, 1, 8) then
			local previous = 0
			for j, rule in s.pointsByRank do
				local rp = `{p}.pointsByRank[{j}]`
				if tbl(ctx, rp, rule) then
					if num(ctx, rp .. ".maxTeamRank", rule.maxTeamRank, 1, 30, false, true) then
						if rule.maxTeamRank <= previous then
							addError(ctx, "SEASON", rp .. ".maxTeamRank", "ranks must ascend")
						end
						previous = rule.maxTeamRank
					end
					num(ctx, rp .. ".win", rule.win, 0, 1000)
					num(ctx, rp .. ".loss", rule.loss, 0, 1000)
				end
			end
		end
		if list(ctx, p .. ".chapters", s.chapters, 1, 6) then
			for j, chapter in s.chapters do
				local cp = `{p}.chapters[{j}]`
				if not tbl(ctx, cp, chapter) then
					continue
				end
				str(ctx, cp .. ".id", chapter.id, MAX_ID_LENGTH)
				str(ctx, cp .. ".name", chapter.name, 48)
				local stagesOk = num(ctx, cp .. ".stages", chapter.stages, 1, 200, false, true)
				num(ctx, cp .. ".pointsPerStage", chapter.pointsPerStage, 1, 10000)
				rewards(ctx, cp .. ".finalReward", chapter.finalReward, 1, true)
				if list(ctx, cp .. ".rewards", chapter.rewards, 0, 400) then
					for k, reward in chapter.rewards do
						local rp = `{cp}.rewards[{k}]`
						if tbl(ctx, rp, reward) then
							if num(ctx, rp .. ".stage", reward.stage, 1, 200, false, true) and stagesOk then
								if reward.stage > chapter.stages then
									addError(ctx, "SEASON", rp .. ".stage", "stage beyond the chapter's stage count")
								end
							end
							enum(ctx, rp .. ".track", reward.track, E.passTrack)
							rewards(ctx, rp .. ".rewards", reward.rewards, 1)
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- validate()
--------------------------------------------------------------------------------

--- Validates everything and returns ALL problems. Ok(report) when there are no errors (warnings allowed);
--- Err(INVALID_ARGS, report) otherwise. Issues are ordered deterministically (kind order, then manifest order).
function Registry.validate(self: ContentRegistry, options: ValidateOptions?): Result<ValidationReport>
	local ctx: Ctx = { errors = {}, warnings = {}, opts = options or {}, reg = self }
	for _, issue in self._buildIssues do
		table.insert(ctx.errors, issue)
	end

	-- Usage maps for orphan warnings.
	local usedShells: { [string]: boolean } = {}
	local usedModules: { [string]: boolean } = {}
	for _, g in self._index.Gun.list do
		if type(g.shells) == "table" then
			for _, s in g.shells do
				usedShells[s] = true
			end
		end
	end
	for _, v in self._index.Vehicle.list do
		if type(v.modules) == "table" then
			for _, slot in CONFIG_SLOTS do
				if type(v.modules[slot.list]) == "table" then
					for _, id in v.modules[slot.list] do
						usedModules[id] = true
					end
				end
			end
		end
	end

	validateFactions(ctx, self)
	validateBranches(ctx, self)
	validateClasses(ctx, self)
	validateRoles(ctx, self)
	validateTiers(ctx, self)
	validateShells(ctx, self, usedShells)
	validateGuns(ctx, self, usedModules)
	validateTurrets(ctx, self, usedModules)
	validateEngines(ctx, self, usedModules)
	validateTracks(ctx, self, usedModules)
	local rows: { [string]: string } = {}
	for i, v in self._index.Vehicle.list do
		validateVehicle(ctx, self, i, v, rows)
	end
	validateTechTree(ctx, self)
	validateEquipment(ctx, self)
	validateConsumables(ctx, self)
	validateSmallKinds(ctx, self)
	validateMissions(ctx, self)
	validateAchievements(ctx, self)
	validateMaps(ctx, self)
	validateLiveOps(ctx, self)

	local report: ValidationReport = { errors = ctx.errors, warnings = ctx.warnings }
	if #ctx.errors > 0 then
		return Result.err(ErrorCodes.INVALID_ARGS, report)
	end
	return Result.ok(report)
end

--- One line per issue ("CODE path: message"), for logs and test failure output.
function ContentRegistry.formatIssues(issues: { ContentIssue }): string
	local lines = {}
	for _, issue in issues do
		table.insert(lines, `{issue.code} {issue.path}: {issue.message}`)
	end
	return table.concat(lines, "\n")
end

return ContentRegistry
