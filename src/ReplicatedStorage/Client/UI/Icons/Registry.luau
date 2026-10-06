--!strict
--[[
	Icons/Registry — icon key -> glyph builder (all fallback sets) plus the generic category badge.

	Purpose:          Merges the glyph sets (classes, minimap, tiers, currency, ammo, modules, crew, battle — hit
	                  results, pings, commands, HUD alerts, minimap markers — and UI) into one table keyed exactly like
	                  the uploaded assets ("<folder>/<file stem>", e.g. "battle/hit_ricochet") and lets feature code
	                  register more glyphs at runtime.
	Dependencies:     Icons/Sets/*.
	State:            Module-level entry table (built at require; register() adds to it).
	Validation:       register rejects malformed keys and entries without a build function; duplicates raise.
	Error handling:   Raises on invalid registrations (programming errors).
	Performance notes: Table lookups only.
]]

local Glyph = require("./Glyph")
local Classes = require("./Sets/Classes")
local Tiers = require("./Sets/Tiers")
local Currency = require("./Sets/Currency")
local Ammo = require("./Sets/Ammo")
local Modules = require("./Sets/Modules")
local Combat = require("./Sets/Combat")
local Ui = require("./Sets/Ui")

export type Entry = {
	build: (c: Glyph.Canvas, p: Glyph.Palette) -> (),
	--- Default tint token for monochrome glyphs.
	color: string?,
	--- Icon material (brand-art §3.8) for multi-tone glyphs (ignored when the caller passes a colour).
	material: string?,
}

local Registry = {}

local entries: { [string]: Entry } = {}

local function merge(set: { [string]: any })
	for key, entry in set do
		if entries[key] ~= nil then
			error(`Icons.Registry: duplicate glyph key "{key}"`)
		end
		entries[key] = entry
	end
end

merge(Classes)
merge(Tiers)
merge(Currency)
merge(Ammo)
merge(Modules)
merge(Combat)
merge(Ui.entries)

--- The generic category badge drawn for keys without a dedicated glyph.
Registry.badge = Ui.badge :: Entry

--- Badge tint per category (token names).
Registry.CATEGORY_COLORS = table.freeze({
	battle = "text.primary",
	markers = "text.primary",
	equipment = "accent.steel",
	consumables = "state.success",
	factions = "brand.khaki",
	ranks = "brand.olive",
	ui = "text.secondary",
	achievements = "rarity.legendary",
	missions = "accent.dusk",
	medals = "rarity.legendary",
	maps = "brand.khaki",
	store = "currency.bullion",
	misc = "text.secondary",
})

function Registry.get(key: string): Entry?
	return entries[key]
end

function Registry.has(key: string): boolean
	return entries[key] ~= nil
end

--- All glyph keys, sorted.
function Registry.keys(): { string }
	local keys = {}
	for key in entries do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

--- Adds a glyph (feature-specific icons). Keys follow the asset key format.
function Registry.register(key: string, entry: Entry)
	if type(key) ~= "string" or not string.match(key, "^[a-z0-9_]+/[a-z0-9_/]+$") then
		error(`Icons.Registry.register: malformed key "{tostring(key)}"`, 2)
	end
	if type(entry) ~= "table" or type(entry.build) ~= "function" then
		error(`Icons.Registry.register: "{key}" needs a build function`, 2)
	end
	if entries[key] ~= nil then
		error(`Icons.Registry.register: "{key}" already exists`, 2)
	end
	entries[key] = entry
end

return Registry
