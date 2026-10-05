-- End-to-end in one VM: real server Bootstrap (HealthService + DebugService) + real Client/Main over loopback remotes.
local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local ServerHarness = require("@tests/Harness/ServerHarness")
local describe, it, expect = Test.describe, Test.it, Test.expect

local Main = require("@game/ReplicatedStorage/Client/Main")
local HealthService = require("@game/ServerScriptService/Server/Services/HealthService")
local DebugService = require("@game/ServerScriptService/Server/Services/DebugService")
local NetServer = require("@game/ReplicatedStorage/Shared/Net/NetServer")
local NetClient = require("@game/ReplicatedStorage/Shared/Net/NetClient")
local Protocol = require("@game/ReplicatedStorage/Shared/Net/Protocol")
local ErrorCodes = require("@game/ReplicatedStorage/Shared/Net/ErrorCodes")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")
local Schema = require("@game/ReplicatedStorage/Shared/Core/Schema")

local capture, h, player

local function localPlayer(userId: number): any
	local players = game:GetService("Players")
	local p = players:GetPlayerByUserId(userId) or players:addPlayer({ UserId = userId })
	players:setLocalPlayer(p)
	return p
end

Test.beforeEach(function()
	capture = LogCapture.start()
end)

Test.afterEach(function()
	if h then
		h.shutdown()
		h = nil
	end
	capture:stop()
end)

describe("Client Main", function()
	it("handshakes, boots role-filtered controllers and flags the client ready", function()
		h = ServerHarness.boot({ role = "Battle", modules = { HealthService, DebugService } })
		player = localPlayer(401)
		local initCtx
		local started = {}
		local controllers = {
			{
				Name = "BattleHud",
				Roles = { "Battle", "Dev" },
				Init = function(_self, ctx)
					initCtx = ctx
				end,
				Start = function()
					table.insert(started, "BattleHud")
				end,
			},
			{
				Name = "Garage",
				Roles = { "Hub", "Dev" },
				Start = function()
					table.insert(started, "Garage")
				end,
			},
		}
		local session = Main.start({ player = player, controllers = controllers :: any, isStudio = false })
		expect(session).toBeOk()
		expect(session.value.hello.role).toBe("Battle")
		expect(session.value.hello.isDeveloper).toBe(false)
		expect(started).toEqual({ "BattleHud" })
		expect(initCtx.role).toBe("Battle")
		expect(initCtx.player).toBe(player)
		expect(initCtx.net).toBe(session.value.net)
		expect(initCtx.hello.version).toBe(Protocol.GAME_VERSION)
		expect(initCtx.log.name).toBe("BattleHud")
		expect(player:GetAttribute(Protocol.ATTR_CLIENT_READY)).toBe(true)
		expect(player:GetAttribute(Protocol.ATTR_LOADING_STATUS)).toBe("Loading...")
		expect(session.value.loader:getStatus("Garage")).toBe("Skipped")
		session.value.net:destroy()
	end)

	it("receives server notices through the client net", function()
		h = ServerHarness.boot({ modules = { HealthService } })
		player = localPlayer(402)
		local session = Main.start({ player = player, controllers = {}, isStudio = false })
		expect(session).toBeOk()
		local notices = {}
		session.value.net:on("ServerNotice", function(notice)
			table.insert(notices, notice)
		end)
		HealthService:notify("Warning", "restart in 5 minutes")
		expect(notices[1].kind).toBe("Warning")
		expect(notices[1].message).toBe("restart in 5 minutes")
		session.value.net:destroy()
	end)

	it("retries Hello while the server answers NOT_READY", function()
		local rs = game:GetService("RunService")
		rs:setServer(true)
		rs:setClient(true)
		player = localPlayer(403)
		local net = NetServer.new({
			registry = {
				{
					name = "Hello",
					kind = "Function",
					direction = "C2S",
					rate = { perSecond = 100, burst = 100 },
					args = { Schema.any },
				},
			},
		})
		local attempts = 0
		net:onInvoke("Hello", function()
			attempts += 1
			if attempts < 3 then
				return Result.err(ErrorCodes.NOT_READY)
			end
			return Result.ok({ role = "Hub", version = "x", protocol = Protocol.PROTOCOL_VERSION })
		end)
		local client = NetClient.new()
		local waits = 0
		local result = Main.handshake(client, {
			retryDelay = 0,
			wait = function()
				waits += 1
			end,
		})
		expect(result).toBeOk()
		expect(attempts).toBe(3)
		expect(waits).toBe(2)
		client:destroy()
		net:destroy()
	end)

	it("server rejects outdated clients with VERSION_MISMATCH", function()
		h = ServerHarness.boot({ modules = { HealthService } })
		player = localPlayer(404)
		local net = NetClient.new()
		local original = Protocol.PROTOCOL_VERSION
		-- Simulate an outdated client by sending a different protocol through a raw invoke.
		local raw = net:invoke("Hello", { clientVersion = "old", protocol = original + 1 })
		expect(raw).toBeErr("VERSION_MISMATCH")
		net:destroy()
	end)

	it("reports a timeout when the remotes never replicate", function()
		local rs = game:GetService("RunService")
		rs:setClient(true)
		player = localPlayer(405)
		local result = Main.start({ player = player, controllers = {}, remotesTimeout = 0.02, isStudio = false })
		expect(result).toBeErr("TIMEOUT")
		expect(player:GetAttribute(Protocol.ATTR_LOADING_STATUS)).toContain("Unable to reach the server")
	end)

	it("surfaces handshake failures through the loading status", function()
		local rs = game:GetService("RunService")
		rs:setServer(true)
		rs:setClient(true)
		player = localPlayer(406)
		local net = NetServer.new() -- full registry, so Client/Main's waitForRemotes completes
		net:onInvoke("Hello", function()
			return Result.err(ErrorCodes.VERSION_MISMATCH, "server protocol 2")
		end)
		local result = Main.start({ player = player, controllers = {}, isStudio = false })
		expect(result).toBeErr("VERSION_MISMATCH")
		expect(player:GetAttribute(Protocol.ATTR_LOADING_STATUS)).toBe(ErrorCodes.message("VERSION_MISMATCH"))
		expect(player:GetAttribute(Protocol.ATTR_CLIENT_READY)).toBeNil()
		net:destroy()
	end)
end)
