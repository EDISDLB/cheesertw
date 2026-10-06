--!strict
--[[
	Icons/Sets/Currency — Credits, Bullion, Vehicle/Free/Crew XP and Campaign Tokens (brand-art §3.6).

	Purpose:          Credits = copper hex-nut token with a stencil C (never a coin); Bullion = tapered gold ingot with
	                  a stamped cartouche; XP = double chevrons (blue over a track run, violet in an open ring, teal
	                  over a padded helmet); Campaign Tokens = rose square counter with small corner chamfers and a
	                  pennant on a summit. Materials: two tones plus one highlight.
	Dependencies:     Icons/Glyph, Kit/Theme.
	State:            None (builder table).
	Validation:       Keys currency/* (FallbackKeys).
	Error handling:   N/A.
	Performance notes: 6–14 primitives per icon.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

local function credits(c: Canvas, p: Palette)
	Glyph.hexagon(c, 32, 32, 28, Theme.ink, true)
	Glyph.hexagon(c, 32, 32, 26, p.base, true)
	Glyph.hexagon(c, 32, 32, 20, p.shade, true)
	Glyph.hexagon(c, 32, 32, 18, p.highlight, true)
	Glyph.hexagon(c, 32, 32, 16.5, p.base, true)
	-- Stencil C: three bars with stencil gaps at the bends.
	Glyph.rect(c, 23, 25, 5, 14, p.shade, { name = "CStem" })
	Glyph.rect(c, 29.5, 21, 12, 5, p.shade, { name = "CTop" })
	Glyph.rect(c, 29.5, 38, 12, 5, p.shade, { name = "CBottom" })
end

local function bullion(c: Canvas, p: Palette)
	-- Front face trapezoid (45° ends), top face lighter, stamped ridge cartouche.
	Glyph.rect(c, 18, 33, 28, 15, Theme.ink)
	Glyph.triangle(c, 3, 33, 15, "br", Theme.ink)
	Glyph.triangle(c, 46, 33, 15, "bl", Theme.ink)
	Glyph.rect(c, 18, 35, 28, 12, p.base)
	Glyph.triangle(c, 6, 35, 12, "br", p.shade)
	Glyph.triangle(c, 46, 35, 12, "bl", p.shade)
	Glyph.chamferRect(c, 17, 22, 30, 13, 5, p.highlight, "top")
	Glyph.chamferRect(c, 26, 38, 12, 6, 2, p.shade, "all")
	Glyph.wedge(c, 32, 39, 3, "up", p.highlight)
end

local function doubleChevron(c: Canvas, p: Palette, top: number)
	Glyph.chevron(c, 32, top, 14, 6, p.base, "up")
	Glyph.chevron(c, 32, top + 12, 14, 6, p.base, "up")
end

local function vehicleXp(c: Canvas, p: Palette)
	doubleChevron(c, p, 10)
	Glyph.chamferRect(c, 12, 44, 40, 10, 4, p.shade, "all")
	for _, x in { 20, 32, 44 } do
		Glyph.circle(c, x, 49, 3, p.highlight)
	end
end

local function freeXp(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 34, 26, 4, p.shade)
	doubleChevron(c, p, 18)
end

local function crewXp(c: Canvas, p: Palette)
	doubleChevron(c, p, 8)
	Glyph.halfDisc(c, 32, 52, 16, "top", p.shade)
	Glyph.rect(c, 12, 50, 40, 5, p.base, { name = "Brim" })
	Glyph.box(c, 32, 44, 18, 3, p.highlight, { name = "Padding" })
end

local function campaignToken(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 8, 8, 48, 48, 6, Theme.ink, "all")
	Glyph.chamferRect(c, 10, 10, 44, 44, 5, p.base, "all")
	Glyph.rect(c, 15, 13, 34, 2, p.highlight, { name = "BevelHi" })
	-- Summit with a planted pennant.
	Glyph.wedge(c, 32, 26, 16, "up", p.shade)
	Glyph.rect(c, 31, 16, 2.5, 12, p.highlight, { name = "Pole" })
	Glyph.triangle(c, 33.5, 16, 8, "tl", p.highlight)
end

local Currency: { [string]: Entry } = {
	["currency/credits"] = { build = credits, material = "copper" },
	["currency/bullion"] = { build = bullion, material = "gold" },
	["currency/vehicle_xp"] = { build = vehicleXp, material = "xp_blue" },
	["currency/free_xp"] = { build = freeXp, material = "xp_violet" },
	["currency/crew_xp"] = { build = crewXp, material = "xp_teal" },
	["currency/campaign_token"] = { build = campaignToken, material = "rose" },
}

return Currency
