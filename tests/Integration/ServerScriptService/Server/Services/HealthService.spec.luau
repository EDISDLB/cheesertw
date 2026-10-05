local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local ServerHarness = require("@tests/Harness/ServerHarness")
local describe, it, expect = Test.describe, Test.it, Test.expect

local HealthService = require("@game/ServerScriptService/Server/Services/HealthService")
local DebugService = require("@game/ServerScriptService/Server/Services/DebugService")
local Protocol = require("@game/ReplicatedStorage/Shared/Net/Protocol")

local capture, h, player

local HELLO = { clientVersion = Protocol.GAME_VERSION, protocol = Protocol.PROTOCOL_VERSION }

Test.beforeEach(function()
	capture = LogCapture.start()
end)

Test.afterEach(function()
	if h then
		h.shutdown()
		h = nil
	end
	if player and player.Parent then
		player:Kick("cleanup")
	end
	capture:stop()
end)

describe("HealthService", function()
	it("answers Hello with role, versions, health and developer flag", function()
		h = ServerHarness.boot({ role = "Battle", modules = { HealthService, DebugService } })
		player = h.adapters.players:addPlayer({ UserId = 101 })
		local result = h.invoke(player, "Hello", HELLO)
		expect(result).toBeOk()
		expect(result.value.role).toBe("Battle")
		expect(result.value.version).toBe(Protocol.GAME_VERSION)
		expect(result.value.protocol).toBe(Protocol.PROTOCOL_VERSION)
		expect(result.value.healthy).toBe(true)
		expect(result.value.isDeveloper).toBe(false)
		expect(result.value.serverTime).toBe(1000)
	end)

	it("flags developers in Studio", function()
		h = ServerHarness.boot({ isStudio = true, modules = { HealthService, DebugService } })
		player = h.adapters.players:addPlayer({ UserId = 102 })
		expect(h.invoke(player, "Hello", HELLO).value.isDeveloper).toBe(true)
	end)

	it("rejects protocol mismatches and malformed requests", function()
		h = ServerHarness.boot({ modules = { HealthService } })
		player = h.adapters.players:addPlayer({ UserId = 103 })
		local mismatch = h.invoke(player, "Hello", { clientVersion = "old", protocol = Protocol.PROTOCOL_VERSION + 1 })
		expect(mismatch).toBeErr("VERSION_MISMATCH")
		h.clock:advance(10)
		expect(h.invoke(player, "Hello", { protocol = 1 })).toBeErr("INVALID_ARGS")
	end)

	it("answers NOT_READY before Start and tracks lifecycle failures", function()
		local failing = {
			Name = "Flaky",
			Dependencies = { "HealthService" },
			Init = function()
				error("flaky init")
			end,
		}
		h = ServerHarness.boot({ modules = { HealthService, failing } })
		player = h.adapters.players:addPlayer({ UserId = 104 })
		local status = HealthService:getStatus()
		expect(status.healthy).toBe(false)
		expect(status.ready).toBe(true)
		expect(status.failures[1].service).toBe("Flaky")
		expect(status.failures[1].phase).toBe("Init")
		expect(status.failures[1].err).toContain("flaky init")
		expect(h.invoke(player, "Hello", HELLO).value.healthy).toBe(false)
		HealthService._ready = false
		expect(h.invoke(player, "Hello", HELLO)).toBeErr("NOT_READY")
	end)

	it("picks up failures that happened before its own Init", function()
		local early = {
			Name = "AEarly",
			Init = function()
				error("early failure")
			end,
		}
		h = ServerHarness.boot({ modules = { early, HealthService } })
		expect(HealthService:isHealthy()).toBe(false)
		expect(HealthService:getStatus().failures[1].service).toBe("AEarly")
	end)

	it("broadcasts notices and a shutdown notice on Stop", function()
		h = ServerHarness.boot({ modules = { HealthService } })
		player = h.adapters.players:addPlayer({ UserId = 105 })
		HealthService:notify("Info", "maintenance soon", { player })
		local remote = h.remote("ServerNotice")
		expect(remote._sent[1].kind).toBe("FireClient")
		expect(remote._sent[1].args[1].message).toBe("maintenance soon")
		h.loader:stop(1)
		local last = remote._sent[#remote._sent]
		expect(last.kind).toBe("FireAllClients")
		expect(last.args[1].kind).toBe("Shutdown")
		expect(HealthService:isReady()).toBe(false)
	end)
end)
