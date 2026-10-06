--!strict
--[[
	Content/Turrets/IronUnion — Iron Union turrets (exemplar line: roster.md §2.1 Foundry trunk, I–III).

	Purpose:          Turret modules: armor, traverse, view range, HP bonus, mountable guns and the turret's own
	                  visual (mounting the upgraded turret changes the model and the armor model).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry).
	Validation:       ContentRegistry: guns exist and are guns, mount/yaw rules, sanity ranges.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Turret view range is the BASE value (before the class factor, crew curve and equipment). Iron Union kit: turret
	armor ×1.10. Builder preset iu_foundry: low faceted domes, heavy block mantlets, NO bustle (so Iron Union ammo
	racks sit in the hull). The Bulmal's upgraded dome is the line's first turret that bounces same-tier standard
	rounds (62 mm at 25° ≈ 1.05 × P(III)), and it is the only turret that fits the 76 mm (top gun requires the top
	turret, 03-R4).
]]

local Content = require("../../../Types/Content")

local turrets: { Content.TurretDefinition } = {
	{
		id = "iu_turret_kolmal",
		kind = "Turret",
		name = "Kolmal faceted dome",
		tier = 1,
		massKg = 1100,
		priceCredits = 0,
		researchXp = 0,
		mount = "Turret",
		armor = { front = 28, side = 18, rear = 15, roof = 10, mantlet = 30, cupola = 10 },
		traverseDegS = 38,
		viewRangeM = 300,
		hpBonus = 0,
		guns = { "iu_gun_37mm", "iu_gun_45mm" },
		visual = {
			style = "FacetedDome",
			lengthM = 1.5,
			widthM = 1.4,
			heightM = 0.65,
			frontAngleDeg = 20,
			sideAngleDeg = 15,
			cupola = true,
		},
	},
	{
		id = "iu_turret_ostmal",
		kind = "Turret",
		name = "Ostmal riveted turret",
		tier = 2,
		massKg = 1600,
		priceCredits = 0,
		researchXp = 0,
		mount = "Turret",
		armor = { front = 38, side = 22, rear = 18, roof = 12, mantlet = 40, cupola = 12 },
		traverseDegS = 40,
		viewRangeM = 310,
		hpBonus = 0,
		guns = { "iu_gun_45mm", "iu_gun_63mm" },
		visual = {
			style = "Box",
			lengthM = 1.9,
			widthM = 1.7,
			heightM = 0.75,
			frontAngleDeg = 10,
			sideAngleDeg = 10,
			cupola = true,
		},
	},
	{
		id = "iu_turret_bulmal_m1",
		kind = "Turret",
		name = "Bulmal riveted turret",
		tier = 3,
		massKg = 2100,
		priceCredits = 0,
		researchXp = 0,
		mount = "Turret",
		armor = { front = 42, side = 28, rear = 20, roof = 14, mantlet = 45, cupola = 14 },
		traverseDegS = 36,
		viewRangeM = 310,
		hpBonus = 0,
		guns = { "iu_gun_63mm" },
		visual = {
			style = "Box",
			lengthM = 2.1,
			widthM = 1.9,
			heightM = 0.8,
			frontAngleDeg = 10,
			sideAngleDeg = 10,
			cupola = true,
		},
	},
	{
		id = "iu_turret_bulmal_m2",
		kind = "Turret",
		name = "Bulmal cast dome",
		tier = 3,
		massKg = 2700,
		priceCredits = 6000,
		researchXp = 140,
		mount = "Turret",
		armor = { front = 62, side = 32, rear = 22, roof = 16, mantlet = 70, cupola = 16 },
		traverseDegS = 40,
		viewRangeM = 320,
		hpBonus = 20,
		guns = { "iu_gun_63mm", "iu_gun_76mm" },
		visual = {
			style = "FacetedDome",
			lengthM = 2.3,
			widthM = 2.1,
			heightM = 0.85,
			frontAngleDeg = 25,
			sideAngleDeg = 20,
			cupola = true,
		},
	},
}

return turrets
