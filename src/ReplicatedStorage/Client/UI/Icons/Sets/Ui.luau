--!strict
--[[
	Icons/Sets/Ui — core interface glyphs used by kit components, and the generic category badge.

	Purpose:          close, back, check, chevrons, plus/minus, info (i in a square), warning (triangle bang), error
	                  (octagon bang), lock, settings (gear), search, timer, plus the nav rail / top bar set (menu,
	                  home, garage, tech tree, crew, missions, store, profile dog tag, friends, notifications bell,
	                  premium sun-over-ridge, favourite bookmark, filter, sort, refresh, forward, exit, help, clock,
	                  research, HP angular heart, damage pierced plate, battle) — monochrome, tinted by the caller
	                  (states are "single state colour on ink", brand-art §6.5; fixed concepts per §6.12). The generic badge (any key without a glyph) is
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

-- Navigation and top-bar glyphs (ui-ux §1.2 rail, §1.4 top bar). One stroke weight (~6 units, brand §6.12).

local function menu(c: Canvas, p: Palette)
	for i, y in { 14, 29, 44 } do
		Glyph.rect(c, 10, y, 44, 6, p.fg, { name = "Bar" .. i })
	end
end

local function home(c: Canvas, p: Palette)
	Glyph.wedge(c, 32, 6, 26, "up", p.fg)
	Glyph.rect(c, 14, 30, 36, 26, p.fg, { name = "Walls" })
	Glyph.rect(c, 27, 40, 10, 16, p.detail, { name = "Door" })
end

local function garage(c: Canvas, p: Palette)
	-- Hangar: chamfered roof line over a slatted door.
	Glyph.chamferRect(c, 6, 14, 52, 42, 12, p.fg, "top")
	Glyph.rect(c, 15, 30, 34, 26, p.detail, { name = "Door" })
	for i, y in { 34, 41, 48 } do
		Glyph.rect(c, 15, y, 34, 3, p.fg, { name = "Slat" .. i })
	end
end

local function techTree(c: Canvas, p: Palette)
	Glyph.rect(c, 24, 6, 16, 12, p.fg, { name = "Root" })
	Glyph.rect(c, 29.5, 18, 5, 10, p.fg, { name = "Trunk" })
	Glyph.rect(c, 12, 26, 40, 5, p.fg, { name = "Branch" })
	Glyph.rect(c, 12, 26, 5, 14, p.fg, { name = "StemL" })
	Glyph.rect(c, 47, 26, 5, 14, p.fg, { name = "StemR" })
	Glyph.rect(c, 6, 40, 17, 14, p.fg, { name = "LeafL" })
	Glyph.rect(c, 41, 40, 17, 14, p.fg, { name = "LeafR" })
end

local function crew(c: Canvas, p: Palette)
	-- Padded tanker helmet.
	Glyph.halfDisc(c, 32, 40, 22, "top", p.fg)
	Glyph.rect(c, 6, 38, 52, 6, p.fg, { name = "Brim" })
	Glyph.rect(c, 13, 44, 8, 12, p.fg, { name = "FlapL" })
	Glyph.rect(c, 43, 44, 8, 12, p.fg, { name = "FlapR" })
	for i, x in { 22, 31, 40 } do
		Glyph.rect(c, x, 20, 3, 16, p.detail, { name = "Pad" .. i })
	end
end

local function missions(c: Canvas, p: Palette)
	-- Clipboard with order lines.
	Glyph.chamferRect(c, 12, 10, 40, 48, 5, p.fg, "brand")
	Glyph.rect(c, 22, 6, 20, 9, p.fg, { name = "Clip" })
	Glyph.rect(c, 26, 8, 12, 4, p.detail, { name = "ClipSlot" })
	for i, w in { 26, 26, 18 } do
		Glyph.rect(c, 19, 18 + i * 9, w, 4, p.detail, { name = "Line" .. i })
	end
end

local function store(c: Canvas, p: Palette)
	-- Supply crate with a carry handle.
	Glyph.ring(c, 32, 24, 13, 5, p.fg, { arc = "top" })
	Glyph.chamferRect(c, 8, 22, 48, 34, 6, p.fg, "brand")
	Glyph.rect(c, 8, 34, 48, 4, p.detail, { name = "Band" })
	Glyph.rect(c, 28, 30, 8, 12, p.detail, { name = "Latch" })
end

local function profile(c: Canvas, p: Palette)
	-- Dog tag on a bead chain (brand §6.12).
	Glyph.chamferRect(c, 18, 14, 30, 44, 9, p.fg, "all")
	Glyph.circle(c, 33, 21, 3, p.detail)
	Glyph.polyline(c, { 33, 18, 22, 6, 12, 14 }, 2.5, p.fg)
	for i, w in { 16, 16, 10 } do
		Glyph.rect(c, 25, 28 + i * 7, w, 3, p.detail, { name = "Stamp" .. i })
	end
end

local function friends(c: Canvas, p: Palette)
	Glyph.circle(c, 43, 22, 8, p.shade)
	Glyph.halfDisc(c, 43, 52, 15, "top", p.shade)
	Glyph.circle(c, 24, 22, 9, p.fg)
	Glyph.halfDisc(c, 24, 54, 17, "top", p.fg)
end

local function notifications(c: Canvas, p: Palette)
	-- Bell.
	Glyph.halfDisc(c, 32, 28, 16, "top", p.fg)
	Glyph.rect(c, 16, 27, 32, 16, p.fg, { name = "Body" })
	Glyph.chamferRect(c, 8, 42, 48, 7, 3, p.fg, "top")
	Glyph.circle(c, 32, 54, 5, p.fg)
	Glyph.rect(c, 30, 6, 4, 6, p.fg, { name = "Loop" })
end

local function premium(c: Canvas, p: Palette)
	-- Sun rising over the ridge (brand §6.12: premium account).
	Glyph.halfDisc(c, 32, 38, 14, "top", p.fg)
	for i = 0, 4 do
		local a = math.rad(180 + i * 45)
		Glyph.box(c, 32 + math.cos(a) * 21, 38 + math.sin(a) * 21, 7, 4, p.fg, {
			rotation = i * 45,
			name = "Ray" .. i,
		})
	end
	Glyph.polyline(c, { 6, 52, 22, 40, 32, 48, 44, 36, 58, 52 }, 6, p.fg)
end

local function favorite(c: Canvas, p: Palette)
	-- Bookmark ribbon (outline).
	Glyph.polyline(c, { 18, 8, 46, 8, 46, 54, 32, 42, 18, 54, 18, 8 }, 6, p.fg)
end

local function favoriteFilled(c: Canvas, p: Palette)
	Glyph.rect(c, 16, 8, 32, 36, p.fg, { name = "Ribbon" })
	Glyph.triangle(c, 16, 44, 14, "tl", p.fg)
	Glyph.triangle(c, 34, 44, 14, "tr", p.fg)
end

local function filter(c: Canvas, p: Palette)
	Glyph.rect(c, 8, 10, 48, 6, p.fg, { name = "Rim" })
	Glyph.wedge(c, 32, 38, 22, "down", p.fg)
	Glyph.rect(c, 28, 34, 8, 20, p.fg, { name = "Stem" })
end

local function sort(c: Canvas, p: Palette)
	Glyph.arrow(c, 22, 54, 22, 10, 6, 11, p.fg)
	Glyph.arrow(c, 42, 10, 42, 54, 6, 11, p.fg)
end

local function refresh(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 22, 6, p.fg, { arc = "top" })
	Glyph.ring(c, 32, 32, 22, 6, p.fg, { arc = "right" })
	-- Arrowhead at the open (left) end of the 270° arc, pointing down along the circle.
	Glyph.wedge(c, 13, 42, 9, "down", p.fg)
end

local function forward(c: Canvas, p: Palette)
	Glyph.arrow(c, 12, 32, 52, 32, 7, 16, p.fg)
end

local function exit(c: Canvas, p: Palette)
	Glyph.rect(c, 8, 8, 6, 48, p.fg, { name = "Jamb" })
	Glyph.rect(c, 8, 8, 26, 6, p.fg, { name = "Head" })
	Glyph.rect(c, 8, 50, 26, 6, p.fg, { name = "Sill" })
	Glyph.arrow(c, 24, 32, 56, 32, 6, 12, p.fg)
end

local function help(c: Canvas, p: Palette)
	-- Question mark built from primitives (no typeset letters) inside a ring.
	Glyph.ring(c, 32, 32, 27, 4, p.fg)
	Glyph.ring(c, 32, 24, 10, 5, p.fg, { arc = "top" })
	Glyph.line(c, 41, 24, 32, 34, 5, p.fg)
	Glyph.rect(c, 29.5, 33, 5, 6, p.fg, { name = "Stem" })
	Glyph.rect(c, 29.5, 43, 5, 5, p.fg, { name = "Dot" })
end

local function clock(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 26, 5, p.fg)
	Glyph.line(c, 32, 32, 32, 15, 5, p.fg)
	Glyph.line(c, 32, 32, 44, 39, 5, p.fg)
end

local function research(c: Canvas, p: Palette)
	-- Laboratory flask.
	Glyph.rect(c, 26, 6, 12, 4, p.fg, { name = "Lip" })
	Glyph.rect(c, 28, 8, 8, 18, p.fg, { name = "Neck" })
	Glyph.wedge(c, 32, 22, 26, "up", p.fg)
	Glyph.rect(c, 6, 48, 52, 8, p.fg, { name = "Base" })
	Glyph.rect(c, 14, 40, 36, 3, p.detail, { name = "Level" })
end

local function hp(c: Canvas, p: Palette)
	-- Angular heart (brand §6.12).
	Glyph.box(c, 23, 24, 18, 18, p.fg, { rotation = 45, name = "LobeL" })
	Glyph.box(c, 41, 24, 18, 18, p.fg, { rotation = 45, name = "LobeR" })
	Glyph.wedge(c, 32, 56, 24, "down", p.fg)
end

local function damage(c: Canvas, p: Palette)
	-- Pierced plate with cracks.
	Glyph.chamferRect(c, 8, 8, 48, 48, 7, p.fg, "brand")
	Glyph.circle(c, 32, 32, 8, p.detail)
	Glyph.polyline(c, { 38, 26, 46, 18, 52, 20 }, 2.5, p.detail)
	Glyph.polyline(c, { 26, 38, 18, 46, 14, 44 }, 2.5, p.detail)
	Glyph.line(c, 39, 37, 48, 46, 2.5, p.detail)
end

local function battle(c: Canvas, p: Palette)
	-- Two crossed rounds: body, pointed nose (a diamond on the axis) and a case rim, each rotated about the centre.
	for i, angle in { 35, -35 } do
		local a = math.rad(angle)
		local ax, ay = math.sin(a), -math.cos(a)
		local cx, cy = 32, 34
		Glyph.box(c, cx, cy, 8, 40, p.fg, { rotation = angle, name = "Body" .. i })
		Glyph.box(c, cx + ax * 20, cy + ay * 20, 5.7, 5.7, p.fg, { rotation = angle + 45, name = "Nose" .. i })
		Glyph.box(c, cx - ax * 20, cy - ay * 20, 12, 4, p.fg, { rotation = angle, name = "Rim" .. i })
	end
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
	["ui/menu"] = { build = menu, color = "text.primary" },
	["ui/home"] = { build = home, color = "text.primary" },
	["ui/garage"] = { build = garage, color = "text.primary" },
	["ui/tech_tree"] = { build = techTree, color = "text.primary" },
	["ui/crew"] = { build = crew, color = "text.primary" },
	["ui/missions"] = { build = missions, color = "text.primary" },
	["ui/store"] = { build = store, color = "text.primary" },
	["ui/profile"] = { build = profile, color = "text.primary" },
	["ui/friends"] = { build = friends, color = "text.primary" },
	["ui/notifications"] = { build = notifications, color = "text.primary" },
	["ui/premium"] = { build = premium, color = "accent.dusk" },
	["ui/favorite"] = { build = favorite, color = "text.primary" },
	["ui/favorite_filled"] = { build = favoriteFilled, color = "accent.dusk" },
	["ui/filter"] = { build = filter, color = "text.primary" },
	["ui/sort"] = { build = sort, color = "text.primary" },
	["ui/refresh"] = { build = refresh, color = "text.primary" },
	["ui/forward"] = { build = forward, color = "text.primary" },
	["ui/exit"] = { build = exit, color = "text.primary" },
	["ui/help"] = { build = help, color = "text.primary" },
	["ui/clock"] = { build = clock, color = "text.primary" },
	["ui/research"] = { build = research, color = "text.primary" },
	["ui/hp"] = { build = hp, color = "text.primary" },
	["ui/damage"] = { build = damage, color = "text.primary" },
	["ui/battle"] = { build = battle, color = "text.primary" },
}

return {
	entries = Ui,
	badge = { build = badge, color = "text.secondary" } :: Entry,
}
