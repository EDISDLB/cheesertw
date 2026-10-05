--[[
	MockMemoryStoreAdapter — in-memory MemoryStoreAdapter (sorted maps + hash maps) with TTL on an injected clock.

	Purpose:          Headless tests for queues, leader-election locks and match manifests.
	Dependencies:     FailureInjector, Serialization, Harness/FakeClock (or any Clock).
	State:            Per-map items { value, sortKey?, expiresAt }. Expired items are purged lazily on access.
	Validation:       Key 1..128 chars, TTL in (0, 3,888,000], value JSON <= 32 KB, sort key number or string
	                  (<= 128 chars); range count 1..200.
	Error handling:   (false, message) like the live adapter; never throws.
	Performance notes: Range queries sort the live items each call (test-only).

	Ordering (Roblox docs): numeric sort keys ascending, then string sort keys ascending, then items without a sort
	key; ties by key. Range bounds are exclusive; a bound with only `sortKey` excludes every item with that sort key.

	Test helpers: failNext(method, count?, message?), failAlways, clearFailures, simulateConflict(mapName, key, value,
	sortKey?) (next UpdateAsync on that key re-runs its transform after a competing write), peek(kind, map, key).
]]

local FailureInjector = require("./FailureInjector")
local Serialization = require("./Serialization")

local MAX_TTL = 3888000
local MAX_VALUE_BYTES = 32 * 1024

local MockMemoryStoreAdapter = {}
MockMemoryStoreAdapter.__index = MockMemoryStoreAdapter

local function validateKey(key: any): string?
	if type(key) ~= "string" or #key == 0 then
		return "MemoryStore key must be a non-empty string"
	end
	if #key > 128 then
		return "MemoryStore key exceeds 128 characters"
	end
	return nil
end

local function validateTtl(ttl: any): string?
	if type(ttl) ~= "number" or ttl ~= ttl or ttl <= 0 or ttl > MAX_TTL then
		return `MemoryStore expiration must be in (0, {MAX_TTL}] seconds`
	end
	return nil
end

local function validateValue(value: any): string?
	if value == nil then
		return "MemoryStore value cannot be nil"
	end
	local ok, err = Serialization.validate(value)
	if not ok then
		return `MemoryStore cannot store value ({err})`
	end
	if Serialization.jsonSize(value) > MAX_VALUE_BYTES then
		return "MemoryStore value exceeds 32 KB"
	end
	return nil
end

local function validateSortKey(sortKey: any): string?
	if sortKey == nil or type(sortKey) == "number" then
		if type(sortKey) == "number" and (sortKey ~= sortKey or math.abs(sortKey) == math.huge) then
			return "MemoryStore sort key must be finite"
		end
		return nil
	end
	if type(sortKey) == "string" then
		if #sortKey > 128 then
			return "MemoryStore sort key exceeds 128 characters"
		end
		return nil
	end
	return "MemoryStore sort key must be a number or string"
end

-- Ordering tuple: (class, sortKey, key). class 0 = numeric, 1 = string, 2 = none.
local function classOf(sortKey: any): number
	if type(sortKey) == "number" then
		return 0
	elseif type(sortKey) == "string" then
		return 1
	end
	return 2
end

-- Compares item/bound positions. keyInfinity: nil | -1 | 1 for bounds without key.
local function compare(
	aClass: number,
	aSort: any,
	aKey: string?,
	aInf: number?,
	bClass: number,
	bSort: any,
	bKey: string?,
	bInf: number?
): number
	if aClass ~= bClass then
		return if aClass < bClass then -1 else 1
	end
	if aClass ~= 2 and aSort ~= bSort then
		return if aSort < bSort then -1 else 1
	end
	if aInf ~= nil or bInf ~= nil then
		local av = aInf or 0
		local bv = bInf or 0
		if av ~= bv then
			return if av < bv then -1 else 1
		end
	end
	if aKey ~= nil and bKey ~= nil and aKey ~= bKey then
		return if aKey < bKey then -1 else 1
	end
	return 0
end

function MockMemoryStoreAdapter.new(options: { clock: any })
	assert(options and options.clock, "MockMemoryStoreAdapter.new requires { clock }")
	return setmetatable({
		_clock = options.clock,
		_sorted = {},
		_hash = {},
		_sortedHandles = {},
		_hashHandles = {},
		_conflicts = {},
		injector = FailureInjector.new(),
		transformCalls = 0,
	}, MockMemoryStoreAdapter)
end

local function purge(self: any, items: { [string]: any })
	local now = self._clock:now()
	for key, item in items do
		if item.expiresAt <= now then
			items[key] = nil
		end
	end
end

local function itemsOf(self: any, kind: string, name: string): { [string]: any }
	local bucket = if kind == "sorted" then self._sorted else self._hash
	local items = bucket[name]
	if items == nil then
		items = {}
		bucket[name] = items
	end
	purge(self, items)
	return items
end

local function runTransform(self: any, transform: (...any) -> ...any, ...: any): (boolean, any, any)
	self.transformCalls += 1
	local args = table.pack(...)
	local co = coroutine.create(function()
		return transform(table.unpack(args, 1, args.n))
	end)
	local results = table.pack(coroutine.resume(co))
	if coroutine.status(co) ~= "dead" then
		coroutine.close(co)
		return false, "MemoryStore transform function cannot yield", nil
	end
	if not results[1] then
		return false, `MemoryStore transform error: {tostring(results[2])}`, nil
	end
	return true, results[2], results[3]
end

-- Sorted map handle -------------------------------------------------------------

local SortedHandle = {}
SortedHandle.__index = SortedHandle

function SortedHandle.getAsync(self: any, key: string): (boolean, any, any)
	local adapter = self._adapter
	local err = validateKey(key) or adapter.injector:check("getAsync")
	if err then
		return false, err
	end
	local item = itemsOf(adapter, "sorted", self._name)[key]
	if item == nil then
		return true, nil, nil
	end
	return true, Serialization.copy(item.value), item.sortKey
end

function SortedHandle.setAsync(self: any, key: string, value: any, ttl: number, sortKey: any): (boolean, any)
	local adapter = self._adapter
	local err = validateKey(key)
		or validateValue(value)
		or validateTtl(ttl)
		or validateSortKey(sortKey)
		or adapter.injector:check("setAsync")
	if err then
		return false, err
	end
	local items = itemsOf(adapter, "sorted", self._name)
	local existed = items[key] ~= nil
	items[key] = { value = Serialization.copy(value), sortKey = sortKey, expiresAt = adapter._clock:now() + ttl }
	return true, existed
end

function SortedHandle.updateAsync(
	self: any,
	key: string,
	transform: (any, any) -> (any, any),
	ttl: number
): (boolean, any, any)
	local adapter = self._adapter
	local err = validateKey(key) or validateTtl(ttl) or adapter.injector:check("updateAsync")
	if err then
		return false, err
	end
	local items = itemsOf(adapter, "sorted", self._name)
	local current = items[key]
	local ok, newValue, newSortKey = runTransform(
		adapter,
		transform,
		if current then Serialization.copy(current.value) else nil,
		if current then current.sortKey else nil
	)
	if not ok then
		return false, newValue
	end
	local conflictKey = "sorted\0" .. self._name .. "\0" .. key
	local conflict = adapter._conflicts[conflictKey]
	if conflict ~= nil and newValue ~= nil then
		adapter._conflicts[conflictKey] = nil
		items[key] = {
			value = Serialization.copy(conflict.value),
			sortKey = conflict.sortKey,
			expiresAt = adapter._clock:now() + ttl,
		}
		ok, newValue, newSortKey =
			runTransform(adapter, transform, Serialization.copy(conflict.value), conflict.sortKey)
		if not ok then
			return false, newValue
		end
	end
	if newValue == nil then
		return true, nil, nil
	end
	local valueErr = validateValue(newValue) or validateSortKey(newSortKey)
	if valueErr then
		return false, valueErr
	end
	items[key] = { value = Serialization.copy(newValue), sortKey = newSortKey, expiresAt = adapter._clock:now() + ttl }
	return true, Serialization.copy(newValue), newSortKey
end

function SortedHandle.removeAsync(self: any, key: string): (boolean, string?)
	local adapter = self._adapter
	local err = validateKey(key) or adapter.injector:check("removeAsync")
	if err then
		return false, err
	end
	itemsOf(adapter, "sorted", self._name)[key] = nil
	return true, nil
end

function SortedHandle.getRangeAsync(self: any, direction: string, count: number, lower: any, upper: any): (boolean, any)
	local adapter = self._adapter
	if direction ~= "Ascending" and direction ~= "Descending" then
		return false, "direction must be Ascending or Descending"
	end
	if type(count) ~= "number" or count < 1 or count > 200 or count ~= math.floor(count) then
		return false, "count must be an integer in [1, 200]"
	end
	local err = adapter.injector:check("getRangeAsync")
	if err then
		return false, err
	end
	local list = {}
	for key, item in itemsOf(adapter, "sorted", self._name) do
		table.insert(list, { key = key, item = item })
	end
	table.sort(list, function(a, b)
		return compare(
			classOf(a.item.sortKey),
			a.item.sortKey,
			a.key,
			nil,
			classOf(b.item.sortKey),
			b.item.sortKey,
			b.key,
			nil
		) < 0
	end)
	local function afterLower(entry: any): boolean
		if lower == nil then
			return true
		end
		local inf = if lower.key == nil then 1 else nil
		local boundClass = classOf(lower.sortKey)
		return compare(
			classOf(entry.item.sortKey),
			entry.item.sortKey,
			entry.key,
			nil,
			boundClass,
			lower.sortKey,
			lower.key,
			inf
		) > 0
	end
	local function beforeUpper(entry: any): boolean
		if upper == nil then
			return true
		end
		local inf = if upper.key == nil then -1 else nil
		local boundClass = classOf(upper.sortKey)
		return compare(
			classOf(entry.item.sortKey),
			entry.item.sortKey,
			entry.key,
			nil,
			boundClass,
			upper.sortKey,
			upper.key,
			inf
		) < 0
	end
	local out = {}
	local first, last, stepBy = 1, #list, 1
	if direction == "Descending" then
		first, last, stepBy = #list, 1, -1
	end
	for i = first, last, stepBy do
		local entry = list[i]
		if afterLower(entry) and beforeUpper(entry) then
			table.insert(
				out,
				{ key = entry.key, value = Serialization.copy(entry.item.value), sortKey = entry.item.sortKey }
			)
			if #out >= count then
				break
			end
		end
	end
	return true, out
end

function SortedHandle.getSizeAsync(self: any): (boolean, any)
	local err = self._adapter.injector:check("getSizeAsync")
	if err then
		return false, err
	end
	local n = 0
	for _ in itemsOf(self._adapter, "sorted", self._name) do
		n += 1
	end
	return true, n
end

-- Hash map handle ---------------------------------------------------------------

local HashHandle = {}
HashHandle.__index = HashHandle

function HashHandle.getAsync(self: any, key: string): (boolean, any)
	local adapter = self._adapter
	local err = validateKey(key) or adapter.injector:check("getAsync")
	if err then
		return false, err
	end
	local item = itemsOf(adapter, "hash", self._name)[key]
	return true, if item then Serialization.copy(item.value) else nil
end

function HashHandle.setAsync(self: any, key: string, value: any, ttl: number): (boolean, any)
	local adapter = self._adapter
	local err = validateKey(key) or validateValue(value) or validateTtl(ttl) or adapter.injector:check("setAsync")
	if err then
		return false, err
	end
	local items = itemsOf(adapter, "hash", self._name)
	local existed = items[key] ~= nil
	items[key] = { value = Serialization.copy(value), expiresAt = adapter._clock:now() + ttl }
	return true, existed
end

function HashHandle.updateAsync(self: any, key: string, transform: (any) -> any, ttl: number): (boolean, any)
	local adapter = self._adapter
	local err = validateKey(key) or validateTtl(ttl) or adapter.injector:check("updateAsync")
	if err then
		return false, err
	end
	local items = itemsOf(adapter, "hash", self._name)
	local current = items[key]
	local ok, newValue = runTransform(adapter, transform, if current then Serialization.copy(current.value) else nil)
	if not ok then
		return false, newValue
	end
	local conflictKey = "hash\0" .. self._name .. "\0" .. key
	local conflict = adapter._conflicts[conflictKey]
	if conflict ~= nil and newValue ~= nil then
		adapter._conflicts[conflictKey] = nil
		items[key] = { value = Serialization.copy(conflict.value), expiresAt = adapter._clock:now() + ttl }
		ok, newValue = runTransform(adapter, transform, Serialization.copy(conflict.value))
		if not ok then
			return false, newValue
		end
	end
	if newValue == nil then
		return true, nil
	end
	local valueErr = validateValue(newValue)
	if valueErr then
		return false, valueErr
	end
	items[key] = { value = Serialization.copy(newValue), expiresAt = adapter._clock:now() + ttl }
	return true, Serialization.copy(newValue)
end

function HashHandle.removeAsync(self: any, key: string): (boolean, string?)
	local adapter = self._adapter
	local err = validateKey(key) or adapter.injector:check("removeAsync")
	if err then
		return false, err
	end
	itemsOf(adapter, "hash", self._name)[key] = nil
	return true, nil
end

function HashHandle.listItemsAsync(self: any, limit: number): (boolean, any)
	local adapter = self._adapter
	if type(limit) ~= "number" or limit < 1 or limit > 200 then
		return false, "count must be in [1, 200]"
	end
	local err = adapter.injector:check("listItemsAsync")
	if err then
		return false, err
	end
	local keys = {}
	for key in itemsOf(adapter, "hash", self._name) do
		table.insert(keys, key)
	end
	table.sort(keys)
	local out = {}
	local items = itemsOf(adapter, "hash", self._name)
	for i = 1, math.min(limit, #keys) do
		table.insert(out, { key = keys[i], value = Serialization.copy(items[keys[i]].value) })
	end
	return true, out
end

-- Adapter -----------------------------------------------------------------------

function MockMemoryStoreAdapter.getSortedMap(self: any, name: string): any
	local handle = self._sortedHandles[name]
	if handle == nil then
		handle = setmetatable({ _adapter = self, _name = name }, SortedHandle)
		self._sortedHandles[name] = handle
	end
	return handle
end

function MockMemoryStoreAdapter.getHashMap(self: any, name: string): any
	local handle = self._hashHandles[name]
	if handle == nil then
		handle = setmetatable({ _adapter = self, _name = name }, HashHandle)
		self._hashHandles[name] = handle
	end
	return handle
end

function MockMemoryStoreAdapter.failNext(self: any, method: string, count: number?, message: string?)
	self.injector:failNext(method, count, message or `MemoryStore request failed (injected, {method})`)
end

function MockMemoryStoreAdapter.failAlways(self: any, method: string, message: string?)
	self.injector:failAlways(method, message or `MemoryStore request failed (injected, {method})`)
end

function MockMemoryStoreAdapter.clearFailures(self: any)
	self.injector:clear()
end

--- kind: "sorted" | "hash"
function MockMemoryStoreAdapter.simulateConflict(
	self: any,
	kind: string,
	mapName: string,
	key: string,
	value: any,
	sortKey: any
)
	self._conflicts[kind .. "\0" .. mapName .. "\0" .. key] = { value = Serialization.copy(value), sortKey = sortKey }
end

--- Raw item (after TTL purge) or nil: { value, sortKey?, expiresAt }.
function MockMemoryStoreAdapter.peek(self: any, kind: string, mapName: string, key: string): any
	local item = itemsOf(self, kind, mapName)[key]
	if item == nil then
		return nil
	end
	return { value = Serialization.copy(item.value), sortKey = item.sortKey, expiresAt = item.expiresAt }
end

return MockMemoryStoreAdapter
