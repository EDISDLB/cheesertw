--!strict
--[[
	Components/ProgressBar — determinate (spring-animated) and indeterminate progress, with an optional ghost fill.

	Purpose:          A bg.inset track with a 1 px bevel_lo border and a fill in a token colour (default accent.dusk;
	                  XP bars pass "currency.vehicle_xp"). Determinate fills follow the value with a critically damped
	                  spring (Motion.follow) so jumps read as motion, never overshoot, and snap under reduced motion.
	                  A `ghost` value draws a lighter fill behind (pending XP on the results screen). `segments` adds
	                  tick separators (module HP, crew levels). Indeterminate mode sweeps a 30 % block across the
	                  track (static half-tone block under reduced motion).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Motion, Components/Common, Core/Trove.
	State:            A Trove per bar (spring loop, indeterminate tween), cleaned with the bar.
	Validation:       Values are clamped to 0..1 (NaN -> 0).
	Error handling:   N/A.
	Performance notes: Spring runs only while moving (Motion.follow stops when settled).
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Motion = require("../Motion")
local Common = require("./Common")
local Trove = require("@game/ReplicatedStorage/Shared/Core/Trove")

type CanBeState<T> = State.CanBeState<T>
type State<T> = State.State<T>

export type ProgressBarProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	--- 0..1.
	value: CanBeState<number>?,
	indeterminate: CanBeState<boolean>?,
	--- Lighter fill drawn behind `value` (0..1), e.g. XP about to be added.
	ghost: CanBeState<number>?,
	color: Common.ColorProp?,
	--- Track height in px (default 6).
	height: number?,
	--- Number of equal segments (draws segments-1 separators).
	segments: number?,
	--- Spring-animate value changes (default true).
	animate: boolean?,
}

local ProgressBar = {}

ProgressBar.SWEEP_PERIOD = 1.2
ProgressBar.SWEEP_WIDTH = 0.3

--- Pure: clamps a progress value to 0..1 (NaN and nil -> 0).
function ProgressBar.clamp(value: number?): number
	if value == nil or value ~= value then
		return 0
	end
	return math.clamp(value, 0, 1)
end

--- Pure: separator positions (fractions) for `segments` equal segments.
function ProgressBar.separators(segments: number): { number }
	local out = {}
	local count = math.floor(segments)
	for i = 1, count - 1 do
		table.insert(out, i / count)
	end
	return out
end

function ProgressBar.new(props: ProgressBarProps): Frame
	local height = props.height or 6
	local scope = Trove.new()
	local target: State<number> = State.map(props.value or 0, ProgressBar.clamp)
	local shown: State<number> = if props.animate == false then target else Motion.follow(target, scope)
	local indeterminate: CanBeState<boolean> = props.indeterminate or false
	local color = Common.color(props.color, "accent.dusk")
	local children: { Instance } = {
		Create.UIStroke({
			Color = Theme.color("border.bevel_lo"),
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}
	if props.ghost ~= nil then
		local ghost = State.map(props.ghost :: CanBeState<number>, ProgressBar.clamp)
		table.insert(
			children,
			Create.Frame({
				Name = "Ghost",
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				BackgroundTransparency = 0.6,
				Size = State.map(ghost, function(v: number): UDim2
					return UDim2.fromScale(v, 1)
				end),
				Visible = Common.negate(indeterminate),
				ZIndex = 2,
			})
		)
	end
	table.insert(
		children,
		Create.Frame({
			Name = "Fill",
			BorderSizePixel = 0,
			BackgroundColor3 = color,
			Size = State.map(shown, function(v: number): UDim2
				return UDim2.fromScale(v, 1)
			end),
			Visible = Common.negate(indeterminate),
			ZIndex = 3,
		})
	)
	local sweep = Create.Frame({
		Name = "Sweep",
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		Size = UDim2.fromScale(ProgressBar.SWEEP_WIDTH, 1),
		Position = UDim2.fromScale(-ProgressBar.SWEEP_WIDTH, 0),
		Visible = indeterminate,
		ZIndex = 3,
	})
	table.insert(children, sweep)
	if props.segments ~= nil and props.segments > 1 then
		for i, fraction in ProgressBar.separators(props.segments) do
			table.insert(
				children,
				Create.Frame({
					Name = "Separator" .. i,
					BorderSizePixel = 0,
					BackgroundColor3 = Theme.color("bg.inset"),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(fraction, 0),
					Size = UDim2.new(0, 2, 1, 0),
					ZIndex = 4,
				})
			)
		end
	end
	local sweepTween: Tween? = nil
	local function stopSweep()
		if sweepTween ~= nil then
			sweepTween:Cancel()
			sweepTween = nil
		end
	end
	scope:Add(stopSweep)
	local function runSweep(active: boolean)
		stopSweep()
		if not active then
			return
		end
		if Motion.isReduced() then
			sweep.Position = UDim2.fromScale(0, 0)
			sweep.Size = UDim2.fromScale(1, 1)
			sweep.BackgroundTransparency = 0.5
			return
		end
		sweep.Size = UDim2.fromScale(ProgressBar.SWEEP_WIDTH, 1)
		sweep.BackgroundTransparency = 0
		sweep.Position = UDim2.fromScale(-ProgressBar.SWEEP_WIDTH, 0)
		sweepTween = Motion.tween(
			sweep,
			{ Position = UDim2.fromScale(1, 0) },
			{ duration = ProgressBar.SWEEP_PERIOD, easing = "linear", repeatCount = -1, kind = "move" }
		)
	end
	State.effect(function()
		local active = State.get(indeterminate)
		State.untracked(function(): nil
			runSweep(active)
			return nil
		end)
		return nil
	end, { scope = scope, name = "ProgressBar.sweep" })
	local values: { [any]: any } = Common.layout(props, {}, { Name = "ProgressBar", Size = UDim2.new(1, 0, 0, height) })
	values.BackgroundColor3 = Theme.color("bg.inset")
	values.BorderSizePixel = 0
	values.ClipsDescendants = true
	values[Create.Children] = children
	values[Create.Cleanup] = scope
	return Common.parent(Create.Frame(values), props)
end

return ProgressBar
