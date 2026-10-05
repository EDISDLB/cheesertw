local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local MockDataStoreAdapter = require("@tests/Harness/Mocks/MockDataStoreAdapter")
local ServerHarness = require("@tests/Harness/ServerHarness")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Bootstrap = require("@game/ServerScriptService/Server/Bootstrap")
local HealthService = require("@game/ServerScriptService/Server/Services/HealthService")
local DebugService = require("@game/ServerScriptService/Server/Services/DebugService")
local Config = require("@game/ReplicatedStorage/Shared/Config")

local capture, h

Test.beforeEach(function()
	capture = LogCapture.start()
end)

Test.afterEach(function()
	if h then
		h.shutdown()
		h = nil
	end
	Config.resetOverrides()
	capture:stop()
end)

describe("Bootstrap.start", function()
	it("boots the foundation services in dependency order with a full context", function()
		h = ServerHarness.boot({ modules = { DebugService, HealthService } })
		expect(h.result).toBeOk()
		expect(h.result.value).toEqual({ "HealthService", "DebugService" })
		local ctx = HealthService._ctx
		expect(ctx.role).toBe("Hub")
		expect(ctx.net).toBe(h.net)
		expect(ctx.adapters).toBe(h.adapters)
		expect(ctx.config).toBe(Config)
		expect(ctx.server.jobId).toBe("mock-job-0001")
		expect(ctx.services.DebugService).toBe(DebugService)
		expect(ctx.log.name).toBe("HealthService")
		expect(h.loader:getStatus("DebugService")).toBe("Started")
	end)

	it("returns configuration errors instead of throwing", function()
		h = ServerHarness.boot({ modules = { { Name = "Orphan", Dependencies = { "Missing" } } } })
		expect(h.result).toBeErr("INTERNAL")
		expect(h.result.detail).toContain('Orphan depends on missing Service "Missing"')
		expect(capture:find("error", "boot failed")).never.toBeNil()
	end)

	it("serverInfo reads DataModel identity", function()
		local info = Bootstrap.serverInfo(game :: any)
		expect(info).toEqual({
			placeId = 0,
			gameId = 0,
			jobId = "mock-job-0001",
			privateServerId = "",
			privateServerOwnerId = 0,
		})
	end)
end)

describe("Bootstrap.loadLiveOverrides", function()
	it("applies stored overrides", function()
		local store = MockDataStoreAdapter.new()
		store:seed(Bootstrap.OVERRIDES_STORE, Bootstrap.OVERRIDES_KEY, { Battle = { SNAPSHOT_RATE = 10 } })
		local result = Bootstrap.loadLiveOverrides(store, Config)
		expect(result).toBeOk()
		expect(result.value).toEqual({ "Battle.SNAPSHOT_RATE" })
		expect(Config.Battle.SNAPSHOT_RATE).toBe(10)
	end)

	it("treats missing overrides as nothing to apply", function()
		local result = Bootstrap.loadLiveOverrides(MockDataStoreAdapter.new(), Config)
		expect(result).toBeOk()
		expect(result.value).toEqual({})
	end)

	it("reports read failures and invalid patches without touching config", function()
		local store = MockDataStoreAdapter.new()
		store:failNext("getAsync", 1, "403: Studio API access disabled")
		local failed = Bootstrap.loadLiveOverrides(store, Config)
		expect(failed).toBeErr("UNAVAILABLE")
		expect(failed.detail).toContain("403")
		store:seed(Bootstrap.OVERRIDES_STORE, Bootstrap.OVERRIDES_KEY, { Battle = { TICK_RATE = 9000 } })
		expect(Bootstrap.loadLiveOverrides(store, Config)).toBeErr("INVALID_ARGS")
		expect(Config.Battle.TICK_RATE).toBe(30)
	end)
end)
