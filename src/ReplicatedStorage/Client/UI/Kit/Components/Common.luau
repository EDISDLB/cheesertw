--!strict
--[[
	Components/Common — shared prop handling and interaction tracking for kit components.

	Purpose:          Keeps every component's API consistent: the same layout props (Name, Position, AnchorPoint,
	                  Size, LayoutOrder, ZIndex, Visible, Parent — any of them may be State), colour props that accept
	                  a token name or a Color3/State, and one interaction tracker (hover / pressed / gamepad-selected)
	                  wired to MouseEnter/Leave, MouseButton1Down/Up, touch InputBegan/Ended and
	                  SelectionGained/Lost, cleaned with the instance.
	Dependencies:     Kit/State, Kit/Create, Kit/Theme, Kit/InputMode, Kit/Layout, Kit/Sound.
	State:            None at module level; per tracked button: three Values.
	Validation:       Unknown colour tokens raise (Theme).
	Error handling:   N/A.
	Performance notes: One connection per tracked event; Values only notify on change.
]]

local State = require("../State")
local Create = require("../Create")
local Theme = require("../Theme")
local InputMode = require("../InputMode")
local Layout = require("../Layout")
local Sound = require("../Sound")

type State<T> = State.State<T>
type CanBeState<T> = State.CanBeState<T>

export type LayoutProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
}

--- Child instances passed to a component (`children`, `actions`). Typed `{ any }` on purpose: Luau tables are
--- invariant, so a literal like `{ Text.body("..."), Button.new({...}) }` (a `{TextLabel | TextButton}`) would not
--- check against `{ Instance }`. Components validate at runtime (Create raises on non-Instances).
export type Children = { any }

--- A colour prop: a token name ("bg.panel") or a Color3 / State<Color3>.
export type ColorProp = string | CanBeState<Color3>

export type Interaction = {
	hovered: State<boolean>,
	pressed: State<boolean>,
	--- Gamepad selection (GuiService.SelectedObject is this element).
	selected: State<boolean>,
}

local Common = {}

local LAYOUT_KEYS = { "Name", "Position", "AnchorPoint", "Size", "LayoutOrder", "ZIndex", "Visible" }

--- Copies the layout props that are set (Parent excluded: apply it last with Common.parent).
function Common.layout(props: any, into: { [any]: any }, defaults: { [string]: any }?): { [any]: any }
	local base: { [string]: any } = defaults or {}
	for key, value in base do
		into[key] = value
	end
	for _, key in LAYOUT_KEYS do
		local value = props[key]
		if value ~= nil then
			into[key] = value
		end
	end
	return into
end

--- Parents `instance` to props.Parent (after it is fully built) and returns it.
function Common.parent<T>(instance: T, props: any): T
	if props.Parent ~= nil then
		(instance :: any).Parent = props.Parent
	end
	return instance
end

--- Resolves a colour prop (token name, Color3 or State) with a token fallback.
function Common.color(value: ColorProp?, fallback: Theme.ColorToken): CanBeState<Color3>
	if value == nil then
		return Theme.color(fallback)
	end
	if type(value) == "string" then
		return Theme.color(value :: any)
	end
	return value :: any
end

--- Boolean prop with a default.
function Common.bool(value: CanBeState<boolean>?, default: boolean): CanBeState<boolean>
	if value == nil then
		return default
	end
	return value
end

--- Reactive negation of a maybe-state boolean.
function Common.negate(value: CanBeState<boolean>): State<boolean>
	return State.map(value, function(v: boolean): boolean
		return not v
	end)
end

--- Tracks hover / press / gamepad selection on a GuiButton (cleaned when it is destroyed).
--- `hoverSound` plays ui_hover on mouse enter (gamepad focus ticks come from Kit/Focus).
function Common.trackInteraction(button: GuiButton, hoverSound: boolean?): Interaction
	local hovered = State.Value(false)
	local pressed = State.Value(false)
	local selected = State.Value(false)
	Create.apply(button, {
		[Create.On("MouseEnter")] = function()
			hovered:set(true)
			if hoverSound and InputMode.mode:peek() == "MouseKeyboard" then
				Sound.play(Sound.KEYS.hover)
			end
		end,
		[Create.On("MouseLeave")] = function()
			hovered:set(false)
			pressed:set(false)
		end,
		[Create.On("MouseButton1Down")] = function()
			pressed:set(true)
		end,
		[Create.On("MouseButton1Up")] = function()
			pressed:set(false)
		end,
		[Create.On("InputBegan")] = function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
				pressed:set(true)
			end
		end,
		[Create.On("InputEnded")] = function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA then
				pressed:set(false)
			end
		end,
		[Create.On("SelectionGained")] = function()
			selected:set(true)
		end,
		[Create.On("SelectionLost")] = function()
			selected:set(false)
			pressed:set(false)
		end,
	})
	return {
		hovered = State.readonly(hovered),
		pressed = State.readonly(pressed),
		selected = State.readonly(selected),
	}
end

-- Buttons whose current touch press became a tooltip long-press (weak keys: destroyed buttons drop out).
local longPressed: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--- Marks `target`'s current touch press as a tooltip long-press (Tooltip.attach calls this): the Activated event
--- that ends the press must not trigger the button (ui-ux §1.7: long-press reads the tooltip, it never activates).
function Common.markLongPress(target: Instance)
	longPressed[target] = true
end

--- Clears a stale mark (a new press began).
function Common.clearLongPress(target: Instance)
	longPressed[target] = nil
end

--- True (once) if the press that is activating `target` was a tooltip long-press. Activation handlers call it first.
function Common.consumeLongPress(target: Instance): boolean
	if longPressed[target] then
		longPressed[target] = nil
		return true
	end
	return false
end

--- Product of the UIScale factors on `instance` and its ancestors (AbsoluteSize px -> layout px).
function Common.effectiveScale(instance: Instance): number
	local scale = 1
	local current: Instance? = instance
	while current ~= nil do
		local uiScale = current:FindFirstChildOfClass("UIScale")
		if uiScale ~= nil then
			scale *= uiScale.Scale
		end
		current = current.Parent
	end
	return if scale > 0 then scale else 1
end

--- Touch-safe height: while touch is the input mode, raises `height` to 44 px (48 px authored on Compact, so the
--- 0.92 floor scale still renders >= 44; ui-ux §1.14).
function Common.touchHeight(height: number): State<number>
	return State.Computed(function(): number
		if InputMode.isTouch:get() then
			local minimum = if Layout.isCompact:get() then Theme.sizes.touchPrimary else Theme.sizes.touchMin
			return math.max(height, minimum)
		end
		return height
	end)
end

-- Legacy Enum.Font twins of the brand faces (TextService:GetTextSize takes Enum.Font).
local LEGACY_FONTS: { [string]: string } = {
	["Oswald"] = "Oswald",
	["BuilderSans:Regular"] = "BuilderSans",
	["BuilderSans:Medium"] = "BuilderSansMedium",
	["BuilderSans:Bold"] = "BuilderSansBold",
	["BuilderSans:SemiBold"] = "BuilderSansBold",
	["BuilderSans:ExtraBold"] = "BuilderSansExtraBold",
	["BuilderMono"] = "RobotoMono",
}

-- Average advance per character as a fraction of the text size (fallback when TextService is unavailable).
local AVERAGE_ADVANCE: { [string]: number } = { Oswald = 0.5, BuilderSans = 0.56, BuilderMono = 0.62 }

--- Width in px of `text` set in a typography role (TextService when available, else a per-face estimate).
--- Honors the player's PreferredTextSize through TextService. Inside a Computed it depends on the role's size.
function Common.measureText(text: string, role: Theme.TypeRole): number
	if text == "" then
		return 0
	end
	local spec = Theme.typography(role)
	-- Tracked reads: a Computed that measures (auto-width buttons, tabs) re-measures when the text scale, layout
	-- minimums or render scale change the size, and when the player's PreferredTextSize changes (TextService
	-- measurements include it).
	local size = spec.size:get()
	Theme.state.preferredTextSize:get()
	local family = string.match(spec.font.Family, "families/([%w]+)%.json$") or "BuilderSans"
	local weight = spec.font.Weight.Name
	local legacy = LEGACY_FONTS[family .. ":" .. weight] or LEGACY_FONTS[family]
	local shown = if spec.upper then string.upper(text) else text
	if legacy ~= nil then
		local ok, bounds = pcall(function(): Vector2
			local TextService = game:GetService("TextService")
			return TextService:GetTextSize(shown, size, (Enum.Font :: any)[legacy], Vector2.new(4096, 4096))
		end)
		if ok and typeof(bounds) == "Vector2" then
			return math.ceil(bounds.X)
		end
	end
	local advance = AVERAGE_ADVANCE[family] or 0.56
	if spec.upper then
		advance *= 1.12
	end
	return math.ceil(utf8.len(shown) or #shown) * size * advance
end

--- Applies the brand case for a role: UPPERCASE display roles (reactive when `text` is a State).
function Common.cased(text: CanBeState<string>, upper: boolean): CanBeState<string>
	if not upper then
		return text
	end
	if State.isState(text) then
		return State.map(text, string.upper)
	end
	return string.upper(text :: string)
end

return Common
