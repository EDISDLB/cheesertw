--!strict
--[[
	Components/Divider — horizontal/vertical rules, optional centred label, ridge (bevel) variant.

	Purpose:          1 px `border.subtle` separators between groups (brand-art §8.2); the "ridge" variant pairs a
	                  bevel_lo shadow line with a bevel_hi highlight (35 %) for machined panel seams; a label variant
	                  centres a caption between two flexed rules ("— OR —", section breaks in long lists).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Components/Text, Components/Common.
	State:            None.
	Validation:       Labels are ignored on vertical dividers.
	Error handling:   N/A.
	Performance notes: 1–3 Frames (+1 label).
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Text = require("./Text")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type DividerProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	direction: ("horizontal" | "vertical")?,
	variant: ("line" | "ridge")?,
	label: CanBeState<string>?,
	color: Common.ColorProp?,
	--- Space around the rule in px along the cross axis (default 0).
	inset: number?,
}

local Divider = {}

local function rule(
	name: string,
	vertical: boolean,
	color: CanBeState<Color3>,
	transparency: number,
	offset: number
): Frame
	return Create.Frame({
		Name = name,
		BorderSizePixel = 0,
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		Position = if vertical then UDim2.new(0.5, offset, 0, 0) else UDim2.new(0, 0, 0.5, offset),
		AnchorPoint = if vertical then Vector2.new(0.5, 0) else Vector2.new(0, 0.5),
		Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1),
	})
end

function Divider.new(props: DividerProps?): Frame
	local opts: DividerProps = props or {}
	local vertical = opts.direction == "vertical"
	local inset = opts.inset or 0
	local color = Common.color(opts.color, "border.subtle")
	local children: { Instance } = {}
	local thickness = 1
	if opts.label ~= nil and not vertical then
		local function flexRule(name: string, order: number): Frame
			return Create.Frame({
				Name = name,
				BorderSizePixel = 0,
				BackgroundColor3 = color,
				Size = UDim2.new(0, 0, 0, 1),
				LayoutOrder = order,
				[Create.Children] = { Layout.flex({ grow = 1, shrink = 1 }) },
			})
		end
		children = {
			Layout.list({ direction = "x", gap = Theme.space(3), align = "center" }),
			flexRule("RuleLeft", 1),
			Text.new({ Name = "Label", text = opts.label :: CanBeState<string>, role = "caption", LayoutOrder = 2 }),
			flexRule("RuleRight", 3),
		}
		thickness = 20
	elseif opts.variant == "ridge" then
		children = {
			rule("Shadow", vertical, Theme.color("border.bevel_lo"), 0, 0),
			rule("Highlight", vertical, Theme.color("border.bevel_hi"), 0.65, 1),
		}
		thickness = 2
	else
		children = { rule("Rule", vertical, color, 0, 0) }
	end
	local size = if vertical
		then UDim2.new(0, thickness + inset * 2, 1, 0)
		else UDim2.new(1, 0, 0, thickness + inset * 2)
	local values: { [any]: any } = Common.layout(opts, {}, { Name = "Divider", Size = size })
	values.BackgroundTransparency = 1
	values[Create.Children] = children
	return Common.parent(Create.Frame(values), opts)
end

return Divider
