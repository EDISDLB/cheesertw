--!strict
--[[
	Components/Toggle — on/off switch row (settings, filters).

	Purpose:          A full-width row (44 px, a valid touch target) with the label on the left and a chamfered
	                  switch on the right: track `bg.inset` -> `accent.steel` when on (brand-art §3.2: steel is the
	                  neutral interactive chrome), knob slides left/right (position, not colour alone, carries the
	                  state). Two-way binding through a Value, or controlled through `checked` + `onChanged`.
	                  Sounds ui_toggle_on / ui_toggle_off; gamepad A toggles.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Motion, Kit/Sound, Components/Chamfer, Components/Text,
	                  Components/Common.
	State:            The value (given or internal) and interaction Values.
	Validation:       N/A.
	Error handling:   onChanged errors propagate to the engine's event handler.
	Performance notes: ~20 Frames; knob moves with a short tween (instant under reduced motion).
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Motion = require("../Motion")
local Sound = require("../Sound")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type ToggleProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	--- Two-way bound value (wins over checked).
	value: State.Value<boolean>?,
	--- Controlled value (use with onChanged).
	checked: CanBeState<boolean>?,
	onChanged: ((checked: boolean) -> ())?,
	label: CanBeState<string>?,
	disabled: CanBeState<boolean>?,
}

local Toggle = {}

local TRACK = Vector2.new(48, 24)
local KNOB = Vector2.new(20, 18)

function Toggle.new(props: ToggleProps): TextButton
	local internal: State.Value<boolean> = props.value or State.Value(State.peek(props.checked or false))
	local checked: CanBeState<boolean> = if props.value ~= nil
		then props.value
		elseif props.checked ~= nil then props.checked
		else internal
	local disabled = props.disabled or false
	local button = Create.TextButton({
		Name = props.Name or "Toggle",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = true,
	})
	local interaction = Common.trackInteraction(button, true)
	local function knobPosition(on: boolean): UDim2
		return if on then UDim2.new(1, -(KNOB.X + 2), 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
	end
	local knob = Create.Frame({
		Name = "Knob",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = knobPosition(State.peek(checked)),
		Size = UDim2.fromOffset(KNOB.X, KNOB.Y),
		ZIndex = 4,
		[Create.Children] = {
			Chamfer.new({
				corners = "all",
				size = 3,
				fill = State.Computed(function(): Color3
					if State.get(disabled) then
						return Theme.color("text.disabled"):get()
					end
					return if State.get(checked)
						then Theme.color("text.primary"):get()
						else Theme.color("text.tertiary"):get()
				end),
				zIndex = 4,
			}),
		},
	})
	-- The knob animation observer lives exactly as long as the button (no rooted observer outliving it).
	local knobObserver: State.Connection? = nil
	if State.isState(checked) then
		knobObserver = State.observe(checked :: State.State<boolean>, function(on: boolean)
			Motion.tween(knob, { Position = knobPosition(on) }, { duration = "fast", kind = "move" })
		end)
	end
	local track = Create.Frame({
		Name = "Track",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(TRACK.X, TRACK.Y),
		ZIndex = 2,
		[Create.Children] = {
			Chamfer.new({
				corners = "all",
				size = 4,
				fill = State.Computed(function(): Color3
					return if State.get(checked) and not State.get(disabled)
						then Theme.color("accent.steel"):get()
						else Theme.color("bg.inset"):get()
				end),
				border = State.Computed(function(): Color3
					return if interaction.hovered:get() and not State.get(disabled)
						then Theme.color("text.secondary"):get()
						else Theme.color("border.strong"):get()
				end),
				zIndex = 2,
			}) :: Instance,
			knob,
		},
	})
	local values: { [any]: any } = Common.layout(props, {}, { Size = UDim2.new(0, 320, 0, Theme.sizes.touchMin) })
	local children: { Instance } = { track }
	if props.label ~= nil then
		table.insert(
			children,
			Text.new({
				Name = "Label",
				text = props.label,
				role = "body",
				color = State.Computed(function(): Color3
					return if State.get(disabled)
						then Theme.color("text.disabled"):get()
						else Theme.color("text.primary"):get()
				end),
				Size = UDim2.new(1, -(TRACK.X + Theme.space(3)), 1, 0),
				truncate = true,
				wrap = false,
			})
		)
	end
	values[Create.Children] = children
	values[Create.On("Activated")] = function()
		if State.peek(disabled) then
			Sound.play(Sound.KEYS.error)
			return
		end
		local nextValue = not State.peek(checked)
		Sound.play(if nextValue then Sound.KEYS.toggleOn else Sound.KEYS.toggleOff)
		local bound = props.value
		if bound ~= nil then
			bound:set(nextValue)
		elseif props.checked == nil then
			internal:set(nextValue)
		end
		if props.onChanged ~= nil then
			props.onChanged(nextValue)
		end
	end
	if knobObserver ~= nil then
		values[Create.Cleanup] = knobObserver
	end
	Create.apply(button, values)
	return Common.parent(button, props)
end

return Toggle
