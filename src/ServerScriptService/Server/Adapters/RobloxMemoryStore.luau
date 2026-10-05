--!strict
--[[
	RobloxMemoryStore — MemoryStoreAdapter over MemoryStoreService sorted maps and hash maps.

	Purpose:          Matchmaking tickets, leader-election locks and match manifests (ARCHITECTURE §2.1, §8).
	Dependencies:     MemoryStoreService, Adapters/Retry, Types/Adapters.
	State:            Cached map handles by name.
	Validation:       Roblox enforces key (128 chars), value (32 KB) and TTL (<= 3,888,000 s) limits; errors returned.
	Error handling:   (false, message) on failure; transient failures retried (3 attempts, backoff).
	Performance notes: One handle object per map name.
]]

local AdapterTypes = require("@game/ReplicatedStorage/Shared/Types/Adapters")
local Retry = require("./Retry")

type MemoryStoreAdapter = AdapterTypes.MemoryStoreAdapter
type MemorySortedMap = AdapterTypes.MemorySortedMap
type MemoryHashMap = AdapterTypes.MemoryHashMap
type SortKey = AdapterTypes.SortKey

--- attempts: max tries per call (default 3; Players: 2). wait: backoff sleeper (default task.wait; tests inject).
export type Options = { attempts: number?, wait: ((seconds: number) -> ())? }

local RobloxMemoryStore = {}

local function sortedMapHandle(map: MemoryStoreSortedMap, retryOptions: Retry.RetryOptions): MemorySortedMap
	local handle = {}

	function handle.getAsync(_self: MemorySortedMap, key: string): (boolean, any, SortKey?)
		local ok, result = Retry.call(function()
			local value, sortKey = map:GetAsync(key)
			return { value = value, sortKey = sortKey }
		end, retryOptions)
		if not ok then
			return false, result
		end
		local packed = result :: { value: any, sortKey: SortKey? }
		return true, packed.value, packed.sortKey
	end

	function handle.setAsync(
		_self: MemorySortedMap,
		key: string,
		value: any,
		ttl: number,
		sortKey: SortKey?
	): (boolean, any)
		return Retry.call(function()
			return map:SetAsync(key, value, ttl, sortKey)
		end, retryOptions)
	end

	function handle.updateAsync(
		_self: MemorySortedMap,
		key: string,
		transform: (value: any, sortKey: SortKey?) -> (any, SortKey?),
		ttl: number
	): (boolean, any, SortKey?)
		local ok, result = Retry.call(function()
			local value, sortKey = map:UpdateAsync(key, function(old: any, oldSortKey: any)
				return transform(old, oldSortKey)
			end, ttl)
			return { value = value, sortKey = sortKey }
		end, retryOptions)
		if not ok then
			return false, result
		end
		local packed = result :: { value: any, sortKey: SortKey? }
		return true, packed.value, packed.sortKey
	end

	function handle.removeAsync(_self: MemorySortedMap, key: string): (boolean, string?)
		local ok, result = Retry.call(function()
			map:RemoveAsync(key)
			return true
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		return true, nil
	end

	function handle.getRangeAsync(
		_self: MemorySortedMap,
		direction: AdapterTypes.SortDirection,
		count: number,
		lower: AdapterTypes.SortedMapBound?,
		upper: AdapterTypes.SortedMapBound?
	): (boolean, { AdapterTypes.SortedMapItem } | string)
		local enumDirection = if direction == "Descending"
			then Enum.SortDirection.Descending
			else Enum.SortDirection.Ascending
		local ok, result = Retry.call(function()
			local items = map:GetRangeAsync(enumDirection, math.clamp(count, 1, 200), lower, upper)
			local out: { AdapterTypes.SortedMapItem } = {}
			for _, item in items do
				table.insert(out, { key = item.key, value = item.value, sortKey = item.sortKey })
			end
			return out
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		return true, result
	end

	function handle.getSizeAsync(_self: MemorySortedMap): (boolean, number | string)
		return Retry.call(function()
			return map:GetSizeAsync()
		end, retryOptions)
	end

	local conforming: MemorySortedMap = handle -- type-checks every method against the interface
	return conforming
end

local function hashMapHandle(map: MemoryStoreHashMap, retryOptions: Retry.RetryOptions): MemoryHashMap
	local handle = {}

	function handle.getAsync(_self: MemoryHashMap, key: string): (boolean, any)
		return Retry.call(function()
			return map:GetAsync(key)
		end, retryOptions)
	end

	function handle.setAsync(_self: MemoryHashMap, key: string, value: any, ttl: number): (boolean, any)
		return Retry.call(function()
			return map:SetAsync(key, value, ttl)
		end, retryOptions)
	end

	function handle.updateAsync(
		_self: MemoryHashMap,
		key: string,
		transform: (value: any) -> any,
		ttl: number
	): (boolean, any)
		return Retry.call(function()
			return map:UpdateAsync(key, function(old: any)
				return transform(old)
			end, ttl)
		end, retryOptions)
	end

	function handle.removeAsync(_self: MemoryHashMap, key: string): (boolean, string?)
		local ok, result = Retry.call(function()
			map:RemoveAsync(key)
			return true
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		return true, nil
	end

	function handle.listItemsAsync(
		_self: MemoryHashMap,
		limit: number
	): (boolean, { AdapterTypes.HashMapItem } | string)
		local ok, result = Retry.call(function()
			local pages = map:ListItemsAsync(math.clamp(limit, 1, 200))
			local out: { AdapterTypes.HashMapItem } = {}
			for _, entry in pages:GetCurrentPage() do
				table.insert(out, { key = entry.key, value = entry.value })
			end
			return out
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		return true, result
	end

	local conforming: MemoryHashMap = handle -- type-checks every method against the interface
	return conforming
end

function RobloxMemoryStore.new(options: Options?): MemoryStoreAdapter
	local MemoryStoreService = game:GetService("MemoryStoreService")
	local retryOptions: Retry.RetryOptions = {
		attempts = if options and options.attempts then options.attempts else nil,
		wait = if options then options.wait else nil,
	}
	local sortedMaps: { [string]: MemorySortedMap } = {}
	local hashMaps: { [string]: MemoryHashMap } = {}

	local adapter = {}

	function adapter.getSortedMap(_self: MemoryStoreAdapter, name: string): MemorySortedMap
		local existing = sortedMaps[name]
		if existing then
			return existing
		end
		local handle = sortedMapHandle(MemoryStoreService:GetSortedMap(name), retryOptions)
		sortedMaps[name] = handle
		return handle
	end

	function adapter.getHashMap(_self: MemoryStoreAdapter, name: string): MemoryHashMap
		local existing = hashMaps[name]
		if existing then
			return existing
		end
		local handle = hashMapHandle(MemoryStoreService:GetHashMap(name), retryOptions)
		hashMaps[name] = handle
		return handle
	end

	local conforming: MemoryStoreAdapter = adapter -- type-checks every method against the interface
	return conforming
end

return RobloxMemoryStore
