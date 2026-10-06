--!strict
--[[
	Components/IconButton — square icon-only button (close, settings, filters, carousel arrows).

	Purpose:          A Button state machine around one Icon: ghost (default; icon text.secondary -> text.primary on
	                  hover, bg.raised hover plate), secondary (bordered plate) or primary (dusk). 44 px by default so it
	                  is a valid touch target (brand-art §4.2); smaller authored sizes (toast close 32) keep their drawn
	                  plate but grow their hit area to the touch minimum on touch. `label` feeds the tooltip so meaning
	                  never depends on the icon alone.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Sound, Components/Chamfer, Components/Common,
	                  Components/Tooltip (lazy), Icons/Icon.
	State:            Interaction Values per button.
	Validation:       Unknown variants raise.
	Error handling:   onActivated errors propagate to the engine's event handler.
	Performance notes: 1 chamfer surface + 1 icon.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Sound = require("../Sound")
local Chamfer = require("./Chamfer")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")

type CanBeState<T> = State.CanBeState<T>

export type IconButtonProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	icon: CanBeState<string>,
	--- Accessible label: shown as the tooltip.
	label: CanBeState<string>?,
	variant: ("ghost" | "secondary" | "primary")?,
	--- Square size in px (default 44).
	size: number?,
	disabled: CanBeState<boolean>?,
	selected: CanBeState<boolean>?,
	onActivated: (() -> ())?,
	sound: (string | boolean)?,
}

local IconButton = {}

function IconButton.new(props: IconButtonProps): TextButton
	local variant = props.variant or "ghost"
	if variant ~= "ghost" and variant ~= "secondary" and variant ~= "primary" then
		error(`IconButton: unknown variant "{tostring(variant)}"`, 2)
	end
	local size = props.size or Theme.sizes.touchMin
	local disabled = props.disabled or false
	local selected = props.selected or false
	local hitSize = Common.touchHeight(size)
	local button = Create.TextButton({
		Name = props.Name or "IconButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = true,
		Size = State.map(hitSize, function(s: number): UDim2
			return UDim2.fromOffset(s, s)
		end),
	})
	local interaction = Common.trackInteraction(button, true)
	local fill = State.Computed(function(): Color3
		if variant == "primary" then
			return if State.get(disabled)
				then Theme.color("bg.raised"):get()
				elseif interaction.pressed:get() then Theme.color("accent.dusk_lo"):get()
				elseif interaction.hovered:get() then Theme.color("accent.dusk_hi"):get()
				else Theme.color("accent.dusk"):get()
		end
		if interaction.pressed:get() then
			return Theme.color("bg.inset"):get()
		elseif interaction.hovered:get() or State.get(selected) then
			return Theme.color("bg.selected"):get()
		end
		return Theme.color("bg.raised"):get()
	end)
	local fillTransparency = State.Computed(function(): number
		if variant ~= "ghost" then
			return 0
		end
		return if interaction.hovered:get() or interaction.pressed:get() or State.get(selected) then 0 else 1
	end)
	local iconColor = State.Computed(function(): Color3
		if State.get(disabled) then
			return Theme.color("text.disabled"):get()
		elseif variant == "primary" then
			return Theme.color("text.inverse"):get()
		elseif interaction.hovered:get() or State.get(selected) then
			return Theme.color("text.primary"):get()
		end
		return Theme.color("text.secondary"):get()
	end)
	local values: { [any]: any } = Common.layout(props, {})
	values[Create.Children] = {
		-- The drawn plate keeps the authored size, centred in the (possibly larger, touch) hit area.
		Create.Frame({
			Name = "Plate",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			[Create.Children] = {
				Chamfer.new({
					name = "Fill",
					corners = "brand",
					size = 6,
					fill = fill,
					fillTransparency = fillTransparency,
					border = if variant == "secondary" then Theme.color("border.strong") else nil,
				}),
			},
		}),
		Icon.new({
			key = props.icon,
			size = math.floor(size * 0.5),
			color = iconColor,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = State.Computed(function(): UDim2
				return UDim2.new(0.5, 0, 0.5, if interaction.pressed:get() then 1 else 0)
			end),
			ZIndex = 3,
		}),
	}
	values[Create.On("Activated")] = function()
		if Common.consumeLongPress(button) then
			return
		end
		if State.peek(disabled) then
			Sound.play(Sound.KEYS.error)
			return
		end
		if props.sound ~= false then
			Sound.play(if type(props.sound) == "string" then props.sound else Sound.KEYS.click)
		end
		if props.onActivated ~= nil then
			props.onActivated()
		end
	end
	Create.apply(button, values)
	if props.label ~= nil then
		local Tooltip = require("./Tooltip") :: any
		Create.onDestroy(button, Tooltip.attach(button, props.label))
	end
	return Common.parent(button, props)
end

return IconButton
