--!strict
--[[
	Content/Shells/IronUnion — ammunition for Iron Union guns (exemplar line: roster.md §2.1 Foundry trunk, I–III).

	Purpose:          Shell definitions referenced by Guns/IronUnion (gun.shells lists ids from here).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: kinds, calibre = every gun that lists the shell, sanity ranges, HE fields.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Authoring defaults (00-DECISIONS §1): special pen = 1.30 × AP pen, same alpha; HE alpha = 1.30 × AP alpha,
	HE pen = calibre / 2; APCR velocity = 1.25 × AP; HE velocity = AP; in-game velocity = 0.6 × real. Prices: tier
	shell price (Tiers economy), special = 2.5 × standard. Iron Union kit: alpha × 1.10.
]]

local Content = require("../../../Types/Content")

local shells: { Content.ShellDefinition } = {
	-- 37 mm (IU-1 Kolmal stock: the quick gun) ----------------------------------------------------------------------
	{
		id = "iu_37mm_ap",
		name = "AP-T 37",
		kind = "AP",
		special = false,
		caliberMm = 37,
		damage = 40,
		penetrationMm = 38,
		velocityMps = 456,
		priceCredits = 0,
	},
	{
		id = "iu_37mm_apcr",
		name = "HVAP 37",
		kind = "APCR",
		special = true,
		caliberMm = 37,
		damage = 40,
		penetrationMm = 49,
		velocityMps = 570,
		priceCredits = 0,
	},
	{
		id = "iu_37mm_he",
		name = "HE-F 37",
		kind = "HE",
		special = false,
		caliberMm = 37,
		damage = 52,
		penetrationMm = 18,
		velocityMps = 456,
		explosionRadiusM = 0.37,
		priceCredits = 0,
	},
	-- 45 mm (IU-1 Kolmal top: the hard-hitting gun; IU-2 Ostmal stock) ----------------------------------------------
	{
		id = "iu_45mm_ap",
		name = "AP-T 45",
		kind = "AP",
		special = false,
		caliberMm = 45,
		damage = 50,
		penetrationMm = 45,
		velocityMps = 456,
		priceCredits = 50,
	},
	{
		id = "iu_45mm_apcr",
		name = "HVAP 45",
		kind = "APCR",
		special = true,
		caliberMm = 45,
		damage = 50,
		penetrationMm = 58,
		velocityMps = 570,
		priceCredits = 125,
	},
	{
		id = "iu_45mm_he",
		name = "HE-F 45",
		kind = "HE",
		special = false,
		caliberMm = 45,
		damage = 65,
		penetrationMm = 22,
		velocityMps = 456,
		explosionRadiusM = 0.45,
		priceCredits = 50,
	},
	-- 63 mm (IU-2 Ostmal top: short high-alpha gun; IU-3 Bulmal stock) ----------------------------------------------
	{
		id = "iu_63mm_ap",
		name = "AP-T 63",
		kind = "AP",
		special = false,
		caliberMm = 63,
		damage = 62,
		penetrationMm = 52,
		velocityMps = 420,
		priceCredits = 50,
	},
	{
		id = "iu_63mm_apcr",
		name = "HVAP 63",
		kind = "APCR",
		special = true,
		caliberMm = 63,
		damage = 62,
		penetrationMm = 68,
		velocityMps = 525,
		priceCredits = 125,
	},
	{
		id = "iu_63mm_he",
		name = "HE-F 63",
		kind = "HE",
		special = false,
		caliberMm = 63,
		damage = 81,
		penetrationMm = 32,
		velocityMps = 420,
		explosionRadiusM = 0.63,
		priceCredits = 50,
	},
	-- 76 mm (IU-3 Bulmal top) ---------------------------------------------------------------------------------------
	{
		id = "iu_76mm_ap",
		name = "AP-T 76",
		kind = "AP",
		special = false,
		caliberMm = 76,
		damage = 75,
		penetrationMm = 66,
		velocityMps = 408,
		priceCredits = 100,
	},
	{
		id = "iu_76mm_apcr",
		name = "HVAP 76",
		kind = "APCR",
		special = true,
		caliberMm = 76,
		damage = 75,
		penetrationMm = 86,
		velocityMps = 510,
		priceCredits = 250,
	},
	{
		id = "iu_76mm_he",
		name = "HE-F 76",
		kind = "HE",
		special = false,
		caliberMm = 76,
		damage = 98,
		penetrationMm = 38,
		velocityMps = 408,
		explosionRadiusM = 0.76,
		priceCredits = 100,
	},
}

return shells
