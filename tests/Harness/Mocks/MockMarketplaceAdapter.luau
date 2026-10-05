--[[
	MockMarketplaceAdapter — developer products / game passes without MarketplaceService.

	Purpose:          Receipt processing tests (idempotency, NotProcessedYet redelivery), ownership and prompts.
	Dependencies:     FailureInjector, Core/Signal.
	State:            Receipt handler, pending receipts (redelivered until granted), ownership table, product info,
	                  prompt log.
	Validation:       Decisions other than "PurchaseGranted" count as NotProcessedYet (like Roblox).
	Error handling:   Handler errors -> NotProcessedYet (receipt stays pending).
	Performance notes: Test-only.

	Helpers: simulatePurchase(playerId, productId, currencySpent?) -> (receipt, decision); redeliverPending() ->
	decisions; grantGamePass(userId, passId); setProductInfo(id, info); completeGamePassPurchase(player, passId, ok).
]]

local FailureInjector = require("./FailureInjector")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")

local MockMarketplaceAdapter = {}
MockMarketplaceAdapter.__index = MockMarketplaceAdapter

function MockMarketplaceAdapter.new(options: { placeId: number? }?)
	return setmetatable({
		GamePassPurchaseFinished = Signal.new(),
		_handler = nil,
		_owned = {},
		_productInfo = {},
		_purchaseCounter = 0,
		_placeId = if options and options.placeId then options.placeId else 0,
		pending = {},
		granted = {},
		prompts = {},
		injector = FailureInjector.new(),
	}, MockMarketplaceAdapter)
end

function MockMarketplaceAdapter.setReceiptHandler(self: any, handler: (any) -> string)
	self._handler = handler
end

local function process(self: any, receipt: any): string
	local handler = self._handler
	if handler == nil then
		return "NotProcessedYet"
	end
	local ok, decision = pcall(handler, table.clone(receipt))
	if ok and decision == "PurchaseGranted" then
		return "PurchaseGranted"
	end
	return "NotProcessedYet"
end

--- Delivers a new receipt to the handler. Ungranted receipts stay pending for redeliverPending().
function MockMarketplaceAdapter.simulatePurchase(
	self: any,
	playerId: number,
	productId: number,
	currencySpent: number?
): (any, string)
	self._purchaseCounter += 1
	local receipt = {
		purchaseId = string.format("purchase-%06d", self._purchaseCounter),
		playerId = playerId,
		productId = productId,
		currencySpent = currencySpent or 0,
		placeIdWherePurchased = self._placeId,
	}
	local decision = process(self, receipt)
	if decision == "PurchaseGranted" then
		table.insert(self.granted, receipt)
	else
		table.insert(self.pending, receipt)
	end
	return receipt, decision
end

--- Redelivers every pending receipt (as Roblox does on rejoin/retry). Returns the decisions in order.
function MockMarketplaceAdapter.redeliverPending(self: any): { string }
	local decisions = {}
	local still = {}
	for _, receipt in self.pending do
		local decision = process(self, receipt)
		table.insert(decisions, decision)
		if decision == "PurchaseGranted" then
			table.insert(self.granted, receipt)
		else
			table.insert(still, receipt)
		end
	end
	self.pending = still
	return decisions
end

--- Delivers an exact receipt again (duplicate delivery / idempotency tests).
function MockMarketplaceAdapter.deliverReceipt(self: any, receipt: any): string
	return process(self, receipt)
end

function MockMarketplaceAdapter.userOwnsGamePassAsync(self: any, userId: number, gamePassId: number): (boolean, any)
	local injected = self.injector:check("userOwnsGamePassAsync")
	if injected then
		return false, injected
	end
	return true, self._owned[userId .. ":" .. gamePassId] == true
end

function MockMarketplaceAdapter.getProductInfoAsync(self: any, id: number, kind: string): (boolean, any)
	local injected = self.injector:check("getProductInfoAsync")
	if injected then
		return false, injected
	end
	local info = self._productInfo[kind .. ":" .. id]
	if info == nil then
		return false, `{kind} {id} not found`
	end
	return true, table.clone(info)
end

function MockMarketplaceAdapter.promptProductPurchase(self: any, player: any, productId: number)
	table.insert(self.prompts, { kind = "Product", player = player, id = productId })
end

function MockMarketplaceAdapter.promptGamePassPurchase(self: any, player: any, gamePassId: number)
	table.insert(self.prompts, { kind = "GamePass", player = player, id = gamePassId })
end

function MockMarketplaceAdapter.grantGamePass(self: any, userId: number, gamePassId: number)
	self._owned[userId .. ":" .. gamePassId] = true
end

function MockMarketplaceAdapter.setProductInfo(self: any, id: number, kind: string, info: { [string]: any })
	self._productInfo[kind .. ":" .. id] = info
end

function MockMarketplaceAdapter.completeGamePassPurchase(self: any, player: any, gamePassId: number, purchased: boolean)
	if purchased then
		self:grantGamePass(player.UserId, gamePassId)
	end
	self.GamePassPurchaseFinished:Fire(player, gamePassId, purchased)
end

function MockMarketplaceAdapter.failNext(self: any, method: string, count: number?, message: string?)
	self.injector:failNext(method, count, message)
end

function MockMarketplaceAdapter.failAlways(self: any, method: string, message: string?)
	self.injector:failAlways(method, message)
end

function MockMarketplaceAdapter.clearFailures(self: any)
	self.injector:clear()
end

return MockMarketplaceAdapter
