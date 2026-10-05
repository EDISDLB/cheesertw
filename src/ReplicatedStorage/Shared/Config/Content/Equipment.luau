--!strict
--[[
	Content/Equipment — Equipment items (00-DECISIONS §13): categories, tier bands, exclusive groups, StatModifier effects and the optional explicit category-slot values.

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: categories/effects use valid enums and StatKeys, tier bands inside 1..11, exclusive group set, never Bullion-only prices.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  Rammer Assist (Firepower, II–IV, "rammer_assist_c") would be authored as
	  { id = "rammer_assist_c", name = "Rammer Assist", description = "Reload −10 %.", icon = "equipment/rammer",
	    categories = { "Firepower" }, grade = "Standard", tiers = { min = 2, max = 4 }, exclusiveGroup = "rammer",
	    effects = { { stat = "reloadTime", op = "mul", value = 0.90 } },
	    categorySlotEffects = { { stat = "reloadTime", op = "mul", value = 0.885 } },
	    compatibility = { excludeReload = { "Magazine" } }, price = { credits = 25000 } }
]]

local Content = require("../../Types/Content")

local equipment: { Content.EquipmentDefinition } = {}

return equipment
