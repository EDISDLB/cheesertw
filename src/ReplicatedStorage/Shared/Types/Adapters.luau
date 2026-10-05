--!strict
--[[
	Types/Adapters — interfaces over Roblox platform services (dependency injection, ARCHITECTURE §5.3).

	Purpose:          Server code talks to DataStores, MemoryStores, Messaging, Teleport, Marketplace and Players only
	                  through these interfaces. Implementations: Server/Adapters/Roblox* (live) and
	                  tests/Harness/Mocks/Mock*Adapter (failure injection, deterministic).
	Dependencies:     Types/Core (Signal, Connection), Types/World (World).
	State:            None (type-only).
	Validation:       N/A. Implementations validate key/value limits and surface them as errors.
	Error handling:   Every *Async method returns `(ok: boolean, valueOrErr)`: on failure the second value is an error
	                  message string; nothing throws (implementations pcall the Roblox API).
	Performance notes: Erased at runtime.

	Error strings from live adapters keep Roblox's numeric prefix when present (e.g. "502: API Services rejected...")
	so callers can classify transient failures with `string.match(err, "^(%d+):")`.
]]

local CoreTypes = require("./Core")
local WorldTypes = require("./World")

type Signal<T...> = CoreTypes.Signal<T...>
type Connection = CoreTypes.Connection

--------------------------------------------------------------------------------
-- DataStore
--------------------------------------------------------------------------------

export type DataStoreKeyInfo = {
	version: string,
	createdTime: number, -- ms since epoch
	updatedTime: number, -- ms since epoch
	userIds: { number },
	metadata: { [string]: any },
}

export type DataStoreVersionInfo = {
	version: string,
	createdTime: number,
	isDeleted: boolean,
}

--- Request kinds for budget queries ("Update" consumes Get and Set budget).
export type DataStoreRequestKind = "Get" | "Set" | "Update" | "Remove" | "List" | "GetVersion"

--- UpdateAsync transform: return nil to cancel the write. Must not yield. May run more than once.
export type DataStoreTransform = (current: any, keyInfo: DataStoreKeyInfo?) -> (any, { number }?, { [string]: any }?)

export type DataStoreAdapter = {
	--- (true, value | nil, keyInfo?) or (false, err)
	getAsync: (self: DataStoreAdapter, store: string, key: string) -> (boolean, any, DataStoreKeyInfo?),
	--- (true, versionString) or (false, err)
	setAsync: (
		self: DataStoreAdapter,
		store: string,
		key: string,
		value: any,
		userIds: { number }?,
		metadata: { [string]: any }?
	) -> (boolean, any),
	--- (true, newValue | nil when cancelled, keyInfo?) or (false, err)
	updateAsync: (
		self: DataStoreAdapter,
		store: string,
		key: string,
		transform: DataStoreTransform
	) -> (boolean, any, DataStoreKeyInfo?),
	--- (true, previousValue | nil) or (false, err)
	removeAsync: (self: DataStoreAdapter, store: string, key: string) -> (boolean, any),
	--- (true, newNumber) or (false, err)
	incrementAsync: (self: DataStoreAdapter, store: string, key: string, delta: number) -> (boolean, any),
	--- (true, versions newest first) or (false, err)
	listVersionsAsync: (
		self: DataStoreAdapter,
		store: string,
		key: string,
		limit: number?
	) -> (boolean, { DataStoreVersionInfo } | string),
	--- (true, value at that version | nil) or (false, err)
	getVersionAsync: (self: DataStoreAdapter, store: string, key: string, version: string) -> (boolean, any),
	--- Remaining request budget for this kind (non-yielding).
	getRequestBudget: (self: DataStoreAdapter, kind: DataStoreRequestKind) -> number,
}

--------------------------------------------------------------------------------
-- MemoryStore (sorted maps + hash maps; every write has a TTL in seconds, max 3,888,000)
--------------------------------------------------------------------------------

export type SortKey = number | string
export type SortDirection = "Ascending" | "Descending"
export type SortedMapBound = { key: string?, sortKey: SortKey? }
export type SortedMapItem = { key: string, value: any, sortKey: SortKey? }
export type HashMapItem = { key: string, value: any }

export type MemorySortedMap = {
	--- (true, value | nil, sortKey?) or (false, err)
	getAsync: (self: MemorySortedMap, key: string) -> (boolean, any, SortKey?),
	--- (true, overwroteExisting: boolean) or (false, err)
	setAsync: (self: MemorySortedMap, key: string, value: any, ttlSeconds: number, sortKey: SortKey?) -> (boolean, any),
	--- transform(oldValue, oldSortKey) -> (newValue, newSortKey) or nil to cancel. (true, value | nil, sortKey?)
	updateAsync: (
		self: MemorySortedMap,
		key: string,
		transform: (value: any, sortKey: SortKey?) -> (any, SortKey?),
		ttlSeconds: number
	) -> (boolean, any, SortKey?),
	removeAsync: (self: MemorySortedMap, key: string) -> (boolean, string?),
	--- Exclusive bounds; ordering: numeric sort keys, then string sort keys, then no sort key; ties by key.
	getRangeAsync: (
		self: MemorySortedMap,
		direction: SortDirection,
		count: number,
		lower: SortedMapBound?,
		upper: SortedMapBound?
	) -> (boolean, { SortedMapItem } | string),
	getSizeAsync: (self: MemorySortedMap) -> (boolean, number | string),
}

export type MemoryHashMap = {
	getAsync: (self: MemoryHashMap, key: string) -> (boolean, any),
	--- (true, overwroteExisting: boolean) or (false, err)
	setAsync: (self: MemoryHashMap, key: string, value: any, ttlSeconds: number) -> (boolean, any),
	--- transform(oldValue) -> newValue or nil to cancel. (true, value | nil)
	updateAsync: (
		self: MemoryHashMap,
		key: string,
		transform: (value: any) -> any,
		ttlSeconds: number
	) -> (boolean, any),
	removeAsync: (self: MemoryHashMap, key: string) -> (boolean, string?),
	--- Up to `limit` items (no ordering guarantee).
	listItemsAsync: (self: MemoryHashMap, limit: number) -> (boolean, { HashMapItem } | string),
}

export type MemoryStoreAdapter = {
	getSortedMap: (self: MemoryStoreAdapter, name: string) -> MemorySortedMap,
	getHashMap: (self: MemoryStoreAdapter, name: string) -> MemoryHashMap,
}

--------------------------------------------------------------------------------
-- Messaging (cross-server pub/sub; message <= 1 KB after JSON encoding)
--------------------------------------------------------------------------------

export type MessagingAdapter = {
	publishAsync: (self: MessagingAdapter, topic: string, message: any) -> (boolean, string?),
	--- callback(message, sentUnixSeconds). (true, Connection) or (false, err)
	subscribeAsync: (
		self: MessagingAdapter,
		topic: string,
		callback: (message: any, sentAt: number) -> ()
	) -> (boolean, Connection | string),
}

--------------------------------------------------------------------------------
-- Teleport
--------------------------------------------------------------------------------

export type ReservedServer = { accessCode: string, privateServerId: string }
export type TeleportSpec = { reservedServerAccessCode: string?, teleportData: any? }

export type TeleportAdapter = {
	reserveServerAsync: (self: TeleportAdapter, placeId: number) -> (boolean, ReservedServer | string),
	--- Starts a teleport; later failures arrive on TeleportFailed.
	teleportAsync: (
		self: TeleportAdapter,
		placeId: number,
		players: { Player },
		spec: TeleportSpec?
	) -> (boolean, string?),
	--- (player, resultName e.g. "Failure"/"GameFull"/"Flooded", message)
	TeleportFailed: Signal<Player, string, string>,
}

--------------------------------------------------------------------------------
-- Marketplace
--------------------------------------------------------------------------------

export type ReceiptInfo = {
	purchaseId: string,
	playerId: number,
	productId: number,
	currencySpent: number,
	placeIdWherePurchased: number,
}

export type PurchaseDecision = "PurchaseGranted" | "NotProcessedYet"
export type ProductInfoKind = "Product" | "GamePass" | "Asset"

export type MarketplaceAdapter = {
	--- The handler must be idempotent by purchaseId; errors are treated as NotProcessedYet.
	setReceiptHandler: (self: MarketplaceAdapter, handler: (receipt: ReceiptInfo) -> PurchaseDecision) -> (),
	userOwnsGamePassAsync: (
		self: MarketplaceAdapter,
		userId: number,
		gamePassId: number
	) -> (boolean, boolean | string),
	getProductInfoAsync: (
		self: MarketplaceAdapter,
		id: number,
		kind: ProductInfoKind
	) -> (boolean, { [string]: any } | string),
	promptProductPurchase: (self: MarketplaceAdapter, player: Player, productId: number) -> (),
	promptGamePassPurchase: (self: MarketplaceAdapter, player: Player, gamePassId: number) -> (),
	--- (player, gamePassId, purchased)
	GamePassPurchaseFinished: Signal<Player, number, boolean>,
}

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

export type PlayersAdapter = {
	getPlayers: (self: PlayersAdapter) -> { Player },
	getPlayerByUserId: (self: PlayersAdapter, userId: number) -> Player?,
	kick: (self: PlayersAdapter, player: Player, message: string) -> (),
	--- Highest rank the user holds in the group (0 when not a member).
	getGroupRankAsync: (self: PlayersAdapter, userId: number, groupId: number) -> (boolean, number | string),
	PlayerAdded: Signal<Player>,
	PlayerRemoving: Signal<Player>,
}

--------------------------------------------------------------------------------
-- Bundle passed in ServiceContext.adapters
--------------------------------------------------------------------------------

export type Adapters = {
	players: PlayersAdapter,
	dataStore: DataStoreAdapter,
	memoryStore: MemoryStoreAdapter,
	messaging: MessagingAdapter,
	teleport: TeleportAdapter,
	marketplace: MarketplaceAdapter,
	--- Set by the battle host once a map is loaded (RobloxWorld / HeightmapWorld); nil in hubs.
	world: WorldTypes.World?,
}

return {}
