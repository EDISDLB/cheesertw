--!strict
--[[
	Client/Main — client boot: connect, handshake, then boot controllers with the shared ServiceLoader.

	Purpose:          Wait for the remotes, call "Hello" (retrying while the server is still starting), boot every
	                  controller under Client/Controllers filtered by the server role, then flag the client ready
	                  (LocalPlayer attribute read by ReplicatedFirst/LoadingBootstrap).
	Dependencies:     Net/NetClient, Net/Protocol, Net/ErrorCodes, Core/ServiceLoader, Core/Log, Core/Clock,
	                  Core/Result, Config, Types.
	State:            The controller loader and NetClient (returned from start()).
	Validation:       Hello responses are shape-checked; protocol mismatches stop the boot with a rejoin message.
	Error handling:   Failures are shown through the loading-status attribute and returned as Err; individual
	                  controller failures degrade (ServiceLoader) instead of aborting the client.
	Performance notes: Runs once per session.

	Controllers follow the ServiceModule shape (Name, Roles?, Dependencies?, Init(ctx), Start(), Stop()) and receive a
	ControllerContext (role, services, net, config, log, clock, isStudio, player, lifecycle, hello).
]]

local Types = require("@game/ReplicatedStorage/Shared/Types")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local NetClient = require("@game/ReplicatedStorage/Shared/Net/NetClient")
local Protocol = require("@game/ReplicatedStorage/Shared/Net/Protocol")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")
local ServiceLoader = require("@game/ReplicatedStorage/Shared/Core/ServiceLoader")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")
local Clock = require("@game/ReplicatedStorage/Shared/Core/Clock")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")

export type StartOptions = {
	--- Injected for tests; defaults to NetClient.new().
	net: Types.NetClient?,
	--- Defaults to Players.LocalPlayer.
	player: Player?,
	--- Controllers to boot; defaults to the ModuleScripts under Client/Controllers.
	controllers: { Types.ServiceModule }?,
	--- Hello attempts while the server answers NOT_READY / TIMEOUT / RATE_LIMITED (default 30, 1 s apart).
	helloAttempts: number?,
	retryDelay: number?,
	remotesTimeout: number?,
	isStudio: boolean?,
	wait: ((seconds: number) -> ())?,
}

export type Session = {
	loader: ServiceLoader.ServiceLoader,
	net: Types.NetClient,
	hello: Types.HelloResponse,
}

local log = Log.scope("Client")

local RETRYABLE: { [string]: boolean } = {
	[ErrorCodes.NOT_READY] = true,
	[ErrorCodes.TIMEOUT] = true,
	[ErrorCodes.RATE_LIMITED] = true,
}

local Main = {}

local function setStatus(player: Player?, text: string)
	if player ~= nil then
		player:SetAttribute(Protocol.ATTR_LOADING_STATUS, text)
	end
end

local function discoverControllers(): { Types.ServiceModule }
	local modules: { Types.ServiceModule } = {}
	local folder = script.Parent:FindFirstChild("Controllers")
	if folder == nil then
		return modules
	end
	-- Controller discovery is the one sanctioned use of instance requires on the client.
	local dynamicRequire = require :: any
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, module = pcall(dynamicRequire, child)
			if not ok then
				log:error("failed to load controller %s: %s", child.Name, tostring(module))
			elseif type(module) ~= "table" or module.Name ~= child.Name then
				log:error("controller %s must return a table whose Name is %q", child.Name, child.Name)
			else
				table.insert(modules, module)
			end
		end
	end
	return modules
end

local function isHelloResponse(value: any): boolean
	return type(value) == "table"
		and (value.role == "Hub" or value.role == "Battle" or value.role == "Dev")
		and type(value.version) == "string"
		and type(value.protocol) == "number"
end

--- Performs the Hello handshake with retries. Returns the validated response.
function Main.handshake(net: Types.NetClient, options: StartOptions?): Types.Result<Types.HelloResponse>
	local opts: StartOptions = options or {}
	local attempts = opts.helloAttempts or 30
	local delay = opts.retryDelay or 1
	local waitFn: (seconds: number) -> () = opts.wait or function(seconds: number)
		task.wait(seconds)
	end
	local request: Types.HelloRequest = { clientVersion = Protocol.GAME_VERSION, protocol = Protocol.PROTOCOL_VERSION }
	local lastErr: string = ErrorCodes.INTERNAL
	local lastDetail: any = "no attempt made"
	for attempt = 1, attempts do
		local response = net:invoke("Hello", request)
		if response.ok then
			if not isHelloResponse(response.value) then
				return Result.err(ErrorCodes.INTERNAL, "malformed Hello response")
			end
			return Result.ok(response.value :: Types.HelloResponse)
		end
		lastErr, lastDetail = response.err, response.detail
		if not RETRYABLE[lastErr] or attempt == attempts then
			break
		end
		waitFn(delay)
	end
	return Result.err(lastErr, lastDetail)
end

--- Boots the client. Yields until the handshake completes. Returns the session or an error.
function Main.start(options: StartOptions?): Types.Result<Session>
	local opts: StartOptions = options or {}
	local player: Player? = opts.player or game:GetService("Players").LocalPlayer
	local isStudio = if opts.isStudio ~= nil then opts.isStudio else game:GetService("RunService"):IsStudio()
	setStatus(player, "Connecting...")

	local net = opts.net or NetClient.new()
	if not net:waitForRemotes(opts.remotesTimeout or 60) then
		setStatus(player, "Unable to reach the server. Please rejoin.")
		return Result.err(ErrorCodes.TIMEOUT, "remotes did not replicate")
	end

	local hello = Main.handshake(net, opts)
	if not hello.ok then
		setStatus(player, ErrorCodes.message(hello.err))
		log:error("handshake failed: %s (%s)", hello.err, tostring(hello.detail))
		return Result.err(hello.err, hello.detail)
	end
	local info = hello.value
	log:info("connected: role %s, server %s (protocol %d)", info.role, info.version, info.protocol)
	setStatus(player, "Loading...")

	local loader = ServiceLoader.new({
		role = info.role :: string,
		kind = "Controller",
		context = {
			role = info.role,
			services = {},
			net = net,
			config = Config,
			clock = Clock.real(),
			isStudio = isStudio,
			player = player,
			hello = info,
		},
		spawn = function(fn: () -> ()): thread
			return task.spawn(fn)
		end,
		cancel = task.cancel,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
	})
	local ok, err = pcall(function()
		loader:registerMany(opts.controllers or discoverControllers())
		loader:boot()
	end)
	if not ok then
		log:error("controller boot failed: %s", tostring(err))
		setStatus(player, "Something went wrong while loading. Please rejoin.")
		return Result.err(ErrorCodes.INTERNAL, tostring(err))
	end

	if player ~= nil then
		player:SetAttribute(Protocol.ATTR_CLIENT_READY, true)
	end
	return Result.ok({ loader = loader, net = net, hello = info })
end

return Main
