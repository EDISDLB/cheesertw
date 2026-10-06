--!strict
--[[
	Icons/Sets/Combat — battle glyphs: hit-result callouts, map pings, radial commands, HUD alerts, minimap markers.

	Purpose:          Fallbacks for `assets/icons/battle/*` under the SAME keys (`battle/<file stem>`), so uploaded art
	                  replaces them with no code change:
	                    * hit results (brand-art §10.2, pre-coloured): pierced plate, critical (module flash), blocked
	                      plate, deflect arrow, kill, flame, broken track; plus layered plate / burst / ammo detonation
	                      for the §10.2 results that have no art yet;
	                    * map pings (§6.12 pin family): an octagonal head on a narrow spike with a flat tip; the cut-out
	                      says which (attack = down triangle, defend = battlement, help = bang, position = dot,
	                      spotted = the single crest chevron — never an eye, the light class owns it);
	                    * radial commands (00-DECISIONS §9 presets, `cmd_*`), white for tinting;
	                    * HUD alerts: the dusk crest chevron with two ripple arcs (§8.8, never a lamp), spotted-enemy;
	                    * minimap markers (§6.12 shape language): self arrow, last-seen ghost (dashed ring + dot),
	                      bases (ring + flag; enemy adds four target ticks), capture point (four heavy ring segments),
	                      objective (corner brackets — the only square zone).
	                  Keys without source art yet are listed in Shared/Assets/FallbackKeys.awaitingArt.
	Dependencies:     Icons/Glyph, Kit/Theme.
	State:            None (builder table).
	Validation:       Keys battle/* (FallbackKeys.glyphs; the Icons spec checks them against assets/icons).
	Error handling:   N/A.
	Performance notes: 3–16 primitives per glyph.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

--------------------------------------------------------------------------------
-- Hit results (pre-coloured callouts)
--------------------------------------------------------------------------------

local function plate(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 8, 8, 48, 48, 7, Theme.ink, "brand")
	Glyph.chamferRect(c, 10, 10, 44, 44, 6, p.base, "brand")
	Glyph.rect(c, 17, 12, 30, 2, p.highlight, { name = "PlateHi" })
	Glyph.rect(c, 10, 50, 37, 2, p.shade, { name = "PlateLo" })
end

local function penetration(c: Canvas, p: Palette)
	plate(c, p)
	Glyph.circle(c, 30, 34, 9, Theme.ink)
	-- Molten spark cone leaving the hole (dusk, brand §10.2).
	local dusk: Glyph.Paint = if p.tinted then p.fg else Theme.color("accent.dusk")
	Glyph.line(c, 38, 26, 54, 10, 3.5, dusk)
	Glyph.line(c, 40, 33, 57, 30, 3.5, dusk)
	Glyph.line(c, 37, 41, 50, 54, 3.5, dusk)
end

local function critical(c: Canvas, p: Palette)
	-- Ring flash around a gear (the module hit), amber.
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
	-- A shallow dent (no hole) with a scuff: the shell did not get through.
	Glyph.ring(c, 32, 33, 11, 3.5, p.shade)
	Glyph.circle(c, 32, 33, 5, p.highlight)
	Glyph.line(c, 16, 47, 26, 41, 2.5, p.highlight)
	Glyph.line(c, 38, 25, 48, 19, 2.5, p.highlight)
end

local function ricochet(c: Canvas, p: Palette)
	Glyph.line(c, 6, 52, 58, 52, 5, p.shade)
	Glyph.line(c, 10, 14, 32, 48, 5, p.fg)
	Glyph.arrow(c, 32, 48, 54, 14, 5, 10, p.fg)
end

local function kill(c: Canvas, p: Palette)
	Glyph.octagon(c, 32, 32, 52, p.fg)
	Glyph.octagon(c, 32, 32, 40, Theme.ink)
	Glyph.cross(c, 32, 32, 22, 7, p.fg)
end

local function flame(c: Canvas, p: Palette)
	-- Three tongues of flame with a bright core.
	Glyph.drop(c, 19, 44, 8, p.base)
	Glyph.drop(c, 45, 44, 8, p.base)
	Glyph.drop(c, 32, 40, 14, p.base)
	Glyph.drop(c, 32, 46, 7, p.highlight)
end

local function trackHalf(c: Canvas, p: Palette, x: number, y: number)
	Glyph.chamferRect(c, x, y, 25, 20, 7, p.fg, "all")
	Glyph.rect(c, x + 4, y + 6, 17, 8, Theme.ink, { name = "Inner" })
	Glyph.circle(c, x + 8.5, y + 10, 3.5, p.fg)
	Glyph.circle(c, x + 16.5, y + 10, 3.5, p.fg)
end

local function trackBroken(c: Canvas, p: Palette)
	-- Track run broken in two, the halves pushed apart and dropped (the break is the shape cue, brand §6.8).
	trackHalf(c, p, 3, 20)
	trackHalf(c, p, 36, 26)
	-- Loose links falling from the break.
	Glyph.box(c, 32, 50, 5, 5, p.fg, { rotation = 30, name = "Link1" })
	Glyph.box(c, 29, 57, 4, 4, p.fg, { rotation = 60, name = "Link2" })
end

local function absorbed(c: Canvas, p: Palette)
	-- Layered plate (spaced armour / screens).
	Glyph.chamferRect(c, 6, 20, 34, 36, 5, p.shade, "brand")
	Glyph.chamferRect(c, 16, 13, 34, 36, 5, p.base, "brand")
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
	burst(c, p.base, p.highlight)
end

local function detonation(c: Canvas, p: Palette)
	burst(c, p.base, p.highlight)
	-- The ammo glyph inside the fireball (brand §10.2 "ammo glyph").
	Glyph.rect(c, 29, 26, 6, 13, Theme.ink, { name = "Shell" })
	Glyph.wedge(c, 32, 21, 3, "up", Theme.ink)
end

--------------------------------------------------------------------------------
-- Map pings: the pin family (brand §6.12)
--------------------------------------------------------------------------------

-- Octagonal head on a narrow spike with a flat-cut tip. Returns nothing; cut-outs are drawn by the caller.
local function pin(c: Canvas, p: Palette)
	Glyph.octagon(c, 32, 25, 40, p.fg)
	Glyph.rect(c, 28, 40, 8, 13, p.fg, { name = "Spike" })
	Glyph.wedge(c, 32, 57, 4, "down", p.fg)
end

local function pingAttack(c: Canvas, p: Palette)
	pin(c, p)
	Glyph.wedge(c, 32, 33, 10, "down", p.detail)
end

local function pingDefend(c: Canvas, p: Palette)
	pin(c, p)
	-- Battlement: a wall with three merlons.
	Glyph.rect(c, 21, 26, 22, 8, p.detail, { name = "Wall" })
	for i, x in { 21, 29.5, 38 } do
		Glyph.rect(c, x, 19, 5, 7, p.detail, { name = "Merlon" .. i })
	end
end

local function pingHelp(c: Canvas, p: Palette)
	pin(c, p)
	Glyph.bang(c, 32, 24, 22, p.detail)
end

local function pingPosition(c: Canvas, p: Palette)
	pin(c, p)
	Glyph.circle(c, 32, 25, 7, p.detail)
end

local function pingSpotted(c: Canvas, p: Palette)
	pin(c, p)
	Glyph.chevron(c, 32, 19, 10, 5, p.detail, "up")
end

--------------------------------------------------------------------------------
-- Radial commands (white, tinted at runtime)
--------------------------------------------------------------------------------

local function cmdAttack(c: Canvas, p: Palette)
	Glyph.rect(c, 27, 26, 10, 30, p.fg, { name = "Shaft" })
	Glyph.wedge(c, 32, 6, 20, "up", p.fg)
end

local function cmdDefend(c: Canvas, p: Palette)
	-- Tower with battlements (never a shield: the heavy class owns that outline).
	Glyph.rect(c, 14, 24, 36, 32, p.fg, { name = "Tower" })
	for i, x in { 14, 28, 42 } do
		Glyph.rect(c, x, 12, 8, 12, p.fg, { name = "Merlon" .. i })
	end
	Glyph.rect(c, 27, 40, 10, 16, p.detail, { name = "Gate" })
end

local function cmdHelp(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 26, 5, p.fg)
	Glyph.bang(c, 32, 31, 28, p.fg)
end

local function cmdRetreat(c: Canvas, p: Palette)
	Glyph.rect(c, 27, 8, 10, 30, p.fg, { name = "Shaft" })
	Glyph.wedge(c, 32, 58, 20, "down", p.fg)
end

local function cmdEnemySpotted(c: Canvas, p: Palette)
	-- The single crest chevron (the "spotted" cue) over a ground mark: "enemy spotted here".
	Glyph.chevron(c, 32, 10, 20, 8, p.fg, "up")
	Glyph.circle(c, 32, 42, 6, p.fg)
	Glyph.rect(c, 10, 51, 44, 5, p.fg, { name = "Ground" })
end

local function cmdCapture(c: Canvas, p: Palette)
	-- A flag planted inside the base ring.
	Glyph.ring(c, 32, 33, 25, 4, p.fg)
	Glyph.rect(c, 23, 17, 4, 30, p.fg, { name = "Pole" })
	Glyph.rect(c, 27, 17, 12, 12, p.fg, { name = "Flag" })
	Glyph.triangle(c, 39, 17, 6, "tl", p.fg)
	Glyph.triangle(c, 39, 23, 6, "bl", p.fg)
	Glyph.rect(c, 17, 45, 16, 4, p.fg, { name = "Footing" })
end

local function cmdFollowMe(c: Canvas, p: Palette)
	Glyph.arrow(c, 32, 46, 32, 10, 7, 14, p.fg)
	Glyph.circle(c, 32, 54, 5, p.fg)
end

local function cmdNeedAssistance(c: Canvas, p: Palette)
	-- Rally to me: four chevrons converging on a dot.
	Glyph.circle(c, 32, 32, 6, p.fg)
	Glyph.chevron(c, 32, 22, 8, 5, p.fg, "down")
	Glyph.chevron(c, 32, 42, 8, 5, p.fg, "up")
	Glyph.chevron(c, 22, 32, 8, 5, p.fg, "right")
	Glyph.chevron(c, 42, 32, 8, 5, p.fg, "left")
end

local function cmdAffirmative(c: Canvas, p: Palette)
	Glyph.check(c, 32, 33, 40, 8, p.fg)
end

local function cmdNegative(c: Canvas, p: Palette)
	Glyph.cross(c, 32, 32, 34, 8, p.fg)
end

local function cmdReloading(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 34, 22, 6, p.fg, { arc = "top" })
	Glyph.ring(c, 32, 34, 22, 6, p.fg, { arc = "left" })
	-- Arrowhead at the open end of the 270° arc (right side), pointing down along the circle.
	Glyph.wedge(c, 51, 46, 10, "down", p.fg)
end

local function cmdPingMap(c: Canvas, p: Palette)
	-- Folded map sheet with a pin.
	Glyph.chamferRect(c, 6, 20, 52, 36, 4, p.shade, "brand")
	Glyph.line(c, 23, 22, 23, 54, 2, p.fg)
	Glyph.line(c, 41, 22, 41, 54, 2, p.fg)
	Glyph.octagon(c, 32, 18, 20, p.fg)
	Glyph.rect(c, 30, 26, 4, 12, p.fg, { name = "Spike" })
	Glyph.circle(c, 32, 18, 3.5, p.detail)
end

local function cmdHold(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 26, 5, p.fg)
	Glyph.rect(c, 16, 28, 32, 8, p.fg, { name = "Hold" })
end

local function cmdFocusFire(c: Canvas, p: Palette)
	-- Lock brackets around concentric rings.
	Glyph.ring(c, 32, 32, 16, 4, p.fg)
	Glyph.circle(c, 32, 32, 5, p.fg)
	for _, corner in { { 6, 6, 1, 1 }, { 58, 6, -1, 1 }, { 6, 58, 1, -1 }, { 58, 58, -1, -1 } } do
		local x, y, sx, sy = corner[1], corner[2], corner[3], corner[4]
		Glyph.line(c, x, y, x + 14 * sx, y, 4.5, p.fg)
		Glyph.line(c, x, y, x, y + 14 * sy, 4.5, p.fg)
	end
end

local function cmdMoving(c: Canvas, p: Palette)
	-- Map pin with a forward chevron.
	Glyph.octagon(c, 32, 24, 36, p.fg)
	Glyph.rect(c, 28, 38, 8, 15, p.fg, { name = "Spike" })
	Glyph.wedge(c, 32, 57, 4, "down", p.fg)
	Glyph.chevron(c, 36, 24, 7, 4.5, p.detail, "right")
end

local function cmdThanks(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 26, 4.5, p.fg)
	Glyph.check(c, 32, 33, 26, 6, p.fg)
end

--------------------------------------------------------------------------------
-- HUD alerts
--------------------------------------------------------------------------------

local function spottedWarning(c: Canvas, p: Palette)
	-- Dusk crest chevron (^) with two ripple arcs (brand-art §8.8).
	Glyph.ring(c, 32, 40, 28, 3, p.fg, { arc = "top", transparency = 0.45 })
	Glyph.ring(c, 32, 40, 20, 3, p.fg, { arc = "top", transparency = 0.2 })
	Glyph.chevron(c, 32, 30, 14, 7, p.fg, "up")
end

local function spottedEnemy(c: Canvas, p: Palette)
	-- Crest chevron inside target brackets ("you spotted an enemy").
	for _, corner in { { 8, 10, 1, 1 }, { 56, 10, -1, 1 }, { 8, 54, 1, -1 }, { 56, 54, -1, -1 } } do
		local x, y, sx, sy = corner[1], corner[2], corner[3], corner[4]
		Glyph.line(c, x, y, x + 12 * sx, y, 4, p.fg)
		Glyph.line(c, x, y, x, y + 12 * sy, 4, p.fg)
	end
	Glyph.chevron(c, 32, 24, 13, 6, p.fg, "up")
	Glyph.circle(c, 32, 42, 4, p.fg)
end

--------------------------------------------------------------------------------
-- Minimap markers (white, team-tinted at runtime)
--------------------------------------------------------------------------------

local function selfArrow(c: Canvas, p: Palette)
	-- Own vehicle: one heavy chevron arrow with a solid point (rotated with the hull by the minimap). A single
	-- chevron never reads as a rank or XP stack (brand §6.12).
	Glyph.polyline(c, { 12, 56, 32, 14, 52, 56 }, 12, p.fg)
	Glyph.wedge(c, 32, 4, 14, "up", p.fg)
end

local function lastSeen(c: Canvas, p: Palette)
	-- Thin ring of eight short dashes around a dot.
	for i = 0, 7 do
		local a = math.rad(i * 45)
		Glyph.box(c, 32 + math.cos(a) * 22, 32 + math.sin(a) * 22, 8, 3.5, p.fg, {
			rotation = i * 45 + 90,
			name = "Dash" .. i,
		})
	end
	Glyph.circle(c, 32, 32, 5, p.fg)
end

local function baseFlag(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 22, 4, p.fg)
	Glyph.rect(c, 26, 18, 3.5, 26, p.fg, { name = "Pole" })
	Glyph.rect(c, 29.5, 18, 12, 10, p.fg, { name = "Flag" })
end

local function baseAlly(c: Canvas, p: Palette)
	baseFlag(c, p)
end

local function baseEnemy(c: Canvas, p: Palette)
	baseFlag(c, p)
	-- Four target ticks outside the ring (shape cue).
	Glyph.rect(c, 30, 2, 4, 7, p.fg, { name = "TickN" })
	Glyph.rect(c, 30, 55, 4, 7, p.fg, { name = "TickS" })
	Glyph.rect(c, 2, 30, 7, 4, p.fg, { name = "TickW" })
	Glyph.rect(c, 55, 30, 7, 4, p.fg, { name = "TickE" })
end

local function capturePoint(c: Canvas, p: Palette)
	-- Four heavy ring segments (tangent bars on the diagonals).
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		Glyph.box(c, 32 + math.cos(a) * 21, 32 + math.sin(a) * 21, 22, 7, p.fg, {
			rotation = i * 90 + 135,
			name = "Segment" .. i,
		})
	end
	Glyph.circle(c, 32, 32, 5, p.fg)
end

local function objective(c: Canvas, p: Palette)
	for _, corner in { { 8, 8, 1, 1 }, { 56, 8, -1, 1 }, { 8, 56, 1, -1 }, { 56, 56, -1, -1 } } do
		local x, y, sx, sy = corner[1], corner[2], corner[3], corner[4]
		Glyph.line(c, x, y, x + 16 * sx, y, 6, p.fg)
		Glyph.line(c, x, y, x, y + 16 * sy, 6, p.fg)
	end
	Glyph.circle(c, 32, 32, 6, p.fg)
end

local Combat: { [string]: Entry } = {
	-- Hit results (pre-coloured; art in assets/icons/battle/hit_*).
	["battle/hit_penetration"] = { build = penetration, material = "steel" },
	["battle/hit_critical"] = { build = critical, color = "state.warning" },
	["battle/hit_blocked"] = { build = blocked, material = "steel" },
	["battle/hit_ricochet"] = { build = ricochet, material = "apcr" },
	["battle/hit_kill"] = { build = kill, color = "state.danger" },
	["battle/hit_fire"] = { build = flame, material = "dusk" },
	["battle/hit_track"] = { build = trackBroken, color = "state.warning" },
	-- brand-art §10.2 results without art yet (FallbackKeys.awaitingArt).
	["battle/hit_absorbed"] = { build = absorbed, material = "cobalt" },
	["battle/hit_splash"] = { build = splash, material = "he" },
	["battle/hit_detonation"] = { build = detonation, material = "signal" },
	-- Map pings (white; tinted with the sender's team colour).
	["battle/ping_attack"] = { build = pingAttack, color = "team.self" },
	["battle/ping_defend"] = { build = pingDefend, color = "team.self" },
	["battle/ping_help"] = { build = pingHelp, color = "team.self" },
	["battle/ping_position"] = { build = pingPosition, color = "team.self" },
	["battle/ping_spotted"] = { build = pingSpotted, color = "team.self" },
	-- Radial commands (white; the radial menu tints them).
	["battle/cmd_attack"] = { build = cmdAttack, color = "text.primary" },
	["battle/cmd_defend"] = { build = cmdDefend, color = "text.primary" },
	["battle/cmd_help"] = { build = cmdHelp, color = "text.primary" },
	["battle/cmd_retreat"] = { build = cmdRetreat, color = "text.primary" },
	["battle/cmd_enemy_spotted"] = { build = cmdEnemySpotted, color = "text.primary" },
	["battle/cmd_capture"] = { build = cmdCapture, color = "text.primary" },
	["battle/cmd_follow_me"] = { build = cmdFollowMe, color = "text.primary" },
	["battle/cmd_need_assistance"] = { build = cmdNeedAssistance, color = "text.primary" },
	["battle/cmd_affirmative"] = { build = cmdAffirmative, color = "text.primary" },
	["battle/cmd_negative"] = { build = cmdNegative, color = "text.primary" },
	["battle/cmd_reloading"] = { build = cmdReloading, color = "text.primary" },
	["battle/cmd_ping_map"] = { build = cmdPingMap, color = "text.primary" },
	-- Decided presets whose art is requested (ui-ux §5.1; FallbackKeys.awaitingArt).
	["battle/cmd_hold"] = { build = cmdHold, color = "text.primary" },
	["battle/cmd_focus_fire"] = { build = cmdFocusFire, color = "text.primary" },
	["battle/cmd_moving"] = { build = cmdMoving, color = "text.primary" },
	["battle/cmd_thanks"] = { build = cmdThanks, color = "text.primary" },
	-- HUD alerts.
	["battle/spotted_warning"] = { build = spottedWarning, color = "accent.dusk" },
	["battle/spotted_enemy"] = { build = spottedEnemy, color = "team.self" },
	-- Minimap markers (white; team-tinted at runtime).
	["battle/self"] = { build = selfArrow, color = "team.self" },
	["battle/last_seen"] = { build = lastSeen, color = "team.self" },
	["battle/base_ally"] = { build = baseAlly, color = "team.self" },
	["battle/base_enemy"] = { build = baseEnemy, color = "team.self" },
	["battle/capture_point"] = { build = capturePoint, color = "team.self" },
	["battle/objective"] = { build = objective, color = "team.self" },
}

return Combat
