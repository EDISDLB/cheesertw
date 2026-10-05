--!strict
--[[
	Content/Consumables — Consumables (00-DECISIONS §13): repair kits, medkits, extinguishers, rations, fuel and event-only items.

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: Manual/Automatic items need a cooldown; effects use StatKeys; prices never Bullion-only below their credit price.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  A small repair kit: { id = "repair_kit", name = "Repair Kit", description = "Repairs all modules.",
	  icon = "consumables/repair_kit", kind = "RepairKit", activation = "Manual", cooldownS = 90,
	  repairs = { modules = true }, exclusiveGroup = "repair", price = { credits = 3000 } }
]]

local Content = require("../../Types/Content")

local consumables: { Content.ConsumableDefinition } = {}

return consumables
