--[[
	MockPlayersAdapter — PlayersAdapter backed by the MockGame Players service.

	Purpose:          Services under test see joins/leaves through the adapter exactly as with RobloxPlayers.
	Dependencies:     FailureInjector, Core/Signal, a MockPlayers service (default: game:GetService("Players")).
	State:            Group ranks table; signals bridged from the service.
	Validation:       N/A.
	Error handling:   getGroupRankAsync honours injected failures.
	Performance notes: Test-only.

	Helpers: addPlayer(props) / removePlayer(player) (delegate to the service so both signal layers fire),
	setGroupRank(userId, groupId, rank), kicked (list of { player, message }).
]]

local FailureInjector = require("./FailureInjector")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

local MockPlayersAdapter = {}
MockPlayersAdapter.__index = MockPlayersAdapter

function MockPlayersAdapter.new(playersService: any?)
	local service = playersService or game:GetService("Players")
	local self = setmetatable({
		service = service,
		PlayerAdded = Signal.new(),
		PlayerRemoving = Signal.new(),
		kicked = {},
		_ranks = {},
		injector = FailureInjector.new(),
	}, MockPlayersAdapter)
	service.PlayerAdded:Connect(function(player)
		self.PlayerAdded:Fire(player)
	end)
	service.PlayerRemoving:Connect(function(player)
		self.PlayerRemoving:Fire(player)
	end)
	return self
end

function MockPlayersAdapter.getPlayers(self: any): { any }
	return self.service:GetPlayers()
end

function MockPlayersAdapter.getPlayerByUserId(self: any, userId: number): any
	return self.service:GetPlayerByUserId(userId)
end

function MockPlayersAdapter.kick(self: any, player: any, message: string)
	table.insert(self.kicked, { player = player, message = message })
	player:Kick(message)
end

function MockPlayersAdapter.getGroupRankAsync(self: any, userId: number, groupId: number): (boolean, any)
	local injected = self.injector:check("getGroupRankAsync")
	if injected then
		return false, injected
	end
	return true, self._ranks[userId .. ":" .. groupId] or 0
end

function MockPlayersAdapter.setGroupRank(self: any, userId: number, groupId: number, rank: number)
	self._ranks[userId .. ":" .. groupId] = rank
end

function MockPlayersAdapter.addPlayer(self: any, props: { [string]: any }?): any
	return self.service:addPlayer(props)
end

function MockPlayersAdapter.removePlayer(self: any, player: any)
	self.service:removePlayer(player)
end

function MockPlayersAdapter.failNext(self: any, method: string, count: number?, message: string?)
	self.injector:failNext(method, count, message)
end

function MockPlayersAdapter.failAlways(self: any, method: string, message: string?)
	self.injector:failAlways(method, message)
end

function MockPlayersAdapter.clearFailures(self: any)
	self.injector:clear()
end

return MockPlayersAdapter
