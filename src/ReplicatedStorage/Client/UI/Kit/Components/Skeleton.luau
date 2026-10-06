--!strict
--[[
	Components/Skeleton — loading placeholders (blocks, text lines, circles) with a slow shimmer.

	Purpose:          Shown while data streams in (profile, store catalogue, tech tree) so layouts do not jump:
	                  bg.raised shapes with a light band sweeping left-to-right every 1.4 s (a UIGradient Offset tween).
	                  Under reduced motion the shimmer is off and the shapes are static — live: turning reduced motion
	                  on (Settings, or GuiService.ReducedMotionEnabled) stops running shimmers, turning it off starts
	                  them. `lines` builds a paragraph stand-in (last line 60 % wide).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Kit/Motion, Components/Common.
	State:            One tween and one reduced-motion effect per shape (both end when the shape is destroyed).
	Validation:       Line counts are clamped to 1..20.
	Error handling:   N/A.
	Performance notes: Engine tweens only; keep to a few dozen shapes per screen.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Motion = require("../Motion")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type Shape = "block" | "lines" | "circle"
export type SkeletonProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	shape: Shape?,
	--- lines: number of lines (default 3).
	lines: number?,
	--- lines: line height in px (default 12).
	lineHeight: number?,
}

local Skeleton = {}

Skeleton.PERIOD = 1.4

local SHIMMER_BAND = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(0.4, 0.15),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.6, 0.15),
	NumberSequenceKeypoint.new(1, 0.15),
})
local SHIMMER_STATIC = NumberSequence.new(0.15)

local function shimmer(frame: GuiObject)
	local gradient = Create.UIGradient({
		Name = "Shimmer",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
		}),
		Transparency = SHIMMER_BAND,
		Offset = Vector2.new(-1, 0),
		Parent = frame,
	})
	local tween: Tween? = nil
	local function stop()
		if tween ~= nil then
			tween:Cancel()
			tween = nil
		end
	end
	-- Follows reduced motion live (an infinite tween started before the player turned it on must stop).
	local connection = State.effect(function()
		local reduced = Theme.state.reducedMotion:get()
		State.untracked(function(): nil
			stop()
			if reduced then
				gradient.Offset = Vector2.new(0, 0)
				gradient.Transparency = SHIMMER_STATIC
			else
				gradient.Transparency = SHIMMER_BAND
				gradient.Offset = Vector2.new(-1, 0)
				tween = Motion.tween(
					gradient,
					{ Offset = Vector2.new(1, 0) },
					{ duration = Skeleton.PERIOD, easing = "linear", repeatCount = -1, kind = "move" }
				)
			end
			return nil
		end)
		return nil
	end, { name = "Skeleton.shimmer" })
	Create.onDestroy(frame, function()
		connection:Disconnect()
		stop()
	end)
end

local function shape(name: string, size: UDim2, circle: boolean, order: number?): Frame
	local frame = Create.Frame({
		Name = name,
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.color("bg.raised"),
		Size = size,
		LayoutOrder = order or 0,
		[Create.Children] = {
			Create.UICorner({ CornerRadius = if circle then UDim.new(0.5, 0) else Theme.radius("s") }),
		},
	})
	shimmer(frame)
	return frame
end

function Skeleton.new(props: SkeletonProps?): Frame
	local opts: SkeletonProps = props or {}
	local kind: Shape = opts.shape or "block"
	if kind == "lines" then
		local count = math.clamp(math.floor(opts.lines or 3), 1, 20)
		local lineHeight = opts.lineHeight or 12
		local children: { Instance } = { Layout.list({ gap = math.floor(lineHeight * 0.75) }) }
		for i = 1, count do
			local width = if i == count and count > 1 then 0.6 else 1
			table.insert(children, shape("Line" .. i, UDim2.new(width, 0, 0, lineHeight), false, i))
		end
		local values: { [any]: any } = Common.layout(opts, {}, { Name = "Skeleton", Size = UDim2.fromScale(1, 0) })
		values.BackgroundTransparency = 1
		values.AutomaticSize = Enum.AutomaticSize.Y
		values[Create.Children] = children
		return Common.parent(Create.Frame(values), opts)
	end
	local frame = shape("Skeleton", UDim2.fromOffset(48, 48), kind == "circle")
	Create.apply(frame, Common.layout(opts, {}))
	if kind == "circle" then
		Create.UIAspectRatioConstraint({ AspectRatio = 1, Parent = frame })
	end
	return Common.parent(frame, opts)
end

return Skeleton
