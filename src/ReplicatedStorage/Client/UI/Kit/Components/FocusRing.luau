--!strict
--[[
	Components/FocusRing — the brand gamepad focus adornment (SelectionImageObject templates).

	Purpose:          brand-art §8.3: focus = 2 px `accent.dusk_hi` ring offset 2 px + animated corner brackets;
	                  destructive actions use a `state.danger` ring. Built as a chamfered outline (HULLDOWN cut)
	                  sized with scale UDim2 (1, 8, 1, 8) so it overlays any selected GuiObject (the engine sizes a
	                  SelectionImageObject relative to the selected element). Brackets mark the two uncut corners.
	                  The ring is centred on the element; its "breathing" (Motion.pulse) starts/stops live with reduced
	                  motion.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Motion, Components/Chamfer.
	State:            One cached template per variant and its reduced-motion observer (session lifetime; never parented).
	Validation:       Unknown variants raise.
	Error handling:   N/A.
	Performance notes: Two shared templates for the whole UI; the engine draws them only for the selected object.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Motion = require("../Motion")
local Chamfer = require("./Chamfer")

export type Variant = "default" | "danger"

local FocusRing = {}

local OFFSET = 4
local BRACKET = 8

local cache: { [string]: Frame } = {}

local function bracket(name: string, anchor: Vector2, position: UDim2, color: any): Frame
	local horizontalX = if anchor.X > 0.5 then UDim2.new(1, -BRACKET, 0, 0) else UDim2.new(0, 0, 0, 0)
	local verticalY = if anchor.Y > 0.5 then UDim2.new(0, 0, 1, -BRACKET) else UDim2.new(0, 0, 0, 0)
	return Create.Frame({
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = anchor,
		Position = position,
		Size = UDim2.fromOffset(BRACKET, BRACKET),
		[Create.Children] = {
			Create.Frame({
				Name = "H",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				Position = UDim2.new(horizontalX.X, if anchor.Y > 0.5 then UDim.new(1, -2) else UDim.new(0, 0)),
				Size = UDim2.new(1, 0, 0, 2),
			}),
			Create.Frame({
				Name = "V",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				Position = UDim2.new(if anchor.X > 0.5 then UDim.new(1, -2) else UDim.new(0, 0), verticalY.Y),
				Size = UDim2.new(0, 2, 1, 0),
			}),
		},
	})
end

--- Builds a new ring template (not cached).
function FocusRing.build(variant: Variant?): Frame
	local color = if variant == "danger" then Theme.color("state.danger") else Theme.color("accent.dusk_hi")
	-- Centred on the selected element so the pulse (a UIScale) breathes around its middle, not its corner.
	local ring = Create.Frame({
		Name = "KitFocusRing",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * OFFSET, 1, 2 * OFFSET),
		ZIndex = Theme.z("top"),
		[Create.Children] = {
			Chamfer.new({
				name = "Outline",
				corners = "brand",
				size = Theme.chamfer("m") + 2,
				border = color,
				borderThickness = Theme.stroke("focus"),
				zIndex = Theme.z("top"),
			}),
			bracket("BracketTopRight", Vector2.new(1, 0), UDim2.new(1, 3, 0, -3), color),
			bracket("BracketBottomLeft", Vector2.new(0, 1), UDim2.new(0, -3, 1, 3), color),
		},
	})
	return ring
end

--- Shared template for a variant (assign to PlayerGui/GuiObject.SelectionImageObject).
function FocusRing.get(variant: Variant?): Frame
	local key = variant or "default"
	if key ~= "default" and key ~= "danger" then
		error(`FocusRing: unknown variant "{tostring(variant)}"`, 2)
	end
	local cached: Frame? = cache[key]
	if cached ~= nil then
		return cached
	end
	local ring = FocusRing.build(key :: Variant)
	-- The bracket pulse follows reduced motion live (static ring when reduced, ui-ux §3.5).
	local stopPulse: (() -> ())? = nil
	State.observe(Theme.state.reducedMotion, function(reduced: boolean)
		if stopPulse ~= nil then
			stopPulse()
			stopPulse = nil
		end
		if not reduced then
			stopPulse = Motion.pulse(ring)
		end
	end, { immediate = true })
	cache[key] = ring
	return ring
end

return FocusRing
