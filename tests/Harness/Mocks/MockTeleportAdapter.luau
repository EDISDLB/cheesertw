--[[
	MockTeleportAdapter — records reservations/teleports and simulates TeleportInitFailed.

	Purpose:          Matchmaking/battle handoff tests without TeleportService.
	Dependencies:     FailureInjector, Core/Signal.
	State:            reservations { placeId, accessCode, privateServerId }, teleports { placeId, userIds, spec }.
	Validation:       teleportAsync requires a non-empty player list and a positive placeId.
	Error handling:   Injected failures return (false, message); simulateTeleportFailure fires TeleportFailed later.
	Performance notes: Test-only.
]]

local FailureInjector = require("./FailureInjector")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

local MockTeleportAdapter = {}
MockTeleportAdapter.__index = MockTeleportAdapter

function MockTeleportAdapter.new()
	return setmetatable({
		TeleportFailed = Signal.new(),
		reservations = {},
		teleports = {},
		injector = FailureInjector.new(),
		_counter = 0,
	}, MockTeleportAdapter)
end

function MockTeleportAdapter.reserveServerAsync(self: any, placeId: number): (boolean, any)
	local injected = self.injector:check("reserveServerAsync")
	if injected then
		return false, injected
	end
	self._counter += 1
	local reserved = {
		accessCode = string.format("access-%04d", self._counter),
		privateServerId = string.format("ps-%04d", self._counter),
	}
	table.insert(
		self.reservations,
		{ placeId = placeId, accessCode = reserved.accessCode, privateServerId = reserved.privateServerId }
	)
	return true, reserved
end

function MockTeleportAdapter.teleportAsync(self: any, placeId: number, players: { any }, spec: any): (boolean, string?)
	if type(placeId) ~= "number" or placeId <= 0 then
		return false, "TeleportAsync: invalid placeId"
	end
	if type(players) ~= "table" or #players == 0 then
		return false, "TeleportAsync: players list is empty"
	end
	local injected = self.injector:check("teleportAsync")
	if injected then
		return false, injected
	end
	local userIds = {}
	for _, player in players do
		table.insert(userIds, player.UserId)
	end
	table.insert(self.teleports, { placeId = placeId, userIds = userIds, players = table.clone(players), spec = spec })
	return true, nil
end

--- Fires TeleportFailed(player, result, message) as TeleportInitFailed would.
function MockTeleportAdapter.simulateTeleportFailure(self: any, player: any, result: string?, message: string?)
	self.TeleportFailed:Fire(player, result or "Failure", message or "simulated teleport failure")
end

function MockTeleportAdapter.failNext(self: any, method: string, count: number?, message: string?)
	self.injector:failNext(method, count, message)
end

function MockTeleportAdapter.failAlways(self: any, method: string, message: string?)
	self.injector:failAlways(method, message)
end

function MockTeleportAdapter.clearFailures(self: any)
	self.injector:clear()
end

return MockTeleportAdapter
