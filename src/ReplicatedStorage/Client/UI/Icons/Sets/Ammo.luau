--!strict
--[[
	Icons/Sets/Ammo — shell types (brand-art §10.1 colours: ammo.* tokens).

	Purpose:          Upright shells that differ by nose outline, not colour alone: AP pointed ogive, APCR thin dart
	                  with a sabot band, HEAT blunt nose with a standoff spike, HE rounded nose, HESH flat squash head.
	                  "_special" variants (premium rounds) add the ammo.special gold driving band.
	Dependencies:     Icons/Glyph, Kit/Theme.
	State:            None (builder table).
	Validation:       Keys ammo/* (FallbackKeys).
	Error handling:   N/A.
	Performance notes: 6–10 primitives per shell.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

local function casing(c: Canvas, special: boolean)
	local brass = Theme.material("brass")
	Glyph.rect(c, 23, 33, 18, 25, Theme.ink)
	Glyph.rect(c, 24.5, 34, 15, 22.5, brass.base)
	Glyph.rect(c, 24.5, 34, 4, 22.5, brass.highlight, { name = "CasingHi" })
	Glyph.rect(c, 22, 54, 20, 4, brass.shade, { name = "Rim" })
	if special then
		Glyph.rect(c, 23, 30, 18, 4, Theme.peekColor("ammo.special"), { name = "SpecialBand" })
	end
end

local function shell(nose: (c: Canvas, p: Palette) -> ()): (boolean) -> (Canvas, Palette) -> ()
	return function(special: boolean)
		return function(c: Canvas, p: Palette)
			nose(c, p)
			casing(c, special)
		end
	end
end

local ap = shell(function(c: Canvas, p: Palette)
	Glyph.rect(c, 24.5, 20, 15, 14, p.fg)
	Glyph.wedge(c, 32, 12.5, 7.5, "up", p.fg)
end)

local apcr = shell(function(c: Canvas, p: Palette)
	Glyph.rect(c, 28, 14, 8, 20, p.fg)
	Glyph.wedge(c, 32, 9, 4, "up", p.fg)
	Glyph.rect(c, 23, 26, 18, 5, p.shade, { name = "Sabot" })
end)

local heat = shell(function(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 24.5, 16, 15, 18, 4, p.fg, "top")
	Glyph.rect(c, 30.5, 5, 3, 12, p.fg, { name = "Spike" })
	Glyph.circle(c, 32, 6, 2.5, p.fg)
end)

local he = shell(function(c: Canvas, p: Palette)
	Glyph.rect(c, 24.5, 21, 15, 13, p.fg)
	Glyph.circle(c, 32, 21, 7.5, p.fg)
end)

local hesh = shell(function(c: Canvas, p: Palette)
	Glyph.rect(c, 24.5, 22, 15, 12, p.fg)
	Glyph.chamferRect(c, 21, 13, 22, 10, 3, p.fg, "top")
	Glyph.rect(c, 21, 21, 22, 2, p.shade, { name = "SquashLine" })
end)

local Ammo: { [string]: Entry } = {
	["ammo/ap"] = { build = ap(false), color = "ammo.ap" },
	["ammo/ap_special"] = { build = ap(true), color = "ammo.ap" },
	["ammo/apcr"] = { build = apcr(false), color = "ammo.apcr" },
	["ammo/apcr_special"] = { build = apcr(true), color = "ammo.apcr" },
	["ammo/heat"] = { build = heat(false), color = "ammo.heat" },
	["ammo/heat_special"] = { build = heat(true), color = "ammo.heat" },
	["ammo/he"] = { build = he(false), color = "ammo.he" },
	["ammo/he_special"] = { build = he(true), color = "ammo.he" },
	["ammo/hesh"] = { build = hesh(false), color = "ammo.hesh" },
}

return Ammo
