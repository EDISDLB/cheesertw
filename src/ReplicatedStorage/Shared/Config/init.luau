--!strict
--[[
	Config — aggregates every config section, deep-freezes it and applies validated live overrides.

	Purpose:          `local Config = require("@game/ReplicatedStorage/Shared/Config")` then `Config.Battle.TICK_RATE`.
	Dependencies:     Config/Battle, Config/Places, Config/DevAccess (+ sections other teams add), Core/Freeze,
	                  Core/TableUtil, Core/Result, Net/ErrorCodes.
	State:            One frozen table per section; the original sections are kept for resetOverrides().
	Validation:       applyOverrides only accepts numeric values for keys declared in the section's BOUNDS
	                  (min/max/integer). The whole patch is validated before anything changes (all-or-nothing).
	Error handling:   applyOverrides returns Result.err(INVALID_ARGS, "Battle.TICK_RATE: expected <= 60, got 90; ...").
	Performance notes: Overrides copy only the touched sections. Read `Config.<Section>.<KEY>` at use time (or after
	                  boot) — an override replaces the section table, so references cached before it go stale.

	Sections are pre-registered for every owning team (Battle, Combat, Spotting, Movement, Economy, Progression,
	Matchmaking, Bots, Audio, Vfx, Interface, Places, DevAccess): fill your own Config/<Section>.luau (plain table plus
	an optional BOUNDS table of overridable keys -> { min, max, integer }). Content data lives in Config/Content and is
	indexed by Config/ContentRegistry, not here. A brand-new section must be added to SECTIONS and the Config table.
]]

local Freeze = require("@game/ReplicatedStorage/Shared/Core/Freeze")
local TableUtil = require("@game/ReplicatedStorage/Shared/Core/TableUtil")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")

local Battle = require("@self/Battle")
local Combat = require("@self/Combat")
local Spotting = require("@self/Spotting")
local Movement = require("@self/Movement")
local Economy = require("@self/Economy")
local Progression = require("@self/Progression")
local Matchmaking = require("@self/Matchmaking")
local Bots = require("@self/Bots")
local Audio = require("@self/Audio")
local Vfx = require("@self/Vfx")
local Interface = require("@self/Interface")
local Places = require("@self/Places")
local DevAccess = require("@self/DevAccess")

export type Bound = { min: number?, max: number?, integer: boolean? }
export type OverridePatch = { [string]: { [string]: any } }

local Config = {
	Battle = Freeze.deep(Battle),
	Combat = Freeze.deep(Combat),
	Spotting = Freeze.deep(Spotting),
	Movement = Freeze.deep(Movement),
	Economy = Freeze.deep(Economy),
	Progression = Freeze.deep(Progression),
	Matchmaking = Freeze.deep(Matchmaking),
	Bots = Freeze.deep(Bots),
	Audio = Freeze.deep(Audio),
	Vfx = Freeze.deep(Vfx),
	Interface = Freeze.deep(Interface),
	Places = Freeze.deep(Places),
	DevAccess = Freeze.deep(DevAccess),
}

--- Section names in deterministic order. Add new sections here AND in the Config table above.
local SECTIONS: { string } = {
	"Audio",
	"Battle",
	"Bots",
	"Combat",
	"DevAccess",
	"Economy",
	"Interface",
	"Matchmaking",
	"Movement",
	"Places",
	"Progression",
	"Spotting",
	"Vfx",
}

local originals: { [string]: any } = {}
for _, name in SECTIONS do
	originals[name] = (Config :: any)[name]
end

local function boundsOf(section: any): { [string]: Bound }?
	if type(section) == "table" and type(section.BOUNDS) == "table" then
		return section.BOUNDS
	end
	return nil
end

local function splitPath(path: string): { string }
	local parts = {}
	for part in string.gmatch(path, "[^%.]+") do
		table.insert(parts, part)
	end
	return parts
end

local function readPath(root: any, parts: { string }): any
	local node = root
	for _, part in parts do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

local function checkBound(bound: Bound, value: any): string?
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return `expected a finite number, got {typeof(value)}`
	end
	if bound.integer and value ~= math.floor(value) then
		return `expected an integer, got {value}`
	end
	if bound.min ~= nil and value < bound.min then
		return `expected >= {bound.min}, got {value}`
	end
	if bound.max ~= nil and value > bound.max then
		return `expected <= {bound.max}, got {value}`
	end
	return nil
end

-- Flattens a nested patch table into ("A.B", value) leaves.
local function flatten(prefix: string, value: any, out: { { path: string, value: any } })
	-- An empty table is a leaf (and fails the numeric bound check) instead of silently overriding nothing.
	if type(value) == "table" and next(value) ~= nil then
		for _, key in TableUtil.sortedKeys(value) do
			local keyText = tostring(key)
			flatten(if prefix == "" then keyText else prefix .. "." .. keyText, value[key], out)
		end
	else
		table.insert(out, { path = prefix, value = value })
	end
end

--- Validates and applies live overrides, e.g. `{ Battle = { SNAPSHOT_RATE = 15 } }`.
--- Returns Ok(list of "Section.KEY" paths applied) or Err(INVALID_ARGS, detail) with nothing changed.
function Config.applyOverrides(patch: OverridePatch): Result.Result<{ string }>
	if type(patch) ~= "table" then
		return Result.err(ErrorCodes.INVALID_ARGS, "overrides must be a table")
	end
	local problems: { string } = {}
	local changes: { [string]: { { parts: { string }, value: number } } } = {}
	local applied: { string } = {}
	for _, sectionName in TableUtil.sortedKeys(patch) do
		local sectionPatch = patch[sectionName]
		local section = if type(sectionName) == "string" then (Config :: any)[sectionName] else nil
		local bounds = boundsOf(section)
		if bounds == nil or table.find(SECTIONS, sectionName) == nil then
			table.insert(problems, `{tostring(sectionName)}: section has no overridable keys`)
			continue
		end
		if type(sectionPatch) ~= "table" then
			table.insert(problems, `{sectionName}: expected a table of overrides`)
			continue
		end
		local leaves = {}
		for _, key in TableUtil.sortedKeys(sectionPatch) do
			flatten(tostring(key), sectionPatch[key], leaves)
		end
		for _, leaf in leaves do
			local fullPath = `{sectionName}.{leaf.path}`
			local bound = bounds[leaf.path]
			if bound == nil then
				table.insert(problems, `{fullPath}: not overridable (no BOUNDS entry)`)
				continue
			end
			local parts = splitPath(leaf.path)
			if type(readPath(section, parts)) ~= "number" then
				table.insert(problems, `{fullPath}: current value is not a number`)
				continue
			end
			local problem = checkBound(bound, leaf.value)
			if problem ~= nil then
				table.insert(problems, `{fullPath}: {problem}`)
				continue
			end
			local list = changes[sectionName]
			if list == nil then
				list = {}
				changes[sectionName] = list
			end
			table.insert(list, { parts = parts, value = leaf.value })
			table.insert(applied, fullPath)
		end
	end
	if #problems > 0 then
		return Result.err(ErrorCodes.INVALID_ARGS, table.concat(problems, "; "))
	end
	for sectionName, list in changes do
		local copy = TableUtil.deepCopy((Config :: any)[sectionName])
		for _, change in list do
			local node = copy
			for i = 1, #change.parts - 1 do
				node = node[change.parts[i]]
			end
			node[change.parts[#change.parts]] = change.value
		end
		(Config :: any)[sectionName] = Freeze.deep(copy)
	end
	table.sort(applied)
	return Result.ok(applied)
end

--- Restores every section to its shipped values.
function Config.resetOverrides()
	for _, name in SECTIONS do
		(Config :: any)[name] = originals[name]
	end
end

--- Problems with declared BOUNDS (default values outside their own bounds, bounds on non-numbers). Used by tests.
function Config.validateBounds(): { string }
	local problems = {}
	for _, sectionName in SECTIONS do
		local section = (Config :: any)[sectionName]
		local bounds = boundsOf(section)
		if bounds ~= nil then
			for _, path in TableUtil.sortedKeys(bounds) do
				local value = readPath(section, splitPath(path))
				local problem = checkBound(bounds[path], value)
				if problem ~= nil then
					table.insert(problems, `{sectionName}.{path}: default {problem}`)
				end
			end
		end
	end
	return problems
end

--- Section names (sorted).
function Config.sections(): { string }
	return table.clone(SECTIONS)
end

return Config
