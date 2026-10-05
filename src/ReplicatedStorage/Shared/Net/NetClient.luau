--!strict
--[[
	NetClient — client side of the remote layer (ARCHITECTURE §5.2). CLIENT ONLY.

	Purpose:          Waits for ReplicatedStorage.Remotes (warning while it waits) and exposes registry-checked
	                  helpers: fire (C2S events), on (S2C events, non-yielding), invoke (C2S functions with timeout,
	                  returning a Result).
	Dependencies:     Net/Remotes, Net/Protocol, Net/ErrorCodes, Core/Result, Core/Signal, Core/Log, Core/Clock,
	                  Types/Net. Roblox: RunService/ReplicatedStorage (call-time only), task (injectable).
	State:            Resolved remote instances, one Signal per S2C remote (handlers attach before the remote exists).
	Validation:       Names must be registered and used with the right direction/kind; outgoing arguments are
	                  validated locally with the registry validators (bugs surface on the client, not as strikes).
	Error handling:   invoke never throws: transport errors -> Err(INTERNAL), malformed responses -> Err(INTERNAL),
	                  timeouts -> Err(TIMEOUT), missing remote -> Err(NOT_FOUND), bad arguments -> Err(INVALID_ARGS).
	Performance notes: fire() is a table lookup + FireServer. invoke() spawns one thread and one timer.

	Client-only guard: NetClient.new() checks RunService:IsClient() when called.
	invoke() yields: call it from a yieldable thread (scripts, task.spawn'd functions), never from Init.
]]

local CoreTypes = require("../Types/Core")
local NetTypes = require("../Types/Net")
local Remotes = require("./Remotes")
local Protocol = require("./Protocol")
local ErrorCodes = require("./ErrorCodes")
local Result = require("../Core/Result")
local Signal = require("../Core/Signal")
local Log = require("../Core/Log")
local Clock = require("../Core/Clock")

type Clock = CoreTypes.Clock
type Logger = CoreTypes.Logger
type Connection = CoreTypes.Connection
type RemoteSpec = NetTypes.RemoteSpec
export type NetClient = NetTypes.NetClient

type SpawnFn = (threadOrFn: any, ...any) -> thread
type DelayFn = (seconds: number, fn: () -> ()) -> thread
type CancelFn = (thread: thread) -> ()

export type NetClientOptions = {
	registry: { RemoteSpec }?,
	container: Instance?,
	runService: RunService?,
	clock: Clock?,
	log: Logger?,
	--- Default invoke timeout in seconds (Protocol.INVOKE_TIMEOUT).
	invokeTimeout: number?,
	--- Seconds between "still waiting" warnings (default 5).
	warnInterval: number?,
	--- Validate outgoing arguments locally (default true).
	validateArgs: boolean?,
	spawn: SpawnFn?,
	delay: DelayFn?,
	cancel: CancelFn?,
}

type NetClientImpl = {
	_specs: { [string]: RemoteSpec },
	_container: Instance,
	_folder: Instance?,
	_remotes: { [string]: Instance? },
	_events: { [string]: CoreTypes.Signal<...any> },
	_cleanups: { () -> () },
	_clock: Clock,
	_log: Logger,
	_invokeTimeout: number,
	_warnInterval: number,
	_validateArgs: boolean,
	_spawn: SpawnFn,
	_delay: DelayFn,
	_cancel: CancelFn,
	_destroyed: boolean,
}

local NetClientClass = {}
NetClientClass.__index = NetClientClass

local function specFor(self: NetClientImpl, name: string, method: string): RemoteSpec
	local spec = self._specs[name]
	if spec == nil then
		error(`NetClient:{method}: unknown remote "{tostring(name)}" (add it to Net/Remotes)`, 3)
	end
	return spec
end

local function validateOutgoing(self: NetClientImpl, spec: RemoteSpec, ...: any): string?
	if not self._validateArgs then
		return nil
	end
	local validators: { CoreTypes.Validator } = spec.args or {}
	local count = select("#", ...)
	if count > #validators then
		return `expected at most {#validators} arguments, got {count}`
	end
	for i, validator in validators do
		local called, ok, err = pcall(validator, (select(i, ...)))
		if not called then
			return `arg{i}: validator error ({tostring(ok)})`
		end
		if ok ~= true then
			local message = if type(err) == "string" then err else "invalid"
			local first = string.sub(message, 1, 1)
			return if first == "." or first == "[" then `arg{i}{message}` else `arg{i}: {message}`
		end
	end
	return nil
end

local function bindRemote(self: NetClientImpl, spec: RemoteSpec, instance: Instance)
	self._remotes[spec.name] = instance
	if spec.direction == "S2C" and spec.kind ~= "Function" then
		local event = self._events[spec.name]
		local remote = instance :: RemoteEvent
		local connection = remote.OnClientEvent:Connect(function(...: any)
			event:Fire(...)
		end)
		table.insert(self._cleanups, function()
			connection:Disconnect()
		end)
	end
end

local function findFolder(self: NetClientImpl): Instance?
	if self._folder == nil then
		self._folder = self._container:FindFirstChild(Protocol.REMOTES_FOLDER)
	end
	return self._folder
end

-- Binds every registered remote already present under the folder (non-yielding).
local function bindAvailable(self: NetClientImpl)
	local folder = findFolder(self)
	if folder == nil then
		return
	end
	for name, spec in self._specs do
		if self._remotes[name] == nil then
			local instance = folder:FindFirstChild(name)
			if instance ~= nil then
				bindRemote(self, spec, instance)
			end
		end
	end
end

local function missingNames(self: NetClientImpl): { string }
	local missing = {}
	for name in self._specs do
		if self._remotes[name] == nil then
			table.insert(missing, name)
		end
	end
	table.sort(missing)
	return missing
end

--- Waits until the Remotes folder and every registered remote exist (yields). Warns every `warnInterval` seconds.
--- Returns false if `timeout` elapses first (nil = wait forever).
function NetClientClass.waitForRemotes(self: NetClientImpl, timeout: number?): boolean
	local started = self._clock:now()
	local function remaining(): number
		if timeout == nil then
			return self._warnInterval
		end
		return math.max(0, math.min(self._warnInterval, timeout - (self._clock:now() - started)))
	end
	local function expired(): boolean
		return timeout ~= nil and self._clock:now() - started >= timeout
	end
	while findFolder(self) == nil do
		local folder = self._container:WaitForChild(Protocol.REMOTES_FOLDER, remaining())
		if folder ~= nil then
			self._folder = folder
			break
		end
		self._log:warn("still waiting for %s.%s", self._container.Name, Protocol.REMOTES_FOLDER)
		if expired() then
			return false
		end
	end
	bindAvailable(self)
	local folder = self._folder :: Instance
	while true do
		local missing = missingNames(self)
		if #missing == 0 then
			return true
		end
		local instance = folder:WaitForChild(missing[1], remaining())
		if instance ~= nil then
			bindRemote(self, self._specs[missing[1]], instance)
		else
			self._log:warn("still waiting for remotes: %s", table.concat(missing, ", "))
			if expired() then
				return false
			end
		end
		bindAvailable(self)
	end
end

local function remoteFor(self: NetClientImpl, name: string, timeout: number): Instance?
	local instance = self._remotes[name]
	if instance ~= nil then
		return instance
	end
	bindAvailable(self)
	instance = self._remotes[name]
	if instance ~= nil then
		return instance
	end
	local folder = findFolder(self) or self._container:WaitForChild(Protocol.REMOTES_FOLDER, timeout)
	if folder == nil then
		return nil
	end
	self._folder = folder
	local found = folder:WaitForChild(name, timeout)
	if found ~= nil then
		bindRemote(self, self._specs[name], found)
	end
	return found
end

--- Fires a C2S Event/Unreliable remote. Invalid arguments are dropped with a warning.
function NetClientClass.fire(self: NetClientImpl, name: string, ...: any)
	local spec = specFor(self, name, "fire")
	if spec.direction ~= "C2S" or spec.kind == "Function" then
		error(`NetClient:fire("{name}") requires a C2S Event/Unreliable remote`, 2)
	end
	local problem = validateOutgoing(self, spec, ...)
	if problem ~= nil then
		self._log:warn("dropped %s: invalid arguments (%s)", name, problem)
		return
	end
	local remote = remoteFor(self, name, self._invokeTimeout)
	if remote == nil then
		self._log:warn("dropped %s: remote not found", name)
		return
	end
	(remote :: RemoteEvent):FireServer(...)
end

--- Subscribes to an S2C event. Never yields: handlers attached before the remote replicates still receive events.
function NetClientClass.on(self: NetClientImpl, name: string, handler: (...any) -> ()): Connection
	local spec = specFor(self, name, "on")
	if spec.direction ~= "S2C" or spec.kind == "Function" then
		error(`NetClient:on("{name}") requires an S2C Event/Unreliable remote`, 2)
	end
	bindAvailable(self)
	return self._events[name]:Connect(handler)
end

--- Invokes a C2S Function remote with an explicit timeout (seconds). Yields; always returns a Result.
function NetClientClass.invokeWithTimeout(
	self: NetClientImpl,
	name: string,
	timeout: number,
	...: any
): Result.Result<any>
	local spec = specFor(self, name, "invoke")
	if spec.kind ~= "Function" then
		error(`NetClient:invoke("{name}") requires a Function remote`, 2)
	end
	local problem = validateOutgoing(self, spec, ...)
	if problem ~= nil then
		return Result.err(ErrorCodes.INVALID_ARGS, problem)
	end
	local remote = remoteFor(self, name, timeout)
	if remote == nil then
		return Result.err(ErrorCodes.NOT_FOUND, `remote {name} not found`)
	end

	local caller = coroutine.running()
	local args = table.pack(...)
	local finished = false
	local waiting = false
	local outcome: Result.Result<any> = Result.err(ErrorCodes.INTERNAL, "no response")

	local function finish(value: Result.Result<any>)
		if finished then
			return
		end
		finished = true
		outcome = value
		if waiting then
			waiting = false
			self._spawn(caller)
		end
	end

	self._spawn(function()
		local ok, response = pcall(function()
			return (remote :: RemoteFunction):InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not ok then
			finish(Result.err(ErrorCodes.INTERNAL, tostring(response)))
		elseif not Result.is(response) then
			finish(Result.err(ErrorCodes.INTERNAL, "malformed response"))
		else
			finish(response)
		end
	end)

	if not finished then
		local timer = self._delay(timeout, function()
			finish(Result.err(ErrorCodes.TIMEOUT, `{name} timed out after {timeout}s`))
		end)
		waiting = true
		coroutine.yield()
		pcall(self._cancel, timer)
	end
	return outcome
end

--- Invokes a C2S Function remote with the default timeout. Yields; always returns a Result.
function NetClientClass.invoke(self: NetClientImpl, name: string, ...: any): Result.Result<any>
	return NetClientClass.invokeWithTimeout(self, name, self._invokeTimeout, ...)
end

function NetClientClass.destroy(self: NetClientImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, cleanup in self._cleanups do
		cleanup()
	end
	table.clear(self._cleanups)
	for _, event in self._events do
		event:DisconnectAll()
	end
end

local NetClient = {}

--- Creates the client endpoint. Must be called on the client. Does not yield (call waitForRemotes to wait).
function NetClient.new(options: NetClientOptions?): NetClient
	local opts: NetClientOptions = options or {}
	local runService: RunService = opts.runService or game:GetService("RunService")
	if not runService:IsClient() then
		error("NetClient.new: NetClient can only be used on the client", 2)
	end
	local specs: { [string]: RemoteSpec } = {}
	local events: { [string]: CoreTypes.Signal<...any> } = {}
	for _, spec in opts.registry or Remotes.all() do
		specs[spec.name] = spec
		if spec.direction == "S2C" and spec.kind ~= "Function" then
			events[spec.name] = Signal.new()
		end
	end
	local self: NetClientImpl = setmetatable({
		_specs = specs,
		_container = opts.container or game:GetService("ReplicatedStorage"),
		_folder = nil,
		_remotes = {},
		_events = events,
		_cleanups = {},
		_clock = opts.clock or Clock.real(),
		_log = opts.log or Log.scope("NetClient"),
		_invokeTimeout = opts.invokeTimeout or Protocol.INVOKE_TIMEOUT,
		_warnInterval = opts.warnInterval or 5,
		_validateArgs = opts.validateArgs ~= false,
		_spawn = opts.spawn or task.spawn,
		_delay = opts.delay or task.delay,
		_cancel = opts.cancel or task.cancel,
		_destroyed = false,
	}, NetClientClass) :: any
	bindAvailable(self)
	return (self :: any) :: NetClient
end

return NetClient
