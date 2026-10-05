--[[
	MockGame — DataModel stand-in injected as `game` (and `workspace`) by the Loader.

	Purpose:          GetService registry with settable services; DataModel properties (PlaceId, JobId,
	                  PrivateServerId...), Loaded/IsLoaded, BindToClose + close() to simulate shutdown.
	Dependencies:     MockInstance, MockRunService, MockPlayers.
	State:            Service instances (children of the DataModel), bound close callbacks.
	Validation:       GetService errors for names that are not known Roblox services unless registered.
	Error handling:   close() runs every BindToClose callback under pcall and returns the errors.
	Performance notes: Test-only.
]]

local MockInstance = require("./MockInstance")
local MockRunService = require("./MockRunService")
local MockPlayers = require("./MockPlayers")

local MockGame = {}

local KNOWN_SERVICES = {
	"ReplicatedStorage",
	"ReplicatedFirst",
	"ServerScriptService",
	"ServerStorage",
	"StarterPlayer",
	"StarterGui",
	"StarterPack",
	"Lighting",
	"SoundService",
	"Teams",
	"Chat",
	"TextChatService",
	"HttpService",
	"TweenService",
	"UserInputService",
	"ContextActionService",
	"GuiService",
	"CollectionService",
	"Debris",
	"PhysicsService",
	"TeleportService",
	"DataStoreService",
	"MemoryStoreService",
	"MessagingService",
	"MarketplaceService",
	"GroupService",
	"PolicyService",
	"LocalizationService",
	"TextService",
	"ContentProvider",
	"Stats",
	"TestService",
}

MockInstance.defineClass("DataModel", {
	signals = { "Loaded", "Close" },
	init = function(inst: any)
		rawset(inst, "_closeCallbacks", {})
		rawset(inst, "_services", {})
	end,
	methods = {
		GetService = function(self: any, name: string): any
			local services = rawget(self, "_services")
			local existing = services[name]
			if existing ~= nil then
				return existing
			end
			if table.find(KNOWN_SERVICES, name) == nil then
				error(`'{name}' is not a valid Service name (MockGame: register it with game:setService)`, 2)
			end
			local service = MockInstance.new(name)
			service.Name = name
			service.Parent = self
			services[name] = service
			return service
		end,
		FindService = function(self: any, name: string): any
			return rawget(self, "_services")[name]
		end,
		-- Registers (or replaces) a service object; any table works (plain fakes are allowed).
		setService = function(self: any, name: string, service: any)
			rawget(self, "_services")[name] = service
			if MockInstance.isMock(service) and rawget(service, "_parent") == nil then
				service.Parent = self
			end
		end,
		IsLoaded = function(_self: any): boolean
			return true
		end,
		BindToClose = function(self: any, fn: () -> ())
			table.insert(rawget(self, "_closeCallbacks"), fn)
		end,
		-- Simulates server shutdown: runs BindToClose callbacks in order; returns error messages.
		close = function(self: any): { string }
			local errors = {}
			for _, fn in rawget(self, "_closeCallbacks") do
				local ok, err = pcall(fn)
				if not ok then
					table.insert(errors, tostring(err))
				end
			end
			return errors
		end,
	},
})

function MockGame.new(): any
	local dm = MockInstance.new("DataModel")
	dm.Name = "Game"
	dm.PlaceId = 0
	dm.GameId = 0
	dm.PlaceVersion = 0
	dm.JobId = "mock-job-0001"
	dm.PrivateServerId = ""
	dm.PrivateServerOwnerId = 0
	dm.CreatorId = 0

	local services = rawget(dm, "_services")

	local runService = MockRunService.new()
	runService.Parent = dm
	services.RunService = runService

	local players = MockPlayers.new()
	players.Parent = dm
	services.Players = players

	local workspace = MockInstance.new("Workspace")
	workspace.Name = "Workspace"
	workspace.Parent = dm
	services.Workspace = workspace
	dm.Workspace = workspace

	MockInstance.setLocalPlayerProvider(function()
		return players.LocalPlayer
	end)
	return dm
end

return MockGame
