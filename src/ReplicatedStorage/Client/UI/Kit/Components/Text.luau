--!strict
--[[
	Components/Text — TextStyles: labels built from typography roles (the only way screens should make text).

	Purpose:          `Text.new({ role = "h3", text = "Crew" })` or the shortcuts (Text.h1, Text.body, Text.label, ...)
	                  give a TextLabel with the brand face/weight (FontFace), reactive TextSize (text scale, platform
	                  minimums), line height, brand case (UPPER for display/label roles), colour by token, wrapping and
	                  truncation defaults per role. No TextScaled, so the player's PreferredTextSize keeps working
	                  (research 09 R2); AutomaticSize hugs the text unless a Size is given.
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Components/Common.
	State:            None.
	Validation:       Unknown roles/tokens raise (Theme).
	Error handling:   N/A.
	Performance notes: One TextLabel; no UIStroke/UIGradient on text (GuiEffect cost on high-churn labels).
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type Align = "left" | "center" | "right"
export type TextProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	text: CanBeState<string>,
	role: Theme.TypeRole?,
	--- Token name or Color3/State (default text.primary; captions text.secondary).
	color: Common.ColorProp?,
	transparency: CanBeState<number>?,
	align: Align?,
	valign: ("top" | "center" | "bottom")?,
	--- Wrap lines (default: on for sentence roles, off for labels/numerals).
	wrap: boolean?,
	--- Truncate with "..." instead of overflowing (default: on for non-wrapping text with a fixed Size).
	truncate: boolean?,
	--- "x" | "y" | "xy" | "none" (default "xy" without Size, "y" when wrapping with a Size, else "none").
	autoSize: ("x" | "y" | "xy" | "none")?,
	--- Max width in px for auto-sized wrapping text.
	maxWidth: number?,
	richText: boolean?,
	--- Override the role's case.
	upper: boolean?,
}

--- Options for the shortcuts (`Text.h3("Crew", { LayoutOrder = 2 })`): TextProps without `text`.
export type TextOptions = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	role: Theme.TypeRole?,
	color: Common.ColorProp?,
	transparency: CanBeState<number>?,
	align: Align?,
	valign: ("top" | "center" | "bottom")?,
	wrap: boolean?,
	truncate: boolean?,
	autoSize: ("x" | "y" | "xy" | "none")?,
	maxWidth: number?,
	richText: boolean?,
	upper: boolean?,
}

local Text = {}

local function xAlignment(align: Align?): Enum.TextXAlignment
	if align == "center" then
		return Enum.TextXAlignment.Center
	elseif align == "right" then
		return Enum.TextXAlignment.Right
	end
	return Enum.TextXAlignment.Left
end

local function yAlignment(align: ("top" | "center" | "bottom")?): Enum.TextYAlignment
	if align == "top" then
		return Enum.TextYAlignment.Top
	elseif align == "bottom" then
		return Enum.TextYAlignment.Bottom
	end
	return Enum.TextYAlignment.Center
end

local function automaticSize(mode: ("x" | "y" | "xy" | "none")?): Enum.AutomaticSize
	if mode == "x" then
		return Enum.AutomaticSize.X
	elseif mode == "y" then
		return Enum.AutomaticSize.Y
	elseif mode == "xy" then
		return Enum.AutomaticSize.XY
	end
	return Enum.AutomaticSize.None
end

--- Builds a themed TextLabel.
function Text.new(props: TextProps): TextLabel
	local role: Theme.TypeRole = props.role or "body"
	local spec = Theme.typography(role)
	local sentence = spec.kind == "sentence"
	local wrap = if props.wrap == nil then sentence else props.wrap
	local hasSize = props.Size ~= nil
	local autoMode: ("x" | "y" | "xy" | "none")? = props.autoSize
	if autoMode == nil then
		autoMode = if not hasSize then "xy" elseif wrap then "y" else "none"
	end
	local truncate = if props.truncate == nil then (not wrap and hasSize) else props.truncate
	local upper = if props.upper == nil then spec.upper else props.upper
	local defaultColor: Theme.ColorToken = if role == "caption" then "text.secondary" else "text.primary"
	local values: { [any]: any } = Common.layout(props, {}, {
		Name = "Text",
		Size = UDim2.new(),
	})
	values.BackgroundTransparency = 1
	values.BorderSizePixel = 0
	values.Text = Common.cased(props.text, upper)
	values.FontFace = spec.font
	values.TextSize = spec.size
	values.LineHeight = spec.lineHeight
	values.TextColor3 = Common.color(props.color, defaultColor)
	values.TextTransparency = props.transparency or 0
	values.TextXAlignment = xAlignment(props.align)
	values.TextYAlignment = yAlignment(props.valign)
	values.TextWrapped = wrap
	values.TextTruncate = if truncate then Enum.TextTruncate.AtEnd else Enum.TextTruncate.None
	values.AutomaticSize = automaticSize(autoMode)
	values.RichText = props.richText == true
	local label = Create.TextLabel(values)
	if props.maxWidth ~= nil then
		Create.UISizeConstraint({ MaxSize = Vector2.new(props.maxWidth, math.huge), Parent = label })
	end
	return Common.parent(label, props)
end

local function shortcut(role: Theme.TypeRole): (text: CanBeState<string>, options: TextOptions?) -> TextLabel
	return function(text: CanBeState<string>, options: TextOptions?): TextLabel
		local merged: TextProps = if options then table.clone(options) :: any else {} :: any
		merged.text = text
		merged.role = merged.role or role
		return Text.new(merged)
	end
end

Text.display = shortcut("display.hero")
Text.h1 = shortcut("h1")
Text.h2 = shortcut("h2")
Text.h3 = shortcut("h3")
Text.h4 = shortcut("h4")
Text.bodyLarge = shortcut("body.l")
Text.body = shortcut("body")
Text.bodySmall = shortcut("body.s")
Text.label = shortcut("label")
Text.caption = shortcut("caption")
Text.numXL = shortcut("num.xl")
Text.numL = shortcut("num.l")
Text.numM = shortcut("num.m")
Text.mono = shortcut("mono")
Text.micro = shortcut("micro")
Text.titleSmall = shortcut("title.s")

return Text
