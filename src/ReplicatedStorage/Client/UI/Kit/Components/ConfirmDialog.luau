--!strict
--[[
	Components/ConfirmDialog — yes/no confirmation built on Modal.open, with a hazard band for destructive actions.

	Purpose:          `ConfirmDialog.open({ title, body, confirmLabel, onConfirm })` for purchases, sells, leaving a
	                  battle, resetting settings. Destructive confirmations get a warning hazard-stripe band, a
	                  danger confirm button and initial gamepad focus on Cancel (an accidental A press must never
	                  destroy something). Back / scrim / close count as cancel. The handle's `closed` fires with true
	                  (confirmed) or false.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Components/Modal, Components/Common.
	State:            See Modal.open.
	Validation:       N/A.
	Error handling:   See Modal.open.
	Performance notes: The hazard band is ~width/16 small frames with one UIGradient each (dialogs only).
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Modal = require("./Modal")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type ConfirmProps = {
	title: CanBeState<string>,
	body: CanBeState<string>?,
	icon: string?,
	confirmLabel: CanBeState<string>?,
	cancelLabel: CanBeState<string>?,
	destructive: boolean?,
	size: Modal.Size?,
	children: Common.Children?,
	onConfirm: (() -> ())?,
	onCancel: (() -> ())?,
	anchor: Instance?,
}

local ConfirmDialog = {}

ConfirmDialog.STRIPE_TILE = 16

--- Hazard band: warning/ink 45° stripes, `height` px tall, filling its parent's width.
function ConfirmDialog.hazardBand(width: number, height: number?): Frame
	local tile = ConfirmDialog.STRIPE_TILE
	local tiles = math.ceil(width / tile) + 1
	local warning = Theme.color("state.warning")
	local ink = Theme.color("ink")
	local children: { Instance } = {}
	for i = 1, tiles do
		table.insert(
			children,
			Create.Frame({
				Name = "Tile" .. i,
				BorderSizePixel = 0,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Position = UDim2.fromOffset((i - 1) * tile, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.fromOffset(tile, tile),
				[Create.Children] = {
					Create.UIGradient({
						Rotation = 45,
						Color = State.Computed(function(): ColorSequence
							local a, b = warning:get(), ink:get()
							return ColorSequence.new({
								ColorSequenceKeypoint.new(0, a),
								ColorSequenceKeypoint.new(0.25, a),
								ColorSequenceKeypoint.new(0.251, b),
								ColorSequenceKeypoint.new(0.5, b),
								ColorSequenceKeypoint.new(0.501, a),
								ColorSequenceKeypoint.new(0.75, a),
								ColorSequenceKeypoint.new(0.751, b),
								ColorSequenceKeypoint.new(1, b),
							})
						end),
					}),
				},
			})
		)
	end
	return Create.Frame({
		Name = "HazardBand",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, height or 6),
		[Create.Children] = {
			Create.Frame({
				Name = "Tiles",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(1, 0),
				[Create.Children] = children,
			}),
		},
	})
end

function ConfirmDialog.open(props: ConfirmProps): Modal.Handle
	local destructive = props.destructive == true
	local settled = false
	local function settle(confirmed: boolean)
		if settled then
			return
		end
		settled = true
		if confirmed then
			if props.onConfirm ~= nil then
				props.onConfirm()
			end
		elseif props.onCancel ~= nil then
			props.onCancel()
		end
	end
	local size: Modal.Size = props.size or "s"
	local actions: { Modal.Action } = {
		{ id = false, text = props.cancelLabel or "Cancel", variant = "secondary", focus = destructive },
		{
			id = true,
			text = props.confirmLabel or "Confirm",
			variant = if destructive then "danger" else "primary",
			focus = not destructive,
		},
	}
	return Modal.open({
		title = props.title,
		body = props.body,
		icon = props.icon or (if destructive then "ui/warning" else nil),
		size = size,
		children = props.children,
		anchor = props.anchor,
		banner = if destructive then ConfirmDialog.hazardBand(Modal.width(size) - 2 * Theme.space(5)) else nil,
		actions = actions,
		onResult = function(result: any)
			settle(result == true)
		end,
	})
end

return ConfirmDialog
