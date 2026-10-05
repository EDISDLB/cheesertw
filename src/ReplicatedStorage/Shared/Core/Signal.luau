--!strict
--[[
	Signal — synchronous, typed event dispatcher (pure Luau, works in Roblox and Lune).

	Purpose:          Decoupled events between modules: `Signal.new<T...>()`, `:Connect`, `:Once`, `:Fire`, `:Wait`.
	Dependencies:     Types/Core (Signal, Connection), Core/Log (handler error reporting).
	State:            Ordered connection list per signal (copy-on-write while firing).
	Validation:       Connect/Once require a function.
	Error handling:   Each handler runs under xpcall; an error is logged (scope "Signal") and the remaining handlers
	                  still run. Fire never throws because of a handler.
	Performance notes: Fire iterates the current array without allocating. Connect/Disconnect during a Fire copy the
	                  array once (copy-on-write) so the in-flight iteration is never disturbed.

	Semantics:
	  * Handlers run synchronously in the firing thread, in connection order (FIFO). Handlers must not yield;
	    spawn a thread yourself if you need to.
	  * A handler disconnected during a Fire (by itself or another handler) is not called afterwards in that Fire.
	  * A handler connected during a Fire is not called until the next Fire.
	  * `:Wait()` suspends the calling coroutine until the next Fire and returns its arguments (Roblox runtime code).
]]

local CoreTypes = require("../Types/Core")
local Log = require("./Log")

export type Signal<T...> = CoreTypes.Signal<T...>
export type Connection = CoreTypes.Connection

local log = Log.scope("Signal")

type SignalImpl = {
	_connections: { ConnectionImpl },
	_firing: number,
}

type ConnectionImpl = {
	Connected: boolean,
	_signal: SignalImpl?,
	_fn: (...any) -> (),
}

local ConnectionClass = {}
ConnectionClass.__index = ConnectionClass

local SignalClass = {}
SignalClass.__index = SignalClass

local function removeConnection(signal: SignalImpl, connection: ConnectionImpl)
	local list = signal._connections
	local index = table.find(list, connection)
	if index == nil then
		return
	end
	if signal._firing > 0 then
		list = table.clone(list)
		signal._connections = list
	end
	table.remove(list, index)
end

function ConnectionClass.Disconnect(self: ConnectionImpl)
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	self._signal = nil
	if signal ~= nil then
		removeConnection(signal, self)
	end
end

ConnectionClass.Destroy = ConnectionClass.Disconnect

local function connect(self: SignalImpl, fn: (...any) -> ()): ConnectionImpl
	local connection: ConnectionImpl = setmetatable({
		Connected = true,
		_signal = self,
		_fn = fn,
	}, ConnectionClass) :: any
	if self._firing > 0 then
		self._connections = table.clone(self._connections)
	end
	table.insert(self._connections, connection)
	return connection
end

function SignalClass.Connect(self: SignalImpl, fn: (...any) -> ()): ConnectionImpl
	if type(fn) ~= "function" then
		error(`Signal:Connect expects a function, got {typeof(fn)}`, 2)
	end
	return connect(self, fn)
end

function SignalClass.Once(self: SignalImpl, fn: (...any) -> ()): ConnectionImpl
	if type(fn) ~= "function" then
		error(`Signal:Once expects a function, got {typeof(fn)}`, 2)
	end
	local connection: ConnectionImpl
	connection = connect(self, function(...)
		ConnectionClass.Disconnect(connection)
		fn(...)
	end)
	return connection
end

local function onHandlerError(err: any): string
	return debug.traceback(tostring(err), 2)
end

function SignalClass.Fire(self: SignalImpl, ...: any)
	local list = self._connections
	self._firing += 1
	for _, connection in list do
		if connection.Connected then
			local ok, err = xpcall(connection._fn :: any, onHandlerError, ...)
			if not ok then
				log:error("handler error: %s", tostring(err))
			end
		end
	end
	self._firing -= 1
end

function SignalClass.Wait(self: SignalImpl): ...any
	local thread = coroutine.running()
	SignalClass.Once(self, function(...)
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			log:error("resumed waiting thread errored: %s", tostring(err))
		end
	end)
	return coroutine.yield()
end

function SignalClass.DisconnectAll(self: SignalImpl)
	local list = self._connections
	self._connections = {}
	for _, connection in list do
		connection.Connected = false
		connection._signal = nil
	end
end

SignalClass.Destroy = SignalClass.DisconnectAll

local Signal = {}

--- Creates a new signal. Annotate the payload: `local changed: Signal.Signal<number> = Signal.new()`.
function Signal.new<T...>(): Signal<T...>
	local self: SignalImpl = setmetatable({
		_connections = {},
		_firing = 0,
	}, SignalClass) :: any
	return (self :: any) :: Signal<T...>
end

--- True if `value` is a Signal created by this module.
function Signal.is(value: unknown): boolean
	return type(value) == "table" and getmetatable(value :: any) == SignalClass
end

return Signal
