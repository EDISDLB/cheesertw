--!strict
--[[
	Content/Classes — the five vehicle classes (00-DECISIONS §5, §6, §7.1; brand-art §6.6).

	Purpose:          Class identity (UI names, icons), class defaults that StatsCalculator falls back to (camo,
	                  view-range factor, after-shot bloom, terrain resistance) and the class multipliers vs the
	                  Medium baseline used by the balance lint.
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: exactly these five ids; every listed role exists and belongs to the class.
	Error handling:   N/A.
	Performance notes: Loaded once.
]]

local Content = require("../../Types/Content")

local classes: { Content.ClassDefinition } = {
	{
		id = "light",
		name = "Light tank",
		shortName = "LT",
		description = "Fast scouts that find the enemy, flank and finish damaged targets. Light armor; survive by staying unseen.",
		icon = "classes/light",
		minimapIcon = "minimap/class_light",
		order = 1,
		tiers = { min = 1, max = 11 },
		roles = { "light_scout", "light_support", "light_versatile" },
		baseline = {
			mul = {
				hp = 0.80,
				alpha = 0.85,
				penetration = 0.90,
				reload = 0.95,
				aimTime = 0.90,
				dispersion = 1.05,
				topSpeed = 1.20,
				specificPower = 1.6,
				hullTraverse = 1.18,
				turretTraverse = 1.15,
				hullArmor = 0.50,
			},
		},
		camo = { stationary = 0.18, moving = 0.18, net = 0.10 },
		viewRangeMul = 1.10,
		afterShotBloom = 3.0,
		terrainResistance = { hard = 0.8, medium = 1.0, soft = 1.7 },
		signalRangeM = 700,
	},
	{
		id = "medium",
		name = "Medium tank",
		shortName = "MT",
		description = "All-rounders that trade at mid range, rotate between flanks and hold ridges with accurate, fast-firing guns.",
		icon = "classes/medium",
		minimapIcon = "minimap/class_medium",
		order = 2,
		tiers = { min = 1, max = 11 },
		roles = { "medium_assault", "medium_sniper", "medium_support", "medium_versatile" },
		baseline = {},
		camo = { stationary = 0.12, moving = 0.07, net = 0.10 },
		viewRangeMul = 1.0,
		afterShotBloom = 3.0,
		terrainResistance = { hard = 0.9, medium = 1.1, soft = 1.9 },
		signalRangeM = 600,
	},
	{
		id = "heavy",
		name = "Heavy tank",
		shortName = "HT",
		description = "The front line. Thick armor and big guns that push chokepoints and absorb fire for the team.",
		icon = "classes/heavy",
		minimapIcon = "minimap/class_heavy",
		order = 3,
		tiers = { min = 3, max = 11 },
		roles = { "heavy_assault", "heavy_breakthrough", "heavy_support", "heavy_versatile" },
		baseline = {
			mul = {
				hp = 1.20,
				alpha = 1.25,
				penetration = 1.03,
				reload = 1.27,
				aimTime = 1.20,
				dispersion = 1.05,
				topSpeed = 0.72,
				specificPower = 0.77,
				hullTraverse = 0.60,
				turretTraverse = 0.65,
				hullArmor = 1.60,
			},
		},
		camo = { stationary = 0.05, moving = 0.025, net = 0.05 },
		viewRangeMul = 0.95,
		afterShotBloom = 3.5,
		terrainResistance = { hard = 1.1, medium = 1.3, soft = 2.3 },
		signalRangeM = 600,
	},
	{
		id = "td",
		name = "Tank destroyer",
		shortName = "TD",
		description = "Ambushers with the hardest-hitting guns. Most have a fixed casemate, so position decides everything.",
		icon = "classes/td",
		minimapIcon = "minimap/class_td",
		order = 4,
		tiers = { min = 2, max = 11 },
		roles = { "td_assault", "td_sniper", "td_support", "td_versatile" },
		baseline = {
			mul = {
				hp = 0.85,
				alpha = 1.50,
				penetration = 1.18,
				reload = 1.45,
				aimTime = 1.05,
				dispersion = 0.92,
				topSpeed = 0.80,
				specificPower = 0.80,
				hullTraverse = 0.67,
				turretTraverse = 0.50,
				hullArmor = 1.1,
			},
		},
		camo = { stationary = 0.18, moving = 0.11, net = 0.15 },
		camoCasemate = { stationary = 0.28, moving = 0.16, net = 0.15 },
		viewRangeMul = 0.95,
		afterShotBloom = 3.0,
		terrainResistance = { hard = 1.0, medium = 1.2, soft = 2.1 },
		signalRangeM = 600,
	},
	{
		id = "artillery",
		name = "Artillery",
		shortName = "SPG",
		description = "Indirect fire that stuns and softens targets spotted by the team. Fragile, slow to aim and revealed when it fires.",
		icon = "classes/artillery",
		minimapIcon = "minimap/class_artillery",
		order = 5,
		tiers = { min = 4, max = 10 },
		roles = { "artillery_support", "artillery_area_control" },
		baseline = {
			mul = {
				hp = 0.30,
				alpha = 2.0,
				penetration = 0.25,
				reload = 4.0,
				aimTime = 2.3,
				dispersion = 1.75,
				topSpeed = 0.75,
				specificPower = 0.80,
				hullTraverse = 0.55,
				hullArmor = 0.6,
			},
		},
		camo = { stationary = 0.10, moving = 0.05, net = 0.05 },
		viewRangeMul = 0.85,
		afterShotBloom = 4.0,
		terrainResistance = { hard = 1.0, medium = 1.2, soft = 2.1 },
		signalRangeM = 600,
	},
}

return classes
