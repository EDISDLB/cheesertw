--!strict
--[[
	Components/Panel — brand panel: chamfered gunmetal surface, bevel lines, optional header strip.

	Purpose:          brand-art §8.2: `bg.panel` fill, 1 px `border.subtle` border, 1 px inner top highlight
	                  (`border.bevel_hi` at 35 %) and bottom shadow (`border.bevel_lo`), HULLDOWN cut (8 px chamfers on
	                  the top-left and bottom-right; drawn with Components/Chamfer until 9-slices are uploaded). The
	                  header strip is a `bg.base` -> `bg.panel` vertical gradient with a 2 px `border.strong` bottom
	                  edge, an optional stencil section number ("01", Oswald, text.tertiary), icon, h3 title and
	                  right-aligned actions. Variants: default, raised (cards inside panels), inset (wells), hero
	                  (adds rivet dots — hero panels only).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Components/Chamfer, Components/Text,
	                  Components/Common, Icons/Icon.
	State:            None.
	Validation:       Unknown variants fall back to default.
	Error handling:   N/A.
	Performance notes: ~15 Frames for the surface + header; content is a plain Frame ("Content").
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")

type CanBeState<T> = State.CanBeState<T>

export type Variant = "default" | "raised" | "inset" | "hero"
export type PanelProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	title: CanBeState<string>?,
	--- Stencil section number shown before the title ("01").
	number: string?,
	--- Header icon key.
	icon: string?,
	--- Instances placed at the right of the header (buttons, chips).
	actions: Common.Children?,
	variant: Variant?,
	--- Content padding in px (default 16).
	padding: number?,
	--- Grow with the content (AutomaticSize Y).
	autoHeight: boolean?,
	--- Content list layout (gap/direction/...); nil = no layout object.
	list: Layout.ListOptions?,
	children: Common.Children?,
	headerHeight: number?,
}

local Panel = {}

local FILLS: { [string]: Theme.ColorToken } = {
	default = "bg.panel",
	raised = "bg.raised",
	inset = "bg.inset",
	hero = "bg.panel",
}

local function rivets(): { Instance }
	local out: { Instance } = {}
	local positions: { [string]: UDim2 } = {
		RivetTL = UDim2.new(0, 12, 0, 4),
		RivetTR = UDim2.new(1, -6, 0, 4),
		RivetBL = UDim2.new(0, 4, 1, -6),
		RivetBR = UDim2.new(1, -14, 1, -6),
	}
	for name, position in positions do
		table.insert(
			out,
			Create.Frame({
				Name = name,
				BorderSizePixel = 0,
				Position = position,
				Size = UDim2.fromOffset(2, 2),
				BackgroundColor3 = Theme.color("border.bevel_hi"),
				ZIndex = 4,
			})
		)
	end
	return out
end

local function header(props: PanelProps, height: number): Frame
	local left: { Instance } = { Layout.list({ direction = "x", gap = Theme.space(2), align = "center" }) }
	if props.number ~= nil then
		table.insert(left, Text.new({ text = props.number, role = "h3", color = "text.tertiary", LayoutOrder = 1 }))
	end
	if props.icon ~= nil then
		table.insert(
			left,
			Icon.new({ key = props.icon, size = 24, color = Theme.color("text.secondary"), LayoutOrder = 2 })
		)
	end
	if props.title ~= nil then
		table.insert(left, Text.new({ text = props.title, role = "h3", LayoutOrder = 3 }))
	end
	local actions: { Instance } =
		{ Layout.list({ direction = "x", gap = Theme.space(2), align = "center", justify = "end" }) }
	local given: { Instance } = props.actions or {}
	for i, action in given do
		if action:IsA("GuiObject") then
			(action :: GuiObject).LayoutOrder = i
		end
		table.insert(actions, action)
	end
	return Create.Frame({
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
		ZIndex = 3,
		[Create.Children] = {
			Chamfer.new({
				name = "HeaderSurface",
				corners = "tl",
				size = Theme.chamfer("m"),
				gradient = {
					top = Theme.peekColor("bg.base"),
					bottom = Theme.peekColor("bg.panel"),
					nominalHeight = height,
				},
				zIndex = 2,
			}),
			Create.Frame({
				Name = "HeaderEdge",
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 1, -2),
				Size = UDim2.new(1, 0, 0, 2),
				BackgroundColor3 = Theme.color("border.strong"),
				ZIndex = 4,
			}),
			Create.Frame({
				Name = "TitleRow",
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(Theme.space(4), 0),
				Size = UDim2.new(0.6, 0, 1, -2),
				ZIndex = 5,
				[Create.Children] = left,
			}),
			Create.Frame({
				Name = "Actions",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -Theme.space(3), 0, 0),
				Size = UDim2.new(0.4, 0, 1, -2),
				ZIndex = 5,
				[Create.Children] = actions,
			}),
		},
	})
end

--- Builds a panel. Children go into `panel.Content` (props.children or later via Panel.content(panel)).
function Panel.new(props: PanelProps): Frame
	local variant: Variant = props.variant or "default"
	local fill: Theme.ColorToken = FILLS[variant] or "bg.panel"
	local headerHeight = if props.title ~= nil or props.number ~= nil then props.headerHeight or 48 else 0
	local padding = props.padding or Theme.space(4)
	local autoHeight = props.autoHeight == true
	local borderToken: Theme.ColorToken = if variant == "inset" then "border.bevel_lo" else "border.subtle"
	local contentChildren: { Instance } = { Layout.padding(padding) }
	if props.list ~= nil then
		table.insert(contentChildren, Layout.list(props.list))
	end
	local given: { Instance } = props.children or {}
	for _, child in given do
		table.insert(contentChildren, child)
	end
	local children: { Instance } = {
		Chamfer.new({
			name = "Surface",
			corners = "brand",
			size = Theme.chamfer("m"),
			fill = Theme.color(fill),
			border = Theme.color(borderToken),
			bevel = variant ~= "inset",
			zIndex = 1,
		}),
		Create.Frame({
			Name = "Content",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, headerHeight),
			Size = if autoHeight then UDim2.new(1, 0, 0, 0) else UDim2.new(1, 0, 1, -headerHeight),
			AutomaticSize = if autoHeight then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
			ZIndex = 3,
			[Create.Children] = contentChildren,
		}),
	}
	if headerHeight > 0 then
		table.insert(children, header(props, headerHeight))
	end
	if variant == "hero" then
		for _, rivet in rivets() do
			table.insert(children, rivet)
		end
	end
	local values: { [any]: any } = Common.layout(props, {}, {
		Name = "Panel",
		Size = UDim2.fromOffset(400, 240),
	})
	values.BackgroundTransparency = 1
	values.BorderSizePixel = 0
	if autoHeight then
		values.AutomaticSize = Enum.AutomaticSize.Y
	end
	values[Create.Children] = children
	return Common.parent(Create.Frame(values), props)
end

--- The content container of a panel.
function Panel.content(panel: Instance): Frame
	local content = panel:FindFirstChild("Content")
	if content == nil or not content:IsA("Frame") then
		error("Panel.content: not a kit Panel", 2)
	end
	return content
end

return Panel
