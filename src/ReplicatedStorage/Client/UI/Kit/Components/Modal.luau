--!strict
--[[
	Components/Modal — dialog card (Modal.new) and self-managed dialogs (Modal.open) with trapped focus.

	Purpose:          `Modal.new` builds the brand dialog card: shadow, HULLDOWN-cut bg.panel surface with a
	                  border.strong edge, header (icon + h3 title + close button), body (sentence text and/or
	                  children) and a right-aligned action row, at the s/m/l widths (480/640/880). Use it as the
	                  `build` result of a Router modal screen (the Router supplies scrim, focus trap and Back).
	                  `Modal.open` is the imperative form for one-off dialogs: it adds a scrim in the Modals layer,
	                  traps gamepad focus inside the card (Kit/Focus scope, trap = true), makes Back close it (or
	                  swallows Back when not dismissible, so the screen underneath never pops), pops it in, and
	                  returns a handle whose `closed` signal fires once with the result.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Kit/Layers, Kit/Focus, Kit/UIInput, Kit/Motion,
	                  Kit/Sound, Components/Chamfer, Components/Shadow, Components/Text, Components/Button,
	                  Components/IconButton, Components/Common, Icons/Icon, Core/Signal.
	State:            Per open dialog: its focus scope, Back interceptor and closed flag.
	Validation:       Unknown sizes fall back to "m".
	Error handling:   Modal.open raises when there is no Modals layer (create a Router first); action handler
	                  errors propagate (the dialog stays open).
	Performance notes: Built on open, destroyed on close.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Layers = require("../Layers")
local Focus = require("../Focus")
local UIInput = require("../UIInput")
local Motion = require("../Motion")
local Sound = require("../Sound")
local Chamfer = require("./Chamfer")
local Shadow = require("./Shadow")
local Text = require("./Text")
local Button = require("./Button")
local IconButton = require("./IconButton")
local Common = require("./Common")
local Icon = require("../../Icons/Icon")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

type CanBeState<T> = State.CanBeState<T>

export type Size = "s" | "m" | "l"
export type Action = {
	text: CanBeState<string>,
	variant: Button.Variant?,
	--- Result passed to `close` / `closed` by Modal.open (default: the action's position).
	id: any?,
	icon: string?,
	hint: string?,
	disabled: CanBeState<boolean>?,
	onActivated: (() -> ())?,
	--- Modal.open: keep the dialog open after this action (default false).
	keepOpen: boolean?,
	--- Initial gamepad focus.
	focus: boolean?,
	--- Hold-to-confirm on gamepad/touch (Button `hold`).
	hold: (boolean | number)?,
	--- Shows the button's loading state (non-activating while true).
	loading: CanBeState<boolean>?,
}
export type ModalProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	title: CanBeState<string>,
	icon: string?,
	body: CanBeState<string>?,
	children: Common.Children?,
	actions: { Action }?,
	size: Size?,
	--- Shows the close button (and lets Back/scrim close it in Modal.open). Default true.
	dismissible: boolean?,
	--- Close button handler (Modal.new); Modal.open wires it to close(nil).
	onClose: (() -> ())?,
	--- Instances inserted above the header (e.g. ConfirmDialog's hazard band).
	banner: Instance?,
}
--- ModalProps plus the Modal.open extras (flat, not an intersection, so table literals type-check).
export type OpenProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	title: CanBeState<string>,
	icon: string?,
	body: CanBeState<string>?,
	children: Common.Children?,
	actions: { Action }?,
	size: Size?,
	dismissible: boolean?,
	onClose: (() -> ())?,
	banner: Instance?,
	--- Called once with the result when the dialog closes.
	onResult: ((result: any) -> ())?,
	--- Anchor used to find the Modals layer (default: the registered layer).
	anchor: Instance?,
	--- Initial focus override (default: the action with focus = true, else the last action).
	initialFocus: GuiObject?,
}
export type Handle = {
	close: (result: any?) -> (),
	isOpen: () -> boolean,
	closed: Signal.Signal<any>,
	--- Full-screen holder (scrim + dialog) in the Modals layer.
	root: Frame,
	dialog: Frame,
}

local Modal = {}

Modal.Z = 200

local WIDTHS: { [string]: number } = Theme.sizes.modalWidth :: any

--- Pure: dialog width for a size name.
function Modal.width(size: Size?): number
	return WIDTHS[size or "m"] or WIDTHS.m
end

--- Builds the dialog card. Action buttons are found by name: "Action1", "Action2", ...
function Modal.new(props: ModalProps): Frame
	local width = Modal.width(props.size)
	local dismissible = props.dismissible ~= false
	local header: { Instance } = {
		Layout.list({ direction = "x", gap = Theme.space(2), align = "center" }),
	}
	if props.icon ~= nil then
		table.insert(
			header,
			Icon.new({ key = props.icon :: string, size = 28, color = Theme.color("text.primary"), LayoutOrder = 1 })
		)
	end
	table.insert(
		header,
		Text.new({
			Name = "Title",
			text = props.title,
			role = "h3",
			LayoutOrder = 2,
			Size = UDim2.new(1, if dismissible then -(44 + 36) else -36, 0, 32),
			truncate = true,
			wrap = false,
		})
	)
	local headerFrame = Create.Frame({
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 2,
		[Create.Children] = header,
	})
	if dismissible then
		IconButton.new({
			Name = "Close",
			icon = "ui/close",
			label = "Close",
			size = 44,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			onActivated = props.onClose,
			sound = false,
			Parent = headerFrame,
		})
	end
	local content: { Instance } = {
		Layout.list({ gap = Theme.space(4) }),
		Layout.padding({ x = Theme.space(5), top = Theme.space(4), bottom = Theme.space(5) }),
		headerFrame,
	}
	if props.banner ~= nil then
		local banner = props.banner :: GuiObject
		banner.LayoutOrder = 1
		table.insert(content, banner)
	end
	local bodyChildren: { Instance } = { Layout.list({ gap = Theme.space(3) }) }
	if props.body ~= nil then
		table.insert(
			bodyChildren,
			Text.new({
				Name = "BodyText",
				text = props.body :: CanBeState<string>,
				role = "body",
				color = "text.secondary",
				Size = UDim2.fromScale(1, 0),
				wrap = true,
				autoSize = "y",
				LayoutOrder = 1,
			})
		)
	end
	local extraChildren: { Instance } = props.children or {}
	for i, child in extraChildren do
		if child:IsA("GuiObject") and child.LayoutOrder == 0 then
			child.LayoutOrder = 1 + i
		end
		table.insert(bodyChildren, child)
	end
	table.insert(
		content,
		Create.Frame({
			Name = "Body",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3,
			[Create.Children] = bodyChildren,
		})
	)
	local actions: { Action } = props.actions or {}
	if #actions > 0 then
		local row: { Instance } = {
			Layout.list({ direction = "x", gap = Theme.space(3), align = "center", justify = "end" }),
		}
		for i, action in actions do
			table.insert(
				row,
				Button.new({
					Name = "Action" .. i,
					text = action.text,
					variant = action.variant or (if i == #actions then "primary" else "secondary"),
					size = "medium",
					icon = action.icon,
					hint = action.hint,
					disabled = action.disabled,
					loading = action.loading,
					hold = action.hold,
					onActivated = action.onActivated,
					LayoutOrder = i,
				})
			)
		end
		table.insert(
			content,
			Create.Frame({
				Name = "Actions",
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, Theme.sizes.buttonHeight.large),
				LayoutOrder = 4,
				[Create.Children] = row,
			})
		)
	end
	local values: { [any]: any } = Common.layout(props, {}, {
		Name = "Modal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
	})
	values.Size = UDim2.fromOffset(width, 0)
	values.AutomaticSize = Enum.AutomaticSize.Y
	values.BackgroundTransparency = 1
	values.Active = true
	values[Create.Children] = {
		Shadow.new({ zIndex = 0 }) :: Instance,
		Chamfer.new({
			corners = "brand",
			size = Theme.chamfer("m"),
			fill = Theme.color("bg.panel"),
			border = Theme.color("border.strong"),
			borderThickness = Theme.borderWidth(),
			bevel = true,
			zIndex = 1,
		}),
		Create.Frame({
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 3,
			[Create.Children] = content,
		}),
	}
	return Common.parent(Create.Frame(values), props)
end

--- Opens a self-managed dialog in the Modals layer. Returns its handle.
function Modal.open(props: OpenProps): Handle
	local parent = Layers.parentFor("Modals", props.anchor)
	if parent == nil then
		error("Modal.open: no Modals layer is registered (create a Kit Router first)", 2)
	end
	local dismissible = props.dismissible ~= false
	local closed = Signal.new() :: Signal.Signal<any>
	local isClosed = false
	local removeInterceptor: (() -> ())? = nil
	local scope: Focus.FocusScope? = nil
	local holder: Frame
	local close: (result: any?) -> ()

	local cardProps: ModalProps = table.clone(props) :: any
	cardProps.Parent = nil
	cardProps.onClose = function()
		close(nil)
	end
	local wrapped: { Action } = {}
	local sourceActions: { Action } = props.actions or {}
	for i, action in sourceActions do
		local copy = table.clone(action)
		copy.onActivated = function()
			if action.onActivated ~= nil then
				action.onActivated()
			end
			if not action.keepOpen then
				close(if action.id ~= nil then action.id else i)
			end
		end
		table.insert(wrapped, copy)
	end
	cardProps.actions = wrapped
	local dialog = Modal.new(cardProps)
	dialog.ZIndex = Modal.Z + 1

	local scrim = Create.TextButton({
		Name = "Scrim",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.color("bg.scrim"),
		BackgroundTransparency = 1,
		ZIndex = Modal.Z,
		[Create.On("Activated")] = function()
			if dismissible then
				close(nil)
			end
		end,
	})
	holder = Create.Frame({
		Name = "ModalHost",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Modal.Z,
		[Create.Children] = { scrim :: Instance, dialog },
		Parent = parent,
	})

	close = function(result: any?)
		if isClosed then
			return
		end
		isClosed = true
		if removeInterceptor ~= nil then
			removeInterceptor()
			removeInterceptor = nil
		end
		if scope ~= nil then
			scope:Destroy()
			scope = nil
		end
		Sound.play(Sound.KEYS.close)
		holder:Destroy()
		if props.onResult ~= nil then
			props.onResult(result)
		end
		closed:Fire(result)
		closed:DisconnectAll()
	end

	local initial: GuiObject? = props.initialFocus
	if initial == nil then
		local actionList: { Action } = props.actions or {}
		for i, action in actionList do
			if action.focus then
				initial = dialog:FindFirstChild("Action" .. i, true) :: GuiObject?
			end
		end
		if initial == nil and #actionList > 0 then
			initial = dialog:FindFirstChild("Action" .. #actionList, true) :: GuiObject?
		end
	end
	local focusScope = Focus.scope(dialog, { name = "Modal", trap = true, initial = initial })
	scope = focusScope
	focusScope:activate()
	removeInterceptor = UIInput.interceptBack(function(): boolean
		if dismissible then
			close(nil)
		end
		return true
	end)
	Motion.tween(
		scrim,
		{ BackgroundTransparency = Theme.tokenTransparency("bg.scrim"):peek() },
		{ duration = "base", kind = "fade" }
	)
	Motion.pop(dialog, { duration = "base" })
	Sound.play(Sound.KEYS.open)

	return {
		close = close,
		isOpen = function(): boolean
			return not isClosed
		end,
		closed = closed,
		root = holder,
		dialog = dialog,
	}
end

return Modal
