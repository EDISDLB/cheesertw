local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Places = require("@game/ReplicatedStorage/Shared/Config/Places")
local Config = require("@game/ReplicatedStorage/Shared/Config")

describe("Config/Places", function()
	it("is the same frozen table Config exposes", function()
		expect(Config.Places).toBe(Places)
		expect(table.isfrozen(Places)).toBe(true)
	end)

	it("Studio is always Dev, whatever the place id", function()
		for _, placeId in { 0, 1, Places.HUB_PLACE_ID, Places.BATTLE_PLACE_ID, 2 ^ 53 } do
			expect(Places.resolveRole(placeId, true)).toBe("Dev")
		end
	end)

	it("unmapped and placeholder (0) place ids resolve to Dev on live servers (never fail boot)", function()
		expect(Places.resolveRole(0, false)).toBe("Dev")
		expect(Places.resolveRole(123456, false)).toBe("Dev")
		expect(Places.resolveRole(-1, false)).toBe("Dev")
	end)

	it("published ids map to their roles and back", function()
		for _, role in { "Hub", "Battle" } do
			local id = Places.placeIdFor(role :: any)
			if id ~= 0 then
				expect(Places.resolveRole(id, false)).toBe(role)
			end
		end
		expect(Places.placeIdFor("Hub")).toBe(Places.HUB_PLACE_ID)
		expect(Places.placeIdFor("Battle")).toBe(Places.BATTLE_PLACE_ID)
		expect(Places.placeIdFor("Dev")).toBe(Places.DEV_PLACE_ID)
		expect(Places.ROLES).toEqual({ "Hub", "Battle", "Dev" })
	end)

	it("published ids are distinct when set (one place cannot have two roles)", function()
		local seen = {}
		for _, id in { Places.HUB_PLACE_ID, Places.BATTLE_PLACE_ID, Places.DEV_PLACE_ID } do
			if id ~= 0 then
				expect(seen[id]).toBeNil()
				seen[id] = true
			end
		end
	end)
end)
