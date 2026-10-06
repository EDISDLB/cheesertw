--!strict
--[[
	Icons/Sets/Combat — hit-result callouts, quick-command pings and HUD alert glyphs.

	Purpose:          Hit results (brand-art §10.2 callout icons: pierced plate, module flash, blocked plate, deflect
	                  arrow, layered plate, burst, flame, ammo detonation), the 12 quick commands + map attention
	                  (00-DECISIONS §9; pings are tinted with team colours at runtime) and the "spotted" crest chevron
	                  with two ripple arcs (§8.8 — never a lamp). Every result has its own outline, so colour is only a
	                  secondary cue.
	Dependencies:     Icons/Glyph, Kit/Theme.
	State:            None (builder table).
	Validation:       Keys hits/*, pings/*, hud/* (FallbackKeys).
	Error handling:   N/A.
	Performance notes: 3–14 primitives per glyph.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

local function plate(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 10, 10, 44, 44, 6, p.base, "brand")
	Glyph.rect(c, 16, 13, 32, 2, p.highlight, { name = "PlateHi" })
end

local function penetration(c: Canvas, p: Palette)
	plate(c, p)
	Glyph.circle(c, 32, 32, 9, Theme.ink)
	local dusk = Theme.color("accent.dusk")
	Glyph.line(c, 40, 24, 54, 10, 3.5, dusk)
	Glyph.line(c, 42, 32, 58, 30, 3.5, dusk)
	Glyph.line(c, 38, 40, 50, 52, 3.5, dusk)
end

local function critical(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 27, 3, p.fg)
	Glyph.circle(c, 32, 32, 13, p.fg)
	for i = 0, 5 do
		local a = math.rad(i * 60)
		Glyph.box(c, 32 + math.cos(a) * 15, 32 + math.sin(a) * 15, 7, 6, p.fg, { rotation = i * 60, name = "Cog" })
	end
	Glyph.circle(c, 32, 32, 5, Theme.ink)
end

local function blocked(c: Canvas, p: Palette)
	plate(c, p)
	Glyph.halfDisc(c, 32, 33, 9, "bottom", Theme.ink)
	Glyph.circle(c, 22, 22, 2.5, p.fg)
	Glyph.circle(c, 42, 22, 2.5, p.fg)
	Glyph.circle(c, 32, 18, 2.5, p.fg)
end

local function ricochet(c: Canvas, p: Palette)
	Glyph.line(c, 8, 50, 56, 50, 5, p.base)
	Glyph.line(c, 10, 14, 32, 46, 5, p.fg)
	Glyph.arrow(c, 32, 46, 54, 14, 5, 10, p.fg)
end

local function absorbed(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 6, 18, 34, 36, 5, p.shade, "brand")
	Glyph.chamferRect(c, 16, 12, 34, 36, 5, p.fg, "brand")
	Glyph.chamferRect(c, 26, 6, 32, 34, 5, p.highlight, "brand")
end

local function burst(c: Canvas, paint: Glyph.Paint, core: Glyph.Paint)
	for i = 0, 7 do
		local a = math.rad(i * 45 + 22.5)
		Glyph.box(
			c,
			32 + math.cos(a) * 20,
			32 + math.sin(a) * 20,
			14,
			5,
			paint,
			{ rotation = i * 45 + 22.5, name = "Ray" }
		)
	end
	Glyph.circle(c, 32, 32, 13, paint)
	Glyph.circle(c, 32, 32, 7, core)
end

local function splash(c: Canvas, p: Palette)
	burst(c, p.fg, p.highlight)
end

local function hitFire(c: Canvas, p: Palette)
	Glyph.circle(c, 32, 42, 14, p.fg)
	Glyph.wedge(c, 32, 10, 18, "up", p.fg)
	Glyph.circle(c, 32, 45, 7, p.highlight)
	Glyph.wedge(c, 32, 30, 8, "up", p.highlight)
end

local function detonation(c: Canvas, p: Palette)
	burst(c, p.fg, Theme.color("team.self"))
	Glyph.rect(c, 29, 24, 6, 14, Theme.ink, { name = "Shell" })
	Glyph.wedge(c, 32, 20, 3, "up", Theme.ink)
end

-- Pings (quick commands).
local function attack(c: Canvas, p: Palette)
	Glyph.rect(c, 27, 24, 10, 30, p.fg)
	Glyph.wedge(c, 32, 6, 20, "up", p.fg)
end

local function defendBase(c: Canvas, p: Palette)
	Glyph.rect(c, 14, 10, 36, 22, p.fg)
	local side = 36 / math.sqrt(2)
	Glyph.box(c, 32, 32, side, side, p.fg, { rotation = 45, name = "Point" })
	Glyph.rect(c, 22, 18, 20, 4, p.detail, { name = "Wall" })
end

local function needHelp(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 25, 5, p.fg)
	Glyph.bang(c, 32, 31, 28, p.fg)
end

local function affirmative(c: Canvas, p: Palette)
	Glyph.check(c, 32, 33, 40, 8, p.fg)
end

local function negative(c: Canvas, p: Palette)
	Glyph.cross(c, 32, 32, 34, 8, p.fg)
end

local function reloading(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 34, 22, 6, p.fg, { arc = "top" })
	Glyph.ring(c, 32, 34, 22, 6, p.fg, { arc = "left" })
	-- Arrowhead at the open end of the 270° arc (right side), pointing down along the circle.
	Glyph.wedge(c, 51, 46, 10, "down", p.fg)
end

local function thanks(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 26, 4.5, p.fg)
	Glyph.check(c, 32, 33, 26, 6, p.fg)
end

local function holdPosition(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 26, 5, p.fg)
	Glyph.rect(c, 16, 28, 32, 8, p.fg, { name = "Hold" })
end

local function followMe(c: Canvas, p: Palette)
	Glyph.arrow(c, 32, 46, 32, 12, 7, 14, p.fg)
	Glyph.circle(c, 32, 54, 5, p.fg)
end

local function crosshair(c: Canvas, p: Palette, ringR: number)
	Glyph.ring(c, 32, 32, ringR, 4.5, p.fg)
	Glyph.rect(c, 30, 4, 4, 14, p.fg, { name = "TickN" })
	Glyph.rect(c, 30, 46, 4, 14, p.fg, { name = "TickS" })
	Glyph.rect(c, 4, 30, 14, 4, p.fg, { name = "TickW" })
	Glyph.rect(c, 46, 30, 14, 4, p.fg, { name = "TickE" })
end

local function enemySpotted(c: Canvas, p: Palette)
	crosshair(c, p, 20)
	Glyph.circle(c, 32, 32, 5, p.fg)
end

local function movingHere(c: Canvas, p: Palette)
	Glyph.circle(c, 32, 24, 16, p.fg)
	Glyph.box(c, 32, 36, 20, 20, p.fg, { rotation = 45, name = "PinPoint" })
	Glyph.circle(c, 32, 24, 6, p.detail)
end

local function focusFire(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 27, 4, p.fg)
	Glyph.ring(c, 32, 32, 16, 4, p.fg)
	Glyph.circle(c, 32, 32, 5, p.fg)
end

local function attention(c: Canvas, p: Palette)
	Glyph.circle(c, 32, 32, 7, p.fg)
	Glyph.ring(c, 32, 32, 18, 3.5, p.fg)
	Glyph.ring(c, 32, 32, 28, 3, p.fg, { transparency = 0.35 })
end

local function spotted(c: Canvas, p: Palette)
	-- Dusk crest chevron (^) with two ripple arcs (brand-art §8.8).
	Glyph.ring(c, 32, 40, 28, 3, p.fg, { arc = "top", transparency = 0.45 })
	Glyph.ring(c, 32, 40, 20, 3, p.fg, { arc = "top", transparency = 0.2 })
	Glyph.chevron(c, 32, 30, 14, 7, p.fg, "up")
end

local Combat: { [string]: Entry } = {
	["hits/penetration"] = { build = penetration, material = "steel" },
	["hits/critical"] = { build = critical, color = "team.platoon" },
	["hits/blocked"] = { build = blocked, material = "steel" },
	["hits/ricochet"] = { build = ricochet, color = "state.info" },
	["hits/absorbed"] = { build = absorbed, material = "cobalt" },
	["hits/splash"] = { build = splash, material = "he" },
	["hits/fire"] = { build = hitFire, material = "dusk" },
	["hits/detonation"] = { build = detonation, material = "signal" },
	["pings/attack"] = { build = attack, color = "text.primary" },
	["pings/defend_base"] = { build = defendBase, color = "text.primary" },
	["pings/need_help"] = { build = needHelp, color = "text.primary" },
	["pings/affirmative"] = { build = affirmative, color = "text.primary" },
	["pings/negative"] = { build = negative, color = "text.primary" },
	["pings/reloading"] = { build = reloading, color = "text.primary" },
	["pings/thanks"] = { build = thanks, color = "text.primary" },
	["pings/hold_position"] = { build = holdPosition, color = "text.primary" },
	["pings/follow_me"] = { build = followMe, color = "text.primary" },
	["pings/enemy_spotted"] = { build = enemySpotted, color = "text.primary" },
	["pings/moving_here"] = { build = movingHere, color = "text.primary" },
	["pings/focus_fire"] = { build = focusFire, color = "text.primary" },
	["pings/attention"] = { build = attention, color = "text.primary" },
	["hud/spotted"] = { build = spotted, color = "accent.dusk" },
}

return Combat
