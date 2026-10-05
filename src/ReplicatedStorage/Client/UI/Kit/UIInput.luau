--!strict
--[[
	Kit/UIInput — UI navigation actions (Back, TabPrev, TabNext) on the Input Action System.

	Purpose:          Builds one code-created InputContext ("KitUI", ReplicatedStorage/Inputs, research 09 R5) with
	                  Bool InputActions bound to the keys of the InputMode action registry (Back = Backspace/ButtonB,
	                  TabPrev = Q/ButtonL1, TabNext = E/ButtonR1) and re-emits them as Signals that Router (back) and
	                  Focus (shoulder tab switching) listen to. The context is enabled only while a focus scope is
	                  active (Focus toggles it), never sinks input, and ignores presses while a TextBox has focus.
	                  If the engine refuses to create IAS instances, it falls back to UserInputService.InputBegan.
	Dependencies:     Kit/InputMode (key lists), Kit/Services, Core/Signal, Core/Log.
	State:            The created context/actions (one per start), enabled flag, the three Signals.
	Validation:       Only registered action names can be triggered.
	Error handling:   IAS creation failures are logged once and switch to the fallback.
	Performance notes: Event-driven; no per-frame work.
]]

local InputMode = require("./InputMode")
local Services = require("./Services")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

export type ActionName = "Back" | "TabPrev" | "TabNext"
export type StartOptions = {
	--- Where the InputContext lives (default ReplicatedStorage/Inputs, created on demand).
	parent: Instance?,
	--- Context priority (default 3100: above the Input team's Menu context at 3000).
	priority: number?,
	--- Force the UserInputService fallback (tests, engines without IAS).
	useFallback: boolean?,
}

local log = Log.scope("UI.Input")

local UIInput = {}

UIInput.ACTIONS = { "Back", "TabPrev", "TabNext" } :: { ActionName }
UIInput.CONTEXT_NAME = "KitUI"
UIInput.DEFAULT_PRIORITY = 3100

--- Fired when the player asks to go back (Router listens).
UIInput.back = Signal.new() :: Signal.Signal<>
--- Fired for LB / Q (Focus forwards it to the top scope's shoulder handler).
UIInput.tabPrev = Signal.new() :: Signal.Signal<>
--- Fired for RB / E.
UIInput.tabNext = Signal.new() :: Signal.Signal<>

local enabled = false
local context: InputContext? = nil

local function signalFor(name: string): Signal.Signal<>?
	if name == "Back" then
		return UIInput.back
	elseif name == "TabPrev" then
		return UIInput.tabPrev
	elseif name == "TabNext" then
		return UIInput.tabNext
	end
	return nil
end

local function textBoxFocused(): boolean
	local ok, focused = pcall(function(): TextBox?
		return Services.input():GetFocusedTextBox()
	end)
	return ok and focused ~= nil
end

--- Emits an action as if pressed (on-screen back buttons, tests). Ignored while disabled or typing.
function UIInput.trigger(name: ActionName): boolean
	local signal = signalFor(name)
	if signal == nil then
		error(`UIInput.trigger: unknown action "{tostring(name)}"`, 2)
	end
	if not enabled or textBoxFocused() then
		return false
	end
	signal:Fire()
	return true
end

--- Enables/disables the UI context (Focus enables it while any focus scope is active).
function UIInput.setEnabled(value: boolean)
	enabled = value
	local current = context
	if current ~= nil then
		current.Enabled = value
	end
end

function UIInput.isEnabled(): boolean
	return enabled
end

local function inputsFolder(): Instance
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local folder = ReplicatedStorage:FindFirstChild("Inputs")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Inputs"
		folder.Parent = ReplicatedStorage
	end
	return folder :: Instance
end

local function buildContext(parent: Instance, priority: number, connections: { RBXScriptConnection }): InputContext
	local ctx = Instance.new("InputContext")
	ctx.Name = UIInput.CONTEXT_NAME
	ctx.Priority = priority
	ctx.Sink = false
	ctx.Enabled = enabled
	for _, name in UIInput.ACTIONS do
		local action = Instance.new("InputAction")
		action.Name = name
		action.Type = Enum.InputActionType.Bool
		for _, keyCode in InputMode.keysFor(name) do
			local binding = Instance.new("InputBinding")
			binding.Name = keyCode.Name
			binding.KeyCode = keyCode
			binding.Parent = action
		end
		action.Parent = ctx
		table.insert(
			connections,
			action.Pressed:Connect(function()
				UIInput.trigger(name :: ActionName)
			end)
		)
	end
	ctx.Parent = parent
	return ctx
end

--- Creates the IAS context (or the fallback listener). Returns stop().
function UIInput.start(options: StartOptions?): () -> ()
	local opts: StartOptions = options or {}
	local connections: { RBXScriptConnection } = {}
	local created: InputContext? = nil
	if not opts.useFallback then
		local ok, result = pcall(function()
			return buildContext(opts.parent or inputsFolder(), opts.priority or UIInput.DEFAULT_PRIORITY, connections)
		end)
		if ok then
			created = result
			context = result
		else
			log:warn("Input Action System unavailable (%s); using UserInputService fallback", tostring(result))
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
		end
	end
	if created == nil then
		table.insert(
			connections,
			Services.input().InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
				if gameProcessed then
					return
				end
				for _, name in UIInput.ACTIONS do
					if InputMode.matches(name, input.KeyCode) then
						UIInput.trigger(name :: ActionName)
						return
					end
				end
			end)
		)
	end
	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		if created ~= nil then
			if context == created then
				context = nil
			end
			created:Destroy()
		end
	end
end

return UIInput
