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
	secondaries and text tints are the brand tokens; vehicle paints are muted field colours chosen to read on every
	biome while keeping one faction accent.
]]

local Content = require("../../Types/Content")

local factions: { Content.FactionDefinition } = {
	{
		id = "iron_union",
		name = "Iron Union",
		shortName = "IU",
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
			base = Color3.fromHex("#5A5A48"),
			secondary = Color3.fromHex("#3E3F36"),
			accent = Color3.fromHex("#B8492A"),
			camo = { Color3.fromHex("#5A5A48"), Color3.fromHex("#6E5B44"), Color3.fromHex("#3B3A31") },
		},
		kit = {
			mul = { alpha = 1.10, reload = 1.10, turretArmor = 1.10, dispersion = 1.06, aimTime = 1.05 },
			depressionDeg = 5,
		},
		signatures = { "DualGun" },
	},
	{
		id = "crown_industries",
		name = "Crown Industries",
		shortName = "CI",
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
			base = Color3.fromHex("#5C6355"),
			secondary = Color3.fromHex("#43483D"),
			accent = Color3.fromHex("#D6AA4E"),
			camo = { Color3.fromHex("#5C6355"), Color3.fromHex("#7A715B"), Color3.fromHex("#3D4237") },
		},
		kit = {
			mul = { dispersion = 0.93, aimTime = 0.94, alpha = 0.92, reload = 0.92 },
			depressionDeg = 10,
		},
		signatures = { "HESH" },
	},
	{
		id = "eastern_armor",
		name = "Eastern Armor Group",
		shortName = "EAG",
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
			base = Color3.fromHex("#4F5D57"),
			secondary = Color3.fromHex("#36403C"),
			accent = Color3.fromHex("#1C8582"),
			camo = { Color3.fromHex("#4F5D57"), Color3.fromHex("#6B6A55"), Color3.fromHex("#2F3833") },
		},
		kit = {
			mul = { specificPower = 1.10, topSpeed = 1.06, turretArmor = 0.80 },
		},
		signatures = { "Magazine", "Wheeled" },
	},
	{
		id = "desert_corps",
		name = "Desert Armor Corps",
		shortName = "DAC",
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
			base = Color3.fromHex("#B39A6E"),
			secondary = Color3.fromHex("#8C744E"),
			accent = Color3.fromHex("#C8933A"),
			camo = { Color3.fromHex("#B39A6E"), Color3.fromHex("#8C744E"), Color3.fromHex("#6E5A3E") },
		},
		kit = {
			mul = { aimTime = 0.94, reload = 0.95, turretArmor = 1.08, lowerPlateArmor = 0.85 },
			depressionDeg = 10,
		},
		signatures = { "Autoreloader" },
	},
	{
		id = "mountain_republic",
		name = "Mountain Republic",
		shortName = "MR",
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
			base = Color3.fromHex("#56664F"),
			secondary = Color3.fromHex("#3B4637"),
			accent = Color3.fromHex("#3C7650"),
			camo = { Color3.fromHex("#56664F"), Color3.fromHex("#7D8070"), Color3.fromHex("#2F382B") },
		},
		kit = {
			mul = { topSpeed = 1.15, hullArmor = 0.60 },
			depressionDeg = 12,
		},
		signatures = { "SiegeMode", "Hydropneumatic" },
	},
	{
		id = "northern_federation",
		name = "Northern Federation",
		shortName = "NF",
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
			base = Color3.fromHex("#7D8A90"),
			secondary = Color3.fromHex("#5B676D"),
			accent = Color3.fromHex("#4F8FCB"),
			camo = { Color3.fromHex("#E3E8EA"), Color3.fromHex("#7D8A90"), Color3.fromHex("#4A555B") },
		},
		kit = {
			mul = { hp = 1.05, hullArmor = 1.06, dispersion = 0.94, specificPower = 0.94 },
		},
		signatures = { "AssaultTD" },
	},
}

return factions
