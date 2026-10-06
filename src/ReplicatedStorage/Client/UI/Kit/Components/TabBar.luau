--!strict
--[[
	Components/TabBar — top-level tabs and segmented sub-tabs, with LB/RB cycling.

	Purpose:          brand-art §8.4. Top tabs: Oswald SemiBold 20 UPPER in text.secondary; the active tab is
	                  text.primary with a 3 px dusk underline carrying a centred 4 px crest notch (the ridge); hover is
	                  text.primary at 80 %; 1 px border.subtle separators. Gamepad: LB/RB cycle tabs (registered with
	                  Kit/Focus, so it works on whatever screen is on top) and shoulder glyphs show at both ends.
	                  Segmented: a bg.inset track, the active segment bg.selected + text.primary + 2 px accent.steel
	                  bottom line. Optional icons and counter badges per tab.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Kit/Focus, Kit/Sound,
	                  Components/Chamfer, Components/Text, Components/KeyPrompt, Components/Badge, Components/Common,
	                  Icons/Icon.
	State:            The bound selected Value; one interaction tracker per tab.
	Validation:       Tab ids must be unique (duplicates keep the first).
	Error handling:   onChanged errors propagate to the caller's handler.
	Performance notes: Tabs re-render only when the tab list changes (keyed by id).
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Focus = require("../Focus")
local Sound = require("../Sound")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local KeyPrompt = require("./KeyPrompt")
local Badge = require("./Badge")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")

type CanBeState<T> = State.CanBeState<T>

export type Tab = { id: string, label: string, icon: string?, badge: CanBeState<number>?, disabled: boolean? }
export type TabBarProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	tabs: CanBeState<{ Tab }>,
	selected: State.Value<string>,
	onChanged: ((id: string) -> ())?,
	variant: ("top" | "segmented")?,
	--- LB/RB cycling + shoulder glyphs (default true for "top").
	shoulder: boolean?,
}

local TabBar = {}

--- Pure: the id `direction` steps away from `current` (wrapping, skipping disabled tabs); nil if none.
function TabBar.cycle(tabs: { Tab }, current: string, direction: number): string?
	local count = #tabs
	if count == 0 then
		return nil
	end
	local index = 0
	for i, tab in tabs do
		if tab.id == current then
			index = i
			break
		end
	end
	local step = if direction < 0 then -1 else 1
	local i = index
	for _ = 1, count do
		i = ((i - 1 + step) % count) + 1
		if not tabs[i].disabled then
			return tabs[i].id
		end
	end
	return nil
end

local function choose(props: TabBarProps, id: string)
	if props.selected:peek() == id then
		return
	end
	Sound.play(Sound.KEYS.tab)
	props.selected:set(id)
	if props.onChanged ~= nil then
		props.onChanged(id)
	end
end

local function topTab(props: TabBarProps, tab: State.Value<Tab>, index: State.Value<number>): TextButton
	local id = tab:peek().id
	local button = Create.TextButton({
		Name = "Tab_" .. id,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = true,
		LayoutOrder = index,
	})
	local interaction = Common.trackInteraction(button, true)
	local active = State.Computed(function(): boolean
		return props.selected:get() == id
	end)
	local label = State.map(tab, function(t: Tab): string
		return t.label
	end)
	local width = State.Computed(function(): UDim2
		local t = tab:get()
		local textWidth = Common.measureText(t.label, "tab")
		local extra = (if t.icon then 28 else 0) + (if t.badge ~= nil then 24 else 0)
		return UDim2.new(0, textWidth + extra + Theme.space(5) * 2, 1, 0)
	end)
	local initial = tab:peek()
	local content: { Instance } = {
		Layout.list({ direction = "x", gap = Theme.space(2), align = "center", justify = "center" }),
	}
	if initial.icon ~= nil then
		table.insert(
			content,
			Icon.new({
				key = initial.icon :: string,
				size = 20,
				color = State.Computed(function(): Color3
					return if active:get()
						then Theme.color("text.primary"):get()
						else Theme.color("text.secondary"):get()
				end),
				LayoutOrder = 1,
			})
		)
	end
	if initial.badge ~= nil then
		table.insert(content, Badge.new({ kind = "count", count = initial.badge, LayoutOrder = 3 }))
	end
	table.insert(
		content,
		Text.new({
			Name = "Label",
			text = label,
			role = "tab",
			LayoutOrder = 2,
			color = State.Computed(function(): Color3
				if tab:get().disabled then
					return Theme.color("text.disabled"):get()
				end
				return if active:get() or interaction.hovered:get()
					then Theme.color("text.primary"):get()
					else Theme.color("text.secondary"):get()
			end),
			transparency = State.Computed(function(): number
				return if interaction.hovered:get() and not active:get() then 0.2 else 0
			end),
		})
	)
	Create.apply(button, {
		Size = width,
		[Create.Children] = {
			Create.Frame({
				Name = "Content",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				[Create.Children] = content,
			}) :: Instance,
			Create.Frame({
				Name = "Underline",
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 3),
				BackgroundColor3 = Theme.color("accent.dusk"),
				Visible = active,
				ZIndex = 3,
			}),
			Create.Frame({
				Name = "Crest",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -3),
				Size = UDim2.fromOffset(8, 4),
				Visible = active,
				ZIndex = 3,
				[Create.Children] = {
					Chamfer.new({ corners = "top", size = 4, fill = Theme.color("accent.dusk") }),
				},
			}),
		},
		[Create.On("Activated")] = function()
			if tab:peek().disabled then
				Sound.play(Sound.KEYS.error)
				return
			end
			choose(props, id)
		end,
	})
	return button
end

local function segment(props: TabBarProps, tab: State.Value<Tab>, index: State.Value<number>): TextButton
	local id = tab:peek().id
	local button = Create.TextButton({
		Name = "Segment_" .. id,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = true,
		LayoutOrder = index,
	})
	local interaction = Common.trackInteraction(button, true)
	local active = State.Computed(function(): boolean
		return props.selected:get() == id
	end)
	Create.apply(button, {
		Size = State.Computed(function(): UDim2
			return UDim2.new(0, Common.measureText(tab:get().label, "label") + Theme.space(4) * 2, 1, 0)
		end),
		[Create.Children] = {
			Create.Frame({
				Name = "Fill",
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Theme.color("bg.selected"),
				BackgroundTransparency = State.Computed(function(): number
					return if active:get() then 0 elseif interaction.hovered:get() then 0.5 else 1
				end),
			}) :: Instance,
			Create.Frame({
				Name = "ActiveLine",
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = Theme.color("accent.steel"),
				Visible = active,
				ZIndex = 3,
			}),
			Text.new({
				Name = "Label",
				text = State.map(tab, function(t: Tab): string
					return t.label
				end),
				role = "label",
				align = "center",
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
				color = State.Computed(function(): Color3
					return if active:get()
						then Theme.color("text.primary"):get()
						else Theme.color("text.secondary"):get()
				end),
			}),
		},
		[Create.On("Activated")] = function()
			if tab:peek().disabled then
				Sound.play(Sound.KEYS.error)
				return
			end
			choose(props, id)
		end,
	})
	return button
end

function TabBar.new(props: TabBarProps): Frame
	local variant = props.variant or "top"
	local segmented = variant == "segmented"
	local shoulder = if props.shoulder == nil then not segmented else props.shoulder
	local tabsState = State.list(props.tabs, function(tab: Tab): any
		return tab.id
	end, function(tab: State.Value<Tab>, index: State.Value<number>): Instance
		return if segmented then segment(props, tab, index) else topTab(props, tab, index)
	end)
	local row = Create.Frame({
		Name = "Tabs",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		[Create.Children] = {
			Layout.list({
				direction = "x",
				gap = if segmented then 0 else 1,
				align = "center",
				justify = if segmented then "start" else "center",
			}) :: any,
			tabsState,
		},
	})
	local children: { Instance } = {}
	if segmented then
		table.insert(
			children,
			Chamfer.new({
				corners = "brand",
				size = 4,
				fill = Theme.color("bg.inset"),
				border = Theme.color("border.bevel_lo"),
			})
		)
	else
		table.insert(
			children,
			Create.Frame({
				Name = "Baseline",
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = Theme.color("border.subtle"),
			})
		)
	end
	table.insert(children, row)
	if shoulder then
		-- LB/RB on gamepad, Q/E keycaps on keyboard, hidden on touch (KeyPrompt follows the input mode).
		table.insert(
			children,
			KeyPrompt.new({
				action = "TabPrev",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				ZIndex = 3,
			})
		)
		table.insert(
			children,
			KeyPrompt.new({
				action = "TabNext",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				ZIndex = 3,
			})
		)
	end
	local values: { [any]: any } = Common.layout(props, {}, {
		Name = "TabBar",
		-- Segments are 36 px, raised to the touch minimum on touch (top tabs are 48 already).
		Size = if segmented
			then State.map(Common.touchHeight(36), function(h: number): UDim2
				return UDim2.new(1, 0, 0, h)
			end)
			else UDim2.new(1, 0, 0, Theme.sizes.tabHeight),
	})
	values.BackgroundTransparency = 1
	values[Create.Children] = children
	local frame = Create.Frame(values)
	if shoulder then
		local unregister = Focus.registerShoulder(frame, function(direction: number)
			local nextId = TabBar.cycle(State.peek(props.tabs), props.selected:peek(), direction)
			if nextId ~= nil then
				choose(props, nextId)
			end
		end)
		Create.onDestroy(frame, unregister)
	end
	return Common.parent(frame, props)
end

return TabBar
