--!strict
--[[
	Icons/Sets/Ammo — shell types (brand-art §6.9 silhouettes, §6.10 special treatment, §3.9 `ammo.*` paint).

	Purpose:          Upright rounds on one shared base line, told apart by the NOSE silhouette (colour only
	                  confirms it): AP = full calibre, long sharp ogive; APCR = short sabot collar with a thin stepped
	                  penetrator needle and a small tip; HE = short blunt ogive cut flat for a protruding steel fuze;
	                  HEAT = straight cone shoulder plus a thin stand-off probe with a crown; HESH = the shortest round,
	                  a wide blunt squash dome on an olive body with an HE band. Standard cases are lacquered
	                  gunmetal; `_special` rounds (premium) get a gold case and the gold rim (an ink keyline, a gold
	                  band, an outer ink line) — the rim means "special" and nothing else. Projectile and case are
	                  separated by an ink line at the case mouth so a gold case never merges with an HE/AP body.
	Dependencies:     Icons/Glyph, Kit/Theme.
	State:            None (builder table).
	Validation:       Keys ammo/* (FallbackKeys); every key matches assets/icons/ammo/*.svg.
	Error handling:   N/A.
	Performance notes: 7–14 primitives per round.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

-- Shared geometry (64 grid): the case spans x 24..40, y 36..56 for every round.
local CASE_X, CASE_Y, CASE_W, CASE_H = 24, 36, 16, 20

local function case(c: Canvas, p: Palette, special: boolean)
	local material = Theme.material(if special then "gold" else "gunmetal")
	local ink = Theme.ink
	if special then
		-- Gold rim around the case: outer ink line, gold band, inner keyline.
		Glyph.rect(c, CASE_X - 4, CASE_Y - 1, CASE_W + 8, CASE_H + 5, ink, { name = "RimOuter" })
		Glyph.rect(c, CASE_X - 2.5, CASE_Y, CASE_W + 5, CASE_H + 3, material.base, { name = "RimBand" })
	end
	Glyph.rect(c, CASE_X - 1, CASE_Y - 1, CASE_W + 2, CASE_H + 3, ink, { name = "CaseKeyline" })
	local body: Glyph.Paint = if p.tinted then p.shade else material.base
	local hi: Glyph.Paint = if p.tinted then p.base else material.highlight
	local lo: Glyph.Paint = if p.tinted then p.shade else material.shade
	Glyph.rect(c, CASE_X, CASE_Y, CASE_W, CASE_H, body, { name = "Case" })
	Glyph.rect(c, CASE_X + 1.5, CASE_Y + 1, 3, CASE_H - 2, hi, { name = "CaseHi" })
	Glyph.rect(c, CASE_X - 1, CASE_Y + CASE_H - 1, CASE_W + 2, 3, lo, { name = "Base" })
	-- Case mouth: ink line between projectile and case.
	Glyph.rect(c, CASE_X - 1, CASE_Y - 1.5, CASE_W + 2, 1.5, ink, { name = "Mouth" })
end

local function round(nose: (c: Canvas, p: Palette) -> ()): (boolean) -> (Canvas, Palette) -> ()
	return function(special: boolean)
		return function(c: Canvas, p: Palette)
			case(c, p, special)
			nose(c, p)
		end
	end
end

local ap = round(function(c: Canvas, p: Palette)
	-- Long sharp tangent ogive + copper driving band.
	Glyph.rect(c, CASE_X, 22, CASE_W, 12.5, p.fg, { name = "Body" })
	Glyph.wedge(c, 32, 6, 8, "up", p.fg)
	Glyph.rect(c, CASE_X, 14, CASE_W, 8, p.fg, { name = "Ogive" })
	Glyph.rect(c, CASE_X, 30, CASE_W, 3, Theme.material("copper").base, { name = "DrivingBand" })
	Glyph.rect(c, CASE_X + 1.5, 16, 3, 14, p.highlight, { name = "BodyHi" })
end)

local apcr = round(function(c: Canvas, p: Palette)
	-- Sabot collar (gunmetal), tapered petals, thin stepped penetrator needle with a small ballistic tip.
	local sabot = Theme.material("gunmetal")
	Glyph.rect(c, CASE_X, 27, CASE_W, 7.5, sabot.base, { name = "Sabot" })
	Glyph.triangle(c, CASE_X, 21, 6, "br", sabot.shade)
	Glyph.triangle(c, CASE_X + CASE_W - 6, 21, 6, "bl", sabot.shade)
	Glyph.rect(c, 29, 12, 6, 15, p.fg, { name = "Needle" })
	Glyph.rect(c, 30.5, 7, 3, 5, p.fg, { name = "NeedleStep" })
	Glyph.wedge(c, 32, 4, 3, "up", p.fg)
end)

local he = round(function(c: Canvas, p: Palette)
	-- Short blunt ogive cut flat, protruding steel fuze nub.
	Glyph.rect(c, CASE_X, 24, CASE_W, 10.5, p.fg, { name = "Body" })
	Glyph.chamferRect(c, CASE_X, 15, CASE_W, 10, 5, p.fg, "top")
	Glyph.rect(c, 28.5, 10, 7, 5, Theme.material("steel").base, { name = "Fuze" })
	Glyph.rect(c, CASE_X + 1.5, 18, 3, 14, p.highlight, { name = "BodyHi" })
end)

local heat = round(function(c: Canvas, p: Palette)
	-- Straight cone shoulder + thin stand-off probe with a crown.
	local steel = Theme.material("steel")
	Glyph.rect(c, CASE_X, 26, CASE_W, 8.5, p.fg, { name = "Body" })
	Glyph.triangle(c, CASE_X, 18, 8, "br", p.fg)
	Glyph.triangle(c, 32, 18, 8, "bl", p.fg)
	Glyph.rect(c, 30.5, 6, 3, 13, steel.base, { name = "Probe" })
	Glyph.rect(c, 28.5, 4, 7, 3, steel.highlight, { name = "Crown" })
end)

local hesh = round(function(c: Canvas, p: Palette)
	-- Shortest round: wide blunt squash dome, olive body, HE band.
	Glyph.rect(c, CASE_X, 26, CASE_W, 8.5, p.fg, { name = "Body" })
	Glyph.halfDisc(c, 32, 27, 10, "top", p.fg)
	Glyph.rect(c, CASE_X, 29, CASE_W, 3, Theme.peekColor("ammo.he"), { name = "HeBand" })
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
