--!strict
--[[
	Content/Customization — Cosmetics: paints, camouflages, emblems, inscriptions, styles, gun sleeves and stat trackers.

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: kind/rarity/source enums, scope references, colours are Color3.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  { id = "paint_foundry_red", name = "Foundry Red", icon = "customization/paint", kind = "Paint",
	  rarity = "uncommon", colors = { Color3.fromHex("#8A3B26") }, camoBonus = true,
	  scope = { factions = { "iron_union" } }, source = "Store", price = { credits = 50000 } }
]]

local Content = require("../../Types/Content")

local customization: { Content.CustomizationDefinition } = {}

return customization
