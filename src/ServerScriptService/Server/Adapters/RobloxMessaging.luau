--!strict
--[[
	RobloxMessaging — MessagingAdapter over MessagingService (cross-server pub/sub).

	Purpose:          Hub <-> matchmaker notifications (ARCHITECTURE §8).
	Dependencies:     MessagingService, Adapters/Retry, Core/Log, Types/Adapters, Types/Core.
	State:            None (subscriptions are owned by the returned connections).
	Validation:       Roblox enforces topic (80 chars) and message (1 KB) limits; errors returned.
	Error handling:   publish: 3 attempts with backoff. Subscriber callback errors are caught and logged so one bad
	                  message cannot kill the subscription.
	Performance notes: Delivery is asynchronous and best-effort (Roblox does not guarantee delivery).
]]

local AdapterTypes = require("@game/ReplicatedStorage/Shared/Types/Adapters")
local CoreTypes = require("@game/ReplicatedStorage/Shared/Types/Core")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")
local Retry = require("./Retry")

type MessagingAdapter = AdapterTypes.MessagingAdapter
type Connection = CoreTypes.Connection

--- attempts: max tries per call (default 3; Players: 2). wait: backoff sleeper (default task.wait; tests inject).
export type Options = { attempts: number?, wait: ((seconds: number) -> ())? }

local log = Log.scope("RobloxMessaging")

local RobloxMessaging = {}

function RobloxMessaging.new(options: Options?): MessagingAdapter
	local MessagingService = game:GetService("MessagingService")
	local retryOptions: Retry.RetryOptions = {
		attempts = if options and options.attempts then options.attempts else nil,
		wait = if options then options.wait else nil,
	}

	local adapter = {}

	function adapter.publishAsync(_self: MessagingAdapter, topic: string, message: any): (boolean, string?)
		local ok, result = Retry.call(function()
			MessagingService:PublishAsync(topic, message)
			return true
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		return true, nil
	end

	function adapter.subscribeAsync(
		_self: MessagingAdapter,
		topic: string,
		callback: (message: any, sentAt: number) -> ()
	): (boolean, Connection | string)
		local ok, result = Retry.call(function()
			return MessagingService:SubscribeAsync(topic, function(payload: any)
				local data = if type(payload) == "table" then payload.Data else nil
				local sent = if type(payload) == "table" and type(payload.Sent) == "number" then payload.Sent else 0
				local callbackOk, err = pcall(callback :: any, data, sent)
				if not callbackOk then
					log:error("subscriber for %s failed: %s", topic, tostring(err))
				end
			end)
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		local rbxConnection = result :: RBXScriptConnection
		local connection = { Connected = true }
		function connection.Disconnect(self: any)
			if self.Connected then
				self.Connected = false
				rbxConnection:Disconnect()
			end
		end
		return true, (connection :: any) :: Connection
	end

	local conforming: MessagingAdapter = adapter -- type-checks every method against the interface
	return conforming
end

return RobloxMessaging
