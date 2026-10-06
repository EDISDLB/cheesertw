--!strict
--[[
	Icons/Sets/Ui — core interface glyphs used by kit components, and the generic category badge.

	Purpose:          close, back, check, chevrons, plus/minus, info (i in a square), warning (triangle bang), error
	                  (octagon bang), lock, settings (gear), search, timer — monochrome, tinted by the caller (states
	                  are "single state colour on ink", brand-art §6.5). The generic badge (any key without a glyph) is
	                  a chamfered plate in the HULLDOWN cut with a ring-and-dot mark tinted per category.
	Dependencies:     Icons/Glyph, Kit/Theme.
	State:            None (builder table).
	Validation:       Keys ui/* (FallbackKeys); badge categories in FallbackKeys.badgeCategories.
	Error handling:   N/A.
	Performance notes: 2–12 primitives per glyph.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

local function close(c: Canvas, p: Palette)
	Glyph.cross(c, 32, 32, 34, 7, p.fg)
end

local function back(c: Canvas, p: Palette)
	Glyph.arrow(c, 52, 32, 12, 32, 7, 16, p.fg)
end

local function check(c: Canvas, p: Palette)
	Glyph.check(c, 32, 33, 42, 8, p.fg)
end

local function chevron(direction: "up" | "down" | "left" | "right"): (Canvas, Palette) -> ()
	return function(c: Canvas, p: Palette)
		local cx, cy = 32, 32
		if direction == "up" then
			cy = 22
		elseif direction == "down" then
			cy = 42
		elseif direction == "left" then
			cx = 22
		else
			cx = 42
		end
		Glyph.chevron(c, cx, cy, 16, 7, p.fg, direction)
	end
end

local function plus(c: Canvas, p: Palette)
	Glyph.box(c, 32, 32, 40, 8, p.fg)
	Glyph.box(c, 32, 32, 8, 40, p.fg)
end

local function minus(c: Canvas, p: Palette)
	Glyph.box(c, 32, 32, 40, 8, p.fg)
end

local function info(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 8, 8, 48, 48, 6, p.fg, "brand")
	Glyph.rect(c, 28.5, 27, 7, 21, Theme.ink, { name = "Stem" })
	Glyph.rect(c, 28.5, 16, 7, 7, Theme.ink, { name = "Dot" })
end

local function warning(c: Canvas, p: Palette)
	Glyph.wedge(c, 32, 8, 24, "up", p.fg)
	Glyph.bang(c, 32, 24, 14, Theme.ink)
end

local function errorGlyph(c: Canvas, p: Palette)
	Glyph.octagon(c, 32, 32, 50, p.fg)
	Glyph.bang(c, 32, 32, 30, Theme.ink)
end

local function lock(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 28, 15, 6, p.fg, { arc = "top" })
	Glyph.rect(c, 17, 27, 6, 6, p.fg, { name = "ShackleL" })
	Glyph.rect(c, 41, 27, 6, 6, p.fg, { name = "ShackleR" })
	Glyph.chamferRect(c, 12, 30, 40, 26, 4, p.fg, "brand")
	Glyph.circle(c, 32, 40, 4, Theme.ink)
	Glyph.rect(c, 30.5, 42, 3, 7, Theme.ink, { name = "Keyway" })
end

local function settings(c: Canvas, p: Palette)
	Glyph.circle(c, 32, 32, 18, p.fg)
	for i = 0, 7 do
		local a = math.rad(i * 45)
		Glyph.box(c, 32 + math.cos(a) * 20, 32 + math.sin(a) * 20, 10, 9, p.fg, { rotation = i * 45, name = "Tooth" })
	end
	Glyph.circle(c, 32, 32, 7, Theme.ink)
end

local function search(c: Canvas, p: Palette)
	Glyph.ring(c, 27, 27, 18, 6, p.fg)
	Glyph.line(c, 39, 39, 54, 54, 8, p.fg)
end

local function timer(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 35, 24, 5, p.fg)
	Glyph.rect(c, 27, 4, 10, 5, p.fg, { name = "Crown" })
	Glyph.line(c, 32, 35, 32, 21, 4.5, p.fg)
	Glyph.line(c, 32, 35, 42, 41, 4.5, p.fg)
end

--- Generic category badge (any key without a dedicated glyph).
local function badge(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 8, 8, 48, 48, 8, Theme.ink, "brand")
	Glyph.chamferRect(c, 10, 10, 44, 44, 7, Theme.color("bg.raised"), "brand")
	Glyph.rect(c, 17, 12, 35, 1.5, Theme.color("border.bevel_hi"), { name = "Bevel" })
	Glyph.ring(c, 32, 32, 13, 4, p.fg)
	Glyph.circle(c, 32, 32, 4, p.fg)
end

local Ui: { [string]: Entry } = {
	["ui/close"] = { build = close, color = "text.primary" },
	["ui/back"] = { build = back, color = "text.primary" },
	["ui/check"] = { build = check, color = "state.success" },
	["ui/chevron_left"] = { build = chevron("left"), color = "text.primary" },
	["ui/chevron_right"] = { build = chevron("right"), color = "text.primary" },
	["ui/chevron_up"] = { build = chevron("up"), color = "text.primary" },
	["ui/chevron_down"] = { build = chevron("down"), color = "text.primary" },
	["ui/plus"] = { build = plus, color = "text.primary" },
	["ui/minus"] = { build = minus, color = "text.primary" },
	["ui/info"] = { build = info, color = "state.info" },
	["ui/warning"] = { build = warning, color = "state.warning" },
	["ui/error"] = { build = errorGlyph, color = "state.danger" },
	["ui/lock"] = { build = lock, color = "text.secondary" },
	["ui/settings"] = { build = settings, color = "text.primary" },
	["ui/search"] = { build = search, color = "text.primary" },
	["ui/timer"] = { build = timer, color = "text.primary" },
}

return {
	entries = Ui,
	badge = { build = badge, color = "text.secondary" } :: Entry,
}
