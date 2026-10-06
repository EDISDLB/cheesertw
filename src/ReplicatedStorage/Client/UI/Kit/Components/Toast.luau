--!strict
--[[
	Components/Toast — transient notifications (card builder + `Toast.show` on the shared stack).

	Purpose:          The ui-ux §1.5 / brand §8.5 toast: a 360 px bg.panel (95 %) card with a 4 px tone stripe on the
	                  left, a 24 px tone glyph (check / warning / error / info), a title.s title, an optional caption
	                  body (text.secondary, at most two lines), an optional secondary compact action and a close button.
	                  `Toast.show(spec)` pushes onto the default ToastStack in the Toasts layer (top-right, under the
	                  header); see Components/ToastStack for stacking, timing (4 s, 8 s with an action, paused while
	                  hovered) and dismissal. Toasts never take gamepad focus: an action shown in a toast must also be
	                  reachable from the screen (accessibility checklist).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Components/Chamfer, Components/Text,
	                  Components/Button, Components/IconButton, Icons/Icon, Components/ToastStack (lazy).
	State:            None (the stack owns timers).
	Validation:       Unknown tones fall back to neutral.
	Error handling:   Toast.show without a Toasts layer logs once and returns nil.
	Performance notes: ~12 instances per toast; at most `max` (3) alive per stack.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Button = require("./Button")
local IconButton = require("./IconButton")
local Icon = require("../../Icons/Icon")

type CanBeState<T> = State.CanBeState<T>

export type Spec = {
	title: CanBeState<string>,
	body: CanBeState<string>?,
	tone: Theme.Tone?,
	--- Icon key (default per tone).
	icon: string?,
	action: { text: CanBeState<string>, onActivated: () -> () }?,
	--- Hold time in seconds (default 4, 8 with an action).
	duration: number?,
	--- Never auto-dismiss.
	sticky: boolean?,
	--- Replaces an existing toast with the same key instead of stacking a duplicate.
	key: string?,
	--- Play ui_notification (default true).
	sound: boolean?,
}

local Toast = {}

local TONE_ICONS: { [string]: string } = {
	neutral = "ui/info",
	info = "ui/info",
	success = "ui/check",
	warning = "ui/warning",
	danger = "ui/error",
}

--- Pure: the icon key for a spec.
function Toast.iconFor(spec: Spec): string
	return spec.icon or TONE_ICONS[spec.tone or "neutral"] or "ui/info"
end

--- Pure: hold seconds for a spec (nil = sticky).
function Toast.holdFor(spec: Spec): number?
	if spec.sticky then
		return nil
	end
	if spec.duration ~= nil then
		return spec.duration
	end
	return Theme.duration(if spec.action ~= nil then "toastHoldAction" else "toastHold")
end

local ACTION_WIDTH = 112
local CLOSE_SIZE = 32

--- Builds the toast card (a TextButton: activating it, or its close button, dismisses via `onDismiss`).
function Toast.new(spec: Spec, onDismiss: (() -> ())?): TextButton
	local tone: Theme.Tone = spec.tone or "neutral"
	local toneColor = if tone == "neutral" then Theme.color("accent.steel") else Theme.tone(tone)
	local captionSize = Theme.textSize("caption")
	local texts: { Instance } = {
		Layout.list({ gap = 2 }),
		Text.new({ Name = "Title", text = spec.title, role = "title.s", LayoutOrder = 1 }),
	}
	if spec.body ~= nil then
		local body = Text.new({
			Name = "Body",
			text = spec.body :: CanBeState<string>,
			role = "caption",
			color = "text.secondary",
			Size = UDim2.fromScale(1, 0),
			wrap = true,
			truncate = true,
			autoSize = "y",
			LayoutOrder = 2,
		})
		-- At most two lines (ui-ux §1.5 toast anatomy); longer bodies end in an ellipsis.
		Create.UISizeConstraint({
			MaxSize = State.map(captionSize, function(size: number): Vector2
				return Vector2.new(math.huge, math.ceil(size * Theme.lineHeight("caption") * 2))
			end),
			Parent = body,
		})
		table.insert(texts, body)
	end
	local action = spec.action
	local reserved = 24 + CLOSE_SIZE + 2 * Theme.space(3) + (if action ~= nil then ACTION_WIDTH + Theme.space(3) else 0)
	local row: { Instance } = {
		Layout.list({ direction = "x", gap = Theme.space(3), align = "center" }),
		Layout.padding({ left = Theme.space(4), right = Theme.space(2), y = Theme.space(3) }),
		Icon.new({ key = Toast.iconFor(spec), size = 24, color = toneColor, LayoutOrder = 1 }),
		Create.Frame({
			Name = "Texts",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -reserved, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			[Create.Children] = texts,
		}),
	}
	if action ~= nil then
		table.insert(
			row,
			Button.new({
				Name = "Action",
				text = action.text,
				variant = "secondary",
				size = "compact",
				width = ACTION_WIDTH,
				onActivated = function()
					action.onActivated()
					if onDismiss ~= nil then
						onDismiss()
					end
				end,
				LayoutOrder = 3,
			})
		)
	end
	table.insert(
		row,
		IconButton.new({
			Name = "Close",
			icon = "ui/close",
			label = "Dismiss",
			size = CLOSE_SIZE,
			sound = false,
			onActivated = onDismiss,
			LayoutOrder = 4,
		})
	)
	local values: { [any]: any } = {
		Name = "Toast",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Selectable = false,
		Size = UDim2.fromOffset(Theme.sizes.toastWidth, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		[Create.Children] = {
			Chamfer.new({
				corners = "brand",
				size = Theme.chamfer("s"),
				fill = Theme.color("bg.panel"),
				fillTransparency = 0.05,
				border = Theme.color("border.subtle"),
			}) :: Instance,
			Create.Frame({
				Name = "ToneBar",
				BorderSizePixel = 0,
				BackgroundColor3 = toneColor,
				Position = UDim2.fromOffset(0, Theme.chamfer("s")),
				Size = UDim2.new(0, 4, 1, -2 * Theme.chamfer("s")),
				ZIndex = 3,
			}),
			Create.Frame({
				Name = "Content",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				ZIndex = 3,
				[Create.Children] = row,
			}),
		},
		[Create.On("Activated")] = function()
			if action == nil and onDismiss ~= nil then
				onDismiss()
			end
		end,
	}
	return Create.TextButton(values)
end

--- Pushes a toast on the default stack (Toasts layer). Returns its id, or nil without a Toasts layer.
function Toast.show(spec: Spec): number?
	local ToastStack = require("./ToastStack") :: any
	local stack = ToastStack.default()
	if stack == nil then
		return nil
	end
	return stack:push(spec)
end

--- Dismisses a toast shown with Toast.show.
function Toast.dismiss(id: number)
	local ToastStack = require("./ToastStack") :: any
	local stack = ToastStack.default()
	if stack ~= nil then
		stack:dismiss(id)
	end
end

return Toast
