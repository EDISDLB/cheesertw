--!strict
--[[
	Components/Slider — numeric slider for settings (volumes, sensitivities, UI scale).

	Purpose:          Label + value readout (Builder Mono) over a chamfered `bg.inset` track with an `accent.steel`
	                  fill and thumb. Mouse/touch drag on the track; gamepad/keyboard: while the track is selected,
	                  D-pad / arrow keys / A-D / left thumbstick step by `step` (horizontal neighbours point at the
	                  slider itself so selection does not leave sideways; up/down navigate away). ui_slider_tick per
	                  step (the AudioEngine rate-limits it).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Sound, Kit/Services, Components/Chamfer, Components/Text,
	                  Components/Common.
	State:            The bound Value, drag flag, thumbstick repeat timer.
	Validation:       min < max required; step > 0 when given; values are clamped and snapped (pure helpers).
	Error handling:   Invalid ranges raise at build time.
	Performance notes: Global input listeners are connected only while dragging or selected.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Sound = require("../Sound")
local Services = require("../Services")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type SliderProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	value: State.Value<number>,
	min: number,
	max: number,
	step: number?,
	label: CanBeState<string>?,
	--- Readout text (default: the number with the step's decimals).
	format: ((value: number) -> string)?,
	onChanged: ((value: number) -> ())?,
	disabled: CanBeState<boolean>?,
}

local Slider = {}

local STICK_THRESHOLD = 0.6
--- Height of the drawn track row (the touch hit area is taller, see Slider.new).
local TRACK_HEIGHT = 24
local STICK_REPEAT = 0.15

--- Pure: clamps to [min, max] and snaps to the step grid anchored at min.
function Slider.snap(value: number, min: number, max: number, step: number?): number
	local v = math.clamp(if value ~= value then min else value, min, max)
	if step ~= nil and step > 0 then
		-- The epsilon rounds decimal halves up despite binary noise (0.35 / 0.1 = 3.4999999999999996).
		v = min + math.floor((v - min) / step + 0.5 + 1e-9) * step
		v = math.clamp(v, min, max)
		-- Remove binary noise (0.1 + 0.2).
		local decimals = math.max(0, math.ceil(-math.log10(step) + 1e-9))
		local factor = 10 ^ decimals
		v = math.floor(v * factor + 0.5) / factor
	end
	return v
end

--- Pure: position of `value` along the track (0..1).
function Slider.fraction(value: number, min: number, max: number): number
	if max <= min then
		return 0
	end
	return math.clamp((value - min) / (max - min), 0, 1)
end

--- Pure: value for a track fraction (snapped).
function Slider.fromFraction(fraction: number, min: number, max: number, step: number?): number
	return Slider.snap(min + math.clamp(fraction, 0, 1) * (max - min), min, max, step)
end

local function decimalsOf(step: number?): number
	if step == nil or step <= 0 or step >= 1 then
		return 0
	end
	return math.ceil(-math.log10(step) - 1e-9)
end

function Slider.new(props: SliderProps): Frame
	if not (props.max > props.min) then
		error("Slider: max must be greater than min", 2)
	end
	if props.step ~= nil and props.step <= 0 then
		error("Slider: step must be > 0", 2)
	end
	local min, max, step = props.min, props.max, props.step
	local value = props.value
	local disabled = props.disabled or false
	local decimals = decimalsOf(step)
	local format = props.format or function(v: number): string
		return string.format(`%.{decimals}f`, v)
	end
	local function commit(newValue: number)
		local snapped = Slider.snap(newValue, min, max, step)
		if snapped ~= value:peek() then
			value:set(snapped)
			Sound.play(Sound.KEYS.slider)
			if props.onChanged ~= nil then
				props.onChanged(snapped)
			end
		end
	end
	local fraction = State.Computed(function(): number
		return Slider.fraction(value:get(), min, max)
	end)
	-- The visual track is a 24 px row at the bottom; on touch the hit area grows upward to the 44 px minimum
	-- (48 authored on Compact) behind the label, so the drawn slider does not move.
	local hitHeight = Common.touchHeight(TRACK_HEIGHT)
	local track = Create.TextButton({
		Name = "Track",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = true,
		Position = State.map(hitHeight, function(h: number): UDim2
			return UDim2.new(0, 0, 1, -h)
		end),
		Size = State.map(hitHeight, function(h: number): UDim2
			return UDim2.new(1, 0, 0, h)
		end),
	})
	track.NextSelectionLeft = track
	track.NextSelectionRight = track
	local interaction = Common.trackInteraction(track, false)
	local fillColor = State.Computed(function(): Color3
		return if State.get(disabled) then Theme.color("text.disabled"):get() else Theme.color("accent.steel"):get()
	end)
	Create.apply(track, {
		[Create.Children] = {
			Create.Frame({
				Name = "Bar",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 1, -TRACK_HEIGHT / 2),
				Size = UDim2.new(1, 0, 0, 8),
				ZIndex = 2,
				[Create.Children] = {
					Chamfer.new({
						corners = "all",
						size = 2,
						fill = Theme.color("bg.inset"),
						border = Theme.color("border.bevel_lo"),
						zIndex = 2,
					}) :: Instance,
					Create.Frame({
						Name = "Fill",
						BorderSizePixel = 0,
						BackgroundColor3 = fillColor,
						Size = State.Computed(function(): UDim2
							return UDim2.fromScale(fraction:get(), 1)
						end),
						ZIndex = 3,
					}),
				},
			}),
			Create.Frame({
				Name = "Thumb",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = State.Computed(function(): UDim2
					return UDim2.new(fraction:get(), 0, 1, -TRACK_HEIGHT / 2)
				end),
				Size = UDim2.fromOffset(12, 20),
				ZIndex = 5,
				[Create.Children] = {
					Chamfer.new({
						corners = "brand",
						size = 3,
						fill = State.Computed(function(): Color3
							if State.get(disabled) then
								return Theme.color("text.disabled"):get()
							end
							return if interaction.hovered:get() or interaction.selected:get()
								then Theme.color("accent.dusk_hi"):get()
								else Theme.color("text.primary"):get()
						end),
						zIndex = 5,
					}),
				},
			}),
		},
	})

	-- Pointer dragging.
	local UserInputService = Services.input()
	local dragConnections: { RBXScriptConnection } = {}
	local function stopDrag()
		for _, connection in dragConnections do
			connection:Disconnect()
		end
		table.clear(dragConnections)
	end
	local function setFromScreenX(x: number)
		local position, size = track.AbsolutePosition, track.AbsoluteSize
		if size.X <= 0 then
			return
		end
		commit(Slider.fromFraction((x - position.X) / size.X, min, max, step))
	end
	Create.apply(track, {
		[Create.On("InputBegan")] = function(input: InputObject)
			if State.peek(disabled) then
				return
			end
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				setFromScreenX(input.Position.X)
				stopDrag()
				table.insert(
					dragConnections,
					UserInputService.InputChanged:Connect(function(changed: InputObject)
						local t = changed.UserInputType
						if t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch then
							setFromScreenX(changed.Position.X)
						end
					end)
				)
				table.insert(
					dragConnections,
					UserInputService.InputEnded:Connect(function(ended: InputObject)
						local t = ended.UserInputType
						if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
							stopDrag()
						end
					end)
				)
			end
		end,
		[Create.Cleanup] = stopDrag,
	})

	-- Gamepad / keyboard stepping while selected.
	local stepSize = step or (max - min) / 20
	local selectionConnections: { RBXScriptConnection } = {}
	local lastStick = 0
	local function stopStepping()
		for _, connection in selectionConnections do
			connection:Disconnect()
		end
		table.clear(selectionConnections)
	end
	local function nudge(direction: number)
		if not State.peek(disabled) then
			commit(value:peek() + direction * stepSize)
		end
	end
	Create.apply(track, {
		[Create.On("SelectionGained")] = function()
			stopStepping()
			table.insert(
				selectionConnections,
				UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
					local key = input.KeyCode
					-- D-pad presses on the selected slider are ours even though GuiService marks navigation input
					-- as processed (NextSelectionLeft/Right point at the slider itself); keyboard keys respect it
					-- so typing in a TextBox never moves a slider.
					local dpad = key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.DPadRight
					if processed and not dpad then
						return
					end
					if key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.Left or key == Enum.KeyCode.A then
						nudge(-1)
					elseif key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.Right or key == Enum.KeyCode.D then
						nudge(1)
					end
				end)
			)
			table.insert(
				selectionConnections,
				UserInputService.InputChanged:Connect(function(input: InputObject)
					if input.KeyCode ~= Enum.KeyCode.Thumbstick1 then
						return
					end
					local x = input.Position.X
					local now = os.clock()
					if math.abs(x) >= STICK_THRESHOLD and now - lastStick >= STICK_REPEAT then
						lastStick = now
						nudge(if x > 0 then 1 else -1)
					end
				end)
			)
		end,
		[Create.On("SelectionLost")] = stopStepping,
		[Create.Cleanup] = stopStepping,
	})

	local header: { Instance } = {}
	if props.label ~= nil then
		table.insert(header, Text.new({ Name = "Label", text = props.label, role = "label", color = "text.secondary" }))
	end
	table.insert(
		header,
		Text.new({
			Name = "Value",
			text = State.map(value, format),
			role = "mono",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
		})
	)
	local values: { [any]: any } = Common.layout(props, {}, { Name = "Slider", Size = UDim2.fromOffset(320, 56) })
	values.BackgroundTransparency = 1
	values[Create.Children] = {
		Create.Frame({
			Name = "Header",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 24),
			[Create.Children] = header,
		}) :: Instance,
		track,
	}
	return Common.parent(Create.Frame(values), props)
end

return Slider
