local Test = require("@tests/Harness/Test")
local LogCapture = require("@tests/Harness/LogCapture")
local describe, it, expect = Test.describe, Test.it, Test.expect

local NetServer = require("@game/ReplicatedStorage/Shared/Net/NetServer")
local NetClient = require("@game/ReplicatedStorage/Shared/Net/NetClient")
local Schema = require("@game/ReplicatedStorage/Shared/Core/Schema")
local Result = require("@game/ReplicatedStorage/Shared/Core/Result")

local REGISTRY = {
	{
		name = "Ping",
		kind = "Function",
		direction = "C2S",
		rate = { perSecond = 100, burst = 100 },
		args = { Schema.number() },
	},
	{
		name = "Chat",
		kind = "Event",
		direction = "C2S",
		rate = { perSecond = 100, burst = 100 },
		args = { Schema.string({ maxLen = 10 }) },
	},
	{ name = "Notice", kind = "Event", direction = "S2C" },
}

local capture, server, client, player

Test.beforeEach(function()
	capture = LogCapture.start()
	local rs = game:GetService("RunService")
	rs:setServer(true)
	rs:setClient(true)
	local players = game:GetService("Players")
	player = players:GetPlayerByUserId(7) or players:addPlayer({ UserId = 7 })
	players:setLocalPlayer(player)
	server = NetServer.new({ registry = REGISTRY })
	client = NetClient.new({ registry = REGISTRY, invokeTimeout = 1, warnInterval = 0.02 })
end)

Test.afterEach(function()
	client:destroy()
	if server then
		server:destroy()
	end
	capture:stop()
end)

describe("NetClient", function()
	it("refuses to run on the server only", function()
		game:GetService("RunService"):setClient(false)
		expect(function()
			NetClient.new({ registry = REGISTRY })
		end).toThrow("only be used on the client")
		game:GetService("RunService"):setClient(true)
	end)

	it("waits for remotes that already exist", function()
		expect(client:waitForRemotes(1)).toBe(true)
	end)

	it("times out (with warnings) when the folder never appears", function()
		server:destroy()
		server = nil
		local lonely = NetClient.new({ registry = REGISTRY, warnInterval = 0.01 })
		expect(lonely:waitForRemotes(0.05)).toBe(false)
		expect(capture:find("warn", "still waiting")).never.toBeNil()
		lonely:destroy()
	end)

	it("invokes functions and returns the server Result", function()
		server:onInvoke("Ping", function(p, n)
			return Result.ok({ who = p.UserId, n = n + 1 })
		end)
		local result = client:invoke("Ping", 41)
		expect(result).toBeOk()
		expect(result.value).toEqual({ who = 7, n = 42 })
	end)

	it("passes server errors through", function()
		server:onInvoke("Ping", function()
			return Result.err("INSUFFICIENT_FUNDS", "need more")
		end)
		expect(client:invoke("Ping", 1)).toBeErr("INSUFFICIENT_FUNDS")
	end)

	it("validates arguments locally before sending", function()
		local calls = 0
		server:onInvoke("Ping", function()
			calls += 1
			return Result.ok(true)
		end)
		local result = client:invoke("Ping", "nope")
		expect(result).toBeErr("INVALID_ARGS")
		expect(result.detail).toBe("arg1: expected finite number, got string")
		expect(calls).toBe(0)
	end)

	it("times out slow invocations", function()
		server:onInvoke("Ping", function()
			task.wait(0.3)
			return Result.ok(true)
		end)
		local started = os.clock()
		local result = client:invokeWithTimeout("Ping", 0.05, 1)
		expect(result).toBeErr("TIMEOUT")
		expect(os.clock() - started).toBeLessThan(0.25)
	end)

	it("maps transport errors and malformed responses to INTERNAL", function()
		local remote = game:GetService("ReplicatedStorage").Remotes.Ping
		remote.OnServerInvoke = function()
			error("transport broke")
		end
		expect(client:invoke("Ping", 1)).toBeErr("INTERNAL")
		remote.OnServerInvoke = function()
			return 5
		end
		local malformed = client:invoke("Ping", 1)
		expect(malformed).toBeErr("INTERNAL")
		expect(malformed.detail).toBe("malformed response")
	end)

	it("fires validated events and drops invalid ones with a warning", function()
		local received = {}
		server:on("Chat", function(p, text)
			table.insert(received, { p, text })
		end)
		client:fire("Chat", "hello")
		client:fire("Chat", string.rep("x", 50))
		expect(#received).toBe(1)
		expect(received[1][1]).toBe(player)
		expect(received[1][2]).toBe("hello")
		expect(capture:find("warn", "dropped Chat")).never.toBeNil()
	end)

	it("on() works before the remote replicates", function()
		server:destroy()
		local early = NetClient.new({ registry = REGISTRY })
		local got = {}
		early:on("Notice", function(text)
			table.insert(got, text)
		end)
		server = NetServer.new({ registry = REGISTRY })
		expect(early:waitForRemotes(1)).toBe(true)
		server:fire("Notice", player, "welcome")
		server:fireAll("Notice", "everyone")
		expect(got).toEqual({ "welcome", "everyone" })
		early:destroy()
	end)

	it("returns NOT_FOUND when the remote never appears", function()
		server:destroy()
		server = nil
		local orphan = NetClient.new({ registry = REGISTRY })
		expect(orphan:invokeWithTimeout("Ping", 0.02, 1)).toBeErr("NOT_FOUND")
		orphan:destroy()
	end)

	it("rejects misuse", function()
		expect(function()
			client:fire("Notice")
		end).toThrow("requires a C2S")
		expect(function()
			client:on("Chat", function() end)
		end).toThrow("requires an S2C")
		expect(function()
			client:invoke("Chat", "x")
		end).toThrow("requires a Function")
		expect(function()
			client:fire("Unknown")
		end).toThrow('unknown remote "Unknown"')
	end)
end)
