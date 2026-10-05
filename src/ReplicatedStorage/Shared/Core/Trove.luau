--!strict
--[[
	Trove — cleanup bag for connections, instances, threads, functions and destroyable objects.

	Purpose:          Tie the lifetime of many resources to one owner: `trove:Add(x)` ... `trove:Clean()`.
	Dependencies:     Types/Core (Connection), Core/Log (cleanup error reporting); task.cancel for threads (Roblox and
	                  the Lune harness both provide it).
	State:            Ordered list of (object, cleanup method) entries; destroyed flag.
	Validation:       Add rejects values it cannot clean, unknown cleanup method names and the trove itself immediately.
	Error handling:   A failing cleanup is logged and the remaining entries are still cleaned.
	Performance notes: Clean is LIFO and O(n); Remove is O(n).

	Cleanup kinds (auto-detected unless `cleanupMethod` is given):
	  function -> called;  thread -> task.cancel (if not dead/running);  Instance -> :Destroy();
	  RBXScriptConnection / Signal Connection -> :Disconnect();  table with Destroy -> :Destroy();
	  table with Disconnect -> :Disconnect();  Trove -> :Destroy().
	  An explicit `cleanupMethod` works for tables, Instances and other userdata (e.g. RBXScriptConnection, which is
	  what `trove:Connect(rbxSignal, fn)` tracks); if tracking fails, Connect disconnects before rethrowing.
	After trove:Destroy(), anything added is cleaned immediately (guards async setup racing teardown).
]]

local CoreTypes = require("../Types/Core")
local Log = require("./Log")

type Connection = CoreTypes.Connection

local log = Log.scope("Trove")

local FN_MARKER = "__function"
local THREAD_MARKER = "__thread"

type Entry = { object: any, method: string }

local TroveClass = {}
TroveClass.__index = TroveClass

export type Trove = typeof(setmetatable(
	{} :: { _entries: { Entry }, _cleaning: boolean, _destroyed: boolean },
	TroveClass
))

local function detectMethod(object: any, explicit: string?): string
	if explicit ~= nil then
		-- Tables, Instances and other userdata (RBXScriptConnection, ...) can carry methods. Roblox userdata throw
		-- when indexed with an unknown member, so the lookup is pcall'd.
		local kind = type(object)
		if kind ~= "table" and kind ~= "userdata" then
			error(`Trove:Add cleanup method "{explicit}" given for a {typeof(object)}`, 3)
		end
		local ok, member = pcall(function()
			return (object :: any)[explicit]
		end)
		if not ok or type(member) ~= "function" then
			error(`Trove:Add {typeof(object)} has no method "{explicit}"`, 3)
		end
		return explicit
	end
	local t = typeof(object)
	if t == "function" then
		return FN_MARKER
	elseif t == "thread" then
		return THREAD_MARKER
	elseif t == "Instance" then
		return "Destroy"
	elseif t == "RBXScriptConnection" then
		return "Disconnect"
	elseif t == "table" then
		if type(object.Destroy) == "function" then
			return "Destroy"
		elseif type(object.Disconnect) == "function" then
			return "Disconnect"
		end
	end
	error(`Trove:Add cannot clean a {t} (pass a cleanup method name)`, 3)
end

local function cleanEntry(entry: Entry)
	local object, method = entry.object, entry.method
	if method == FN_MARKER then
		object()
	elseif method == THREAD_MARKER then
		local status = coroutine.status(object)
		if status ~= "dead" and object ~= coroutine.running() then
			task.cancel(object)
		end
	else
		object[method](object)
	end
end

--- Adds `object` and returns it (so `local part = trove:Add(Instance.new("Part"))` works).
function TroveClass.Add<T>(self: Trove, object: T, cleanupMethod: string?): T
	if object == nil then
		error("Trove:Add object is nil", 2)
	end
	if rawequal(object, self) then
		error("Trove:Add cannot add a trove to itself", 2)
	end
	local method = detectMethod(object, cleanupMethod)
	local entry = { object = object, method = method }
	if self._destroyed then
		local ok, err = pcall(cleanEntry :: any, entry)
		if not ok then
			log:error("cleanup after destroy failed: %s", tostring(err))
		end
		return object
	end
	table.insert(self._entries, entry)
	return object
end

--- Connects `fn` to a Signal or RBXScriptSignal and tracks the connection.
function TroveClass.Connect(self: Trove, signal: any, fn: (...any) -> ()): Connection
	local connection = signal:Connect(fn)
	local ok, err = pcall(TroveClass.Add, self, connection, "Disconnect")
	if not ok then
		-- Never leak a live connection because it could not be tracked.
		pcall(function()
			connection:Disconnect()
		end)
		error(err, 0)
	end
	return connection
end

--- Creates a child trove that is cleaned when this trove is cleaned.
function TroveClass.Extend(self: Trove): Trove
	local child = (setmetatable({ _entries = {}, _cleaning = false, _destroyed = false }, TroveClass) :: any) :: Trove
	TroveClass.Add(self, child, "Destroy")
	return child
end

--- Removes `object` from the trove AND cleans it. Returns false if it was not tracked.
function TroveClass.Remove(self: Trove, object: any): boolean
	local entries = self._entries
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if entry.object == object then
			table.remove(entries, i)
			local ok, err = pcall(cleanEntry :: any, entry)
			if not ok then
				log:error("cleanup failed: %s", tostring(err))
			end
			return true
		end
	end
	return false
end

--- Cleans everything (last added first). The trove stays usable.
function TroveClass.Clean(self: Trove)
	if self._cleaning then
		return
	end
	self._cleaning = true
	local entries = self._entries
	while #entries > 0 do
		local entry = table.remove(entries) :: Entry
		local ok, err = pcall(cleanEntry :: any, entry)
		if not ok then
			log:error("cleanup failed: %s", tostring(err))
		end
	end
	self._cleaning = false
end

--- Cleans everything and marks the trove destroyed (later Adds are cleaned immediately).
function TroveClass.Destroy(self: Trove)
	TroveClass.Clean(self)
	self._destroyed = true
end

local Trove = {}

function Trove.new(): Trove
	return (setmetatable({ _entries = {}, _cleaning = false, _destroyed = false }, TroveClass) :: any) :: Trove
end

return Trove
