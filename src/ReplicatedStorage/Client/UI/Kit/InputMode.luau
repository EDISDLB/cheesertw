--!strict
--[[
	Kit/InputMode — current input mode as State, plus key/button glyphs for UI actions.

	Purpose:          `InputMode.mode` is "MouseKeyboard" | "Gamepad" | "Touch", driven by
	                  UserInputService.PreferredInput (MicroGamepad counts as Gamepad), falling back to the last input
	                  type on engines without PreferredInput. Screens switch prompts, focus rings and layouts on it.
	                  `InputMode.glyph(action)` resolves the prompt for a UI action in the current mode: keyboard key
	                  text (layout-aware GetStringForKeyCode, abbreviated) or the gamepad button image
	                  (GetImageForKeyCode: Xbox/PlayStation art) with a short text fallback (A / ✕ / LB / L1 ...).
	Dependencies:     Kit/State, Kit/Services, Core/Signal.
	State:            Module-level mode Value, action registry (name -> keyboard/gamepad key codes).
	Validation:       Actions must declare at least one key; reserved keys (Esc, ButtonStart, F9, F11, F12,
	                  PrintScreen — 00-DECISIONS §16) are rejected at registration.
	Error handling:   Engine glyph calls are pcall'd; failures fall back to built-in text labels.
	Performance notes: Glyph lookups are cheap but not cached (layouts can change); bind them through glyphState.

	Default UI actions (screens may add more with InputMode.registerAction):
	  Confirm  Return / ButtonA        Back      Backspace / ButtonB     Secondary  F / ButtonX
	  Tertiary G / ButtonY             TabPrev   Q / ButtonL1            TabNext    E / ButtonR1
	  PagePrev Z / ButtonL2            PageNext  C / ButtonR2            Scoreboard Tab / ButtonSelect
]]

local State = require("./State")
local Services = require("./Services")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

type State<T> = State.State<T>

export type Mode = "MouseKeyboard" | "Gamepad" | "Touch"
export type GlyphKind = "key" | "button" | "none"
export type Glyph = {
	kind: GlyphKind,
	keyCode: Enum.KeyCode?,
	--- Short text for a keycap/button plate ("Enter", "Bksp", "A", "✕", "LB").
	text: string,
	--- Gamepad button art (rbxasset/rbxassetid) when the engine provides it.
	image: string?,
}
export type ActionSpec = {
	keyboard: { Enum.KeyCode },
	gamepad: { Enum.KeyCode },
	label: string?,
}

local InputMode = {}

InputMode.MODES = { "MouseKeyboard", "Gamepad", "Touch" } :: { Mode }

--- Inputs Roblox reserves (00-DECISIONS §16), by KeyCode name: never bind or prompt them.
InputMode.RESERVED = table.freeze({
	Escape = true,
	ButtonStart = true,
	F9 = true,
	F11 = true,
	F12 = true,
	Print = true,
})

--- True for keys Roblox reserves (Esc/ButtonStart menu, F9 console, F11 fullscreen, F12 record, PrintScreen).
function InputMode.isReserved(keyCode: Enum.KeyCode): boolean
	return InputMode.RESERVED[keyCode.Name] == true
end

local modeValue: State.Value<Mode> = State.Value("MouseKeyboard") :: any

--- Reactive input mode.
InputMode.mode = State.readonly(modeValue) :: State<Mode>

local isCache: { [string]: State<boolean> } = {}

--- Reactive "mode == m" (cached).
function InputMode.is(mode: Mode): State<boolean>
	local cached = isCache[mode]
	if cached then
		return cached
	end
	local state = State.Computed(function(): boolean
		return modeValue:get() == mode
	end)
	isCache[mode] = state
	return state
end

InputMode.isGamepad = InputMode.is("Gamepad")
InputMode.isTouch = InputMode.is("Touch")
InputMode.isMouseKeyboard = InputMode.is("MouseKeyboard")

--- Maps Enum.PreferredInput to a mode (MicroGamepad -> Gamepad).
function InputMode.fromPreferredInput(preferred: EnumItem?): Mode?
	if preferred == nil then
		return nil
	end
	local name = preferred.Name
	if name == "KeyboardAndMouse" then
		return "MouseKeyboard"
	elseif name == "Gamepad" or name == "MicroGamepad" then
		return "Gamepad"
	elseif name == "Touch" then
		return "Touch"
	end
	return nil
end

--- Maps a UserInputType to a mode (nil for types that say nothing about the device, e.g. Focus).
function InputMode.fromUserInputType(inputType: EnumItem?): Mode?
	if inputType == nil then
		return nil
	end
	local name = inputType.Name
	if name == "Keyboard" or string.sub(name, 1, 5) == "Mouse" or name == "TextInput" then
		return "MouseKeyboard"
	elseif string.sub(name, 1, 7) == "Gamepad" then
		return "Gamepad"
	elseif name == "Touch" then
		return "Touch"
	end
	return nil
end

--- Forces a mode (tests, gallery preview). `start` overrides it again on the next device change.
function InputMode.set(mode: Mode)
	if table.find(InputMode.MODES, mode) == nil then
		error(`InputMode.set: unknown mode "{tostring(mode)}"`, 2)
	end
	modeValue:set(mode)
end

--- Follows PreferredInput (or the last input type when PreferredInput is unavailable). Returns stop().
function InputMode.start(): () -> ()
	local UserInputService = Services.input()
	local connections: { RBXScriptConnection } = {}
	local okPreferred, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if okPreferred and preferred ~= nil then
		local function sync()
			local mode: Mode? = InputMode.fromPreferredInput(UserInputService.PreferredInput)
			if mode ~= nil then
				modeValue:set(mode)
			end
		end
		sync()
		table.insert(connections, UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(sync))
	else
		local function apply(inputType: EnumItem)
			local mode: Mode? = InputMode.fromUserInputType(inputType)
			if mode ~= nil then
				modeValue:set(mode)
			end
		end
		apply(UserInputService:GetLastInputType())
		table.insert(connections, UserInputService.LastInputTypeChanged:Connect(apply))
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end
end

--------------------------------------------------------------------------------
-- Actions and glyphs
--------------------------------------------------------------------------------

local actions: { [string]: ActionSpec } = {}

--- Fires (action name) after an action's keys change (remapping): UIInput rebinds its context, prompts refresh.
InputMode.actionsChanged = Signal.new() :: Signal.Signal<string>
local actionsVersion = State.Value(0)

--- Registers (or replaces) a UI action's keys (also the remapping entry point). Reserved keys raise.
function InputMode.registerAction(name: string, spec: ActionSpec)
	if type(name) ~= "string" or name == "" then
		error("InputMode.registerAction: name must be a non-empty string", 2)
	end
	if #spec.keyboard == 0 and #spec.gamepad == 0 then
		error(`InputMode.registerAction("{name}"): at least one key is required`, 2)
	end
	for _, list in { spec.keyboard, spec.gamepad } do
		for _, keyCode in list do
			if InputMode.isReserved(keyCode) then
				error(`InputMode.registerAction("{name}"): {keyCode.Name} is reserved by Roblox`, 2)
			end
		end
	end
	actions[name] = {
		keyboard = table.clone(spec.keyboard),
		gamepad = table.clone(spec.gamepad),
		label = spec.label,
	}
	actionsVersion:update(function(v: number): number
		return v + 1
	end)
	InputMode.actionsChanged:Fire(name)
end

function InputMode.action(name: string): ActionSpec?
	return actions[name]
end

InputMode.registerAction("Confirm", { keyboard = { Enum.KeyCode.Return }, gamepad = { Enum.KeyCode.ButtonA } })
InputMode.registerAction("Back", { keyboard = { Enum.KeyCode.Backspace }, gamepad = { Enum.KeyCode.ButtonB } })
InputMode.registerAction("Secondary", { keyboard = { Enum.KeyCode.F }, gamepad = { Enum.KeyCode.ButtonX } })
InputMode.registerAction("Tertiary", { keyboard = { Enum.KeyCode.G }, gamepad = { Enum.KeyCode.ButtonY } })
InputMode.registerAction("TabPrev", { keyboard = { Enum.KeyCode.Q }, gamepad = { Enum.KeyCode.ButtonL1 } })
InputMode.registerAction("TabNext", { keyboard = { Enum.KeyCode.E }, gamepad = { Enum.KeyCode.ButtonR1 } })
InputMode.registerAction("PagePrev", { keyboard = { Enum.KeyCode.Z }, gamepad = { Enum.KeyCode.ButtonL2 } })
InputMode.registerAction("PageNext", { keyboard = { Enum.KeyCode.C }, gamepad = { Enum.KeyCode.ButtonR2 } })
InputMode.registerAction("Scoreboard", { keyboard = { Enum.KeyCode.Tab }, gamepad = { Enum.KeyCode.ButtonSelect } })

local KEYBOARD_FALLBACK: { [string]: string } = {
	Return = "Enter",
	KeypadEnter = "Enter",
	Backspace = "Bksp",
	Space = "Space",
	Tab = "Tab",
	LeftShift = "Shift",
	RightShift = "Shift",
	LeftControl = "Ctrl",
	RightControl = "Ctrl",
	LeftAlt = "Alt",
	RightAlt = "Alt",
	Delete = "Del",
	Up = "↑",
	Down = "↓",
	Left = "←",
	Right = "→",
	MouseLeftButton = "LMB",
	MouseRightButton = "RMB",
	MouseMiddleButton = "MMB",
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Five = "5",
	Six = "6",
	Seven = "7",
	Eight = "8",
	Nine = "9",
	Zero = "0",
}

-- GetStringForKeyCode names (Xbox and PlayStation, per the UserInputService reference) -> short plate text.
local GAMEPAD_TEXT: { [string]: string } = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonLB = "LB",
	ButtonRB = "RB",
	ButtonLT = "LT",
	ButtonRT = "RT",
	ButtonLS = "LS",
	ButtonRS = "RS",
	ButtonSelect = "View",
	ButtonCross = "✕",
	ButtonCircle = "○",
	ButtonSquare = "□",
	ButtonTriangle = "△",
	ButtonL1 = "L1",
	ButtonR1 = "R1",
	ButtonL2 = "L2",
	ButtonR2 = "R2",
	ButtonL3 = "L3",
	ButtonR3 = "R3",
	ButtonTouchpad = "Pad",
	ButtonShare = "Share",
	DPadUp = "↑",
	DPadDown = "↓",
	DPadLeft = "←",
	DPadRight = "→",
}

-- Engine-independent names for gamepad key codes (used when GetStringForKeyCode is unavailable).
local GAMEPAD_DEFAULT: { [string]: string } = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonL3 = "LS",
	ButtonR3 = "RS",
	ButtonSelect = "View",
}

--- Short label for a keyboard key (layout-aware through GetStringForKeyCode when the engine supports it).
function InputMode.keyText(keyCode: Enum.KeyCode): string
	local name = keyCode.Name
	local fallback = KEYBOARD_FALLBACK[name]
	-- Mouse buttons, arrows and digits use fixed symbols (layout-independent).
	if fallback ~= nil and (string.sub(name, 1, 5) == "Mouse" or utf8.len(fallback) == 1) then
		return fallback
	end
	local ok, text = pcall(function()
		return Services.input():GetStringForKeyCode(keyCode, (Enum :: any).KeyCodeStringFormat.Abbreviated)
	end)
	if not ok or type(text) ~= "string" or text == "" then
		ok, text = pcall(function()
			return Services.input():GetStringForKeyCode(keyCode)
		end)
	end
	if ok and type(text) == "string" and text ~= "" and text ~= name then
		return text
	end
	return fallback or name
end

--- Short label for a gamepad button (Xbox letters / PlayStation symbols per the connected pad).
function InputMode.buttonText(keyCode: Enum.KeyCode): string
	local ok, mapped = pcall(function()
		return Services.input():GetStringForKeyCode(keyCode)
	end)
	if ok and type(mapped) == "string" and GAMEPAD_TEXT[mapped] ~= nil then
		return GAMEPAD_TEXT[mapped]
	end
	return GAMEPAD_DEFAULT[keyCode.Name] or GAMEPAD_TEXT[keyCode.Name] or keyCode.Name
end

--- Gamepad button art for the connected controller, or nil.
function InputMode.buttonImage(keyCode: Enum.KeyCode): string?
	local ok, image = pcall(function()
		return Services.input():GetImageForKeyCode(keyCode)
	end)
	if ok and type(image) == "string" and image ~= "" then
		return image
	end
	return nil
end

--- Glyph for an action (or a raw KeyCode) in `mode` (default: current mode). Touch has no key prompts.
function InputMode.glyph(action: string | Enum.KeyCode, mode: Mode?): Glyph
	local current = mode or modeValue:peek()
	if current == "Touch" then
		return { kind = "none", keyCode = nil, text = "", image = nil }
	end
	local keyCode: Enum.KeyCode? = nil
	if typeof(action) == "EnumItem" then
		keyCode = action :: Enum.KeyCode
	else
		local spec = actions[action :: string]
		if spec == nil then
			error(`InputMode.glyph: unknown action "{tostring(action)}"`, 2)
		end
		local list = if current == "Gamepad" then spec.gamepad else spec.keyboard
		keyCode = list[1]
	end
	if keyCode == nil then
		return { kind = "none", keyCode = nil, text = "", image = nil }
	end
	local isGamepadKey = string.sub(keyCode.Name, 1, 6) == "Button" or string.sub(keyCode.Name, 1, 4) == "DPad"
	if isGamepadKey then
		return {
			kind = "button",
			keyCode = keyCode,
			text = InputMode.buttonText(keyCode),
			image = InputMode.buttonImage(keyCode),
		}
	end
	return { kind = "key", keyCode = keyCode, text = InputMode.keyText(keyCode), image = nil }
end

--- Reactive glyph that follows the input mode and remapping.
function InputMode.glyphState(action: string | Enum.KeyCode): State<Glyph>
	return State.Computed(function(): Glyph
		actionsVersion:get()
		return InputMode.glyph(action, modeValue:get())
	end, { equals = State.shallowEqual })
end

--- Key codes that trigger `action` in any mode (for input handlers).
function InputMode.keysFor(action: string): { Enum.KeyCode }
	local spec = actions[action]
	if spec == nil then
		error(`InputMode.keysFor: unknown action "{tostring(action)}"`, 2)
	end
	local out = table.clone(spec.keyboard)
	for _, keyCode in spec.gamepad do
		table.insert(out, keyCode)
	end
	return out
end

--- True if `keyCode` triggers `action`.
function InputMode.matches(action: string, keyCode: Enum.KeyCode): boolean
	local spec = actions[action]
	if spec == nil then
		return false
	end
	return table.find(spec.keyboard, keyCode) ~= nil or table.find(spec.gamepad, keyCode) ~= nil
end

return InputMode
