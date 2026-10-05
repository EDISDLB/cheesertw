--!strict
--[[
	RobloxPlayers — PlayersAdapter over Players and GroupService.

	Purpose:          Player enumeration/lookup, kicks, group rank (dev access) and join/leave signals for services.
	Dependencies:     Players, GroupService, Adapters/Retry, Core/Signal, Types/Adapters.
	State:            PlayerAdded/PlayerRemoving signals bridged from the engine.
	Validation:       Group role payloads are type-checked; non-members have rank 0.
	Error handling:   getGroupRankAsync retries twice and returns (false, message) on failure.
	Performance notes: Signals are bridged once per adapter instance. Players already in the server before a
	                  service connects are NOT replayed: services should iterate getPlayers() in Start.
]]

local AdapterTypes = require("@game/ReplicatedStorage/Shared/Types/Adapters")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local Retry = require("./Retry")

type PlayersAdapter = AdapterTypes.PlayersAdapter

--- attempts: max tries per call (default 3; Players: 2). wait: backoff sleeper (default task.wait; tests inject).
export type Options = { attempts: number?, wait: ((seconds: number) -> ())? }

local RobloxPlayers = {}

function RobloxPlayers.new(options: Options?): PlayersAdapter
	local Players = game:GetService("Players")
	local GroupService = game:GetService("GroupService")
	local retryOptions: Retry.RetryOptions = {
		attempts = if options and options.attempts then options.attempts else 2,
		wait = if options then options.wait else nil,
	}

	local adapter = {
		PlayerAdded = Signal.new() :: Signal.Signal<Player>,
		PlayerRemoving = Signal.new() :: Signal.Signal<Player>,
	}

	Players.PlayerAdded:Connect(function(player: Player)
		adapter.PlayerAdded:Fire(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		adapter.PlayerRemoving:Fire(player)
	end)

	function adapter.getPlayers(_self: PlayersAdapter): { Player }
		return Players:GetPlayers()
	end

	function adapter.getPlayerByUserId(_self: PlayersAdapter, userId: number): Player?
		return Players:GetPlayerByUserId(userId)
	end

	function adapter.kick(_self: PlayersAdapter, player: Player, message: string)
		player:Kick(message)
	end

	function adapter.getGroupRankAsync(
		_self: PlayersAdapter,
		userId: number,
		groupId: number
	): (boolean, number | string)
		return Retry.call(function(): number
			local info = GroupService:GetRolesInGroupAsync(userId, groupId)
			if type(info) ~= "table" or info.IsMember ~= true or type(info.Roles) ~= "table" then
				return 0
			end
			local best = 0
			for _, role in info.Roles do
				if type(role) == "table" and type(role.Rank) == "number" and role.Rank > best then
					best = role.Rank
				end
			end
			return best
		end, retryOptions)
	end

	local conforming: PlayersAdapter = adapter -- type-checks every method against the interface
	return conforming
end

return RobloxPlayers
