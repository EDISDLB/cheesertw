--[[
	MockMessagingAdapter — in-memory MessagingAdapter; several adapters can share a bus to simulate servers.

	Purpose:          Cross-server pub/sub in tests (hub <-> matchmaker notifications).
	Dependencies:     FailureInjector, Serialization, Core/Clock.
	State:            Bus: subscribers per topic, deferred queue; adapter: published log.
	Validation:       Topic 1..80 chars; message storable and <= 1 KB JSON (Roblox limits).
	Error handling:   (false, message) like the live adapter. Subscriber errors are caught (like Roblox) and
	                  recorded in bus.errors.
	Performance notes: Test-only.

	Usage: local bus = MockMessagingAdapter.newBus({ deferred = true }); local a = MockMessagingAdapter.new({ bus = bus })
	       Deferred buses deliver on bus:flush(); immediate buses deliver inside publishAsync. Publishers also
	       receive their own messages (as on Roblox).
]]

local FailureInjector = require("./FailureInjector")
local Serialization = require("./Serialization")
local Clock = require("@game/ReplicatedStorage/Shared/Core/Clock")

local MAX_MESSAGE_BYTES = 1024

local MockMessagingAdapter = {}
MockMessagingAdapter.__index = MockMessagingAdapter

local Bus = {}
Bus.__index = Bus

function MockMessagingAdapter.newBus(options: { deferred: boolean?, clock: any? }?)
	local opts = options or {}
	return setmetatable({
		_subscribers = {},
		_queue = {},
		_deferred = opts.deferred == true,
		_clock = opts.clock or Clock.fake(1.7e9),
		errors = {},
		delivered = 0,
	}, Bus)
end

local function deliver(bus: any, topic: string, message: any, sentAt: number)
	for _, sub in table.clone(bus._subscribers[topic] or {}) do
		if sub.connected then
			local ok, err = pcall(sub.callback, Serialization.copy(message), sentAt)
			bus.delivered += 1
			if not ok then
				table.insert(bus.errors, tostring(err))
			end
		end
	end
end

--- Delivers queued messages (deferred buses). Returns how many messages were delivered.
function Bus.flush(self: any): number
	local count = 0
	while #self._queue > 0 do
		local item = table.remove(self._queue, 1)
		deliver(self, item.topic, item.message, item.sentAt)
		count += 1
	end
	return count
end

function Bus.pending(self: any): number
	return #self._queue
end

function MockMessagingAdapter.new(options: { bus: any? }?)
	local opts = options or {}
	return setmetatable({
		bus = opts.bus or MockMessagingAdapter.newBus(),
		published = {},
		injector = FailureInjector.new(),
	}, MockMessagingAdapter)
end

function MockMessagingAdapter.publishAsync(self: any, topic: string, message: any): (boolean, string?)
	if type(topic) ~= "string" or #topic == 0 or #topic > 80 then
		return false, "MessagingService topic must be 1-80 characters"
	end
	local ok, err = Serialization.validate(message)
	if not ok then
		return false, `MessagingService cannot send value ({err})`
	end
	if Serialization.jsonSize(message) > MAX_MESSAGE_BYTES then
		return false, "MessagingService message exceeds 1 KB"
	end
	local injected = self.injector:check("publishAsync")
	if injected then
		return false, injected
	end
	local copy = Serialization.copy(message)
	table.insert(self.published, { topic = topic, message = copy })
	local sentAt = self.bus._clock:now()
	if self.bus._deferred then
		table.insert(self.bus._queue, { topic = topic, message = copy, sentAt = sentAt })
	else
		deliver(self.bus, topic, copy, sentAt)
	end
	return true, nil
end

function MockMessagingAdapter.subscribeAsync(self: any, topic: string, callback: (any, number) -> ()): (boolean, any)
	if type(topic) ~= "string" or #topic == 0 or #topic > 80 then
		return false, "MessagingService topic must be 1-80 characters"
	end
	local injected = self.injector:check("subscribeAsync")
	if injected then
		return false, injected
	end
	local subs = self.bus._subscribers[topic]
	if subs == nil then
		subs = {}
		self.bus._subscribers[topic] = subs
	end
	local sub = { callback = callback, connected = true }
	table.insert(subs, sub)
	local connection = { Connected = true }
	function connection.Disconnect(conn: any)
		if conn.Connected then
			conn.Connected = false
			sub.connected = false
			local index = table.find(subs, sub)
			if index then
				table.remove(subs, index)
			end
		end
	end
	return true, connection
end

function MockMessagingAdapter.failNext(self: any, method: string, count: number?, message: string?)
	self.injector:failNext(method, count, message)
end

function MockMessagingAdapter.failAlways(self: any, method: string, message: string?)
	self.injector:failAlways(method, message)
end

function MockMessagingAdapter.clearFailures(self: any)
	self.injector:clear()
end

return MockMessagingAdapter
