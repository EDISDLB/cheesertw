--!strict
--[[
	Content/Guns/IronUnion — Iron Union guns (exemplar line: roster.md §2.1 Foundry trunk, I–III). Guns are shared
	across vehicles: the 45 mm is the IU-1 Kolmal's top gun AND the IU-2 Ostmal's stock gun, the 63 mm is the
	Ostmal's top gun and the IU-3 Bulmal's stock gun (researched once, carried over).

	Purpose:          Gun modules referenced by turrets (turret.guns) and vehicles (vehicle.modules.guns).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: 1..3 existing shells of the same calibre (first = standard), reload model,
	                  sanity ranges, visual/audio enums.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Iron Union kit (00-DECISIONS §7.3): alpha ×1.10, reload ×1.10, dispersion ×1.06, aim ×1.05, depression 5°.
	Builder preset iu_foundry: short-to-medium thick barrels; the double-baffle brake ("Double") appears on the
	Ostmal's stubby 63 mm (roster.md §2.1). Stock guns sit ≈ 1/1.2 of the top gun's pen (03-R4).
]]

local Content = require("../../../Types/Content")

local guns: { Content.GunDefinition } = {
	{
		id = "iu_gun_37mm",
		kind = "Gun",
		name = "37 mm L/46 Spark",
		tier = 1,
		massKg = 350,
		priceCredits = 0,
		researchXp = 0,
		caliberMm = 37,
		shells = { "iu_37mm_ap", "iu_37mm_apcr", "iu_37mm_he" },
		reload = { kind = "Single", reloadS = 1.9 },
		dispersionM100 = 0.54,
		aimTimeS = 2.1,
		arcs = { depressionDeg = 5, elevationDeg = 20 },
		ammoCapacity = 120,
		visual = { barrelLengthM = 1.6, muzzleBrake = "None", mantlet = "Box" },
		audio = "small_20_45mm",
	},
	{
		id = "iu_gun_45mm",
		kind = "Gun",
		name = "45 mm L/40 Rivet",
		tier = 1,
		massKg = 520,
		priceCredits = 1000,
		researchXp = 100,
		caliberMm = 45,
		shells = { "iu_45mm_ap", "iu_45mm_apcr", "iu_45mm_he" },
		reload = { kind = "Single", reloadS = 2.4 },
		dispersionM100 = 0.52,
		aimTimeS = 2.1,
		arcs = { depressionDeg = 5, elevationDeg = 20 },
		ammoCapacity = 100,
		visual = { barrelLengthM = 1.8, muzzleBrake = "None", mantlet = "Box" },
		audio = "small_20_45mm",
	},
	{
		id = "iu_gun_63mm",
		kind = "Gun",
		name = "63 mm L/30 Stub",
		tier = 2,
		massKg = 780,
		priceCredits = 2100,
		researchXp = 160,
		caliberMm = 63,
		shells = { "iu_63mm_ap", "iu_63mm_apcr", "iu_63mm_he" },
		reload = { kind = "Single", reloadS = 2.9 },
		dispersionM100 = 0.52,
		aimTimeS = 2.1,
		arcs = { depressionDeg = 5, elevationDeg = 18 },
		ammoCapacity = 80,
		visual = { barrelLengthM = 1.9, muzzleBrake = "Double", mantlet = "Box" },
		audio = "medium_50_85mm",
	},
	{
		id = "iu_gun_76mm",
		kind = "Gun",
		name = "76 mm L/41 Breaker",
		tier = 3,
		massKg = 1150,
		priceCredits = 6000,
		researchXp = 160,
		caliberMm = 76,
		shells = { "iu_76mm_ap", "iu_76mm_apcr", "iu_76mm_he" },
		reload = { kind = "Single", reloadS = 3.0 },
		dispersionM100 = 0.50,
		aimTimeS = 2.2,
		arcs = { depressionDeg = 5, elevationDeg = 20 },
		ammoCapacity = 70,
		visual = { barrelLengthM = 3.1, muzzleBrake = "Double", mantlet = "Cast", mantletWidthM = 0.9 },
		audio = "medium_50_85mm",
	},
}

return guns
