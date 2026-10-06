--!strict
--[[
	Components/Dropdown — single-choice select with a popup option list.

	Purpose:          A secondary-style field showing the selected option (or a placeholder) and a chevron. Activating
	                  it opens a popup list in the Tooltip layer (above Modals, ui-ux §1.1) under the field (flipped above when there is no room),
	                  with a shadow, an outside-click catcher and a trapped focus scope that starts on the selected
	                  option. Back (gamepad B / Backspace) closes it first through a UIInput back interceptor, so the
	                  Router does not pop the screen. Disabled options are focusable but inert.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layers, Kit/Layout, Kit/Focus, Kit/UIInput, Kit/Sound,
	                  Kit/Services, Components/Chamfer, Components/Shadow, Components/Text, Components/Common,
	                  Icons/Icon.
	State:            The bound selected Value and the open popup (one per dropdown).
	Validation:       Option values should be unique; duplicates select the first match.
	Error handling:   Without a Tooltip layer or ScreenGui ancestor the popup cannot open (logged once).
	Performance notes: The popup is built on open and destroyed on close; lists over 8 options scroll.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layers = require("../Layers")
local Layout = require("../Layout")
local Focus = require("../Focus")
local UIInput = require("../UIInput")
local Sound = require("../Sound")
local Services = require("../Services")
local Chamfer = require("./Chamfer")
local Shadow = require("./Shadow")
local Text = require("./Text")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

type CanBeState<T> = State.CanBeState<T>

export type Option = { value: any, label: string, icon: string?, disabled: boolean? }
export type DropdownProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	options: CanBeState<{ Option }>,
	selected: State.Value<any>,
	onChanged: ((value: any) -> ())?,
	placeholder: string?,
	--- Field width in px (default 240).
	width: number?,
	disabled: CanBeState<boolean>?,
}

local log = Log.scope("UI.Dropdown")

local Dropdown = {}

local ROW_HEIGHT = 40
local MAX_VISIBLE_ROWS = 8

--- Pure: label for the current selection (placeholder when nothing matches).
function Dropdown.labelFor(options: { Option }, value: any, placeholder: string?): (string, boolean)
	for _, option in options do
		if option.value == value then
			return option.label, true
		end
	end
	return placeholder or "Select", false
end

--- Pure: popup top-left (screen px) below the anchor, flipped above when it would leave the viewport.
function Dropdown.popupPosition(
	anchorPosition: Vector2,
	anchorSize: Vector2,
	popupHeight: number,
	viewport: Vector2
): Vector2
	local below = anchorPosition.Y + anchorSize.Y + 4
	if below + popupHeight > viewport.Y and anchorPosition.Y - 4 - popupHeight >= 0 then
		return Vector2.new(anchorPosition.X, anchorPosition.Y - 4 - popupHeight)
	end
	return Vector2.new(anchorPosition.X, math.min(below, math.max(0, viewport.Y - popupHeight)))
end

function Dropdown.new(props: DropdownProps): TextButton
	local width = props.width or 240
	local disabled = props.disabled or false
	local options = props.options
	local isOpen = State.Value(false)
	local field = Create.TextButton({
		Name = props.Name or "Dropdown",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = true,
		Size = UDim2.fromOffset(width, Theme.sizes.touchMin),
	})
	local interaction = Common.trackInteraction(field, true)
	local labelState = State.Computed(function(): string
		local text = Dropdown.labelFor(State.get(options), props.selected:get(), props.placeholder)
		return text
	end)
	local hasValue = State.Computed(function(): boolean
		local _, found = Dropdown.labelFor(State.get(options), props.selected:get(), props.placeholder)
		return found
	end)

	local popup: Frame? = nil
	local scope: Focus.FocusScope? = nil
	local removeInterceptor: (() -> ())? = nil

	local function close()
		if removeInterceptor ~= nil then
			removeInterceptor()
			removeInterceptor = nil
		end
		if scope ~= nil then
			scope:Destroy()
			scope = nil
		end
		if popup ~= nil then
			popup:Destroy()
			popup = nil
		end
		isOpen:set(false)
	end

	local function choose(option: Option)
		if option.disabled then
			Sound.play(Sound.KEYS.error)
			return
		end
		Sound.play(Sound.KEYS.click)
		props.selected:set(option.value)
		close()
		if props.onChanged ~= nil then
			props.onChanged(option.value)
		end
	end

	local function open()
		-- Dropdown lists live in the Tooltip layer (ui-ux §1.1), above Modals, so a dropdown inside a dialog opens on top.
		local parent = Layers.parentFor("Tooltip", field)
		if parent == nil then
			log:warn("dropdown %s has no Tooltip layer or ScreenGui to open in", field.Name)
			return
		end
		local list = State.peek(options)
		-- Option rows are touch targets too: 40 px, raised to 44 (48 authored on Compact) on touch.
		local rowHeight = Common.touchHeight(ROW_HEIGHT):peek()
		local rows: { Instance } = { Layout.list({ gap = 2 }) }
		local selectedRow: GuiObject? = nil
		for index, option in list do
			local row = Create.TextButton({
				Name = "Option" .. index,
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Selectable = true,
				Size = UDim2.new(1, 0, 0, rowHeight),
				LayoutOrder = index,
			})
			local rowInteraction = Common.trackInteraction(row, true)
			local isSelected = option.value == props.selected:peek()
			if isSelected then
				selectedRow = row
			end
			local rowContent: { Instance } = {
				Layout.padding({ x = Theme.space(3) }),
				Layout.list({ direction = "x", gap = Theme.space(2), align = "center" }),
				Text.new({
					text = option.label,
					role = "body",
					color = if option.disabled then "text.disabled" else "text.primary",
					LayoutOrder = 2,
				}),
			}
			if option.icon ~= nil then
				table.insert(
					rowContent,
					Icon.new({
						key = option.icon :: string,
						size = 20,
						color = Theme.color("text.secondary"),
						LayoutOrder = 1,
					})
				)
			end
			local rowChildren: { Instance } = {
				Create.Frame({
					Name = "Fill",
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Theme.color("bg.selected"),
					BackgroundTransparency = State.Computed(function(): number
						return if rowInteraction.hovered:get()
								or rowInteraction.selected:get()
								or isSelected
							then 0
							else 1
					end),
				}),
				Create.Frame({
					Name = "SelectedEdge",
					BorderSizePixel = 0,
					Size = UDim2.new(0, 2, 1, 0),
					BackgroundColor3 = Theme.color("accent.dusk"),
					Visible = isSelected,
					ZIndex = 3,
				}),
				Create.Frame({
					Name = "Row",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 3,
					[Create.Children] = rowContent,
				}),
			}
			Create.apply(row, {
				[Create.Children] = rowChildren,
				[Create.On("Activated")] = function()
					choose(option)
				end,
			})
			table.insert(rows, row)
		end
		local visibleRows = math.min(#list, MAX_VISIBLE_ROWS)
		local height = visibleRows * (rowHeight + 2) + 8
		local scale = 1
		local rootScale = parent:FindFirstChildOfClass("UIScale")
		if rootScale ~= nil then
			scale = rootScale.Scale
		end
		local screenPosition =
			Dropdown.popupPosition(field.AbsolutePosition, field.AbsoluteSize, height * scale, Services.viewportSize())
		-- Into the layer root's content space (its UIScale and the TV-safe UIPadding).
		local localPosition = Layers.toLocal(parent, screenPosition)
		local listFrame = Create.Frame({
			Name = "List",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(localPosition.X, localPosition.Y),
			Size = UDim2.fromOffset(width, height),
			ZIndex = Theme.z("popover"),
			[Create.Children] = {
				Shadow.new({ zIndex = Theme.z("popover") }) :: Instance,
				Chamfer.new({
					corners = "brand",
					size = Theme.chamfer("s"),
					fill = Theme.color("bg.raised"),
					border = Theme.color("border.strong"),
					zIndex = Theme.z("popover"),
				}),
				Create.ScrollingFrame({
					Name = "Options",
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(0, 4),
					Size = UDim2.new(1, 0, 1, -8),
					CanvasSize = UDim2.new(),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					ScrollBarThickness = if #list > MAX_VISIBLE_ROWS then Theme.sizes.scrollBar.mouse else 0,
					ScrollBarImageColor3 = Theme.color("accent.steel"),
					Selectable = false,
					ZIndex = Theme.z("popover") + 1,
					[Create.Children] = rows,
				}),
			},
		})
		local holder = Create.Frame({
			Name = "DropdownPopup",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = Theme.z("popover"),
			[Create.Children] = {
				Create.TextButton({
					Name = "Catcher",
					Text = "",
					AutoButtonColor = false,
					BackgroundTransparency = 1,
					Selectable = false,
					Size = UDim2.fromScale(1, 1),
					ZIndex = Theme.z("popover"),
					[Create.On("Activated")] = close,
				}) :: Instance,
				listFrame,
			},
			Parent = parent,
		})
		popup = holder
		isOpen:set(true)
		-- The Tooltip layer can go away under an open list (router:destroy()): release Back and focus with it.
		holder.Destroying:Connect(function()
			if popup == holder then
				popup = nil
				close()
			end
		end)
		local listScope = Focus.scope(listFrame, { name = "DropdownList", trap = true, initial = selectedRow })
		scope = listScope
		listScope:activate()
		removeInterceptor = UIInput.interceptBack(function(): boolean
			close()
			return true
		end)
		Sound.play(Sound.KEYS.open)
	end

	local values: { [any]: any } = Common.layout(props, {})
	values[Create.Children] = {
		Chamfer.new({
			name = "Fill",
			corners = "brand",
			size = 6,
			fill = State.Computed(function(): Color3
				return if interaction.hovered:get() or isOpen:get()
					then Theme.color("bg.selected"):get()
					else Theme.color("bg.inset"):get()
			end),
			border = State.Computed(function(): Color3
				return if isOpen:get() then Theme.color("accent.steel"):get() else Theme.color("border.strong"):get()
			end),
		}) :: Instance,
		Text.new({
			Name = "Value",
			text = labelState,
			role = "body",
			color = State.Computed(function(): Color3
				if State.get(disabled) then
					return Theme.color("text.disabled"):get()
				end
				return if hasValue:get() then Theme.color("text.primary"):get() else Theme.color("text.tertiary"):get()
			end),
			Position = UDim2.fromOffset(Theme.space(3), 0),
			Size = UDim2.new(1, -(Theme.space(3) * 2 + 24), 1, 0),
			truncate = true,
			wrap = false,
			ZIndex = 3,
		}),
		Icon.new({
			key = State.Computed(function(): string
				return if isOpen:get() then "ui/chevron_up" else "ui/chevron_down"
			end),
			size = 20,
			color = Theme.color("text.secondary"),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Theme.space(3), 0.5, 0),
			ZIndex = 3,
		}),
	}
	values[Create.On("Activated")] = function()
		if Common.consumeLongPress(field) then
			return
		end
		if State.peek(disabled) then
			Sound.play(Sound.KEYS.error)
			return
		end
		if isOpen:peek() then
			close()
		else
			open()
		end
	end
	values[Create.Cleanup] = close
	Create.apply(field, values)
	return Common.parent(field, props)
end

return Dropdown
