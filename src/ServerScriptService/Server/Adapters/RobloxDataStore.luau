--!strict
--[[
	RobloxDataStore — DataStoreAdapter over DataStoreService (live servers / Studio with API access).

	Purpose:          Thin, typed wrapper: every call is pcall'd, transient errors retried (Retry), Roblox objects
	                  (DataStoreKeyInfo, version pages) converted to plain tables.
	Dependencies:     DataStoreService, Adapters/Retry, Types/Adapters.
	State:            Cache of DataStore objects by name.
	Validation:       Roblox validates keys/values; its error messages (with numeric codes) are returned verbatim.
	Error handling:   Returns (false, message) on failure; never throws. UpdateAsync transforms that throw are
	                  surfaced as failures (Roblox aborts the write).
	Performance notes: Default 3 attempts with backoff; DataService (owner of the retry/budget policy) can construct
	                  this with { attempts = 1 }.
]]

local AdapterTypes = require("@game/ReplicatedStorage/Shared/Types/Adapters")
local Retry = require("./Retry")

type DataStoreAdapter = AdapterTypes.DataStoreAdapter
type KeyInfo = AdapterTypes.DataStoreKeyInfo

--- attempts: max tries per call (default 3; Players: 2). wait: backoff sleeper (default task.wait; tests inject).
export type Options = { attempts: number?, wait: ((seconds: number) -> ())? }

type Packed = { value: any, info: DataStoreKeyInfo? }

local function toKeyInfo(info: DataStoreKeyInfo?): KeyInfo?
	if info == nil then
		return nil
	end
	return {
		version = info.Version,
		createdTime = info.CreatedTime,
		updatedTime = info.UpdatedTime,
		userIds = info:GetUserIds(),
		metadata = info:GetMetadata(),
	}
end

local RobloxDataStore = {}

function RobloxDataStore.new(options: Options?): DataStoreAdapter
	local DataStoreService = game:GetService("DataStoreService")
	local retryOptions: Retry.RetryOptions = {
		attempts = if options and options.attempts then options.attempts else nil,
		wait = if options then options.wait else nil,
	}
	local stores: { [string]: DataStore } = {}

	local function storeFor(name: string): DataStore
		local cached = stores[name]
		if cached then
			return cached
		end
		local store = DataStoreService:GetDataStore(name)
		stores[name] = store
		return store
	end

	local adapter = {}

	function adapter.getAsync(_self: DataStoreAdapter, store: string, key: string): (boolean, any, KeyInfo?)
		local ok, result = Retry.call(function(): Packed
			local value, info = storeFor(store):GetAsync(key)
			return { value = value, info = info }
		end, retryOptions)
		if not ok then
			return false, result
		end
		local packed = result :: Packed
		return true, packed.value, toKeyInfo(packed.info)
	end

	function adapter.setAsync(
		_self: DataStoreAdapter,
		store: string,
		key: string,
		value: any,
		userIds: { number }?,
		metadata: { [string]: any }?
	): (boolean, any)
		return Retry.call(function()
			local setOptions: DataStoreSetOptions? = nil
			if metadata ~= nil then
				local created = Instance.new("DataStoreSetOptions")
				created:SetMetadata(metadata)
				setOptions = created
			end
			return storeFor(store):SetAsync(key, value, userIds, setOptions)
		end, retryOptions)
	end

	function adapter.updateAsync(
		_self: DataStoreAdapter,
		store: string,
		key: string,
		transform: AdapterTypes.DataStoreTransform
	): (boolean, any, KeyInfo?)
		local ok, result = Retry.call(function(): Packed
			local value, info = storeFor(store):UpdateAsync(key, function(current: any, keyInfo: DataStoreKeyInfo): any
				return transform(current, toKeyInfo(keyInfo))
			end)
			return { value = value, info = info }
		end, retryOptions)
		if not ok then
			return false, result
		end
		local packed = result :: Packed
		return true, packed.value, toKeyInfo(packed.info)
	end

	function adapter.removeAsync(_self: DataStoreAdapter, store: string, key: string): (boolean, any)
		return Retry.call(function()
			local previous = storeFor(store):RemoveAsync(key)
			return previous
		end, retryOptions)
	end

	function adapter.incrementAsync(_self: DataStoreAdapter, store: string, key: string, delta: number): (boolean, any)
		return Retry.call(function()
			local value = storeFor(store):IncrementAsync(key, delta)
			return value
		end, retryOptions)
	end

	function adapter.listVersionsAsync(
		_self: DataStoreAdapter,
		store: string,
		key: string,
		limit: number?
	): (boolean, { AdapterTypes.DataStoreVersionInfo } | string)
		local pageSize = math.clamp(limit or 20, 1, 100)
		local ok, result = Retry.call(function()
			local pages = storeFor(store):ListVersionsAsync(key, Enum.SortDirection.Descending, nil, nil, pageSize)
			local out: { AdapterTypes.DataStoreVersionInfo } = {}
			for _, item in pages:GetCurrentPage() do
				local info = item :: DataStoreObjectVersionInfo
				table.insert(
					out,
					{ version = info.Version, createdTime = info.CreatedTime, isDeleted = info.IsDeleted }
				)
			end
			return out
		end, retryOptions)
		if not ok then
			return false, result :: string
		end
		return true, result
	end

	function adapter.getVersionAsync(
		_self: DataStoreAdapter,
		store: string,
		key: string,
		version: string
	): (boolean, any)
		return Retry.call(function()
			local value = storeFor(store):GetVersionAsync(key, version)
			return value
		end, retryOptions)
	end

	function adapter.getRequestBudget(_self: DataStoreAdapter, kind: AdapterTypes.DataStoreRequestKind): number
		local get = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync)
		local set = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync)
		if kind == "Get" then
			return get
		elseif kind == "Set" or kind == "Remove" then
			return set
		elseif kind == "Update" then
			return math.min(get, set)
		elseif kind == "List" then
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.ListAsync)
		end
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetVersionAsync)
	end

	local conforming: DataStoreAdapter = adapter -- type-checks every method against the interface
	return conforming
end

return RobloxDataStore
