--!strict
--[[
	Components/Card — selectable, clickable card (list rows, vehicle tiles, store items).

	Purpose:          brand-art §8.2/§3.5: `bg.raised` card; hover lifts to `bg.selected` with the border going to
	                  `border.strong`; selected adds a 2 px dusk left edge; rarity shows as a 3 px top edge plus a
	                  rarity pip (never a full-card fill). Small HULLDOWN cut (6 px). Gamepad-selectable (the global
	                  focus ring draws the focus state); disabled cards stay focusable (so their tooltip is reachable)
	                  but ignore activation.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Kit/Sound, Components/Chamfer, Components/Common.
	State:            Interaction Values per card.
	Validation:       Unknown rarity names raise (Theme).
	Error handling:   onActivated errors propagate to the engine's event handler (logged by Roblox).
	Performance notes: ~12 Frames; use VirtualList for long card lists.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Sound = require("../Sound")
local Chamfer = require("./Chamfer")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type CardProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	onActivated: (() -> ())?,
	selected: CanBeState<boolean>?,
	disabled: CanBeState<boolean>?,
	rarity: CanBeState<Theme.Rarity?>?,
	padding: number?,
	list: Layout.ListOptions?,
	children: Common.Children?,
	--- UI sound on activation (default ui_click; false = silent).
	sound: (string | boolean)?,
}

local Card = {}

local CUT = 6

function Card.new(props: CardProps): TextButton
	local selected = props.selected or false
	local disabled = props.disabled or false
	local rarity: CanBeState<Theme.Rarity?> = props.rarity or nil :: any
	local button = Create.TextButton({
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = true,
	})
	local interaction = Common.trackInteraction(button, true)
	local fill = State.Computed(function(): Color3
		if State.get(disabled) then
			return Theme.color("bg.panel"):get()
		elseif interaction.pressed:get() then
			return Theme.color("bg.inset"):get()
		elseif interaction.hovered:get() or State.get(selected) then
			return Theme.color("bg.selected"):get()
		end
		return Theme.color("bg.raised"):get()
	end)
	local border = State.Computed(function(): Color3
		if interaction.hovered:get() and not State.get(disabled) then
			return Theme.color("border.strong"):get()
		end
		return Theme.color("border.subtle"):get()
	end)
	local rarityColor = State.Computed(function(): Color3
		local name = State.get(rarity)
		return if name then Theme.rarity(name):get() else Theme.color("rarity.common"):get()
	end)
	local hasRarity = State.Computed(function(): boolean
		return State.get(rarity) ~= nil
	end)
	local contentChildren: { Instance } = { Layout.padding(props.padding or Theme.space(3)) }
	if props.list ~= nil then
		table.insert(contentChildren, Layout.list(props.list))
	end
	local given: { Instance } = props.children or {}
	for _, child in given do
		table.insert(contentChildren, child)
	end
	local values: { [any]: any } = Common.layout(props, {}, { Size = UDim2.fromOffset(280, 96) })
	values[Create.Children] = {
		Chamfer.new({
			name = "Surface",
			corners = "brand",
			size = CUT,
			fill = fill,
			border = border,
			borderThickness = Theme.borderWidth(),
			bevel = true,
		}),
		Create.Frame({
			Name = "SelectedEdge",
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, CUT),
			Size = UDim2.new(0, 2, 1, -CUT),
			BackgroundColor3 = Theme.color("accent.dusk"),
			Visible = selected,
			ZIndex = 4,
		}),
		Create.Frame({
			Name = "RarityEdge",
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(CUT, 0),
			Size = UDim2.new(1, -CUT, 0, 3),
			BackgroundColor3 = rarityColor,
			Visible = hasRarity,
			ZIndex = 4,
		}),
		Create.Frame({
			Name = "RarityPip",
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(8, 8),
			Visible = hasRarity,
			ZIndex = 4,
			[Create.Children] = { Chamfer.new({ corners = "all", size = 2, fill = rarityColor }) },
		}),
		Create.Frame({
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			[Create.Children] = contentChildren,
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
	return Common.parent(button, props)
end

return Card
