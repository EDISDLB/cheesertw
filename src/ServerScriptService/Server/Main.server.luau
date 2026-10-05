--!strict
--[[
	Main (server) — HULLDOWN server entry point.

	Purpose:          Resolve the server role, construct live adapters and the NetServer, apply live config
	                  overrides, discover service modules under Server/Services and boot them; Stop them on
	                  BindToClose within a 25 s budget.
	Dependencies:     Server/Bootstrap, Server/Adapters/*, Shared Config/Net/Core.
	State:            The ServiceLoader for the lifetime of the server.
	Validation:       Discovered modules are validated by ServiceLoader (shape, dependencies, cycles).
	Error handling:   Boot configuration errors are logged and every joining player is kicked with an explanation
	                  (never play on a half-booted server). Failed individual services degrade via HealthService.
	Performance notes: Runs once. Service discovery is the one sanctioned use of instance requires.
]]

local RunService = game:GetService("RunService")

local Config = require("@game/ReplicatedStorage/Shared/Config")
local Protocol = require("@game/ReplicatedStorage/Shared/Net/Protocol")
local NetServer = require("@game/ReplicatedStorage/Shared/Net/NetServer")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")
local Clock = require("@game/ReplicatedStorage/Shared/Core/Clock")
local Types = require("@game/ReplicatedStorage/Shared/Types")
local Bootstrap = require("./Bootstrap")
local RobloxPlayers = require("./Adapters/RobloxPlayers")
local RobloxDataStore = require("./Adapters/RobloxDataStore")
local RobloxMemoryStore = require("./Adapters/RobloxMemoryStore")
local RobloxMessaging = require("./Adapters/RobloxMessaging")
local RobloxTeleport = require("./Adapters/RobloxTeleport")
local RobloxMarketplace = require("./Adapters/RobloxMarketplace")

local SHUTDOWN_BUDGET_SECONDS = 25

local log = Log.scope("Server")
local isStudio = RunService:IsStudio()
if isStudio then
	Log.setLevel("debug")
end

local role: Types.ServerRole = Config.Places.resolveRole(game.PlaceId, isStudio)
log:info("HULLDOWN %s booting as %s (place %d, job %s)", Protocol.GAME_VERSION, role, game.PlaceId, game.JobId)

local adapters: Types.Adapters = {
	players = RobloxPlayers.new(),
	dataStore = RobloxDataStore.new(),
	memoryStore = RobloxMemoryStore.new(),
	messaging = RobloxMessaging.new(),
	teleport = RobloxTeleport.new(),
	marketplace = RobloxMarketplace.new(),
	world = nil,
}

local overrides = Bootstrap.loadLiveOverrides(adapters.dataStore, Config)
if overrides.ok then
	if #overrides.value > 0 then
		log:info("live config overrides applied: %s", table.concat(overrides.value, ", "))
	end
else
	log:warn("live config overrides not applied (%s): %s", overrides.err, tostring(overrides.detail))
end

local net = NetServer.new({ players = adapters.players })

-- Service discovery: every ModuleScript child of Server/Services (a folder service is its init ModuleScript).
local dynamicRequire = require :: any
local modules: { Types.ServiceModule } = {}
local servicesFolder = script.Parent:WaitForChild("Services")
for _, child in servicesFolder:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, module = pcall(dynamicRequire, child)
		if not ok then
			log:error("failed to load service module %s: %s", child.Name, tostring(module))
		elseif type(module) ~= "table" or module.Name ~= child.Name then
			log:error("service module %s must return a table whose Name is %q", child.Name, child.Name)
		else
			table.insert(modules, module)
		end
	end
end

local loader, booted = Bootstrap.start({
	role = role,
	isStudio = isStudio,
	modules = modules,
	adapters = adapters,
	net = net,
	config = Config,
	clock = Clock.real(),
	server = Bootstrap.serverInfo(game),
	spawn = function(fn: () -> ()): thread
		return task.spawn(fn)
	end,
	cancel = task.cancel,
	wait = function(seconds: number)
		task.wait(seconds)
	end,
})

if booted.ok then
	log:info("boot complete: %s", table.concat(booted.value, ", "))
else
	log:error("BOOT FAILED: %s", tostring(booted.detail))
	local message = "This server failed to start. Please rejoin."
	adapters.players.PlayerAdded:Connect(function(player: Player)
		adapters.players:kick(player, message)
	end)
	for _, player in adapters.players:getPlayers() do
		adapters.players:kick(player, message)
	end
end

game:BindToClose(function()
	local report = loader:stop(SHUTDOWN_BUDGET_SECONDS)
	log:info("shutdown: %d stopped, %d timed out, %.2f s", #report.stopped, #report.timedOut, report.elapsed)
end)
