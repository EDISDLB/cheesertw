--!strict
--[[
	DebugService — developer access resolution and the developer command console ("DebugCommand" remote).

	Purpose:          Decides who is a developer (Config.DevAccess: Studio, allow-listed user ids, group rank) and
	                  installs that check into NetServer so every devOnly remote is gated. Hosts a command registry
	                  other services extend: `ctx.services.DebugService:registerCommand("spawnbot", {...})`.
	Dependencies:     HealthService (status command), ctx.net, ctx.adapters.players (group rank), ctx.config.DevAccess.
	State:            Command registry; per-user developer cache (resolved on join, cleared on leave).
	Validation:       Command names/args are schema-validated by NetServer (DebugCommand spec); duplicate command
	                  names are rejected at registration.
	Error handling:   Unknown command -> Err(NOT_FOUND); handler errors -> Err(INTERNAL) (logged); non-developers
	                  never reach this service (NetServer reports NOT_ALLOWED strikes).
	Performance notes: Group rank lookups happen once per join (async in Start / PlayerAdded threads).
]]

local Types = require("@game/ReplicatedStorage/Shared/Types")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

type ServiceContext = Types.ServiceContext

export type CommandHandler = (player: Player, args: { any }) -> Types.Result<string>
export type CommandSpec = { description: string, handler: CommandHandler }

type DevAccessConfig = {
	GROUP_ID: number,
	isAllowed: (userId: number, groupRank: number?, isStudio: boolean) -> boolean,
}

local DebugService = {
	Name = "DebugService",
	Roles = { "Hub", "Battle", "Dev" },
	Dependencies = { "HealthService" },
	_ctx = (nil :: any) :: ServiceContext,
	_commands = {} :: { [string]: CommandSpec },
	_devCache = {} :: { [number]: boolean },
	_connections = {} :: { Types.Connection },
}

local function devAccess(): DevAccessConfig
	local configured = DebugService._ctx.config.DevAccess
	if type(configured) == "table" and type(configured.isAllowed) == "function" then
		return configured
	end
	return Config.DevAccess
end

local function resolveDeveloper(player: Player)
	local ctx = DebugService._ctx
	local access = devAccess()
	local rank: number? = nil
	if not ctx.isStudio and access.GROUP_ID ~= 0 then
		local ok, value = ctx.adapters.players:getGroupRankAsync(player.UserId, access.GROUP_ID)
		if ok then
			rank = value :: number
		else
			ctx.log:warn("group rank lookup failed for %d: %s", player.UserId, tostring(value))
		end
	end
	DebugService._devCache[player.UserId] = access.isAllowed(player.UserId, rank, ctx.isStudio)
end

local function runCommand(player: Player, command: string, args: { any }?): Types.Result<string>
	local spec = DebugService._commands[string.lower(command)]
	if spec == nil then
		return Result.err(ErrorCodes.NOT_FOUND, `unknown command "{command}" (try "help")`)
	end
	DebugService._ctx.log:info("%s (%d) ran debug command %s", player.Name, player.UserId, command)
	local ok, result = pcall(spec.handler, player, args or {})
	if not ok then
		DebugService._ctx.log:error("debug command %s failed: %s", command, tostring(result))
		return Result.err(ErrorCodes.INTERNAL, tostring(result))
	end
	if not Result.is(result) then
		return Result.err(ErrorCodes.INTERNAL, "command returned a non-Result value")
	end
	return result
end

local function registerBuiltins()
	DebugService:registerCommand("help", {
		description = "List available commands.",
		handler = function(_player: Player, _args: { any }): Types.Result<string>
			local lines = {}
			for _, name in DebugService:listCommands() do
				table.insert(lines, `{name} - {DebugService._commands[name].description}`)
			end
			return Result.ok(table.concat(lines, "\n"))
		end,
	})
	DebugService:registerCommand("ping", {
		description = "Round-trip check.",
		handler = function(_player: Player, _args: { any }): Types.Result<string>
			return Result.ok("pong")
		end,
	})
	DebugService:registerCommand("health", {
		description = "Server health summary.",
		handler = function(_player: Player, _args: { any }): Types.Result<string>
			local health = DebugService._ctx.services.HealthService
			local status = health:getStatus()
			local lines = {
				`role={status.role} ready={tostring(status.ready)} healthy={tostring(status.healthy)} uptime={math.floor(
					status.uptime
				)}s`,
			}
			for _, failure in status.failures do
				table.insert(lines, `FAILED {failure.service} during {failure.phase}: {failure.err}`)
			end
			return Result.ok(table.concat(lines, "\n"))
		end,
	})
	DebugService:registerCommand("services", {
		description = "Service lifecycle statuses.",
		handler = function(_player: Player, _args: { any }): Types.Result<string>
			local lines = {}
			for _, info in DebugService._ctx.lifecycle.getStatuses() do
				table.insert(lines, `{info.name}: {info.status}{if info.err then " (" .. info.err .. ")" else ""}`)
			end
			return Result.ok(table.concat(lines, "\n"))
		end,
	})
	DebugService:registerCommand("loglevel", {
		description = "Set the server log level: loglevel debug|info|warn|error.",
		handler = function(_player: Player, args: { any }): Types.Result<string>
			local level = args[1]
			if level ~= "debug" and level ~= "info" and level ~= "warn" and level ~= "error" then
				return Result.err(ErrorCodes.INVALID_ARGS, "expected debug|info|warn|error")
			end
			Log.setLevel(level)
			return Result.ok(`log level set to {level}`)
		end,
	})
end

function DebugService.Init(self: typeof(DebugService), ctx: ServiceContext)
	self._ctx = ctx
	self._commands = {}
	self._devCache = {}
	self._connections = {}
	registerBuiltins()
	ctx.net:setDeveloperCheck(function(player: Player): boolean
		return self:isDeveloper(player)
	end)
	table.insert(
		self._connections,
		ctx.net:onInvoke("DebugCommand", function(player: Player, command: any, args: any): Types.Result<any>
			return runCommand(player, command, args)
		end)
	)
end

function DebugService.Start(self: typeof(DebugService))
	local players = self._ctx.adapters.players
	table.insert(
		self._connections,
		players.PlayerAdded:Connect(function(player: Player)
			-- Group lookups yield; never yield inside a Signal handler.
			task.spawn(resolveDeveloper, player)
		end)
	)
	table.insert(
		self._connections,
		players.PlayerRemoving:Connect(function(player: Player)
			self._devCache[player.UserId] = nil
		end)
	)
	for _, player in players:getPlayers() do
		task.spawn(resolveDeveloper, player)
	end
end

function DebugService.Stop(self: typeof(DebugService))
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
end

--- True when `player` may use developer tools. Before the async group lookup finishes, only Studio and the
--- user-id allow-list grant access.
function DebugService.isDeveloper(self: typeof(DebugService), player: Player): boolean
	local cached = self._devCache[player.UserId]
	if cached ~= nil then
		return cached
	end
	return devAccess().isAllowed(player.UserId, nil, self._ctx.isStudio)
end

--- Adds a console command. Names are case-insensitive and must be unique.
function DebugService.registerCommand(self: typeof(DebugService), name: string, spec: CommandSpec)
	local key = string.lower(name)
	if not string.match(key, "^[%w_%.%-]+$") then
		error(`DebugService: invalid command name "{name}"`, 2)
	end
	if self._commands[key] ~= nil then
		error(`DebugService: command "{name}" is already registered`, 2)
	end
	assert(type(spec.handler) == "function", "DebugService: command handler must be a function")
	self._commands[key] = spec
end

function DebugService.listCommands(self: typeof(DebugService)): { string }
	local names = {}
	for name in self._commands do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--- Runs a command as `player` (used by the remote and by server-side tooling/tests).
function DebugService.run(
	_self: typeof(DebugService),
	player: Player,
	command: string,
	args: { any }?
): Types.Result<string>
	return runCommand(player, command, args)
end

return DebugService
