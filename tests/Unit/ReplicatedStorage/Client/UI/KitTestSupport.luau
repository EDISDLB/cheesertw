--[[
	KitTestSupport — shared fixtures for UI kit specs (test-only; not part of the harness).

	Purpose:          Extends MockInstance (from the test side, via MockInstance.defineClass) with the GUI events and
	                  methods the kit uses (GuiObject/GuiButton signals, Instance tags, TextBox, InputAction), and
	                  installs fake TweenService / UserInputService / GuiService / Camera / PlayerGui through
	                  `game:setService`. Optional API-dump validation checks that every property the kit assigns
	                  exists on the real Roblox class, is writable and has a compatible type.
	Dependencies:     Harness MockInstance, Core/Signal, @lune/fs/serde/process (API dump, optional).
	State:            Per spec file (fresh module cache): the installed fakes.
	Validation:       validateTree raises listing every invalid property assignment it finds.
	Error handling:   Missing API dump => validation is skipped (reported by `Support.hasApiDump()`).
	Performance notes: Test-only.
]]

local MockInstance = require("@tests/Harness/Mocks/MockInstance")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")

local Support = {}

local GUI_OBJECT_SIGNALS = {
	"InputBegan",
	"InputEnded",
	"InputChanged",
	"MouseEnter",
	"MouseLeave",
	"MouseMoved",
	"MouseWheelForward",
	"MouseWheelBackward",
	"SelectionGained",
	"SelectionLost",
	"TouchLongPress",
	"TouchTap",
	"TouchPan",
	"TouchSwipe",
	"TouchPinch",
	"TouchRotate",
}

local GUI_BUTTON_SIGNALS = {
	"Activated",
	"MouseButton1Click",
	"MouseButton1Down",
	"MouseButton1Up",
	"MouseButton2Click",
	"MouseButton2Down",
	"MouseButton2Up",
	"SecondaryActivated",
}

local GUI_DEFAULTS: { [string]: any } = {
	Visible = true,
	Active = false,
	Interactable = true,
	Selectable = false,
	SelectionOrder = 0,
	ZIndex = 1,
	LayoutOrder = 0,
	Rotation = 0,
	BackgroundTransparency = 0,
	AbsolutePosition = nil,
	AbsoluteSize = nil,
}

local function setDefaults(inst: any, defaults: { [string]: any })
	local props = rawget(inst, "_props")
	for key, value in defaults do
		if props[key] == nil then
			props[key] = value
		end
	end
end

local function guiInit(inst: any)
	setDefaults(inst, GUI_DEFAULTS)
	local props = rawget(inst, "_props")
	props.AbsolutePosition = Vector2.new(0, 0)
	props.AbsoluteSize = Vector2.new(100, 40)
	props.Size = UDim2.fromOffset(100, 40)
	props.Position = UDim2.new()
	props.AnchorPoint = Vector2.new(0, 0)
end

local function buttonInit(inst: any)
	guiInit(inst)
	rawget(inst, "_props").Selectable = true
	rawget(inst, "_props").Active = true
end

local installed = false

--- Defines the mock GUI classes (idempotent per spec file).
function Support.defineClasses()
	if installed then
		return
	end
	installed = true
	-- Harness gap: MockInstance stores the parent in a raw field and does not expose `.Parent` reads. Patch the shared
	-- metatable (this spec file's module instance only) so Roblox-style `inst.Parent` reads work.
	local meta = getmetatable(MockInstance.new("Folder"))
	local originalIndex = meta.__index
	if rawget(meta, "_kitParentPatch") == nil then
		rawset(meta, "_kitParentPatch", true)
		meta.__index = function(inst: any, key: any): any
			if key == "Parent" then
				return rawget(inst, "_parent")
			end
			return originalIndex(inst, key)
		end
	end
	MockInstance.defineClass("Instance", {
		-- Records which properties code actually wrote (defaults set by mocks are not writes).
		init = function(inst: any)
			local written = {}
			rawset(inst, "_written", written)
			inst.Changed:Connect(function(key: string)
				written[key] = true
			end)
		end,
		methods = {
			AddTag = function(self: any, tag: string)
				local tags = rawget(self, "_tags") or {}
				rawset(self, "_tags", tags)
				tags[tag] = true
			end,
			RemoveTag = function(self: any, tag: string)
				local tags = rawget(self, "_tags")
				if tags then
					tags[tag] = nil
				end
			end,
			HasTag = function(self: any, tag: string): boolean
				local tags = rawget(self, "_tags")
				return tags ~= nil and tags[tag] == true
			end,
			-- Harness gap: MockInstance has no ancestor-by-class queries.
			FindFirstAncestorWhichIsA = function(self: any, className: string): any
				local node = rawget(self, "_parent")
				while node ~= nil do
					if node:IsA(className) then
						return node
					end
					node = rawget(node, "_parent")
				end
				return nil
			end,
			FindFirstAncestorOfClass = function(self: any, className: string): any
				local node = rawget(self, "_parent")
				while node ~= nil do
					if node.ClassName == className then
						return node
					end
					node = rawget(node, "_parent")
				end
				return nil
			end,
			GetTags = function(self: any): { string }
				local out = {}
				for tag in rawget(self, "_tags") or {} do
					table.insert(out, tag)
				end
				table.sort(out)
				return out
			end,
		},
	})
	MockInstance.defineClass("GuiBase2d", { supers = { "GuiBase" }, signals = { "SelectionChanged" } })
	MockInstance.defineClass("GuiObject", { supers = { "GuiBase2d", "GuiBase" }, signals = GUI_OBJECT_SIGNALS })
	MockInstance.defineClass(
		"GuiButton",
		{ supers = { "GuiObject", "GuiBase2d", "GuiBase" }, signals = GUI_BUTTON_SIGNALS }
	)
	for _, name in
		{ "Frame", "TextLabel", "ImageLabel", "ScrollingFrame", "CanvasGroup", "ViewportFrame", "VideoFrame" }
	do
		MockInstance.defineClass(name, { supers = { "GuiObject", "GuiBase2d", "GuiBase" }, init = guiInit })
	end
	for _, name in { "TextButton", "ImageButton" } do
		MockInstance.defineClass(
			name,
			{ supers = { "GuiButton", "GuiObject", "GuiBase2d", "GuiBase" }, init = buttonInit }
		)
	end
	MockInstance.defineClass("TextBox", {
		supers = { "GuiObject", "GuiBase2d", "GuiBase" },
		signals = { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" },
		init = function(inst: any)
			buttonInit(inst)
		end,
		methods = {
			CaptureFocus = function(self: any)
				rawset(self, "_focused", true)
			end,
			ReleaseFocus = function(self: any)
				rawset(self, "_focused", false)
			end,
			IsFocused = function(self: any): boolean
				return rawget(self, "_focused") == true
			end,
		},
	})
	MockInstance.defineClass("ScreenGui", {
		supers = { "LayerCollector", "GuiBase2d", "GuiBase" },
		init = function(inst: any)
			setDefaults(inst, { Enabled = true, DisplayOrder = 0 })
			rawget(inst, "_props").AbsoluteSize = Vector2.new(1920, 1080)
			rawget(inst, "_props").AbsolutePosition = Vector2.new(0, 0)
		end,
	})
	MockInstance.defineClass("InputAction", {
		signals = { "Pressed", "Released", "StateChanged" },
		methods = {
			GetState = function(self: any): any
				return rawget(self, "_state") or false
			end,
			Fire = function(self: any, state: any)
				rawset(self, "_state", state)
				if state == true then
					self.Pressed:Fire()
				elseif state == false then
					self.Released:Fire()
				end
				self.StateChanged:Fire(state)
			end,
		},
	})
	MockInstance.defineClass("Camera", {})
	MockInstance.defineClass("PlayerGui", { supers = { "BasePlayerGui" } })
	MockInstance.defineClass("UserInputService", {
		signals = {
			"InputBegan",
			"InputEnded",
			"InputChanged",
			"LastInputTypeChanged",
			"GamepadConnected",
			"GamepadDisconnected",
			"TouchStarted",
			"TouchEnded",
			"TouchMoved",
			"TouchLongPress",
			"TouchTap",
		},
		methods = {
			GetLastInputType = function(self: any): any
				return rawget(self, "_lastInputType") or Enum.UserInputType.MouseMovement
			end,
			GetStringForKeyCode = function(_self: any, keyCode: any, _format: any): string
				local playstation = rawget(_self, "_playstation")
				if playstation then
					local map = {
						ButtonA = "ButtonCross",
						ButtonB = "ButtonCircle",
						ButtonX = "ButtonSquare",
						ButtonY = "ButtonTriangle",
					}
					return map[keyCode.Name] or keyCode.Name
				end
				-- Xbox names per the UserInputService reference table.
				local xbox = {
					ButtonL1 = "ButtonLB",
					ButtonR1 = "ButtonRB",
					ButtonL2 = "ButtonLT",
					ButtonR2 = "ButtonRT",
					ButtonL3 = "ButtonLS",
					ButtonR3 = "ButtonRS",
				}
				return xbox[keyCode.Name] or keyCode.Name
			end,
			GetImageForKeyCode = function(_self: any, keyCode: any): string
				return "rbxasset://fake/" .. keyCode.Name .. ".png"
			end,
			GetFocusedTextBox = function(self: any): any
				return rawget(self, "_focusedTextBox")
			end,
			GetMouseLocation = function(self: any): Vector2
				return rawget(self, "_mouse") or Vector2.new(0, 0)
			end,
			IsKeyDown = function(_self: any, _keyCode: any): boolean
				return false
			end,
		},
	})
	MockInstance.defineClass("GuiService", {
		signals = { "MenuOpened", "MenuClosed" },
		methods = {
			Select = function(self: any, parent: any)
				local best, bestOrder = nil, math.huge
				local function visible(node: any): boolean
					local p = node
					while p ~= nil and p ~= parent do
						if p.Visible == false or p.Enabled == false then
							return false
						end
						p = p.Parent
					end
					return true
				end
				for _, d in parent:GetDescendants() do
					if d.Selectable == true and visible(d) then
						local order = d.SelectionOrder or 0
						if order < bestOrder then
							best, bestOrder = d, order
						end
					end
				end
				if best ~= nil then
					self.SelectedObject = best
				end
			end,
			IsTenFootInterface = function(self: any): boolean
				return rawget(self, "_tenFoot") == true
			end,
			GetGuiInset = function(_self: any): (Vector2, Vector2)
				return Vector2.new(0, 58), Vector2.new(0, 0)
			end,
		},
	})
	MockInstance.defineClass("TweenService", {
		methods = {
			Create = function(self: any, instance: any, info: any, props: any): any
				local env = rawget(self, "_env")
				local tween = {
					Instance = instance,
					TweenInfo = info,
					Props = props,
					PlaybackState = Enum.PlaybackState.Begin,
					Completed = Signal.new(),
					_played = false,
				}
				function tween.Play(t: any)
					t._played = true
					t.PlaybackState = Enum.PlaybackState.Playing
					if env.deferTweens then
						table.insert(env.pendingTweens, t)
						return
					end
					t:_finish()
				end
				function tween._finish(t: any)
					if t.PlaybackState ~= Enum.PlaybackState.Playing then
						return
					end
					for key, value in t.Props do
						t.Instance[key] = value
					end
					t.PlaybackState = Enum.PlaybackState.Completed
					t.Completed:Fire(Enum.PlaybackState.Completed)
				end
				function tween.Cancel(t: any)
					if t.PlaybackState == Enum.PlaybackState.Playing then
						t.PlaybackState = Enum.PlaybackState.Cancelled
						t.Completed:Fire(Enum.PlaybackState.Cancelled)
					end
				end
				function tween.Pause(t: any)
					t.PlaybackState = Enum.PlaybackState.Paused
				end
				function tween.Destroy(t: any)
					t.Completed:DisconnectAll()
				end
				table.insert(env.tweens, tween)
				return tween
			end,
		},
	})
end

export type Env = {
	tweenService: any,
	userInputService: any,
	guiService: any,
	runService: any,
	players: any,
	player: any,
	playerGui: any,
	camera: any,
	tweens: { any },
	pendingTweens: { any },
	deferTweens: boolean,
	completeTweens: (self: Env) -> (),
	step: (self: Env, dt: number?) -> (),
	setPreferredInput: (self: Env, input: any) -> (),
	setViewport: (self: Env, size: Vector2) -> (),
}

--- Installs mock classes and fake services into the current spec's MockGame. Returns handles for driving them.
function Support.install(options: { viewport: Vector2?, preferredInput: any? }?): Env
	Support.defineClasses()
	local opts = options or {}
	local env: any = { tweens = {}, pendingTweens = {}, deferTweens = false }

	local tweenService = MockInstance.new("TweenService")
	tweenService.Name = "TweenService"
	rawset(tweenService, "_env", env)
	game:setService("TweenService", tweenService)

	local uis = MockInstance.new("UserInputService")
	uis.Name = "UserInputService"
	rawset(uis, "_props", rawget(uis, "_props"))
	local uisProps = rawget(uis, "_props")
	uisProps.PreferredInput = opts.preferredInput or Enum.PreferredInput.KeyboardAndMouse
	uisProps.TouchEnabled = false
	uisProps.KeyboardEnabled = true
	uisProps.MouseEnabled = true
	uisProps.GamepadEnabled = false
	game:setService("UserInputService", uis)

	local guiService = MockInstance.new("GuiService")
	guiService.Name = "GuiService"
	local guiProps = rawget(guiService, "_props")
	guiProps.AutoSelectGuiEnabled = true
	guiProps.GuiNavigationEnabled = true
	guiProps.ReducedMotionEnabled = false
	guiProps.PreferredTransparency = 1
	guiProps.PreferredTextSize = Enum.PreferredTextSize.Medium
	guiProps.ViewportDisplaySize = Enum.DisplaySize.Medium
	game:setService("GuiService", guiService)

	local runService = game:GetService("RunService")
	runService:setClient(true)
	runService:setServer(false)

	local players = game:GetService("Players")
	local player = players.LocalPlayer
	if player == nil then
		player = players:addPlayer({ UserId = 1, Name = "Tester" })
		players:setLocalPlayer(player)
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		playerGui = MockInstance.new("PlayerGui")
		playerGui.Name = "PlayerGui"
		playerGui.Parent = player
	end

	local camera = MockInstance.new("Camera")
	camera.Name = "Camera"
	rawget(camera, "_props").ViewportSize = opts.viewport or Vector2.new(1920, 1080)
	camera.Parent = workspace
	workspace.CurrentCamera = camera

	env.tweenService = tweenService
	env.userInputService = uis
	env.guiService = guiService
	env.runService = runService
	env.players = players
	env.player = player
	env.playerGui = playerGui
	env.camera = camera
	function env.completeTweens(self: any)
		local pending = self.pendingTweens
		self.pendingTweens = {}
		for _, tween in pending do
			tween:_finish()
		end
	end
	function env.step(self: any, dt: number?)
		self.runService:step(dt or 1 / 60)
	end
	function env.setPreferredInput(self: any, input: any)
		self.userInputService.PreferredInput = input
	end
	function env.setViewport(self: any, size: Vector2)
		self.camera.ViewportSize = size
	end
	return env :: Env
end

--------------------------------------------------------------------------------
-- Tree helpers
--------------------------------------------------------------------------------

function Support.find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	return root:FindFirstChild(name, true)
end

function Support.descendants(root: any, className: string?): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if className == nil or d.ClassName == className then
			table.insert(out, d)
		end
	end
	return out
end

--- Fires a mock event on an instance (`Support.fire(button, "Activated")`).
function Support.fire(inst: any, eventName: string, ...: any)
	local signal = inst[eventName]
	assert(signal ~= nil, `mock {inst.ClassName} has no event {eventName}`)
	signal:Fire(...)
end

function Support.click(button: any)
	Support.fire(button, "MouseButton1Click")
	Support.fire(button, "Activated", nil, 1)
end

--- Moves gamepad selection: updates GuiService.SelectedObject and fires SelectionLost/SelectionGained.
function Support.select(guiService: any, target: any)
	local previous = guiService.SelectedObject
	if previous == target then
		return
	end
	guiService.SelectedObject = target
	if previous ~= nil and previous.SelectionLost then
		previous.SelectionLost:Fire()
	end
	if target ~= nil and target.SelectionGained then
		target.SelectionGained:Fire()
	end
end

--- Fake InputObject for InputBegan/InputEnded handlers.
function Support.input(props: { [string]: any }): any
	return {
		KeyCode = props.KeyCode or Enum.KeyCode.Unknown,
		UserInputType = props.UserInputType or Enum.UserInputType.Keyboard,
		UserInputState = props.UserInputState or Enum.UserInputState.Begin,
		Position = props.Position or Vector3.new(0, 0, 0),
		Delta = props.Delta or Vector3.new(0, 0, 0),
	}
end

--------------------------------------------------------------------------------
-- API dump validation
--------------------------------------------------------------------------------

type Member = { name: string, valueType: { Category: string, Name: string }?, readOnly: boolean }
local apiClasses: { [string]: { superclass: string?, members: { [string]: Member } } }? = nil
local apiLoaded = false

local function apiDumpPath(): string?
	local explicit = process.env.HULLDOWN_API_DUMP
	if explicit and fs.isFile(explicit) then
		return explicit
	end
	local tools = process.env.HULLDOWN_TOOLS
	if tools then
		local candidate = tools .. "/API-Dump.json"
		if fs.isFile(candidate) then
			return candidate
		end
	end
	return nil
end

local function loadApi()
	if apiLoaded then
		return
	end
	apiLoaded = true
	local path = apiDumpPath()
	if path == nil then
		return
	end
	local dump = serde.decode("json", fs.readFile(path))
	local classes = {}
	for _, class in dump.Classes do
		local members = {}
		for _, member in class.Members do
			if member.MemberType == "Property" then
				local tags = member.Tags or {}
				local readOnly = table.find(tags, "ReadOnly") ~= nil or table.find(tags, "NotScriptable") ~= nil
				local security = member.Security
				if type(security) == "table" and security.Write ~= "None" then
					readOnly = true
				end
				members[member.Name] = { name = member.Name, valueType = member.ValueType, readOnly = readOnly }
			end
		end
		classes[class.Name] = {
			superclass = if class.Superclass ~= "<<<ROOT>>>" then class.Superclass else nil,
			members = members,
		}
	end
	apiClasses = classes
end

function Support.hasApiDump(): boolean
	loadApi()
	return apiClasses ~= nil
end

local function findMember(className: string, prop: string): Member?
	local classes = apiClasses :: any
	local current: string? = className
	while current ~= nil do
		local class = classes[current]
		if class == nil then
			return nil
		end
		local member = class.members[prop]
		if member then
			return member
		end
		current = class.superclass
	end
	return nil
end

local PRIMITIVE_TYPES: { [string]: string } = {
	bool = "boolean",
	float = "number",
	double = "number",
	int = "number",
	int64 = "number",
	string = "string",
}

local function typeProblem(member: Member, value: any): string?
	local valueType = member.valueType
	if valueType == nil or value == nil then
		return nil
	end
	local category, name = valueType.Category, valueType.Name
	if category == "Primitive" then
		local expected = PRIMITIVE_TYPES[name]
		if expected and type(value) ~= expected then
			return `expected {name}, got {typeof(value)}`
		end
	elseif category == "Enum" then
		local enumName = if typeof(value) == "EnumItem"
			then string.gsub(tostring(value.EnumType), "^Enum%.", "")
			else nil
		if enumName ~= name then
			return `expected Enum.{name}, got {typeof(value)} {tostring(value)}`
		end
	elseif category == "DataType" then
		if name == "Content" or name == "ContentId" then
			if type(value) ~= "string" and typeof(value) ~= "Content" then
				return `expected {name}, got {typeof(value)}`
			end
		elseif typeof(value) ~= name then
			return `expected {name}, got {typeof(value)}`
		end
	elseif category == "Class" then
		if typeof(value) ~= "Instance" then
			return `expected {name} instance, got {typeof(value)}`
		end
	end
	return nil
end

local SKIP_PROPS = { Name = true, ClassName = true, Parent = true }

--- Checks every property assigned on `root` and its descendants against the Roblox API dump (class membership,
--- writability, value type). Skipped (returns false) when no dump is available; raises on problems.
function Support.validateTree(root: any, ignoreClasses: { [string]: boolean }?): boolean
	loadApi()
	if apiClasses == nil then
		return false
	end
	local problems = {}
	local nodes = { root }
	for _, d in root:GetDescendants() do
		table.insert(nodes, d)
	end
	for _, node in nodes do
		local className = rawget(node, "_class")
		if (ignoreClasses and ignoreClasses[className]) or (apiClasses :: any)[className] == nil then
			continue
		end
		local written = rawget(node, "_written") or {}
		for key, value in rawget(node, "_props") do
			if type(key) == "string" and not SKIP_PROPS[key] then
				local member = findMember(className, key)
				if member == nil then
					table.insert(problems, `{node:GetFullName()} ({className}).{key}: not a property`)
				else
					local problem = typeProblem(member, value)
					if problem then
						table.insert(problems, `{node:GetFullName()} ({className}).{key}: {problem}`)
					elseif written[key] and member.readOnly then
						table.insert(problems, `{node:GetFullName()} ({className}).{key}: read-only property written`)
					end
				end
			end
		end
	end
	if #problems > 0 then
		error("API validation failed:\n  " .. table.concat(problems, "\n  "), 0)
	end
	return true
end

--- Records property writes made after this call so validateTree can flag writes to read-only properties.
function Support.assertWritable(inst: any, props: { string })
	loadApi()
	if apiClasses == nil then
		return
	end
	for _, prop in props do
		local member = findMember(inst.ClassName, prop)
		assert(member ~= nil, `{inst.ClassName}.{prop} is not a property`)
		assert(not (member :: Member).readOnly, `{inst.ClassName}.{prop} is read-only`)
	end
end

return Support
