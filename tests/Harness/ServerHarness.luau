--[[
	ServerHarness — boots the real server Bootstrap with mock adapters for integration specs.

	Purpose:          One call gives a running server (NetServer on the mock ReplicatedStorage, services booted) plus
	                  helpers to call remotes as a given player.
	Dependencies:     Server/Bootstrap, Net/NetServer, Config, Harness mocks.
	State:            Per-boot objects returned to the caller.
	Validation:       N/A.
	Error handling:   Boot errors are returned (Result) so specs can assert on them.
	Performance notes: Test-only.
]]

local Bootstrap = require("@game/ServerScriptService/Server/Bootstrap")
local NetServer = require("@game/ReplicatedStorage/Shared/Net/NetServer")
local Config = require("@game/ReplicatedStorage/Shared/Config")
local FakeClock = require("@tests/Harness/FakeClock")
local MockAdapters = require("@tests/Harness/Mocks/MockAdapters")

local ServerHarness = {}

export type BootArgs = {
	role: string?,
	isStudio: boolean?,
	modules: { any },
	config: any?,
}

function ServerHarness.boot(args: BootArgs)
	local rs = game:GetService("RunService")
	rs:setServer(true)
	rs:setClient(true)
	rs:setStudio(args.isStudio == true)
	local clock = FakeClock.new(1000)
	local adapters = MockAdapters.new({ clock = clock })
	local net = NetServer.new({ players = adapters.players, clock = clock })
	local loader, result = Bootstrap.start({
		role = (args.role or "Hub") :: any,
		isStudio = args.isStudio == true,
		modules = args.modules,
		adapters = adapters :: any,
		net = net,
		config = args.config or Config,
		clock = clock,
		server = Bootstrap.serverInfo(game :: any),
		spawn = function(fn)
			return task.spawn(fn)
		end,
		cancel = task.cancel,
		wait = function(seconds)
			task.wait(seconds)
		end,
	})
	local h = { clock = clock, adapters = adapters, net = net, loader = loader, result = result }

	function h.remote(name: string): any
		return game:GetService("ReplicatedStorage").Remotes[name]
	end

	function h.invoke(player: any, name: string, ...: any): any
		return h.remote(name):_simulateInvokeServer(player, ...)
	end

	function h.shutdown()
		loader:stop(1)
		net:destroy()
	end

	return h
end

return ServerHarness
