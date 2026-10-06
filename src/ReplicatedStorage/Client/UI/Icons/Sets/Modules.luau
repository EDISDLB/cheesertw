--!strict
--[[
	Icons/Sets/Modules — vehicle modules (normal / damaged / destroyed) and crew roles (normal / injured).

	Purpose:          Module silhouettes per brand-art §6.8: engine = piston and crank, ammo rack = three shells in a
	                  clamp rack, fuel tank = hooped drum with a drop, gun = elevated barrel on a trunnion cradle,
	                  turret ring = internally toothed ring with its pinion, optics = two lens barrels on a bridge,
	                  track = track run with its front slope to the right (`track_left` mirrors it), plus fire and
	                  repair. One material per state and a SHAPE change (never colour alone): damaged = amber + a
	                  V-shaped bite at the top-right with a thin crack; destroyed = signal + the silhouette broken in
	                  two by a jagged band. Crew = helmet (olive, bottom-left) + role tool (bone, top-right, the larger
	                  share): commander pennant, gunner crosshair, driver wheel, loader shell; injured = signal +
	                  the first-aid badge. Cut-outs are ink, which reads as a gap on the dark panels they sit on.
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

-- Module outlines follow brand-art §6.8 (each differs in silhouette, not only in interior marks).

local function engine(c: Canvas, p: Palette)
	-- Piston and crank: a ringed piston, its connecting rod and the crank disc with an offset pin.
	Glyph.chamferRect(c, 18, 6, 22, 20, 3, p.fg, "top")
	Glyph.rect(c, 18, 11, 22, 2.5, p.detail, { name = "Ring1" })
	Glyph.rect(c, 18, 16, 22, 2.5, p.detail, { name = "Ring2" })
	Glyph.line(c, 29, 24, 36, 42, 7, p.fg)
	Glyph.circle(c, 36, 44, 14, p.fg)
	Glyph.circle(c, 36, 44, 5, p.detail)
	Glyph.circle(c, 40, 40, 3, p.highlight)
end

local function ammoRack(c: Canvas, p: Palette)
	-- Three shells in a clamp rack.
	for _, x in { 12, 26, 40 } do
		Glyph.rect(c, x, 24, 12, 30, p.fg)
		Glyph.wedge(c, x + 6, 14, 10, "up", p.fg)
		Glyph.rect(c, x, 44, 12, 3, p.detail, { name = "Band" })
	end
	Glyph.rect(c, 8, 32, 48, 5, p.shade, { name = "Clamp" })
	Glyph.rect(c, 8, 54, 48, 4, p.fg, { name = "Rack" })
end

local function fuelTank(c: Canvas, p: Palette)
	-- Hooped drum with a drop.
	Glyph.chamferRect(c, 8, 14, 36, 44, 5, p.fg, "all")
	Glyph.rect(c, 8, 25, 36, 3, p.detail, { name = "Hoop1" })
	Glyph.rect(c, 8, 43, 36, 3, p.detail, { name = "Hoop2" })
	Glyph.rect(c, 15, 9, 8, 5, p.fg, { name = "Bung" })
	Glyph.drop(c, 51, 38, 6.5, p.fg)
end

local function gun(c: Canvas, p: Palette)
	-- Elevated barrel on a trunnion cradle (never a key shape).
	Glyph.halfDisc(c, 20, 52, 14, "top", p.fg)
	Glyph.rect(c, 6, 51, 28, 5, p.fg, { name = "Base" })
	Glyph.circle(c, 20, 44, 4, p.detail)
	Glyph.line(c, 12, 48, 50, 18, 7, p.fg)
	Glyph.box(c, 52, 16.5, 10, 10, p.fg, { rotation = -38, name = "Brake" })
	Glyph.box(c, 52, 16.5, 3, 10, p.detail, { rotation = -38, name = "Port" })
end

local function turretRing(c: Canvas, p: Palette)
	-- Internally toothed ring with its pinion.
	Glyph.ring(c, 30, 32, 24, 6, p.fg)
	for i = 0, 9 do
		local a = math.rad(i * 36 + 18)
		Glyph.box(c, 30 + math.cos(a) * 16.5, 32 + math.sin(a) * 16.5, 5, 4, p.fg, {
			rotation = i * 36 + 18,
			name = "Tooth" .. i,
		})
	end
	Glyph.circle(c, 49, 32, 7, p.shade)
	Glyph.circle(c, 49, 32, 2.5, p.highlight)
end

local function optics(c: Canvas, p: Palette)
	-- Front-view vision device: two lens barrels on a bridge.
	Glyph.chamferRect(c, 8, 14, 48, 10, 3, p.fg, "top")
	Glyph.circle(c, 20, 38, 13, p.fg)
	Glyph.circle(c, 44, 38, 13, p.fg)
	Glyph.circle(c, 20, 38, 7, p.detail)
	Glyph.circle(c, 44, 38, 7, p.detail)
	Glyph.circle(c, 18, 36, 2.5, p.highlight)
	Glyph.circle(c, 42, 36, 2.5, p.highlight)
end

local function trackRun(c: Canvas, p: Palette, front: "left" | "right")
	-- Track run with its front slope (to the right; the left track is the mirror).
	local slopeX = if front == "right" then 44 else 6
	local bodyX = if front == "right" then 6 else 20
	Glyph.rect(c, bodyX, 22, 38, 22, p.fg, { name = "Run" })
	Glyph.triangle(c, slopeX, 22, 14, if front == "right" then "bl" else "br", p.fg)
	Glyph.rect(c, slopeX, 36, 14, 8, p.fg, { name = "Nose" })
	Glyph.rect(c, 10, 28, 44, 10, p.detail, { name = "Inner" })
	for _, x in { 16, 26, 36, 46 } do
		Glyph.circle(c, x, 33, 4.5, p.fg)
	end
end

local function fire(c: Canvas, p: Palette)
	-- Dusk flame with an HE-yellow core (brand §6.8 process indicator).
	Glyph.drop(c, 19, 44, 8, p.fg)
	Glyph.drop(c, 45, 44, 8, p.fg)
	Glyph.drop(c, 32, 40, 14, p.fg)
	Glyph.drop(c, 32, 46, 7, if p.tinted then p.highlight else Theme.peekColor("ammo.he"))
end

local function repair(c: Canvas, p: Palette)
	Glyph.line(c, 18, 46, 40, 24, 7, p.fg)
	Glyph.ring(c, 44, 20, 11, 5, p.fg)
	Glyph.box(c, 50, 14, 8, 6, p.detail, { rotation = 45, name = "Jaw" })
	Glyph.circle(c, 16, 48, 5, p.fg)
end

-- State cuts are placed per module so they bite into (and break through) the actual silhouette.
type Cuts = {
	--- Damaged: V-notch mouth on the outline at (x, y), cutting inwards ("down" from a top edge, "left" from a right
	--- edge), `depth` units deep; the thin crack runs on from its apex.
	bite: { x: number, y: number, dir: "down" | "left", depth: number },
	--- Destroyed: jagged break polyline through the silhouette.
	breakLine: { number },
}

-- Damaged (brand §6.8): a V-shaped bite chipped out of the outline where a crack enters from the top-right, running
-- on as a thin crack. Drawn in ink, which reads as a notch on the dark HUD/garage panels these glyphs sit on.
local function damagedMark(c: Canvas, cuts: Cuts)
	local ink = Theme.ink
	local bite = cuts.bite
	local d = bite.depth
	if bite.dir == "down" then
		Glyph.wedge(c, bite.x, bite.y + d, d, "down", ink)
		Glyph.polyline(
			c,
			{ bite.x, bite.y + d - 0.5, bite.x - 4, bite.y + d + 7, bite.x - 1, bite.y + d + 12 },
			1.6,
			ink
		)
	else
		Glyph.wedge(c, bite.x - d, bite.y, d, "left", ink)
		Glyph.polyline(
			c,
			{ bite.x - d + 0.5, bite.y, bite.x - d - 7, bite.y + 4, bite.x - d - 12, bite.y + 1 },
			1.6,
			ink
		)
	end
end

-- Destroyed (brand §6.8): the silhouette broken in two along a jagged line, halves pushed apart by a clear band.
local function destroyedMark(c: Canvas, cuts: Cuts)
	Glyph.polyline(c, cuts.breakLine, 5, Theme.ink)
end

local function withState(
	build: (Canvas, Palette) -> (),
	cuts: Cuts,
	state: "normal" | "damaged" | "destroyed"
): (Canvas, Palette) -> ()
	return function(c: Canvas, p: Palette)
		build(c, p)
		if state == "damaged" then
			damagedMark(c, cuts)
		elseif state == "destroyed" then
			destroyedMark(c, cuts)
		end
	end
end

local Modules: { [string]: Entry } = {}

type ModuleSpec = { build: (Canvas, Palette) -> (), cuts: Cuts }

local MODULES: { [string]: ModuleSpec } = {
	engine = {
		build = engine,
		cuts = {
			bite = { x = 33, y = 6, dir = "down", depth = 6 },
			breakLine = { 42, 5, 34, 24, 38, 32, 26, 57 },
		},
	},
	ammo_rack = {
		build = ammoRack,
		cuts = {
			bite = { x = 52, y = 44, dir = "left", depth = 6 },
			breakLine = { 37, 12, 30, 33, 35, 40, 28, 58 },
		},
	},
	fuel_tank = {
		build = fuelTank,
		cuts = {
			bite = { x = 35, y = 14, dir = "down", depth = 6 },
			breakLine = { 34, 10, 26, 32, 31, 38, 22, 58 },
		},
	},
	gun = {
		build = gun,
		cuts = {
			bite = { x = 38, y = 23.5, dir = "down", depth = 5 },
			breakLine = { 41, 15, 33, 27, 37, 31, 31, 42 },
		},
	},
	turret_ring = {
		build = turretRing,
		cuts = {
			bite = { x = 40, y = 10, dir = "down", depth = 6 },
			breakLine = { 44, 6, 32, 30, 36, 36, 22, 58 },
		},
	},
	optics = {
		build = optics,
		cuts = {
			bite = { x = 44, y = 14, dir = "down", depth = 6 },
			breakLine = { 38, 12, 30, 30, 35, 36, 28, 52 },
		},
	},
	track = {
		build = function(c: Canvas, p: Palette)
			trackRun(c, p, "right")
		end,
		cuts = {
			bite = { x = 36, y = 22, dir = "down", depth = 6 },
			breakLine = { 38, 18, 32, 30, 36, 34, 30, 48 },
		},
	},
	track_left = {
		build = function(c: Canvas, p: Palette)
			trackRun(c, p, "left")
		end,
		cuts = {
			bite = { x = 46, y = 22, dir = "down", depth = 6 },
			breakLine = { 38, 18, 32, 30, 36, 34, 30, 48 },
		},
	},
	track_right = {
		build = function(c: Canvas, p: Palette)
			trackRun(c, p, "right")
		end,
		cuts = {
			bite = { x = 36, y = 22, dir = "down", depth = 6 },
			breakLine = { 38, 18, 32, 30, 36, 34, 30, 48 },
		},
	},
}

for name, spec in MODULES do
	-- One material per state (brand §6.8): steel normal, amber damaged, signal destroyed.
	Modules["modules/" .. name] = { build = withState(spec.build, spec.cuts, "normal"), material = "steel" }
	Modules["modules/" .. name .. "_damaged"] = {
		build = withState(spec.build, spec.cuts, "damaged"),
		material = "amber",
	}
	Modules["modules/" .. name .. "_destroyed"] = {
		build = withState(spec.build, spec.cuts, "destroyed"),
		material = "signal",
	}
end
Modules["modules/fire"] = { build = fire, color = "accent.dusk" }
Modules["modules/repair"] = { build = repair, color = "state.success" }

-- Crew (brand §6.8): helmet + role tool. The tool is the identifier, so it takes the larger share (top-right) and the
-- helmet sits smaller at the bottom-left. Normal: olive helmet, bone tool. Injured: signal helmet and tool plus the
-- first-aid badge (bone plus on a verdant chamfered tile) at the bottom-right.
type CrewColors = { helmet: Glyph.Paint, helmetShade: Glyph.Paint, tool: Glyph.Paint, detail: Glyph.Paint }

local function helmet(c: Canvas, colors: CrewColors)
	Glyph.halfDisc(c, 21, 50, 15, "top", colors.helmet)
	Glyph.rect(c, 4, 49, 34, 5, colors.helmetShade, { name = "Brim" })
	Glyph.rect(c, 10, 41, 22, 2.5, colors.helmetShade, { name = "Padding" })
end

local function commander(c: Canvas, colors: CrewColors)
	-- Swallowtail pennant on a staff.
	Glyph.rect(c, 33, 4, 3.5, 40, colors.tool, { name = "Staff" })
	Glyph.rect(c, 36.5, 6, 11, 16, colors.tool, { name = "Pennant" })
	Glyph.triangle(c, 47.5, 6, 8, "tl", colors.tool)
	Glyph.triangle(c, 47.5, 14, 8, "bl", colors.tool)
end

local function gunner(c: Canvas, colors: CrewColors)
	-- Crosshair: thin ring, long protruding ticks.
	Glyph.ring(c, 44, 22, 11, 2.5, colors.tool)
	Glyph.rect(c, 42.5, 2, 3, 13, colors.tool, { name = "TickN" })
	Glyph.rect(c, 42.5, 29, 3, 13, colors.tool, { name = "TickS" })
	Glyph.rect(c, 24, 20.5, 13, 3, colors.tool, { name = "TickW" })
	Glyph.rect(c, 51, 20.5, 11, 3, colors.tool, { name = "TickE" })
	Glyph.circle(c, 44, 22, 2, colors.tool)
end

local function driver(c: Canvas, colors: CrewColors)
	-- Steering wheel: heavy rim, three spokes.
	Glyph.ring(c, 44, 22, 16, 5, colors.tool)
	Glyph.circle(c, 44, 22, 4.5, colors.tool)
	Glyph.line(c, 30, 20, 40, 22, 4, colors.tool)
	Glyph.line(c, 58, 20, 48, 22, 4, colors.tool)
	Glyph.line(c, 44, 26, 44, 36, 4, colors.tool)
end

local function loader(c: Canvas, colors: CrewColors)
	-- Upright shell.
	Glyph.rect(c, 39, 16, 12, 26, colors.tool, { name = "Body" })
	Glyph.wedge(c, 45, 4, 6, "up", colors.tool)
	Glyph.rect(c, 39, 10, 12, 6, colors.tool, { name = "Ogive" })
	Glyph.rect(c, 39, 34, 12, 2.5, colors.detail, { name = "Band" })
	Glyph.rect(c, 37, 40, 16, 3, colors.tool, { name = "Rim" })
end

local function firstAidBadge(c: Canvas)
	local verdant = Theme.material("verdant")
	local bone = Theme.material("bone")
	Glyph.chamferRect(c, 40, 40, 22, 22, 4, Theme.ink, "brand")
	Glyph.chamferRect(c, 42, 42, 18, 18, 3.5, verdant.base, "brand")
	Glyph.box(c, 51, 51, 12, 4, bone.highlight, { name = "PlusH" })
	Glyph.box(c, 51, 51, 4, 12, bone.highlight, { name = "PlusV" })
end

local function crewColors(p: Palette, injured: boolean): CrewColors
	if p.tinted then
		return { helmet = p.base, helmetShade = p.shade, tool = p.fg, detail = p.detail }
	end
	if injured then
		local signal = Theme.material("signal")
		return { helmet = signal.base, helmetShade = signal.shade, tool = signal.highlight, detail = Theme.ink }
	end
	local olive = Theme.material("olive")
	local bone = Theme.material("bone")
	return { helmet = olive.base, helmetShade = olive.shade, tool = bone.base, detail = bone.shade }
end

local CREW: { [string]: (Canvas, CrewColors) -> () } = {
	commander = commander,
	gunner = gunner,
	driver = driver,
	loader = loader,
}

for name, tool in CREW do
	Modules["crew/" .. name] = {
		build = function(c: Canvas, p: Palette)
			local colors = crewColors(p, false)
			helmet(c, colors)
			tool(c, colors)
		end,
		color = "brand.bone",
	}
	Modules["crew/" .. name .. "_injured"] = {
		build = function(c: Canvas, p: Palette)
			local colors = crewColors(p, true)
			helmet(c, colors)
			tool(c, colors)
			firstAidBadge(c)
		end,
		color = "state.danger",
	}
end

return Modules
