--!strict
--[[
	Icons/Sets/Tiers — tier data plates I–XI (brand-art §6.6).

	Purpose:          A chamfered "data plate" whose material escalates with the tier band — steel (I–III), bronze
	                  with side notches (IV–VI), silver with a crest tab and two rivets (VII–VIII), gold, narrower,
	                  with crest and side fins (IX–X) — and an engraved (ink) roman numeral. Tier XI: obsidian plate,
	                  dusk inner rim, dusk crest and keel point, raised gold numerals (the only tier that glows).
	                  Numerals are real text in a plate (not placeholder text).
	Dependencies:     Icons/Glyph, Kit/Theme, Kit/Format.
	State:            None (builder table).
	Validation:       Keys tiers/tier_01..tier_11 (FallbackKeys).
	Error handling:   N/A.
	Performance notes: 8–20 primitives per plate.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")
local Format = require("../../Kit/Format")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

local function bandOf(tier: number): string
	if tier <= 3 then
		return "steel"
	elseif tier <= 6 then
		return "bronze"
	elseif tier <= 8 then
		return "silver"
	elseif tier <= 10 then
		return "gold"
	end
	return "obsidian"
end

local function plate(tier: number): (Canvas, Palette) -> ()
	return function(c: Canvas, _p: Palette)
		local band = bandOf(tier)
		local material = Theme.material(band)
		local ink = Theme.ink
		local narrow = band == "gold"
		local x, w = if narrow then 12 else 8, if narrow then 40 else 48
		local y, h = 16, 34
		if band == "silver" or band == "gold" or band == "obsidian" then
			-- Crest tab on top.
			Glyph.chamferRect(
				c,
				24,
				8,
				16,
				10,
				3,
				if band == "obsidian" then Theme.peekColor("accent.dusk") else material.base,
				"top"
			)
			if band == "silver" then
				Glyph.circle(c, 28.5, 13, 1.6, ink)
				Glyph.circle(c, 35.5, 13, 1.6, ink)
			end
		end
		if band == "gold" then
			-- Side fins.
			Glyph.triangle(c, 4, 26, 8, "tr", material.shade)
			Glyph.triangle(c, 52, 26, 8, "tl", material.shade)
		end
		Glyph.chamferRect(c, x - 2, y - 2, w + 4, h + 4, 7, ink, "all")
		Glyph.chamferRect(c, x, y, w, h, 6, material.base, "all")
		Glyph.rect(c, x + 6, y + 1.5, w - 12, 2, material.highlight, { name = "BevelHi" })
		Glyph.rect(c, x + 6, y + h - 3.5, w - 12, 2, material.shade, { name = "BevelLo" })
		if band == "bronze" then
			Glyph.rect(c, x - 1, y + h / 2 - 3, 4, 6, ink, { name = "NotchL" })
			Glyph.rect(c, x + w - 3, y + h / 2 - 3, 4, 6, ink, { name = "NotchR" })
		end
		if band == "obsidian" then
			-- Dusk inner rim and keel point.
			Glyph.chamferRect(c, x + 3, y + 3, w - 6, 1.5, 0.5, Theme.peekColor("accent.dusk"), "all")
			Glyph.chamferRect(c, x + 3, y + h - 4.5, w - 6, 1.5, 0.5, Theme.peekColor("accent.dusk"), "all")
			Glyph.wedge(c, 32, 56, 5, "down", Theme.peekColor("accent.dusk"))
		end
		local numeral = Format.roman(tier)
		local textHeight = if #numeral >= 4 then 22 elseif #numeral == 3 then 25 else 28
		local textColor = if band == "obsidian" then Theme.material("gold").base else ink
		Glyph.text(c, numeral, 32, y + h / 2 + 0.5, textHeight, textColor, "num.l")
	end
end

local Tiers: { [string]: Entry } = {}
for tier = 1, 11 do
	Tiers[string.format("tiers/tier_%02d", tier)] = { build = plate(tier), material = bandOf(tier) }
end

return Tiers
