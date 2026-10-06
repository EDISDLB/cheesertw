--!strict
--[[
	Icons/Sets/Modules — vehicle modules (normal / damaged / destroyed) and crew roles (normal / injured).

	Purpose:          Module silhouettes: engine block, ammo rack, fuel can, gun, turret ring, optics, track runs
	                  (both / left / right), plus fire and repair. States never rely on colour alone (research 06
	                  A4, brand §8.8): damaged = state.warning + a warning-triangle "!" badge; destroyed =
	                  state.danger + an "×" badge. Crew roles use their tool as the symbol (commander binoculars,
	                  gunner reticle, driver wheel, loader shell); injured adds an octagon-bang badge in state.danger.
	Dependencies:     Icons/Glyph, Kit/Theme.
	State:            None (builder table).
	Validation:       Keys modules/* and crew/* (FallbackKeys). No radio module/operator (00-DECISIONS §2, §12).
	Error handling:   N/A.
	Performance notes: 5–16 primitives per icon.
]]

local Glyph = require("../Glyph")
local Theme = require("../../Kit/Theme")

type Canvas = Glyph.Canvas
type Palette = Glyph.Palette
export type Entry = { build: (c: Canvas, p: Palette) -> (), color: string?, material: string? }

local function engine(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 8, 22, 36, 26, 4, p.fg, "all")
	for _, x in { 12, 22, 32 } do
		Glyph.rect(c, x, 14, 8, 8, p.fg, { name = "Head" })
	end
	Glyph.circle(c, 51, 35, 9, p.fg)
	Glyph.circle(c, 51, 35, 3.5, p.detail)
	Glyph.rect(c, 14, 30, 24, 3, p.detail, { name = "Fin1" })
	Glyph.rect(c, 14, 37, 24, 3, p.detail, { name = "Fin2" })
end

local function ammoRack(c: Canvas, p: Palette)
	for _, x in { 12, 26, 40 } do
		Glyph.rect(c, x, 24, 12, 30, p.fg)
		Glyph.wedge(c, x + 6, 18, 6, "up", p.fg)
		Glyph.rect(c, x, 44, 12, 3, p.detail, { name = "Band" })
	end
	Glyph.rect(c, 8, 54, 48, 4, p.fg, { name = "Rack" })
end

local function fuelTank(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 16, 12, 32, 44, 8, p.fg, "brand")
	Glyph.rect(c, 30, 8, 12, 6, p.fg, { name = "Handle" })
	Glyph.rect(c, 33, 10, 6, 3, p.detail, { name = "HandleGap" })
	Glyph.line(c, 22, 24, 42, 48, 3, p.detail)
	Glyph.line(c, 42, 24, 22, 48, 3, p.detail)
end

local function gun(c: Canvas, p: Palette)
	Glyph.rect(c, 8, 22, 14, 20, p.fg, { name = "Breech" })
	Glyph.rect(c, 20, 28, 32, 8, p.fg, { name = "Barrel" })
	Glyph.rect(c, 50, 25, 7, 14, p.fg, { name = "Brake" })
	Glyph.rect(c, 52, 29, 3, 6, p.detail, { name = "Port" })
	Glyph.rect(c, 12, 26, 6, 12, p.detail, { name = "Block" })
end

local function turretRing(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 22, 7, p.fg)
	for i = 0, 7 do
		local a = math.rad(i * 45)
		Glyph.box(c, 32 + math.cos(a) * 24, 32 + math.sin(a) * 24, 6, 5, p.fg, { rotation = i * 45, name = "Tooth" })
	end
	Glyph.circle(c, 32, 32, 4, p.fg)
end

local function optics(c: Canvas, p: Palette)
	Glyph.chamferRect(c, 22, 8, 20, 12, 3, p.fg, "top")
	Glyph.ring(c, 32, 38, 18, 6, p.fg)
	Glyph.circle(c, 32, 38, 8, p.fg)
	Glyph.circle(c, 29, 35, 2.5, p.detail)
end

local function trackRun(c: Canvas, p: Palette, marker: "both" | "left" | "right")
	Glyph.chamferRect(c, 6, 22, 52, 22, 9, p.fg, "all")
	Glyph.chamferRect(c, 11, 27, 42, 12, 5, p.detail, "all")
	for _, x in { 18, 27, 37, 46 } do
		Glyph.circle(c, x, 33, 4, p.fg)
	end
	if marker == "left" then
		Glyph.wedge(c, 6, 52, 6, "left", p.fg)
		Glyph.rect(c, 12, 50, 16, 4, p.fg, { name = "Side" })
	elseif marker == "right" then
		Glyph.wedge(c, 58, 52, 6, "right", p.fg)
		Glyph.rect(c, 36, 50, 16, 4, p.fg, { name = "Side" })
	end
end

local function fire(c: Canvas, p: Palette)
	Glyph.circle(c, 32, 42, 14, p.fg)
	Glyph.wedge(c, 32, 10, 18, "up", p.fg)
	Glyph.circle(c, 32, 45, 7, p.highlight)
	Glyph.wedge(c, 32, 30, 8, "up", p.highlight)
end

local function repair(c: Canvas, p: Palette)
	Glyph.line(c, 18, 46, 40, 24, 7, p.fg)
	Glyph.ring(c, 44, 20, 11, 5, p.fg)
	Glyph.box(c, 50, 14, 8, 6, p.detail, { rotation = 45, name = "Jaw" })
	Glyph.circle(c, 16, 48, 5, p.fg)
end

local function damagedBadge(c: Canvas)
	local warning = Theme.color("state.warning")
	Glyph.wedge(c, 50, 38, 13, "up", Theme.ink)
	Glyph.wedge(c, 50, 41, 10.5, "up", warning)
	Glyph.bang(c, 50, 47, 7, Theme.ink)
end

local function destroyedBadge(c: Canvas)
	Glyph.circle(c, 50, 50, 11, Theme.ink)
	Glyph.circle(c, 50, 50, 9, Theme.color("state.danger"))
	Glyph.cross(c, 50, 50, 8, 3, Theme.ink)
end

local function withState(
	build: (Canvas, Palette) -> (),
	state: "normal" | "damaged" | "destroyed"
): (Canvas, Palette) -> ()
	return function(c: Canvas, p: Palette)
		build(c, p)
		if state == "damaged" then
			damagedBadge(c)
		elseif state == "destroyed" then
			destroyedBadge(c)
		end
	end
end

local Modules: { [string]: Entry } = {}

local MODULES: { [string]: (Canvas, Palette) -> () } = {
	engine = engine,
	ammo_rack = ammoRack,
	fuel_tank = fuelTank,
	gun = gun,
	turret_ring = turretRing,
	optics = optics,
	track = function(c: Canvas, p: Palette)
		trackRun(c, p, "both")
	end,
	track_left = function(c: Canvas, p: Palette)
		trackRun(c, p, "left")
	end,
	track_right = function(c: Canvas, p: Palette)
		trackRun(c, p, "right")
	end,
}

for name, build in MODULES do
	Modules["modules/" .. name] = { build = withState(build, "normal"), color = "accent.steel" }
	Modules["modules/" .. name .. "_damaged"] = { build = withState(build, "damaged"), color = "state.warning" }
	Modules["modules/" .. name .. "_destroyed"] = { build = withState(build, "destroyed"), color = "state.danger" }
end
Modules["modules/fire"] = { build = fire, color = "accent.dusk" }
Modules["modules/repair"] = { build = repair, color = "state.success" }

-- Crew: role tools.
local function commander(c: Canvas, p: Palette)
	Glyph.ring(c, 21, 34, 12, 5, p.fg)
	Glyph.ring(c, 43, 34, 12, 5, p.fg)
	Glyph.rect(c, 28, 28, 8, 8, p.fg, { name = "Bridge" })
	Glyph.rect(c, 13, 18, 12, 6, p.fg, { name = "EyecupL" })
	Glyph.rect(c, 39, 18, 12, 6, p.fg, { name = "EyecupR" })
end

local function gunner(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 20, 4.5, p.fg)
	Glyph.rect(c, 30, 6, 4, 14, p.fg, { name = "TickN" })
	Glyph.rect(c, 30, 44, 4, 14, p.fg, { name = "TickS" })
	Glyph.rect(c, 6, 30, 14, 4, p.fg, { name = "TickW" })
	Glyph.rect(c, 44, 30, 14, 4, p.fg, { name = "TickE" })
	Glyph.circle(c, 32, 32, 3.5, p.fg)
end

local function driver(c: Canvas, p: Palette)
	Glyph.ring(c, 32, 32, 22, 6, p.fg)
	Glyph.circle(c, 32, 32, 6, p.fg)
	Glyph.line(c, 12, 30, 26, 32, 5, p.fg)
	Glyph.line(c, 52, 30, 38, 32, 5, p.fg)
	Glyph.line(c, 32, 38, 32, 52, 5, p.fg)
end

local function loader(c: Canvas, p: Palette)
	Glyph.rect(c, 25, 22, 14, 34, p.fg)
	Glyph.wedge(c, 32, 12, 7, "up", p.fg)
	Glyph.rect(c, 25, 40, 14, 3, p.detail, { name = "Band" })
	Glyph.line(c, 12, 34, 24, 30, 5, p.fg)
	Glyph.line(c, 52, 34, 40, 30, 5, p.fg)
end

local function injuredBadge(c: Canvas)
	Glyph.octagon(c, 50, 50, 20, Theme.ink)
	Glyph.octagon(c, 50, 50, 16, Theme.color("state.danger"))
	Glyph.bang(c, 50, 50, 10, Theme.ink)
end

local CREW: { [string]: (Canvas, Palette) -> () } = {
	commander = commander,
	gunner = gunner,
	driver = driver,
	loader = loader,
}

for name, build in CREW do
	Modules["crew/" .. name] = { build = build, color = "brand.bone" }
	Modules["crew/" .. name .. "_injured"] = {
		build = function(c: Canvas, p: Palette)
			build(c, p)
			injuredBadge(c)
		end,
		color = "brand.bone",
	}
end

return Modules
