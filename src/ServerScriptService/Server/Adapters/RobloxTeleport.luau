--!strict
--[[
	RobloxTeleport — TeleportAdapter over TeleportService (reserved battle servers, ARCHITECTURE §2.1).

	Purpose:          ReserveServerAsync -> { accessCode, privateServerId }; TeleportAsync with TeleportOptions;
	                  TeleportInitFailed bridged to the adapter's TeleportFailed signal.
	Dependencies:     TeleportService, Adapters/Retry, Core/Signal, Types/Adapters.
	State:            The TeleportFailed signal and its engine connection.
	Validation:       Teleport data must be TeleportData-compatible (Roblox errors otherwise; returned as failure).
	                  Teleport data is never trusted by the receiving server (match manifests live in MemoryStore).
	Error handling:   reserve: 3 attempts with backoff; teleport: single attempt (QueueService owns retry/requeue).
	Performance notes: N/A.
]]

local AdapterTypes = require("@game/ReplicatedStorage/Shared/Types/Adapters")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local Retry = require("./Retry")

type TeleportAdapter = AdapterTypes.TeleportAdapter

--- attempts: max tries per call (default 3; Players: 2). wait: backoff sleeper (default task.wait; tests inject).
export type Options = { attempts: number?, wait: ((seconds: number) -> ())? }

local RobloxTeleport = {}

function RobloxTeleport.new(options: Options?): TeleportAdapter
	local TeleportService = game:GetService("TeleportService")
	local retryOptions: Retry.RetryOptions = {
		attempts = if options and options.attempts then options.attempts else nil,
		wait = if options then options.wait else nil,
	}

	local adapter = {
		TeleportFailed = Signal.new() :: Signal.Signal<Player, string, string>,
	}

	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		adapter.TeleportFailed:Fire(player, result.Name, message)
	end)

	function adapter.reserveServerAsync(
		_self: TeleportAdapter,
		placeId: number
	): (boolean, AdapterTypes.ReservedServer | string)
		local ok, result = Retry.call(function(): AdapterTypes.ReservedServer
			local accessCode, privateServerId = TeleportService:ReserveServerAsync(placeId)
			if type(accessCode) ~= "string" or type(privateServerId) ~= "string" then
				error("ReserveServerAsync returned unexpected values")
			end
			return { accessCode = accessCode, privateServerId = privateServerId }
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		return true, result
	end

	function adapter.teleportAsync(
		_self: TeleportAdapter,
		placeId: number,
		players: { Player },
		spec: AdapterTypes.TeleportSpec?
	): (boolean, string?)
		local ok, err = pcall(function()
			local teleportOptions = Instance.new("TeleportOptions")
			if spec ~= nil then
				if spec.reservedServerAccessCode ~= nil then
					teleportOptions.ReservedServerAccessCode = spec.reservedServerAccessCode
				end
				if spec.teleportData ~= nil then
					teleportOptions:SetTeleportData(spec.teleportData)
				end
			end
			TeleportService:TeleportAsync(placeId, players, teleportOptions)
		end)
		if not ok then
			return false, tostring(err)
		end
		return true, nil
	end

	local conforming: TeleportAdapter = adapter -- type-checks every method against the interface
	return conforming
end

return RobloxTeleport
