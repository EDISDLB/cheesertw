--[[
	MockDataStoreAdapter — in-memory DataStoreAdapter with Roblox semantics and failure injection.

	Purpose:          Headless tests for DataService & co: GetAsync/SetAsync/UpdateAsync/RemoveAsync/IncrementAsync,
	                  version history, request budgets, Roblox-style error codes, conflicting concurrent writes.
	Dependencies:     FailureInjector, Serialization, Core/Clock (timestamps).
	State:            stores[store][key] = { value, version, createdTime, updatedTime, userIds, metadata, history }.
	Validation:       Key/store names 1..50 chars (101/102), storable values only (104), JSON size <= 4 MB (105),
	                  UpdateAsync transforms must not yield.
	Error handling:   Returns (false, "CODE: message") like the live adapter; never throws.
	Performance notes: Deep copies on every read/write (values are never aliased with caller tables).

	Test helpers: failNext/failAlways/clearFailures, setBudget(kind, n), seed(store, key, value), peek(store, key),
	injectConcurrentWrite(store, key, value) (next UpdateAsync on that key sees a conflict and re-runs its transform),
	transformCalls (count of transform invocations), injector.calls (call log).
]]

local FailureInjector = require("./FailureInjector")
local Serialization = require("./Serialization")
local Clock = require("@game/ReplicatedStorage/Shared/Core/Clock")

local MAX_BYTES = 4194304

local MockDataStoreAdapter = {}
MockDataStoreAdapter.__index = MockDataStoreAdapter

local KIND_BY_METHOD = {
	getAsync = { "Get" },
	setAsync = { "Set" },
	updateAsync = { "Get", "Set" },
	removeAsync = { "Set" },
	incrementAsync = { "Set" },
	listVersionsAsync = { "List" },
	getVersionAsync = { "GetVersion" },
}

local THROTTLE_CODES = { Get = 301, Set = 302, List = 305, GetVersion = 306 }

function MockDataStoreAdapter.new(options: { clock: any? }?)
	local opts = options or {}
	return setmetatable({
		_clock = opts.clock or Clock.fake(1.7e9),
		_stores = {},
		_budgets = { Get = math.huge, Set = math.huge, List = math.huge, GetVersion = math.huge },
		_versionCounter = 0,
		_conflicts = {},
		injector = FailureInjector.new(),
		transformCalls = 0,
	}, MockDataStoreAdapter)
end

local function nowMs(self: any): number
	return math.floor(self._clock:now() * 1000)
end

local function validateKey(store: string, key: string): string?
	if type(store) ~= "string" or #store == 0 or #store > 50 then
		return "102: DataStore name must be 1-50 characters."
	end
	if type(key) ~= "string" or #key == 0 then
		return "101: Key name can't be empty."
	end
	if #key > 50 then
		return "102: Key name exceeds the 50 character limit."
	end
	return nil
end

local function validateValue(value: any): string?
	local ok, err = Serialization.validate(value)
	if not ok then
		return `104: Cannot store value in DataStore ({err})`
	end
	if Serialization.jsonSize(value) > MAX_BYTES then
		return "105: Serialized value exceeds 4MB limit."
	end
	return nil
end

-- Consumes budget + injected failures; returns an error message or nil.
local function precheck(self: any, method: string): string?
	local injected = self.injector:check(method)
	if injected ~= nil then
		return injected
	end
	for _, kind in KIND_BY_METHOD[method] do
		if self._budgets[kind] < 1 then
			return `{THROTTLE_CODES[kind] or 304}: {method} request dropped. Request was throttled, but throttled request queue was full.`
		end
	end
	for _, kind in KIND_BY_METHOD[method] do
		self._budgets[kind] -= 1
	end
	return nil
end

local function entryFor(self: any, store: string, key: string)
	local s = self._stores[store]
	return if s then s[key] else nil
end

local function keyInfo(entry: any)
	if entry == nil then
		return nil
	end
	return {
		version = entry.version,
		createdTime = entry.createdTime,
		updatedTime = entry.updatedTime,
		userIds = table.clone(entry.userIds),
		metadata = table.clone(entry.metadata),
	}
end

local function write(
	self: any,
	store: string,
	key: string,
	value: any,
	userIds: { number }?,
	metadata: { [string]: any }?
)
	self._stores[store] = self._stores[store] or {}
	local entry = self._stores[store][key]
	self._versionCounter += 1
	local version = string.format("v%08d", self._versionCounter)
	local now = nowMs(self)
	if entry == nil then
		entry = { createdTime = now, history = {} }
		self._stores[store][key] = entry
	end
	entry.value = Serialization.copy(value)
	entry.version = version
	entry.updatedTime = now
	entry.userIds = if userIds then table.clone(userIds) else {}
	entry.metadata = if metadata then table.clone(metadata) else {}
	entry.deleted = false
	table.insert(
		entry.history,
		{ version = version, createdTime = now, value = Serialization.copy(value), isDeleted = false }
	)
	return entry
end

function MockDataStoreAdapter.getAsync(self: any, store: string, key: string): (boolean, any, any)
	local err = validateKey(store, key) or precheck(self, "getAsync")
	if err then
		return false, err
	end
	local entry = entryFor(self, store, key)
	if entry == nil or entry.deleted then
		return true, nil, nil
	end
	return true, Serialization.copy(entry.value), keyInfo(entry)
end

function MockDataStoreAdapter.setAsync(
	self: any,
	store: string,
	key: string,
	value: any,
	userIds: { number }?,
	metadata: { [string]: any }?
): (boolean, any)
	local err = validateKey(store, key) or validateValue(value) or precheck(self, "setAsync")
	if err then
		return false, err
	end
	local entry = write(self, store, key, value, userIds, metadata)
	return true, entry.version
end

function MockDataStoreAdapter.updateAsync(
	self: any,
	store: string,
	key: string,
	transform: (any, any) -> (any, any, any)
): (boolean, any, any)
	local err = validateKey(store, key) or precheck(self, "updateAsync")
	if err then
		return false, err
	end
	local function runTransform(entry: any): (boolean, any, any, any, any)
		self.transformCalls += 1
		local current = if entry and not entry.deleted then Serialization.copy(entry.value) else nil
		local info = if entry and not entry.deleted then keyInfo(entry) else nil
		local co = coroutine.create(function()
			return transform(current, info)
		end)
		local results = table.pack(coroutine.resume(co))
		if coroutine.status(co) ~= "dead" then
			coroutine.close(co)
			return false, "UpdateAsync callback function cannot yield"
		end
		if not results[1] then
			return false, `UpdateAsync transform error: {tostring(results[2])}`
		end
		return true, results[2], results[3], results[4], nil
	end

	local entry = entryFor(self, store, key)
	local ok, newValue, userIds, metadata = runTransform(entry)
	if not ok then
		return false, newValue
	end
	local conflictKey = store .. "\0" .. key
	local conflict = self._conflicts[conflictKey]
	if conflict ~= nil and newValue ~= nil then
		-- Another server committed first: store its value, then Roblox re-runs the transform on the new value.
		self._conflicts[conflictKey] = nil
		write(self, store, key, conflict.value, nil, nil)
		entry = entryFor(self, store, key)
		ok, newValue, userIds, metadata = runTransform(entry)
		if not ok then
			return false, newValue
		end
	end
	if newValue == nil then
		return true, nil, nil
	end
	local valueErr = validateValue(newValue)
	if valueErr then
		return false, valueErr
	end
	local written = write(self, store, key, newValue, userIds, metadata)
	return true, Serialization.copy(written.value), keyInfo(written)
end

function MockDataStoreAdapter.removeAsync(self: any, store: string, key: string): (boolean, any)
	local err = validateKey(store, key) or precheck(self, "removeAsync")
	if err then
		return false, err
	end
	local entry = entryFor(self, store, key)
	if entry == nil or entry.deleted then
		return true, nil
	end
	local previous = Serialization.copy(entry.value)
	self._versionCounter += 1
	local version = string.format("v%08d", self._versionCounter)
	entry.deleted = true
	entry.value = nil
	entry.version = version
	table.insert(entry.history, { version = version, createdTime = nowMs(self), value = nil, isDeleted = true })
	return true, previous
end

function MockDataStoreAdapter.incrementAsync(self: any, store: string, key: string, delta: number): (boolean, any)
	local err = validateKey(store, key) or precheck(self, "incrementAsync")
	if err then
		return false, err
	end
	if type(delta) ~= "number" or delta ~= math.floor(delta) then
		return false, "103: IncrementAsync delta must be an integer"
	end
	local entry = entryFor(self, store, key)
	local current = if entry and not entry.deleted then entry.value else 0
	if type(current) ~= "number" then
		return false, "103: Cannot increment a non-numeric value"
	end
	local written = write(self, store, key, current + delta, if entry then entry.userIds else nil, nil)
	return true, written.value
end

function MockDataStoreAdapter.listVersionsAsync(self: any, store: string, key: string, limit: number?): (boolean, any)
	local err = validateKey(store, key) or precheck(self, "listVersionsAsync")
	if err then
		return false, err
	end
	local entry = entryFor(self, store, key)
	local out = {}
	if entry ~= nil then
		for i = #entry.history, 1, -1 do
			local h = entry.history[i]
			table.insert(out, { version = h.version, createdTime = h.createdTime, isDeleted = h.isDeleted })
			if #out >= (limit or 20) then
				break
			end
		end
	end
	return true, out
end

function MockDataStoreAdapter.getVersionAsync(self: any, store: string, key: string, version: string): (boolean, any)
	local err = validateKey(store, key) or precheck(self, "getVersionAsync")
	if err then
		return false, err
	end
	local entry = entryFor(self, store, key)
	if entry ~= nil then
		for _, h in entry.history do
			if h.version == version then
				return true, Serialization.copy(h.value)
			end
		end
	end
	return true, nil
end

function MockDataStoreAdapter.getRequestBudget(self: any, kind: string): number
	if kind == "Update" then
		return math.min(self._budgets.Get, self._budgets.Set)
	elseif kind == "Remove" then
		return self._budgets.Set
	end
	return self._budgets[kind] or 0
end

-- Test helpers ------------------------------------------------------------------

function MockDataStoreAdapter.setBudget(self: any, kind: string, n: number)
	if kind == "Update" then
		self._budgets.Get = n
		self._budgets.Set = n
	elseif kind == "Remove" then
		self._budgets.Set = n
	else
		self._budgets[kind] = n
	end
end

function MockDataStoreAdapter.failNext(self: any, method: string, count: number?, message: string?)
	self.injector:failNext(method, count, message or `502: API Services rejected request (injected, {method})`)
end

function MockDataStoreAdapter.failAlways(self: any, method: string, message: string?)
	self.injector:failAlways(method, message or `502: API Services rejected request (injected, {method})`)
end

function MockDataStoreAdapter.clearFailures(self: any)
	self.injector:clear()
end

function MockDataStoreAdapter.seed(self: any, store: string, key: string, value: any)
	write(self, store, key, value, nil, nil)
end

function MockDataStoreAdapter.peek(self: any, store: string, key: string): any
	local entry = entryFor(self, store, key)
	if entry == nil or entry.deleted then
		return nil
	end
	return Serialization.copy(entry.value)
end

function MockDataStoreAdapter.injectConcurrentWrite(self: any, store: string, key: string, value: any)
	self._conflicts[store .. "\0" .. key] = { value = Serialization.copy(value) }
end

return MockDataStoreAdapter
