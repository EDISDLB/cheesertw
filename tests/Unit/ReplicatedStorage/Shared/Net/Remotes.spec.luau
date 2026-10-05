local Test = require("@tests/Harness/Test")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Remotes = require("@game/ReplicatedStorage/Shared/Net/Remotes")
local Protocol = require("@game/ReplicatedStorage/Shared/Net/Protocol")
local Schema = require("@game/ReplicatedStorage/Shared/Core/Schema")

describe("Remotes registry", function()
	it("contains the foundation remotes", function()
		expect(Remotes.get("Hello").kind).toBe("Function")
		expect(Remotes.get("ServerNotice").direction).toBe("S2C")
		expect(Remotes.get("DebugCommand").devOnly).toBe(true)
		expect(Remotes.get("Nope")).toBeNil()
	end)

	it("every entry is valid, frozen and C2S entries are rate limited with validators", function()
		for _, spec in Remotes.all() do
			local ok, err = Remotes.validateSpec(spec)
			if not ok then
				error(err)
			end
			expect(table.isfrozen(spec)).toBe(true)
			if spec.direction == "C2S" then
				expect(spec.rate).never.toBeNil()
				expect(spec.args).never.toBeNil()
			end
			if spec.kind == "Function" then
				expect(spec.direction).toBe("C2S")
			end
		end
	end)

	it("lists names sorted and exposes spec() for required lookups", function()
		local names = Remotes.names()
		local sorted = table.clone(names)
		table.sort(sorted)
		expect(names).toEqual(sorted)
		expect(Remotes.spec("Hello").name).toBe("Hello")
		expect(function()
			Remotes.spec("Missing")
		end).toThrow('unknown remote "Missing"')
	end)

	it("validateSpec rejects malformed entries", function()
		local bad = {
			{ spec = { name = "1x", kind = "Event", direction = "S2C" }, msg = "invalid remote name" },
			{ spec = { name = "X", kind = "Stream", direction = "S2C" }, msg = "invalid kind" },
			{ spec = { name = "X", kind = "Event", direction = "Both" }, msg = "invalid direction" },
			{ spec = { name = "X", kind = "Function", direction = "S2C" }, msg = "must be C2S" },
			{ spec = { name = "X", kind = "Event", direction = "C2S" }, msg = "must declare args" },
			{ spec = { name = "X", kind = "Event", direction = "C2S", args = { 5 } }, msg = "not a validator" },
			{
				spec = { name = "X", kind = "Event", direction = "C2S", args = {}, rate = { perSecond = 1, burst = 0 } },
				msg = "rate must have",
			},
		}
		for _, case in bad do
			local ok, err = Remotes.validateSpec(case.spec :: any)
			expect(ok).toBe(false)
			expect(err).toContain(case.msg)
		end
		expect((Remotes.validateSpec({ name = "Ok", kind = "Event", direction = "C2S", args = { Schema.any } }))).toBe(
			true
		)
	end)

	it("Hello validates the handshake payload", function()
		local validator = (Remotes.get("Hello") :: any).args[1]
		expect((validator({ clientVersion = Protocol.GAME_VERSION, protocol = Protocol.PROTOCOL_VERSION }))).toBe(true)
		expect((validator({ clientVersion = string.rep("x", 33), protocol = 1 }))).toBe(false)
		expect((validator({ clientVersion = "1", protocol = 1.5 }))).toBe(false)
		expect((validator({ clientVersion = "1", protocol = 1, extra = true }))).toBe(false)
	end)

	it("maps kinds to instance classes", function()
		expect(Remotes.className("Event")).toBe("RemoteEvent")
		expect(Remotes.className("Unreliable")).toBe("UnreliableRemoteEvent")
		expect(Remotes.className("Function")).toBe("RemoteFunction")
	end)
end)
