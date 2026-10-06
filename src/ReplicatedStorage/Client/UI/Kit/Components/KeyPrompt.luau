--!strict
--[[
	Components/KeyPrompt — input glyph for a UI action (keycap or gamepad button) + optional label; HintBar.

	Purpose:          Shows the right prompt for the current input mode (Kit/InputMode): gamepad button art from
	                  GetImageForKeyCode (Xbox/PlayStation) with a text plate fallback, keyboard keycaps with the
	                  layout-aware key name, nothing on touch. `KeyPrompt.hintBar` builds the footer hint row
	                  (research 09 R3: X/Y contextual actions shown in a footer hint bar).
	Dependencies:     Kit/Create, Kit/State, Kit/Theme, Kit/InputMode, Kit/Layout, Components/Chamfer, Components/Text,
	                  Components/Common.
	State:            One reactive glyph per prompt.
	Validation:       Unknown actions raise (InputMode).
	Error handling:   N/A.
	Performance notes: 4–8 instances per prompt; glyph updates only on input-mode changes.
]]

local Create = require("../Create")
local State = require("../State")
local Theme = require("../Theme")
local InputMode = require("../InputMode")
local Layout = require("../Layout")
local Chamfer = require("./Chamfer")
local Text = require("./Text")
local Common = require("./Common")

type CanBeState<T> = State.CanBeState<T>

export type KeyPromptProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	action: string | Enum.KeyCode,
	label: CanBeState<string>?,
	--- Glyph height in px (default 24).
	size: number?,
}

export type Hint = { action: string, label: string }
export type HintBarProps = {
	Name: string?,
	Position: CanBeState<UDim2>?,
	AnchorPoint: CanBeState<Vector2>?,
	Size: CanBeState<UDim2>?,
	LayoutOrder: CanBeState<number>?,
	ZIndex: number?,
	Visible: CanBeState<boolean>?,
	Parent: Instance?,
	hints: CanBeState<{ Hint }>,
	align: ("left" | "center" | "right")?,
	--- Also show on mouse/keyboard (setting `ui.hintsKbm`; default false: gamepad/TV only, ui-ux §1.12).
	keyboard: CanBeState<boolean>?,
}

local KeyPrompt = {}

function KeyPrompt.new(props: KeyPromptProps): Frame
	local size = props.size or 24
	local glyph = InputMode.glyphState(props.action)
	local hasImage = State.Computed(function(): boolean
		return glyph:get().image ~= nil
	end)
	local showCap = State.Computed(function(): boolean
		local g = glyph:get()
		return g.kind ~= "none" and g.image == nil
	end)
	local visible = State.Computed(function(): boolean
		return glyph:get().kind ~= "none"
	end)
	local children: { Instance } = {
		Layout.list({ direction = "x", gap = Theme.space(1), align = "center" }),
		Create.ImageLabel({
			Name = "ButtonImage",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			Image = State.Computed(function(): string
				return glyph:get().image or ""
			end),
			Visible = hasImage,
			LayoutOrder = 1,
		}),
		Create.Frame({
			Name = "Keycap",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size),
			AutomaticSize = Enum.AutomaticSize.X,
			Visible = showCap,
			LayoutOrder = 2,
			[Create.Children] = {
				-- ui-ux §1.12 keycap: bg.inset fill, 1 px border.strong, Builder Mono label (chamfered, never round).
				Chamfer.new({
					corners = "all",
					size = 3,
					fill = Theme.color("bg.inset"),
					border = Theme.color("border.strong"),
				}) :: Instance,
				Layout.padding({ x = 6 }),
				Text.new({
					text = State.Computed(function(): string
						return glyph:get().text
					end),
					role = "keycap",
					upper = false,
					Size = UDim2.new(0, 0, 1, 0),
					autoSize = "x",
					align = "center",
					ZIndex = 3,
				}),
			},
		}),
	}
	if props.label ~= nil then
		table.insert(children, Text.new({ text = props.label, role = "caption", LayoutOrder = 3 }))
	end
	local values: { [any]: any } = Common.layout(props, {}, { Name = "KeyPrompt", Size = UDim2.fromOffset(0, size) })
	values.BackgroundTransparency = 1
	values.AutomaticSize = Enum.AutomaticSize.X
	-- Hidden when the current input has no glyph (touch), and whenever the caller hides it.
	local callerVisible = props.Visible
	values.Visible = if callerVisible == nil
		then visible
		else State.Computed(function(): boolean
			return visible:get() and State.get(callerVisible :: State.CanBeState<boolean>)
		end)
	values[Create.Children] = children
	return Common.parent(Create.Frame(values), props)
end

--- Footer hint row: one KeyPrompt + label per hint. Gamepad only by default (`keyboard` adds mouse/keyboard); never
--- on touch. Screens reserve its 48 px at the bottom while it is visible (ui-ux §1.12).
function KeyPrompt.hintBar(props: HintBarProps): Frame
	local justify: Layout.Justify = if props.align == "left"
		then "start"
		elseif props.align == "center" then "center"
		else "end"
	local values: { [any]: any } = Common.layout(props, {}, { Name = "HintBar", Size = UDim2.new(1, 0, 0, 48) })
	values.BackgroundTransparency = 1
	local keyboard: CanBeState<boolean> = props.keyboard or false
	local shown = State.Computed(function(): boolean
		local mode = InputMode.mode:get()
		return mode == "Gamepad" or (mode == "MouseKeyboard" and State.get(keyboard))
	end)
	local callerVisible = props.Visible
	values.Visible = if callerVisible == nil
		then shown
		else State.Computed(function(): boolean
			return shown:get() and State.get(callerVisible :: State.CanBeState<boolean>)
		end)
	values[Create.Children] = {
		Layout.list({ direction = "x", gap = Theme.space(5), align = "center", justify = justify }) :: any,
		State.list(props.hints, function(hint: Hint): any
			return hint.action
		end, function(hint: State.Value<Hint>, index: State.Value<number>): Instance
			return KeyPrompt.new({
				action = hint:peek().action,
				label = State.map(hint, function(h: Hint): string
					return h.label
				end),
				LayoutOrder = index,
			})
		end),
	}
	return Common.parent(Create.Frame(values), props)
end

return KeyPrompt
