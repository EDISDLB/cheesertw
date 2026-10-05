local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local MockMarketplaceAdapter = require("@tests/Harness/Mocks/MockMarketplaceAdapter")

describe("MockMarketplaceAdapter", function()
	it("keeps receipts pending until the handler grants them", function()
		local adapter = MockMarketplaceAdapter.new()
		local _, decision = adapter:simulatePurchase(1, 100)
		expect(decision).toBe("NotProcessedYet")
		local processed = {}
		local fail = true
		adapter:setReceiptHandler(function(receipt)
			if fail then
				error("datastore down")
			end
			if processed[receipt.purchaseId] then
				return "PurchaseGranted"
			end
			processed[receipt.purchaseId] = true
			return "PurchaseGranted"
		end)
		expect(adapter:redeliverPending()).toEqual({ "NotProcessedYet" })
		fail = false
		expect(adapter:redeliverPending()).toEqual({ "PurchaseGranted" })
		expect(#adapter.pending).toBe(0)
		expect(#adapter.granted).toBe(1)
		expect(adapter:deliverReceipt(adapter.granted[1])).toBe("PurchaseGranted")
	end)

	it("ownership, product info, prompts and pass purchase signal", function()
		local adapter = MockMarketplaceAdapter.new()
		expect(select(2, adapter:userOwnsGamePassAsync(1, 9))).toBe(false)
		adapter:grantGamePass(1, 9)
		expect(select(2, adapter:userOwnsGamePassAsync(1, 9))).toBe(true)
		adapter:setProductInfo(5, "Product", { Name = "Gold x100", PriceInRobux = 99 })
		local ok, info = adapter:getProductInfoAsync(5, "Product")
		expect(ok).toBe(true)
		expect(info.PriceInRobux).toBe(99)
		expect((adapter:getProductInfoAsync(6, "Product"))).toBe(false)
		adapter:promptProductPurchase("p", 5)
		expect(adapter.prompts[1]).toEqual({ kind = "Product", player = "p", id = 5 })
		local finished
		adapter.GamePassPurchaseFinished:Connect(function(player, passId, purchased)
			finished = { player.UserId, passId, purchased }
		end)
		adapter:completeGamePassPurchase({ UserId = 2 }, 9, true)
		expect(finished).toEqual({ 2, 9, true })
		expect(select(2, adapter:userOwnsGamePassAsync(2, 9))).toBe(true)
		adapter:failNext("userOwnsGamePassAsync")
		expect((adapter:userOwnsGamePassAsync(2, 9))).toBe(false)
	end)
end)
