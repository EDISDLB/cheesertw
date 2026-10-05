-- Runs the live Roblox adapters against fake engine services (registered with game:setService) to verify their
-- translation logic: pcall + retry, Roblox return shapes -> plain tables, enum mapping, signal bridging.
local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local RobloxDataStore = require("@game/ServerScriptService/Server/Adapters/RobloxDataStore")
local RobloxMemoryStore = require("@game/ServerScriptService/Server/Adapters/RobloxMemoryStore")
local RobloxMessaging = require("@game/ServerScriptService/Server/Adapters/RobloxMessaging")
local RobloxTeleport = require("@game/ServerScriptService/Server/Adapters/RobloxTeleport")
local RobloxMarketplace = require("@game/ServerScriptService/Server/Adapters/RobloxMarketplace")
local RobloxPlayers = require("@game/ServerScriptService/Server/Adapters/RobloxPlayers")

local NO_WAIT = { wait = function() end }

local capture
Test.beforeEach(function()
	capture = LogCapture.start()
end)
Test.afterEach(function()
	capture:stop()
end)

local function keyInfo(version: string, userIds: { number }?, metadata: { [string]: any }?)
	return {
		Version = version,
		CreatedTime = 1,
		UpdatedTime = 2,
		GetUserIds = function()
			return userIds or {}
		end,
		GetMetadata = function()
			return metadata or {}
		end,
	}
end

describe("RobloxDataStore", function()
	local store, failuresLeft, service

	Test.beforeEach(function()
		failuresLeft = 0
		store = { data = {}, calls = {} }
		local function maybeFail(method: string)
			table.insert(store.calls, method)
			if failuresLeft > 0 then
				failuresLeft -= 1
				error("502: API Services rejected request", 0)
			end
		end
		function store.GetAsync(_self, key)
			maybeFail("GetAsync")
			local entry = store.data[key]
			if entry == nil then
				return nil, nil
			end
			return entry.value, keyInfo("v1", entry.userIds, entry.metadata)
		end
		function store.SetAsync(_self, key, value, userIds, options)
			maybeFail("SetAsync")
			store.data[key] =
				{ value = value, userIds = userIds, metadata = if options then options:GetMetadata() else nil }
			return "v-set"
		end
		function store.UpdateAsync(_self, key, transform)
			maybeFail("UpdateAsync")
			local entry = store.data[key]
			local newValue, userIds, metadata = transform(entry and entry.value, if entry then keyInfo("v1") else nil)
			if newValue == nil then
				return nil, nil
			end
			store.data[key] = { value = newValue, userIds = userIds, metadata = metadata }
			return newValue, keyInfo("v2", userIds, metadata)
		end
		function store.RemoveAsync(_self, key)
			maybeFail("RemoveAsync")
			local entry = store.data[key]
			store.data[key] = nil
			return entry and entry.value, nil
		end
		function store.IncrementAsync(_self, key, delta)
			maybeFail("IncrementAsync")
			local current = (store.data[key] and store.data[key].value) or 0
			store.data[key] = { value = current + delta }
			return current + delta
		end
		function store.ListVersionsAsync(_self, _key, direction, _min, _max, pageSize)
			maybeFail("ListVersionsAsync")
			store.lastList = { direction = direction, pageSize = pageSize }
			return {
				GetCurrentPage = function()
					return {
						{ Version = "v2", CreatedTime = 20, IsDeleted = true },
						{ Version = "v1", CreatedTime = 10, IsDeleted = false },
					}
				end,
			}
		end
		function store.GetVersionAsync(_self, _key, version)
			maybeFail("GetVersionAsync")
			return "value@" .. version, nil
		end
		service = {
			names = {},
			GetDataStore = function(self, name)
				table.insert(self.names, name)
				return store
			end,
			GetRequestBudgetForRequestType = function(_self, requestType)
				local budgets = { GetAsync = 60, SetIncrementAsync = 40, ListAsync = 5, GetVersionAsync = 7 }
				return budgets[requestType.Name] or -1
			end,
		}
		game:setService("DataStoreService", service)
	end)

	it("converts values and key info, caching DataStore objects", function()
		local adapter = RobloxDataStore.new(NO_WAIT)
		expect(select(2, adapter:setAsync("Profiles", "u1", { credits = 5 }, { 1 }, { schema = 2 }))).toBe("v-set")
		local ok, value, info = adapter:getAsync("Profiles", "u1")
		expect(ok).toBe(true)
		expect(value).toEqual({ credits = 5 })
		expect(info).toEqual({
			version = "v1",
			createdTime = 1,
			updatedTime = 2,
			userIds = { 1 },
			metadata = { schema = 2 },
		})
		adapter:getAsync("Profiles", "u2")
		expect(service.names).toEqual({ "Profiles" })
		local okMissing, missing, missingInfo = adapter:getAsync("Profiles", "nobody")
		expect(okMissing).toBe(true)
		expect(missing).toBeNil()
		expect(missingInfo).toBeNil()
	end)

	it("wraps UpdateAsync transforms with plain key info", function()
		local adapter = RobloxDataStore.new(NO_WAIT)
		store.data.u1 = { value = { n = 1 } }
		local seenVersion
		local ok, value, info = adapter:updateAsync("Profiles", "u1", function(current, ki)
			seenVersion = ki and ki.version
			return { n = current.n + 1 }, { 9 }, { lock = "job" }
		end)
		expect(ok).toBe(true)
		expect(seenVersion).toBe("v1")
		expect(value).toEqual({ n = 2 })
		expect(info.userIds).toEqual({ 9 })
		expect(info.metadata).toEqual({ lock = "job" })
		local okCancel, cancelled = adapter:updateAsync("Profiles", "u1", function()
			return nil
		end)
		expect(okCancel).toBe(true)
		expect(cancelled).toBeNil()
	end)

	it("retries transient failures and gives up after the attempts", function()
		local adapter = RobloxDataStore.new({ attempts = 3, wait = function() end })
		failuresLeft = 2
		expect((adapter:getAsync("Profiles", "u1"))).toBe(true)
		expect(#store.calls).toBe(3)
		failuresLeft = 5
		local ok, err = adapter:setAsync("Profiles", "u1", 1)
		expect(ok).toBe(false)
		expect(err).toContain("502")
	end)

	it("remove, increment, versions and budgets", function()
		local adapter = RobloxDataStore.new(NO_WAIT)
		store.data.k = { value = "old" }
		expect(select(2, adapter:removeAsync("S", "k"))).toBe("old")
		expect(select(2, adapter:incrementAsync("S", "count", 3))).toBe(3)
		local ok, versions = adapter:listVersionsAsync("S", "k", 500)
		expect(ok).toBe(true)
		expect(versions).toEqual({
			{ version = "v2", createdTime = 20, isDeleted = true },
			{ version = "v1", createdTime = 10, isDeleted = false },
		})
		expect(store.lastList.pageSize).toBe(100)
		expect(store.lastList.direction).toBe(Enum.SortDirection.Descending)
		expect(select(2, adapter:getVersionAsync("S", "k", "v1"))).toBe("value@v1")
		expect(adapter:getRequestBudget("Get")).toBe(60)
		expect(adapter:getRequestBudget("Set")).toBe(40)
		expect(adapter:getRequestBudget("Update")).toBe(40)
		expect(adapter:getRequestBudget("List")).toBe(5)
		expect(adapter:getRequestBudget("GetVersion")).toBe(7)
	end)
end)

describe("RobloxMemoryStore", function()
	it("wraps sorted maps and hash maps", function()
		local sorted = { items = {} }
		function sorted.GetAsync(_self, key)
			local item = sorted.items[key]
			return item and item.value, item and item.sortKey
		end
		function sorted.SetAsync(_self, key, value, ttl, sortKey)
			local existed = sorted.items[key] ~= nil
			sorted.items[key] = { value = value, sortKey = sortKey, ttl = ttl }
			return existed
		end
		function sorted.UpdateAsync(_self, key, transform, _ttl)
			local item = sorted.items[key]
			local v, s = transform(item and item.value, item and item.sortKey)
			if v == nil then
				return nil
			end
			sorted.items[key] = { value = v, sortKey = s }
			return v, s
		end
		function sorted.RemoveAsync(_self, key)
			sorted.items[key] = nil
		end
		function sorted.GetRangeAsync(_self, direction, count, lower, upper)
			sorted.lastRange = { direction = direction, count = count, lower = lower, upper = upper }
			return { { key = "a", value = 1, sortKey = 5 } }
		end
		function sorted.GetSizeAsync()
			return 1
		end
		local hash = { items = {} }
		function hash.GetAsync(_self, key)
			return hash.items[key]
		end
		function hash.SetAsync(_self, key, value)
			hash.items[key] = value
			return false
		end
		function hash.UpdateAsync(_self, key, transform)
			local v = transform(hash.items[key])
			hash.items[key] = v
			return v
		end
		function hash.RemoveAsync(_self, key)
			hash.items[key] = nil
		end
		function hash.ListItemsAsync(_self, count)
			hash.lastCount = count
			return {
				GetCurrentPage = function()
					return { { key = "k", value = "v" } }
				end,
			}
		end
		game:setService("MemoryStoreService", {
			GetSortedMap = function()
				return sorted
			end,
			GetHashMap = function()
				return hash
			end,
		})
		local adapter = RobloxMemoryStore.new(NO_WAIT)
		local map = adapter:getSortedMap("Queue")
		expect(adapter:getSortedMap("Queue")).toBe(map)
		expect(select(2, map:setAsync("t1", { s = 1 }, 30, 7))).toBe(false)
		local ok, value, sortKey = map:getAsync("t1")
		expect(ok).toBe(true)
		expect(value).toEqual({ s = 1 })
		expect(sortKey).toBe(7)
		local _, updated, newSort = map:updateAsync("t1", function(v, s)
			return { s = v.s + 1 }, s + 1
		end, 30)
		expect(updated).toEqual({ s = 2 })
		expect(newSort).toBe(8)
		local _, items = map:getRangeAsync("Descending", 500, { sortKey = 1 })
		expect(items).toEqual({ { key = "a", value = 1, sortKey = 5 } })
		expect(sorted.lastRange.direction).toBe(Enum.SortDirection.Descending)
		expect(sorted.lastRange.count).toBe(200)
		expect(select(2, map:getSizeAsync())).toBe(1)
		expect((map:removeAsync("t1"))).toBe(true)
		local hashMap = adapter:getHashMap("Manifests")
		hashMap:setAsync("m", "x", 10)
		expect(select(2, hashMap:getAsync("m"))).toBe("x")
		expect(select(
			2,
			hashMap:updateAsync("m", function(v)
				return v .. "y"
			end, 10)
		)).toBe("xy")
		expect(select(2, hashMap:listItemsAsync(1000))).toEqual({ { key = "k", value = "v" } })
		expect(hash.lastCount).toBe(200)
		expect((hashMap:removeAsync("m"))).toBe(true)
	end)

	it("surfaces errors after retries", function()
		game:setService("MemoryStoreService", {
			GetSortedMap = function()
				return {
					GetAsync = function()
						error("MemoryStore throttled", 0)
					end,
				}
			end,
		})
		local adapter = RobloxMemoryStore.new({ attempts = 2, wait = function() end })
		local ok, err = adapter:getSortedMap("X"):getAsync("k")
		expect(ok).toBe(false)
		expect(err).toBe("MemoryStore throttled")
	end)
end)

describe("RobloxMessaging", function()
	it("publishes and bridges subscriptions (Data/Sent unwrapped, errors contained)", function()
		local fake = { published = {}, callbacks = {}, disconnected = false }
		function fake.PublishAsync(_self, topic, message)
			table.insert(fake.published, { topic, message })
		end
		function fake.SubscribeAsync(_self, topic, callback)
			fake.callbacks[topic] = callback
			return {
				Disconnect = function()
					fake.disconnected = true
				end,
			}
		end
		game:setService("MessagingService", fake)
		local adapter = RobloxMessaging.new(NO_WAIT)
		expect((adapter:publishAsync("Matches", { id = 1 }))).toBe(true)
		expect(fake.published[1][1]).toBe("Matches")
		local got = {}
		local ok, connection = adapter:subscribeAsync("Matches", function(message, sentAt)
			table.insert(got, { message, sentAt })
			if message == "bad" then
				error("subscriber failure")
			end
		end)
		expect(ok).toBe(true)
		fake.callbacks.Matches({ Data = { id = 2 }, Sent = 1234 })
		fake.callbacks.Matches({ Data = "bad", Sent = 1 })
		expect(got[1]).toEqual({ { id = 2 }, 1234 })
		expect(capture:find("error", "subscriber failure")).never.toBeNil()
		connection:Disconnect()
		expect(fake.disconnected).toBe(true)
		expect(connection.Connected).toBe(false)
	end)
end)

describe("RobloxTeleport", function()
	it("reserves servers, builds TeleportOptions and bridges TeleportInitFailed", function()
		local fake = { TeleportInitFailed = Signal.new(), teleports = {} }
		function fake.ReserveServerAsync(_self, placeId)
			return "code-" .. placeId, "ps-" .. placeId
		end
		function fake.TeleportAsync(_self, placeId, players, options)
			table.insert(fake.teleports, {
				placeId = placeId,
				count = #players,
				code = options.ReservedServerAccessCode,
				data = options:GetTeleportData(),
			})
			return {}
		end
		game:setService("TeleportService", fake)
		local adapter = RobloxTeleport.new(NO_WAIT)
		local ok, reserved = adapter:reserveServerAsync(77)
		expect(ok).toBe(true)
		expect(reserved).toEqual({ accessCode = "code-77", privateServerId = "ps-77" })
		local p = game:GetService("Players"):addPlayer({ UserId = 900 })
		expect((adapter:teleportAsync(77, { p }, { reservedServerAccessCode = "code-77", teleportData = { m = 1 } }))).toBe(
			true
		)
		expect(fake.teleports[1]).toEqual({ placeId = 77, count = 1, code = "code-77", data = { m = 1 } })
		local failures = {}
		adapter.TeleportFailed:Connect(function(player, result, message)
			table.insert(failures, { player, result, message })
		end)
		fake.TeleportInitFailed:Fire(p, Enum.TeleportResult.GameFull, "full")
		expect(failures[1]).toEqual({ p, "GameFull", "full" })
		fake.TeleportAsync = function()
			error("Teleport failed: unauthorized", 0)
		end
		local okFail, err = adapter:teleportAsync(77, { p })
		expect(okFail).toBe(false)
		expect(err).toContain("unauthorized")
		p:Kick("done")
	end)
end)

describe("RobloxMarketplace", function()
	it("owns ProcessReceipt and never grants on errors", function()
		local fake = { PromptGamePassPurchaseFinished = Signal.new(), prompts = {} }
		function fake.UserOwnsGamePassAsync(_self, userId, passId)
			return userId == 1 and passId == 2
		end
		function fake.GetProductInfoAsync(_self, id, infoType)
			fake.lastInfoType = infoType
			return { Name = "Product " .. id }
		end
		function fake.PromptProductPurchase(_self, player, productId)
			table.insert(fake.prompts, { player, productId })
		end
		function fake.PromptGamePassPurchase(_self, player, passId)
			table.insert(fake.prompts, { player, passId })
		end
		game:setService("MarketplaceService", fake)
		local adapter = RobloxMarketplace.new(NO_WAIT)
		local raw = { PurchaseId = "p1", PlayerId = 5, ProductId = 10, CurrencySpent = 99, PlaceIdWherePurchased = 3 }
		expect(fake.ProcessReceipt(raw)).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
		local seen
		adapter:setReceiptHandler(function(receipt)
			seen = receipt
			return "PurchaseGranted"
		end)
		expect(fake.ProcessReceipt(raw)).toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
		expect(seen).toEqual({
			purchaseId = "p1",
			playerId = 5,
			productId = 10,
			currencySpent = 99,
			placeIdWherePurchased = 3,
		})
		expect(fake.ProcessReceipt({ PurchaseId = 5 })).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
		adapter:setReceiptHandler(function()
			error("datastore down")
		end)
		expect(fake.ProcessReceipt(raw)).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
		adapter:setReceiptHandler(function()
			return "NotProcessedYet"
		end)
		expect(fake.ProcessReceipt(raw)).toBe(Enum.ProductPurchaseDecision.NotProcessedYet)
		expect(select(2, adapter:userOwnsGamePassAsync(1, 2))).toBe(true)
		expect(select(2, adapter:getProductInfoAsync(10, "GamePass")).Name).toBe("Product 10")
		expect(fake.lastInfoType).toBe(Enum.InfoType.GamePass)
		adapter:promptProductPurchase("player" :: any, 10)
		expect(fake.prompts[1]).toEqual({ "player", 10 })
		local finished
		adapter.GamePassPurchaseFinished:Connect(function(player, passId, purchased)
			finished = { player, passId, purchased }
		end)
		fake.PromptGamePassPurchaseFinished:Fire("p", 2, true)
		expect(finished).toEqual({ "p", 2, true })
	end)
end)

describe("RobloxPlayers", function()
	it("bridges Players signals and computes the highest group rank", function()
		game:setService("GroupService", {
			GetRolesInGroupAsync = function(_self, userId, _groupId)
				if userId == 1 then
					return { IsMember = true, Roles = { { Rank = 100 }, { Rank = 254 }, { Rank = 1 } } }
				end
				return { IsMember = false, Roles = {} }
			end,
		})
		local adapter = RobloxPlayers.new(NO_WAIT)
		local added = {}
		adapter.PlayerAdded:Connect(function(p)
			table.insert(added, p.UserId)
		end)
		local players = game:GetService("Players")
		local p = players:addPlayer({ UserId = 1 })
		expect(added).toEqual({ 1 })
		expect(adapter:getPlayerByUserId(1)).toBe(p)
		expect(#adapter:getPlayers()).toBe(1)
		expect(select(2, adapter:getGroupRankAsync(1, 5))).toBe(254)
		expect(select(2, adapter:getGroupRankAsync(2, 5))).toBe(0)
		local removed = false
		adapter.PlayerRemoving:Connect(function()
			removed = true
		end)
		adapter:kick(p, "bye")
		expect(removed).toBe(true)
		expect((p:wasKicked())).toBe(true)
	end)
end)
