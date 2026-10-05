local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local ServerHarness = require("@tests/Harness/ServerHarness")
local describe, it, expect = Test.describe, Test.it, Test.expect

local HealthService = require("@game/ServerScriptService/Server/Services/HealthService")
local DebugService = require("@game/ServerScriptService/Server/Services/DebugService")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local Log = require("@game/ReplicatedStorage/Shared/Core/Log")

local capture, h

Test.beforeEach(function()
	capture = LogCapture.start()
end)

Test.afterEach(function()
	if h then
		h.shutdown()
		h = nil
	end
	for _, p in game:GetService("Players"):GetPlayers() do
		p:Kick("cleanup")
	end
	capture:stop()
end)

describe("DebugService access control", function()
	it("rejects non-developers on live servers before the service is reached", function()
		h = ServerHarness.boot({ modules = { HealthService, DebugService } })
		local violations = {}
		h.net:setViolationHandler(function(_, reason)
			table.insert(violations, reason)
		end)
		local player = h.adapters.players:addPlayer({ UserId = 201 })
		expect(h.invoke(player, "DebugCommand", "ping")).toBeErr("NOT_ALLOWED")
		expect(violations).toEqual({ "NOT_ALLOWED" })
	end)

	it("allows everyone in Studio", function()
		h = ServerHarness.boot({ isStudio = true, modules = { HealthService, DebugService } })
		local player = h.adapters.players:addPlayer({ UserId = 202 })
		local result = h.invoke(player, "DebugCommand", "ping")
		expect(result).toBeOk()
		expect(result.value).toBe("pong")
	end)

	it("resolves group-rank developers on join (live server)", function()
		local config = {
			DevAccess = {
				GROUP_ID = 77,
				isAllowed = function(_userId: number, rank: number?, isStudio: boolean): boolean
					return isStudio or (rank or 0) >= 200
				end,
			},
		}
		h = ServerHarness.boot({ modules = { HealthService, DebugService }, config = config })
		h.adapters.players:setGroupRank(300, 77, 250)
		local dev = h.adapters.players:addPlayer({ UserId = 300 })
		local pleb = h.adapters.players:addPlayer({ UserId = 301 })
		task.wait() -- group lookups run in spawned threads
		expect(DebugService:isDeveloper(dev)).toBe(true)
		expect(DebugService:isDeveloper(pleb)).toBe(false)
		expect(h.net:isDeveloper(dev)).toBe(true)
		expect(h.invoke(dev, "DebugCommand", "ping")).toBeOk()
		expect(h.invoke(pleb, "DebugCommand", "ping")).toBeErr("NOT_ALLOWED")
		pleb:Kick("bye")
		expect(DebugService._devCache[301]).toBeNil()
	end)
end)

describe("DebugService commands", function()
	local player

	Test.beforeEach(function()
		h = ServerHarness.boot({ isStudio = true, modules = { HealthService, DebugService } })
		player = h.adapters.players:addPlayer({ UserId = 210 })
	end)

	it("lists and runs built-in commands", function()
		local help = h.invoke(player, "DebugCommand", "help")
		expect(help).toBeOk()
		for _, name in { "health", "loglevel", "ping", "services" } do
			expect(help.value).toContain(name)
		end
		expect(h.invoke(player, "DebugCommand", "health").value).toContain("role=Hub")
		expect(h.invoke(player, "DebugCommand", "services").value).toContain("HealthService: Started")
	end)

	it("changes the log level with validated arguments", function()
		expect(h.invoke(player, "DebugCommand", "loglevel", { "verbose" })).toBeErr("INVALID_ARGS")
		expect(h.invoke(player, "DebugCommand", "loglevel", { "warn" })).toBeOk()
		expect(Log.getLevel()).toBe("warn")
	end)

	it("reports unknown commands and schema violations", function()
		expect(h.invoke(player, "DebugCommand", "nope")).toBeErr("NOT_FOUND")
		expect(h.invoke(player, "DebugCommand", "bad name!")).toBeErr("INVALID_ARGS")
		expect(h.invoke(player, "DebugCommand", "ping", { {} })).toBeErr("INVALID_ARGS")
	end)

	it("lets other services register commands and isolates their failures", function()
		DebugService:registerCommand("spawnbot", {
			description = "Spawn a bot.",
			handler = function(_p, args)
				return Result.ok("spawned " .. tostring(args[1]))
			end,
		})
		DebugService:registerCommand("explode", {
			description = "Always fails.",
			handler = function()
				error("command blew up")
			end,
		})
		expect(h.invoke(player, "DebugCommand", "SpawnBot", { 3 }).value).toBe("spawned 3")
		expect(h.invoke(player, "DebugCommand", "explode")).toBeErr("INTERNAL")
		expect(function()
			DebugService:registerCommand("ping", { description = "dup", handler = function() end :: any })
		end).toThrow("already registered")
		expect(DebugService:run(player, "ping")).toBeOk()
	end)
end)
