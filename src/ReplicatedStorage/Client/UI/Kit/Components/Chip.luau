--!strict
--[[
	Components/Chip — tags (static) and chips (selectable filters, removable tokens).

	Purpose:          A 4 px-chamfered pill with an optional leading icon or tone dot, a "label" role caption and an
	                  optional remove cross. Static tags (no handlers) are plain Frames-in-a-TextButton that do not take
	                  gamepad focus; filter chips toggle `selected` (bg.selected fill + accent.steel border); removable
	                  chips call onRemove from the cross (mouse/touch) or from activation when no onActivated is given
	                  (gamepad). Interactive chips grow to the 44 px touch minimum on touch.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Kit/Sound, Components/Chamfer, Components/Text,
	                  Components/Common, Icons/Icon.
	State:            Interaction Values per chip.
	Validation:       N/A.
	Error handling:   Handler errors propagate to the engine's event handler.
	Performance notes: ~10 instances per chip.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Sound = require("../Sound")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")

type CanBeState<T> = State.CanBeState<T>

export type ChipProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	label: CanBeState<string>,
	icon: CanBeState<string>?,
	--- Tone dot (and selected border) colour.
	tone: Theme.Tone?,
	selected: CanBeState<boolean>?,
	disabled: CanBeState<boolean>?,
	onActivated: (() -> ())?,
	removable: boolean?,
	onRemove: (() -> ())?,
}

local Chip = {}

local HEIGHT = 28

function Chip.new(props: ChipProps): TextButton
	local interactive = props.onActivated ~= nil or props.removable == true
	local selected = props.selected or false
	local disabled = props.disabled or false
	local height = if interactive then Common.touchHeight(HEIGHT) else State.Value(HEIGHT)
	local chip = Create.TextButton({
		Name = props.Name or "Chip",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = interactive,
		Active = interactive,
		AutomaticSize = Enum.AutomaticSize.X,
	})
	local interaction = Common.trackInteraction(chip, interactive)
	local toneColor = if props.tone ~= nil and props.tone ~= "neutral" then Theme.tone(props.tone) else nil
	local children: { Instance } = {
		Chamfer.new({
			name = "Fill",
			corners = "brand",
			size = Theme.chamfer("s"),
			fill = State.Computed(function(): Color3
				if State.get(selected) then
					return Theme.color("bg.selected"):get()
				elseif interactive and interaction.hovered:get() then
					return Theme.color("bg.selected"):get():Lerp(Theme.color("bg.raised"):get(), 0.5)
				end
				return Theme.color("bg.raised"):get()
			end),
			border = State.Computed(function(): Color3
				if State.get(selected) then
					return if toneColor ~= nil then toneColor:get() else Theme.color("accent.steel"):get()
				end
				return Theme.color("border.subtle"):get()
			end),
		}),
	}
	-- Content sits in its own auto-sized frame so the scale-sized surface does not take a list slot.
	local content: { Instance } = {
		Layout.padding({ left = Theme.space(2), right = if props.removable then Theme.space(1) else Theme.space(2) }),
		Layout.list({ direction = "x", gap = Theme.space(1), align = "center" }),
	}
	if toneColor ~= nil and props.icon == nil then
		table.insert(
			content,
			Create.Frame({
				Name = "Dot",
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(6, 6),
				BackgroundColor3 = toneColor,
				LayoutOrder = 1,
				ZIndex = 3,
				[Create.Children] = { Create.UICorner({ CornerRadius = UDim.new(0.5, 0) }) },
			})
		)
	end
	if props.icon ~= nil then
		table.insert(
			content,
			Icon.new({
				key = props.icon :: CanBeState<string>,
				size = 16,
				color = toneColor or Theme.color("text.secondary"),
				LayoutOrder = 1,
				ZIndex = 3,
			})
		)
	end
	table.insert(
		content,
		Text.new({
			Name = "Label",
			text = props.label,
			role = "label",
			LayoutOrder = 2,
			ZIndex = 3,
			color = State.Computed(function(): Color3
				if State.get(disabled) then
					return Theme.color("text.disabled"):get()
				end
				return if State.get(selected)
					then Theme.color("text.primary"):get()
					else Theme.color("text.secondary"):get()
			end),
		})
	)
	local function remove()
		if State.peek(disabled) then
			return
		end
		Sound.play(Sound.KEYS.back)
		if props.onRemove ~= nil then
			props.onRemove()
		end
	end
	if props.removable then
		local removeProps: { [any]: any } = {
			Name = "Remove",
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Selectable = false,
			-- 20 px cross; a 44 px target on touch (the only remove path when the chip also has onActivated).
			Size = State.map(Common.touchHeight(20), function(px: number): UDim2
				return UDim2.fromOffset(px, px)
			end),
			LayoutOrder = 3,
			ZIndex = 4,
			[Create.Children] = {
				Icon.new({
					key = "ui/close",
					size = 12,
					color = Theme.color("text.tertiary"),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
				}),
			},
			[Create.On("Activated")] = remove,
		}
		table.insert(content, Create.TextButton(removeProps))
	end
	table.insert(
		children,
		Create.Frame({
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 3,
			[Create.Children] = content,
		})
	)
	local values: { [any]: any } = Common.layout(props, {})
	values.Size = State.map(height, function(h: number): UDim2
		return UDim2.fromOffset(0, h)
	end)
	values[Create.Children] = children
	values[Create.On("Activated")] = function()
		if not interactive or Common.consumeLongPress(chip) then
			return
		end
		if State.peek(disabled) then
			Sound.play(Sound.KEYS.error)
			return
		end
		if props.onActivated ~= nil then
			Sound.play(Sound.KEYS.click)
			props.onActivated()
		elseif props.removable then
			remove()
		end
	end
	Create.apply(chip, values)
	return Common.parent(chip, props)
end

--- Static tag shortcut: `Chip.tag("HEAT", "warning")`.
function Chip.tag(label: CanBeState<string>, tone: Theme.Tone?, props: ChipProps?): TextButton
	local merged: ChipProps = if props then table.clone(props) else { label = label }
	merged.label = label
	merged.tone = tone or merged.tone
	merged.onActivated = nil
	merged.removable = false
	return Chip.new(merged)
end

return Chip
