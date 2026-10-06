--!strict
--[[
	Components/Button — the brand button: primary CTA, secondary, ghost, danger and battle variants.

	Purpose:          brand-art §8.3 states for every variant — idle, hover, pressed (label 1 px lower), disabled,
	                  loading (spinner, non-activating), gamepad focus (the global brand focus ring; danger buttons use
	                  the danger ring) — with optional leading/trailing icons, an input-glyph hint (KeyPrompt), UI
	                  sounds (hover/click via Kit/Sound) and tooltips. Primary/battle use the dusk vertical gradient
	                  (#FF8A45 -> #E8641F), lighten to dusk_hi with a 2 px dusk glow on hover, dusk_lo when pressed;
	                  HULLDOWN-cut chamfers. Heights 56 (large), 44 (medium), 36 (compact; raised to 44 on touch),
	                  64 battle (min 280 wide); minimum width 2.5 × height. One primary CTA per screen.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/Layout, Kit/Sound, Kit/InputMode, Components/Chamfer,
	                  Components/Common, Components/Text, Components/Spinner, Components/KeyPrompt,
	                  Components/FocusRing, Components/Tooltip (lazy), Icons/Icon.
	State:            Interaction Values (hover/pressed/selected) and derived visual-state Computeds per button.
	Validation:       Unknown variant/size names raise.
	Error handling:   onActivated errors propagate to the engine's event handler (logged by Roblox).
	Performance notes: Primary/battle carry 4 chamfer surfaces (~30 Frames, few per screen); other variants one.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Layout = require("../Layout")
local Sound = require("../Sound")
local InputMode = require("../InputMode")
local Chamfer = require("./Chamfer")
local Common = require("./Common")
local Text = require("./Text")
local Spinner = require("./Spinner")
local KeyPrompt = require("./KeyPrompt")
local FocusRing = require("./FocusRing")
local Icon = require("../../Icons/Icon")

type State<T> = State.State<T>
type CanBeState<T> = State.CanBeState<T>

export type Variant = "primary" | "secondary" | "ghost" | "danger" | "battle"
export type Size = "large" | "medium" | "compact"
export type VisualState = "idle" | "hover" | "pressed" | "disabled"

export type ButtonProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	--- Explicit size (overrides width/height rules).
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	text: CanBeState<string>,
	variant: Variant?,
	size: Size?,
	--- Icon keys (Icons registry / asset keys).
	icon: CanBeState<string>?,
	iconRight: CanBeState<string>?,
	--- InputMode action whose glyph is shown at the right (e.g. "Tertiary" for Y).
	hint: string?,
	disabled: CanBeState<boolean>?,
	loading: CanBeState<boolean>?,
	onActivated: (() -> ())?,
	--- px width, "fill" (parent width) or "auto" (measured text, default).
	width: (number | "fill" | "auto")?,
	--- Sound on activation (default ui_click; ui_confirm for primary/battle; false = silent).
	sound: (string | boolean)?,
	tooltip: CanBeState<string>?,
}

local Button = {}

local HEIGHTS: { [string]: number } = { large = 56, medium = 44, compact = 36 }
local PADDING: { [string]: number } = { large = 24, medium = 16, compact = 12, battle = 32 }

--- Pure: visual state from interaction flags (disabled wins, then pressed, then hover).
function Button.visualState(disabled: boolean, pressed: boolean, hovered: boolean): VisualState
	if disabled then
		return "disabled"
	elseif pressed then
		return "pressed"
	elseif hovered then
		return "hover"
	end
	return "idle"
end

--- Pure: button width for a measured label (min 2.5 × height; battle min 280).
function Button.computeWidth(variant: Variant, height: number, labelWidth: number, extras: number): number
	local padding = PADDING[if variant == "battle"
		then "battle"
		elseif height >= 56 then "large"
		elseif height >= 44 then "medium"
		else "compact"]
	local width = labelWidth + extras + padding * 2
	local minimum = height * Theme.sizes.buttonMinWidthRatio
	if variant == "battle" then
		minimum = math.max(minimum, Theme.sizes.battleMinWidth)
	end
	return math.ceil(math.max(width, minimum))
end

local function labelRole(variant: Variant): Theme.TypeRole
	if variant == "battle" then
		return "button.battle"
	elseif variant == "primary" then
		return "button.cta"
	end
	return "button"
end

-- Primary/battle: one chamfer surface per visual state (gradients cannot be State-bound).
local function ctaSurfaces(visual: State<VisualState>, height: number): { Instance }
	local function visibleWhen(states: { VisualState }): State<boolean>
		return State.Computed(function(): boolean
			return table.find(states, visual:get()) ~= nil
		end)
	end
	local glow = Create.Frame({
		Name = "Glow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-2, -2),
		Size = UDim2.new(1, 4, 1, 4),
		Visible = visibleWhen({ "hover" }),
		ZIndex = 1,
		[Create.Children] = {
			Chamfer.new({
				corners = "brand",
				size = Theme.chamfer("m") + 1,
				border = Theme.color("accent.dusk"),
				borderThickness = 2,
				borderTransparency = 0.6,
				zIndex = 1,
			}),
		},
	})
	local function surface(name: string, states: { VisualState }, props: Chamfer.ChamferProps): Frame
		local frame = Chamfer.new(props)
		frame.Name = name
		frame.Visible = false
		Create.apply(frame, { Visible = visibleWhen(states) })
		return frame
	end
	local top, bottom = Theme.peekColor("cta.top"), Theme.peekColor("cta.bottom")
	return {
		glow,
		surface("FillIdle", { "idle" }, {
			corners = "brand",
			gradient = { top = top, bottom = bottom, nominalHeight = height },
			zIndex = 2,
		}),
		surface("FillHover", { "hover" }, {
			corners = "brand",
			gradient = { top = Theme.peekColor("accent.dusk_hi"), bottom = bottom, nominalHeight = height },
			zIndex = 2,
		}),
		surface("FillPressed", { "pressed" }, { corners = "brand", fill = Theme.color("accent.dusk_lo"), zIndex = 2 }),
		surface("FillDisabled", { "disabled" }, {
			corners = "brand",
			fill = Theme.color("bg.raised"),
			border = Theme.color("border.subtle"),
			zIndex = 2,
		}),
	}
end

local function plainSurface(variant: Variant, visual: State<VisualState>): { Instance }
	if variant == "ghost" then
		return {}
	end
	local fill = State.Computed(function(): Color3
		local state = visual:get()
		if variant == "danger" then
			if state == "hover" then
				return Theme.color("bg.raised"):get():Lerp(Theme.color("state.danger"):get(), 0.12)
			elseif state == "pressed" then
				return Theme.color("bg.raised"):get():Lerp(Theme.color("state.danger"):get(), 0.2)
			end
			return Theme.color("bg.raised"):get()
		end
		if state == "hover" then
			return Theme.color("bg.selected"):get()
		elseif state == "pressed" then
			return Theme.color("bg.inset"):get()
		end
		return Theme.color("bg.raised"):get()
	end)
	local border = State.Computed(function(): Color3
		local state = visual:get()
		if variant == "danger" then
			return if state == "disabled" then Theme.color("border.subtle"):get() else Theme.color("state.danger"):get()
		end
		return if state == "disabled" then Theme.color("border.subtle"):get() else Theme.color("border.strong"):get()
	end)
	return { Chamfer.new({ name = "Fill", corners = "brand", fill = fill, border = border, zIndex = 2 }) }
end

local function labelColor(variant: Variant, visual: State<VisualState>): State<Color3>
	return State.Computed(function(): Color3
		local state = visual:get()
		if state == "disabled" then
			return Theme.color("text.disabled"):get()
		elseif variant == "primary" or variant == "battle" then
			return Theme.color("text.inverse"):get()
		elseif variant == "danger" then
			return Theme.color("state.danger"):get()
		elseif variant == "ghost" then
			if state == "hover" then
				return Theme.color("text.primary"):get()
			elseif state == "pressed" then
				return Theme.color("text.tertiary"):get()
			end
			return Theme.color("text.secondary"):get()
		end
		return Theme.color("text.primary"):get()
	end)
end

--- Builds a button (a TextButton; content in "Content").
function Button.new(props: ButtonProps): TextButton
	local variant: Variant = props.variant or "secondary"
	if
		variant ~= "primary"
		and variant ~= "secondary"
		and variant ~= "ghost"
		and variant ~= "danger"
		and variant ~= "battle"
	then
		error(`Button: unknown variant "{tostring(variant)}"`, 2)
	end
	local sizeName: Size = props.size or (if variant == "primary" then "large" else "medium")
	local baseHeight = if variant == "battle" then Theme.sizes.buttonHeight.battle else HEIGHTS[sizeName]
	if baseHeight == nil then
		error(`Button: unknown size "{tostring(sizeName)}"`, 2)
	end
	local height: State<number> = Common.touchHeight(baseHeight)
	local disabled = props.disabled or false
	local loading = props.loading or false
	local button = Create.TextButton({
		Name = props.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = true,
	})
	local interaction = Common.trackInteraction(button, true)
	local visual: State<VisualState> = State.Computed(function(): VisualState
		return Button.visualState(
			State.get(disabled),
			interaction.pressed:get(),
			interaction.hovered:get() or (variant == "ghost" and interaction.selected:get())
		)
	end) :: any
	local role: Theme.TypeRole = labelRole(variant)
	local text = props.text
	local color = labelColor(variant, visual)
	local isLoading = State.map(loading, function(v: boolean): boolean
		return v
	end)
	local hasIcon = props.icon ~= nil
	local iconSize = if baseHeight >= 56 then 24 else 20
	local content: { Instance } = {
		Layout.list({ direction = "x", gap = Theme.space(2), align = "center", justify = "center" }),
	}
	if hasIcon then
		table.insert(
			content,
			Icon.new({
				key = props.icon :: CanBeState<string>,
				size = iconSize,
				color = color,
				LayoutOrder = 1,
				Visible = Common.negate(isLoading),
			})
		)
	end
	table.insert(content, Spinner.new({ size = iconSize, color = color, LayoutOrder = 1, Visible = isLoading }))
	table.insert(
		content,
		Text.new({
			Name = "Label",
			text = text,
			role = role,
			color = color,
			LayoutOrder = 2,
		})
	)
	if props.iconRight ~= nil then
		table.insert(
			content,
			Icon.new({ key = props.iconRight :: CanBeState<string>, size = iconSize, color = color, LayoutOrder = 3 })
		)
	end
	if props.hint ~= nil then
		table.insert(content, KeyPrompt.new({ action = props.hint, size = 20, LayoutOrder = 4 }))
	end
	local surfaces: { Instance } = if variant == "primary" or variant == "battle"
		then ctaSurfaces(visual, baseHeight)
		else plainSurface(variant, visual)
	local children: { Instance } = {}
	for _, surface in surfaces do
		table.insert(children, surface)
	end
	if variant == "ghost" then
		-- Hover underline (outside the content list so it does not take a layout slot).
		table.insert(
			children,
			Create.Frame({
				Name = "Underline",
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -8),
				Size = UDim2.new(1, -2 * PADDING[sizeName], 0, 1),
				BackgroundColor3 = Theme.color("text.primary"),
				ZIndex = 5,
				Visible = State.Computed(function(): boolean
					return visual:get() == "hover"
				end),
			})
		)
	end
	table.insert(
		children,
		Create.Frame({
			Name = "Content",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Position = State.Computed(function(): UDim2
				return UDim2.fromOffset(0, if visual:get() == "pressed" then 1 else 0)
			end),
			ZIndex = 5,
			[Create.Children] = content,
		})
	)
	local size: CanBeState<UDim2>
	if props.Size ~= nil then
		size = props.Size
	elseif props.width == "fill" then
		size = State.map(height, function(h: number): UDim2
			return UDim2.new(1, 0, 0, h)
		end)
	elseif type(props.width) == "number" then
		local fixed = props.width :: number
		size = State.map(height, function(h: number): UDim2
			return UDim2.fromOffset(fixed, h)
		end)
	else
		local extras = (if hasIcon then iconSize + Theme.space(2) else 0)
			+ (if props.iconRight ~= nil then iconSize + Theme.space(2) else 0)
		size = State.Computed(function(): UDim2
			local h = height:get()
			local label = State.get(text)
			Theme.textSize(role):get()
			local hintWidth = if props.hint ~= nil and not InputMode.isTouch:get() then 32 + Theme.space(2) else 0
			local width = Button.computeWidth(variant, h, Common.measureText(label, role), extras + hintWidth)
			return UDim2.fromOffset(width, h)
		end)
	end
	local values: { [any]: any } = Common.layout(props, {})
	values.Size = size
	values[Create.Children] = children
	values[Create.On("Activated")] = function()
		if State.peek(disabled) or State.peek(loading) then
			if State.peek(disabled) then
				Sound.play(Sound.KEYS.error)
			end
			return
		end
		if props.sound ~= false then
			local default = if variant == "primary" or variant == "battle" then Sound.KEYS.confirm else Sound.KEYS.click
			Sound.play(if type(props.sound) == "string" then props.sound else default)
		end
		if props.onActivated ~= nil then
			props.onActivated()
		end
	end
	if variant == "danger" then
		values.SelectionImageObject = FocusRing.get("danger")
	end
	Create.apply(button, values)
	if props.tooltip ~= nil then
		local Tooltip = require("./Tooltip") :: any
		Create.onDestroy(button, Tooltip.attach(button, props.tooltip))
	end
	return Common.parent(button, props)
end

return Button
