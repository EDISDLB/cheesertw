--!strict
--[[
	Content/Factions — the six locked HULLDOWN factions (00-DECISIONS §0, brand-art §3.7 / §6.6).

	Purpose:          Faction identity for UI (names, emblems, palette), the renderer (default vehicle paint) and the
	                  balance lint (faction kit, 00-DECISIONS §7.3).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: exactly these six ids, palettes are Color3, kit stats are BalanceStat keys.
	Error handling:   N/A.
	Performance notes: Loaded once.

	All six are fictional: no real nations, flags, insignia or conflicts (brand-art §1.1). Palette primaries,
	secondaries and text tints are the brand tokens (brand-art §3.7). Vehicle paints follow the roster bible's
	proposal (roster.md §1: field colour = base, trim metal = secondary, enamel band = accent), pending the brand
	owner's check_palette.py pass. idPrefix and builderPreset come from roster.md §0.2 / §1.x.
]]

local Content = require("../../Types/Content")

local factions: { Content.FactionDefinition } = {
	{
		id = "iron_union",
		name = "Iron Union",
		shortName = "IU",
		idPrefix = "iu",
		motto = "Forged to hold the line.",
		description = "A federation of foundry towns that builds heavy, hard-hitting machines in vast numbers. Iron Union crews trade finesse for thick turrets and guns that end arguments.",
		focus = { "Heavy armor", "High alpha damage", "Dual-gun heavies" },
		emblem = "factions/iron_union",
		order = 1,
		palette = {
			primary = Color3.fromHex("#B8492A"),
			secondary = Color3.fromHex("#59616A"),
			textTint = Color3.fromHex("#E07A55"),
		},
		vehiclePaint = {
			base = Color3.fromHex("#5B4C43"),
			secondary = Color3.fromHex("#59616A"),
			accent = Color3.fromHex("#B8492A"),
			camo = { Color3.fromHex("#5B4C43"), Color3.fromHex("#6E5B44"), Color3.fromHex("#3B3A31") },
		},
		kit = {
			mul = { alpha = 1.10, reload = 1.10, turretArmor = 1.10, dispersion = 1.06, aimTime = 1.05 },
			depressionDeg = 5,
		},
		signatures = { "DualGun" },
		builderPreset = "iu_foundry",
	},
	{
		id = "crown_industries",
		name = "Crown Industries",
		shortName = "CI",
		idPrefix = "ci",
		motto = "Measure twice. Fire once.",
		description = "A chartered manufacturing house famous for precise guns and fast-cycling breeches. Crown vehicles reward patient aim and good positions over brute force.",
		focus = { "Accurate guns", "Fast reloads", "HESH shells" },
		emblem = "factions/crown_industries",
		order = 2,
		palette = {
			primary = Color3.fromHex("#5A3D8C"),
			secondary = Color3.fromHex("#D6AA4E"),
			textTint = Color3.fromHex("#B79BE8"),
		},
		vehiclePaint = {
			base = Color3.fromHex("#4A4553"),
			secondary = Color3.fromHex("#D6AA4E"),
			accent = Color3.fromHex("#5A3D8C"),
			camo = { Color3.fromHex("#4A4553"), Color3.fromHex("#6A6158"), Color3.fromHex("#34313B") },
		},
		kit = {
			mul = { dispersion = 0.93, aimTime = 0.94, alpha = 0.92, reload = 0.92 },
			depressionDeg = 10,
		},
		signatures = { "HESH" },
		builderPreset = "ci_guild",
	},
	{
		id = "eastern_armor",
		name = "Eastern Armor Group",
		shortName = "EAG",
		idPrefix = "ea",
		motto = "Strike first. Strike fast.",
		description = "A consortium of light-industry yards that prizes speed and burst damage. Eastern machines arrive before the enemy is ready and leave before it can answer.",
		focus = { "Mobility", "Burst damage", "Magazine guns", "Wheeled scouts" },
		emblem = "factions/eastern_armor",
		order = 3,
		palette = {
			primary = Color3.fromHex("#1C8582"),
			secondary = Color3.fromHex("#E9DFC6"),
			textTint = Color3.fromHex("#4FC9C2"),
		},
		vehiclePaint = {
			base = Color3.fromHex("#3F5553"),
			secondary = Color3.fromHex("#E9DFC6"),
			accent = Color3.fromHex("#1C8582"),
			camo = { Color3.fromHex("#3F5553"), Color3.fromHex("#6B6A55"), Color3.fromHex("#2F3833") },
		},
		kit = {
			mul = { specificPower = 1.10, topSpeed = 1.06, turretArmor = 0.80 },
		},
		signatures = { "Magazine", "Wheeled" },
		builderPreset = "ea_windward",
	},
	{
		id = "desert_corps",
		name = "Desert Armor Corps",
		shortName = "DAC",
		idPrefix = "dc",
		motto = "The horizon is our cover.",
		description = "Long-range specialists raised on open sand and salt flats. Desert Corps crews fight from the ridge line with quick aim, good depression and self-loading guns.",
		focus = { "Long-range fire", "Gun depression", "Autoreloaders" },
		emblem = "factions/desert_corps",
		order = 4,
		palette = {
			primary = Color3.fromHex("#C8933A"),
			secondary = Color3.fromHex("#7A5530"),
			textTint = Color3.fromHex("#E8B868"),
		},
		vehiclePaint = {
			base = Color3.fromHex("#A38C63"),
			secondary = Color3.fromHex("#7A5530"),
			accent = Color3.fromHex("#C8933A"),
			camo = { Color3.fromHex("#A38C63"), Color3.fromHex("#8C744E"), Color3.fromHex("#6E5A3E") },
		},
		kit = {
			mul = { aimTime = 0.94, reload = 0.95, turretArmor = 1.08, lowerPlateArmor = 0.85 },
			depressionDeg = 10,
		},
		signatures = { "Autoreloader" },
		builderPreset = "dc_caravan",
	},
	{
		id = "mountain_republic",
		name = "Mountain Republic",
		shortName = "MR",
		idPrefix = "mr",
		motto = "Every slope is a fortress.",
		description = "An alpine federation whose engineers build light, agile hulls that use the terrain as armor. Mountain crews master hull-down play, siege positions and steep climbs.",
		focus = { "Terrain mobility", "Extreme depression", "Siege tank destroyers" },
		emblem = "factions/mountain_republic",
		order = 5,
		palette = {
			primary = Color3.fromHex("#3C7650"),
			secondary = Color3.fromHex("#F2F5F7"),
			textTint = Color3.fromHex("#74B98A"),
		},
		vehiclePaint = {
			base = Color3.fromHex("#495B4C"),
			secondary = Color3.fromHex("#F2F5F7"),
			accent = Color3.fromHex("#3C7650"),
			camo = { Color3.fromHex("#495B4C"), Color3.fromHex("#7D8070"), Color3.fromHex("#2F382B") },
		},
		kit = {
			mul = { topSpeed = 1.15, hullArmor = 0.60 },
			depressionDeg = 12,
		},
		signatures = { "SiegeMode", "Hydropneumatic" },
		builderPreset = "mr_highland",
	},
	{
		id = "northern_federation",
		name = "Northern Federation",
		shortName = "NF",
		idPrefix = "nf",
		motto = "Endure. Outlast. Prevail.",
		description = "Builders from the ice fields who design for survival first. Northern vehicles carry extra hit points and heavy hulls, and their assault tank destroyers break fortified lines.",
		focus = { "Survivability", "Heavy hulls", "Assault tank destroyers" },
		emblem = "factions/northern_federation",
		order = 6,
		palette = {
			primary = Color3.fromHex("#4F8FCB"),
			secondary = Color3.fromHex("#EEF6FC"),
			textTint = Color3.fromHex("#8EC3EE"),
		},
		vehiclePaint = {
			base = Color3.fromHex("#7D8A94"),
			secondary = Color3.fromHex("#EEF6FC"),
			accent = Color3.fromHex("#4F8FCB"),
			camo = { Color3.fromHex("#E3E8EA"), Color3.fromHex("#7D8A94"), Color3.fromHex("#4A555B") },
		},
		kit = {
			mul = { hp = 1.05, hullArmor = 1.06, dispersion = 0.94, specificPower = 0.94 },
		},
		signatures = { "AssaultTD" },
		builderPreset = "nf_rimeworks",
	},
}

return factions
