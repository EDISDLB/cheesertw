--!strict
--[[
	Bootstrap — testable core of the server boot sequence (Main.server.luau is the thin Roblox entry point).

	Purpose:          Builds the ServiceContext, loads validated live config overrides, runs the ServiceLoader
	                  (Init/Start) and exposes the loader so Main can Stop it from BindToClose.
	Dependencies:     Core/ServiceLoader, Core/Log, Core/Result, Config, Net/ErrorCodes, Types.
	State:            None (returns the loader).
	Validation:       Live overrides go through Config.applyOverrides (bounds-checked, all-or-nothing).
	Error handling:   Configuration errors (missing dependency, cycle) are caught and returned as Err(INTERNAL) with
	                  the loader so Main can report them; failed services degrade (see ServiceLoader).
	Performance notes: Boot-time only. loadLiveOverrides performs one DataStore read.
]]

local Types = require("@game/ReplicatedStorage/Shared/Types")
local ServiceLoader = require("@game/ReplicatedStorage/Shared/Core/ServiceLoader")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")

export type BootOptions = {
	role: Types.ServerRole,
	isStudio: boolean,
	modules: { Types.ServiceModule },
	adapters: Types.Adapters,
	net: Types.NetServer,
	config: { [string]: any },
	clock: Types.Clock,
	server: Types.ServerInfo,
	spawn: ((fn: () -> ()) -> thread)?,
	cancel: ((thread: thread) -> ())?,
	wait: ((seconds: number) -> ())?,
	failFast: boolean?,
}

--- DataStore location of live config overrides (a nested table like `{ Battle = { SNAPSHOT_RATE = 15 } }`).
local OVERRIDES_STORE = "HulldownConfig"
local OVERRIDES_KEY = "LiveOverrides"

local log = Log.scope("Bootstrap")

local Bootstrap = {}

Bootstrap.OVERRIDES_STORE = OVERRIDES_STORE
Bootstrap.OVERRIDES_KEY = OVERRIDES_KEY

--- Reads the DataModel identity (call with `game`).
function Bootstrap.serverInfo(dataModel: DataModel): Types.ServerInfo
	return {
		placeId = dataModel.PlaceId,
		gameId = dataModel.GameId,
		jobId = dataModel.JobId,
		privateServerId = dataModel.PrivateServerId,
		privateServerOwnerId = dataModel.PrivateServerOwnerId,
	}
end

--- Fetches and applies live overrides. Missing overrides are Ok({}); read failures and invalid patches are Err and
--- leave the shipped config untouched.
function Bootstrap.loadLiveOverrides(dataStore: Types.DataStoreAdapter, config: any): Types.Result<{ string }>
	local ok, value = dataStore:getAsync(OVERRIDES_STORE, OVERRIDES_KEY)
	if not ok then
		return Result.err(ErrorCodes.UNAVAILABLE, `could not read live overrides: {tostring(value)}`)
	end
	if value == nil then
		return Result.ok({})
	end
	return config.applyOverrides(value)
end

--- Creates the loader with the full service context, registers `modules` and boots them.
--- Returns the loader and Ok(order) or Err(INTERNAL, message) for configuration errors.
function Bootstrap.start(options: BootOptions): (ServiceLoader.ServiceLoader, Types.Result<{ string }>)
	local context = {
		role = options.role,
		services = {},
		net = options.net,
		config = options.config,
		log = Log.scope("Server"),
		clock = options.clock,
		adapters = options.adapters,
		isStudio = options.isStudio,
		server = options.server,
	}
	local loader = ServiceLoader.new({
		role = options.role :: string,
		context = context,
		spawn = options.spawn,
		cancel = options.cancel,
		wait = options.wait,
		clock = options.clock,
		kind = "Service",
		failFast = options.failFast,
	})
	local ok, err = pcall(function()
		loader:registerMany(options.modules)
		loader:boot()
	end)
	if not ok then
		log:error("boot failed: %s", tostring(err))
		return loader, Result.err(ErrorCodes.INTERNAL, tostring(err))
	end
	return loader, Result.ok(loader:getOrder())
end

return Bootstrap
