--!strict
--[[
	Content/Store — Store catalogue: Bullion packs (developer products), Premium Time, premium vehicles, bundles, cosmetics. Fixed grants only; no paid random items (00-DECISIONS §15).

	Purpose:          Registry consumed through ContentRegistry (no direct requires from gameplay code).
	Dependencies:     Types/Content.
	State:            Data only (deep-frozen by ContentRegistry). Empty but valid until the content team fills it.
	Validation:       ContentRegistry: exactly one of price/robux, grants reference existing content, Bullion packs are developer products, windows ordered.
	Error handling:   N/A.
	Performance notes: Loaded once.

	Example entry (see docs/design/content-schema.md for every field):
	  { id = "bullion_pack_s", name = "Bullion, small pack", description = "250 Bullion.", kind = "BullionPack",
	  robux = { kind = "DeveloperProduct", productId = 0 }, grants = { { kind = "Bullion", amount = 250 } } }
]]

local Content = require("../../Types/Content")

local store: { Content.StoreItem } = {}

return store
