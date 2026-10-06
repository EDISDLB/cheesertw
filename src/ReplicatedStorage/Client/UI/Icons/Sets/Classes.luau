--!strict
--[[
	Icons/Sets/Classes — vehicle class symbols and their minimap twins (brand-art §6.6).

	Purpose:          Distinct outlines that read apart at 16 px: light = spotter's eye (almond lids + iris),
	                  medium = flat-top hexagon with a horizontal slot, heavy = bastion shield (flat top, point down)
	                  with an engraved inner contour, td = low wide casemate trapezoid with a muzzle ring, artillery =
	                  trajectory arch over an impact point. Never rhombus/diamond/chevron-stack (IP guardrails §1.1).
	                  Monochrome: tinted per context (bone neutral, gold premium, dusk elite, team colour on markers).
	Dependencies:     Icons/Glyph.
	State:            None (builder table).
	Validation:       Keys are listed in Shared/Assets/FallbackKeys (checked by the Icons spec).
	Error handling:   N/A.
	Performance notes: 4–9 primitives per symbol.
]]

local Glyph = require("../Glyph")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

local function light(c: Canvas, p: Palette)
	-- Almond lids (two 4-segment arcs) meeting at sharp corners, iris + pupil.
	Glyph.polyline(c, { 6, 32, 16, 22.5, 32, 18, 48, 22.5, 58, 32 }, 5, p.fg)
	Glyph.polyline(c, { 6, 32, 16, 41.5, 32, 46, 48, 41.5, 58, 32 }, 5, p.fg)
	Glyph.circle(c, 32, 32, 10.5, p.fg)
	Glyph.ring(c, 32, 32, 6.5, 2.5, p.detail)
end

local function medium(c: Canvas, p: Palette)
	Glyph.hexagon(c, 32, 32, 26, p.fg)
	Glyph.box(c, 32, 32, 26, 5, p.detail, { name = "Slot" })
end

local function shield(c: Canvas, x: number, top: number, w: number, bodyH: number, paint: Glyph.Paint)
	-- Flat top, straight sides, V point: rect + 45° square whose lower half is the point.
	Glyph.rect(c, x, top, w, bodyH, paint)
	local side = w / math.sqrt(2)
	Glyph.box(c, x + w / 2, top + bodyH, side, side, paint, { rotation = 45, name = "Point" })
end

local function heavy(c: Canvas, p: Palette)
	shield(c, 12, 8, 40, 26, p.fg)
	shield(c, 18, 14, 28, 20, p.detail)
	shield(c, 21, 17, 22, 17, p.fg)
end

local function td(c: Canvas, p: Palette)
	-- Casemate: 45° sloped front and back, low and wide (live area 6..58).
	Glyph.rect(c, 22, 24, 20, 18, p.fg)
	Glyph.triangle(c, 4, 24, 18, "br", p.fg)
	Glyph.triangle(c, 42, 24, 18, "bl", p.fg)
	Glyph.ring(c, 32, 34, 5.5, 2.5, p.detail)
end

local function artillery(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 42, 24, 6, p.fg, { arc = "top" })
	Glyph.circle(c, 32, 48, 5, p.fg)
	Glyph.rect(c, 22, 54, 20, 3, p.fg, { name = "Ground" })
end

local Classes: { [string]: Entry } = {
	["classes/light"] = { build = light, color = "brand.bone" },
	["classes/medium"] = { build = medium, color = "brand.bone" },
	["classes/heavy"] = { build = heavy, color = "brand.bone" },
	["classes/td"] = { build = td, color = "brand.bone" },
	["classes/artillery"] = { build = artillery, color = "brand.bone" },
	-- Minimap twins: white, tinted at runtime (team colours).
	["minimap/class_light"] = { build = light, color = "team.self" },
	["minimap/class_medium"] = { build = medium, color = "team.self" },
	["minimap/class_heavy"] = { build = heavy, color = "team.self" },
	["minimap/class_td"] = { build = td, color = "team.self" },
	["minimap/class_artillery"] = { build = artillery, color = "team.self" },
}

return Classes
