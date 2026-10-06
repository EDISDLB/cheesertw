--!strict
--[[
	Matchmaking/Pools — builds the MatchmakerConfig: settings + bot vehicle pool (indexed by tier and class) + map
	pool + role groups + resolved mode rules.

	Purpose:          Pools.fromContent(settings, content, modes?) for production (ContentRegistry lists);
	                  Pools.build(settings, vehicles, maps, roleGroups?, modes?) for plain entries (tests, tools).
	                  Pools.availability(config, tier) tells which classes bots can field at a tier.
	Dependencies:     Types/Matchmaking, Types/Content, Core/Freeze, Matchmaking/Rules.
	State:            None; the returned config is deep-frozen (shared read-only by every run).
	Validation:       Raises on malformed entries (programming / content mistakes surface at boot, not mid-run):
	                  vehicle ids unique, tier in range, known class, role of that class, wheeled only on lights; map
	                  ids unique, tier range sane, weight finite >= 0; mode TEAM_SIZE integer >= 1.
	Error handling:   error() with a "Pools: ..." message on invalid input.
	Performance notes: Built once per content load (O(vehicles + maps)); run() only reads it.
]]

local MatchmakingTypes = require("@game/ReplicatedStorage/Shared/Types/Matchmaking")
local ContentTypes = require("@game/ReplicatedStorage/Shared/Types/Content")
local Freeze = require("@game/ReplicatedStorage/Shared/Core/Freeze")
local Rules = require("./Rules")

type MatchmakingSettings = MatchmakingTypes.MatchmakingSettings
type MatchmakerConfig = MatchmakingTypes.MatchmakerConfig
type BotVehicle = MatchmakingTypes.BotVehicle
type MapEntry = MatchmakingTypes.MapEntry
type ModeRules = MatchmakingTypes.ModeRules
type VehicleIndex = MatchmakingTypes.VehicleIndex

local Pools = {}

--- Content lists Pools.fromContent reads (ContentRegistry: allVehicles(), allMaps(), list("Role")).
export type ContentLists = {
	vehicles: { ContentTypes.VehicleDefinition },
	maps: { ContentTypes.MapDefinition },
	roles: { ContentTypes.RoleDefinition }?,
}

local function fail(message: string): never
	error("Pools: " .. message, 3)
end

local function checkVehicle(settings: MatchmakingSettings, v: BotVehicle, seen: { [string]: boolean })
	if type(v) ~= "table" or type(v.defId) ~= "string" or v.defId == "" then
		fail("vehicle without a defId")
	end
	if seen[v.defId] then
		fail(`vehicle {v.defId} listed twice`)
	end
	seen[v.defId] = true
	if type(v.tier) ~= "number" or v.tier ~= math.floor(v.tier) or v.tier < settings.TIER_MIN or v.tier > settings.TIER_MAX then
		fail(`vehicle {v.defId}: tier out of range`)
	end
	if Rules.CLASS_INDEX[v.class] == nil then
		fail(`vehicle {v.defId}: unknown class {tostring(v.class)}`)
	end
	if type(v.role) ~= "string" or string.sub(v.role, 1, #v.class + 1) ~= v.class .. "_" then
		fail(`vehicle {v.defId}: role {tostring(v.role)} does not belong to class {v.class}`)
	end
	if type(v.faction) ~= "string" then
		fail(`vehicle {v.defId}: missing faction`)
	end
	if v.wheeled and v.class ~= "light" then
		fail(`vehicle {v.defId}: only light vehicles are wheeled`)
	end
end

local function checkMap(settings: MatchmakingSettings, m: MapEntry, seen: { [string]: boolean })
	if type(m) ~= "table" or type(m.id) ~= "string" or m.id == "" then
		fail("map without an id")
	end
	if seen[m.id] then
		fail(`map {m.id} listed twice`)
	end
	seen[m.id] = true
	if type(m.tierMin) ~= "number" or type(m.tierMax) ~= "number" or m.tierMin > m.tierMax then
		fail(`map {m.id}: bad tier range`)
	end
	if m.tierMax < settings.TIER_MIN or m.tierMin > settings.TIER_MAX then
		fail(`map {m.id}: tier range outside {settings.TIER_MIN}..{settings.TIER_MAX}`)
	end
	if type(m.weight) ~= "number" or m.weight ~= m.weight or m.weight < 0 or m.weight == math.huge then
		fail(`map {m.id}: weight must be finite and >= 0`)
	end
	if type(m.battleTypes) ~= "table" or type(m.modes) ~= "table" then
		fail(`map {m.id}: battleTypes and modes must be arrays`)
	end
end

--- Mode rules from settings.MODES plus caller overrides (override entries replace the whole mode).
local function resolveModes(settings: MatchmakingSettings, overrides: { [string]: ModeRules }?): { [string]: ModeRules }
	local out: { [string]: ModeRules } = {}
	for name, spec in settings.MODES do
		out[name] = {
			teamSize = spec.TEAM_SIZE,
			botFill = spec.BOT_FILL,
			competitive = spec.COMPETITIVE,
			randomBattleTypes = spec.RANDOM_BATTLE_TYPES,
		}
	end
	if overrides then
		for name, rules in overrides do
			out[name] = table.clone(rules)
		end
	end
	for name, rules in out do
		local n = rules.teamSize
		if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > 50 then
			fail(`mode {name}: teamSize must be an integer 1..50`)
		end
	end
	return out
end

local function buildIndex(settings: MatchmakingSettings, vehicles: { BotVehicle }): VehicleIndex
	local index: VehicleIndex = {}
	for tier = settings.TIER_MIN, settings.TIER_MAX do
		local perClass = table.create(Rules.CLASS_COUNT)
		for i = 1, Rules.CLASS_COUNT do
			perClass[i] = {}
		end
		index[tier] = perClass
	end
	for _, v in vehicles do
		table.insert(index[v.tier][Rules.CLASS_INDEX[v.class]], v)
	end
	return index
end

--- Builds a config from plain pool entries. Vehicles and maps are copied, sorted by id and frozen with the result.
function Pools.build(
	settings: MatchmakingSettings,
	vehicles: { BotVehicle },
	maps: { MapEntry },
	roleGroups: { [string]: string }?,
	modes: { [string]: ModeRules }?
): MatchmakerConfig
	if type(settings) ~= "table" or type(settings.TEMPLATES) ~= "table" then
		fail("settings must be the Config.Matchmaking section")
	end
	local seenV: { [string]: boolean } = {}
	local vlist: { BotVehicle } = {}
	for _, v in vehicles do
		checkVehicle(settings, v, seenV)
		table.insert(vlist, {
			defId = v.defId,
			tier = v.tier,
			class = v.class,
			role = v.role,
			faction = v.faction,
			wheeled = v.wheeled == true,
			premium = v.premium == true,
		})
	end
	table.sort(vlist, function(a: BotVehicle, b: BotVehicle): boolean
		return a.defId < b.defId
	end)
	local seenM: { [string]: boolean } = {}
	local mlist: { MapEntry } = {}
	for _, m in maps do
		checkMap(settings, m, seenM)
		table.insert(mlist, {
			id = m.id,
			tierMin = m.tierMin,
			tierMax = m.tierMax,
			battleTypes = table.clone(m.battleTypes),
			modes = table.clone(m.modes),
			weight = m.weight,
		})
	end
	table.sort(mlist, function(a: MapEntry, b: MapEntry): boolean
		return a.id < b.id
	end)
	local config: MatchmakerConfig = {
		settings = settings,
		vehicles = vlist,
		maps = mlist,
		roleGroups = if roleGroups then table.clone(roleGroups) else {},
		modes = resolveModes(settings, modes),
		index = buildIndex(settings, vlist),
	}
	return Freeze.deep(config)
end

local function isWheeled(def: ContentTypes.VehicleDefinition): boolean
	if def.mechanics then
		for _, m in def.mechanics do
			if m.kind == "Wheeled" then
				return true
			end
		end
	end
	return false
end

--- Builds a config from content definitions: bot vehicles = not hidden and acquisition in BOT_ACQUISITIONS; maps
--- keep their tierRange / battleTypes / modes with weight 1; role groups from RoleDefinition.group.
function Pools.fromContent(
	settings: MatchmakingSettings,
	content: ContentLists,
	modes: { [string]: ModeRules }?
): MatchmakerConfig
	local vehicles: { BotVehicle } = {}
	for _, def in content.vehicles do
		if def.hidden == true or table.find(settings.BOT_ACQUISITIONS, def.acquisition) == nil then
			continue
		end
		table.insert(vehicles, {
			defId = def.id,
			tier = def.tier,
			class = def.class,
			role = def.role,
			faction = def.faction,
			wheeled = isWheeled(def),
			premium = def.acquisition == "Premium",
		})
	end
	local maps: { MapEntry } = {}
	for _, def in content.maps do
		table.insert(maps, {
			id = def.id,
			tierMin = def.tierRange.min,
			tierMax = def.tierRange.max,
			battleTypes = def.battleTypes,
			modes = def.modes,
			weight = 1,
		})
	end
	local groups: { [string]: string } = {}
	if content.roles then
		for _, r in content.roles do
			groups[r.id] = r.group
		end
	end
	return Pools.build(settings, vehicles, maps, groups, modes)
end

--- Classes bots can field at a tier (array in Rules.CLASSES order). Light needs a tracked (non-wheeled) light so a
--- bot never depends on the wheeled cap (roster.md §3.4 rule 1).
function Pools.availability(config: MatchmakerConfig, tier: number): { boolean }
	local out = table.create(Rules.CLASS_COUNT, false)
	local perClass = config.index[tier]
	if perClass == nil then
		return out
	end
	for ci = 1, Rules.CLASS_COUNT do
		local list = perClass[ci]
		if ci == Rules.LIGHT then
			for _, v in list do
				if not v.wheeled then
					out[ci] = true
					break
				end
			end
		else
			out[ci] = #list > 0
		end
	end
	return out
end

return Pools
