--[[
	MockInstance — a pure-Luau stand-in for Roblox Instances used by the Lune test harness.

	Purpose:          Lets Roblox-facing code (NetServer/NetClient, services, bootstraps) run headless: Name/Parent
	                  tree, children lookup, attributes, signals, remotes with loopback "network", bindables.
	                  Injected as the global `Instance` (`Instance.new(className, parent?)`) by the Loader.
	Dependencies:     Core/Signal, task (injected global) for WaitForChild polling.
	State:            Per-instance raw fields (_props, _children, _signals, _attributes, _destroyed).
	Validation:       Parent assignment rejects cycles and destroyed instances (Roblox "Parent property is locked").
	Error handling:   Misuse raises errors with Roblox-like messages; WaitForChild without timeout errors after 5 s
	                  instead of hanging the test run.
	Performance notes: Test-only; linear child scans are fine.

	Network loopback: a RemoteEvent's FireServer(...) fires OnServerEvent(localPlayer, ...) and FireClient /
	FireAllClients fire OnClientEvent(...) in the same VM. Arguments are deep-copied (functions dropped) to mimic
	Roblox serialization. Every send is recorded in `remote._sent` for assertions.
]]

local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

local MockInstance = {}

type ClassDef = {
	supers: { string },
	methods: { [string]: any },
	signals: { string },
	init: ((any) -> ())?,
}

local classes: { [string]: ClassDef } = {}

local localPlayerProvider: () -> any = function()
	return nil
end

--- Registers class-specific behaviour. `supers` lists ancestor class names for IsA (Instance is implicit).
function MockInstance.defineClass(
	name: string,
	def: {
		supers: { string }?,
		methods: { [string]: any }?,
		signals: { string }?,
		init: ((any) -> ())?,
	}
)
	classes[name] = {
		supers = def.supers or {},
		methods = def.methods or {},
		signals = def.signals or {},
		init = def.init,
	}
end

function MockInstance.setLocalPlayerProvider(fn: () -> any)
	localPlayerProvider = fn
end

function MockInstance.getLocalPlayer(): any
	return localPlayerProvider()
end

local InstanceMeta = {}
local BaseMethods: { [string]: any } = {}

local function isMock(value: any): boolean
	return type(value) == "table" and getmetatable(value) == InstanceMeta
end

MockInstance.isMock = isMock

local function classChain(className: string): { string }
	local chain = { className }
	local def = classes[className]
	if def then
		for _, s in def.supers do
			table.insert(chain, s)
		end
	end
	table.insert(chain, "Instance")
	return chain
end

local function getSignal(inst: any, name: string)
	local signals = rawget(inst, "_signals")
	local s = signals[name]
	if s == nil then
		s = Signal.new()
		signals[name] = s
	end
	return s
end

local BASE_SIGNALS = {
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	AttributeChanged = true,
	Destroying = true,
	Changed = true,
	AncestryChanged = true,
}

local function findMethod(inst: any, key: string): any
	local className = rawget(inst, "_class")
	for _, cls in classChain(className) do
		local def = classes[cls]
		if def and def.methods[key] ~= nil then
			return def.methods[key]
		end
	end
	return BaseMethods[key]
end

local function hasClassSignal(inst: any, key: string): boolean
	if BASE_SIGNALS[key] then
		return true
	end
	for _, cls in classChain(rawget(inst, "_class")) do
		local def = classes[cls]
		if def and table.find(def.signals, key) then
			return true
		end
	end
	return false
end

InstanceMeta.__type = "Instance"

function InstanceMeta.__index(inst: any, key: any): any
	local props = rawget(inst, "_props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	if type(key) ~= "string" then
		return nil
	end
	local method = findMethod(inst, key)
	if method ~= nil then
		return method
	end
	if hasClassSignal(inst, key) then
		return getSignal(inst, key)
	end
	for _, child in rawget(inst, "_children") do
		if rawget(child, "_props").Name == key then
			return child
		end
	end
	return nil
end

local function wouldCycle(inst: any, newParent: any): boolean
	local p = newParent
	while p ~= nil do
		if p == inst then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end

local function setParent(inst: any, newParent: any)
	if rawget(inst, "_destroyed") then
		error(
			`The Parent property of {rawget(inst, "_props").Name} is locked, current parent: NULL, new parent {if newParent
				then newParent.Name
				else "NULL"}`,
			3
		)
	end
	if newParent ~= nil and not isMock(newParent) then
		error(`MockInstance: Parent must be a MockInstance or nil, got {typeof(newParent)}`, 3)
	end
	if newParent ~= nil and wouldCycle(inst, newParent) then
		error(
			`Attempt to set parent of {rawget(inst, "_props").Name} to {newParent.Name} would result in circular reference`,
			3
		)
	end
	local old = rawget(inst, "_parent")
	if old == newParent then
		return
	end
	if old ~= nil then
		local siblings = rawget(old, "_children")
		local index = table.find(siblings, inst)
		if index then
			table.remove(siblings, index)
		end
		getSignal(old, "ChildRemoved"):Fire(inst)
	end
	rawset(inst, "_parent", newParent)
	if newParent ~= nil then
		table.insert(rawget(newParent, "_children"), inst)
		getSignal(newParent, "ChildAdded"):Fire(inst)
		local ancestor = newParent
		while ancestor ~= nil do
			getSignal(ancestor, "DescendantAdded"):Fire(inst)
			ancestor = rawget(ancestor, "_parent")
		end
	end
	getSignal(inst, "AncestryChanged"):Fire(inst, newParent)
end

function InstanceMeta.__newindex(inst: any, key: any, value: any)
	if key == "Parent" then
		setParent(inst, value)
		return
	end
	if key == "ClassName" then
		error("ClassName is read-only", 2)
	end
	local props = rawget(inst, "_props")
	if props[key] == value then
		return
	end
	props[key] = value
	getSignal(inst, "Changed"):Fire(key)
	local propSignals = rawget(inst, "_propSignals")
	local s = propSignals[key]
	if s then
		s:Fire()
	end
end

function InstanceMeta.__tostring(inst: any): string
	return rawget(inst, "_props").Name
end

local function newInstance(className: string, parent: any?): any
	assert(type(className) == "string", "Instance.new: className must be a string")
	local inst = setmetatable({
		_class = className,
		_props = { Name = className, ClassName = className },
		_children = {},
		_signals = {},
		_propSignals = {},
		_attributes = {},
		_attributeSignals = {},
		_parent = nil,
		_destroyed = false,
	}, InstanceMeta)
	for _, cls in classChain(className) do
		local def = classes[cls]
		if def and def.init then
			def.init(inst)
		end
	end
	if parent ~= nil then
		setParent(inst, parent)
	end
	return inst
end

MockInstance.new = newInstance

--------------------------------------------------------------------------------
-- Base methods (every class)
--------------------------------------------------------------------------------

function BaseMethods.GetChildren(self: any): { any }
	return table.clone(rawget(self, "_children"))
end

function BaseMethods.GetDescendants(self: any): { any }
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function BaseMethods.FindFirstChild(self: any, name: string, recursive: boolean?): any
	for _, child in rawget(self, "_children") do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in rawget(self, "_children") do
			local found = BaseMethods.FindFirstChild(child, name, true)
			if found then
				return found
			end
		end
	end
	return nil
end

function BaseMethods.FindFirstChildOfClass(self: any, className: string): any
	for _, child in rawget(self, "_children") do
		if rawget(child, "_class") == className then
			return child
		end
	end
	return nil
end

function BaseMethods.FindFirstChildWhichIsA(self: any, className: string): any
	for _, child in rawget(self, "_children") do
		if BaseMethods.IsA(child, className) then
			return child
		end
	end
	return nil
end

function BaseMethods.FindFirstAncestor(self: any, name: string): any
	local p = rawget(self, "_parent")
	while p ~= nil do
		if rawget(p, "_props").Name == name then
			return p
		end
		p = rawget(p, "_parent")
	end
	return nil
end

function BaseMethods.WaitForChild(self: any, name: string, timeout: number?): any
	local found = BaseMethods.FindFirstChild(self, name)
	if found then
		return found
	end
	local limit = timeout or 5
	local started = os.clock()
	while os.clock() - started < limit do
		task.wait(0.005)
		found = BaseMethods.FindFirstChild(self, name)
		if found then
			return found
		end
	end
	if timeout ~= nil then
		return nil
	end
	error(
		`MockInstance: infinite yield on {BaseMethods.GetFullName(self)}:WaitForChild("{name}") (aborted after 5 s)`,
		2
	)
end

function BaseMethods.IsA(self: any, className: string): boolean
	return table.find(classChain(rawget(self, "_class")), className) ~= nil
end

function BaseMethods.IsDescendantOf(self: any, ancestor: any): boolean
	local p = rawget(self, "_parent")
	while p ~= nil do
		if p == ancestor then
			return true
		end
		p = rawget(p, "_parent")
	end
	return false
end

function BaseMethods.GetFullName(self: any): string
	local parts = {}
	local node = self
	while node ~= nil do
		if rawget(node, "_class") == "DataModel" then
			break
		end
		table.insert(parts, 1, rawget(node, "_props").Name)
		node = rawget(node, "_parent")
	end
	return table.concat(parts, ".")
end

function BaseMethods.ClearAllChildren(self: any)
	for _, child in table.clone(rawget(self, "_children")) do
		BaseMethods.Destroy(child)
	end
end

function BaseMethods.Destroy(self: any)
	if rawget(self, "_destroyed") then
		return
	end
	getSignal(self, "Destroying"):Fire()
	for _, child in table.clone(rawget(self, "_children")) do
		BaseMethods.Destroy(child)
	end
	setParent(self, nil)
	rawset(self, "_destroyed", true)
	for _, s in rawget(self, "_signals") do
		s:DisconnectAll()
	end
end

function BaseMethods.Clone(self: any): any
	local copy = newInstance(rawget(self, "_class"))
	for k, v in rawget(self, "_props") do
		if k ~= "ClassName" then
			rawget(copy, "_props")[k] = v
		end
	end
	for k, v in rawget(self, "_attributes") do
		rawget(copy, "_attributes")[k] = v
	end
	for _, child in rawget(self, "_children") do
		setParent(BaseMethods.Clone(child), copy)
	end
	return copy
end

function BaseMethods.SetAttribute(self: any, name: string, value: any)
	local attrs = rawget(self, "_attributes")
	if attrs[name] == value then
		return
	end
	attrs[name] = value
	getSignal(self, "AttributeChanged"):Fire(name)
	local s = rawget(self, "_attributeSignals")[name]
	if s then
		s:Fire()
	end
end

function BaseMethods.GetAttribute(self: any, name: string): any
	return rawget(self, "_attributes")[name]
end

function BaseMethods.GetAttributes(self: any): { [string]: any }
	return table.clone(rawget(self, "_attributes"))
end

function BaseMethods.GetAttributeChangedSignal(self: any, name: string)
	local signals = rawget(self, "_attributeSignals")
	local s = signals[name]
	if s == nil then
		s = Signal.new()
		signals[name] = s
	end
	return s
end

function BaseMethods.GetPropertyChangedSignal(self: any, name: string)
	local signals = rawget(self, "_propSignals")
	local s = signals[name]
	if s == nil then
		s = Signal.new()
		signals[name] = s
	end
	return s
end

--------------------------------------------------------------------------------
-- Remote / bindable classes
--------------------------------------------------------------------------------

-- Mimics Roblox argument serialization: tables are deep-copied, functions/threads become nil.
local function serialize(value: any, seen: { [any]: any }?): any
	local t = type(value)
	if t == "function" or t == "thread" then
		return nil
	end
	if t == "table" and not isMock(value) and getmetatable(value) == nil then
		local memo = seen or {}
		if memo[value] then
			return memo[value]
		end
		local copy = {}
		memo[value] = copy
		for k, v in value do
			copy[serialize(k, memo)] = serialize(v, memo)
		end
		return copy
	end
	if t == "buffer" then
		local copy = buffer.create(buffer.len(value))
		buffer.copy(copy, 0, value)
		return copy
	end
	return value
end

local function serializeArgs(...: any): { n: number, [number]: any }
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = serialize(args[i])
	end
	return args
end

MockInstance.serialize = serialize

local function remoteInit(inst: any)
	rawset(inst, "_sent", {})
end

local function recordSend(inst: any, kind: string, player: any, args: { n: number, [number]: any })
	table.insert(rawget(inst, "_sent"), { kind = kind, player = player, args = args })
end

local remoteEventMethods = {
	FireServer = function(self: any, ...: any)
		local args = serializeArgs(...)
		local player = localPlayerProvider()
		recordSend(self, "FireServer", player, args)
		getSignal(self, "OnServerEvent"):Fire(player, table.unpack(args, 1, args.n))
	end,
	FireClient = function(self: any, player: any, ...: any)
		if player == nil then
			error("FireClient: player argument must be a Player", 2)
		end
		local args = serializeArgs(...)
		recordSend(self, "FireClient", player, args)
		if player == localPlayerProvider() then
			getSignal(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
		end
	end,
	FireAllClients = function(self: any, ...: any)
		local args = serializeArgs(...)
		recordSend(self, "FireAllClients", nil, args)
		getSignal(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
	end,
	-- Test helper: deliver a client->server event as `player` (simulates another client).
	_simulateFireServer = function(self: any, player: any, ...: any)
		local args = serializeArgs(...)
		recordSend(self, "FireServer", player, args)
		getSignal(self, "OnServerEvent"):Fire(player, table.unpack(args, 1, args.n))
	end,
	_clearSent = function(self: any)
		table.clear(rawget(self, "_sent"))
	end,
}

MockInstance.defineClass("BaseRemoteEvent", {})

MockInstance.defineClass("RemoteEvent", {
	supers = { "BaseRemoteEvent" },
	methods = remoteEventMethods,
	signals = { "OnServerEvent", "OnClientEvent" },
	init = remoteInit,
})

MockInstance.defineClass("UnreliableRemoteEvent", {
	supers = { "BaseRemoteEvent" },
	methods = remoteEventMethods,
	signals = { "OnServerEvent", "OnClientEvent" },
	init = remoteInit,
})

MockInstance.defineClass("RemoteFunction", {
	init = remoteInit,
	methods = {
		InvokeServer = function(self: any, ...: any): ...any
			local callback = rawget(self, "_props").OnServerInvoke
			if callback == nil then
				error(`RemoteFunction {self.Name}: OnServerInvoke is not set (mock would yield forever)`, 2)
			end
			local args = serializeArgs(...)
			local player = localPlayerProvider()
			recordSend(self, "InvokeServer", player, args)
			local results = table.pack(callback(player, table.unpack(args, 1, args.n)))
			for i = 1, results.n do
				results[i] = serialize(results[i])
			end
			return table.unpack(results, 1, results.n)
		end,
		_simulateInvokeServer = function(self: any, player: any, ...: any): ...any
			local callback = rawget(self, "_props").OnServerInvoke
			if callback == nil then
				error(`RemoteFunction {self.Name}: OnServerInvoke is not set`, 2)
			end
			local args = serializeArgs(...)
			recordSend(self, "InvokeServer", player, args)
			local results = table.pack(callback(player, table.unpack(args, 1, args.n)))
			for i = 1, results.n do
				results[i] = serialize(results[i])
			end
			return table.unpack(results, 1, results.n)
		end,
	},
})

MockInstance.defineClass("BindableEvent", {
	signals = { "Event" },
	methods = {
		Fire = function(self: any, ...: any)
			getSignal(self, "Event"):Fire(...)
		end,
	},
})

MockInstance.defineClass("BindableFunction", {
	methods = {
		Invoke = function(self: any, ...: any): ...any
			local callback = rawget(self, "_props").OnInvoke
			if callback == nil then
				error("BindableFunction: OnInvoke is not set", 2)
			end
			return callback(...)
		end,
	},
})

MockInstance.defineClass("DataStoreSetOptions", {
	init = function(inst: any)
		rawset(inst, "_metadata", {})
	end,
	methods = {
		SetMetadata = function(self: any, metadata: { [string]: any })
			rawset(self, "_metadata", table.clone(metadata))
		end,
		GetMetadata = function(self: any): { [string]: any }
			return table.clone(rawget(self, "_metadata"))
		end,
	},
})

MockInstance.defineClass("TeleportOptions", {
	methods = {
		SetTeleportData = function(self: any, data: any)
			rawset(self, "_teleportData", data)
		end,
		GetTeleportData = function(self: any): any
			return rawget(self, "_teleportData")
		end,
	},
})

MockInstance.defineClass("ModuleScript", { supers = { "LuaSourceContainer" } })
MockInstance.defineClass("Script", { supers = { "BaseScript", "LuaSourceContainer" } })
MockInstance.defineClass("LocalScript", { supers = { "Script", "BaseScript", "LuaSourceContainer" } })
for _, gui in { "Frame", "TextLabel", "TextButton", "ImageLabel", "ImageButton", "ScrollingFrame", "TextBox" } do
	MockInstance.defineClass(gui, { supers = { "GuiObject", "GuiBase2d", "GuiBase" } })
end
MockInstance.defineClass("ScreenGui", { supers = { "LayerCollector", "GuiBase2d", "GuiBase" } })
for _, part in { "Part", "WedgePart", "MeshPart", "TrussPart" } do
	MockInstance.defineClass(part, { supers = { "BasePart", "PVInstance" } })
end
MockInstance.defineClass("Model", { supers = { "PVInstance" } })
MockInstance.defineClass("Workspace", { supers = { "WorldRoot", "Model", "PVInstance" } })

--- The table injected as the global `Instance` in tests.
MockInstance.InstanceApi = {
	new = newInstance,
	fromExisting = function(existing: any): any
		return BaseMethods.Clone(existing)
	end,
}

return MockInstance
