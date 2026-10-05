local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

describe("Types", function()
	it("every type module loads (types are erased at runtime)", function()
		for _, name in { "Core", "World", "Adapters", "Net", "Service", "Content", "Battle", "Profile" } do
			expect(type(require(`@game/ReplicatedStorage/Shared/Types/{name}`))).toBe("table")
		end
		local Types = require("@game/ReplicatedStorage/Shared/Types")
		expect(table.isfrozen(Types)).toBe(true)
	end)
end)
