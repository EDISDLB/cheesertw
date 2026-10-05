--!strict
--[[
	Content/Shells/IronUnion — ammunition for Iron Union guns (exemplar line, tiers I–III).

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
	-- 37 mm (IU-1 Forge stock) -------------------------------------------------------------------------------
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
		penetrationMm = 50,
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
		penetrationMm = 19,
		velocityMps = 456,
		explosionRadiusM = 0.37,
		priceCredits = 0,
	},
	-- 45 mm (IU-1 Forge top, IU-2 Anvil stock) ---------------------------------------------------------------
	{
		id = "iu_45mm_ap",
		name = "AP-T 45",
		kind = "AP",
		special = false,
		caliberMm = 45,
		damage = 47,
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
		damage = 47,
		penetrationMm = 59,
		velocityMps = 570,
		priceCredits = 125,
	},
	{
		id = "iu_45mm_he",
		name = "HE-F 45",
		kind = "HE",
		special = false,
		caliberMm = 45,
		damage = 61,
		penetrationMm = 23,
		velocityMps = 456,
		explosionRadiusM = 0.45,
		priceCredits = 50,
	},
	-- 57 mm (IU-2 Anvil top, IU-3 Bastion stock) -------------------------------------------------------------
	{
		id = "iu_57mm_ap",
		name = "AP-T 57",
		kind = "AP",
		special = false,
		caliberMm = 57,
		damage = 55,
		penetrationMm = 55,
		velocityMps = 510,
		priceCredits = 50,
	},
	{
		id = "iu_57mm_apcr",
		name = "HVAP 57",
		kind = "APCR",
		special = true,
		caliberMm = 57,
		damage = 55,
		penetrationMm = 72,
		velocityMps = 638,
		priceCredits = 125,
	},
	{
		id = "iu_57mm_he",
		name = "HE-F 57",
		kind = "HE",
		special = false,
		caliberMm = 57,
		damage = 72,
		penetrationMm = 29,
		velocityMps = 510,
		explosionRadiusM = 0.57,
		priceCredits = 50,
	},
	-- 76 mm (IU-3 Bastion top) --------------------------------------------------------------------------------
	{
		id = "iu_76mm_ap",
		name = "AP-T 76",
		kind = "AP",
		special = false,
		caliberMm = 76,
		damage = 82,
		penetrationMm = 67,
		velocityMps = 408,
		priceCredits = 100,
	},
	{
		id = "iu_76mm_apcr",
		name = "HVAP 76",
		kind = "APCR",
		special = true,
		caliberMm = 76,
		damage = 82,
		penetrationMm = 87,
		velocityMps = 510,
		priceCredits = 250,
	},
	{
		id = "iu_76mm_he",
		name = "HE-F 76",
		kind = "HE",
		special = false,
		caliberMm = 76,
		damage = 107,
		penetrationMm = 38,
		velocityMps = 408,
		explosionRadiusM = 0.76,
		priceCredits = 100,
	},
}

return shells
