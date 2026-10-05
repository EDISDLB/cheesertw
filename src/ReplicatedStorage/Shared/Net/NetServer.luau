--!strict
--[[
	NetServer — server side of the remote layer (ARCHITECTURE §5.2). SERVER ONLY.

	Purpose:          Creates ReplicatedStorage.Remotes from the registry and guards every client->server call:
	                  token-bucket rate limit (per player, per remote) -> dev-only gate -> schema validation of each
	                  argument -> pcall'd handler. Function remotes always answer with a Result.
	Dependencies:     Net/Remotes, Net/Protocol, Net/ErrorCodes, Security/RateLimiter, Core/Result, Core/Log,
	                  Core/Clock, Types/Net, Types/Adapters. Roblox: Instance.new, RunService (call-time only).
	State:            Remote instances + handlers per registry entry, rate-limiter buckets, violation handler,
	                  developer check.
	Validation:       Registration API rejects unknown names and wrong kind/direction. Incoming calls with too many
	                  arguments, failing validators (anything but `true`, or a validator that throws), devOnly
	                  access by non-developers, rate overruns, or a client firing an S2C remote never reach handlers.
	Error handling:   Violations are reported to the violation handler (AntiExploitService:strike) with a weight.
	                  Handler errors are logged with traceback; Function handlers then return Err(INTERNAL).
	                  Function remotes without a handler yet answer Err(NOT_READY).
	Performance notes: Per call: one bucket refill + one validator per argument; no allocation on the event path
	                  except varargs.

	Server-only guard: NetServer.new() checks RunService:IsServer() when called (requiring the module is harmless).
]]

local CoreTypes = require("../Types/Core")
local NetTypes = require("../Types/Net")
local AdapterTypes = require("../Types/Adapters")
local Remotes = require("./Remotes")
local Protocol = require("./Protocol")
local ErrorCodes = require("./ErrorCodes")
local RateLimiter = require("../Security/RateLimiter")
local Result = require("../Core/Result")
local Log = require("../Core/Log")
local Clock = require("../Core/Clock")

type Clock = CoreTypes.Clock
type Logger = CoreTypes.Logger
type Connection = CoreTypes.Connection
type RemoteSpec = NetTypes.RemoteSpec
type ViolationHandler = NetTypes.ViolationHandler
type ViolationReason = NetTypes.ViolationReason
export type NetServer = NetTypes.NetServer

export type NetServerOptions = {
	--- Remote specs to expose (default: every entry of Net/Remotes).
	registry: { RemoteSpec }?,
	--- Parent of the Remotes folder (default: ReplicatedStorage).
	container: Instance?,
	clock: Clock?,
	--- When given, rate-limit state is dropped on PlayerRemoving.
	players: AdapterTypes.PlayersAdapter?,
	--- Decides who may call devOnly remotes (default: Studio only). DebugService replaces it via setDeveloperCheck.
	isDeveloper: ((player: Player) -> boolean)?,
	runService: RunService?,
	log: Logger?,
}

local VIOLATION_WEIGHTS: { [ViolationReason]: number } = table.freeze({
	RATE_LIMITED = 1,
	INVALID_ARGS = 2,
	NOT_ALLOWED = 3,
	PROTOCOL_VIOLATION = 5,
})

type Endpoint = {
	spec: RemoteSpec,
	instance: Instance,
	handler: ((...any) -> ...any)?,
}

type NetServerImpl = {
	_endpoints: { [string]: Endpoint },
	_folder: Folder,
	_limiter: RateLimiter.RateLimiter,
	_violation: ViolationHandler?,
	_isDeveloper: (player: Player) -> boolean,
	_log: Logger,
	_cleanups: { () -> () },
	_destroyed: boolean,
}

local NetServerClass = {}
NetServerClass.__index = NetServerClass

local function traceback(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function report(self: NetServerImpl, player: Player, reason: ViolationReason, remoteName: string, detail: string?)
	local weight = VIOLATION_WEIGHTS[reason]
	local text = if detail then `{remoteName}: {detail}` else remoteName
	self._log:debug("violation %s by %s (%s)", reason, tostring(player and player.UserId), text)
	local handler = self._violation
	if handler ~= nil then
		local ok, err = pcall(handler :: any, player, reason, weight, text)
		if not ok then
			self._log:error("violation handler failed: %s", tostring(err))
		end
	end
end

-- Returns nil when the call may proceed, otherwise (code, detail).
local function gate(self: NetServerImpl, endpoint: Endpoint, player: Player, ...: any): (string?, string?)
	local spec = endpoint.spec
	if not self._limiter:consume(player, spec.name, spec.rate or Protocol.DEFAULT_RATE) then
		report(self, player, "RATE_LIMITED", spec.name, nil)
		return ErrorCodes.RATE_LIMITED, nil
	end
	if spec.devOnly then
		local ok, allowed = pcall(self._isDeveloper, player)
		if not ok or allowed ~= true then
			report(self, player, "NOT_ALLOWED", spec.name, "developer-only remote")
			return ErrorCodes.NOT_ALLOWED, nil
		end
	end
	local validators: { CoreTypes.Validator } = spec.args or {}
	local count = select("#", ...)
	if count > #validators then
		local detail = `expected at most {#validators} arguments, got {count}`
		report(self, player, "INVALID_ARGS", spec.name, detail)
		return ErrorCodes.INVALID_ARGS, detail
	end
	for i, validator in validators do
		-- A validator that throws on hostile input (custom validators, bugs) must still fail closed with a Result:
		-- nothing may throw across the remote boundary.
		local called, ok, err = pcall(validator, (select(i, ...)))
		if not called then
			self._log:error("validator for %s arg%d threw: %s", spec.name, i, tostring(ok))
			local detail = `arg{i}: rejected (validator error)`
			report(self, player, "INVALID_ARGS", spec.name, detail)
			return ErrorCodes.INVALID_ARGS, detail
		end
		if ok ~= true then
			local message = if type(err) == "string" then err else "invalid"
			local first = string.sub(message, 1, 1)
			local detail = if first == "." or first == "[" then `arg{i}{message}` else `arg{i}: {message}`
			report(self, player, "INVALID_ARGS", spec.name, detail)
			return ErrorCodes.INVALID_ARGS, detail
		end
	end
	return nil, nil
end

local function onEvent(self: NetServerImpl, endpoint: Endpoint, player: Player, ...: any)
	local spec = endpoint.spec
	if spec.direction ~= "C2S" then
		report(self, player, "PROTOCOL_VIOLATION", spec.name, "client fired a server-to-client remote")
		return
	end
	local code = gate(self, endpoint, player, ...)
	if code ~= nil then
		return
	end
	local handler = endpoint.handler
	if handler == nil then
		self._log:debug("%s received with no handler registered", spec.name)
		return
	end
	local ok, err = xpcall(handler, traceback, player, ...)
	if not ok then
		self._log:error("handler for %s failed (player %s): %s", spec.name, tostring(player.UserId), tostring(err))
	end
end

local function onInvoke(self: NetServerImpl, endpoint: Endpoint, player: Player, ...: any): Result.Result<any>
	local spec = endpoint.spec
	local code, detail = gate(self, endpoint, player, ...)
	if code ~= nil then
		return Result.err(code, detail)
	end
	local handler = endpoint.handler
	if handler == nil then
		return Result.err(ErrorCodes.NOT_READY, `{spec.name} is not ready`)
	end
	local ok, response = xpcall(handler, traceback, player, ...)
	if not ok then
		self._log:error("handler for %s failed (player %s): %s", spec.name, tostring(player.UserId), tostring(response))
		return Result.err(ErrorCodes.INTERNAL, nil)
	end
	if not Result.is(response) then
		self._log:error("handler for %s returned a non-Result value (%s)", spec.name, typeof(response))
		return Result.err(ErrorCodes.INTERNAL, nil)
	end
	return response
end

local function endpointFor(self: NetServerImpl, name: string, method: string): Endpoint
	local endpoint = self._endpoints[name]
	if endpoint == nil then
		error(`NetServer:{method}: unknown remote "{tostring(name)}" (add it to Net/Remotes)`, 3)
	end
	return endpoint
end

local function makeHandle(endpoint: Endpoint, handler: (...any) -> ...any): Connection
	local handle = { Connected = true }
	function handle.Disconnect(self: any)
		if self.Connected then
			self.Connected = false
			if endpoint.handler == handler then
				endpoint.handler = nil
			end
		end
	end
	return (handle :: any) :: Connection
end

function NetServerClass.on(self: NetServerImpl, name: string, handler: NetTypes.EventHandler): Connection
	local endpoint = endpointFor(self, name, "on")
	local spec = endpoint.spec
	if spec.direction ~= "C2S" or spec.kind == "Function" then
		error(`NetServer:on("{name}") requires a C2S Event/Unreliable remote (use onInvoke for Functions)`, 2)
	end
	if endpoint.handler ~= nil then
		error(`NetServer:on("{name}"): a handler is already registered`, 2)
	end
	endpoint.handler = handler
	return makeHandle(endpoint, handler)
end

function NetServerClass.onInvoke(self: NetServerImpl, name: string, handler: NetTypes.InvokeHandler): Connection
	local endpoint = endpointFor(self, name, "onInvoke")
	if endpoint.spec.kind ~= "Function" then
		error(`NetServer:onInvoke("{name}") requires a Function remote`, 2)
	end
	if endpoint.handler ~= nil then
		error(`NetServer:onInvoke("{name}"): a handler is already registered`, 2)
	end
	endpoint.handler = handler
	return makeHandle(endpoint, handler)
end

-- RemoteEvent and UnreliableRemoteEvent share FireClient/FireAllClients signatures; typed as RemoteEvent.
local function s2cRemote(self: NetServerImpl, name: string, method: string): RemoteEvent
	local endpoint = endpointFor(self, name, method)
	local spec = endpoint.spec
	if spec.direction ~= "S2C" or spec.kind == "Function" then
		error(`NetServer:{method}("{name}") requires an S2C Event/Unreliable remote`, 3)
	end
	return endpoint.instance :: any
end

function NetServerClass.fire(self: NetServerImpl, name: string, player: Player, ...: any)
	s2cRemote(self, name, "fire"):FireClient(player, ...)
end

function NetServerClass.fireAll(self: NetServerImpl, name: string, ...: any)
	s2cRemote(self, name, "fireAll"):FireAllClients(...)
end

function NetServerClass.fireList(self: NetServerImpl, name: string, players: { Player }, ...: any)
	local remote = s2cRemote(self, name, "fireList")
	for _, player in players do
		remote:FireClient(player, ...)
	end
end

function NetServerClass.setViolationHandler(self: NetServerImpl, handler: ViolationHandler?)
	self._violation = handler
end

function NetServerClass.setDeveloperCheck(self: NetServerImpl, check: (player: Player) -> boolean)
	assert(type(check) == "function", "NetServer:setDeveloperCheck expects a function")
	self._isDeveloper = check
end

function NetServerClass.isDeveloper(self: NetServerImpl, player: Player): boolean
	local ok, allowed = pcall(self._isDeveloper, player)
	return ok and allowed == true
end

function NetServerClass.getRemote(self: NetServerImpl, name: string): Instance?
	local endpoint = self._endpoints[name]
	return if endpoint then endpoint.instance else nil
end

function NetServerClass.forgetPlayer(self: NetServerImpl, player: Player)
	self._limiter:forget(player)
end

function NetServerClass.destroy(self: NetServerImpl)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, cleanup in self._cleanups do
		cleanup()
	end
	table.clear(self._cleanups)
	for _, endpoint in self._endpoints do
		endpoint.handler = nil
	end
	self._folder:Destroy()
end

local NetServer = {}

NetServer.VIOLATION_WEIGHTS = VIOLATION_WEIGHTS

--- Creates the Remotes folder and returns the server endpoint. Must be called on the server.
function NetServer.new(options: NetServerOptions?): NetServer
	local opts: NetServerOptions = options or {}
	local runService: RunService = opts.runService or game:GetService("RunService")
	if not runService:IsServer() then
		error("NetServer.new: NetServer can only be used on the server", 2)
	end
	local container: Instance = opts.container or game:GetService("ReplicatedStorage")
	if container:FindFirstChild(Protocol.REMOTES_FOLDER) ~= nil then
		error(`NetServer.new: {container:GetFullName()}.{Protocol.REMOTES_FOLDER} already exists`, 2)
	end

	local folder = Instance.new("Folder")
	folder.Name = Protocol.REMOTES_FOLDER

	local self: NetServerImpl = setmetatable({
		_endpoints = {},
		_folder = folder,
		_limiter = RateLimiter.new(opts.clock or Clock.real()),
		_violation = nil,
		_isDeveloper = opts.isDeveloper or function(_player: Player): boolean
			return runService:IsStudio()
		end,
		_log = opts.log or Log.scope("NetServer"),
		_cleanups = {},
		_destroyed = false,
	}, NetServerClass) :: any

	for _, spec in opts.registry or Remotes.all() do
		-- Custom registries (tests, tools) get the same load-time validation as Net/Remotes entries.
		local valid, problem = Remotes.validateSpec(spec)
		if not valid then
			error(`NetServer.new: {problem}`, 2)
		end
		if self._endpoints[spec.name] ~= nil then
			error(`NetServer.new: duplicate remote "{spec.name}" in registry`, 2)
		end
		local endpoint: Endpoint
		if spec.kind == "Function" then
			local remote = Instance.new("RemoteFunction")
			remote.Name = spec.name
			endpoint = { spec = spec, instance = remote, handler = nil }
			remote.OnServerInvoke = function(player: Player, ...: any): any
				return onInvoke(self, endpoint, player, ...)
			end
			remote.Parent = folder
		else
			-- Both classes expose OnServerEvent(player, ...); the unreliable one is typed through RemoteEvent.
			local remote: RemoteEvent = if spec.kind == "Unreliable"
				then Instance.new("UnreliableRemoteEvent") :: any
				else Instance.new("RemoteEvent")
			remote.Name = spec.name
			endpoint = { spec = spec, instance = remote, handler = nil }
			local connection = remote.OnServerEvent:Connect(function(player: Player, ...: any)
				onEvent(self, endpoint, player, ...)
			end)
			table.insert(self._cleanups, function()
				connection:Disconnect()
			end)
			remote.Parent = folder
		end
		self._endpoints[spec.name] = endpoint
	end

	if opts.players ~= nil then
		local connection = opts.players.PlayerRemoving:Connect(function(player: Player)
			self._limiter:forget(player)
		end)
		table.insert(self._cleanups, function()
			connection:Disconnect()
		end)
	end

	folder.Parent = container
	return (self :: any) :: NetServer
end

return NetServer
