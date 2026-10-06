--!strict
--[[
	Components/EmptyState — the "nothing here yet" block for lists, inventories and search results.

	Purpose:          A centred column: a 48 px glyph in text.tertiary, an h4 title, an optional body sentence
	                  (body.s, text.secondary, max 360 px) and an optional secondary action button. Use it instead of
	                  blank space whenever a list can be empty (research 06 A7: every empty list explains itself and
	                  offers the next step).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Components/Text, Components/Button,
	                  Components/Common, Icons/Icon.
	State:            None.
	Validation:       N/A.
	Error handling:   N/A.
	Performance notes: ~6 instances + the glyph.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Text = require("./Text")
local Button = require("./Button")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")

type CanBeState<T> = State.CanBeState<T>

export type Action = { text: CanBeState<string>, onActivated: () -> (), icon: string?, hint: string? }
export type EmptyStateProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	--- Icon key (default "ui/info").
	icon: CanBeState<string>?,
	title: CanBeState<string>,
	body: CanBeState<string>?,
	action: Action?,
}

local EmptyState = {}

EmptyState.MAX_WIDTH = 360

function EmptyState.new(props: EmptyStateProps): Frame
	local children: { Instance } = {
		Layout.list({ gap = Theme.space(2), align = "center", justify = "center" }),
		Layout.padding(Theme.space(5)),
		Icon.new({
			key = props.icon or "ui/info",
			size = Theme.sizes.icon.xl,
			color = Theme.color("text.tertiary"),
			LayoutOrder = 1,
		}),
		Text.new({ Name = "Title", text = props.title, role = "h4", align = "center", LayoutOrder = 2 }),
	}
	if props.body ~= nil then
		table.insert(
			children,
			Text.new({
				Name = "Body",
				text = props.body :: CanBeState<string>,
				role = "body.s",
				color = "text.secondary",
				align = "center",
				wrap = true,
				maxWidth = EmptyState.MAX_WIDTH,
				LayoutOrder = 3,
			})
		)
	end
	local action = props.action
	if action ~= nil then
		table.insert(
			children,
			Create.Frame({
				Name = "ActionSpacer",
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(1, Theme.space(1)),
				LayoutOrder = 4,
			})
		)
		table.insert(
			children,
			Button.new({
				Name = "Action",
				text = action.text,
				icon = action.icon,
				hint = action.hint,
				variant = "secondary",
				size = "medium",
				onActivated = action.onActivated,
				LayoutOrder = 5,
			})
		)
	end
	local values: { [any]: any } = Common.layout(props, {}, { Name = "EmptyState", Size = UDim2.fromScale(1, 1) })
	values.BackgroundTransparency = 1
	values[Create.Children] = children
	return Common.parent(Create.Frame(values), props)
end

return EmptyState
