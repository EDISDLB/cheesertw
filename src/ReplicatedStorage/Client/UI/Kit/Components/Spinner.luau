--!strict
--[[
	Components/Spinner — indeterminate activity indicator.

	Purpose:          A half-ring arc (UIStroke + gradient mask) turning once per 0.9 s over a faint full ring.
	                  Reduced motion: the arc stays still (the faint ring + arc still read as "busy").
	Dependencies:     Kit/Create, Kit/Theme, Kit/Motion, Components/Common.
	State:            The rotation tween (cancelled when the spinner is destroyed).
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: Engine tween; 2 Frames.
]]

local Create = require("../Create")
local Motion = require("../Motion")
local Common = require("./Common")
local State = require("../State")

type CanBeState<T> = State.CanBeState<T>

export type SpinnerProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	size: number?,
	color: Common.ColorProp?,
}

local Spinner = {}

local function ring(name: string, size: number, color: any, transparency: number, arc: boolean): Frame
	local strokeChildren: { Instance } = {}
	if arc then
		table.insert(
			strokeChildren,
			Create.UIGradient({
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(0.501, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
			})
		)
	end
	local thickness = math.max(2, math.floor(size / 8))
	return Create.Frame({
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size - 2 * thickness, size - 2 * thickness),
		[Create.Children] = {
			Create.UICorner({ CornerRadius = UDim.new(0.5, 0) }) :: Instance,
			Create.UIStroke({
				Color = color,
				Thickness = thickness,
				Transparency = transparency,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				[Create.Children] = strokeChildren,
			}),
		},
	})
end

function Spinner.new(props: SpinnerProps?): Frame
	local opts: SpinnerProps = props or {}
	local size = opts.size or 24
	local color = Common.color(opts.color, "accent.steel")
	local arc = ring("Arc", size, color, 0, true)
	local values: { [any]: any } = Common.layout(opts, {}, { Name = "Spinner", Size = UDim2.fromOffset(size, size) })
	values.BackgroundTransparency = 1
	values[Create.Children] = { ring("Track", size, color, 0.75, false), arc }
	local frame = Create.Frame(values)
	local tween = Motion.tween(
		arc,
		{ Rotation = 360 },
		{ duration = 0.9, easing = "linear", repeatCount = -1, kind = "move" }
	)
	if tween ~= nil then
		Create.onDestroy(frame, function()
			tween:Cancel()
		end)
	end
	return Common.parent(frame, opts)
end

return Spinner
