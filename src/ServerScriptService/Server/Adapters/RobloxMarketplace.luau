--!strict
--[[
	RobloxMarketplace — MarketplaceAdapter over MarketplaceService (developer products, game passes).

	Purpose:          Owns MarketplaceService.ProcessReceipt and translates receipts to plain ReceiptInfo tables;
	                  game pass ownership/product info lookups; purchase prompts.
	Dependencies:     MarketplaceService, Adapters/Retry, Core/Signal, Core/Log, Types/Adapters.
	State:            The current receipt handler and the GamePassPurchaseFinished signal.
	Validation:       Receipt fields are type-checked before reaching the handler.
	Error handling:   A missing handler, a malformed receipt or a handler error returns NotProcessedYet so Roblox
	                  retries the receipt later (never grant on error). Lookups retry 3 times.
	Performance notes: N/A.
]]

local AdapterTypes = require("@game/ReplicatedStorage/Shared/Types/Adapters")
local Signal = require("@game/ReplicatedStorage/Shared/Core/Signal")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")
local Retry = require("./Retry")

type MarketplaceAdapter = AdapterTypes.MarketplaceAdapter
type ReceiptInfo = AdapterTypes.ReceiptInfo
type PurchaseDecision = AdapterTypes.PurchaseDecision

--- attempts: max tries per call (default 3; Players: 2). wait: backoff sleeper (default task.wait; tests inject).
export type Options = { attempts: number?, wait: ((seconds: number) -> ())? }

local log = Log.scope("RobloxMarketplace")

local RobloxMarketplace = {}

local function toReceipt(raw: { [string]: any }): ReceiptInfo?
	if type(raw) ~= "table" then
		return nil
	end
	local purchaseId, playerId, productId = raw.PurchaseId, raw.PlayerId, raw.ProductId
	if type(purchaseId) ~= "string" or type(playerId) ~= "number" or type(productId) ~= "number" then
		return nil
	end
	return {
		purchaseId = purchaseId,
		playerId = playerId,
		productId = productId,
		currencySpent = if type(raw.CurrencySpent) == "number" then raw.CurrencySpent else 0,
		placeIdWherePurchased = if type(raw.PlaceIdWherePurchased) == "number" then raw.PlaceIdWherePurchased else 0,
	}
end

function RobloxMarketplace.new(options: Options?): MarketplaceAdapter
	local MarketplaceService = game:GetService("MarketplaceService")
	local retryOptions: Retry.RetryOptions = {
		attempts = if options and options.attempts then options.attempts else nil,
		wait = if options then options.wait else nil,
	}
	local handler: ((receipt: ReceiptInfo) -> PurchaseDecision)? = nil

	local adapter = {
		GamePassPurchaseFinished = Signal.new() :: Signal.Signal<Player, number, boolean>,
	}

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, purchased: boolean)
			adapter.GamePassPurchaseFinished:Fire(player, gamePassId, purchased)
		end
	)

	MarketplaceService.ProcessReceipt = function(raw: { [string]: any }): Enum.ProductPurchaseDecision
		local receipt = toReceipt(raw)
		local current = handler
		if receipt == nil or current == nil then
			log:warn("receipt not processed (%s)", if receipt == nil then "malformed receipt" else "no handler yet")
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local ok, decision = pcall(current, receipt)
		if ok and decision == "PurchaseGranted" then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if not ok then
			log:error("receipt handler failed for %s: %s", receipt.purchaseId, tostring(decision))
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	function adapter.setReceiptHandler(_self: MarketplaceAdapter, fn: (receipt: ReceiptInfo) -> PurchaseDecision)
		handler = fn
	end

	function adapter.userOwnsGamePassAsync(
		_self: MarketplaceAdapter,
		userId: number,
		gamePassId: number
	): (boolean, boolean | string)
		return Retry.call(function()
			return MarketplaceService:UserOwnsGamePassAsync(userId, gamePassId)
		end, retryOptions)
	end

	function adapter.getProductInfoAsync(
		_self: MarketplaceAdapter,
		id: number,
		kind: AdapterTypes.ProductInfoKind
	): (boolean, { [string]: any } | string)
		local infoType = if kind == "Product"
			then Enum.InfoType.Product
			elseif kind == "GamePass" then Enum.InfoType.GamePass
			else Enum.InfoType.Asset
		return Retry.call(function()
			return MarketplaceService:GetProductInfoAsync(id, infoType)
		end, retryOptions)
	end

	function adapter.promptProductPurchase(_self: MarketplaceAdapter, player: Player, productId: number)
		MarketplaceService:PromptProductPurchase(player, productId)
	end

	function adapter.promptGamePassPurchase(_self: MarketplaceAdapter, player: Player, gamePassId: number)
		MarketplaceService:PromptGamePassPurchase(player, gamePassId)
	end

	local conforming: MarketplaceAdapter = adapter -- type-checks every method against the interface
	return conforming
end

return RobloxMarketplace
