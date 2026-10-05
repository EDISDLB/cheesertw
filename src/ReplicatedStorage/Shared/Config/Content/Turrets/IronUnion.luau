--!strict
--[[
	Content/Turrets/IronUnion — Iron Union turrets (exemplar line, tiers I–III).

	Purpose:          Turret modules: armor, traverse, view range, HP bonus, mountable guns and the turret's own
	                  visual (mounting the upgraded turret changes the model and the armor model).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: guns exist and are guns, mount/yaw rules, sanity ranges.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Turret view range is the BASE value (before the class factor, crew curve and equipment). Iron Union kit: turret
	armor ×1.10. The Bastion's upgraded turret only fits the 76 mm (top gun requires the top turret, 03-R4) and
	carries a thinner cupola: the classic weak spot of an otherwise strong face.
]]

local Content = require("../../../Types/Content")

local turrets: { Content.TurretDefinition } = {
	{
		id = "iu_turret_forge",
		kind = "Turret",
		name = "Forge welded turret",
		tier = 1,
		massKg = 1300,
		priceCredits = 0,
		researchXp = 0,
		mount = "Turret",
		armor = { front = 28, side = 20, rear = 15, roof = 10, mantlet = 30, cupola = 10 },
		traverseDegS = 40,
		viewRangeM = 300,
		hpBonus = 0,
		guns = { "iu_gun_37mm", "iu_gun_45mm" },
		visual = {
			style = "Welded",
			lengthM = 1.9,
			widthM = 1.6,
			heightM = 0.75,
			bustleLengthM = 0.3,
			frontAngleDeg = 15,
			sideAngleDeg = 10,
			cupola = true,
		},
	},
	{
		id = "iu_turret_anvil",
		kind = "Turret",
		name = "Anvil cast turret",
		tier = 2,
		massKg = 1700,
		priceCredits = 0,
		researchXp = 0,
		mount = "Turret",
		armor = { front = 38, side = 25, rear = 18, roof = 12, mantlet = 40, cupola = 12 },
		traverseDegS = 40,
		viewRangeM = 310,
		hpBonus = 0,
		guns = { "iu_gun_45mm", "iu_gun_57mm" },
		visual = {
			style = "Cast",
			lengthM = 2.1,
			widthM = 1.8,
			heightM = 0.8,
			bustleLengthM = 0.35,
			frontAngleDeg = 20,
			sideAngleDeg = 15,
			cupola = true,
		},
	},
	{
		id = "iu_turret_bastion_m1",
		kind = "Turret",
		name = "Bastion turret, early pattern",
		tier = 3,
		massKg = 3200,
		priceCredits = 0,
		researchXp = 0,
		mount = "Turret",
		armor = { front = 60, side = 35, rear = 25, roof = 15, mantlet = 65, cupola = 15 },
		traverseDegS = 24,
		viewRangeM = 310,
		hpBonus = 0,
		guns = { "iu_gun_57mm" },
		visual = {
			style = "Cast",
			lengthM = 2.4,
			widthM = 2.1,
			heightM = 0.95,
			bustleLengthM = 0.4,
			frontAngleDeg = 10,
			sideAngleDeg = 12,
			cupola = true,
		},
	},
	{
		id = "iu_turret_bastion_m2",
		kind = "Turret",
		name = "Bastion turret, heavy pattern",
		tier = 3,
		massKg = 3900,
		priceCredits = 6000,
		researchXp = 140,
		mount = "Turret",
		armor = { front = 72, side = 40, rear = 28, roof = 18, mantlet = 80, cupola = 20 },
		traverseDegS = 26,
		viewRangeM = 320,
		hpBonus = 30,
		guns = { "iu_gun_57mm", "iu_gun_76mm" },
		visual = {
			style = "Cast",
			lengthM = 2.6,
			widthM = 2.2,
			heightM = 1.0,
			bustleLengthM = 0.6,
			frontAngleDeg = 15,
			sideAngleDeg = 12,
			cupola = true,
		},
	},
}

return turrets
