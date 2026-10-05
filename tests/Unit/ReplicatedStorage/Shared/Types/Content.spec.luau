-- Types/Content smoke tests: the module loads, and every string-literal union the validator mirrors at runtime
-- (ContentRegistry.ENUMS) matches the type declaration exactly, so the static schema and the validator cannot drift.
local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local ContentRegistry = require("@game/ReplicatedStorage/Shared/Config/ContentRegistry")
local TypeSource = require("./TypeSource")

local SOURCE = TypeSource.read("Content")

-- Type name -> ContentRegistry.ENUMS key.
local MIRRORS: { [string]: string } = {
	FactionId = "faction",
	VehicleClass = "class",
	RoleId = "role",
	CrewRole = "crewRole",
	ShellKind = "shellKind",
	InternalModuleKind = "internalModule",
	EquipmentCategory = "equipmentCategory",
	Acquisition = "acquisition",
	BattleMode = "battleMode",
	BattleType = "battleType",
	Rarity = "rarity",
	Biome = "biome",
	StatKey = "statKey",
	StatOp = "statOp",
	StatCondition = "statCondition",
	BalanceStat = "balanceStat",
	FactionSignature = "factionSignature",
	RoleScoreComponent = "roleScore",
	RoleGroup = "roleGroup",
	TracerStyle = "tracer",
	ReloadKind = "reloadKind",
	MuzzleBrake = "muzzleBrake",
	MantletStyle = "mantlet",
	GunAudioFamily = "gunAudio",
	TurretMount = "turretMount",
	TurretStyle = "turretStyle",
	EngineFuel = "engineFuel",
	EngineAudioFamily = "engineAudio",
	TrackLinkStyle = "trackLink",
	HullStyle = "hullStyle",
	SuspensionStyle = "suspension",
	AmmoRackPlacement = "ammoRack",
	MechanicKind = "mechanic",
	ConsumableKind = "consumableKind",
	CustomizationKind = "customizationKind",
	BattleStatKey = "battleStat",
	MissionCadence = "cadence",
	CampaignSeries = "campaignSeries",
	RewardKind = "rewardKind",
	AchievementCategory = "achievementCategory",
	AchievementKind = "achievementKind",
	TerrainFeatureKind = "terrainFeature",
	TerrainMaterial = "terrainMaterial",
	LaneKind = "laneKind",
	FoliageKind = "foliage",
	DestructibleClass = "destructible",
	StoreItemKind = "storeKind",
	EventKind = "eventKind",
	PassTrack = "passTrack",
}

describe("Types/Content", function()
	it("loads as a type-only module", function()
		expect(require("@game/ReplicatedStorage/Shared/Types/Content")).toEqual({})
		expect(table.isfrozen(ContentRegistry.ENUMS)).toBe(true)
	end)

	for typeName, enumKey in MIRRORS do
		it(`{typeName} matches ContentRegistry.ENUMS.{enumKey}`, function()
			local enum = (ContentRegistry.ENUMS :: any)[enumKey]
			expect(enum).never.toBeNil()
			expect(TypeSource.sortedKeys(enum)).toEqual(TypeSource.unionMembers(SOURCE, typeName))
		end)
	end

	it("ReloadSpec and SpecialMechanic tags match ReloadKind and MechanicKind", function()
		expect(TypeSource.tagsOf(SOURCE, "ReloadSpec", "kind")).toEqual(TypeSource.unionMembers(SOURCE, "ReloadKind"))
		expect(TypeSource.tagsOf(SOURCE, "SpecialMechanic", "kind")).toEqual(
			TypeSource.unionMembers(SOURCE, "MechanicKind")
		)
	end)

	it("the bundle, the manifest and ContentKind describe the same 22 kinds", function()
		local kinds = TypeSource.unionMembers(SOURCE, "ContentKind")
		expect(#kinds).toBe(22)
		local bundle = TypeSource.fieldNames(SOURCE, "ContentBundle")
		local sources = TypeSource.fieldNames(SOURCE, "ContentSources")
		expect(#bundle).toBe(22)
		expect(bundle).toEqual(sources)
		local shipped = ContentRegistry.shippedBundle() :: any
		expect(TypeSource.sortedKeys(shipped)).toEqual(bundle)
	end)

	it("every module kind carries the common module fields", function()
		for _, typeName in { "GunDefinition", "TurretDefinition", "EngineDefinition", "TracksDefinition" } do
			local names = TypeSource.fieldNames(SOURCE, typeName)
			for _, common in { "id", "kind", "name", "tier", "massKg", "priceCredits", "researchXp" } do
				expect(names).toContain(common)
			end
		end
	end)

	it("the exemplar vehicles author every required VehicleDefinition field and nothing unknown", function()
		local required = TypeSource.fieldNames(SOURCE, "VehicleDefinition")
		local all = TypeSource.fieldNames(SOURCE, "VehicleDefinition", true)
		local allowed = {}
		for _, name in all do
			allowed[name] = true
		end
		for _, vehicle in ContentRegistry.get():allVehicles() do
			for _, name in required do
				if (vehicle :: any)[name] == nil then
					error(`{vehicle.id} misses {name}`)
				end
			end
			for key in vehicle :: any do
				expect(allowed[key]).toBe(true)
			end
		end
	end)

	it("documents a Config default or rule for every optional shell field", function()
		-- Optional shell fields fall back to documented defaults; each must carry a comment saying so.
		for _, field in TypeSource.fieldsOf(SOURCE, "ShellDefinition") do
			if field.optional then
				local line = string.match(SOURCE, `\n\t{field.name}: [^\n]*`)
				expect(line).never.toBeNil()
				expect(string.find(line :: string, "--", 1, true)).never.toBeNil()
			end
		end
	end)
end)
